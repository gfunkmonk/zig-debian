#!/usr/bin/env bash
# Build zig (meta) + zig-0 (transitional) + zig-stable .deb packages for
# Debian distros.  Used for dev/nightly builds that still ship the deprecated
# zig-0 compatibility package alongside the stable one.
# Usage: ./build_zig_debian.sh <zig_version> <build_version> [architecture]
# Example: ./build_zig_debian.sh 0.16.0-dev.2682+02142a54d 1
# Example: ./build_zig_debian.sh 0.16.0-dev.2682+02142a54d 1 arm64
set -euo pipefail

ZIG_VERSION=${1:?"Usage: $0 <zig_version> <build_version> [architecture]
Example: $0 0.16.0-dev.2682+02142a54d 1 arm64
Example: $0 0.16.0-dev.2682+02142a54d 1 all
Supported architectures: amd64 arm64 armel riscv64 ppc64el i386 loong64 s390x all"}
BUILD_VERSION=${2:?"Usage: $0 <zig_version> <build_version> [architecture]"}
ARCH=${3:-all}

# shellcheck source=build_common.sh
source "$(dirname "$0")/build_common.sh"

MAN_VARIANT="stable"
DISTROS=(bookworm trixie forky sid)

build_dist() {
    local dist=$1 build_arch=$2 zig_arch=$3
    local full_ver="${ZIG_VERSION}-${BUILD_VERSION}+${dist}_${build_arch}"
    local cid

    echo "  [$dist] Building zig + zig-0 + zig-stable ${full_ver}..."

    # --- meta package (zig) --------------------------------------------------
    docker build . -t "zig-${dist}-${build_arch}" \
        --build-arg ZIG_VERSION="$ZIG_VERSION" \
        --build-arg DEBIAN_DIST="$dist" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$full_ver" \
        --build-arg ARCH="$build_arch" \
        -f meta_Dockerfile \
        || { echo "❌ [$dist] Failed meta build"; return 1; }
    cid="$(docker create "zig-${dist}-${build_arch}")"
    docker_copy "$cid" "/zig_${full_ver}.deb" "."

    # --- zig-0 transitional (deprecated) package ----------------------------
    # BUG WAS HERE: original code used image name "zig-stable-*" and tried to
    # copy /zig-stable_*.deb — a path that does not exist in zero_Dockerfile.
    # zero_Dockerfile outputs /zig-zero_${FULL_VERSION}.deb.
    docker build . -t "zig-zero-${dist}-${build_arch}" \
        --build-arg ZIG_VERSION="$ZIG_VERSION" \
        --build-arg DEBIAN_DIST="$dist" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$full_ver" \
        --build-arg ARCH="$build_arch" \
        --build-arg ZIG_ARCH="$zig_arch" \
        -f zero_Dockerfile \
        || { echo "❌ [$dist] Failed zero build"; return 1; }
    cid="$(docker create "zig-zero-${dist}-${build_arch}")"
    docker_copy "$cid" "/zig-zero_${full_ver}.deb" "."

    # --- zig-stable package --------------------------------------------------
    docker build . -t "zig-stable-${dist}-${build_arch}" \
        --build-arg ZIG_VERSION="$ZIG_VERSION" \
        --build-arg DEBIAN_DIST="$dist" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$full_ver" \
        --build-arg ARCH="$build_arch" \
        --build-arg ZIG_ARCH="$zig_arch" \
        -f stable_Dockerfile \
        || { echo "❌ [$dist] Failed stable build"; return 1; }
    cid="$(docker create "zig-stable-${dist}-${build_arch}")"
    docker_copy "$cid" "/zig-stable_${full_ver}.deb" "."

    echo "  ✅ [$dist] Done"
}

run_builds "zig (Debian dev)" "zig_*.deb" "zig-zero_*.deb" "zig-stable_*.deb"