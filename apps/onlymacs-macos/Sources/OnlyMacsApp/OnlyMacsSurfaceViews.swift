import SwiftUI
import OnlyMacsCore

struct SwarmSessionCardView: View {
    let title: String
    let status: String
    let resolvedModel: String
    let routeSummary: String?
    let selectionExplanation: String?
    let warningMessage: String?
    let premiumNudge: String?
    let savedTokensLabel: String
    let queueBadge: String?
    let queueDetail: String?
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack {
                Text(title)
                    .font(titleFont.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(status.capitalized)
                    .font(statusFont.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            Text(resolvedModel)
                .font(modelFont.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let routeSummary, !routeSummary.isEmpty {
                Text(routeSummary)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let selectionExplanation, !selectionExplanation.isEmpty {
                Text(selectionExplanation)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let warningMessage, !warningMessage.isEmpty {
                Text(warningMessage)
                    .font(detailFont.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let premiumNudge, !premiumNudge.isEmpty {
                Text(premiumNudge)
                    .font(detailFont.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(savedTokensLabel)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                Spacer()
                if let queueBadge, !queueBadge.isEmpty {
                    Text(queueBadge)
                        .font(detailFont)
                        .foregroundStyle(.orange)
                }
            }

            if let queueDetail, !queueDetail.isEmpty {
                Text(queueDetail)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 8 : 10)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
    }

    private var statusColor: Color {
        switch status {
        case "running":
            return .green
        case "queued":
            return .orange
        default:
            return .secondary
        }
    }

    private var titleFont: Font {
        compact ? .caption : .body
    }

    private var statusFont: Font {
        compact ? .caption2 : .caption
    }

    private var modelFont: Font {
        compact ? .caption2 : .caption
    }

    private var detailFont: Font {
        compact ? .caption2 : .caption
    }

    private var cardBackground: some ShapeStyle {
        Color.secondary.opacity(compact ? 0.08 : 0.06)
    }
}

struct InviteControlsPanel: View {
    let inviteToken: String
    let inviteLinkString: String
    let inviteShareMessage: String
    let canShareInvite: Bool
    let invitePayload: InviteLinkPayload?
    let inviteStatusTitle: String?
    let inviteStatusDetail: String?
    let inviteExpiryDetail: String?
    let inviteRecoveryMessage: String?
    let compact: Bool
    let copyToken: () -> Void
    let copyLink: () -> Void
    let copyInviteMessage: () -> Void

    var body: some View {
        if !inviteToken.isEmpty {
            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                tokenRow

                if !inviteLinkString.isEmpty {
                    linkRow
                }

                actionRow

                if let invitePayload {
                    InviteQRCodePanel(payload: invitePayload)
                }

                if let inviteStatusTitle, let inviteStatusDetail {
                    VStack(alignment: .leading, spacing: 4) {
                        MetricRow(label: "Invite Status", value: inviteStatusTitle)
                        Text(inviteStatusDetail)
                            .font(detailFont)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let inviteExpiryDetail, !inviteExpiryDetail.isEmpty {
                    Text(inviteExpiryDetail)
                        .font(detailFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let inviteRecoveryMessage, !inviteRecoveryMessage.isEmpty {
                    Text(inviteRecoveryMessage)
                        .font(detailFont)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var tokenRow: some View {
        HStack {
            Text(inviteToken)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
            Button("Copy") {
                copyToken()
            }
            .buttonStyle(buttonStyle)
            .disabled(!canShareInvite)
        }
    }

    private var linkRow: some View {
        HStack {
            Text(inviteLinkString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
            Button("Copy Link") {
                copyLink()
            }
            .buttonStyle(buttonStyle)
            .disabled(!canShareInvite)
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Copy Invite") {
                copyInviteMessage()
            }
            .buttonStyle(buttonStyle)
            .disabled(!canShareInvite)

            ShareLink(item: inviteShareMessage, subject: Text("Join my OnlyMacs swarm")) {
                Text("Share Invite")
            }
            .disabled(!canShareInvite)
        }
    }

    private var detailFont: Font {
        compact ? .caption2 : .caption
    }

    private var buttonStyle: BorderlessButtonStyle {
        .init()
    }
}

struct SwarmSharePanel: View {
    let activeSwarm: SwarmOption?
    let createInviteLabel: String
    let isLoading: Bool
    let canCreateInvite: Bool
    let inviteToken: String
    let inviteLinkString: String
    let inviteShareMessage: String
    let canShareInvite: Bool
    let invitePayload: InviteLinkPayload?
    let inviteStatusTitle: String?
    let inviteStatusDetail: String?
    let inviteExpiryDetail: String?
    let inviteRecoveryMessage: String?
    let compact: Bool
    let createInvite: () -> Void
    let copyToken: () -> Void
    let copyLink: () -> Void
    let copyInviteMessage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            if activeSwarm?.allowsInviteSharing == true {
                if canShareInvite {
                    InviteControlsPanel(
                        inviteToken: inviteToken,
                        inviteLinkString: inviteLinkString,
                        inviteShareMessage: inviteShareMessage,
                        canShareInvite: canShareInvite,
                        invitePayload: invitePayload,
                        inviteStatusTitle: inviteStatusTitle,
                        inviteStatusDetail: inviteStatusDetail,
                        inviteExpiryDetail: inviteExpiryDetail,
                        inviteRecoveryMessage: inviteRecoveryMessage,
                        compact: compact,
                        copyToken: copyToken,
                        copyLink: copyLink,
                        copyInviteMessage: copyInviteMessage
                    )
                } else {
                    HStack {
                        Text("No invite is ready for this swarm.")
                            .font(detailFont)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(createInviteLabel) {
                            createInvite()
                        }
                        .disabled(isLoading || !canCreateInvite)
                        .accessibilityLabel("Create Invite")
                    }
                }
            } else {
                Text("Only private swarms use invite links.")
                    .font(detailFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailFont: Font {
        compact ? .caption : .body
    }
}

struct ModeSelectionPanel: View {
    let compact: Bool
    @Binding var selectedMode: AppMode
    let isLoading: Bool
    let hasPendingChanges: Bool
    let applyLabel: String
    let lockedMode: AppMode?
    let helperText: String?
    let applyChanges: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            modePicker

            Button(isLoading ? "Applying…" : applyLabel) {
                applyChanges()
            }
            .disabled(isLoading || !hasPendingChanges || lockedMode != nil)

            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var modePicker: some View {
        if let lockedMode {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lockedMode.title)
                        .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                    Text("Required for the public swarm")
                        .font(detailFont)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 10 : 12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            let picker = Picker(compact ? "Mode" : "App Mode", selection: $selectedMode) {
                ForEach(AppMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if compact {
                picker.pickerStyle(.segmented)
            } else {
                picker.pickerStyle(.inline)
            }
        }
    }

    private var detailFont: Font {
        compact ? .caption : .caption
    }
}

struct SwarmSelectionPanel: View {
    let compact: Bool
    let activeSwarm: SwarmOption?
    let pendingSwarm: SwarmOption?
    let swarms: [SwarmOption]
    @Binding var selectedSwarmID: String
    let activeSessionCount: Int
    let isLoading: Bool
    let hasPendingChanges: Bool
    let applyLabel: String
    let helperText: String?
    let applyChanges: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if let activeSwarm {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(activeSwarm.name)
                            .font(compact ? .caption.weight(.semibold) : .body.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(activeSwarm.visibilityBadgeTitle)
                            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(activeSwarm.isPublic ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(activeSwarm.selectionDetail(activeSessionCount: activeSessionCount))
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(activeSwarm.accessDetail)
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pendingSwarm, pendingSwarm.id != activeSwarm.id {
                        Text("Pending switch: \(pendingSwarm.name). Press \(applyLabel) to connect to it.")
                            .font(compact ? .caption2 : .caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(compact ? 8 : 10)
                .background(Color.secondary.opacity(compact ? 0.08 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
            } else if let pendingSwarm {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pending Swarm")
                        .font(compact ? .caption.weight(.semibold) : .body.weight(.semibold))
                    Text(pendingSwarm.name)
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                    Text("Press \(applyLabel) to connect.")
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(.orange)
                }
                .padding(compact ? 8 : 10)
                .background(Color.secondary.opacity(compact ? 0.08 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
            } else {
                Text("No active swarm selected yet.")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(.secondary)
            }

            if swarms.isEmpty {
                Text("No swarms available yet.")
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
            } else {
                let picker = Picker(compact ? "Switch Swarm" : "Choose Active Swarm", selection: $selectedSwarmID) {
                    Text("No Active Swarm").tag("")
                    ForEach(swarms) { swarm in
                        if compact {
                            Text(swarm.pickerTitle).tag(swarm.id)
                        } else {
                            Text("\(swarm.pickerTitle) (\(swarm.memberCount) members, \(swarm.slotSummaryLabel))").tag(swarm.id)
                        }
                    }
                }
                if compact {
                    picker.pickerStyle(.menu)
                } else {
                    picker.pickerStyle(.inline)
                }
            }

            Button(isLoading ? "Applying…" : applyLabel) {
                applyChanges()
            }
            .disabled(isLoading || !hasPendingChanges)
            .accessibilityLabel("Apply Swarm")
            .accessibilityHint("Connect this Mac to the selected swarm.")
            .accessibilityIdentifier("onlymacs.swarm.apply")

            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MemberIdentityPanel: View {
    let compact: Bool
    @Binding var memberName: String
    let currentMemberID: String
    let hasPendingChanges: Bool
    let isLoading: Bool
    let isConfirmationPending: Bool
    let saveName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 8) {
                TextField("Kevin", text: $memberName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("OnlyMacs Member Name")
                    .accessibilityIdentifier("onlymacs.memberName.field")
                Button(isLoading ? "Saving..." : "Save") {
                    saveName()
                }
                .disabled(isLoading || !hasPendingChanges || memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Save OnlyMacs Name")
                .accessibilityIdentifier("onlymacs.memberName.save")
            }

            if isConfirmationPending {
                Text("Confirming \(memberName.trimmingCharacters(in: .whitespacesAndNewlines))...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !currentMemberID.isEmpty {
                Text(currentMemberID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

struct CurrentSwarmMembersPanel: View {
    let compact: Bool
    let activeSwarmID: String
    let activeSwarmName: String
    let swarm: SwarmCapacitySummary
    let members: [SwarmMemberSummary]

    private let statColumns = [GridItem(.adaptive(minimum: 132), spacing: 8)]
    private let modelColumns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT SWARM")
                        .font(compact ? .caption.weight(.semibold) : .body.weight(.semibold))
                    Text(activeSwarmName)
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(members.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                    .accessibilityLabel("\(members.count) swarm members")
            }

            if !hasActiveSwarm {
                Text("No current swarm connected...")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: compact ? 56 : 96, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                LazyVGrid(columns: statColumns, alignment: .leading, spacing: 8) {
                    CurrentSwarmStatPill(label: "Total RAM", value: totalRAMLabel)
                    CurrentSwarmStatPill(label: "Total Slots", value: "\(swarm.slotsTotal)")
                    CurrentSwarmStatPill(label: "Total Open Slots", value: "\(swarm.slotsFree)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Members")
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))

                    if currentMembers.isEmpty {
                        Text("No live members are visible for this swarm yet.")
                            .font(compact ? .caption2 : .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if compact {
                        VStack(spacing: 6) {
                            ForEach(currentMembers.prefix(4)) { member in
                                CompactSwarmMemberRow(member: member)
                            }
                        }
                        if currentMembers.count > 4 {
                            Text("\(currentMembers.count - 4) more in Settings.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 8) {
                            ForEach(currentMembers) { member in
                                CurrentSwarmMemberPill(member: member)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Models")
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))

                    if uniqueModelNames.isEmpty {
                        Text("No models advertised by this swarm yet.")
                            .font(compact ? .caption2 : .caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: modelColumns, alignment: .leading, spacing: 8) {
                            ForEach(uniqueModelNames, id: \.self) { model in
                                Text(model)
                                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private var hasActiveSwarm: Bool {
        !activeSwarmID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentMembers: [SwarmMemberSummary] {
        guard hasActiveSwarm else { return [] }
        let filtered = members.filter { $0.swarmID == activeSwarmID }
        return filtered.isEmpty ? members : filtered
    }

    private var totalRAMLabel: String {
        let memoryValues = currentMembers.compactMap { $0.hardware?.memoryGB }.filter { $0 > 0 }
        guard !memoryValues.isEmpty else { return "Unknown" }
        return "\(memoryValues.reduce(0, +))GB"
    }

    private var uniqueModelNames: [String] {
        var namesByKey: [String: String] = [:]
        for member in currentMembers {
            let memberModels = [member.activeModel, member.bestModel].compactMap { $0 }
            for name in memberModels {
                addModelName(name, to: &namesByKey)
            }
            for capability in member.capabilities {
                let capabilityModels = [capability.activeModel, capability.bestModel].compactMap { $0 } + capability.models.map(\.name)
                for name in capabilityModels {
                    addModelName(name, to: &namesByKey)
                }
            }
        }
        return namesByKey.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func addModelName(_ rawName: String, to namesByKey: inout [String: String]) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        namesByKey[name.lowercased()] = name
    }
}

private struct CurrentSwarmStatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CurrentSwarmMemberPill: View {
    let member: SwarmMemberSummary

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.memberName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(member.currentSwarmStatusLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

            CurrentSwarmMemberMetric(label: "tokens/s", value: member.currentSwarmTokenRateLabel)
            CurrentSwarmMemberMetric(label: "slots", value: "\(member.currentSwarmTotalSlots)")
            CurrentSwarmMemberMetric(label: "free", value: "\(member.currentSwarmFreeSlots)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("\(member.memberName), \(member.currentSwarmStatusLabel), \(member.currentSwarmTokenRateLabel), \(member.currentSwarmFreeSlots) of \(member.currentSwarmTotalSlots) slots free")
    }

    private var indicatorColor: Color {
        if member.activeJobsServing > 0 {
            return .blue
        }
        if member.currentSwarmFreeSlots > 0 {
            return .green
        }
        return .secondary
    }
}

private struct CurrentSwarmMemberMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 58, alignment: .trailing)
    }
}

private extension SwarmMemberSummary {
    var currentSwarmStatusLabel: String {
        if activeJobsServing > 0, activeJobsConsuming > 0 {
            return "Working + Requesting"
        }
        if activeJobsServing > 0 {
            return "Working"
        }
        if activeJobsConsuming > 0 {
            return "Requesting"
        }

        let maintenance = maintenanceState?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch maintenance?.isEmpty == false ? maintenance! : status {
        case "installing_model":
            return "Installing Model"
        case "importing_model":
            return "Importing Model"
        case "updating_app":
            return "Updating"
        case "available", "serving", "serving_and_using":
            return "Idle"
        case "using":
            return "Requesting"
        default:
            return isAvailableInSwarm ? "Idle" : statusTitle
        }
    }

    var currentSwarmTokenRateLabel: String {
        let directRate = max(0, recentUploadedTokensPerSecond ?? 0)
        let capabilityRate = capabilities.reduce(0) { partial, capability in
            partial + max(0, capability.recentUploadedTokensPerSecond ?? 0)
        }
        return formatCurrentSwarmTokensPerSecond(max(directRate, capabilityRate)) ?? "0"
    }

    var currentSwarmTotalSlots: Int {
        capabilities.reduce(0) { $0 + max(0, $1.slots.total) }
    }

    var currentSwarmFreeSlots: Int {
        capabilities.reduce(0) { $0 + max(0, $1.slots.free) }
    }
}

private func formatCurrentSwarmTokensPerSecond(_ tokensPerSecond: Double) -> String? {
    guard tokensPerSecond.isFinite else { return nil }
    let normalized = max(0, tokensPerSecond)
    guard normalized >= 0.1 else { return nil }

    if normalized >= 1_000 {
        let value = String(format: "%.1f", normalized / 1_000).replacingOccurrences(of: ".0", with: "")
        return "\(value)K"
    }
    if normalized >= 10 {
        return "\(Int(normalized.rounded()))"
    }
    let value = String(format: "%.1f", normalized).replacingOccurrences(of: ".0", with: "")
    return value
}

struct CompactSwarmMemberRow: View {
    let member: SwarmMemberSummary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: member.isActiveInSwarm || member.isAvailableInSwarm ? "circle.fill" : "circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(indicatorColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.memberName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(member.hardwareLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 150, alignment: .trailing)
        }
    }

    private var indicatorColor: Color {
        if member.isActiveInSwarm {
            return .blue
        }
        if member.isAvailableInSwarm {
            return .green
        }
        return .secondary
    }

    private var statusLine: String {
        if member.isActiveInSwarm {
            return "\(member.statusTitle) / \(member.totalModelsAvailable) models"
        }
        return "\(member.statusTitle) / \(member.totalModelsAvailable) models / \(member.bestModel ?? "No model")"
    }
}

private struct SwarmMemberHeaderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Member").frame(width: 150, alignment: .leading)
            Text("Serving").frame(width: 58, alignment: .trailing)
            Text("Using").frame(width: 50, alignment: .trailing)
            Text("Models").frame(width: 54, alignment: .trailing)
            Text("Best Model").frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            Text("Hardware").frame(width: 190, alignment: .leading)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct SwarmMemberDetailRow: View {
    let member: SwarmMemberSummary
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.memberName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(member.statusTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 150, alignment: .leading)
                    Text("\(member.activeJobsServing)").frame(width: 58, alignment: .trailing)
                    Text("\(member.activeJobsConsuming)").frame(width: 50, alignment: .trailing)
                    Text("\(member.totalModelsAvailable)").frame(width: 54, alignment: .trailing)
                    Text(member.bestModel ?? "None")
                        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Text(member.hardwareLabel)
                        .frame(width: 190, alignment: .leading)
                        .lineLimit(1)
                }
                .font(.caption)
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(member.memberName), \(member.statusTitle), \(member.totalModelsAvailable) models")

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if member.capabilities.isEmpty {
                        Text("No shared provider is published for this member right now.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(member.capabilities) { capability in
                            Text("\(capability.providerName): \(capability.slots.free)/\(capability.slots.total) slots, \(capability.modelCount) models\(capability.bestModel.map { ", best \($0)" } ?? "")")
                                .lineLimit(2)
                        }
                    }
                }
                .font(.caption2)
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }
        }
    }
}


struct StartupPreferencePanel: View {
    let compact: Bool
    let isEnabled: Bool
    let statusTitle: String
    let detail: String
    var showsDetail = true
    let setEnabled: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Button {
                setEnabled(!isEnabled)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Run on Startup")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(statusTitle)
                            .font(compact ? .caption2 : .caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    PersistentAccentSwitch(isOn: isEnabled)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Run on Startup")
            .accessibilityValue(isEnabled ? "On" : "Off")
            .accessibilityHint("Choose whether OnlyMacs launches automatically when this Mac starts.")
            .accessibilityIdentifier("onlymacs.settings.runOnStartup")

            if showsDetail {
                Text(detail)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PersistentAccentSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.28))
                .frame(width: 48, height: 30)
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)
                .padding(3)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isOn)
        .accessibilityHidden(true)
    }
}

private enum PrivateSwarmCompactMode: Equatable {
    case create
    case join
}

struct SwarmInviteManagementPanel: View {
    let compact: Bool
    let slotsFree: Int?
    let slotsTotal: Int?
    let modelCount: Int?
    let activeSessionCount: Int?
    let activePrivateSwarmName: String?
    let showsInviteControls: Bool
    @Binding var newSwarmName: String
    let createSwarmLabel: String
    let createInviteLabel: String
    @Binding var joinInviteToken: String
    let joinLabel: String
    let isLoading: Bool
    let canCreateInvite: Bool
    let inviteToken: String
    let inviteLinkString: String
    let inviteShareMessage: String
    let canShareInvite: Bool
    let inviteHelperText: String?
    let invitePayload: InviteLinkPayload?
    let inviteStatusTitle: String?
    let inviteStatusDetail: String?
    let inviteExpiryDetail: String?
    let inviteRecoveryMessage: String?
    let createSwarm: () -> Void
    let createInvite: () -> Void
    let joinSwarm: () -> Void
    let copyToken: () -> Void
    let copyLink: () -> Void
    let copyInviteMessage: () -> Void
    @State private var compactMode: PrivateSwarmCompactMode?

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(privateSwarmTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button("Create") {
                    compactMode = compactMode == .create ? nil : .create
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Join") {
                    compactMode = compactMode == .join ? nil : .join
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if compactMode == .create {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name your private swarm", text: $newSwarmName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Private Swarm Name")
                        .accessibilityIdentifier("onlymacs.swarm.create.nameField")
                    HStack {
                        Button(isLoading ? "Creating..." : "Create") {
                            createSwarm()
                        }
                        .disabled(isLoading || newSwarmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Create Private Swarm")
                        .accessibilityIdentifier("onlymacs.swarm.create")

                        Button(createInviteLabel) {
                            createInvite()
                        }
                        .disabled(isLoading || !canCreateInvite)
                        .accessibilityLabel("Create Invite")
                        .accessibilityIdentifier("onlymacs.swarm.createInvite")
                    }
                }
            } else if compactMode == .join {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Paste invite token", text: $joinInviteToken)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Private Swarm Invite Token")
                        .accessibilityIdentifier("onlymacs.swarm.join.tokenField")
                    Button(isLoading ? "Joining..." : "Join") {
                        joinSwarm()
                    }
                    .disabled(isLoading || joinInviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Join Private Swarm")
                    .accessibilityIdentifier("onlymacs.swarm.join")
                }
            }

            if showsInviteControls {
                inviteControls
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let slotsFree, let slotsTotal, let modelCount, let activeSessionCount {
                MetricRow(label: "Slots Free", value: "\(slotsFree)")
                MetricRow(label: "Total Slots", value: "\(slotsTotal)")
                MetricRow(label: "Models", value: "\(modelCount)")
                MetricRow(label: "Active Sessions", value: "\(activeSessionCount)")
            }

            if let activePrivateSwarmName, !activePrivateSwarmName.isEmpty {
                Label("Connected to \(activePrivateSwarmName)", systemImage: "lock.fill")
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Make a private swarm")
                    .font(.headline.weight(.semibold))
                TextField("Name your private swarm", text: $newSwarmName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Private Swarm Name")
                    .accessibilityIdentifier("onlymacs.swarm.create.nameField")
                HStack {
                    Button(createSwarmLabel) {
                        createSwarm()
                    }
                    .disabled(isLoading || newSwarmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Create Private Swarm")
                    .accessibilityIdentifier("onlymacs.swarm.create")

                    Button(createInviteLabel) {
                        createInvite()
                    }
                    .disabled(isLoading || !canCreateInvite)
                    .accessibilityLabel("Create Invite")
                    .accessibilityIdentifier("onlymacs.swarm.createInvite")
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Join with an invite")
                    .font(.headline.weight(.semibold))
                TextField("Paste an invite token", text: $joinInviteToken)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Private Swarm Invite Token")
                    .accessibilityIdentifier("onlymacs.swarm.join.tokenField")
                Button(joinLabel) {
                    joinSwarm()
                }
                .disabled(isLoading || joinInviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Join Private Swarm")
                .accessibilityIdentifier("onlymacs.swarm.join")
            }
            .padding(14)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if showsInviteControls {
                inviteControls
            }
        }
    }

    private var inviteControls: some View {
        InviteControlsPanel(
            inviteToken: inviteToken,
            inviteLinkString: inviteLinkString,
            inviteShareMessage: inviteShareMessage,
            canShareInvite: canShareInvite,
            invitePayload: invitePayload,
            inviteStatusTitle: inviteStatusTitle,
            inviteStatusDetail: inviteStatusDetail,
            inviteExpiryDetail: inviteExpiryDetail,
            inviteRecoveryMessage: inviteRecoveryMessage,
            compact: compact,
            copyToken: copyToken,
            copyLink: copyLink,
            copyInviteMessage: copyInviteMessage
        )
    }

    private var privateSwarmTitle: String {
        "Private Swarms"
    }
}

struct LocalSharePublishingPanel: View {
    let compact: Bool
    let status: String
    let published: Bool
    let swarmName: String?
    let activeSessions: Int
    let servedSessions: Int
    let streamedSessions: Int?
    let failedSessions: Int
    let uploadedTokens: String
    let downloadedTokens: String?
    let swarmBudget: String?
    let communityBoostLabel: String
    let communityBoost: String
    let communityTrait: String?
    let communityDetail: String
    let errorMessage: String?
    let lastServedModel: String?
    let failureNote: String?
    let recentActivity: [ProviderServeActivityDisplayItem]
    let models: [ModelSummary]
    let publishedModelIDs: Set<String>
    let isLoading: Bool
    let selectedSwarmID: String
    let publishLabel: String
    let publishToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            ShareHealthSummaryPanel(
                compact: compact,
                status: status,
                published: published,
                swarmName: swarmName,
                activeSessions: activeSessions,
                servedSessions: servedSessions,
                streamedSessions: streamedSessions,
                failedSessions: failedSessions,
                uploadedTokens: uploadedTokens,
                downloadedTokens: downloadedTokens,
                swarmBudget: swarmBudget,
                communityBoostLabel: communityBoostLabel,
                communityBoost: communityBoost,
                communityTrait: communityTrait,
                communityDetail: communityDetail,
                errorMessage: errorMessage,
                lastServedModel: lastServedModel,
                failureNote: failureNote
            )

            ProviderActivityFeedPanel(
                compact: compact,
                items: recentActivity
            )

            if models.isEmpty {
                Text(compact ? "No local Ollama models discovered yet." : "No local Ollama models discovered.")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(compact ? Array(models.prefix(3)) : models) { model in
                    HStack {
                        if compact {
                            Text(model.name)
                                .lineLimit(1)
                            Spacer()
                            Text(model.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                Text(model.id)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if publishedModelIDs.contains(model.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .font(compact ? .caption : .body)
                }
            }

            Button(publishLabel) {
                publishToggle()
            }
            .disabled(isLoading || selectedSwarmID.isEmpty)
        }
    }
}

struct RecentSwarmDisplayItem: Identifiable {
    let id: String
    let title: String
    let status: String
    let resolvedModel: String
    let routeSummary: String?
    let selectionExplanation: String?
    let warningMessage: String?
    let premiumNudge: String?
    let savedTokensLabel: String
    let queueBadge: String?
    let queueDetail: String?
}

struct ProviderServeActivityDisplayItem: Identifiable {
    let id: String
    let title: String
    let statusTitle: String
    let detail: String
    let timestampLabel: String
    let modelLabel: String?
    let sessionLabel: String?
    let tokensLabel: String?
    let warningStyle: Bool
}

struct ProviderActivityFeedPanel: View {
    let compact: Bool
    let items: [ProviderServeActivityDisplayItem]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if items.isEmpty {
                Text("No one has used this Mac through OnlyMacs yet. When a friend or swarm worker runs on this box, it will appear here.")
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(compact ? Array(items.prefix(3)) : items) { item in
                    VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                        HStack {
                            Text(item.title)
                                .font((compact ? Font.caption : .body).weight(.medium))
                            Spacer()
                            Text(item.timestampLabel)
                                .font(detailFont)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(item.statusTitle)
                                .font(detailFont.weight(.semibold))
                                .foregroundStyle(item.warningStyle ? .orange : .secondary)
                            Spacer()
                            if let tokensLabel = item.tokensLabel, !tokensLabel.isEmpty {
                                Text(tokensLabel)
                                    .font(detailFont.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(item.detail)
                            .font(detailFont)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let modelLabel = item.modelLabel, !modelLabel.isEmpty {
                            MetricRow(label: "Model", value: modelLabel)
                        }
                        if let sessionLabel = item.sessionLabel, !sessionLabel.isEmpty {
                            MetricRow(label: "Session", value: sessionLabel)
                        }
                    }
                    .padding(compact ? 8 : 10)
                    .background((item.warningStyle ? Color.orange : Color.secondary).opacity(compact ? 0.08 : 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
                }
            }
        }
    }

    private var detailFont: Font {
        compact ? .caption2 : .caption
    }
}



struct DetectedToolDisplayItem: Identifiable {
    let id: String
    let name: String
    let statusTitle: String
    let statusColor: Color
    let detail: String
    let locationDetail: String?
    let actionTitle: String?
    let performAction: (() -> Void)?
}

struct HowToUseRecipeItem: Identifiable {
    let title: String
    let detail: String
    let command: String
    let section: HowToUseRecipeSection
    let symbolName: String
    let tint: Color

    var id: String { title }
}

struct HowToUseStrategyItem: Identifiable {
    let title: String
    let detail: String
    let routeLabel: String
    let symbolName: String
    let tint: Color

    var id: String { title }
}

struct HowToUseParameterItem: Identifiable {
    let title: String
    let syntax: String
    let kindLabel: String
    let tint: Color
    let detail: String

    var id: String { title }
}

struct SetupLauncherOption: Identifiable {
    let target: LauncherInstallTarget
    let title: String
    let detail: String
    let locationDetail: String
    let available: Bool

    var id: String { target.rawValue }
}

struct ToolIntegrationActionsPanel: View {
    let primaryActionTitle: String
    let primaryDetail: String
    let showReopenAction: Bool
    let installOrRefreshTools: () -> Void
    let reopenTools: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(primaryActionTitle) {
                    installOrRefreshTools()
                }
                .buttonStyle(.borderedProminent)

                if showReopenAction {
                    Button("Open Supported Apps") {
                        reopenTools()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ToolIntegrationCardsPanel: View {
    let items: [DetectedToolDisplayItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.name)
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text(item.statusTitle)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(item.statusColor.opacity(0.14))
                            .foregroundStyle(item.statusColor)
                            .clipShape(Capsule())
                    }

                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let locationDetail = item.locationDetail, !locationDetail.isEmpty {
                        Text(locationDetail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    if let actionTitle = item.actionTitle, let performAction = item.performAction {
                        Button(actionTitle) {
                            performAction()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

struct QuickCommandChipsPanel: View {
    let title: String
    let items: [StarterCommandSuggestion]
    let copyCommand: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    Button(item.title) {
                        copyCommand(item.command)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text("Tap any chip to copy the matching command.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct HowToUseRecipesPanel: View {
    let strategies: [HowToUseStrategyItem]
    let items: [HowToUseRecipeItem]
    let parameters: [HowToUseParameterItem]
    let copyCommand: (String) -> Void
    @State private var selectedSection: HowToUseRecipeSection = .publicSwarm

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Best Ways To Use OnlyMacs")
                    .font(.caption.weight(.semibold))

                Text("Start with the plain `/onlymacs ...` form, then let OnlyMacs decide whether it needs public-safe excerpts, trusted repo access, or a fully local path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(strategies) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
	                            Image(systemName: item.symbolName)
	                                .foregroundStyle(item.tint)
	                            VStack(alignment: .leading, spacing: 4) {
	                                Text(item.title)
	                                    .font(.caption.monospaced().weight(.semibold))
	                                    .textSelection(.enabled)
	                                Text(item.detail)
	                                    .font(.caption)
	                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Text(item.routeLabel)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(item.tint.opacity(0.16))
                                .foregroundStyle(item.tint)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HowToUseRecipeSection.allCases) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    section.tint.opacity(selectedSection == section ? 0.24 : 0.12)
                                )
                                .foregroundStyle(section.tint)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Text(selectedSection.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selectedSection.tint.opacity(0.16))
                    .foregroundStyle(selectedSection.tint)
                    .clipShape(Capsule())
                Text(selectedSection.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if selectedSection == .parameters {
                ForEach(parameters) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(item.title)
                                .font(.body.weight(.semibold))
                            Spacer()
                            Text(item.kindLabel)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(item.tint.opacity(0.16))
                                .foregroundStyle(item.tint)
                                .clipShape(Capsule())
                        }

                        Text(item.syntax)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Copy Syntax") {
                            copyCommand(item.syntax)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            } else {
                ForEach(items.filter { $0.section == selectedSection }) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
	                            Image(systemName: item.symbolName)
	                                .foregroundStyle(item.tint)
	                            VStack(alignment: .leading, spacing: 4) {
	                                Text(item.command)
	                                    .font(.caption.monospaced().weight(.semibold))
	                                    .textSelection(.enabled)
	                                    .fixedSize(horizontal: false, vertical: true)
	                                Text(item.title)
	                                    .font(.caption.weight(.semibold))
	                                    .foregroundStyle(.secondary)
	                                Text(item.detail)
	                                    .font(.caption)
	                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                        }

	                        Button("Copy /onlymacs Recipe") {
	                            copyCommand(item.command)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }
}

struct OnlyMacsActivityDisplayItem {
    let title: String
    let statusTitle: String
    let detail: String
    let timestampLabel: String
    let routeLabel: String?
    let modelLabel: String?
    let sessionLabel: String?
    let warningStyle: Bool
}




struct RecentSwarmsPanel: View {
    let compact: Bool
    let queuePressureLabel: String?
    let queuePressureDetail: String?
    let emptyMessage: String
    let items: [RecentSwarmDisplayItem]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if let queuePressureLabel, !queuePressureLabel.isEmpty {
                MetricRow(label: "Queue Pressure", value: queuePressureLabel)
            }
            if let queuePressureDetail, !queuePressureDetail.isEmpty {
                Text(queuePressureDetail)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if items.isEmpty {
                Text(emptyMessage)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(items) { item in
                    SwarmSessionCardView(
                        title: item.title,
                        status: item.status,
                        resolvedModel: item.resolvedModel,
                        routeSummary: item.routeSummary,
                        selectionExplanation: item.selectionExplanation,
                        warningMessage: item.warningMessage,
                        premiumNudge: item.premiumNudge,
                        savedTokensLabel: item.savedTokensLabel,
                        queueBadge: item.queueBadge,
                        queueDetail: item.queueDetail,
                        compact: compact
                    )
                    .padding(.vertical, compact ? 0 : 2)
                }
            }
        }
    }

    private var detailFont: Font {
        compact ? .caption : .caption
    }
}







struct LauncherCommandPanel: View {
    let compact: Bool
    let statusLabel: String
    let menuBarStateTitle: String
    let menuBarStateDetail: String
    let localEligibilityTitle: String
    let localEligibilityDetail: String
    let shimDirectoryPath: String?
    let detail: String
    @Binding var preferredRoute: PreferredRequestRoute
    let preferredRouteSummary: String
    let actionTitle: String
    let needsPathFix: Bool
    let shouldReopenTools: Bool
    let showCopyPathFix: Bool
    let starterCommand: String
    let starterCommands: [StarterCommandSuggestion]
    let latestActivity: OnlyMacsActivityDisplayItem?
    @Binding var notificationsEnabled: Bool
    let notificationsDetail: String
    let pathHelpText: String?
    let guidanceHeading: String
    let guidanceIntro: String
    let guidanceSuggestions: [CommandGuidanceSuggestion]
    let installLaunchers: () -> Void
    let copyStarterCommand: () -> Void
    let applyPathFix: () -> Void
    let reopenTools: () -> Void
    let copyPathFix: () -> Void
    let copyCommand: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Use /onlymacs to use your swarm")
                    .font((compact ? Font.body : .title3).weight(.semibold))
                Text("After setup finishes, use `/onlymacs` in Codex or Claude Code, or run `onlymacs` in Terminal, to send work through your swarm.")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MetricRow(label: "Launcher Status", value: statusLabel)
            MetricRow(label: compact ? "Menu State" : "Menu Bar State", value: menuBarStateTitle)
            MetricRow(label: compact ? "This Mac" : "This Mac Eligibility", value: localEligibilityTitle)
            if let shimDirectoryPath, !shimDirectoryPath.isEmpty {
                MetricRow(label: "Shim Directory", value: shimDirectoryPath)
            }
            Text(detail)
                .font(detailFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(menuBarStateDetail)
                .font(detailFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(localEligibilityDetail)
                .font(detailFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            preferredRoutePicker

            Text(preferredRouteSummary)
                .font(detailFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(actionTitle) {
                    installLaunchers()
                }
                .accessibilityLabel(actionTitle)
                .accessibilityHint("Install or refresh the OnlyMacs command surfaces for Codex, Claude Code, and Terminal.")
                .accessibilityIdentifier("onlymacs.launchers.install")

                Button("Copy Starter\(compact ? "" : " Command")") {
                    copyStarterCommand()
                }
                .accessibilityLabel("Copy Starter Command")
                .accessibilityHint("Copy a starter OnlyMacs command to the clipboard.")
                .accessibilityIdentifier("onlymacs.launchers.copyStarterCommand")

                if needsPathFix {
                    Button("Repair PATH") {
                        applyPathFix()
                    }
                    .accessibilityIdentifier("onlymacs.launchers.repairPath")
                }

                if shouldReopenTools {
                    Button("Reopen Tools") {
                        reopenTools()
                    }
                    .accessibilityIdentifier("onlymacs.launchers.reopenTools")
                }

                if showCopyPathFix {
                    Button("Copy PATH Fix") {
                        copyPathFix()
                    }
                    .accessibilityIdentifier("onlymacs.launchers.copyPathFix")
                }
            }
            .buttonStyle(buttonStyle)

            Text(starterCommand)
                .font((compact ? Font.body : .title3).monospaced())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let latestActivity {
                OnlyMacsActivityPanel(
                    compact: compact,
                    activity: latestActivity
                )
            } else {
                Text("No `/onlymacs` launcher activity recorded yet. Start a command from Codex or Claude Code and OnlyMacs will mirror the latest route and result here.")
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Desktop Alerts For /onlymacs", isOn: $notificationsEnabled)
                .font(compact ? .caption : .body)

            Text(notificationsDetail)
                .font(detailFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let pathHelpText, !pathHelpText.isEmpty {
                Text(pathHelpText)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(starterCommands) { suggestion in
                VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                    HStack(alignment: compact ? .firstTextBaseline : .top, spacing: 8) {
                        Text(suggestion.title)
                            .font(compact ? .caption : .body)
                        Spacer()
                        Button("Copy") {
                            copyCommand(suggestion.command)
                        }
                        .buttonStyle(buttonStyle)
                    }

                    Text(suggestion.command)
                        .font(commandFont.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CommandGuidancePanel(
                heading: guidanceHeading,
                intro: guidanceIntro,
                suggestions: guidanceSuggestions,
                compact: compact,
                copyCommand: copyCommand
            )
        }
    }

    private var detailFont: Font {
        compact ? .caption2 : .caption
    }

    private var commandFont: Font {
        compact ? .body : .title3
    }

    @ViewBuilder
    private var preferredRoutePicker: some View {
        let picker = Picker("Preferred Route", selection: $preferredRoute) {
            ForEach(PreferredRequestRoute.allCases) { route in
                Text(route.title).tag(route)
            }
        }

        if compact {
            picker.pickerStyle(.menu)
        } else {
            picker
        }
    }

    private var buttonStyle: BorderlessButtonStyle {
        .init()
    }
}

struct OnlyMacsActivityPanel: View {
    let compact: Bool
    let activity: OnlyMacsActivityDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack {
                Text("Latest /onlymacs Activity")
                    .font((compact ? Font.caption : .body).weight(.medium))
                Spacer()
                Text(activity.timestampLabel)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(activity.title)
                    .font(commandFont.monospaced())
                    .lineLimit(1)
                Spacer()
                Text(activity.statusTitle)
                    .font(detailFont.weight(.semibold))
                    .foregroundStyle(activity.warningStyle ? .orange : .secondary)
            }

            Text(activity.detail)
                .font(detailFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let routeLabel = activity.routeLabel, !routeLabel.isEmpty {
                MetricRow(label: "Route", value: routeLabel)
            }
            if let modelLabel = activity.modelLabel, !modelLabel.isEmpty {
                MetricRow(label: "Model", value: modelLabel)
            }
            if let sessionLabel = activity.sessionLabel, !sessionLabel.isEmpty {
                MetricRow(label: "Session", value: sessionLabel)
            }
        }
        .padding(compact ? 8 : 10)
        .background((activity.warningStyle ? Color.orange : Color.secondary).opacity(compact ? 0.08 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
    }

    private var detailFont: Font {
        compact ? .caption2 : .caption
    }

    private var commandFont: Font {
        compact ? .caption2 : .caption
    }
}

struct RuntimeDiagnosticsPanel: View {
    let compact: Bool
    let runtimeState: LocalRuntimeState
    let isRuntimeBusy: Bool
    let lastSupportBundlePath: String?
    let restartLabel: String
    let exportLabel: String
    let ollamaActionTitle: String?
    let restartRuntime: () -> Void
    let runOllamaAction: () -> Void
    let openLogs: () -> Void
    let copyDiagnostics: () -> Void
    let exportSupportBundle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            MetricRow(label: "Runtime Status", value: runtimeState.status.capitalized)
            MetricRow(label: compact ? "Model Runtime" : "Model Runtime", value: runtimeState.ollamaStatus.displayName)
            MetricRow(label: compact ? "Helpers" : "Helper Source", value: runtimeState.helperSource)
            MetricRow(label: "Logs", value: runtimeState.logsDirectory)

            Text(runtimeState.detail)
                .font(detailFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !runtimeState.ollamaDetail.isEmpty {
                Text(runtimeState.ollamaDetail)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(isRuntimeBusy ? (compact ? "Restarting…" : "Restarting…") : restartLabel) {
                restartRuntime()
            }
            .disabled(isRuntimeBusy)

            if let ollamaActionTitle {
                Button(ollamaActionTitle) {
                    runOllamaAction()
                }
                .disabled(isRuntimeBusy)
            }

            HStack {
                Button("Open Logs") {
                    openLogs()
                }
                .buttonStyle(buttonStyle)

                Button("Copy Diagnostics") {
                    copyDiagnostics()
                }
                .buttonStyle(buttonStyle)

                Button(exportLabel) {
                    exportSupportBundle()
                }
                .buttonStyle(buttonStyle)
            }

            if let lastSupportBundlePath, !lastSupportBundlePath.isEmpty {
                Text(lastSupportBundlePath)
                    .font(commandFont.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detailFont: Font {
        compact ? .caption2 : .caption
    }

    private var commandFont: Font {
        compact ? .caption2 : .caption2
    }

    private var buttonStyle: BorderlessButtonStyle {
        .init()
    }
}

struct CoordinatorConnectionPanel: View {
    let compact: Bool
    @Binding var coordinatorURLDraft: String
    let effectiveTarget: String
    let validationError: String?
    let isRuntimeBusy: Bool
    let hasPendingChanges: Bool
    let recoveryMessage: String?
    var showsHelperText = true
    let applyLabel: String
    let retryLabel: String
    let openLogsLabel: String
    let applyChanges: () -> Void
    let retryHosted: () -> Void
    let openLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            MetricRow(label: compact ? "Mode" : "Connection Mode", value: CoordinatorConnectionMode.hostedRemote.title)

            TextField("Hosted Coordinator URL", text: $coordinatorURLDraft)
                .textFieldStyle(.roundedBorder)
            if showsHelperText {
                Text("Use the hosted coordinator so this Mac can discover swarms and relay work with other Macs.")
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MetricRow(label: compact ? "Target" : "Effective Target", value: effectiveTarget)

            if let validationError, !validationError.isEmpty {
                Text(validationError)
                    .font(detailFont)
                    .foregroundStyle(.red)
            }

            Button(isRuntimeBusy ? "Applying…" : applyLabel) {
                applyChanges()
            }
            .disabled(isRuntimeBusy || !hasPendingChanges || validationError != nil)

            if let recoveryMessage, !recoveryMessage.isEmpty {
                Text(recoveryMessage)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(retryLabel) {
                        retryHosted()
                    }
                    .disabled(isRuntimeBusy)

                    Button(openLogsLabel) {
                        openLogs()
                    }
                    .buttonStyle(buttonStyle)
                }
            }
        }
    }

    private var detailFont: Font {
        compact ? .caption2 : .caption
    }

    private var buttonStyle: BorderlessButtonStyle {
        .init()
    }
}

struct RequesterHighlightsPanel: View {
    let compact: Bool
    let tokensSaved: String
    let downloaded: String
    let uploaded: String
    let swarmBudget: String?
    let communityBoostLabel: String
    let communityBoost: String
    let activeSwarms: Int
    let queuedSwarms: Int
    let queuePressureLabel: String?
    let communityTrait: String?
    let communityDetail: String
    let queuePressureDetail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                HStack(spacing: 8) {
                    compactChip("Saved", value: tokensSaved)
                    compactChip("Downloaded", value: downloaded)
                    if queuedSwarms > 0 {
                        compactChip("Queued", value: "\(queuedSwarms)")
                    }
                }

                if let queuePressureLabel, !queuePressureLabel.isEmpty {
                    Text(queuePressureLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if let communityTrait, !communityTrait.isEmpty {
                    Text("\(communityTrait): \(communityDetail)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let queuePressureDetail, !queuePressureDetail.isEmpty {
                    Text(queuePressureDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                MetricRow(label: "Tokens Saved", value: tokensSaved)
                if let swarmBudget, !swarmBudget.isEmpty {
                    MetricRow(label: "Swarm Budget", value: swarmBudget)
                }
                MetricRow(label: "Live Swarms", value: "\(activeSwarms)")
                if queuedSwarms > 0 {
                    MetricRow(label: "Queued", value: "\(queuedSwarms)")
                }
                if let queuePressureLabel, !queuePressureLabel.isEmpty {
                    Text(queuePressureLabel)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let communityTrait, !communityTrait.isEmpty {
                    Text("\(communityTrait): \(communityDetail)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let queuePressureDetail, !queuePressureDetail.isEmpty {
                    Text(queuePressureDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func compactChip(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ShareHealthSummaryPanel: View {
    let compact: Bool
    let status: String
    let published: Bool
    let swarmName: String?
    let activeSessions: Int
    let servedSessions: Int
    let streamedSessions: Int?
    let failedSessions: Int
    let uploadedTokens: String
    let downloadedTokens: String?
    let swarmBudget: String?
    let communityBoostLabel: String
    let communityBoost: String
    let communityTrait: String?
    let communityDetail: String
    let errorMessage: String?
    let lastServedModel: String?
    let failureNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if compact {
                HStack(spacing: 8) {
                    summaryBadge(title: published ? "Sharing" : "Not Sharing", tint: published ? .green : .secondary)
                    if activeSessions > 0 {
                        summaryBadge(title: "\(activeSessions) Live Job\(activeSessions == 1 ? "" : "s")", tint: .blue)
                    }
                    if failedSessions > 0 {
                        summaryBadge(title: "\(failedSessions) Issue\(failedSessions == 1 ? "" : "s")", tint: .orange)
                    }
                }

                Text(swarmName.map { published ? "Helping \(String($0))" : "Connected to \(String($0))" } ?? "Not connected to a swarm yet.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if activeSessions > 0 {
                    Text("This Mac is serving a live swarm right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let lastServedModel, !lastServedModel.isEmpty {
                    Text("Last used: \(lastServedModel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if published {
                    Text("This Mac is ready to help when a swarm needs it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Turn on sharing when you want this Mac to help other people in the swarm.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let failureNote, !failureNote.isEmpty {
                    Text(failureNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if activeSessions > 0 {
                    Text("Generated \(uploadedTokens) so far across \(servedSessions) finished session\(servedSessions == 1 ? "" : "s").")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let communityTrait, !communityTrait.isEmpty {
                    Text("\(communityTrait): \(communityDetail)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                MetricRow(label: "Share Status", value: status.capitalized)
                MetricRow(label: "Published", value: published ? "Yes" : "No")
                MetricRow(label: "Swarm", value: swarmName ?? "None")
                MetricRow(label: "Live Jobs", value: "\(activeSessions)")
                MetricRow(label: "Served Sessions", value: "\(servedSessions)")
                if let streamedSessions {
                    MetricRow(label: "Streamed Sessions", value: "\(streamedSessions)")
                }
                MetricRow(label: "Failed Sessions", value: "\(failedSessions)")
                MetricRow(label: "Uploaded Tokens", value: uploadedTokens)
                if let downloadedTokens, !downloadedTokens.isEmpty {
                    MetricRow(label: "Downloaded Tokens", value: downloadedTokens)
                }
                if let swarmBudget, !swarmBudget.isEmpty {
                    MetricRow(label: "Swarm Budget", value: swarmBudget)
                }
                MetricRow(label: communityBoostLabel, value: communityBoost)

                if let communityTrait, !communityTrait.isEmpty {
                    Text("\(communityTrait): \(communityDetail)")
                        .font(detailFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(detailFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let lastServedModel, !lastServedModel.isEmpty {
                    Text(lastServedLabel)
                        .font(detailFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let failureNote, !failureNote.isEmpty {
                    Text(failureNote)
                        .font(detailFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var detailFont: Font {
        compact ? .caption2 : .caption
    }

    private var lastServedLabel: String {
        compact ? "Last served: \(lastServedModel ?? "")" : "Last served model: \(lastServedModel ?? "")"
    }

    private func summaryBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

enum CommandGuidanceTone {
    case safe
    case savings
    case premium
    case caution

    var iconName: String {
        switch self {
        case .safe:
            return "lock.shield.fill"
        case .savings:
            return "banknote.fill"
        case .premium:
            return "sparkles"
        case .caution:
            return "lightbulb.max.fill"
        }
    }

    var color: Color {
        switch self {
        case .safe:
            return .blue
        case .savings:
            return .green
        case .premium:
            return .orange
        case .caution:
            return .yellow
        }
    }
}

struct CommandGuidanceSuggestion: Identifiable {
    let title: String
    let detail: String
    let command: String
    let tone: CommandGuidanceTone

    var id: String { title }
}

struct CommandGuidancePanel: View {
    let heading: String
    let intro: String?
    let suggestions: [CommandGuidanceSuggestion]
    let compact: Bool
    let copyCommand: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text(heading)
                .font((compact ? Font.caption : .body).weight(.semibold))

            if let intro, !intro.isEmpty {
                Text(intro)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(suggestions) { suggestion in
                VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: suggestion.tone.iconName)
                            .foregroundStyle(suggestion.tone.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.title)
                                .font((compact ? Font.caption : .body).weight(.medium))
                            Text(suggestion.detail)
                                .font(detailFont)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack {
                        Button("Copy") {
                            copyCommand(suggestion.command)
                        }
                        .buttonStyle(buttonStyle)
                        Spacer()
                    }

                    Text(suggestion.command)
                        .font(commandFont.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(compact ? 8 : 10)
                .background(suggestion.tone.color.opacity(compact ? 0.08 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
            }
        }
    }

    private var detailFont: Font {
        compact ? .caption2 : .caption
    }

    private var commandFont: Font {
        compact ? .caption2 : .caption
    }

    private var buttonStyle: BorderlessButtonStyle {
        .init()
    }
}

enum RecoveryCardTone {
    case info
    case warning
    case error

    var iconName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "clock.badge.exclamationmark"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

enum RecoveryActionKind: Hashable {
    case refreshBridge
    case makeReady
    case fixEverything
    case restartRuntime
    case installOllama
    case launchOllama
    case openLogs
    case exportSupportBundle
    case useHostedRemote
    case createInvite
    case installLaunchers
    case applyPathFix
    case reopenDetectedTools
    case copyPathFix
    case copyFriendTest
    case copyFounderPacket
    case copyStarterCommand
    case runSelfTest
}

struct RecoveryActionItem: Identifiable {
    let kind: RecoveryActionKind
    let label: String

    var id: String { "\(kind)-\(label)" }
}

struct RecoveryCardContent {
    let title: String
    let detail: String
    let tone: RecoveryCardTone
    let actions: [RecoveryActionItem]
}

struct RecoveryActionCardView: View {
    let content: RecoveryCardContent
    let compact: Bool
    let performAction: (RecoveryActionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: content.tone.iconName)
                    .foregroundStyle(content.tone.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font((compact ? Font.caption : .body).weight(.semibold))
                    Text(content.detail)
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !content.actions.isEmpty {
                HStack {
                    ForEach(content.actions.prefix(3)) { action in
                        Button(action.label) {
                            performAction(action.kind)
                        }
                        .buttonStyle(buttonStyle)
                    }
                }
            }
        }
        .padding(compact ? 8 : 10)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
    }

    private var background: some ShapeStyle {
        content.tone.color.opacity(compact ? 0.10 : 0.08)
    }

    private var buttonStyle: BorderlessButtonStyle {
        .init()
    }
}

enum FriendTestStatusLevel {
    case ready
    case needsAction
    case blocked

    var iconName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .needsAction:
            return "circle.dashed"
        case .blocked:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready:
            return .green
        case .needsAction:
            return .orange
        case .blocked:
            return .red
        }
    }

    var summaryPrefix: String {
        switch self {
        case .ready:
            return "[Ready]"
        case .needsAction:
            return "[Needs Action]"
        case .blocked:
            return "[Blocked]"
        }
    }
}

struct FriendTestStatusItem: Identifiable {
    let title: String
    let detail: String
    let status: FriendTestStatusLevel

    var id: String { title }
}

struct FriendTestStatusSummary {
    let title: String
    let detail: String
    let items: [FriendTestStatusItem]
    let actions: [RecoveryActionItem]
}
