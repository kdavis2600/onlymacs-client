#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

bash "$repo_root/scripts/validate-model-catalog-seed-loader.sh" >/dev/null

required_files=(
  "$repo_root/apps/onlymacs-macos/Sources/OnlyMacsCore/ProviderCapabilityTiering.swift"
  "$repo_root/apps/onlymacs-macos/Sources/OnlyMacsCore/InstallerRecommendationEngine.swift"
  "$repo_root/apps/onlymacs-macos/Sources/OnlyMacsCore/ModelDownloadQueue.swift"
  "$repo_root/apps/onlymacs-macos/Tests/OnlyMacsCoreTests/InstallerRecommendationEngineTests.swift"
  "$repo_root/apps/onlymacs-macos/Tests/OnlyMacsCoreTests/ModelDownloadQueueTests.swift"
)

missing=0
for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[ERROR] Missing required recommendation-slice file: $file" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

app_file="$repo_root/apps/onlymacs-macos/Sources/OnlyMacsApp/OnlyMacsApp.swift"
if ! rg -q '^import OnlyMacsCore$' "$app_file"; then
  echo "[ERROR] OnlyMacsApp.swift does not import OnlyMacsCore." >&2
  exit 1
fi

if ! rg -q 'ModelCatalog|ModelCatalogLoader|InstallerRecommendationEngine|ProviderCapabilityTiering|ModelDownloadQueue' "$app_file"; then
  echo "[ERROR] OnlyMacsApp.swift is not consuming the new OnlyMacsCore model/recommendation types yet." >&2
  exit 1
fi

swift test --package-path "$repo_root/apps/onlymacs-macos"
