#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
app_path="$project_dir/MeetingAssistant.app"
binary_path="$project_dir/.build/release/MeetingAssistant"

export DEVELOPER_DIR="$developer_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/cache/swiftpm"

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
swift build -c release --disable-sandbox

if [[ -d "$app_path" ]]; then
    rm -rf "$app_path"
fi
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/MeetingAssistant"
cp "$project_dir/Packaging/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/Packaging/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"

print "Built $app_path"
