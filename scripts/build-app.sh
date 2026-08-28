#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
app_path="$project_dir/MeetingAssistant.app"
universal=false

case "${1:-}" in
    "") ;;
    --universal) universal=true ;;
    *)
        print -u2 "Usage: $0 [--universal]"
        exit 2
        ;;
esac

if (( $# > 1 )); then
    print -u2 "Usage: $0 [--universal]"
    exit 2
fi

export DEVELOPER_DIR="$developer_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/cache/swiftpm"

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

typeset -a release_binaries
if [[ "$universal" == true ]]; then
    for architecture in arm64 x86_64; do
        scratch_path="$project_dir/.build/universal/$architecture"
        triple="${architecture}-apple-macosx14.0"
        swift build \
            -c release \
            --disable-sandbox \
            --scratch-path "$scratch_path" \
            --triple "$triple"
        release_binaries+=("$scratch_path/${architecture}-apple-macosx/release/MeetingAssistant")
    done
else
    swift build -c release --disable-sandbox
    release_binaries+=("$project_dir/.build/release/MeetingAssistant")
fi

if [[ -d "$app_path" ]]; then
    rm -rf "$app_path"
fi
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [[ "$universal" == true ]]; then
    lipo -create "${release_binaries[@]}" -output "$app_path/Contents/MacOS/MeetingAssistant"
else
    cp "${release_binaries[1]}" "$app_path/Contents/MacOS/MeetingAssistant"
fi
cp "$project_dir/Packaging/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/Packaging/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"

print "Built $app_path"
