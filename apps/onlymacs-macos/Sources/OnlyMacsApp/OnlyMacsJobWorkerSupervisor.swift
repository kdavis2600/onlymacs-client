import Foundation

enum OnlyMacsJobWorkerSupervisorStatus: String, Equatable {
    case disabled
    case stopped
    case running
    case degraded
}

struct OnlyMacsJobWorkerSupervisorPolicy: Equatable {
    let disabledByEnvironment: Bool
    let runtimeReady: Bool
    let bridgeReady: Bool
    let modeAllowsShare: Bool
    let published: Bool
    let activeSwarmID: String
    let activeSwarmIsPublic: Bool
    let discoveredModelCount: Int
    let unifiedMemoryGB: Int
    let publishedSlotCount: Int
    let activeLocalSessions: Int
    let runtimeBusy: Bool
    let installingModels: Bool
    let updateReadyOrInstalling: Bool
    let maxLanesOverride: Int?

    init(
        disabledByEnvironment: Bool = false,
        runtimeReady: Bool = true,
        bridgeReady: Bool = true,
        modeAllowsShare: Bool = true,
        published: Bool = true,
        activeSwarmID: String,
        activeSwarmIsPublic: Bool = false,
        discoveredModelCount: Int = 1,
        unifiedMemoryGB: Int = 64,
        publishedSlotCount: Int = 1,
        activeLocalSessions: Int = 0,
        runtimeBusy: Bool = false,
        installingModels: Bool = false,
        updateReadyOrInstalling: Bool = false,
        maxLanesOverride: Int? = nil
    ) {
        self.disabledByEnvironment = disabledByEnvironment
        self.runtimeReady = runtimeReady
        self.bridgeReady = bridgeReady
        self.modeAllowsShare = modeAllowsShare
        self.published = published
        self.activeSwarmID = activeSwarmID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activeSwarmIsPublic = activeSwarmIsPublic
        self.discoveredModelCount = discoveredModelCount
        self.unifiedMemoryGB = unifiedMemoryGB
        self.publishedSlotCount = publishedSlotCount
        self.activeLocalSessions = activeLocalSessions
        self.runtimeBusy = runtimeBusy
        self.installingModels = installingModels
        self.updateReadyOrInstalling = updateReadyOrInstalling
        self.maxLanesOverride = maxLanesOverride
    }
}

struct OnlyMacsJobWorkerPlan: Equatable {
    let desiredLanes: Int
    let allowTests: Bool
    let stopReason: String?

    var shouldRun: Bool {
        desiredLanes > 0
    }
}

struct OnlyMacsJobWorkerSupervisorState: Equatable {
    let status: OnlyMacsJobWorkerSupervisorStatus
    let desiredLanes: Int
    let runningLanes: Int
    let activeSwarmID: String
    let allowTests: Bool
    let reason: String?

    static let bootstrapping = OnlyMacsJobWorkerSupervisorState(
        status: .stopped,
        desiredLanes: 0,
        runningLanes: 0,
        activeSwarmID: "",
        allowTests: false,
        reason: "Waiting for the bridge to finish starting."
    )

    var displayTitle: String {
        switch status {
        case .running:
            return "\(runningLanes)/\(desiredLanes) worker lanes"
        case .degraded:
            return runningLanes > 0 ? "\(runningLanes)/\(desiredLanes) worker lanes, degraded" : "Worker degraded"
        case .disabled:
            return "Workers disabled"
        case .stopped:
            return "Workers stopped"
        }
    }

    var displayDetail: String {
        let swarmSuffix = activeSwarmID.isEmpty ? "" : " Swarm: \(activeSwarmID)."
        switch status {
        case .running:
            return "OnlyMacs is watching the job board for claimable tickets.\(swarmSuffix)"
        case .degraded:
            return "\(reason ?? "OnlyMacs could not keep all job worker lanes running.").\(swarmSuffix)"
        case .disabled, .stopped:
            return reason ?? "OnlyMacs is not running background job workers right now."
        }
    }
}

func onlyMacsEnvironmentFlagIsEnabled(_ value: String?) -> Bool {
    switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on":
        return true
    default:
        return false
    }
}

func parseOnlyMacsJobWorkerMaxLanes(_ value: String?) -> Int? {
    guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return nil
    }
    guard let parsed = Int(raw) else {
        return nil
    }
    return min(max(parsed, 0), 8)
}

func defaultOnlyMacsJobWorkerLaneCeiling(unifiedMemoryGB: Int) -> Int {
    if unifiedMemoryGB >= 256 {
        return 4
    }
    if unifiedMemoryGB >= 128 {
        return 2
    }
    if unifiedMemoryGB >= 32 {
        return 1
    }
    return 0
}

func recommendedOnlyMacsShareSlotCount(unifiedMemoryGB: Int, currentSlots: Int) -> Int {
    max(max(currentSlots, 1), defaultOnlyMacsJobWorkerLaneCeiling(unifiedMemoryGB: unifiedMemoryGB))
}

func onlyMacsJobWorkerPlan(policy: OnlyMacsJobWorkerSupervisorPolicy) -> OnlyMacsJobWorkerPlan {
    let allowTests = !policy.activeSwarmIsPublic

    if policy.disabledByEnvironment {
        return OnlyMacsJobWorkerPlan(
            desiredLanes: 0,
            allowTests: allowTests,
            stopReason: "Automatic job workers are disabled by ONLYMACS_DISABLE_JOB_WORKERS."
        )
    }
    if !policy.runtimeReady {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "Waiting for the local runtime to be ready.")
    }
    if !policy.bridgeReady {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "Waiting for the bridge to be ready.")
    }
    if !policy.modeAllowsShare {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "This Mac is not in a sharing mode.")
    }
    if policy.runtimeBusy {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "The local runtime is being restarted.")
    }
    if policy.installingModels {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "OnlyMacs is installing local models.")
    }
    if policy.updateReadyOrInstalling {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "OnlyMacs is pausing workers while an app update is ready or installing.")
    }
    if !policy.published {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "Waiting for this Mac to publish into the active swarm.")
    }
    if policy.activeSwarmID.isEmpty {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "Waiting for an active swarm.")
    }
    if policy.discoveredModelCount <= 0 {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "Waiting for at least one local model.")
    }

    let memoryCeiling = defaultOnlyMacsJobWorkerLaneCeiling(unifiedMemoryGB: policy.unifiedMemoryGB)
    if memoryCeiling <= 0 {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "Unified memory is below the 32 GB worker floor.")
    }

    let publishedSlotCeiling = max(policy.publishedSlotCount, 1)
    let maxLanes = policy.maxLanesOverride ?? 8
    let configuredCeiling = min(memoryCeiling, publishedSlotCeiling, maxLanes)
    if configuredCeiling <= 0 {
        return OnlyMacsJobWorkerPlan(desiredLanes: 0, allowTests: allowTests, stopReason: "The configured job worker lane limit is 0.")
    }

    let liveShareLoad = max(policy.activeLocalSessions, 0)
    let availableLanes = max(configuredCeiling - liveShareLoad, 0)
    if availableLanes <= 0 {
        return OnlyMacsJobWorkerPlan(
            desiredLanes: 0,
            allowTests: allowTests,
            stopReason: "Live share sessions are using this Mac's worker capacity."
        )
    }

    return OnlyMacsJobWorkerPlan(desiredLanes: availableLanes, allowTests: allowTests, stopReason: nil)
}
