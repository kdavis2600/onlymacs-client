import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import OnlyMacsCore
import SwiftUI

// Bridge-facing transport and presentation models live here so the main store
// file can focus on state ownership, effects, and coordination logic.

struct BridgeStatusSnapshot: Decodable {
    var bridge: BridgeSummary
    var runtime: BridgeRuntime
    var identity: LocalIdentitySummary
    var modes: [String]
    var swarms: [SwarmOption]
    var swarm: SwarmSummary
    var usage: UsageSummary
    var providers: [ProviderSummary]
    var members: [SwarmMemberSummary]
    var models: [ModelSummary]
    var lastUpdated: Date?

    private enum CodingKeys: String, CodingKey {
        case bridge
        case runtime
        case identity
        case modes
        case swarms
        case swarm
        case usage
        case providers
        case members
        case models
    }

    init(
        bridge: BridgeSummary,
        runtime: BridgeRuntime,
        identity: LocalIdentitySummary,
        modes: [String],
        swarms: [SwarmOption],
        swarm: SwarmSummary,
        usage: UsageSummary,
        providers: [ProviderSummary],
        members: [SwarmMemberSummary],
        models: [ModelSummary],
        lastUpdated: Date?
    ) {
        self.bridge = bridge
        self.runtime = runtime
        self.identity = identity
        self.modes = modes
        self.swarms = swarms
        self.swarm = swarm
        self.usage = usage
        self.providers = providers
        self.members = members
        self.models = models
        self.lastUpdated = lastUpdated
    }

    static let placeholder = BridgeStatusSnapshot(
        bridge: BridgeSummary(status: "bootstrapping", coordinatorURL: nil, activeSwarmName: nil, error: nil),
        runtime: BridgeRuntime(mode: "use", activeSwarmID: ""),
        identity: .placeholder,
        modes: ["use", "share", "both"],
        swarms: [],
        swarm: SwarmSummary(activeSessionCount: 0, queuedSessionCount: 0, queueSummary: .empty, recentSessions: []),
        usage: UsageSummary(
            tokensSavedEstimate: 0,
            downloadedTokensEstimate: 0,
            uploadedTokensEstimate: 0,
            recentRemoteTokensPerSecond: 0,
            activeReservations: 0,
            reservationCap: 0,
            communityBoost: CommunityBoostSummary(level: 3, label: "Steady", metricLabel: "Community Boost", primaryTrait: "Fresh Face", traits: ["Fresh Face"], detail: "Fresh start. Share this Mac and your boost climbs when the rare slots get crowded.")
        ),
        providers: [],
        members: [],
        models: [],
        lastUpdated: nil
    )

    static func offline(message: String) -> BridgeStatusSnapshot {
        BridgeStatusSnapshot(
            bridge: BridgeSummary(status: "degraded", coordinatorURL: nil, activeSwarmName: nil, error: message),
            runtime: BridgeRuntime(mode: "use", activeSwarmID: ""),
            identity: .placeholder,
            modes: ["use", "share", "both"],
            swarms: [],
            swarm: SwarmSummary(activeSessionCount: 0, queuedSessionCount: 0, queueSummary: .empty, recentSessions: []),
            usage: UsageSummary(
                tokensSavedEstimate: 0,
                downloadedTokensEstimate: 0,
                uploadedTokensEstimate: 0,
                recentRemoteTokensPerSecond: 0,
                activeReservations: 0,
                reservationCap: 0,
                communityBoost: CommunityBoostSummary(level: 3, label: "Steady", metricLabel: "Community Boost", primaryTrait: "Fresh Face", traits: ["Fresh Face"], detail: "Fresh start. Share this Mac and your boost climbs when the rare slots get crowded.")
            ),
            providers: [],
            members: [],
            models: [],
            lastUpdated: nil
        )
    }

    var summaryLine: String {
        let queued = swarm.queuedSessionCount > 0 ? ", \(swarm.queuedSessionCount) queued" : ""
        return "\(swarm.slotCapacityLabel), \(swarm.modelCount) models, \(swarm.activeSessionCount) active swarms\(queued)"
    }

    func withUpdatedTimestamp() -> BridgeStatusSnapshot {
        var copy = self
        copy.lastUpdated = Date()
        return copy
    }

    func withOptimisticLocalMemberName(_ memberName: String) -> BridgeStatusSnapshot {
        var copy = self
        let trimmed = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return copy }

        let localMemberID = identity.memberID
        let localProviderID = identity.providerID
        copy.identity = identity.withMemberName(trimmed)
        copy.providers = providers.map { provider in
            if provider.id == localProviderID || provider.ownerMemberID == localMemberID {
                return provider.withOwnerMemberName(trimmed, providerName: provider.id == localProviderID ? trimmed : nil)
            }
            return provider
        }
        copy.members = members.map { member in
            member.memberID == localMemberID ? member.withMemberName(trimmed, providerID: localProviderID) : member
        }
        return copy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bridge = try container.decode(BridgeSummary.self, forKey: .bridge)
        runtime = try container.decode(BridgeRuntime.self, forKey: .runtime)
        identity = try container.decodeIfPresent(LocalIdentitySummary.self, forKey: .identity) ?? .placeholder
        modes = try container.decodeIfPresent([String].self, forKey: .modes) ?? []
        swarms = try container.decodeIfPresent([SwarmOption].self, forKey: .swarms) ?? []
        swarm = try container.decode(SwarmSummary.self, forKey: .swarm)
        usage = try container.decode(UsageSummary.self, forKey: .usage)
        providers = try container.decodeIfPresent([ProviderSummary].self, forKey: .providers) ?? []
        members = try container.decodeIfPresent([SwarmMemberSummary].self, forKey: .members) ?? []
        models = try container.decodeIfPresent([ModelSummary].self, forKey: .models) ?? []
        lastUpdated = nil
    }
}

struct LocalIdentitySummary: Decodable {
    let memberID: String
    let memberName: String
    let providerID: String
    let providerName: String

    private enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case memberName = "member_name"
        case providerID = "provider_id"
        case providerName = "provider_name"
    }

    static let placeholder = LocalIdentitySummary(
        memberID: "",
        memberName: "This Mac",
        providerID: "",
        providerName: "This Mac"
    )

    func withMemberName(_ name: String) -> LocalIdentitySummary {
        LocalIdentitySummary(
            memberID: memberID,
            memberName: name,
            providerID: providerID,
            providerName: name
        )
    }
}

struct SwarmSummary: Decodable {
    let activeSessionCount: Int
    let queuedSessionCount: Int
    let queueSummary: QueueSummarySnapshot
    let recentSessions: [SwarmSessionSnapshot]
    let slotsFree: Int
    let slotsTotal: Int
    let modelCount: Int
    let providerActiveCount: Int

    private enum CodingKeys: String, CodingKey {
        case activeSessionCount = "active_session_count"
        case queuedSessionCount = "queued_session_count"
        case queueSummary = "queue_summary"
        case recentSessions = "recent_sessions"
        case slotsFree = "slots_free"
        case slotsTotal = "slots_total"
        case modelCount = "model_count"
        case providerActiveCount = "provider_active_count"
    }

    init(
        activeSessionCount: Int,
        queuedSessionCount: Int = 0,
        queueSummary: QueueSummarySnapshot = .empty,
        recentSessions: [SwarmSessionSnapshot] = [],
        slotsFree: Int = 0,
        slotsTotal: Int = 0,
        modelCount: Int = 0,
        providerActiveCount: Int = 0
    ) {
        self.activeSessionCount = activeSessionCount
        self.queuedSessionCount = queuedSessionCount
        self.queueSummary = queueSummary
        self.recentSessions = recentSessions
        self.slotsFree = slotsFree
        self.slotsTotal = slotsTotal
        self.modelCount = modelCount
        self.providerActiveCount = providerActiveCount
    }

    init(slotsFree: Int, slotsTotal: Int, modelCount: Int, activeSessionCount: Int) {
        self.init(
            activeSessionCount: activeSessionCount,
            queuedSessionCount: 0,
            queueSummary: .empty,
            recentSessions: [],
            slotsFree: slotsFree,
            slotsTotal: slotsTotal,
            modelCount: modelCount,
            providerActiveCount: activeSessionCount
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeSessionCount = try container.decodeIfPresent(Int.self, forKey: .activeSessionCount) ?? 0
        queuedSessionCount = try container.decodeIfPresent(Int.self, forKey: .queuedSessionCount) ?? 0
        queueSummary = try container.decodeIfPresent(QueueSummarySnapshot.self, forKey: .queueSummary) ?? .empty
        recentSessions = try container.decodeIfPresent([SwarmSessionSnapshot].self, forKey: .recentSessions) ?? []
        slotsFree = try container.decodeIfPresent(Int.self, forKey: .slotsFree) ?? 0
        slotsTotal = try container.decodeIfPresent(Int.self, forKey: .slotsTotal) ?? 0
        modelCount = try container.decodeIfPresent(Int.self, forKey: .modelCount) ?? 0
        providerActiveCount = try container.decodeIfPresent(Int.self, forKey: .providerActiveCount) ?? activeSessionCount
    }

    var slotCapacityLabel: String {
        switch (slotsFree, slotsTotal) {
        case (_, let total) where total <= 0:
            return "no slots ready"
        default:
            return "\(slotsFree)/\(slotsTotal) slots free"
        }
    }
}

typealias SwarmCapacitySummary = SwarmSummary

struct QueueSummarySnapshot: Decodable {
    let queuedSessionCount: Int
    let premiumContentionCount: Int
    let premiumBudgetCount: Int
    let premiumCooldownCount: Int
    let capacityWaitCount: Int
    let widthLimitedCount: Int
    let requesterBudgetCount: Int
    let memberCapCount: Int
    let staleQueuedCount: Int
    let nextETASeconds: Int
    let maxETASeconds: Int
    let primaryReason: String
    let primaryDetail: String
    let suggestedAction: String

    static let empty = QueueSummarySnapshot(
        queuedSessionCount: 0,
        premiumContentionCount: 0,
        premiumBudgetCount: 0,
        premiumCooldownCount: 0,
        capacityWaitCount: 0,
        widthLimitedCount: 0,
        requesterBudgetCount: 0,
        memberCapCount: 0,
        staleQueuedCount: 0,
        nextETASeconds: 0,
        maxETASeconds: 0,
        primaryReason: "",
        primaryDetail: "",
        suggestedAction: ""
    )

    private enum CodingKeys: String, CodingKey {
        case queuedSessionCount = "queued_session_count"
        case premiumContentionCount = "premium_contention_count"
        case premiumBudgetCount = "premium_budget_count"
        case premiumCooldownCount = "premium_cooldown_count"
        case capacityWaitCount = "capacity_wait_count"
        case widthLimitedCount = "width_limited_count"
        case requesterBudgetCount = "requester_budget_count"
        case memberCapCount = "member_cap_count"
        case staleQueuedCount = "stale_queued_count"
        case nextETASeconds = "next_eta_seconds"
        case maxETASeconds = "max_eta_seconds"
        case primaryReason = "primary_reason"
        case primaryDetail = "primary_detail"
        case suggestedAction = "suggested_action"
    }

    init(
        queuedSessionCount: Int,
        premiumContentionCount: Int,
        premiumBudgetCount: Int,
        premiumCooldownCount: Int,
        capacityWaitCount: Int,
        widthLimitedCount: Int,
        requesterBudgetCount: Int,
        memberCapCount: Int,
        staleQueuedCount: Int,
        nextETASeconds: Int,
        maxETASeconds: Int,
        primaryReason: String,
        primaryDetail: String,
        suggestedAction: String
    ) {
        self.queuedSessionCount = queuedSessionCount
        self.premiumContentionCount = premiumContentionCount
        self.premiumBudgetCount = premiumBudgetCount
        self.premiumCooldownCount = premiumCooldownCount
        self.capacityWaitCount = capacityWaitCount
        self.widthLimitedCount = widthLimitedCount
        self.requesterBudgetCount = requesterBudgetCount
        self.memberCapCount = memberCapCount
        self.staleQueuedCount = staleQueuedCount
        self.nextETASeconds = nextETASeconds
        self.maxETASeconds = maxETASeconds
        self.primaryReason = primaryReason
        self.primaryDetail = primaryDetail
        self.suggestedAction = suggestedAction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queuedSessionCount = try container.decodeIfPresent(Int.self, forKey: .queuedSessionCount) ?? 0
        premiumContentionCount = try container.decodeIfPresent(Int.self, forKey: .premiumContentionCount) ?? 0
        premiumBudgetCount = try container.decodeIfPresent(Int.self, forKey: .premiumBudgetCount) ?? 0
        premiumCooldownCount = try container.decodeIfPresent(Int.self, forKey: .premiumCooldownCount) ?? 0
        capacityWaitCount = try container.decodeIfPresent(Int.self, forKey: .capacityWaitCount) ?? 0
        widthLimitedCount = try container.decodeIfPresent(Int.self, forKey: .widthLimitedCount) ?? 0
        requesterBudgetCount = try container.decodeIfPresent(Int.self, forKey: .requesterBudgetCount) ?? 0
        memberCapCount = try container.decodeIfPresent(Int.self, forKey: .memberCapCount) ?? 0
        staleQueuedCount = try container.decodeIfPresent(Int.self, forKey: .staleQueuedCount) ?? 0
        nextETASeconds = try container.decodeIfPresent(Int.self, forKey: .nextETASeconds) ?? 0
        maxETASeconds = try container.decodeIfPresent(Int.self, forKey: .maxETASeconds) ?? 0
        primaryReason = try container.decodeIfPresent(String.self, forKey: .primaryReason) ?? ""
        primaryDetail = try container.decodeIfPresent(String.self, forKey: .primaryDetail) ?? ""
        suggestedAction = try container.decodeIfPresent(String.self, forKey: .suggestedAction) ?? ""
    }
}

struct SwarmSessionSnapshot: Decodable, Identifiable {
    let id: String
    let title: String?
    let status: String
    let resolvedModel: String
    let selectionReason: String?
    let selectionExplanation: String?
    let routeSummary: String?
    let warnings: [String]?
    let savedTokensEstimate: Int
    let queueRemainder: Int
    let queueReason: String?
    let etaSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case resolvedModel = "resolved_model"
        case selectionReason = "selection_reason"
        case selectionExplanation = "selection_explanation"
        case routeSummary = "route_summary"
        case warnings
        case savedTokensEstimate = "saved_tokens_estimate"
        case queueRemainder = "queue_remainder"
        case queueReason = "queue_reason"
        case etaSeconds = "eta_seconds"
    }
}

struct StarterCommandSuggestion: Identifiable {
    let title: String
    let command: String

    var id: String { title }
}

struct LocalShareSnapshot: Decodable {
    let providerID: String
    let providerName: String
    let mode: String
    let activeSwarmID: String
    let activeSwarmName: String?
    let published: Bool
    let status: String
    let maintenanceState: String?
    let activeSessions: Int
    let slots: Slots
    let discoveredModels: [ModelSummary]
    let publishedModels: [ModelSummary]
    let servedSessions: Int
    let servedStreamSessions: Int
    let failedSessions: Int
    let uploadedTokensEstimate: Int
    let recentUploadedTokensPerSecond: Double
    let lastServedModel: String?
    let lastServedAt: String?
    let clientBuild: ClientBuildSummary?
    let recentProviderActivity: [ProviderActivitySummary]
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case mode
        case activeSwarmID = "active_swarm_id"
        case activeSwarmName = "active_swarm_name"
        case published
        case status
        case maintenanceState = "maintenance_state"
        case activeSessions = "active_sessions"
        case slots
        case discoveredModels = "discovered_models"
        case publishedModels = "published_models"
        case servedSessions = "served_sessions"
        case servedStreamSessions = "served_stream_sessions"
        case failedSessions = "failed_sessions"
        case uploadedTokensEstimate = "uploaded_tokens_estimate"
        case recentUploadedTokensPerSecond = "recent_uploaded_tokens_per_second"
        case lastServedModel = "last_served_model"
        case lastServedAt = "last_served_at"
        case clientBuild = "client_build"
        case recentProviderActivity = "recent_provider_activity"
        case error
    }

    init(
        providerID: String,
        providerName: String,
        mode: String,
        activeSwarmID: String,
        activeSwarmName: String?,
        published: Bool,
        status: String,
        maintenanceState: String?,
        activeSessions: Int,
        slots: Slots,
        discoveredModels: [ModelSummary],
        publishedModels: [ModelSummary],
        servedSessions: Int,
        servedStreamSessions: Int,
        failedSessions: Int,
        uploadedTokensEstimate: Int,
        recentUploadedTokensPerSecond: Double,
        lastServedModel: String?,
        lastServedAt: String?,
        clientBuild: ClientBuildSummary?,
        recentProviderActivity: [ProviderActivitySummary],
        error: String?
    ) {
        self.providerID = providerID
        self.providerName = providerName
        self.mode = mode
        self.activeSwarmID = activeSwarmID
        self.activeSwarmName = activeSwarmName
        self.published = published
        self.status = status
        self.maintenanceState = maintenanceState
        self.activeSessions = activeSessions
        self.slots = slots
        self.discoveredModels = discoveredModels
        self.publishedModels = publishedModels
        self.servedSessions = servedSessions
        self.servedStreamSessions = servedStreamSessions
        self.failedSessions = failedSessions
        self.uploadedTokensEstimate = uploadedTokensEstimate
        self.recentUploadedTokensPerSecond = recentUploadedTokensPerSecond
        self.lastServedModel = lastServedModel
        self.lastServedAt = lastServedAt
        self.clientBuild = clientBuild
        self.recentProviderActivity = recentProviderActivity
        self.error = error
    }

    static let placeholder = LocalShareSnapshot(
        providerID: "provider-this-mac",
        providerName: "This Mac",
        mode: "use",
        activeSwarmID: "",
        activeSwarmName: nil,
        published: false,
        status: "bootstrapping",
        maintenanceState: nil,
        activeSessions: 0,
        slots: Slots(free: 1, total: 1),
        discoveredModels: [],
        publishedModels: [],
        servedSessions: 0,
        servedStreamSessions: 0,
        failedSessions: 0,
        uploadedTokensEstimate: 0,
        recentUploadedTokensPerSecond: 0,
        lastServedModel: nil,
        lastServedAt: nil,
        clientBuild: nil,
        recentProviderActivity: [],
        error: nil
    )

    static func offline(message: String) -> LocalShareSnapshot {
        LocalShareSnapshot(
            providerID: "provider-this-mac",
            providerName: "This Mac",
            mode: "use",
            activeSwarmID: "",
            activeSwarmName: nil,
            published: false,
            status: "offline",
            maintenanceState: nil,
            activeSessions: 0,
            slots: Slots(free: 0, total: 0),
            discoveredModels: [],
            publishedModels: [],
            servedSessions: 0,
            servedStreamSessions: 0,
            failedSessions: 0,
            uploadedTokensEstimate: 0,
            recentUploadedTokensPerSecond: 0,
            lastServedModel: nil,
            lastServedAt: nil,
            clientBuild: nil,
            recentProviderActivity: [],
            error: message
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(String.self, forKey: .providerID)
        providerName = try container.decode(String.self, forKey: .providerName)
        mode = try container.decode(String.self, forKey: .mode)
        activeSwarmID = try container.decodeIfPresent(String.self, forKey: .activeSwarmID) ?? ""
        activeSwarmName = try container.decodeIfPresent(String.self, forKey: .activeSwarmName)
        published = try container.decode(Bool.self, forKey: .published)
        status = try container.decode(String.self, forKey: .status)
        maintenanceState = try container.decodeIfPresent(String.self, forKey: .maintenanceState)
        activeSessions = try container.decodeIfPresent(Int.self, forKey: .activeSessions) ?? 0
        slots = try container.decode(Slots.self, forKey: .slots)
        discoveredModels = try container.decodeIfPresent([ModelSummary].self, forKey: .discoveredModels) ?? []
        publishedModels = try container.decodeIfPresent([ModelSummary].self, forKey: .publishedModels) ?? []
        servedSessions = try container.decodeIfPresent(Int.self, forKey: .servedSessions) ?? 0
        servedStreamSessions = try container.decodeIfPresent(Int.self, forKey: .servedStreamSessions) ?? 0
        failedSessions = try container.decodeIfPresent(Int.self, forKey: .failedSessions) ?? 0
        uploadedTokensEstimate = try container.decodeIfPresent(Int.self, forKey: .uploadedTokensEstimate) ?? 0
        recentUploadedTokensPerSecond = try container.decodeIfPresent(Double.self, forKey: .recentUploadedTokensPerSecond) ?? 0
        lastServedModel = try container.decodeIfPresent(String.self, forKey: .lastServedModel)
        lastServedAt = try container.decodeIfPresent(String.self, forKey: .lastServedAt)
        clientBuild = try container.decodeIfPresent(ClientBuildSummary.self, forKey: .clientBuild)
        recentProviderActivity = try container.decodeIfPresent([ProviderActivitySummary].self, forKey: .recentProviderActivity) ?? []
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    func withOptimisticProviderName(_ name: String) -> LocalShareSnapshot {
        LocalShareSnapshot(
            providerID: providerID,
            providerName: name,
            mode: mode,
            activeSwarmID: activeSwarmID,
            activeSwarmName: activeSwarmName,
            published: published,
            status: status,
            maintenanceState: maintenanceState,
            activeSessions: activeSessions,
            slots: slots,
            discoveredModels: discoveredModels,
            publishedModels: publishedModels,
            servedSessions: servedSessions,
            servedStreamSessions: servedStreamSessions,
            failedSessions: failedSessions,
            uploadedTokensEstimate: uploadedTokensEstimate,
            recentUploadedTokensPerSecond: recentUploadedTokensPerSecond,
            lastServedModel: lastServedModel,
            lastServedAt: lastServedAt,
            clientBuild: clientBuild,
            recentProviderActivity: recentProviderActivity,
            error: error
        )
    }
}

struct ProviderActivitySummary: Decodable, Identifiable {
    let id: String
    let jobID: String?
    let sessionID: String?
    let swarmID: String?
    let swarmName: String?
    let providerID: String
    let providerName: String?
    let ownerMemberID: String?
    let ownerMemberName: String?
    let requesterMemberID: String?
    let requesterMemberName: String?
    let resolvedModel: String?
    let stream: Bool
    let status: String
    let statusCode: Int
    let uploadedBytes: Int
    let uploadedTokensEstimate: Int
    let startedAt: String?
    let updatedAt: String?
    let completedAt: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case jobID = "job_id"
        case sessionID = "session_id"
        case swarmID = "swarm_id"
        case swarmName = "swarm_name"
        case providerID = "provider_id"
        case providerName = "provider_name"
        case ownerMemberID = "owner_member_id"
        case ownerMemberName = "owner_member_name"
        case requesterMemberID = "requester_member_id"
        case requesterMemberName = "requester_member_name"
        case resolvedModel = "resolved_model"
        case stream
        case status
        case statusCode = "status_code"
        case uploadedBytes = "uploaded_bytes"
        case uploadedTokensEstimate = "uploaded_tokens_estimate"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case error
    }
}

struct BridgeSummary: Decodable {
    let status: String
    let coordinatorURL: String?
    let activeSwarmName: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case coordinatorURL = "coordinator_url"
        case activeSwarmName = "active_swarm_name"
        case error
    }
}

struct BridgeRuntime: Codable {
    let mode: String
    let activeSwarmID: String

    private enum CodingKeys: String, CodingKey {
        case mode
        case activeSwarmID = "active_swarm_id"
    }
}

struct SwarmJoinPolicyOption: Decodable, Equatable {
    let version: Int
    let mode: String
    let passwordConfigured: Bool
    let allowedEmails: [String]
    let allowedDomains: [String]
    let requireApproval: Bool

    private enum CodingKeys: String, CodingKey {
        case version
        case mode
        case passwordConfigured = "password_configured"
        case allowedEmails = "allowed_emails"
        case allowedDomains = "allowed_domains"
        case requireApproval = "require_approval"
    }

    init(
        version: Int = 1,
        mode: String,
        passwordConfigured: Bool = false,
        allowedEmails: [String] = [],
        allowedDomains: [String] = [],
        requireApproval: Bool = false
    ) {
        self.version = version
        self.mode = mode
        self.passwordConfigured = passwordConfigured
        self.allowedEmails = allowedEmails
        self.allowedDomains = allowedDomains
        self.requireApproval = requireApproval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "invite_link"
        passwordConfigured = try container.decodeIfPresent(Bool.self, forKey: .passwordConfigured) ?? false
        allowedEmails = try container.decodeIfPresent([String].self, forKey: .allowedEmails) ?? []
        allowedDomains = try container.decodeIfPresent([String].self, forKey: .allowedDomains) ?? []
        requireApproval = try container.decodeIfPresent(Bool.self, forKey: .requireApproval) ?? false
    }

    static func fallback(discoverability: String, visibility: String) -> SwarmJoinPolicyOption {
        if discoverability == "listed" || visibility == "public" {
            return SwarmJoinPolicyOption(mode: "open")
        }
        return SwarmJoinPolicyOption(mode: "invite_link")
    }

    var isOpenMembership: Bool {
        mode == "open"
    }
}

struct SwarmOption: Decodable, Identifiable {
    let id: String
    let name: String
    let slug: String?
    let publicPath: String?
    let visibility: String
    let discoverability: String
    let joinPolicy: SwarmJoinPolicyOption
    let memberCount: Int
    let slotsFree: Int
    let slotsTotal: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case publicPath = "public_path"
        case visibility
        case discoverability
        case joinPolicy = "join_policy"
        case memberCount = "member_count"
        case slotsFree = "slots_free"
        case slotsTotal = "slots_total"
    }

    init(
        id: String,
        name: String,
        slug: String? = nil,
        publicPath: String? = nil,
        visibility: String,
        discoverability: String? = nil,
        joinPolicy: SwarmJoinPolicyOption? = nil,
        memberCount: Int,
        slotsFree: Int,
        slotsTotal: Int
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.publicPath = publicPath
        self.visibility = visibility
        let resolvedDiscoverability = discoverability ?? (visibility == "public" ? "listed" : "unlisted")
        self.discoverability = resolvedDiscoverability
        self.joinPolicy = joinPolicy ?? SwarmJoinPolicyOption.fallback(discoverability: resolvedDiscoverability, visibility: visibility)
        self.memberCount = memberCount
        self.slotsFree = slotsFree
        self.slotsTotal = slotsTotal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        publicPath = try container.decodeIfPresent(String.self, forKey: .publicPath)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility) ?? "private"
        discoverability = try container.decodeIfPresent(String.self, forKey: .discoverability) ?? (visibility == "public" ? "listed" : "unlisted")
        joinPolicy = try container.decodeIfPresent(SwarmJoinPolicyOption.self, forKey: .joinPolicy) ?? SwarmJoinPolicyOption.fallback(discoverability: discoverability, visibility: visibility)
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        slotsFree = try container.decodeIfPresent(Int.self, forKey: .slotsFree) ?? 0
        slotsTotal = try container.decodeIfPresent(Int.self, forKey: .slotsTotal) ?? 0
    }

    var isPublic: Bool { discoverability == "listed" || visibility == "public" }

    var allowsInviteSharing: Bool { !joinPolicy.isOpenMembership }

    var visibilityBadgeTitle: String {
        isPublic ? "Public" : "Private"
    }

    var accessDetail: String {
        if joinPolicy.isOpenMembership {
            return "Open to everyone on this coordinator."
        }
        if joinPolicy.mode == "password" {
            return "People with the swarm link and password can join."
        }
        if joinPolicy.mode == "oauth_allowlist" {
            return "Only approved accounts can join."
        }
        return "Only people with your invite can join."
    }

    func selectionDetail(activeSessionCount: Int) -> String {
        let memberLabel = memberCount == 1 ? "member" : "members"
        let activeLabel = activeSessionCount == 1 ? "active swarm" : "active swarms"
        return "\(memberCount) \(memberLabel), \(slotSummaryLabel), \(activeSessionCount) \(activeLabel)"
    }

    var slotSummaryLabel: String {
        switch (slotsFree, slotsTotal) {
        case (_, let total) where total <= 0:
            return "no slots shared yet"
        case (let free, let total) where free == total:
            let slotLabel = total == 1 ? "slot" : "slots"
            return "\(total) \(slotLabel) ready"
        default:
            return "\(slotsFree)/\(slotsTotal) slots free"
        }
    }

    var pickerTitle: String {
        if isPublic {
            return "\(name) (public)"
        }
        return "\(name) (invite-only)"
    }

    var connectedHeadlineTitle: String {
        let memberLabel = memberCount == 1 ? "member" : "members"
        let slotLabel = slotsTotal == 1 ? "slot" : "slots"

        guard memberCount > 0 || slotsTotal > 0 else {
            return name
        }

        return "\(name) (\(memberCount) \(memberLabel), \(slotsTotal) \(slotLabel))"
    }
}

struct UsageSummary: Decodable {
    let tokensSavedEstimate: Int
    let downloadedTokensEstimate: Int
    let uploadedTokensEstimate: Int
    let recentRemoteTokensPerSecond: Double
    let activeReservations: Int
    let reservationCap: Int
    let communityBoost: CommunityBoostSummary

    private enum CodingKeys: String, CodingKey {
        case tokensSavedEstimate = "tokens_saved_estimate"
        case downloadedTokensEstimate = "downloaded_tokens_estimate"
        case uploadedTokensEstimate = "uploaded_tokens_estimate"
        case recentRemoteTokensPerSecond = "recent_remote_tokens_per_second"
        case activeReservations = "active_reservations"
        case reservationCap = "reservation_cap"
        case communityBoost = "community_boost"
    }

    init(
        tokensSavedEstimate: Int,
        downloadedTokensEstimate: Int,
        uploadedTokensEstimate: Int,
        recentRemoteTokensPerSecond: Double,
        activeReservations: Int,
        reservationCap: Int,
        communityBoost: CommunityBoostSummary
    ) {
        self.tokensSavedEstimate = tokensSavedEstimate
        self.downloadedTokensEstimate = downloadedTokensEstimate
        self.uploadedTokensEstimate = uploadedTokensEstimate
        self.recentRemoteTokensPerSecond = recentRemoteTokensPerSecond
        self.activeReservations = activeReservations
        self.reservationCap = reservationCap
        self.communityBoost = communityBoost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tokensSavedEstimate = try container.decodeIfPresent(Int.self, forKey: .tokensSavedEstimate) ?? 0
        downloadedTokensEstimate = try container.decodeIfPresent(Int.self, forKey: .downloadedTokensEstimate) ?? 0
        uploadedTokensEstimate = try container.decodeIfPresent(Int.self, forKey: .uploadedTokensEstimate) ?? 0
        recentRemoteTokensPerSecond = try container.decodeIfPresent(Double.self, forKey: .recentRemoteTokensPerSecond) ?? 0
        activeReservations = try container.decodeIfPresent(Int.self, forKey: .activeReservations) ?? 0
        reservationCap = try container.decodeIfPresent(Int.self, forKey: .reservationCap) ?? 0
        communityBoost = try container.decode(CommunityBoostSummary.self, forKey: .communityBoost)
    }
}

struct CommunityBoostSummary: Decodable {
    let level: Int
    let label: String
    let metricLabel: String?
    let primaryTrait: String?
    let traits: [String]
    let detail: String

    private enum CodingKeys: String, CodingKey {
        case level
        case label
        case metricLabel = "metric_label"
        case primaryTrait = "primary_trait"
        case traits
        case detail
    }

    var metricRowLabel: String {
        guard let metricLabel, !metricLabel.isEmpty else { return "Community Boost" }
        return metricLabel
    }

    var displayValue: String {
        if metricRowLabel != "Community Boost" {
            return label
        }
        return "\(level)/5 \(label)"
    }
}

struct SwarmCreateRequest: Encodable {
    let name: String
    let memberName: String
    let mode: String

    private enum CodingKeys: String, CodingKey {
        case name
        case memberName = "member_name"
        case mode
    }
}

struct SwarmInviteRequest: Encodable {
    let swarmID: String

    private enum CodingKeys: String, CodingKey {
        case swarmID = "swarm_id"
    }
}

struct SwarmJoinRequest: Encodable {
    let swarmID: String
    let inviteToken: String
    let memberName: String
    let mode: String

    private enum CodingKeys: String, CodingKey {
        case swarmID = "swarm_id"
        case inviteToken = "invite_token"
        case memberName = "member_name"
        case mode
    }
}

struct PublishShareRequest: Encodable {
    let slotsTotal: Int
    let modelIDs: [String]?
    let maintenanceState: String?

    init(slotsTotal: Int, modelIDs: [String]?, maintenanceState: String? = nil) {
        self.slotsTotal = slotsTotal
        self.modelIDs = modelIDs
        self.maintenanceState = maintenanceState
    }

    private enum CodingKeys: String, CodingKey {
        case slotsTotal = "slots_total"
        case modelIDs = "model_ids"
        case maintenanceState = "maintenance_state"
    }
}

struct EmptyBridgeRequest: Encodable {}

struct IdentityUpdateRequest: Encodable {
    let memberName: String

    private enum CodingKeys: String, CodingKey {
        case memberName = "member_name"
    }
}

struct SwarmCreateResponse: Decodable {
    let swarm: SwarmOption
    let invite: SwarmInvite
    let runtime: BridgeRuntime
}

struct SwarmJoinResponse: Decodable {
    let swarm: SwarmOption
    let runtime: BridgeRuntime
}

struct InviteResponse: Decodable {
    let invite: SwarmInvite
}

struct SwarmInvite: Decodable {
    let inviteToken: String
    let swarmID: String?
    let swarmName: String?
    let expiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case inviteToken = "invite_token"
        case swarmID = "swarm_id"
        case swarmName = "swarm_name"
        case expiresAt = "expires_at"
    }
}

struct ShareMutationResponse: Decodable {
    let status: String
}

struct BridgeErrorEnvelope: Decodable {
    let error: BridgeErrorMessage
}

struct BridgeErrorMessage: Decodable {
    let message: String
}

struct BridgeRequestError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct ProviderSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let ownerMemberID: String?
    let ownerMemberName: String?
    let status: String
    let maintenanceState: String?
    let activeSessions: Int
    let activeModel: String?
    let slots: Slots
    let hardware: HardwareProfileSummary?
    let clientBuild: ClientBuildSummary?
    let models: [ModelSummary]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerMemberID = "owner_member_id"
        case ownerMemberName = "owner_member_name"
        case status
        case maintenanceState = "maintenance_state"
        case activeSessions = "active_sessions"
        case activeModel = "active_model"
        case slots
        case hardware
        case clientBuild = "client_build"
        case models
    }

    func withOwnerMemberName(_ memberName: String, providerName: String? = nil) -> ProviderSummary {
        ProviderSummary(
            id: id,
            name: providerName ?? name,
            ownerMemberID: ownerMemberID,
            ownerMemberName: memberName,
            status: status,
            maintenanceState: maintenanceState,
            activeSessions: activeSessions,
            activeModel: activeModel,
            slots: slots,
            hardware: hardware,
            clientBuild: clientBuild,
            models: models
        )
    }
}

struct ClientBuildSummary: Decodable, Equatable {
    let product: String?
    let version: String?
    let buildNumber: String?
    let buildTimestamp: String?
    let channel: String?

    private enum CodingKeys: String, CodingKey {
        case product
        case version
        case buildNumber = "build_number"
        case buildTimestamp = "build_timestamp"
        case channel
    }
}

struct HardwareProfileSummary: Decodable, Equatable {
    let cpuBrand: String?
    let memoryGB: Int?

    private enum CodingKeys: String, CodingKey {
        case cpuBrand = "cpu_brand"
        case memoryGB = "memory_gb"
    }

    var displayLabel: String {
        var parts: [String] = []
        if let cpuBrand, !cpuBrand.isEmpty {
            parts.append(cpuBrand)
        }
        if let memoryGB, memoryGB > 0 {
            parts.append("\(memoryGB)GB")
        }
        return parts.isEmpty ? "Hardware unknown" : parts.joined(separator: " / ")
    }
}

struct SwarmMemberCapabilitySummary: Decodable, Identifiable {
    let providerID: String
    let providerName: String
    let status: String
    let maintenanceState: String?
    let activeSessions: Int
    let activeModel: String?
    let slots: Slots
    let modelCount: Int
    let bestModel: String?
    let recentUploadedTokensPerSecond: Double?
    let hardware: HardwareProfileSummary?
    let clientBuild: ClientBuildSummary?
    let models: [ModelSummary]

    var id: String { providerID }

    private enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case status
        case maintenanceState = "maintenance_state"
        case activeSessions = "active_sessions"
        case activeModel = "active_model"
        case slots
        case modelCount = "model_count"
        case bestModel = "best_model"
        case recentUploadedTokensPerSecond = "recent_uploaded_tokens_per_second"
        case hardware
        case clientBuild = "client_build"
        case models
    }

    func withProviderName(_ name: String) -> SwarmMemberCapabilitySummary {
        SwarmMemberCapabilitySummary(
            providerID: providerID,
            providerName: name,
            status: status,
            maintenanceState: maintenanceState,
            activeSessions: activeSessions,
            activeModel: activeModel,
            slots: slots,
            modelCount: modelCount,
            bestModel: bestModel,
            recentUploadedTokensPerSecond: recentUploadedTokensPerSecond,
            hardware: hardware,
            clientBuild: clientBuild,
            models: models
        )
    }
}

struct SwarmMemberSummary: Decodable, Identifiable {
    let memberID: String
    let memberName: String
    let mode: String
    let swarmID: String
    let status: String
    let maintenanceState: String?
    let lastSeenAt: String?
    let providerCount: Int
    let activeJobsServing: Int
    let activeJobsConsuming: Int
    let activeModel: String?
    let recentUploadedTokensPerSecond: Double?
    let totalModelsAvailable: Int
    let bestModel: String?
    let hardware: HardwareProfileSummary?
    let clientBuild: ClientBuildSummary?
    let capabilities: [SwarmMemberCapabilitySummary]

    var id: String { memberID }

    private enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case memberName = "member_name"
        case mode
        case swarmID = "swarm_id"
        case status
        case maintenanceState = "maintenance_state"
        case lastSeenAt = "last_seen_at"
        case providerCount = "provider_total"
        case activeJobsServing = "active_jobs_serving"
        case activeJobsConsuming = "active_jobs_consuming"
        case activeModel = "active_model"
        case recentUploadedTokensPerSecond = "recent_uploaded_tokens_per_second"
        case totalModelsAvailable = "total_models_available"
        case bestModel = "best_model"
        case hardware
        case clientBuild = "client_build"
        case capabilities
    }

    var statusTitle: String {
        if activeJobsServing > 0 {
            let model = activeModel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? capabilities.first(where: { $0.activeSessions > 0 })?.activeModel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? capabilities.first(where: { $0.activeSessions > 0 })?.bestModel
                ?? bestModel
            let rate = formatMemberTokenRate(memberServingTokensPerSecond)
            let detail = [model, rate].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }.joined(separator: ", ")
            if !detail.isEmpty {
                return activeJobsConsuming > 0 ? "Serving + Using (\(detail))" : "Serving (\(detail))"
            }
            return activeJobsConsuming > 0 ? "Serving + Using" : "Serving"
        }
        switch maintenanceState?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? status {
        case "serving_and_using":
            return "Serving + Using"
        case "serving":
            return "Serving"
        case "using":
            return "Using"
        case "installing_model":
            return "Installing Model"
        case "importing_model":
            return "Importing Model"
        case "updating_app":
            return "Updating"
        case "available":
            return "Available"
        default:
            return "Online"
        }
    }

    var hardwareLabel: String {
        hardware?.displayLabel ?? "Hardware unknown"
    }

    private var memberServingTokensPerSecond: Double {
        if let recentUploadedTokensPerSecond, recentUploadedTokensPerSecond > 0 {
            return recentUploadedTokensPerSecond
        }
        return capabilities
            .filter { $0.activeSessions > 0 }
            .reduce(0) { $0 + max(0, $1.recentUploadedTokensPerSecond ?? 0) }
    }

    var isActiveInSwarm: Bool {
        activeJobsServing + activeJobsConsuming > 0
    }

    var isAvailableInSwarm: Bool {
        providerCount > 0 || !capabilities.isEmpty
    }

    func withMemberName(_ name: String, providerID: String) -> SwarmMemberSummary {
        SwarmMemberSummary(
            memberID: memberID,
            memberName: name,
            mode: mode,
            swarmID: swarmID,
            status: status,
            maintenanceState: maintenanceState,
            lastSeenAt: lastSeenAt,
            providerCount: providerCount,
            activeJobsServing: activeJobsServing,
            activeJobsConsuming: activeJobsConsuming,
            activeModel: activeModel,
            recentUploadedTokensPerSecond: recentUploadedTokensPerSecond,
            totalModelsAvailable: totalModelsAvailable,
            bestModel: bestModel,
            hardware: hardware,
            clientBuild: clientBuild,
            capabilities: capabilities.map { capability in
                capability.providerID == providerID ? capability.withProviderName(name) : capability
            }
        )
    }
}

private func formatMemberTokenRate(_ tokensPerSecond: Double) -> String? {
    guard tokensPerSecond.isFinite else { return nil }
    let normalized = max(0, tokensPerSecond)
    guard normalized >= 0.1 else { return nil }

    if normalized >= 1_000 {
        let value = String(format: "%.1f", normalized / 1_000).replacingOccurrences(of: ".0", with: "")
        return "\(value)K tokens/s"
    }
    if normalized >= 10 {
        return "\(Int(normalized.rounded())) tokens/s"
    }
    let value = String(format: "%.1f", normalized).replacingOccurrences(of: ".0", with: "")
    return "\(value) tokens/s"
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct ModelSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let slotsFree: Int
    let slotsTotal: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case slotsFree = "slots_free"
        case slotsTotal = "slots_total"
    }
}

struct Slots: Decodable {
    let free: Int
    let total: Int
}

struct BridgePreflightRequest: Encodable {
    let model: String
    let maxProviders: Int
    let routeScope: String?

    private enum CodingKeys: String, CodingKey {
        case model
        case maxProviders = "max_providers"
        case routeScope = "route_scope"
    }
}

struct BridgePreflightResponse: Decodable {
    let available: Bool
    let resolvedModel: String
    let routeScope: String?
    let availableModels: [ModelSummary]

    private enum CodingKeys: String, CodingKey {
        case available
        case resolvedModel = "resolved_model"
        case routeScope = "route_scope"
        case availableModels = "available_models"
    }
}

struct SelfTestChatRequest: Encodable {
    let model: String
    let stream: Bool
    let routeScope: String
    let messages: [ChatMessage]

    private enum CodingKeys: String, CodingKey {
        case model
        case stream
        case routeScope = "route_scope"
        case messages
    }
}

struct ChatMessage: Encodable {
    let role: String
    let content: String
}

struct SetupAssistantState {
    let stageTitle: String
    let etaLabel: String
    let steps: [SetupAssistantStep]

    init(
        mode: AppMode,
        snapshot: BridgeStatusSnapshot,
        localShare: LocalShareSnapshot,
        runtimeState: LocalRuntimeState,
        selfTestState: SelfTestState,
        starterModelDetail: String,
        starterModelStatus: SetupAssistantStepStatus
    ) {
        var nextStage = "Checking your Mac"
        var eta = "< 10 sec"
        var steps: [SetupAssistantStep] = []

        let runtimeReady = runtimeState.status == "ready" && snapshot.bridge.status == "ready"
        steps.append(
            SetupAssistantStep(
                title: "Local runtime",
                detail: runtimeReady ? "Coordinator and bridge are healthy." : runtimeState.detail,
                status: runtimeReady ? .done : .inProgress
            )
        )
        if !runtimeReady {
            nextStage = "Starting local services"
            self.stageTitle = nextStage
            self.etaLabel = eta
            self.steps = steps
            return
        }

        let ollamaReady = runtimeState.ollamaReady
        steps.append(
            SetupAssistantStep(
                title: "Local model runtime",
                detail: runtimeState.ollamaDetail,
                status: ollamaReady ? .done : .blocked
            )
        )
        if !ollamaReady {
            nextStage = "Preparing local model runtime"
            eta = "Depends on Ollama install"
            self.stageTitle = nextStage
            self.etaLabel = eta
            self.steps = steps
            return
        }

        let hasSwarm = !snapshot.runtime.activeSwarmID.isEmpty
        steps.append(
            SetupAssistantStep(
                title: "Active swarm",
                detail: hasSwarm ? (snapshot.bridge.activeSwarmName ?? "Swarm selected.") : "Create or join a swarm so OnlyMacs knows where to route requests.",
                status: hasSwarm ? .done : .pending
            )
        )
        if !hasSwarm {
            nextStage = "Choosing a swarm"
            self.stageTitle = nextStage
            self.etaLabel = eta
            self.steps = steps
            return
        }

        steps.append(
            SetupAssistantStep(
                title: "Models",
                detail: starterModelDetail,
                status: starterModelStatus
            )
        )
        if starterModelStatus == .blocked {
            nextStage = "Choosing models"
            eta = "Depends on your picks"
            self.stageTitle = nextStage
            self.etaLabel = eta
            self.steps = steps
            return
        }
        if starterModelStatus == .inProgress || starterModelStatus == .pending {
            nextStage = "Downloading models"
            eta = "Depends on download size"
            self.stageTitle = nextStage
            self.etaLabel = eta
            self.steps = steps
            return
        }

        if mode.allowsShare {
            let shareStatus: SetupAssistantStep
            if localShare.discoveredModels.isEmpty {
                shareStatus = SetupAssistantStep(
                    title: "Local share capacity",
                    detail: "No local models are visible yet, so this Mac cannot share out of the box.",
                    status: .blocked
                )
                eta = "Needs a local model"
                nextStage = "Waiting for a local model"
            } else if localShare.published {
                shareStatus = SetupAssistantStep(
                    title: "Sharing",
                    detail: "This Mac is published in \(localShare.activeSwarmName ?? "the active swarm").",
                    status: .done
                )
            } else {
                shareStatus = SetupAssistantStep(
                    title: "Sharing",
                    detail: "This Mac is connected and will start helping automatically as soon as OnlyMacs finishes bringing local sharing online.",
                    status: .pending
                )
                nextStage = "Connecting This Mac"
            }
            steps.append(shareStatus)
            if shareStatus.status == .blocked && !mode.allowsUse {
                self.stageTitle = nextStage
                self.etaLabel = eta
                self.steps = steps
                return
            }
        }

        if mode.allowsUse {
            let hasCapacity = snapshot.swarm.slotsTotal > 0
            steps.append(
                SetupAssistantStep(
                    title: "Request path",
                    detail: hasCapacity ? "The active swarm has visible shared slot capacity." : "Waiting for shared slot capacity in the active swarm.",
                    status: hasCapacity ? .done : .pending
                )
            )
            if !hasCapacity {
                nextStage = "Waiting for a friend or This Mac"
                eta = "Depends on swarm activity"
            }
        }

        if selfTestState.isSuccessful {
            steps.append(
                SetupAssistantStep(
                    title: "Self-test",
                    detail: selfTestState.detail,
                    status: .done
                )
            )
        }

        if steps.allSatisfy({ $0.status == .done }) {
            nextStage = "Ready"
            eta = "Ready now"
        }

        self.stageTitle = nextStage
        self.etaLabel = eta
        self.steps = steps
    }
}

struct SetupAssistantStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let status: SetupAssistantStepStatus
}

enum SetupAssistantStepStatus: Equatable {
    case done
    case inProgress
    case pending
    case blocked

    var symbolName: String {
        switch self {
        case .done:
            return "checkmark.circle.fill"
        case .inProgress:
            return "clock.fill"
        case .pending:
            return "circle.dashed"
        case .blocked:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .done:
            return .green
        case .inProgress:
            return .blue
        case .pending:
            return .secondary
        case .blocked:
            return .orange
        }
    }
}

struct InviteProgress: Identifiable {
    let id = UUID()
    let token: String
    let swarmID: String
    let swarmName: String?
    var stage: InviteProgressStage
    var detail: String
}

struct CachedInviteRecord: Codable {
    let token: String
    let swarmID: String
    let swarmName: String?
    let expiresAt: Date?

    var isUsable: Bool {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !swarmID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }
        guard let expiresAt else { return true }
        return expiresAt > Date()
    }
}

enum InviteProgressStage {
    case created
    case sent
    case joined
    case ready

    var title: String {
        switch self {
        case .created:
            return "Ready To Share"
        case .sent:
            return "Sent"
        case .joined:
            return "Joined"
        case .ready:
            return "Ready"
        }
    }
}

enum SelfTestState: Equatable {
    case idle
    case running(String)
    case passed(String)
    case failed(String)

    var detail: String {
        switch self {
        case .idle:
            return "Run Test checks whether OnlyMacs can complete a real request from the current setup."
        case let .running(message), let .passed(message), let .failed(message):
            return message
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .running:
            return .blue
        case .passed:
            return .green
        case .failed:
            return .red
        }
    }

    var buttonTitle: String {
        switch self {
        case .running:
            return "Testing…"
        default:
            return "Run Test"
        }
    }

    var isSuccessful: Bool {
        if case .passed = self {
            return true
        }
        return false
    }
}

struct DetectedTool: Identifiable {
    let id = UUID()
    let name: String
    let statusTitle: String
    let detail: String
    let color: Color
    let actionTitle: String?
    private let action: (() -> Void)?

    var canOpen: Bool {
        action != nil
    }

    @discardableResult
    func performAction() -> Bool {
        guard let action else { return false }
        action()
        return true
    }

    static func codex(launcherStatus: LauncherInstallStatus) -> DetectedTool {
        let appURL = applicationURL(
            bundleIdentifiers: [
                "com.openai.codex",
                "com.openai.chatgpt.codex",
            ],
            fallbackPaths: [
                "/Applications/Codex.app",
                "/Applications/OpenAI Codex.app",
            ]
        )
        let commandVisible = commandExists("codex")
        if commandVisible || appURL != nil {
            if !launcherStatus.installed {
                return DetectedTool(
                    name: "Codex",
                    statusTitle: "Integration Needed",
                    detail: "Codex is installed. Install the Codex integration from Tools if the OnlyMacs skill is not available there yet.",
                    color: .orange,
                    actionTitle: appURL != nil ? "Open Codex" : nil,
                    action: appURL.map { url in
                        { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in } }
                    }
                )
            }
            let detail: String
            if commandVisible {
                detail = "Codex is ready. OnlyMacs can use the app, the shared skill in ~/.agents/skills/onlymacs/SKILL.md, and the shell launcher in ~/.local/bin/onlymacs-shell."
            } else {
                detail = "Codex is installed. The shared skill and shell launcher are on disk; if one already-open Codex session cannot see them, restart Codex once."
            }
            return DetectedTool(
                name: "Codex",
                statusTitle: "Detected",
                detail: detail,
                color: .green,
                actionTitle: appURL != nil ? "Open Codex" : nil,
                action: appURL.map { url in
                    { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in } }
                }
            )
        }
        return DetectedTool(
            name: "Codex",
            statusTitle: "Missing",
            detail: "Codex is not installed on this Mac yet, but OnlyMacs can still preinstall the shared skill at ~/.agents/skills/onlymacs/SKILL.md for Codex and other compatible IDEs later.",
            color: .orange,
            actionTitle: nil,
            action: nil
        )
    }

    static func claude(launcherStatus: LauncherInstallStatus) -> DetectedTool {
        let appURL = applicationURL(
            bundleIdentifiers: [
                "com.anthropic.claudefordesktop",
                "com.anthropic.claude",
            ],
            fallbackPaths: [
                "/Applications/Claude.app",
            ]
        )
        if commandExists("claude") || appURL != nil {
            if !launcherStatus.installed {
                return DetectedTool(
                    name: "Claude Code",
                    statusTitle: "Integration Needed",
                    detail: "Claude Code is installed. Install the Claude integration from Tools if the OnlyMacs slash command is not available there yet.",
                    color: .orange,
                    actionTitle: appURL != nil ? "Open Claude Code" : nil,
                    action: appURL.map { url in
                        { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in } }
                    }
                )
            }
            return DetectedTool(
                name: "Claude Code",
                statusTitle: "Detected",
                detail: "Claude Code is ready. OnlyMacs can use the app, ~/.claude/skills/onlymacs/SKILL.md, and ~/.local/bin/onlymacs.",
                color: .green,
                actionTitle: appURL != nil ? "Open Claude Code" : nil,
                action: appURL.map { url in
                    { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in } }
                }
            )
        }
        return DetectedTool(
            name: "Claude Code",
            statusTitle: "Missing",
            detail: "Claude Code is not installed on this Mac yet, but OnlyMacs can still preinstall the skill at ~/.claude/skills/onlymacs/SKILL.md for later.",
            color: .orange,
            actionTitle: nil,
            action: nil
        )
    }

    private static func applicationURL(bundleIdentifiers: [String], fallbackPaths: [String]) -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        for path in fallbackPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func commandExists(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
