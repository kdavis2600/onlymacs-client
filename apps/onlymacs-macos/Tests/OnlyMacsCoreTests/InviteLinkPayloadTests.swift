import Testing
@testable import OnlyMacsCore

struct InviteLinkPayloadTests {
    @Test
    func buildsHostedInviteLinkWithCoordinatorURL() throws {
        let payload = try #require(InviteLinkPayload(
            inviteToken: "invite-test-token-for-docs",
            coordinatorURL: "https://relay.onlymacs.example.com/"
        ))

        #expect(payload.coordinatorURL == "https://relay.onlymacs.example.com")
        #expect(payload.appURL?.absoluteString == "onlymacs://join?invite_token=invite-test-token-for-docs&coordinator_url=https://relay.onlymacs.example.com")
    }

    @Test
    func parsesHostedInviteLink() throws {
        let payload = try #require(InviteLinkPayload.parse("onlymacs://join?invite_token=invite-test-token-for-docs&coordinator_url=https%3A%2F%2Frelay.onlymacs.example.com"))

        #expect(payload.inviteToken == "invite-test-token-for-docs")
        #expect(payload.coordinatorURL == "https://relay.onlymacs.example.com")
    }

    @Test
    func parsesBareInviteTokenFromFreeformText() throws {
        let payload = try #require(InviteLinkPayload.parse("Join with backup token invite-R4nd0mAlpha_beta9Zyx when you are ready"))

        #expect(payload.inviteToken == "invite-R4nd0mAlpha_beta9Zyx")
        #expect(payload.coordinatorURL == nil)
    }
}
