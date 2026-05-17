import Foundation

public enum ModelCatalogLoaderError: Error, CustomStringConvertible, Sendable {
    case missingBundledCatalog
    case unreadableCatalog(URL)
    case invalidJSON(String)
    case invalidSchemaVersion
    case emptyCatalog
    case duplicateModelID(String)
    case emptyFamily(String)
    case emptyExactModelName(String)
    case emptyHuggingFaceRepo(String)
    case emptyLicense(String)
    case emptySupportedTiers(String)
    case emptyFirstRunVisibleTiers(String)
    case firstRunVisibilityOutsideSupportedTiers(String)
    case defaultSelectionOutsideFirstRunVisibility(String)
    case invalidEstimatedSizes(String)

    public var description: String {
        switch self {
        case .missingBundledCatalog:
            return "Missing bundled model catalog resource."
        case .unreadableCatalog(let url):
            return "Could not read bundled model catalog at \(url.path)."
        case .invalidJSON(let message):
            return "Invalid model catalog JSON: \(message)"
        case .invalidSchemaVersion:
            return "Model catalog schemaVersion must be non-empty."
        case .emptyCatalog:
            return "Model catalog must contain at least one model."
        case .duplicateModelID(let id):
            return "Model catalog contains duplicate model id '\(id)'."
        case .emptyFamily(let id):
            return "Model '\(id)' is missing family."
        case .emptyExactModelName(let id):
            return "Model '\(id)' is missing exactModelName."
        case .emptyHuggingFaceRepo(let id):
            return "Model '\(id)' is missing huggingFaceRepo."
        case .emptyLicense(let id):
            return "Model '\(id)' is missing license metadata."
        case .emptySupportedTiers(let id):
            return "Model '\(id)' must support at least one provider capability tier."
        case .emptyFirstRunVisibleTiers(let id):
            return "Model '\(id)' must be visible to at least one verified provider tier on first run."
        case .firstRunVisibilityOutsideSupportedTiers(let id):
            return "Model '\(id)' exposes first-run visible tiers that are not supported tiers."
        case .defaultSelectionOutsideFirstRunVisibility(let id):
            return "Model '\(id)' defaults to tiers that cannot see it on first run."
        case .invalidEstimatedSizes(let id):
            return "Model '\(id)' must have positive estimated download and installed sizes."
        }
    }
}

public enum ModelCatalogLoader {
    public static func loadBundled() throws -> ModelCatalog {
        if let appBundle = appHostedResourceBundle() {
            return try loadBundled(bundle: appBundle)
        }
        return try loadBundled(bundle: .module)
    }

    public static func loadBundled(bundle: Bundle) throws -> ModelCatalog {
        guard let url = bundle.url(forResource: "model-catalog.v1", withExtension: "json") else {
            throw ModelCatalogLoaderError.missingBundledCatalog
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ModelCatalogLoaderError.unreadableCatalog(url)
        }

        return try load(data: data)
    }

    public static func load(data: Data) throws -> ModelCatalog {
        let decoder = JSONDecoder()

        let catalog: ModelCatalog
        do {
            catalog = try decoder.decode(ModelCatalog.self, from: data)
        } catch {
            throw ModelCatalogLoaderError.invalidJSON(String(describing: error))
        }

        try validate(catalog)
        return catalog
    }

    private static func validate(_ catalog: ModelCatalog) throws {
        guard catalog.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ModelCatalogLoaderError.invalidSchemaVersion
        }

        guard catalog.models.isEmpty == false else {
            throw ModelCatalogLoaderError.emptyCatalog
        }

        var seenIDs = Set<String>()

        for model in catalog.models {
            guard seenIDs.insert(model.id).inserted else {
                throw ModelCatalogLoaderError.duplicateModelID(model.id)
            }

            guard model.family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw ModelCatalogLoaderError.emptyFamily(model.id)
            }

            guard model.exactModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw ModelCatalogLoaderError.emptyExactModelName(model.id)
            }

            guard model.huggingFaceRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw ModelCatalogLoaderError.emptyHuggingFaceRepo(model.id)
            }

            guard model.license.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  model.license.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw ModelCatalogLoaderError.emptyLicense(model.id)
            }

            guard model.capabilityTiers.supportedTiers.isEmpty == false else {
                throw ModelCatalogLoaderError.emptySupportedTiers(model.id)
            }

            guard model.capabilityTiers.firstRunVisibleTiers.isEmpty == false else {
                throw ModelCatalogLoaderError.emptyFirstRunVisibleTiers(model.id)
            }

            let supported = Set(model.capabilityTiers.supportedTiers)
            let firstRunVisible = Set(model.capabilityTiers.firstRunVisibleTiers)
            guard firstRunVisible.isSubset(of: supported) else {
                throw ModelCatalogLoaderError.firstRunVisibilityOutsideSupportedTiers(model.id)
            }

            let defaultSelected = Set(model.installer.defaultSelectedTiers)
            guard defaultSelected.isSubset(of: firstRunVisible) else {
                throw ModelCatalogLoaderError.defaultSelectionOutsideFirstRunVisibility(model.id)
            }

            guard model.installer.estimatedDownloadGB > 0, model.installer.estimatedInstalledGB > 0 else {
                throw ModelCatalogLoaderError.invalidEstimatedSizes(model.id)
            }
        }
    }

    private static func appHostedResourceBundle() -> Bundle? {
        let bundleName = "OnlyMacsApp_OnlyMacsCore.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return nil
    }
}
