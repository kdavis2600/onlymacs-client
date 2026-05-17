import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import OnlyMacsCore
import SwiftUI

// These are the advanced settings, automation, and file approval shell surfaces.

struct SettingsView: View {
    @ObservedObject var store: BridgeStore
    @State private var selectedPane: SettingsPane = .coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsPanePill(
                        pane: pane,
                        isSelected: pane == selectedPane,
                        select: { selectedPane = pane }
                    )
                }
            }
            .accessibilityIdentifier("onlymacs.settings.panePicker")

            SettingsPaneCard(title: selectedPane.title, symbolName: selectedPane.symbolName) {
                selectedPaneContent
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(minWidth: 520, minHeight: 340, alignment: .topLeading)
    }

    @ViewBuilder
    private var selectedPaneContent: some View {
        switch selectedPane {
        case .coordinator:
            CoordinatorConnectionPanel(
                compact: false,
                coordinatorURLDraft: $store.coordinatorURLDraft,
                effectiveTarget: store.effectiveCoordinatorTarget,
                validationError: store.coordinatorSettings.validationError,
                isRuntimeBusy: store.isRuntimeBusy,
                hasPendingChanges: store.hasPendingCoordinatorChanges,
                recoveryMessage: store.coordinatorRecoveryMessage,
                showsHelperText: false,
                applyLabel: "Save And Restart Runtime",
                retryLabel: "Retry Hosted Connection",
                openLogsLabel: "Open Runtime Logs",
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
            VStack(alignment: .leading, spacing: 18) {
                MemberIdentityPanel(
                    compact: false,
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
                    compact: false,
                    isEnabled: store.launchAtLoginEnabled,
                    statusTitle: store.launchAtLoginStatusTitle,
                    detail: store.launchAtLoginDetail,
                    showsDetail: false,
                    setEnabled: store.setLaunchAtLoginNow
                )
            }
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
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

private struct SettingsPanePill: View {
    let pane: SettingsPane
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Label(pane.title, systemImage: pane.symbolName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .background(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pane.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct SettingsPaneCard<Content: View>: View {
    let title: String
    let symbolName: String
    let content: Content

    init(title: String, symbolName: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbolName = symbolName
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbolName)
                .font(.headline)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SettingsCoreSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        Section("Starter Model Setup") {
            InstallerRecommendationsPanel(
                assessment: store.capabilityAssessment,
                capabilitySnapshot: store.capabilitySnapshot,
                plan: store.installerPlan,
                catalogError: store.catalogError,
                items: store.setupVisibleModelRecommendations,
                selectedModelIDs: store.selectedInstallerModelIDs,
                installableModelIDs: store.installableInstallerModelIDs,
                installedModelIDs: store.installedInstallerModelIDs,
                diskBlockedModelIDs: store.diskBlockedInstallerModelIDs,
                queueItems: store.installerQueueDisplayItems,
                isInstalling: store.isInstallingStarterModels,
                statusDetail: store.starterModelStatusDetail ?? (store.starterModelCompletionDetail == nil ? store.starterModelSetupSummary : nil),
                completionDetail: store.starterModelCompletionDetail,
                toggleSelection: store.toggleInstallerModelSelection,
                resetSelections: store.resetInstallerSelectionsNow,
                installSelectedModels: store.installSelectedStarterModelsNow
            )
        }

        Section("Network Health") {
            Text("OnlyMacs always lets this Mac use help from the swarm and share help back when it is ready. That keeps every swarm healthier and simpler.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section("Bridge") {
            BridgeOverviewPanel(
                status: store.snapshot.bridge.status.capitalized,
                menuBarStateTitle: store.menuBarStateTitle,
                menuBarStateDetail: store.menuBarStateDetail,
                localEligibilityTitle: store.localEligibilitySummary.title,
                localEligibilityDetail: store.localEligibilitySummary.detail,
                jobWorkerTitle: store.jobWorkerState.displayTitle,
                jobWorkerDetail: store.jobWorkerState.displayDetail,
                coordinator: store.snapshot.bridge.coordinatorURL ?? "Unavailable",
                build: store.buildDisplayLabel,
                lastUpdated: store.formattedLastUpdated,
                errorMessage: store.lastError,
                isLoading: store.isLoading,
                lastSupportBundlePath: store.lastSupportBundlePath,
                refresh: store.refreshNow,
                openLogs: store.openLogsNow,
                copyDiagnostics: store.copyDiagnosticSummaryNow,
                exportSupportBundle: store.exportSupportBundleNow
            )
        }

        Section("Updates") {
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

        Section("Coordinator Connection") {
            CoordinatorConnectionPanel(
                compact: false,
                coordinatorURLDraft: $store.coordinatorURLDraft,
                effectiveTarget: store.effectiveCoordinatorTarget,
                validationError: store.coordinatorSettings.validationError,
                isRuntimeBusy: store.isRuntimeBusy,
                hasPendingChanges: store.hasPendingCoordinatorChanges,
                recoveryMessage: store.coordinatorRecoveryMessage,
                applyLabel: "Save And Restart Runtime",
                retryLabel: "Retry Hosted Connection",
                openLogsLabel: "Open Runtime Logs",
                applyChanges: store.applyCoordinatorConnectionNow,
                retryHosted: store.restartRuntimeNow,
                openLogs: store.openLogsNow
            )
        }

        if let recoveryCard = store.recoveryCard {
            Section("What Happened?") {
                RecoveryActionCardView(
                    content: recoveryCard,
                    compact: false,
                    performAction: store.performRecoveryAction
                )
            }
        }

        if store.selectedMode.allowsUse {
            Section("Recent Swarms") {
                RecentSwarmsPanel(
                    compact: false,
                    queuePressureLabel: store.queuePressureLabel,
                    queuePressureDetail: store.queuePressureDetail,
                    emptyMessage: "No swarm sessions yet. Start one from Codex or Claude Code with `onlymacs go ...` and OnlyMacs will show the model choice, route, and saved tokens here.",
                    items: store.settingsRecentSwarmDisplayItems
                )
            }
        }
    }
}

struct ConnectionStatusBadge: View {
    let title: String
    let symbolName: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbolName)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.16))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

struct PopupNavigationRail: View {
    @Binding var selectedSection: ControlCenterSection

    private let popupSections: [ControlCenterSection] = [.swarms, .currentSwarm, .models, .tools, .runtime]
    private let utilitySections: [ControlCenterSection] = [.howToUse]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(popupSections) { section in
                Button {
                    selectedSection = section
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selectedSection == section ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.05))
                        .overlay {
                            Image(systemName: section.symbolName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selectedSection == section ? Color.accentColor : Color.secondary)
                        }
                        .frame(width: 42, height: 42)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(Text(section.title))
                .accessibilityIdentifier("onlymacs.popup.section.\(section.automationID)")
            }

            Spacer(minLength: 0)

            ForEach(utilitySections) { section in
                Button {
                    selectedSection = section
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selectedSection == section ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.05))
                        .overlay {
                            Image(systemName: section.symbolName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selectedSection == section ? Color.accentColor : Color.secondary)
                        }
                        .frame(width: 42, height: 42)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(Text(section.title))
                .accessibilityIdentifier("onlymacs.popup.section.\(section.automationID)")
            }
        }
        .padding(12)
        .frame(width: 66)
    }
}

struct PopupSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CompactSwarmDirectoryPanel: View {
    let compact: Bool
    let swarms: [SwarmOption]
    let activeSwarmID: String
    let activeSessionCount: Int
    var members: [SwarmMemberSummary] = []
    let connectToSwarm: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            if swarms.isEmpty {
                Text("No swarms are available yet.")
                    .font(compact ? .subheadline : .body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(swarms) { swarm in
                    Button {
                        connectToSwarm(swarm.id)
                    } label: {
                        CompactSwarmDirectoryRow(
                            compact: compact,
                            swarm: swarm,
                            activeSwarmID: activeSwarmID,
                            activeSessionCount: activeSessionCount,
                            members: swarm.id == activeSwarmID ? members : []
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

func recentSwarmConnectionSwarms(swarms: [SwarmOption], activeSwarmID: String) -> [SwarmOption] {
    swarms
        .filter { swarm in
            activeSwarmID.isEmpty || swarm.id != activeSwarmID
        }
        .sorted { lhs, rhs in
            if lhs.isPublic != rhs.isPublic { return lhs.isPublic }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
}

struct RecentSwarmConnectionsPanel: View {
    let compact: Bool
    let swarms: [SwarmOption]
    let activeSwarmID: String
    let activeSessionCount: Int
    var members: [SwarmMemberSummary] = []
    let connectToSwarm: (String) -> Void

    var body: some View {
        if !visibleSwarms.isEmpty {
            CompactSwarmDirectoryPanel(
                compact: compact,
                swarms: visibleSwarms,
                activeSwarmID: activeSwarmID,
                activeSessionCount: activeSessionCount,
                members: members,
                connectToSwarm: connectToSwarm
            )
        }
    }

    private var visibleSwarms: [SwarmOption] {
        recentSwarmConnectionSwarms(swarms: swarms, activeSwarmID: activeSwarmID)
    }
}

struct CompactSwarmDirectoryRow: View {
    let compact: Bool
    let swarm: SwarmOption
    let activeSwarmID: String
    let activeSessionCount: Int
    let members: [SwarmMemberSummary]

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 12 : 14) {
            swarmIcon
            VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                Text(swarm.name)
                    .font((compact ? Font.body : .title3).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(compact ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                HStack(spacing: 8) {
                    Text(swarm.visibilityBadgeTitle)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(swarm.isPublic ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    Text(memberCountLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(Capsule())
                }
                Text(swarm.accessDetail)
                    .font(compact ? .subheadline : .body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !compact {
                    Text(swarm.selectionDetail(activeSessionCount: activeSessionCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            connectionLabel
        }
        .padding(compact ? 14 : 16)
        .background(swarm.id == activeSwarmID ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous))
    }

    private var memberCountLabel: String {
        let count = swarm.id == activeSwarmID && !members.isEmpty ? members.count : swarm.memberCount
        return "\(count) \(count == 1 ? "member" : "members")"
    }

    private var swarmIcon: some View {
        ZStack {
            Circle()
                .fill(swarm.isPublic ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                .frame(width: compact ? 34 : 40, height: compact ? 34 : 40)
            Image(systemName: swarm.isPublic ? "globe" : "person.2.fill")
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(swarm.isPublic ? Color.accentColor : Color.secondary)
        }
    }

    @ViewBuilder
    private var connectionLabel: some View {
        if swarm.id == activeSwarmID {
            ConnectionStatusBadge(
                title: "Connected",
                symbolName: "checkmark.circle.fill",
                color: .green
            )
        } else {
            Text("Connect")
                .font((compact ? Font.caption : .callout).weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

struct ControlCenterWindowView: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ConnectionStatusBadge(
                    title: store.swarmConnectionTitle,
                    symbolName: store.swarmConnectionSymbolName,
                    color: store.swarmConnectionColor
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.activeSwarmHeadline)
                        .font(.headline)
                    Text(store.activeSwarmDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Settings") {
                    store.openSettingsWindowNow()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("onlymacs.controlCenter.openSettings")
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.16),
                        Color.accentColor.opacity(0.06),
                        Color.secondary.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            Divider()

            HStack(spacing: 0) {
                ControlCenterSidebar(
                    selectedSection: Binding(
                        get: { store.controlCenterSection },
                        set: { store.selectControlCenterSection($0) }
                    )
                )
                Divider()
                controlCenterContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: store.controlCenterSection)
        .accessibilityIdentifier("onlymacs.controlCenter.windowContent")
    }

    @ViewBuilder
    private var controlCenterContent: some View {
        switch store.controlCenterSection {
        case .swarms:
            ControlCenterSwarmSections(store: store)
        case .currentSwarm:
            ControlCenterCurrentSwarmSections(store: store)
        case .activity:
            ControlCenterActivitySections(store: store)
        case .sharing:
            ControlCenterSharingSections(store: store)
        case .models:
            ControlCenterModelSections(store: store)
        case .tools:
            ControlCenterToolSections(store: store)
        case .runtime:
            ControlCenterRuntimeSections(store: store)
        case .howToUse:
            ControlCenterHowToUseSections(store: store)
        }
    }
}

struct ControlCenterSidebar: View {
    @Binding var selectedSection: ControlCenterSection

    var body: some View {
        VStack(spacing: 12) {
            ForEach(ControlCenterSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(selectedSection == section ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.05))
                        .overlay {
                            VStack(spacing: 7) {
                                Image(systemName: section.symbolName)
                                    .font(.system(size: 17, weight: .semibold))
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(selectedSection == section ? Color.accentColor : Color.secondary)
                        }
                        .frame(width: 86, height: 70)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(Text(section.title))
                .accessibilityIdentifier("onlymacs.controlCenter.section.\(section.automationID)")
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .frame(width: 110)
    }
}

struct OnlyMacsFileApprovalWindowView: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        Group {
            if let approval = store.pendingFileAccessApproval {
                OnlyMacsFileAccessApprovalView(store: store, approval: approval)
                    .onAppear {
                        store.markFileApprovalWindowVisible()
                    }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ControlCenterPage<Content: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String
    let content: Content

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    if let eyebrow, !eyebrow.isEmpty {
                        Text(eyebrow.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.clear)
    }
}

struct ControlCenterCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct PopupSnapshotCard<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ControlCenterCurrentSwarmSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        ControlCenterPage(
            eyebrow: "Current Swarm",
            title: store.snapshot.bridge.activeSwarmName ?? "Current Swarm",
            subtitle: "Live members, capacity, hardware, and models for the swarm this Mac is connected to now."
        ) {
            ControlCenterCard(
                title: "Current Swarm",
                subtitle: "Use this when you want to confirm who is online, who is serving, and what each Mac can run."
            ) {
                CurrentSwarmMembersPanel(
                    compact: false,
                    activeSwarmID: store.snapshot.runtime.activeSwarmID,
                    activeSwarmName: store.snapshot.bridge.activeSwarmName ?? "No current swarm connected",
                    swarm: store.snapshot.swarm,
                    members: store.snapshot.members
                )
            }
        }
    }
}

struct ControlCenterActivitySections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        ControlCenterPage(
            eyebrow: "Activity",
            title: "What OnlyMacs is doing",
            subtitle: "A calmer view of your recent work, not a debug dashboard."
        ) {
            if store.selectedMode.allowsUse {
                ControlCenterCard(
                    title: "Requester summary",
                    subtitle: "See whether OnlyMacs is saving work right now and if anything is queued."
                ) {
                    RequesterHighlightsPanel(
                        compact: false,
                        tokensSaved: store.formattedTokensSaved,
                        downloaded: store.formattedSavedTokens(store.snapshot.usage.downloadedTokensEstimate),
                        uploaded: store.formattedSavedTokens(store.snapshot.usage.uploadedTokensEstimate),
                        swarmBudget: store.snapshot.usage.reservationCap > 0 ? "\(store.snapshot.usage.activeReservations)/\(store.snapshot.usage.reservationCap)" : nil,
                        communityBoostLabel: store.snapshot.usage.communityBoost.metricRowLabel,
                        communityBoost: store.snapshot.usage.communityBoost.displayValue,
                        activeSwarms: store.snapshot.swarm.activeSessionCount,
                        queuedSwarms: store.snapshot.swarm.queuedSessionCount,
                        queuePressureLabel: store.queuePressureLabel,
                        communityTrait: store.snapshot.usage.communityBoost.primaryTrait,
                        communityDetail: store.snapshot.usage.communityBoost.detail,
                        queuePressureDetail: store.queuePressureDetail
                    )
                }

                if let latestActivity = store.latestOnlyMacsActivityDisplayItem {
                    ControlCenterCard(
                        title: "Latest /onlymacs request",
                        subtitle: "The newest routed action from Codex or Claude Code."
                    ) {
                        OnlyMacsActivityPanel(
                            compact: false,
                            activity: latestActivity
                        )
                    }
                }

                ControlCenterCard(
                    title: "Recent swarms",
                    subtitle: "Recent work, chosen routes, and model decisions."
                ) {
                    RecentSwarmsPanel(
                        compact: false,
                        queuePressureLabel: store.queuePressureLabel,
                        queuePressureDetail: store.queuePressureDetail,
                        emptyMessage: "No swarm sessions yet. Start one from Codex or Claude Code with `onlymacs go ...` and it will appear here.",
                        items: store.settingsRecentSwarmDisplayItems
                    )
                }
            } else {
                ControlCenterCard(
                    title: "Requester summary",
                    subtitle: "Switch this Mac to Use Remote Macs or Both if you want activity to appear here."
                ) {
                    Text("Right now this Mac is not set to request help from a swarm.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ControlCenterSharingSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        ControlCenterPage(
            eyebrow: "This Mac",
            title: "Share this Mac",
            subtitle: "Turn this Mac on for the swarm and choose what it can serve."
        ) {
            ControlCenterCard(
                title: store.localShare.published ? "This Mac is helping" : "This Mac is not sharing yet",
                subtitle: store.localShare.published
                    ? "It is ready to help the current swarm with the models you have turned on."
                    : "Switch sharing on when you want this Mac to help the current swarm."
            ) {
                LocalSharePublishingPanel(
                    compact: false,
                    status: store.localShare.status,
                    published: store.localShare.published,
                    swarmName: store.localShare.activeSwarmName,
                    activeSessions: store.localShare.activeSessions,
                    servedSessions: store.localShare.servedSessions,
                    streamedSessions: store.localShare.servedStreamSessions,
                    failedSessions: store.localShare.failedSessions,
                    uploadedTokens: store.formattedSavedTokens(store.localShare.uploadedTokensEstimate),
                    downloadedTokens: store.formattedSavedTokens(store.snapshot.usage.downloadedTokensEstimate),
                    swarmBudget: store.snapshot.usage.reservationCap > 0 ? "\(store.snapshot.usage.activeReservations)/\(store.snapshot.usage.reservationCap)" : nil,
                    communityBoostLabel: store.snapshot.usage.communityBoost.metricRowLabel,
                    communityBoost: store.snapshot.usage.communityBoost.displayValue,
                    communityTrait: store.snapshot.usage.communityBoost.primaryTrait,
                    communityDetail: store.snapshot.usage.communityBoost.detail,
                    errorMessage: store.localShare.error,
                    lastServedModel: store.localShare.lastServedModel,
                    failureNote: store.localShareFailureNote(compact: false),
                    recentActivity: store.recentProviderActivityDisplayItems,
                    models: store.localShare.discoveredModels,
                    publishedModelIDs: store.publishedLocalModelIDs,
                    isLoading: store.isLoading,
                    selectedSwarmID: store.selectedSwarmID,
                    publishLabel: store.localShare.published ? "Stop Sharing This Mac" : "Start Sharing This Mac",
                    publishToggle: {
                        if store.localShare.published {
                            store.unpublishThisMacNow()
                        } else {
                            store.publishThisMacNow()
                        }
                    }
                )
            }
        }
    }
}

struct ControlCenterModelSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        ControlCenterPage(
            eyebrow: "Models",
            title: "Models",
            subtitle: ""
        ) {
            ControlCenterCard(
                title: "Model library",
                subtitle: nil
            ) {
                if let presentation = store.modelRuntimeDependencyPresentation {
                    ModelRuntimeDependencyBanner(
                        presentation: presentation,
                        action: store.modelRuntimeDependencyAction
                    )
                    .padding(.bottom, 12)
                }

                ModelLibraryPanel(
                    compact: false,
                    summaryTitle: store.modelLibrarySummaryTitle,
                    summaryDetail: store.modelLibrarySummaryDetail,
                    items: store.modelLibraryDisplayItems,
                    installModel: store.installInstallerModelNow
                )
            }

            ControlCenterCard(
                title: "Suggested first downloads",
                subtitle: "These are the easiest good picks for this Mac if you want OnlyMacs ready quickly."
            ) {
                InstallerRecommendationsPanel(
                    assessment: store.capabilityAssessment,
                    capabilitySnapshot: store.capabilitySnapshot,
                    plan: store.installerPlan,
                    catalogError: store.catalogError,
                    items: store.setupVisibleModelRecommendations,
                    selectedModelIDs: store.selectedInstallerModelIDs,
                    installableModelIDs: store.installableInstallerModelIDs,
                    installedModelIDs: store.installedInstallerModelIDs,
                    diskBlockedModelIDs: store.diskBlockedInstallerModelIDs,
                    queueItems: store.installerQueueDisplayItems,
                    isInstalling: store.isInstallingStarterModels,
                    statusDetail: store.starterModelStatusDetail ?? (store.starterModelCompletionDetail == nil ? store.starterModelSetupSummary : nil),
                    completionDetail: store.starterModelCompletionDetail,
                    toggleSelection: store.toggleInstallerModelSelection,
                    resetSelections: store.resetInstallerSelectionsNow,
                    installSelectedModels: store.installSelectedStarterModelsNow
                )
            }
        }
    }
}

struct ControlCenterSwarmSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        ControlCenterPage(
            eyebrow: "Swarms",
            title: "Choose where this Mac connects",
            subtitle: "Switch between OnlyMacs Public and your private swarms without digging through settings."
        ) {
            ControlCenterCard(
                title: "Your name",
                subtitle: "Use a friendly label so every tester can see who is sharing and who is busy."
            ) {
                MemberIdentityPanel(
                    compact: false,
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

            ControlCenterCard(
                title: "SWARM SELECT",
                subtitle: "See the swarm this Mac is connected to now, and switch when you are ready."
            ) {
                SwarmSelectionPanel(
                    compact: false,
                    activeSwarm: store.activeRuntimeSwarm,
                    pendingSwarm: store.selectedSwarm,
                    swarms: store.snapshot.swarms,
                    selectedSwarmID: Binding(
                        get: { store.selectedSwarmID },
                        set: { store.setSelectedSwarmDraftNow($0) }
                    ),
                    activeSessionCount: store.snapshot.swarm.activeSessionCount,
                    isLoading: store.isLoading,
                    hasPendingChanges: store.hasPendingRuntimeChanges,
                    applyLabel: "Connect To Selected Swarm",
                    helperText: "OnlyMacs Public is the default open swarm. Private swarms are for named invite-only groups you create or join.",
                    applyChanges: store.applyRuntimeNow
                )
            }

            ControlCenterCard(
                title: "CURRENT SWARM",
                subtitle: "Live capacity, members, and unique models offered by the connected swarm."
            ) {
                CurrentSwarmMembersPanel(
                    compact: false,
                    activeSwarmID: store.snapshot.runtime.activeSwarmID,
                    activeSwarmName: store.snapshot.bridge.activeSwarmName ?? "No current swarm connected",
                    swarm: store.snapshot.swarm,
                    members: store.snapshot.members
                )
            }

            if store.activeRuntimeSwarm?.allowsInviteSharing == true {
                ControlCenterCard(
                    title: "Share",
                    subtitle: "Invite link and QR code for this private swarm."
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
                        compact: false,
                        createInvite: store.createInviteNow,
                        copyToken: store.copyLatestInviteToken,
                        copyLink: store.copyInviteLink,
                        copyInviteMessage: store.copyInviteMessage
                    )
                }
            }

            ControlCenterCard(
                title: "Available swarms",
                subtitle: "Tap any swarm below to connect this Mac to it."
            ) {
                CompactSwarmDirectoryPanel(
                    compact: false,
                    swarms: store.snapshot.swarms,
                    activeSwarmID: store.snapshot.runtime.activeSwarmID,
                    activeSessionCount: store.snapshot.swarm.activeSessionCount,
                    members: store.snapshot.members,
                    connectToSwarm: store.connectToSwarmNow
                )
            }

            ControlCenterCard(
                title: "Private swarms",
                subtitle: "Make one for friends, or join one with an invite code."
            ) {
                SwarmInviteManagementPanel(
                    compact: false,
                    slotsFree: nil,
                    slotsTotal: nil,
                    modelCount: nil,
                    activeSessionCount: nil,
                    activePrivateSwarmName: store.activeRuntimeSwarm?.isPublic == false ? store.activeRuntimeSwarm?.name : nil,
                    showsInviteControls: false,
                    newSwarmName: $store.newSwarmName,
                    createSwarmLabel: store.isLoading ? "Creating…" : "Create Private Swarm",
                    createInviteLabel: store.isLoading ? "Creating…" : "Create Invite",
                    joinInviteToken: $store.joinInviteToken,
                    joinLabel: store.isLoading ? "Joining…" : "Join Private Swarm",
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
            }
        }
    }
}

struct ControlCenterToolSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        ControlCenterPage(
            eyebrow: "Tools",
            title: "Integrations and launchers",
            subtitle: "Keep Codex, Claude Code, and terminal-friendly editors ready to use OnlyMacs."
        ) {
            ControlCenterCard(
                title: "Tooling",
                subtitle: store.toolIntegrationPrimaryDetail
            ) {
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
    }
}

struct ControlCenterHowToUseSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        ControlCenterPage(
            eyebrow: "How To Use",
            title: "Paste project-ready /onlymacs recipes",
            subtitle: "Public uses approved text/source excerpts, private handles real repo-aware work, and local-first keeps sensitive paths on This Mac."
        ) {
            ControlCenterCard(
                title: "Project recipes",
                subtitle: "Paste these into Codex or Claude Code with your project already open, then edit the wording for your actual task and route."
            ) {
                HowToUseRecipesPanel(
                    strategies: store.howToUseStrategyItems,
                    items: store.howToUseRecipeItems,
                    parameters: store.howToUseParameterItems,
                    copyCommand: store.copyCommand
                )
            }
        }
    }
}

struct ControlCenterRuntimeSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        ControlCenterPage(
            eyebrow: "Runtime",
            title: "Tools and runtime",
            subtitle: "Fix launcher, startup, runtime, and coordinator problems from one place."
        ) {
            ControlCenterCard(
                title: "Launchers",
                subtitle: "Install or refresh the command and assistant integrations."
            ) {
                LauncherCommandPanel(
                    compact: false,
                    statusLabel: store.launcherStatusLabel,
                    menuBarStateTitle: store.menuBarStateTitle,
                    menuBarStateDetail: store.menuBarStateDetail,
                    localEligibilityTitle: store.localEligibilitySummary.title,
                    localEligibilityDetail: store.localEligibilitySummary.detail,
                    shimDirectoryPath: store.launcherStatus.shimDirectoryURL.path,
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
                    guidanceHeading: "Trust And Premium Guidance",
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

            ControlCenterCard(
                title: "Run on startup",
                subtitle: "Choose whether OnlyMacs opens automatically after your Mac restarts."
            ) {
                StartupPreferencePanel(
                    compact: false,
                    isEnabled: store.launchAtLoginEnabled,
                    statusTitle: store.launchAtLoginStatusTitle,
                    detail: store.launchAtLoginDetail,
                    setEnabled: store.setLaunchAtLoginNow
                )
            }

            ControlCenterCard(
                title: "Coordinator connection",
                subtitle: "Keep OnlyMacs connected to the hosted coordinator used for shared swarms."
            ) {
                CoordinatorConnectionPanel(
                    compact: false,
                    coordinatorURLDraft: $store.coordinatorURLDraft,
                    effectiveTarget: store.effectiveCoordinatorTarget,
                    validationError: store.coordinatorSettings.validationError,
                    isRuntimeBusy: store.isRuntimeBusy,
                    hasPendingChanges: store.hasPendingCoordinatorChanges,
                    recoveryMessage: store.coordinatorRecoveryMessage,
                    applyLabel: "Save And Restart Runtime",
                    retryLabel: "Retry Hosted Connection",
                    openLogsLabel: "Open Runtime Logs",
                    applyChanges: store.applyCoordinatorConnectionNow,
                    retryHosted: store.restartRuntimeNow,
                    openLogs: store.openLogsNow
                )
            }
        }
    }
}

struct SettingsCommandSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        Section("OnlyMacs CLI") {
            LauncherCommandPanel(
                compact: false,
                statusLabel: store.launcherStatusLabel,
                menuBarStateTitle: store.menuBarStateTitle,
                menuBarStateDetail: store.menuBarStateDetail,
                localEligibilityTitle: store.localEligibilitySummary.title,
                localEligibilityDetail: store.localEligibilitySummary.detail,
                shimDirectoryPath: store.launcherStatus.shimDirectoryURL.path,
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
                guidanceHeading: "Trust And Premium Guidance",
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

        Section("Startup") {
            StartupPreferencePanel(
                compact: false,
                isEnabled: store.launchAtLoginEnabled,
                statusTitle: store.launchAtLoginStatusTitle,
                detail: store.launchAtLoginDetail,
                setEnabled: store.setLaunchAtLoginNow
            )
        }
    }
}

struct SettingsSwarmSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        Section("Your Swarm Name") {
            MemberIdentityPanel(
                compact: false,
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

        Section("SWARM SELECT") {
            SwarmSelectionPanel(
                compact: false,
                activeSwarm: store.activeRuntimeSwarm,
                pendingSwarm: store.selectedSwarm,
                swarms: store.snapshot.swarms,
                selectedSwarmID: Binding(
                    get: { store.selectedSwarmID },
                    set: { store.setSelectedSwarmDraftNow($0) }
                ),
                activeSessionCount: store.snapshot.swarm.activeSessionCount,
                isLoading: store.isLoading,
                hasPendingChanges: store.hasPendingRuntimeChanges,
                applyLabel: "Apply Swarm",
                helperText: "OnlyMacs Public is the default open swarm. Private swarms are for named invite-only groups you create or join.",
                applyChanges: store.applyRuntimeNow
            )
        }

        Section("CURRENT SWARM") {
            CurrentSwarmMembersPanel(
                compact: false,
                activeSwarmID: store.snapshot.runtime.activeSwarmID,
                activeSwarmName: store.snapshot.bridge.activeSwarmName ?? "No current swarm connected",
                swarm: store.snapshot.swarm,
                members: store.snapshot.members
            )
        }

        if store.activeRuntimeSwarm?.allowsInviteSharing == true {
            Section("Share") {
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
                    compact: false,
                    createInvite: store.createInviteNow,
                    copyToken: store.copyLatestInviteToken,
                    copyLink: store.copyInviteLink,
                    copyInviteMessage: store.copyInviteMessage
                )
            }
        }

        Section("Swarm Actions") {
            SwarmInviteManagementPanel(
                compact: false,
                slotsFree: nil,
                slotsTotal: nil,
                modelCount: nil,
                activeSessionCount: nil,
                activePrivateSwarmName: store.activeRuntimeSwarm?.isPublic == false ? store.activeRuntimeSwarm?.name : nil,
                showsInviteControls: false,
                newSwarmName: $store.newSwarmName,
                createSwarmLabel: store.isLoading ? "Creating…" : "Create Private Swarm And Join",
                createInviteLabel: store.isLoading ? "Creating…" : "Create Invite",
                joinInviteToken: $store.joinInviteToken,
                joinLabel: store.isLoading ? "Joining…" : "Join Private Swarm",
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
        }

        Section("Share This Mac") {
            LocalSharePublishingPanel(
                compact: false,
                status: store.localShare.status,
                published: store.localShare.published,
                swarmName: store.localShare.activeSwarmName,
                activeSessions: store.localShare.activeSessions,
                servedSessions: store.localShare.servedSessions,
                streamedSessions: store.localShare.servedStreamSessions,
                failedSessions: store.localShare.failedSessions,
                uploadedTokens: store.formattedSavedTokens(store.localShare.uploadedTokensEstimate),
                downloadedTokens: store.formattedSavedTokens(store.snapshot.usage.downloadedTokensEstimate),
                swarmBudget: store.snapshot.usage.reservationCap > 0 ? "\(store.snapshot.usage.activeReservations)/\(store.snapshot.usage.reservationCap)" : nil,
                communityBoostLabel: store.snapshot.usage.communityBoost.metricRowLabel,
                communityBoost: store.snapshot.usage.communityBoost.displayValue,
                communityTrait: store.snapshot.usage.communityBoost.primaryTrait,
                communityDetail: store.snapshot.usage.communityBoost.detail,
                errorMessage: store.localShare.error,
                lastServedModel: store.localShare.lastServedModel,
                failureNote: store.localShareFailureNote(compact: false),
                recentActivity: store.recentProviderActivityDisplayItems,
                models: store.localShare.discoveredModels,
                publishedModelIDs: store.publishedLocalModelIDs,
                isLoading: store.isLoading,
                selectedSwarmID: store.selectedSwarmID,
                publishLabel: store.localShare.published ? "Unpublish This Mac" : "Publish This Mac",
                publishToggle: {
                    if store.localShare.published {
                        store.unpublishThisMacNow()
                    } else {
                        store.publishThisMacNow()
                    }
                }
            )
        }
    }
}

struct SettingsInventorySections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        Section("Model Library") {
            if let presentation = store.modelRuntimeDependencyPresentation {
                ModelRuntimeDependencyBanner(
                    presentation: presentation,
                    action: store.modelRuntimeDependencyAction
                )
            }

            ModelLibraryPanel(
                compact: false,
                summaryTitle: store.modelLibrarySummaryTitle,
                summaryDetail: store.modelLibrarySummaryDetail,
                items: store.modelLibraryDisplayItems,
                installModel: store.installInstallerModelNow
            )
        }

        Section("Detected Tools") {
            DetectedToolsPanel(
                emptyMessage: "No supported tools detected yet.",
                items: store.popupToolDisplayItems
            )
        }

        Section("Exact Models") {
            ExactModelsPanel(
                compact: false,
                emptyMessage: "No models available.",
                items: store.visibleModelDisplayItems
            )
        }
        if let suggestion = store.nextModelSuggestion {
            Section("Suggested Next Model") {
                SuggestedNextModelPanel(
                    detail: "\(suggestion.name) is already available on this Mac. Publish it after your first success to expand what friends can request.",
                    isLoading: store.isLoading,
                    addSuggestedModel: store.publishSuggestedModelNow
                )
            }
        }
    }
}

struct CompactRequesterSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                RequesterHighlightsPanel(
                    compact: false,
                    tokensSaved: store.formattedTokensSaved,
                    downloaded: store.formattedSavedTokens(store.snapshot.usage.downloadedTokensEstimate),
                    uploaded: store.formattedSavedTokens(store.snapshot.usage.uploadedTokensEstimate),
                    swarmBudget: store.snapshot.usage.reservationCap > 0 ? "\(store.snapshot.usage.activeReservations)/\(store.snapshot.usage.reservationCap)" : nil,
                    communityBoostLabel: store.snapshot.usage.communityBoost.metricRowLabel,
                    communityBoost: store.snapshot.usage.communityBoost.displayValue,
                    activeSwarms: store.snapshot.swarm.activeSessionCount,
                    queuedSwarms: store.snapshot.swarm.queuedSessionCount,
                    queuePressureLabel: store.queuePressureLabel,
                    communityTrait: store.snapshot.usage.communityBoost.primaryTrait,
                    communityDetail: store.snapshot.usage.communityBoost.detail,
                    queuePressureDetail: store.queuePressureDetail
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Swarms")
                    .font(.caption.weight(.semibold))
                RecentSwarmsPanel(
                    compact: true,
                    queuePressureLabel: nil,
                    queuePressureDetail: nil,
                emptyMessage: "No swarm sessions yet. Start one from Codex or Claude Code with `onlymacs go ...` and it will appear here.",
                    items: store.compactRecentSwarmDisplayItems
                )
            }
        }
    }
}

struct CompactOperationsSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
    }
}

struct CompactSwarmSections: View {
    @ObservedObject var store: BridgeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Swarm")
                    .font(.caption.weight(.semibold))
                SwarmSelectionPanel(
                    compact: true,
                    activeSwarm: store.activeRuntimeSwarm,
                    pendingSwarm: store.selectedSwarm,
                    swarms: store.snapshot.swarms,
                    selectedSwarmID: Binding(
                        get: { store.selectedSwarmID },
                        set: { store.setSelectedSwarmDraftNow($0) }
                    ),
                    activeSessionCount: store.snapshot.swarm.activeSessionCount,
                    isLoading: store.isLoading,
                    hasPendingChanges: store.hasPendingRuntimeChanges,
                    applyLabel: "Apply Swarm",
                    helperText: "OnlyMacs Public is the default open swarm. Private swarms are for named invite-only groups you create or join.",
                    applyChanges: store.applyRuntimeNow
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
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("This Mac")
                    .font(.caption.weight(.semibold))
                LocalSharePublishingPanel(
                    compact: true,
                    status: store.localShare.status,
                    published: store.localShare.published,
                    swarmName: store.localShare.activeSwarmName,
                    activeSessions: store.localShare.activeSessions,
                    servedSessions: store.localShare.servedSessions,
                    streamedSessions: nil,
                    failedSessions: store.localShare.failedSessions,
                    uploadedTokens: store.formattedSavedTokens(store.localShare.uploadedTokensEstimate),
                    downloadedTokens: nil,
                    swarmBudget: store.snapshot.usage.reservationCap > 0 ? "\(store.snapshot.usage.activeReservations)/\(store.snapshot.usage.reservationCap)" : nil,
                    communityBoostLabel: store.snapshot.usage.communityBoost.metricRowLabel,
                    communityBoost: store.snapshot.usage.communityBoost.displayValue,
                    communityTrait: store.snapshot.usage.communityBoost.primaryTrait,
                    communityDetail: store.snapshot.usage.communityBoost.detail,
                    errorMessage: store.localShare.error,
                    lastServedModel: store.localShare.lastServedModel,
                    failureNote: store.localShareFailureNote(compact: true),
                    recentActivity: store.recentProviderActivityDisplayItems,
                    models: store.localShare.discoveredModels,
                    publishedModelIDs: store.publishedLocalModelIDs,
                    isLoading: store.isLoading,
                    selectedSwarmID: store.selectedSwarmID,
                    publishLabel: store.localShare.published ? "Unpublish This Mac" : "Publish This Mac",
                    publishToggle: {
                        if store.localShare.published {
                            store.unpublishThisMacNow()
                        } else {
                            store.publishThisMacNow()
                        }
                    }
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Exact Models")
                    .font(.caption.weight(.semibold))
                ExactModelsPanel(
                    compact: true,
                    emptyMessage: "No shared models visible yet.",
                    items: store.compactVisibleModelDisplayItems
                )
            }
        }
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.18))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case "ready":
            return .green
        case "degraded":
            return .orange
        default:
            return .secondary
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

struct InviteQRCodePanel: View {
    let payload: InviteLinkPayload

    private static let qrContext = CIContext()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scan To Join")
                .font(.caption.weight(.semibold))

            if let image = qrImage {
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .padding(6)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Point a second Mac at this code and OnlyMacs will open the swarm invite directly.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let coordinatorURL = payload.coordinatorURL {
                            Text("Hosted via \(coordinatorURL)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("OnlyMacs could not render the invite QR right now, but the invite link still works.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var qrImage: NSImage? {
        guard let urlString = payload.appURL?.absoluteString else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(urlString.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = Self.qrContext.createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: outputImage.extent.width, height: outputImage.extent.height))
    }
}
