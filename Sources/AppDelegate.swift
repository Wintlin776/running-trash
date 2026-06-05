import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarTrash: MenuBarTrash!
    private var runningWindow: RunningTrashWindow!
    private var trashMonitor: TrashMonitor!

    // MARK: - Entry point

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // No Dock icon, no main menu — pure menu bar / floating toy.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar trash (the real, functional one).
        menuBarTrash = MenuBarTrash()

        // Desktop running trash (the visual toy).
        runningWindow = RunningTrashWindow()
        // Menu bar "聚焦废纸篓" summons the runaway can to the corner.
        menuBarTrash.onFocus = { [weak self] in
            self?.runningWindow.focusToCorner()
        }
        // When something is dropped into the desktop can, re-check the real Trash.
        runningWindow.onRecycled = { [weak self] in
            self?.trashMonitor.refresh()
        }
        runningWindow.show()

        // Watch the system Trash and keep both icons in sync.
        trashMonitor = TrashMonitor { [weak self] isEmpty in
            self?.menuBarTrash.setTrashEmpty(isEmpty)
            self?.runningWindow.setTrashEmpty(isEmpty)
        }
        trashMonitor.start()

        // Apply the initial state immediately.
        let empty = trashMonitor.isEmpty
        menuBarTrash.setTrashEmpty(empty)
        runningWindow.setTrashEmpty(empty)
    }

    func applicationWillTerminate(_ notification: Notification) {
        trashMonitor.stop()
        runningWindow.stop()
    }
}
