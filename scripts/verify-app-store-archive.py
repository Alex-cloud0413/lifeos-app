#!/usr/bin/env python3
"""Inspect the actual artifact, not just the project build settings."""
import plistlib
import subprocess
import sys
from pathlib import Path

archive, platform = Path(sys.argv[1]), sys.argv[2]
unsigned = "--unsigned" in sys.argv[3:]
development_signature = "--development-signature" in sys.argv[3:]
apps = [archive] if archive.suffix == ".app" else list((archive / "Products/Applications").glob("*.app"))
if len(apps) != 1:
    raise SystemExit("Expected exactly one archived application")
app = apps[0]
root = app / "Contents" if platform == "macos" else app
info = plistlib.loads((root / "Info.plist").read_bytes())
assert info["LifeOSCloudEnvironment"] == "Production", "Wrong data environment"
assert info["ITSAppUsesNonExemptEncryption"] is False
for key in ("CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString", "LifeOSCloudContainer"):
    assert info[key] and "$(" not in info[key], f"Unexpanded {key}"
manifest = root / ("Resources/PrivacyInfo.xcprivacy" if platform == "macos" else "PrivacyInfo.xcprivacy")
assert manifest.exists(), "Missing main app privacy manifest"
privacy = plistlib.loads(manifest.read_bytes())
assert privacy["NSPrivacyTracking"] is False
if platform == "ios":
    extensions = list((app / "PlugIns").glob("*.appex"))
    assert len(extensions) == 1, "Missing share extension"
    ext_info = plistlib.loads((extensions[0] / "Info.plist").read_bytes())
    assert ext_info["CFBundleVersion"] == info["CFBundleVersion"]
    assert ext_info["CFBundleShortVersionString"] == info["CFBundleShortVersionString"]
    assert (extensions[0] / "PrivacyInfo.xcprivacy").exists(), "Missing extension privacy manifest"
if not unsigned:
    assert not info["CFBundleIdentifier"].startswith("com.example."), "Placeholder bundle ID"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)], capture_output=True, check=True)
    entitlements = plistlib.loads(result.stdout)
    assert entitlements["com.apple.developer.icloud-container-environment"] == "Production"
    assert info["LifeOSCloudContainer"] in entitlements["com.apple.developer.icloud-container-identifiers"]
    aps_key = "com.apple.developer.aps-environment" if platform == "macos" else "aps-environment"
    assert entitlements[aps_key] == ("development" if development_signature else "production")
    if not development_signature:
        assert not entitlements.get("get-task-allow", entitlements.get("com.apple.security.get-task-allow", False))
print(f"Verified {platform}: {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), Production; "
      + ("unsigned compile check only" if unsigned else "archive must be re-signed and validated for distribution" if development_signature else "distribution-signed archive, not yet validated by App Store Connect"))
