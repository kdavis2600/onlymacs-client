import SwiftUI

struct OnlyMacsFileAccessApprovalView: View {
    @ObservedObject var store: BridgeStore
    let approval: PendingFileAccessApproval

    private var isPublicCapsule: Bool {
        approval.request.trustTier == .publicUntrusted
    }

    private var headlineTitle: String {
        isPublicCapsule ? "Approve public file capsule" : "Approve trusted file access"
    }

    private var headlineSubtitle: String {
        if isPublicCapsule {
            return "OnlyMacs will export approved excerpts for this request. Public workers cannot browse your repo or write back to local files."
        }
        return "OnlyMacs will export a small read-only bundle for this one request. It will not mount your project folder."
    }

    private var summaryIntro: String {
        if let warning = approval.request.userFacingWarning, !warning.isEmpty {
            return warning
        }
        if isPublicCapsule {
            return "Only the checked excerpts below will leave this Mac. Hidden files, secrets, and raw repo browsing stay blocked."
        }
        return "Only the checked files below will leave this Mac. Secret and credential files stay blocked automatically."
    }

    private var approveButtonTitle: String {
        isPublicCapsule ? "Share Selected Excerpts" : "Share Selected Files"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            HStack(alignment: .top, spacing: 24) {
                filesColumn
                summaryColumn
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .frame(minWidth: 1060, minHeight: 720)
        .accessibilityIdentifier("onlymacs.fileApproval.windowContent")
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 58, height: 58)
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(headlineTitle)
                    .font(.title.weight(.bold))
                Text(headlineSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var filesColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Files for this request")
                        .font(.title2.weight(.semibold))
                    Text("Recommended files are preselected. You can still add or remove anything before it leaves this Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Choose Files…") {
                    store.chooseAdditionalFileAccessFilesNow()
                }
                .accessibilityLabel("Choose Files")
                .accessibilityHint("Open a file picker to add more files to this request.")
                .accessibilityIdentifier("onlymacs.fileApproval.chooseFiles")
            }

            if approval.suggestions.isEmpty {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .overlay(
                        Text("OnlyMacs could not guess the right files from this workspace yet. Use “Choose Files…” to pick the exact docs, schema files, or example JSON files.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(24)
                    )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !recommendedSuggestions.isEmpty {
                            suggestionSection(
                                title: "Recommended",
                                subtitle: "Best matches for this request. These are preselected first.",
                                suggestions: recommendedSuggestions
                            )
                        }

                        if !otherSuggestions.isEmpty {
                            suggestionSection(
                                title: "More Available Files",
                                subtitle: "Still available from this workspace, but not part of the default recommended bundle.",
                                suggestions: otherSuggestions
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 480)
                .accessibilityIdentifier("onlymacs.fileApproval.suggestionsList")
            }
        }
        .frame(minWidth: 640, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onlymacs.fileApproval.filesColumn")
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This request needs local files")
                            .font(.title3.weight(.semibold))
                        Text(summaryIntro)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    detailCard
                    if let contextRequestSummary = approval.request.contextRequestSummary,
                       !contextRequestSummary.isEmpty {
                        contextRequestCard(summary: contextRequestSummary)
                    }
                    countsCard
                    previewSummary

                    if let error = store.lastError, !error.isEmpty {
                        Text(error)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(summaryFooterText)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") {
                        store.rejectPendingFileAccessNow()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Reject this request and return to Codex without sharing anything.")
                    .accessibilityIdentifier("onlymacs.fileApproval.cancel")

                    Spacer()

                    Button(approveButtonTitle) {
                        store.approvePendingFileAccessNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!approval.preview.hasExportableFiles)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint(isPublicCapsule
                        ? "Approve this request and export the selected excerpts to the public-safe capsule flow."
                        : "Approve this request and export the selected files to your trusted swarm.")
                    .accessibilityIdentifier("onlymacs.fileApproval.shareSelectedFiles")
                }
            }
        }
        .frame(width: 320, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onlymacs.fileApproval.summaryColumn")
    }

    private var previewSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About \(ByteCountFormatter.string(fromByteCount: Int64(approval.preview.totalExportBytes), countStyle: .file)) will leave this Mac for this one request.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !approval.preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(approval.preview.warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.orange)
                                .padding(.top, 2)
                            Text(warning)
                                .font(.subheadline)
                                .foregroundStyle(Color.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .accessibilityIdentifier("onlymacs.fileApproval.warningSummary")
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailRow(title: "Request", value: approval.promptSummary, monospaced: false)

            if let swarmName = approval.request.swarmName, !swarmName.isEmpty {
                detailRow(title: isPublicCapsule ? "Public swarm" : "Trusted swarm", value: swarmName, monospaced: false)
            }

            detailRow(title: "Workspace", value: approval.workspaceRoot, monospaced: true)
            if let leaseID = approval.request.leaseID, !leaseID.isEmpty {
                detailRow(title: "Workspace lease", value: leaseID, monospaced: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .accessibilityIdentifier("onlymacs.fileApproval.requestDetails")
    }

    private func contextRequestCard(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More context requested")
                .font(.headline)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .accessibilityIdentifier("onlymacs.fileApproval.contextRequest")
    }

    private var countsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selection")
                .font(.headline)

            HStack(spacing: 10) {
                summaryBadge(title: "Selected", value: "\(approval.preview.selectedCount)")
                summaryBadge(title: "Recommended", value: "\(recommendedSuggestions.count)")
            }

            HStack(spacing: 10) {
                summaryBadge(title: "Available", value: "\(approval.suggestions.count)")
                if approval.preview.blockedCount > 0 {
                    summaryBadge(title: "Blocked", value: "\(approval.preview.blockedCount)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .accessibilityIdentifier("onlymacs.fileApproval.selectionSummary")
    }

    private func summaryBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
    }

    private var summaryFooterText: String {
        if approval.preview.hasExportableFiles {
            return "\(approval.preview.exportableCount) file\(approval.preview.exportableCount == 1 ? "" : "s") ready to share"
        }
        return "Choose at least one safe text file to continue"
    }

    private var recommendedSuggestions: [OnlyMacsFileSuggestion] {
        approval.suggestions.filter(\.isRecommended)
    }

    private var otherSuggestions: [OnlyMacsFileSuggestion] {
        approval.suggestions.filter { !$0.isRecommended }
    }

    @ViewBuilder
    private func suggestionSection(title: String, subtitle: String, suggestions: [OnlyMacsFileSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(suggestions) { suggestion in
                    FileAccessSuggestionRow(
                        suggestion: suggestion,
                        previewEntry: approval.preview.entries.first(where: { $0.path == suggestion.path }),
                        isSelected: approval.selectedPaths.contains(suggestion.path)
                    ) { enabled in
                        store.updatePendingFileAccessSelection(path: suggestion.path, isSelected: enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if monospaced {
                Text(value)
                    .font(.subheadline.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FileAccessSuggestionRow: View {
    let suggestion: OnlyMacsFileSuggestion
    let previewEntry: OnlyMacsFilePreviewEntry?
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(suggestion.fileName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        suggestionBadge(title: suggestion.category, emphasized: suggestion.isRecommended)
                    }
                    Text(suggestion.relativePath)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Text(suggestion.reason)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(suggestion.sizeLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if let previewEntry {
                        Text(statusText(for: previewEntry))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(statusColor(for: previewEntry))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.fileName), \(suggestion.category), \(statusAccessibilityText)")
        .accessibilityHint(isSelected ? "Selected for sharing. Activate to remove it from this request." : "Not selected. Activate to include it in this request.")
        .accessibilityIdentifier("onlymacs.fileApproval.fileRow.\(suggestion.id)")
    }

    private func suggestionBadge(title: String, emphasized: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(emphasized ? Color.accentColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(emphasized ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10))
            )
            .fixedSize(horizontal: true, vertical: false)
    }

    private func statusText(for entry: OnlyMacsFilePreviewEntry) -> String {
        switch entry.status {
        case .ready:
            return "Ready to share"
        case .trimmed:
            return "Will be trimmed to \(entry.exportedSizeLabel)"
        case .blocked:
            return entry.reason ?? "Blocked"
        case .missing:
            return entry.reason ?? "Missing"
        }
    }

    private func statusColor(for entry: OnlyMacsFilePreviewEntry) -> Color {
        switch entry.status {
        case .ready:
            return .green
        case .trimmed:
            return .orange
        case .blocked, .missing:
            return .red
        }
    }

    private var statusAccessibilityText: String {
        if let previewEntry {
            return statusText(for: previewEntry)
        }
        return suggestion.reason
    }
}
