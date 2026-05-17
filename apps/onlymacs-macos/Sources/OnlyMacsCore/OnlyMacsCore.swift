public enum ProviderCapabilityTier: String, CaseIterable, Codable, Sendable {
    case tier4
    case tier3
    case tier2
    case tier1

    public var displayName: String {
        switch self {
        case .tier4:
            return "Tier 4"
        case .tier3:
            return "Tier 3"
        case .tier2:
            return "Tier 2"
        case .tier1:
            return "Tier 1"
        }
    }

    public var installerRecommendationMode: InstallerRecommendationMode {
        switch self {
        case .tier4, .tier3:
            return .singleRecommendedModel
        case .tier2:
            return .premiumBundle
        case .tier1:
            return .beastBundle
        }
    }
}

public enum InstallerRecommendationMode: String, CaseIterable, Codable, Sendable {
    case singleRecommendedModel
    case premiumBundle
    case beastBundle

    public var label: String {
        switch self {
        case .singleRecommendedModel:
            return "Single Recommended Model"
        case .premiumBundle:
            return "Premium Bundle"
        case .beastBundle:
            return "Beast Bundle"
        }
    }
}
