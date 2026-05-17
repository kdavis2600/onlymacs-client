import AppKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import OnlyMacsCore
import SwiftUI

// App shell responsibilities live here so window lifecycle, activation policy,
// and menu-bar specific coordination stay separate from BridgeStore state/effects.

enum OnlyMacsWindowTitle {
    static let fileApproval = "OnlyMacs File Approval"
    static let automationPopup = "OnlyMacs Popup"
    static let automationControlCenter = "OnlyMacs Automation Control Center"
}

enum OnlyMacsAppNotification {
    static let didOpenURL = Notification.Name("OnlyMacsDidOpenURLNotification")
}

final class OnlyMacsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateDuplicateOnlyMacsInstances()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(name: OnlyMacsAppNotification.didOpenURL, object: url)
        }
    }
}

@MainActor
func terminateDuplicateOnlyMacsInstances() {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let duplicates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { $0.processIdentifier != currentPID }

    for app in duplicates {
        _ = app.terminate()
    }
}

@MainActor
func bringOnlyMacsWindowToFront(title: String, retries: Bool = true) {
    forceActivateOnlyMacsApp()

    let focusWindow = { @MainActor in
        guard let window = NSApp.windows.first(where: { $0.title.localizedCaseInsensitiveContains(title) }) else {
            return
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.orderFront(nil)
        window.makeMain()
        forceActivateOnlyMacsApp()
    }

    let delays: [UInt64] = retries ? [0, 60_000_000, 140_000_000, 260_000_000, 420_000_000, 900_000_000, 1_800_000_000] : [0]
    for delay in delays {
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            focusWindow()
        }
    }
}

@MainActor
func forceActivateOnlyMacsApp() {
    if NSApp.activationPolicy() != .regular {
        NSApp.setActivationPolicy(.regular)
    }
    NSRunningApplication.current.unhide()
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    NSApp.activate(ignoringOtherApps: true)

    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = [
        "-e",
        "tell application id \"\(bundleIdentifier)\" to activate"
    ]
    try? process.run()
}

@MainActor
func restoreOnlyMacsAgentPolicyIfPossible() {
    guard NSApp.activationPolicy() != .accessory else { return }
    guard NSApp.windows.allSatisfy({ !$0.isVisible }) else { return }
    NSApp.setActivationPolicy(.accessory)
}

@MainActor
func openOnlyMacsSettingsWindow() {
    OnlyMacsStatusItemController.shared.dismissPopover()
    forceActivateOnlyMacsApp()

    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 120_000_000)

        let opened = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            || NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)

        if opened {
            forceActivateOnlyMacsApp()
        }
    }
}

@MainActor
func closeOnlyMacsWindows(titles: [String]) {
    let loweredTitles = titles.map { $0.lowercased() }
    let matchingWindows = NSApp.windows.filter { window in
        let title = window.title.lowercased()
        return loweredTitles.contains(where: { title.localizedCaseInsensitiveContains($0) })
    }

    let closeWindows = { @MainActor in
        for window in matchingWindows {
            window.performClose(nil)
            window.orderOut(nil)
            if window.isVisible {
                window.close()
            }
        }
    }

    closeWindows()
    for delay in [80_000_000 as UInt64, 220_000_000 as UInt64, 500_000_000 as UInt64] {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            closeWindows()
        }
    }
}

@MainActor
func closeOnlyMacsWindow(title: String) {
    closeOnlyMacsWindows(titles: [title])
}

@MainActor
final class OnlyMacsFileApprovalWindowController: NSWindowController, NSWindowDelegate {
    private weak var store: BridgeStore?
    private var isProgrammaticClose = false
    private let hostingView: NSHostingView<OnlyMacsFileApprovalWindowView>

    init(store: BridgeStore) {
        self.store = store
        let contentView = OnlyMacsFileApprovalWindowView(store: store)
        self.hostingView = NSHostingView(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = OnlyMacsWindowTitle.fileApproval
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior.insert(.moveToActiveSpace)
        let container = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 980, height: 720))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        window.contentView = container
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(store: BridgeStore) {
        self.store = store
        hostingView.rootView = OnlyMacsFileApprovalWindowView(store: store)
    }

    func present() {
        isProgrammaticClose = false
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        bringOnlyMacsWindowToFront(title: OnlyMacsWindowTitle.fileApproval)
    }

    func dismiss() {
        isProgrammaticClose = true
        window?.orderOut(nil)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        defer {
            OnlyMacsFileApprovalWindowManager.shared.controller = nil
        }
        store?.markFileApprovalWindowHidden()
        guard !isProgrammaticClose else { return }
        if store?.pendingFileAccessApproval != nil {
            store?.rejectPendingFileAccessNow(message: "You closed the trusted file approval window.")
        }
    }
}

@MainActor
enum OnlyMacsFileApprovalWindowManager {
    static var shared = OnlyMacsFileApprovalWindowManagerState()
}

@MainActor
final class OnlyMacsFileApprovalWindowManagerState {
    var controller: OnlyMacsFileApprovalWindowController?

    func present(store: BridgeStore) {
        guard store.pendingFileAccessApproval != nil else {
            dismiss()
            return
        }
        if let controller {
            controller.refresh(store: store)
            controller.present()
            store.markFileApprovalWindowVisible()
            return
        }
        let controller = OnlyMacsFileApprovalWindowController(store: store)
        self.controller = controller
        controller.present()
        store.markFileApprovalWindowVisible()
    }

    func dismiss() {
        controller?.dismiss()
        controller = nil
    }
}

private struct OnlyMacsAutomationPopupSnapshot {
    let currentSectionTitle: String
    let currentSectionSubtitle: String
    let swarmConnectionTitle: String
    let activeSwarmHeadline: String
    let activeSwarmDetail: String
}

@MainActor
final class OnlyMacsAutomationPopupContentViewController: NSViewController {
    private let titleField = NSTextField(labelWithString: "OnlyMacs Popup Mirror")
    private let subtitleField = NSTextField(
        labelWithString: "Automation uses this lightweight window instead of the live menu bar popup so UI QA can open and close it deterministically."
    )
    private let connectionField = NSTextField(labelWithString: "")
    private let swarmHeadlineField = NSTextField(labelWithString: "")
    private let swarmDetailField = NSTextField(labelWithString: "")
    private let sectionTitleField = NSTextField(labelWithString: "")
    private let sectionSubtitleField = NSTextField(labelWithString: "")
    private lazy var openSettingsButton: NSButton = {
        let button = NSButton(title: "Open Settings", target: self, action: #selector(openSettings))
        button.identifier = NSUserInterfaceItemIdentifier("onlymacs.popup.automation.openSettings")
        return button
    }()

    private let openSettingsAction: () -> Void

    fileprivate init(
        snapshot: OnlyMacsAutomationPopupSnapshot,
        openSettingsAction: @escaping () -> Void
    ) {
        self.openSettingsAction = openSettingsAction
        super.init(nibName: nil, bundle: nil)
        apply(snapshot: snapshot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 640))
        root.identifier = NSUserInterfaceItemIdentifier("onlymacs.popup.automationMirror")

        titleField.font = .systemFont(ofSize: 22, weight: .semibold)
        subtitleField.font = .systemFont(ofSize: 13)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.maximumNumberOfLines = 0
        subtitleField.lineBreakMode = .byWordWrapping

        connectionField.font = .systemFont(ofSize: 14, weight: .semibold)
        swarmHeadlineField.font = .systemFont(ofSize: 18, weight: .semibold)
        swarmDetailField.font = .systemFont(ofSize: 13)
        swarmDetailField.textColor = .secondaryLabelColor
        swarmDetailField.maximumNumberOfLines = 0
        swarmDetailField.lineBreakMode = .byWordWrapping
        sectionTitleField.font = .systemFont(ofSize: 15, weight: .semibold)
        sectionSubtitleField.font = .systemFont(ofSize: 12)
        sectionSubtitleField.textColor = .secondaryLabelColor
        sectionSubtitleField.maximumNumberOfLines = 0
        sectionSubtitleField.lineBreakMode = .byWordWrapping

        let buttonRow = NSStackView(views: [openSettingsButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY

        let stack = NSStackView(views: [
            titleField,
            subtitleField,
            connectionField,
            swarmHeadlineField,
            swarmDetailField,
            sectionTitleField,
            sectionSubtitleField,
            buttonRow
        ])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20)
        ])

        self.view = root
    }

    fileprivate func apply(snapshot: OnlyMacsAutomationPopupSnapshot) {
        connectionField.stringValue = snapshot.swarmConnectionTitle
        swarmHeadlineField.stringValue = snapshot.activeSwarmHeadline
        swarmDetailField.stringValue = snapshot.activeSwarmDetail
        sectionTitleField.stringValue = "Current Section: \(snapshot.currentSectionTitle)"
        sectionSubtitleField.stringValue = snapshot.currentSectionSubtitle
    }

    @objc private func openSettings() {
        openSettingsAction()
    }
}

@MainActor
final class OnlyMacsAutomationPopupWindowController: NSWindowController, NSWindowDelegate {
    private weak var store: BridgeStore?

    private static func snapshot(for store: BridgeStore) -> OnlyMacsAutomationPopupSnapshot {
        OnlyMacsAutomationPopupSnapshot(
            currentSectionTitle: store.controlCenterSection.title,
            currentSectionSubtitle: store.controlCenterSection.subtitle,
            swarmConnectionTitle: store.swarmConnectionTitle,
            activeSwarmHeadline: store.activeSwarmHeadline,
            activeSwarmDetail: store.activeSwarmDetail
        )
    }

    init(store: BridgeStore) {
        self.store = store
        let contentController = OnlyMacsAutomationPopupContentViewController(
            snapshot: Self.snapshot(for: store),
            openSettingsAction: {
                openOnlyMacsSettingsWindow()
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = OnlyMacsWindowTitle.automationPopup
        window.isReleasedWhenClosed = true
        window.level = .floating
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentMinSize = NSSize(width: 520, height: 640)
        window.contentMaxSize = NSSize(width: 520, height: 640)
        window.setContentSize(NSSize(width: 520, height: 640))
        window.contentViewController = contentController
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(store: BridgeStore) {
        self.store = store
        if let contentController = window?.contentViewController as? OnlyMacsAutomationPopupContentViewController {
            contentController.apply(snapshot: Self.snapshot(for: store))
        }
    }

    func present(section: ControlCenterSection) {
        store?.showControlCenterSection(section)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        bringOnlyMacsWindowToFront(title: OnlyMacsWindowTitle.automationPopup, retries: false)
    }

    func dismiss() {
        window?.performClose(nil)
        window?.orderOut(nil)
        if window?.isVisible == true {
            window?.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        OnlyMacsAutomationWindowManager.shared.popupController = nil
        restoreOnlyMacsAgentPolicyIfPossible()
    }
}

@MainActor
final class OnlyMacsAutomationControlCenterWindowController: NSWindowController, NSWindowDelegate {
    private weak var store: BridgeStore?

    init(store: BridgeStore) {
        self.store = store
        let contentView = ControlCenterWindowView(store: store)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = OnlyMacsWindowTitle.automationControlCenter
        window.isReleasedWhenClosed = true
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentViewController = hostingController
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(store: BridgeStore) {
        self.store = store
        if let hostingController = window?.contentViewController as? NSHostingController<ControlCenterWindowView> {
            hostingController.rootView = ControlCenterWindowView(store: store)
        }
    }

    func present(section: ControlCenterSection) {
        store?.showControlCenterSection(section)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        bringOnlyMacsWindowToFront(title: OnlyMacsWindowTitle.automationControlCenter, retries: false)
    }

    func dismiss() {
        window?.performClose(nil)
        window?.orderOut(nil)
        if window?.isVisible == true {
            window?.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        OnlyMacsAutomationWindowManager.shared.controlCenterController = nil
        restoreOnlyMacsAgentPolicyIfPossible()
    }
}

@MainActor
enum OnlyMacsAutomationWindowManager {
    static var shared = OnlyMacsAutomationWindowManagerState()
}

@MainActor
final class OnlyMacsAutomationWindowManagerState {
    var popupController: OnlyMacsAutomationPopupWindowController?
    var controlCenterController: OnlyMacsAutomationControlCenterWindowController?

    func presentPopup(store: BridgeStore, section: ControlCenterSection) {
        if let popupController {
            popupController.refresh(store: store)
            popupController.present(section: section)
            return
        }
        let popupController = OnlyMacsAutomationPopupWindowController(store: store)
        self.popupController = popupController
        popupController.present(section: section)
    }

    func dismissPopup() {
        popupController?.dismiss()
        popupController = nil
        closeOnlyMacsWindow(title: OnlyMacsWindowTitle.automationPopup)
    }

    func presentControlCenter(store: BridgeStore, section: ControlCenterSection) {
        if let controlCenterController {
            controlCenterController.refresh(store: store)
            controlCenterController.present(section: section)
            return
        }
        let controlCenterController = OnlyMacsAutomationControlCenterWindowController(store: store)
        self.controlCenterController = controlCenterController
        controlCenterController.present(section: section)
    }

    func dismissControlCenter() {
        controlCenterController?.dismiss()
        controlCenterController = nil
        closeOnlyMacsWindow(title: OnlyMacsWindowTitle.automationControlCenter)
    }
}

@MainActor
final class OnlyMacsStatusItemController: NSObject, NSPopoverDelegate {
    static let shared = OnlyMacsStatusItemController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var store: BridgeStore?
    private var storeObserver: AnyCancellable?
    private var menuContentController: NSHostingController<MenuContentView>?
    private var iconHostingView: NSHostingView<MenuBarIconLabel>?

    private override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 520, height: 640)
    }

    func install(with store: BridgeStore) {
        self.store = store
        if statusItem == nil {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            self.statusItem = statusItem
            configureButton(for: statusItem)
        }
        bind(to: store)
        refreshAppearance()

        Task { @MainActor [weak store] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            store?.activateMenuBarExperienceIfNeeded()
        }
    }

    func refreshAppearance() {
        guard let store else { return }

        if let menuContentController {
            menuContentController.rootView = MenuContentView(store: store)
        } else {
            let controller = NSHostingController(rootView: MenuContentView(store: store))
            controller.view.frame = NSRect(x: 0, y: 0, width: 520, height: 640)
            menuContentController = controller
            popover.contentViewController = controller
        }

        iconHostingView?.rootView = MenuBarIconLabel(
            state: store.menuBarVisualState,
            image: store.menuBarIconImage,
            fallbackSystemImage: store.menuBarIconName,
            accessibilityLabel: "OnlyMacs \(store.menuBarStateTitle)"
        )
        statusItem?.button?.toolTip = "OnlyMacs \(store.menuBarStateTitle)"
    }

    var isPopoverShown: Bool {
        popover.isShown
    }

    @discardableResult
    func presentPopover(forceActivate: Bool, section: ControlCenterSection? = nil) -> Bool {
        guard let statusButton = statusItem?.button, let store else { return false }
        if let section {
            store.showControlCenterSection(section)
        }
        refreshAppearance()
        if forceActivate {
            forceActivateOnlyMacsApp()
        }
        if !popover.isShown {
            popover.show(relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
        }
        statusButton.highlight(true)
        writePopoverMarkerIfNeeded()
        return popover.isShown
    }

    func dismissPopover() {
        popover.performClose(nil)
        statusItem?.button?.highlight(false)
    }

    func togglePopover() {
        guard let store else { return }
        if popover.isShown {
            dismissPopover()
            return
        }
        presentPopover(forceActivate: false, section: store.controlCenterSection)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
        restoreOnlyMacsAgentPolicyIfPossible()
    }

    @objc
    private func statusItemClicked(_ sender: Any?) {
        togglePopover()
    }

    private func bind(to store: BridgeStore) {
        storeObserver = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAppearance()
            }
    }

    private func configureButton(for statusItem: NSStatusItem) {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.image = nil
        button.title = ""
        button.identifier = NSUserInterfaceItemIdentifier("onlymacs.menuBar.statusItem")
        button.subviews.forEach { $0.removeFromSuperview() }

        let iconView = NSHostingView(
            rootView: MenuBarIconLabel(
                state: .ready,
                image: MenuBarIconAsset.image,
                fallbackSystemImage: "bolt.circle",
                accessibilityLabel: "OnlyMacs"
            )
        )
        iconView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
        ])
        self.iconHostingView = iconView
    }

    private func writePopoverMarkerIfNeeded() {
        guard popover.isShown else { return }
        guard let markerPath = ProcessInfo.processInfo.environment["ONLYMACS_TEST_POPOVER_MARKER"],
              !markerPath.isEmpty else { return }
        let markerURL = URL(fileURLWithPath: markerPath)
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data("shown".utf8).write(to: markerURL, options: .atomic)
    }
}

@main
struct OnlyMacsApp: App {
    @NSApplicationDelegateAdaptor(OnlyMacsAppDelegate.self) private var appDelegate
    @StateObject private var store: BridgeStore

    init() {
        let store = BridgeStore()
        _store = StateObject(wrappedValue: store)
        OnlyMacsStatusItemController.shared.install(with: store)
    }

    var body: some Scene {
        Settings {
            SettingsView(store: store)
                .frame(minWidth: 760, minHeight: 900)
        }
    }
}

private struct MenuBarIconLabel: View {
    let state: MenuBarVisualState
    let image: NSImage?
    let fallbackSystemImage: String
    let accessibilityLabel: String

    var body: some View {
        ZStack(alignment: badgeAlignment) {
            baseIcon

            if let badgeStyle {
                MenuBarStatusBadge(style: badgeStyle)
                    .offset(badgeOffset)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    @ViewBuilder
    private var baseIcon: some View {
        if let image {
            if state.usesCircularBase {
                Image(nsImage: image)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
                    .modifier(MenuBarIconBaseStyle(inverted: usesInvertedBase))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.35), lineWidth: 0.55)
                    )
            } else {
                Image(nsImage: image)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
                    .modifier(MenuBarIconBaseStyle(inverted: usesInvertedBase))
            }
        } else {
            Image(systemName: fallbackSystemImage)
                .imageScale(.large)
        }
    }

    private var usesInvertedBase: Bool {
        switch state {
        case .usingRemote, .both:
            return true
        case .loading, .ready, .sharing, .degraded:
            return false
        }
    }

    private var badgeStyle: MenuBarStatusBadge.Style? {
        switch state {
        case .sharing:
            return .sharingLight
        case .both:
            return .sharingDark
        case .degraded:
            return .warning
        case .loading, .ready, .usingRemote:
            return nil
        }
    }

    private var badgeAlignment: Alignment {
        switch state {
        case .degraded:
            return .topTrailing
        case .sharing, .both:
            return .bottomTrailing
        case .loading, .ready, .usingRemote:
            return .center
        }
    }

    private var badgeOffset: CGSize {
        switch state {
        case .degraded:
            return CGSize(width: 1, height: -1)
        case .sharing, .both:
            return CGSize(width: 1, height: 1)
        case .loading, .ready, .usingRemote:
            return .zero
        }
    }
}

private struct MenuBarIconBaseStyle: ViewModifier {
    let inverted: Bool

    func body(content: Content) -> some View {
        if inverted {
            content
                .colorInvert()
                .brightness(-0.02)
        } else {
            content
        }
    }
}

private struct MenuBarStatusBadge: View {
    enum Style {
        case sharingLight
        case sharingDark
        case warning
    }

    let style: Style

    var body: some View {
        switch style {
        case .sharingLight:
            Circle()
                .fill(Color.black)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1.1)
                )
                .frame(width: 7, height: 7)
        case .sharingDark:
            Circle()
                .fill(Color.white)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.85), lineWidth: 1.1)
                )
                .frame(width: 7, height: 7)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.orange)
                .shadow(color: Color.black.opacity(0.15), radius: 0.3, x: 0, y: 0.2)
        }
    }
}

enum MenuBarIconAsset {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "app-icon-logo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

enum AppMode: String, CaseIterable, Identifiable {
    case use
    case share
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .use:
            return "Use Remote Macs"
        case .share:
            return "Share This Mac"
        case .both:
            return "Both"
        }
    }

    var allowsUse: Bool {
        self == .use || self == .both
    }

    var allowsShare: Bool {
        self == .share || self == .both
    }

    var defaultSwarmName: String {
        "My Private Swarm"
    }
}

enum PreferredRequestRoute: String, CaseIterable, Identifiable {
    case automatic
    case localOnly = "local_only"
    case trustedOnly = "trusted_only"
    case swarm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .localOnly:
            return "This Mac Only"
        case .trustedOnly:
            return "My Macs Only"
        case .swarm:
            return "Swarm Allowed"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "OnlyMacs picks the safest sensible route for built-in checks and starter guidance."
        case .localOnly:
            return "Keep starter work and self-tests on This Mac unless you intentionally widen the route."
        case .trustedOnly:
            return "Prefer your trusted Macs and keep starter work out of the broader swarm."
        case .swarm:
            return "Allow the broader active swarm by default when you use the starter path."
        }
    }

    var routeScope: String {
        switch self {
        case .automatic:
            return "swarm"
        case .localOnly:
            return "local_only"
        case .trustedOnly:
            return "trusted_only"
        case .swarm:
            return "swarm"
        }
    }

    func starterReviewCommand(base: String) -> String {
        switch self {
        case .automatic:
            return "\(base) \"do a code review on my project\""
        case .localOnly:
            return "\(base) go local-first \"do a code review on my project\""
        case .trustedOnly:
            return "\(base) go trusted-only \"do a code review on my project\""
        case .swarm:
            return "\(base) \"do a code review on my project\""
        }
    }
}

enum ControlCenterSection: String, CaseIterable, Identifiable {
    case swarms
    case currentSwarm
    case activity
    case sharing
    case models
    case tools
    case runtime
    case howToUse

    var id: String { rawValue }
    var automationID: String { rawValue }

    var title: String {
        switch self {
        case .swarms:
            return "Swarms"
        case .currentSwarm:
            return "Current Swarm"
        case .activity:
            return "Activity"
        case .sharing:
            return "Sharing"
        case .models:
            return "Models"
        case .tools:
            return "Tools"
        case .runtime:
            return "Runtime"
        case .howToUse:
            return "How To Use"
        }
    }

    var subtitle: String {
        switch self {
        case .swarms:
            return "Switch swarms, create private ones, and invite people in."
        case .currentSwarm:
            return "See who is connected, serving, busy, and what models the swarm can run."
        case .activity:
            return "See recent swarm work, queue pressure, and savings."
        case .sharing:
            return "Publish this Mac, manage models, and check sharing health."
        case .models:
            return "See what this Mac can run, what is installed, and what is ready to add."
        case .tools:
            return "Check Codex, Claude Code, and terminal-friendly integrations."
        case .runtime:
            return "Launchers, coordinator targeting, runtime health, and logs."
        case .howToUse:
            return "See starter recipes and example OnlyMacs prompts that work well."
        }
    }

    var symbolName: String {
        switch self {
        case .swarms:
            return "circle.hexagongrid.fill"
        case .currentSwarm:
            return "person.3.sequence.fill"
        case .activity:
            return "chart.bar.fill"
        case .sharing:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .models:
            return "cpu.fill"
        case .tools:
            return "command.square.fill"
        case .runtime:
            return "gearshape.2.fill"
        case .howToUse:
            return "questionmark.circle.fill"
        }
    }
}

enum SetupSwarmChoice: String, CaseIterable, Identifiable {
    case publicSwarm
    case privateSwarm
    case joinInvite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicSwarm:
            return "OnlyMacs Public"
        case .privateSwarm:
            return "Create Private Swarm"
        case .joinInvite:
            return "Join With Invite"
        }
    }

    var detail: String {
        switch self {
        case .publicSwarm:
            return "Join the default open swarm and start using OnlyMacs right away."
        case .privateSwarm:
            return "Create one named invite-only swarm for your own Macs or a small trusted group."
        case .joinInvite:
            return "Paste a private invite token and join a swarm someone else created."
        }
    }

    var symbolName: String {
        switch self {
        case .publicSwarm:
            return "globe"
        case .privateSwarm:
            return "lock.fill"
        case .joinInvite:
            return "person.badge.plus"
        }
    }
}

enum SwarmConnectionState: Equatable {
    case loading
    case connected
    case disconnected
    case attention

    var title: String {
        switch self {
        case .loading:
            return "Loading"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .attention:
            return "Needs Attention"
        }
    }

    var color: Color {
        switch self {
        case .loading:
            return .blue
        case .connected:
            return .green
        case .disconnected:
            return .secondary
        case .attention:
            return .orange
        }
    }

    var symbolName: String {
        switch self {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "dot.radiowaves.left.and.right"
        case .disconnected:
            return "slash.circle"
        case .attention:
            return "exclamationmark.triangle.fill"
        }
    }
}
