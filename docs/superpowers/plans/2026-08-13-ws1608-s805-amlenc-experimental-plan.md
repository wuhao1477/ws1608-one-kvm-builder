# WS1608 S805 AMLENC Experimental Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变现有稳定镜像自动生成链路的前提下，建立 WS1608/S805 H.264 硬件编码实验版本，并验证 One-KVM 0.2.6+、USB HDMI 采集、HID 和 MSD 可以同时工作。

**Architecture:** 稳定通道继续使用 `.github/workflows/build.yml`、`config/base.env` 和现有五资产 Release 契约。新版本全部放在 `experimental/amlenc/`，由独立的手动/PR 工作流构建；先验证 S805 编码器，再接入 One-KVM，最后处理 USB Gadget 和直刷镜像。任何实验产物只发布为 prerelease，完成实体 WS1608 验收后仍需单独 PR 才能改变稳定基础。

**Tech Stack:** Linux 3.10.107 armhf、Hardkernel S805/Meson8b 内核、Amlogic `amvenc_avc`、M8 `libvpcodec`、One-KVM Rust、Debian 11 Bullseye、GitHub Actions、AmlImg、Node.js 测试、Bash。

## Global Constraints

- 不修改 `.github/workflows/build.yml` 的每周日 `02:17 UTC` 检查、无更新跳过、权限分离和发布行为。
- 不修改 `config/base.env` 当前固定的 `base-20260804-consolefix`，除非实验版本完成全部实体验收并通过独立晋级 PR。
- 不复用或覆盖 `ws1608-one-kvm-*` 稳定 tag；实验 tag 使用 `ws1608-amlenc-exp-<one-kvm-version>-<upstream-tag>-k3.10.107-bRRRAAA`。
- 实验工作流不配置 `schedule` 和 `repository_dispatch`，只允许 `pull_request` 与手动 `workflow_dispatch`。
- 所有实验 Release 必须设置 `prerelease=true`，同一版本多次构建必须生成新的不可变 tag。
- 首个性能目标固定为 `1280x720@30 H.264`、NV12 输入；验证完成前不承诺 1080p，不实现 H.265。
- 编码最小验证没有产生包含 SPS/PPS/IDR 且可被 FFmpeg 解码的 H.264 时，停止后续 One-KVM、USB Gadget 和镜像集成。
- GitHub 托管 runner 只证明源码、内核、rootfs、镜像和发布资产通过静态检查，不得标记实体硬件通过。
- `khadas/libencoder`、测试工具或其他无明确许可证的代码，在许可证核查完成前只用于研究和本地验证，不放入公开 Release。
- 稳定通道现有五项资产、manifest schema 2、Amlogic CRC、分区 VERIFY、ext4 和上传后复验机制保持原样。

## Source Locks

实验分支开始时固定以下已核对输入；升级必须提交 digest 变化和重新验证证据：

```text
hardkernel/linux ref=odroidc-3.10.y commit=5aed95d35d252cafc75ce613a3a0052285662de2
khadas/libencoder ref=yocto-kirkstone-202406-smarthome commit=bfee62dad4f7ebb6d1705df8522da871dcad861e
mofeng-git/One-KVM tag=v260802 commit=a4073d64cb49a1404df49e7813b73dd9f78d0931 version=0.2.6
mofeng-git/amlenc ref=master commit=a28b6b33819ef1d261c0c1deac7bd880321a44e5
kernel=3.10.107
userspace=Debian 11 Bullseye armhf
```

## Planned File Structure

```text
.github/workflows/amlenc-experimental.yml
experimental/amlenc/config/sources.env
experimental/amlenc/config/hardware-limits.json
experimental/amlenc/patches/kernel/0001-ws1608-vendor-dts.patch
experimental/amlenc/patches/kernel/0002-enable-amvenc-avc.patch
experimental/amlenc/patches/kernel/0003-configfs-hid-msd.patch
experimental/amlenc/patches/libencoder/0001-enable-m8-armhf.patch
experimental/amlenc/patches/libencoder/0002-one-kvm-abi-v1.patch
experimental/amlenc/patches/one-kvm/0001-detect-meson8b-armv7.patch
experimental/amlenc/scripts/verify-source-locks.mjs
experimental/amlenc/scripts/build-kernel.sh
experimental/amlenc/scripts/build-libvpcodec.sh
experimental/amlenc/scripts/build-one-kvm.sh
experimental/amlenc/scripts/build-image.sh
experimental/amlenc/scripts/verify-build.sh
experimental/amlenc/scripts/verify-image.sh
experimental/amlenc/scripts/package-release.sh
experimental/amlenc/tests/*.test.mjs
experimental/amlenc/docs/bringup.md
experimental/amlenc/docs/hardware-validation.md
experimental/amlenc/docs/licensing.md
```

---

### Task 1: Protect The Existing Stable Channel

**Files:**
- Create: `experimental/amlenc/tests/stable-boundary.test.mjs`
- Create: `experimental/amlenc/config/sources.env`
- Create: `experimental/amlenc/scripts/verify-source-locks.mjs`

**Interfaces:**
- Consumes: stable workflow/config text and experimental source lock variables.
- Produces: a nonzero result when the stable cron/base/release prefix changes or an experimental source is not pinned to a 40-character commit.

- [ ] **Step 1: Write the failing policy test**

  Assert that `.github/workflows/build.yml` still contains `cron: "17 2 * * 0"`, reads `config/base.env`, uses `ws1608-one-kvm-`, and does not reference `experimental/amlenc`. Assert that `config/base.env` contains `BASE_RELEASE_TAG=base-20260804-consolefix`.

- [ ] **Step 2: Run the test and observe RED**

  Run: `node --test experimental/amlenc/tests/stable-boundary.test.mjs`

  Expected: FAIL because the experimental source lock and validator do not exist.

- [ ] **Step 3: Add exact source locks and validation**

  Store the four repository URLs, exact commits, kernel version, Debian suite, One-KVM tag/version, and SHA-256 fields for every downloaded archive in `sources.env`. Reject a moving branch as a build input even when the informational ref name is retained.

- [ ] **Step 4: Run focused and stable tests**

  Run: `node --test experimental/amlenc/tests/stable-boundary.test.mjs && npm test`

  Expected: both commands pass; `git diff -- .github/workflows/build.yml config/base.env` is empty.

- [ ] **Step 5: Commit**

  ```bash
  git add experimental/amlenc/config/sources.env experimental/amlenc/scripts/verify-source-locks.mjs experimental/amlenc/tests/stable-boundary.test.mjs
  git commit -S -m "test(amlenc): 保护稳定镜像构建边界"
  ```

### Task 2: Build A WS1608 S805 Vendor Kernel

**Files:**
- Create: `experimental/amlenc/patches/kernel/0001-ws1608-vendor-dts.patch`
- Create: `experimental/amlenc/patches/kernel/0002-enable-amvenc-avc.patch`
- Create: `experimental/amlenc/scripts/build-kernel.sh`
- Create: `experimental/amlenc/scripts/verify-build.sh`
- Create: `experimental/amlenc/tests/kernel-contract.test.mjs`

**Interfaces:**
- Consumes: pinned Hardkernel kernel tree and the WS1608 factory DTS values.
- Produces: ARM `zImage`, WS1608 DTB, modules archive, `.config`, source manifest and SHA-256 list.

- [ ] **Step 1: Write the failing kernel contract test**

  Require the patch set to retain WS1608 eMMC, Ethernet, HDMI and both USB controllers; require an enabled `amvenc_avc` node bound to an 18 MiB contiguous region. Require `CONFIG_CMA=y`, `CONFIG_AMLOGIC_ION=y`, `CONFIG_USB_GADGET=y` and the Amlogic encoder driver.

- [ ] **Step 2: Run the test and observe RED**

  Run: `node --test experimental/amlenc/tests/kernel-contract.test.mjs`

  Expected: FAIL because the kernel patches and build script are absent.

- [ ] **Step 3: Add the WS1608 DTS patch**

  Base it on the factory `m8b_m201_1G` description. Keep `amvenc_avc`, `codec_mm`, `ppmgr`, `ion_dev`, HDMI, eMMC and network nodes. Set the encoder CMA region to exactly `0x01200000`; do not copy ODROID-specific GPIO assignments.

- [ ] **Step 4: Add the kernel build and artifact verifier**

  Build with an Ubuntu arm-linux-gnueabihf cross-toolchain. The verifier must use `file`, `readelf`, `dtc -I dtb -O dts`, `scripts/config --state`, `sha256sum --check`, and reject untracked source changes after patch application.

- [ ] **Step 5: Build and verify in Linux CI**

  Run: `experimental/amlenc/scripts/build-kernel.sh && experimental/amlenc/scripts/verify-build.sh kernel`

  Expected: exit 0; decompiled DTB contains `amlogic,amvenc_avc` and `reg = <0x0 0x1200000>`; kernel is ARM EABI and reports `3.10.107`.

- [ ] **Step 6: Commit**

  ```bash
  git add experimental/amlenc/patches/kernel experimental/amlenc/scripts/build-kernel.sh experimental/amlenc/scripts/verify-build.sh experimental/amlenc/tests/kernel-contract.test.mjs
  git commit -S -m "feat(amlenc): 构建WS1608厂商编码内核"
  ```

### Task 3: Build The M8 Encoder Library And Diagnostic

**Files:**
- Create: `experimental/amlenc/patches/libencoder/0001-enable-m8-armhf.patch`
- Create: `experimental/amlenc/patches/libencoder/0002-one-kvm-abi-v1.patch`
- Create: `experimental/amlenc/scripts/build-libvpcodec.sh`
- Create: `experimental/amlenc/tests/libvpcodec-abi.test.mjs`
- Create: `experimental/amlenc/docs/licensing.md`

**Interfaces:**
- Consumes: `/dev/amvenc_avc`, contiguous NV12 and M8 ioctl ABI.
- Produces: armhf `libvpcodec.so`, `amlenc-m8-diag`, symbol report and source/license manifest.

- [ ] **Step 1: Write the failing ABI test**

  Require an ELF32 ARM shared object exporting exactly `one_kvm_amlenc_abi_version`, `vl_video_encoder_init`, `vl_video_encoder_encode` and the vendor-compatible `vl_video_encoder_destory`. Require the ABI marker to return `1` in an armhf test harness.

- [ ] **Step 2: Run the test and observe RED**

  Run: `node --test experimental/amlenc/tests/libvpcodec-abi.test.mjs`

  Expected: FAIL because no library artifact or build recipe exists.

- [ ] **Step 3: Enable only the M8 implementation**

  Restore `m8_enc` and `m8_enc_fast` objects for 32-bit ARM, preserve the driver fallback to `M8_FAST`, and remove GX/H.265 objects from this build. Add a seven-argument ABI v1 wrapper matching One-KVM's H.264 function type.

- [ ] **Step 4: Build a minimal diagnostic**

  `amlenc-m8-diag` must accept `--input frame.nv12 --width 1280 --height 720 --fps 30 --bitrate 4000000 --frames 300 --output test.h264`. It must fail on wrong frame size, missing device, zero output, missing SPS/PPS/IDR or an encoder call timeout.

- [ ] **Step 5: Record redistribution status**

  Document the license found in every source directory and classify each output as `redistributable`, `source-only`, or `local-test-only`. The packaging script must reject `local-test-only` binaries.

- [ ] **Step 6: Build and verify**

  Run: `experimental/amlenc/scripts/build-libvpcodec.sh && experimental/amlenc/scripts/verify-build.sh libvpcodec`

  Expected: exit 0; `readelf -h` reports ARM; `readelf -Ws` finds all ABI v1 symbols.

- [ ] **Step 7: Commit**

  ```bash
  git add experimental/amlenc/patches/libencoder experimental/amlenc/scripts/build-libvpcodec.sh experimental/amlenc/tests/libvpcodec-abi.test.mjs experimental/amlenc/docs/licensing.md
  git commit -S -m "feat(amlenc): 构建M8硬件编码用户态库"
  ```

### Task 4: Pass The Hardware Encoder Stop Gate

**Files:**
- Create: `experimental/amlenc/docs/bringup.md`
- Create: `experimental/amlenc/config/hardware-limits.json`
- Create: `experimental/amlenc/scripts/validate-h264.sh`

**Interfaces:**
- Consumes: WS1608 running the experimental kernel, diagnostic binary and NV12 fixture.
- Produces: a redacted result bundle containing kernel identity, device node, dmesg excerpts, H.264 metadata, decode result, frame count and hashes.

- [ ] **Step 1: Boot without writing eMMC**

  Boot the kernel/rootfs from removable media or a recoverable temporary path. Record `uname -a`, DT compatible strings, `/proc/iomem`, `/proc/meminfo`, `ls -l /dev/amvenc_avc`, and encoder-related `dmesg` lines.

- [ ] **Step 2: Run three fixed probes**

  Run 640x480@30 for 300 frames, 1280x720@30 for 1,800 frames, then 1280x720@30 for 8 hours. Use 1 Mbps for 640x480 and 4 Mbps for 720p. Do not run 1080p in this gate.

- [ ] **Step 3: Validate every stream independently**

  Run: `ffprobe -v error -show_streams -of json test.h264` and `ffmpeg -v error -i test.h264 -f null -`.

  Expected: codec `h264`, expected width/height, at least one IDR, SPS and PPS, no decode error, output duration matching submitted frames within one frame interval.

- [ ] **Step 4: Apply the stop decision**

  Pass only when all probes complete without kernel oops, CMA failure, device timeout or corrupt stream. On failure, open a focused issue containing the redacted result bundle and stop this plan before Task 5.

- [ ] **Step 5: Commit the verified limits, not device secrets**

  Store supported resolution/FPS/bitrate limits and public hashes in `hardware-limits.json`. Do not commit IP addresses, passwords, serial numbers or raw private logs.

### Task 5: Add Meson8b ARMv7 To One-KVM AMLENC

**Files:**
- Create: `experimental/amlenc/patches/one-kvm/0001-detect-meson8b-armv7.patch`
- Create: `experimental/amlenc/scripts/build-one-kvm.sh`
- Create: `experimental/amlenc/tests/one-kvm-contract.test.mjs`

**Interfaces:**
- Consumes: One-KVM `v260802`, ABI v1 `libvpcodec.so`, `/dev/amvenc_avc` and contiguous NV12 frames.
- Produces: custom armhf One-KVM Deb whose codec registry exposes H.264 AMLENC only on Meson8b/S805.

- [ ] **Step 1: Write the failing One-KVM contract test**

  Require Linux `arm`/`armv7` plus compatible values `amlogic,meson8b`, `AMLOGIC,8726_M8B` or `m8b_m201_1G`. Require `/dev/amvenc_avc` and ABI smoke test. Explicitly reject H.265 registration on Meson8b.

- [ ] **Step 2: Run the test and observe RED**

  Run: `node --test experimental/amlenc/tests/one-kvm-contract.test.mjs`

  Expected: FAIL because upstream only detects Linux/aarch64 S912/GXM.

- [ ] **Step 3: Patch detection and limits**

  Keep the existing S912/GXM path unchanged. Add a separate Meson8b capability returning H.264 only, read maximum width/height/FPS from the compiled S805 limits, and retain the existing 640x480 destructive smoke test and Annex-B checks.

- [ ] **Step 4: Build a traceable armhf Deb**

  Use version `0.2.6+ws1608amlenc.<build-number>` and embed upstream tag/commit plus patch digest in `/usr/share/doc/one-kvm/ws1608-amlenc-build.json`. Do not disguise it as the upstream `0.2.6` Deb.

- [ ] **Step 5: Verify the package**

  Run: `dpkg-deb -f one-kvm_*_armhf.deb Package Version Architecture` and inspect the binary with `readelf` under Linux CI.

  Expected: package `one-kvm`, architecture `armhf`, version includes `ws1608amlenc`, interpreter is `/lib/ld-linux-armhf.so.3`, and no H.265 AMLENC library is packaged.

- [ ] **Step 6: Commit**

  ```bash
  git add experimental/amlenc/patches/one-kvm experimental/amlenc/scripts/build-one-kvm.sh experimental/amlenc/tests/one-kvm-contract.test.mjs
  git commit -S -m "feat(amlenc): 接入One-KVM的S805编码后端"
  ```

### Task 6: Restore One-KVM USB Gadget Functions

**Files:**
- Create: `experimental/amlenc/patches/kernel/0003-configfs-hid-msd.patch`
- Create: `experimental/amlenc/tests/gadget-contract.test.mjs`
- Create: `experimental/amlenc/scripts/verify-gadget.sh`

**Interfaces:**
- Consumes: Amlogic DWC OTG controller in peripheral mode.
- Produces: ConfigFS/libcomposite support for keyboard HID, mouse HID and mass storage matching One-KVM's runtime expectations.

- [ ] **Step 1: Write the failing gadget contract test**

  Require `CONFIG_CONFIGFS_FS=y`, `CONFIG_USB_GADGET=y`, `CONFIG_USB_CONFIGFS=y`, HID and mass-storage ConfigFS functions, one UDC, and no dependency on the current 6.12 USB role sysfs path.

- [ ] **Step 2: Run the test and observe RED**

  Run: `node --test experimental/amlenc/tests/gadget-contract.test.mjs`

  Expected: FAIL because Hardkernel 3.10 lacks the modern ConfigFS composite functions.

- [ ] **Step 3: Backport the minimum ConfigFS functions**

  Backport only libcomposite, ConfigFS HID and mass-storage support required by One-KVM. Keep UDC selection and peripheral mode in an experimental helper; do not modify `config/one-kvm-enable-otg` used by the stable 6.12 image.

- [ ] **Step 4: Verify on WS1608**

  Run `verify-gadget.sh` after One-KVM starts. It must check UDC binding, both HID report descriptors, writable MSD backing file, unbind/rebind, and recovery after disconnect/reconnect.

  Expected: the controlled host receives keyboard, mouse and storage functions in BIOS and Linux; encoder operation continues during HID and MSD activity.

- [ ] **Step 5: Commit**

  ```bash
  git add experimental/amlenc/patches/kernel/0003-configfs-hid-msd.patch experimental/amlenc/tests/gadget-contract.test.mjs experimental/amlenc/scripts/verify-gadget.sh
  git commit -S -m "feat(amlenc): 恢复旧内核复合USB设备"
  ```

### Task 7: Build And Independently Verify The Experimental Burn Image

**Files:**
- Create: `experimental/amlenc/scripts/build-image.sh`
- Create: `experimental/amlenc/scripts/verify-image.sh`
- Create: `experimental/amlenc/scripts/package-release.sh`
- Create: `experimental/amlenc/tests/image-contract.test.mjs`

**Interfaces:**
- Consumes: pinned boot container, Bullseye armhf rootfs, verified kernel/DTB/modules, M8 library and custom One-KVM Deb.
- Produces: burn image, xz image, `SHA256SUMS`, manifest and experimental validation report.

- [ ] **Step 1: Write the failing image contract test**

  Require a distinct experimental manifest schema and tag prefix, exact source commits, kernel/config/DTB hashes, custom Deb hash, AMLENC library hash, `hardware_encoder_tested=false` in hosted CI, and `stable_channel_modified=false`.

- [ ] **Step 2: Run the test and observe RED**

  Run: `node --test experimental/amlenc/tests/image-contract.test.mjs`

  Expected: FAIL because the image scripts do not exist.

- [ ] **Step 3: Implement isolated image assembly**

  Reuse the reviewed AmlImg and sparse/ext4 helper modules where their interface is kernel-neutral. Do not call or edit the stable `scripts/build-image.sh`. Install experimental files only under their explicit package paths and write `/etc/ws1608-amlenc-release`.

- [ ] **Step 4: Implement independent verification**

  Re-unpack the final image and verify Amlogic CRC, partition SHA-1, boot files, DTB contents, kernel version, module dependency closure, armhf loader, One-KVM package version, AMLENC symbols, service links, ext4 integrity and absence of build tools. Reject a report claiming hardware pass in hosted CI.

- [ ] **Step 5: Verify release assets after upload/download round-trip**

  Use the stable design principle of five immutable assets, but use experimental names and schema. Run `xz -t`, decompressed image comparison, manifest/digest verification and file allowlisting before any release operation.

- [ ] **Step 6: Commit**

  ```bash
  git add experimental/amlenc/scripts experimental/amlenc/tests/image-contract.test.mjs
  git commit -S -m "feat(amlenc): 生成并验证实验直刷镜像"
  ```

### Task 8: Add The Separate Experimental Workflow And Prerelease

**Files:**
- Create: `.github/workflows/amlenc-experimental.yml`
- Create: `experimental/amlenc/tests/workflow-policy.test.mjs`

**Interfaces:**
- Consumes: locked sources and experimental build scripts.
- Produces: PR validation artifact or immutable GitHub prerelease; never a stable-channel Release.

- [ ] **Step 1: Write the failing workflow policy test**

  Require no `schedule`, no `repository_dispatch`, default `contents: read`, `contents: write` only in the release job, pinned action SHAs, build-before-release dependencies, `prerelease=true`, unique concurrency per forced run and no `--clobber`.

- [ ] **Step 2: Run the test and observe RED**

  Run: `node --test experimental/amlenc/tests/workflow-policy.test.mjs`

  Expected: FAIL because `.github/workflows/amlenc-experimental.yml` is absent.

- [ ] **Step 3: Add manual and PR orchestration**

  `pull_request` builds and verifies without publishing. `workflow_dispatch` accepts `publish=false` by default and a required `acknowledge_experimental=true` before publishing. Every release uses the experimental tag format and remains a prerelease.

- [ ] **Step 4: Run local policy checks**

  Run: `npm test && node --test experimental/amlenc/tests/*.test.mjs && for script in experimental/amlenc/scripts/*.sh; do bash -n "$script"; done && actionlint .github/workflows/build.yml .github/workflows/amlenc-experimental.yml && git diff --check`

  Expected: all commands pass; the stable workflow diff remains empty.

- [ ] **Step 5: Run cloud validation without publishing**

  Dispatch the experimental workflow with `publish=false`. Download its artifact and repeat source, kernel, image, xz and manifest verification locally.

- [ ] **Step 6: Commit**

  ```bash
  git add .github/workflows/amlenc-experimental.yml experimental/amlenc/tests/workflow-policy.test.mjs
  git commit -S -m "ci(amlenc): 新增独立实验镜像构建"
  ```

### Task 9: Complete Hardware Qualification And Promotion Decision

**Files:**
- Create: `experimental/amlenc/docs/hardware-validation.md`
- Modify: `README.md`
- Modify: `docs/README.md`
- Create: `docs/adr/0003-s805-amlenc-experimental-channel.md`

**Interfaces:**
- Consumes: one immutable experimental image and its public hashes.
- Produces: pass/fail hardware record and an explicit decision that either retains the experimental channel or permits a later stable-base candidate PR.

- [ ] **Step 1: Execute the fixed hardware matrix**

  Verify USB Burning Tool import and flash, cold boot, HDMI console, DHCP/SSH, eMMC, One-KVM health, `/api/stream/codecs`, USB capture video, WebRTC, keyboard, mouse, MSD, reconnect, reboot and 8-hour 720p30 encoding.

- [ ] **Step 2: Require observable hardware encoding**

  `/api/stream/codecs` must list `h264_amlenc` with `is_hardware=true`; One-KVM logs must show AMLENC smoke-test success; CPU usage must be recorded against the same 720p30 software x264 input. A device node alone is not a pass.

- [ ] **Step 3: Exercise failure recovery**

  Disconnect/reconnect the capture device and controlled-host USB cable, request keyframes from two browser sessions, change bitrate, restart One-KVM and cold reboot. Reject kernel oops, unrecoverable black video, stuck encoder or missing HID/MSD functions.

- [ ] **Step 4: Publish only as an experimental prerelease**

  After all static gates pass, publish with `acknowledge_experimental=true`. Attach the five verified assets and state the exact hardware test result in the Release notes. Do not mark it GitHub Latest.

- [ ] **Step 5: Record the architectural decision**

  ADR-0003 must state the tested board revision, kernel source commit, One-KVM source commit, accepted limits and remaining security/license constraints. A stable-base change requires a new PR that changes `config/base.env` and reruns the existing stable workflow; this experimental plan never performs that change automatically.

- [ ] **Step 6: Final verification**

  Run: `npm test && node --test experimental/amlenc/tests/*.test.mjs && actionlint .github/workflows/build.yml .github/workflows/amlenc-experimental.yml && git diff --check`

  Expected: all commands exit zero, stable workflow still schedules once every seven days, and no experimental tag or asset can satisfy stable release discovery.

