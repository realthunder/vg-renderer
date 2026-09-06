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
# Profiles: the same set bgfx bakes for its own embedded shaders. Two of
# them, dxbc (s_5_0) and dxil (s_6_0), need a shaderc built on Windows,
# which is where it can reach D3DCompile and DXC; a Linux run leaves
# those two arrays out of the headers it writes.
#
# That is not cosmetic. bgfx picks Direct3D 11 by default on Windows,
# createEmbeddedShader then finds no entry for the running renderer and
# returns an invalid handle -- and bgfx substitutes program handle 0 for
# an invalid program rather than refusing the draw, so the frame comes
# out drawn by an unrelated program instead of failing loudly. Rebake on
# Windows, or the headers you commit are blind there.

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
                "windows s_5_0 dxbc" \
                "windows s_6_0 dxil" \
                "ios metal mtl"; do
        set -- $prof
        plat=$1; p=$2; suffix=$3
        opt=""
        case "$suffix" in
            mtl|dxbc|dxil) opt="-O 3";;
        esac
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
