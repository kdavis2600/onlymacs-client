import Testing
@testable import OnlyMacsCore

@Test
func tierFourGetsOneSafeStarterDefault() throws {
    let catalog = try ModelCatalogLoader.loadBundled()
    let plan = InstallerRecommendationEngine.plan(
        catalog: catalog,
        snapshot: ProviderCapabilitySnapshot(unifiedMemoryGB: 32, freeDiskGB: 180)
    )

    #expect(plan.tier == .tier4)
    #expect(plan.mode == .singleRecommendedModel)
    #expect(plan.selectedModels.count == 1)
    #expect(plan.selectedModels.first?.model.id == "qwen25-coder-7b-q4km")
    #expect(plan.beastModeModels.isEmpty)
}

@Test
func tierOneBundleLoadsPremiumAndBeastDefaultsWhenDiskIsHuge() throws {
    let catalog = try ModelCatalogLoader.loadBundled()
    let plan = InstallerRecommendationEngine.plan(
        catalog: catalog,
        snapshot: ProviderCapabilitySnapshot(unifiedMemoryGB: 256, freeDiskGB: 1_200)
    )

    #expect(plan.tier == .tier1)
    #expect(plan.selectedModels.contains { $0.model.id == "qwen25-coder-32b-q5km" })
    #expect(plan.selectedModels.contains { $0.model.id == "gemma4-31b-q4km" })
    #expect(plan.beastModeModels.contains { $0.model.id == "qwen3-235b-a22b-beast" && $0.selectedByDefault })
    #expect(plan.beastModeModels.contains { $0.model.id == "llama4-maverick-beast" && $0.selectedByDefault })
}

@Test
func reserveFloorKeepsTierTwoFromOvercommittingDisk() throws {
    let catalog = try ModelCatalogLoader.loadBundled()
    let plan = InstallerRecommendationEngine.plan(
        catalog: catalog,
        snapshot: ProviderCapabilitySnapshot(unifiedMemoryGB: 128, freeDiskGB: 150),
        reserveFloorGB: 120
    )

    #expect(plan.tier == .tier2)
    #expect(plan.usableDiskGB == 30)
    #expect(plan.totalSelectedInstalledGB <= 30)
    #expect(plan.warnings.isEmpty == false)
}

@Test
func tierTwoBundleIncludesQwen36FlagshipWhenDiskAllows() throws {
    let catalog = try ModelCatalogLoader.loadBundled()
    let plan = InstallerRecommendationEngine.plan(
        catalog: catalog,
        snapshot: ProviderCapabilitySnapshot(unifiedMemoryGB: 128, freeDiskGB: 320),
        reserveFloorGB: 120
    )

    #expect(plan.tier == .tier2)
    #expect(plan.selectedModels.contains { $0.model.id == "qwen36-35b-a3b-q8_0" })
}

@Test
func tierTwoPlanSurfacesLargeModelsWithoutPrecheckingThem() throws {
    let catalog = try ModelCatalogLoader.loadBundled()
    let plan = InstallerRecommendationEngine.plan(
        catalog: catalog,
        snapshot: ProviderCapabilitySnapshot(unifiedMemoryGB: 128, freeDiskGB: 500),
        reserveFloorGB: 120
    )

    let largeModelIDs: Set<String> = [
        "gpt-oss-120b-mxfp4",
        "deepseek-r1-70b-q4km",
        "qwen25-72b-q4km",
        "llama31-70b-q4km",
    ]
    let selectedIDs = Set(plan.selectedModels.map(\.model.id))
    let optionalIDs = Set(plan.optionalModels.map(\.model.id))

    #expect(plan.tier == .tier2)
    #expect(largeModelIDs.isSubset(of: optionalIDs))
    #expect(selectedIDs.isDisjoint(with: largeModelIDs))
}

@Test
func tierTwoBundleIncludesSharedCompatibilityCoderModel() throws {
    let catalog = try ModelCatalogLoader.loadBundled()
    let plan = InstallerRecommendationEngine.plan(
        catalog: catalog,
        snapshot: ProviderCapabilitySnapshot(unifiedMemoryGB: 128, freeDiskGB: 320),
        reserveFloorGB: 120
    )

    #expect(plan.tier == .tier2)
    #expect(plan.selectedModels.contains {
        $0.model.role == .coding && $0.model.capabilityTiers.supportedTiers.contains(.tier3)
    })
}

@Test
func sixtyFourAndOneTwentyEightGigPlansShareAtLeastOneStarterModel() throws {
    let catalog = try ModelCatalogLoader.loadBundled()
    let sixtyFourPlan = InstallerRecommendationEngine.plan(
        catalog: catalog,
        snapshot: ProviderCapabilitySnapshot(unifiedMemoryGB: 64, freeDiskGB: 240),
        reserveFloorGB: 80
    )
    let oneTwentyEightPlan = InstallerRecommendationEngine.plan(
        catalog: catalog,
        snapshot: ProviderCapabilitySnapshot(unifiedMemoryGB: 128, freeDiskGB: 320),
        reserveFloorGB: 120
    )

    let sharedModelIDs = Set(sixtyFourPlan.selectedModels.map(\.model.id)).intersection(oneTwentyEightPlan.selectedModels.map(\.model.id))
    #expect(sharedModelIDs.isEmpty == false)
}

@Test
func sixtyFourGigPlanCanSeeQwen36Q4AsManualOption() throws {
    let catalog = try ModelCatalogLoader.loadBundled()
    let plan = InstallerRecommendationEngine.plan(
        catalog: catalog,
        snapshot: ProviderCapabilitySnapshot(unifiedMemoryGB: 64, freeDiskGB: 240),
        reserveFloorGB: 80
    )

    #expect(plan.tier == .tier3)
    #expect(plan.selectedModels.contains { $0.model.id == "qwen36-35b-a3b-q4km" } == false)
    #expect(plan.optionalModels.contains { $0.model.id == "qwen36-35b-a3b-q4km" })
    #expect(plan.optionalModels.contains { $0.model.id == "gpt-oss-120b-mxfp4" } == false)
    #expect(plan.optionalModels.contains { $0.model.id == "deepseek-r1-70b-q4km" } == false)
    #expect(plan.optionalModels.contains { $0.model.id == "qwen25-72b-q4km" } == false)
    #expect(plan.optionalModels.contains { $0.model.id == "llama31-70b-q4km" } == false)
}
