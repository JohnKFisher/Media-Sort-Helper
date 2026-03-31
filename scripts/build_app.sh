#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Media Sort Helper.app"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
INFO_PLIST_PATH="$ROOT_DIR/Resources/Info.plist"
VERSION_STATE_DIR="$ROOT_DIR/.build"
VERSION_STATE_FILE="$VERSION_STATE_DIR/version-build-state"
MINIMUM_MACOS_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST_PATH")"
DEFAULT_TARGET_TRIPLES="arm64-apple-macosx${MINIMUM_MACOS_VERSION} x86_64-apple-macosx${MINIMUM_MACOS_VERSION}"
TARGET_TRIPLES_STRING="${MEDIA_SORT_HELPER_TARGET_TRIPLES:-$DEFAULT_TARGET_TRIPLES}"
declare -a TARGET_TRIPLES=()

while IFS= read -r triple; do
    if [[ -n "$triple" ]]; then
        TARGET_TRIPLES+=("$triple")
    fi
done < <(printf '%s\n' "$TARGET_TRIPLES_STRING" | tr ' ' '\n')

if [[ "${#TARGET_TRIPLES[@]}" -eq 0 ]]; then
    echo "No target triples configured. Set MEDIA_SORT_HELPER_TARGET_TRIPLES to one or more macOS Swift target triples." >&2
    exit 1
fi

current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_PATH")"
current_source_hash="$(
    {
        find "$ROOT_DIR/Sources" -type f
        find "$ROOT_DIR/Resources" -type f ! -name 'Info.plist'
        echo "$ROOT_DIR/Package.swift"
        echo "$ROOT_DIR/scripts/build_app.sh"
    } | LC_ALL=C sort | while IFS= read -r file_path; do
        shasum "$file_path"
    done | shasum | awk '{print $1}'
)"

last_version=""
last_build="0"
last_hash=""
if [[ -f "$VERSION_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$VERSION_STATE_FILE"
    last_version="${VERSION:-}"
    last_build="${BUILD:-0}"
    last_hash="${SOURCE_HASH:-}"
fi

if [[ "$current_version" == "$last_version" && "$last_build" =~ ^[0-9]+$ ]]; then
    if [[ "$current_source_hash" == "$last_hash" ]]; then
        next_build="$last_build"
    else
        next_build="$((last_build + 1))"
    fi
else
    next_build="1"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next_build" "$INFO_PLIST_PATH"
mkdir -p "$VERSION_STATE_DIR"
cat >"$VERSION_STATE_FILE" <<EOF
VERSION=$current_version
BUILD=$next_build
SOURCE_HASH=$current_source_hash
EOF

echo "Preparing $APP_NAME version $current_version build $next_build..."
echo "Target triples: ${TARGET_TRIPLES[*]}"

ICONSET_SOURCE_DIR="$ROOT_DIR/Sources/MediaSortHelper/Assets.xcassets/AppIcon.appiconset"
ICONSET_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mediasort-icon.XXXXXX")"
ICONSET_TMP_DIR="$ICONSET_TMP_ROOT/AppIcon.iconset"
UNIVERSAL_BINARY_PATH="$ICONSET_TMP_ROOT/MediaSortHelper"
declare -a EXECUTABLE_PATHS=()
RESOURCE_BUNDLE_PATH=""

cleanup() {
    rm -rf "$ICONSET_TMP_ROOT"
}
trap cleanup EXIT

if [[ ! -d "$ICONSET_SOURCE_DIR" ]]; then
    echo "Missing app icon source set at: $ICONSET_SOURCE_DIR" >&2
    exit 1
fi

for target_triple in "${TARGET_TRIPLES[@]}"; do
    echo "Building release binary for $target_triple..."
    swift build -c release --triple "$target_triple" >/dev/null

    build_bin_dir="$(swift build -c release --triple "$target_triple" --show-bin-path)"
    executable_path="$build_bin_dir/MediaSortHelper"
    resource_bundle_candidate="$build_bin_dir/MediaSortHelper_MediaSortHelper.bundle"

    if [[ ! -f "$executable_path" ]]; then
        echo "Missing executable at: $executable_path" >&2
        exit 1
    fi

    if [[ ! -d "$resource_bundle_candidate" ]]; then
        echo "Missing resource bundle at: $resource_bundle_candidate" >&2
        exit 1
    fi

    EXECUTABLE_PATHS+=("$executable_path")

    if [[ -z "$RESOURCE_BUNDLE_PATH" ]]; then
        RESOURCE_BUNDLE_PATH="$resource_bundle_candidate"
    fi
done

echo "Creating app bundle at: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

if [[ "${#EXECUTABLE_PATHS[@]}" -eq 1 ]]; then
    cp "${EXECUTABLE_PATHS[0]}" "$APP_DIR/Contents/MacOS/MediaSortHelper"
else
    echo "Merging architecture slices into a universal app binary..."
    lipo -create "${EXECUTABLE_PATHS[@]}" -output "$UNIVERSAL_BINARY_PATH"
    cp "$UNIVERSAL_BINARY_PATH" "$APP_DIR/Contents/MacOS/MediaSortHelper"
fi

cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp -R "$RESOURCE_BUNDLE_PATH" "$APP_DIR/Contents/Resources/"
chmod +x "$APP_DIR/Contents/MacOS/MediaSortHelper"

echo "Generating AppIcon.icns..."
mkdir -p "$ICONSET_TMP_DIR"
cp "$ICONSET_SOURCE_DIR"/icon_*.png "$ICONSET_TMP_DIR/"
iconutil -c icns "$ICONSET_TMP_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "Code-signing app bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "Done."
echo "App: $APP_DIR"
echo "Architectures: $(lipo -archs "$APP_DIR/Contents/MacOS/MediaSortHelper")"
echo "Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
echo "Build: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")"
