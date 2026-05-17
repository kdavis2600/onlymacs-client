#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

required_files=(
  "$repo_root/apps/onlymacs-macos/Sources/OnlyMacsCore/ModelCatalog.swift"
  "$repo_root/apps/onlymacs-macos/Sources/OnlyMacsCore/ModelCatalogLoader.swift"
  "$repo_root/apps/onlymacs-macos/Sources/OnlyMacsCore/Resources/model-catalog.v1.json"
  "$repo_root/apps/onlymacs-macos/Tests/OnlyMacsCoreTests/ModelCatalogLoaderTests.swift"
)

missing=0
for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[ERROR] Missing required catalog-slice file: $file" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

package_file="$repo_root/apps/onlymacs-macos/Package.swift"
if ! rg -q 'resources:\s*\[' "$package_file"; then
  echo "[ERROR] Package.swift does not declare bundled resources for OnlyMacsCore." >&2
  exit 1
fi

if ! rg -q 'process\("Resources"\)' "$package_file"; then
  echo "[ERROR] Package.swift does not process OnlyMacsCore Resources." >&2
  exit 1
fi

swift test --package-path "$repo_root/apps/onlymacs-macos"
