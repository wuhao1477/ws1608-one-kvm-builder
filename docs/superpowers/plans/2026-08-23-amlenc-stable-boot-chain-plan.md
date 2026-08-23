# AMLENC Stable Boot Chain Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留已验证的 6.12.28 HDMI 启动链，把 AMLENC 实验限制在 rootfs、用户态 ABI 和后续可独立加载的 6.12 驱动模块中，禁止 3.10.107 内核或自定义 DTB 进入可刷写实验镜像。

**Architecture:** 稳定基础镜像继续由 `config/base.env` 固定；实验工作流复制稳定 boot/rootfs 分区，仅向 rootfs 注入实验 One-KVM、AMLENC 用户态库、诊断工具和 provenance。3.10.107 内核构建保留为研究制品，不再被 `build-burn-image.sh` 消费。后续 6.12 AMLENC 驱动以独立模块/补丁形式验证，未通过设备节点和单帧探测前不启用 One-KVM 的硬件编码注册。

**Tech Stack:** Armbian 6.12.28 Meson kernel, stable AmlImg burn container, One-KVM Rust 0.2.6 armhf, AMLENC ABI v1, Debian rootfs, GitHub Actions, Node.js/Bash tests.

## Global Constraints

- 不修改 `.github/workflows/build.yml`、`config/base.env` 或稳定 Release/Tag 契约。
- 实验 burn image 必须保留稳定基础的 bootloader、boot、resource、kernel、DTB 和 rootfs 分区布局。
- `experimental/amlenc/scripts/build-kernel.sh` 产生的 3.10.107 文件只能作为研究 artifact，不能作为 burn image 输入。
- One-KVM AMLENC 启动探测默认关闭；只有显式 `ONE_KVM_AMLENC_SMOKE_TEST=1` 才执行破坏性探测。
- Hosted CI 不得声明硬件启动、HDMI 或硬件编码已通过。
- 每次实验发布仍为 prerelease，Tag 必须包含 One-KVM 版本、上游 Tag、实验渠道和唯一 build revision。

---

### Task 1: Lock the stable boot-chain boundary

**Files:**
- Modify: `experimental/amlenc/tests/burn-image-contract.test.mjs`
- Modify: `experimental/amlenc/scripts/build-burn-image.sh`
- Modify: `experimental/amlenc/scripts/verify-burn-image.sh`
- Modify: `experimental/amlenc/config/sources.env`

**Interfaces:**
- Consumes: stable `BASE_IMAGE_URL`, `BASE_IMAGE_SHA256`, AmlImg package entries.
- Produces: burn manifest fields identifying stable boot assets and a verifier rejection when diagnostic 3.10 artifacts are supplied.

- [ ] **Step 1: Write the failing test**

  Add a contract fixture asserting that `build-burn-image.sh` reads `BASE_IMAGE_NAME`/`BASE_IMAGE_SHA256`, extracts boot and rootfs from the stable base, and does not reference `out/amlenc/kernel/zImage`, `ws1608-s805.dtb`, or `3.10.107` as burn inputs.

- [ ] **Step 2: Run the focused test**

  Run: `node --test experimental/amlenc/tests/burn-image-contract.test.mjs`

  Expected: FAIL because the current script copies the diagnostic USB image, which embeds the 3.10.107 kernel and DTB.

- [ ] **Step 3: Implement the minimal boundary change**

  Change the burn assembly input from `DIAGNOSTIC_IMAGE` to a stable-base working tree. Preserve the stable boot raw image byte-for-byte; inject only the experimental rootfs payload into the stable rootfs partition. Record `stable_base_preserved=true` and the stable base digest in `manifest.json`.

- [ ] **Step 4: Verify the focused test**

  Run: `node --test experimental/amlenc/tests/burn-image-contract.test.mjs && git diff -- .github/workflows/build.yml config/base.env`

  Expected: tests pass and the stable workflow/base diff is empty.

- [ ] **Step 5: Commit**

  ```bash
  git add experimental/amlenc/tests/burn-image-contract.test.mjs experimental/amlenc/scripts/build-burn-image.sh experimental/amlenc/scripts/verify-burn-image.sh experimental/amlenc/config/sources.env
  git commit -S -m "fix(amlenc): 保留稳定六点一二启动链"
  ```

### Task 2: Build an experimental rootfs on the stable base

**Files:**
- Modify: `experimental/amlenc/scripts/assemble-diagnostic-usb.sh`
- Modify: `experimental/amlenc/scripts/build-diagnostic-image.sh`
- Modify: `experimental/amlenc/scripts/configure-diagnostic-rootfs.sh`
- Create: `experimental/amlenc/scripts/assemble-stable-rootfs.mjs`
- Modify: `experimental/amlenc/tests/diagnostic-image-contract.test.mjs`

**Interfaces:**
- Consumes: stable rootfs raw image, armhf One-KVM package, AMLENC userland artifacts.
- Produces: a rootfs-only experimental artifact with stable kernel/DTB identity and explicit `kernel_source=stable-base` metadata.

- [ ] **Step 1: Write the failing test**

  Add a fixture that rejects a diagnostic manifest with `kernel.version=3.10.107` when used as a burn input, and accepts a manifest that references `BASE_KERNEL=6.12.28-current-meson` while keeping `hardware_encoder_tested=false`.

- [ ] **Step 2: Run the focused test**

  Run: `node --test experimental/amlenc/tests/diagnostic-image-contract.test.mjs`

  Expected: FAIL until rootfs and manifest contracts distinguish stable boot assets from research kernel artifacts.

- [ ] **Step 3: Implement rootfs-only assembly**

  Reuse the stable rootfs partition size and UUID. Install One-KVM, `libvpcodec.so`, `amlenc-m8-diag`, `validate-h264.sh`, hardware limits and release provenance into the stable rootfs. Do not copy a 3.10 kernel, DTB, modules archive, or legacy boot script into the burn image.

- [ ] **Step 4: Verify**

  Run: `node --test experimental/amlenc/tests/diagnostic-image-contract.test.mjs experimental/amlenc/tests/burn-image-contract.test.mjs`

  Expected: all focused tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add experimental/amlenc/scripts experimental/amlenc/tests/diagnostic-image-contract.test.mjs
  git commit -S -m "feat(amlenc): 基于稳定镜像构建实验根文件系统"
  ```

### Task 3: Make AMLENC activation non-destructive by default

**Files:**
- Modify: `experimental/amlenc/patches/one-kvm/0001-detect-meson8b-armv7.patch`
- Modify: `experimental/amlenc/scripts/build-one-kvm.sh`
- Modify: `experimental/amlenc/tests/one-kvm-contract.test.mjs`
- Modify: `experimental/amlenc/docs/bringup.md`

**Interfaces:**
- Consumes: One-KVM source and optional `ONE_KVM_AMLENC_SMOKE_TEST=1` environment variable.
- Produces: a package that starts with software fallback and only runs AMLENC smoke testing when explicitly enabled.

- [ ] **Step 1: Write the failing test**

  Assert the patch contains an explicit environment gate, that the package metadata records `amlenc_smoke_test_default=false`, and that the rootfs service does not export the gate by default.

- [ ] **Step 2: Run the focused test**

  Run: `node --test experimental/amlenc/tests/one-kvm-contract.test.mjs`

  Expected: FAIL if the package still performs the hardware probe during every startup.

- [ ] **Step 3: Implement the gate**

  Keep the Meson8b H.264 registry path, but use software fallback unless `ONE_KVM_AMLENC_SMOKE_TEST=1`. Add a documented one-shot diagnostic command that exports the variable only for manual testing.

- [ ] **Step 4: Verify**

  Run: `node --test experimental/amlenc/tests/one-kvm-contract.test.mjs && bash -n experimental/amlenc/scripts/*.sh`

- [ ] **Step 5: Commit**

  ```bash
  git add experimental/amlenc/patches/one-kvm experimental/amlenc/scripts/build-one-kvm.sh experimental/amlenc/tests/one-kvm-contract.test.mjs experimental/amlenc/docs/bringup.md
  git commit -S -m "fix(amlenc): 默认关闭启动硬件探测"
  ```

### Task 4: Add the 6.12 AMLENC driver research boundary

**Files:**
- Create: `experimental/amlenc/patches/stable-kernel/0001-amlenc-6.12-research-boundary.patch`
- Create: `experimental/amlenc/scripts/verify-stable-kernel-boundary.sh`
- Create: `experimental/amlenc/tests/stable-kernel-boundary.test.mjs`
- Modify: `experimental/amlenc/docs/bringup.md`

**Interfaces:**
- Consumes: stable 6.12.28 kernel identity and 3.10.107 driver ABI notes.
- Produces: a separately verifiable 6.12 module/patch candidate; no change to stable boot assets until hardware validation passes.

- [ ] **Step 1: Write the failing test**

  Require the research patch to target the stable kernel version, keep stable HDMI/eMMC/USB nodes untouched, and expose only a disabled AMLENC device/module path.

- [ ] **Step 2: Run the focused test**

  Run: `node --test experimental/amlenc/tests/stable-kernel-boundary.test.mjs`

  Expected: FAIL because no 6.12 driver boundary exists.

- [ ] **Step 3: Implement the research boundary**

  Do not replace the stable DTB or kernel in the image. Record the old `amvenc_avc` ioctl contract, memory requirements and expected device node; keep the 6.12 candidate disabled until a Linux build produces a loadable module and a device-side test is available.

- [ ] **Step 4: Verify**

  Run: `node --test experimental/amlenc/tests/stable-kernel-boundary.test.mjs && experimental/amlenc/scripts/verify-stable-kernel-boundary.sh`

- [ ] **Step 5: Commit**

  ```bash
  git add experimental/amlenc/patches/stable-kernel experimental/amlenc/scripts/verify-stable-kernel-boundary.sh experimental/amlenc/tests/stable-kernel-boundary.test.mjs experimental/amlenc/docs/bringup.md
  git commit -S -m "feat(amlenc): 建立六点一二驱动研究边界"
  ```

### Task 5: Rebuild and publish the corrected experimental candidate

**Files:**
- Modify: `.github/workflows/amlenc-experimental.yml`
- Modify: `experimental/amlenc/tests/workflow-policy.test.mjs`
- Modify: `docs/superpowers/plans/2026-08-23-amlenc-stable-boot-chain-plan.md`

**Interfaces:**
- Consumes: rootfs-only experimental image, stable base digest, explicit hardware-gate state.
- Produces: PR artifact and prerelease with five assets, stable boot provenance, and no 3.10 kernel/DTB in the burn image.

- [ ] **Step 1: Write the failing workflow test**

  Require the workflow to reject a burn manifest containing `kernel.version=3.10.107`, require `stable_base_preserved=true`, and keep `publish` disabled by default.

- [ ] **Step 2: Run the focused test**

  Run: `node --test experimental/amlenc/tests/workflow-policy.test.mjs`

- [ ] **Step 3: Update the workflow**

  Build the research kernel as a separate artifact, but pass only the stable base and rootfs package to the burn-image builder. Keep the existing post-upload download verification and prerelease-only policy.

- [ ] **Step 4: Run all local gates**

  ```bash
  npm test
  node --test experimental/amlenc/tests/*.test.mjs
  for script in experimental/amlenc/scripts/*.sh; do bash -n "$script"; done
  git diff --check
  ```

- [ ] **Step 5: Run GitHub Actions**

  First dispatch with `publish=false`; inspect the artifact manifest and assert the boot partition digest equals the stable base boot digest. Then dispatch with `publish=true` and `acknowledge_experimental=true` only after the artifact checks pass.

- [ ] **Step 6: Commit**

  ```bash
  git add .github/workflows/amlenc-experimental.yml experimental/amlenc/tests/workflow-policy.test.mjs docs/superpowers/plans/2026-08-23-amlenc-stable-boot-chain-plan.md
  git commit -S -m "ci(amlenc): 发布稳定启动链实验候选"
  ```

## Verification Checklist

- [ ] `npm test` passes.
- [ ] `node --test experimental/amlenc/tests/*.test.mjs` passes.
- [ ] Every experimental shell script passes `bash -n`.
- [ ] Stable workflow and `config/base.env` have no diff.
- [ ] Burn image boot partition matches the stable base boot partition.
- [ ] Burn manifest does not contain `kernel.version=3.10.107`.
- [ ] One-KVM package verification reports Rust `1.97.1`.
- [ ] Hosted CI report keeps hardware boot and encoder status false.
- [ ] Release has exactly five assets and remains prerelease.
