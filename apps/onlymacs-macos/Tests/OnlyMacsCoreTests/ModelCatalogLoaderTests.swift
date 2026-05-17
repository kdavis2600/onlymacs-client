import Foundation
import Testing
@testable import OnlyMacsCore

@Test
func bundledCatalogLoadsWithStarterSubsetAndBeastModeCoverage() throws {
    let catalog = try ModelCatalogLoader.loadBundled()

    #expect(catalog.schemaVersion == "1.0")
    #expect(catalog.models.count >= 8)

    let starterModels = catalog.models.filter(\.installer.starterSubset)
    let beastModeModels = catalog.models.filter(\.advancedVisibility.beastModeEligible)

    #expect(starterModels.isEmpty == false)
    #expect(beastModeModels.isEmpty == false)
    #expect(beastModeModels.allSatisfy { $0.advancedVisibility.collapsedByDefault })

    let tierFourStarter = try #require(
        catalog.models.first(where: { $0.installer.defaultSelectedTiers.contains(.tier4) })
    )
    #expect(tierFourStarter.exactModelName == "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF")
}

@Test
func loaderRejectsDuplicateModelIdentifiers() throws {
    let invalidJSON = """
    {
      "schema_version": "1.0",
      "models": [
        {
          "id": "duplicate",
          "family": "Qwen",
          "exact_model_name": "Qwen/Foo",
          "hugging_face_repo": "Qwen/Foo",
          "role": "coding",
          "quant": { "label": "q4_k_m", "format": "gguf", "bits": 4 },
          "approximate_ram_gb": 16,
          "license": { "id": "apache-2.0", "display_name": "Apache 2.0" },
          "capability_tiers": {
            "supported_tiers": ["tier4"],
            "first_run_visible_tiers": ["tier4"]
          },
          "installer": {
            "starter_subset": true,
            "recommendation_mode": "singleRecommendedModel",
            "default_selected_tiers": ["tier4"],
            "estimated_download_gb": 1.0,
            "estimated_installed_gb": 1.0
          },
          "advanced_visibility": {
            "beast_mode_eligible": false,
            "collapsed_by_default": false
          }
        },
        {
          "id": "duplicate",
          "family": "Gemma",
          "exact_model_name": "Gemma/Bar",
          "hugging_face_repo": "Gemma/Bar",
          "role": "general",
          "quant": { "label": "q4_k_m", "format": "gguf", "bits": 4 },
          "approximate_ram_gb": 32,
          "license": { "id": "gemma", "display_name": "Gemma Terms" },
          "capability_tiers": {
            "supported_tiers": ["tier3"],
            "first_run_visible_tiers": ["tier3"]
          },
          "installer": {
            "starter_subset": true,
            "recommendation_mode": "singleRecommendedModel",
            "default_selected_tiers": ["tier3"],
            "estimated_download_gb": 2.0,
            "estimated_installed_gb": 2.0
          },
          "advanced_visibility": {
            "beast_mode_eligible": false,
            "collapsed_by_default": false
          }
        }
      ]
    }
    """

    #expect(throws: ModelCatalogLoaderError.self) {
        try ModelCatalogLoader.load(data: Data(invalidJSON.utf8))
    }
}

@Test
func loaderRejectsDefaultSelectionOutsideFirstRunVisibility() throws {
    let invalidJSON = """
    {
      "schema_version": "1.0",
      "models": [
        {
          "id": "bad-default-selection",
          "family": "Qwen",
          "exact_model_name": "Qwen/Foo",
          "hugging_face_repo": "Qwen/Foo",
          "role": "coding",
          "quant": { "label": "q4_k_m", "format": "gguf", "bits": 4 },
          "approximate_ram_gb": 16,
          "license": { "id": "apache-2.0", "display_name": "Apache 2.0" },
          "capability_tiers": {
            "supported_tiers": ["tier4", "tier3"],
            "first_run_visible_tiers": ["tier4"]
          },
          "installer": {
            "starter_subset": true,
            "recommendation_mode": "singleRecommendedModel",
            "default_selected_tiers": ["tier3"],
            "estimated_download_gb": 1.0,
            "estimated_installed_gb": 1.0
          },
          "advanced_visibility": {
            "beast_mode_eligible": false,
            "collapsed_by_default": false
          }
        }
      ]
    }
    """

    #expect(throws: ModelCatalogLoaderError.self) {
        try ModelCatalogLoader.load(data: Data(invalidJSON.utf8))
    }
}
