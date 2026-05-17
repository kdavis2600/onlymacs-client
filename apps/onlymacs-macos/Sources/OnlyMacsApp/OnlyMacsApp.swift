import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import OnlyMacsCore
import SwiftUI

// BridgeStore is the app's primary state and side-effect owner. UI container
// views and window lifecycle code now live in dedicated ownership files.

@MainActor
final class BridgeStore: ObservableObject {
    private static let inviteExpiryFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    private static let activityFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    private static let bridgeTimestampFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let bridgeTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let startupLoadingGraceInterval: TimeInterval = 20
    private static let bridgeRefreshIntervalNanoseconds: UInt64 = 30_000_000_000

    @Published var selectedMode: AppMode = .both
    @Published var selectedSwarmID: String = ""
    @Published var newSwarmName: String = ""
    @Published var joinInviteToken: String = ""
    @Published var coordinatorConnectionMode: CoordinatorConnectionMode
    @Published var coordinatorURLDraft: String
    @Published var preferredRequestRoute: PreferredRequestRoute = .automatic
    @Published var onlyMacsNotificationsEnabled: Bool
    @Published var setupSwarmChoice: SetupSwarmChoice
    @Published var setupPrivateSwarmName: String
    @Published var setupInviteTokenDraft: String
    @Published var memberNameDraft: String
    @Published var pendingMemberNameConfirmation: String?
    @Published var isSavingMemberName = false
    @Published var setupLaunchAtLoginEnabled: Bool
    @Published var launchAtLoginEnabled: Bool
    @Published var controlCenterSection: ControlCenterSection = .swarms
    @Published var latestInviteToken: String = ""
    @Published var latestInviteExpiresAt: Date?
    @Published var snapshot: BridgeStatusSnapshot = .placeholder
    @Published var localShare: LocalShareSnapshot = .placeholder
    @Published var isLoading = false
    @Published var isRuntimeBusy = false
    @Published var isQuitting = false
    @Published var lastError: String?
    @Published var runtimeState: LocalRuntimeState = .bootstrapping
    @Published var jobWorkerState: OnlyMacsJobWorkerSupervisorState = .bootstrapping
    @Published var clipboardInviteToken: String?
    @Published var inviteProgress: InviteProgress?
    @Published var selfTestState: SelfTestState = .idle
    @Published var toolStatuses: [DetectedTool] = []
    @Published var catalog: ModelCatalog?
    @Published var capabilitySnapshot: ProviderCapabilitySnapshot = .init(unifiedMemoryGB: 0, freeDiskGB: 0)
    @Published var capabilityAssessment: ProviderCapabilityAssessment?
    @Published var installerPlan: InstallerRecommendationPlan?
    @Published var selectedInstallerModelIDs = Set<String>()
    @Published var modelDownloadQueue = ModelDownloadQueue(modelIDs: [])
    @Published var isInstallingStarterModels = false
    @Published var isCompletingGuidedSetup = false
    @Published var starterModelStatusDetail: String?
    @Published var starterModelCompletionDetail: String?
    @Published var hasCompletedStarterModelSetup: Bool
    @Published var selectedSetupLauncherTargets: Set<LauncherInstallTarget>
    @Published var catalogError: String?
    @Published var launcherStatus = LauncherInstaller.status()
    @Published var toolIntegrationRefreshNeedsAppRestart = false
    @Published var lastSupportBundlePath: String?
    @Published var latestOnlyMacsActivity: OnlyMacsCommandActivity?
    @Published var pendingFileAccessApproval: PendingFileAccessApproval?
    @Published var pendingFileAccessPresentationCounter: Int = 0
    @Published var isFileApprovalWindowVisible = false
    @Published var isCheckingForUpdates = false
    @Published var isDownloadingUpdate = false
    @Published var isInstallingUpdate = false
    @Published var isUpdateReadyToInstallOnQuit = false
    @Published var availableUpdate: OnlyMacsAvailableUpdate?
    @Published var updateCheckError: String?
    @Published var lastUpdateCheckAt: Date?

    // These stay app-internal, but are not `private`, so ownership-based
    // BridgeStore extensions can hold runtime/bootstrap logic outside this file.
    var refreshTask: Task<Void, Never>?
    var commandActivityPollTask: Task<Void, Never>?
    var fileAccessPollTask: Task<Void, Never>?
    var automationPollTask: Task<Void, Never>?
    var modelInstallTask: Task<Void, Never>?
    let startupLoadingGraceEndsAt = Date().addingTimeInterval(BridgeStore.startupLoadingGraceInterval)
    let decoder = JSONDecoder()
    let supervisor = LocalRuntimeSupervisor()
    let userDefaults: UserDefaults
    let buildInfo = BuildInfo.current
    let notificationService = OnlyMacsUserNotificationService()
    let modelInstaller = ModelInstallerService()
    let sparkleUpdater: OnlyMacsSparkleUpdater
    @Published var appliedCoordinatorSettings: CoordinatorConnectionSettings
    var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    var dismissedClipboardInviteToken: String?
    var latestOnlyMacsActivityModifiedAt: Date?
    var notificationsPrimed = false
    var installerQueueDetails: [String: String] = [:]
    var sessionSavedTokensBaseline: Int?
    var sessionUploadedTokensBaseline: Int?
    var hasAppliedInstallerSelectionDefaults = false
    var hasAppliedInstallerModelDefaults = false
    var hasCustomizedSetupSwarmChoice = false
    var hasManualSwarmSelectionDraft = false
    var hasEditedMemberNameDraft = false
    var hasHandledOllamaDependencyThisLaunch = false
    var hasActivatedMenuBarExperienceThisLaunch = false
    var hasTriggeredAutomaticPopupBootstrapThisLaunch = false
    var hasUserNavigatedPopupSectionsThisLaunch = false
    var hasHandledInteractiveActivationThisLaunch = false
    var isReconcilingAutomaticSharingState = false
    var finalizedFileAccessRequestIDs: [String: Date] = [:]
    let launchRequestedSetupWindow = ProcessInfo.processInfo.arguments.contains("--onlymacs-open-setup")
    let launchRequestedInstallerSelectionApply = ProcessInfo.processInfo.arguments.contains("--onlymacs-apply-installer-selections")
    let automationModeEnabled = ProcessInfo.processInfo.arguments.contains("--onlymacs-automation-mode")
    let installerPackageSelections: InstallerPackageSelections?
    let shouldPresentMenuBarRevealThisLaunch: Bool

    init() {
        let storedSettings = Self.loadCoordinatorSettings()
        let storedPreferredRoute = Self.loadPreferredRequestRoute()
        let storedNotificationsEnabled = Self.loadOnlyMacsNotificationsEnabled()
        let storedLaunchAtLoginPreference = Self.loadSetupLaunchAtLoginEnabled()
        let hasPresentedMenuBarReveal = Self.loadHasPresentedMenuBarReveal()
        let installerPackageSelections = InstallerPackageSelections.loadCurrent()
        self.installerPackageSelections = installerPackageSelections
        shouldPresentMenuBarRevealThisLaunch = !hasPresentedMenuBarReveal && !ProcessInfo.processInfo.arguments.contains("--onlymacs-automation-mode")
        coordinatorConnectionMode = storedSettings.mode
        coordinatorURLDraft = storedSettings.remoteCoordinatorURL
        preferredRequestRoute = storedPreferredRoute
        onlyMacsNotificationsEnabled = storedNotificationsEnabled
        setupSwarmChoice = .publicSwarm
        setupPrivateSwarmName = "My Private Swarm"
        setupInviteTokenDraft = ""
        memberNameDraft = Self.loadCachedMemberName() ?? Self.suggestedDefaultMemberName()
        setupLaunchAtLoginEnabled = installerPackageSelections?.runOnStartup ?? storedLaunchAtLoginPreference
        launchAtLoginEnabled = LaunchAtLoginManager.isEnabled()
        if let installerPackageSelections {
            selectedSetupLauncherTargets = installerPackageSelections.requestedLauncherTargets
        } else {
            selectedSetupLauncherTargets = [.codex, .claude]
        }
        appliedCoordinatorSettings = storedSettings
        userDefaults = .standard
        sparkleUpdater = OnlyMacsSparkleUpdater(buildInfo: buildInfo, notificationService: notificationService)
        hasCompletedStarterModelSetup = Self.loadStarterModelSetupCompleted()
        if let cachedInvite = Self.loadCachedInvite(), cachedInvite.isUsable {
            latestInviteToken = cachedInvite.token
            latestInviteExpiresAt = cachedInvite.expiresAt
            inviteProgress = InviteProgress(
                token: cachedInvite.token,
                swarmID: cachedInvite.swarmID,
                swarmName: cachedInvite.swarmName,
                stage: .created,
                detail: "Invite is ready to share."
            )
        }
        decoder.dateDecodingStrategy = .iso8601
        sparkleUpdater.automaticInstallDecisionProvider = { [weak self] in
            guard let self else {
                return .waitForIdle(reason: "OnlyMacs finishes starting")
            }
            return OnlyMacsAutomaticInstallDecision.evaluate(
                activeRequesterSessions: self.activeRequesterSessionSignal,
                activeLocalShareSessions: self.localShare.activeSessions,
                isRuntimeBusy: self.isRuntimeBusy,
                isInstallingStarterModels: self.isInstallingStarterModels,
                isCompletingGuidedSetup: self.isCompletingGuidedSetup
            )
        }
        sparkleUpdater.onStateChange = { [weak self] state in
            self?.applySparkleUpdateState(state)
        }
        applySparkleUpdateState(sparkleUpdater.state)
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [supervisor] _ in
            Task {
                await supervisor.stop()
            }
        }
        _ = NotificationCenter.default.addObserver(
            forName: OnlyMacsAppNotification.didOpenURL,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            Task { @MainActor [weak self] in
                self?.handleIncomingURL(url)
            }
        }
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleInteractiveActivationIfNeeded()
            }
        }
        startRefreshing()
        reloadInstallerRecommendations()
        refreshLauncherStatus()
        applyInstallerPackageSelectionsIfNeeded()
        refreshSetupLauncherSelections()
        refreshSetupDefaultsFromRuntime()
        focusSwarmsSectionIfNeeded(force: launchRequestedSetupWindow || launchRequestedInstallerSelectionApply)
    }

    deinit {
        refreshTask?.cancel()
        commandActivityPollTask?.cancel()
        fileAccessPollTask?.cancel()
        automationPollTask?.cancel()
        modelInstallTask?.cancel()
    }

    var menuBarIconName: String {
        menuBarVisualState.iconName
    }

    var menuBarIconImage: NSImage? {
        MenuBarIconAsset.image
    }

    var activeRequesterSessionSignal: Int {
        let launcherActive = latestOnlyMacsActivity?.isRecentInProgress() == true ? 1 : 0
        return max(snapshot.swarm.activeSessionCount, snapshot.usage.activeReservations, launcherActive)
    }

    var menuBarVisualState: MenuBarVisualState {
        deriveMenuBarVisualState(
            bridgeStatus: snapshot.bridge.status,
            runtimeStatus: runtimeState.status,
            activeRequesterSessions: activeRequesterSessionSignal,
            localSharePublished: localShare.published,
            localShareSlotsFree: localShare.slots.free,
            localShareSlotsTotal: localShare.slots.total,
            hasConfirmedStatus: snapshot.lastUpdated != nil,
            isLoading: isLoading,
            isRuntimeBusy: isRuntimeBusy,
            startupGraceActive: isStartupLoadingGraceActive
        )
    }

    var menuBarStateTitle: String {
        menuBarVisualState.title
    }

    var swarmConnectionState: SwarmConnectionState {
        deriveSwarmConnectionState(
            bridgeStatus: snapshot.bridge.status,
            runtimeStatus: runtimeState.status,
            hasActiveSwarm: activeRuntimeSwarm != nil,
            hasConfirmedStatus: snapshot.lastUpdated != nil,
            isLoading: isLoading,
            isRuntimeBusy: isRuntimeBusy,
            startupGraceActive: isStartupLoadingGraceActive
        )
    }

    var swarmConnectionTitle: String {
        swarmConnectionState.title
    }

    var swarmConnectionColor: Color {
        swarmConnectionState.color
    }

    var swarmConnectionSymbolName: String {
        swarmConnectionState.symbolName
    }

    var activeSwarmHeadline: String {
        if swarmConnectionState == .loading, activeRuntimeSwarm == nil {
            return "Starting OnlyMacs"
        }
        return activeRuntimeSwarm?.connectedHeadlineTitle ?? "No active swarm"
    }

    var activeSwarmDetail: String {
        switch swarmConnectionState {
        case .loading:
            return "Status: Loading. Starting the local bridge and reconnecting to the swarm."
        case .connected:
            guard activeRuntimeSwarm != nil else {
                return "OnlyMacs is healthy, but no swarm is currently connected."
            }
            return deriveSwarmActivityStatusPresentation(
                activeRequesterSessions: activeRequesterSessionSignal,
                localShareActiveSessions: localShare.activeSessions,
                remoteTokensPerSecond: snapshot.usage.recentRemoteTokensPerSecond,
                localTokensPerSecond: localShare.recentUploadedTokensPerSecond
            ).detail
        case .disconnected:
            return "Choose a swarm to connect this Mac and your requests. Everyone lands in OnlyMacs Public by default."
        case .attention:
            return menuBarStateDetail
        }
    }

    private var isStartupLoadingGraceActive: Bool {
        Date() < startupLoadingGraceEndsAt
    }

    var activeSwarmMetricLine: String {
        guard let activeRuntimeSwarm else {
            return snapshot.summaryLine
        }
        return activeRuntimeSwarm.selectionDetail(activeSessionCount: snapshot.swarm.activeSessionCount)
    }

    var menuBarStateDetail: String {
        switch menuBarVisualState {
        case .ready:
            if localEligibilitySummary.isEligible {
                return "OnlyMacs is healthy, and This Mac is currently eligible for local requester work."
            }
            return "OnlyMacs is healthy, but This Mac is not the first local candidate right now."
        case .usingRemote:
            return "OnlyMacs is currently borrowing compute from other Macs."
        case .sharing:
            return "This Mac is actively serving swarm work right now."
        case .both:
            return "OnlyMacs is both borrowing compute and serving this Mac at the same time."
        case .loading:
            return "OnlyMacs is starting the local bridge and reconnecting to the swarm."
        case .degraded:
            return "OnlyMacs needs attention before it should be trusted for more live work."
        }
    }

    var formattedLastUpdated: String {
        guard let lastUpdated = snapshot.lastUpdated else {
            return "Never"
        }
        return lastUpdated.formatted(date: .omitted, time: .standard)
    }

    var buildDisplayLabel: String {
        buildInfo.displayLabel
    }

    var buildDetailLabel: String {
        buildInfo.detailLabel
    }

    var updateStatusTitle: String {
        if isUpdateReadyToInstallOnQuit {
            return "Restart to update"
        }
        if isInstallingUpdate {
            return "Applying update…"
        }
        if isDownloadingUpdate {
            return "Downloading update…"
        }
        if isCheckingForUpdates {
            return "Checking for updates…"
        }
        if let availableUpdate {
            return "Update available: \(availableUpdate.displayLabel)"
        }
        if shouldSurfaceOnlyMacsUpdateError(updateCheckError) {
            return "Update check failed"
        }
        if lastUpdateCheckAt != nil {
            return "OnlyMacs is up to date"
        }
        return "Update checks are ready"
    }

    var updateStatusDetail: String {
        if !buildInfo.sparkleConfigured {
            return "This build is missing the Sparkle feed or signing key, so in-app automatic updates are disabled."
        }
        if isUpdateReadyToInstallOnQuit {
            return "Sparkle already downloaded \(availableUpdate?.displayLabel ?? "the latest build"). OnlyMacs will install it automatically when no swarm work is active, or you can use Restart to Update now."
        }
        if isInstallingUpdate {
            return "Sparkle is applying the downloaded update and relaunching OnlyMacs."
        }
        if isDownloadingUpdate {
            return "Sparkle is downloading the latest signed app archive after the update was requested."
        }
        if isCheckingForUpdates {
            return "OnlyMacs is asking the Sparkle appcast whether a newer build is available for the \(buildInfo.channelIdentifier) channel."
        }
        if let availableUpdate {
            var parts = [
                "Current: \(buildDisplayLabel)",
                "Latest: \(availableUpdate.detailLabel)",
            ]
            if let releaseNotesURL = availableUpdate.releaseNotesURL {
                parts.append("Release notes: \(releaseNotesURL.absoluteString)")
            }
            return parts.joined(separator: " • ")
        }
        if shouldSurfaceOnlyMacsUpdateError(updateCheckError), let updateCheckError {
            return updateCheckError
        }
        if let lastUpdateCheckAt {
            return "Checked \(Self.activityFormatter.localizedString(for: lastUpdateCheckAt, relativeTo: Date())). Current build: \(buildDisplayLabel)."
        }
        return "OnlyMacs checks for release notices while the app is open, then asks Sparkle to download signed updates in the background. App replacement waits until OnlyMacs is idle."
    }

    var updateLastCheckedLabel: String {
        guard let lastUpdateCheckAt else { return "Never" }
        return lastUpdateCheckAt.formatted(date: .abbreviated, time: .shortened)
    }

    var updateActionTitle: String {
        if isUpdateReadyToInstallOnQuit {
            return "Restart to Update"
        }
        if isInstallingUpdate {
            return "Applying…"
        }
        if isDownloadingUpdate {
            return "Downloading…"
        }
        if availableUpdate != nil {
            return "Install Update"
        }
        return "Check for Updates"
    }

    var updateActionDetail: String {
        if !buildInfo.sparkleConfigured {
            return "OnlyMacs needs a Sparkle feed URL and public signing key before seamless app updates can start."
        }
        if isUpdateReadyToInstallOnQuit {
            return "Installs the downloaded update immediately and relaunches OnlyMacs, even if automatic install is waiting for idle time."
        }
        if let availableUpdate {
            return "Brings the Sparkle update flow into focus for \(availableUpdate.displayLabel)."
        }
        return "Checks the live Sparkle appcast now. OnlyMacs also starts this check automatically when the hosted release feed publishes a newer build."
    }

    var formattedTokensSaved: String {
        Self.formatSavedTokens(snapshot.usage.tokensSavedEstimate)
    }

    var sessionTokensUsed: Int {
        deriveSessionTokensUsed(
            tokensSavedEstimate: snapshot.usage.tokensSavedEstimate,
            uploadedTokensEstimate: localShare.uploadedTokensEstimate,
            baselineSavedTokens: sessionSavedTokensBaseline,
            baselineUploadedTokens: sessionUploadedTokensBaseline
        )
    }

    var lifetimeTokensUsed: Int {
        deriveLifetimeTokensUsed(
            tokensSavedEstimate: snapshot.usage.tokensSavedEstimate,
            uploadedTokensEstimate: localShare.uploadedTokensEstimate
        )
    }

    var formattedSessionAndLifetimeTokensUsed: String {
        "\(Self.formatSavedTokens(sessionTokensUsed)) tokens used (this session), \(Self.formatSavedTokens(lifetimeTokensUsed)) lifetime"
    }

    func formattedSavedTokens(_ tokens: Int) -> String {
        Self.formatSavedTokens(tokens)
    }

    var recentSwarmDisplayItems: [RecentSwarmDisplayItem] {
        snapshot.swarm.recentSessions.map { session in
            RecentSwarmDisplayItem(
                id: session.id,
                title: session.title ?? session.id,
                status: session.status,
                resolvedModel: session.resolvedModel,
                routeSummary: session.routeSummary,
                selectionExplanation: session.selectionExplanation,
                warningMessage: sessionWarningMessage(session),
                premiumNudge: sessionPremiumNudgeMessage(session),
                savedTokensLabel: "Saved \(formattedSavedTokens(session.savedTokensEstimate))",
                queueBadge: sessionQueueBadge(session),
                queueDetail: sessionQueueDetail(session)
            )
        }
    }

    var setupAssistantStepDisplayItems: [SetupAssistantStepDisplayItem] {
        setupAssistant.steps.map { step in
            SetupAssistantStepDisplayItem(
                id: step.id.uuidString,
                title: step.title,
                detail: step.detail,
                symbolName: step.status.symbolName,
                color: step.status.color
            )
        }
    }

    var selfTestStatusDetail: String? {
        selfTestState == .idle ? nil : selfTestState.detail
    }

    var selfTestStatusColor: Color? {
        selfTestState == .idle ? nil : selfTestState.color
    }

    var selfTestButtonTitle: String {
        selfTestState.buttonTitle
    }

    var setupAssistantStageTitle: String {
        setupAssistant.stageTitle
    }

    var setupAssistantETALabel: String {
        setupAssistant.etaLabel
    }

    var guidedSetupIsReadyToClose: Bool {
        setupAssistant.stageTitle == "Ready"
    }

    var setupAssistantProgressValue: Double {
        let steps = setupAssistant.steps
        guard !steps.isEmpty else { return 0 }

        let weightedCompletion = steps.reduce(0.0) { partial, step in
            switch step.status {
            case .done:
                return partial + 1
            case .inProgress:
                return partial + 0.6
            case .pending:
                return partial + 0.15
            case .blocked:
                return partial
            }
        }

        return min(max(weightedCompletion / Double(steps.count), 0), 1)
    }

    var setupAssistantProgressLabel: String {
        let completedCount = setupAssistant.steps.filter { $0.status == .done }.count
        let totalCount = setupAssistant.steps.count
        guard totalCount > 0 else { return "Preparing setup checks…" }
        return "\(completedCount) of \(totalCount) setup checks completed"
    }

    var setupAssistantProgressDetail: String? {
        if setupAssistant.stageTitle == "Ready" {
            return "OnlyMacs is ready. Switch to the menu bar icon for quick status, swarms, and models."
        }

        if isInstallingStarterModels {
            let activeItem = installerQueueDisplayItems.first(where: { item in
                item.phaseLabel == "Downloading" || item.phaseLabel == "Warming"
            }) ?? installerQueueDisplayItems.first(where: { $0.phaseLabel == "Pending" })

            let remainingCount = installerQueueDisplayItems.filter { item in
                item.phaseLabel != "Done"
            }.count

            if let activeItem {
                var parts = ["\(activeItem.title) is in progress."]
                if let detail = activeItem.detail, !detail.isEmpty {
                    parts.append(detail)
                }
                parts.append("\(remainingCount) model download\(remainingCount == 1 ? "" : "s") still need attention.")
                parts.append("ETA \(setupAssistantETALabel).")
                return parts.joined(separator: " ")
            }

            return "Starter model setup is still running in the background. ETA \(setupAssistantETALabel)."
        }

        let remainingTitles = setupAssistant.steps
            .filter { $0.status != .done }
            .map(\.title)

        guard !remainingTitles.isEmpty else {
            return "OnlyMacs is wrapping up the final checks now."
        }

        let preview = remainingTitles.prefix(2).joined(separator: " and ")
        let suffix = remainingTitles.count > 2 ? ", plus \(remainingTitles.count - 2) more." : "."
        return "Still working on \(preview)\(suffix) ETA \(setupAssistantETALabel)."
    }

    var nextModelSuggestionText: String? {
        guard let suggestion = nextModelSuggestion else { return nil }
        return "\(suggestion.name) is already local. Publish it next to expand request coverage."
    }

    var visibleModelDisplayItems: [ModelAvailabilityDisplayItem] {
        snapshot.models.map { model in
            ModelAvailabilityDisplayItem(
                id: model.id,
                name: model.name,
                identifier: model.id,
                slotsLabel: "\(model.slotsFree)/\(model.slotsTotal)"
            )
        }
    }

    var compactRecentSwarmDisplayItems: [RecentSwarmDisplayItem] {
        Array(recentSwarmDisplayItems.prefix(3))
    }

    var settingsRecentSwarmDisplayItems: [RecentSwarmDisplayItem] {
        Array(recentSwarmDisplayItems.prefix(5))
    }

    var compactVisibleModelDisplayItems: [ModelAvailabilityDisplayItem] {
        Array(visibleModelDisplayItems.prefix(4))
    }

    var publishedLocalModelIDs: Set<String> {
        Set(localShare.publishedModels.map(\.id))
    }

    var detectedToolDisplayItems: [DetectedToolDisplayItem] {
        toolStatuses.map { tool in
            DetectedToolDisplayItem(
                id: tool.id.uuidString,
                name: tool.name,
                statusTitle: tool.statusTitle,
                statusColor: tool.color,
                detail: tool.detail,
                locationDetail: toolLocationDetail(for: tool.name),
                actionTitle: tool.actionTitle,
                performAction: tool.actionTitle == nil ? nil : { tool.performAction() }
            )
        }
    }

    var toolIntegrationPrimaryActionTitle: String {
        launcherStatus.installed ? "Refresh All Tools" : "Install All Tools"
    }

    var toolIntegrationPrimaryDetail: String {
        if !launcherStatus.installed {
            return "Installs the OnlyMacs CLI plus Codex, Claude Code, and the shared `.agents` skill surface used by compatible editors like OpenCode."
        }
        if shouldReopenDetectedTools {
            return "OnlyMacs refreshed an assistant integration while the app was already open. If the command surface is missing there, quit and reopen that app once."
        }
        return "The command, Codex skill, Claude Code command, and shared skill surfaces are installed. Refresh all tools here if a file looks stale."
    }

    var popupToolDisplayItems: [DetectedToolDisplayItem] {
        func appURL(bundleIdentifiers: [String], fallbackPaths: [String]) -> URL? {
            for identifier in bundleIdentifiers {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                    return url
                }
            }
            for path in fallbackPaths {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
            return nil
        }

        func openAppAction(_ url: URL?) -> (() -> Void)? {
            guard let url else { return nil }
            return {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
        }

        func fileExists(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
        }

        func commandExists(_ command: String) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [command]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }

        let cliURL = launcherStatus.entrypointURL
        let codexSkillURL = LauncherInstaller.agentsSkillsDirectoryURL
            .appendingPathComponent("onlymacs/SKILL.md", isDirectory: false)
        let codexShellURL = LauncherInstaller.shimDirectoryURL
            .appendingPathComponent("onlymacs-shell", isDirectory: false)
        let claudeCommandURL = LauncherInstaller.claudeCommandsDirectoryURL
            .appendingPathComponent("onlymacs.md", isDirectory: false)
        let claudeSkillURL = LauncherInstaller.claudeSkillsDirectoryURL
            .appendingPathComponent("onlymacs/SKILL.md", isDirectory: false)

        func editorToolItem(
            name: String,
            bundleIdentifiers: [String],
            fallbackPaths: [String],
            commandName: String? = nil,
            usesAgentsSkill: Bool = false
        ) -> DetectedToolDisplayItem {
            let detectedURL = appURL(bundleIdentifiers: bundleIdentifiers, fallbackPaths: fallbackPaths)
            let commandVisible = commandName.map(commandExists) ?? false
            let agentsSkillVisible = fileExists(codexSkillURL)
            if usesAgentsSkill {
                let statusTitle: String
                let statusColor: Color
                let detail: String
                let actionTitle: String?
                let performAction: (() -> Void)?
                if agentsSkillVisible {
                    statusTitle = commandVisible || detectedURL != nil ? "Shared Skill Visible" : "Skill Ready"
                    statusColor = .green
                    detail = "\(name) can use OnlyMacs if it reads shared `.agents` skills. The OnlyMacs skill is visible at ~/.agents/skills/onlymacs/SKILL.md."
                    actionTitle = detectedURL != nil ? "Open \(name)" : nil
                    performAction = openAppAction(detectedURL)
                } else {
                    statusTitle = "Skill Not Visible"
                    statusColor = .orange
                    detail = "\(name) appears compatible with shared `.agents` skills, but the OnlyMacs skill is not installed there yet."
                    actionTitle = "Install Shared Skill"
                    performAction = { self.installLaunchersNow(targets: [.core, .codex]) }
                }
                return DetectedToolDisplayItem(
                    id: "tool-\(name.lowercased())",
                    name: name,
                    statusTitle: statusTitle,
                    statusColor: statusColor,
                    detail: detail,
                    locationDetail: "\(codexSkillURL.path)\n\(cliURL.path)",
                    actionTitle: actionTitle,
                    performAction: performAction
                )
            }
            if !launcherStatus.installed {
                return DetectedToolDisplayItem(
                    id: "tool-\(name.lowercased())",
                    name: name,
                    statusTitle: "CLI Needed",
                    statusColor: .orange,
                    detail: "\(name) uses the shared OnlyMacs CLI from its integrated terminal.",
                    locationDetail: cliURL.path,
                    actionTitle: "Install OnlyMacs CLI",
                    performAction: { self.installLaunchersNow(targets: [.core]) }
                )
            }
            return DetectedToolDisplayItem(
                id: "tool-\(name.lowercased())",
                name: name,
                statusTitle: detectedURL != nil || commandVisible ? "Terminal Ready" : "Optional",
                statusColor: detectedURL != nil || commandVisible ? .green : .secondary,
                detail: "OnlyMacs does not install a native \(name) skill yet. Use the shared `onlymacs` command from this editor's integrated terminal.",
                locationDetail: cliURL.path,
                actionTitle: detectedURL != nil ? "Open \(name)" : nil,
                performAction: openAppAction(detectedURL)
            )
        }

        func codexToolItem() -> DetectedToolDisplayItem {
            let detectedURL = appURL(
                bundleIdentifiers: [
                    "com.openai.codex",
                    "com.openai.chatgpt.codex",
                ],
                fallbackPaths: [
                    "/Applications/Codex.app",
                    "/Applications/OpenAI Codex.app",
                ]
            )
            let installed = fileExists(codexSkillURL) && fileExists(codexShellURL)
            if installed {
                let restartRecommended = toolIntegrationRefreshNeedsAppRestart && detectedURL != nil && Self.bundleIdentifierIsRunning([
                    "com.openai.codex",
                    "com.openai.chatgpt.codex",
                ])
                return DetectedToolDisplayItem(
                    id: "tool-codex",
                    name: "Codex",
                    statusTitle: restartRecommended ? "Restart Recommended" : "Installed",
                    statusColor: restartRecommended ? .orange : .green,
                    detail: restartRecommended
                        ? "OnlyMacs refreshed the Codex skill while Codex may already be running. The files are installed; restart Codex only if `/onlymacs` is missing there."
                        : "Codex can use the shared OnlyMacs skill and shell launcher. The files are visible on disk.",
                    locationDetail: "\(codexSkillURL.path)\n\(codexShellURL.path)",
                    actionTitle: detectedURL != nil ? "Open Codex" : nil,
                    performAction: openAppAction(detectedURL)
                )
            }
            return DetectedToolDisplayItem(
                id: "tool-codex",
                name: "Codex",
                statusTitle: detectedURL == nil ? "App Not Found" : "Integration Needed",
                statusColor: detectedURL == nil ? .secondary : .orange,
                detail: "Installs the Codex-compatible OnlyMacs skill and shell launcher.",
                locationDetail: "\(codexSkillURL.path)\n\(codexShellURL.path)",
                actionTitle: "Install Codex Integration",
                performAction: { self.installLaunchersNow(targets: [.core, .codex]) }
            )
        }

        func claudeToolItem() -> DetectedToolDisplayItem {
            let detectedURL = appURL(
                bundleIdentifiers: [
                    "com.anthropic.claudefordesktop",
                    "com.anthropic.claude",
                ],
                fallbackPaths: [
                    "/Applications/Claude.app",
                ]
            )
            let installed = fileExists(claudeCommandURL) && fileExists(claudeSkillURL)
            if installed {
                let restartRecommended = toolIntegrationRefreshNeedsAppRestart && detectedURL != nil && Self.bundleIdentifierIsRunning([
                    "com.anthropic.claudefordesktop",
                    "com.anthropic.claude",
                ])
                return DetectedToolDisplayItem(
                    id: "tool-claude",
                    name: "Claude Code",
                    statusTitle: restartRecommended ? "Restart Recommended" : "Installed",
                    statusColor: restartRecommended ? .orange : .green,
                    detail: restartRecommended
                        ? "OnlyMacs refreshed the Claude command while Claude Code may already be running. The files are installed; restart Claude Code only if `/onlymacs` is missing there."
                        : "Claude Code can use the OnlyMacs slash command and skill. The files are visible on disk.",
                    locationDetail: "\(claudeCommandURL.path)\n\(claudeSkillURL.path)",
                    actionTitle: detectedURL != nil ? "Open Claude Code" : nil,
                    performAction: openAppAction(detectedURL)
                )
            }
            return DetectedToolDisplayItem(
                id: "tool-claude",
                name: "Claude Code",
                statusTitle: detectedURL == nil ? "App Not Found" : "Integration Needed",
                statusColor: detectedURL == nil ? .secondary : .orange,
                detail: "Installs the Claude Code slash command and OnlyMacs skill.",
                locationDetail: "\(claudeCommandURL.path)\n\(claudeSkillURL.path)",
                actionTitle: "Install Claude Integration",
                performAction: { self.installLaunchersNow(targets: [.core, .claude]) }
            )
        }

        let commandItem = DetectedToolDisplayItem(
            id: "tool-onlymacs-command",
            name: "OnlyMacs CLI",
            statusTitle: launcherStatusLabel,
            statusColor: launcherStatus.installed ? (launcherStatus.pathNeedsSetup ? .orange : .green) : .orange,
            detail: launcherStatus.detail,
            locationDetail: cliURL.path,
            actionTitle: launcherStatus.installed ? "Refresh OnlyMacs CLI" : "Install OnlyMacs CLI",
            performAction: { self.installLaunchersNow(targets: [.core]) }
        )

        return [commandItem]
            + [codexToolItem(), claudeToolItem()]
            + [
                editorToolItem(
                    name: "OpenCode",
                    bundleIdentifiers: ["com.opencodestudio.app"],
                    fallbackPaths: ["/Applications/OpenCode.app"],
                    commandName: "opencode",
                    usesAgentsSkill: true
                ),
                editorToolItem(
                    name: "Cursor",
                    bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"],
                    fallbackPaths: ["/Applications/Cursor.app"],
                    commandName: "cursor"
                ),
                editorToolItem(
                    name: "VS Code",
                    bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
                    fallbackPaths: ["/Applications/Visual Studio Code.app", "/Applications/Visual Studio Code - Insiders.app"],
                    commandName: "code"
                ),
            ]
    }

    private func toolLocationDetail(for name: String) -> String? {
        switch name {
        case "Codex":
            let skillURL = LauncherInstaller.agentsSkillsDirectoryURL
                .appendingPathComponent("onlymacs/SKILL.md", isDirectory: false)
            let shellURL = LauncherInstaller.shimDirectoryURL
                .appendingPathComponent("onlymacs-shell", isDirectory: false)
            return "\(skillURL.path)\n\(shellURL.path)"
        case "Claude Code":
            let commandURL = LauncherInstaller.claudeCommandsDirectoryURL
                .appendingPathComponent("onlymacs.md", isDirectory: false)
            let skillURL = LauncherInstaller.claudeSkillsDirectoryURL
                .appendingPathComponent("onlymacs/SKILL.md", isDirectory: false)
            return "\(commandURL.path)\n\(skillURL.path)"
        default:
            return LauncherInstaller.shimDirectoryURL.appendingPathComponent("onlymacs", isDirectory: false).path
        }
    }

    var latestOnlyMacsActivityDisplayItem: OnlyMacsActivityDisplayItem? {
        guard let activity = latestOnlyMacsActivity else { return nil }
        let sessionLabel: String?
        if let sessionStatus = activity.sessionStatus, let sessionID = activity.sessionID {
            sessionLabel = "\(sessionStatus.capitalized) • \(sessionID)"
        } else if let sessionStatus = activity.sessionStatus {
            sessionLabel = sessionStatus.capitalized
        } else if let sessionID = activity.sessionID {
            sessionLabel = sessionID
        } else {
            sessionLabel = nil
        }

        return OnlyMacsActivityDisplayItem(
            title: activity.displayTitle,
            statusTitle: humanOnlyMacsOutcome(activity.outcome),
            detail: activity.detail ?? "OnlyMacs recorded a recent launcher action from \(activity.toolName).",
            timestampLabel: Self.activityFormatter.localizedString(for: activity.recordedAt, relativeTo: Date()),
            routeLabel: activity.routeScope.map(humanRouteScope),
            modelLabel: activity.model,
            sessionLabel: sessionLabel,
            warningStyle: activity.outcome == "failed"
        )
    }

    var latestOnlyMacsActivitySummary: String? {
        guard let activity = latestOnlyMacsActivity else { return nil }
        var parts = [activity.displayTitle, humanOnlyMacsOutcome(activity.outcome)]
        if let routeScope = activity.routeScope, !routeScope.isEmpty {
            parts.append(humanRouteScope(routeScope))
        }
        if let model = activity.model, !model.isEmpty {
            parts.append(model)
        }
        if let detail = activity.detail, !detail.isEmpty {
            parts.append(detail)
        }
        return parts.joined(separator: " • ")
    }

    var recentProviderActivityDisplayItems: [ProviderServeActivityDisplayItem] {
        localShare.recentProviderActivity.map { activity in
            let requesterLabel = activity.requesterMemberName
                ?? activity.requesterMemberID
                ?? "Another Mac"
            let timestamp = Self.parseBridgeTimestamp(activity.completedAt)
                ?? Self.parseBridgeTimestamp(activity.updatedAt)
                ?? Self.parseBridgeTimestamp(activity.startedAt)
                ?? Date()
            let modelLabel = activity.resolvedModel
            let sessionLabel = activity.sessionID
            let tokensLabel = activity.uploadedTokensEstimate > 0
                ? "\(Self.formatSavedTokens(activity.uploadedTokensEstimate)) tokens"
                : nil

            let detail: String
            switch activity.status {
            case "running":
                detail = "\(requesterLabel) is using this Mac right now\(modelLabel.map { " on \($0)" } ?? ".")"
            case "completed":
                detail = "\(requesterLabel) finished a remote run on this Mac\(modelLabel.map { " with \($0)" } ?? ".")"
            case "failed":
                detail = activity.error?.isEmpty == false
                    ? activity.error!
                    : "\(requesterLabel)'s remote run on this Mac failed."
            case "cancelled":
                detail = activity.error?.isEmpty == false
                    ? activity.error!
                    : "\(requesterLabel)'s remote run on this Mac was cancelled."
            default:
                detail = "\(requesterLabel) used this Mac through OnlyMacs."
            }

            return ProviderServeActivityDisplayItem(
                id: activity.id,
                title: requesterLabel,
                statusTitle: humanProviderActivityStatus(activity.status),
                detail: detail,
                timestampLabel: Self.activityFormatter.localizedString(for: timestamp, relativeTo: Date()),
                modelLabel: modelLabel,
                sessionLabel: sessionLabel,
                tokensLabel: tokensLabel,
                warningStyle: activity.status == "failed" || activity.status == "cancelled"
            )
        }
    }

    var onlyMacsNotificationsDetail: String {
        if onlyMacsNotificationsEnabled {
            return "Desktop alerts fire once when an OnlyMacs swarm completes or fails, or when the latest `/onlymacs` command fails."
        }
        return "Desktop alerts are off. OnlyMacs will keep mirroring the latest command and recent swarms here without posting notifications."
    }

    static func parseBridgeTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let parsed = bridgeTimestampFormatterWithFractional.date(from: value) {
            return parsed
        }
        return bridgeTimestampFormatter.date(from: value)
    }

    func humanProviderActivityStatus(_ status: String) -> String {
        switch status {
        case "running":
            return "Working"
        case "completed":
            return "Completed"
        case "failed":
            return "Failed"
        case "cancelled":
            return "Cancelled"
        default:
            return status.capitalized
        }
    }
    func sessionQueueBadge(_ session: SwarmSessionSnapshot) -> String? {
        if session.queueRemainder > 0 {
            return "\(session.queueRemainder) queued"
        }
        if !(session.queueReason ?? "").isEmpty, session.status == "queued" {
            return "Queued"
        }
        return nil
    }
    func sessionQueueDetail(_ session: SwarmSessionSnapshot) -> String? {
        var parts: [String] = []
        let reason = Self.humanQueueReason(session.queueReason ?? "")
        if !reason.isEmpty {
            parts.append(reason)
        }
        if session.etaSeconds > 0 {
            parts.append("ETA \(Self.shortETALabel(session.etaSeconds))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    func sessionPremiumNudgeMessage(_ session: SwarmSessionSnapshot) -> String? {
        guard session.selectionReason == "scarce_premium_fallback" else { return nil }
        return "Scarce premium slot protected. OnlyMacs kept this swarm moving on the best strong fallback instead of making it wait."
    }
    func sessionWarningMessage(_ session: SwarmSessionSnapshot) -> String? {
        session.warnings?.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    var queuePressureLabel: String? {
        guard snapshot.swarm.queuedSessionCount > 0 else { return nil }
        let reason = snapshot.swarm.queueSummary.primaryReason
        let human = Self.humanQueueReason(reason)
        return human.isEmpty ? "Active queue pressure" : human
    }

    var queuePressureDetail: String? {
        guard snapshot.swarm.queuedSessionCount > 0 else { return nil }
        var parts: [String] = []
        if !snapshot.swarm.queueSummary.primaryDetail.isEmpty {
            parts.append(snapshot.swarm.queueSummary.primaryDetail)
        }
        if let breakdown = queuePressureBreakdown {
            parts.append(breakdown)
        }
        if snapshot.swarm.queueSummary.nextETASeconds > 0 {
            parts.append("Next opening \(Self.shortETALabel(snapshot.swarm.queueSummary.nextETASeconds)).")
        }
        if !snapshot.swarm.queueSummary.suggestedAction.isEmpty {
            parts.append(snapshot.swarm.queueSummary.suggestedAction)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var queuePressureBreakdown: String? {
        guard snapshot.swarm.queuedSessionCount > 0 else { return nil }
        var parts: [String] = []
        if snapshot.swarm.queueSummary.memberCapCount > 0 {
            parts.append("\(snapshot.swarm.queueSummary.memberCapCount) member-budget hold\(snapshot.swarm.queueSummary.memberCapCount == 1 ? "" : "s")")
        }
        if snapshot.swarm.queueSummary.requesterBudgetCount > 0 {
            parts.append("\(snapshot.swarm.queueSummary.requesterBudgetCount) requester-budget hold\(snapshot.swarm.queueSummary.requesterBudgetCount == 1 ? "" : "s")")
        }
        if snapshot.swarm.queueSummary.staleQueuedCount > 0 {
            parts.append("\(snapshot.swarm.queueSummary.staleQueuedCount) stale queued")
        }
        if parts.isEmpty {
            return nil
        }
        return "Queue mix: \(parts.joined(separator: " • "))."
    }

    var supportURL: URL {
        Self.supportURL
    }

    var coordinatorSettings: CoordinatorConnectionSettings {
        CoordinatorConnectionSettings(
            mode: coordinatorConnectionMode,
            remoteCoordinatorURL: coordinatorURLDraft
        )
    }

    var hasPendingCoordinatorChanges: Bool {
        coordinatorSettings != appliedCoordinatorSettings
    }

    var effectiveCoordinatorTarget: String {
        coordinatorSettings.effectiveCoordinatorURL
    }

    var shouldAutoFocusSwarmsSection: Bool {
        if automationModeEnabled {
            return false
        }
        if launchRequestedSetupWindow && !guidedSetupIsReadyToClose {
            return true
        }
        if launchRequestedInstallerSelectionApply && !hasCompletedStarterModelSetup {
            return true
        }
        if runtimeState.ollamaStatus != .ready && runtimeState.ollamaStatus != .external {
            return true
        }
        if !hasCompletedStarterModelSetup {
            return true
        }
        if !launcherStatus.installed {
            return true
        }
        if snapshot.runtime.activeSwarmID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    var launchedFromInstallerSelections: Bool {
        launchRequestedInstallerSelectionApply && installerPackageSelections?.presentedByInstaller == true
    }

    var shouldBootstrapOllamaDependency: Bool {
        shouldAutoBootstrapOllamaDependency(
            launchRequestedInstallerSelectionApply: launchRequestedInstallerSelectionApply,
            installerPackageSelections: installerPackageSelections
        )
    }

    var ollamaActionTitle: String? {
        switch runtimeState.ollamaStatus {
        case .missing:
            return "Install Ollama"
        case .installedButUnavailable:
            return "Launch Ollama"
        case .ready, .external:
            return nil
        }
    }

    var launchAtLoginStatusTitle: String {
        launchAtLoginEnabled ? "On" : "Off"
    }

    var launchAtLoginDetail: String {
        if launchAtLoginEnabled {
            return "OnlyMacs will start again after you sign in on this Mac."
        }
        return "OnlyMacs stays off after sign-in until you launch it manually."
    }

    var setupLaunchAtLoginDetail: String {
        if setupLaunchAtLoginEnabled {
            return "Recommended. OnlyMacs will reopen after restart so your models and sharing state can come back automatically."
        }
        return "OnlyMacs will stay manual after restart until you launch it yourself."
    }

    var setupSwarmCoordinatorDetail: String {
        if coordinatorConnectionMode == .hostedRemote {
            return "Hosted Remote is active, so swarms and invites can be shared across Macs."
        }
        return "OnlyMacs is preparing the hosted coordinator so swarms and invites can be shared across Macs."
    }

    var setupSelectedLauncherSummary: String {
        let toolTitles = selectedSetupLauncherTargets.sorted { $0.rawValue < $1.rawValue }.map(\.title)
        if toolTitles.isEmpty {
            return "OnlyMacs will install its main command in ~/.local/bin/onlymacs."
        }
        return "OnlyMacs will install its main command and set up \(toolTitles.joined(separator: " + "))."
    }

    var setupLauncherOptions: [SetupLauncherOption] {
        [
            SetupLauncherOption(
                target: .codex,
                title: "Codex",
                detail: toolStatuses.contains(where: { $0.name == "Codex" && $0.statusTitle != "Missing" })
                    ? "OnlyMacs installs the Codex-compatible skill at `~/.agents/skills/onlymacs/SKILL.md` and keeps the `onlymacs-shell` launcher ready too. Other IDEs and agent runtimes that read `.agents/skills` can reuse it."
                    : "Safe to install now. If Codex or another compatible IDE is added later, the skill at `~/.agents/skills/onlymacs/SKILL.md` is already waiting for it.",
                locationDetail: "~/.agents/skills/onlymacs/SKILL.md\n~/.local/bin/onlymacs-shell\n~/.local/bin/onlymacs",
                available: true
            ),
            SetupLauncherOption(
                target: .claude,
                title: "Claude Code",
                detail: toolStatuses.contains(where: { $0.name == "Claude Code" && $0.statusTitle != "Missing" })
                    ? "OnlyMacs installs the Claude Code skill at `~/.claude/skills/onlymacs/SKILL.md` and keeps the main command ready too."
                    : "Safe to install now. If Claude Code is added later, the skill at `~/.claude/skills/onlymacs/SKILL.md` is already waiting for it.",
                locationDetail: "~/.claude/skills/onlymacs/SKILL.md\n~/.local/bin/onlymacs",
                available: true
            ),
        ]
    }

    var shouldReopenDetectedTools: Bool {
        toolIntegrationRefreshNeedsAppRestart && toolStatuses.contains(where: \.canOpen)
    }

    var hasPendingRuntimeChanges: Bool {
        selectedMode.rawValue != snapshot.runtime.mode || selectedSwarmID != snapshot.runtime.activeSwarmID
    }

    var canCreateInvite: Bool {
        inviteTargetSwarm != nil
    }

    var inviteTargetSwarm: SwarmOption? {
        guard let activeRuntimeSwarm, activeRuntimeSwarm.allowsInviteSharing else {
            return nil
        }
        return activeRuntimeSwarm
    }

    var selectedOrActiveSwarmRequiresBoth: Bool {
        if let selectedSwarm, selectedSwarm.isPublic {
            return true
        }
        return selectedSwarmID.isEmpty && activeRuntimeSwarm?.isPublic == true
    }

    var activeRuntimeSwarm: SwarmOption? {
        activeRuntimeSwarmOption(
            swarms: snapshot.swarms,
            activeSwarmID: snapshot.runtime.activeSwarmID,
            activeSwarmName: snapshot.bridge.activeSwarmName,
            swarm: snapshot.swarm,
            memberCount: snapshot.members.count
        )
    }

    var selectedSwarm: SwarmOption? {
        snapshot.swarms.first(where: { $0.id == selectedSwarmID })
    }

    var inviteIsExpired: Bool {
        guard let latestInviteExpiresAt else { return false }
        return latestInviteExpiresAt <= Date()
    }

    var hasUsableInvite: Bool {
        let tokenReady = !latestInviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !inviteIsExpired
        guard tokenReady else { return false }
        guard let inviteProgress else { return true }
        return inviteProgress.swarmID == snapshot.runtime.activeSwarmID
    }

    var canShareInvite: Bool {
        hasUsableInvite && !inviteShareMessage.isEmpty
    }

    var founderInviteStatusLabel: String {
        if hasUsableInvite {
            return inviteExpiryDetail ?? "Invite ready"
        }
        if inviteIsExpired {
            return "Expired"
        }
        return "Missing"
    }

    var inviteLinkPayload: InviteLinkPayload? {
        guard hasUsableInvite else { return nil }
        return InviteLinkPayload(
            inviteToken: latestInviteToken,
            coordinatorURL: appliedCoordinatorSettings.mode == .hostedRemote ? appliedCoordinatorSettings.effectiveCoordinatorURL : nil
        )
    }

    var inviteLinkString: String {
        inviteLinkPayload?.appURL?.absoluteString ?? ""
    }

    var inviteExpiryDetail: String? {
        guard let latestInviteExpiresAt else { return nil }
        if latestInviteExpiresAt <= Date() {
            return "Invite expired. Create a fresh invite before sharing again."
        }
        return "Expires \(Self.inviteExpiryFormatter.localizedString(for: latestInviteExpiresAt, relativeTo: Date()))."
    }

    var inviteStatusTitle: String? {
        inviteProgress?.stage.title
    }

    var inviteStatusDetail: String? {
        inviteProgress?.detail
    }

    var inviteShareMessage: String {
        let token = latestInviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasUsableInvite, !token.isEmpty else { return "" }
        let swarmName = inviteProgress?.swarmName ?? inviteTargetSwarm?.name ?? snapshot.bridge.activeSwarmName ?? "my OnlyMacs swarm"
        let inviteLink = inviteLinkString
        let expiryHint = inviteExpiryDetail ?? "Create a fresh invite if this one ever stops opening."
        let coordinatorHint = appliedCoordinatorSettings.mode == .hostedRemote
            ? "OnlyMacs will switch to the shared coordinator automatically when this link opens."
            : "This invite is local-only right now. Switch to Hosted Remote before sending it to a friend on another Mac."
        return """
        Join the \(swarmName) swarm in OnlyMacs.

        1. Install and open OnlyMacs.
        2. Choose Use Remote Macs, Share This Mac, or Both.
        3. Open this invite link or paste the backup token if the link is not clickable.
        4. \(coordinatorHint)
        5. \(expiryHint)

        Invite link: \(inviteLink)
        Backup token: \(token)
        """
    }

    var inviteFriendTestMessage: String {
        let token = latestInviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasUsableInvite, !token.isEmpty else { return "" }
        let swarmName = inviteProgress?.swarmName ?? inviteTargetSwarm?.name ?? snapshot.bridge.activeSwarmName ?? "my OnlyMacs swarm"
        let expiryHint = inviteExpiryDetail ?? "Create a fresh invite if this one ever stops opening."
        let hostedHint = appliedCoordinatorSettings.mode == .hostedRemote
            ? "The app should switch to the shared coordinator automatically when the invite opens."
            : "This invite stays local-only until Hosted Remote is enabled here, so switch that on before sending it to another Mac."
        return """
        OnlyMacs friend test for \(swarmName)

        1. Download and open OnlyMacs.
        2. Choose Use Remote Macs if you want borrowed compute only, or Both if you also want to share your Mac back.
        3. Open this invite link. If the link does not open the app, paste the backup token in OnlyMacs and join the swarm manually.
        4. \(hostedHint)
        5. \(expiryHint)
        6. Wait for OnlyMacs to show Ready, then use the app's starter command or run `onlymacs "do a code review on my project"` if the launcher is installed.
        7. If anything fails, click Export Support Bundle in OnlyMacs and send me the JSON first.

        Invite link: \(inviteLinkString)
        Backup token: \(token)
        """
    }

    var founderTestPacketMessage: String {
        let swarmName = selectedSwarm?.name ?? snapshot.bridge.activeSwarmName ?? "No active swarm yet"
        let statusLines = friendTestStatus.items.map { item in
            "\(item.status.summaryPrefix) \(item.title): \(item.detail)"
        }.joined(separator: "\n")
        let inviteSection: String
        if hasUsableInvite {
            let token = latestInviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
            inviteSection = """
            Invite link: \(inviteLinkString)
            Backup token: \(token)
            \(inviteExpiryDetail ?? "Create a fresh invite if this one stops opening.")
            """
        } else {
            inviteSection = "Invite: not ready yet. Create a fresh invite before sending the DMG."
        }

        return """
        OnlyMacs founder handoff

        Build: \(buildDisplayLabel)
        Menu bar state: \(menuBarStateTitle)
        Coordinator: \(effectiveCoordinatorTarget)
        Active swarm: \(swarmName)
        Preferred starter route: \(preferredRequestRoute.title)
        This Mac eligibility: \(localEligibilitySummary.title) — \(localEligibilitySummary.detail)
        Latest /onlymacs activity: \(latestOnlyMacsActivitySummary ?? "No launcher activity recorded yet.")

        Two-Mac status
        \(statusLines)

        \(inviteSection)

        Trust posture
        - Private swarm joins use opaque invite tokens with expiry instead of guessable IDs.
        - Trusted-circle swarms should use the secret invite plus rotate/revoke flow.
        - Broader-share swarms should move to approval-required membership before they widen trust further.

        Founder send steps
        1. Verify the DMG/checksum from the repo before sending it.
        2. Send the DMG and the friend-test message.
        3. If the friend gets stuck, ask for the Two-Mac status summary first.
        4. If anything still looks wrong, ask for the redacted support bundle JSON next.
        """
    }

    var setupAssistant: SetupAssistantState {
        SetupAssistantState(
            mode: selectedMode,
            snapshot: snapshot,
            localShare: localShare,
            runtimeState: runtimeState,
            selfTestState: selfTestState,
            starterModelDetail: starterModelSetupSummary,
            starterModelStatus: starterModelSetupStepStatus
        )
    }

    var starterModelSetupStepStatus: SetupAssistantStepStatus {
        if isInstallingStarterModels {
            return .inProgress
        }
        if !localShare.discoveredModels.isEmpty {
            return .done
        }
        if selectedInstallerModelIDs.isEmpty {
            return .blocked
        }
        return .pending
    }

    var recoveryCard: RecoveryCardContent? {
        if case let .failed(message) = selfTestState {
            return RecoveryCardContent(
                title: "OnlyMacs needs attention",
                detail: message,
                tone: .error,
                actions: [
                    RecoveryActionItem(kind: .fixEverything, label: "Try Automatic Fix"),
                    RecoveryActionItem(kind: .exportSupportBundle, label: "Export Support Info"),
                ]
            )
        }

        if let recoveryMessage = coordinatorRecoveryMessage {
            return RecoveryCardContent(
                title: "Hosted coordinator needs help",
                detail: recoveryMessage,
                tone: .warning,
                actions: [
                    RecoveryActionItem(kind: .restartRuntime, label: "Retry Hosted"),
                    RecoveryActionItem(kind: .openLogs, label: "Open Logs"),
                ]
            )
        }

        if let error = lastError, !error.isEmpty {
            let actions: [RecoveryActionItem]
            if coordinatorConnectionMode == .hostedRemote {
                actions = [
                    RecoveryActionItem(kind: .restartRuntime, label: "Restart Runtime"),
                    RecoveryActionItem(kind: .exportSupportBundle, label: "Export Support Info"),
                ]
            } else {
                actions = [
                    RecoveryActionItem(kind: .restartRuntime, label: "Restart Runtime"),
                    RecoveryActionItem(kind: .openLogs, label: "Open Logs"),
                    RecoveryActionItem(kind: .exportSupportBundle, label: "Export Support Info"),
                ]
            }
            return RecoveryCardContent(
                title: "OnlyMacs needs attention",
                detail: error,
                tone: .error,
                actions: actions
            )
        }

        if let inviteRecoveryMessage {
            return RecoveryCardContent(
                title: inviteIsExpired ? "This invite expired" : "This invite is not remote-ready yet",
                detail: inviteRecoveryMessage,
                tone: .warning,
                actions: inviteIsExpired
                    ? [RecoveryActionItem(kind: .createInvite, label: "Create Invite")]
                    : []
            )
        }

        if let shareHealthRecoveryMessage {
            return RecoveryCardContent(
                title: "This Mac's share health needs attention",
                detail: shareHealthRecoveryMessage,
                tone: .warning,
                actions: [
                    RecoveryActionItem(kind: .openLogs, label: "Open Logs"),
                    RecoveryActionItem(kind: .exportSupportBundle, label: "Export Support Info"),
                    RecoveryActionItem(kind: .restartRuntime, label: "Restart Runtime"),
                ]
            )
        }

        if let premiumSession = snapshot.swarm.recentSessions.first(where: { $0.selectionReason == "scarce_premium_fallback" }) {
            let detailParts = [
                sessionPremiumNudgeMessage(premiumSession),
                sessionQueueDetail(premiumSession),
                premiumSession.selectionExplanation,
            ]
            return RecoveryCardContent(
                title: premiumSession.status == "queued" ? "Waiting on a rare premium slot" : "OnlyMacs protected a rare premium slot",
                detail: Self.joinRecoveryDetails(detailParts) ?? "OnlyMacs kept this swarm moving on the strongest safe fallback while premium capacity was scarce.",
                tone: .warning,
                actions: [
                    RecoveryActionItem(kind: .refreshBridge, label: "Refresh"),
                    RecoveryActionItem(kind: .copyStarterCommand, label: "Copy Starter"),
                ]
            )
        }

        if let queuedSession = snapshot.swarm.recentSessions.first(where: { $0.status == "queued" }) {
            let detailParts = [
                queuedSession.selectionExplanation,
                sessionQueueDetail(queuedSession),
                queuedSession.routeSummary,
            ]
            return RecoveryCardContent(
                title: "A swarm is waiting in line",
                detail: Self.joinRecoveryDetails(detailParts) ?? "OnlyMacs queued this swarm until capacity opens up.",
                tone: .info,
                actions: [
                    RecoveryActionItem(kind: .refreshBridge, label: "Refresh"),
                    RecoveryActionItem(kind: .copyStarterCommand, label: "Copy Starter"),
                ]
            )
        }

        if selectedMode.allowsShare, !selectedSwarmID.isEmpty, localShare.discoveredModels.isEmpty {
            return RecoveryCardContent(
                title: "This Mac can’t share yet",
                detail: "OnlyMacs is in the swarm, but this Mac does not have a local model installed yet. Requesting still works; sharing turns on after at least one local model is available.",
                tone: .info,
                actions: []
            )
        }

        return nil
    }

    var starterCommand: String {
        let base = launcherStatus.commandOnPath ? "onlymacs" : launcherStatus.entrypointURL.path
        return preferredRequestRoute.starterReviewCommand(base: base)
    }

    var starterCommands: [StarterCommandSuggestion] {
        let base = launcherStatus.commandOnPath ? "onlymacs" : launcherStatus.entrypointURL.path
        return [
            StarterCommandSuggestion(title: "Check", command: "\(base) check"),
            StarterCommandSuggestion(title: "\(preferredRequestRoute.title) Review", command: preferredRequestRoute.starterReviewCommand(base: base)),
            StarterCommandSuggestion(title: "Summary", command: "\(base) \"summarize this repo\""),
            StarterCommandSuggestion(title: "Latest Status", command: "\(base) status latest"),
            StarterCommandSuggestion(title: "Watch Current", command: "\(base) watch current"),
        ]
    }

    var howToUseRecipeItems: [HowToUseRecipeItem] {
        deriveHowToUseRecipeItems()
    }

    var howToUseStrategyItems: [HowToUseStrategyItem] {
        deriveHowToUseStrategyItems()
    }

    var howToUseParameterItems: [HowToUseParameterItem] {
        deriveHowToUseParameterItems()
    }

    var launcherStatusLabel: String {
        if launcherStatus.installed {
            if launcherStatus.commandOnPath || launcherStatus.profileConfigured {
                return "Installed"
            }
            return "Installed (PATH setup needed)"
        }
        return "Not Installed"
    }

    var launcherPathHelpText: String? {
        guard launcherStatus.installed, !launcherStatus.commandOnPath else {
            return nil
        }
        if launcherStatus.profileConfigured {
            return "OnlyMacs is installed and your shell profile already includes `\(launcherStatus.shimDirectoryURL.path)`. The menu-bar app may still report a limited macOS launch PATH; use the full launcher path below if one existing terminal has not refreshed yet."
        }
        return "OnlyMacs installs its main command at `\(launcherStatus.shimDirectoryURL.path)`. If Codex or Claude Code still do not see it, run Install Launchers again or reopen those apps once after your shell refreshes."
    }

    var preferredRequestRouteSummary: String {
        if preferredRequestRoute == .automatic {
            if localEligibilitySummary.isEligible {
                return "Automatic is currently biasing toward This Mac because this Mac is published, healthy, and has a free local slot."
            }
            return "Automatic is not biasing toward This Mac right now because \(localEligibilitySummary.shortLabel.lowercased()). \(localEligibilitySummary.detail)"
        }
        return preferredRequestRoute.detail
    }

    var localEligibilitySummary: LocalEligibilitySummary {
        let runtimeModeAllowsShare = AppMode(rawValue: snapshot.runtime.mode)?.allowsShare ?? selectedMode.allowsShare
        return deriveLocalEligibilitySummary(
            modeAllowsShare: runtimeModeAllowsShare,
            activeSwarmID: snapshot.runtime.activeSwarmID,
            runtimeStatus: runtimeState.status,
            bridgeStatus: snapshot.bridge.status,
            localSharePublished: localShare.published,
            localShareSlotsFree: localShare.slots.free,
            localShareSlotsTotal: localShare.slots.total,
            discoveredModelCount: localShare.discoveredModels.count,
            failedSessions: localShare.failedSessions
        )
    }

    var commandGuidanceIntro: String {
        if snapshot.swarm.queueSummary.premiumContentionCount > 0 {
            return "Rare premium capacity is busy right now. Keep lightweight asks on the normal path, use `offload-max` when you want to save tokens, and save `precise` for work that truly needs the same strong model."
        }
        if (activeRuntimeSwarm?.memberCount ?? 0) > 1 && snapshot.swarm.slotsTotal > 0 {
            return "This swarm can route real work off your Mac. Keep sensitive asks local-first, lean on offload-max when you want savings, and use precise only when silent degradation would be worse than waiting."
        }
        return "OnlyMacs works best when the route matches the job: local-first for sensitive work, offload-max for savings, precise for continuity, and the plain natural-language path for lightweight asks."
    }

    var commandGuidanceSuggestions: [CommandGuidanceSuggestion] {
        let base = launcherStatus.commandOnPath ? "onlymacs" : launcherStatus.entrypointURL.path
        return [
            CommandGuidanceSuggestion(
                title: "Sensitive work stays local-first",
                detail: "Private repos, auth flows, and anything with real secrets should stay on this Mac or trusted capacity first.",
                command: "\(base) go local-first \"review this private auth flow for secret leakage\"",
                tone: .safe
            ),
            CommandGuidanceSuggestion(
                title: "Save tokens before you go wide",
                detail: "Use offload-max when you want OnlyMacs to squeeze the most from your Macs and trusted swarm capacity before expensive fallbacks.",
                command: "\(base) go offload-max \"debug this failing test without burning paid tokens\"",
                tone: .savings
            ),
            CommandGuidanceSuggestion(
                title: "Use rare premium on purpose",
                detail: "Choose precise for risky migrations or final review passes where the same stronger model matters more than raw speed.",
                command: "\(base) go precise \"finish this risky migration plan without degrading the model\"",
                tone: .premium
            ),
            CommandGuidanceSuggestion(
                title: "Keep lightweight asks cheap",
                detail: "For summaries, triage, and repo orientation, start with the plain natural-language path instead of burning a scarce flagship slot.",
                command: "\(base) \"summarize this repo before we open a wider swarm\"",
                tone: .caution
            ),
        ]
    }

    var inviteRecoveryMessage: String? {
        guard !latestInviteToken.isEmpty else { return nil }
        if inviteIsExpired {
            return "This invite expired. Create a fresh invite before sending it or copying friend-test instructions again."
        }
        guard appliedCoordinatorSettings.mode != .hostedRemote else { return nil }
        return "This invite is ready for this Mac, but friends on other Macs need Hosted Remote selected so they land on the same coordinator."
    }

    func localShareFailureNote(compact: Bool) -> String? {
        guard localShare.failedSessions > 0 else { return nil }
        if compact {
            if localShare.failedSessions >= 4 {
                return "Recent relay failures: \(localShare.failedSessions). OnlyMacs may temporarily sideline this Mac from new swarm work until share health stabilizes."
            }
            return "Recent relay failures: \(localShare.failedSessions). This Mac may be temporarily down-ranked until share health stabilizes."
        }
        return "Recent relay failures: \(localShare.failedSessions). Healthier Macs may be preferred until this Mac stabilizes."
    }

    var shareHealthRecoveryMessage: String? {
        guard selectedMode.allowsShare, localShare.published, localShare.failedSessions >= 3 else { return nil }
        if localShare.failedSessions >= 4 {
            return "This Mac is published, but repeated relay failures (\(localShare.failedSessions)) mean OnlyMacs may temporarily sideline it from new swarm work until share health stabilizes. Open logs or export a support bundle before re-publishing or sending another friend test."
        }
        return "This Mac is published, but recent relay failures (\(localShare.failedSessions)) mean healthier Macs may be preferred until share health stabilizes. Open logs or export a support bundle before re-publishing or sending another friend test."
    }

    var coordinatorRecoveryMessage: String? {
        guard coordinatorConnectionMode == .hostedRemote else { return nil }
        if runtimeState.status == "ready", snapshot.bridge.status == "ready" {
            return nil
        }
        return "Hosted Remote is selected, but OnlyMacs is not healthy yet. Retry the hosted connection, open the runtime logs, or export support info if the problem continues."
    }

    var friendTestStatus: FriendTestStatusSummary {
        var items: [FriendTestStatusItem] = []
        var actions: [RecoveryActionItem] = []

        let runtimeReady = runtimeState.status == "ready" && snapshot.bridge.status == "ready"
        items.append(
            FriendTestStatusItem(
                title: "Local runtime",
                detail: runtimeReady ? "OnlyMacs helpers are healthy on this Mac." : runtimeState.detail,
                status: runtimeReady ? .ready : .blocked
            )
        )
        if !runtimeReady {
            actions.append(RecoveryActionItem(kind: .restartRuntime, label: "Restart Runtime"))
        }

        let ollamaReady = runtimeState.ollamaReady
        items.append(
            FriendTestStatusItem(
                title: "Local model runtime",
                detail: runtimeState.ollamaDetail,
                status: ollamaReady ? .ready : .blocked
            )
        )
        if !ollamaReady {
            switch runtimeState.ollamaStatus {
            case .missing:
                actions.append(RecoveryActionItem(kind: .installOllama, label: "Install Ollama"))
            case .installedButUnavailable:
                actions.append(RecoveryActionItem(kind: .launchOllama, label: "Launch Ollama"))
            case .ready, .external:
                break
            }
        }

        let hostedReady = appliedCoordinatorSettings.mode == .hostedRemote
        items.append(
            FriendTestStatusItem(
                title: "Shared coordinator",
                detail: hostedReady
                    ? "Invite links can carry your friend onto the same remote coordinator."
                    : "Switch to Hosted Remote before sending an invite to another Mac.",
                status: hostedReady ? .ready : .blocked
            )
        )
        if !hostedReady {
            actions.append(RecoveryActionItem(kind: .useHostedRemote, label: "Use Hosted Remote"))
        }

        let hasSwarm = !selectedSwarmID.isEmpty
        items.append(
            FriendTestStatusItem(
                title: "Swarm selected",
                detail: hasSwarm
                    ? (snapshot.bridge.activeSwarmName ?? "A swarm is active for this Mac.")
                    : "Choose the public swarm or create/join a private swarm first so OnlyMacs knows where to route the test.",
                status: hasSwarm ? .ready : .blocked
            )
        )

        let hasInvite = hasUsableInvite
        items.append(
            FriendTestStatusItem(
                title: "Friend invite",
                detail: hasInvite
                    ? "The current invite can be copied with the backup token and test instructions."
                    : (inviteIsExpired
                        ? "The last invite expired. Create a fresh invite before you send the DMG or copy the friend-test steps."
                        : "Create an invite before you send the DMG to your friend."),
                status: hasInvite ? .ready : .needsAction
            )
        )
        if !hasInvite, hasSwarm {
            actions.append(RecoveryActionItem(kind: .createInvite, label: "Create Invite"))
        }

        items.append(
            FriendTestStatusItem(
                title: "OnlyMacs command",
                detail: launcherStatus.installed
                    ? launcherStatus.detail
                    : "Install the branded `onlymacs` launchers so Codex or Claude Code can start the first test without repo paths.",
                status: launcherStatus.installed
                    ? (launcherStatus.commandOnPath ? .ready : .needsAction)
                    : .needsAction
            )
        )
        if !launcherStatus.installed {
            actions.append(RecoveryActionItem(kind: .installLaunchers, label: "Install Launchers"))
        } else if launcherStatus.needsPathFix {
            actions.append(RecoveryActionItem(kind: .applyPathFix, label: "Repair PATH"))
        } else if shouldReopenDetectedTools {
            actions.append(RecoveryActionItem(kind: .reopenDetectedTools, label: "Reopen Tools"))
        }

        if selectedMode.allowsUse {
            let requestDetail: String
            let requestStatus: FriendTestStatusLevel
            if selfTestState.isSuccessful {
                requestDetail = selfTestState.detail
                requestStatus = .ready
            } else if snapshot.swarm.slotsTotal > 0 {
                requestDetail = "The active swarm has visible shared slot capacity. Run Test to confirm a real routed request."
                requestStatus = .needsAction
            } else {
                requestDetail = "No live shared slot capacity is visible yet. Your friend may still need to join, publish, or finish model setup."
                requestStatus = .needsAction
            }
            items.append(
                FriendTestStatusItem(
                    title: "Request path",
                    detail: requestDetail,
                    status: requestStatus
                )
            )
            if !selfTestState.isSuccessful {
                actions.append(RecoveryActionItem(kind: .runSelfTest, label: "Run Test"))
            }
        }

        if selectedMode.allowsShare {
            let shareStatus: FriendTestStatusLevel
            let shareDetail: String
            if localShare.published, localShare.failedSessions >= 3 {
                shareStatus = .needsAction
                shareDetail = "This Mac is helping \(localShare.activeSwarmName ?? "the active swarm"), but recent relay failures (\(localShare.failedSessions)) mean healthier Macs may be preferred until local sharing stabilizes."
            } else if localShare.published {
                shareStatus = .ready
                if localShare.failedSessions > 0 {
                    shareDetail = "This Mac is helping \(localShare.activeSwarmName ?? "the active swarm"). OnlyMacs also saw \(localShare.failedSessions) recent relay failure(s), so keep an eye on local sharing health."
                } else {
                    shareDetail = "This Mac is already helping \(localShare.activeSwarmName ?? "the active swarm")."
                }
            } else if localShare.discoveredModels.isEmpty {
                shareStatus = .blocked
                shareDetail = "No local models are available yet, so this Mac cannot share back until model setup finishes."
            } else {
                shareStatus = .needsAction
                shareDetail = "This Mac can share back as soon as you publish it into the active swarm."
            }
            items.append(
                FriendTestStatusItem(
                    title: "Share back path",
                    detail: shareDetail,
                    status: shareStatus
                )
            )
        }

        let blockedCount = items.filter { $0.status == .blocked }.count
        let needsActionCount = items.filter { $0.status == .needsAction }.count
        let title: String
        let detail: String
        if blockedCount > 0 {
            title = "Two-Mac test is not ready yet"
            detail = "Fix the blocked items first. Once those are green, the friend test should stop feeling guessy."
        } else if needsActionCount > 0 {
            title = "Two-Mac test is almost ready"
            detail = "OnlyMacs is close. Finish the remaining action items, then send the invite and run the first swarm."
        } else {
            title = "Two-Mac test is ready"
            detail = "You can send the DMG, copy the friend test instructions, and expect the first routed request to work without manual triage."
        }

        return FriendTestStatusSummary(
            title: title,
            detail: detail,
            items: items,
            actions: Array(actions.reduce(into: [RecoveryActionItem]()) { result, action in
                if !result.contains(where: { $0.kind == action.kind }) {
                    result.append(action)
                }
            }.prefix(3))
        )
    }

    static func suggestedDefaultMemberName() -> String {
        let candidates = [
            Host.current().localizedName,
            NSFullUserName(),
            NSUserName(),
        ]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "This Mac"
    }

    var defaultMemberName: String {
        Self.suggestedDefaultMemberName()
    }

    private static let supportURL = URL(string: "https://github.com")!
    static let coordinatorSettingsKey = "OnlyMacs.CoordinatorConnectionSettings"
    static let preferredRequestRouteKey = "OnlyMacs.PreferredRequestRoute"
    static let onlyMacsNotificationsKey = "OnlyMacs.OnlyMacsNotificationsEnabled"
    static let starterModelSetupCompletedKey = "OnlyMacs.StarterModelSetupCompleted"
    static let setupLaunchAtLoginKey = "OnlyMacs.SetupLaunchAtLoginEnabled"
    static let cachedMemberNameKey = "OnlyMacs.CachedMemberName"
    static let cachedInviteKey = "OnlyMacs.CachedInvite"
    static let appliedInstallerSelectionSignatureKey = "OnlyMacs.AppliedInstallerSelectionSignature"
    static let hasPresentedMenuBarRevealKey = "OnlyMacs.HasPresentedMenuBarReveal"

    private static func humanQueueReason(_ reason: String) -> String {
        switch reason {
        case "premium_cooldown":
            return "Premium cooldown"
        case "premium_budget":
            return "Premium-budget hold"
        case "requester_budget":
            return "Requester queue budget"
        case "member_cap":
            return "Swarm member budget"
        case "premium_contention":
            return "Scarce premium capacity"
        case "swarm_capacity":
            return "Swarm saturation"
        case "trust_scope":
            return "Trust-scope wait"
        case "workspace_cap":
            return "Workspace width limit"
        case "thread_cap":
            return "Thread width limit"
        case "global_cap":
            return "Global safety limit"
        case "manual_pause":
            return "Paused"
        case "cancelled":
            return "Cancelled"
        case "model_unavailable":
            return "Model unavailable"
        case "requested_width":
            return "Requested width narrowed"
        case "stale_queue":
            return "Stale queued work"
        default:
            return ""
        }
    }

    private static func shortETALabel(_ seconds: Int) -> String {
        if seconds <= 0 {
            return "soon"
        }
        if seconds < 60 {
            return "< 1 min"
        }
        if seconds < 3600 {
            return "\(Int(ceil(Double(seconds) / 60.0))) min"
        }
        return "\(Int(ceil(Double(seconds) / 3600.0))) hr"
    }

    private static func joinRecoveryDetails(_ parts: [String?]) -> String? {
        let filtered = parts.compactMap { part in
            let trimmed = part?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !filtered.isEmpty else { return nil }
        return filtered.joined(separator: " ")
    }

    private func applySparkleUpdateState(_ state: OnlyMacsSparkleState) {
        availableUpdate = state.availableUpdate
        lastUpdateCheckAt = state.lastCheckedAt
        isCheckingForUpdates = state.isChecking
        isDownloadingUpdate = state.isDownloading
        isInstallingUpdate = state.isInstalling
        isUpdateReadyToInstallOnQuit = state.isReadyToInstallOnQuit
        updateCheckError = state.errorMessage
    }

    private static func loadOnlyMacsNotificationsEnabled() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: onlyMacsNotificationsKey) == nil {
            return true
        }
        return defaults.bool(forKey: onlyMacsNotificationsKey)
    }

    private static func loadStarterModelSetupCompleted() -> Bool {
        UserDefaults.standard.bool(forKey: starterModelSetupCompletedKey)
    }

    private static func loadSetupLaunchAtLoginEnabled() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: setupLaunchAtLoginKey) == nil {
            return true
        }
        return defaults.bool(forKey: setupLaunchAtLoginKey)
    }

    static func loadCachedMemberName() -> String? {
        let trimmed = UserDefaults.standard
            .string(forKey: cachedMemberNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func persistCachedMemberName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userDefaults.set(trimmed, forKey: Self.cachedMemberNameKey)
    }

    static func loadCachedInvite() -> CachedInviteRecord? {
        guard let data = UserDefaults.standard.data(forKey: cachedInviteKey) else { return nil }
        return try? JSONDecoder().decode(CachedInviteRecord.self, from: data)
    }

    func persistCachedInvite(token: String, swarmID: String, swarmName: String?, expiresAt: Date?) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSwarmID = swarmID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty, !trimmedSwarmID.isEmpty else { return }
        let record = CachedInviteRecord(
            token: trimmedToken,
            swarmID: trimmedSwarmID,
            swarmName: swarmName?.trimmingCharacters(in: .whitespacesAndNewlines),
            expiresAt: expiresAt
        )
        if let data = try? JSONEncoder().encode(record) {
            userDefaults.set(data, forKey: Self.cachedInviteKey)
        }
    }

    func clearCachedInvite() {
        userDefaults.removeObject(forKey: Self.cachedInviteKey)
    }

    private static func loadHasPresentedMenuBarReveal() -> Bool {
        UserDefaults.standard.bool(forKey: hasPresentedMenuBarRevealKey)
    }

    func startRefreshing() {
        guard refreshTask == nil else { return }

        refreshTask = Task {
            await ensureRuntimeRunning()
            await refresh()

            while !Task.isCancelled {
                let shouldRefreshRuntime = snapshot.bridge.status != "ready"
                    || (runtimeState.ollamaStatus != .ready && runtimeState.ollamaStatus != .external)
                if shouldRefreshRuntime {
                    await ensureRuntimeRunning()
                }
                await refresh()
                try? await Task.sleep(nanoseconds: Self.bridgeRefreshIntervalNanoseconds)
            }
        }

        guard fileAccessPollTask == nil else { return }
        if commandActivityPollTask == nil {
            commandActivityPollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.refreshLatestOnlyMacsActivity()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }

        fileAccessPollTask = Task {
            while !Task.isCancelled {
                await reconcilePendingFileAccessRequest(forceFront: false)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        guard automationPollTask == nil else { return }
        automationPollTask = Task {
            while !Task.isCancelled {
                await reconcilePendingAutomationCommand()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        sparkleUpdater.start()
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    func checkForUpdatesNow() {
        sparkleUpdater.checkForUpdates()
    }

    func restartRuntimeNow() {
        Task {
            await restartRuntime()
        }
    }

    func installOllamaNow() {
        guard let url = URL(string: "https://ollama.com/download") else { return }
        NSWorkspace.shared.open(url)
    }

    func launchOllamaNow() {
        if let appPath = runtimeState.ollamaAppPath, !appPath.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: appPath, isDirectory: true))
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await ensureRuntimeRunning()
                await refresh()
            }
            return
        }
        installOllamaNow()
    }

    func installAvailableUpdateNow() {
        sparkleUpdater.installPreparedUpdateOrCheck()
    }

    func quitOnlyMacsNow() {
        Task {
            await quitOnlyMacs()
        }
    }

    func applyCoordinatorConnectionNow() {
        Task {
            await applyCoordinatorConnection()
        }
    }

    func applyRuntimeNow() {
        Task {
            await applyRuntime()
        }
    }

    func setSelectedSwarmDraftNow(_ swarmID: String) {
        selectedSwarmID = swarmID
        hasManualSwarmSelectionDraft = swarmID != snapshot.runtime.activeSwarmID
    }

    func saveMemberNameNow() {
        Task {
            await saveMemberName()
        }
    }

    func selectControlCenterSection(_ section: ControlCenterSection) {
        hasUserNavigatedPopupSectionsThisLaunch = true
        controlCenterSection = section
    }

    func showControlCenterSection(_ section: ControlCenterSection) {
        controlCenterSection = section
    }

    func openSettingsWindowNow() {
        openOnlyMacsSettingsWindow()
    }

    func connectToSwarmNow(_ swarmID: String) {
        selectedSwarmID = swarmID
        hasManualSwarmSelectionDraft = false
        if snapshot.swarms.first(where: { $0.id == swarmID })?.isPublic == true {
            selectedMode = .both
        }
        guard snapshot.runtime.activeSwarmID != swarmID || hasPendingRuntimeChanges else { return }
        applyRuntimeNow()
    }

    func createSwarmNow() {
        Task {
            await createSwarm()
        }
    }

    func createInviteNow() {
        Task {
            await createInvite()
        }
    }

    func copyInviteMessage() {
        guard canShareInvite else {
            lastError = inviteIsExpired
                ? "The current invite expired. Create a fresh invite before sending it."
                : "Create an invite before copying it."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(inviteShareMessage, forType: .string)
        markInviteShared(stage: .sent, detail: "Invite message copied and ready to send.")
    }

    func copyInviteLink() {
        guard canShareInvite, !inviteLinkString.isEmpty else {
            lastError = inviteIsExpired
                ? "The current invite expired. Create a fresh invite before copying the link."
                : "Create an invite before copying the link."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(inviteLinkString, forType: .string)
        markInviteShared(stage: .sent, detail: "Invite link copied and ready to send.")
    }

    func copyFriendTestMessage() {
        guard canShareInvite, !inviteFriendTestMessage.isEmpty else {
            lastError = inviteIsExpired
                ? "The current invite expired. Create a fresh invite before copying the friend test."
                : "Create an invite before copying the friend test."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(inviteFriendTestMessage, forType: .string)
        markInviteShared(stage: .sent, detail: "Friend test steps copied with the invite and support-bundle fallback.")
    }

    func copyFounderPacketMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(founderTestPacketMessage, forType: .string)
    }

    func installLaunchersNow() {
        installLaunchersNow(targets: Set(LauncherInstallTarget.allCases))
    }

    func installLaunchersNow(targets: Set<LauncherInstallTarget>) {
        do {
            let affectedToolWasRunning = supportedToolIsRunning(for: targets)
            launcherStatus = try LauncherInstaller.installLaunchers(targets: targets)
            toolIntegrationRefreshNeedsAppRestart = affectedToolWasRunning
            refreshToolStatuses()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func supportedToolIsRunning(for targets: Set<LauncherInstallTarget>) -> Bool {
        if targets.contains(.codex),
           Self.bundleIdentifierIsRunning([
               "com.openai.codex",
               "com.openai.chatgpt.codex",
           ]) {
            return true
        }
        if targets.contains(.claude),
           Self.bundleIdentifierIsRunning([
               "com.anthropic.claudefordesktop",
               "com.anthropic.claude",
           ]) {
            return true
        }
        return false
    }

    private static func bundleIdentifierIsRunning(_ identifiers: [String]) -> Bool {
        identifiers.contains { identifier in
            !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
        }
    }

    func toggleSetupLauncherTarget(_ target: LauncherInstallTarget) {
        guard target != .core else { return }
        if selectedSetupLauncherTargets.contains(target) {
            selectedSetupLauncherTargets.remove(target)
        } else {
            selectedSetupLauncherTargets.insert(target)
        }
    }

    func setSetupSwarmChoiceNow(_ choice: SetupSwarmChoice) {
        hasCustomizedSetupSwarmChoice = true
        setupSwarmChoice = choice
        if choice == .publicSwarm {
            selectedMode = .both
        }
    }

    func setSetupPrivateSwarmNameNow(_ name: String) {
        hasCustomizedSetupSwarmChoice = true
        setupPrivateSwarmName = name
    }

    func setSetupInviteTokenDraftNow(_ token: String) {
        hasCustomizedSetupSwarmChoice = true
        setupInviteTokenDraft = token
    }

    func setLaunchAtLoginNow(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            launchAtLoginEnabled = enabled
            setupLaunchAtLoginEnabled = enabled
            persistSetupLaunchAtLoginEnabled(enabled)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func copyStarterCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(starterCommand, forType: .string)
    }

    func copyCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    func toggleInstallerModelSelection(_ modelID: String) {
        guard !isInstallingStarterModels, installableInstallerModelIDs.contains(modelID) else { return }
        if selectedInstallerModelIDs.contains(modelID) {
            selectedInstallerModelIDs.remove(modelID)
        } else {
            selectedInstallerModelIDs.insert(modelID)
        }
        starterModelCompletionDetail = nil
        rebuildInstallerQueue()
        persistStarterModelSetupCompleted(false)
    }

    func resetInstallerSelectionsNow() {
        guard !isInstallingStarterModels else { return }
        selectedInstallerModelIDs = defaultInstallerSelectionIDs()
        starterModelCompletionDetail = nil
        rebuildInstallerQueue()
        persistStarterModelSetupCompleted(false)
    }

    func installInstallerModelNow(_ modelID: String) {
        guard let model = libraryModel(for: modelID), model.proofRuntimeModelID != nil else { return }
        guard !modelNeedsMoreDisk(model) else { return }
        guard !modelIsInstalled(model) else { return }

        if isInstallingStarterModels {
            selectedInstallerModelIDs.insert(modelID)
        } else {
            selectedInstallerModelIDs = [modelID]
        }
        starterModelCompletionDetail = nil
        persistStarterModelSetupCompleted(false)

        if let existing = modelDownloadQueue.item(for: modelID) {
            if existing.phase == .failed {
                try? modelDownloadQueue.retry(modelID)
            }
        } else if isInstallingStarterModels {
            try? modelDownloadQueue.enqueue(modelID)
        } else {
            modelDownloadQueue = ModelDownloadQueue(modelIDs: [modelID])
            installerQueueDetails = [:]
        }

        setInstallerQueueDetail(modelID, "Queued for download.")
        starterModelStatusDetail = "OnlyMacs queued \(Self.presentableModelName(model)) for background install."
        startModelInstallTaskIfNeeded()
    }

    func installSelectedStarterModelsNow() {
        let itemsToInstall = orderedSelectedInstallerItems(needingInstallOnly: true)
        guard !itemsToInstall.isEmpty else {
            starterModelStatusDetail = "The models you picked are already on this Mac."
            starterModelCompletionDetail = "Your selected models are ready. Open the OnlyMacs menu bar icon next and this Mac will help the active swarm automatically while it stays connected."
            persistStarterModelSetupCompleted(true)
            return
        }

        starterModelCompletionDetail = nil
        starterModelStatusDetail = "OnlyMacs is getting your selected models ready."
        modelDownloadQueue = ModelDownloadQueue(modelIDs: itemsToInstall.map(\.id))
        installerQueueDetails = [:]
        persistStarterModelSetupCompleted(false)
        startModelInstallTaskIfNeeded()
    }

    private func startModelInstallTaskIfNeeded() {
        guard modelInstallTask == nil else { return }
        modelInstallTask = Task {
            await installSelectedStarterModels()
            await MainActor.run {
                self.modelInstallTask = nil
            }
        }
    }

    func copyDiagnosticSummaryNow() {
        let summary = SupportBundleWriter.diagnosticSummary(makeSupportBundleInput(bridgeStatusJSON: nil, localShareJSON: nil, swarmSessionsJSON: nil))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    func copyPathFixNow() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(launcherStatus.pathFixSnippet, forType: .string)
    }

    func applyPathFixNow() {
        do {
            launcherStatus = try LauncherInstaller.applyPathFix()
            lastError = nil
            refreshToolStatuses()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reopenDetectedToolsNow() {
        let reopened = toolStatuses.reduce(into: 0) { count, tool in
            if tool.performAction() {
                count += 1
            }
        }
        if reopened == 0 {
            lastError = "OnlyMacs could not find a supported app to reopen right now."
        } else {
            lastError = nil
        }
    }

    func setPreferredRequestRoute(_ route: PreferredRequestRoute) {
        preferredRequestRoute = route
        userDefaults.set(route.rawValue, forKey: Self.preferredRequestRouteKey)
    }

    func performRecoveryAction(_ action: RecoveryActionKind) {
        switch action {
        case .refreshBridge:
            refreshNow()
        case .makeReady:
            makeReadyNow()
        case .fixEverything:
            fixEverythingNow()
        case .restartRuntime:
            restartRuntimeNow()
        case .installOllama:
            installOllamaNow()
        case .launchOllama:
            launchOllamaNow()
        case .openLogs:
            openLogsNow()
        case .exportSupportBundle:
            exportSupportBundleNow()
        case .useHostedRemote:
            switchToHostedRemoteNow()
        case .createInvite:
            createInviteNow()
        case .installLaunchers:
            installLaunchersNow()
        case .applyPathFix:
            applyPathFixNow()
        case .reopenDetectedTools:
            reopenDetectedToolsNow()
        case .copyPathFix:
            copyPathFixNow()
        case .copyFriendTest:
            copyFriendTestMessage()
        case .copyFounderPacket:
            copyFounderPacketMessage()
        case .copyStarterCommand:
            copyStarterCommand()
        case .runSelfTest:
            runSelfTestNow()
        }
    }

    func exportSupportBundleNow() {
        Task {
            await exportSupportBundle()
        }
    }

    func openLogsNow() {
        NSWorkspace.shared.open(LocalRuntimeSupervisor.logsDirectoryURL)
    }

    func switchToHostedRemoteNow() {
        coordinatorConnectionMode = .hostedRemote
        if coordinatorURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let defaultCoordinatorURL = buildInfo.normalizedDefaultCoordinatorURL {
            coordinatorURLDraft = defaultCoordinatorURL
        }
        applyCoordinatorConnectionNow()
    }

    func dismissClipboardInvite() {
        dismissedClipboardInviteToken = clipboardInviteToken
        clipboardInviteToken = nil
    }

    func joinClipboardInviteNow() {
        guard let clipboardInviteToken else { return }
        joinInviteToken = clipboardInviteToken
        self.clipboardInviteToken = nil
        Task {
            await joinSwarm()
        }
    }

    func joinSwarmNow() {
        Task {
            await joinSwarm()
        }
    }

    func completeGuidedSetupNow() {
        guard !isCompletingGuidedSetup else { return }
        isCompletingGuidedSetup = true
        Task {
            await completeGuidedSetup()
            await MainActor.run {
                self.isCompletingGuidedSetup = false
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        if handleFileAccessURL(url) {
            return
        }

        guard let payload = InviteLinkPayload.parse(url.absoluteString) else {
            lastError = "OnlyMacs could not read an invite token from that link."
            return
        }

        joinInviteToken = payload.inviteToken
        dismissedClipboardInviteToken = nil
        clipboardInviteToken = nil
        lastError = nil

        Task {
            if let coordinatorURL = payload.coordinatorURL {
                let incomingSettings = CoordinatorConnectionSettings(mode: .hostedRemote, remoteCoordinatorURL: coordinatorURL)
                persistCoordinatorSettings(incomingSettings)
                appliedCoordinatorSettings = incomingSettings
                coordinatorConnectionMode = incomingSettings.mode
                coordinatorURLDraft = incomingSettings.remoteCoordinatorURL
                await restartRuntime()
            } else {
                await ensureRuntimeRunning()
            }
            guard runtimeState.status == "ready" else { return }
            await joinSwarm()
        }
    }

    private func handleFileAccessURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        let route = components.host ?? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard route == "file-access" else {
            return false
        }
        guard let requestID = components.queryItems?.first(where: { $0.name == "request_id" })?.value,
              !requestID.isEmpty else {
            lastError = "OnlyMacs could not find the file approval request."
            return true
        }

        do {
            let request = try OnlyMacsFileAccessStore.loadRequest(id: requestID)
            surfacePendingFileAccessRequest(request)
            lastError = nil
        } catch {
            lastError = "OnlyMacs could not open that file approval request."
        }
        return true
    }

    private func reconcilePendingFileAccessRequest(forceFront: Bool) async {
        do {
            guard let request = try OnlyMacsFileAccessStore.latestPendingRequest() else { return }
            pruneFinalizedFileAccessRequests()
            guard finalizedFileAccessRequestIDs[request.id] == nil else { return }
            if let pending = pendingFileAccessApproval,
               pending.request.id == request.id {
                if forceFront {
                    pendingFileAccessPresentationCounter += 1
                    bringOnlyMacsWindowToFront(title: OnlyMacsWindowTitle.fileApproval)
                }
                return
            }
            surfacePendingFileAccessRequest(request)
            if forceFront {
                bringOnlyMacsWindowToFront(title: OnlyMacsWindowTitle.fileApproval)
            }
        } catch {
            // This runs continuously in the background to surface pending approvals.
            // Do not turn a transient read problem into a product-level red error
            // unless the user explicitly triggered a file approval action.
        }
    }

    private func reconcilePendingAutomationCommand() async {
        do {
            guard let command = try OnlyMacsAutomationStore.latestPendingCommand() else { return }
            let receipt = handleAutomationCommand(command)
            try OnlyMacsAutomationStore.saveReceipt(receipt)
        } catch {
            // Automation polling should be quiet during normal app use.
        }
    }

    private func handleAutomationCommand(_ command: OnlyMacsAutomationCommand) -> OnlyMacsAutomationReceipt {
        let defaultSection = command.controlCenterSection ?? controlCenterSection
        switch (command.surface, command.action) {
        case (.popup, .open):
            OnlyMacsAutomationWindowManager.shared.presentPopup(store: self, section: defaultSection)
            return OnlyMacsAutomationReceipt(
                id: command.id,
                handledAt: Date(),
                status: .handled,
                message: "Opened the OnlyMacs popup mirror on \(defaultSection.title)."
            )
        case (.popup, .close):
            Task { @MainActor in
                OnlyMacsAutomationWindowManager.shared.dismissPopup()
            }
            return OnlyMacsAutomationReceipt(
                id: command.id,
                handledAt: Date(),
                status: .handled,
                message: "Closed the OnlyMacs popup mirror."
            )
        case (.controlCenter, .open):
            OnlyMacsAutomationWindowManager.shared.presentControlCenter(store: self, section: defaultSection)
            return OnlyMacsAutomationReceipt(
                id: command.id,
                handledAt: Date(),
                status: .handled,
                message: "Opened the automation Control Center on \(defaultSection.title)."
            )
        case (.controlCenter, .close):
            Task { @MainActor in
                OnlyMacsAutomationWindowManager.shared.dismissControlCenter()
            }
            return OnlyMacsAutomationReceipt(
                id: command.id,
                handledAt: Date(),
                status: .handled,
                message: "Closed the automation Control Center."
            )
        case (.popup, .approve), (.popup, .reject), (.controlCenter, .approve), (.controlCenter, .reject):
            return OnlyMacsAutomationReceipt(
                id: command.id,
                handledAt: Date(),
                status: .failed,
                message: "Popup and Control Center automation only support open or close."
            )
        case (.fileApproval, .approve):
            guard pendingFileAccessApproval != nil else {
                return OnlyMacsAutomationReceipt(
                    id: command.id,
                    handledAt: Date(),
                    status: .failed,
                    message: "No trusted file approval is currently pending."
                )
            }
            approvePendingFileAccessNow()
            return OnlyMacsAutomationReceipt(
                id: command.id,
                handledAt: Date(),
                status: .handled,
                message: "Approved the trusted file selection."
            )
        case (.fileApproval, .reject):
            guard pendingFileAccessApproval != nil else {
                return OnlyMacsAutomationReceipt(
                    id: command.id,
                    handledAt: Date(),
                    status: .failed,
                    message: "No trusted file approval is currently pending."
                )
            }
            rejectPendingFileAccessNow(message: "Rejected by OnlyMacs automation.")
            return OnlyMacsAutomationReceipt(
                id: command.id,
                handledAt: Date(),
                status: .handled,
                message: "Rejected the trusted file selection."
            )
        case (.fileApproval, .open), (.fileApproval, .close):
            return OnlyMacsAutomationReceipt(
                id: command.id,
                handledAt: Date(),
                status: .failed,
                message: "File approval automation only supports approve or reject."
            )
        }
    }

    private func surfacePendingFileAccessRequest(_ request: OnlyMacsFileAccessRequest) {
        pruneFinalizedFileAccessRequests()
        guard finalizedFileAccessRequestIDs[request.id] == nil else { return }
        if pendingFileAccessApproval?.request.id == request.id {
            OnlyMacsFileApprovalWindowManager.shared.present(store: self)
            return
        }
        let suggestions = OnlyMacsFileAccessStore.suggestFiles(for: request)
        let seededPaths = Set(request.seedSelectedPaths ?? [])
        let preselected = Set(OnlyMacsFileAccessStore.preselectedPaths(for: request, suggestions: suggestions))
            .union(seededPaths)
        let preview = OnlyMacsFileExportBuilder.buildPreview(
            for: request,
            selectedPaths: Array(preselected)
        )
        pendingFileAccessApproval = PendingFileAccessApproval(
            request: request,
            suggestions: suggestions,
            selectedPaths: preselected,
            preview: preview
        )
        pendingFileAccessPresentationCounter += 1
        OnlyMacsFileApprovalWindowManager.shared.present(store: self)
        do {
            try OnlyMacsFileAccessStore.saveClaim(
                OnlyMacsFileAccessClaim(
                    id: request.id,
                    claimedAt: Date(),
                    workspaceRoot: request.workspaceRoot
                )
            )
        } catch {
            lastError = "OnlyMacs found the file request, but could not confirm it back to the launcher."
        }
    }

    func markFileApprovalWindowVisible() {
        isFileApprovalWindowVisible = true
    }

    func markFileApprovalWindowHidden() {
        isFileApprovalWindowVisible = false
        restoreOnlyMacsAgentPolicyIfPossible()
    }

    func updatePendingFileAccessSelection(path: String, isSelected: Bool) {
        guard var pending = pendingFileAccessApproval else { return }
        if isSelected {
            pending.selectedPaths.insert(path)
        } else {
            pending.selectedPaths.remove(path)
        }
        pending.preview = OnlyMacsFileExportBuilder.buildPreview(
            for: pending.request,
            selectedPaths: pending.selectedPaths.sorted()
        )
        pendingFileAccessApproval = pending
    }

    func chooseAdditionalFileAccessFilesNow() {
        guard var pending = pendingFileAccessApproval else { return }
        let chosenPaths = OnlyMacsFileAccessStore.chooseFiles(startingAt: pending.workspaceRoot)
        guard !chosenPaths.isEmpty else { return }

        let fileManager = FileManager.default
        let additions = chosenPaths.map { path -> OnlyMacsFileSuggestion in
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            let root = URL(fileURLWithPath: pending.workspaceRoot, isDirectory: true).path
            let relativePath: String
            if path.hasPrefix(root + "/") {
                relativePath = path.replacingOccurrences(of: root + "/", with: "")
            } else {
                relativePath = URL(fileURLWithPath: path).lastPathComponent
            }
            return OnlyMacsFileSuggestion(
                path: path,
                relativePath: relativePath,
                bytes: bytes,
                reason: "Manually selected for this trusted request",
                category: "Manual",
                priority: 200,
                isRecommended: false
            )
        }

        for suggestion in additions where !pending.suggestions.contains(suggestion) {
            pending.suggestions.append(suggestion)
        }
        pending.suggestions.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        pending.selectedPaths.formUnion(chosenPaths)
        pending.preview = OnlyMacsFileExportBuilder.buildPreview(
            for: pending.request,
            selectedPaths: pending.selectedPaths.sorted()
        )
        pendingFileAccessApproval = pending
    }

    func rejectPendingFileAccessNow(message: String = "You cancelled the trusted file share request.") {
        guard let pending = pendingFileAccessApproval else { return }
        pendingFileAccessApproval = nil
        pendingFileAccessPresentationCounter = 0
        rememberFinalizedFileAccessRequest(id: pending.request.id)
        OnlyMacsFileApprovalWindowManager.shared.dismiss()
        do {
            try OnlyMacsFileAccessStore.saveResponse(
                OnlyMacsFileAccessResponse(
                    id: pending.request.id,
                    decidedAt: Date(),
                    status: .rejected,
                    selectedPaths: [],
                    contextPath: nil,
                    manifestPath: nil,
                    bundlePath: nil,
                    bundleSHA256: nil,
                    exportMode: nil,
                    warnings: [],
                    message: message
                )
            )
            try OnlyMacsFileAccessStore.appendAuditRecord(
                OnlyMacsFileAccessAuditRecord(
                    id: pending.request.id,
                    decidedAt: Date(),
                    status: .rejected,
                    workspaceRoot: pending.request.workspaceRoot,
                    swarmName: pending.request.swarmName,
                    promptSummary: pending.promptSummary,
                    selectedPaths: pending.selectedPaths.sorted(),
                    exportedPaths: [],
                    blockedPaths: pending.preview.entries.filter { $0.status == .blocked }.map(\.path),
                    warnings: pending.preview.warnings
                )
            )
        } catch {
            lastError = "OnlyMacs could not save the file approval response."
        }
    }

    func approvePendingFileAccessNow() {
        guard let pending = pendingFileAccessApproval else { return }
        pendingFileAccessApproval = nil
        pendingFileAccessPresentationCounter = 0
        rememberFinalizedFileAccessRequest(id: pending.request.id)
        OnlyMacsFileApprovalWindowManager.shared.dismiss()
        do {
            let artifacts = try OnlyMacsFileExportBuilder.buildArtifacts(
                for: pending.request,
                selectedPaths: pending.selectedPaths.sorted()
            )
            try OnlyMacsFileAccessStore.saveResponse(
                OnlyMacsFileAccessResponse(
                    id: pending.request.id,
                    decidedAt: Date(),
                    status: .approved,
                    selectedPaths: pending.selectedPaths.sorted(),
                    contextPath: artifacts.contextURL.path,
                    manifestPath: artifacts.manifestURL.path,
                    bundlePath: artifacts.bundleURL.path,
                    bundleSHA256: artifacts.bundleSHA256,
                    exportMode: artifacts.manifest.exportMode,
                    warnings: artifacts.manifest.warnings,
                    message: nil
                )
            )
            try OnlyMacsFileAccessStore.appendAuditRecord(
                OnlyMacsFileAccessAuditRecord(
                    id: pending.request.id,
                    decidedAt: Date(),
                    status: .approved,
                    workspaceRoot: pending.request.workspaceRoot,
                    swarmName: pending.request.swarmName,
                    promptSummary: pending.promptSummary,
                    selectedPaths: pending.selectedPaths.sorted(),
                    exportedPaths: artifacts.manifest.files.filter { $0.status == .ready || $0.status == .trimmed }.map(\.path),
                    blockedPaths: artifacts.manifest.files.filter { $0.status == .blocked || $0.status == .missing }.map(\.path),
                    warnings: artifacts.manifest.warnings
                )
            )
        } catch {
            pendingFileAccessApproval = pending
            finalizedFileAccessRequestIDs.removeValue(forKey: pending.request.id)
            lastError = "OnlyMacs could not prepare the trusted file bundle."
        }
    }

    func publishThisMacNow() {
        Task {
            await publishThisMac()
        }
    }

    func unpublishThisMacNow() {
        Task {
            await unpublishThisMac()
        }
    }

    func makeReadyNow() {
        Task {
            await makeReady()
        }
    }

    func fixEverythingNow() {
        Task {
            await fixEverything()
        }
    }

    func runSelfTestNow() {
        Task {
            await runSelfTest()
        }
    }

    func resetToSafeDefaultsNow() {
        Task {
            await resetToSafeDefaults()
        }
    }

    func publishSuggestedModelNow() {
        guard let suggestion = nextModelSuggestion else { return }
        Task {
            await publishSuggestedModel(suggestion)
        }
    }

    func copyLatestInviteToken() {
        guard hasUsableInvite else {
            lastError = inviteIsExpired
                ? "The current invite expired. Create a fresh invite before copying the backup token."
                : "Create an invite before copying the backup token."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latestInviteToken, forType: .string)
        markInviteShared(stage: .sent, detail: "Invite token copied and ready to send.")
    }

    func setOnlyMacsNotificationsEnabled(_ enabled: Bool) {
        onlyMacsNotificationsEnabled = enabled
        userDefaults.set(enabled, forKey: Self.onlyMacsNotificationsKey)
    }

}
