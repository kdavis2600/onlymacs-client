import Testing
@testable import OnlyMacsCore

@Test
func tierInstallerDefaultsMatchLockedProductRules() {
    #expect(ProviderCapabilityTier.tier4.installerRecommendationMode == .singleRecommendedModel)
    #expect(ProviderCapabilityTier.tier3.installerRecommendationMode == .singleRecommendedModel)
    #expect(ProviderCapabilityTier.tier2.installerRecommendationMode == .premiumBundle)
    #expect(ProviderCapabilityTier.tier1.installerRecommendationMode == .beastBundle)
}
