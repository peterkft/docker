# docker

Generic build images that projects build inside. GitHub Actions builds, smoke-tests and publishes each image to GitHub's container registry (`ghcr.io/peterkft/<image>`). A project pins an image version and pulls it from there; nothing about a project lives in this repository.

## Images

| Image | What's in it | Current version |
| --- | --- | --- |
| [`tauri-builder`](images/tauri-builder/Dockerfile) | Ubuntu 22.04, Rust (with clippy, rustfmt and the x86_64 and aarch64 musl targets), Node 24, zig with cargo-zigbuild, and the Linux libraries Tauri 2 needs. Builds Tauri apps, and static Linux binaries for x86_64 and aarch64. Linux packages built in it run on Ubuntu 22.04 and newer. | not published yet |

## Layout

```
images/
└── <image>/
    ├── Dockerfile   the image; the folder name is the image name (lower case)
    └── smoke.sh     run inside the image after every build
.github/
├── workflows/images.yml   builds, tests and publishes the images
└── dependabot.yml         monthly updates for the actions and the base images
```

## Image contract

Every image keeps these promises, so a project's build script works with any of them. Changing one is a new major version.

| What | Promise |
| --- | --- |
| User | Runs as any UID:GID given with `docker run --user`. Nothing at build time needs root. |
| Source | The project mounts it at `/src`, which is the working directory. |
| Home | `HOME=/home/builder`, writable by any user. |
| Caches a project may mount | `/home/builder/.cache` and `/home/builder/.npm`; in Rust images also `/usr/local/cargo/registry` and `/usr/local/cargo/git`. Each exists in the image and is writable by any user, so a new named volume starts with those permissions. |
| Scratch | `/cache`, writable by any user, for example for `CARGO_TARGET_DIR=/cache/target`. |
| Mounting volumes | Mount each volume on one of the folders above, not on a path below it. A new volume mounted on a path the image doesn't have, such as `/cache/target`, is owned by root, so a non-root user can't write to it. |
| Version | `BUILDER_IMAGE_VERSION` in the environment, plus the OCI labels `version`, `source` and `revision`. |
| Entrypoint | None. The project passes the command. |

A project typically runs:

```bash
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/src" \
  -v myproject-cargo-registry:/usr/local/cargo/registry \
  ghcr.io/peterkft/tauri-builder:1.0.0 bash scripts/build.sh
```

## Versions

- **Image versions:** each image has its own, set by a git tag `<image>/vX.Y.Z`.
  - Bump the patch version for a rebuild or a security update.
  - Bump the minor version when a toolchain version changes.
  - Bump the major version when the image contract changes.
- **Tool versions:** every download in a Dockerfile is pinned to a version and its SHA-256. Change both together.
- **What Dependabot updates:** the base image digest and the pinned actions. Toolchain versions (Rust, Node, zig, cargo-zigbuild) are bumped by hand.

## Building and testing locally

```bash
docker build -t tauri-builder:dev images/tauri-builder
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$PWD/images/tauri-builder/smoke.sh:/smoke.sh:ro" tauri-builder:dev bash /smoke.sh
```

A project can try a local build before it's published by pointing its image setting at `tauri-builder:dev`. For GitLane, that's `GITLANE_BUILDER_IMAGE=tauri-builder:dev`.

## Releasing a new version

1. Push the change. The Images workflow builds the changed images and runs their `smoke.sh` as two different non-root users. Watch it with `gh run watch`.
2. When it passes on `main`, tag and push:
   ```bash
   git tag tauri-builder/v1.0.0 && git push origin tauri-builder/v1.0.0
   ```
   The tag builds and tests the image again, then publishes `:1.0.0` and `:latest`.
3. Update the version in the table above, and in each project that should move to it.

## Adding an image

Add a folder under `images/` with a `Dockerfile` that keeps the image contract, and a `smoke.sh`. The workflow picks the folder up by itself. Add the image to the table above.

## GitHub setup

- The packages are private.
- The first tag of an image creates its package, linked to this repository.
- **Give a project access:** for each project that builds in an image, open the package on github.com: your profile → **Packages** → the image → **Package settings**. Under **Manage Actions access**, add the project's repository with the role **Read**. Its workflow can then pull the image with its own `GITHUB_TOKEN`, given `packages: read`.
- **Developer login:** developers log in once with `docker login ghcr.io -u <GitHub user>`, using a personal access token (classic) with only the `read:packages` scope as the password.
