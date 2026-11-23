# A9s KVM 测试内核 — GitHub Actions 构建

给三星 Galaxy A9s（SM-A9200，国行，骁龙 660）编一个开 KVM 的测试内核，
刷上去看 `/dev/kvm` 出不出来，判断 bootloader 有没有把 EL2 锁死。

## 用的东西

- **源码**：`riarumoda/kernel_samsung_a9y18qlte`（GitHub，基于三星官方开源代码），
  内核版本 **4.4.205**，和手机原厂内核版本完全一致。
- **配置**：`a9200-kvm.config` —— 手机自己 boot.img 里提取的原厂配置
  （5933 行），只改了两处：`CONFIG_VIRTUALIZATION=y`、`CONFIG_KVM=y`，
  其余 KVM 依赖由 `olddefconfig` 自动补齐（本地已验证：原厂配置 0 项被丢弃，
  只多了 14 个 KVM 相关选项 + 1 个 ARM64 erratum 选项，没有任何值被改动）。
- **工具链**：GCC 4.9（`aarch64-linux-android-4.9`），从 Android NDK r17c 里取。
  原厂内核就是用 GCC 4.9 编的，这是同代编译器。前 6 次用 ARM GCC 9.2 每次都
  死在新版才有的警告上（缩进、重复 const、bool 比较……），每次修一个才暴露
  下一个；GCC 4.9 根本不报这些警告，从根上断了这个循环。Linaro 的 4.9 包
  现在下不到了，NDK r17c 是最后一个带 GCC 的 NDK，676 MB，是最小的可靠来源。
  备用方案：如果这条工具链下载失败或编译失败，改用 Ubuntu 24.04 自带的
  `gcc-aarch64-linux-gnu`（GCC 13），并在 `build-kvm.sh` 的 make 命令上加
  `KBUILD_CFLAGS="-fcommon"`。

## 怎么跑

Actions 页 → **Build KVM test kernel (A9s)** → Run workflow；
或者 push 改动到 `build-kvm-kernel.yml` / `build-kvm.sh` / `a9200-kvm.config`
会自动跑。预计 **30–60 分钟**（原厂配置开了 `CONFIG_DEBUG_INFO=y`，
编得慢；如果超时，先关 DEBUG_INFO，它不影响运行行为）。

## 产出（artifact 名 `a9s-kvm-kernel`，保留 30 天）

| 文件 | 说明 |
|---|---|
| `Image` / `Image.gz` | 编好的内核。**`Image.gz` 是打包 boot.img 用的那个** |
| `System.map` | 符号表，排错用 |
| `kernel.config` | 最终生效的配置 |
| `modules.tar.gz` | 编好的内核模块 |
| `dtbs/sdm660-sec-a9y18qlte-eur-r*.dtb` | 源码树编出的 A920F（欧版）设备树，仅供参考 |

## 下一步（主 agent 做，不在这里）

用 `Image.gz` + 已恢复的原厂 ramdisk / A9200 设备树打包 boot.img，
用户自己用 Odin 刷 boot 分区，开机后 `adb shell ls /dev/kvm`。
出来就是 EL2 可用，虚拟化这条路能走；出不来就是 EL2 被 bootloader 锁死了。

## 已知注意点

- 配置里 `CONFIG_MODULE_SIG_FORCE=y` 是原厂就有的：这次编的内核会用新生成的
  签名密钥，手机 vendor 里原厂签名的模块（如 WiFi 的 `qca_cld3_wlan.ko`）
  会被拒绝加载。不影响 KVM 测试（用 USB adb 检查），但测试期间 WiFi 可能不可用。
- 这里的 DTB 是 A920F 欧版的，打包 boot.img 时要用已恢复的 A9200 原厂 DTB。
- 和主线内核构建（`build-kernel.yml` / `build.sh`）是两套独立的东西，互不干扰。
- 吸取了主线构建 run #2 的教训：本流程里没有任何 `ls | head` 管道，
  不会再因为 SIGPIPE 在编完之后失败。
