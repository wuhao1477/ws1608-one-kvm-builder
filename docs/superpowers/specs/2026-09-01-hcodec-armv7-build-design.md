# WS1608 Armbian 6.12 HCODEC ARMv7 构建设计

- 状态：静态构建实现完成，等待实体硬件验证
- 日期：2026-09-01
- 实现日期：2026-09-02
- 范围：首个 Linux 6.12 HCODEC 可复现构建里程碑

## 目标

在不刷写实体设备、不修改 One-KVM、不改变稳定镜像链的前提下，生成一个
可复现的 ARMv7 Linux 6.12 HCODEC 构建 artifact。artifact 用于后续实体
WS1608 独立 V4L2 M2M 验证，不代表当前已具备硬件编码能力。

## 已确认约束

| 项目 | 决策 |
| --- | --- |
| 系统底座 | 已验证 Armbian 26.8 / Debian Trixie / `6.12.28-current-meson` |
| 硬件范围 | 1 GiB OneCloud/WS1608，Meson8b/S805，ARMv7 |
| 内核来源 | 固定 Armbian build framework 提交，必须与稳定镜像唯一对应 |
| 内核集成 | 完整 in-tree，`CONFIG_VIDEO_MESON_VENC=m` |
| 补丁策略 | 保留原 18 个 Linux 6.12 补丁，追加 Meson8b 集成修正补丁 |
| DTB | 从稳定基础实际 DTB 还原语义基线，再启用 HCODEC 节点 |
| 配置 | 只允许 HCODEC 必需符号白名单差异 |
| 启动参数 | 候选 `extraargs` 写入 `cma=128M`，不修改稳定 DTB |
| uImage | 同时保留原始 `zImage` 与按稳定 boot metadata 生成的 `uImage` |
| 模块加载 | 实机阶段手动 `modprobe`，不自动加载 |
| 工具 ABI | 与 Armbian 基础一致的 glibc 动态链接 |
| 首个性能门槛 | NV12、`1280x720@30`、4 Mbps、GOP 30、CQP 26、60 秒/1800 帧 |
| One-KVM | 首个 PR 不修改；后续临时使用 `ONE_KVM_V4L2M2M_ALLOW=1` |
| 固件 | 从固定公开源码提取；只上传来源记录和摘要，不上传固件二进制 |
| artifact | 单一 `.tar.xz`，附 `manifest.json` 与 `SHA256SUMS`，保留 14 天 |
| CI | GitHub `ubuntu-24.04` + 固定摘要 Docker 构建镜像 |
| 触发 | PR 与手动 workflow，独立工作流，不创建 tag/Release |
| 质量优先级 | 可复现性与正确性优先，无法证明时阻塞 |

## 证据基线

新的研究资料包含 18 个 Linux 6.12 补丁、最终 `meson-venc` 驱动、
`amlogic,meson8b-hcodec` binding、V4L2 MMAP/DMABUF 工具和固件提取脚本。
参考任务确认的编码链为：

```text
NV12/YUYV → V4L2 OUTPUT → 连续 DMA/CMA → Canvas/MFDIN
→ HCODEC 固件与 mailbox IRQ → V4L2 CAPTURE → Annex-B H.264
```

驱动声明支持 64×64 至 1920×1088、NV12/YUYV、H.264 Baseline Level 4.0、
SPS/PPS/IDR、I/P 帧、GOP、I/P QP、强制关键帧及 CQ/VBR/CBR。它不支持 B 帧，
同一时间只允许一个编码实例，CBR/VBR 为软件 QP 反馈而非成熟硬件 VBV。

现有资料不能直接用于目标设备：预编译模块是 AArch64
`6.12.98-ipkvm-release`；Meson8b 时钟和 HHI 属性在补丁与最终源码之间不
一致；`meson8b_h264.bin` 未随资料提供。

## 组件与职责

### `experimental/hcodec/config/`

保存稳定基础 URL/SHA-256、Armbian build 提交、内核配置来源、工具链容器
摘要、补丁系列摘要、固件提取输入和候选 `cma=128M` 参数。所有来源必须
使用完整提交或内容摘要，不接受 moving branch。

### `experimental/hcodec/patches/linux-6.12/`

复制原 18 个补丁并按顺序编号；追加补丁只允许修复 Meson8b 的：

- HCODEC 时钟 ID/provider；
- `amlogic,hhi-sysctrl`、AO syscon、Canvas 和 IRQ 资源；
- OneCloud 板级 DOS 地址和节点 `status = "okay"`；
- ARMv7 Kconfig、Makefile、模块依赖和 firmware 路径；
- 与 `6.12.28-current-meson` API 的构建兼容性。

追加补丁不得引入新的编码协议、码率算法、One-KVM 接口或自动加载逻辑。

### `experimental/hcodec/tools/`

提交 ARMv7 V4L2 smoke/capture 工具、固件提取脚本、Makefile 和工具源码
摘要。不得提交研究资料中的预编译 `.ko`、工具或固件二进制。

### `experimental/hcodec/scripts/`

提供基础镜像取证、源码唯一映射、补丁应用、内核构建、DT 生成、工具构建、
配置白名单、模块签名策略、artifact 打包和独立验证脚本。

### `.github/workflows/hcodec-candidate.yml`

只响应 `pull_request` 和 `workflow_dispatch`，PR 与手动运行都执行完整构建。
artifact 名称包含 run number/attempt，保留 14 天，不创建 tag 或 Release。
工作流不修改 `.github/workflows/build.yml`、`config/base.env`、稳定脚本或
One-KVM 代码。

## 构建数据流

```text
固定稳定 burn.img.xz
→ 提取实际 .config、DTB、uImage 头和 boot 参数
→ 核对 Armbian build commit/metadata/内核包版本/源码提交
→ 应用 18 个补丁
→ 应用 Meson8b 修正补丁
→ 配置白名单比较
→ ARMv7 in-tree zImage/uImage/模块/DTB 构建
→ dt_binding_check、vermagic、符号和签名策略验证
→ 构建 glibc 动态 V4L2 工具
→ 固件来源摘要与提取记录
→ tar.xz + manifest.json + SHA256SUMS
```

源码、配置、DTB、boot 地址或签名策略无法唯一证明时，构建必须阻塞；不得
使用“最接近版本”继续生成 artifact。

## 配置与启动参数

候选 `.config` 从稳定基础实际 `config-6.12.28-current-meson` 提取，并与
Armbian build framework 生成配置逐项比较。允许差异仅限：

```text
CONFIG_VIDEO_MESON_VENC=m
CONFIG_V4L2_MEM2MEM_DEV=y
CONFIG_VIDEOBUF2_DMA_CONTIG=y
CONFIG_MESON_CANVAS=y
HCODEC 所需时钟、firmware loader、media 和 ARMv7 模块依赖
```

候选 boot 参数通过 `extraargs` 增加 `cma=128M`；原稳定 DTB 的内存布局不改。
若稳定启动 metadata 中没有唯一 load/entry 地址，uImage 生成阻塞。

`meson-venc` 为模块，候选镜像不自动加载。实机阶段先验证 `modprobe` 输出、
模块架构、vermagic、符号和设备树 probe，再运行 V4L2 工具。

## 固件与许可证

固件由固定公开源码提取，manifest 记录提取脚本、输入摘要、输出摘要和许可
状态。再分发授权未确认时：

- 构建仍可生成内核和模块；
- artifact 只包含来源说明、脚本和摘要；
- 固件二进制不上传；
- 没有固件的 artifact 不得标记为可启动或硬件已验证。

## 验证门

### 静态门

- Armbian 源码四项证据唯一匹配；
- 18 个补丁和修正补丁顺序、摘要、SPDX 正确；
- ARMv7 `zImage`、`uImage`、模块和工具架构正确；
- `.config` 只有白名单差异；
- DT binding、OneCloud 资源、HCODEC 节点和 `cma=128M` 元数据正确；
- 模块签名策略与稳定基础一致；
- 工具 glibc 解释器和依赖可解析；
- artifact 文件白名单、manifest 和 `SHA256SUMS` 一致。

### 实机门（后续里程碑）

首个实体测试只允许手动加载模块并运行 NV12 `1280x720@30`、4 Mbps、GOP 30、
CQP 26、60 秒/1800 帧。必须检查 H.264 SPS/PPS/IDR、帧数、完整解码、CMA、
温度和 kernel log。通过后才进入 YUYV、1080p 和 One-KVM。

所有候选从以下状态开始：

```text
hardware_boot_tested=false
hardware_encoder_tested=false
```

## 错误处理

- 来源映射失败：阻塞并输出缺失证据名称；
- 补丁冲突：阻塞，禁止自动跳过 hunk；
- 新增 HCODEC 警告：失败；Armbian 既有警告逐条记录白名单；
- DT 资源冲突：失败，不通过禁用节点掩盖；
- 固件授权缺失：排除二进制并保留来源记录；
- 构建工具或模块签名不匹配：失败；
- artifact 内容超出白名单：失败；
- 任一静态门失败：不生成可供实机使用的候选说明。

## 非目标

- 不刷写或重启实体 WS1608；
- 不修改 One-KVM Rust 或其 V4L2 后端；
- 不修改稳定工作流、基础配置或稳定 Release；
- 不恢复 Linux 3.10、Bullseye、`/dev/amvenc_avc`、`libvpcodec`、双内核或 kexec；
- 不在首个里程碑验证 YUYV、1080p、One-KVM 实时流、HID 或虚拟介质；
- 不把外部教程性能值写成 WS1608 实测结论。
