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

echo "== patch gcc-wrapper.py for Python 3 =="
# The 4.4 tree's scripts/gcc-wrapper.py is Python 2 code (print >> sys.stderr
# and byte-stream Popen). The Makefile runs it with $(PYTHON)=python, which
# is Python 3 on ubuntu-24.04, so the first compile that produced any gcc
# output crashed it (run #1: hw_breakpoint.o, TypeError). Convert the prints
# and read stderr as text. Verified locally: py_compile passes and a smoke
# test with a fake gcc still forwards warnings and exits 1 on a forbidden
# warning, i.e. the script's intended behaviour is preserved.
python3 - <<'PYEOF'
p = 'scripts/gcc-wrapper.py'
s = open(p).read()
s = s.replace("proc = subprocess.Popen(args, stderr=subprocess.PIPE)",
              "proc = subprocess.Popen(args, stderr=subprocess.PIPE, universal_newlines=True)")
s = s.replace('print >> sys.stderr, "error, forbidden warning:", m.group(2)',
              'print("error, forbidden warning:", m.group(2), file=sys.stderr)')
s = s.replace('print >> sys.stderr, line,',
              "print(line, file=sys.stderr, end='')")
s = s.replace("print >> sys.stderr, args[0] + ':',e.strerror",
              "print(args[0] + ':', e.strerror, file=sys.stderr)")
s = s.replace("print >> sys.stderr, 'Is your PATH set correctly?'",
              "print('Is your PATH set correctly?', file=sys.stderr)")
s = s.replace("print >> sys.stderr, ' '.join(args), str(e)",
              "print(' '.join(args), str(e), file=sys.stderr)")
assert 'print >>' not in s, 'gcc-wrapper.py still has Python 2 print statements'
assert 'universal_newlines=True' in s, 'gcc-wrapper.py Popen patch missing'
open(p, 'w').write(s)
print('gcc-wrapper.py patched to Python 3')
PYEOF

echo "== patch kvm_mmu.h: cpuid_feature_extract_field needs 3 args =="
# Run #2 failure: arch/arm64/include/asm/kvm_mmu.h:309 calls
# cpuid_feature_extract_field(reg, ID_AA64MMFR1_VMIDBITS_SHIFT) with 2 args,
# but cpufeature.h declares it with 3: (u64 features, int field, bool sign).
# Every other call site in the tree passes a third arg. VMIDBITS is an
# unsigned field (0/1 = 8-bit VMID, 2 = 16-bit), so sign = false.
# The "control reaches end of non-void function" warning at line 310 was a
# consequence of the broken return statement and goes away with this fix.
python3 - <<'PYEOF'
p = 'arch/arm64/include/asm/kvm_mmu.h'
s = open(p).read()
old = 'return (cpuid_feature_extract_field(reg, ID_AA64MMFR1_VMIDBITS_SHIFT) == 2) ? 16 : 8;'
new = 'return (cpuid_feature_extract_field(reg, ID_AA64MMFR1_VMIDBITS_SHIFT, false) == 2) ? 16 : 8;'
assert old in s, 'kvm_mmu.h call site not found (already patched?)'
s = s.replace(old, new)
open(p, 'w').write(s)
print('kvm_mmu.h patched: cpuid_feature_extract_field now takes false (unsigned)')
PYEOF

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
