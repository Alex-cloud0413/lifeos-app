#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
platform="${1:-}"
mode="${2:-}"
if [[ "$platform" != macos && "$platform" != ios ]] || [[ -n "$mode" && "$mode" != --unsigned ]]; then
  print -u2 'Usage: zsh scripts/archive-app-store.sh [macos|ios] [--unsigned]'
  exit 2
fi
if [[ "$mode" != --unsigned && ! -f Config/Local.xcconfig ]]; then
  print -u2 'Set your Apple team and identifiers in Config/Local.xcconfig first. See docs/app-store.md.'
  exit 2
fi
if [[ "$platform" == macos ]]; then
  scheme=Dayline-Mac
  destination='generic/platform=macOS'
else
  scheme=Dayline-iOS
  destination='generic/platform=iOS'
fi
archive="build/AppStore-$platform${mode:+-unsigned}.xcarchive"
if [[ -e "$archive" ]]; then
  print -u2 "Archive already exists: $archive. Move it aside before building a new candidate."
  exit 2
fi
# Archives use automatic development signing; distribution re-signs the artifact.
signing=(-allowProvisioningUpdates 'CODE_SIGN_IDENTITY=Apple Development' LIFEOS_PUSH_ENVIRONMENT=development)
if [[ "$mode" == --unsigned ]]; then
  signing=(CODE_SIGNING_ALLOWED=NO)
fi
xcodebuild -project Dayline.xcodeproj -scheme "$scheme" -configuration Release \
  -xcconfig Config/AppStore.xcconfig -destination "$destination" \
  -derivedDataPath "build/AppStoreDerived-$platform" -archivePath "$archive" \
  "${signing[@]}" archive
if [[ "$mode" == --unsigned ]]; then
  python3 scripts/verify-app-store-archive.py "$archive" "$platform" --unsigned
else
  python3 scripts/verify-app-store-archive.py "$archive" "$platform" --development-signature
fi
print "Archive: $PWD/$archive"
print 'No upload or App Review submission has been performed.'
