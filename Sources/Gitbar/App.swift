import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var settingsWindow: NSWindow?
    private let store = Store()
    private var appearanceObservation: NSKeyValueObservation?
    private var clickOutsideMonitor: Any?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusButton()
        setupPanel()
        setupMainMenu()

        syncAppearance()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.syncAppearance() }
        }

        if store.hasToken {
            store.refresh()
            store.reconfigurePollingFromDefaults()
        }

        // ImageRenderer often yields nil on the first pass; refresh once the run loop has ticked.
        DispatchQueue.main.async { [weak self] in
            self?.configureStatusButton()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshBadge() }
        }

        NotificationCenter.default.addObserver(
            forName: .gitbarStoreDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshBadge() }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyDown(event)
        }
    }

    /// Global shortcuts while Gitbar has key focus (panel or settings).
    private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 53 { // Escape
            if panel.isKeyWindow {
                hidePanel()
                return nil
            }
            if settingsWindow?.isKeyWindow == true {
                settingsWindow?.close()
                return nil
            }
            return event
        }

        guard flags == .command else { return event }

        let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch ch {
        case "q":
            NSApp.terminate(nil)
            return nil
        case ",":
            openSettings()
            return nil
        case "w":
            if panel.isKeyWindow {
                hidePanel()
                return nil
            }
            return event
        case "r":
            if panel.isKeyWindow {
                store.refresh()
                if store.isStatsTabActive {
                    Task { await store.loadStats(range: store.lastStatsRange) }
                }
                return nil
            }
            if settingsWindow?.isKeyWindow == true {
                store.refresh()
                return nil
            }
            return event
        default:
            return event
        }
    }

    /// LSUIElement apps don't show a menu bar, but an NSMainMenu is still required
    /// for ⌘V / ⌘C / ⌘X / ⌘A to dispatch to the first responder (NSTextField etc.).
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupPanel() {
        let rect = NSRect(x: 0, y: 0, width: 520, height: 620)
        panel = FloatingPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false

        let host = NSHostingController(
            rootView: PanelView(onOpenSettings: { [weak self] in self?.openSettings() })
                .environmentObject(store)
        )
        host.view.wantsLayer = true
        host.view.layer?.cornerRadius = 14
        host.view.layer?.masksToBounds = true
        host.view.focusRingType = .none
        panel.contentView = host.view
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = GitbarMenuBarIcon.gitGraphTemplate(pointSize: 13)
        button.imagePosition = .imageLeft
        button.action = #selector(onStatusClick(_:))
        button.target = self
        refreshBadge()
    }

    func refreshBadge() {
        guard let button = statusItem.button else { return }
        let total = store.badgeCount
        button.title = total > 0 ? " \(total)" : ""
        let changesOn = Self.defaultsBool("gitbar.notify.changesRequested", default: true)
        let changesCount = store.myPRsNeedingChanges.count
        if changesOn, changesCount > 0 {
            button.toolTip = "Gitbar — \(changesCount) PR\(changesCount == 1 ? "" : "s") need changes"
        } else {
            button.toolTip = "Gitbar"
        }
    }

    private static func defaultsBool(_ key: String, default def: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return def }
        return UserDefaults.standard.bool(forKey: key)
    }

    @objc private func onStatusClick(_ sender: Any?) {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let size = panel.frame.size

        var x = screenRect.midX - size.width / 2
        let y = screenRect.minY - size.height - 6

        if let screen = buttonWindow.screen {
            let vf = screen.visibleFrame
            x = min(max(x, vf.minX + 6), vf.maxX - size.width - 6)
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard !EmojiPaletteState.isOpen else { return }
                self?.hidePanel()
            }
        }

        if store.hasToken { store.refresh() }
    }

    private func hidePanel() {
        panel.orderOut(nil)
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
        refreshBadge()
    }

    private func syncAppearance() {
        let appearance = NSApp.effectiveAppearance
        panel?.appearance = appearance
        panel?.contentView?.appearance = appearance
        settingsWindow?.appearance = appearance
        settingsWindow?.contentViewController?.view.appearance = appearance
    }

    func openSettings() {
        hidePanel()
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(
            rootView: SettingsView(onClose: { [weak self] in self?.settingsWindow?.close() })
                .environmentObject(store)
        )
        let window = NSWindow(contentViewController: controller)
        window.title = "Gitbar Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 640))
        window.isReleasedWhenClosed = false
        window.appearance = NSApp.effectiveAppearance
        controller.view.appearance = NSApp.effectiveAppearance
        window.center()
        window.delegate = WindowCloseHandler.shared
        settingsWindow = window
        WindowCloseHandler.shared.onClose = { [weak self] in self?.settingsWindow = nil }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class WindowCloseHandler: NSObject, NSWindowDelegate {
    static let shared = WindowCloseHandler()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

@main
enum GitbarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
