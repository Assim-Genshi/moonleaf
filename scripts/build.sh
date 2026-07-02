#!/bin/bash
set -eo pipefail

BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/moonleaf.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RSC_DIR="$CONTENTS_DIR/Resources"
BIN_DIR="$RSC_DIR/bin"
SAVER_BUILD_DIR="${BUILD_DIR}/saver"
SAVER_DIR="${SAVER_BUILD_DIR}/moonleafSaver.saver"
CACHE_DIR=".build-cache"

MP_VER_STRING="v4.0.0"
MP_VER_SHORT_STRING="v4.0"

BUILD_ALL=false
CLEAN=false
for arg in "$@"; do
    if [[ "$arg" == "--all" ]]; then
        BUILD_ALL=true
    elif [[ "$arg" == "--clean" ]]; then
        CLEAN=true
    fi
done

if [[ "$BUILD_ALL" == true ]]; then
    echo ""
    read -p "do you really want to build moonleaf for arm64 and x86_64? it will take longer. (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "cancelled..."
        exit 1
    fi
fi

# get host arch
HOST_ARCH=$(uname -m)
if [[ "$HOST_ARCH" == "arm64" ]]; then
    HOST_TARGET="arm64-apple-macos13.0"
elif [[ "$HOST_ARCH" == "x86_64" ]]; then
    HOST_TARGET="x86_64-apple-macos13.0"
else
    # useless else block
    exit 1
fi

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$REPO_ROOT" || exit 1

# clean build cache if --clean flag is passed
if [[ "$CLEAN" == true ]]; then
    echo "cleaning build cache..."
    rm -rf "$CACHE_DIR" "$BUILD_DIR"
fi

mkdir -p "$MACOS_DIR"
mkdir -p "$RSC_DIR"
mkdir -p "$BIN_DIR"

# -----------------------------------------------
# incremental compilation helpers
# -----------------------------------------------

# Generate an output-file-map.json that tells swiftc where to put
# .o and .swiftdeps files for each source, enabling incremental builds.
generate_file_map() {
    local cache_subdir="$1"
    shift
    local sources=("$@")
    local map_file="$cache_subdir/output-file-map.json"

    {
        echo '{'
        # master swift-dependencies entry (tracks cross-file deps)
        echo '  "": {'
        echo "    \"swift-dependencies\": \"$cache_subdir/master.swiftdeps\""
        echo '  },'

        local count=${#sources[@]}
        local i=0
        for src in "${sources[@]}"; do
            i=$((i + 1))
            # derive a unique name from the full path to avoid collisions
            # e.g. moonleaf/main/BrowseView.swift -> moonleaf_main_BrowseView
            local safe_name
            safe_name=$(echo "$src" | tr '/' '_' | sed 's/\.swift$//')

            echo "  \"$src\": {"
            echo "    \"object\": \"$cache_subdir/${safe_name}.o\","
            echo "    \"swift-dependencies\": \"$cache_subdir/${safe_name}.swiftdeps\""
            if [[ $i -lt $count ]]; then
                echo '  },'
            else
                echo '  }'
            fi
        done

        echo '}'
    } > "$map_file"
}

# Incrementally compile Swift sources, then link into a binary.
#
# Usage:
#   swift_build <target> <cache_subdir> <module_name> <output_binary> \
#       <framework1> <framework2> ... -- <source1.swift> <source2.swift> ...
swift_build() {
    local target="$1"
    local cache_subdir="$2"
    local module_name="$3"
    local output="$4"
    shift 4

    local frameworks=()
    local sources=()
    local past_separator=false
    for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
            past_separator=true
            continue
        fi
        if [[ "$past_separator" == true ]]; then
            sources+=("$arg")
        else
            frameworks+=("-framework" "$arg")
        fi
    done

    mkdir -p "$cache_subdir"

    # generate the output file map for this target + arch
    generate_file_map "$cache_subdir" "${sources[@]}"

    # phase 1: compile (only changed files get recompiled)
    swiftc \
        -suppress-warnings \
        -target "$target" \
        "${frameworks[@]}" \
        -O \
        -incremental \
        -output-file-map "$cache_subdir/output-file-map.json" \
        -module-name "$module_name" \
        -c \
        "${sources[@]}"

    # phase 2: link all object files into the final binary
    local objects=()
    for src in "${sources[@]}"; do
        local safe_name
        safe_name=$(echo "$src" | tr '/' '_' | sed 's/\.swift$//')
        objects+=("$cache_subdir/${safe_name}.o")
    done

    swiftc \
        -target "$target" \
        "${frameworks[@]}" \
        "${objects[@]}" \
        -o "$output"
}

echo ""
echo -e "
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m.\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;59m-\033[0m\033[38;5;145m*\033[0m\033[38;5;102m+\033[0m\033[38;5;59m-\033[0m\033[38;5;17m.\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m.\033[0m\033[38;5;17m.\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m.\033[0m\033[38;5;109m*\033[0m\033[38;5;103m+\033[0m\033[38;5;0m.\033[0m\033[38;5;146m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;66m=\033[0m\033[38;5;0m.\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m.\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;59m:\033[0m\033[38;5;59m:\033[0m\033[38;5;59m:\033[0m\033[38;5;0m.\033[0m\033[38;5;0m.\033[0m\033[38;5;146m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;146m#\033[0m\033[38;5;59m:\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;60m=\033[0m\033[38;5;0m.\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;17m.\033[0m\033[38;5;17m.\033[0m\033[38;5;0m \033[0m\033[38;5;60m-\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;59m-\033[0m\033[38;5;103m+\033[0m\033[38;5;59m:\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;103m+\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;189m%\033[0m\033[38;5;188m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m#\033[0m\033[38;5;0m.\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;60m-\033[0m\033[38;5;146m#\033[0m\033[38;5;146m*\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;189m%\033[0m\033[38;5;182m#\033[0m\033[38;5;146m*\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m#\033[0m\033[38;5;188m%\033[0m\033[38;5;103m*\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;110m*\033[0m\033[38;5;146m*\033[0m\033[38;5;146m*\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;189m%\033[0m\033[38;5;182m#\033[0m\033[38;5;146m*\033[0m\033[38;5;189m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;182m#\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;104m*\033[0m\033[38;5;146m*\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;189m%\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;189m%\033[0m\033[38;5;188m%\033[0m\033[38;5;182m#\033[0m\033[38;5;59m-\033[0m\033[38;5;59m-\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;59m-\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;188m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;189m%\033[0m\033[38;5;146m*\033[0m\033[38;5;182m#\033[0m\033[38;5;189m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;0m.\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;59m-\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;66m=\033[0m\033[38;5;147m#\033[0m\033[38;5;147m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;147m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;189m%\033[0m\033[38;5;188m%\033[0m\033[38;5;146m*\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;66m=\033[0m\033[38;5;60m=\033[0m\033[38;5;110m*\033[0m\033[38;5;146m#\033[0m\033[38;5;59m-\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;59m-\033[0m\033[38;5;0m \033[0m\033[38;5;59m-\033[0m\033[38;5;146m*\033[0m\033[38;5;147m#\033[0m\033[38;5;147m#\033[0m\033[38;5;147m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;189m%\033[0m\033[38;5;146m#\033[0m\033[38;5;146m#\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;188m%\033[0m\033[38;5;147m#\033[0m\033[38;5;147m#\033[0m\033[38;5;110m*\033[0m\033[38;5;59m:\033[0m\033[38;5;59m-\033[0m\033[38;5;59m-\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m.\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;59m-\033[0m\033[38;5;103m*\033[0m\033[38;5;146m#\033[0m\033[38;5;153m#\033[0m\033[38;5;153m#\033[0m\033[38;5;153m#\033[0m\033[38;5;153m#\033[0m\033[38;5;153m#\033[0m\033[38;5;188m%\033[0m\033[38;5;189m%\033[0m\033[38;5;182m#\033[0m\033[38;5;146m*\033[0m\033[38;5;189m%\033[0m\033[38;5;188m%\033[0m\033[38;5;146m#\033[0m\033[38;5;103m+\033[0m\033[38;5;59m:\033[0m\033[38;5;59m:\033[0m\033[38;5;17m.\033[0m\033[38;5;60m=\033[0m\033[38;5;59m-\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m.\033[0m\033[38;5;59m:\033[0m\033[38;5;60m=\033[0m\033[38;5;103m+\033[0m\033[38;5;103m+\033[0m\033[38;5;109m*\033[0m\033[38;5;110m*\033[0m\033[38;5;145m*\033[0m\033[38;5;103m*\033[0m\033[38;5;139m*\033[0m\033[38;5;102m+\033[0m\033[38;5;59m:\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;60m=\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m
        \033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;60m-\033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m\033[38;5;0m \033[0m"
echo "####################################################"
echo "        building moonleaf ${MP_VER_STRING} to ${BUILD_DIR}"
echo "####################################################"
echo "macOS $(sw_vers -productVersion), arch: $HOST_ARCH"

# -----------------------------------------------
# moonleaf (Swift, incremental)
# -----------------------------------------------
echo ""
echo "-- moonleaf --"

MOONLEAF_SOURCES=(moonleaf/main/*.swift moonleaf/utils/*.swift)
MOONLEAF_FRAMEWORKS=(SwiftUI AppKit AVKit AVFoundation UniformTypeIdentifiers Combine)

if [[ "$BUILD_ALL" == true ]]; then
    swift_build "x86_64-apple-macos13.0" "$CACHE_DIR/moonleaf-amd64" "moonleaf" \
        "$MACOS_DIR/macpaper_amd64" \
        "${MOONLEAF_FRAMEWORKS[@]}" -- "${MOONLEAF_SOURCES[@]}"
    echo "compiled moonleaf (amd64) (1/3)"

    swift_build "arm64-apple-macos13.0" "$CACHE_DIR/moonleaf-arm64" "moonleaf" \
        "$MACOS_DIR/macpaper_arm64" \
        "${MOONLEAF_FRAMEWORKS[@]}" -- "${MOONLEAF_SOURCES[@]}"
    echo "compiled moonleaf (arm64) (2/3)"

    lipo -create \
        "$MACOS_DIR/macpaper_amd64" \
        "$MACOS_DIR/macpaper_arm64" \
        -o "$MACOS_DIR/moonleaf"

    echo "compiled moonleaf (universal) (3/3)"
    rm "$MACOS_DIR/macpaper_amd64" "$MACOS_DIR/macpaper_arm64"
else
    swift_build "$HOST_TARGET" "$CACHE_DIR/moonleaf-$HOST_ARCH" "moonleaf" \
        "$MACOS_DIR/moonleaf" \
        "${MOONLEAF_FRAMEWORKS[@]}" -- "${MOONLEAF_SOURCES[@]}"
    echo "compiled moonleaf ($HOST_ARCH)"
fi
echo ""

# -----------------------------------------------
# glasswp (Swift, incremental)
# -----------------------------------------------
echo ""
echo "-- moonleaf Animated Wallpaper Engine (glasswp) --"

GLASSWP_SOURCES=(glasswp/glasswp.swift)
GLASSWP_FRAMEWORKS=(AppKit AVFoundation MediaToolbox Accelerate)

if [[ "$BUILD_ALL" == true ]]; then
    swift_build "x86_64-apple-macos13.0" "$CACHE_DIR/glasswp-amd64" "glasswp" \
        "$MACOS_DIR/glasswp_amd64" \
        "${GLASSWP_FRAMEWORKS[@]}" -- "${GLASSWP_SOURCES[@]}"
    echo "compiled glasswp (amd64) (1/3)"

    swift_build "arm64-apple-macos13.0" "$CACHE_DIR/glasswp-arm64" "glasswp" \
        "$MACOS_DIR/glasswp_arm64" \
        "${GLASSWP_FRAMEWORKS[@]}" -- "${GLASSWP_SOURCES[@]}"
    echo "compiled glasswp (arm64) (2/3)"

    lipo -create "$MACOS_DIR/glasswp_amd64" "$MACOS_DIR/glasswp_arm64" \
        -o "$BIN_DIR/glasswp"

    echo "compiled glasswp (universal) (3/3)"
    rm "$MACOS_DIR/glasswp_amd64" "$MACOS_DIR/glasswp_arm64"
else
    swift_build "$HOST_TARGET" "$CACHE_DIR/glasswp-$HOST_ARCH" "glasswp" \
        "$BIN_DIR/glasswp" \
        "${GLASSWP_FRAMEWORKS[@]}" -- "${GLASSWP_SOURCES[@]}"
    echo "compiled glasswp ($HOST_ARCH)"
fi
echo ""

# -----------------------------------------------
# moonleaf-bin (C, single file — no incremental needed)
# -----------------------------------------------
echo "-- moonleaf-bin --"

if [[ "$BUILD_ALL" == true ]]; then
    gcc -target x86_64-apple-macos13.0 \
        moonleaf/obj/moonleaf.c -o "$MACOS_DIR/moonleaf-bin_amd64"

    gcc -target arm64-apple-macos13.0 \
        moonleaf/obj/moonleaf.c -o "$MACOS_DIR/moonleaf-bin_arm64"

    lipo -create "$MACOS_DIR/moonleaf-bin_amd64" "$MACOS_DIR/moonleaf-bin_arm64" \
        -o "$MACOS_DIR/moonleaf-bin"

    echo "compiled moonleaf-bin (universal)"
    rm "$MACOS_DIR/moonleaf-bin_amd64" "$MACOS_DIR/moonleaf-bin_arm64"
else
    gcc -target "$HOST_TARGET" \
        moonleaf/obj/moonleaf.c -o "$MACOS_DIR/moonleaf-bin"

    echo "compiled moonleaf-bin ($HOST_ARCH)"
fi
echo ""

# -----------------------------------------------
# bundle app resources
# -----------------------------------------------
echo "adding moonleaf Info.plist"
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>moonleaf</string>
    <key>CFBundleIdentifier</key>
    <string>com.naomisphere.macpaper</string>
    <key>CFBundleName</key>
    <string>moonleaf</string>
    <key>CFBundleDisplayName</key>
    <string>moonleaf</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MP_VER_SHORT_STRING}</string>
    <key>CFBundleVersion</key>
    <string>${MP_VER_STRING}</string>
    <key>CFBundleIconFile</key>
    <string>moonleaf.icns</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>ATSApplicationFontsPath</key>
    <string>.</string>
</dict>
</plist>
EOF

echo ""
echo "-- bundling app resources --"
cp artwork/icns/moonleaf/moonleaf.icns "$RSC_DIR" 2>/dev/null || true
cp artwork/png/moonleaf.png "${RSC_DIR}/.moonleaf_logo.png" 2>/dev/null || true
cp artwork/png/moonleaf.png "${RSC_DIR}/StatusBarIcon.png" 2>/dev/null || true
cp img/png/kofi_symbol.png "$RSC_DIR/.kofi.png" 2>/dev/null || true

gzip -dc moonleaf/resources/bin/wallpaper.gz > "moonleaf/resources/bin/wallpaper" 2>/dev/null
chmod +x "moonleaf/resources/bin/wallpaper" 2>/dev/null || true
cp -R moonleaf/resources/* "$RSC_DIR/" 2>/dev/null || true
rm -f "$RSC_DIR/bin/wallpaper.gz" 2>/dev/null
chmod +x "$BIN_DIR/wallpaper" 2>/dev/null || true

echo "adding localization strings"
cp -r lang/*.lproj "$RSC_DIR"

if [[ -d "moonleaf/Assets.xcassets" ]]; then
    echo "compiling asset catalog..."
    actool moonleaf/Assets.xcassets \
        --compile "$RSC_DIR" \
        --platform macosx \
        --minimum-deployment-target 13.0 \
        --output-format xml1 > /dev/null
fi


echo ""
echo "done! moonleaf ${MP_VER_STRING} is at ${BUILD_DIR}/moonleaf.app"
echo "glasswp installed to: $BIN_DIR/glasswp"
echo ""
