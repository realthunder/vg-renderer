#!/bin/sh
# Regenerate the embedded shader headers (*.bin.h) from the .sc sources
# with the bgfx shaderc this tree actually builds against.
#
# The upstream makefile includes bgfx/scripts/shader-embeded.mk by a
# relative path that assumes vg-renderer sits next to a bgfx checkout;
# inside the FreeCAD tree the bgfx submodule is nested one level deeper,
# so this script replays the same recipe with explicit paths instead.
#
# Usage:  ./rebake.sh <path-to-shaderc> <path-to-bgfx-src-dir>
# e.g. from a FreeCAD build tree:
#   cd src/3rdParty/vg-renderer/src/shaders
#   ./rebake.sh ../../../../../build/<cfg>/src/3rdParty/bgfx/cmake/bgfx/shaderc \
#               ../../../bgfx/bgfx/src
#
# Profiles: the same set bgfx bakes for its own embedded shaders, minus
# the two that need a Windows host compiler (dxbc s_5_0, dxil s_6_0).
# A consumer on any platform where bgfx's embedded_shader.h expects
# those arrays must define BGFX_PLATFORM_SUPPORTS_DXBC=0 (and _DXIL=0)
# before including the headers; on Linux FreeCAD's CMake does that, and
# its bgfx backend never selects Direct3D anyway.

set -e

SHADERC=$1
BGFXSRC=$2
if [ -z "$SHADERC" ] || [ -z "$BGFXSRC" ]; then
    echo "usage: $0 <shaderc> <bgfx-src-dir>" >&2
    exit 1
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

bake() { # <type> <base>
    type=$1; base=$2
    out=$base.bin.h
    : > "$out"
    for prof in "linux 120 glsl" \
                "android 100_es essl" \
                "linux spirv spv" \
                "linux wgsl wgsl" \
                "ios metal mtl"; do
        set -- $prof
        plat=$1; p=$2; suffix=$3
        opt=""
        [ "$suffix" = mtl ] && opt="-O 3"
        "$SHADERC" --type "$type" --platform "$plat" -p "$p" $opt \
            -i "$BGFXSRC" -f "$base.sc" -o "$TMP" --bin2c "${base}_${suffix}"
        cat "$TMP" >> "$out"
    done
    printf 'extern const uint8_t* %s_pssl;\n' "$base" >> "$out"
    printf 'extern const uint32_t %s_pssl_size;\n' "$base" >> "$out"
    echo "[$out]"
}

for f in vs_*.sc; do
    bake vertex "${f%.sc}"
done
for f in fs_*.sc; do
    bake fragment "${f%.sc}"
done
