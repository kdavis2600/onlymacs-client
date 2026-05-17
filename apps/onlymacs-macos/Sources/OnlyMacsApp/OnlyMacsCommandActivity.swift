import Foundation

struct OnlyMacsCommandActivity: Codable, Equatable {
    let recordedAt: Date
    let wrapperName: String
    let toolName: String
    let workspaceID: String
    let threadID: String
    let commandLabel: String
    let interpretedAs: String?
    let routeScope: String?
    let model: String?
    let outcome: String
    let detail: String?
    let sessionID: String?
    let sessionStatus: String?

    enum CodingKeys: String, CodingKey {
        case recordedAt = "recorded_at"
        case wrapperName = "wrapper_name"
        case toolName = "tool_name"
        case workspaceID = "workspace_id"
        case threadID = "thread_id"
        case commandLabel = "command_label"
        case interpretedAs = "interpreted_as"
        case routeScope = "route_scope"
        case model
        case outcome
        case detail
        case sessionID = "session_id"
        case sessionStatus = "session_status"
    }

    var displayTitle: String {
        let interpreted = interpretedAs?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return interpreted.isEmpty ? commandLabel : interpreted
    }

    func isRecentInProgress(relativeTo now: Date = Date(), ttl: TimeInterval = 15 * 60) -> Bool {
        let normalizedOutcome = outcome.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedOutcome == "running" || normalizedOutcome == "streaming" || normalizedOutcome == "launching" else {
            return false
        }

        let age = now.timeIntervalSince(recordedAt)
        return age >= 0 && age <= ttl
    }
}

enum OnlyMacsCommandActivityStore {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func lastActivityURL() -> URL {
        OnlyMacsStatePaths.stateDirectoryURL()
            .appendingPathComponent("last-activity.json", isDirectory: false)
    }

    static func loadLatest() -> OnlyMacsCommandActivity? {
        let url = lastActivityURL()
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(OnlyMacsCommandActivity.self, from: data)
    }
}
