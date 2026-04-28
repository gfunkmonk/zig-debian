#!/usr/bin/env bash
# Convenience wrapper: build both Debian and Ubuntu packages in one shot.
# Usage: ./build.sh <zig_version> <build_version> [architecture]
# Example: ./build.sh 0.16.0-dev.2682+02142a54d 1
# Example: ./build.sh 0.16.0-dev.2682+02142a54d 1 amd64
set -euo pipefail

ZIG_VERSION=${1:?"Usage: $0 <zig_version> <build_version> [architecture]"}
BUILD_VERSION=${2:?"Usage: $0 <zig_version> <build_version> [architecture]"}
ARCH=${3:-all}

"$(dirname "$0")/build_zig_debian.sh" "$ZIG_VERSION" "$BUILD_VERSION" "$ARCH"
"$(dirname "$0")/build_zig_ubuntu.sh" "$ZIG_VERSION" "$BUILD_VERSION" "$ARCH"