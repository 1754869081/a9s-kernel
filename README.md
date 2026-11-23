# A9s 内核 GitHub Actions 编译工程

给三星 Galaxy A9s（SM-A9200，国行 CHC，代号 `a9y18qltechn`，骁龙 660）纯 Linux 移植用的**第一步**：在 GitHub 的免费服务器上把主线内核编出来，验证工具链、源码和配置都没问题，拿到可以继续往下用的内核文件。

> **先说清楚这一步能证明什么、不能证明什么**
>
> - ✅ 能证明：sdm660-mainline 的内核源码 + `sdm660_defconfig` + 交叉编译工具链可以在 GitHub 的标准服务器上编出 arm64 内核（`Image`、`Image.gz`、各机型的 `.dtb`、内核模块）。
> - ❌ **不能证明手机能用这个内核启动。** 主线内核里**没有 A9s 的设备树**（`a9y18qltechn` 的 DTS 不存在，2026-11-23 已核实），所以这次编出来的 `.dtb` 都是别的 SDM660/SDM636 机型的（小米 lavender、clover 等），**没有一个能直接给 A9s 用**。想让 A9s 启动，还要补一块工作：按原厂 DTB 写一份 `sdm660-samsung-a9y18qltechn.dts`（见下面“下一步”）。
> - ❌ 这一步**不是刷机包**。它只产出内核文件，没有 rootfs、没有 boot.img、不能直接刷进手机。

## 仓库里有什么

| 文件 | 说明 |
|---|---|
| `.github/workflows/build-kernel.yml` | GitHub Actions 工作流：装工具链 → 拉内核源码 → 编译 → 上传产物 |
| `build.sh` | 编译脚本（工作流调用它），步骤和上游项目自己的 CI 保持一致 |
| `stock-4.4.205.config` | **原厂内核配置的逐字副本**：从 A9s 原厂 boot.img 里提取的 `Linux/arm64 4.4.205` 完整配置，5933 行。本次主线编译**不用它**（主线用的是 `sdm660_defconfig`），留在这里是给后续对照用的——写 A9s 设备树、开/关驱动时要拿它当参考。来源：`~/workspace/a9s-port/recovered/kernel-config.txt`，boot.img SHA256 与提取报告完全一致 |

## 已核实的信息（2026-11-23）

- 内核源码：https://github.com/sdm660-mainline/linux ，默认分支 **`qcom-sdm660-7.2.y`**，HEAD 提交 `5690ded6161e97967f9a5c23cc22a93e022c3c62`，最新标签 `v7.2.15-sdm660`。
- 该分支有 `arch/arm64/configs/sdm660_defconfig`（1016 行），其中 `CONFIG_USB_CONFIGFS_RNDIS=y`、`CONFIG_USB_DWC3=y`、`CONFIG_MMC_SDHCI_MSM=y`、`CONFIG_EXT4_FS=y`、`CONFIG_MODULES=y` 都有开——对无头服务器目标是好消息。
- 上游自己的 CI（`.github/workflows/build-images.yml`）就是 `make defconfig sdm660_defconfig` 然后 `make all Image.gz`；上游用的是自家 aarch64 服务器原生编译，本工程改成在 GitHub 的 x86_64 标准服务器上用 `gcc-aarch64-linux-gnu`（Ubuntu 24.04，GCC 13）交叉编译，这是唯一的区别。
- `arch/arm64/boot/dts/qcom/` 里**没有** `a9y18qltechn` / `a9y18qlte` 的设备树（635 个文件里查过，三星的只有老 MSM8916/MSM8939 机型和较新的 SDM845/SM8xxx 机型）。6 个原厂 DTB（Rev00/02/03/04/05/06，model `A9Y18QLTE`）目前在 `~/workspace/a9s-port/recovered/dtb/`，**不在这个仓库里**——写 DTS 时要用到它们。
- 原厂内核配置 `stock-4.4.205.config` 已找回（之前以为丢在阿里云服务器上了，2026-11-23 已从用户发来的 boot.img.lz4 重新提取并核对过）。

## 操作步骤（照着点就行）

### 1. 新建一个空的 GitHub 仓库

1. 打开 https://github.com ，登录后点右上角 `+` → `New repository`。
2. Repository name 填 `a9s-kernel`（随便起个名字也行）。
3. 选 **Public**，不要勾 `Add a README file`，不要加 `.gitignore` 和 license。
4. 点 `Create repository`。

> 仓库选 Public 的话 Actions 不花钱（公开仓库不限分钟）；选 Private 的话免费账号每月有 2000 分钟额度，这次编译一次大概用 30–60 分钟，也够用。

### 2. 把这三个文件传上去

仓库建好后，页面上有个 `uploading an existing file` 链接，点它，把下面这些文件拖进去：

- `build.sh`
- `stock-4.4.205.config`
- 整个 `.github` 文件夹（里面是 `.github/workflows/build-kernel.yml`）

注意：`.github` 是隐藏文件夹，拖整个文件夹最稳妥；如果浏览器上传看不到它，就把 `.github/workflows/build-kernel.yml` 所在的路径结构原样保留（先在仓库里点 `Add file` → `Create new file`，文件名填 `.github/workflows/build-kernel.yml`，再把内容粘贴进去也行）。

传完点 `Commit changes`。传完后仓库里应该有这三样东西。

### 3. 运行编译

1. 点仓库顶部的 **Actions** 选项卡。
2. 左边找到 **Build sdm660 kernel (A9s)**，点进去。
3. 点右边 **Run workflow** 按钮（分支不用改，`kernel_branch` 和 `defconfig` 也不用改，直接用默认的 `qcom-sdm660-7.2.y` / `sdm660_defconfig`），再点绿色的 **Run workflow**。
4. 等着就行，一般 20–50 分钟。页面上能看到进度，变绿 ✅ 就是编成了，变红 ❌ 就是失败了（见下面“失败了怎么办”）。

> 上传文件后也可能自动触发一次编译（push 触发），那就不用再手动点了，直接在 Actions 里看那次运行的结果就行。

### 4. 下载产物

编成之后，点那次运行记录，拉到最下面 **Artifacts**，下载 **`a9s-kernel-build`**（一个 zip 包），解压后里面有：

| 文件 | 说明 |
|---|---|
| `Image` | 编好的 arm64 内核（未压缩，几十 MB） |
| `Image.gz` | 压缩版内核，刷机时一般用这个 |
| `System.map` | 内核符号表，调试用的 |
| `kernel.config` | 这次编译实际用的完整配置 |
| `dtbs/*.dtb` | 编出来的设备树（**注意：全是别的机型的**，小米 lavender、clover、jasmine、platina、索尼等，**没有 A9s 的**） |
| `modules.tar.gz` | 内核模块（解开后是 `lib/modules/...`） |
| `BUILD_INFO.txt` | 这次编译的记录：分支、提交号、内核版本、工具链版本 |

## 编出来之后怎么办（下一步）

按顺序，缺一不可：

1. **写 A9s 的设备树（最关键的一步，还没做）。** 以主线 `arch/arm64/boot/dts/qcom/sdm660.dtsi` 为底，照着原厂 DTB 反编译的 DTS（`~/workspace/a9s-port/recovered/dts/dtb*.dts`，6 个 Rev，先要拿到真机 Download Mode 里的 board-id 才知道用哪一个）写一份 `sdm660-samsung-a9y18qltechn.dts`，加到内核源码的 `arch/arm64/boot/dts/qcom/` 里，并在同目录的 `Makefile` 里登记它，再跑一次这个工作流，就会多出一个 `sdm660-samsung-a9y18qltechn.dtb`。
2. **对照原厂配置补驱动。** 拿 `stock-4.4.205.config` 和这次的 `kernel.config` 对一下：WCN3990 WiFi（`CONFIG_QCA_CLD_WLAN`）在主线的支持有限，要单独验证；电源（PM660L）、充电（SM5705）、eMMC、USB 这些按原厂 DTS 核对。
3. **做 boot.img / lk2nd。** 有了对的 DTB 才能打包 boot.img（配合 lk2nd，走 Heimdall 刷），再接 pmbootstrap 的 `device-samsung-a9y18qltechn` 设备包和 rootfs。那是下一阶段的工作，不在这个仓库里。

## 已知的缺口（诚实清单）

- **没有 A9s 的 DTS/DTB。** 这是最大的缺口，上面已经说了。没有它，这次编出来的内核在 A9s 上起不来。
- **不知道真机是 6 个 Rev 里的哪一个。** 需要手机进 Download Mode，看顶部显示的 board-id / Rev，才能决定用 `dtb0`–`dtb5` 里哪一个起草 DTS。
- **dtbo.img / system.img / vendor.img 还没拿到。** 原厂固件 AP 之前传坏过，PC 上的固件 zip 用户已确认是好的，后续可以从它重新提取 vendor blobs（WiFi 固件等）。
- **完整编译没在本地跑通过。** 本地已验证：源码、分支、defconfig、工具链、上游 CI 命令逐项核实过，YAML 和脚本语法通过，配置生成阶段（`defconfig` → 去调试信息 → `olddefconfig`，用和工作流一样的命令、同一分支、同一工具链）在 2026-11-23 跑通过。完整编译（`make all Image.gz`）因为本机太慢没跑，第一次完整编译就是 GitHub Actions 这次。如果它在 GitHub 上失败，把失败日志贴出来再排查。
- **GitHub 免费服务器磁盘紧张。** 内核编译产物很大，工作流里已经做了两件事：删了 runner 上预装的 dotnet/Android/GHC（约 10 GB），并且默认关掉调试信息（关 BTF 和全部 DWARF 版本、开 `DEBUG_INFO_NONE`，只影响调试元数据，不影响内核本身；注意：只关 `CONFIG_DEBUG_INFO` 是没用的，DWARF5 会把它重新选回来，`build.sh` 里已经按验证过的方法处理了）。如果还报磁盘不足，先确认清理步骤的日志里磁盘确实变多了；调试信息想恢复的话，把 `build.sh` 里的 `KEEP_DEBUG_INFO` 改成 `1`（但这会更占磁盘，只在磁盘够用时才开）。

## 失败了怎么办

- 点进失败的那次运行，看红色 ❌ 的那一步，展开日志，把最后 30 行发给助手。
- 最常见的几种：
  - `No space left on device`：磁盘满了，见上面“已知的缺口”最后一条。
  - `aarch64-linux-gnu-gcc: No such file`：工具链没装上，一般是 apt 源抽风，点 `Re-run jobs` 再跑一次。
  - `error: pathspec ... did not match` 或 clone 失败：GitHub 到 sdm660-mainline 的网络问题，重跑一次。
  - 编译中途某个驱动报错：把报错的驱动名记下来，可能是这个分支在某个提交上本来就是坏的，换一个分支（比如 `qcom-sdm660-6.12.y`）再试——工作流运行时 `kernel_branch` 那一栏可以改。
