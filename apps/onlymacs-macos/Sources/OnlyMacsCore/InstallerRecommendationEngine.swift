import Foundation

public struct InstallerRecommendationItem: Equatable, Hashable, Identifiable, Sendable {
    public let model: ModelCatalogEntry
    public let selectedByDefault: Bool
    public let reason: String

    public var id: String { model.id }

    public init(model: ModelCatalogEntry, selectedByDefault: Bool, reason: String) {
        self.model = model
        self.selectedByDefault = selectedByDefault
        self.reason = reason
    }
}

public struct InstallerRecommendationPlan: Equatable, Sendable {
    public let tier: ProviderCapabilityTier
    public let mode: InstallerRecommendationMode
    public let freeDiskGB: Int
    public let reserveFloorGB: Int
    public let usableDiskGB: Int
    public let selectedModels: [InstallerRecommendationItem]
    public let optionalModels: [InstallerRecommendationItem]
    public let beastModeModels: [InstallerRecommendationItem]
    public let warnings: [String]
    public let totalSelectedDownloadGB: Double
    public let totalSelectedInstalledGB: Double

    public init(
        tier: ProviderCapabilityTier,
        mode: InstallerRecommendationMode,
        freeDiskGB: Int,
        reserveFloorGB: Int,
        usableDiskGB: Int,
        selectedModels: [InstallerRecommendationItem],
        optionalModels: [InstallerRecommendationItem],
        beastModeModels: [InstallerRecommendationItem],
        warnings: [String]
    ) {
        self.tier = tier
        self.mode = mode
        self.freeDiskGB = freeDiskGB
        self.reserveFloorGB = reserveFloorGB
        self.usableDiskGB = usableDiskGB
        self.selectedModels = selectedModels
        self.optionalModels = optionalModels
        self.beastModeModels = beastModeModels
        self.warnings = warnings
        self.totalSelectedDownloadGB = selectedModels.reduce(0) { $0 + $1.model.installer.estimatedDownloadGB }
        self.totalSelectedInstalledGB = selectedModels.reduce(0) { $0 + $1.model.installer.estimatedInstalledGB }
    }
}

public enum InstallerRecommendationEngine {
    public static func plan(
        catalog: ModelCatalog,
        snapshot: ProviderCapabilitySnapshot,
        reserveFloorGB: Int? = nil
    ) -> InstallerRecommendationPlan {
        let assessment = ProviderCapabilityTiering.assess(snapshot)
        return plan(
            catalog: catalog,
            tier: assessment.tier,
            freeDiskGB: snapshot.freeDiskGB,
            reserveFloorGB: reserveFloorGB ?? defaultReserveFloor(for: assessment.tier)
        )
    }

    public static func plan(
        catalog: ModelCatalog,
        tier: ProviderCapabilityTier,
        freeDiskGB: Int,
        reserveFloorGB: Int
    ) -> InstallerRecommendationPlan {
        let usableDiskGB = max(0, freeDiskGB - reserveFloorGB)
        let visibleModels = catalog.models.filter { $0.capabilityTiers.firstRunVisibleTiers.contains(tier) }
        let standardVisible = visibleModels
            .filter { !$0.advancedVisibility.beastModeEligible }
            .sorted(by: compareModels)
        let beastVisible = visibleModels
            .filter(\.advancedVisibility.beastModeEligible)
            .sorted(by: compareModels)

        var warnings: [String] = []
        var selectedIDs = Set<String>()
        var selectedItems: [InstallerRecommendationItem] = []
        var usedInstalledGB = 0.0

        func trySelect(_ model: ModelCatalogEntry, reason: String) {
            guard !selectedIDs.contains(model.id) else { return }
            let nextInstalled = usedInstalledGB + model.installer.estimatedInstalledGB
            guard nextInstalled <= Double(usableDiskGB) else { return }
            selectedIDs.insert(model.id)
            selectedItems.append(
                InstallerRecommendationItem(
                    model: model,
                    selectedByDefault: true,
                    reason: reason
                )
            )
            usedInstalledGB = nextInstalled
        }

        let defaultModels = standardVisible.filter { $0.installer.defaultSelectedTiers.contains(tier) }
        let premiumCandidates = standardVisible.filter {
            $0.installer.starterSubset && $0.installer.recommendationMode != .singleRecommendedModel
        }
        let singleCandidates = standardVisible.filter { $0.installer.recommendationMode == .singleRecommendedModel }

        switch tier {
        case .tier4, .tier3:
            if let primary = (defaultModels + singleCandidates).first {
                trySelect(primary, reason: "OnlyMacs preselects one fast, safe starter model for this tier.")
            }
        case .tier2:
            for model in defaultModels {
                trySelect(model, reason: "OnlyMacs starts Tier 2 hosts with a premium coding default.")
            }
            if let sharedStarter = preferredSharedStarterModel(for: tier, visibleModels: standardVisible) {
                trySelect(sharedStarter, reason: "OnlyMacs also preloads one shared-starter model so small mixed-memory swarms have a better chance of landing on the same coding model by default.")
            }
            for model in premiumCandidates where !selectedIDs.contains(model.id) {
                trySelect(model, reason: "This model expands what your Mac can share without overfilling the drive.")
            }
        case .tier1:
            for model in defaultModels {
                trySelect(model, reason: "OnlyMacs starts Tier 1 hosts with the flagship coding default.")
            }
            if let sharedStarter = preferredSharedStarterModel(for: tier, visibleModels: standardVisible) {
                trySelect(sharedStarter, reason: "OnlyMacs also preloads one shared-starter model so small mixed-memory swarms have a better chance of landing on the same coding model by default.")
            }
            for model in premiumCandidates where !selectedIDs.contains(model.id) {
                trySelect(model, reason: "This high-memory model is part of the default premium starter bundle.")
            }
            for model in beastVisible {
                trySelect(model, reason: "This Beast Mode model fits the current disk budget, so OnlyMacs is preloading it.")
            }
        }

        if selectedItems.isEmpty, let fallback = standardVisible.first {
            trySelect(fallback, reason: "OnlyMacs fell back to the safest visible starter because disk headroom is tight.")
        }

        if freeDiskGB <= reserveFloorGB {
            warnings.append("OnlyMacs is keeping \(reserveFloorGB) GB free, so no models can be preselected until more disk space is available.")
        } else {
            let unselectedDefaults = standardVisible.filter {
                ($0.installer.defaultSelectedTiers.contains(tier) || ($0.installer.recommendationMode != .singleRecommendedModel && tier.sortRank <= ProviderCapabilityTier.tier2.sortRank))
                    && !selectedIDs.contains($0.id)
            }
            if !unselectedDefaults.isEmpty {
                warnings.append("Some stronger defaults stayed unchecked because OnlyMacs is keeping \(reserveFloorGB) GB free.")
            }
        }

        if tier == .tier1, beastVisible.isEmpty == false, beastVisible.allSatisfy({ !selectedIDs.contains($0.id) }) {
            warnings.append("Beast Mode is visible on this Mac, but the current free-space budget is not large enough to precheck the giant models yet.")
        }

        let optionalModels = standardVisible
            .filter { !selectedIDs.contains($0.id) }
            .map {
                InstallerRecommendationItem(
                    model: $0,
                    selectedByDefault: false,
                    reason: optionalReason(for: $0)
                )
            }

        let beastModeModels = beastVisible.map {
            InstallerRecommendationItem(
                model: $0,
                selectedByDefault: selectedIDs.contains($0.id),
                reason: selectedIDs.contains($0.id)
                    ? "Preselected because this Tier 1 Mac has the disk headroom to absorb a Beast Mode download."
                    : "Visible in Beast Mode so you can opt into giant flagship installs when you want them."
            )
        }

        return InstallerRecommendationPlan(
            tier: tier,
            mode: tier.installerRecommendationMode,
            freeDiskGB: freeDiskGB,
            reserveFloorGB: reserveFloorGB,
            usableDiskGB: usableDiskGB,
            selectedModels: selectedItems,
            optionalModels: optionalModels,
            beastModeModels: beastModeModels,
            warnings: warnings
        )
    }

    public static func defaultReserveFloor(for tier: ProviderCapabilityTier) -> Int {
        switch tier {
        case .tier4, .tier3:
            return 80
        case .tier2:
            return 120
        case .tier1:
            return 160
        }
    }

    private static func compareModels(_ lhs: ModelCatalogEntry, _ rhs: ModelCatalogEntry) -> Bool {
        let lhsScore = modelPriority(lhs)
        let rhsScore = modelPriority(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        if lhs.approximateRAMGB != rhs.approximateRAMGB {
            return lhs.approximateRAMGB > rhs.approximateRAMGB
        }
        return lhs.id < rhs.id
    }

    private static func modelPriority(_ model: ModelCatalogEntry) -> Int {
        var score = 0

        if model.installer.defaultSelectedTiers.isEmpty == false {
            score += 400
        }
        if model.installer.recommendationMode == .beastBundle {
            score += 250
        } else if model.installer.recommendationMode == .premiumBundle {
            score += 150
        }

        switch model.role {
        case .coding:
            score += 80
        case .general:
            score += 55
        case .reasoning:
            score += 45
        case .multimodal:
            score += 20
        }

        if let badge = model.installer.recommendationBadge?.lowercased() {
            if badge.contains("recommended") {
                score += 60
            }
            if badge.contains("beast") {
                score += 40
            }
        }

        return score
    }

    private static func optionalReason(for model: ModelCatalogEntry) -> String {
        if !model.installer.starterSubset {
            return model.capabilityTiers.hardwareHint ?? "Fits this Mac as a high-memory option, but OnlyMacs leaves it unchecked until you choose to add it."
        }
        return "Visible for this tier, but left unchecked so you can decide how much disk to spend."
    }

    private static func preferredSharedStarterModel(
        for tier: ProviderCapabilityTier,
        visibleModels: [ModelCatalogEntry]
    ) -> ModelCatalogEntry? {
        let candidates = visibleModels.filter {
            $0.installer.starterSubset
                && !$0.advancedVisibility.beastModeEligible
                && supportsLowerTierInterop($0, from: tier)
        }
        return candidates.max { left, right in
            sharedStarterPriority(left) < sharedStarterPriority(right)
        }
    }

    private static func supportsLowerTierInterop(_ model: ModelCatalogEntry, from tier: ProviderCapabilityTier) -> Bool {
        model.capabilityTiers.supportedTiers.contains { $0.sortRank > tier.sortRank }
    }

    private static func sharedStarterPriority(_ model: ModelCatalogEntry) -> Int {
        var score = modelPriority(model)
        score += model.approximateRAMGB * 8
        score += max(0, model.capabilityTiers.supportedTiers.count - 1) * 40
        if model.role == .coding {
            score += 500
        }
        return score
    }
}

private extension ProviderCapabilityTier {
    var sortRank: Int {
        switch self {
        case .tier1:
            return 1
        case .tier2:
            return 2
        case .tier3:
            return 3
        case .tier4:
            return 4
        }
    }
}
