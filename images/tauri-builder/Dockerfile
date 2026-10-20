# tauri-builder: builds Tauri 2 desktop apps (Rust and a TypeScript UI) and
# static Linux binaries (musl, linked with zig through cargo-zigbuild).
# It keeps the image contract in the repository README: any user can run it,
# and the consumer mounts its source at /src.
#
# Every download is pinned to a version and its SHA-256; change both together.
FROM ubuntu:26.04@sha256:c098726dd9b9733f3e885f8de0ef375206a311b0a317eadc40d347b1115fb944

LABEL org.opencontainers.image.title="tauri-builder" \
      org.opencontainers.image.description="Builds Tauri 2 apps and static Linux binaries; runs as any user"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Build tools and Tauri 2's Linux prerequisites; patchelf is for AppImages.
# Package versions come from the digest-pinned Ubuntu release; pinning each one
# would break the build whenever Ubuntu ships a security update.
# hadolint ignore=DL3008
RUN export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl wget file git pkg-config xz-utils patchelf \
        libssl-dev libwebkit2gtk-4.1-dev libxdo-dev libayatana-appindicator3-dev librsvg2-dev; \
    rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/opt/node/bin:$PATH

# Rust, with clippy, rustfmt, the musl targets for static binaries, and
# cargo-zigbuild, which links musl and cross-compiled binaries with zig.
# cargo-zigbuild 0.23.4 is tested with zig 0.16 (below). Move both to zig 0.17
# with its next release, which also drops the "ignoring deprecated linker
# optimization setting" warning that zig 0.16 prints.
# Any user may run the image, so the Rust homes are made writable by everyone
# (Cargo writes lock files in CARGO_HOME). That has to happen in this layer: a
# chmod in a later layer would copy the whole toolchain into it.
ARG RUSTUP_VERSION=1.29.1
ARG RUSTUP_SHA256=dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71
ARG RUST_VERSION=1.99.1
ARG CARGO_ZIGBUILD_VERSION=0.23.4
RUN curl -fsSL -o /tmp/rustup-init \
        "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init"; \
    echo "${RUSTUP_SHA256}  /tmp/rustup-init" | sha256sum -c -; \
    chmod +x /tmp/rustup-init; \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain "${RUST_VERSION}"; \
    rm /tmp/rustup-init; \
    rustup component add clippy rustfmt; \
    rustup target add x86_64-unknown-linux-musl aarch64-unknown-linux-musl; \
    cargo install --locked "cargo-zigbuild@${CARGO_ZIGBUILD_VERSION}"; \
    rm -rf "${CARGO_HOME}/registry" "${CARGO_HOME}/git"; \
    mkdir "${CARGO_HOME}/registry" "${CARGO_HOME}/git"; \
    chmod -R a+w "${RUSTUP_HOME}" "${CARGO_HOME}"

# Node.js, in /opt/node.
ARG NODE_VERSION=24.22.0
ARG NODE_SHA256=cc2f601cee82d9a5a233302fe307abc600727035fd7d2c3a3571755989e95008
RUN curl -fsSL -o /tmp/node.tar.xz \
        "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c -; \
    mkdir /opt/node; \
    tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 --no-same-owner; \
    rm /tmp/node.tar.xz

# zig, in /opt/zig.
ARG ZIG_VERSION=0.16.0
ARG ZIG_SHA256=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
RUN curl -fsSL -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz"; \
    echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c -; \
    mkdir /opt/zig; \
    tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 --no-same-owner; \
    rm /tmp/zig.tar.xz; \
    ln -s /opt/zig/zig /usr/local/bin/zig

# The image contract: any UID can run the image, so the home and cache folders
# are writable by everyone (the Rust homes were made so above). The host user
# owns the mounted source, so git trusts every folder. Without
# APPIMAGE_EXTRACT_AND_RUN, the AppImage tools Tauri downloads need FUSE, which
# containers don't have.
ENV HOME=/home/builder \
    LANG=C.UTF-8 \
    APPIMAGE_EXTRACT_AND_RUN=1
RUN mkdir -p /home/builder/.cache /home/builder/.npm /cache; \
    chmod 1777 /home/builder /home/builder/.cache /home/builder/.npm /cache; \
    git config --system --add safe.directory '*'

# Last, so a new version doesn't invalidate the layers above.
ARG IMAGE_VERSION=dev
ENV BUILDER_IMAGE_VERSION=${IMAGE_VERSION}
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"

WORKDIR /src
CMD ["bash"]
