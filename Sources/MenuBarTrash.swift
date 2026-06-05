import AppKit

/// The honest trash can that lives in the menu bar and does the real work.
final class MenuBarTrash: NSObject {

    private let statusItem: NSStatusItem
    private var isEmpty = true

    /// Invoked by the "聚焦废纸篓" menu item to summon the runaway desktop can.
    var onFocus: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        statusItem.menu = buildMenu()
        setTrashEmpty(true)
    }

    // MARK: - UI

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = trashImage(empty: true)
        button.image?.isTemplate = true
        button.toolTip = "RunningTrash"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "打开废纸篓", action: #selector(openTrash), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let empty = NSMenuItem(title: "清空废纸篓…", action: #selector(emptyTrash), keyEquivalent: "")
        empty.target = self
        menu.addItem(empty)

        menu.addItem(.separator())

        let focus = NSMenuItem(title: "聚焦废纸篓（闪现到右下角）", action: #selector(focusTrash), keyEquivalent: "f")
        focus.target = self
        menu.addItem(focus)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 RunningTrash", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - State

    /// Swap the menu bar icon between the empty and full system trash icons.
    func setTrashEmpty(_ empty: Bool) {
        isEmpty = empty
        guard let button = statusItem.button else { return }
        let image = trashImage(empty: empty)
        image?.isTemplate = true
        button.image = image
    }

    private func trashImage(empty: Bool) -> NSImage? {
        let name = empty ? NSImage.trashEmptyName : NSImage.trashFullName
        let image = NSImage(named: name)
        image?.size = NSSize(width: 15, height: 15)
        return image
    }

    // MARK: - Actions

    @objc private func focusTrash() {
        onFocus?()
    }

    @objc private func openTrash() {
        guard let url = TrashLocator.trashURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func emptyTrash() {
        guard let url = TrashLocator.trashURL else { return }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let alert = NSAlert()
        if contents.isEmpty {
            alert.messageText = "废纸篓已经是空的"
            alert.informativeText = "没有需要清空的项目。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }

        alert.messageText = "确定要清空废纸篓吗？"
        alert.informativeText = "废纸篓中的 \(contents.count) 个项目将被永久删除。此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空废纸篓")
        alert.addButton(withTitle: "取消")

        // Make the destructive button visually destructive on macOS 11+.
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for item in (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
