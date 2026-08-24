# WS1608 Legacy Kernel Safe Bring-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
**Goal:** Build a manually triggered WS1608 image that first proves a 6.12 recovery boot, then permits one Linux 3.10.107 HDMI/DHCP/SSH/eMMC trial without serial access.
**Architecture:** Preserve the verified OneCloud U-Boot and all non-boot/rootfs burn items. A Bullseye SysV rootfs carries both module trees; revisioned U-Boot state and FAT markers select recovery, one-shot 3.10 trial, or accepted 3.10. This plan stops before encoder execution, One-KVM integration and USB Gadget work.
**Tech Stack:** Hardkernel Linux 3.10.107, verified Armbian 6.12.28 recovery assets, Debian Bullseye armhf, AmlImg, U-Boot scripts, Bash, Node.js tests, GitHub Actions.
**Spec:** `docs/superpowers/specs/2026-08-24-ws1608-legacy-amlenc-bringup-design.md`

## Global Constraints

- Do not modify `.github/workflows/build.yml`, `config/base.env`, stable tags or stable Releases.
- Lock Hardkernel Linux to `5aed95d35d252cafc75ce613a3a0052285662de2`.
- Use `PWM_D` on `GPIODV_28`, VCCK 860000 to 1140000 microvolts.
- Set global CMA to 64 MiB; do not bind `amvenc_avc` to `linux,contiguous-region`.
- Password login remains disabled; a manual candidate requires an operator SSH public key.
- PR jobs run contracts only. Only `workflow_dispatch` creates a flashable artifact.
- Every hardware status stays false in hosted CI.
- Keep every changed source file at 300 lines or fewer.
---

### Task 1: Lock The OneCloud Board Evidence

**Files:**
- Modify: `experimental/amlenc/config/sources.env`
- Modify: `experimental/amlenc/scripts/verify-source-locks.mjs`
- Modify: `experimental/amlenc/tests/stable-boundary.test.mjs`
**Interfaces:**
- Consumes: immutable GitHub repository, commit, path and content digest fields.
- Produces: verified `ONECLOUD_DTS_*` and `ONECLOUD_UBOOT_*` values for kernel metadata.
- [x] **Step 1: Write the failing source-lock test**
Require these exact fields and reject a changed content digest:
```js
for (const key of [
  'ONECLOUD_DTS_REPOSITORY', 'ONECLOUD_DTS_COMMIT',
  'ONECLOUD_DTS_PATH', 'ONECLOUD_DTS_SHA256',
  'ONECLOUD_UBOOT_REPOSITORY', 'ONECLOUD_UBOOT_COMMIT',
]) assert.match(sources, new RegExp(`^${key}=\\S+$`, 'm'));
```
- [x] **Step 2: Run the source-lock tests and confirm RED**
Run: `node --test experimental/amlenc/tests/stable-boundary.test.mjs`
Expected: FAIL because the OneCloud board-evidence locks are absent.
- [x] **Step 3: Add and validate exact board locks**
Add:
```text
ONECLOUD_DTS_REPOSITORY=https://github.com/coolsnowwolf/lede.git
ONECLOUD_DTS_COMMIT=f7fd86eaa58c29fed97da04ab219c74a835a9358
ONECLOUD_DTS_PATH=target/linux/amlogic/files/arch/arm/boot/dts/amlogic/meson8b-onecloud.dts
ONECLOUD_DTS_SHA256=2728716388bb0c023cf380780b7fee7cf3d361ee3144c722e55f22234cae548f
ONECLOUD_UBOOT_REPOSITORY=https://github.com/hzyitc/u-boot.git
ONECLOUD_UBOOT_COMMIT=0038d741ed1c77a77570c3a6bf88fe6189c11733
```
Extend `verify-source-locks.mjs` with repository, 40-hex commit, safe relative
path and 64-hex SHA-256 checks; do not download the LEDE archive.
- [x] **Step 4: Verify and commit**
Run: `node --test experimental/amlenc/tests/stable-boundary.test.mjs && node experimental/amlenc/scripts/verify-source-locks.mjs experimental/amlenc/config/sources.env`
Commit:
```bash
git add experimental/amlenc/config/sources.env experimental/amlenc/scripts/verify-source-locks.mjs experimental/amlenc/tests/stable-boundary.test.mjs
git commit -S -m "chore(amlenc): 固定玩客云板级来源"
```

### Task 2: Correct The 3.10 Board And Encoder Memory Paths

**Files:**
- Modify: `experimental/amlenc/tests/kernel-contract.test.mjs`
- Modify: `experimental/amlenc/tests/kernel-source-diff.test.mjs`
- Modify: `experimental/amlenc/patches/kernel/0001-ws1608-vendor-dts.patch`
- Replace: `experimental/amlenc/patches/kernel/0002-enable-amvenc-avc.patch`
- Modify: `experimental/amlenc/scripts/build-kernel.sh`
- Modify: `experimental/amlenc/scripts/verify-build.sh`
- Modify: `experimental/amlenc/scripts/verify-kernel-source-diff.sh`
**Interfaces:**
- Consumes: pinned Hardkernel kernel and measured OneCloud board facts.
- Produces: verified 3.10.107 zImage, DTB and modules with safe VCCK/CMA policy.
- [x] **Step 1: Write failing kernel contracts**
Require the patch/build/verifier to contain:
```js
assert.match(board, /pmw_controller = "PWM_D"/);
assert.match(board, /amlogic,setmask=<3 0x04000000>/);
assert.match(board, /amlogic,pins="GPIODV_28"/);
assert.doesNotMatch(encoder, /^\+.*linux,contiguous-region/m);
assert.match(encoder, /reserve_buff\[i\]\.buf_size = .*min_buffsize/);
assert.match(build, /--set-val CMA_SIZE_MBYTES 64/);
```
Update source-diff fixtures so only `meson8b_odroidc.dts` and
`drivers/amlogic/amports/encoder.c` are accepted.
- [x] **Step 2: Run focused tests and confirm RED**
Run: `node --test experimental/amlenc/tests/kernel-contract.test.mjs experimental/amlenc/tests/kernel-source-diff.test.mjs`
Expected: FAIL on PWM_D, CMA policy and encoder source fix.
- [x] **Step 3: Implement the minimal kernel changes**
Change the DT to PWM_D/GPIODV_28, retain the OneCloud Ethernet/eMMC/USB/HDMI
nodes, enable `amvenc_avc` without a contiguous-region phandle, and patch:
```c
reserve_buff[i].buf_size =
    amvenc_buffspec[AMVENC_BUFFER_LEVEL_1080P].min_buffsize;
```
Set CMA to 64 MiB with `scripts/config`. Make `verify-build.sh` decompile the
DTB and reject PWM_C/GPIODV_9, an encoder contiguous-region, or CMA below 64.
- [x] **Step 4: Verify hosted kernel contracts and commit**
Run: `node --test experimental/amlenc/tests/kernel-contract.test.mjs experimental/amlenc/tests/kernel-source-diff.test.mjs && bash -n experimental/amlenc/scripts/build-kernel.sh experimental/amlenc/scripts/verify-build.sh experimental/amlenc/scripts/verify-kernel-source-diff.sh`
Commit:
```bash
git add experimental/amlenc/patches/kernel experimental/amlenc/scripts/build-kernel.sh experimental/amlenc/scripts/verify-build.sh experimental/amlenc/scripts/verify-kernel-source-diff.sh experimental/amlenc/tests/kernel-contract.test.mjs experimental/amlenc/tests/kernel-source-diff.test.mjs
git commit -S -m "fix(amlenc): 修正玩客云电压与编码内存"
```

### Task 3: Implement The Recovery-First Boot State Machine

**Files:**
- Create: `experimental/amlenc/scripts/render-legacy-trial-boot.mjs`
- Create: `experimental/amlenc/rootfs/ws1608-amlenc-arm-trial`
- Create: `experimental/amlenc/rootfs/ws1608-amlenc-mark-success`
- Create: `experimental/amlenc/tests/legacy-boot-contract.test.mjs`
**Interfaces:**
- Consumes: `OUTPUT_DIR ROOTFS_UUID BUILD_REVISION`.
- Produces: `boot.cmd`, `armbianEnv.txt`, recovery/trial helpers and marker rules.
- [x] **Step 1: Write failing state-machine tests**
Render revision `b001001` and assert this order:
```js
assert.ok(command.indexOf('amlenc-force-recovery') < command.indexOf('amlenc-3.10.ok'));
assert.ok(command.indexOf('amlenc-3.10.ok') < command.indexOf('amlenc_trial_revision'));
assert.match(command, /saveenv.*boot_recovery/s);
assert.match(command, /uImage\.recovery/);
assert.match(command, /uImage\.amlenc/);
```
Run helper fixtures with overridden `BOOT_DIR`, `UNAME_RELEASE`, `UPTIME_FILE`
and `IP_COMMAND`; reject the wrong kernel, missing IPv4, inactive sshd, uptime
below 60 seconds, and a read-only boot directory.
- [x] **Step 2: Run the new tests and confirm RED**
Run: `node --test experimental/amlenc/tests/legacy-boot-contract.test.mjs`
Expected: FAIL because renderer and helpers do not exist.
- [x] **Step 3: Implement renderer and helpers**
The renderer validates UUID and `b[0-9]{6}` revision. The candidate ships a
nonempty `amlenc-force-recovery`. `ws1608-amlenc-arm-trial` removes only that
file after recovery checks. `ws1608-amlenc-mark-success` writes
`amlenc-3.10.ok` only after all 3.10 checks and `sync`.
- [x] **Step 4: Verify and commit**
Run: `node --test experimental/amlenc/tests/legacy-boot-contract.test.mjs && bash -n experimental/amlenc/rootfs/*`
Commit:
```bash
git add experimental/amlenc/scripts/render-legacy-trial-boot.mjs experimental/amlenc/rootfs experimental/amlenc/tests/legacy-boot-contract.test.mjs
git commit -S -m "feat(amlenc): 增加一次性内核试启动"
```

### Task 4: Assemble The Bullseye Dual-Kernel Candidate

**Files:**
- Create: `experimental/amlenc/config/legacy-bringup.env`
- Create: `experimental/amlenc/scripts/build-legacy-rootfs.sh`
- Create: `experimental/amlenc/scripts/build-legacy-bringup-image.sh`
- Create: `experimental/amlenc/tests/legacy-image-contract.test.mjs`
**Interfaces:**
- Consumes: stable base XZ, AmlImg, 3.10 artifacts, base boot/rootfs and SSH key.
- Produces: one Amlogic burn image plus `manifest.json` with both kernel identities.
- [x] **Step 1: Write failing assembly contracts**
Require Bullseye SysV, both `/lib/modules/3.10.107*` and
`/lib/modules/6.12.28-current-meson`, password locking, public-key-only SSH,
both boot asset sets, and `hardware_boot_tested=false`. Reject One-KVM files.
- [x] **Step 2: Run focused test and confirm RED**
Run: `node --test experimental/amlenc/tests/legacy-image-contract.test.mjs`
Expected: FAIL because the legacy bring-up builder is absent.
- [x] **Step 3: Implement rootfs and image assembly**
Build a 1,400,897,536-byte ext4 rootfs with old-kernel-compatible features.
Copy the recovery module tree and firmware from the stable rootfs, install the
3.10 modules, DHCP, sshd and both helpers, then create a 256 MiB FAT boot image.
Replace only boot/rootfs sparse entries and their VERIFY files in the stable
AmlImg package. Record the SSH public-key digest, source commits, CMA size,
trial revision and all artifact SHA-256 values.
- [x] **Step 4: Verify contracts and commit**
Run: `node --test experimental/amlenc/tests/legacy-image-contract.test.mjs && bash -n experimental/amlenc/scripts/build-legacy-rootfs.sh experimental/amlenc/scripts/build-legacy-bringup-image.sh`
Commit:
```bash
git add experimental/amlenc/config/legacy-bringup.env experimental/amlenc/scripts/build-legacy-rootfs.sh experimental/amlenc/scripts/build-legacy-bringup-image.sh experimental/amlenc/tests/legacy-image-contract.test.mjs
git commit -S -m "feat(amlenc): 构建双内核启动候选"
```

### Task 5: Add Independent Candidate Verification

**Files:**
- Create: `experimental/amlenc/scripts/verify-legacy-bringup-image.sh`
- Modify: `experimental/amlenc/tests/legacy-image-contract.test.mjs`
**Interfaces:**
- Consumes: final image, manifest, decompressed stable base and AmlImg.
- Produces: nonzero exit for any container, boot, rootfs or provenance mismatch.
- [x] **Step 1: Extend the test with verifier requirements**
Assert every non-boot/rootfs command entry matches the stable base byte for
byte; verify both partition SHA-1 files, ext4, both kernel sets, boot order,
force-recovery marker, module trees, helper modes, SSH policy and manifest.
- [x] **Step 2: Run the focused test and confirm RED**
Run: `node --test experimental/amlenc/tests/legacy-image-contract.test.mjs`
- [x] **Step 3: Implement the independent verifier**
Use AmlImg unpack, `cmp`, sparse conversion, `e2fsck -fn`, `mcopy`, `debugfs`,
`file`, `mkimage -l`, `jq`, SHA-1 and SHA-256. Reject a manifest claiming
hardware boot, encoder, One-KVM, HID or MSD success.
- [x] **Step 4: Verify and commit**
Run: `node --test experimental/amlenc/tests/legacy-image-contract.test.mjs && bash -n experimental/amlenc/scripts/verify-legacy-bringup-image.sh`
Commit:
```bash
git add experimental/amlenc/scripts/verify-legacy-bringup-image.sh experimental/amlenc/tests/legacy-image-contract.test.mjs
git commit -S -m "test(amlenc): 验证双内核启动候选"
```

### Task 6: Add An Isolated Manual GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/amlenc-legacy-bringup.yml`
- Create: `experimental/amlenc/tests/legacy-workflow-policy.test.mjs`
**Interfaces:**
- Consumes: required `workflow_dispatch` input `ssh_public_key_b64`.
- Produces: verified five-file artifact; never creates a tag or Release.
- [x] **Step 1: Write failing workflow policy tests**
Require PR contract-only behavior, manual candidate build, nonempty public-key
input, pinned actions, stable-chain checks, post-build verification, 14-day
artifact retention, `contents: read`, no schedule and no release command.
- [x] **Step 2: Run policy tests and confirm RED**
Run: `node --test experimental/amlenc/tests/legacy-workflow-policy.test.mjs`
- [x] **Step 3: Implement the workflow**
Reuse the pinned toolchain/container steps from `amlenc-experimental.yml`, but
build only the kernel and bring-up image. Derive `bRRRAAA` from run number and
attempt. Decode the public key into runner temporary storage, validate it,
package five assets, then download them in a second job and reverify.
- [x] **Step 4: Run local workflow gates and commit**
Run: `node --test experimental/amlenc/tests/legacy-workflow-policy.test.mjs && go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/amlenc-legacy-bringup.yml`
Commit:
```bash
git add .github/workflows/amlenc-legacy-bringup.yml experimental/amlenc/tests/legacy-workflow-policy.test.mjs
git commit -S -m "ci(amlenc): 增加旧内核启动云构建"
```

### Task 7: Run All Gates And Produce The Hardware Candidate

**Files:**
- Modify: `docs/superpowers/plans/2026-08-24-ws1608-legacy-bringup-plan.md`
**Interfaces:**
- Consumes: completed branch and operator public key `~/.ssh/id_rsa.pub`.
- Produces: PR, successful manual Actions run and locally reverified artifact.
- [x] **Step 1: Run all local gates**
```bash
npm test
node --test experimental/amlenc/tests/*.test.mjs
for script in experimental/amlenc/scripts/*.sh experimental/amlenc/rootfs/*; do bash -n "$script"; done
experimental/amlenc/scripts/verify-stable-chain.sh
git diff --check
```
- [x] **Step 2: Push and create a dependent PR**
Push `codex/amlenc-legacy-bringup` and create a PR against
`codex/amlenc-mainline`. Do not merge or publish a Release.
- [x] **Step 3: Dispatch the hardware candidate**
Base64-encode `~/.ssh/id_rsa.pub`, dispatch `amlenc-legacy-bringup.yml`, and
wait for its automatically derived revision and every reverify job to pass.
- [x] **Step 4: Download and independently verify**
Download the five-file artifact outside the Git worktree, run
`verify-legacy-bringup-image.sh`, `sha256sum --check`, and `xz -t`. Confirm the
manifest keeps every hardware field false.
- [x] **Step 5: Mark the plan evidence and commit**
Record the PR/run/artifact identities and checked hashes in this plan, then:
```bash
git add docs/superpowers/plans/2026-08-24-ws1608-legacy-bringup-plan.md
git commit -S -m "docs(amlenc): 记录旧内核启动候选证据"
git push
```

#### Task 7 Evidence — 2026-08-24

- Local full gates: `npm test` 142/142; AMLENC tests 83/83; all changed shell
  files pass `bash -n`; stable-chain verification reports 42 files; source
  lock verification reports 4 locks; actionlint and `git diff --check` pass.
- Dependent PR: [#8](https://github.com/wuhao1477/ws1608-one-kvm-builder/pull/8),
  source branch `codex/amlenc-legacy-bringup`, base
  `codex/amlenc-mainline`, still open and not merged.
- Manual workflow run:
  [32703542651](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/32703542651)
  on commit `3873105`; contract job, candidate build job and downloaded-artifact
  recheck job all succeeded.
- Artifact: GitHub artifact `9511909586`,
  `ws1608-amlenc-legacy-b009001`, five files, 1,329,249,972 bytes; build
  revision `b009001`.
- Candidate image:
  `WS1608-AMLENC-Bringup_b009001_Onecloud_bullseye_3.10.107-recovery6.12.28.burn.img`
  SHA-256 `14a904c15c6acabba718b4a552f061400c584bc7609d867cfe97cbda47029f97`.
- Compressed image:
  `WS1608-AMLENC-Bringup_b009001_Onecloud_bullseye_3.10.107-recovery6.12.28.burn.img.xz`
  SHA-256 `640d397f7f505c0bba42516a29584cca61af114b0927bdb55cf7dc0b28744fdf`.
- Manifest identities: recovery `6.12.28-current-meson`; trial kernel
  `3.10.107`; Hardkernel commit
  `5aed95d35d252cafc75ce613a3a0052285662de2`; CMA `64 MiB`; SSH public-key
  digest `667e9b9b91d9039a32dab4f2f9b198b05271fe79c7417cbbe06734c9b46e8e05`.
- Hosted and downloaded-artifact validation keeps
  `hardware_boot_tested=false`, `hardware_encoder_tested=false`,
  `one_kvm_included=false`, `hid_tested=false`, `msd_tested=false`.
- Local artifact checks: exactly five files; `SHA256SUMS` all OK; `xz -t` OK;
  AmlImg `commands.txt` identical to the stable base; all non-boot/rootfs
  package entries byte-identical to the stable base; boot/rootfs sparse
  partitions changed as intended. The repository verifier's `mkimage -l`
  step was not runnable on macOS because the local Homebrew installation has
  no `mkimage`; the same verifier passed in both Ubuntu Actions jobs.

## Deferred Plans

- Stage C/D: `/dev/amvenc_avc`, bounded mmap and standalone 720p30 encoding.
- Stage E: One-KVM hardware H.264 registration and WebRTC.
- Stage F/G: fixed HID/mass-storage composite Gadget and final single-kernel image.
