import Foundation

/// Resolves the user's Trash directory once and caches it.
enum TrashLocator {
    static let trashURL: URL? = try? FileManager.default.url(
        for: .trashDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
    )
}

/// Watches the system Trash folder and reports whether it is empty.
final class TrashMonitor {

    private let onChange: (Bool) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var pollTimer: Timer?
    private var lastReported: Bool?

    /// Current emptiness, recomputed on demand.
    var isEmpty: Bool { computeIsEmpty() }

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard let url = TrashLocator.trashURL else { return }

        fileDescriptor = open(url.path, O_EVTONLY)
        if fileDescriptor >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend],
                queue: .main
            )

            src.setEventHandler { [weak self] in
                self?.report()
            }

            src.setCancelHandler { [weak self] in
                guard let self else { return }
                if self.fileDescriptor >= 0 {
                    close(self.fileDescriptor)
                    self.fileDescriptor = -1
                }
            }

            source = src
            src.resume()
        }

        // Safety net: the directory watcher can coalesce or miss events, and it
        // won't notice changes made by other apps. Poll periodically so both
        // trash icons stay truthfully in sync with the real Trash.
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.report()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        source?.cancel()
        source = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Re-check the Trash, but only notify when the empty/full state changed.
    func refresh() {
        report(force: true)
    }

    private func report(force: Bool = false) {
        let empty = computeIsEmpty()
        if force || empty != lastReported {
            lastReported = empty
            onChange(empty)
        }
    }

    private func computeIsEmpty() -> Bool {
        guard let url = TrashLocator.trashURL else { return true }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.isEmpty
    }
}
