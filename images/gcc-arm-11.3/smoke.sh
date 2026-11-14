#!/usr/bin/env bash
# Smoke test for the gcc-arm-11.3 image. The Images workflow pulls the image
# it just pushed and runs this inside it as non-root users: the runner's own
# UID and an arbitrary one.
#   docker run --rm --user "$(id -u):$(id -g)" \
#     -v "$PWD/images/gcc-arm-11.3/smoke.sh:/smoke.sh:ro" gcc-arm-11.3:dev bash /smoke.sh
set -euo pipefail

echo "gcc-arm-11.3 ${BUILDER_IMAGE_VERSION:-unknown}, running as $(id -u):$(id -g)"

# A build that needs a name for its UID adds it, as the image contract says.
if ! getent passwd "$(id -u)" >/dev/null; then
  echo "builder:x:$(id -u):$(id -g)::$HOME:/bin/bash" >> /etc/passwd
fi
if ! getent group "$(id -g)" >/dev/null; then
  echo "builder:x:$(id -g):" >> /etc/group
fi
getent passwd "$(id -u)"

# Programs built here for the host need this glibc or newer; firmware doesn't
# care, but host test binaries and tools do. Change this only on purpose.
glibc="$(getconf GNU_LIBC_VERSION)"
echo "$glibc"
if [[ "$glibc" != "glibc 2.35" ]]; then
  echo "Expected glibc 2.35 (Ubuntu 22.04), found $glibc" >&2
  exit 1
fi

# Home, caches and scratch must be writable by whoever runs the image.
for dir in "$HOME" "$HOME/.cache" "$HOME/.npm" /cache "$CPPUTEST_HOME" /opt/venv/lib/python3.10/site-packages; do
  touch "$dir/.smoke-$$"
  rm "$dir/.smoke-$$"
done

[[ "$(date +%Z)" == NZ?T ]] || { echo "Expected New Zealand time, found $(date +%Z)" >&2; exit 1; }
echo "ARM_GCC_HOME=$ARM_GCC_HOME CPPUTEST_HOME=$CPPUTEST_HOME PC_LINT_HOME=$PC_LINT_HOME"
gcc --version | head -n 1
cmake --version | head -n 1
echo "ninja $(ninja --version)"
uncrustify --version
git --version

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

# The Arm toolchain: the right version, the newlib header Arm ships unfilled,
# and a Cortex-M4 program compiled, linked against newlib-nano and checked.
[[ "$(arm-none-eabi-gcc -dumpversion)" == 11.3.1 ]]
"$ARM_GCC_HOME/bin/arm-none-eabi-gcc" --version | head -n 1
# arm-none-eabi-gdb is Ubuntu's gdb-multiarch, with Ubuntu's Python 3.10.
arm-none-eabi-gdb --version | head -n 1
gdb_python="$(arm-none-eabi-gdb -batch -ex 'python import gdb, json, sys; print(sys.version.split()[0])')"
echo "gdb python $gdb_python"
[[ "$gdb_python" == 3.10.* ]]
newlib="$(echo '#include <newlib.h>' | arm-none-eabi-gcc -E -dM - | sed -n 's/^#define _NEWLIB_VERSION //p')"
echo "newlib $newlib"
[[ "$newlib" == '"4.2.0"' ]]
cat > firmware.c <<'EOF'
#include <newlib.h>
#include <stdio.h>
#include <string.h>
#if __NEWLIB__ != 4 || __NEWLIB_MINOR__ != 2
#error "unexpected newlib version"
#endif
int main(void) {
    char buffer[32];
    snprintf(buffer, sizeof buffer, "newlib %s", _NEWLIB_VERSION);
    return (int)strlen(buffer);
}
EOF
arm-none-eabi-gcc -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 -O2 -Wall -Werror \
  --specs=nano.specs --specs=nosys.specs firmware.c -o firmware.elf
arm-none-eabi-size firmware.elf
arm-none-eabi-objcopy -O ihex firmware.elf firmware.hex
info="$(file -b firmware.elf)"
echo "firmware.elf: $info"
[[ "$info" == *"ELF 32-bit LSB executable, ARM"* ]]
# gdb reads the firmware as Arm code.
arch="$(arm-none-eabi-gdb -batch -ex 'file firmware.elf' -ex 'show architecture')"
echo "gdb: $arch"
[[ "$arch" == *'(currently "arm'* ]]

# PC-lint Plus, when a local build copied it in or a project mounted it.
if [[ -e "$PC_LINT_HOME/linux/pclp64_linux" ]]; then
  printf 'int main(void) { return 0; }\n' > lint.c
  "$PC_LINT_HOME/linux/pclp64_linux" -b lint.c
  echo "PC-lint Plus ran from $PC_LINT_HOME"
else
  echo "PC-lint Plus isn't in $PC_LINT_HOME"
fi

# CppUTest: a test built on the host against the libraries in the image.
cat > test.cpp <<'EOF'
#include "CppUTest/CommandLineTestRunner.h"
#include "CppUTest/TestHarness.h"
#include "CppUTestExt/MockSupport.h"
TEST_GROUP(Smoke) { void teardown() { mock().clear(); } };
TEST(Smoke, Adds) { LONGS_EQUAL(3, 1 + 2); }
TEST(Smoke, Mocks) {
    mock().expectOneCall("f");
    mock().actualCall("f");
    mock().checkExpectations();
}
int main(int argc, char **argv) { return CommandLineTestRunner::RunAllTests(argc, argv); }
EOF
g++ -I"$CPPUTEST_HOME/include" test.cpp -L"$CPPUTEST_HOME/lib" -lCppUTestExt -lCppUTest -o tests
./tests -v

# The Python tools, from the virtual environment on PATH.
[[ "$(command -v python)" == /opt/venv/bin/python ]]
python --version
pip check
mkdir py
cd py
printf '"""A tiny module."""\n\n\ndef add(a: int, b: int) -> int:\n    """Add two numbers."""\n    return a + b\n' > mod.py
printf '"""Tests."""\nfrom mod import add\n\n\ndef test_add():\n    """Check add."""\n    assert add(1, 2) == 3\n' > test_mod.py
pytest -q -p no:cacheprovider -n 2 --cov=. --html="$work/report.html"
coverage run -m pytest -q -p no:cacheprovider
pylint --disable=invalid-name --score=n mod.py
flake8 mod.py
mypy --no-incremental --cache-dir=/dev/null mod.py
black --check mod.py
isort --check-only mod.py
pydocstyle mod.py
docformatter --check mod.py
gcovr --version | head -n 1
invoke --version
pyocd --version
fpvgcc --help >/dev/null
jupyter --version >/dev/null
python - <<'EOF'
import bitarray, boto3, can, cbor2, click, dash, geopy, gmplot, intelhex, isotp
import jenkins, junitparser, paho.mqtt.client, pem, psutil, psycopg2, PyCRC
import pytz, serial, testrail_api, usb, yaml
import heatshrink2
import pyvisa
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.asymmetric import ec

data = b"hello hello hello" * 10
assert heatshrink2.decompress(heatshrink2.compress(data)) == data
ec.generate_private_key(ec.SECP256R1(), default_backend())
pyvisa.ResourceManager("@py").close()
import usb.backend.libusb1
assert usb.backend.libusb1.get_backend() is not None, "pyusb found no libusb-1.0"
print("psycopg2", psycopg2.__version__)
EOF

echo "Smoke test passed"
