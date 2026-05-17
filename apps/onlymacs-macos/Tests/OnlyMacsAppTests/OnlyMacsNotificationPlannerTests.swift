import Foundation
import Testing
@testable import OnlyMacsApp

struct OnlyMacsNotificationPlannerTests {
    @Test
    func plansCompletedSwarmOnTerminalTransition() {
        let previous = [
            OnlyMacsNotificationSessionSnapshot(
                id: "swarm-1",
                title: "Code Review",
                status: "running",
                resolvedModel: "qwen2.5-coder:32b",
                routeSummary: "My Macs only",
                warningMessage: nil
            )
        ]
        let current = [
            OnlyMacsNotificationSessionSnapshot(
                id: "swarm-1",
                title: "Code Review",
                status: "completed",
                resolvedModel: "qwen2.5-coder:32b",
                routeSummary: "My Macs only",
                warningMessage: nil
            )
        ]

        let plans = OnlyMacsNotificationPlanner.plans(
            previousSessions: previous,
            currentSessions: current,
            previousShare: nil,
            currentShare: nil,
            previousActivity: nil,
            currentActivity: nil
        )

        #expect(plans.count == 1)
        #expect(plans.first?.title == "OnlyMacs finished a swarm")
        #expect(plans.first?.body.contains("Code Review completed") == true)
    }

    @Test
    func doesNotRepeatCompletedSwarmWhenStatusDidNotChange() {
        let session = OnlyMacsNotificationSessionSnapshot(
            id: "swarm-1",
            title: "Code Review",
            status: "completed",
            resolvedModel: "qwen2.5-coder:32b",
            routeSummary: "My Macs only",
            warningMessage: nil
        )

        let plans = OnlyMacsNotificationPlanner.plans(
            previousSessions: [session],
            currentSessions: [session],
            previousShare: nil,
            currentShare: nil,
            previousActivity: nil,
            currentActivity: nil
        )

        #expect(plans.isEmpty)
    }

    @Test
    func plansFailedActivityWhenNoTerminalSwarmChangeExists() {
        let previousActivity = OnlyMacsNotificationActivitySnapshot(
            title: "go local-first",
            outcome: "launched",
            detail: "Started a new OnlyMacs swarm.",
            routeScope: "local_only",
            model: "qwen2.5-coder:32b"
        )
        let currentActivity = OnlyMacsNotificationActivitySnapshot(
            title: "go local-first",
            outcome: "failed",
            detail: "Could not start the swarm session.",
            routeScope: "local_only",
            model: "qwen2.5-coder:32b"
        )

        let plans = OnlyMacsNotificationPlanner.plans(
            previousSessions: [],
            currentSessions: [],
            previousShare: nil,
            currentShare: nil,
            previousActivity: previousActivity,
            currentActivity: currentActivity
        )

        #expect(plans.count == 1)
        #expect(plans.first?.title == "OnlyMacs command needs attention")
        #expect(plans.first?.body.contains("This Mac only") == true)
    }

    @Test
    func prefersTerminalSwarmNotificationOverLauncherFailure() {
        let previousSessions = [
            OnlyMacsNotificationSessionSnapshot(
                id: "swarm-1",
                title: "Release Review",
                status: "running",
                resolvedModel: "qwen2.5-coder:32b",
                routeSummary: "Swarm allowed",
                warningMessage: nil
            )
        ]
        let currentSessions = [
            OnlyMacsNotificationSessionSnapshot(
                id: "swarm-1",
                title: "Release Review",
                status: "failed",
                resolvedModel: "qwen2.5-coder:32b",
                routeSummary: "Swarm allowed",
                warningMessage: "OnlyMacs could not keep the previous premium slot."
            )
        ]
        let currentActivity = OnlyMacsNotificationActivitySnapshot(
            title: "go precise",
            outcome: "failed",
            detail: "Could not start the swarm session.",
            routeScope: "swarm",
            model: "qwen2.5-coder:32b"
        )

        let plans = OnlyMacsNotificationPlanner.plans(
            previousSessions: previousSessions,
            currentSessions: currentSessions,
            previousShare: nil,
            currentShare: nil,
            previousActivity: nil,
            currentActivity: currentActivity
        )

        #expect(plans.count == 1)
        #expect(plans.first?.id == "swarm:swarm-1:failed")
    }

    @Test
    func plansProviderUseNotificationWhenThisMacStartsHelping() {
        let previousShare = OnlyMacsNotificationShareSnapshot(
            published: true,
            activeSwarmName: "OnlyMacs Public",
            activeSessions: 0,
            servedSessions: 2
        )
        let currentShare = OnlyMacsNotificationShareSnapshot(
            published: true,
            activeSwarmName: "OnlyMacs Public",
            activeSessions: 1,
            servedSessions: 2
        )

        let plans = OnlyMacsNotificationPlanner.plans(
            previousSessions: [],
            currentSessions: [],
            previousShare: previousShare,
            currentShare: currentShare,
            previousActivity: nil,
            currentActivity: nil
        )

        #expect(plans.count == 1)
        #expect(plans.first?.title == "OnlyMacs is using this Mac")
        #expect(plans.first?.body.contains("OnlyMacs Public") == true)
    }

    @Test
    func doesNotRepeatProviderUseNotificationWhenActiveSessionsStayFlat() {
        let share = OnlyMacsNotificationShareSnapshot(
            published: true,
            activeSwarmName: "OnlyMacs Public",
            activeSessions: 1,
            servedSessions: 2
        )

        let plans = OnlyMacsNotificationPlanner.plans(
            previousSessions: [],
            currentSessions: [],
            previousShare: share,
            currentShare: share,
            previousActivity: nil,
            currentActivity: nil
        )

        #expect(plans.isEmpty)
    }
}
