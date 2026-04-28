#!/usr/bin/env bash
# Build zig-oldstable .deb packages for Debian distros.
# Usage: ./build_zig_oldstable_debian.sh <zig_version> <build_version> [architecture]
# Example: ./build_zig_oldstable_debian.sh 0.14.0 1
# Example: ./build_zig_oldstable_debian.sh 0.14.0 1 arm64
set -euo pipefail

ZIG_VERSION=${1:?"Usage: $0 <zig_version> <build_version> [architecture]
Example: $0 0.14.0 1 arm64
Example: $0 0.14.0 1 all
Supported architectures: amd64 arm64 armel riscv64 ppc64el i386 loong64 s390x all"}
BUILD_VERSION=${2:?"Usage: $0 <zig_version> <build_version> [architecture]"}
ARCH=${3:-all}

# shellcheck source=build_common.sh
source "$(dirname "$0")/build_common.sh"

MAN_VARIANT="oldstable"
DISTROS=(bookworm trixie forky sid)

build_dist() {
    local dist=$1 build_arch=$2 zig_arch=$3
    local full_ver="${ZIG_VERSION}-${BUILD_VERSION}+${dist}_${build_arch}"
    local cid

    echo "  [$dist] Building zig-oldstable ${full_ver}..."

    docker build . -t "zig-oldstable-${dist}-${build_arch}" \
        --build-arg ZIG_VERSION="$ZIG_VERSION" \
        --build-arg DEBIAN_DIST="$dist" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$full_ver" \
        --build-arg ARCH="$build_arch" \
        --build-arg ZIG_ARCH="$zig_arch" \
        -f oldstable_Dockerfile \
        || { echo "❌ [$dist] Failed oldstable build"; return 1; }
    cid="$(docker create "zig-oldstable-${dist}-${build_arch}")"
    docker_copy "$cid" "/zig-oldstable_${full_ver}.deb" "."

    echo "  ✅ [$dist] Done"
}

run_builds "zig-oldstable (Debian)" "zig-oldstable_*.deb"