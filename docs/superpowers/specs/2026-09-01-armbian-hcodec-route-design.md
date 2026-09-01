# WS1608 Armbian HCODEC 路线设计

- 状态：Approved
- 日期：2026-09-01
- 范围：仓库文档架构与后续硬件编码研发方向

## 目标

统一仓库文档，以已经实机验证可启动、显示、联网并运行 One-KVM 的
Armbian 26.8 / Debian Trixie / Linux `6.12.28-current-meson` 为唯一系统底座。
H.264 硬件编码研发采用 Linux 6.12 原生 V4L2 M2M 接口，不再继续 Linux
3.10 厂商内核和私有 AMLENC ABI 路线。

本规格只定义文档迁移。内核、设备树、工作流、构建脚本和 One-KVM 代码的
实现改动属于后续开发任务。

## 架构决策

唯一有效路线如下：

1. 保留 `base-20260804-consolefix` 的启动链、U-Boot、HDMI、网络、eMMC、
   rootfs 和 One-KVM 集成。
2. 在与该基础一致的 Linux 6.12 源码中移植 `meson-venc` HCODEC 驱动，
   使用标准 V4L2 M2M 用户态接口。
3. 为 Meson8b/S805 补齐 HCODEC 时钟、复位、电源、Canvas、固件、中断、
   DMA/CMA 和设备树资源。
4. 由 One-KVM 使用其 V4L2 M2M 后端；不再维护 `/dev/amvenc_avc`、
   `libvpcodec` 或 One-KVM AMLENC 私有 ABI 适配。
5. 保留四种软件编码路径。只有实机产生可解码 H.264 码流并通过稳定性验证
   后，才把 H.264 V4L2 M2M 标记为硬件可用。

## 新证据

2026-09-01 核对的资料支持继续使用 Linux 6.12：

- 本地研究资料包含 18 个 Linux 6.12 补丁，提供 `meson-venc` V4L2 M2M
  驱动、HCODEC 固件生命周期、DMA/CMA、Canvas、IRQ、码率控制，以及
  Meson8b、GXL、GXM 后端。
- 补丁包含 `amlogic,meson8b-hcodec` 绑定和 ARM Meson8b 设备树节点。
- One-KVM `0.2.6` 已包含 `h264_v4l2m2m` 后端，因此目标接口可以直接使用
  标准 V4L2，而不必恢复 3.10 私有字符设备 ABI。Amlogic 平台默认不探测
  该后端，实验阶段必须显式设置 `ONE_KVM_V4L2M2M_ALLOW=1`；实机验证前
  不得把该变量写入稳定服务配置。
- 当前 Armbian 6.12 基础已经具备 3.10 候选一直未达到的实机启动、HDMI、
  网络、SSH、eMMC 和 One-KVM 运行证据。

资料仍存在必须通过实现和实机测试解决的限制：

- 资料中的现成 `meson-venc.ko` 是 AArch64、`6.12.98-ipkvm-release`，不能
  直接加载到 WS1608 的 ARMv7 `6.12.28-current-meson`。
- Meson8b 公共节点默认 `status = "disabled"`，OneCloud 板级设备树必须在
  确认 DOS 寄存器资源不冲突后显式启用。
- Meson8b 补丁中的 HCODEC 时钟 ID 和 `amlogic,hhi-sysctrl` 描述需要与
  实际 6.12.28 ARM 时钟树逐项核对。补丁 18 缺少最终驱动强制读取的
  `amlogic,hhi-sysctrl`，补丁 1/2 又只修改 GXBB/GXL 时钟定义，当前补丁
  集不能直接作为 S805 可构建结论。
- 18 个补丁与目录中的最终驱动不是同一修订；最终驱动增加了直接 HHI
  时钟控制和设备树属性。实施时必须选定一个一致源码基线，不能混合使用。
- 资料没有附带必需的 `meson/venc/meson8b_h264.bin`，只有固件提取脚本；
  固件来源、摘要和许可证必须进入可复现输入清单。
- 教程给出的 1080p30、128 MiB CMA 和 One-KVM 1080p20 只能作为测试目标，
  不能写成 WS1608 已验证结果。

驱动源码声明的能力边界为：64×64 至 1920×1088、NV12/YUYV 输入、H.264
Baseline Level 4.0、I/P 帧、SPS/PPS/IDR、GOP、I/P QP、强制关键帧及
CQ/VBR/CBR 控制。它不支持 B 帧，同一时间只允许一个编码会话；第二个会话
应返回 `EBUSY`。当前 CBR/VBR 是软件 QP 反馈，不应描述为成熟硬件 VBV。

1080p 的内存预算必须写入后续验收：驱动工作区约 15.44 MiB，单个 NV12
输入约 2.97 MiB，单个 YUYV 输入约 3.96 MiB，单个 H.264 输出缓冲按当前
实现可达 8 MiB。One-KVM 使用 4 个输入和 4 个输出缓冲时，仅编码部分约需
59.30 MiB（NV12）或 63.26 MiB（YUYV）；再加 USB 采集和其他 DMA，64 MiB
CMA 不足，`cma=128M` 是候选配置而不是已验证定值。

研究资料压缩包 SHA-256：
`4422aa4c8d9f3f18cc6220ec3c0da056ed5979fdddeaad1b6b09166edf80e0a6`。

## 明确废弃的路线

以下内容不得再作为当前或后续实施方案：

- Linux `3.10.107`、Debian Bullseye armhf 实验底座；
- Hardkernel 3.10 厂商编码驱动和 `/dev/amvenc_avc`；
- M8 `libvpcodec`、AMLENC ABI v1 和相应 One-KVM 私有补丁；
- 双内核、recovery-first、kexec、U-Boot 冷启动试验；
- 3.10 initramfs、启动阶段标记和旧内核成功标记；
- 以 3.10 为目标的实验 Release、构建计划和实机验收步骤。

旧资料可以保留历史结论，但必须明确标记为“已废弃”，不得保留可直接执行的
3.10 构建、刷写或试启动指令。

## 后续实现边界

文档描述的后续工程顺序固定为：

1. 固定可复现的 Armbian 6.12 内核源码、配置和基础镜像输入。
2. 让 18 个补丁在目标 ARMv7 内核树上完成应用、编译、DT schema 和模块
   依赖验证。
3. 选择补丁系列或最终源码之一作为唯一实现基线，补齐可追溯的 Meson8b
   H.264 固件。
4. 修正 Meson8b 时钟及 HHI 资源，增加 OneCloud 板级 HCODEC 节点。
5. 先用独立 V4L2 M2M 工具验证 640×480 和 1280×720 H.264。
6. 评估 1080p、128 MiB CMA、码率、单实例限制、温度和长时间稳定性。
7. 独立验证通过后，以 `ONE_KVM_V4L2M2M_ALLOW=1` 接入 One-KVM，再决定
   是否写入候选服务配置。
8. 实机启动、视频、HID、虚拟介质和重启验证全部通过后，才能进入候选
   Release；稳定通道升级仍需单独决策。

任何阶段失败时，继续使用当前已验证 Armbian 镜像，不改变稳定 Release。

## 文档迁移规则

仓库现有 Markdown 文件按以下规则处理：

| 文档 | 处理方式 |
| --- | --- |
| `README.md` | 更新项目现状、唯一技术路线和硬件验证边界 |
| `THIRD_PARTY.md` | 增加 Linux 6.12 HCODEC/V4L2 资料及许可证来源 |
| `docs/README.md` | 更新文档导航，移除 3.10 执行入口 |
| `docs/HANDOFF.md` | 重写当前交接、分支状态和下一阶段 |
| `docs/architecture.md` | 增加稳定系统与 HCODEC 候选内核的架构关系 |
| `docs/build-pipeline.md` | 区分稳定镜像工作流和后续 Armbian 内核候选工作流 |
| `docs/hardware-validation.md` | 改为 V4L2 M2M、CMA、码流和稳定性验收 |
| `docs/image-lineage.md` | 记录继续使用 consolefix Armbian 基础的决策 |
| `docs/maintenance.md` | 更新维护禁区、分支和版本升级规则 |
| `docs/manifest-schema.md` | 定义后续 HCODEC 候选证据字段，不声明硬件已通过 |
| `docs/troubleshooting.md` | 删除 3.10 排障入口，增加 V4L2/HCODEC/CMA/DT 排障 |
| `docs/adr/0001-*` | 保留固定基础决策，补充 Linux 6.12 HCODEC 路线 |
| `docs/adr/0002-*` | 保留不可变 Release 决策，限制未验证 HCODEC 发布 |
| `docs/superpowers/specs/2026-07-20-*` | 增加当前路线说明，不改写历史发布设计 |
| `docs/superpowers/plans/2026-07-20-*` | 增加当前路线说明，不改写已完成历史计划 |
| 两份 2026-08 AMLENC 计划 | 替换为简短的已废弃历史记录，移除执行清单 |
| `experimental/amlenc/docs/bringup.md` | 重写为 Armbian 6.12 HCODEC 实机验证指南 |
| `experimental/amlenc/docs/licensing.md` | 改为 Linux 6.12 GPL 驱动、固件和工具许可证边界 |

新增文档：

- `docs/adr/0003-armbian-6.12-hcodec-route.md`：正式记录路线变更；
- `docs/superpowers/plans/2026-09-01-armbian-hcodec-documentation-plan.md`：
  批量文档迁移实施计划。

## 文档验收标准

迁移完成后必须满足：

- 所有当前状态、架构、维护、排障和验收文档只推荐 Armbian/Linux 6.12；
- 出现 3.10、Bullseye、kexec、`amvenc_avc` 或 `libvpcodec` 时，只能位于
  明确的“已废弃历史”语境；
- 不存在可直接执行的 3.10 构建、刷写、切换或试启动步骤；
- 已验证 Armbian 基础的启动证据与 HCODEC 候选状态分开记录；任何加入新
  内核或设备树的 HCODEC 候选都保持 `hardware_boot_tested=false` 和
  `hardware_encoder_tested=false`，直到对应实机验收完成；
- 文档不引用本机绝对路径、Codex 任务 ID、IP、密码或设备序列号；
- 相对链接有效，Markdown 无尾随空格和冲突标记；
- 文档修改不改变 `.github/workflows/`、`config/`、`scripts/`、`tests/` 或
  `experimental/amlenc` 中的非文档代码。

## 非目标

- 本次不应用 18 个内核补丁；
- 不构建或加载新的内核模块；
- 不修改现有实验工作流；
- 不删除现有 Git tag、Release、分支或历史提交；
- 不把教程或其他 SoC 的结果写成 WS1608 实测结论。
