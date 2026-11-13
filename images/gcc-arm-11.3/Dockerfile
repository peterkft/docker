# gcc-arm-11.3: builds and tests firmware for Arm Cortex-M with the Arm GNU
# Toolchain 11.3.rel1 (arm-none-eabi), unit-tests it on the host with CppUTest,
# and runs the firmware projects' Python tools.
# It keeps the image contract in the repository README: any user can run it,
# and the consumer mounts its source at /src.
#
# Every download is pinned to a version and its SHA-256; change both together.
# The Python packages are pinned, with their dependencies and hashes, in
# requirements.txt (compiled from requirements.in).
#
# PC-lint Plus is licensed, so it isn't in the image: a project mounts its own
# copy on /opt/pc-lint (PC_LINT_HOME), for example
#   -v "$HOME/firmware_tools/pc-lint:/opt/pc-lint:ro"
FROM ubuntu:22.04@sha256:0a9887931b0e38af2e3487ed39e29436b0535c4f3f52e57745baaf79d1898956

LABEL org.opencontainers.image.title="gcc-arm-11.3" \
      org.opencontainers.image.description="Builds Arm Cortex-M firmware with GCC 11.3 (arm-none-eabi), CppUTest and Python tools; runs as any user"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Firmware builds use New Zealand time, as on the old firmware_tools image.
ENV TZ=Pacific/Auckland

# Host build tools, and what the Python packages without a wheel for Python
# 3.10 need to build (python3-dev, libpq-dev for psycopg2). The toolchain's gdb
# links libncursesw.so.5 and libtinfo.so.5.
# Package versions come from the digest-pinned Ubuntu release; pinning each one
# would break the build whenever Ubuntu ships a security update.
# hadolint ignore=DL3008
RUN export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates cmake curl file git ninja-build xz-utils tzdata \
        libncurses-dev libncursesw5 libtinfo5 libssl-dev libpq-dev \
        python3 python3-dev python3-venv uncrustify; \
    rm -rf /var/lib/apt/lists/*; \
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime; \
    echo "$TZ" > /etc/timezone

# Arm GNU Toolchain 11.3.rel1, in /opt/arm-gnu-toolchain-11.3.rel1.
# Arm's archive ships include/_newlib_version.h with its placeholders
# (@NEWLIB_VERSION@ ...) never filled in, so code that checks the newlib
# version doesn't compile; this release's newlib is 4.2.0.
ARG ARM_GCC_VERSION=11.3.rel1
ARG ARM_GCC_SHA256=d420d87f68615d9163b99bbb62fe69e85132dc0a8cd69fca04e813597fe06121
ENV ARM_GCC_HOME=/opt/arm-gnu-toolchain-11.3.rel1
RUN curl -fsSL -o /tmp/arm-gcc.tar.xz \
        "https://developer.arm.com/-/media/Files/downloads/gnu/${ARM_GCC_VERSION}/binrel/arm-gnu-toolchain-${ARM_GCC_VERSION}-x86_64-arm-none-eabi.tar.xz"; \
    echo "${ARM_GCC_SHA256}  /tmp/arm-gcc.tar.xz" | sha256sum -c -; \
    mkdir -p "${ARM_GCC_HOME}"; \
    tar -xJf /tmp/arm-gcc.tar.xz -C "${ARM_GCC_HOME}" --strip-components=1 --no-same-owner; \
    rm /tmp/arm-gcc.tar.xz; \
    header="${ARM_GCC_HOME}/arm-none-eabi/include/_newlib_version.h"; \
    sed -i -e 's/@NEWLIB_VERSION@/4.2.0/' -e 's/@NEWLIB_MAJOR_VERSION@/4/' \
        -e 's/@NEWLIB_MINOR_VERSION@/2/' -e 's/@NEWLIB_PATCHLEVEL_VERSION@/0/' "$header"; \
    grep -qx '#define _NEWLIB_VERSION "4.2.0"' "$header"; \
    if grep -q @ "$header"; then echo "$header still has placeholders" >&2; exit 1; fi
ENV PATH=${ARM_GCC_HOME}/bin:$PATH

# CppUTest 4.0, built in /opt/cpputest so CppUTest's MakefileWorker.mk finds
# its libraries in $CPPUTEST_HOME/lib. Writable by everyone, so a project that
# rebuilds CppUTest (for example in cpputest_build) can, as any user.
ARG CPPUTEST_VERSION=4.0
ARG CPPUTEST_SHA256=21c692105db15299b5529af81a11a7ad80397f92c122bd7bf1e4a4b0e85654f7
ENV CPPUTEST_HOME=/opt/cpputest
RUN curl -fsSL -o /tmp/cpputest.tar.gz \
        "https://github.com/cpputest/cpputest/releases/download/v${CPPUTEST_VERSION}/cpputest-${CPPUTEST_VERSION}.tar.gz"; \
    echo "${CPPUTEST_SHA256}  /tmp/cpputest.tar.gz" | sha256sum -c -; \
    mkdir "${CPPUTEST_HOME}"; \
    tar -xzf /tmp/cpputest.tar.gz -C "${CPPUTEST_HOME}" --strip-components=1 --no-same-owner; \
    rm /tmp/cpputest.tar.gz; \
    cd "${CPPUTEST_HOME}"; \
    ./configure --quiet; \
    make --quiet -j"$(nproc)"; \
    test -f lib/libCppUTest.a; test -f lib/libCppUTestExt.a; \
    mkdir -p cpputest_build; \
    chmod -R a+w "${CPPUTEST_HOME}"

# The Python tools, in a virtual environment in /opt/venv that's first on PATH
# (python, pip, pytest, ...). Every package, dependencies too, comes from
# requirements.txt with its hash. pip builds the ones without a wheel for
# Python 3.10 with setuptools < 70 (build-constraints.txt says why).
COPY requirements.txt build-constraints.txt /tmp/python/
ENV VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH
RUN python3 -m venv "${VIRTUAL_ENV}"; \
    PIP_CONSTRAINT=/tmp/python/build-constraints.txt \
        pip install --no-cache-dir --disable-pip-version-check --require-hashes --no-deps \
        -r /tmp/python/requirements.txt; \
    pip check; \
    rm -rf /tmp/python

# PC-lint Plus goes here when a project mounts it (see the top of this file).
ENV PC_LINT_HOME=/opt/pc-lint
RUN mkdir "${PC_LINT_HOME}"

# The image contract: any UID can run the image, so the home and cache folders
# are writable by everyone. The host user owns the mounted source, so git
# trusts every folder. /etc/passwd and /etc/group are writable, for a build
# that needs a name for its UID to add one.
ENV HOME=/home/builder \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8
RUN mkdir -p /home/builder/.cache /home/builder/.npm /cache; \
    chmod 1777 /home/builder /home/builder/.cache /home/builder/.npm /cache; \
    chmod a+w /etc/passwd /etc/group; \
    git config --system --add safe.directory '*'

# Last, so a new version doesn't invalidate the layers above.
ARG IMAGE_VERSION=dev
ENV BUILDER_IMAGE_VERSION=${IMAGE_VERSION}
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"

WORKDIR /src
CMD ["bash"]
