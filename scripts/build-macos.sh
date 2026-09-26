#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
xcodegen generate --spec project.yml

container="${MACOS_XCODE_CONTAINER:-}"
if [[ -z "$container" ]]; then
  container="$(find . -maxdepth 3 -type d -name '*.xcworkspace' ! -path '*/Pods/*' ! -path '*.xcodeproj/*' -print -quit)"
fi
if [[ -z "$container" ]]; then
  container="$(find . -maxdepth 3 -type d -name '*.xcodeproj' ! -path '*/Pods/*' -print -quit)"
fi
if [[ -z "$container" || ! -d "$container" ]]; then
  echo "No Xcode workspace or project found" >&2
  exit 1
fi
case "$container" in
  *.xcworkspace) container_flag="-workspace" ;;
  *.xcodeproj) container_flag="-project" ;;
  *) echo "Invalid Xcode container: $container" >&2; exit 1 ;;
esac

xcodebuild -list -json "$container_flag" "$container" > build/schemes.json
scheme="${MACOS_SCHEME:-}"
if [[ -z "$scheme" ]]; then
  scheme="$(python3 -c 'import json; d=json.load(open("build/schemes.json")); print(next(iter(d.get("project",d.get("workspace",{})).get("schemes",[])), ""))')"
fi
if [[ -z "$scheme" ]]; then
  echo "No Xcode scheme found. Share the scheme or set MACOS_SCHEME." >&2
  exit 1
fi

xcodebuild "$container_flag" "$container" -scheme "$scheme" -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$root/DerivedData" \
  "ARCHS=$(uname -m)" ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

app_name="${MACOS_APP_NAME:-MochiDrop}"
app="$root/DerivedData/Build/Products/Release/$app_name.app"
if [[ ! -d "$app" ]]; then
  app="$(find "$root/DerivedData/Build/Products/Release" -maxdepth 1 -type d -name '*.app' -print -quit)"
fi
if [[ -z "$app" || ! -d "$app" ]]; then
  echo "Release .app not found" >&2
  exit 1
fi

mkdir -p "$app/Contents/Resources/tools"
cp "$root/build/tools/yt-dlp" "$root/build/tools/gallery-dl" \
  "$root/build/tools/mochidrop-torrent" "$app/Contents/Resources/tools/"
chmod +x "$app/Contents/Resources/tools/"*
mkdir -p "$app/Contents/Resources/licenses"
cp "$root/third_party/yt-dlp-LICENSE.txt" "$root/third_party/gallery-dl-LICENSE.txt" \
  "$root/third_party/rqbit-LICENSE.txt" \
  "$app/Contents/Resources/licenses/"
for binary in "$app/Contents/Resources/tools/"*; do
  codesign --force --sign - "$binary"
done
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

arch="$(uname -m)"
out="$root/build/artifacts"
mkdir -p "$out"
ditto "$app" "$out/$(basename "$app")"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/MochiDrop-macOS-$arch.zip"
stage="$root/build/dmg-stage"
mkdir -p "$stage"
ditto "$app" "$stage/$(basename "$app")"
ln -sfn /Applications "$stage/Applications"
hdiutil create -volname MochiDrop -srcfolder "$stage" -ov -format UDZO "$out/MochiDrop-macOS-$arch.dmg"
hdiutil verify "$out/MochiDrop-macOS-$arch.dmg"
test -x "$app/Contents/MacOS/MochiDrop"
test -x "$app/Contents/Resources/tools/mochidrop-torrent"
plutil -lint "$app/Contents/Info.plist"
shasum -a 256 "$out"/*.zip "$out"/*.dmg
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'ARTIFACT_DIR=%s\n' "$out" >> "$GITHUB_ENV"
fi
