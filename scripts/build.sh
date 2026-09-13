#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
flavor="${1:-preview}"
if [[ "$flavor" != preview && "$flavor" != cloud ]]; then
  print -u2 'Usage: scripts/build.sh [preview|cloud]'
  exit 2
fi
mkdir -p build
swift build -c release --product lifeos --scratch-path build/swift
cli_dir="$(swift build -c release --show-bin-path --scratch-path build/swift)"
cp "$cli_dir/lifeos" build/lifeos
if [[ "$flavor" == preview ]]; then
  xcodebuild -project Dayline.xcodeproj -scheme Dayline-Mac \
    -configuration Preview -destination 'platform=macOS' \
    -derivedDataPath build/PreviewDerivedData CODE_SIGNING_ALLOWED=NO build
  print "App: $PWD/build/PreviewDerivedData/Build/Products/Preview/Dayline.app"
else
  if [[ ! -f Config/Local.xcconfig ]]; then
    print -u2 'Copy Config/Local.xcconfig.example to Config/Local.xcconfig and configure your Apple team and iCloud identifiers first. See docs/building.md.'
    exit 2
  fi
  xcodebuild -project Dayline.xcodeproj -scheme Dayline-Mac \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath build/CloudDerivedData -allowProvisioningUpdates \
    CODE_SIGN_IDENTITY='Apple Development' build
  print "App: $PWD/build/CloudDerivedData/Build/Products/Release/Dayline.app"
fi
print "CLI: $PWD/build/lifeos"
