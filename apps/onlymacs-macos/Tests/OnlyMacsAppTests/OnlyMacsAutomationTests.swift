import Foundation
import Testing
@testable import OnlyMacsApp

@Suite(.serialized)
struct OnlyMacsAutomationTests {
    @Test
    func automationCommandJSONRoundTripsSectionAndSurface() throws {
        let command = OnlyMacsAutomationCommand(
            id: "pending",
            createdAt: Date(timeIntervalSince1970: 1_000),
            surface: .fileApproval,
            action: .approve,
            section: ControlCenterSection.activity.rawValue
        )

        let data = try OnlyMacsAutomationStore.encodeJSON(command)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OnlyMacsAutomationCommand.self, from: data)

        #expect(decoded.id == command.id)
        #expect(decoded.surface == .fileApproval)
        #expect(decoded.action == .approve)
        #expect(decoded.controlCenterSection == .activity)
    }
}
