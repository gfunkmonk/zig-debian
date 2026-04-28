#!/usr/bin/env bash
# Build zig (meta) + zig-0 (transitional) + zig-stable .deb packages for
# Ubuntu distros.  Used for dev/nightly builds that still ship the deprecated
# zig-0 compatibility package alongside the stable one.
# Usage: ./build_zig_ubuntu.sh <zig_version> <build_version> [architecture]
# Example: ./build_zig_ubuntu.sh 0.16.0-dev.2682+02142a54d 1
# Example: ./build_zig_ubuntu.sh 0.16.0-dev.2682+02142a54d 1 arm64
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
DISTROS=(jammy noble questing)

build_dist() {
    local dist=$1 build_arch=$2 zig_arch=$3
    local full_ver="${ZIG_VERSION}-${BUILD_VERSION}+${dist}_${build_arch}_ubu"
    local cid

    echo "  [$dist] Building zig + zig-0 + zig-stable ${full_ver}..."

    # --- meta package (zig) --------------------------------------------------
    docker build . -f meta_Dockerfile.ubu -t "zig-ubuntu-${dist}-${build_arch}" \
        --build-arg ZIG_VERSION="$ZIG_VERSION" \
        --build-arg UBUNTU_DIST="$dist" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$full_ver" \
        --build-arg ARCH="$build_arch" \
        || { echo "❌ [$dist] Failed meta build"; return 1; }
    cid="$(docker create "zig-ubuntu-${dist}-${build_arch}")"
    docker_copy "$cid" "/zig_${full_ver}.deb" "."

    # --- zig-0 transitional (deprecated) package ----------------------------
    # BUG WAS HERE: original code used image name "zig-ubuntu-stable-*" and
    # tried to copy /zig-stable_*.deb from zero_Dockerfile.ubu, which only
    # produces /zig-zero_${FULL_VERSION}.deb.
    docker build . -f zero_Dockerfile.ubu -t "zig-ubuntu-zero-${dist}-${build_arch}" \
        --build-arg ZIG_VERSION="$ZIG_VERSION" \
        --build-arg UBUNTU_DIST="$dist" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$full_ver" \
        --build-arg ARCH="$build_arch" \
        --build-arg ZIG_ARCH="$zig_arch" \
        || { echo "❌ [$dist] Failed zero build"; return 1; }
    cid="$(docker create "zig-ubuntu-zero-${dist}-${build_arch}")"
    docker_copy "$cid" "/zig-zero_${full_ver}.deb" "."

    # --- zig-stable package --------------------------------------------------
    docker build . -f stable_Dockerfile.ubu -t "zig-ubuntu-stable-${dist}-${build_arch}" \
        --build-arg ZIG_VERSION="$ZIG_VERSION" \
        --build-arg UBUNTU_DIST="$dist" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$full_ver" \
        --build-arg ARCH="$build_arch" \
        --build-arg ZIG_ARCH="$zig_arch" \
        || { echo "❌ [$dist] Failed stable build"; return 1; }
    cid="$(docker create "zig-ubuntu-stable-${dist}-${build_arch}")"
    docker_copy "$cid" "/zig-stable_${full_ver}.deb" "."

    echo "  ✅ [$dist] Done"
}

run_builds "zig (Ubuntu dev)" "zig_*.deb" "zig-zero_*.deb" "zig-stable_*.deb"