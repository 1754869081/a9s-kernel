#!/usr/bin/env bash
# Build the sdm660-mainline kernel for arm64 (cross-compiled on x86_64).
#
# Usage (run from the repo root, after cloning the kernel into ./linux):
#   KERNEL_DIR="$PWD/linux" DEFCONFIG=sdm660_defconfig bash build.sh
#
# Inputs (env vars, all optional):
#   KERNEL_DIR  - kernel source dir (default: ./linux)
#   DEFCONFIG   - defconfig in arch/arm64/configs (default: sdm660_defconfig)
#   OUT_DIR     - where to stage artifacts (default: ./out)
#   KEEP_DEBUG_INFO - set to 1 to keep CONFIG_DEBUG_INFO/BTF (needs much
#                     more disk; default 0 = strip debug info for CI runners)
#
# What it produces in $OUT_DIR:
#   Image, Image.gz, System.map, kernel.config, dtbs/*.dtb,
#   modules.tar.gz, BUILD_INFO.txt
#
# This mirrors the upstream project's own CI (.github/workflows/build-images.yml
# in sdm660-mainline/linux): `make defconfig sdm660_defconfig` then
# `make all Image.gz`. Upstream builds natively on aarch64 self-hosted runners;
# here we cross-compile with gcc-aarch64-linux-gnu on x86_64, which is the
# only difference in toolchain.
set -euo pipefail

KERNEL_DIR="${KERNEL_DIR:-$PWD/linux}"
DEFCONFIG="${DEFCONFIG:-sdm660_defconfig}"
OUT_DIR="${OUT_DIR:-$PWD/out}"
KEEP_DEBUG_INFO="${KEEP_DEBUG_INFO:-0}"

if [ ! -d "$KERNEL_DIR" ]; then
  echo "ERROR: kernel source dir not found: $KERNEL_DIR" >&2
  exit 1
fi

cd "$KERNEL_DIR"
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

echo "=== toolchain ==="
aarch64-linux-gnu-gcc --version | head -1
echo "=== kernel ==="
KERNEL_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
KERNEL_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
KERNEL_VERSION="$(make -s kernelversion 2>/dev/null || echo unknown)"
echo "branch: $KERNEL_BRANCH"
echo "commit: $KERNEL_COMMIT"
echo "version: $KERNEL_VERSION"
echo "defconfig: $DEFCONFIG"

mkdir -p .output

echo "=== defconfig ==="
make O=.output LOCALVERSION= defconfig "$DEFCONFIG"

if [ "$KEEP_DEBUG_INFO" = "0" ]; then
  # CI slimming: drop DWARF/BTF debug info. It changes nothing about the
  # code in the Image, it only removes debug metadata, and it saves several
  # GB of disk on GitHub-hosted runners. Upstream's own CI keeps it because
  # their self-hosted runners have the disk. Set KEEP_DEBUG_INFO=1 to keep it.
  #
  # NOTE: simply disabling CONFIG_DEBUG_INFO does NOT work — the DWARF
  # version choice (DEBUG_INFO_DWARF5=y in the defconfig) SELECTs
  # DEBUG_INFO, so olddefconfig turns it back on. The DWARF variants must
  # be disabled explicitly and DEBUG_INFO_NONE enabled instead. Verified
  # locally 2026-11-23: after this, .config has DEBUG_INFO_NONE=y and no
  # DEBUG_INFO=y / DEBUG_INFO_BTF.
  echo "=== strip debug info for CI disk (KEEP_DEBUG_INFO=0) ==="
  ./scripts/config --file .output/.config \
    -d CONFIG_DEBUG_INFO_BTF \
    -d CONFIG_DEBUG_INFO_DWARF5 \
    -d CONFIG_DEBUG_INFO_DWARF4 \
    -d CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
    -e CONFIG_DEBUG_INFO_NONE
  make O=.output LOCALVERSION= olddefconfig
fi

echo "=== build (Image, modules, dtbs) ==="
make O=.output LOCALVERSION= -j"$(nproc)" all Image.gz

echo "=== install modules (stripped) ==="
rm -rf "$PWD/../modules-staging"
make O=.output LOCALVERSION= INSTALL_MOD_PATH="$PWD/../modules-staging" INSTALL_MOD_STRIP=1 modules_install

echo "=== stage artifacts ==="
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/dtbs"
cp .output/arch/arm64/boot/Image "$OUT_DIR/"
cp .output/arch/arm64/boot/Image.gz "$OUT_DIR/"
cp .output/System.map "$OUT_DIR/"
cp .output/.config "$OUT_DIR/kernel.config"
cp .output/arch/arm64/boot/dts/qcom/*.dtb "$OUT_DIR/dtbs/" 2>/dev/null || true
tar -czf "$OUT_DIR/modules.tar.gz" -C "$PWD/../modules-staging" .
rm -rf "$PWD/../modules-staging"

{
  echo "A9s (SM-A9200 / a9y18qltechn) kernel build"
  echo "date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "kernel repo: https://github.com/sdm660-mainline/linux"
  echo "kernel branch: $KERNEL_BRANCH"
  echo "kernel commit: $KERNEL_COMMIT"
  echo "kernel version: $KERNEL_VERSION"
  echo "defconfig: $DEFCONFIG"
  echo "toolchain: $(aarch64-linux-gnu-gcc --version | head -1)"
  echo "debug info stripped: $([ "$KEEP_DEBUG_INFO" = "0" ] && echo yes || echo no)"
  echo "NOTE: this build contains NO a9y18qltechn device tree yet."
  echo "The DTBs in dtbs/ are for other SDM660/SDM636 devices"
  echo "(e.g. Xiaomi lavender, clover). See README.md for the follow-up work."
} > "$OUT_DIR/BUILD_INFO.txt"

echo "=== artifacts ==="
ls -lh "$OUT_DIR" "$OUT_DIR/dtbs" | head -60
echo "BUILD OK"
