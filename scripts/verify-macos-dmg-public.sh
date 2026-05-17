#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="$ROOT_DIR/dist/OnlyMacs-public.dmg"
MANIFEST_PATH="$ROOT_DIR/dist/OnlyMacs-public-manifest.json"
CHECKSUM_PATH="$ROOT_DIR/dist/OnlyMacs-public.sha256"

for required_path in "$DMG_PATH" "$MANIFEST_PATH" "$CHECKSUM_PATH"; do
  if [[ ! -e "$required_path" ]]; then
    echo "missing required artifact: $required_path" >&2
    exit 1
  fi
done

python3 - "$MANIFEST_PATH" "$DMG_PATH" "$CHECKSUM_PATH" <<'PY'
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import os

manifest_path = pathlib.Path(sys.argv[1])
dmg_path = pathlib.Path(sys.argv[2])
checksum_path = pathlib.Path(sys.argv[3])

manifest = json.loads(manifest_path.read_text())
checksum_line = checksum_path.read_text().strip()
expected_default_coordinator_url = os.environ.get("ONLYMACS_EXPECT_DEFAULT_COORDINATOR_URL", "").strip()

if not checksum_line:
    raise SystemExit("checksum file is empty")

actual_sha = hashlib.sha256(dmg_path.read_bytes()).hexdigest()
expected_sha = manifest["artifact_sha256"]

if actual_sha != expected_sha:
    raise SystemExit(f"manifest SHA mismatch: expected {expected_sha}, got {actual_sha}")

checksum_sha = checksum_line.split()[0]
if checksum_sha != actual_sha:
    raise SystemExit(f"checksum file SHA mismatch: expected {actual_sha}, got {checksum_sha}")

if manifest["artifact_bytes"] != dmg_path.stat().st_size:
    raise SystemExit("manifest artifact_bytes does not match actual DMG size")

dmg_signed = False
dmg_codesign_stderr = ""
dmg_verify = subprocess.run(
    ["codesign", "--verify", str(dmg_path)],
    capture_output=True,
    text=True,
)
dmg_signed = dmg_verify.returncode == 0
if dmg_signed:
    dmg_codesign = subprocess.run(
        ["codesign", "-dv", "--verbose=4", str(dmg_path)],
        capture_output=True,
        text=True,
        check=True,
    )
    dmg_codesign_stderr = dmg_codesign.stderr

with tempfile.TemporaryDirectory() as tmpdir:
    mountpoint = pathlib.Path(tmpdir) / "mount"
    mountpoint.mkdir()
    app_signed = False
    codesign_stderr = ""
    attach = subprocess.run(
        ["hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", str(mountpoint), str(dmg_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if attach.returncode != 0:
        raise SystemExit(f"dmg attach failed: {(attach.stdout + attach.stderr).strip()}")

    try:
        info_plist_path = mountpoint / "OnlyMacs.app" / "Contents" / "Info.plist"
        if not info_plist_path.exists():
            raise SystemExit("mounted DMG missing OnlyMacs.app/Contents/Info.plist")

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
                "mounted app default coordinator mismatch: "
                f"expected {expected_default_coordinator_url}, got {expected_pairs['default_coordinator_url']}"
            )

        mounted_app_path = info_plist_path.parent.parent
        verify = subprocess.run(
            ["codesign", "--verify", "--deep", "--strict", str(mounted_app_path)],
            capture_output=True,
            text=True,
        )
        app_signed = verify.returncode == 0
        if app_signed:
            codesign = subprocess.run(
                ["codesign", "-dv", "--verbose=4", str(mounted_app_path)],
                capture_output=True,
                text=True,
                check=True,
            )
            codesign_stderr = codesign.stderr
    finally:
        detach = subprocess.run(
            ["hdiutil", "detach", str(mountpoint)],
            capture_output=True,
            text=True,
            check=False,
        )
        if detach.returncode != 0:
            raise SystemExit(f"dmg detach failed: {(detach.stdout + detach.stderr).strip()}")

if manifest["app_signed"] != app_signed:
    raise SystemExit(f"manifest app_signed mismatch: expected {app_signed}, got {manifest['app_signed']}")

if manifest.get("artifact_signed", False) != dmg_signed:
    raise SystemExit(f"manifest artifact_signed mismatch: expected {dmg_signed}, got {manifest.get('artifact_signed')}")

if dmg_signed:
    dmg_authority = ""
    dmg_team_id = ""
    for line in dmg_codesign_stderr.splitlines():
        if line.startswith("Authority=") and not dmg_authority:
            dmg_authority = line.split("=", 1)[1]
        if line.startswith("TeamIdentifier="):
            dmg_team_id = line.split("=", 1)[1]
    if manifest.get("artifact_signing_authority", "") != dmg_authority:
        raise SystemExit(
            f"manifest artifact_signing_authority mismatch: expected {dmg_authority}, got {manifest.get('artifact_signing_authority', '')}"
        )
    if manifest.get("artifact_signing_team_id", "") != dmg_team_id:
        raise SystemExit(
            f"manifest artifact_signing_team_id mismatch: expected {dmg_team_id}, got {manifest.get('artifact_signing_team_id', '')}"
        )

if app_signed:
    authority = ""
    team_id = ""
    for line in codesign_stderr.splitlines():
        if line.startswith("Authority=") and not authority:
            authority = line.split("=", 1)[1]
        if line.startswith("TeamIdentifier="):
            team_id = line.split("=", 1)[1]
    if manifest["app_signing_authority"] != authority:
        raise SystemExit(f"manifest app_signing_authority mismatch: expected {authority}, got {manifest['app_signing_authority']}")
    if manifest["app_signing_team_id"] != team_id:
        raise SystemExit(f"manifest app_signing_team_id mismatch: expected {team_id}, got {manifest['app_signing_team_id']}")
else:
    if manifest["app_signing_authority"] or manifest["app_signing_team_id"]:
        raise SystemExit("manifest signing metadata should be empty for an unsigned app")

print("artifact ok")
print(f"DMG: {dmg_path.name}")
print(f"SHA256: {actual_sha}")
print(f"Bundle ID: {manifest['bundle_id']}")
print(f"Build: {manifest['build_version']} ({manifest['build_number']}) {manifest['build_channel']}")
print(f"Timestamp: {manifest['build_timestamp']}")
print(f"App signed: {'yes' if app_signed else 'no'}")
print(f"DMG signed: {'yes' if dmg_signed else 'no'}")
print(f"Artifact notarized: {'yes' if manifest.get('artifact_notarized') else 'no'}")
PY
