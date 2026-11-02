#!/usr/bin/env bash
# Smoke test for the tauri-builder image. The Images workflow pulls the image
# it just pushed and runs this inside it as non-root users: the runner's own
# UID and an arbitrary one.
#   docker run --rm --user "$(id -u):$(id -g)" \
#     -v "$PWD/images/tauri-builder/smoke.sh:/smoke.sh:ro" tauri-builder:dev bash /smoke.sh
set -euo pipefail

echo "tauri-builder ${BUILDER_IMAGE_VERSION:-unknown}, running as $(id -u):$(id -g)"

# A build that needs a name for its UID adds it, as the image contract says.
if ! getent passwd "$(id -u)" >/dev/null; then
  echo "builder:x:$(id -u):$(id -g)::$HOME:/bin/bash" >> /etc/passwd
fi
if ! getent group "$(id -g)" >/dev/null; then
  echo "builder:x:$(id -g):" >> /etc/group
fi
getent passwd "$(id -u)"
rustc --version
cargo --version
cargo clippy --version
cargo fmt --version
node --version
npm --version
echo "zig $(zig version)"
cargo-zigbuild --version
git --version
git lfs version
gpg --version | head -n 1
ssh -V

# Programs built here need this glibc or newer, so the base image decides which
# systems they run on: Ubuntu 22.04 (glibc 2.35) and newer. A newer base drops
# older systems; change this only on purpose.
glibc="$(getconf GNU_LIBC_VERSION)"
echo "$glibc"
if [[ "$glibc" != "glibc 2.35" ]]; then
  echo "Expected glibc 2.35 (Ubuntu 22.04), found $glibc" >&2
  exit 1
fi

# The libraries Tauri links against on Linux.
pkg-config --print-errors --exists webkit2gtk-4.1 ayatana-appindicator3-0.1 librsvg-2.0 openssl

# Git LFS's filters are there for every repository.
[[ "$(git config --system filter.lfs.process)" == "git-lfs filter-process" ]]

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

# A commit signed with a new SSH key, and its signature checked, as any user.
repo="$work/signed"
git init -q "$repo"
ssh-keygen -q -t ed25519 -N "" -C smoke -f "$work/key"
echo "smoke@example.invalid $(cat "$work/key.pub")" > "$work/allowed"
git -C "$repo" -c user.name=Smoke -c user.email=smoke@example.invalid -c gpg.format=ssh \
  -c user.signingkey="$work/key" commit -q -S --allow-empty -m "signed"
git -C "$repo" -c gpg.ssh.allowedSignersFile="$work/allowed" verify-commit HEAD

echo "Smoke test passed"
