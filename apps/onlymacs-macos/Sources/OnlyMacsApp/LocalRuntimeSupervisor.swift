import Foundation
import OnlyMacsCore
import Darwin

struct LocalRuntimeState {
    let status: String
    let detail: String
    let logsDirectory: String
    let helperSource: String
    let ollamaStatus: OllamaDependencyStatus
    let ollamaDetail: String
    let ollamaAppPath: String?

    var ollamaReady: Bool {
        switch ollamaStatus {
        case .ready, .external:
            return true
        case .missing, .installedButUnavailable:
            return false
        }
    }

    static let bootstrapping = LocalRuntimeState(
        status: "bootstrapping",
        detail: "Starting OnlyMacs runtime.",
        logsDirectory: LocalRuntimeSupervisor.logsDirectoryURL.path,
        helperSource: "unresolved",
        ollamaStatus: .installedButUnavailable,
        ollamaDetail: "OnlyMacs has not checked the local model runtime yet.",
        ollamaAppPath: nil
    )
}

enum OllamaDependencyStatus: String, Equatable {
    case ready
    case external
    case installedButUnavailable
    case missing

    var displayName: String {
        switch self {
        case .ready:
            return "Ready"
        case .external:
            return "External"
        case .installedButUnavailable:
            return "Needs Launch"
        case .missing:
            return "Missing"
        }
    }
}

private struct OllamaDependencyState {
    let status: OllamaDependencyStatus
    let detail: String
    let appPath: String?
}

func normalizeReportedCoordinatorURL(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return nil }
    if trimmed == CoordinatorConnectionSettings.embeddedCoordinatorURL {
        return CoordinatorConnectionSettings.embeddedCoordinatorURL
    }
    return CoordinatorConnectionSettings(
        mode: .hostedRemote,
        remoteCoordinatorURL: trimmed
    ).normalizedRemoteCoordinatorURL
}

func bridgeUsesExpectedCoordinator(reportedCoordinatorURL: String?, settings: CoordinatorConnectionSettings) -> Bool {
    normalizeReportedCoordinatorURL(reportedCoordinatorURL) == normalizeReportedCoordinatorURL(settings.effectiveCoordinatorURL)
}

func shouldReplaceHealthyBridge(reportedCoordinatorURL: String?, settings: CoordinatorConnectionSettings) -> Bool {
    !bridgeUsesExpectedCoordinator(reportedCoordinatorURL: reportedCoordinatorURL, settings: settings)
}

actor LocalRuntimeSupervisor {
    private static let trackedProcessTerminateTimeout: TimeInterval = 1.0
    private static let trackedProcessKillTimeout: TimeInterval = 0.5
    private static let signalToolTimeout: TimeInterval = 1.0
    private static let signalToolKillTimeout: TimeInterval = 0.25
    private static let processExitPollIntervalNanos: UInt64 = 25_000_000

    static let logsDirectoryURL: URL = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("OnlyMacs/Logs", isDirectory: true)
    }()

    private let fileManager = FileManager.default
    private let healthSession: URLSession
    private var coordinatorProcess: Process?
    private var bridgeProcess: Process?
    private var jobWorkerProcesses: [Int: Process] = [:]
    private var jobWorkerLastLaunchFailureAt: [Int: Date] = [:]
    private var jobWorkerLastExitAt: [Int: Date] = [:]
    private var jobWorkerActiveSwarmID = ""
    private var jobWorkerAllowsTests = false
    private var currentHelperSource = "unresolved"
    private let ollamaBaseURL: URL

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1
        configuration.timeoutIntervalForResource = 1
        healthSession = URLSession(configuration: configuration)
        ollamaBaseURL = Self.defaultOllamaURL()
    }

    func ensureRunning(settings: CoordinatorConnectionSettings) async -> LocalRuntimeState {
        let coordinatorHealthy = settings.launchesEmbeddedCoordinator ? await isHealthy(url: coordinatorHealthURL) : true
        let bridgeHealthy = await isHealthy(url: bridgeHealthURL)
        let reportedCoordinatorURL = bridgeHealthy ? await currentBridgeCoordinatorURL() : nil

        if coordinatorHealthy,
           bridgeHealthy,
           !shouldReplaceHealthyBridge(reportedCoordinatorURL: reportedCoordinatorURL, settings: settings) {
            let ollamaState = await inspectOllamaDependency(autostartIfInstalled: false)
            return makeState(
                status: "ready",
                detail: detailText(for: settings, ollamaState: ollamaState),
                ollamaState: ollamaState
            )
        }

        do {
            try prepareLogsDirectory()
            if bridgeHealthy, shouldReplaceHealthyBridge(reportedCoordinatorURL: reportedCoordinatorURL, settings: settings) {
                await stopTrackedProcesses()
            }
            try await launchTrackedServicesIfNeeded(settings: settings)
            if settings.launchesEmbeddedCoordinator {
                try await waitUntilHealthy(serviceName: "coordinator", url: coordinatorHealthURL)
            }
            try await waitUntilHealthy(serviceName: "local bridge", url: bridgeHealthURL)
            let ollamaState = await inspectOllamaDependency(autostartIfInstalled: false)
            return makeState(
                status: "ready",
                detail: detailText(for: settings, ollamaState: ollamaState),
                ollamaState: ollamaState
            )
        } catch {
            await stopTrackedProcesses()
            return makeState(status: "error", detail: error.localizedDescription, ollamaState: currentOllamaState())
        }
    }

    func restart(settings: CoordinatorConnectionSettings) async -> LocalRuntimeState {
        await stopTrackedProcesses()
        return await ensureRunning(settings: settings)
    }

    func stop() async {
        await stopTrackedProcesses()
    }

    func reconcileJobWorkers(policy: OnlyMacsJobWorkerSupervisorPolicy) async -> OnlyMacsJobWorkerSupervisorState {
        let plan = onlyMacsJobWorkerPlan(policy: policy)
        cleanupExitedJobWorkerProcesses()

        guard plan.shouldRun else {
            await stopJobWorkerProcesses()
            jobWorkerActiveSwarmID = ""
            jobWorkerAllowsTests = false
            return OnlyMacsJobWorkerSupervisorState(
                status: policy.disabledByEnvironment ? .disabled : .stopped,
                desiredLanes: 0,
                runningLanes: 0,
                activeSwarmID: policy.activeSwarmID,
                allowTests: plan.allowTests,
                reason: plan.stopReason
            )
        }

        if jobWorkerActiveSwarmID != policy.activeSwarmID || jobWorkerAllowsTests != plan.allowTests {
            await stopJobWorkerProcesses()
            jobWorkerActiveSwarmID = policy.activeSwarmID
            jobWorkerAllowsTests = plan.allowTests
        }

        for lane in jobWorkerProcesses.keys.sorted() where lane > plan.desiredLanes {
            await stopJobWorkerProcess(lane: lane)
        }

        var launchError: String?
        if plan.desiredLanes > 0 {
            for lane in 1...plan.desiredLanes {
                guard jobWorkerProcesses[lane]?.isRunning != true else { continue }
                guard shouldRetryJobWorkerLaunch(lane: lane) else { continue }
                do {
                    jobWorkerProcesses[lane] = try launchJobWorkerLane(
                        lane: lane,
                        swarmID: policy.activeSwarmID,
                        allowTests: plan.allowTests
                    )
                    jobWorkerLastLaunchFailureAt[lane] = nil
                    jobWorkerLastExitAt[lane] = nil
                } catch {
                    jobWorkerLastLaunchFailureAt[lane] = Date()
                    launchError = error.localizedDescription
                }
            }
        }

        cleanupExitedJobWorkerProcesses()
        let runningLanes = jobWorkerProcesses.values.filter(\.isRunning).count
        let status: OnlyMacsJobWorkerSupervisorStatus = runningLanes == plan.desiredLanes ? .running : .degraded
        let reason = launchError ?? (status == .degraded ? "OnlyMacs is waiting before retrying one or more worker lanes." : nil)
        return OnlyMacsJobWorkerSupervisorState(
            status: status,
            desiredLanes: plan.desiredLanes,
            runningLanes: runningLanes,
            activeSwarmID: policy.activeSwarmID,
            allowTests: plan.allowTests,
            reason: reason
        )
    }

    private func launchTrackedServicesIfNeeded(settings: CoordinatorConnectionSettings) async throws {
        if settings.launchesEmbeddedCoordinator {
            if coordinatorProcess?.isRunning != true {
                coordinatorProcess = try launchService(
                    helperName: "onlymacs-coordinator",
                    environment: [
                        "ONLYMACS_COORDINATOR_ADDR": "127.0.0.1:4319",
                    ],
                    logName: "coordinator.log"
                )
            }
        } else if let coordinatorProcess, coordinatorProcess.isRunning {
            await stop(process: coordinatorProcess)
            self.coordinatorProcess = nil
        }

        if bridgeProcess?.isRunning != true {
            var bridgeEnvironment = Self.bridgeClientBuildEnvironment()
            bridgeEnvironment.merge([
                "ONLYMACS_COORDINATOR_URL": settings.effectiveCoordinatorURL,
                "ONLYMACS_BRIDGE_ADDR": "127.0.0.1:4318",
                "ONLYMACS_STATE_DIR": OnlyMacsStatePaths.stateDirectoryURL().path,
                "ONLYMACS_RUNTIME_STATE_PATH": OnlyMacsStatePaths.stateDirectoryURL()
                    .appendingPathComponent("runtime.json", isDirectory: false).path,
                "ONLYMACS_OLLAMA_URL": ProcessInfo.processInfo.environment["ONLYMACS_OLLAMA_URL"] ?? "http://127.0.0.1:11434",
                "ONLYMACS_ENABLE_CANNED_CHAT": ProcessInfo.processInfo.environment["ONLYMACS_ENABLE_CANNED_CHAT"] ?? "0",
            ]) { _, latest in latest }
            bridgeProcess = try launchService(
                helperName: "onlymacs-local-bridge",
                environment: bridgeEnvironment,
                logName: "local-bridge.log"
            )
        }
    }

    private static func bridgeClientBuildEnvironment() -> [String: String] {
        let buildInfo = BuildInfo.current
        return [
            "ONLYMACS_CLIENT_PRODUCT": "OnlyMacs",
            "ONLYMACS_CLIENT_VERSION": buildInfo.version,
            "ONLYMACS_CLIENT_BUILD_NUMBER": buildInfo.buildNumber,
            "ONLYMACS_CLIENT_BUILD_TIMESTAMP": buildInfo.buildTimestamp ?? "",
            "ONLYMACS_CLIENT_BUILD_CHANNEL": buildInfo.buildChannel ?? "",
        ]
    }

    private func currentOllamaState() -> OllamaDependencyState {
        if !usesManagedLocalOllama {
            return OllamaDependencyState(
                status: .external,
                detail: "OnlyMacs is using the configured external model runtime at \(ollamaBaseURL.absoluteString).",
                appPath: nil
            )
        }
        if let appURL = detectOllamaAppURL() {
            return OllamaDependencyState(
                status: .installedButUnavailable,
                detail: "OnlyMacs found Ollama at \(appURL.path), but it is not serving the local API yet.",
                appPath: appURL.path
            )
        }
        return OllamaDependencyState(
            status: .missing,
            detail: "OnlyMacs needs Ollama installed before this Mac can host local models or run one-click model installs.",
            appPath: nil
        )
    }

    private func inspectOllamaDependency(autostartIfInstalled: Bool) async -> OllamaDependencyState {
        if !usesManagedLocalOllama {
            return OllamaDependencyState(
                status: .external,
                detail: "OnlyMacs is using the configured external model runtime at \(ollamaBaseURL.absoluteString).",
                appPath: nil
            )
        }

        if await isHealthy(url: ollamaHealthURL) {
            return OllamaDependencyState(
                status: .ready,
                detail: "Ollama is reachable on this Mac and ready for model installs.",
                appPath: detectOllamaAppURL()?.path
            )
        }

        guard let appURL = detectOllamaAppURL() else {
            return OllamaDependencyState(
                status: .missing,
                detail: "OnlyMacs needs Ollama installed before this Mac can host local models or run one-click model installs.",
                appPath: nil
            )
        }

        if autostartIfInstalled {
            launchOllamaApp(at: appURL)
            for _ in 0..<40 {
                if await isHealthy(url: ollamaHealthURL) {
                    return OllamaDependencyState(
                        status: .ready,
                        detail: "Ollama launched and is ready for local model downloads.",
                        appPath: appURL.path
                    )
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        return OllamaDependencyState(
            status: .installedButUnavailable,
            detail: "OnlyMacs found Ollama at \(appURL.path), but the local runtime is not answering yet. Launch Ollama and wait a moment.",
            appPath: appURL.path
        )
    }

    private func detectOllamaAppURL() -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Ollama.app", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Ollama.app", isDirectory: true),
        ]

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private func launchOllamaApp(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", url.path]
        try? process.run()
    }

    private func launchService(helperName: String, environment: [String: String], logName: String) throws -> Process {
        guard let executableURL = resolveHelper(named: helperName) else {
            throw SupervisorError.helperNotFound(helperName)
        }

        let process = Process()
        process.executableURL = executableURL
        process.environment = Self.helperBaseEnvironment().merging(environment) { _, new in new }
        process.standardOutput = try logHandle(named: logName)
        process.standardError = process.standardOutput
        try process.run()
        return process
    }

    private func launchJobWorkerLane(lane: Int, swarmID: String, allowTests: Bool) throws -> Process {
        guard let scriptURL = resolveOnlyMacsLauncherScript() else {
            throw SupervisorError.jobWorkerLauncherNotFound
        }

        try prepareLogsDirectory()
        try prepareJobWorkspaceRoot()

        var arguments = [
            scriptURL.path,
            "jobs",
            "work",
            "--watch",
            "--swarm-id",
            swarmID,
            "--slots",
            "1",
            "--poll",
            "10",
            "--lease-seconds",
            "600",
            "--heartbeat-seconds",
            "20",
        ]
        if allowTests {
            arguments.append("--allow-tests")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.currentDirectoryURL = Self.jobWorkerDirectoryURL
        process.environment = Self.helperBaseEnvironment().merging(jobWorkerEnvironment(lane: lane)) { _, new in new }
        process.standardOutput = try logHandle(named: "job-worker-\(lane).log")
        process.standardError = process.standardOutput
        try process.run()
        return process
    }

    private static func helperBaseEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let exactKeys = [
            "HOME",
            "LANG",
            "LOGNAME",
            "PATH",
            "SHELL",
            "TMPDIR",
            "USER",
            "XPC_SERVICE_NAME",
        ]
        var environment: [String: String] = [:]
        for key in exactKeys {
            if let value = source[key], !value.isEmpty {
                environment[key] = value
            }
        }
        for (key, value) in source where key.hasPrefix("LC_") && !value.isEmpty {
            environment[key] = value
        }
        if environment["PATH"] == nil {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        return environment
    }

    private func resolveHelper(named helperName: String) -> URL? {
        let candidates = helperCandidates(named: helperName)
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            currentHelperSource = helperSourceDescription(for: candidate)
            return candidate
        }
        return nil
    }

    private func helperCandidates(named helperName: String) -> [URL] {
        var candidates: [URL] = []

        let bundledHelper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent(helperName, isDirectory: false)
        candidates.append(bundledHelper)

        if let resourceHelper = Bundle.main.url(forResource: helperName, withExtension: nil, subdirectory: "Helpers") {
            candidates.append(resourceHelper)
        }

        if let executableURL = Bundle.main.executableURL {
            var cursor = executableURL.deletingLastPathComponent()
            for _ in 0..<9 {
                candidates.append(cursor.appendingPathComponent(".tmp/bin", isDirectory: true).appendingPathComponent(helperName, isDirectory: false))
                candidates.append(cursor.appendingPathComponent("dist/OnlyMacs.app/Contents/Helpers", isDirectory: true).appendingPathComponent(helperName, isDirectory: false))
                let next = cursor.deletingLastPathComponent()
                if next.path == cursor.path {
                    break
                }
                cursor = next
            }
        }

        return candidates
    }

    private func resolveOnlyMacsLauncherScript() -> URL? {
        let candidates = onlyMacsLauncherScriptCandidates()
        return candidates.first(where: { fileManager.isReadableFile(atPath: $0.path) })
    }

    private func onlyMacsLauncherScriptCandidates() -> [URL] {
        var candidates: [URL] = []

        let bundledScript = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/Integrations/onlymacs", isDirectory: true)
            .appendingPathComponent("onlymacs.sh", isDirectory: false)
        candidates.append(bundledScript)

        if let resourceScript = Bundle.main.url(forResource: "onlymacs", withExtension: "sh", subdirectory: "Integrations/onlymacs") {
            candidates.append(resourceScript)
        }

        if let executableURL = Bundle.main.executableURL {
            var cursor = executableURL.deletingLastPathComponent()
            for _ in 0..<10 {
                candidates.append(cursor.appendingPathComponent("integrations/onlymacs", isDirectory: true).appendingPathComponent("onlymacs.sh", isDirectory: false))
                candidates.append(cursor.appendingPathComponent("dist/OnlyMacs.app/Contents/Resources/Integrations/onlymacs", isDirectory: true).appendingPathComponent("onlymacs.sh", isDirectory: false))
                let next = cursor.deletingLastPathComponent()
                if next.path == cursor.path {
                    break
                }
                cursor = next
            }
        }

        return candidates
    }

    private func helperSourceDescription(for url: URL) -> String {
        if url.path.contains("/Contents/Helpers/") {
            return "bundled helper"
        }
        if url.path.contains("/.tmp/bin/") {
            return "repo helper build"
        }
        return url.deletingLastPathComponent().path
    }

    private func logHandle(named fileName: String) throws -> FileHandle {
        try prepareLogsDirectory()
        let logURL = Self.logsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: Data())
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.truncate(atOffset: 0)
        try handle.seekToEnd()
        return handle
    }

    private func prepareLogsDirectory() throws {
        try fileManager.createDirectory(at: Self.logsDirectoryURL, withIntermediateDirectories: true)
    }

    private func prepareJobWorkspaceRoot() throws {
        try fileManager.createDirectory(at: Self.jobWorkerDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: Self.jobWorkspaceRootURL, withIntermediateDirectories: true)
    }

    private func currentBridgeCoordinatorURL() async -> String? {
        do {
            let (data, response) = try await healthSession.data(from: bridgeStatusURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            guard
                let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let bridge = payload["bridge"] as? [String: Any],
                let coordinatorURL = bridge["coordinator_url"] as? String
            else {
                return nil
            }
            return coordinatorURL
        } catch {
            return nil
        }
    }

    private func isHealthy(url: URL) async -> Bool {
        do {
            let (_, response) = try await healthSession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    private func waitUntilHealthy(serviceName: String, url: URL) async throws {
        for _ in 0..<40 {
            if await isHealthy(url: url) {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw SupervisorError.startTimeout(serviceName)
    }

    private func stopTrackedProcesses() async {
        await stopJobWorkerProcesses()
        await stop(process: bridgeProcess)
        await stop(process: coordinatorProcess)
        await terminateLingeringHelper(named: "onlymacs-local-bridge")
        await terminateLingeringHelper(named: "onlymacs-coordinator")
        bridgeProcess = nil
        coordinatorProcess = nil
        jobWorkerActiveSwarmID = ""
        jobWorkerAllowsTests = false
    }

    private func stopJobWorkerProcesses() async {
        for lane in jobWorkerProcesses.keys.sorted() {
            await stopJobWorkerProcess(lane: lane)
        }
    }

    private func stopJobWorkerProcess(lane: Int) async {
        await stop(process: jobWorkerProcesses[lane])
        jobWorkerProcesses[lane] = nil
        jobWorkerLastExitAt[lane] = nil
    }

    private func cleanupExitedJobWorkerProcesses() {
        for (lane, process) in jobWorkerProcesses where process.isRunning != true {
            jobWorkerProcesses[lane] = nil
            jobWorkerLastExitAt[lane] = Date()
        }
    }

    private func shouldRetryJobWorkerLaunch(lane: Int) -> Bool {
        let now = Date()
        if let failedAt = jobWorkerLastLaunchFailureAt[lane],
           now.timeIntervalSince(failedAt) < 30 {
            return false
        }
        if let exitedAt = jobWorkerLastExitAt[lane],
           now.timeIntervalSince(exitedAt) < 30 {
            return false
        }
        return true
    }

    private func terminateLingeringHelper(named helperName: String) async {
        await signalMatchingProcesses(named: helperName, signal: "TERM")
        await signalKnownListener(for: helperName, signal: "TERM")
        try? await Task.sleep(nanoseconds: 200_000_000)
        await signalMatchingProcesses(named: helperName, signal: "KILL")
        await signalKnownListener(for: helperName, signal: "KILL")
    }

    private func signalMatchingProcesses(named helperName: String, signal: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-\(signal)", "-x", "-U", String(getuid()), helperName]
        await runShortLivedProcess(process, timeout: Self.signalToolTimeout)
    }

    private func signalKnownListener(for helperName: String, signal: String) async {
        guard let port = helperListenPort(named: helperName) else { return }
        for pid in await listeningPIDs(on: port) {
            signalProcess(pid: pid, signal: signal)
        }
    }

    private func helperListenPort(named helperName: String) -> Int? {
        switch helperName {
        case "onlymacs-local-bridge":
            return 4318
        case "onlymacs-coordinator":
            return 4319
        default:
            return nil
        }
    }

    private func listeningPIDs(on port: Int) async -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-ti", "tcp:\(port)", "-sTCP:LISTEN"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            guard await waitForExit(process, timeout: Self.signalToolTimeout) else {
                await forceTerminate(process, timeout: Self.signalToolKillTimeout)
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
                .split(whereSeparator: \.isNewline)
                .map { String($0) }
        } catch {
            return []
        }
    }

    private func signalProcess(pid: String, signal: String) {
        guard let processID = pid_t(pid) else { return }
        _ = kill(processID, signalNumber(named: signal))
    }

    private func stop(process: Process?) async {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            guard await waitForExit(process, timeout: Self.trackedProcessTerminateTimeout) else {
                await forceTerminate(process, timeout: Self.trackedProcessKillTimeout)
                return
            }
        }
    }

    private func runShortLivedProcess(_ process: Process, timeout: TimeInterval) async {
        do {
            try process.run()
            guard await waitForExit(process, timeout: timeout) else {
                await forceTerminate(process, timeout: Self.signalToolKillTimeout)
                return
            }
        } catch {
            return
        }
    }

    private func forceTerminate(_ process: Process, timeout: TimeInterval) async {
        guard process.isRunning else { return }
        _ = kill(process.processIdentifier, SIGKILL)
        _ = await waitForExit(process, timeout: timeout)
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                return false
            }
            try? await Task.sleep(nanoseconds: Self.processExitPollIntervalNanos)
        }
        return true
    }

    private func signalNumber(named signal: String) -> Int32 {
        switch signal {
        case "KILL":
            return SIGKILL
        default:
            return SIGTERM
        }
    }

    private func makeState(status: String, detail: String, ollamaState: OllamaDependencyState) -> LocalRuntimeState {
        LocalRuntimeState(
            status: status,
            detail: detail,
            logsDirectory: Self.logsDirectoryURL.path,
            helperSource: currentHelperSource,
            ollamaStatus: ollamaState.status,
            ollamaDetail: ollamaState.detail,
            ollamaAppPath: ollamaState.appPath
        )
    }

    private func detailText(for settings: CoordinatorConnectionSettings, ollamaState: OllamaDependencyState) -> String {
        let base: String = switch settings.mode {
        case .embeddedLocal:
            "Local coordinator and bridge are supervised by the app."
        case .hostedRemote:
            "Local bridge is supervised by the app and connected to \(settings.effectiveCoordinatorURL)."
        }

        if ollamaState.status == .ready || ollamaState.status == .external {
            return base
        }
        return "\(base) \(ollamaState.detail)"
    }

    private var coordinatorHealthURL: URL {
        URL(string: "http://127.0.0.1:4319/health")!
    }

    private var bridgeHealthURL: URL {
        URL(string: "http://127.0.0.1:4318/health")!
    }

    private var bridgeStatusURL: URL {
        URL(string: "http://127.0.0.1:4318/admin/v1/status")!
    }

    private var ollamaHealthURL: URL {
        ollamaBaseURL.appending(path: "/api/version")
    }

    private var usesManagedLocalOllama: Bool {
        guard let host = ollamaBaseURL.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }

    private var jobWorkerEnvironmentPath: String {
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        if currentPath.isEmpty {
            return fallbackPath
        }
        return "\(fallbackPath):\(currentPath)"
    }

    private func jobWorkerEnvironment(lane: Int) -> [String: String] {
        Self.bridgeClientBuildEnvironment().merging([
            "ONLYMACS_BRIDGE_URL": "http://127.0.0.1:4318",
            "ONLYMACS_JOB_WORKER_LANE": "\(lane)",
            "ONLYMACS_JOB_WORKER_REPAIR_ON_FAILURE": "1",
            "ONLYMACS_JOB_WORKSPACE_ROOT": Self.jobWorkspaceRootURL.path,
            "PATH": jobWorkerEnvironmentPath,
        ]) { _, latest in latest }
    }

    private static func defaultOllamaURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["ONLYMACS_OLLAMA_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           let url = URL(string: override)
        {
            return url
        }
        return URL(string: "http://127.0.0.1:11434")!
    }

    private static var jobWorkerDirectoryURL: URL {
        logsDirectoryURL.deletingLastPathComponent().appendingPathComponent("JobWorkers", isDirectory: true)
    }

    private static var jobWorkspaceRootURL: URL {
        logsDirectoryURL.deletingLastPathComponent().appendingPathComponent("JobWorkspaces", isDirectory: true)
    }
}

private enum SupervisorError: LocalizedError {
    case helperNotFound(String)
    case jobWorkerLauncherNotFound
    case startTimeout(String)

    var errorDescription: String? {
        switch self {
        case let .helperNotFound(helperName):
            return "Missing helper executable: \(helperName). Build helper binaries or launch the bundled app."
        case .jobWorkerLauncherNotFound:
            return "Missing OnlyMacs launcher script for job workers."
        case let .startTimeout(serviceName):
            return "Timed out waiting for \(serviceName) to become healthy."
        }
    }
}
