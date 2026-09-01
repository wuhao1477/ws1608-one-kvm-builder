# Armbian 6.12 HCODEC 文档迁移实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修改仓库全部 Markdown 文档，使 Armbian 26.8 / Trixie / Linux 6.12.28 HCODEC V4L2 M2M 成为唯一有效研发路线，并把 Linux 3.10 路线改为不可执行的历史记录。

**Architecture:** 稳定通道继续使用已验证的 `base-20260804-consolefix`，硬件编码作为独立 Linux 6.12 内核候选研发。文档明确区分“已验证的 Armbian 基础”和“尚未实机验证的 HCODEC 候选”，不修改任何代码、配置或工作流。

**Tech Stack:** Markdown、Armbian 26.8、Debian Trixie、Linux 6.12.28、Meson8b/S805 HCODEC、V4L2 M2M、One-KVM `h264_v4l2m2m`。

**Spec:** `docs/superpowers/specs/2026-09-01-armbian-hcodec-route-design.md`

## Global Constraints

- 唯一系统底座是 `base-20260804-consolefix`、Armbian `26.8.0-trunk.413`、Debian Trixie、Linux `6.12.28-current-meson`。
- 唯一硬件编码研发接口是 Linux 6.12 `meson-venc` HCODEC V4L2 M2M。
- Linux `3.10.107`、Bullseye、`/dev/amvenc_avc`、`libvpcodec`、双内核和 kexec 只允许出现在明确的已废弃历史说明中。
- 不保留可直接执行的 3.10 构建、刷写、切换或试启动步骤。
- 已验证 Armbian 基础与 HCODEC 候选状态分开记录；HCODEC 候选保持 `hardware_boot_tested=false` 和 `hardware_encoder_tested=false`。
- One-KVM 实验接入使用 `h264_v4l2m2m` 与 `ONE_KVM_V4L2M2M_ALLOW=1`，实机通过前不写入稳定服务环境。
- `cma=128M` 是基于内存预算的候选值，不是 WS1608 已验证配置。
- 现成 `meson-venc.ko` 是 AArch64 `6.12.98-ipkvm-release`，不得描述为可直接加载到 ARMv7 6.12.28。
- 18 个补丁与最终驱动源码不是同一修订，后续实现必须选择一致源码基线。
- 本计划只允许修改或新增 `.md` 文件；`Downloads/` 保持未跟踪，不提交。
- 不写入本机绝对路径、Codex 任务 ID、IP、密码、私钥或设备序列号。
- 所有 Git 提交使用 SSH/GPG 签名，提交信息遵循 `<type>(scope): <中文动词摘要>`。

---

### Task 1: 建立正式路线决策和文档导航

**Files:**
- Create: `docs/adr/0003-armbian-6.12-hcodec-route.md`
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/HANDOFF.md`

**Interfaces:**
- Consumes: 已批准路线规格、当前稳定基础元数据和参考资料结论。
- Produces: 全仓库当前状态入口、正式 ADR 和后续文档共同引用的术语。

- [ ] **Step 1: 记录迁移前的失败基线**

```bash
rg -n '3\.10|Bullseye|amvenc_avc|libvpcodec|双内核|kexec' \
  README.md docs/README.md docs/HANDOFF.md
```

Expected: 至少发现旧版本状态或旧路线缺失，证明当前入口文档尚未完整描述 Armbian 6.12 HCODEC 决策。

- [ ] **Step 2: 创建 ADR-0003**

写入以下固定章节：

```markdown
# ADR-0003：放弃 Linux 3.10，采用 Armbian Linux 6.12 HCODEC

- 状态：Accepted
- 日期：2026-09-01

## 背景
## 新证据
## 决策
## 已废弃内容
## 验证边界
## 结果
## 后续变更条件
```

`决策` 必须声明稳定基础、V4L2 M2M、One-KVM 后端和候选发布边界；`新证据` 必须记录 18 个补丁、ARM64 模块不兼容、固件缺失、时钟/HHI 缺口和 CMA 预算。

- [ ] **Step 3: 重写 README 当前路线**

保留稳定自动更新和五资产发布说明，新增“硬件编码研发路线”章节。明确稳定镜像继续可用，HCODEC 是独立候选，3.10 已废弃，当前不宣称硬件编码通过。

- [ ] **Step 4: 更新文档索引**

在 `docs/README.md` 中把 ADR-0003、路线规格、实施计划、HCODEC 验收和排障文档列为当前入口；两份 2026-08 计划仅列在“已废弃历史”下。

- [ ] **Step 5: 重写交接文档**

`docs/HANDOFF.md` 必须记录：

- `main` 当前稳定与实验发布历史；
- Armbian 6.12 是唯一有效底座；
- HCODEC 资料成熟度和已知缺口；
- 当前没有可加载的 ARMv7 模块和 Meson8b 固件；
- 下一步从可复现 ARMv7 内核构建开始；
- 3.10 分支和产物不再继续。

- [ ] **Step 6: 验证入口文档**

```bash
rg -n 'Armbian|6\.12\.28|HCODEC|V4L2 M2M|hardware_encoder_tested=false' \
  README.md docs/README.md docs/HANDOFF.md docs/adr/0003-armbian-6.12-hcodec-route.md
rg -n '执行.*3\.10|刷入.*3\.10|构建.*3\.10|使用.*amvenc_avc' \
  README.md docs/README.md docs/HANDOFF.md docs/adr/0003-armbian-6.12-hcodec-route.md && exit 1 || true
git diff --check -- README.md docs/README.md docs/HANDOFF.md docs/adr/0003-armbian-6.12-hcodec-route.md
```

Expected: 第一条在四个文件中找到新路线，第二条无输出，格式检查退出 0。

- [ ] **Step 7: 创建签名提交**

```bash
git add README.md docs/README.md docs/HANDOFF.md docs/adr/0003-armbian-6.12-hcodec-route.md
git commit -S -m "docs(architecture): 采用Armbian HCODEC路线"
```

---

### Task 2: 重写架构、构建、来源和维护文档

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/build-pipeline.md`
- Modify: `docs/image-lineage.md`
- Modify: `docs/maintenance.md`
- Modify: `docs/manifest-schema.md`
- Modify: `docs/adr/0001-pinned-base-weekly-check.md`
- Modify: `docs/adr/0002-immutable-versioned-rebuilds.md`

**Interfaces:**
- Consumes: ADR-0003 的稳定/候选边界和现有稳定五资产发布契约。
- Produces: 后续内核候选工作流、manifest 和维护工作的统一规则。

- [ ] **Step 1: 重写架构数据流**

`docs/architecture.md` 保留稳定 rootfs 更新数据流，并增加独立候选链：

```text
固定 Armbian 6.12 源码/配置
→ 一致的 meson-venc 补丁基线
→ ARMv7 内核/模块/DTB/固件
→ 静态验证
→ 独立 V4L2 实机探针
→ One-KVM 显式 V4L2 M2M 探针
→ 候选镜像
→ 实机验收
```

明确候选链不得修改稳定 Release。

- [ ] **Step 2: 更新构建流程文档**

`docs/build-pipeline.md` 继续准确描述现有 `.github/workflows/build.yml`，另设“未来 HCODEC 候选流程”章节。该章节只能描述计划接口，不得声称工作流已经实现。

- [ ] **Step 3: 更新镜像来源**

`docs/image-lineage.md` 记录 `base-20260804-consolefix` 继续作为稳定父镜像；Linux 3.10 只保留失败历史；HCODEC 候选必须从与稳定基础匹配的 Armbian/Linux 6.12 源码重建。

- [ ] **Step 4: 更新维护规则**

`docs/maintenance.md` 增加以下禁区：

- 不恢复 3.10 分支；
- 不加载资料中的 AArch64 模块；
- 不混用 18 个补丁和最终源码；
- 不缺省启用 `ONE_KVM_V4L2M2M_ALLOW=1`；
- 不用教程性能值替代 WS1608 实测。

- [ ] **Step 5: 扩展 manifest 文档**

`docs/manifest-schema.md` 为未来候选定义以下证据字段，并明确它们尚未由当前工作流生成：

```json
{
  "kernel_base": { "const": "6.12.28-current-meson" },
  "encoder_backend": { "const": "h264_v4l2m2m" },
  "driver_source_sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
  "firmware_sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
  "cma_mib": { "type": "integer", "minimum": 1 },
  "hardware_boot_tested": { "type": "boolean" },
  "hardware_encoder_tested": { "type": "boolean" }
}
```

候选 manifest 实例仍必须记录实际摘要和实际 CMA 数值。

- [ ] **Step 6: 修订 ADR-0001 和 ADR-0002**

ADR-0001 增加 ADR-0003 引用并说明固定基础决策支持 Linux 6.12 路线；ADR-0002 增加未实机验证 HCODEC 候选只能作为 prerelease、不得覆盖稳定资产的规则。

- [ ] **Step 7: 验证架构文档**

```bash
rg -n 'HCODEC|V4L2 M2M|6\.12\.28|ADR-0003' \
  docs/architecture.md docs/build-pipeline.md docs/image-lineage.md \
  docs/maintenance.md docs/manifest-schema.md docs/adr/0001-pinned-base-weekly-check.md \
  docs/adr/0002-immutable-versioned-rebuilds.md
git diff --check -- docs/architecture.md docs/build-pipeline.md docs/image-lineage.md \
  docs/maintenance.md docs/manifest-schema.md docs/adr
```

Expected: 每个文件至少包含一个当前路线或 ADR 引用，格式检查退出 0。

- [ ] **Step 8: 创建签名提交**

```bash
git add docs/architecture.md docs/build-pipeline.md docs/image-lineage.md \
  docs/maintenance.md docs/manifest-schema.md docs/adr/0001-pinned-base-weekly-check.md \
  docs/adr/0002-immutable-versioned-rebuilds.md
git commit -S -m "docs(architecture): 更新六点一二候选架构"
```

---

### Task 3: 重写 HCODEC 实机验收和排障文档

**Files:**
- Modify: `docs/hardware-validation.md`
- Modify: `docs/troubleshooting.md`
- Modify: `experimental/amlenc/docs/bringup.md`

**Interfaces:**
- Consumes: Linux 6.12 V4L2 M2M 设备接口、CMA 预算和 One-KVM 显式探测开关。
- Produces: 从内核启动到 H.264 码流、One-KVM、HID 和重启的可执行验收流程。

- [ ] **Step 1: 重写硬件验收阶段**

`docs/hardware-validation.md` 按以下阶段组织：

1. 稳定基础回归：HDMI、网络、SSH、eMMC、One-KVM 软件编码；
2. 候选内核识别：`uname -r`、内核配置、DT compatible、CMA；
3. V4L2 拓扑：`v4l2-ctl --list-devices`、`media-ctl -p`；
4. 独立 H.264 探针：640×480、1280×720，再评估 1920×1080；
5. 码流验证：SPS/PPS/IDR、分辨率、帧数、完整解码；
6. One-KVM 显式探针；
7. USB 视频、HID、虚拟介质、重启、温度和长时间运行。

- [ ] **Step 2: 写入只读诊断命令**

文档使用以下命令，不使用 3.10 工具：

```bash
uname -a
cat /proc/cmdline
grep -E 'CmaTotal|CmaFree' /proc/meminfo
v4l2-ctl --list-devices
v4l2-ctl -d /dev/video0 --all
media-ctl -p
dmesg | grep -Ei 'meson-venc|hcodec|firmware|cma|dma|canvas|timeout|oops|panic'
```

设备节点编号必须由 `v4l2-ctl --list-devices` 确认，不能假定永久是 `/dev/video0`。

- [ ] **Step 3: 写入独立编码与校验流程**

使用资料自带的 ARMv7 MMAP/DMABUF 测试工具或匹配候选内核构建的工具产生 Annex-B H.264，再用：

```bash
ffprobe -v error -show_streams candidate.h264
ffmpeg -v error -i candidate.h264 -f null -
```

文档必须要求保存候选内核摘要、DTB 摘要、固件摘要、CMA、测试参数和筛选后的内核日志。

- [ ] **Step 4: 写入 One-KVM 显式测试**

只在独立探针通过后执行：

```bash
ONE_KVM_V4L2M2M_ALLOW=1 /usr/bin/one-kvm
```

明确这是临时实验命令；稳定服务配置保持不变。验证 API 报告 `h264_v4l2m2m`，并确认失败时软件编码仍可用。

- [ ] **Step 5: 重写排障矩阵**

`docs/troubleshooting.md` 增加以下故障分层：

- 模块无法加载：架构、vermagic、符号或配置不一致；
- DT probe 失败：时钟 ID、HHI syscon、DOS 地址、IRQ、Canvas 冲突；
- 固件失败：文件缺失、摘要不一致、DMA 上传失败；
- 分配失败：CMA 太小或碎片化；
- 编码超时：HCODEC 时钟、电源、复位、邮箱 IRQ；
- 码流损坏：缓冲区、Canvas/MFDIN、SPS/PPS/IDR；
- One-KVM 不发现后端：环境开关、V4L2 格式或设备权限。

- [ ] **Step 6: 重写实验 bring-up 文档**

`experimental/amlenc/docs/bringup.md` 删除全部 3.10、双内核和私有 AMLENC 步骤，改为候选内核构建产物清单、稳定基础回归、V4L2 探针和停止条件。

- [ ] **Step 7: 验证不存在旧执行路径**

```bash
rg -n 'ws1608-amlenc-arm-trial|ws1608-amlenc-kexec-trial|uImage\.amlenc|/dev/amvenc_avc|LD_LIBRARY_PATH=.*libvpcodec' \
  docs/hardware-validation.md docs/troubleshooting.md experimental/amlenc/docs/bringup.md && exit 1 || true
rg -n 'v4l2-ctl|media-ctl|h264_v4l2m2m|ONE_KVM_V4L2M2M_ALLOW|CmaTotal' \
  docs/hardware-validation.md docs/troubleshooting.md experimental/amlenc/docs/bringup.md
git diff --check -- docs/hardware-validation.md docs/troubleshooting.md experimental/amlenc/docs/bringup.md
```

Expected: 旧路径扫描无输出，新路线扫描覆盖三个文件，格式检查退出 0。

- [ ] **Step 8: 创建签名提交**

```bash
git add docs/hardware-validation.md docs/troubleshooting.md experimental/amlenc/docs/bringup.md
git commit -S -m "docs(validation): 改用V4L2硬件编码验收"
```

---

### Task 4: 更新第三方边界并归档旧计划

**Files:**
- Modify: `THIRD_PARTY.md`
- Modify: `experimental/amlenc/docs/licensing.md`
- Modify: `docs/superpowers/plans/2026-08-13-ws1608-s805-amlenc-experimental-plan.md`
- Modify: `docs/superpowers/plans/2026-08-14-ws1608-amlenc-next-version-plan.md`
- Modify: `docs/superpowers/plans/2026-07-20-versioned-releases-plan.md`
- Modify: `docs/superpowers/specs/2026-07-20-versioned-releases-design.md`
- Modify: `docs/superpowers/specs/2026-09-01-armbian-hcodec-route-design.md`

**Interfaces:**
- Consumes: GPL 驱动来源、固件来源要求、已完成稳定发布历史和 ADR-0003。
- Produces: 不会被误执行的历史记录及完整许可证边界。

- [ ] **Step 1: 更新第三方来源**

`THIRD_PARTY.md` 增加 Linux 6.12 `meson-venc` 参考实现、内核补丁、测试工具和固件提取脚本。明确代码适用 GPL-2.0 及各文件 SPDX，固件必须单独确认来源与再分发条件。

- [ ] **Step 2: 重写实验许可证文档**

`experimental/amlenc/docs/licensing.md` 删除把 `libvpcodec` 作为未来交付依赖的描述，改为：

- 旧 `libvpcodec` 仅为已废弃研究历史；
- 新驱动和补丁按其 SPDX/GPL 条款处理；
- 固件没有来源、摘要和授权记录时不得进入公开产物；
- 测试工具二进制必须由仓库固定源码构建，不能发布资料中的预编译文件。

- [ ] **Step 3: 替换 2026-08-13 旧计划**

将文件改为不超过 80 行的历史记录，固定包含：原目标、已完成研究、失败原因、废弃日期、ADR-0003、新路线规格链接。删除全部复选框、构建命令和 3.10 执行步骤。

- [ ] **Step 4: 替换 2026-08-14 旧计划**

采用相同归档结构，保留 One-KVM ARMv7、软件编码和实验门禁的历史结论；明确私有 AMLENC 集成不再继续。删除全部复选框、构建命令和 3.10 执行步骤。

- [ ] **Step 5: 标记 2026-07 稳定发布设计与计划**

在两个文件开头增加“历史稳定发布设计，仍适用于 One-KVM rootfs 自动更新；硬件编码路线由 ADR-0003 管理”的说明。不要改写已完成的发布步骤。

- [ ] **Step 6: 补充规格文档关联**

在本规格的“新增文档”中把 ADR-0003 和本实施计划标记为已创建，并增加第三方资料许可证边界引用。

- [ ] **Step 7: 验证归档不可执行**

```bash
test -z "$(rg -n '^- \[[ xX]\]' \
  docs/superpowers/plans/2026-08-13-ws1608-s805-amlenc-experimental-plan.md \
  docs/superpowers/plans/2026-08-14-ws1608-amlenc-next-version-plan.md || true)"
rg -n '已废弃|ADR-0003|2026-09-01-armbian-hcodec-route-design' \
  docs/superpowers/plans/2026-08-13-ws1608-s805-amlenc-experimental-plan.md \
  docs/superpowers/plans/2026-08-14-ws1608-amlenc-next-version-plan.md
rg -n '固件|SPDX|GPL|预编译' THIRD_PARTY.md experimental/amlenc/docs/licensing.md
git diff --check -- THIRD_PARTY.md experimental/amlenc/docs/licensing.md docs/superpowers
```

Expected: 两份归档没有复选框，废弃状态和新路线链接存在，许可证关键词存在，格式检查退出 0。

- [ ] **Step 8: 创建签名提交**

```bash
git add THIRD_PARTY.md experimental/amlenc/docs/licensing.md \
  docs/superpowers/plans/2026-08-13-ws1608-s805-amlenc-experimental-plan.md \
  docs/superpowers/plans/2026-08-14-ws1608-amlenc-next-version-plan.md \
  docs/superpowers/plans/2026-07-20-versioned-releases-plan.md \
  docs/superpowers/specs/2026-07-20-versioned-releases-design.md \
  docs/superpowers/specs/2026-09-01-armbian-hcodec-route-design.md
git commit -S -m "docs(amlenc): 归档三点一零实验路线"
```

---

### Task 5: 验证全部文档和变更范围

**Files:**
- Verify: every tracked `*.md` outside `Downloads/`
- Verify: Git commits introduced by this plan

**Interfaces:**
- Consumes: Tasks 1-4 的全部文档变更。
- Produces: 可证明全部文档使用新路线、旧路线不可执行且非文档文件未变化的验证记录。

- [ ] **Step 1: 生成 Markdown 清单**

```bash
rg --files -g '*.md' -g '!Downloads/**' | sort
```

Expected: 清单包含原有 19 个 Markdown、路线规格、本计划和 ADR-0003，共 22 个文件。

- [ ] **Step 2: 检查全部文件已纳入迁移**

```bash
git diff --name-only origin/main...HEAD -- '*.md' | sort
```

Expected: 输出包含 Step 1 的全部 21 个文件；没有遗漏的旧文档。

- [ ] **Step 3: 扫描旧路线的主动指令**

```bash
rg -n -i '(执行|构建|刷入|切换|启动|采用|使用).*(3\.10|Bullseye|amvenc_avc|libvpcodec|kexec|双内核)' \
  --glob '*.md' --glob '!Downloads/**'
```

Expected: 只允许命中含“已废弃”“不得”“不再”语义的历史说明；逐条检查并改写任何仍可解释为当前指令的行。

- [ ] **Step 4: 扫描新路线和事实边界**

```bash
rg -l 'Armbian|Linux 6\.12|6\.12\.28|HCODEC|V4L2 M2M' \
  --glob '*.md' --glob '!Downloads/**' | sort
rg -n 'hardware_boot_tested=false|hardware_encoder_tested=false|尚未实机验证|不得.*已验证' \
  --glob '*.md' --glob '!Downloads/**'
```

Expected: 当前状态、架构、构建、维护、验收、排障和实验文档均命中新路线；候选文档明确保留未验证边界。

- [ ] **Step 5: 检查隐私和不可移植引用**

```bash
node --input-type=module <<'NODE'
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
const files = execFileSync('rg', ['--files', '-g', '*.md', '-g', '!Downloads/**'], { encoding: 'utf8' })
  .trim().split('\n').filter(Boolean);
const patterns = [new RegExp(['/', 'Users', '/'].join('')), new RegExp(['codex', '://'].join('')),
  /192[.]168[.][0-9]+[.][0-9]+/, new RegExp(['BEGIN ', 'PRIVATE KEY'].join('')),
  new RegExp(['password', '='].join(''))];
const matches = files.flatMap((file) => fs.readFileSync(file, 'utf8').split('\n')
  .flatMap((line, index) => patterns.some((pattern) => pattern.test(line))
    ? [`${file}:${index + 1}:${line}`] : []));
if (matches.length) { console.error(matches.join('\n')); process.exit(1); }
console.log('no private or machine-local references');
NODE
```

Expected: `no private or machine-local references`。

- [ ] **Step 6: 检查相对 Markdown 链接**

```bash
node --input-type=module <<'NODE'
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
const files = execFileSync('rg', ['--files', '-g', '*.md', '-g', '!Downloads/**'], { encoding: 'utf8' })
  .trim().split('\n').filter(Boolean);
const missing = [];
for (const file of files) {
  for (const match of fs.readFileSync(file, 'utf8').matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
    const target = match[1].replace(/^<|>$/g, '').split('#', 1)[0];
    if (!target || /^[a-z]+:/i.test(target) || target.startsWith('#')) continue;
    const resolved = path.resolve(path.dirname(file), decodeURIComponent(target));
    if (!fs.existsSync(resolved)) missing.push(`${file}: ${target}`);
  }
}
if (missing.length) { console.error(missing.join('\n')); process.exit(1); }
console.log(`verified ${files.length} Markdown files`);
NODE
```

Expected: `verified 22 Markdown files`。

- [ ] **Step 7: 检查只有文档发生变化**

```bash
test -z "$(git diff --name-only origin/main...HEAD | grep -vE '\.md$' || true)"
git diff --check origin/main...HEAD
npm test
```

Expected: 非 Markdown 变更为空，格式检查退出 0，现有 Node 测试零失败。

- [ ] **Step 8: 检查签名和工作区状态**

```bash
for commit in $(git rev-list --reverse origin/main..HEAD); do
  git cat-file commit "$commit" | grep -q '^gpgsig '
done
git status --short --branch
```

Expected: 所有新提交包含 `gpgsig`；状态只允许显示未跟踪的 `Downloads/`，没有未提交的文档变化。
