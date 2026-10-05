import AppKit
import Observation
import SwiftUI

extension Notification.Name {
    /// Asks the SwiftUI side to open the Settings scene; `openSettings` is only reachable from a view.
    static let memoOpenSettings = Notification.Name("MemoOpenSettings")
}

/// Layout values the panel's SwiftUI content needs from AppKit.
@Observable
final class PanelState {
    /// Horizontal position of the arrow tip, measured from the panel's left edge.
    var arrowX: CGFloat = Theme.panelWidth / 2
    /// Tallest the task list may grow before it scrolls.
    var maxListHeight: CGFloat = 600
}

/// Borderless panel that hangs below the status item. It keeps its top edge pinned while
/// SwiftUI resizes it, so the arrow stays attached to the menu bar.
final class MenuPanel: NSPanel {
    var anchoredTop: CGFloat?
    var onClose: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let anchoredTop {
            frame.origin.y = anchoredTop - frame.height
        }
        super.setFrame(frame, display: flag)
        invalidateShadow()
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }
}

/// Owns the menu bar item and the panel it opens.
final class StatusItemController: NSObject {
    private let store: TodoStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = MenuPanel()
    private let panelState = PanelState()
    private var eventMonitors: [Any] = []
    private var contextMenuMonitor: Any?

    init(store: TodoStore) {
        self.store = store
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseDown])
            button.imagePosition = .imageLeading
        }
        updateStatusButton()

        let content = PanelChrome(state: panelState) {
            TodoMenuView(store: store, panelState: panelState)
        }
        let hostingView = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
        hostingView.sizingOptions = [.intrinsicContentSize, .minSize, .maxSize]
        panel.contentView = hostingView
        // Build the view now so it's listening for .memoOpenSettings before the panel first opens.
        hostingView.layoutSubtreeIfNeeded()
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onClose = { [weak self] in self?.closePanel() }
        installContextMenuMonitor()
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let margin: CGFloat = 8
        let width = Theme.panelWidth

        var x = buttonFrame.midX - width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - margin - width)
        let arrowInset = Theme.panelCornerRadius + Theme.arrowWidth / 2
        panelState.arrowX = min(max(buttonFrame.midX - x, arrowInset), width - arrowInset)

        let top = buttonFrame.minY - 1
        panelState.maxListHeight = max(200, top - visible.minY - margin - 120)
        panel.anchoredTop = top
        panel.setFrame(NSRect(x: x, y: top - panel.frame.height, width: width, height: panel.frame.height), display: false)

        panel.makeKeyAndOrderFront(nil)
        // Don't drop the cursor into the first "add to" field on open.
        panel.makeFirstResponder(nil)
        button.highlight(true)
        installEventMonitors()
    }

    func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        removeEventMonitors()
    }

    // MARK: Right-click menu

    /// Right-clicks (and Control-clicks) on the icon are taken before the button sees them.
    /// If the button handled the mouse-down, the menu would swallow the matching mouse-up and
    /// the button would keep waiting for it, eating the next click on the icon.
    private func installContextMenuMonitor() {
        contextMenuMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self,
                  event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                  self.isOverStatusButton(NSEvent.mouseLocation) else { return event }
            DispatchQueue.main.async { self.showContextMenu() }
            return nil
        }
    }

    private func showContextMenu() {
        closePanel()

        let menu = NSMenu()
        menu.autoenablesItems = false

        let clear = NSMenuItem(title: "Clear Completed", action: #selector(clearCompleted), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = store.completedCount > 0
        menu.addItem(clear)

        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Memo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        // Attaching the menu only for this click makes AppKit position it like any menu bar menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func clearCompleted() {
        store.clearCompleted()
    }

    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .memoOpenSettings, object: nil)
    }

    /// Clicking anywhere outside the panel closes it, like a menu.
    private func installEventMonitors() {
        removeEventMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Clicks on the menu bar icon are left to togglePanel; closing here as well would
        // close the panel and then immediately reopen it.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            guard let self, !self.isOverStatusButton(NSEvent.mouseLocation) else { return }
            self.closePanel()
        }) {
            eventMonitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            guard let self else { return event }
            if let window = event.window, self.belongsToPanel(window) {
                return event
            }
            if self.isOverStatusButton(NSEvent.mouseLocation) {
                return event
            }
            self.closePanel()
            return event
        }) {
            eventMonitors.append(local)
        }
    }

    private func belongsToPanel(_ window: NSWindow) -> Bool {
        if window === panel || window === statusItem.button?.window { return true }
        // Popovers (the due date picker) and menus opened from inside the panel.
        var parent = window.parent
        while let current = parent {
            if current === panel { return true }
            parent = current.parent
        }
        let className = String(describing: type(of: window))
        return className.contains("Popover") || className.contains("Menu")
    }

    private func isOverStatusButton(_ screenPoint: NSPoint) -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(screenPoint)
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    // MARK: Menu bar button

    private func updateStatusButton() {
        withObservationTracking {
            applyStatusButton()
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.updateStatusButton() }
        }
    }

    private func applyStatusButton() {
        guard let button = statusItem.button else { return }

        let image: NSImage?
        if let systemImageName = store.menuBarIconStyle.systemImageName {
            image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: "Memo")
        } else {
            image = NSImage(named: "MenuBarIcon")
        }
        image?.isTemplate = true
        button.image = image

        if store.showCounter && !store.items.isEmpty {
            button.title = "\(store.completedCount)/\(store.items.count)"
        } else {
            button.title = ""
        }
        button.imagePosition = button.title.isEmpty ? .imageOnly : .imageLeading
    }
}

/// The panel's opaque background: a rounded body with an arrow pointing at the status item.
struct PanelChrome<Content: View>: View {
    let state: PanelState
    @ViewBuilder var content: Content

    var body: some View {
        let shape = PanelShape(arrowX: state.arrowX)

        content
            .padding(.top, Theme.arrowHeight)
            .frame(width: Theme.panelWidth)
            .background(Theme.panelBackground)
            .clipShape(shape)
            .overlay(shape.stroke(Theme.panelBorder, lineWidth: 0.5))
    }
}

struct PanelShape: Shape {
    var arrowX: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 0.25
        let body = CGRect(
            x: rect.minX + inset,
            y: rect.minY + Theme.arrowHeight + inset,
            width: rect.width - inset * 2,
            height: rect.height - Theme.arrowHeight - inset * 2
        )
        let radius = Theme.panelCornerRadius
        let halfArrow = Theme.arrowWidth / 2
        let tipRadius: CGFloat = 1.5

        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addLine(to: CGPoint(x: arrowX - halfArrow, y: body.minY))
        // Arrow with a slightly softened tip.
        path.addArc(
            tangent1End: CGPoint(x: arrowX, y: rect.minY + inset),
            tangent2End: CGPoint(x: arrowX + halfArrow, y: body.minY),
            radius: tipRadius
        )
        path.addLine(to: CGPoint(x: arrowX + halfArrow, y: body.minY))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.minY),
            tangent2End: CGPoint(x: body.maxX, y: body.maxY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.maxY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.minY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.minY),
            tangent2End: CGPoint(x: body.maxX, y: body.minY),
            radius: radius
        )
        path.closeSubpath()
        return path
    }
}
