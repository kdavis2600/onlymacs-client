import Foundation
import Testing
@testable import OnlyMacsApp

struct SupportBundleWriterTests {
    @Test
    func redactJSONTextScrubsPromptMessagesTitlesAndTokens() {
        let input = """
        {
          "sessions": [
            {
              "title": "review this secret auth flow",
              "prompt": "api_key=sk-live-123",
              "messages": [
                { "role": "user", "content": "password=hunter2" },
                { "role": "assistant", "content": "some answer" }
              ],
              "invite_token": "invite-12345"
            }
          ],
          "authorization": "Bearer super-secret-token",
          "body_base64": "SGVsbG8="
        }
        """

        let redacted = SupportBundleWriter.redactJSONText(input)

        #expect(redacted.contains("[REDACTED TITLE]"))
        #expect(redacted.contains("[REDACTED MESSAGE]"))
        #expect(redacted.contains("\"prompt\" : \"[REDACTED]\"") || redacted.contains("\"prompt\":\"[REDACTED]\""))
        #expect(redacted.contains("\"invite_token\" : \"[REDACTED]\"") || redacted.contains("\"invite_token\":\"[REDACTED]\""))
        #expect(redacted.contains("\"authorization\" : \"[REDACTED]\"") || redacted.contains("\"authorization\":\"[REDACTED]\""))
        #expect(redacted.contains("\"body_base64\" : \"[REDACTED]\"") || redacted.contains("\"body_base64\":\"[REDACTED]\""))
        #expect(redacted.contains("review this secret auth flow") == false)
        #expect(redacted.contains("sk-live-123") == false)
        #expect(redacted.contains("hunter2") == false)
        #expect(redacted.contains("invite-12345") == false)
        #expect(redacted.contains("super-secret-token") == false)
    }

    @Test
    func redactFreeformScrubsBearerTokensInviteTokensAndKeyBlocks() {
        let input = """
        Authorization: Bearer secret-token-123
        invite_token=invite-abc
        password=hunter2
        -----BEGIN PRIVATE KEY-----
        super secret key material
        -----END PRIVATE KEY-----
        """

        let redacted = SupportBundleWriter.redactFreeform(input)

        #expect(redacted.contains("secret-token-123") == false)
        #expect(redacted.contains("invite-abc") == false)
        #expect(redacted.contains("hunter2") == false)
        #expect(redacted.contains("super secret key material") == false)
        #expect(redacted.contains("[REDACTED KEY BLOCK]"))
    }

    @Test
    func diagnosticSummaryRedactsLastErrorAndMentionsPrivacy() {
        let input = SupportBundleInput(
            generatedAt: Date(timeIntervalSince1970: 0),
            buildVersion: "0.2.0",
            buildNumber: "20260415094500",
            buildTimestamp: "2026-04-15T09:45:00Z",
            buildChannel: "public",
            hostName: "Kevin's Mac",
            selectedMode: "both",
            coordinatorMode: "hosted",
            coordinatorTarget: "https://onlymacs.example.com",
            lastError: "Bearer top-secret token=abc123",
            recoveryTitle: "Needs Attention",
            recoveryDetail: "password=hunter2",
            recoveryActions: ["Export Bundle"],
            inviteExpiryDetail: "Expires in 6 days.",
            runtimeStatus: "ready",
            runtimeDetail: "token=xyz",
            helperSource: "bundled",
            logsDirectory: "/tmp/onlymacs-logs",
            jobWorkerStatus: "1/1 worker lanes",
            jobWorkerDesiredLanes: 1,
            jobWorkerRunningLanes: 1,
            jobWorkerDetail: "OnlyMacs is watching the job board.",
            launcherStatus: LauncherInstallStatus(
                installed: true,
                commandOnPath: true,
                profileConfigured: true,
                shimDirectoryURL: URL(fileURLWithPath: "/tmp/bin", isDirectory: true),
                entrypointURL: URL(fileURLWithPath: "/tmp/bin/onlymacs"),
                shellProfilePath: "/Users/test/.zshrc"
            ),
            tools: [SupportToolSnapshot(name: "Codex", status: "Detected", detail: "token=hidden")],
            latestOnlyMacsActivity: OnlyMacsCommandActivity(
                recordedAt: Date(timeIntervalSince1970: 10),
                wrapperName: "onlymacs",
                toolName: "Codex",
                workspaceID: "/tmp/workspace",
                threadID: "thread-123",
                commandLabel: "go local-first",
                interpretedAs: "go local-first (auto-safe)",
                routeScope: "local_only",
                model: "qwen2.5-coder:32b",
                outcome: "launched",
                detail: "Started a new OnlyMacs swarm.",
                sessionID: "session-123",
                sessionStatus: "running"
            ),
            localShareStatus: "ready",
            localEligibilityCode: "published_and_healthy",
            localEligibilityTitle: "Published and healthy",
            localEligibilityDetail: "This Mac is published into the active swarm and has a free local slot.",
            localSharePublished: true,
            localShareServedSessions: 12,
            localShareFailedSessions: 3,
            localShareUploadedTokensEstimate: 98765,
            localShareLastServedModel: "qwen2.5-coder:32b",
            activeReservations: 2,
            reservationCap: 4,
            bridgeStatusJSON: nil,
            localShareJSON: nil,
            swarmSessionsJSON: nil
        )

        let summary = SupportBundleWriter.diagnosticSummary(input)

        #expect(summary.contains("top-secret") == false)
        #expect(summary.contains("abc123") == false)
        #expect(summary.contains("hunter2") == false)
        #expect(summary.contains("Build: 0.2.0 (20260415094500) · public · 2026-04-15T09:45:00Z"))
        #expect(summary.contains("Share: ready, published=yes, served=12, failed=3, uploaded=98765"))
        #expect(summary.contains("This Mac Eligibility: Published and healthy"))
        #expect(summary.contains("Swarm Budget: 2/4"))
        #expect(summary.contains("Invite: Expires in 6 days."))
        #expect(summary.contains("Latest /onlymacs: go local-first (auto-safe) · launched · local_only · qwen2.5-coder:32b"))
        #expect(summary.contains("Privacy: prompts, secrets, tokens, and session titles are redacted by default"))
    }
}
