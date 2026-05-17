import Foundation

public struct ModelCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let generatedAt: String?
    public let models: [ModelCatalogEntry]

    public init(schemaVersion: String, generatedAt: String? = nil, models: [ModelCatalogEntry]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.models = models
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case models
    }
}

public struct ModelCatalogEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let family: String
    public let exactModelName: String
    public let huggingFaceRepo: String
    public let huggingFaceFile: String?
    public let role: ModelRole
    public let quant: ModelQuantization
    public let approximateRAMGB: Int
    public let license: ModelLicense
    public let capabilityTiers: CapabilityTierMetadata
    public let installer: InstallerMetadata
    public let advancedVisibility: AdvancedVisibilityMetadata

    enum CodingKeys: String, CodingKey {
        case id
        case family
        case exactModelName = "exact_model_name"
        case huggingFaceRepo = "hugging_face_repo"
        case huggingFaceFile = "hugging_face_file"
        case role
        case quant
        case approximateRAMGB = "approximate_ram_gb"
        case license
        case capabilityTiers = "capability_tiers"
        case installer
        case advancedVisibility = "advanced_visibility"
    }
}

public enum ModelRole: String, Codable, CaseIterable, Sendable {
    case coding
    case general
    case reasoning
    case multimodal
}

public struct ModelQuantization: Codable, Equatable, Hashable, Sendable {
    public let label: String
    public let format: String
    public let bits: Int
}

public struct ModelLicense: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let metadataURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case metadataURL = "metadata_url"
    }
}

public struct CapabilityTierMetadata: Codable, Equatable, Hashable, Sendable {
    public let supportedTiers: [ProviderCapabilityTier]
    public let firstRunVisibleTiers: [ProviderCapabilityTier]
    public let hardwareHint: String?

    enum CodingKeys: String, CodingKey {
        case supportedTiers = "supported_tiers"
        case firstRunVisibleTiers = "first_run_visible_tiers"
        case hardwareHint = "hardware_hint"
    }
}

public struct InstallerMetadata: Codable, Equatable, Hashable, Sendable {
    public let starterSubset: Bool
    public let recommendationMode: InstallerRecommendationMode
    public let defaultSelectedTiers: [ProviderCapabilityTier]
    public let recommendationBadge: String?
    public let estimatedDownloadGB: Double
    public let estimatedInstalledGB: Double

    enum CodingKeys: String, CodingKey {
        case starterSubset = "starter_subset"
        case recommendationMode = "recommendation_mode"
        case defaultSelectedTiers = "default_selected_tiers"
        case recommendationBadge = "recommendation_badge"
        case estimatedDownloadGB = "estimated_download_gb"
        case estimatedInstalledGB = "estimated_installed_gb"
    }
}

public struct AdvancedVisibilityMetadata: Codable, Equatable, Hashable, Sendable {
    public let beastModeEligible: Bool
    public let collapsedByDefault: Bool

    enum CodingKeys: String, CodingKey {
        case beastModeEligible = "beast_mode_eligible"
        case collapsedByDefault = "collapsed_by_default"
    }
}
