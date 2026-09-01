# WS1608 Armbian 6.12 HCODEC ARMv7 构建实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不修改稳定镜像、旧 `experimental/amlenc/` 或 One-KVM 的前提下，构建与已验证 Armbian `6.12.28-current-meson` 匹配的 ARMv7 `meson-venc` HCODEC 模块、OneCloud DTB、V4L2 工具和可复现 artifact。

**Architecture:** 新建 `experimental/hcodec/`。从固定基础镜像提取实际配置、DTB、uImage 地址和模块签名策略；还原唯一对应的 Armbian build 源码，应用 18 个研究补丁及一个 Meson8b 修正补丁。模块手动加载，`cma=128M` 仅写入候选 boot 参数和 manifest，首个 PR 不刷机、不改 One-KVM。

**Tech Stack:** Armbian build framework、Linux 6.12.28 ARMv7、GitHub Actions `ubuntu-24.04`、digest-pinned Docker、ARM GCC/binutils、dtc、dt-schema、Bash、Node.js tests、V4L2 MMAP/DMABUF、tar/xz。

**Spec:** `docs/superpowers/specs/2026-09-01-hcodec-armv7-build-design.md`

## Global Constraints

- 只支持 1 GiB OneCloud/WS1608/S805 ARMv7。
- 源码必须唯一映射到稳定 Armbian `6.12.28-current-meson`；证据不完整时阻塞。
- 保留原 18 个补丁，追加补丁只修复 Meson8b 集成缺口。
- `CONFIG_VIDEO_MESON_VENC=m`，实机阶段手动 `modprobe`，不自动加载。
- 只允许 HCODEC 配置白名单差异，其余 `.config` 与稳定基础实际配置一致。
- DTB 从稳定基础实际 DTB 还原语义后启用 OneCloud HCODEC 节点。
- `cma=128M` 写入候选 `extraargs` 和 manifest，不修改稳定 DTB 内存布局。
- 同时产出 `zImage` 和按稳定 boot metadata 生成的 `uImage`。
- 固件从固定公开源码提取；不上传固件二进制，只上传来源和摘要。
- 测试工具使用与 Armbian 基础一致的 glibc 动态链接。
- PR 与手动 workflow 都执行完整构建，artifact 保留 14 天，不创建 tag/Release。
- 首个 PR 不修改 One-KVM、稳定 workflow、`config/base.env` 或 `experimental/amlenc/`。
- manifest 保持 `hardware_boot_tested=false`、`hardware_encoder_tested=false`。

---

### Task 1: 来源锁与稳定基础取证

**Files:**
- Create: `experimental/hcodec/config/sources.env`
- Create: `experimental/hcodec/config/protected-files.sha256`
- Create: `experimental/hcodec/scripts/verify-source-locks.mjs`
- Create: `experimental/hcodec/scripts/collect-base-evidence.sh`
- Create: `experimental/hcodec/tests/source-lock.test.mjs`
- Create: `experimental/hcodec/tests/base-evidence-contract.test.mjs`

**Interfaces:**
- Consumes: `config/base.env`、固定 Armbian build commit和基础 `.burn.img.xz`。
- Produces: `base-evidence/`，包含实际 `.config`、DTB、boot 参数、uImage load/entry、`CONFIG_MODULE_SIG*`、证书摘要、内核版本和四项源码匹配证据。

- [ ] **Step 1: 写失败测试**：拒绝 moving branch、重复 key、缺少 archive digest、缺少基础 SHA-256、非唯一 uImage 地址和不完整签名策略。
- [ ] **Step 2: 实现来源锁验证**：复用现有严格 env 解析，新增 Armbian build、kernel config、uImage、模块签名和 firmware extraction 字段。
- [ ] **Step 3: 实现基础取证**：下载并校验固定基础，解包 Amlogic v2，提取 boot/rootfs 证据；无法唯一读取时退出非零。
- [ ] **Step 4: 保护稳定链**：生成稳定 workflow/config/scripts/tests 的路径和 SHA-256 清单，排除 `Downloads/` 与 `experimental/amlenc/`。
- [ ] **Step 5: 验证并提交**：运行 `node --test experimental/hcodec/tests/*.test.mjs`，`git diff --check`，提交 `feat(hcodec): 固定Armbian内核来源`。

---

### Task 2: 导入 18 个补丁并追加 Meson8b 修正

**Files:**
- Create: `experimental/hcodec/patches/linux-6.12/0001` 至 `0018` 的 18 个原始补丁文件（沿用研究资料原文件名）
- Create: `experimental/hcodec/patches/linux-6.12/0019-meson8b-hhi-and-dt-fix.patch`
- Create: `experimental/hcodec/scripts/patch-digest.sh`
- Create: `experimental/hcodec/scripts/apply-patches.sh`
- Create: `experimental/hcodec/tests/patch-series.test.mjs`
- Create: `experimental/hcodec/tests/meson8b-resource-contract.test.mjs`

**Interfaces:**
- Consumes: Task 1 的来源锁和 `base-evidence/`。
- Produces: 可审计的 19 个补丁序列和规范化 patch digest。

- [ ] **Step 1: 写失败测试**：检查 18 个补丁顺序、SPDX、允许文件、Meson8b HHI/AO/Canvas/IRQ/时钟/firmware 资源和无 DOS 重叠。
- [ ] **Step 2: 导入补丁**：从研究资料复制补丁文本和提交信息，不复制预编译对象。
- [ ] **Step 3: 编写修正补丁**：只修复 Meson8b 时钟 provider、`amlogic,hhi-sysctrl`、OneCloud 节点 `status = "okay"`、Kconfig/Makefile、模块依赖和 firmware 路径。
- [ ] **Step 4: 应用与摘要**：逐个 `git apply --check` 后应用；冲突、未跟踪改动或顺序错误立即失败；摘要与工作目录无关。
- [ ] **Step 5: 验证并提交**：运行两个契约测试，提交 `feat(hcodec): 修正Meson8b内核资源`。

---

### Task 3: 构建 ARMv7 in-tree 内核、DTB 和模块

**Files:**
- Create: `experimental/hcodec/scripts/build-kernel.sh`
- Create: `experimental/hcodec/scripts/verify-kernel.sh`
- Create: `experimental/hcodec/scripts/verify-config-diff.sh`
- Create: `experimental/hcodec/scripts/verify-module-signing.sh`
- Create: `experimental/hcodec/tests/kernel-build-contract.test.mjs`
- Create: `experimental/hcodec/tests/config-diff-contract.test.mjs`

**Interfaces:**
- Consumes: Tasks 1-2 的源码、配置、证据和补丁。
- Produces: `out/hcodec/kernel/` 的 `zImage`、`uImage`、OneCloud DTB、模块 tar、`.config`、`System.map`、`Module.symvers`、source manifest、签名报告和 `SHA256SUMS`。

- [ ] **Step 1: 写失败测试**：要求 ARM 32-bit、`6.12.28-current-meson`、`CONFIG_VIDEO_MESON_VENC=m`、启用 HCODEC DT 节点、稳定地址和无自动加载。
- [ ] **Step 2: 实现构建**：从固定 Armbian framework 恢复源码/config，应用补丁，运行 `olddefconfig`，比较白名单差异，在 digest-pinned Docker 中构建 kernel/DTB/modules。
- [ ] **Step 3: 生成镜像**：用 base evidence 的 load/entry 封装 `zImage`；地址不唯一时阻塞。
- [ ] **Step 4: 签名策略**：比较稳定基础的 `CONFIG_MODULE_SIG*`、算法、证书摘要和新模块；强制验签但无匹配密钥时阻塞。
- [ ] **Step 5: 验证并提交**：运行 build/verify 脚本和契约测试，提交 `feat(hcodec): 构建Armbian ARMv7内核`。

---

### Task 4: 构建 V4L2 工具与固件来源记录

**Files:**
- Create: `experimental/hcodec/tools/meson-venc-smoke/`
- Create: `experimental/hcodec/tools/meson-venc-capture/`
- Create: `experimental/hcodec/tools/extract-meson8b-ucode.py`
- Create: `experimental/hcodec/scripts/build-tools.sh`
- Create: `experimental/hcodec/scripts/verify-tools.sh`
- Create: `experimental/hcodec/tests/tools-contract.test.mjs`

**Interfaces:**
- Consumes: Task 2 的 V4L2 API 和固定固件提取输入。
- Produces: ARMv7 glibc 动态 MMAP/DMABUF 工具、工具 manifest、固件来源/摘要记录；不上传固件二进制。

- [ ] **Step 1: 写失败测试**：检查设备路径、NV12、宽高、FPS、帧数、GOP、CQP、内存模式、输出文件、ARM ELF、解释器、依赖和失败退出码。
- [ ] **Step 2: 实现最小工具**：支持 NV12 `1280x720@30`、4 Mbps、GOP 30、CQP 26、1800 帧；设备/格式/缓冲/timeout/空输出/SPS-PPS-IDR 缺失均失败。
- [ ] **Step 3: 实现固件记录**：输出提取命令、输入/输出 SHA-256、许可证和 `binary_included=false` JSON。
- [ ] **Step 4: 验证并提交**：运行工具构建和契约测试，提交 `feat(hcodec): 增加V4L2编码测试工具`。

---

### Task 5: artifact 打包和独立 GitHub Actions

**Files:**
- Create: `experimental/hcodec/scripts/package-artifact.sh`
- Create: `experimental/hcodec/scripts/verify-artifact.sh`
- Create: `experimental/hcodec/tests/artifact-contract.test.mjs`
- Create: `.github/workflows/hcodec-candidate.yml`

**Interfaces:**
- Consumes: Tasks 1-4 的全部输出。
- Produces: `ws1608-hcodec-armv7-run-${GITHUB_RUN_NUMBER}-${GITHUB_RUN_ATTEMPT}.tar.xz`、manifest、`SHA256SUMS` 和 14 天 artifact。

- [ ] **Step 1: 写失败测试**：workflow 只有 PR/手动触发，无 schedule/repository_dispatch/tag/Release，PR/手动都跑完整构建，artifact 白名单明确。
- [ ] **Step 2: 实现打包**：manifest 记录 kernel/DTB/module/tool/base/source/patch/compiler 摘要、`cma=128M`、硬件 false、固件不包含；使用排序、固定时间戳和 xz。
- [ ] **Step 3: 实现验证**：检查白名单、摘要、tar/xz 往返、ARM ELF、配置差异、DT binding、签名报告、无固件二进制和无旧 AMLENC 路径。
- [ ] **Step 4: 编写 workflow**：使用 `ubuntu-24.04`、digest-pinned Docker 和固定 Actions SHA；contract、build、artifact 下载后复验全部存在。
- [ ] **Step 5: 验证并提交**：运行 HCODEC tests、`bash -n`、固定版本 actionlint，提交 `ci(hcodec): 增加ARMv7候选构建`。

---

### Task 6: 首个里程碑交接

**Files:**
- Create: `experimental/hcodec/docs/build.md`
- Create: `experimental/hcodec/docs/artifact.md`
- Modify: `docs/superpowers/specs/2026-09-01-hcodec-armv7-build-design.md`
- Modify: `docs/superpowers/plans/2026-09-01-hcodec-armv7-build-plan.md`

**Interfaces:**
- Consumes: CI run、artifact manifest、静态验证报告。
- Produces: 可审计交接记录，不刷机、不修改 One-KVM、不宣称硬件通过。

- [ ] **Step 1: 写文档**：记录固定输入、构建命令、输出清单、固件不上传、失败处理、14 天保留和手动 `modprobe` 规则。
- [ ] **Step 2: 完成验证**：运行 `node --test`、HCODEC tests、`git diff --check`、全量 shell 语法和 actionlint；确认非文档/实现文件仅限计划范围。
- [ ] **Step 3: 更新状态**：只记录实际 CI/artifact 摘要；`hardware_boot_tested=false`、`hardware_encoder_tested=false` 保持不变。
- [ ] **Step 4: 创建签名提交**：提交 `docs(hcodec): 记录ARMv7候选构建`。

## 完成标准

- `experimental/hcodec/` 可在固定 CI 中构建 ARMv7 Linux 6.12 kernel/module/DTB/tool。
- 来源、配置、补丁、uImage 地址、签名策略和固件提取证据可独立复验。
- artifact 为单一 tar.xz，附 manifest/SHA256SUMS，保留 14 天，不含固件二进制或预编译研究模块。
- PR/手动 workflow 均通过，不创建 tag/Release，不刷机，不改 One-KVM。
- `hardware_boot_tested=false`、`hardware_encoder_tested=false` 保持不变。
