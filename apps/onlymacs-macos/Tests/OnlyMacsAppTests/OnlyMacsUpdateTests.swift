import XCTest
@testable import OnlyMacsApp
import OnlyMacsCore

final class OnlyMacsUpdateTests: XCTestCase {
    func testBuildInfoExposesSparkleFeedURL() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260419010000",
            buildChannel: "public",
            sparkleFeedURLString: "https://onlymacs.ai/onlymacs/updates/appcast-public.xml",
            sparklePublicEDKey: "public-key"
        )

        XCTAssertEqual(buildInfo.sparkleFeedURL?.absoluteString, "https://onlymacs.ai/onlymacs/updates/appcast-public.xml")
        XCTAssertTrue(buildInfo.sparkleConfigured)
    }

    func testBuildInfoDerivesSparkleReleaseManifestURL() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260419010000",
            buildChannel: "public",
            sparkleFeedURLString: "https://onlymacs.ai/onlymacs/updates/appcast-public.xml",
            sparklePublicEDKey: "public-key"
        )

        XCTAssertEqual(buildInfo.sparkleReleaseManifestURL?.absoluteString, "https://onlymacs.ai/onlymacs/updates/latest-public.json")
    }

    func testBuildInfoMarksSparkleAsUnavailableWithoutPublicKey() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260419010000",
            buildChannel: "public",
            sparkleFeedURLString: "https://onlymacs.ai/onlymacs/updates/appcast-public.xml",
            sparklePublicEDKey: nil
        )

        XCTAssertFalse(buildInfo.sparkleConfigured)
    }

    func testInstallerApplyLaunchAutoBootstrapsOllamaForPublicStarterModels() {
        let selections = InstallerPackageSelections(
            joinPublicSwarm: true,
            shareThisMac: true,
            runOnStartup: true,
            installStarterModels: true,
            installCodex: true,
            installClaude: true,
            presentedByInstaller: true
        )

        XCTAssertFalse(
            shouldAutoBootstrapOllamaDependency(
                launchRequestedInstallerSelectionApply: false,
                installerPackageSelections: selections
            )
        )
        XCTAssertTrue(
            shouldAutoBootstrapOllamaDependency(
                launchRequestedInstallerSelectionApply: true,
                installerPackageSelections: selections
            )
        )
        XCTAssertFalse(
            shouldAutoBootstrapOllamaDependency(
                launchRequestedInstallerSelectionApply: true,
                installerPackageSelections: nil
            )
        )
    }

    func testAvailableUpdateDetailIncludesChannelWhenPresent() {
        let update = OnlyMacsAvailableUpdate(
            version: "0.1.1",
            buildNumber: "20260419120000",
            title: "OnlyMacs 0.1.1",
            channel: "public",
            releaseNotesURL: nil
        )

        XCTAssertEqual(update.displayLabel, "v0.1.1 · build 20260419120000")
        XCTAssertEqual(update.detailLabel, "v0.1.1 · build 20260419120000 · public")
    }

    func testSparkleNoUpdateErrorDoesNotSurfaceAsFailedCheck() {
        let noUpdateError = NSError(
            domain: "SUSparkleErrorDomain",
            code: onlyMacsSparkleNoUpdateErrorCode,
            userInfo: [NSLocalizedDescriptionKey: "You're up to date!"]
        )
        let noUpdateReasonError = NSError(
            domain: "SUSparkleErrorDomain",
            code: 9999,
            userInfo: ["SUNoUpdateFoundReason": 1]
        )
        let realFailure = NSError(
            domain: "SUSparkleErrorDomain",
            code: 2001,
            userInfo: [NSLocalizedDescriptionKey: "Could not fetch appcast."]
        )

        XCTAssertTrue(isOnlyMacsSparkleNoUpdateError(noUpdateError))
        XCTAssertTrue(isOnlyMacsSparkleNoUpdateError(noUpdateReasonError))
        XCTAssertFalse(isOnlyMacsSparkleNoUpdateError(realFailure))
        XCTAssertFalse(shouldSurfaceOnlyMacsUpdateError("You're up to date!"))
        XCTAssertFalse(shouldSurfaceOnlyMacsUpdateError("OnlyMacs is already on the newest public build Sparkle can see."))
        XCTAssertTrue(shouldSurfaceOnlyMacsUpdateError("Could not fetch appcast."))
    }

    func testAutomaticInstallRunsImmediatelyWhenOnlyMacsIsIdle() {
        XCTAssertEqual(
            OnlyMacsAutomaticInstallDecision.evaluate(
                activeRequesterSessions: 0,
                activeLocalShareSessions: 0,
                isRuntimeBusy: false,
                isInstallingStarterModels: false,
                isCompletingGuidedSetup: false
            ),
            .installNow
        )
    }

    func testAutomaticInstallWaitsForRequesterWorkToFinish() {
        XCTAssertEqual(
            OnlyMacsAutomaticInstallDecision.evaluate(
                activeRequesterSessions: 1,
                activeLocalShareSessions: 0,
                isRuntimeBusy: false,
                isInstallingStarterModels: false,
                isCompletingGuidedSetup: false
            ),
            .waitForIdle(reason: "swarm requests finish")
        )
    }

    func testAutomaticInstallWaitsForServedWorkToFinish() {
        XCTAssertEqual(
            OnlyMacsAutomaticInstallDecision.evaluate(
                activeRequesterSessions: 0,
                activeLocalShareSessions: 1,
                isRuntimeBusy: false,
                isInstallingStarterModels: false,
                isCompletingGuidedSetup: false
            ),
            .waitForIdle(reason: "this Mac stops serving remote work")
        )
    }

    func testAutomaticInstallWaitsForSetupAndModelInstallWork() {
        XCTAssertEqual(
            OnlyMacsAutomaticInstallDecision.evaluate(
                activeRequesterSessions: 0,
                activeLocalShareSessions: 0,
                isRuntimeBusy: false,
                isInstallingStarterModels: true,
                isCompletingGuidedSetup: false
            ),
            .waitForIdle(reason: "model installation finishes")
        )

        XCTAssertEqual(
            OnlyMacsAutomaticInstallDecision.evaluate(
                activeRequesterSessions: 0,
                activeLocalShareSessions: 0,
                isRuntimeBusy: false,
                isInstallingStarterModels: false,
                isCompletingGuidedSetup: true
            ),
            .waitForIdle(reason: "setup finishes")
        )

        XCTAssertEqual(
            OnlyMacsAutomaticInstallDecision.evaluate(
                activeRequesterSessions: 0,
                activeLocalShareSessions: 0,
                isRuntimeBusy: true,
                isInstallingStarterModels: false,
                isCompletingGuidedSetup: false
            ),
            .waitForIdle(reason: "OnlyMacs finishes starting or reconfiguring")
        )
    }

    func testBuildInfoExposesPackagedCoordinatorDefault() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260420010000",
            buildChannel: "public",
            defaultCoordinatorURLString: " https://relay.onlymacs.example.com/ "
        )

        XCTAssertEqual(buildInfo.normalizedDefaultCoordinatorURL, "https://relay.onlymacs.example.com")
        XCTAssertEqual(buildInfo.preferredCoordinatorSettings?.mode, .hostedRemote)
        XCTAssertEqual(buildInfo.preferredCoordinatorSettings?.effectiveCoordinatorURL, "https://relay.onlymacs.example.com")
    }

    @MainActor
    func testStoredLocalCoordinatorUpgradesToPackagedHostedCoordinator() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260420010000",
            buildChannel: "public",
            defaultCoordinatorURLString: "https://relay.onlymacs.example.com"
        )

        let resolved = BridgeStore.resolveStoredCoordinatorSettings(
            CoordinatorConnectionSettings(mode: .embeddedLocal, remoteCoordinatorURL: ""),
            buildInfo: buildInfo
        )

        XCTAssertEqual(resolved.mode, .hostedRemote)
        XCTAssertEqual(resolved.effectiveCoordinatorURL, "https://relay.onlymacs.example.com")
    }

    @MainActor
    func testStoredLocalCoordinatorFallsBackToPublicHostedDefaultWithoutPackagedURL() {
        let buildInfo = BuildInfo(
            version: "dev",
            buildNumber: "dev"
        )

        let resolved = BridgeStore.resolveStoredCoordinatorSettings(
            CoordinatorConnectionSettings(mode: .embeddedLocal, remoteCoordinatorURL: ""),
            buildInfo: buildInfo
        )

        XCTAssertEqual(resolved.mode, .hostedRemote)
        XCTAssertEqual(resolved.effectiveCoordinatorURL, "https://onlymacs.ai")
    }

    @MainActor
    func testStoredHostedFallbackToLocalhostUpgradesToPackagedHostedCoordinator() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260423010000",
            buildChannel: "public",
            defaultCoordinatorURLString: "https://relay.onlymacs.example.com"
        )

        let resolved = BridgeStore.resolveStoredCoordinatorSettings(
            CoordinatorConnectionSettings(
                mode: .hostedRemote,
                remoteCoordinatorURL: ""
            ),
            buildInfo: buildInfo
        )

        XCTAssertEqual(resolved.mode, .hostedRemote)
        XCTAssertEqual(resolved.effectiveCoordinatorURL, "https://relay.onlymacs.example.com")
    }

    @MainActor
    func testStoredHostedLocalhostURLUpgradesToPackagedHostedCoordinator() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260425010000",
            buildChannel: "public",
            defaultCoordinatorURLString: "https://relay.onlymacs.example.com"
        )

        let resolved = BridgeStore.resolveStoredCoordinatorSettings(
            CoordinatorConnectionSettings(
                mode: .hostedRemote,
                remoteCoordinatorURL: "http://localhost:4319/"
            ),
            buildInfo: buildInfo
        )

        XCTAssertEqual(resolved.mode, .hostedRemote)
        XCTAssertEqual(resolved.effectiveCoordinatorURL, "https://relay.onlymacs.example.com")
    }

    @MainActor
    func testStoredEmbeddedLocalhostDraftUpgradesToPackagedHostedCoordinator() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260424010000",
            buildChannel: "public",
            defaultCoordinatorURLString: "https://relay.onlymacs.example.com"
        )

        let resolved = BridgeStore.resolveStoredCoordinatorSettings(
            CoordinatorConnectionSettings(
                mode: .embeddedLocal,
                remoteCoordinatorURL: "http://127.0.0.1:4319"
            ),
            buildInfo: buildInfo
        )

        XCTAssertEqual(resolved.mode, .hostedRemote)
        XCTAssertEqual(resolved.effectiveCoordinatorURL, "https://relay.onlymacs.example.com")
    }

    @MainActor
    func testStoredHostedRailwayURLUpgradesToPackagedOnlyMacsDomainCoordinator() {
        let buildInfo = BuildInfo(
            version: "0.1.3",
            buildNumber: "20260426060019",
            buildChannel: "public",
            defaultCoordinatorURLString: "https://onlymacs.ai"
        )

        let resolved = BridgeStore.resolveStoredCoordinatorSettings(
            CoordinatorConnectionSettings(
                mode: .hostedRemote,
                remoteCoordinatorURL: "https://onlymacs-coordinator-alpha.up.railway.app/"
            ),
            buildInfo: buildInfo
        )

        XCTAssertEqual(resolved.mode, .hostedRemote)
        XCTAssertEqual(resolved.effectiveCoordinatorURL, "https://onlymacs.ai")
    }

    func testBridgeUsesExpectedCoordinatorForHostedTarget() {
        let settings = CoordinatorConnectionSettings(
            mode: .hostedRemote,
            remoteCoordinatorURL: "https://relay.onlymacs.example.com"
        )

        XCTAssertTrue(
            bridgeUsesExpectedCoordinator(
                reportedCoordinatorURL: "https://relay.onlymacs.example.com/",
                settings: settings
            )
        )
        XCTAssertFalse(
            bridgeUsesExpectedCoordinator(
                reportedCoordinatorURL: "http://127.0.0.1:4319",
                settings: settings
            )
        )
    }

    func testBridgeUsesExpectedCoordinatorForEmbeddedTarget() {
        let settings = CoordinatorConnectionSettings(mode: .embeddedLocal, remoteCoordinatorURL: "")

        XCTAssertTrue(
            bridgeUsesExpectedCoordinator(
                reportedCoordinatorURL: "http://127.0.0.1:4319",
                settings: settings
            )
        )
        XCTAssertFalse(
            bridgeUsesExpectedCoordinator(
                reportedCoordinatorURL: "https://relay.onlymacs.example.com",
                settings: settings
            )
        )
    }

    func testHealthyBridgeWithUnexpectedCoordinatorShouldBeReplaced() {
        let settings = CoordinatorConnectionSettings(
            mode: .hostedRemote,
            remoteCoordinatorURL: "https://relay.onlymacs.example.com"
        )

        XCTAssertTrue(
            shouldReplaceHealthyBridge(
                reportedCoordinatorURL: "http://127.0.0.1:4319",
                settings: settings
            )
        )
        XCTAssertFalse(
            shouldReplaceHealthyBridge(
                reportedCoordinatorURL: "https://relay.onlymacs.example.com/",
                settings: settings
            )
        )
    }

    func testPublicSwarmAdoptsPackagedHostedCoordinator() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260422070000",
            buildChannel: "public",
            defaultCoordinatorURLString: "https://relay.onlymacs.example.com"
        )

        XCTAssertTrue(
            shouldAdoptHostedCoordinatorForPublicSwarm(
                currentSettings: CoordinatorConnectionSettings(mode: .embeddedLocal, remoteCoordinatorURL: ""),
                activeSwarmIsPublic: true,
                buildInfo: buildInfo
            )
        )
    }

    func testPublicSwarmAdoptsPackagedHostedCoordinatorWhenHostedModeFallsBackToLocalhost() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260422070000",
            buildChannel: "public",
            defaultCoordinatorURLString: "https://relay.onlymacs.example.com"
        )

        XCTAssertTrue(
            shouldAdoptHostedCoordinatorForPublicSwarm(
                currentSettings: CoordinatorConnectionSettings(
                    mode: .hostedRemote,
                    remoteCoordinatorURL: ""
                ),
                activeSwarmIsPublic: true,
                buildInfo: buildInfo
            )
        )
    }

    func testPublicSwarmAdoptsPackagedHostedCoordinatorWhenHostedModeStillTargetsLocalhost() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260422070000",
            buildChannel: "public",
            defaultCoordinatorURLString: "https://relay.onlymacs.example.com"
        )

        XCTAssertTrue(
            shouldAdoptHostedCoordinatorForPublicSwarm(
                currentSettings: CoordinatorConnectionSettings(
                    mode: .hostedRemote,
                    remoteCoordinatorURL: "http://127.0.0.1:4319"
                ),
                activeSwarmIsPublic: true,
                buildInfo: buildInfo
            )
        )
    }

    func testPrivateSwarmDoesNotForceHostedCoordinator() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260422070000",
            buildChannel: "public",
            defaultCoordinatorURLString: "https://relay.onlymacs.example.com"
        )

        XCTAssertFalse(
            shouldAdoptHostedCoordinatorForPublicSwarm(
                currentSettings: CoordinatorConnectionSettings(),
                activeSwarmIsPublic: false,
                buildInfo: buildInfo
            )
        )
    }

    func testHostedCoordinatorAlreadySelectedDoesNotReapplyForPublicSwarm() {
        let buildInfo = BuildInfo(
            version: "0.1.0",
            buildNumber: "20260422070000",
            buildChannel: "public",
            defaultCoordinatorURLString: "https://relay.onlymacs.example.com"
        )

        XCTAssertFalse(
            shouldAdoptHostedCoordinatorForPublicSwarm(
                currentSettings: CoordinatorConnectionSettings(
                    mode: .hostedRemote,
                    remoteCoordinatorURL: "https://relay.onlymacs.example.com"
                ),
                activeSwarmIsPublic: true,
                buildInfo: buildInfo
            )
        )
    }

    func testPublishedReleaseNoticeTriggersProbeForNewerBuild() {
        let notice = OnlyMacsPublishedReleaseNotice(
            version: "0.1.1",
            buildNumber: "20260422103000",
            channel: "public",
            publishedAt: ISO8601DateFormatter().date(from: "2026-04-22T10:30:00Z"),
            appcastURL: URL(string: "https://onlymacs.ai/onlymacs/updates/appcast-public.xml"),
            archiveURL: URL(string: "https://onlymacs.ai/onlymacs/updates/files/OnlyMacs-public.dmg"),
            releaseNotes: "New build"
        )

        XCTAssertTrue(
            shouldTriggerOnlyMacsPublishedReleaseProbe(
                currentBuildNumber: "20260422100000",
                currentChannelIdentifier: "public",
                state: OnlyMacsSparkleState(),
                notice: notice,
                lastTriggeredBuildNumber: nil,
                lastTriggeredAt: nil,
                now: ISO8601DateFormatter().date(from: "2026-04-22T10:31:00Z")!
            )
        )
    }

    func testAutomaticSparkleCheckStartsForNewerPublishedRelease() {
        let notice = OnlyMacsPublishedReleaseNotice(
            version: "0.1.1",
            buildNumber: "20260422103000",
            channel: "public",
            publishedAt: ISO8601DateFormatter().date(from: "2026-04-22T10:30:00Z"),
            appcastURL: nil,
            archiveURL: nil,
            releaseNotes: nil
        )

        XCTAssertTrue(
            shouldStartOnlyMacsAutomaticSparkleCheck(
                currentBuildNumber: "20260422100000",
                currentChannelIdentifier: "public",
                state: OnlyMacsSparkleState(),
                notice: notice,
                lastTriggeredBuildNumber: nil,
                lastTriggeredAt: nil,
                now: ISO8601DateFormatter().date(from: "2026-04-22T10:31:00Z")!
            )
        )
    }

    func testAutomaticSparkleCheckSkipsRecentDuplicateRelease() {
        let notice = OnlyMacsPublishedReleaseNotice(
            version: "0.1.1",
            buildNumber: "20260422103000",
            channel: "public",
            publishedAt: ISO8601DateFormatter().date(from: "2026-04-22T10:30:00Z"),
            appcastURL: nil,
            archiveURL: nil,
            releaseNotes: nil
        )

        XCTAssertFalse(
            shouldStartOnlyMacsAutomaticSparkleCheck(
                currentBuildNumber: "20260422100000",
                currentChannelIdentifier: "public",
                state: OnlyMacsSparkleState(),
                notice: notice,
                lastTriggeredBuildNumber: "20260422103000",
                lastTriggeredAt: ISO8601DateFormatter().date(from: "2026-04-22T10:25:00Z"),
                now: ISO8601DateFormatter().date(from: "2026-04-22T10:31:00Z")!
            )
        )
    }

    @MainActor
    func testStartEnforcesUnattendedSparklePolicy() {
        let driver = FakeOnlyMacsSparkleDriver()
        driver.automaticallyChecksForUpdates = false
        driver.automaticallyDownloadsUpdates = false
        driver.allowsAutomaticUpdates = true
        let updater = OnlyMacsSparkleUpdater(
            buildInfo: sparkleConfiguredBuildInfo(),
            notificationService: OnlyMacsUserNotificationService(),
            sparkleDriver: driver
        )

        updater.start()

        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(driver.clearFeedURLCount, 1)
        XCTAssertTrue(driver.automaticallyChecksForUpdates)
        XCTAssertTrue(driver.automaticallyDownloadsUpdates)
    }

    @MainActor
    func testPublishedReleaseNoticeStartsBackgroundSparkleCheck() {
        let driver = FakeOnlyMacsSparkleDriver()
        driver.canCheckForUpdates = true
        let updater = OnlyMacsSparkleUpdater(
            buildInfo: sparkleConfiguredBuildInfo(buildNumber: "20260422100000"),
            notificationService: OnlyMacsUserNotificationService(),
            sparkleDriver: driver
        )
        let notice = OnlyMacsPublishedReleaseNotice(
            version: "0.1.1",
            buildNumber: "20260422103000",
            channel: "public",
            publishedAt: ISO8601DateFormatter().date(from: "2026-04-22T10:30:00Z"),
            appcastURL: nil,
            archiveURL: nil,
            releaseNotes: nil
        )

        updater.handlePublishedReleaseNotice(
            notice,
            now: ISO8601DateFormatter().date(from: "2026-04-22T10:31:00Z")!
        )

        XCTAssertEqual(driver.backgroundCheckCount, 1)
        XCTAssertEqual(driver.foregroundCheckCount, 0)
        XCTAssertEqual(driver.showUpdateInFocusCount, 0)
        XCTAssertTrue(driver.automaticallyChecksForUpdates)
        XCTAssertTrue(driver.automaticallyDownloadsUpdates)
        XCTAssertTrue(updater.state.isChecking)
        XCTAssertEqual(updater.state.availableUpdate?.buildNumber, "20260422103000")
    }

    @MainActor
    func testPublishedReleaseNoticeDoesNotStartBackgroundSparkleCheckWhenSparkleIsBusy() {
        let driver = FakeOnlyMacsSparkleDriver()
        driver.canCheckForUpdates = false
        let updater = OnlyMacsSparkleUpdater(
            buildInfo: sparkleConfiguredBuildInfo(buildNumber: "20260422100000"),
            notificationService: OnlyMacsUserNotificationService(),
            sparkleDriver: driver
        )
        let notice = OnlyMacsPublishedReleaseNotice(
            version: "0.1.1",
            buildNumber: "20260422103000",
            channel: "public",
            publishedAt: ISO8601DateFormatter().date(from: "2026-04-22T10:30:00Z"),
            appcastURL: nil,
            archiveURL: nil,
            releaseNotes: nil
        )

        updater.handlePublishedReleaseNotice(
            notice,
            now: ISO8601DateFormatter().date(from: "2026-04-22T10:31:00Z")!
        )

        XCTAssertEqual(driver.backgroundCheckCount, 0)
        XCTAssertEqual(driver.foregroundCheckCount, 0)
        XCTAssertEqual(updater.state.availableUpdate?.buildNumber, "20260422103000")
        XCTAssertFalse(updater.state.isChecking)
    }

    @MainActor
    func testPublishedReleaseNoticeRetriesBackgroundSparkleCheckAfterBusySession() {
        let driver = FakeOnlyMacsSparkleDriver()
        driver.canCheckForUpdates = false
        let updater = OnlyMacsSparkleUpdater(
            buildInfo: sparkleConfiguredBuildInfo(buildNumber: "20260422100000"),
            notificationService: OnlyMacsUserNotificationService(),
            sparkleDriver: driver
        )
        let notice = OnlyMacsPublishedReleaseNotice(
            version: "0.1.1",
            buildNumber: "20260422103000",
            channel: "public",
            publishedAt: ISO8601DateFormatter().date(from: "2026-04-22T10:30:00Z"),
            appcastURL: nil,
            archiveURL: nil,
            releaseNotes: nil
        )

        updater.handlePublishedReleaseNotice(
            notice,
            now: ISO8601DateFormatter().date(from: "2026-04-22T10:31:00Z")!
        )
        driver.canCheckForUpdates = true
        updater.handlePublishedReleaseNotice(
            notice,
            now: ISO8601DateFormatter().date(from: "2026-04-22T10:36:00Z")!
        )

        XCTAssertEqual(driver.backgroundCheckCount, 1)
        XCTAssertEqual(driver.foregroundCheckCount, 0)
        XCTAssertTrue(updater.state.isChecking)
    }

    func testPublishedReleaseNoticeSkipsRecentDuplicateProbe() {
        let notice = OnlyMacsPublishedReleaseNotice(
            version: "0.1.1",
            buildNumber: "20260422103000",
            channel: "public",
            publishedAt: ISO8601DateFormatter().date(from: "2026-04-22T10:30:00Z"),
            appcastURL: nil,
            archiveURL: nil,
            releaseNotes: nil
        )

        XCTAssertFalse(
            shouldTriggerOnlyMacsPublishedReleaseProbe(
                currentBuildNumber: "20260422100000",
                currentChannelIdentifier: "public",
                state: OnlyMacsSparkleState(),
                notice: notice,
                lastTriggeredBuildNumber: "20260422103000",
                lastTriggeredAt: ISO8601DateFormatter().date(from: "2026-04-22T10:25:00Z"),
                now: ISO8601DateFormatter().date(from: "2026-04-22T10:31:00Z")!
            )
        )
    }

    private func sparkleConfiguredBuildInfo(
        version: String = "0.1.0",
        buildNumber: String = "20260422100000"
    ) -> BuildInfo {
        BuildInfo(
            version: version,
            buildNumber: buildNumber,
            buildChannel: "public",
            sparkleFeedURLString: "https://onlymacs.ai/onlymacs/updates/appcast-public.xml",
            sparklePublicEDKey: "public-key"
        )
    }
}

@MainActor
private final class FakeOnlyMacsSparkleDriver: OnlyMacsSparkleDriver {
    var lastUpdateCheckDate: Date?
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var allowsAutomaticUpdates = true
    var startCount = 0
    var clearFeedURLCount = 0
    var foregroundCheckCount = 0
    var backgroundCheckCount = 0
    var showUpdateInFocusCount = 0

    func startUpdater() {
        startCount += 1
    }

    func clearFeedURLFromUserDefaults() {
        clearFeedURLCount += 1
    }

    func checkForUpdates() {
        foregroundCheckCount += 1
    }

    func checkForUpdatesInBackground() {
        backgroundCheckCount += 1
        lastUpdateCheckDate = Date()
    }

    func showUpdateInFocus() {
        showUpdateInFocusCount += 1
    }
}
