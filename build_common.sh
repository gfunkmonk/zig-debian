#!/usr/bin/env bash
# Shared helpers for zig Debian/Ubuntu package build scripts.
# Source with:  source "$(dirname "$0")/build_common.sh"
#
# The calling script must set these globals before calling run_builds:
#   ZIG_VERSION   – zig version string (e.g. 0.16.0)
#   BUILD_VERSION – packaging revision (e.g. 1)
#   ARCH          – target arch or "all"
#   MAN_VARIANT   – "stable" or "oldstable"
#   DISTROS       – bash array of distro codenames
#
# The calling script must also define:
#   build_dist <dist> <build_arch> <zig_arch>

# ---------------------------------------------------------------------------
# Architecture mapping
# ---------------------------------------------------------------------------

get_zig_arch() {
    case "$1" in
        amd64)   echo "x86_64" ;;
        arm64)   echo "aarch64" ;;
        armel)   echo "arm" ;;
        riscv64) echo "riscv64" ;;
        ppc64el) echo "powerpc64le" ;;
        i386)    echo "x86" ;;
        loong64) echo "loongarch64" ;;
        s390x)   echo "s390x" ;;
        *)       echo "" ;;
    esac
}

# ---------------------------------------------------------------------------
# Docker helpers
# ---------------------------------------------------------------------------

# Extract a single file from a stopped container into dest_dir, then remove
# the container.
# Usage: docker_copy <container_id> <src_path_in_container> <dest_dir>
docker_copy() {
    local cid=$1 src=$2 dest_dir=$3
    # `docker cp <id>:/path -` streams a tar whose single entry is the
    # basename of src; pipe straight into tar to avoid a temp-file detour.
    docker cp "$cid:$src" - | tar -xf - -C "$dest_dir"
    docker rm "$cid" >/dev/null
}

# ---------------------------------------------------------------------------
# Man-page builder
# ---------------------------------------------------------------------------

# Build docs_Dockerfile for <variant> and extract zig-<variant>.1.gz into
# build/man/.  Called once per architecture before the parallel distro builds.
# Usage: build_man_page <build_arch> <zig_arch> <variant>
build_man_page() {
    local build_arch=$1 zig_arch=$2 variant=$3
    local image="zig-docs-${variant}-${build_arch}"

    echo "  Generating man page for ${variant} (${build_arch})..."
    mkdir -p "build/man"

    if ! docker build . -t "$image" \
        --build-arg ZIG_VERSION="$ZIG_VERSION" \
        --build-arg ZIG_ARCH="$zig_arch" \
        --build-arg ARCH="$build_arch" \
        --build-arg VARIANT="$variant" \
        -f docs_Dockerfile; then
        echo "❌ Failed to build man page for ${variant} (${build_arch})"
        return 1
    fi

    local cid
    cid="$(docker create "$image")"
    docker_copy "$cid" "/man/zig-${variant}.1.gz" "build/man"
}

# ---------------------------------------------------------------------------
# Per-architecture orchestration
# ---------------------------------------------------------------------------

# Download + unpack the zig tarball once, build all DISTROS in parallel via
# build_dist(), then clean up.
build_architecture() {
    local build_arch=$1
    local zig_arch
    zig_arch=$(get_zig_arch "$build_arch")

    if [[ -z "$zig_arch" ]]; then
        echo "❌ Unsupported architecture: $build_arch"
        echo "   Supported: amd64 arm64 armel riscv64 ppc64el i386 loong64 s390x"
        return 1
    fi

    echo "Building for architecture: $build_arch (zig arch: $zig_arch)"

    # Download and extract once on the host to avoid concurrent Docker COPY
    # collisions when multiple distros build in parallel.
    local tarball="zig-${zig_arch}-linux-${ZIG_VERSION}.tar.xz"
    if ! wget -q "https://ziglang.org/download/${ZIG_VERSION}/${tarball}" \
            -O "$tarball"; then
        echo "❌ Failed to download zig tarball for $build_arch"
        return 1
    fi
    mkdir -p "build/${build_arch}"
    tar -xf "$tarball" -C "build/${build_arch}"
    rm -f "$tarball"

    # Man page is also generated once and shared across distro builds.
    if ! build_man_page "$build_arch" "$zig_arch" "$MAN_VARIANT"; then
        rm -rf "build/${build_arch}"
        return 1
    fi

    # Launch one background job per distro.
    local pids=()
    for dist in "${DISTROS[@]}"; do
        build_dist "$dist" "$build_arch" "$zig_arch" &
        pids+=($!)
    done

    local failed=0
    for pid in "${pids[@]}"; do
        wait "$pid" || failed=1
    done

    # Always clean up, even on failure.
    rm -rf "build/${build_arch}"
    rm -f "build/man/zig-${MAN_VARIANT}.1.gz"

    if [[ $failed -ne 0 ]]; then
        echo "❌ One or more distro builds failed for $build_arch"
        return 1
    fi

    echo "✅ Successfully built for $build_arch"
}

# ---------------------------------------------------------------------------
# Top-level entry point
# ---------------------------------------------------------------------------

ALL_ARCHES=(amd64 arm64 armel riscv64 ppc64el i386 loong64 s390x)

# Build for ARCH (single architecture or "all").
# Usage: run_builds <display_label> <deb_glob> [<deb_glob> ...]
run_builds() {
    local label=$1; shift
    local globs=("$@")

    if [[ "$ARCH" == "all" ]]; then
        echo "🚀 Building ${label} ${ZIG_VERSION}-${BUILD_VERSION} for all architectures..."
        echo ""
        for build_arch in "${ALL_ARCHES[@]}"; do
            echo "==========================================="
            echo "Building for architecture: $build_arch"
            echo "==========================================="
            if ! build_architecture "$build_arch"; then
                echo "❌ Failed to build for $build_arch"
                exit 1
            fi
            echo ""
        done
        echo "🎉 All architectures built successfully!"
        echo "Generated packages:"
        ls -la "${globs[@]}" 2>/dev/null || true
    else
        build_architecture "$ARCH" || exit 1
    fi
}