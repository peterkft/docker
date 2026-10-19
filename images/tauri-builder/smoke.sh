#!/usr/bin/env bash
# Smoke test for the tauri-builder image. The Images workflow runs it inside
# the image as non-root users: the runner's own UID and an arbitrary one.
#   docker run --rm --user "$(id -u):$(id -g)" \
#     -v "$PWD/images/tauri-builder/smoke.sh:/smoke.sh:ro" tauri-builder:dev bash /smoke.sh
set -euo pipefail

echo "tauri-builder ${BUILDER_IMAGE_VERSION:-unknown}, running as $(id -u):$(id -g)"
rustc --version
cargo --version
cargo clippy --version
cargo fmt --version
node --version
npm --version
echo "zig $(zig version)"
cargo zigbuild --version

# The libraries Tauri links against on Linux.
pkg-config --print-errors --exists webkit2gtk-4.1 ayatana-appindicator3-0.1 librsvg-2.0 openssl

# Home, caches and scratch must be writable by whoever runs the image.
for dir in "$HOME" "$HOME/.cache" "$HOME/.npm" /cache "$CARGO_HOME/registry" "$CARGO_HOME/git"; do
  touch "$dir/.smoke-$$"
  rm "$dir/.smoke-$$"
done

# A small Rust program: for glibc, then as static musl binaries for x86_64 and
# aarch64 (the aarch64 one can't run here, so only its type is checked).
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cargo new --quiet --vcs none "$work/hello"
cd "$work/hello"

cargo build --quiet --release
./target/release/hello

check_static() { # <binary> <architecture as file(1) prints it>
  local info
  info="$(file -b "$1")"
  echo "$1: $info"
  [[ "$info" == *"$2"* ]] && [[ "$info" =~ static(ally|-pie)\ linked ]]
}

cargo zigbuild --quiet --release --target x86_64-unknown-linux-musl
check_static target/x86_64-unknown-linux-musl/release/hello x86-64
./target/x86_64-unknown-linux-musl/release/hello

cargo zigbuild --quiet --release --target aarch64-unknown-linux-musl
check_static target/aarch64-unknown-linux-musl/release/hello "ARM aarch64"

echo "Smoke test passed"
