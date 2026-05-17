import Foundation
import OnlyMacsCore
import Testing
@testable import OnlyMacsApp

struct OnlyMacsAppStatePresentationTests {
    @Test
    func swarmsAutofocusStopsAfterManualPopupNavigation() {
        #expect(
            shouldAutoSelectSwarmsSection(
                force: false,
                shouldFocusSwarms: true,
                currentSection: .swarms,
                hasUserNavigatedPopupSectionsThisLaunch: true
            ) == false
        )

        #expect(
            shouldAutoSelectSwarmsSection(
                force: true,
                shouldFocusSwarms: false,
                currentSection: .models,
                hasUserNavigatedPopupSectionsThisLaunch: true
            ) == true
        )
    }

    @Test
    func automaticPopupBootstrapCanRetryWhenOllamaBecomesReady() {
        #expect(shouldResetAutomaticPopupBootstrapAfterRuntimeTransition(
            previousOllamaReady: false,
            currentOllamaReady: true,
            hasCompletedStarterModelSetup: false
        ) == true)
        #expect(shouldResetAutomaticPopupBootstrapAfterRuntimeTransition(
            previousOllamaReady: false,
            currentOllamaReady: false,
            hasCompletedStarterModelSetup: false
        ) == false)
        #expect(shouldResetAutomaticPopupBootstrapAfterRuntimeTransition(
            previousOllamaReady: false,
            currentOllamaReady: true,
            hasCompletedStarterModelSetup: true
        ) == false)
    }

    @Test
    func controlCenterSectionsDoNotExposeRemovedReadyNav() {
        let rawValues = Set(ControlCenterSection.allCases.map(\.rawValue))
        let titles = Set(ControlCenterSection.allCases.map(\.title))

        #expect(!rawValues.contains("setup"))
        #expect(!titles.contains("Ready"))
        #expect(!titles.contains("Readiness"))
    }

    @Test
    func controlCenterSectionsExposeCurrentSwarmNav() {
        let rawValues = Set(ControlCenterSection.allCases.map(\.rawValue))
        let titles = Set(ControlCenterSection.allCases.map(\.title))

        #expect(rawValues.contains("currentSwarm"))
        #expect(titles.contains("Current Swarm"))
    }

    @Test
    func displayableBridgeErrorRequiresDegradedStatus() {
        #expect(displayableBridgeError(status: "ready", error: "Get /admin/v1/swarms: context deadline exceeded") == nil)
        #expect(displayableBridgeError(status: "degraded", error: "Get /admin/v1/swarms: context deadline exceeded") == "Get /admin/v1/swarms: context deadline exceeded")
        #expect(displayableBridgeError(status: "error", error: "  Bridge failed  ") == "Bridge failed")
        #expect(displayableBridgeError(status: "degraded", error: "   ") == nil)
    }

    @Test
    func publicSwarmJoinPolicyDecodesWhenOptionalFieldsAreMissing() throws {
        let json = Data(#"""
        {
          "id": "swarm-public",
          "name": "OnlyMacs Public",
          "slug": "onlymacs",
          "public_path": "/swarms/public/onlymacs",
          "visibility": "public",
          "discoverability": "listed",
          "join_policy": {
            "version": 1,
            "mode": "open"
          },
          "member_count": 1,
          "slots_free": 1,
          "slots_total": 1
        }
        """#.utf8)

        let swarm = try JSONDecoder().decode(SwarmOption.self, from: json)

        #expect(swarm.id == "swarm-public")
        #expect(swarm.joinPolicy.mode == "open")
        #expect(swarm.joinPolicy.passwordConfigured == false)
        #expect(swarm.joinPolicy.allowedEmails.isEmpty)
        #expect(swarm.joinPolicy.allowedDomains.isEmpty)
        #expect(swarm.joinPolicy.requireApproval == false)
    }

    @Test
    func transientCoordinatorRefreshMissKeepsLastConnectedSnapshot() {
        var previous = BridgeStatusSnapshot.placeholder
        previous.bridge = BridgeSummary(
            status: "ready",
            coordinatorURL: "https://onlymacs.ai",
            activeSwarmName: "OnlyMacs Public",
            error: nil
        )
        previous.runtime = BridgeRuntime(mode: "both", activeSwarmID: "swarm-public")
        previous.lastUpdated = Date()

        #expect(
            shouldPreserveBridgeSnapshotAfterTransientRefreshFailure(
                previousSnapshot: previous,
                runtimeStatus: "ready",
                errorMessage: #"Get "https://onlymacs.ai/admin/v1/swarms": context deadline exceeded"#
            ) == true
        )
        #expect(
            shouldPreserveBridgeSnapshotAfterTransientRefreshFailure(
                previousSnapshot: previous,
                runtimeStatus: "ready",
                errorMessage: "Bridge returned HTTP 502."
            ) == true
        )
        #expect(
            shouldPreserveBridgeSnapshotAfterTransientRefreshFailure(
                previousSnapshot: previous,
                runtimeStatus: "ready",
                errorMessage: "Could not connect to the server."
            ) == false
        )

        previous.bridge = BridgeSummary(
            status: "degraded",
            coordinatorURL: "https://onlymacs.ai",
            activeSwarmName: "OnlyMacs Public",
            error: "Bridge failed"
        )
        #expect(
            shouldPreserveBridgeSnapshotAfterTransientRefreshFailure(
                previousSnapshot: previous,
                runtimeStatus: "ready",
                errorMessage: "The request timed out."
            ) == false
        )
    }

    @Test
    func activeRuntimeSwarmFallsBackToBridgeSwarmNameWhenSwarmsAreTemporarilyMissing() {
        let fallback = activeRuntimeSwarmOption(
            swarms: [],
            activeSwarmID: "swarm-public",
            activeSwarmName: "OnlyMacs Public",
            swarm: SwarmCapacitySummary(slotsFree: 2, slotsTotal: 2, modelCount: 11, activeSessionCount: 0),
            memberCount: 2
        )

        #expect(fallback?.id == "swarm-public")
        #expect(fallback?.name == "OnlyMacs Public")
        #expect(fallback?.isPublic == true)
        #expect(fallback?.memberCount == 2)
        #expect(fallback?.slotsTotal == 2)
    }

    @Test
    func unavailableActiveSwarmFallsBackToPublicSwarmWhenSwarmListIsKnown() {
        let publicSwarm = SwarmOption(
            id: "swarm-public",
            name: "OnlyMacs Public",
            visibility: "public",
            memberCount: 0,
            slotsFree: 0,
            slotsTotal: 0
        )
        let privateSwarm = SwarmOption(
            id: "swarm-private",
            name: "Private",
            visibility: "private",
            memberCount: 0,
            slotsFree: 0,
            slotsTotal: 0
        )

        #expect(
            replacementActiveSwarmIDForUnavailableActiveSwarm(
                activeSwarmID: "swarm-000001",
                swarms: [publicSwarm, privateSwarm]
            ) == "swarm-public"
        )
        #expect(
            replacementActiveSwarmIDForUnavailableActiveSwarm(
                activeSwarmID: "swarm-private",
                swarms: [publicSwarm, privateSwarm]
            ) == nil
        )
        #expect(
            replacementActiveSwarmIDForUnavailableActiveSwarm(
                activeSwarmID: "swarm-000001",
                swarms: []
            ) == nil
        )
    }

    @Test
    func settingsPanesStayCondensed() {
        let titles = SettingsPane.allCases.map(\.title)

        #expect(titles == ["Coordinator", "Updates", "Basic Settings"])
        #expect(!titles.contains("Identity"))
        #expect(!titles.contains("Startup"))
    }

    @Test
    func tierTwoModelListShows128GBPowerModelsFirst() throws {
        let catalog = try ModelCatalogLoader.loadBundled()
        let plan = InstallerRecommendationEngine.plan(
            catalog: catalog,
            snapshot: ProviderCapabilitySnapshot(unifiedMemoryGB: 128, freeDiskGB: 500),
            reserveFloorGB: 120
        )
        let recommendedIDs = Set(plan.selectedModels.map(\.id))
        let visibleModels = catalog.models.filter { $0.approximateRAMGB <= 128 }
        let sortedIDs = visibleModels.sorted { lhs, rhs in
            compareLibraryModelsForDisplay(
                lhs,
                rhs,
                lhsInstalled: false,
                rhsInstalled: false,
                lhsRecommended: recommendedIDs.contains(lhs.id),
                rhsRecommended: recommendedIDs.contains(rhs.id),
                prioritize128GBOnlyPowerModels: true
            )
        }.map(\.id)

        let expectedPowerPrefix = [
            "gpt-oss-120b-mxfp4",
            "qwen25-72b-q4km",
            "deepseek-r1-70b-q4km",
            "llama31-70b-q4km",
        ]

        #expect(Array(sortedIDs.prefix(expectedPowerPrefix.count)) == expectedPowerPrefix)
        #expect(expectedPowerPrefix.allSatisfy { id in
            catalog.models.first(where: { $0.id == id }).map(modelIs128GBOnlyPowerModel) == true
        })
        #expect(modelLibraryGroupOrder(prioritizesPowerModels: true).firstIndex(of: .readyToAdd)! < modelLibraryGroupOrder(prioritizesPowerModels: true).firstIndex(of: .biggerModels)!)
        #expect(modelLibraryGroupOrder(prioritizesPowerModels: false).firstIndex(of: .readyToAdd)! < modelLibraryGroupOrder(prioritizesPowerModels: false).firstIndex(of: .biggerModels)!)
    }

    @Test
    func optimisticMemberNameUpdatesLocalRowsWhileCoordinatorCatchesUp() {
        let capability = SwarmMemberCapabilitySummary(
            providerID: "provider-local",
            providerName: "Xray-India",
            status: "available",
            maintenanceState: nil,
            activeSessions: 0,
            activeModel: nil,
            slots: Slots(free: 1, total: 1),
            modelCount: 1,
            bestModel: "qwen",
            recentUploadedTokensPerSecond: nil,
            hardware: nil,
            clientBuild: nil,
            models: []
        )
        let member = SwarmMemberSummary(
            memberID: "member-local",
            memberName: "Xray-India",
            mode: "both",
            swarmID: "swarm-public",
            status: "available",
            maintenanceState: nil,
            lastSeenAt: nil,
            providerCount: 1,
            activeJobsServing: 0,
            activeJobsConsuming: 0,
            activeModel: nil,
            recentUploadedTokensPerSecond: nil,
            totalModelsAvailable: 1,
            bestModel: "qwen",
            hardware: nil,
            clientBuild: nil,
            capabilities: [capability]
        )
        let provider = ProviderSummary(
            id: "provider-local",
            name: "Xray-India",
            ownerMemberID: "member-local",
            ownerMemberName: "Xray-India",
            status: "available",
            maintenanceState: nil,
            activeSessions: 0,
            activeModel: nil,
            slots: Slots(free: 1, total: 1),
            hardware: nil,
            clientBuild: nil,
            models: []
        )
        let snapshot = BridgeStatusSnapshot(
            bridge: BridgeSummary(status: "ready", coordinatorURL: nil, activeSwarmName: "OnlyMacs Public", error: nil),
            runtime: BridgeRuntime(mode: "both", activeSwarmID: "swarm-public"),
            identity: LocalIdentitySummary(
                memberID: "member-local",
                memberName: "Xray-India",
                providerID: "provider-local",
                providerName: "Xray-India"
            ),
            modes: ["both"],
            swarms: [],
            swarm: SwarmCapacitySummary(slotsFree: 1, slotsTotal: 1, modelCount: 1, activeSessionCount: 0),
            usage: BridgeStatusSnapshot.placeholder.usage,
            providers: [provider],
            members: [member],
            models: [],
            lastUpdated: nil
        ).withOptimisticLocalMemberName("Kevin")

        #expect(snapshot.identity.memberName == "Kevin")
        #expect(snapshot.identity.providerName == "Kevin")
        #expect(snapshot.providers.first?.name == "Kevin")
        #expect(snapshot.providers.first?.ownerMemberName == "Kevin")
        #expect(snapshot.members.first?.memberName == "Kevin")
        #expect(snapshot.members.first?.capabilities.first?.providerName == "Kevin")
    }

    @Test
    func swarmMemberServingStatusIncludesModelAndTokenRate() {
        let member = SwarmMemberSummary(
            memberID: "member-studio",
            memberName: "StudioHost",
            mode: "both",
            swarmID: "swarm-public",
            status: "serving",
            maintenanceState: nil,
            lastSeenAt: nil,
            providerCount: 1,
            activeJobsServing: 1,
            activeJobsConsuming: 0,
            activeModel: "qwen3.6:35b-a3b-q8_0",
            recentUploadedTokensPerSecond: 17.2,
            totalModelsAvailable: 7,
            bestModel: "qwen3.6:35b-a3b-q8_0",
            hardware: nil,
            clientBuild: nil,
            capabilities: []
        )

        #expect(member.statusTitle == "Serving (qwen3.6:35b-a3b-q8_0, 17 tokens/s)")
        #expect(member.isActiveInSwarm == true)
        #expect(member.isAvailableInSwarm == true)
    }

    @Test
    func swarmMemberMaintenanceStatusIsReadable() {
        let member = SwarmMemberSummary(
            memberID: "member-installing",
            memberName: "Installing Mac",
            mode: "both",
            swarmID: "swarm-public",
            status: "installing_model",
            maintenanceState: "installing_model",
            lastSeenAt: nil,
            providerCount: 1,
            activeJobsServing: 0,
            activeJobsConsuming: 0,
            activeModel: nil,
            recentUploadedTokensPerSecond: nil,
            totalModelsAvailable: 7,
            bestModel: "qwen3.6:35b-a3b-q8_0",
            hardware: nil,
            clientBuild: nil,
            capabilities: []
        )

        #expect(member.statusTitle == "Installing Model")
        #expect(member.isAvailableInSwarm == true)
    }

    @Test
    func popupAndShellFilesDoNotContainOldReadyStrings() throws {
        let forbidden = [
            "Getting Ready",
            "Readiness",
            "Ready To Use",
            "Get Ready",
            "Make Ready",
        ]
        let paths = [
            "Sources/OnlyMacsApp/OnlyMacsShell.swift",
            "Sources/OnlyMacsApp/OnlyMacsShellViews.swift",
            "Sources/OnlyMacsApp/OnlyMacsPopupViews.swift",
        ]

        for path in paths {
            let contents = try Self.packageFileContents(path)
            for phrase in forbidden {
                #expect(!contents.contains(phrase), "Found forbidden phrase '\(phrase)' in \(path)")
            }
        }
    }

    @Test
    func publicPopupAndShellDoNotRenderRuntimeDiagnosticsPanel() throws {
        let paths = [
            "Sources/OnlyMacsApp/OnlyMacsShellViews.swift",
            "Sources/OnlyMacsApp/OnlyMacsPopupViews.swift",
        ]

        for path in paths {
            let contents = try Self.packageFileContents(path)
            #expect(!contents.contains("RuntimeDiagnosticsPanel("), "Found public runtime diagnostics panel in \(path)")
            #expect(!contents.contains("Runtime Status"), "Found runtime status copy in \(path)")
        }
    }

    @Test
    func publicSwarmBadgeUsesPublicLabel() {
        let swarm = SwarmOption(
            id: "swarm-public",
            name: "OnlyMacs Public",
            visibility: "public",
            memberCount: 2,
            slotsFree: 1,
            slotsTotal: 2
        )

        #expect(swarm.visibilityBadgeTitle == "Public")
        #expect(swarm.pickerTitle.contains("(public)"))
    }

    @Test
    func connectedSwarmHeadlineShowsMembersAndSlots() {
        let swarm = SwarmOption(
            id: "swarm-public",
            name: "OnlyMacs Public",
            visibility: "public",
            memberCount: 2,
            slotsFree: 2,
            slotsTotal: 2
        )

        #expect(swarm.connectedHeadlineTitle == "OnlyMacs Public (2 members, 2 slots)")
    }

    @Test
    func connectedSwarmHeadlineFallsBackToNameWithoutLiveCounts() {
        let swarm = SwarmOption(
            id: "swarm-public",
            name: "OnlyMacs Public",
            visibility: "public",
            memberCount: 0,
            slotsFree: 0,
            slotsTotal: 0
        )

        #expect(swarm.connectedHeadlineTitle == "OnlyMacs Public")
    }

    @Test
    func recentSwarmsExcludeConnectedSwarmAndHideWhenEmpty() {
        let publicSwarm = SwarmOption(
            id: "swarm-public",
            name: "OnlyMacs Public",
            visibility: "public",
            memberCount: 2,
            slotsFree: 1,
            slotsTotal: 2
        )
        let privateSwarm = SwarmOption(
            id: "swarm-private",
            name: "Investor Private",
            visibility: "private",
            memberCount: 1,
            slotsFree: 1,
            slotsTotal: 1
        )

        #expect(recentSwarmConnectionSwarms(swarms: [publicSwarm], activeSwarmID: "swarm-public").isEmpty)
        #expect(recentSwarmConnectionSwarms(swarms: [publicSwarm, privateSwarm], activeSwarmID: "swarm-public").map(\.id) == ["swarm-private"])
        #expect(recentSwarmConnectionSwarms(swarms: [privateSwarm, publicSwarm], activeSwarmID: "").map(\.id) == ["swarm-public", "swarm-private"])
    }

    @Test
    func automaticSharingPublishesWhenConnectedAndEligible() {
        #expect(
            automaticSharingAction(
                selectedMode: .both,
                runtimeStatus: "ready",
                activeSwarmID: "swarm-123",
                published: false,
                publishedSwarmID: "",
                discoveredModelCount: 1
            ) == .publish
        )
    }

    @Test
    func automaticSharingUnpublishesWhenNoSwarmRemains() {
        #expect(
            automaticSharingAction(
                selectedMode: .both,
                runtimeStatus: "ready",
                activeSwarmID: "",
                published: true,
                publishedSwarmID: "swarm-123",
                discoveredModelCount: 1
            ) == .unpublish
        )
    }

    @Test
    func automaticJobWorkerPolicyUsesRamAwareLaneCeilings() {
        let mac64 = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            unifiedMemoryGB: 64,
            publishedSlotCount: 4
        ))
        let mac128 = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            unifiedMemoryGB: 128,
            publishedSlotCount: 4
        ))
        let mac256 = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            unifiedMemoryGB: 256,
            publishedSlotCount: 8
        ))

        #expect(mac64.desiredLanes == 1)
        #expect(mac128.desiredLanes == 2)
        #expect(mac256.desiredLanes == 4)
    }

    @Test
    func automaticJobWorkerPolicyKeeps32GBToOneLaneAndStopsBelowFloor() {
        let mac32 = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            unifiedMemoryGB: 32,
            publishedSlotCount: 4
        ))
        let mac16 = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            unifiedMemoryGB: 16,
            publishedSlotCount: 4
        ))

        #expect(mac32.desiredLanes == 1)
        #expect(mac16.desiredLanes == 0)
        #expect(mac16.stopReason?.contains("32 GB worker floor") == true)
    }

    @Test
    func automaticJobWorkerPolicyRespectsPublicAndPrivateSafety() {
        let publicPlan = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-public",
            activeSwarmIsPublic: true,
            unifiedMemoryGB: 128,
            publishedSlotCount: 2
        ))
        let privatePlan = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            activeSwarmIsPublic: false,
            unifiedMemoryGB: 128,
            publishedSlotCount: 2
        ))

        #expect(publicPlan.desiredLanes == 2)
        #expect(publicPlan.allowTests == false)
        #expect(privatePlan.desiredLanes == 2)
        #expect(privatePlan.allowTests == true)
    }

    @Test
    func automaticJobWorkerPolicyStopsWhenMacIsNotActuallyReadyToWork() {
        let notPublished = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            published: false,
            activeSwarmID: "swarm-private",
            unifiedMemoryGB: 128,
            publishedSlotCount: 2
        ))
        let noModel = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            discoveredModelCount: 0,
            unifiedMemoryGB: 128,
            publishedSlotCount: 2
        ))
        let updateReady = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            unifiedMemoryGB: 128,
            publishedSlotCount: 2,
            updateReadyOrInstalling: true
        ))

        #expect(notPublished.desiredLanes == 0)
        #expect(noModel.desiredLanes == 0)
        #expect(updateReady.desiredLanes == 0)
    }

    @Test
    func automaticJobWorkerPolicyReducesLanesForLiveShareLoadAndEnvCaps() {
        let liveLoad = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            unifiedMemoryGB: 128,
            publishedSlotCount: 2,
            activeLocalSessions: 1
        ))
        let envCap = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            unifiedMemoryGB: 256,
            publishedSlotCount: 8,
            maxLanesOverride: 2
        ))
        let envDisabled = onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy(
            activeSwarmID: "swarm-private",
            unifiedMemoryGB: 256,
            publishedSlotCount: 8,
            maxLanesOverride: 0
        ))

        #expect(liveLoad.desiredLanes == 1)
        #expect(envCap.desiredLanes == 2)
        #expect(envDisabled.desiredLanes == 0)
    }

    @Test
    func recommendedShareSlotsIncreaseForHighMemoryMacsWithoutLoweringCurrentSlots() {
        #expect(recommendedOnlyMacsShareSlotCount(unifiedMemoryGB: 32, currentSlots: 0) == 1)
        #expect(recommendedOnlyMacsShareSlotCount(unifiedMemoryGB: 64, currentSlots: 0) == 1)
        #expect(recommendedOnlyMacsShareSlotCount(unifiedMemoryGB: 128, currentSlots: 1) == 2)
        #expect(recommendedOnlyMacsShareSlotCount(unifiedMemoryGB: 256, currentSlots: 1) == 4)
        #expect(recommendedOnlyMacsShareSlotCount(unifiedMemoryGB: 64, currentSlots: 3) == 3)
    }

    @Test
    func localEligibilityPrefersPublishedHealthyState() {
        let summary = deriveLocalEligibilitySummary(
            modeAllowsShare: true,
            activeSwarmID: "swarm-000001",
            runtimeStatus: "ready",
            bridgeStatus: "ready",
            localSharePublished: true,
            localShareSlotsFree: 1,
            localShareSlotsTotal: 1,
            discoveredModelCount: 2,
            failedSessions: 0
        )

        #expect(summary.code == .publishedAndHealthy)
        #expect(summary.isEligible)
        #expect(summary.shortLabel == "Eligible")
    }

    @Test
    func localEligibilityCallsOutBusyLocalSlot() {
        let summary = deriveLocalEligibilitySummary(
            modeAllowsShare: true,
            activeSwarmID: "swarm-000001",
            runtimeStatus: "ready",
            bridgeStatus: "ready",
            localSharePublished: true,
            localShareSlotsFree: 0,
            localShareSlotsTotal: 1,
            discoveredModelCount: 2,
            failedSessions: 0
        )

        #expect(summary.code == .localSlotBusy)
        #expect(summary.isEligible == false)
    }

    @Test
    func localEligibilityCallsOutDegradedShareHealth() {
        let summary = deriveLocalEligibilitySummary(
            modeAllowsShare: true,
            activeSwarmID: "swarm-000001",
            runtimeStatus: "ready",
            bridgeStatus: "ready",
            localSharePublished: true,
            localShareSlotsFree: 1,
            localShareSlotsTotal: 1,
            discoveredModelCount: 2,
            failedSessions: 4
        )

        #expect(summary.code == .shareHealthDegraded)
        #expect(summary.detail.contains("Recent relay failures"))
    }

    @Test
    func menuBarVisualStateTracksUsingAndSharing() {
        #expect(
            deriveMenuBarVisualState(
                bridgeStatus: "ready",
                runtimeStatus: "ready",
                activeRequesterSessions: 1,
                localSharePublished: true,
                localShareSlotsFree: 0,
                localShareSlotsTotal: 1
            ) == .both
        )

        #expect(
            deriveMenuBarVisualState(
                bridgeStatus: "ready",
                runtimeStatus: "ready",
                activeRequesterSessions: 0,
                localSharePublished: true,
                localShareSlotsFree: 1,
                localShareSlotsTotal: 1
            ) == .ready
        )

        #expect(
            deriveMenuBarVisualState(
                bridgeStatus: "degraded",
                runtimeStatus: "ready",
                activeRequesterSessions: 1,
                localSharePublished: true,
                localShareSlotsFree: 0,
                localShareSlotsTotal: 1
            ) == .degraded
        )
    }

    @Test
    func startupConnectionStateUsesLoadingBeforeAttention() {
        #expect(
            deriveSwarmConnectionState(
                bridgeStatus: "bootstrapping",
                runtimeStatus: "bootstrapping",
                hasActiveSwarm: false,
                hasConfirmedStatus: false,
                isLoading: false,
                isRuntimeBusy: false,
                startupGraceActive: true
            ) == .loading
        )

        #expect(
            deriveSwarmConnectionState(
                bridgeStatus: "degraded",
                runtimeStatus: "ready",
                hasActiveSwarm: false,
                hasConfirmedStatus: false,
                isLoading: false,
                isRuntimeBusy: false,
                startupGraceActive: true
            ) == .loading
        )

        #expect(
            deriveSwarmConnectionState(
                bridgeStatus: "degraded",
                runtimeStatus: "ready",
                hasActiveSwarm: true,
                hasConfirmedStatus: true,
                isLoading: false,
                isRuntimeBusy: false,
                startupGraceActive: false
            ) == .attention
        )

        #expect(
            deriveMenuBarVisualState(
                bridgeStatus: "degraded",
                runtimeStatus: "ready",
                activeRequesterSessions: 0,
                localSharePublished: false,
                localShareSlotsFree: 0,
                localShareSlotsTotal: 0,
                hasConfirmedStatus: false,
                isLoading: false,
                isRuntimeBusy: false,
                startupGraceActive: true
            ) == .loading
        )
    }

    @Test
    func swarmActivityStatusTracksIdleRemoteLocalAndBoth() {
        #expect(
            deriveSwarmActivityStatusPresentation(
                activeRequesterSessions: 0,
                localShareActiveSessions: 0,
                remoteTokensPerSecond: 0,
                localTokensPerSecond: 0
            ).label == "Idle"
        )

        #expect(
            deriveSwarmActivityStatusPresentation(
                activeRequesterSessions: 2,
                localShareActiveSessions: 0,
                remoteTokensPerSecond: 12.4,
                localTokensPerSecond: 0
            ).label == "Working (Remote, 12 tokens/s)"
        )

        #expect(
            deriveSwarmActivityStatusPresentation(
                activeRequesterSessions: 0,
                localShareActiveSessions: 1,
                remoteTokensPerSecond: 0,
                localTokensPerSecond: 3.6
            ).label == "Working (Local, 3.6 tokens/s)"
        )

        #expect(
            deriveSwarmActivityStatusPresentation(
                activeRequesterSessions: 1,
                localShareActiveSessions: 1,
                remoteTokensPerSecond: 21.8,
                localTokensPerSecond: 5.2
            ).label == "Working (Remote / Local, 22 tokens/s / 5.2 tokens/s)"
        )
    }

    @Test
    func menuBarVisualStateUsesCircularIconOnlyWhenActive() {
        #expect(MenuBarVisualState.loading.usesCircularBase == false)
        #expect(MenuBarVisualState.ready.usesCircularBase == false)
        #expect(MenuBarVisualState.usingRemote.usesCircularBase == true)
        #expect(MenuBarVisualState.sharing.usesCircularBase == true)
        #expect(MenuBarVisualState.both.usesCircularBase == true)
        #expect(MenuBarVisualState.degraded.usesCircularBase == false)
    }

    @Test
    func commandActivityInProgressMarkerExpires() {
        let now = Date()
        let active = OnlyMacsCommandActivity(
            recordedAt: now.addingTimeInterval(-2),
            wrapperName: "onlymacs",
            toolName: "codex",
            workspaceID: "workspace",
            threadID: "thread",
            commandLabel: "chat best-available",
            interpretedAs: "chat best-available",
            routeScope: "swarm",
            model: nil,
            outcome: "running",
            detail: "Direct OnlyMacs chat is in progress.",
            sessionID: nil,
            sessionStatus: "running"
        )
        let stale = OnlyMacsCommandActivity(
            recordedAt: now.addingTimeInterval(-901),
            wrapperName: "onlymacs",
            toolName: "codex",
            workspaceID: "workspace",
            threadID: "thread",
            commandLabel: "chat best-available",
            interpretedAs: "chat best-available",
            routeScope: "swarm",
            model: nil,
            outcome: "running",
            detail: "Direct OnlyMacs chat is in progress.",
            sessionID: nil,
            sessionStatus: "running"
        )

        #expect(active.isRecentInProgress(relativeTo: now) == true)
        #expect(stale.isRecentInProgress(relativeTo: now) == false)
        #expect(active.isRecentInProgress(relativeTo: now, ttl: 1) == false)
    }

    @Test
    func sessionTokensUsedAddsRequesterAndSharingDeltasSinceLaunch() {
        #expect(
            deriveSessionTokensUsed(
                tokensSavedEstimate: 18_000,
                uploadedTokensEstimate: 7_500,
                baselineSavedTokens: 10_000,
                baselineUploadedTokens: 2_500
            ) == 13_000
        )

        #expect(
            deriveSessionTokensUsed(
                tokensSavedEstimate: 4_000,
                uploadedTokensEstimate: 1_000,
                baselineSavedTokens: nil,
                baselineUploadedTokens: nil
            ) == 0
        )
    }

    @Test
    func lifetimeTokensUsedAddsRequesterAndSharingTotals() {
        #expect(
            deriveLifetimeTokensUsed(
                tokensSavedEstimate: 18_000,
                uploadedTokensEstimate: 7_500
            ) == 25_500
        )

        #expect(
            deriveLifetimeTokensUsed(
                tokensSavedEstimate: -50,
                uploadedTokensEstimate: 1_000
            ) == 1_000
        )
    }

    @Test
    func modelRuntimeDependencyPresentationShowsInstallActionWhenMissing() {
        let presentation = deriveModelRuntimeDependencyPresentation(
            ollamaStatus: .missing,
            ollamaDetail: "OnlyMacs needs Ollama installed before this Mac can host local models or run one-click model installs."
        )

        #expect(presentation?.title == "Install Ollama")
        #expect(presentation?.labelTitle == "Install Ollama")
        #expect(presentation?.systemImage == "arrow.down.circle.fill")
        #expect(presentation?.style == .actionRequired)
        #expect(presentation?.isActionable == true)
    }

    @Test
    func modelRuntimeDependencyPresentationShowsOpenActionWhenUnavailable() {
        let presentation = deriveModelRuntimeDependencyPresentation(
            ollamaStatus: .installedButUnavailable,
            ollamaDetail: "OnlyMacs found Ollama, but the local runtime is not answering yet. Launch Ollama and wait a moment."
        )

        #expect(presentation?.title == "Launch Ollama")
        #expect(presentation?.labelTitle == "Launch Ollama")
        #expect(presentation?.systemImage == "play.circle.fill")
        #expect(presentation?.style == .actionRequired)
        #expect(presentation?.isActionable == true)
    }

    @Test
    func modelRuntimeDependencyPresentationShowsInstalledStateWhenReady() {
        let presentation = deriveModelRuntimeDependencyPresentation(
            ollamaStatus: .ready,
            ollamaDetail: "Ollama is reachable on this Mac and ready for model installs."
        )

        #expect(presentation?.title == "Ollama Installed")
        #expect(presentation?.labelTitle == "Installed")
        #expect(presentation?.systemImage == "checkmark.circle.fill")
        #expect(presentation?.style == .success)
        #expect(presentation?.isActionable == false)
    }

    @Test
    func modelRuntimeDependencyPresentationHidesBannerForExternalRuntime() {
        let presentation = deriveModelRuntimeDependencyPresentation(
            ollamaStatus: .external,
            ollamaDetail: "OnlyMacs is using an external runtime."
        )

        #expect(presentation == nil)
    }

    @Test
    func howToUseRecipesCoverPublicPrivateLocalAndParameters() {
        let strategies = deriveHowToUseStrategyItems()
        let items = deriveHowToUseRecipeItems()
        let parameterItems = deriveHowToUseParameterItems()
        let publicItems = items.filter { $0.section == .publicSwarm }
        let privateItems = items.filter { $0.section == .privateSwarm }
        let localItems = items.filter { $0.section == .localFirst }

        #expect(strategies.count == 10)
        #expect(items.count == 30)
        #expect(items.allSatisfy { $0.command.hasPrefix("/onlymacs ") })
        #expect(publicItems.count == 10)
        #expect(privateItems.count == 10)
        #expect(localItems.count == 10)
        #expect(parameterItems.count == 10)
        #expect(publicItems.contains {
            $0.title == "Work On A Current Repo File Slice" &&
            $0.detail.contains("Markdown, docs, schema, or example")
        })
        #expect(publicItems.contains {
            $0.title == "Generate Structured Output From Pipeline Inputs" &&
            $0.command.contains("current intake, schema, glossary, and example JSON files")
        })
        #expect(items.contains {
            $0.title == "Map A New Repo" && $0.command == #"/onlymacs "summarize this repo, point out the main entrypoints, and tell me where to start""#
        })
        #expect(items.contains {
            $0.title == "Keep It Explicit On Your Macs" && $0.command.contains("go trusted-only")
        })
        #expect(items.contains {
            $0.title == "Review My Current Diff" && $0.command.contains("review my current diff")
        })
        #expect(items.contains {
            $0.title == "Review An Auth Flow" && $0.command.contains("go local-first")
        })
        #expect(strategies.contains {
            $0.title == #"/onlymacs "review this README section""# && $0.routeLabel == "Any Route"
        })
        #expect(strategies.contains {
            $0.title == #"/onlymacs go trusted-only "review my current diff""# && $0.routeLabel == "Private"
        })
        #expect(HowToUseRecipeSection.publicSwarm.detail.contains("approve the exact docs or file excerpts"))
        #expect(HowToUseRecipeSection.localFirst.detail.contains("This Mac"))
        #expect(HowToUseRecipeSection.privateSwarm.detail.contains("real help on the repo itself"))
        #expect(HowToUseRecipeSection.parameters.detail.contains("commands"))
        #expect(parameterItems.contains { $0.title == "local-first" })
        #expect(parameterItems.contains {
            $0.title == "Default /onlymacs Form" &&
            $0.detail.contains("Prompt-only work tries another Mac first")
        })
    }
}

extension OnlyMacsAppStatePresentationTests {
    private static func packageFileContents(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = packageRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
