import Testing
@testable import OnlyMacsCore

struct CoordinatorConnectionSettingsTests {
    @Test func hostedRemoteIsTheOnlyUserSelectableCoordinatorMode() {
        #expect(CoordinatorConnectionMode.userSelectableCases == [.hostedRemote])
    }

    @Test func defaultModeUsesHostedCoordinator() {
        let settings = CoordinatorConnectionSettings()

        #expect(!settings.launchesEmbeddedCoordinator)
        #expect(settings.effectiveCoordinatorURL == "https://onlymacs.ai")
        #expect(settings.validationError == nil)
    }

    @Test func explicitLocalCoordinatorModeUsesBundledCoordinator() {
        let settings = CoordinatorConnectionSettings(mode: .embeddedLocal, remoteCoordinatorURL: "")

        #expect(settings.launchesEmbeddedCoordinator)
        #expect(settings.effectiveCoordinatorURL == "http://127.0.0.1:4319")
        #expect(settings.validationError == nil)
    }

    @Test func hostedModeNormalizesCoordinatorURL() {
        let settings = CoordinatorConnectionSettings(
            mode: .hostedRemote,
            remoteCoordinatorURL: " https://relay.onlymacs.example.com/ "
        )

        #expect(!settings.launchesEmbeddedCoordinator)
        #expect(settings.normalizedRemoteCoordinatorURL == "https://relay.onlymacs.example.com")
        #expect(settings.effectiveCoordinatorURL == "https://relay.onlymacs.example.com")
        #expect(settings.validationError == nil)
    }

    @Test func hostedModeRejectsInvalidURL() {
        let settings = CoordinatorConnectionSettings(
            mode: .hostedRemote,
            remoteCoordinatorURL: "ftp://example.com"
        )

        #expect(settings.normalizedRemoteCoordinatorURL == nil)
        #expect(settings.validationError == "Enter a valid hosted coordinator URL.")
    }
}
