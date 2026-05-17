import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum OnlyMacsFileAccessMode: String, Codable, Hashable, Sendable {
    case none
    case blockedPublic = "blocked_public"
    case capsuleSnapshot = "capsule_snapshot"
    case capsuleWithContextRequests = "capsule_with_context_requests"
    case privateProjectLease = "private_project_lease"
    case gitBackedCheckout = "git_backed_checkout"
    case localOnly = "local_only"
}

struct OnlyMacsFileAccessRequest: Codable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let workspaceID: String
    let workspaceRoot: String
    let threadID: String
    let prompt: String
    let taskKind: OnlyMacsRequestTaskKind?
    let routeScope: String
    let toolName: String
    let wrapperName: String
    let swarmName: String?
    let fileAccessMode: OnlyMacsFileAccessMode?
    let trustTier: OnlyMacsCapsuleTrustTier?
    let allowContextRequests: Bool?
    let maxContextRequestRounds: Int?
    let userFacingWarning: String?
    let suggestedContextPacks: [String]?
    let suggestedFiles: [String]?
    let seedSelectedPaths: [String]?
    let contextRequestSummary: String?
    let contextRequestRound: Int?
    let leaseID: String?

    init(
        id: String,
        createdAt: Date,
        workspaceID: String,
        workspaceRoot: String,
        threadID: String,
        prompt: String,
        taskKind: OnlyMacsRequestTaskKind? = nil,
        routeScope: String,
        toolName: String,
        wrapperName: String,
        swarmName: String?,
        fileAccessMode: OnlyMacsFileAccessMode? = nil,
        trustTier: OnlyMacsCapsuleTrustTier? = nil,
        allowContextRequests: Bool? = nil,
        maxContextRequestRounds: Int? = nil,
        userFacingWarning: String? = nil,
        suggestedContextPacks: [String]? = nil,
        suggestedFiles: [String]? = nil,
        seedSelectedPaths: [String]? = nil,
        contextRequestSummary: String? = nil,
        contextRequestRound: Int? = nil,
        leaseID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.workspaceID = workspaceID
        self.workspaceRoot = workspaceRoot
        self.threadID = threadID
        self.prompt = prompt
        self.taskKind = taskKind
        self.routeScope = routeScope
        self.toolName = toolName
        self.wrapperName = wrapperName
        self.swarmName = swarmName
        self.fileAccessMode = fileAccessMode
        self.trustTier = trustTier
        self.allowContextRequests = allowContextRequests
        self.maxContextRequestRounds = maxContextRequestRounds
        self.userFacingWarning = userFacingWarning
        self.suggestedContextPacks = suggestedContextPacks
        self.suggestedFiles = suggestedFiles
        self.seedSelectedPaths = seedSelectedPaths
        self.contextRequestSummary = contextRequestSummary
        self.contextRequestRound = contextRequestRound
        self.leaseID = leaseID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case workspaceID = "workspace_id"
        case workspaceRoot = "workspace_root"
        case threadID = "thread_id"
        case prompt
        case taskKind = "task_kind"
        case routeScope = "route_scope"
        case toolName = "tool_name"
        case wrapperName = "wrapper_name"
        case swarmName = "swarm_name"
        case fileAccessMode = "file_access_mode"
        case trustTier = "trust_tier"
        case allowContextRequests = "allow_context_requests"
        case maxContextRequestRounds = "max_context_request_rounds"
        case userFacingWarning = "user_facing_warning"
        case suggestedContextPacks = "suggested_context_packs"
        case suggestedFiles = "suggested_files"
        case seedSelectedPaths = "seed_selected_paths"
        case contextRequestSummary = "context_request_summary"
        case contextRequestRound = "context_request_round"
        case leaseID = "lease_id"
    }
}

enum OnlyMacsRequestTaskKind: String, Codable, Sendable {
    case review
    case debug
    case generate
    case transform
    case summarize
    case translate
    case plan
    case explain
    case generic
}

enum OnlyMacsFileAccessDecisionStatus: String, Codable, Equatable, Sendable {
    case approved
    case rejected
}

struct OnlyMacsFileAccessResponse: Codable, Equatable, Sendable {
    let id: String
    let decidedAt: Date
    let status: OnlyMacsFileAccessDecisionStatus
    let selectedPaths: [String]
    let contextPath: String?
    let manifestPath: String?
    let bundlePath: String?
    let bundleSHA256: String?
    let exportMode: OnlyMacsFileExportMode?
    let warnings: [String]
    let message: String?

    enum CodingKeys: String, CodingKey {
        case id
        case decidedAt = "decided_at"
        case status
        case selectedPaths = "selected_paths"
        case contextPath = "context_path"
        case manifestPath = "manifest_path"
        case bundlePath = "bundle_path"
        case bundleSHA256 = "bundle_sha256"
        case exportMode = "export_mode"
        case warnings
        case message
    }
}

enum OnlyMacsFileExportMode: String, Codable, Hashable, Sendable {
    case publicExcerptCapsule = "public_excerpt_capsule"
    case trustedReviewFull = "trusted_review_full"
    case trustedContextFlexible = "trusted_context_flexible"
    case privateProjectLease = "private_project_lease"
    case gitBackedCheckout = "git_backed_checkout"
}

struct OnlyMacsFileAccessClaim: Codable, Equatable, Sendable {
    let id: String
    let claimedAt: Date
    let workspaceRoot: String
}

struct OnlyMacsFileSuggestion: Identifiable, Hashable, Codable, Sendable {
    let path: String
    let relativePath: String
    let bytes: Int
    let reason: String
    let category: String
    let priority: Int
    let isRecommended: Bool

    var id: String { path }

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var sizeLabel: String {
        ByteCountFormatter.onlyMacsString(fromByteCount: Int64(bytes))
    }
}

enum OnlyMacsFilePreviewStatus: String, Codable, Hashable, Sendable {
    case ready
    case trimmed
    case blocked
    case missing
}

struct OnlyMacsFilePreviewEntry: Identifiable, Codable, Hashable, Sendable {
    let path: String
    let relativePath: String
    let originalBytes: Int
    let exportedBytes: Int
    let status: OnlyMacsFilePreviewStatus
    let reason: String?

    var id: String { path }

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var originalSizeLabel: String {
        ByteCountFormatter.onlyMacsString(fromByteCount: Int64(originalBytes))
    }

    var exportedSizeLabel: String {
        ByteCountFormatter.onlyMacsString(fromByteCount: Int64(exportedBytes))
    }
}

struct OnlyMacsFileSelectionPreview: Codable, Hashable, Sendable {
    let entries: [OnlyMacsFilePreviewEntry]
    let warnings: [String]
    let totalSelectedBytes: Int
    let totalExportBytes: Int

    var selectedCount: Int { entries.count }
    var exportableCount: Int {
        entries.filter { $0.status == .ready || $0.status == .trimmed }.count
    }
    var blockedCount: Int {
        entries.filter { $0.status == .blocked || $0.status == .missing }.count
    }
    var hasExportableFiles: Bool { exportableCount > 0 }
}

struct PendingFileAccessApproval: Identifiable, Equatable {
    let request: OnlyMacsFileAccessRequest
    var suggestions: [OnlyMacsFileSuggestion]
    var selectedPaths: Set<String>
    var preview: OnlyMacsFileSelectionPreview

    var id: String { request.id }
    var workspaceRoot: String { request.workspaceRoot }
    var promptSummary: String { request.prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct OnlyMacsCapsuleLease: Codable, Hashable, Sendable {
    let id: String
    let mode: String
    let round: Int
    let maxRounds: Int
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case mode
        case round
        case maxRounds = "max_rounds"
        case expiresAt = "expires_at"
    }
}

struct OnlyMacsCapsuleWorkspace: Codable, Hashable, Sendable {
    let kind: String
    let vcs: String?
    let gitHead: String?
    let gitBranch: String?
    let gitDirty: Bool
    let trackedFiles: [String]

    enum CodingKeys: String, CodingKey {
        case kind
        case vcs
        case gitHead = "git_head"
        case gitBranch = "git_branch"
        case gitDirty = "git_dirty"
        case trackedFiles = "tracked_files"
    }
}

struct OnlyMacsFileExportManifestFile: Codable, Hashable, Sendable {
    let path: String
    let relativePath: String
    let category: String?
    let selectionReason: String?
    let isRecommended: Bool
    let reviewPriority: Int
    let evidenceHints: [String]
    let evidenceAnchors: [OnlyMacsFileEvidenceAnchor]
    let originalBytes: Int
    let exportedBytes: Int
    let status: OnlyMacsFilePreviewStatus
    let reason: String?
    let sha256: String?

    enum CodingKeys: String, CodingKey {
        case path
        case relativePath = "relative_path"
        case category
        case selectionReason = "selection_reason"
        case isRecommended = "is_recommended"
        case reviewPriority = "review_priority"
        case evidenceHints = "evidence_hints"
        case evidenceAnchors = "evidence_anchors"
        case originalBytes = "original_bytes"
        case exportedBytes = "exported_bytes"
        case status
        case reason
        case sha256
    }
}

struct OnlyMacsFileEvidenceAnchor: Codable, Hashable, Sendable {
    let kind: String
    let lineStart: Int
    let lineEnd: Int
    let text: String

    enum CodingKeys: String, CodingKey {
        case kind
        case lineStart = "line_start"
        case lineEnd = "line_end"
        case text
    }
}

enum OnlyMacsCapsuleTrustTier: String, Codable, Hashable, Sendable {
    case publicUntrusted = "public_untrusted"
    case privateStandard = "private_standard"
    case privateTrusted = "private_trusted"
    case privateGitBacked = "private_git_backed"
    case local = "local"
}

struct OnlyMacsCapsulePermissions: Codable, Hashable, Sendable {
    let allowContextRequests: Bool
    let maxContextRequestRounds: Int
    let allowSourceMutation: Bool
    let allowStagedMutation: Bool
    let allowOutputArtifacts: Bool

    enum CodingKeys: String, CodingKey {
        case allowContextRequests = "allow_context_requests"
        case maxContextRequestRounds = "max_context_request_rounds"
        case allowSourceMutation = "allow_source_mutation"
        case allowStagedMutation = "allow_staged_mutation"
        case allowOutputArtifacts = "allow_output_artifacts"
    }
}

struct OnlyMacsCapsuleBudgets: Codable, Hashable, Sendable {
    let maxFileBytes: Int
    let maxTotalBytes: Int
    let maxScanBytes: Int
    let requiresFullFiles: Bool
    let allowTrimming: Bool

    enum CodingKeys: String, CodingKey {
        case maxFileBytes = "max_file_bytes"
        case maxTotalBytes = "max_total_bytes"
        case maxScanBytes = "max_scan_bytes"
        case requiresFullFiles = "requires_full_files"
        case allowTrimming = "allow_trimming"
    }
}

struct OnlyMacsCapsuleBlockedFile: Codable, Hashable, Sendable {
    let relativePath: String
    let status: OnlyMacsFilePreviewStatus
    let reason: String

    enum CodingKeys: String, CodingKey {
        case relativePath = "relative_path"
        case status
        case reason
    }
}

struct OnlyMacsCapsuleApprovalMetadata: Codable, Hashable, Sendable {
    let approvalRequired: Bool
    let requestedAt: Date
    let approvedAt: Date
    let selectedCount: Int
    let exportableCount: Int

    enum CodingKeys: String, CodingKey {
        case approvalRequired = "approval_required"
        case requestedAt = "requested_at"
        case approvedAt = "approved_at"
        case selectedCount = "selected_count"
        case exportableCount = "exportable_count"
    }
}

struct OnlyMacsCapsuleContextPack: Codable, Hashable, Sendable {
    let id: String
    let description: String
    let scope: String
    let source: String
    let matchedFiles: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case scope
        case source
        case matchedFiles = "matched_files"
    }
}

struct OnlyMacsFileExportManifest: Codable, Hashable, Sendable {
    let schema: String
    let capsuleID: String
    let id: String
    let requestID: String
    let createdAt: Date
    let expiresAt: Date
    let workspaceRoot: String
    let workspaceRootLabel: String
    let workspaceFingerprint: String
    let routeScope: String
    let trustTier: OnlyMacsCapsuleTrustTier
    let absolutePathsIncluded: Bool
    let swarmName: String?
    let toolName: String
    let promptSummary: String
    let requestIntent: String
    let exportMode: OnlyMacsFileExportMode
    let outputContract: String?
    let requiredSections: [String]
    let groundingRules: [String]
    let contextRequestRules: [String]
    let permissions: OnlyMacsCapsulePermissions
    let budgets: OnlyMacsCapsuleBudgets
    let lease: OnlyMacsCapsuleLease?
    let workspace: OnlyMacsCapsuleWorkspace?
    let contextPacks: [OnlyMacsCapsuleContextPack]
    let files: [OnlyMacsFileExportManifestFile]
    let blocked: [OnlyMacsCapsuleBlockedFile]
    let warnings: [String]
    let approval: OnlyMacsCapsuleApprovalMetadata
    let totalSelectedBytes: Int
    let totalExportBytes: Int

    enum CodingKeys: String, CodingKey {
        case schema
        case capsuleID = "capsule_id"
        case id
        case requestID = "request_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case workspaceRoot = "workspace_root"
        case workspaceRootLabel = "workspace_root_label"
        case workspaceFingerprint = "workspace_fingerprint"
        case routeScope = "route_scope"
        case trustTier = "trust_tier"
        case absolutePathsIncluded = "absolute_paths_included"
        case swarmName = "swarm_name"
        case toolName = "tool_name"
        case promptSummary = "prompt_summary"
        case requestIntent = "request_intent"
        case exportMode = "export_mode"
        case outputContract = "output_contract"
        case requiredSections = "required_sections"
        case groundingRules = "grounding_rules"
        case contextRequestRules = "context_request_rules"
        case permissions
        case budgets
        case lease
        case workspace
        case contextPacks = "context_packs"
        case files
        case blocked
        case warnings
        case approval
        case totalSelectedBytes = "total_selected_bytes"
        case totalExportBytes = "total_export_bytes"
    }
}

private struct OnlyMacsExportContract {
    let requestIntent: String
    let outputContract: String?
    let requiredSections: [String]
    let groundingRules: [String]
    let contextRequestRules: [String]

    static func forRequest(
        _ request: OnlyMacsFileAccessRequest,
        policy: OnlyMacsTrustedExportPolicy
    ) -> OnlyMacsExportContract {
        let promptProfile = OnlyMacsPromptProfile(prompt: request.prompt, taskKind: request.taskKind)
        let allowContextRequests = request.allowContextRequests ?? policy.allowContextRequests
        let requestSections = allowContextRequests ? ["Context Requests"] : []
        let contextRequestRules = allowContextRequests ? [
            "Use Context Requests only when the approved files are not enough to answer safely.",
            "Each Context Requests item must use this shape: Need: short request; Why: short reason; Suggested files: exact filenames or file types.",
            "Write 'None.' under Context Requests when no more context is needed."
        ] : []
        switch promptProfile.exportIntent(policy: policy) {
        case .groundedReview:
            return OnlyMacsExportContract(
                requestIntent: "grounded_review",
                outputContract: "categorized_findings",
                requiredSections: ["Findings", "Open Questions"] + requestSections + ["Referenced Files"],
                groundingRules: [
                    "Base every material claim only on the approved files in this bundle.",
                    "For each finding, cite the exact approved relative file path that supports it.",
                    "If a file is trimmed or evidence is incomplete, say so plainly instead of guessing.",
                    "Avoid generic filler or broad advice that is not tied to cited files.",
                    "Always include Open Questions, even when there are none. Write 'None.' under that section instead of skipping it.",
                    "Always include every required section, even when it is empty. Use 'None.' instead of omitting the section."
                ],
                contextRequestRules: contextRequestRules
            )
        case .groundedCodeReview:
            return OnlyMacsExportContract(
                requestIntent: "grounded_code_review",
                outputContract: "code_review_findings",
                requiredSections: ["Findings", "Missing Tests"] + requestSections + ["Referenced Files"],
                groundingRules: [
                    "Prioritize behavioral bugs, regressions, risky assumptions, and missing tests over style-only commentary.",
                    "Every finding must cite the exact approved relative file path and line range that supports it.",
                    "If the approved files are not enough to prove a bug, move that concern into Missing Tests or Open Questions instead of guessing.",
                    "When Findings is 'None.', every Missing Tests item must still cite the exact approved relative file path and line range that justify the gap.",
                    "Avoid vague commentary like 'clean this up' unless you can tie it to a concrete risk in the approved files.",
                    "Always include every required section, even when it is empty. Use 'None.' instead of omitting the section."
                ],
                contextRequestRules: contextRequestRules
            )
        case .groundedGeneration:
            return OnlyMacsExportContract(
                requestIntent: "grounded_generation",
                outputContract: "proposed_outputs",
                requiredSections: ["Proposed Output", "Open Questions"] + requestSections + ["Referenced Files"],
                groundingRules: [
                    "Propose concrete outputs that are justified by the approved files in this bundle.",
                    "For each proposed output, name the target file or artifact shape explicitly and cite the approved files that support it.",
                    "If schema, examples, or workflow docs are incomplete, say so under Open Questions instead of inventing missing rules.",
                    "Do not claim any file has already been created or saved.",
                    "Always include every required section, even when it is empty. Use 'None.' instead of omitting the section."
                ],
                contextRequestRules: contextRequestRules
            )
        case .groundedTransform:
            return OnlyMacsExportContract(
                requestIntent: "grounded_transform",
                outputContract: "proposed_changes",
                requiredSections: ["Proposed Changes", "Open Questions"] + requestSections + ["Referenced Files"],
                groundingRules: [
                    "Describe concrete file changes that follow from the approved files in this bundle.",
                    "For each proposed change, name the target file and cite the approved evidence that justifies it.",
                    "If the approved files are not enough to propose a safe change, say so under Open Questions.",
                    "Do not claim a patch has already been applied.",
                    "Always include every required section, even when it is empty. Use 'None.' instead of omitting the section."
                ],
                contextRequestRules: contextRequestRules
            )
        case .trustedContext:
            break
        }

        return OnlyMacsExportContract(
            requestIntent: "trusted_context",
            outputContract: nil,
            requiredSections: [],
            groundingRules: [
                "Use only the approved files below as trusted context for this request.",
                "If important context is missing from the approved files, say so plainly."
            ],
            contextRequestRules: contextRequestRules
        )
    }
}

struct OnlyMacsFileExportArtifacts {
    let contextURL: URL
    let manifestURL: URL
    let bundleURL: URL
    let bundleSHA256: String
    let manifest: OnlyMacsFileExportManifest
    let preview: OnlyMacsFileSelectionPreview
}

struct OnlyMacsFileAccessAuditRecord: Codable, Hashable, Sendable {
    let id: String
    let decidedAt: Date
    let status: OnlyMacsFileAccessDecisionStatus
    let workspaceRoot: String
    let swarmName: String?
    let promptSummary: String
    let selectedPaths: [String]
    let exportedPaths: [String]
    let blockedPaths: [String]
    let warnings: [String]
}

private struct OnlyMacsTrustedExportPolicy {
    let mode: OnlyMacsFileExportMode
    let maxFileBytes: Int
    let maxTotalBytes: Int
    let maxScanBytes: Int
    let allowTrimming: Bool
    let requiresFullFiles: Bool
    let trustTier: OnlyMacsCapsuleTrustTier
    let allowContextRequests: Bool
    let maxContextRequestRounds: Int
    let allowAbsolutePaths: Bool
    let leaseMode: String?
    let workspaceKind: String

    static func forRequest(_ request: OnlyMacsFileAccessRequest) -> OnlyMacsTrustedExportPolicy {
        let promptProfile = OnlyMacsPromptProfile(prompt: request.prompt, taskKind: request.taskKind)
        let normalizedRoute = request.routeScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let routeTrustTier: OnlyMacsCapsuleTrustTier
        if normalizedRoute.contains("local") {
            routeTrustTier = .local
        } else if normalizedRoute.contains("public") || normalizedRoute == "swarm" {
            routeTrustTier = .publicUntrusted
        } else if normalizedRoute.contains("git") {
            routeTrustTier = .privateGitBacked
        } else if normalizedRoute.contains("trusted") {
            routeTrustTier = .privateTrusted
        } else {
            routeTrustTier = .privateStandard
        }
        let trustTier = request.trustTier ?? routeTrustTier
        let allowContextRequests = request.allowContextRequests ?? (trustTier != .publicUntrusted)
        let maxContextRequestRounds = request.maxContextRequestRounds ?? (trustTier == .publicUntrusted ? 1 : 2)
        let accessMode = request.fileAccessMode ?? .capsuleSnapshot

        if trustTier == .publicUntrusted {
            return OnlyMacsTrustedExportPolicy(
                mode: .publicExcerptCapsule,
                maxFileBytes: 72_000,
                maxTotalBytes: 180_000,
                maxScanBytes: 90_000,
                allowTrimming: true,
                requiresFullFiles: false,
                trustTier: trustTier,
                allowContextRequests: allowContextRequests,
                maxContextRequestRounds: min(maxContextRequestRounds, 1),
                allowAbsolutePaths: false,
                leaseMode: nil,
                workspaceKind: "public_capsule"
            )
        }

        if accessMode == .gitBackedCheckout {
            return OnlyMacsTrustedExportPolicy(
                mode: .gitBackedCheckout,
                maxFileBytes: 220_000,
                maxTotalBytes: 720_000,
                maxScanBytes: 220_000,
                allowTrimming: false,
                requiresFullFiles: false,
                trustTier: .privateGitBacked,
                allowContextRequests: allowContextRequests,
                maxContextRequestRounds: maxContextRequestRounds,
                allowAbsolutePaths: true,
                leaseMode: "git_backed_checkout",
                workspaceKind: "git_backed"
            )
        }

        if accessMode == .privateProjectLease {
            return OnlyMacsTrustedExportPolicy(
                mode: .privateProjectLease,
                maxFileBytes: 220_000,
                maxTotalBytes: 720_000,
                maxScanBytes: 220_000,
                allowTrimming: false,
                requiresFullFiles: false,
                trustTier: .privateTrusted,
                allowContextRequests: allowContextRequests,
                maxContextRequestRounds: maxContextRequestRounds,
                allowAbsolutePaths: true,
                leaseMode: "private_project_lease",
                workspaceKind: "leased_workspace"
            )
        }

        if promptProfile.requiresReviewGradeExport {
            return OnlyMacsTrustedExportPolicy(
                mode: .trustedReviewFull,
                maxFileBytes: 180_000,
                maxTotalBytes: 480_000,
                maxScanBytes: 200_000,
                allowTrimming: false,
                requiresFullFiles: true,
                trustTier: trustTier,
                allowContextRequests: allowContextRequests,
                maxContextRequestRounds: maxContextRequestRounds,
                allowAbsolutePaths: true,
                leaseMode: nil,
                workspaceKind: "trusted_capsule"
            )
        }
        return OnlyMacsTrustedExportPolicy(
            mode: .trustedContextFlexible,
            maxFileBytes: 160_000,
            maxTotalBytes: 420_000,
            maxScanBytes: 180_000,
            allowTrimming: true,
            requiresFullFiles: false,
            trustTier: trustTier,
            allowContextRequests: allowContextRequests,
            maxContextRequestRounds: maxContextRequestRounds,
            allowAbsolutePaths: true,
            leaseMode: nil,
            workspaceKind: "trusted_capsule"
        )
    }
}

enum OnlyMacsFileAccessStore {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func loadRequest(id: String) throws -> OnlyMacsFileAccessRequest {
        let data = try Data(contentsOf: OnlyMacsStatePaths.requestURL(id: id))
        return try decoder.decode(OnlyMacsFileAccessRequest.self, from: data)
    }

    static func saveResponse(_ response: OnlyMacsFileAccessResponse) throws {
        try ensureStateDirectoryExists()
        let data = try encoder.encode(response)
        try data.write(to: OnlyMacsStatePaths.responseURL(id: response.id), options: .atomic)
    }

    static func saveClaim(_ claim: OnlyMacsFileAccessClaim) throws {
        try ensureStateDirectoryExists()
        let data = try encoder.encode(claim)
        try data.write(to: OnlyMacsStatePaths.claimURL(id: claim.id), options: .atomic)
    }

    static func latestPendingRequest() throws -> OnlyMacsFileAccessRequest? {
        try ensureStateDirectoryExists()
        let directoryURL = OnlyMacsStatePaths.fileAccessDirectoryURL()
        let requestURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
            .filter { $0.lastPathComponent.hasPrefix("request-") && $0.pathExtension == "json" }

        let requests = try requestURLs.compactMap { url -> OnlyMacsFileAccessRequest? in
            let data = try Data(contentsOf: url)
            let request = try decoder.decode(OnlyMacsFileAccessRequest.self, from: data)
            guard !FileManager.default.fileExists(atPath: OnlyMacsStatePaths.responseURL(id: request.id).path) else {
                return nil
            }
            return request
        }

        return requests.max(by: { $0.createdAt < $1.createdAt })
    }

    static func appendAuditRecord(_ record: OnlyMacsFileAccessAuditRecord) throws {
        try ensureStateDirectoryExists()
        let historyURL = OnlyMacsStatePaths.historyURL()
        var records: [OnlyMacsFileAccessAuditRecord] = []
        if FileManager.default.fileExists(atPath: historyURL.path) {
            let data = try Data(contentsOf: historyURL)
            records = try decoder.decode([OnlyMacsFileAccessAuditRecord].self, from: data)
        }
        records.append(record)
        let trimmed = Array(records.suffix(100))
        let data = try encoder.encode(trimmed)
        try data.write(to: historyURL, options: .atomic)
    }

    static func suggestFiles(for request: OnlyMacsFileAccessRequest) -> [OnlyMacsFileSuggestion] {
        let workspaceURL = URL(fileURLWithPath: request.workspaceRoot, isDirectory: true)
        let promptProfile = OnlyMacsPromptProfile(prompt: request.prompt, taskKind: request.taskKind)
        let contextPackCatalog = OnlyMacsContextPackStore.loadCatalog(
            workspaceRoot: request.workspaceRoot,
            promptProfile: promptProfile
        )
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .typeIdentifierKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var suggestions: [OnlyMacsFileSuggestion] = []
        var seenPaths = Set<String>()
        let ignoredPathFragments = [
            "/node_modules/",
            "/.git/",
            "/dist/",
            "/build/",
            "/coverage/",
            "/DerivedData/",
            "/Pods/",
            "/.next/",
            "/.turbo/",
            "/vendor/"
        ]

        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            if ignoredPathFragments.contains(where: { path.contains($0) }) {
                if fileURL.hasDirectoryPath {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .typeIdentifierKey]),
                  values.isRegularFile == true else {
                continue
            }

            let fileName = fileURL.lastPathComponent.lowercased()
            let relativePath = relativePathString(for: path, workspaceRoot: request.workspaceRoot)
            let matchingPacks = contextPackCatalog.suggestedMatches(for: relativePath)
            guard promptProfile.isInteresting(fileName: fileName, relativePath: relativePath) || !matchingPacks.isEmpty else {
                continue
            }

            let bytes = values.fileSize ?? 0
            guard let recommendation = promptProfile.recommendation(
                forFileName: fileName,
                relativePath: relativePath,
                matchingContextPacks: matchingPacks
            ) else {
                continue
            }
            if seenPaths.insert(path).inserted {
                suggestions.append(
                    OnlyMacsFileSuggestion(
                        path: path,
                        relativePath: relativePath,
                        bytes: bytes,
                        reason: recommendation.reason,
                        category: recommendation.category,
                        priority: recommendation.priority,
                        isRecommended: recommendation.isRecommended
                    )
                )
            }
        }

        return suggestions
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                if $0.bytes != $1.bytes { return $0.bytes < $1.bytes }
                return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
            .prefix(60)
            .map { $0 }
    }

    static func preselectedPaths(
        for request: OnlyMacsFileAccessRequest,
        suggestions: [OnlyMacsFileSuggestion]
    ) -> [String] {
        guard !suggestions.isEmpty else { return [] }

        let promptProfile = OnlyMacsPromptProfile(prompt: request.prompt, taskKind: request.taskKind)
        let preferredSuggestions = suggestions.filter(\.isRecommended)
        let candidates = (preferredSuggestions.isEmpty
            ? suggestions
            : preferredSuggestions + suggestions.filter { !$0.isRecommended })
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                if $0.bytes != $1.bytes { return $0.bytes < $1.bytes }
                return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }

        let desiredCount = promptProfile.preselectionTargetCount
        let categoryLimits = promptProfile.preselectionCategoryLimits
        var picked: [OnlyMacsFileSuggestion] = []
        var seenPaths = Set<String>()
        var categoryCounts: [String: Int] = [:]

        func appendSuggestion(_ suggestion: OnlyMacsFileSuggestion) {
            guard seenPaths.insert(suggestion.path).inserted else { return }
            picked.append(suggestion)
            categoryCounts[suggestion.category, default: 0] += 1
        }

        for category in promptProfile.preselectionCategoryOrder {
            let limit = categoryLimits[category] ?? 1
            for suggestion in candidates where suggestion.category == category {
                if (categoryCounts[category] ?? 0) >= limit || picked.count >= desiredCount {
                    break
                }
                appendSuggestion(suggestion)
            }
            if picked.count >= desiredCount {
                break
            }
        }

        if picked.count < desiredCount {
            for suggestion in candidates {
                if picked.count >= desiredCount {
                    break
                }
                appendSuggestion(suggestion)
            }
        }

        return picked.map(\.path)
    }

    @MainActor
    static func chooseFiles(startingAt workspaceRoot: String) -> [String] {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        panel.title = "Choose files to share with this trusted swarm"
        panel.message = "OnlyMacs will export a small read-only bundle for this request."
        panel.prompt = "Share Selected Files"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        guard panel.runModal() == .OK else {
            return []
        }
        return panel.urls.map(\.path)
    }

    private static func ensureStateDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: OnlyMacsStatePaths.fileAccessDirectoryURL(),
            withIntermediateDirectories: true
        )
    }

    static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
}

enum OnlyMacsFileExportBuilder {
    static func buildPreview(
        for request: OnlyMacsFileAccessRequest,
        selectedPaths: [String]
    ) -> OnlyMacsFileSelectionPreview {
        let policy = OnlyMacsTrustedExportPolicy.forRequest(request)
        let normalizedPaths = Array(Set(selectedPaths)).sorted()
        var entries: [OnlyMacsFilePreviewEntry] = []
        var warnings: [String] = []
        var remainingBudget = policy.maxTotalBytes
        var totalSelectedBytes = 0
        var totalExportBytes = 0

        for path in normalizedPaths {
            let evaluation = evaluateSelectedFile(
                path: path,
                workspaceRoot: request.workspaceRoot,
                remainingBudget: remainingBudget,
                policy: policy
            )
            totalSelectedBytes += evaluation.entry.originalBytes
            totalExportBytes += evaluation.entry.exportedBytes
            remainingBudget = max(0, remainingBudget - evaluation.entry.exportedBytes)
            entries.append(evaluation.entry)
            if let warning = evaluation.warning {
                warnings.append(warning)
            }
        }

        return OnlyMacsFileSelectionPreview(
            entries: entries,
            warnings: uniquedPreservingOrder(warnings),
            totalSelectedBytes: totalSelectedBytes,
            totalExportBytes: totalExportBytes
        )
    }

    static func buildArtifacts(
        for request: OnlyMacsFileAccessRequest,
        selectedPaths: [String]
    ) throws -> OnlyMacsFileExportArtifacts {
        let policy = OnlyMacsTrustedExportPolicy.forRequest(request)
        let exportContract = OnlyMacsExportContract.forRequest(request, policy: policy)
        let promptProfile = OnlyMacsPromptProfile(prompt: request.prompt, taskKind: request.taskKind)
        let contextPackCatalog = OnlyMacsContextPackStore.loadCatalog(
            workspaceRoot: request.workspaceRoot,
            promptProfile: promptProfile
        )
        let preview = buildPreview(for: request, selectedPaths: selectedPaths)
        try FileManager.default.createDirectory(
            at: OnlyMacsStatePaths.fileAccessDirectoryURL(),
            withIntermediateDirectories: true
        )

        let exportableEntries = preview.entries.filter { $0.status == .ready || $0.status == .trimmed }
        guard !exportableEntries.isEmpty else {
            throw OnlyMacsFileAccessError.noExportableFiles
        }

        var manifestFiles: [OnlyMacsFileExportManifestFile] = []
        let absolutePathsIncluded = capsuleAllowsAbsolutePaths(routeScope: request.routeScope)
        let selectedContextPacks = contextPackCatalog.selectedManifestEntries(
            selectedRelativePaths: preview.entries.map(\.relativePath)
        )
        let capsuleWarnings = uniquedPreservingOrder(preview.warnings + contextPackCatalog.warnings)
        let trustTier = policy.trustTier
        let workspaceLabel = URL(fileURLWithPath: request.workspaceRoot).lastPathComponent
        let workspaceMetadata = inspectWorkspaceMetadata(
            for: request,
            policy: policy,
            selectedRelativePaths: preview.entries.map(\.relativePath)
        )
        let lease = policy.leaseMode.map {
            OnlyMacsCapsuleLease(
                id: request.leaseID ?? "lease-\(request.workspaceID.replacingOccurrences(of: "/", with: "-"))",
                mode: $0,
                round: request.contextRequestRound ?? 0,
                maxRounds: policy.maxContextRequestRounds,
                expiresAt: Date().addingTimeInterval(30 * 60)
            )
        }
        var sections: [String] = [
            "OnlyMacs trusted file export",
            "Request: \(request.prompt.trimmingCharacters(in: .whitespacesAndNewlines))",
            "Workspace: \(policy.allowAbsolutePaths ? request.workspaceRoot : workspaceLabel)",
            "Request intent: \(exportContract.requestIntent)",
            "Export mode: \(policy.mode.rawValue)",
            "These files were explicitly approved for this one request."
        ]
        if !selectedContextPacks.isEmpty {
            sections.append("Context packs: \(selectedContextPacks.map(\.id).joined(separator: ", "))")
        }
        if let outputContract = exportContract.outputContract {
            sections.append("Output contract: \(outputContract)")
        }
        if !exportContract.requiredSections.isEmpty {
            sections.append("Return sections in this order: \(exportContract.requiredSections.joined(separator: ", "))")
        }
        if !exportContract.groundingRules.isEmpty {
            sections.append("Grounding rules:\n- " + exportContract.groundingRules.joined(separator: "\n- "))
        }

        for entry in preview.entries {
            let recommendation = promptProfile.recommendation(
                forFileName: entry.fileName.lowercased(),
                relativePath: entry.relativePath
            )
            if entry.status == .ready || entry.status == .trimmed,
               let rendered = renderExportedFile(
                   at: entry.path,
                   relativePath: entry.relativePath,
                   exportedBytes: entry.exportedBytes,
                   category: recommendation?.category,
                   selectionReason: recommendation?.reason
               ) {
                sections.append(rendered.text)
                manifestFiles.append(
                    OnlyMacsFileExportManifestFile(
                        path: absolutePathsIncluded ? entry.path : "",
                        relativePath: entry.relativePath,
                        category: recommendation?.category,
                        selectionReason: recommendation?.reason,
                        isRecommended: recommendation?.isRecommended ?? false,
                        reviewPriority: recommendation?.priority ?? 0,
                        evidenceHints: rendered.evidenceHints,
                        evidenceAnchors: rendered.evidenceAnchors,
                        originalBytes: entry.originalBytes,
                        exportedBytes: entry.exportedBytes,
                        status: entry.status,
                        reason: entry.reason,
                        sha256: rendered.sha256
                    )
                )
            } else {
                manifestFiles.append(
                    OnlyMacsFileExportManifestFile(
                        path: absolutePathsIncluded ? entry.path : "",
                        relativePath: entry.relativePath,
                        category: recommendation?.category,
                        selectionReason: recommendation?.reason,
                        isRecommended: recommendation?.isRecommended ?? false,
                        reviewPriority: recommendation?.priority ?? 0,
                        evidenceHints: [],
                        evidenceAnchors: [],
                        originalBytes: entry.originalBytes,
                        exportedBytes: entry.exportedBytes,
                        status: entry.status,
                        reason: entry.reason,
                        sha256: nil
                    )
                )
            }
        }

        let blockedEntries = preview.entries
            .filter { $0.status == .blocked || $0.status == .missing }
            .map {
                OnlyMacsCapsuleBlockedFile(
                    relativePath: $0.relativePath,
                    status: $0.status,
                    reason: $0.reason ?? "OnlyMacs excluded this path from the context capsule."
                )
            }

        let capsuleID = "capsule-\(request.id)"
        let now = Date()
        let expiresAt = now.addingTimeInterval(30 * 60)

        let manifest = OnlyMacsFileExportManifest(
            schema: "context_capsule.v2",
            capsuleID: capsuleID,
            id: request.id,
            requestID: request.id,
            createdAt: now,
            expiresAt: expiresAt,
            workspaceRoot: policy.allowAbsolutePaths ? request.workspaceRoot : "",
            workspaceRootLabel: workspaceLabel,
            workspaceFingerprint: workspaceFingerprint(for: request.workspaceRoot, selectedPaths: preview.entries.map(\.relativePath)),
            routeScope: request.routeScope,
            trustTier: trustTier,
            absolutePathsIncluded: policy.allowAbsolutePaths,
            swarmName: request.swarmName,
            toolName: request.toolName,
            promptSummary: request.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            requestIntent: exportContract.requestIntent,
            exportMode: policy.mode,
            outputContract: exportContract.outputContract,
            requiredSections: exportContract.requiredSections,
            groundingRules: exportContract.groundingRules,
            contextRequestRules: exportContract.contextRequestRules,
            permissions: OnlyMacsCapsulePermissions(
                allowContextRequests: policy.allowContextRequests,
                maxContextRequestRounds: policy.maxContextRequestRounds,
                allowSourceMutation: false,
                allowStagedMutation: trustTier != .publicUntrusted && (request.taskKind == .transform || request.taskKind == .generate),
                allowOutputArtifacts: true
            ),
            budgets: OnlyMacsCapsuleBudgets(
                maxFileBytes: policy.maxFileBytes,
                maxTotalBytes: policy.maxTotalBytes,
                maxScanBytes: policy.maxScanBytes,
                requiresFullFiles: policy.requiresFullFiles,
                allowTrimming: policy.allowTrimming
            ),
            lease: lease,
            workspace: workspaceMetadata,
            contextPacks: selectedContextPacks,
            files: manifestFiles,
            blocked: blockedEntries,
            warnings: capsuleWarnings,
            approval: OnlyMacsCapsuleApprovalMetadata(
                approvalRequired: true,
                requestedAt: request.createdAt,
                approvedAt: now,
                selectedCount: preview.selectedCount,
                exportableCount: preview.exportableCount
            ),
            totalSelectedBytes: preview.totalSelectedBytes,
            totalExportBytes: preview.totalExportBytes
        )

        let contextURL = OnlyMacsStatePaths.contextURL(id: request.id)
        let manifestURL = OnlyMacsStatePaths.manifestURL(id: request.id)
        let bundleURL = OnlyMacsStatePaths.bundleURL(id: request.id)
        let contextText = sections.joined(separator: "\n\n")
        try contextText.write(to: contextURL, atomically: true, encoding: .utf8)
        let manifestData = try OnlyMacsFileAccessStore.encodeJSON(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)
        let bundleSHA256 = try createBundle(
            for: request.id,
            manifest: manifest,
            preview: preview,
            destinationURL: bundleURL
        )

        return OnlyMacsFileExportArtifacts(
            contextURL: contextURL,
            manifestURL: manifestURL,
            bundleURL: bundleURL,
            bundleSHA256: bundleSHA256,
            manifest: manifest,
            preview: preview
        )
    }

    private static func evaluateSelectedFile(
        path: String,
        workspaceRoot: String,
        remainingBudget: Int,
        policy: OnlyMacsTrustedExportPolicy
    ) -> (entry: OnlyMacsFilePreviewEntry, warning: String?) {
        let relativePath = relativePathString(for: path, workspaceRoot: workspaceRoot)
        let fileURL = URL(fileURLWithPath: path, isDirectory: false)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path),
              let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            return (
                OnlyMacsFilePreviewEntry(
                    path: path,
                    relativePath: relativePath,
                    originalBytes: 0,
                    exportedBytes: 0,
                    status: .missing,
                    reason: "This file is no longer available."
                ),
                "OnlyMacs skipped \(relativePath) because it could not be found anymore."
            )
        }

        let originalBytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let lowercasedPath = relativePath.lowercased()

        if OnlyMacsSensitiveFileRules.isBlockedByPath(lowercasedPath) {
            return (
                OnlyMacsFilePreviewEntry(
                    path: path,
                    relativePath: relativePath,
                    originalBytes: originalBytes,
                    exportedBytes: 0,
                    status: .blocked,
                    reason: "This looks like a secret or credential file."
                ),
                "OnlyMacs blocked \(relativePath) because secret and credential files never leave this Mac automatically."
            )
        }

        if !OnlyMacsSensitiveFileRules.isSupportedTextFile(fileURL: fileURL) {
            return (
                OnlyMacsFilePreviewEntry(
                    path: path,
                    relativePath: relativePath,
                    originalBytes: originalBytes,
                    exportedBytes: 0,
                    status: .blocked,
                    reason: "OnlyMacs only exports readable text files for trusted swarm tasks."
                ),
                "OnlyMacs skipped \(relativePath) because it does not look like a text file."
            )
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return (
                OnlyMacsFilePreviewEntry(
                    path: path,
                    relativePath: relativePath,
                    originalBytes: originalBytes,
                    exportedBytes: 0,
                    status: .blocked,
                    reason: "OnlyMacs could not read this file."
                ),
                "OnlyMacs skipped \(relativePath) because it could not read it."
            )
        }

        let scanWindow = data.prefix(policy.maxScanBytes)
        if let reason = OnlyMacsSensitiveFileRules.contentBlockReason(for: scanWindow) {
            return (
                OnlyMacsFilePreviewEntry(
                    path: path,
                    relativePath: relativePath,
                    originalBytes: originalBytes,
                    exportedBytes: 0,
                    status: .blocked,
                    reason: reason
                ),
                "OnlyMacs blocked \(relativePath) because it appears to contain secrets or credentials."
            )
        }

        if remainingBudget <= 0 {
            return (
                OnlyMacsFilePreviewEntry(
                    path: path,
                    relativePath: relativePath,
                    originalBytes: originalBytes,
                    exportedBytes: 0,
                    status: .blocked,
                    reason: "The approved bundle is already full."
                ),
                policy.requiresFullFiles
                    ? "OnlyMacs skipped \(relativePath) because full-file review mode is already at its size limit."
                    : "OnlyMacs skipped \(relativePath) because the trusted export is already at its size limit."
            )
        }

        let perFileBudget = min(policy.maxFileBytes, remainingBudget)
        if policy.requiresFullFiles && originalBytes > perFileBudget {
            return (
                OnlyMacsFilePreviewEntry(
                    path: path,
                    relativePath: relativePath,
                    originalBytes: originalBytes,
                    exportedBytes: 0,
                    status: .blocked,
                    reason: "This review needs the full file, but it would exceed the trusted export budget."
                ),
                "OnlyMacs needs the full file for a review-grade export. Remove some files or narrow the request before sharing \(relativePath)."
            )
        }

        let exportedBytes = policy.allowTrimming ? min(originalBytes, perFileBudget) : originalBytes
        let wasTrimmed = exportedBytes < originalBytes
        let reason = wasTrimmed ? "OnlyMacs will send a trimmed preview of this file." : nil
        let warning = wasTrimmed ? "OnlyMacs will trim \(relativePath) so the trusted bundle stays readable." : nil
        return (
            OnlyMacsFilePreviewEntry(
                path: path,
                relativePath: relativePath,
                originalBytes: originalBytes,
                exportedBytes: exportedBytes,
                status: wasTrimmed ? .trimmed : .ready,
                reason: reason
            ),
            warning
        )
    }

    private static func createBundle(
        for requestID: String,
        manifest: OnlyMacsFileExportManifest,
        preview: OnlyMacsFileSelectionPreview,
        destinationURL: URL
    ) throws -> String {
        let fileManager = FileManager.default
        let stagingID = manifest.lease.map { "lease-\($0.id)" } ?? requestID
        let stagingRoot = OnlyMacsStatePaths.bundleStagingDirectoryURL(id: stagingID)
        try? fileManager.removeItem(at: stagingRoot)
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        let manifestURL = stagingRoot.appendingPathComponent("manifest.json", isDirectory: false)
        let manifestData = try OnlyMacsFileAccessStore.encodeJSON(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        for entry in preview.entries where entry.status == .ready || entry.status == .trimmed {
            let sourceURL = URL(fileURLWithPath: entry.path, isDirectory: false)
            let destinationFileURL = stagingRoot.appendingPathComponent(entry.relativePath, isDirectory: false)
            try fileManager.createDirectory(at: destinationFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Data(contentsOf: sourceURL).prefix(max(0, entry.exportedBytes))
            try Data(data).write(to: destinationFileURL, options: .atomic)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar", isDirectory: false)
        process.currentDirectoryURL = stagingRoot.deletingLastPathComponent()
        process.arguments = [
            "-czf",
            destinationURL.lastPathComponent,
            stagingRoot.lastPathComponent
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OnlyMacsFileAccessError.bundleCreationFailed
        }

        let bundleData = try Data(contentsOf: destinationURL)
        let digest = SHA256.hash(data: bundleData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func capsuleAllowsAbsolutePaths(routeScope: String) -> Bool {
        !routeScope.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("public")
    }

    private static func capsuleTrustTier(for routeScope: String) -> OnlyMacsCapsuleTrustTier {
        let normalized = routeScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("local") {
            return .local
        }
        if normalized.contains("public") || normalized == "swarm" {
            return .publicUntrusted
        }
        if normalized.contains("git") {
            return .privateGitBacked
        }
        if normalized.contains("trusted") {
            return .privateTrusted
        }
        return .privateStandard
    }

    private static func inspectWorkspaceMetadata(
        for request: OnlyMacsFileAccessRequest,
        policy: OnlyMacsTrustedExportPolicy,
        selectedRelativePaths: [String]
    ) -> OnlyMacsCapsuleWorkspace? {
        let rootURL = URL(fileURLWithPath: request.workspaceRoot, isDirectory: true)
        let gitDirectory = rootURL.appendingPathComponent(".git", isDirectory: true)
        let selected = Array(Set(selectedRelativePaths)).sorted()

        guard policy.mode == .gitBackedCheckout || policy.mode == .privateProjectLease else {
            return OnlyMacsCapsuleWorkspace(
                kind: policy.workspaceKind,
                vcs: nil,
                gitHead: nil,
                gitBranch: nil,
                gitDirty: false,
                trackedFiles: selected
            )
        }

        guard FileManager.default.fileExists(atPath: gitDirectory.path) else {
            return OnlyMacsCapsuleWorkspace(
                kind: policy.workspaceKind,
                vcs: nil,
                gitHead: nil,
                gitBranch: nil,
                gitDirty: false,
                trackedFiles: selected
            )
        }

        let head = gitOutput(arguments: ["rev-parse", "HEAD"], workspaceRoot: request.workspaceRoot)
        let branch = gitOutput(arguments: ["rev-parse", "--abbrev-ref", "HEAD"], workspaceRoot: request.workspaceRoot)
        let dirty = !(gitOutput(arguments: ["status", "--porcelain"], workspaceRoot: request.workspaceRoot)?.isEmpty ?? true)
        let trackedFiles = gitTrackedFiles(workspaceRoot: request.workspaceRoot, selectedRelativePaths: selected)

        return OnlyMacsCapsuleWorkspace(
            kind: policy.workspaceKind,
            vcs: "git",
            gitHead: head,
            gitBranch: branch,
            gitDirty: dirty,
            trackedFiles: trackedFiles
        )
    }

    private static func gitOutput(arguments: [String], workspaceRoot: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git", isDirectory: false)
        process.arguments = ["-C", workspaceRoot] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        } catch {
            return nil
        }
    }

    private static func gitTrackedFiles(workspaceRoot: String, selectedRelativePaths: [String]) -> [String] {
        guard let output = gitOutput(arguments: ["ls-files"] + selectedRelativePaths, workspaceRoot: workspaceRoot) else {
            return selectedRelativePaths
        }
        let tracked = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return tracked.isEmpty ? selectedRelativePaths : tracked
    }

    private static func workspaceFingerprint(for workspaceRoot: String, selectedPaths: [String]) -> String {
        let normalized = ([workspaceRoot] + selectedPaths.sorted()).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func renderExportedFile(
        at path: String,
        relativePath: String,
        exportedBytes: Int,
        category: String?,
        selectionReason: String?
    ) -> (text: String, sha256: String, evidenceHints: [String], evidenceAnchors: [OnlyMacsFileEvidenceAnchor])? {
        let fileURL = URL(fileURLWithPath: path, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let trimmedData = data.prefix(max(0, exportedBytes))
        guard let text = String(data: trimmedData, encoding: .utf8) else {
            return nil
        }

        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = fileURL.pathExtension
        let evidenceAnchors = extractEvidenceAnchors(from: cleanText)
        let evidenceHints = evidenceAnchors.map(\.text)
        var metadataLines: [String] = []
        if let category, !category.isEmpty {
            metadataLines.append("Category: \(category)")
        }
        if let selectionReason, !selectionReason.isEmpty {
            metadataLines.append("Why selected: \(selectionReason)")
        }
        if !evidenceHints.isEmpty {
            metadataLines.append("Evidence hints: " + evidenceHints.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        if !evidenceAnchors.isEmpty {
            let anchors = evidenceAnchors.map { anchor in
                "lines \(anchor.lineStart)-\(anchor.lineEnd) \"\(anchor.text)\""
            }.joined(separator: ", ")
            metadataLines.append("Evidence anchors: \(anchors)")
        }
        let metadataBlock = metadataLines.isEmpty ? "" : metadataLines.joined(separator: "\n") + "\n"
        let rendered = """
        ### Approved File: \(relativePath)
        \(metadataBlock)```\(language)
        \(cleanText)
        ```
        """
        let digest = SHA256.hash(data: trimmedData)
        let sha = digest.map { String(format: "%02x", $0) }.joined()
        return (rendered, sha, evidenceHints, evidenceAnchors)
    }

    private static func extractEvidenceAnchors(from text: String) -> [OnlyMacsFileEvidenceAnchor] {
        var anchors: [OnlyMacsFileEvidenceAnchor] = []

        func appendAnchor(kind: String, lineNumber: Int, raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalized = trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let clipped = normalized.count > 90 ? String(normalized.prefix(90)) + "…" : normalized
            guard !anchors.contains(where: { $0.text == clipped && $0.lineStart == lineNumber && $0.kind == kind }) else { return }
            anchors.append(
                OnlyMacsFileEvidenceAnchor(
                    kind: kind,
                    lineStart: lineNumber,
                    lineEnd: lineNumber,
                    text: clipped
                )
            )
        }

        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") {
                appendAnchor(
                    kind: "heading",
                    lineNumber: index + 1,
                    raw: trimmed.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
                )
            }
            if anchors.count >= 3 {
                return anchors
            }
        }

        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("```") else { continue }
            appendAnchor(kind: "snippet", lineNumber: index + 1, raw: trimmed)
            if anchors.count >= 3 {
                break
            }
        }

        return anchors
    }

    private static func uniquedPreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

enum OnlyMacsFileAccessError: Error {
    case noExportableFiles
    case bundleCreationFailed
}

private enum OnlyMacsSensitiveFileRules {
    private static let likelyTextExtensions: Set<String> = [
        "md", "markdown", "txt", "json", "yaml", "yml",
        "ts", "tsx", "js", "jsx", "mjs", "cjs",
        "swift", "py", "sh", "csv", "html", "css",
        "scss", "sass", "xml", "toml", "ini", "conf"
    ]

    private static let blockedPathFragments = [
        ".env",
        "id_rsa",
        ".pem",
        ".p12",
        ".key",
        "credentials",
        "credential",
        "secret",
        "secrets"
    ]

    private static let contentNeedles = [
        "begin private key",
        "begin rsa private key",
        "begin openssh private key",
        "authorization: bearer",
        "aws_secret_access_key",
        "openai_api_key",
        "anthropic_api_key",
        "x-api-key"
    ]

    private static let contentRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"AKIA[0-9A-Z]{16}"#),
        try! NSRegularExpression(pattern: #"sk-[A-Za-z0-9]{20,}"#),
        try! NSRegularExpression(pattern: #"sk-ant-[A-Za-z0-9\-_]{20,}"#)
    ]

    static func isBlockedByPath(_ lowercasedPath: String) -> Bool {
        blockedPathFragments.contains { lowercasedPath.contains($0) }
    }

    static func isSupportedTextFile(fileURL: URL) -> Bool {
        let loweredExtension = fileURL.pathExtension.lowercased()
        if likelyTextExtensions.contains(loweredExtension) {
            return true
        }
        guard let type = UTType(filenameExtension: fileURL.pathExtension) else {
            return false
        }
        return type.conforms(to: .text) || type == .json || type == .xml || type == .sourceCode
    }

    static func contentBlockReason(for data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8)?.lowercased() else {
            return nil
        }
        if contentNeedles.contains(where: { text.contains($0) }) {
            return "This file appears to contain credentials or bearer tokens."
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        if contentRegexes.contains(where: { $0.firstMatch(in: text, options: [], range: range) != nil }) {
            return "This file appears to contain live API keys or cloud credentials."
        }
        return nil
    }
}

fileprivate struct OnlyMacsFileSuggestionRecommendation {
    let priority: Int
    let reason: String
    let category: String
    let isRecommended: Bool
}

struct OnlyMacsPromptProfile {
    enum ExportIntent {
        case groundedReview
        case groundedCodeReview
        case groundedGeneration
        case groundedTransform
        case trustedContext
    }

    private enum Kind {
        case contentPipeline
        case codeReview
        case dataTransform
        case generic
    }

    private let prompt: String
    private let kind: Kind

    init(prompt: String, taskKind: OnlyMacsRequestTaskKind? = nil) {
        self.prompt = prompt.lowercased()
        if taskKind == .generate || taskKind == .transform,
           (self.prompt.contains("content pipeline")
                || self.prompt.contains("pipeline docs")
                || self.prompt.contains("json file")
                || self.prompt.contains("json files")
                || self.prompt.contains("schema")
                || self.prompt.contains("glossary")
                || self.prompt.contains("lesson")) {
            self.kind = .contentPipeline
        } else if taskKind == .review || taskKind == .debug || taskKind == .transform,
                  (self.prompt.contains("code review")
                    || self.prompt.contains("review this repo")
                    || self.prompt.contains("review this project")
                    || self.prompt.contains("review this codebase")
                    || ((self.prompt.contains("repo") || self.prompt.contains("project") || self.prompt.contains("codebase"))
                        && (self.prompt.contains("code")
                            || self.prompt.contains("auth")
                            || self.prompt.contains("api")
                            || self.prompt.contains("react")
                            || self.prompt.contains("app flow")))
                    || self.prompt.contains("source tree")
                    || self.prompt.contains("tests")
                    || self.prompt.contains("build")
                    || self.prompt.contains("concurrency")
                    || self.prompt.contains("race condition")
                    || self.prompt.contains("import paths")
                    || self.prompt.contains("package.json")
                    || self.prompt.contains("tsconfig")
                    || self.prompt.contains("review my code")) {
            self.kind = .codeReview
        } else if self.prompt.contains("content pipeline")
            || self.prompt.contains("pipeline docs")
            || self.prompt.contains("master docs")
            || self.prompt.contains("content generation")
            || (self.prompt.contains("pipeline") && self.prompt.contains("docs"))
            || self.prompt.contains("flashcard")
            || self.prompt.contains("json file")
            || self.prompt.contains("json files") {
            self.kind = .contentPipeline
        } else if self.prompt.contains("review my code")
            || self.prompt.contains("code review")
            || self.prompt.contains("review this repo")
            || self.prompt.contains("review this project")
            || self.prompt.contains("review this codebase")
            || ((self.prompt.contains("repo") || self.prompt.contains("project") || self.prompt.contains("codebase"))
                && (self.prompt.contains("code")
                    || self.prompt.contains("auth")
                    || self.prompt.contains("api")
                    || self.prompt.contains("react")
                    || self.prompt.contains("app flow")))
            || self.prompt.contains("source tree")
            || self.prompt.contains("tests")
            || self.prompt.contains("build")
            || self.prompt.contains("concurrency")
            || self.prompt.contains("race condition")
            || self.prompt.contains("import paths")
            || self.prompt.contains("package.json")
            || self.prompt.contains("tsconfig") {
            self.kind = .codeReview
        } else if self.prompt.contains("rearrange") || self.prompt.contains("transform") || self.prompt.contains("schema") {
            self.kind = .dataTransform
        } else {
            self.kind = .generic
        }
    }

    private var looksLikeGeneration: Bool {
        prompt.contains("generate")
            || prompt.contains("create ")
            || prompt.contains("create more")
            || prompt.contains("write new")
            || prompt.contains("fresh batch")
            || prompt.contains("five more")
            || prompt.contains("new json")
            || prompt.contains("draft ")
            || prompt.contains("produce ")
            || prompt.contains("synthesize")
            || prompt.contains("assemble ")
    }

    private var looksLikeTransform: Bool {
        prompt.contains("edit")
            || prompt.contains("rewrite")
            || prompt.contains("update")
            || prompt.contains("modify")
            || prompt.contains("fix")
            || prompt.contains("patch")
            || prompt.contains("rearrange")
            || prompt.contains("rename")
            || prompt.contains("refactor")
            || prompt.contains("change")
            || prompt.contains("apply")
            || prompt.contains("transform")
    }

    private var contentPipelineWantsDocs: Bool {
        prompt.contains("docs")
            || prompt.contains("documentation")
            || prompt.contains("readme")
            || prompt.contains("guide")
            || prompt.contains("glossary")
    }

    private var contentPipelineWantsExamples: Bool {
        prompt.contains("example")
            || prompt.contains("examples")
            || prompt.contains("sample")
            || prompt.contains("json file")
            || prompt.contains("json files")
    }

    private var contentPipelineIsReviewRequest: Bool {
        prompt.contains("review")
            || prompt.contains("audit")
            || prompt.contains("inspect")
            || prompt.contains("unclear")
            || prompt.contains("inconsistent")
            || prompt.contains("likely to break")
    }

    private var contentPipelineWantsSchema: Bool {
        prompt.contains("schema")
            || prompt.contains("structure")
            || prompt.contains("json")
            || prompt.contains("format")
    }

    private var contentPipelineWantsRunArtifacts: Bool {
        prompt.contains("manifest")
            || prompt.contains("checkpoint")
            || prompt.contains("run notes")
            || prompt.contains("handoff")
    }

    private var contentPipelineWantsScripts: Bool {
        prompt.contains("runner")
            || prompt.contains("script")
            || prompt.contains("implementation")
            || prompt.contains("break")
    }

    private var contentPipelineWantsMasterDocs: Bool {
        prompt.contains("pipeline docs")
            || prompt.contains("master docs")
            || prompt.contains("docs in this project")
            || prompt.contains("unclear")
            || prompt.contains("inconsistent")
            || prompt.contains("likely to break")
            || prompt.contains("review")
    }

    private var contentPipelineWantsIntake: Bool {
        prompt.contains("intake")
            || prompt.contains("language intake")
            || prompt.contains("source language")
            || prompt.contains("source assumptions")
            || prompt.contains("input language")
    }

    private var contentPipelineWantsGlossary: Bool {
        prompt.contains("glossary")
            || prompt.contains("terminology")
            || prompt.contains("definitions")
    }

    private var contentPipelineWantsFullSourceSet: Bool {
        guard kind == .contentPipeline else { return false }
        let wantsCompleteness = prompt.contains("full ")
            || prompt.contains("complete")
            || prompt.contains("entire")
            || prompt.contains("end-to-end")
            || prompt.contains("whole ")
            || prompt.contains("full set")
            || prompt.contains("all master docs")
            || prompt.contains("all pipeline docs")
            || prompt.contains("source set")
        let wantsGroundedAssembly = looksLikeGeneration
            || looksLikeTransform
            || prompt.contains("build ")
            || prompt.contains("from the ")
            || prompt.contains("using the ")
        let wantsCoreSources = contentPipelineWantsMasterDocs
            || contentPipelineWantsIntake
            || contentPipelineWantsSchema
            || contentPipelineWantsExamples
        return wantsCompleteness && wantsGroundedAssembly && wantsCoreSources
    }

    private var contentPipelineNeedsExpandedSourceSet: Bool {
        guard kind == .contentPipeline else { return false }
        if contentPipelineWantsFullSourceSet {
            return true
        }
        let wantsSynthesis = looksLikeGeneration
            || looksLikeTransform
            || prompt.contains("build ")
            || prompt.contains("from the ")
            || prompt.contains("using the ")
        let mentionsMultipleSourceKinds = [contentPipelineWantsMasterDocs, contentPipelineWantsIntake, contentPipelineWantsSchema, contentPipelineWantsExamples, contentPipelineWantsGlossary]
            .filter { $0 }
            .count >= 2
        return wantsSynthesis && mentionsMultipleSourceKinds
    }

    var requiresReviewGradeExport: Bool {
        switch exportIntent(policy: OnlyMacsTrustedExportPolicy(
            mode: .trustedContextFlexible,
            maxFileBytes: 0,
            maxTotalBytes: 0,
            maxScanBytes: 0,
            allowTrimming: true,
            requiresFullFiles: false,
            trustTier: .privateStandard,
            allowContextRequests: true,
            maxContextRequestRounds: 1,
            allowAbsolutePaths: true,
            leaseMode: nil,
            workspaceKind: "trusted_capsule"
        )) {
        case .groundedReview, .groundedCodeReview:
            return true
        case .groundedGeneration, .groundedTransform, .trustedContext:
            return false
        }
    }

    fileprivate func exportIntent(policy: OnlyMacsTrustedExportPolicy) -> ExportIntent {
        let isGeneration = looksLikeGeneration
        let isTransform = looksLikeTransform
        let isReview = prompt.contains("review")
            || prompt.contains("audit")
            || prompt.contains("inspect")
            || prompt.contains("check")
            || prompt.contains("validate")
            || prompt.contains("unclear")
            || prompt.contains("inconsistent")
            || prompt.contains("likely to break")
            || prompt.contains("debug")
            || prompt.contains("broken")
            || prompt.contains("risks")
            || prompt.contains("contradictions")

        if isGeneration {
            return .groundedGeneration
        }
        if isTransform {
            return .groundedTransform
        }
        if kind == .codeReview || prompt.contains("code review") {
            return .groundedCodeReview
        }
        if isReview || policy.mode == .trustedReviewFull {
            return .groundedReview
        }
        return .trustedContext
    }

    func isInteresting(fileName: String, relativePath: String) -> Bool {
        let lower = relativePath.lowercased()
        switch kind {
        case .contentPipeline:
            return isInterestingContentPipelinePath(lower)
        case .codeReview:
            return lower.contains("readme")
                || lower.contains("package.json")
                || lower.contains("tsconfig")
                || lower.contains("/src/")
                || lower.hasSuffix(".swift")
                || lower.hasSuffix(".ts")
                || lower.hasSuffix(".tsx")
                || lower.hasSuffix(".js")
        case .dataTransform:
            return lower.contains("schema")
                || lower.contains("example")
                || lower.contains("sample")
                || lower.hasSuffix(".json")
                || lower.hasSuffix(".csv")
                || lower.hasSuffix(".md")
                || lower.hasSuffix(".yaml")
                || lower.hasSuffix(".yml")
        case .generic:
            return lower.contains("readme")
                || lower.contains("guide")
                || lower.contains("prompt")
                || lower.contains("instructions")
                || lower.hasSuffix(".md")
                || lower.hasSuffix(".json")
                || lower.hasSuffix(".yaml")
                || lower.hasSuffix(".yml")
                || lower.hasSuffix(".txt")
        }
    }

    fileprivate func recommendation(
        forFileName fileName: String,
        relativePath: String,
        matchingContextPacks: [OnlyMacsContextPackDefinition] = []
    ) -> OnlyMacsFileSuggestionRecommendation? {
        let lower = relativePath.lowercased()
        let base: OnlyMacsFileSuggestionRecommendation?
        switch kind {
        case .contentPipeline:
            base = contentPipelineRecommendation(for: lower)
        case .codeReview:
            base = codeReviewRecommendation(for: lower)
        case .dataTransform:
            base = genericRecommendation(
                for: lower,
                matches: [
                    ("schema", 98, "Schema or structure rules", "Schema"),
                    ("example", 94, "Example input or output", "Examples"),
                    ("sample", 92, "Example input or output", "Examples")
                ],
                extensions: [
                    (".json", 90, "Data file or example payload", "JSON"),
                    (".csv", 88, "Tabular source data", "Data"),
                    (".md", 82, "Readable instructions or docs", "Docs"),
                    (".yaml", 86, "Config or schema definition", "Config"),
                    (".yml", 86, "Config or schema definition", "Config")
                ],
                recommendedThreshold: 92
            )
        case .generic:
            base = genericRecommendation(
                for: lower,
                matches: [
                    ("readme", 92, "Project overview and usage notes", "Docs"),
                    ("guide", 90, "Instructions or implementation guide", "Docs"),
                    ("prompt", 86, "Prompt or workflow instructions", "Docs"),
                    ("instructions", 86, "Instructions or implementation guide", "Docs")
                ],
                extensions: [
                    (".md", 82, "Readable instructions or docs", "Docs"),
                    (".json", 80, "Structured data or examples", "JSON"),
                    (".yaml", 80, "Config or schema definition", "Config"),
                    (".yml", 80, "Config or schema definition", "Config"),
                    (".txt", 76, "Plain-text notes or instructions", "Docs")
                ],
                recommendedThreshold: 90
            )
        }

        return boostedRecommendation(base: base, matchingContextPacks: matchingContextPacks)
    }

    private func contentPipelineRecommendation(for lower: String) -> OnlyMacsFileSuggestionRecommendation? {
        var best: OnlyMacsFileSuggestionRecommendation?
        let isDeprecated = lower.contains("/deprecated/")
        let isDraft = lower.contains("/drafts/")
        let wantsDocs = contentPipelineWantsDocs
        let wantsExamples = contentPipelineWantsExamples
        let isReviewRequest = contentPipelineIsReviewRequest
        let wantsSchema = contentPipelineWantsSchema
        let wantsRunArtifacts = contentPipelineWantsRunArtifacts
        let wantsScripts = contentPipelineWantsScripts
        let wantsMasterDocs = contentPipelineWantsMasterDocs
        let wantsIntake = contentPipelineWantsIntake
        let wantsExpandedSourceSet = contentPipelineNeedsExpandedSourceSet

        func consider(priority: Int, reason: String, category: String, recommended: Bool) {
            guard priority > (best?.priority ?? Int.min) else { return }
            best = OnlyMacsFileSuggestionRecommendation(priority: priority, reason: reason, category: category, isRecommended: recommended)
        }

        if lower.hasPrefix("1 - master ")
            || lower.hasPrefix("2 - master ")
            || lower.hasPrefix("3 - master ")
            || lower.hasPrefix("4 - master ")
            || lower.hasPrefix("5 - master ")
            || lower.hasPrefix("6 - master ")
            || lower.contains("/1 - master ")
            || lower.contains("/2 - master ")
            || lower.contains("/3 - master ")
            || lower.contains("/4 - master ")
            || lower.contains("/5 - master ")
            || lower.contains("/6 - master ") {
            consider(
                priority: wantsMasterDocs ? 320 : 290,
                reason: "Core pipeline contract",
                category: "Master Docs",
                recommended: true
            )
        }

        if lower.hasSuffix("/readme.md")
            && (lower.contains("/docs/") || lower.hasPrefix("docs/"))
            && !isDeprecated {
            consider(
                priority: lower.contains("/content-generation/") ? 300 : 304,
                reason: lower.contains("/content-generation/") ? "Content generation outputs and folder rules" : "Top-level pipeline overview",
                category: "Overview",
                recommended: true
            )
        }

        if lower.hasSuffix("/readme.md") && (lower.contains("/scripts/") || lower.hasPrefix("scripts/")) {
            consider(priority: 288, reason: "Runner entrypoints and script usage", category: "Scripts", recommended: true)
        }

        if lower.hasSuffix(".md") && (lower.contains("/docs/") || lower.hasPrefix("docs/")) && !isDeprecated {
            consider(
                priority: wantsDocs ? (isReviewRequest ? 296 : 268) : 206,
                reason: lower.contains("glossary") ? "Shared terminology and definitions" : "Readable pipeline instructions",
                category: lower.contains("glossary") ? "Glossary" : "Docs",
                recommended: wantsDocs || (isReviewRequest && !isDraft)
            )
        }

        if lower.contains("/scripts/")
            && (lower.contains("step2_pilot_runner")
                || lower.contains("run_step2_generation")
                || lower.contains("run_step2_pilot")
                || lower.contains("run_step3_local_qa")
                || lower.contains("report_step2_progress")
                || lower.contains("checkpoint_step2_run")
                || lower.contains("build_standard_step2_config")
                || lower.contains("locale_guide_schema")) {
            consider(
                priority: wantsScripts ? 260 : 236,
                reason: "Pipeline runner or validation logic",
                category: "Scripts",
                recommended: true
            )
        }

        if lower.contains("master-intake") {
            let intakePriority: Int
            if wantsIntake {
                intakePriority = wantsExpandedSourceSet ? 312 : 284
            } else if wantsExpandedSourceSet {
                intakePriority = 248
            } else {
                intakePriority = 188
            }
            consider(
                priority: intakePriority,
                reason: "Language intake and source assumptions",
                category: "Intake",
                recommended: wantsIntake || wantsExpandedSourceSet
            )
        }

        if lower.contains("schema") {
            consider(
                priority: wantsSchema ? (isReviewRequest ? 248 : 232) : 190,
                reason: "Schema or structure rules",
                category: "Schema",
                recommended: wantsSchema || (isReviewRequest && wantsExamples)
            )
        }

        if lower.contains("example") || lower.contains("sample") {
            consider(
                priority: wantsExamples ? (isReviewRequest ? 274 : 246) : 194,
                reason: "Example content or expected output shape",
                category: "Examples",
                recommended: wantsExamples || isReviewRequest
            )
        }

        if lower.contains("run-manifest.json") {
            consider(
                priority: wantsRunArtifacts ? (isDeprecated ? 122 : 176) : (isDeprecated ? 64 : 104),
                reason: "Generated state snapshot for a specific pack",
                category: "Run State",
                recommended: wantsRunArtifacts && !isDeprecated
            )
        }

        if lower.contains("run notes") || lower.contains("step-") && lower.contains("notes") {
            consider(
                priority: wantsRunArtifacts ? (isDeprecated ? 118 : 168) : (isDeprecated ? 60 : 98),
                reason: "Step-specific handoff or run notes",
                category: "Run Notes",
                recommended: wantsRunArtifacts && !isDeprecated
            )
        }

        if isDraft {
            consider(
                priority: wantsSchema ? 150 : 120,
                reason: "Draft pack-specific notes or schema",
                category: "Drafts",
                recommended: false
            )
        }

        if isDeprecated {
            consider(priority: 54, reason: "Older deprecated pipeline artifact", category: "Deprecated", recommended: false)
        }

        if lower.hasSuffix(".md") && (lower.contains("guide") || lower.contains("pipeline") || lower.contains("content")) {
            consider(priority: isDeprecated ? 62 : 162, reason: "Readable pipeline instructions", category: "Docs", recommended: false)
        }

        if lower.hasSuffix(".json") {
            consider(priority: isDeprecated ? 58 : 112, reason: "Structured data or generated output", category: "JSON", recommended: false)
        }

        if lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
            consider(priority: isDeprecated ? 62 : 118, reason: "Config or schema definition", category: "Config", recommended: false)
        }

        if lower.hasSuffix(".js") {
            consider(priority: isDeprecated ? 64 : 124, reason: "Implementation or generation logic", category: "Scripts", recommended: false)
        }

        return best
    }

    private func codeReviewRecommendation(for lower: String) -> OnlyMacsFileSuggestionRecommendation? {
        var best: OnlyMacsFileSuggestionRecommendation?
        let wantsAuth = prompt.contains("auth") || prompt.contains("token") || prompt.contains("credential")
        let wantsAPI = prompt.contains("api") || prompt.contains("network") || prompt.contains("fetch")
        let wantsApp = prompt.contains("react") || prompt.contains("app") || prompt.contains("bootstrap") || prompt.contains("ui")
        let wantsConfig = prompt.contains("package.json") || prompt.contains("tsconfig") || prompt.contains("typescript") || prompt.contains("build")
        let wantsReadme = prompt.contains("readme") || prompt.contains("overview")

        func consider(priority: Int, reason: String, category: String, recommended: Bool) {
            guard priority > (best?.priority ?? Int.min) else { return }
            best = OnlyMacsFileSuggestionRecommendation(priority: priority, reason: reason, category: category, isRecommended: recommended)
        }

        if lower.contains("package.json") {
            consider(priority: wantsConfig ? 330 : 304, reason: "App package and dependency definition", category: "Config", recommended: true)
        }

        if lower.contains("tsconfig") {
            consider(priority: wantsConfig ? 328 : 300, reason: "TypeScript build configuration", category: "Config", recommended: true)
        }

        if lower.contains("readme") {
            consider(priority: wantsReadme ? 320 : 298, reason: "Project overview and usage notes", category: "Docs", recommended: true)
        }

        if wantsAuth && lower.contains("auth") {
            consider(priority: 322, reason: "Authentication and token handling", category: "Source", recommended: true)
        }

        if wantsAPI && lower.contains("api") {
            consider(priority: 320, reason: "API and network request handling", category: "Source", recommended: true)
        }

        if wantsApp && lower.contains("app.") {
            consider(priority: 318, reason: "Main app flow and React usage", category: "Source", recommended: true)
        }

        if lower.contains("/src/") {
            consider(priority: 280, reason: "Primary application source", category: "Source", recommended: true)
        }

        if lower.hasSuffix(".swift") {
            consider(priority: 274, reason: "Swift source to review", category: "Source", recommended: true)
        }

        if lower.hasSuffix(".ts") || lower.hasSuffix(".tsx") {
            consider(priority: 272, reason: "TypeScript source to review", category: "Source", recommended: true)
        }

        if lower.hasSuffix(".js") {
            consider(priority: 266, reason: "JavaScript source to review", category: "Source", recommended: false)
        }

        return best
    }

    private func isInterestingContentPipelinePath(_ lower: String) -> Bool {
        if lower.contains("/deprecated/") && !prompt.contains("deprecated") {
            return lower.contains("run-manifest.json") || lower.contains("run notes")
        }
        return lower.contains("/1 - master ")
            || lower.contains("/2 - master ")
            || lower.contains("/3 - master ")
            || lower.contains("/4 - master ")
            || lower.contains("/5 - master ")
            || lower.contains("/6 - master ")
            || lower.hasSuffix("/readme.md")
            || lower.contains("/content-generation/")
            || lower.contains("/scripts/")
            || lower.contains("schema")
            || lower.contains("run-manifest.json")
            || lower.contains("run notes")
            || lower.contains("step-") && lower.contains("notes")
            || lower.contains("/drafts/")
            || lower.hasSuffix(".json")
            || lower.hasSuffix(".md")
            || lower.hasSuffix(".yaml")
            || lower.hasSuffix(".yml")
            || lower.hasSuffix(".js")
    }

    var preselectionTargetCount: Int {
        switch kind {
        case .contentPipeline:
            if contentPipelineWantsFullSourceSet {
                return 12
            }
            if contentPipelineNeedsExpandedSourceSet {
                return 10
            }
            return 8
        case .codeReview:
            return 8
        case .dataTransform:
            return 6
        case .generic:
            return 6
        }
    }

    var preselectionCategoryOrder: [String] {
        switch kind {
        case .contentPipeline:
            if contentPipelineNeedsExpandedSourceSet {
                return ["Master Docs", "Intake", "Overview", "Schema", "Examples", "Glossary", "Docs", "Scripts", "Config", "JSON", "Drafts", "Run State", "Run Notes"]
            }
            return ["Master Docs", "Intake", "Overview", "Docs", "Glossary", "Examples", "Schema", "Scripts", "Config", "JSON", "Drafts", "Run State", "Run Notes"]
        case .codeReview:
            return ["Source", "Config", "Docs", "Overview"]
        case .dataTransform:
            return ["Schema", "Examples", "Docs", "JSON", "Config", "Data"]
        case .generic:
            return ["Docs", "Overview", "JSON", "Config"]
        }
    }

    var preselectionCategoryLimits: [String: Int] {
        switch kind {
        case .contentPipeline:
            if contentPipelineWantsFullSourceSet {
                return [
                    "Master Docs": 6,
                    "Intake": 2,
                    "Overview": 2,
                    "Docs": 4,
                    "Glossary": 2,
                    "Examples": 3,
                    "Schema": 3,
                    "Scripts": 3,
                    "Config": 2,
                    "JSON": 2
                ]
            }
            if contentPipelineNeedsExpandedSourceSet {
                return [
                    "Master Docs": 4,
                    "Intake": 2,
                    "Overview": 2,
                    "Docs": 3,
                    "Glossary": 1,
                    "Examples": 3,
                    "Schema": 3,
                    "Scripts": 2,
                    "Config": 2,
                    "JSON": 1
                ]
            }
            return [
                "Master Docs": 3,
                "Intake": 1,
                "Overview": 2,
                "Docs": 3,
                "Glossary": 1,
                "Examples": 2,
                "Schema": 2,
                "Scripts": 2,
                "Config": 1,
                "JSON": 1
            ]
        case .codeReview:
            return [
                "Source": 4,
                "Config": 2,
                "Docs": 2,
                "Overview": 1
            ]
        case .dataTransform:
            return [
                "Schema": 2,
                "Examples": 2,
                "Docs": 2,
                "JSON": 2,
                "Config": 1,
                "Data": 1
            ]
        case .generic:
            return [
                "Docs": 3,
                "Overview": 2,
                "JSON": 2,
                "Config": 1
            ]
        }
    }

    private func genericRecommendation(
        for lower: String,
        matches: [(String, Int, String, String)],
        extensions: [(String, Int, String, String)],
        recommendedThreshold: Int
    ) -> OnlyMacsFileSuggestionRecommendation? {
        var bestPriority = Int.min
        var bestReason = ""
        var bestCategory = ""

        for (needle, priority, reason, category) in matches where lower.contains(needle) {
            if priority > bestPriority {
                bestPriority = priority
                bestReason = reason
                bestCategory = category
            }
        }

        for (suffix, priority, reason, category) in extensions where lower.hasSuffix(suffix) {
            if priority > bestPriority {
                bestPriority = priority
                bestReason = reason
                bestCategory = category
            }
        }

        guard bestPriority > Int.min else { return nil }
        return OnlyMacsFileSuggestionRecommendation(
            priority: bestPriority,
            reason: bestReason,
            category: bestCategory,
            isRecommended: bestPriority >= recommendedThreshold
        )
    }

    var suggestedContextPackIDs: [String] {
        switch kind {
        case .contentPipeline:
            return ["content-pipeline", "schema-generation"]
        case .codeReview:
            return ["code-review-core"]
        case .dataTransform:
            return ["transform-context", "schema-generation"]
        case .generic:
            return prompt.contains("review")
                ? ["docs-review"]
                : ["docs-review", "schema-generation"]
        }
    }

    private func boostedRecommendation(
        base: OnlyMacsFileSuggestionRecommendation?,
        matchingContextPacks: [OnlyMacsContextPackDefinition]
    ) -> OnlyMacsFileSuggestionRecommendation? {
        guard !matchingContextPacks.isEmpty else {
            return base
        }

        let packBoost = matchingContextPacks.contains { suggestedContextPackIDs.contains($0.id) } ? 36 : 18
        let pack = matchingContextPacks[0]
        if let base {
            return OnlyMacsFileSuggestionRecommendation(
                priority: base.priority + packBoost,
                reason: base.reason,
                category: base.category,
                isRecommended: base.isRecommended || suggestedContextPackIDs.contains(pack.id)
            )
        }

        return OnlyMacsFileSuggestionRecommendation(
            priority: 160 + packBoost,
            reason: pack.description,
            category: pack.scope == .publicSafe ? "Context Pack" : "Trusted Pack",
            isRecommended: suggestedContextPackIDs.contains(pack.id)
        )
    }
}

private func relativePathString(for path: String, workspaceRoot: String) -> String {
    let normalizedRoot = URL(fileURLWithPath: workspaceRoot, isDirectory: true).standardizedFileURL.path
    let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    if normalizedPath.hasPrefix(normalizedRoot + "/") {
        return String(normalizedPath.dropFirst(normalizedRoot.count + 1))
    }
    return URL(fileURLWithPath: normalizedPath).lastPathComponent
}

private extension ByteCountFormatter {
    static func onlyMacsString(fromByteCount byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: byteCount)
    }
}
