import Foundation
import UserNotifications

struct OnlyMacsNotificationSessionSnapshot: Equatable {
    let id: String
    let title: String?
    let status: String
    let resolvedModel: String
    let routeSummary: String?
    let warningMessage: String?
}

struct OnlyMacsNotificationActivitySnapshot: Equatable {
    let title: String
    let outcome: String
    let detail: String?
    let routeScope: String?
    let model: String?
}

struct OnlyMacsNotificationShareSnapshot: Equatable {
    let published: Bool
    let activeSwarmName: String?
    let activeSessions: Int
    let servedSessions: Int
}

struct OnlyMacsUserNotificationPlan: Equatable {
    let id: String
    let title: String
    let body: String
}

enum OnlyMacsNotificationPlanner {
    static func plans(
        previousSessions: [OnlyMacsNotificationSessionSnapshot],
        currentSessions: [OnlyMacsNotificationSessionSnapshot],
        previousShare: OnlyMacsNotificationShareSnapshot?,
        currentShare: OnlyMacsNotificationShareSnapshot?,
        previousActivity: OnlyMacsNotificationActivitySnapshot?,
        currentActivity: OnlyMacsNotificationActivitySnapshot?
    ) -> [OnlyMacsUserNotificationPlan] {
        var plans: [OnlyMacsUserNotificationPlan] = []

        let previousStatuses = Dictionary(uniqueKeysWithValues: previousSessions.map { ($0.id, $0.status) })
        for session in currentSessions {
            guard isTerminal(status: session.status) else { continue }
            guard previousStatuses[session.id] != session.status else { continue }
            if let plan = plan(for: session) {
                plans.append(plan)
            }
        }

        if plans.contains(where: { $0.id.hasPrefix("swarm:") }) {
            return plans
        }

        if let sharePlan = sharePlan(previous: previousShare, current: currentShare) {
            plans.append(sharePlan)
        }

        if !plans.isEmpty {
            return plans
        }

        if let activityPlan = activityPlan(previous: previousActivity, current: currentActivity) {
            plans.append(activityPlan)
        }

        return plans
    }

    private static func isTerminal(status: String) -> Bool {
        switch status {
        case "completed", "failed":
            return true
        default:
            return false
        }
    }

    private static func plan(for session: OnlyMacsNotificationSessionSnapshot) -> OnlyMacsUserNotificationPlan? {
        let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (title?.isEmpty == false ? title! : session.resolvedModel)

        switch session.status {
        case "completed":
            return OnlyMacsUserNotificationPlan(
                id: "swarm:\(session.id):completed",
                title: "OnlyMacs finished a swarm",
                body: sessionBody(label: label, model: session.resolvedModel, routeSummary: session.routeSummary)
            )
        case "failed":
            return OnlyMacsUserNotificationPlan(
                id: "swarm:\(session.id):failed",
                title: "OnlyMacs swarm needs attention",
                body: failureBody(label: label, model: session.resolvedModel, detail: session.warningMessage)
            )
        default:
            return nil
        }
    }

    private static func activityPlan(
        previous: OnlyMacsNotificationActivitySnapshot?,
        current: OnlyMacsNotificationActivitySnapshot?
    ) -> OnlyMacsUserNotificationPlan? {
        guard let current, current.outcome == "failed" else { return nil }
        guard previous != current else { return nil }

        var parts: [String] = []
        if let routeScope = current.routeScope, !routeScope.isEmpty {
            parts.append(routeDescription(routeScope))
        }
        if let model = current.model, !model.isEmpty {
            parts.append(model)
        }
        if let detail = current.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            parts.append(detail)
        }

        let body = parts.isEmpty
            ? current.title
            : "\(current.title) • \(parts.joined(separator: " • "))"

        return OnlyMacsUserNotificationPlan(
            id: "activity:\(current.title):failed",
            title: "OnlyMacs command needs attention",
            body: body
        )
    }

    private static func sharePlan(
        previous: OnlyMacsNotificationShareSnapshot?,
        current: OnlyMacsNotificationShareSnapshot?
    ) -> OnlyMacsUserNotificationPlan? {
        guard let current, current.published else { return nil }
        let previousActiveSessions = previous?.activeSessions ?? 0
        guard current.activeSessions > previousActiveSessions else { return nil }

        let swarmLabel = current.activeSwarmName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = (swarmLabel?.isEmpty == false) ? swarmLabel! : "your active swarm"
        let liveJobs = current.activeSessions
        let jobsLabel = liveJobs == 1 ? "1 live swarm" : "\(liveJobs) live swarms"

        return OnlyMacsUserNotificationPlan(
            id: "share:\(target):\(current.servedSessions):\(liveJobs)",
            title: "OnlyMacs is using this Mac",
            body: "\(jobsLabel) on \(target) • This Mac is helping right now."
        )
    }

    private static func sessionBody(label: String, model: String, routeSummary: String?) -> String {
        var parts = ["\(label) completed", model]
        if let routeSummary, !routeSummary.isEmpty {
            parts.append(routeSummary)
        }
        return parts.joined(separator: " • ")
    }

    private static func failureBody(label: String, model: String, detail: String?) -> String {
        var parts = ["\(label) failed", model]
        if let detail, !detail.isEmpty {
            parts.append(detail)
        }
        return parts.joined(separator: " • ")
    }

    private static func routeDescription(_ scope: String) -> String {
        switch scope {
        case "local_only":
            return "This Mac only"
        case "trusted_only":
            return "My Macs only"
        default:
            return "Swarm allowed"
        }
    }
}

@MainActor
final class OnlyMacsUserNotificationService {
    func deliver(_ plans: [OnlyMacsUserNotificationPlan]) async {
        guard !plans.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        let authorized = await ensureAuthorization(center: center)
        guard authorized else { return }

        for plan in plans.prefix(2) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default

            let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: nil)
            await add(request, to: center)
        }
    }

    private func ensureAuthorization(center: UNUserNotificationCenter) async -> Bool {
        let authorizationStatus = await notificationAuthorizationStatus(center: center)
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization(center: center)
        default:
            return false
        }
    }

    private func notificationAuthorizationStatus(center: UNUserNotificationCenter) async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization(center: UNUserNotificationCenter) async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func add(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) async {
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }
}
