import OnlyMacsCore
import SwiftUI

// Model and setup presentation surfaces extracted from the broader panel library.

struct SetupAssistantStepDisplayItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbolName: String
    let color: Color
}

struct ModelAvailabilityDisplayItem: Identifiable {
    let id: String
    let name: String
    let identifier: String
    let slotsLabel: String
}

struct InstallerQueueDisplayItem: Identifiable {
    let id: String
    let title: String
    let phaseLabel: String
    let detail: String?
}

enum ModelLibraryGroup: Int, CaseIterable {
    case onThisMac
    case readyToAdd
    case biggerModels
    case needsMoreSpace

    var title: String {
        switch self {
        case .onThisMac:
            return "Installed"
        case .readyToAdd:
            return "Available"
        case .biggerModels:
            return "Available"
        case .needsMoreSpace:
            return "Needs More Disk Space"
        }
    }

    var detail: String {
        switch self {
        case .onThisMac:
            return "Downloaded or currently downloading on this Mac."
        case .readyToAdd:
            return "Fits this Mac now. Higher-memory power models appear first."
        case .biggerModels:
            return "Heavier models this Mac can still handle when you want more power."
        case .needsMoreSpace:
            return "These fit the memory in this Mac, but need more free disk space right now."
        }
    }
}

func modelLibraryGroupOrder(prioritizesPowerModels: Bool) -> [ModelLibraryGroup] {
    [.onThisMac, .readyToAdd, .needsMoreSpace, .biggerModels]
}

struct ModelLibraryDisplayItem: Identifiable {
    let id: String
    let group: ModelLibraryGroup
    let displayName: String
    let exactModelName: String
    let roleLabel: String
    let quantLabel: String
    let recommendationBadge: String?
    let statusTitle: String
    let statusDetail: String
    let statusColor: Color
    let requirementLabel: String
    let downloadLabel: String?
    let actionTitle: String?
    let actionEnabled: Bool
    let showsProgress: Bool
    let isPriorityPowerModel: Bool
    let requiredRAMGB: Int
}

struct SetupAssistantPanel: View {
    enum ActionStyle {
        case full
        case summaryOnly
    }

    let compact: Bool
    let actionStyle: ActionStyle
    let stageTitle: String
    let etaLabel: String
    let progressValue: Double
    let progressLabel: String
    let progressDetail: String?
    let steps: [SetupAssistantStepDisplayItem]
    let isBusy: Bool
    let isLoading: Bool
    let nextModelSuggestionText: String?
    let makeReady: () -> Void
    let publishSuggestedModel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stageTitle)
                        .font((compact ? Font.caption : .headline).weight(.semibold))
                    Text(etaLabel)
                        .font(detailFont)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(progressLabel)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressValue)
                .controlSize(compact ? .small : .regular)

            if let progressDetail, !progressDetail.isEmpty {
                Text(progressDetail)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: step.symbolName)
                        .foregroundStyle(step.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font((compact ? Font.caption : .body).weight(compact ? .medium : .regular))
                        Text(step.detail)
                            .font(detailFont)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if actionStyle == .full {
                HStack {
                    Button(compact && (isBusy || isLoading) ? "Working…" : "Continue") {
                        makeReady()
                    }
                    .disabled(isBusy || isLoading)
                }
            }

            if let nextModelSuggestionText, !nextModelSuggestionText.isEmpty {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggested next model")
                            .font((compact ? Font.caption : .body).weight(.medium))
                        Text(nextModelSuggestionText)
                            .font(detailFont)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let publishSuggestedModel {
                        Button("Add") {
                            publishSuggestedModel()
                        }
                    }
                }
            }
        }
    }

    private var detailFont: Font {
        compact ? .caption2 : .caption
    }
}

struct ExactModelsPanel: View {
    let compact: Bool
    let emptyMessage: String
    let items: [ModelAvailabilityDisplayItem]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if items.isEmpty {
                Text(emptyMessage)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(alignment: compact ? .firstTextBaseline : .top, spacing: 8) {
                        if compact {
                            Text(item.name)
                                .lineLimit(1)
                            Spacer()
                            Text(item.slotsLabel)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text(item.identifier)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.slotsLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(compact ? .caption : .body)
                }
            }
        }
    }

    private var detailFont: Font {
        compact ? .caption : .body
    }
}

struct ModelRuntimeDependencyBanner: View {
    let presentation: ModelRuntimeDependencyPresentation
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action, presentation.isActionable {
                Button(action: action) {
                    bannerContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(presentation.labelTitle))
                .accessibilityHint(Text(presentation.detail))
            } else {
                bannerContent
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("\(presentation.title), \(presentation.labelTitle)"))
                    .accessibilityHint(Text(presentation.detail))
            }
        }
    }

    private var bannerContent: some View {
        let tint = presentation.style.tint

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(presentation.labelTitle)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(presentation.style.badgeBackgroundColor)
                .foregroundStyle(tint)
                .clipShape(Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(presentation.style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ModelLibraryPanel: View {
    let compact: Bool
    let summaryTitle: String
    let summaryDetail: String
    let items: [ModelLibraryDisplayItem]
    let installModel: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            if items.isEmpty {
                Text("No models are ready for this Mac yet.")
                    .font(compact ? .subheadline : .body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupOrder, id: \.rawValue) { group in
                    let groupItems = items
                        .filter { $0.group == group }
                        .sorted(by: modelSort)
                    if !groupItems.isEmpty {
                        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                            Text(groupTitle(group, count: groupItems.count))
                                .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
                            if !compact && group != .onThisMac {
                                Text(group.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(groupItems) { item in
                                modelCard(item)
                            }
                        }
                        .padding(.top, compact ? 4 : 8)
                    }
                }
            }
        }
    }

    private func modelCard(_ item: ModelLibraryDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.displayName)
                            .font((compact ? Font.body : .title3).weight(.semibold))
                            .lineLimit(2)
                        if let recommendationBadge = item.recommendationBadge, !recommendationBadge.isEmpty {
                            Text(recommendationBadge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.14))
                                .clipShape(Capsule())
                        }
                        Spacer(minLength: 8)
                        Text(item.quantLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }

                    if item.exactModelName != item.displayName {
                        Text(item.exactModelName)
                            .font(compact ? .callout : .subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    if item.showsProgress {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let actionTitle = item.actionTitle, !item.showsProgress {
                        Button(actionTitle) {
                            installModel(item.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(compact ? .small : .regular)
                        .disabled(!item.actionEnabled)
                    }
                }
            }

            HStack(spacing: 8) {
                Text(item.statusTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(item.statusColor.opacity(0.14))
                    .foregroundStyle(item.statusColor)
                    .clipShape(Capsule())

                Text(item.requirementLabel)
                    .font(compact ? .callout : .callout)
                    .foregroundStyle(.secondary)

                if let downloadLabel = item.downloadLabel, !downloadLabel.isEmpty {
                    Text(downloadLabel)
                        .font(compact ? .callout : .callout)
                        .foregroundStyle(.secondary)
                }
            }

            if !item.statusDetail.isEmpty {
                Text(item.statusDetail)
                    .font(compact ? .callout : detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 14 : 16)
        .background(Color.secondary.opacity(compact ? 0.08 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous))
    }

    private var detailFont: Font {
        compact ? .caption : .callout
    }

    private var groupOrder: [ModelLibraryGroup] {
        modelLibraryGroupOrder(prioritizesPowerModels: items.contains(where: \.isPriorityPowerModel))
    }

    private func groupTitle(_ group: ModelLibraryGroup, count: Int) -> String {
        switch group {
        case .onThisMac:
            return "Installed (\(count))"
        case .readyToAdd:
            return "Available (\(count))"
        case .biggerModels:
            return "Available (\(count))"
        case .needsMoreSpace:
            return "Needs More Disk Space (\(count))"
        }
    }

    private func modelSort(_ lhs: ModelLibraryDisplayItem, _ rhs: ModelLibraryDisplayItem) -> Bool {
        if lhs.requiredRAMGB != rhs.requiredRAMGB {
            return lhs.requiredRAMGB > rhs.requiredRAMGB
        }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}

struct BridgeOverviewPanel: View {
    let status: String
    let menuBarStateTitle: String
    let menuBarStateDetail: String
    let localEligibilityTitle: String
    let localEligibilityDetail: String
    let jobWorkerTitle: String
    let jobWorkerDetail: String
    let coordinator: String
    let build: String
    let lastUpdated: String
    let errorMessage: String?
    let isLoading: Bool
    let lastSupportBundlePath: String?
    let refresh: () -> Void
    let openLogs: () -> Void
    let copyDiagnostics: () -> Void
    let exportSupportBundle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricRow(label: "Bridge Status", value: status)
            MetricRow(label: "Menu Bar State", value: menuBarStateTitle)
            MetricRow(label: "This Mac Eligibility", value: localEligibilityTitle)
            MetricRow(label: "Job Workers", value: jobWorkerTitle)
            MetricRow(label: "Coordinator", value: coordinator)
            MetricRow(label: "Build", value: build)
            MetricRow(label: "Last Updated", value: lastUpdated)

            Text(menuBarStateDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(localEligibilityDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(jobWorkerDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(isLoading ? "Refreshing…" : "Refresh Bridge Snapshot") {
                refresh()
            }
            .disabled(isLoading)

            HStack {
                Button("Open Logs") {
                    openLogs()
                }
                Button("Copy Diagnostics") {
                    copyDiagnostics()
                }
                Button("Export Support Bundle") {
                    exportSupportBundle()
                }
            }

            if let lastSupportBundlePath, !lastSupportBundlePath.isEmpty {
                Text(lastSupportBundlePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct UpdateStatusPanel: View {
    let currentBuild: String
    let lastChecked: String
    let statusTitle: String
    let statusDetail: String
    let availableBuild: String?
    let isChecking: Bool
    let isDownloading: Bool
    let isInstalling: Bool
    let checkLabel: String
    let actionDetail: String
    let checkForUpdates: () -> Void
    let installUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricRow(label: "Current Build", value: currentBuild)
            MetricRow(label: "Last Checked", value: lastChecked)
            MetricRow(label: "Update Status", value: statusTitle)

            if let availableBuild, !availableBuild.isEmpty {
                MetricRow(label: "Latest Available", value: availableBuild)
            }

            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(isChecking ? "Checking…" : checkLabel) {
                if availableBuild == nil {
                    checkForUpdates()
                } else {
                    installUpdate()
                }
            }
            .disabled(isChecking || isDownloading || isInstalling)

            if availableBuild != nil {
                Button("Check Again") {
                    checkForUpdates()
                }
                .disabled(isChecking || isDownloading || isInstalling)
            }

            Text(actionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InstallerRecommendationsPanel: View {
    let assessment: ProviderCapabilityAssessment?
    let capabilitySnapshot: ProviderCapabilitySnapshot
    let plan: InstallerRecommendationPlan?
    let catalogError: String?
    let items: [InstallerRecommendationItem]
    let selectedModelIDs: Set<String>
    let installableModelIDs: Set<String>
    let installedModelIDs: Set<String>
    let diskBlockedModelIDs: Set<String>
    let queueItems: [InstallerQueueDisplayItem]
    let isInstalling: Bool
    let statusDetail: String?
    let completionDetail: String?
    let toggleSelection: (String) -> Void
    let resetSelections: () -> Void
    let installSelectedModels: () -> Void

    var body: some View {
        if let plan {
            MetricRow(label: "Models That Fit This Mac", value: "\(items.count)")
            MetricRow(label: "Memory", value: "\(capabilitySnapshot.unifiedMemoryGB) GB")
            MetricRow(label: "Free Disk", value: "\(capabilitySnapshot.freeDiskGB) GB")
            MetricRow(label: "Selected Now", value: "\(selectedModelIDs.count) model(s)")
            MetricRow(label: "Download Size", value: String(format: "%.1f GB", selectedDownloadGB))

            Text("OnlyMacs looked at your Mac's memory and free disk space to build this list.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let catalogError, !catalogError.isEmpty {
                Text(catalogError)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else {
                Text("Everything below fits this Mac’s memory. Models that need more free disk space stay visible, but OnlyMacs greys them out until you clear space.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let statusDetail, !statusDetail.isEmpty {
                    Text(statusDetail)
                        .font(.callout)
                        .foregroundStyle(isInstalling ? .blue : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let completionDetail, !completionDetail.isEmpty {
                    Text(completionDetail)
                        .font(.callout)
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("Use Suggested Picks") {
                        resetSelections()
                    }
                    .disabled(isInstalling)

                    Button(isInstalling ? "Downloading…" : "Download Checked Models") {
                        installSelectedModels()
                    }
                    .disabled(isInstalling || selectedModelIDs.isEmpty)
                }

                ForEach(items) { item in
                    InstallerModelRow(
                        item: item,
                        badge: badgeLabel(for: item),
                        selected: selectedModelIDs.contains(item.id),
                        selectable: installableModelIDs.contains(item.id) && !diskBlockedModelIDs.contains(item.id) && !installedModelIDs.contains(item.id),
                        installed: installedModelIDs.contains(item.id),
                        diskBlocked: diskBlockedModelIDs.contains(item.id),
                        toggleSelection: { toggleSelection(item.id) }
                    )
                }

                if !queueItems.isEmpty {
                    Divider()
                    Text("Current Downloads")
                        .font(.headline)
                    ForEach(queueItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.callout.monospaced())
                                Spacer()
                                Text(item.phaseLabel)
                                    .foregroundStyle(.secondary)
                            }
                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                ForEach(plan.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let catalogError, !catalogError.isEmpty {
            Text(catalogError)
                .foregroundStyle(.red)
        } else {
            Text("OnlyMacs is still loading the model list for this Mac.")
                .foregroundStyle(.secondary)
        }
    }

    private func badgeLabel(for item: InstallerRecommendationItem) -> String {
        if installedModelIDs.contains(item.id) {
            return "Installed"
        }
        if diskBlockedModelIDs.contains(item.id) {
            return "Needs Space"
        }
        if !installableModelIDs.contains(item.id) {
            return "Manual"
        }
        if item.selectedByDefault {
            return "Suggested"
        }
        if item.model.advancedVisibility.beastModeEligible {
            return "Large"
        }
        if let recommendationBadge = item.model.installer.recommendationBadge,
           !recommendationBadge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recommendationBadge
        }
        return "Available"
    }

    private var selectedDownloadGB: Double {
        items.reduce(0) { partial, item in
            guard selectedModelIDs.contains(item.id) else { return partial }
            return partial + item.model.installer.estimatedDownloadGB
        }
    }
}

struct SwarmSnapshotPanel: View {
    let activeSwarm: String
    let visibility: String
    let memberCount: Int
    let slotsFree: Int
    let slotsTotal: Int
    let modelCount: Int
    let activeSessionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetricRow(label: "Active Swarm", value: activeSwarm)
            MetricRow(label: "Access", value: visibility)
            MetricRow(label: "Members", value: "\(memberCount)")
            MetricRow(label: "Slots Free", value: "\(slotsFree)")
            MetricRow(label: "Total Slots", value: "\(slotsTotal)")
            MetricRow(label: "Models", value: "\(modelCount)")
            MetricRow(label: "Active Swarms", value: "\(activeSessionCount)")
        }
    }
}

struct DetectedToolsPanel: View {
    let emptyMessage: String
    let items: [DetectedToolDisplayItem]

    var body: some View {
        if items.isEmpty {
            Text(emptyMessage)
                .foregroundStyle(.secondary)
        } else {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(item.statusTitle)
                            .foregroundStyle(item.statusColor)
                    }
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let locationDetail = item.locationDetail, !locationDetail.isEmpty {
                        Text(locationDetail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let actionTitle = item.actionTitle, let performAction = item.performAction {
                        Button(actionTitle) {
                            performAction()
                        }
                    }
                }
            }
        }
    }
}

struct SuggestedNextModelPanel: View {
    let detail: String
    let isLoading: Bool
    let addSuggestedModel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Add Suggested Model") {
                addSuggestedModel()
            }
            .disabled(isLoading)
        }
    }
}

struct InstallerModelRow: View {
    let item: InstallerRecommendationItem
    let badge: String
    let selected: Bool
    let selectable: Bool
    let installed: Bool
    let diskBlocked: Bool
    let toggleSelection: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: toggleSelection) {
                Image(systemName: checkboxSymbolName)
                    .foregroundStyle(checkboxColor)
            }
            .buttonStyle(.plain)
            .disabled(!selectable)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.model.exactModelName)
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectable ? (selected ? .green : .secondary) : .orange)
                }
                Text("\(humanRoleLabel) • \(item.model.quant.label)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("\(item.model.installer.estimatedInstalledGB.formatted(.number.precision(.fractionLength(1)))) GB disk • \(Double(item.model.approximateRAMGB).formatted(.number.precision(.fractionLength(1)))) GB RAM • \(item.model.installer.estimatedDownloadGB.formatted(.number.precision(.fractionLength(1)))) GB download")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(descriptionText)
                    .font(.callout)
                    .foregroundStyle(selectable ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if let runtimeModelID = item.model.proofRuntimeModelID, !runtimeModelID.isEmpty {
                    Text("Local install name: \(runtimeModelID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("One-click download is not ready for this model yet.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(selectable || selected ? 1 : 0.62)
    }

    private var humanRoleLabel: String {
        switch item.model.role {
        case .coding:
            return "Best for coding"
        case .general:
            return "General use"
        case .reasoning:
            return "Reasoning"
        case .multimodal:
            return "Images + text"
        }
    }

    private var descriptionText: String {
        if installed {
            return "Already on this Mac. No download is needed."
        }
        if diskBlocked {
            return "Fits this Mac, but you need more free disk space before OnlyMacs can add it."
        }
        if !selectable {
            return "You can see this model now, but OnlyMacs cannot download it with one click yet."
        }
        if selected {
            return "Checked now, so OnlyMacs will download it during setup."
        }
        return item.reason
    }

    private var checkboxSymbolName: String {
        if installed {
            return "checkmark.square.fill"
        }
        return selected ? "checkmark.square.fill" : "square"
    }

    private var checkboxColor: Color {
        if installed {
            return .green
        }
        return selectable ? (selected ? Color.accentColor : Color.secondary) : Color.secondary
    }
}
