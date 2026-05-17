import AppKit
import OnlyMacsCore
import SwiftUI

// Runtime, networking, bootstrap, and background-refresh operations for BridgeStore.

func shouldAutoSelectSwarmsSection(
    force: Bool,
    shouldFocusSwarms: Bool,
    currentSection: ControlCenterSection,
    hasUserNavigatedPopupSectionsThisLaunch: Bool
) -> Bool {
    if force {
        return true
    }
    guard shouldFocusSwarms else { return false }
    guard !hasUserNavigatedPopupSectionsThisLaunch else { return false }
    return currentSection == .swarms
}

enum AutomaticSharingAction: Equatable {
    case publish
    case unpublish
}

func automaticSharingAction(
    selectedMode: AppMode,
    runtimeStatus: String,
    activeSwarmID: String,
    published: Bool,
    publishedSwarmID: String,
    discoveredModelCount: Int
) -> AutomaticSharingAction? {
    let normalizedSwarmID = activeSwarmID.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedPublishedSwarmID = publishedSwarmID.trimmingCharacters(in: .whitespacesAndNewlines)
    let shouldBeSharing = selectedMode.allowsShare
        && runtimeStatus == "ready"
        && !normalizedSwarmID.isEmpty
        && discoveredModelCount > 0
    let isSharingCurrentSwarm = published && normalizedPublishedSwarmID == normalizedSwarmID

    if shouldBeSharing {
        return isSharingCurrentSwarm ? nil : .publish
    }
    return published ? .unpublish : nil
}

func shouldAdoptHostedCoordinatorForPublicSwarm(
    currentSettings: CoordinatorConnectionSettings,
    activeSwarmIsPublic: Bool,
    buildInfo: BuildInfo
) -> Bool {
    guard activeSwarmIsPublic else { return false }
    guard buildInfo.preferredCoordinatorSettings != nil else { return false }
    if currentSettings.mode == .embeddedLocal || currentSettings.normalizedRemoteCoordinatorURL == nil {
        return true
    }
    guard let url = URL(string: currentSettings.effectiveCoordinatorURL),
          let host = url.host?.lowercased()
    else {
        return false
    }
    return currentSettings.effectiveCoordinatorURL == CoordinatorConnectionSettings.embeddedCoordinatorURL
        || host == "127.0.0.1"
        || host == "localhost"
}

func displayableBridgeError(status: String, error: String?) -> String? {
    let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalizedStatus == "degraded" || normalizedStatus == "error" else {
        return nil
    }
    let trimmedError = error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmedError.isEmpty ? nil : trimmedError
}

func shouldPreserveBridgeSnapshotAfterTransientRefreshFailure(
    previousSnapshot: BridgeStatusSnapshot,
    runtimeStatus: String,
    errorMessage: String
) -> Bool {
    guard previousSnapshot.lastUpdated != nil else { return false }
    let normalizedBridge = previousSnapshot.bridge.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedRuntime = runtimeStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let activeSwarmID = previousSnapshot.runtime.activeSwarmID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedBridge == "ready", normalizedRuntime == "ready", !activeSwarmID.isEmpty else {
        return false
    }
    return isTransientBridgeRefreshError(errorMessage)
}

func replacementActiveSwarmIDForUnavailableActiveSwarm(
    activeSwarmID: String,
    swarms: [SwarmOption]
) -> String? {
    let normalizedActiveSwarmID = activeSwarmID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedActiveSwarmID.isEmpty, !swarms.isEmpty else { return nil }
    if swarms.contains(where: { $0.id == normalizedActiveSwarmID }) {
        return nil
    }
    if let publicSwarm = swarms.first(where: \.isPublic) {
        return publicSwarm.id
    }
    return swarms.first?.id
}

func isTransientBridgeRefreshError(_ message: String) -> Bool {
    let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }
    return [
        "context deadline exceeded",
        "timed out",
        "timeout",
        "network connection was lost",
        "http 502",
        "http 503",
        "http 504",
        "bad gateway",
        "service unavailable",
        "gateway timeout"
    ].contains { normalized.contains($0) }
}

extension BridgeStore {
    func refresh() async {
        let previousSnapshot = snapshot
        let previousLocalShare = localShare
        let previousActivity = latestOnlyMacsActivity
        let previousSelectedMode = selectedMode
        let previousSelectedSwarmID = selectedSwarmID
        let preserveModeDraft = previousSelectedMode.rawValue != previousSnapshot.runtime.mode
        let preserveSwarmDraft = hasManualSwarmSelectionDraft
            && !previousSelectedSwarmID.isEmpty
            && previousSelectedSwarmID != previousSnapshot.runtime.activeSwarmID
        guard let url = bridgeURL(path: "/admin/v1/status") else {
            snapshot = .offline(message: "Bridge URL is invalid.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                let message = statusCode.map { "Bridge returned HTTP \($0)." } ?? "Bridge returned an unexpected response."
                if shouldPreserveBridgeSnapshotAfterTransientRefreshFailure(
                    previousSnapshot: previousSnapshot,
                    runtimeStatus: runtimeState.status,
                    errorMessage: message
                ) {
                    snapshot = previousSnapshot
                    localShare = previousLocalShare
                    lastError = nil
                } else {
                    snapshot = .offline(message: message)
                    lastError = message
                }
                return
            }

            let decoded = try decoder.decode(BridgeStatusSnapshot.self, from: data).withUpdatedTimestamp()
            if let pendingMemberNameConfirmation {
                if decoded.identity.memberName == pendingMemberNameConfirmation {
                    self.pendingMemberNameConfirmation = nil
                    snapshot = decoded
                } else {
                    snapshot = decoded.withOptimisticLocalMemberName(pendingMemberNameConfirmation)
                }
            } else {
                snapshot = decoded
            }
            if !hasEditedMemberNameDraft {
                memberNameDraft = pendingMemberNameConfirmation ?? snapshot.identity.memberName
            }
            persistCachedMemberName(snapshot.identity.memberName)
            initializeSessionSavedTokensBaselineIfNeeded()
            reloadInstallerRecommendations()
            if !preserveModeDraft {
                selectedMode = .both
            }
            if !preserveSwarmDraft || previousSelectedSwarmID.isEmpty {
                selectedSwarmID = decoded.runtime.activeSwarmID
            }
            if activeRuntimeSwarm?.isPublic == true {
                selectedMode = .both
            }
            lastError = displayableBridgeError(status: decoded.bridge.status, error: decoded.bridge.error)
            if let replacementSwarmID = replacementActiveSwarmIDForUnavailableActiveSwarm(
                activeSwarmID: decoded.runtime.activeSwarmID,
                swarms: decoded.swarms
            ) {
                selectedSwarmID = replacementSwarmID
                selectedMode = .both
                await applyRuntime()
                return
            }
            if await adoptHostedCoordinatorForPublicSwarmIfNeeded(activeSwarmIsPublic: activeRuntimeSwarm?.isPublic == true) {
                return
            }
            await refreshLocalShare()
            await reconcileConnectedSwarmSharingStateIfNeeded()
            await reconcileAutomaticJobWorkersIfNeeded()
            refreshToolStatuses()
            refreshLauncherStatus()
            refreshLatestOnlyMacsActivity()
            scanClipboardForInvite()
            updateInviteProgress()
            refreshSetupDefaultsFromRuntime()
            focusSwarmsSectionIfNeeded(force: false)
            maybeAutoBootstrapPopupExperience()
            await processOnlyMacsNotifications(previousSnapshot: previousSnapshot, previousLocalShare: previousLocalShare, previousActivity: previousActivity)
        } catch {
            let message = error.localizedDescription
            if shouldPreserveBridgeSnapshotAfterTransientRefreshFailure(
                previousSnapshot: previousSnapshot,
                runtimeStatus: runtimeState.status,
                errorMessage: message
            ) {
                snapshot = previousSnapshot
                localShare = previousLocalShare
                lastError = nil
            } else {
                snapshot = .offline(message: message)
                localShare = .offline(message: message)
                lastError = message
            }
            await reconcileAutomaticJobWorkersIfNeeded()
            refreshToolStatuses()
            refreshLauncherStatus()
            refreshLatestOnlyMacsActivity()
            scanClipboardForInvite()
            updateInviteProgress()
            focusSwarmsSectionIfNeeded(force: false)
            maybeAutoBootstrapPopupExperience()
            await processOnlyMacsNotifications(previousSnapshot: previousSnapshot, previousLocalShare: previousLocalShare, previousActivity: previousActivity)
        }
    }

    func exportSupportBundle() async {
        let bridgeStatusJSON = await fetchBridgeText(path: "/admin/v1/status")
        let localShareJSON = await fetchBridgeText(path: "/admin/v1/share/local")
        let swarmSessionsJSON = await fetchBridgeText(path: "/admin/v1/swarm/sessions")

        do {
            let outputURL = try SupportBundleWriter.writeBundle(
                makeSupportBundleInput(
                    bridgeStatusJSON: bridgeStatusJSON,
                    localShareJSON: localShareJSON,
                    swarmSessionsJSON: swarmSessionsJSON
                )
            )
            lastSupportBundlePath = outputURL.path
            lastError = nil
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } catch {
            lastError = error.localizedDescription
        }
    }

    func makeSupportBundleInput(
        bridgeStatusJSON: String?,
        localShareJSON: String?,
        swarmSessionsJSON: String?
    ) -> SupportBundleInput {
        let recoveryCard = recoveryCard
        return SupportBundleInput(
            generatedAt: Date(),
            buildVersion: buildInfo.version,
            buildNumber: buildInfo.buildNumber,
            buildTimestamp: buildInfo.buildTimestamp,
            buildChannel: buildInfo.buildChannel,
            hostName: Host.current().localizedName ?? "Unknown Mac",
            selectedMode: selectedMode.rawValue,
            coordinatorMode: coordinatorConnectionMode.rawValue,
            coordinatorTarget: effectiveCoordinatorTarget,
            lastError: lastError,
            recoveryTitle: recoveryCard?.title,
            recoveryDetail: recoveryCard?.detail,
            recoveryActions: recoveryCard?.actions.map(\.label) ?? [],
            inviteExpiryDetail: inviteExpiryDetail,
            runtimeStatus: runtimeState.status,
            runtimeDetail: runtimeState.detail,
            helperSource: runtimeState.helperSource,
            logsDirectory: runtimeState.logsDirectory,
            jobWorkerStatus: jobWorkerState.displayTitle,
            jobWorkerDesiredLanes: jobWorkerState.desiredLanes,
            jobWorkerRunningLanes: jobWorkerState.runningLanes,
            jobWorkerDetail: jobWorkerState.displayDetail,
            launcherStatus: launcherStatus,
            tools: toolStatuses.map { SupportToolSnapshot(name: $0.name, status: $0.statusTitle, detail: $0.detail) },
            latestOnlyMacsActivity: latestOnlyMacsActivity,
            localShareStatus: localShare.status,
            localEligibilityCode: localEligibilitySummary.code.rawValue,
            localEligibilityTitle: localEligibilitySummary.title,
            localEligibilityDetail: localEligibilitySummary.detail,
            localSharePublished: localShare.published,
            localShareServedSessions: localShare.servedSessions,
            localShareFailedSessions: localShare.failedSessions,
            localShareUploadedTokensEstimate: localShare.uploadedTokensEstimate,
            localShareLastServedModel: localShare.lastServedModel,
            activeReservations: snapshot.usage.activeReservations,
            reservationCap: snapshot.usage.reservationCap,
            bridgeStatusJSON: bridgeStatusJSON,
            localShareJSON: localShareJSON,
            swarmSessionsJSON: swarmSessionsJSON
        )
    }

    func fetchBridgeText(path: String) async -> String? {
        guard let url = bridgeURL(path: path) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func ensureRuntimeRunning() async {
        isRuntimeBusy = true
        defer { isRuntimeBusy = false }

        let settings = coordinatorSettings
        if let validationError = settings.validationError {
            runtimeState = LocalRuntimeState(
                status: "error",
                detail: validationError,
                logsDirectory: LocalRuntimeSupervisor.logsDirectoryURL.path,
                helperSource: runtimeState.helperSource,
                ollamaStatus: runtimeState.ollamaStatus,
                ollamaDetail: runtimeState.ollamaDetail,
                ollamaAppPath: runtimeState.ollamaAppPath
            )
            lastError = validationError
            return
        }

        runtimeState = await supervisor.ensureRunning(settings: settings)
        handleOllamaDependencyIfNeeded()
        if runtimeState.status != "ready" {
            lastError = runtimeState.detail
        }
    }

    func restartRuntime() async {
        isRuntimeBusy = true
        defer { isRuntimeBusy = false }

        let settings = coordinatorSettings
        if let validationError = settings.validationError {
            runtimeState = LocalRuntimeState(
                status: "error",
                detail: validationError,
                logsDirectory: LocalRuntimeSupervisor.logsDirectoryURL.path,
                helperSource: runtimeState.helperSource,
                ollamaStatus: runtimeState.ollamaStatus,
                ollamaDetail: runtimeState.ollamaDetail,
                ollamaAppPath: runtimeState.ollamaAppPath
            )
            lastError = validationError
            return
        }

        runtimeState = await supervisor.restart(settings: settings)
        handleOllamaDependencyIfNeeded()
        await refresh()
        if runtimeState.status != "ready" {
            lastError = runtimeState.detail
        }
    }

    func quitOnlyMacs() async {
        guard !isQuitting else { return }
        isQuitting = true
        refreshTask?.cancel()
        modelInstallTask?.cancel()
        await supervisor.stop()
        NSApp.terminate(nil)
    }

    func applyCoordinatorConnection() async {
        let settings = coordinatorSettings
        if let validationError = settings.validationError {
            lastError = validationError
            return
        }

        persistCoordinatorSettings(settings)
        appliedCoordinatorSettings = settings
        await restartRuntime()
    }

    func applyRuntime() async {
        guard let url = bridgeURL(path: "/admin/v1/runtime") else {
            lastError = "Bridge runtime URL is invalid."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            selectedMode = .both
            let body = try JSONEncoder().encode(BridgeRuntime(mode: AppMode.both.rawValue, activeSwarmID: selectedSwarmID))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                lastError = "Bridge rejected the runtime update."
                return
            }

            await refresh()
            hasManualSwarmSelectionDraft = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createSwarm() async {
        do {
            let response: SwarmCreateResponse = try await sendBridgeRequest(
                path: "/admin/v1/swarms/create",
                method: "POST",
                body: SwarmCreateRequest(
                    name: newSwarmName.trimmingCharacters(in: .whitespacesAndNewlines),
                    memberName: defaultMemberName,
                    mode: AppMode.both.rawValue
                )
            )
            latestInviteToken = response.invite.inviteToken
            latestInviteExpiresAt = response.invite.expiresAt
            inviteProgress = InviteProgress(
                token: response.invite.inviteToken,
                swarmID: response.swarm.id,
                swarmName: response.swarm.name,
                stage: .created,
                detail: appliedCoordinatorSettings.mode == .hostedRemote
                    ? "Invite is ready to share."
                    : "Invite is ready on this Mac. Switch to Hosted Remote before sharing it with a friend."
            )
            persistCachedInvite(
                token: response.invite.inviteToken,
                swarmID: response.swarm.id,
                swarmName: response.swarm.name,
                expiresAt: response.invite.expiresAt
            )
            joinInviteToken = ""
            selectedMode = .both
            hasCustomizedSetupSwarmChoice = false
            hasManualSwarmSelectionDraft = false
            selectedSwarmID = response.runtime.activeSwarmID
            if newSwarmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newSwarmName = response.swarm.name
            }
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createInvite() async {
        guard let inviteTargetSwarm else {
            lastError = "Connect to a private swarm before creating an invite."
            return
        }
        do {
            let response: InviteResponse = try await sendBridgeRequest(
                path: "/admin/v1/swarms/invite",
                method: "POST",
                body: SwarmInviteRequest(swarmID: inviteTargetSwarm.id)
            )
            latestInviteToken = response.invite.inviteToken
            latestInviteExpiresAt = response.invite.expiresAt
            inviteProgress = InviteProgress(
                token: response.invite.inviteToken,
                swarmID: response.invite.swarmID ?? inviteTargetSwarm.id,
                swarmName: response.invite.swarmName ?? inviteTargetSwarm.name,
                stage: .created,
                detail: appliedCoordinatorSettings.mode == .hostedRemote
                    ? "Invite is ready to share."
                    : "Invite is ready on this Mac. Switch to Hosted Remote before sharing it with a friend."
            )
            persistCachedInvite(
                token: response.invite.inviteToken,
                swarmID: response.invite.swarmID ?? inviteTargetSwarm.id,
                swarmName: response.invite.swarmName ?? inviteTargetSwarm.name,
                expiresAt: response.invite.expiresAt
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func joinSwarm() async {
        do {
            let response: SwarmJoinResponse = try await sendBridgeRequest(
                path: "/admin/v1/swarms/join",
                method: "POST",
                body: SwarmJoinRequest(
                    swarmID: selectedSwarmID,
                    inviteToken: joinInviteToken.trimmingCharacters(in: .whitespacesAndNewlines),
                    memberName: defaultMemberName,
                    mode: selectedMode.rawValue
                )
            )
            if let runtimeMode = AppMode(rawValue: response.runtime.mode) {
                selectedMode = runtimeMode
            }
            hasCustomizedSetupSwarmChoice = false
            hasManualSwarmSelectionDraft = false
            selectedSwarmID = response.runtime.activeSwarmID
            joinInviteToken = ""
            dismissedClipboardInviteToken = nil
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func publishThisMac() async {
        do {
            try await performPublishThisMacMutation()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unpublishThisMac() async {
        do {
            try await performUnpublishThisMacMutation()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func performPublishThisMacMutation() async throws {
        let _: ShareMutationResponse = try await sendBridgeRequest(
            path: "/admin/v1/share/publish",
            method: "POST",
            body: PublishShareRequest(slotsTotal: recommendedShareSlotCount(), modelIDs: nil)
        )
    }

    func updatePublishedMaintenanceState(_ maintenanceState: String) async {
        guard localShare.published else { return }
        let publishedModelIDs = localShare.publishedModels.map(\.id)
        do {
            let _: ShareMutationResponse = try await sendBridgeRequest(
                path: "/admin/v1/share/publish",
                method: "POST",
                body: PublishShareRequest(
                    slotsTotal: recommendedShareSlotCount(),
                    modelIDs: publishedModelIDs.isEmpty ? nil : publishedModelIDs,
                    maintenanceState: maintenanceState
                )
            )
            await refreshLocalShare()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func performUnpublishThisMacMutation() async throws {
        let _: ShareMutationResponse = try await sendBridgeRequest(
            path: "/admin/v1/share/unpublish",
            method: "POST",
            body: EmptyBridgeRequest()
        )
    }

    func refreshLocalShare() async {
        do {
            let status: LocalShareSnapshot = try await sendBridgeRequest(
                path: "/admin/v1/share/local",
                method: "GET",
                body: Optional<EmptyBridgeRequest>.none
            )
            if let pendingMemberNameConfirmation {
                localShare = status.withOptimisticProviderName(pendingMemberNameConfirmation)
            } else {
                localShare = status
            }
            initializeSessionUploadedTokensBaselineIfNeeded()
            updateStarterModelSetupFromLocalShare()
        } catch {
            localShare = .offline(message: error.localizedDescription)
        }
    }

    func initializeSessionSavedTokensBaselineIfNeeded() {
        if sessionSavedTokensBaseline == nil {
            sessionSavedTokensBaseline = snapshot.usage.tokensSavedEstimate
        }
    }

    func initializeSessionUploadedTokensBaselineIfNeeded() {
        if sessionUploadedTokensBaseline == nil {
            sessionUploadedTokensBaseline = localShare.uploadedTokensEstimate
        }
    }

    func reconcileConnectedSwarmSharingStateIfNeeded() async {
        guard !isReconcilingAutomaticSharingState else { return }

        guard let action = automaticSharingAction(
            selectedMode: selectedMode,
            runtimeStatus: runtimeState.status,
            activeSwarmID: snapshot.runtime.activeSwarmID,
            published: localShare.published,
            publishedSwarmID: localShare.activeSwarmID,
            discoveredModelCount: localShare.discoveredModels.count
        ) else {
            return
        }

        isReconcilingAutomaticSharingState = true
        defer { isReconcilingAutomaticSharingState = false }

        do {
            switch action {
            case .publish:
                try await performPublishThisMacMutation()
            case .unpublish:
                try await performUnpublishThisMacMutation()
            }
            await refreshLocalShare()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reconcileAutomaticJobWorkersIfNeeded() async {
        jobWorkerState = await supervisor.reconcileJobWorkers(policy: automaticJobWorkerPolicy())
    }

    func automaticJobWorkerPolicy() -> OnlyMacsJobWorkerSupervisorPolicy {
        let environment = ProcessInfo.processInfo.environment
        let normalizedRuntimeStatus = runtimeState.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedBridgeStatus = snapshot.bridge.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let activeSwarmID = (localShare.activeSwarmID.isEmpty ? snapshot.runtime.activeSwarmID : localShare.activeSwarmID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modelCount = max(localShare.discoveredModels.count, localShare.publishedModels.count)

        return OnlyMacsJobWorkerSupervisorPolicy(
            disabledByEnvironment: onlyMacsEnvironmentFlagIsEnabled(environment["ONLYMACS_DISABLE_JOB_WORKERS"]),
            runtimeReady: normalizedRuntimeStatus == "ready",
            bridgeReady: normalizedBridgeStatus == "ready",
            modeAllowsShare: selectedMode.allowsShare,
            published: localShare.published,
            activeSwarmID: activeSwarmID,
            activeSwarmIsPublic: activeRuntimeSwarm?.isPublic == true,
            discoveredModelCount: modelCount,
            unifiedMemoryGB: capabilitySnapshot.unifiedMemoryGB,
            publishedSlotCount: localShare.slots.total,
            activeLocalSessions: localShare.activeSessions,
            runtimeBusy: isRuntimeBusy,
            installingModels: isInstallingStarterModels,
            updateReadyOrInstalling: isUpdateReadyToInstallOnQuit || isInstallingUpdate,
            maxLanesOverride: parseOnlyMacsJobWorkerMaxLanes(environment["ONLYMACS_JOB_WORKER_MAX_LANES"])
        )
    }

    func recommendedShareSlotCount() -> Int {
        recommendedOnlyMacsShareSlotCount(
            unifiedMemoryGB: capabilitySnapshot.unifiedMemoryGB,
            currentSlots: localShare.slots.total
        )
    }

    func completeGuidedSetup() async {
        lastError = nil
        let installerManagedBootstrap = installerPackageSelections?.presentedByInstaller == true

        let requestedMemberName = memberNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requestedMemberName.isEmpty, requestedMemberName != snapshot.identity.memberName {
            await saveMemberName()
        }

        if setupSwarmChoice == .publicSwarm {
            selectedMode = .both
            _ = await adoptHostedCoordinatorForPublicSwarmIfNeeded(activeSwarmIsPublic: true)
        }

        if installerManagedBootstrap {
            launchAtLoginEnabled = setupLaunchAtLoginEnabled
            persistSetupLaunchAtLoginEnabled(setupLaunchAtLoginEnabled)
        } else {
            do {
                try LaunchAtLoginManager.setEnabled(setupLaunchAtLoginEnabled)
                launchAtLoginEnabled = setupLaunchAtLoginEnabled
                persistSetupLaunchAtLoginEnabled(setupLaunchAtLoginEnabled)
            } catch {
                lastError = error.localizedDescription
            }
        }

        if !installerManagedBootstrap {
            installLaunchersNow(targets: selectedSetupLauncherTargets.union([.core]))
        }
        await ensureRuntimeRunning()
        guard runtimeState.ollamaReady else {
            handleOllamaDependencyIfNeeded(force: true)
            lastError = runtimeState.ollamaDetail
            return
        }
        guard runtimeState.status == "ready" else { return }

        await refresh()
        refreshSetupDefaultsFromRuntime()

        switch setupSwarmChoice {
        case .publicSwarm:
            if let publicSwarm = snapshot.swarms.first(where: \.isPublic) {
                selectedSwarmID = publicSwarm.id
                if hasPendingRuntimeChanges {
                    await applyRuntime()
                } else {
                    await refresh()
                }
            }
        case .privateSwarm:
            newSwarmName = setupPrivateSwarmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "My Private Swarm"
                : setupPrivateSwarmName.trimmingCharacters(in: .whitespacesAndNewlines)
            await createSwarm()
        case .joinInvite:
            joinInviteToken = setupInviteTokenDraft
            await joinSwarm()
            setupInviteTokenDraft = ""
        }

        if hasPendingRuntimeChanges {
            await applyRuntime()
        } else {
            await refresh()
        }

        if !selectedInstallerModelIDs.isEmpty {
            installSelectedStarterModelsNow()
        } else {
            starterModelStatusDetail = selectedMode.allowsShare
                ? "OnlyMacs finished setup without downloading any models. Add at least one local model before this Mac can help the active swarm."
                : "OnlyMacs finished setup without downloading any models. You can add models later from Models."
            starterModelCompletionDetail = "OnlyMacs saved the defaults and will keep live status in the menu bar popup."
            persistStarterModelSetupCompleted(true)
        }

        if selectedMode.allowsShare, !localShare.published, !localShare.discoveredModels.isEmpty, !selectedSwarmID.isEmpty {
            await publishThisMac()
            await refresh()
        }
    }

    func installSelectedStarterModels() async {
        guard !modelDownloadQueue.items.isEmpty else {
            starterModelStatusDetail = "Choose at least one model first."
            return
        }

        starterModelCompletionDetail = nil
        isInstallingStarterModels = true
        defer { isInstallingStarterModels = false }

        await ensureRuntimeRunning()
        guard runtimeState.ollamaReady else {
            handleOllamaDependencyIfNeeded(force: true)
            starterModelStatusDetail = runtimeState.ollamaDetail
            lastError = runtimeState.ollamaDetail
            return
        }

        await updatePublishedMaintenanceState("installing_model")
        while !Task.isCancelled {
            do {
                guard let next = try modelDownloadQueue.startNextIfPossible() else {
                    break
                }

                guard let item = libraryModel(for: next.id) else {
                    try? modelDownloadQueue.markFailed(next.id, reason: "OnlyMacs lost track of this catalog entry.")
                    setInstallerQueueDetail(next.id, "OnlyMacs lost track of this catalog entry.")
                    continue
                }

                if modelIsInstalled(item) {
                    try? modelDownloadQueue.markReady(item.id)
                    setInstallerQueueDetail(item.id, "Already ready on this Mac.")
                    continue
                }

                starterModelStatusDetail = "Downloading \(Self.presentableModelName(item))…"
                let runtimeModelID = try await modelInstaller.pullModel(item) { progress in
                    Task { @MainActor in
                        self.setInstallerQueueDetail(item.id, progress.detail)
                    }
                }
                try modelDownloadQueue.markWarming(item.id)
                setInstallerQueueDetail(item.id, "Waiting for \(runtimeModelID) to appear in the local runtime.")

                let becameVisible = await waitForStarterModel(runtimeModelID)
                guard becameVisible else {
                    throw ModelInstallerServiceError.backendFailure("\(runtimeModelID) finished downloading, but OnlyMacs did not see it become available locally within 60 seconds.")
                }

                try modelDownloadQueue.markReady(item.id)
                setInstallerQueueDetail(item.id, "Ready on this Mac.")
                starterModelStatusDetail = "\(Self.presentableModelName(item)) is ready."
            } catch {
                let failingID = modelDownloadQueue.activeItem?.id
                if let failingID {
                    try? modelDownloadQueue.markFailed(failingID, reason: error.localizedDescription)
                    setInstallerQueueDetail(failingID, error.localizedDescription)
                }
                starterModelStatusDetail = error.localizedDescription
                lastError = error.localizedDescription
            }
        }
        await updatePublishedMaintenanceState("")

        let failedCount = modelDownloadQueue.items.filter { $0.phase == .failed }.count
        let readyCount = modelDownloadQueue.items.filter { $0.phase == .ready }.count
        starterModelStatusDetail = failedCount == 0 ? nil : "Some model installs failed. Review the model list and retry the failed items."
        if readyCount > 0 {
            starterModelCompletionDetail = readyCount == 1
                ? "That model is ready. Open the OnlyMacs menu bar icon next and this Mac will help the active swarm automatically while it stays connected."
                : "Your selected models are ready. Open the OnlyMacs menu bar icon next and this Mac will help the active swarm automatically while it stays connected."
        }
        persistStarterModelSetupCompleted(failedCount == 0 && readyCount > 0)
        await refresh()
        if failedCount == 0,
           readyCount > 0,
           selectedMode.allowsShare,
           !localShare.published,
           !selectedSwarmID.isEmpty
        {
            await publishThisMac()
            await refresh()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func waitForStarterModel(_ runtimeModelID: String) async -> Bool {
        for _ in 0..<30 {
            await refreshLocalShare()
            if localShare.discoveredModels.contains(where: { $0.id == runtimeModelID }) {
                return true
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return false
    }

    func makeReady() async {
        lastError = nil
        if !launcherStatus.installed {
            do {
                launcherStatus = try LauncherInstaller.installLaunchers()
            } catch {
                lastError = error.localizedDescription
            }
        }
        if launcherStatus.needsPathFix {
            do {
                launcherStatus = try LauncherInstaller.applyPathFix()
                refreshToolStatuses()
            } catch {
                lastError = error.localizedDescription
            }
        }
        if shouldReopenDetectedTools {
            reopenDetectedToolsNow()
        }
        await ensureRuntimeRunning()
        guard runtimeState.status == "ready" else { return }

        await refresh()

        if (snapshot.swarms.isEmpty || selectedSwarmID.isEmpty), let clipboardInviteToken {
            joinInviteToken = clipboardInviteToken
            await joinSwarm()
            await refresh()
        }

        if snapshot.swarms.isEmpty || selectedSwarmID.isEmpty {
            newSwarmName = selectedMode.defaultSwarmName
            await createSwarm()
        }

        if hasPendingRuntimeChanges {
            await applyRuntime()
        }

        await refresh()

        if appliedCoordinatorSettings.mode == .hostedRemote,
           !selectedSwarmID.isEmpty,
           latestInviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            await createInvite()
            await refresh()
        }

        if selectedMode.allowsShare, !localShare.published, !localShare.discoveredModels.isEmpty, !selectedSwarmID.isEmpty {
            await publishThisMac()
            await refresh()
        }

        if selectedMode.allowsShare, localShare.discoveredModels.isEmpty {
            lastError = runtimeState.ollamaReady
                ? "OnlyMacs will start helping the active swarm once this Mac has at least one local model available."
                : runtimeState.ollamaDetail
        }
    }

    func handleOllamaDependencyIfNeeded(force: Bool = false) {
        guard force || shouldBootstrapOllamaDependency else { return }
        guard force || !hasHandledOllamaDependencyThisLaunch else { return }

        switch runtimeState.ollamaStatus {
        case .missing:
            hasHandledOllamaDependencyThisLaunch = true
            installOllamaNow()
        case .installedButUnavailable:
            hasHandledOllamaDependencyThisLaunch = true
            launchOllamaNow()
        case .ready, .external:
            break
        }
    }

    func fixEverything() async {
        lastError = nil
        selfTestState = .idle
        do {
            launcherStatus = try LauncherInstaller.installLaunchers()
        } catch {
            lastError = error.localizedDescription
        }
        if launcherStatus.needsPathFix {
            do {
                launcherStatus = try LauncherInstaller.applyPathFix()
                refreshToolStatuses()
            } catch {
                lastError = error.localizedDescription
            }
        }
        if shouldReopenDetectedTools {
            reopenDetectedToolsNow()
        }
        runtimeState = await supervisor.restart(settings: coordinatorSettings)
        guard runtimeState.status == "ready" else {
            lastError = runtimeState.detail
            return
        }

        await refresh()

        if selectedSwarmID.isEmpty, let firstSwarm = snapshot.swarms.first {
            selectedSwarmID = firstSwarm.id
        }

        if hasPendingRuntimeChanges {
            await applyRuntime()
        }

        await refresh()

        if appliedCoordinatorSettings.mode == .hostedRemote,
           !selectedSwarmID.isEmpty,
           latestInviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            await createInvite()
            await refresh()
        }

        if selectedMode.allowsShare, !localShare.published, !localShare.discoveredModels.isEmpty, !selectedSwarmID.isEmpty {
            await publishThisMac()
            await refresh()
        }
    }

    func resetToSafeDefaults() async {
        if localShare.published {
            await unpublishThisMac()
        }

        selectedMode = .both
        selectedSwarmID = snapshot.swarms.first?.id ?? ""
        newSwarmName = ""
        joinInviteToken = ""
        latestInviteToken = ""
        latestInviteExpiresAt = nil
        clearCachedInvite()
        clipboardInviteToken = nil
        inviteProgress = nil
        dismissedClipboardInviteToken = nil
        selfTestState = .idle
        lastError = nil

        if !selectedSwarmID.isEmpty {
            await applyRuntime()
        } else {
            await refresh()
        }
    }

    func publishSuggestedModel(_ suggestion: ModelSummary) async {
        do {
            let selectedIDs = Array(Set(localShare.publishedModels.map(\.id) + [suggestion.id])).sorted()
            let _: ShareMutationResponse = try await sendBridgeRequest(
                path: "/admin/v1/share/publish",
                method: "POST",
                body: PublishShareRequest(slotsTotal: recommendedShareSlotCount(), modelIDs: selectedIDs)
            )
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func runSelfTest() async {
        selfTestState = .running("Checking local runtime.")
        await ensureRuntimeRunning()
        guard runtimeState.status == "ready" else {
            selfTestState = .failed(runtimeState.detail)
            return
        }

        await refresh()

        guard !selectedSwarmID.isEmpty else {
            selfTestState = .failed("No active swarm is selected. Press Make OnlyMacs Ready first.")
            return
        }

        if selectedMode.allowsShare, !localShare.published, !localShare.discoveredModels.isEmpty {
            selfTestState = .running("Publishing This Mac into the active swarm.")
            await publishThisMac()
            await refresh()
        }

        if selectedMode.allowsShare, localShare.discoveredModels.isEmpty {
            selfTestState = .failed("No local models are available on this Mac yet, so sharing cannot pass self-test.")
            return
        }

        if !selectedMode.allowsUse {
            selfTestState = localShare.published
                ? .passed("Sharing mode is healthy. Switch to Both or Use to test a live requester call.")
                : .failed("This Mac is not published yet.")
            return
        }

        selfTestState = .running("Checking swarm capacity.")
        do {
            let routeScope = preferredSelfTestRouteScope()
            let preflight: BridgePreflightResponse = try await sendBridgeRequest(
                path: "/admin/v1/preflight",
                method: "POST",
                body: BridgePreflightRequest(model: "", maxProviders: 1, routeScope: routeScope)
            )
            let effectiveRouteScope = preflight.routeScope ?? routeScope

            guard preflight.available, !preflight.resolvedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let fallbackModels = preflight.availableModels.map(\.name)
                if effectiveRouteScope == "local_only" {
                    if fallbackModels.isEmpty {
                        selfTestState = .failed("This Mac is not ready to satisfy a local-only request yet.")
                    } else {
                        selfTestState = .failed("This Mac can see \(fallbackModels.joined(separator: ", ")), but no local slot is free right now.")
                    }
                } else if fallbackModels.isEmpty {
                    selfTestState = .failed("No shared slot capacity is available in the active swarm yet.")
                } else {
                    selfTestState = .failed("No live capacity is free right now. Visible models: \(fallbackModels.joined(separator: ", ")).")
                }
                return
            }

            selfTestState = .running("Running a tiny live request with \(preflight.resolvedModel) on \(humanRouteScope(effectiveRouteScope)).")
            let passed = try await performSelfTestChat(model: preflight.resolvedModel, routeScope: effectiveRouteScope)
            selfTestState = passed
                ? .passed("OnlyMacs completed a live request on \(humanRouteScope(effectiveRouteScope)) using \(preflight.resolvedModel).")
                : .failed("The live request returned an unexpected response.")
        } catch {
            selfTestState = .failed(error.localizedDescription)
        }
    }

    func performSelfTestChat(model: String, routeScope: String) async throws -> Bool {
        guard let url = bridgeURL(path: "/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        let body = SelfTestChatRequest(
            model: model,
            stream: false,
            routeScope: routeScope,
            messages: [ChatMessage(role: "user", content: "Reply with ONLYMACS_SELF_TEST_OK exactly.")]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw BridgeRequestError(message: Self.errorMessage(from: data) ?? "Self-test request failed.")
        }

        let bodyText = String(data: data, encoding: .utf8) ?? ""
        return bodyText.contains("ONLYMACS_SELF_TEST_OK")
    }

    func preferredSelfTestRouteScope() -> String {
        if preferredRequestRoute != .automatic {
            return preferredRequestRoute.routeScope
        }
        if selectedMode.allowsShare, localShare.published, !localShare.discoveredModels.isEmpty {
            return "local_only"
        }
        return "swarm"
    }

    func humanRouteScope(_ routeScope: String) -> String {
        switch routeScope {
        case "local_only":
            return "This Mac only"
        case "trusted_only":
            return "your Macs only"
        default:
            return "the active swarm"
        }
    }

    func bridgeURL(path: String) -> URL? {
        URL(string: "http://127.0.0.1:4318\(path)")
    }

    func refreshToolStatuses() {
        toolStatuses = [
            DetectedTool.codex(launcherStatus: launcherStatus),
            DetectedTool.claude(launcherStatus: launcherStatus),
        ]
        refreshSetupLauncherSelections()
    }

    func refreshLatestOnlyMacsActivity() {
        let url = OnlyMacsCommandActivityStore.lastActivityURL()
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes?[.modificationDate] as? Date

        guard let modifiedAt else {
            latestOnlyMacsActivity = nil
            latestOnlyMacsActivityModifiedAt = nil
            return
        }
        if latestOnlyMacsActivityModifiedAt == modifiedAt {
            return
        }

        latestOnlyMacsActivity = OnlyMacsCommandActivityStore.loadLatest()
        latestOnlyMacsActivityModifiedAt = modifiedAt
    }

    func processOnlyMacsNotifications(
        previousSnapshot: BridgeStatusSnapshot,
        previousLocalShare: LocalShareSnapshot,
        previousActivity: OnlyMacsCommandActivity?
    ) async {
        let plans = OnlyMacsNotificationPlanner.plans(
            previousSessions: notificationSessionSnapshots(from: previousSnapshot.swarm.recentSessions),
            currentSessions: notificationSessionSnapshots(from: snapshot.swarm.recentSessions),
            previousShare: notificationShareSnapshot(from: previousLocalShare),
            currentShare: notificationShareSnapshot(from: localShare),
            previousActivity: notificationActivitySnapshot(from: previousActivity),
            currentActivity: notificationActivitySnapshot(from: latestOnlyMacsActivity)
        )

        guard notificationsPrimed else {
            notificationsPrimed = true
            return
        }
        guard onlyMacsNotificationsEnabled else { return }
        await notificationService.deliver(plans)
    }

    func notificationSessionSnapshots(from sessions: [SwarmSessionSnapshot]) -> [OnlyMacsNotificationSessionSnapshot] {
        sessions.map { session in
            OnlyMacsNotificationSessionSnapshot(
                id: session.id,
                title: session.title,
                status: session.status,
                resolvedModel: session.resolvedModel,
                routeSummary: session.routeSummary,
                warningMessage: sessionWarningMessage(session)
            )
        }
    }

    func notificationActivitySnapshot(from activity: OnlyMacsCommandActivity?) -> OnlyMacsNotificationActivitySnapshot? {
        guard let activity else { return nil }
        return OnlyMacsNotificationActivitySnapshot(
            title: activity.displayTitle,
            outcome: activity.outcome,
            detail: activity.detail,
            routeScope: activity.routeScope,
            model: activity.model
        )
    }

    func notificationShareSnapshot(from share: LocalShareSnapshot) -> OnlyMacsNotificationShareSnapshot {
        OnlyMacsNotificationShareSnapshot(
            published: share.published,
            activeSwarmName: share.activeSwarmName,
            activeSessions: share.activeSessions,
            servedSessions: share.servedSessions
        )
    }

    func humanOnlyMacsOutcome(_ outcome: String) -> String {
        switch outcome {
        case "planned":
            return "Planned"
        case "launched":
            return "Launched"
        case "streamed":
            return "Streamed"
        case "checked":
            return "Checked"
        case "preflighted":
            return "Preflighted"
        case "observed":
            return "Observed"
        case "paused":
            return "Paused"
        case "resumed":
            return "Resumed"
        case "cancelled":
            return "Stopped"
        case "failed":
            return "Needs Attention"
        default:
            return outcome.capitalized
        }
    }

    func refreshLauncherStatus() {
        let latestStatus = LauncherInstaller.status()
        if launcherStatus != latestStatus {
            launcherStatus = latestStatus
        }
        refreshToolStatuses()
        applyInstallerPackageSelectionsIfNeeded()
        focusSwarmsSectionIfNeeded(force: false)
    }

    func reloadInstallerRecommendations() {
        do {
            let catalog = try ModelCatalogLoader.loadBundled()
            let snapshot = ProviderCapabilitySnapshot(
                unifiedMemoryGB: Self.unifiedMemoryGB(),
                freeDiskGB: Self.availableDiskGB(at: NSHomeDirectory()) ?? 0
            )
            let assessment = ProviderCapabilityTiering.assess(snapshot)
            let plan = InstallerRecommendationEngine.plan(catalog: catalog, snapshot: snapshot)

            self.catalog = catalog
            self.capabilitySnapshot = snapshot
            self.capabilityAssessment = assessment
            self.installerPlan = plan
            let visibleIDs = Set<String>(catalog.models.compactMap { model in
                model.approximateRAMGB <= snapshot.unifiedMemoryGB ? model.id : nil
            })
            let installableIDs = Set<String>(catalog.models.compactMap { model in
                guard model.approximateRAMGB <= snapshot.unifiedMemoryGB,
                      model.proofRuntimeModelID != nil else { return nil }
                return model.id
            })
            let existingSelection = selectedInstallerModelIDs.intersection(visibleIDs).intersection(installableIDs)
            if existingSelection.isEmpty {
                selectedInstallerModelIDs = defaultInstallerSelectionIDs(for: plan)
            } else {
                selectedInstallerModelIDs = existingSelection
            }
            rebuildInstallerQueue()
            self.catalogError = nil
        } catch {
            self.catalog = nil
            self.installerPlan = nil
            self.catalogError = error.localizedDescription
            self.selectedInstallerModelIDs = []
            self.installerQueueDetails = [:]
            self.modelDownloadQueue = ModelDownloadQueue(modelIDs: [])
        }
        applyInstallerPackageSelectionsIfNeeded()
        focusSwarmsSectionIfNeeded(force: false)
    }

    func refreshSetupLauncherSelections() {
        let availableTargets = Set(setupLauncherOptions.filter(\.available).map(\.target))
        if installerPackageSelections != nil {
            selectedSetupLauncherTargets = selectedSetupLauncherTargets.intersection(availableTargets)
        } else if selectedSetupLauncherTargets.isEmpty {
            selectedSetupLauncherTargets = availableTargets
        } else {
            selectedSetupLauncherTargets = selectedSetupLauncherTargets.intersection(availableTargets)
        }
    }

    func refreshSetupDefaultsFromRuntime() {
        guard !hasCustomizedSetupSwarmChoice else { return }
        if let activeSwarm = activeRuntimeSwarm {
            setupSwarmChoice = activeSwarm.isPublic ? .publicSwarm : .privateSwarm
            if activeSwarm.isPublic {
                selectedMode = .both
            }
            if !activeSwarm.isPublic {
                setupPrivateSwarmName = activeSwarm.name
            }
        }
    }

    func setMemberNameDraftNow(_ name: String) {
        hasEditedMemberNameDraft = true
        memberNameDraft = name
    }

    func saveMemberName() async {
        let trimmed = memberNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "OnlyMacs name cannot be empty."
            return
        }
        let previousSnapshot = snapshot
        let previousLocalShare = localShare
        pendingMemberNameConfirmation = trimmed
        memberNameDraft = trimmed
        hasEditedMemberNameDraft = false
        persistCachedMemberName(trimmed)
        isSavingMemberName = true
        snapshot = snapshot.withOptimisticLocalMemberName(trimmed)
        localShare = localShare.withOptimisticProviderName(trimmed)
        lastError = nil
        defer { isSavingMemberName = false }

        do {
            let response: LocalIdentitySummary = try await sendBridgeRequest(
                path: "/admin/v1/identity",
                method: "POST",
                body: IdentityUpdateRequest(memberName: trimmed)
            )
            pendingMemberNameConfirmation = response.memberName
            memberNameDraft = response.memberName
            persistCachedMemberName(response.memberName)
            snapshot = snapshot.withOptimisticLocalMemberName(response.memberName)
            localShare = localShare.withOptimisticProviderName(response.memberName)
            hasEditedMemberNameDraft = false
            await refresh()
        } catch {
            pendingMemberNameConfirmation = nil
            snapshot = previousSnapshot
            localShare = previousLocalShare
            hasEditedMemberNameDraft = true
            lastError = error.localizedDescription
        }
    }

    func focusSwarmsSectionIfNeeded(force: Bool) {
        guard shouldAutoSelectSwarmsSection(
            force: force,
            shouldFocusSwarms: shouldAutoFocusSwarmsSection,
            currentSection: controlCenterSection,
            hasUserNavigatedPopupSectionsThisLaunch: hasUserNavigatedPopupSectionsThisLaunch
        ) else { return }

        if force {
            hasUserNavigatedPopupSectionsThisLaunch = false
        }
        showControlCenterSection(.swarms)
    }

    func maybeAutoBootstrapPopupExperience() {
        guard shouldAutoFocusSwarmsSection else { return }
        guard installerPlan != nil else { return }
        guard !automationModeEnabled else { return }
        guard pendingFileAccessApproval == nil else { return }
        guard !isCompletingGuidedSetup, !isInstallingStarterModels, !isRuntimeBusy else { return }
        guard !hasTriggeredAutomaticPopupBootstrapThisLaunch else { return }

        hasTriggeredAutomaticPopupBootstrapThisLaunch = true
        focusSwarmsSectionIfNeeded(force: launchRequestedSetupWindow || launchRequestedInstallerSelectionApply)
        completeGuidedSetupNow()
    }

    func activateMenuBarExperienceIfNeeded() {
        guard launchRequestedSetupWindow || launchRequestedInstallerSelectionApply || shouldPresentMenuBarRevealThisLaunch else { return }
        guard !hasActivatedMenuBarExperienceThisLaunch else { return }
        hasActivatedMenuBarExperienceThisLaunch = true
        focusSwarmsSectionIfNeeded(force: true)
        let didPresent = OnlyMacsStatusItemController.shared.presentPopover(forceActivate: true, section: controlCenterSection)
        if !didPresent {
            openSettingsWindowNow()
            return
        }
        userDefaults.set(true, forKey: Self.hasPresentedMenuBarRevealKey)
    }

    func handleInteractiveActivationIfNeeded() {
        guard !automationModeEnabled else { return }
        guard !hasHandledInteractiveActivationThisLaunch else { return }
        guard pendingFileAccessApproval == nil else { return }
        guard !isFileApprovalWindowVisible else { return }
        guard NSApp.windows.allSatisfy({ !$0.isVisible }) else { return }
        guard !OnlyMacsStatusItemController.shared.isPopoverShown else { return }

        hasHandledInteractiveActivationThisLaunch = true
        let didPresent = OnlyMacsStatusItemController.shared.presentPopover(forceActivate: false, section: controlCenterSection)
        if !didPresent {
            openSettingsWindowNow()
        }
    }

    func rememberFinalizedFileAccessRequest(id: String) {
        pruneFinalizedFileAccessRequests()
        finalizedFileAccessRequestIDs[id] = Date()
    }

    func pruneFinalizedFileAccessRequests() {
        let cutoff = Date().addingTimeInterval(-120)
        finalizedFileAccessRequestIDs = finalizedFileAccessRequestIDs.filter { $0.value >= cutoff }
    }

    func applyInstallerPackageSelectionsIfNeeded() {
        guard let installerPackageSelections else { return }
        guard !hasCompletedStarterModelSetup else { return }

        if !hasAppliedInstallerSelectionDefaults {
            selectedMode = .both
            setupLaunchAtLoginEnabled = installerPackageSelections.runOnStartup
            let availableTargets = Set(setupLauncherOptions.filter(\.available).map(\.target))
            selectedSetupLauncherTargets = installerPackageSelections.requestedLauncherTargets.intersection(availableTargets)

            if !hasCustomizedSetupSwarmChoice {
                if installerPackageSelections.joinPublicSwarm {
                    setupSwarmChoice = .publicSwarm
                } else if setupSwarmChoice == .publicSwarm {
                    setupSwarmChoice = .privateSwarm
                }
            }
            hasAppliedInstallerSelectionDefaults = true
        }

        guard !hasAppliedInstallerModelDefaults else { return }

        if installerPackageSelections.installStarterModels {
            guard installerPlan != nil else { return }
            if selectedInstallerModelIDs.isEmpty {
                selectedInstallerModelIDs = defaultInstallerSelectionIDs()
            }
        } else {
            selectedInstallerModelIDs = []
        }
        rebuildInstallerQueue()
        hasAppliedInstallerModelDefaults = true
    }

    func defaultInstallerSelectionIDs(for plan: InstallerRecommendationPlan? = nil) -> Set<String> {
        let sourcePlan = plan ?? installerPlan
        return Set(sourcePlan?.selectedModels.compactMap { item in
            item.model.proofRuntimeModelID == nil ? nil : item.id
        } ?? [])
    }

    func orderedSelectedInstallerItems(needingInstallOnly: Bool = false) -> [InstallerRecommendationItem] {
        setupVisibleModelRecommendations.filter { item in
            guard selectedInstallerModelIDs.contains(item.id) else { return false }
            return !needingInstallOnly || !installerItemIsInstalled(item)
        }
    }

    func rebuildInstallerQueue() {
        let orderedIDs = orderedSelectedInstallerItems(needingInstallOnly: true).map(\.id)
        modelDownloadQueue = ModelDownloadQueue(modelIDs: orderedIDs)
        installerQueueDetails = installerQueueDetails.filter { orderedIDs.contains($0.key) }
    }

    func installerItemIsInstalled(_ item: InstallerRecommendationItem) -> Bool {
        modelIsInstalled(item.model)
    }

    func updateStarterModelSetupFromLocalShare() {
        guard installerPlan != nil else { return }

        let discoveredIDs = Set(localShare.discoveredModels.map(\.id))
        let allSelectedAvailable = orderedSelectedInstallerItems().allSatisfy { item in
            guard let runtimeModelID = item.model.proofRuntimeModelID else { return false }
            return discoveredIDs.contains(runtimeModelID)
        }

        if !isInstallingStarterModels && allSelectedAvailable && !orderedSelectedInstallerItems().isEmpty {
            starterModelCompletionDetail = "Your selected models are ready. Open the OnlyMacs menu bar icon next and this Mac will help the active swarm automatically while it stays connected."
            starterModelStatusDetail = nil
            persistStarterModelSetupCompleted(true)
        }
        focusSwarmsSectionIfNeeded(force: false)
    }

    func scanClipboardForInvite() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string),
              let token = InviteLinkPayload.parse(text)?.inviteToken
        else {
            return
        }

        guard token != dismissedClipboardInviteToken,
              token != latestInviteToken,
              token != joinInviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return
        }

        clipboardInviteToken = token
    }

    func updateInviteProgress() {
        guard var inviteProgress else { return }
        guard let swarm = snapshot.swarms.first(where: { $0.id == inviteProgress.swarmID }) else {
            self.inviteProgress = inviteProgress
            return
        }

        if swarm.memberCount > 1 {
            inviteProgress.stage = .joined
            inviteProgress.detail = "A friend joined \(swarm.name)."
        }
        if swarm.slotsTotal > 0 && swarm.memberCount > 1 {
            inviteProgress.stage = .ready
            inviteProgress.detail = "The shared swarm now has live slot capacity."
        }
        self.inviteProgress = inviteProgress
    }

    func markInviteShared(stage: InviteProgressStage, detail: String) {
        guard var inviteProgress else { return }
        inviteProgress.stage = stage
        inviteProgress.detail = detail
        self.inviteProgress = inviteProgress
    }

    func sendBridgeRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        guard let url = bridgeURL(path: path) else {
            throw URLError(.badURL)
        }

        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw BridgeRequestError(message: Self.errorMessage(from: data) ?? "Bridge request failed.")
        }

        return try decoder.decode(Response.self, from: data)
    }

    static func errorMessage(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(BridgeErrorEnvelope.self, from: data) {
            return payload.error.message
        }
        return String(data: data, encoding: .utf8)
    }

    static func unifiedMemoryGB() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    static func availableDiskGB(at path: String) -> Int? {
        guard let freeBytes = try? FileManager.default.attributesOfFileSystem(forPath: path)[.systemFreeSize] as? NSNumber else {
            return nil
        }
        return Int(truncating: freeBytes) / 1_073_741_824
    }

    static func formatSavedTokens(_ tokens: Int) -> String {
        let safeTokens = max(0, tokens)
        switch safeTokens {
        case 0:
            return "0"
        case 1 ..< 10_000:
            return safeTokens.formatted(.number.grouping(.automatic))
        case 10_000 ..< 1_000_000:
            let rounded = (safeTokens / 10_000) * 10_000
            return "\(rounded / 1_000)K+"
        case 1_000_000 ..< 10_000_000:
            return "\(safeTokens / 1_000_000)M+"
        case 10_000_000 ..< 1_000_000_000:
            return "\(safeTokens / 1_000_000)M"
        default:
            let billions = Double(safeTokens) / 1_000_000_000
            return String(format: "%.2fB", billions)
        }
    }

    static func loadCoordinatorSettings() -> CoordinatorConnectionSettings {
        guard let data = UserDefaults.standard.data(forKey: coordinatorSettingsKey),
              let settings = try? JSONDecoder().decode(CoordinatorConnectionSettings.self, from: data)
        else {
            return resolveStoredCoordinatorSettings(nil, buildInfo: BuildInfo.current)
        }
        let resolved = resolveStoredCoordinatorSettings(settings, buildInfo: BuildInfo.current)
        if resolved != settings,
           let data = try? JSONEncoder().encode(resolved) {
            UserDefaults.standard.set(data, forKey: coordinatorSettingsKey)
        }
        return resolved
    }

    static func resolveStoredCoordinatorSettings(_ storedSettings: CoordinatorConnectionSettings?, buildInfo: BuildInfo) -> CoordinatorConnectionSettings {
        if let storedSettings {
            if storedCoordinatorShouldUpgradeToPackagedHosted(storedSettings) {
                return buildInfo.preferredCoordinatorSettings ?? CoordinatorConnectionSettings()
            }
            return storedSettings
        }
        return buildInfo.preferredCoordinatorSettings ?? CoordinatorConnectionSettings()
    }

    private static func storedCoordinatorShouldUpgradeToPackagedHosted(_ settings: CoordinatorConnectionSettings) -> Bool {
        if settings.mode == .embeddedLocal || settings.normalizedRemoteCoordinatorURL == nil {
            return true
        }
        let effectiveURL = settings.effectiveCoordinatorURL
        guard let url = URL(string: effectiveURL),
              let host = url.host?.lowercased()
        else {
            return false
        }
        return host == "127.0.0.1"
            || host == "localhost"
            || (host.hasPrefix("onlymacs-coordinator-") && host.hasSuffix(".up.railway.app"))
    }

    static func loadPreferredRequestRoute() -> PreferredRequestRoute {
        guard let rawValue = UserDefaults.standard.string(forKey: preferredRequestRouteKey),
              let route = PreferredRequestRoute(rawValue: rawValue)
        else {
            return .automatic
        }
        return route
    }

    func persistCoordinatorSettings(_ settings: CoordinatorConnectionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: Self.coordinatorSettingsKey)
    }

    @discardableResult
    func adoptHostedCoordinatorForPublicSwarmIfNeeded(activeSwarmIsPublic: Bool) async -> Bool {
        guard shouldAdoptHostedCoordinatorForPublicSwarm(
            currentSettings: appliedCoordinatorSettings,
            activeSwarmIsPublic: activeSwarmIsPublic,
            buildInfo: buildInfo
        ) else {
            return false
        }
        guard let packagedHosted = buildInfo.preferredCoordinatorSettings else {
            return false
        }

        persistCoordinatorSettings(packagedHosted)
        appliedCoordinatorSettings = packagedHosted
        coordinatorConnectionMode = packagedHosted.mode
        coordinatorURLDraft = packagedHosted.remoteCoordinatorURL
        await restartRuntime()
        await refresh()
        return true
    }

    func persistStarterModelSetupCompleted(_ completed: Bool) {
        hasCompletedStarterModelSetup = completed
        userDefaults.set(completed, forKey: Self.starterModelSetupCompletedKey)
    }

    func persistSetupLaunchAtLoginEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Self.setupLaunchAtLoginKey)
    }

    func installerSelectionSignatureAlreadyApplied(_ signature: String) -> Bool {
        userDefaults.string(forKey: Self.appliedInstallerSelectionSignatureKey) == signature
    }

    func persistAppliedInstallerSelectionSignature(_ signature: String) {
        userDefaults.set(signature, forKey: Self.appliedInstallerSelectionSignatureKey)
    }
}
