# docker

Generic build images that projects build inside. GitHub Actions builds, smoke-tests and publishes each image to GitHub's container registry (`ghcr.io/peterkft/<image>`). A project pins an image version and pulls it from there; nothing about a project lives in this repository.

## Images

| Image | What's in it | Current version |
| --- | --- | --- |
| [`tauri-builder`](images/tauri-builder/Dockerfile) | Ubuntu 22.04, Rust (with clippy, rustfmt and the x86_64 and aarch64 musl targets), Node 24, zig with cargo-zigbuild, and the Linux libraries Tauri 2 needs. Builds Tauri apps, and static Linux binaries for x86_64 and aarch64. Linux packages built in it run on Ubuntu 22.04 and newer. | `:latest` from `main`; no version tags yet |

## Layout

```
images/
└── <image>/
    ├── Dockerfile   the image; the folder name is the image name (lower case)
    └── smoke.sh     run inside the image, pulled from the registry, after every build
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
  ghcr.io/peterkft/tauri-builder:latest bash scripts/build.sh
```

## Versions

- **Published tags:** every push to `main` publishes each image it built as `:latest` and `:sha-<commit>` (the first 8 characters of the commit), once its smoke test passes. Projects can follow `:latest`, or pin a `:sha-` tag to stay on one build.
- **Test tags:** every run first pushes each image it builds as `:ci-<run id>`, and the smoke test pulls that tag. The run's summary names it, so a project can try a branch's image before it's merged. Don't pin one: they're for testing and can be deleted.
- **Version tags (optional):** a git tag `<image>/vX.Y.Z` publishes `:X.Y.Z`.
  - Bump the patch version for a rebuild or a security update.
  - Bump the minor version when a toolchain version changes.
  - Bump the major version when the image contract changes.
- **Tool versions:** every download in a Dockerfile is pinned to a version and its SHA-256. Change both together.
- **What Dependabot updates:** the base image digest and the pinned actions. It doesn't move an image to a new base release, because that changes which systems the programs built in it run on; each image's `smoke.sh` checks its glibc. Toolchain versions (Rust, Node, zig, cargo-zigbuild) and base releases are changed by hand.

## Building and testing locally

```bash
docker build -t tauri-builder:dev images/tauri-builder
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$PWD/images/tauri-builder/smoke.sh:/smoke.sh:ro" tauri-builder:dev bash /smoke.sh
```

A project can try a local build before it's published by pointing its image setting at `tauri-builder:dev`. For GitLane, that's `GITLANE_BUILDER_IMAGE=tauri-builder:dev`.

## Publishing

1. Push the change to a branch. The Images workflow builds the changed images and pushes each as `:ci-<run id>`. A separate job then pulls it on a fresh runner, the way a project gets it, and runs its `smoke.sh` as two different non-root users. Watch it with `gh run watch`.
2. Merge it into `main`. That run does the same, then tags each image that passed as `:latest` and `:sha-<commit>`. The tags go on the image the smoke test pulled; nothing is rebuilt.
3. Optionally, to give a build a version, tag and push:
   ```bash
   git tag tauri-builder/v1.0.0 && git push origin tauri-builder/v1.0.0
   ```
   The tag builds and tests the image again, then publishes `:1.0.0`. Update the table above, and the projects that should pin it.

## Adding an image

Add a folder under `images/` with a `Dockerfile` that keeps the image contract, and a `smoke.sh`. The workflow picks the folder up by itself. Add the image to the table above.

## GitHub setup

- The packages are private.
- An image's first push, from any branch, creates its package, linked to this repository.
- **Cleanup:** every run adds a `:ci-<run id>` version to the package. Now and then, delete the old ones that carry no other tag: the package's page → **View and manage all versions**.
- **Give a project access:** for each project that builds in an image, open the package on github.com: your profile → **Packages** → the image → **Package settings**. Under **Manage Actions access**, add the project's repository with the role **Read**. Its workflow can then pull the image with its own `GITHUB_TOKEN`, given `packages: read`.
- **Developer login:** developers log in once with `docker login ghcr.io -u <GitHub user>`, using a personal access token (classic) with only the `read:packages` scope as the password.
