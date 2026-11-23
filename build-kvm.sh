#!/usr/bin/env bash
# Build the Samsung downstream 4.4.205 kernel with KVM enabled, for the
# Galaxy A9s (SM-A9200) KVM test.
#
# Inputs (env):
#   KERNEL_DIR    - checked-out kernel source (riarumoda/kernel_samsung_a9y18qlte)
#   CONFIG_FILE   - a9200-kvm.config (stock A9200 config + KVM, resolved)
#   TOOLCHAIN_DIR - ARM GCC 9.2 install dir (bin/aarch64-none-linux-gnu-gcc)
#   OUT_DIR       - where build outputs are collected
#
# Outputs in OUT_DIR:
#   Image, Image.gz, System.map, kernel.config (final resolved .config),
#   modules.tar.gz, dtbs/sdm660-sec-a9y18qlte-eur-r*.dtb
#
# Notes:
# - The Image.gz is the file the parent packs into boot.img (with the
#   recovered ramdisk + the recovered A9200 DTBs, NOT the eur DTBs here).
# - MODULE_SIG_FORCE=y is inherited from the stock config: modules built
#   here are signed with a fresh key, so the phone's stock vendor modules
#   (signed by Samsung) will be refused by this kernel. That does not
#   affect the KVM test (check /dev/kvm over USB adb).
# - DEBUG_INFO=y is inherited from the stock config; it slows the build.
#   If the build times out, disabling it is the first safe optimisation
#   (it changes no runtime behaviour).
# - SIGPIPE lesson (mainline build run #2): never `ls | head` under
#   `set -euo pipefail`. No such pipe exists in this script.
set -euo pipefail

KERNEL_DIR="${KERNEL_DIR:?KERNEL_DIR not set}"
CONFIG_FILE="${CONFIG_FILE:?CONFIG_FILE not set}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:?TOOLCHAIN_DIR not set}"
OUT_DIR="${OUT_DIR:?OUT_DIR not set}"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export ARCH=arm64
export CROSS_COMPILE=aarch64-none-linux-gnu-

cd "$KERNEL_DIR"

echo "== toolchain =="
aarch64-none-linux-gnu-gcc --version
echo "== kernel version =="
head -4 Makefile

echo "== config =="
cp "$CONFIG_FILE" .config
make olddefconfig

echo "== KVM sanity check (must stay enabled after olddefconfig) =="
grep "^CONFIG_VIRTUALIZATION=y$" .config
grep "^CONFIG_KVM=y$" .config
grep "^CONFIG_KVM_ARM_HOST=y$" .config

echo "== build: Image.gz + modules + dtbs =="
make -j"$(nproc)" Image.gz modules dtbs

echo "== collect modules =="
make -j"$(nproc)" modules_install \
  INSTALL_MOD_PATH="$OUT_DIR/modules-staging" INSTALL_MOD_STRIP=1

echo "== collect outputs =="
mkdir -p "$OUT_DIR/dtbs"
cp arch/arm64/boot/Image arch/arm64/boot/Image.gz System.map .config "$OUT_DIR/"
cp .config "$OUT_DIR/kernel.config"
cp arch/arm64/boot/dts/samsung/sdm660-sec-a9y18qlte-*.dtb "$OUT_DIR/dtbs/" || true
tar -czf "$OUT_DIR/modules.tar.gz" -C "$OUT_DIR/modules-staging" .
rm -rf "$OUT_DIR/modules-staging"

echo "== outputs =="
du -sh "$OUT_DIR"
file "$OUT_DIR/Image" "$OUT_DIR/Image.gz"
ls "$OUT_DIR/dtbs"
ls "$OUT_DIR"
