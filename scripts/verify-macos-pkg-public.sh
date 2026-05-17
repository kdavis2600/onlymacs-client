#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_PATH="$ROOT_DIR/dist/OnlyMacs-public.pkg"
MANIFEST_PATH="$ROOT_DIR/dist/OnlyMacs-public-pkg-manifest.json"
CHECKSUM_PATH="$ROOT_DIR/dist/OnlyMacs-public-pkg.sha256"

for required_path in "$PKG_PATH" "$MANIFEST_PATH" "$CHECKSUM_PATH"; do
  if [[ ! -e "$required_path" ]]; then
    echo "missing required artifact: $required_path" >&2
    exit 1
  fi
done

python3 - "$MANIFEST_PATH" "$PKG_PATH" "$CHECKSUM_PATH" <<'PY'
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import os

manifest_path = pathlib.Path(sys.argv[1])
pkg_path = pathlib.Path(sys.argv[2])
checksum_path = pathlib.Path(sys.argv[3])

manifest = json.loads(manifest_path.read_text())
checksum_line = checksum_path.read_text().strip()
expected_default_coordinator_url = os.environ.get("ONLYMACS_EXPECT_DEFAULT_COORDINATOR_URL", "").strip()
if not checksum_line:
    raise SystemExit("checksum file is empty")

actual_sha = hashlib.sha256(pkg_path.read_bytes()).hexdigest()
expected_sha = manifest["artifact_sha256"]
if actual_sha != expected_sha:
    raise SystemExit(f"manifest SHA mismatch: expected {expected_sha}, got {actual_sha}")

checksum_sha = checksum_line.split()[0]
if checksum_sha != actual_sha:
    raise SystemExit(f"checksum file SHA mismatch: expected {actual_sha}, got {checksum_sha}")

if manifest["artifact_bytes"] != pkg_path.stat().st_size:
    raise SystemExit("manifest artifact_bytes does not match actual pkg size")

with tempfile.TemporaryDirectory() as tmpdir:
    expanded_root = pathlib.Path(tmpdir) / "pkg"
    expand = subprocess.run(
        ["pkgutil", "--expand-full", str(pkg_path), str(expanded_root)],
        capture_output=True,
        text=True,
        check=False,
    )
    if expand.returncode != 0:
        raise SystemExit(f"pkg expand failed: {(expand.stdout + expand.stderr).strip()}")

    distribution_path = expanded_root / "Distribution"
    if not distribution_path.exists():
        raise SystemExit("expanded pkg payload missing Distribution metadata")

    distribution_text = distribution_path.read_text()
    expected_markers = ['welcome file="welcome.html"']
    if not all(marker in distribution_text for marker in expected_markers):
        raise SystemExit("distribution metadata missing installer welcome page")
    unexpected_markers = [
        'background file="only-macs-installer-background.png"',
        'background-darkAqua file="only-macs-installer-background-dark.png"',
    ]
    if any(marker in distribution_text for marker in unexpected_markers):
        raise SystemExit("distribution metadata still references deprecated installer background art")

    install_script_text = "\n".join(
        path.read_text(errors="ignore")
        for path in expanded_root.rglob("*")
        if path.is_file() and path.name in {"postinstall", "finalize.sh", "installer-session-helper.sh"}
    )
    if "prepare-app-for-sparkle-updates" not in install_script_text:
        raise SystemExit("installer postinstall does not prepare app ownership for unattended Sparkle updates")

    welcome_candidates = sorted(expanded_root.rglob("welcome.html"))
    if not welcome_candidates:
        raise SystemExit("expanded pkg payload missing installer welcome.html resource")
    welcome_text = welcome_candidates[0].read_text()
    expected_welcome_markers = [
        "OnlyMacs technical install summary",
        "Mac menu bar app, CLI, and approved local AI routes.",
        "Codex and Claude Code skills/slash commands",
        "File-aware remote work requires explicit approval and read-only export",
        "in-app recipe section",
    ]
    for marker in expected_welcome_markers:
        if marker not in welcome_text:
            raise SystemExit(f"installer welcome page missing technical summary marker: {marker}")
    stale_welcome_markers = [
        "Where Idle Macs Get Busy",
        "latest local AI models for free",
    ]
    for marker in stale_welcome_markers:
        if marker in welcome_text:
            raise SystemExit(f"installer welcome page still contains stale marketing copy: {marker}")

    conclusion_candidates = sorted(expanded_root.rglob("conclusion.html"))
    if not conclusion_candidates:
        raise SystemExit("expanded pkg payload missing installer conclusion.html resource")
    conclusion_text = conclusion_candidates[0].read_text()
    expected_conclusion_markers = [
        "Open the menu bar app to finish setup.",
        "native app, local bridge, launcher surface, and selected tool integrations",
        "file approval",
        "in-app recipe section",
    ]
    for marker in expected_conclusion_markers:
        if marker not in conclusion_text:
            raise SystemExit(f"installer conclusion page missing technical summary marker: {marker}")
    stale_conclusion_markers = [
        "Let the era of free tokens begin",
        "free tokens",
    ]
    for marker in stale_conclusion_markers:
        if marker in conclusion_text:
            raise SystemExit(f"installer conclusion page still contains stale marketing copy: {marker}")

    info_candidates = list(expanded_root.rglob("OnlyMacs.app/Contents/Info.plist"))
    if not info_candidates:
        raise SystemExit("expanded pkg payload missing OnlyMacs.app/Contents/Info.plist")
    info_plist_path = info_candidates[0]
    resource_dir = info_plist_path.parent / "Resources"
    resource_bundles = sorted(resource_dir.glob("*.bundle"))
    if not resource_bundles:
        raise SystemExit("expanded pkg payload missing SwiftPM resource bundles")

    with info_plist_path.open("rb") as fh:
        info = plistlib.load(fh)

    expected_pairs = {
        "bundle_id": info["CFBundleIdentifier"],
        "build_version": info["CFBundleShortVersionString"],
        "build_number": info["CFBundleVersion"],
        "build_timestamp": info["OnlyMacsBuildTimestamp"],
        "build_channel": info["OnlyMacsBuildChannel"],
        "default_coordinator_url": info.get("OnlyMacsDefaultCoordinatorURL", ""),
    }

    for key, actual_value in expected_pairs.items():
        manifest_value = manifest[key]
        if manifest_value != actual_value:
            raise SystemExit(f"manifest {key} mismatch: expected {actual_value}, got {manifest_value}")

    if expected_default_coordinator_url and expected_pairs["default_coordinator_url"] != expected_default_coordinator_url:
        raise SystemExit(
            "packaged app default coordinator mismatch: "
            f"expected {expected_default_coordinator_url}, got {expected_pairs['default_coordinator_url']}"
        )

    extracted_app_path = info_plist_path.parent.parent
    app_verify = subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(extracted_app_path)],
        capture_output=True,
        text=True,
    )
    app_signed = app_verify.returncode == 0

if manifest["app_signed"] != app_signed:
    raise SystemExit(f"manifest app_signed mismatch: expected {app_signed}, got {manifest['app_signed']}")

pkg_signature = subprocess.run(
    ["pkgutil", "--check-signature", str(pkg_path)],
    capture_output=True,
    text=True,
    check=False,
)
signature_output = (pkg_signature.stdout + "\n" + pkg_signature.stderr).strip()
pkg_signed = "no signature" not in signature_output.lower()
if manifest["pkg_signed"] != pkg_signed:
    raise SystemExit(f"manifest pkg_signed mismatch: expected {pkg_signed}, got {manifest['pkg_signed']}")

if pkg_signed:
    authority = ""
    for line in signature_output.splitlines():
        stripped = line.strip()
        if stripped.startswith("1. "):
            authority = stripped.split("1. ", 1)[1]
            break
    if manifest["pkg_signing_authority"] != authority:
        raise SystemExit(
            f"manifest pkg_signing_authority mismatch: expected {authority}, got {manifest['pkg_signing_authority']}"
        )
else:
    if manifest["pkg_signing_authority"]:
        raise SystemExit("manifest signing metadata should be empty for an unsigned package")

if manifest.get("artifact_notarized"):
    stapler = subprocess.run(
        ["xcrun", "stapler", "validate", str(pkg_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    stapler_output = (stapler.stdout + "\n" + stapler.stderr).strip()
    if stapler.returncode != 0:
        raise SystemExit(f"stapler validate failed: {stapler_output}")

print("artifact ok")
print(f"PKG: {pkg_path.name}")
print(f"SHA256: {actual_sha}")
print(f"Bundle ID: {manifest['bundle_id']}")
print(f"Build: {manifest['build_version']} ({manifest['build_number']}) {manifest['build_channel']}")
print(f"Timestamp: {manifest['build_timestamp']}")
print(f"Installer UI: {manifest.get('installer_ui', 'component-package')}")
print(f"Installer welcome art: {'yes' if manifest.get('installer_welcome_art') else 'no'}")
print(f"App signed: {'yes' if app_signed else 'no'}")
print(f"PKG signed: {'yes' if pkg_signed else 'no'}")
print(f"Artifact notarized: {'yes' if manifest.get('artifact_notarized') else 'no'}")
PY
