# docker

Generic build images that projects build inside. GitHub Actions builds, smoke-tests and publishes each image to GitHub's container registry (`ghcr.io/peterkft/<image>`). A project pins an image version and pulls it from there; nothing about a project lives in this repository.

## Images

| Image | What's in it | Current version |
| --- | --- | --- |
| [`gcc-arm-11.3`](images/gcc-arm-11.3/Dockerfile) | Ubuntu 22.04, the Arm GNU Toolchain 11.3.rel1 (`arm-none-eabi`, with newlib's version header filled in), CppUTest 4.0 built in `$CPPUTEST_HOME`, CMake, Ninja, uncrustify, and the firmware projects' Python tools (pytest, pylint, flake8, black, mypy, pyocd, …) pinned in [`requirements.in`](images/gcc-arm-11.3/requirements.in). Builds and tests Cortex-M firmware. PC-lint Plus is licensed, so it isn't included: mount your copy on `/opt/pc-lint` (`$PC_LINT_HOME`). Replaces the Ubuntu 18.04 `firmware_tools` image. | `:latest` from `main`; no version tags yet |
| [`tauri-builder`](images/tauri-builder/Dockerfile) | Ubuntu 22.04, Rust (with clippy, rustfmt and the x86_64 and aarch64 musl targets), Node 24, zig with cargo-zigbuild, the Linux libraries Tauri 2 needs, and git with Git LFS, GnuPG and OpenSSH's client for testing what a project does with them. Builds Tauri apps, and static Linux binaries for x86_64 and aarch64. Linux packages built in it run on Ubuntu 22.04 and newer. | `:latest` from `main`; no version tags yet |

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
| User name | `/etc/passwd` and `/etc/group` are writable by any user, so a build that needs a name for its UID (OpenSSH's tools refuse to run without one) can add it: `getent passwd "$(id -u)" \|\| echo "builder:x:$(id -u):$(id -g)::$HOME:/bin/bash" >> /etc/passwd`. |
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
- **What Dependabot updates:** the base image digest and the pinned actions. It doesn't move an image to a new base release, because that changes which systems the programs built in it run on; each image's `smoke.sh` checks its glibc. Toolchain versions (Rust, Node, zig, cargo-zigbuild, the Arm toolchain, CppUTest), Python packages and base releases are changed by hand.

## Moving a project from `firmware_tools` to `gcc-arm-11.3`

`gcc-arm-11.3` keeps this repository's image contract, so a project that ran the old `hermes-docker` image (built from Bitbucket's `firmware_tools`) changes how it runs it:

| | `firmware_tools` | `gcc-arm-11.3` |
| --- | --- | --- |
| Base | Ubuntu 18.04, Python 3.6 | Ubuntu 22.04, Python 3.10 |
| User | root | any UID: `docker run --user "$(id -u):$(id -g)"` |
| Source | mounted at `/home/working` | mounted at `/src` |
| `ARM_GCC_HOME` | `/root/firmware_tools/gcc-arm-none-eabi-7-2018-q2-update` | `/opt/arm-gnu-toolchain-11.3.rel1`, also on `PATH` |
| `CPPUTEST_HOME` | `/root/firmware_tools/cpputest`, source only | `/opt/cpputest`, already built (`lib/libCppUTest.a`, `lib/libCppUTestExt.a`) and writable |
| `PC_LINT_HOME` | `/root/firmware_tools/pc-lint` | `/opt/pc-lint`, empty: mount your copy, for example `-v "$PWD/../firmware_tools/pc-lint:/opt/pc-lint:ro"` |
| Python tools | `pip3` into the system Python | a virtual environment in `/opt/venv`, first on `PATH` |

Four Python tools moved to the oldest release that works on Python 3.10, and their results can differ: pytest 5.4.2 → 6.2.5, mypy 0.782 → 0.910 (it may ask for stub packages such as `types-PyYAML`), intelHex 2.2.1 → 2.3.0 and heatshrink2 0.9.0 → 0.11.0 (the same code). [`requirements.in`](images/gcc-arm-11.3/requirements.in) says why each one moved. black stays at 19.10b0, so formatting doesn't change.

```bash
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/src" \
  -v "$PWD/../firmware_tools/pc-lint:/opt/pc-lint:ro" \
  ghcr.io/peterkft/gcc-arm-11.3:latest make
```

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
