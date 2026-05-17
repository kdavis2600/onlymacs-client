import AppKit
import Foundation
@preconcurrency import Sparkle

struct OnlyMacsAvailableUpdate: Equatable, Codable {
    let version: String
    let buildNumber: String
    let title: String?
    let channel: String?
    let releaseNotesURL: URL?

    init(
        version: String,
        buildNumber: String,
        title: String? = nil,
        channel: String? = nil,
        releaseNotesURL: URL? = nil
    ) {
        self.version = version
        self.buildNumber = buildNumber
        self.title = title
        self.channel = channel
        self.releaseNotesURL = releaseNotesURL
    }

    init(item: SUAppcastItem) {
        version = item.displayVersionString
        buildNumber = item.versionString
        title = item.title
        channel = item.channel
        releaseNotesURL = item.fullReleaseNotesURL ?? item.releaseNotesURL
    }

    var displayLabel: String {
        "v\(version) · build \(buildNumber)"
    }

    var detailLabel: String {
        let trimmedChannel = channel?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedChannel, !trimmedChannel.isEmpty else {
            return displayLabel
        }
        return "\(displayLabel) · \(trimmedChannel)"
    }
}

struct OnlyMacsPublishedReleaseNotice: Equatable, Codable {
    let version: String
    let buildNumber: String
    let channel: String
    let publishedAt: Date?
    let appcastURL: URL?
    let archiveURL: URL?
    let releaseNotes: String?

    enum CodingKeys: String, CodingKey {
        case version
        case buildNumber = "build_number"
        case channel
        case publishedAt = "published_at"
        case appcastURL = "appcast_url"
        case archiveURL = "archive_url"
        case releaseNotes = "release_notes"
    }

    func targets(channelIdentifier: String) -> Bool {
        channel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == channelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func isNewer(than currentBuildNumber: String) -> Bool {
        guard
            let current = Int64(currentBuildNumber.trimmingCharacters(in: .whitespacesAndNewlines)),
            let published = Int64(buildNumber.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return buildNumber > currentBuildNumber
        }
        return published > current
    }
}

func shouldTriggerOnlyMacsPublishedReleaseProbe(
    currentBuildNumber: String,
    currentChannelIdentifier: String,
    state: OnlyMacsSparkleState,
    notice: OnlyMacsPublishedReleaseNotice,
    lastTriggeredBuildNumber: String?,
    lastTriggeredAt: Date?,
    now: Date = Date(),
    retryInterval: TimeInterval = 900
) -> Bool {
    guard notice.targets(channelIdentifier: currentChannelIdentifier) else { return false }
    guard notice.isNewer(than: currentBuildNumber) else { return false }
    guard !state.isChecking, !state.isDownloading, !state.isInstalling, !state.isReadyToInstallOnQuit else { return false }
    guard state.availableUpdate?.buildNumber != notice.buildNumber else { return false }

    if lastTriggeredBuildNumber == notice.buildNumber,
       let lastTriggeredAt,
       now.timeIntervalSince(lastTriggeredAt) < retryInterval {
        return false
    }

    return true
}

func shouldStartOnlyMacsAutomaticSparkleCheck(
    currentBuildNumber: String,
    currentChannelIdentifier: String,
    state: OnlyMacsSparkleState,
    notice: OnlyMacsPublishedReleaseNotice,
    lastTriggeredBuildNumber: String?,
    lastTriggeredAt: Date?,
    now: Date = Date(),
    retryInterval: TimeInterval = 900
) -> Bool {
    guard notice.targets(channelIdentifier: currentChannelIdentifier) else { return false }
    guard notice.isNewer(than: currentBuildNumber) else { return false }
    guard !state.isChecking, !state.isDownloading, !state.isInstalling, !state.isReadyToInstallOnQuit else { return false }

    if lastTriggeredBuildNumber == notice.buildNumber,
       let lastTriggeredAt,
       now.timeIntervalSince(lastTriggeredAt) < retryInterval {
        return false
    }

    return true
}

struct OnlyMacsSparkleState: Equatable {
    var availableUpdate: OnlyMacsAvailableUpdate?
    var lastCheckedAt: Date?
    var isChecking = false
    var isDownloading = false
    var isInstalling = false
    var isReadyToInstallOnQuit = false
    var canCheckForUpdates = false
    var automaticChecksEnabled = false
    var automaticDownloadsEnabled = false
    var errorMessage: String?
    var statusHint: String?
}

let onlyMacsSparkleNoUpdateErrorCode = 1001

func isOnlyMacsSparkleNoUpdateError(_ error: Error?) -> Bool {
    guard let error else { return false }
    let nsError = error as NSError
    if nsError.domain == SUSparkleErrorDomain, nsError.code == onlyMacsSparkleNoUpdateErrorCode {
        return true
    }
    if nsError.userInfo[SPUNoUpdateFoundReasonKey] != nil {
        return true
    }
    let description = nsError.localizedDescription.lowercased()
    return description.contains("up to date") || description.contains("no update")
}

func shouldSurfaceOnlyMacsUpdateError(_ message: String?) -> Bool {
    guard let message else { return false }
    let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }
    if normalized.contains("up to date")
        || normalized.contains("no update")
        || normalized.contains("no newer update")
        || normalized.contains("already on the newest")
        || normalized.contains("already on newest") {
        return false
    }
    return true
}

enum OnlyMacsAutomaticInstallDecision: Equatable {
    case installNow
    case waitForIdle(reason: String)

    static func evaluate(
        activeRequesterSessions: Int,
        activeLocalShareSessions: Int,
        isRuntimeBusy: Bool,
        isInstallingStarterModels: Bool,
        isCompletingGuidedSetup: Bool
    ) -> OnlyMacsAutomaticInstallDecision {
        if activeRequesterSessions > 0 {
            return .waitForIdle(reason: "swarm requests finish")
        }
        if activeLocalShareSessions > 0 {
            return .waitForIdle(reason: "this Mac stops serving remote work")
        }
        if isInstallingStarterModels {
            return .waitForIdle(reason: "model installation finishes")
        }
        if isCompletingGuidedSetup {
            return .waitForIdle(reason: "setup finishes")
        }
        if isRuntimeBusy {
            return .waitForIdle(reason: "OnlyMacs finishes starting or reconfiguring")
        }
        return .installNow
    }
}

@MainActor
protocol OnlyMacsSparkleDriver: AnyObject {
    var lastUpdateCheckDate: Date? { get }
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var allowsAutomaticUpdates: Bool { get }

    func startUpdater()
    func clearFeedURLFromUserDefaults()
    func checkForUpdates()
    func checkForUpdatesInBackground()
    func showUpdateInFocus()
}

@MainActor
private final class OnlyMacsStandardSparkleDriver: OnlyMacsSparkleDriver {
    private let updaterController: SPUStandardUpdaterController

    init(updaterDelegate: SPUUpdaterDelegate, userDriverDelegate: SPUStandardUserDriverDelegate) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: userDriverDelegate
        )
    }

    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate as Date?
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            updaterController.updater.automaticallyChecksForUpdates
        }
        set {
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get {
            updaterController.updater.automaticallyDownloadsUpdates
        }
        set {
            updaterController.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    var allowsAutomaticUpdates: Bool {
        updaterController.updater.allowsAutomaticUpdates
    }

    func startUpdater() {
        updaterController.startUpdater()
    }

    func clearFeedURLFromUserDefaults() {
        _ = updaterController.updater.clearFeedURLFromUserDefaults()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }

    func showUpdateInFocus() {
        updaterController.userDriver.showUpdateInFocus()
    }
}

@MainActor
final class OnlyMacsSparkleUpdater: NSObject {
    private static let releaseManifestPollIntervalNanoseconds: UInt64 = 300_000_000_000
    private static let initialReleaseManifestPollDelayNanoseconds: UInt64 = 15_000_000_000
    private static let releaseManifestRetryInterval: TimeInterval = 900
    private static let automaticSparkleCheckRetryInterval: TimeInterval = 900
    private static let automaticInstallRetryIntervalNanoseconds: UInt64 = 30_000_000_000

    private let buildInfo: BuildInfo
    private let notificationService: OnlyMacsUserNotificationService
    private var sparkleDriver: OnlyMacsSparkleDriver?
    private var immediateInstallHandler: (() -> Void)?
    private var automaticInstallRetryTask: Task<Void, Never>?
    private var lastNotifiedBuildNumber: String?
    private var shouldForegroundUpdateUI = false
    private var foregroundUpdateUIToken = UUID()
    private var releaseManifestPollTask: Task<Void, Never>?
    private var lastReleaseManifestTriggeredBuildNumber: String?
    private var lastReleaseManifestTriggeredAt: Date?
    private var lastAutomaticSparkleCheckBuildNumber: String?
    private var lastAutomaticSparkleCheckAt: Date?
    private let releaseManifestDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private(set) var state = OnlyMacsSparkleState() {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    var onStateChange: ((OnlyMacsSparkleState) -> Void)?
    var automaticInstallDecisionProvider: () -> OnlyMacsAutomaticInstallDecision = { .installNow }

    init(
        buildInfo: BuildInfo,
        notificationService: OnlyMacsUserNotificationService,
        sparkleDriver: OnlyMacsSparkleDriver? = nil
    ) {
        self.buildInfo = buildInfo
        self.notificationService = notificationService
        super.init()

        guard buildInfo.sparkleConfigured else {
            state.errorMessage = "Automatic app updates are not configured in this build yet."
            state.statusHint = "OnlyMacs can still run, but seamless in-app updates need a Sparkle feed URL and public signing key."
            return
        }

        self.sparkleDriver = sparkleDriver ?? OnlyMacsStandardSparkleDriver(
            updaterDelegate: self,
            userDriverDelegate: self
        )
        syncStateFromUpdater()
    }

    func start() {
        guard let sparkleDriver else { return }
        sparkleDriver.startUpdater()
        sparkleDriver.clearFeedURLFromUserDefaults()
        enforceUnattendedSparklePolicy()
        syncStateFromUpdater()
        startReleaseManifestPollingIfNeeded()
    }

    func checkForUpdates() {
        guard let sparkleDriver else { return }
        shouldForegroundUpdateUI = true
        focusUpdateUIIfNeeded(forceActivate: true)
        sparkleDriver.checkForUpdates()
        state.isChecking = true
        state.errorMessage = nil
        state.statusHint = "OnlyMacs is asking Sparkle for the latest \(buildInfo.channelIdentifier) build."
        syncStateFromUpdater()
    }

    func installPreparedUpdateOrCheck() {
        if let immediateInstallHandler {
            automaticInstallRetryTask?.cancel()
            automaticInstallRetryTask = nil
            state.isInstalling = true
            state.statusHint = "OnlyMacs is applying the downloaded update and will relaunch shortly."
            self.immediateInstallHandler = nil
            immediateInstallHandler()
            return
        }
        checkForUpdates()
    }

    deinit {
        releaseManifestPollTask?.cancel()
        automaticInstallRetryTask?.cancel()
    }

    private func syncStateFromUpdater() {
        guard let sparkleDriver else { return }
        state.lastCheckedAt = sparkleDriver.lastUpdateCheckDate
        state.canCheckForUpdates = sparkleDriver.canCheckForUpdates
        state.automaticChecksEnabled = sparkleDriver.automaticallyChecksForUpdates
        state.automaticDownloadsEnabled = sparkleDriver.automaticallyDownloadsUpdates
    }

    private func enforceUnattendedSparklePolicy() {
        guard let sparkleDriver else { return }
        sparkleDriver.automaticallyChecksForUpdates = true
        if sparkleDriver.allowsAutomaticUpdates {
            sparkleDriver.automaticallyDownloadsUpdates = true
        }
    }

    private func setAvailableUpdate(from item: SUAppcastItem?) {
        state.availableUpdate = item.map(OnlyMacsAvailableUpdate.init)
    }

    private func notifyAboutAvailableUpdateIfNeeded(item: SUAppcastItem, userInitiated: Bool) {
        guard !userInitiated else { return }
        let update = OnlyMacsAvailableUpdate(item: item)
        guard lastNotifiedBuildNumber != update.buildNumber else { return }
        lastNotifiedBuildNumber = update.buildNumber
        Task {
            await notificationService.deliver([
                OnlyMacsUserNotificationPlan(
                    id: "sparkle-update:\(update.buildNumber)",
                    title: "OnlyMacs update ready",
                    body: "\(update.displayLabel) is ready to install. OnlyMacs will apply it automatically when idle, or you can use Restart to Update."
                ),
            ])
        }
    }

    private func startReleaseManifestPollingIfNeeded() {
        guard releaseManifestPollTask == nil else { return }
        guard buildInfo.sparkleReleaseManifestURL != nil else { return }

        releaseManifestPollTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: Self.initialReleaseManifestPollDelayNanoseconds)
            while !Task.isCancelled {
                await self.pollPublishedReleaseNoticeIfNeeded()
                try? await Task.sleep(nanoseconds: Self.releaseManifestPollIntervalNanoseconds)
            }
        }
    }

    private func pollPublishedReleaseNoticeIfNeeded() async {
        guard let releaseManifestURL = buildInfo.sparkleReleaseManifestURL else { return }

        do {
            var request = URLRequest(url: releaseManifestURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
                return
            }

            let notice = try releaseManifestDecoder.decode(OnlyMacsPublishedReleaseNotice.self, from: data)
            handlePublishedReleaseNotice(notice, now: Date())
        } catch {
            return
        }
    }

    func handlePublishedReleaseNotice(_ notice: OnlyMacsPublishedReleaseNotice, now: Date = Date()) {
        guard notice.targets(channelIdentifier: buildInfo.channelIdentifier) else { return }
        guard notice.isNewer(than: buildInfo.buildNumber) else { return }

        if shouldTriggerOnlyMacsPublishedReleaseProbe(
            currentBuildNumber: buildInfo.buildNumber,
            currentChannelIdentifier: buildInfo.channelIdentifier,
            state: state,
            notice: notice,
            lastTriggeredBuildNumber: lastReleaseManifestTriggeredBuildNumber,
            lastTriggeredAt: lastReleaseManifestTriggeredAt,
            now: now,
            retryInterval: Self.releaseManifestRetryInterval
        ) {
            lastReleaseManifestTriggeredBuildNumber = notice.buildNumber
            lastReleaseManifestTriggeredAt = now
            recordPublishedReleaseNotice(notice)
        }

        startAutomaticSparkleCheckForPublishedRelease(notice, now: now)
    }

    private func recordPublishedReleaseNotice(_ notice: OnlyMacsPublishedReleaseNotice) {
        state.availableUpdate = OnlyMacsAvailableUpdate(
            version: notice.version,
            buildNumber: notice.buildNumber,
            title: "OnlyMacs \(notice.version)",
            channel: notice.channel,
            releaseNotesURL: nil
        )
        state.errorMessage = nil
        state.statusHint = "OnlyMacs spotted \(notice.version) build \(notice.buildNumber) on the live release feed."
        syncStateFromUpdater()
    }

    private func startAutomaticSparkleCheckForPublishedRelease(_ notice: OnlyMacsPublishedReleaseNotice, now: Date) {
        guard let sparkleDriver else { return }
        guard shouldStartOnlyMacsAutomaticSparkleCheck(
            currentBuildNumber: buildInfo.buildNumber,
            currentChannelIdentifier: buildInfo.channelIdentifier,
            state: state,
            notice: notice,
            lastTriggeredBuildNumber: lastAutomaticSparkleCheckBuildNumber,
            lastTriggeredAt: lastAutomaticSparkleCheckAt,
            now: now,
            retryInterval: Self.automaticSparkleCheckRetryInterval
        ) else {
            return
        }

        enforceUnattendedSparklePolicy()
        syncStateFromUpdater()
        guard sparkleDriver.canCheckForUpdates else {
            state.statusHint = "OnlyMacs found \(notice.version) build \(notice.buildNumber), and Sparkle is already busy with an update session."
            return
        }

        lastAutomaticSparkleCheckBuildNumber = notice.buildNumber
        lastAutomaticSparkleCheckAt = now
        shouldForegroundUpdateUI = false
        sparkleDriver.checkForUpdatesInBackground()
        state.isChecking = true
        state.errorMessage = nil
        state.statusHint = "OnlyMacs found \(notice.version) build \(notice.buildNumber) and asked Sparkle to download it in the background."
        syncStateFromUpdater()
    }

    private func attemptAutomaticImmediateInstall() {
        guard let immediateInstallHandler else {
            automaticInstallRetryTask?.cancel()
            automaticInstallRetryTask = nil
            return
        }

        switch automaticInstallDecisionProvider() {
        case .installNow:
            automaticInstallRetryTask?.cancel()
            automaticInstallRetryTask = nil
            state.isDownloading = false
            state.isInstalling = true
            state.isReadyToInstallOnQuit = false
            state.errorMessage = nil
            state.statusHint = "OnlyMacs is automatically installing the downloaded update and will relaunch shortly."
            self.immediateInstallHandler = nil
            syncStateFromUpdater()
            immediateInstallHandler()
        case .waitForIdle(let reason):
            state.isDownloading = false
            state.isInstalling = false
            state.isReadyToInstallOnQuit = true
            state.errorMessage = nil
            state.statusHint = "The update is downloaded. OnlyMacs will install it automatically when \(reason)."
            scheduleAutomaticInstallRetry()
        }
    }

    private func scheduleAutomaticInstallRetry() {
        guard automaticInstallRetryTask == nil else { return }
        automaticInstallRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.automaticInstallRetryIntervalNanoseconds)
                guard !Task.isCancelled else { return }
                self?.retryAutomaticImmediateInstall()
            }
        }
    }

    private func retryAutomaticImmediateInstall() {
        automaticInstallRetryTask = nil
        attemptAutomaticImmediateInstall()
    }

    private func focusUpdateUIIfNeeded(forceActivate: Bool = false) {
        guard forceActivate || shouldForegroundUpdateUI else { return }
        foregroundUpdateUIToken = UUID()
        let token = foregroundUpdateUIToken
        foregroundUpdateUIPass()

        for delay in [120_000_000, 350_000_000, 800_000_000] as [UInt64] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard let self, foregroundUpdateUIToken == token else { return }
                foregroundUpdateUIPass()
            }
        }
    }

    private func foregroundUpdateUIPass() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        sparkleDriver?.showUpdateInFocus()
        for window in NSApp.windows where window.isVisible {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}

@MainActor
extension OnlyMacsSparkleUpdater: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        buildInfo.sparkleFeedURL?.absoluteString
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        [buildInfo.channelIdentifier]
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        setAvailableUpdate(from: item)
        state.errorMessage = nil
        state.statusHint = "Sparkle found \(OnlyMacsAvailableUpdate(item: item).displayLabel)."
        focusUpdateUIIfNeeded()
        syncStateFromUpdater()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        shouldForegroundUpdateUI = false
        state.errorMessage = nil
        state.isDownloading = false
        state.isInstalling = false
        state.isReadyToInstallOnQuit = false
        immediateInstallHandler = nil
        setAvailableUpdate(from: nil)
        state.statusHint = "OnlyMacs is already on the newest \(buildInfo.channelIdentifier) build Sparkle can see."
        syncStateFromUpdater()
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        setAvailableUpdate(from: item)
        state.isDownloading = true
        state.isInstalling = false
        state.isReadyToInstallOnQuit = false
        state.errorMessage = nil
        state.statusHint = "Sparkle is downloading \(OnlyMacsAvailableUpdate(item: item).displayLabel) after the update was requested."
        syncStateFromUpdater()
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        setAvailableUpdate(from: item)
        state.isDownloading = false
        state.errorMessage = nil
        state.statusHint = "Sparkle finished downloading the update and is preparing it."
        syncStateFromUpdater()
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        setAvailableUpdate(from: item)
        state.isDownloading = false
        state.errorMessage = error.localizedDescription
        state.statusHint = "Sparkle could not download the new build."
        syncStateFromUpdater()
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        state.isDownloading = false
        state.statusHint = "The update download was cancelled."
        syncStateFromUpdater()
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        setAvailableUpdate(from: item)
        state.isDownloading = false
        state.isInstalling = true
        state.statusHint = "Sparkle is verifying and extracting the downloaded update."
        syncStateFromUpdater()
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        setAvailableUpdate(from: item)
        state.isInstalling = true
        state.statusHint = "Sparkle extracted the update and is preparing install-on-quit."
        syncStateFromUpdater()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        setAvailableUpdate(from: item)
        state.isInstalling = true
        state.isReadyToInstallOnQuit = false
        state.statusHint = "OnlyMacs is applying the downloaded update."
        syncStateFromUpdater()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        self.immediateInstallHandler = immediateInstallHandler
        setAvailableUpdate(from: item)
        state.isDownloading = false
        state.isInstalling = false
        state.isReadyToInstallOnQuit = true
        state.errorMessage = nil
        state.statusHint = "The new build is downloaded. OnlyMacs will install it automatically as soon as it is idle."
        notifyAboutAvailableUpdateIfNeeded(item: item, userInitiated: false)
        attemptAutomaticImmediateInstall()
        syncStateFromUpdater()
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        shouldForegroundUpdateUI = false
        state.isChecking = false
        state.isDownloading = false
        state.isInstalling = false
        state.isReadyToInstallOnQuit = false
        immediateInstallHandler = nil
        automaticInstallRetryTask?.cancel()
        automaticInstallRetryTask = nil
        if isOnlyMacsSparkleNoUpdateError(error) {
            state.errorMessage = nil
            setAvailableUpdate(from: nil)
            state.statusHint = "OnlyMacs is already on the newest \(buildInfo.channelIdentifier) build Sparkle can see."
        } else {
            state.errorMessage = error.localizedDescription
        }
        syncStateFromUpdater()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        shouldForegroundUpdateUI = false
        state.isChecking = false
        if isOnlyMacsSparkleNoUpdateError(error) {
            state.errorMessage = nil
            setAvailableUpdate(from: nil)
            state.statusHint = "OnlyMacs is already on the newest \(buildInfo.channelIdentifier) build Sparkle can see."
        } else if let error {
            state.errorMessage = error.localizedDescription
        }
        syncStateFromUpdater()
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        shouldForegroundUpdateUI = false
        state.isInstalling = true
        state.isReadyToInstallOnQuit = false
        state.statusHint = "OnlyMacs is relaunching into the new version."
        syncStateFromUpdater()
    }
}

extension OnlyMacsSparkleUpdater: SPUStandardUserDriverDelegate {
    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor [weak self] in
            self?.focusUpdateUIIfNeeded()
        }
    }

    nonisolated func standardUserDriverDidShowModalAlert() {
        Task { @MainActor [weak self] in
            self?.focusUpdateUIIfNeeded()
        }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if state.userInitiated {
                shouldForegroundUpdateUI = true
            }
            if handleShowingUpdate {
                focusUpdateUIIfNeeded()
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor [weak self] in
            self?.shouldForegroundUpdateUI = false
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor [weak self] in
            self?.shouldForegroundUpdateUI = false
        }
    }
}
