import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import OnlyMacsCore
import SwiftUI

// These are the popup-first menu bar shell surfaces.

struct MenuContentView: View {
    @ObservedObject var store: BridgeStore

    private var popupSelectedSection: ControlCenterSection {
        switch store.controlCenterSection {
        case .activity, .sharing:
            return .swarms
        default:
            return store.controlCenterSection
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            popupHero
            Divider()
            HStack(spacing: 0) {
                PopupNavigationRail(
                    selectedSection: Binding(
                        get: { popupSelectedSection },
                        set: { store.selectControlCenterSection($0) }
                    )
                )
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        popupSectionContent
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            footer
                .padding(14)
        }
        .frame(width: 520, height: 736)
        .animation(.easeInOut(duration: 0.16), value: store.controlCenterSection)
        .accessibilityIdentifier("onlymacs.popup.windowContent")
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Updates")
                .font(.caption.weight(.semibold))
            UpdateStatusPanel(
                currentBuild: store.buildDisplayLabel,
                lastChecked: store.updateLastCheckedLabel,
                statusTitle: store.updateStatusTitle,
                statusDetail: store.updateStatusDetail,
                availableBuild: store.availableUpdate?.displayLabel,
                isChecking: store.isCheckingForUpdates,
                isDownloading: store.isDownloadingUpdate,
                isInstalling: store.isInstallingUpdate,
                checkLabel: store.updateActionTitle,
                actionDetail: store.updateActionDetail,
                checkForUpdates: store.checkForUpdatesNow,
                installUpdate: store.installAvailableUpdateNow
            )
        }
    }

    private var launcherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Launchers")
                .font(.caption.weight(.semibold))
            LauncherCommandPanel(
                compact: true,
                statusLabel: store.launcherStatusLabel,
                menuBarStateTitle: store.menuBarStateTitle,
                menuBarStateDetail: store.menuBarStateDetail,
                localEligibilityTitle: store.localEligibilitySummary.title,
                localEligibilityDetail: store.localEligibilitySummary.detail,
                shimDirectoryPath: String?.none,
                detail: store.launcherStatus.detail,
                preferredRoute: Binding(
                    get: { store.preferredRequestRoute },
                    set: { store.setPreferredRequestRoute($0) }
                ),
                preferredRouteSummary: store.preferredRequestRouteSummary,
                actionTitle: store.launcherStatus.actionTitle,
                needsPathFix: store.launcherStatus.needsPathFix,
                shouldReopenTools: store.shouldReopenDetectedTools,
                showCopyPathFix: store.launcherStatus.pathNeedsSetup,
                starterCommand: store.starterCommand,
                starterCommands: store.starterCommands,
                latestActivity: store.latestOnlyMacsActivityDisplayItem,
                notificationsEnabled: Binding(
                    get: { store.onlyMacsNotificationsEnabled },
                    set: { store.setOnlyMacsNotificationsEnabled($0) }
                ),
                notificationsDetail: store.onlyMacsNotificationsDetail,
                pathHelpText: store.launcherPathHelpText,
                guidanceHeading: "Route Smartly",
                guidanceIntro: store.commandGuidanceIntro,
                guidanceSuggestions: store.commandGuidanceSuggestions,
                installLaunchers: store.installLaunchersNow,
                copyStarterCommand: store.copyStarterCommand,
                applyPathFix: store.applyPathFixNow,
                reopenTools: store.reopenDetectedToolsNow,
                copyPathFix: store.copyPathFixNow,
                copyCommand: store.copyCommand
            )
        }
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Startup")
                .font(.caption.weight(.semibold))
            StartupPreferencePanel(
                compact: true,
                isEnabled: store.launchAtLoginEnabled,
                statusTitle: store.launchAtLoginStatusTitle,
                detail: store.launchAtLoginDetail,
                setEnabled: store.setLaunchAtLoginNow
            )
        }
    }

    private var coordinatorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coordinator")
                .font(.caption.weight(.semibold))
            CoordinatorConnectionPanel(
                compact: true,
                coordinatorURLDraft: $store.coordinatorURLDraft,
                effectiveTarget: store.effectiveCoordinatorTarget,
                validationError: store.coordinatorSettings.validationError,
                isRuntimeBusy: store.isRuntimeBusy,
                hasPendingChanges: store.hasPendingCoordinatorChanges,
                recoveryMessage: store.coordinatorRecoveryMessage,
                applyLabel: "Apply Coordinator",
                retryLabel: "Retry Hosted",
                openLogsLabel: "Open Logs",
                applyChanges: store.applyCoordinatorConnectionNow,
                retryHosted: store.restartRuntimeNow,
                openLogs: store.openLogsNow
            )
        }
    }

    @ViewBuilder
    private var recentSwarmsSection: some View {
        let swarms = recentSwarmConnectionSwarms(
            swarms: store.snapshot.swarms,
            activeSwarmID: store.snapshot.runtime.activeSwarmID
        )
        if !swarms.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Swarms")
                    .font(.caption.weight(.semibold))
                RecentSwarmConnectionsPanel(
                    compact: true,
                    swarms: swarms,
                    activeSwarmID: store.snapshot.runtime.activeSwarmID,
                    activeSessionCount: store.snapshot.swarm.activeSessionCount,
                    members: store.snapshot.members,
                    connectToSwarm: store.connectToSwarmNow
                )
            }
        }
    }

    private var popupHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ConnectionStatusBadge(
                    title: store.swarmConnectionTitle,
                    symbolName: store.swarmConnectionSymbolName,
                    color: store.swarmConnectionColor
                )
                Spacer()
                Text("Updated \(store.formattedLastUpdated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.activeSwarmHeadline)
                        .font(.title3.weight(.semibold))
                    if let popupHeroDetail {
                        Text(popupHeroDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                if let activeSwarm = store.activeRuntimeSwarm {
                    Label(activeSwarm.visibilityBadgeTitle, systemImage: activeSwarm.isPublic ? "globe" : "lock.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(activeSwarm.isPublic ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if store.hasManualSwarmSelectionDraft,
               let activeSwarm = store.activeRuntimeSwarm,
               let pendingSwarm = store.selectedSwarm,
               pendingSwarm.id != activeSwarm.id
            {
                Text("Pending switch: \(pendingSwarm.name). Choose Connect below to apply it.")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if store.swarmConnectionState == .disconnected {
                Text("Pick a swarm from the list below to connect and OnlyMacs will keep the rest moving in the background.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if store.swarmConnectionState == .attention, let error = store.lastError, !error.isEmpty {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let token = store.clipboardInviteToken {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Invite detected on your clipboard.")
                            .font(.caption.weight(.semibold))
                        Text(token)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack {
                            Button("Join Now") {
                                store.joinClipboardInviteNow()
                            }
                            Button("Dismiss") {
                                store.dismissClipboardInvite()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.accentColor.opacity(0.06),
                    Color.secondary.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var popupHeroDetail: String? {
        if store.swarmConnectionState == .connected, store.activeRuntimeSwarm != nil {
            return nil
        }
        return store.activeSwarmDetail
    }

    @ViewBuilder
    private var popupSectionContent: some View {
        switch popupSelectedSection {
        case .swarms, .activity, .sharing:
            VStack(alignment: .leading, spacing: 16) {
                PopupSectionHeader(
                    title: "Available Swarms",
                    subtitle: "Connect to a swarm, or make your own private one."
                )
                PopupSnapshotCard(
                    title: "Your OnlyMacs Name",
                    detail: "This is how this Mac appears to other members in the swarm."
                ) {
                    MemberIdentityPanel(
                        compact: true,
                        memberName: Binding(
                            get: { store.memberNameDraft },
                            set: { store.setMemberNameDraftNow($0) }
                        ),
                        currentMemberID: store.snapshot.identity.memberID,
                        hasPendingChanges: store.memberNameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != store.snapshot.identity.memberName,
                        isLoading: store.isSavingMemberName,
                        isConfirmationPending: store.pendingMemberNameConfirmation != nil,
                        saveName: store.saveMemberNameNow
                    )
                }
                CompactSwarmDirectoryPanel(
                    compact: true,
                    swarms: store.snapshot.swarms,
                    activeSwarmID: store.snapshot.runtime.activeSwarmID,
                    activeSessionCount: store.snapshot.swarm.activeSessionCount,
                    members: store.snapshot.members,
                    connectToSwarm: store.connectToSwarmNow
                )
                SwarmInviteManagementPanel(
                    compact: true,
                    slotsFree: store.snapshot.swarm.slotsFree,
                    slotsTotal: store.snapshot.swarm.slotsTotal,
                    modelCount: store.snapshot.swarm.modelCount,
                    activeSessionCount: store.snapshot.swarm.activeSessionCount,
                    activePrivateSwarmName: store.activeRuntimeSwarm?.isPublic == false ? store.activeRuntimeSwarm?.name : nil,
                    showsInviteControls: false,
                    newSwarmName: $store.newSwarmName,
                    createSwarmLabel: "Create Private Swarm",
                    createInviteLabel: "Create Invite",
                    joinInviteToken: $store.joinInviteToken,
                    joinLabel: "Join Private Swarm",
                    isLoading: store.isLoading,
                    canCreateInvite: store.canCreateInvite,
                    inviteToken: store.latestInviteToken,
                    inviteLinkString: store.inviteLinkString,
                    inviteShareMessage: store.inviteShareMessage,
                    canShareInvite: store.canShareInvite,
                    inviteHelperText: store.selectedSwarm?.visibility == "public" ? "OnlyMacs Public is open. Private swarms are the ones that need invite links." : nil,
                    invitePayload: store.inviteLinkPayload,
                    inviteStatusTitle: store.inviteProgress?.stage.title,
                    inviteStatusDetail: store.inviteProgress?.detail,
                    inviteExpiryDetail: store.inviteExpiryDetail,
                    inviteRecoveryMessage: store.inviteRecoveryMessage,
                    createSwarm: store.createSwarmNow,
                    createInvite: store.createInviteNow,
                    joinSwarm: store.joinSwarmNow,
                    copyToken: store.copyLatestInviteToken,
                    copyLink: store.copyInviteLink,
                    copyInviteMessage: store.copyInviteMessage
                )
                recentSwarmsSection
            }
            .transition(.opacity)
        case .currentSwarm:
            VStack(alignment: .leading, spacing: 16) {
                PopupSectionHeader(
                    title: "Current Swarm",
                    subtitle: "Live status for the swarm this Mac is connected to now."
                )
                PopupSnapshotCard(
                    title: store.snapshot.bridge.activeSwarmName ?? "Current Swarm",
                    detail: "Members, capacity, hardware, and available models."
                ) {
                    CurrentSwarmMembersPanel(
                        compact: true,
                        activeSwarmID: store.snapshot.runtime.activeSwarmID,
                        activeSwarmName: store.snapshot.bridge.activeSwarmName ?? "No current swarm connected",
                        swarm: store.snapshot.swarm,
                        members: store.snapshot.members
                    )
                }
                if store.activeRuntimeSwarm?.allowsInviteSharing == true {
                    PopupSnapshotCard(
                        title: "Share",
                        detail: "Invite link and QR code for this private swarm."
                    ) {
                        SwarmSharePanel(
                            activeSwarm: store.activeRuntimeSwarm,
                            createInviteLabel: store.isLoading ? "Creating..." : "Create Invite",
                            isLoading: store.isLoading,
                            canCreateInvite: store.canCreateInvite,
                            inviteToken: store.latestInviteToken,
                            inviteLinkString: store.inviteLinkString,
                            inviteShareMessage: store.inviteShareMessage,
                            canShareInvite: store.canShareInvite,
                            invitePayload: store.inviteLinkPayload,
                            inviteStatusTitle: store.inviteProgress?.stage.title,
                            inviteStatusDetail: store.inviteProgress?.detail,
                            inviteExpiryDetail: store.inviteExpiryDetail,
                            inviteRecoveryMessage: store.inviteRecoveryMessage,
                            compact: true,
                            createInvite: store.createInviteNow,
                            copyToken: store.copyLatestInviteToken,
                            copyLink: store.copyInviteLink,
                            copyInviteMessage: store.copyInviteMessage
                        )
                    }
                }
            }
            .transition(.opacity)
        case .models:
            VStack(alignment: .leading, spacing: 16) {
                PopupSectionHeader(
                    title: "Models",
                    subtitle: ""
                )
                modelsSection
            }
            .transition(.opacity)
        case .tools:
            VStack(alignment: .leading, spacing: 16) {
                PopupSectionHeader(
                    title: "Tools",
                    subtitle: "Keep Codex, Claude Code, and terminal-friendly editors ready to use OnlyMacs."
                )
                PopupSnapshotCard(
                    title: "Install All Tools",
                    detail: store.toolIntegrationPrimaryDetail
                ) {
                    toolsSection
                }
            }
            .transition(.opacity)
        case .runtime:
            VStack(alignment: .leading, spacing: 16) {
                PopupSettingsSection(store: store)
            }
            .transition(.opacity)
        case .howToUse:
            VStack(alignment: .leading, spacing: 16) {
                PopupSectionHeader(
                    title: "How To Use",
                    subtitle: "Public uses approved text/source excerpts, private handles real repo-aware work, and local-first keeps sensitive paths on This Mac."
                )
                PopupSnapshotCard(
                    title: "Project Recipes",
                    detail: "Paste these into Codex or Claude Code with your project open, then tweak the wording for your repo and task."
                ) {
                    howToUseSection
                }
            }
            .transition(.opacity)
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let presentation = store.modelRuntimeDependencyPresentation {
                ModelRuntimeDependencyBanner(
                    presentation: presentation,
                    action: store.modelRuntimeDependencyAction
                )
            }

            ModelLibraryPanel(
                compact: true,
                summaryTitle: store.modelLibrarySummaryTitle,
                summaryDetail: store.modelLibrarySummaryDetail,
                items: store.modelLibraryDisplayItems,
                installModel: store.installInstallerModelNow
            )
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolIntegrationActionsPanel(
                primaryActionTitle: store.toolIntegrationPrimaryActionTitle,
                primaryDetail: store.toolIntegrationPrimaryDetail,
                showReopenAction: store.shouldReopenDetectedTools,
                installOrRefreshTools: store.installLaunchersNow,
                reopenTools: store.reopenDetectedToolsNow
            )
            ToolIntegrationCardsPanel(items: store.popupToolDisplayItems)
        }
    }

    private var howToUseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HowToUseRecipesPanel(
                strategies: store.howToUseStrategyItems,
                items: store.howToUseRecipeItems,
                parameters: store.howToUseParameterItems,
                copyCommand: store.copyCommand
            )
        }
    }

    private var footer: some View {
        HStack {
            Button(store.isQuitting ? "Quitting…" : "Quit") {
                store.quitOnlyMacsNow()
            }
            .buttonStyle(.borderless)
            .disabled(store.isQuitting)

            Spacer()

            Text(store.formattedSessionAndLifetimeTokensUsed)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .help("OnlyMacs tokens used across requester work and any sharing this Mac did for others. Lifetime is kept locally from the bridge metrics files on this Mac.")

            Spacer()

            Button {
                store.refreshNow()
            } label: {
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .help(store.isLoading ? "Refreshing" : "Refresh")
            .disabled(store.isLoading)
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(store.isLoading ? "Refreshing" : "Refresh"))
        }
    }

}

private struct PopupSettingsSection: View {
    @ObservedObject var store: BridgeStore
    @State private var selectedPane: PopupSettingsPane = .coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PopupSectionHeader(
                title: "Settings",
                subtitle: "Coordinator, updates, and basic app preferences."
            )

            HStack(spacing: 8) {
                ForEach(PopupSettingsPane.allCases) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        Label(pane.title, systemImage: pane.symbolName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(selectedPane == pane ? Color.accentColor : Color.primary)
                            .background(selectedPane == pane ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(pane.title)
                    .accessibilityLabel(Text(pane.title))
                    .accessibilityAddTraits(selectedPane == pane ? [.isSelected] : [])
                }
            }
            .accessibilityIdentifier("onlymacs.popup.settings.panePicker")

            PopupSnapshotCard(title: selectedPane.title, detail: selectedPane.detail) {
                selectedPaneContent
            }
        }
    }

    @ViewBuilder
    private var selectedPaneContent: some View {
        switch selectedPane {
        case .coordinator:
            CoordinatorConnectionPanel(
                compact: true,
                coordinatorURLDraft: $store.coordinatorURLDraft,
                effectiveTarget: store.effectiveCoordinatorTarget,
                validationError: store.coordinatorSettings.validationError,
                isRuntimeBusy: store.isRuntimeBusy,
                hasPendingChanges: store.hasPendingCoordinatorChanges,
                recoveryMessage: store.coordinatorRecoveryMessage,
                applyLabel: "Apply Coordinator",
                retryLabel: "Retry Hosted",
                openLogsLabel: "Open Logs",
                applyChanges: store.applyCoordinatorConnectionNow,
                retryHosted: store.restartRuntimeNow,
                openLogs: store.openLogsNow
            )
        case .updates:
            UpdateStatusPanel(
                currentBuild: store.buildDisplayLabel,
                lastChecked: store.updateLastCheckedLabel,
                statusTitle: store.updateStatusTitle,
                statusDetail: store.updateStatusDetail,
                availableBuild: store.availableUpdate?.displayLabel,
                isChecking: store.isCheckingForUpdates,
                isDownloading: store.isDownloadingUpdate,
                isInstalling: store.isInstallingUpdate,
                checkLabel: store.updateActionTitle,
                actionDetail: store.updateActionDetail,
                checkForUpdates: store.checkForUpdatesNow,
                installUpdate: store.installAvailableUpdateNow
            )
        case .basicSettings:
            VStack(alignment: .leading, spacing: 14) {
                MemberIdentityPanel(
                    compact: true,
                    memberName: Binding(
                        get: { store.memberNameDraft },
                        set: { store.setMemberNameDraftNow($0) }
                    ),
                    currentMemberID: store.snapshot.identity.memberID,
                    hasPendingChanges: store.memberNameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != store.snapshot.identity.memberName,
                    isLoading: store.isSavingMemberName,
                    isConfirmationPending: store.pendingMemberNameConfirmation != nil,
                    saveName: store.saveMemberNameNow
                )

                Divider()

                StartupPreferencePanel(
                    compact: true,
                    isEnabled: store.launchAtLoginEnabled,
                    statusTitle: store.launchAtLoginStatusTitle,
                    detail: store.launchAtLoginDetail,
                    setEnabled: store.setLaunchAtLoginNow
                )
            }
        }
    }
}

private enum PopupSettingsPane: String, CaseIterable, Identifiable {
    case coordinator
    case updates
    case basicSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coordinator:
            return "Coordinator"
        case .updates:
            return "Updates"
        case .basicSettings:
            return "Basic Settings"
        }
    }

    var detail: String {
        switch self {
        case .coordinator:
            return "Choose the coordinator this Mac checks in with."
        case .updates:
            return "Check the installed build and Sparkle update status."
        case .basicSettings:
            return "Name, startup, and local runtime controls."
        }
    }

    var symbolName: String {
        switch self {
        case .coordinator:
            return "network"
        case .updates:
            return "arrow.down.circle"
        case .basicSettings:
            return "gearshape"
        }
    }
}
