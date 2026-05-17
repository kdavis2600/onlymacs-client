import AppKit
import Foundation

struct SupportToolSnapshot {
    let name: String
    let status: String
    let detail: String
}

struct SupportBundleInput {
    let generatedAt: Date
    let buildVersion: String
    let buildNumber: String
    let buildTimestamp: String?
    let buildChannel: String?
    let hostName: String
    let selectedMode: String
    let coordinatorMode: String
    let coordinatorTarget: String
    let lastError: String?
    let recoveryTitle: String?
    let recoveryDetail: String?
    let recoveryActions: [String]
    let inviteExpiryDetail: String?
    let runtimeStatus: String
    let runtimeDetail: String
    let helperSource: String
    let logsDirectory: String
    let jobWorkerStatus: String
    let jobWorkerDesiredLanes: Int
    let jobWorkerRunningLanes: Int
    let jobWorkerDetail: String
    let launcherStatus: LauncherInstallStatus
    let tools: [SupportToolSnapshot]
    let latestOnlyMacsActivity: OnlyMacsCommandActivity?
    let localShareStatus: String
    let localEligibilityCode: String
    let localEligibilityTitle: String
    let localEligibilityDetail: String
    let localSharePublished: Bool
    let localShareServedSessions: Int
    let localShareFailedSessions: Int
    let localShareUploadedTokensEstimate: Int
    let localShareLastServedModel: String?
    let activeReservations: Int
    let reservationCap: Int
    let bridgeStatusJSON: String?
    let localShareJSON: String?
    let swarmSessionsJSON: String?
}

enum SupportBundleWriter {
    static let bundlesDirectoryURL: URL = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("OnlyMacs/SupportBundles", isDirectory: true)
    }()

    @discardableResult
    static func writeBundle(_ input: SupportBundleInput) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: bundlesDirectoryURL, withIntermediateDirectories: true)

        let timestamp = fileStampString(from: input.generatedAt)
        let outputURL = bundlesDirectoryURL.appendingPathComponent("onlymacs-support-\(timestamp).json", isDirectory: false)

        let payload: [String: Any] = [
            "generated_at": iso8601String(from: input.generatedAt),
            "redaction_applied": true,
            "build": [
                "version": input.buildVersion,
                "number": input.buildNumber,
                "timestamp": input.buildTimestamp ?? "",
                "channel": input.buildChannel ?? "",
            ],
            "host_name": input.hostName,
            "selected_mode": input.selectedMode,
            "coordinator_mode": input.coordinatorMode,
            "coordinator_target": input.coordinatorTarget,
            "last_error": redactFreeform(input.lastError ?? ""),
            "recovery": [
                "title": input.recoveryTitle ?? "",
                "detail": redactFreeform(input.recoveryDetail ?? ""),
                "actions": input.recoveryActions,
            ],
            "invite": [
                "expiry_detail": input.inviteExpiryDetail ?? "",
            ],
            "runtime": [
                "status": input.runtimeStatus,
                "detail": redactFreeform(input.runtimeDetail),
                "helper_source": input.helperSource,
                "logs_directory": input.logsDirectory,
            ],
            "job_workers": [
                "status": input.jobWorkerStatus,
                "desired_lanes": input.jobWorkerDesiredLanes,
                "running_lanes": input.jobWorkerRunningLanes,
                "detail": redactFreeform(input.jobWorkerDetail),
            ],
            "launchers": [
                "installed": input.launcherStatus.installed,
                "command_on_path": input.launcherStatus.commandOnPath,
                "shim_directory": input.launcherStatus.shimDirectoryURL.path,
                "entrypoint": input.launcherStatus.entrypointURL.path,
                "detail": redactFreeform(input.launcherStatus.detail),
            ],
            "detected_tools": input.tools.map { tool in
                [
                    "name": tool.name,
                    "status": tool.status,
                    "detail": redactFreeform(tool.detail),
                ]
            },
            "launcher_activity": launcherActivityPayload(input.latestOnlyMacsActivity),
            "local_share_snapshot": [
                "status": input.localShareStatus,
                "eligibility": [
                    "code": input.localEligibilityCode,
                    "title": input.localEligibilityTitle,
                    "detail": redactFreeform(input.localEligibilityDetail),
                ],
                "published": input.localSharePublished,
                "served_sessions": input.localShareServedSessions,
                "failed_sessions": input.localShareFailedSessions,
                "uploaded_tokens_estimate": input.localShareUploadedTokensEstimate,
                "last_served_model": input.localShareLastServedModel ?? "",
            ],
            "requester_budget": [
                "active_reservations": input.activeReservations,
                "reservation_cap": input.reservationCap,
            ],
            "bridge_status_json": redactJSONText(input.bridgeStatusJSON),
            "local_share_json": redactJSONText(input.localShareJSON),
            "swarm_sessions_json": redactJSONText(input.swarmSessionsJSON),
            "log_tails": [
                "coordinator.log": redactedTailText(for: "coordinator.log", logsDirectory: input.logsDirectory),
                "local-bridge.log": redactedTailText(for: "local-bridge.log", logsDirectory: input.logsDirectory),
                "job-worker-1.log": redactedTailText(for: "job-worker-1.log", logsDirectory: input.logsDirectory),
                "job-worker-2.log": redactedTailText(for: "job-worker-2.log", logsDirectory: input.logsDirectory),
                "job-worker-3.log": redactedTailText(for: "job-worker-3.log", logsDirectory: input.logsDirectory),
                "job-worker-4.log": redactedTailText(for: "job-worker-4.log", logsDirectory: input.logsDirectory),
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    static func diagnosticSummary(_ input: SupportBundleInput) -> String {
        let toolSummary = input.tools.map { "\($0.name): \($0.status)" }.joined(separator: ", ")
        return """
        OnlyMacs Diagnostics
        Build: \(input.buildVersion) (\(input.buildNumber))\(input.buildChannel.map { " · \($0)" } ?? "")\(input.buildTimestamp.map { " · \($0)" } ?? "")
        Host: \(input.hostName)
        Mode: \(input.selectedMode)
        Coordinator: \(input.coordinatorMode) -> \(input.coordinatorTarget)
        Runtime: \(input.runtimeStatus) (\(input.helperSource))
        Job Workers: \(input.jobWorkerStatus), lanes=\(input.jobWorkerRunningLanes)/\(input.jobWorkerDesiredLanes), \(redactFreeform(input.jobWorkerDetail))
        Launchers: \(input.launcherStatus.installed ? "installed" : "missing"), path=\(input.launcherStatus.commandOnPath ? "ok" : "pending")
        Share: \(input.localShareStatus), published=\(input.localSharePublished ? "yes" : "no"), served=\(input.localShareServedSessions), failed=\(input.localShareFailedSessions), uploaded=\(input.localShareUploadedTokensEstimate)
        This Mac Eligibility: \(input.localEligibilityTitle) — \(redactFreeform(input.localEligibilityDetail))
        Swarm Budget: \(input.reservationCap > 0 ? "\(input.activeReservations)/\(input.reservationCap)" : "n/a")
        Invite: \(input.inviteExpiryDetail ?? "none")
        Latest /onlymacs: \(launcherActivitySummary(input.latestOnlyMacsActivity))
        Tools: \(toolSummary.isEmpty ? "none detected" : toolSummary)
        Recovery: \(input.recoveryTitle ?? "none")\(input.recoveryDetail.map { " — \(redactFreeform($0))" } ?? "")
        Logs: \(input.logsDirectory)
        Last Error: \(input.lastError.map(redactFreeform) ?? "none")
        Privacy: prompts, secrets, tokens, and session titles are redacted by default
        """
    }

    static func redactJSONText(_ text: String?) -> String {
        let raw = text ?? ""
        guard !raw.isEmpty else { return "" }
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return redactFreeform(raw)
        }

        let redacted = redactJSONValue(json, path: [])
        guard let encoded = try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: encoded, encoding: .utf8)
        else {
            return redactFreeform(raw)
        }
        return string
    }

    static func redactFreeform(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var redacted = text
        redacted = replacing(redacted, pattern: #"(?is)-----BEGIN [A-Z0-9 _-]*KEY-----.*?-----END [A-Z0-9 _-]*KEY-----"#, template: "[REDACTED KEY BLOCK]")
        redacted = replacing(redacted, pattern: #"(?i)(bearer\s+)[A-Za-z0-9._\-]+"#, template: "$1[REDACTED]")
        redacted = replacing(redacted, pattern: #"(?i)([?&](?:invite_token|token|api_key|access_key|password|secret|credential)=)[^&\s]+"#, template: "$1[REDACTED]")
        redacted = replacing(redacted, pattern: #"(?i)\b(invite_token|api[_-]?key|access[_-]?key|password|secret|credential|token)\b\s*[:=]\s*([^\s,;]+)"#, template: "$1=[REDACTED]")
        redacted = replacing(redacted, pattern: #"(?i)"(invite_token|api[_-]?key|access[_-]?key|password|secret|credential|token|authorization|body_base64)"\s*:\s*"[^"]*""#, template: "\"$1\":\"[REDACTED]\"")
        return redacted
    }

    private static func redactedTailText(for fileName: String, logsDirectory: String) -> String {
        let fileURL = URL(fileURLWithPath: logsDirectory, isDirectory: true).appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return redactFreeform(lines.suffix(160).joined(separator: "\n"))
    }

    private static func redactJSONValue(_ value: Any, path: [String]) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            var redacted: [String: Any] = [:]
            for (key, nestedValue) in dictionary {
                let normalizedKey = key.lowercased()
                let nextPath = path + [normalizedKey]
                if normalizedKey == "messages" {
                    redacted[key] = redactMessages(nestedValue)
                    continue
                }
                if normalizedKey == "prompt" || normalizedKey == "body_base64" || isSensitiveKey(normalizedKey) {
                    redacted[key] = "[REDACTED]"
                    continue
                }
                if normalizedKey == "title" && path.contains(where: { $0.contains("session") }) {
                    redacted[key] = "[REDACTED TITLE]"
                    continue
                }
                if normalizedKey == "content" && path.contains("messages") {
                    redacted[key] = "[REDACTED MESSAGE]"
                    continue
                }
                if let stringValue = nestedValue as? String {
                    redacted[key] = redactFreeform(stringValue)
                } else {
                    redacted[key] = redactJSONValue(nestedValue, path: nextPath)
                }
            }
            return redacted
        case let array as [Any]:
            return array.map { redactJSONValue($0, path: path + ["[]"]) }
        case let string as String:
            return redactFreeform(string)
        default:
            return value
        }
    }

    private static func redactMessages(_ value: Any) -> Any {
        guard let messages = value as? [Any] else {
            return "[REDACTED]"
        }
        let redactedMessages: [Any] = messages.map { item in
            guard let message = item as? [String: Any] else {
                return "[REDACTED MESSAGE]"
            }
            var redacted = message
            if message["content"] != nil {
                redacted["content"] = "[REDACTED MESSAGE]"
            }
            return redacted as Any
        }
        return redactedMessages
    }

    private static func launcherActivityPayload(_ activity: OnlyMacsCommandActivity?) -> [String: Any] {
        guard let activity else { return [:] }
        return [
            "recorded_at": iso8601String(from: activity.recordedAt),
            "wrapper_name": activity.wrapperName,
            "tool_name": activity.toolName,
            "workspace_id": activity.workspaceID,
            "thread_id": activity.threadID,
            "command_label": activity.commandLabel,
            "interpreted_as": activity.interpretedAs ?? "",
            "route_scope": activity.routeScope ?? "",
            "model": activity.model ?? "",
            "outcome": activity.outcome,
            "detail": redactFreeform(activity.detail ?? ""),
            "session_id": activity.sessionID ?? "",
            "session_status": activity.sessionStatus ?? "",
        ]
    }

    private static func launcherActivitySummary(_ activity: OnlyMacsCommandActivity?) -> String {
        guard let activity else { return "none" }
        var parts = [activity.displayTitle, activity.outcome]
        if let routeScope = activity.routeScope, !routeScope.isEmpty {
            parts.append(routeScope)
        }
        if let model = activity.model, !model.isEmpty {
            parts.append(model)
        }
        return redactFreeform(parts.joined(separator: " · "))
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        key.contains("token")
            || key.contains("secret")
            || key.contains("password")
            || key.contains("credential")
            || key.contains("authorization")
            || key.contains("api_key")
            || key.contains("apikey")
            || key.contains("access_key")
            || key.contains("private_key")
            || key.contains("ssh_key")
    }

    private static func replacing(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func fileStampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
