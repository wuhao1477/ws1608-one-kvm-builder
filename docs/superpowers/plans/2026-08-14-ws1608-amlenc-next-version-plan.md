# WS1608 AMLENC Next Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在完全保留当前已验证稳定镜像自动生成链路的前提下，完成可追溯的 One-KVM `0.2.6+ws1608amlenc.<BUILD_NUMBER>` 实验版本，并以实机 H.264 硬件编码、USB Gadget 和刷机启动结果决定是否允许发布实验 prerelease。

**Architecture:** 稳定通道继续只由 `.github/workflows/build.yml`、`config/base.env` 和现有 `scripts/` 驱动。新版本只在 `experimental/amlenc/` 与 `.github/workflows/amlenc-experimental.yml` 中开发，先完成可复现 armhf Deb，再依次通过云端静态门禁、WS1608 编码停止门禁、One-KVM 运行门禁、USB Gadget 门禁和独立镜像门禁。任何门禁失败都不得改变稳定基础、稳定 Release 或稳定 tag。

**Tech Stack:** One-KVM Rust `0.2.6`/`v260802`、Linux `3.10.107` armhf、Amlogic S805/Meson8b `amvenc_avc`、M8 `libvpcodec`、Debian 11 Bullseye、GitHub Actions、Bash、Node.js tests、AmlImg。

## Global Constraints

- 当前继续开发的分支为 `codex/s805-amlenc-experimental`，基线提交为 `ca466ae`。
- `.github/workflows/build.yml`、`config/base.env`、`scripts/`、`tests/` 和稳定 `config/` 文件属于受保护稳定链路；本计划不得修改它们。
- 稳定自动检查保持 `17 2 * * 0`，即每 7 天一次；没有新的 One-KVM tag 与 Deb SHA-256 组合时必须跳过 build/release。
- 稳定基础保持 `BASE_RELEASE_TAG=base-20260804-consolefix`，除非以后通过独立的稳定基础升级 PR。
- 新版本包名固定为 `one-kvm_0.2.6+ws1608amlenc.<BUILD_NUMBER>_armhf.deb`；`BUILD_NUMBER` 必须包含 GitHub run number 与 attempt。
- 实验 tag 固定为 `ws1608-amlenc-exp-0.2.6-v260802-k3.10.107-bRRRAAA`；同一 One-KVM 版本可多次构建，但 tag 不得覆盖。
- GitHub 托管 runner 只能写 `hardware_encoder_tested=false`；实机证据通过前不得发布镜像 Release。
- `libvpcodec` 当前分类保持 `redistribution=local-test-only`；许可证未确认前不得上传到公开 Release 或公开仓库的 Actions artifact。
- 第一阶段只支持 H.264、NV12、最大 `1280x720@30`；不注册 S805 H.265，不承诺 1080p。
- 不提交局域网地址、SSH 凭据、板卡序列号、原始私有日志或 GitHub token。

## Current Baseline

| 状态 | 已有结果 |
| --- | --- |
| 已完成 | 稳定边界测试、固定源码、S805 3.10.107 内核、M8 `libvpcodec`、H.264 验证器、可恢复 USB 诊断镜像 |
| 已完成 | One-KVM Meson8b ARMv7 补丁、固定交叉构建输入、armhf Deb 构建与独立静态验证 |
| 已完成 | 相同 `BUILD_NUMBER=repro001` 与 `SOURCE_DATE_EPOCH=1785659915` 的两次 Deb 构建逐字节一致，SHA-256 均为 `06144d80f9f6ed79ebc4519dfe83bf9c8d6ad543d95a912573b6446895530783` |
| 正在验证 | 真实 WS1608 上的硬件编码能力，以及完整构建来源元数据 |
| 尚未通过 | 实机 `/dev/amvenc_avc` 编码、One-KVM 实机流、旧内核 HID/MSD、实验直刷镜像 |
| 禁止执行 | 修改稳定链路、标记硬件通过、发布稳定 Release、覆盖既有 tag |

## Planned File Structure

```text
experimental/amlenc/config/stable-chain.sha256
experimental/amlenc/patches/one-kvm/0001-detect-meson8b-armv7.patch
experimental/amlenc/patches/one-kvm/0002-pin-armv7-build-inputs.patch
experimental/amlenc/patches/kernel/0003-configfs-hid-msd.patch
experimental/amlenc/scripts/verify-stable-chain.sh
experimental/amlenc/scripts/build-one-kvm.sh
experimental/amlenc/scripts/verify-one-kvm.sh
experimental/amlenc/scripts/verify-one-kvm-runtime.sh
experimental/amlenc/scripts/verify-gadget.sh
experimental/amlenc/scripts/build-image.sh
experimental/amlenc/scripts/verify-image.sh
experimental/amlenc/scripts/package-release.sh
experimental/amlenc/tests/stable-chain-digest.test.mjs
experimental/amlenc/tests/one-kvm-contract.test.mjs
experimental/amlenc/tests/gadget-contract.test.mjs
experimental/amlenc/tests/image-contract.test.mjs
experimental/amlenc/docs/one-kvm-hardware-validation.md
experimental/amlenc/docs/release-policy.md
```

---

### Task 1: Freeze The Verified Stable Build Chain

**Files:**
- Create: `experimental/amlenc/config/stable-chain.sha256`
- Create: `experimental/amlenc/scripts/verify-stable-chain.sh`
- Create: `experimental/amlenc/tests/stable-chain-digest.test.mjs`
- Modify: `.github/workflows/amlenc-experimental.yml`

**Interfaces:**
- Consumes: tracked stable workflow, config, scripts, tests and `package.json` at `ca466ae`.
- Produces: a failing check when any protected stable file is changed, removed or added without an explicit baseline update.

- [x] **Step 1: Write the failing protected-file test**

  Require the digest manifest to include `.github/workflows/build.yml`, `config/base.env`, every tracked file below `scripts/` and `tests/`, all stable `config/one-kvm*` files, `config/commands.expected`, `config/systemctl-build-stub`, `config/tool-versions.env` and `package.json`. Reject absolute paths, duplicate paths and entries below `experimental/`.

- [x] **Step 2: Run the focused test and verify RED**

  Run: `node --test experimental/amlenc/tests/stable-chain-digest.test.mjs`

  Expected: FAIL because the digest manifest and verifier do not exist.

- [x] **Step 3: Generate and verify the protected manifest**

  Generate sorted SHA-256 entries with `git ls-files -z` and `shasum -a 256`. `verify-stable-chain.sh` must first validate the exact tracked path set and then run `shasum -a 256 -c experimental/amlenc/config/stable-chain.sha256`.

- [x] **Step 4: Add the verifier to both experimental jobs**

  Run the verifier before contract tests and again immediately before artifact upload. Keep `git diff --exit-code -- .github/workflows/build.yml config/base.env` as a readable secondary check.

- [x] **Step 5: Verify the stable behavior contract**

  Run: `npm test && node --test experimental/amlenc/tests/stable-boundary.test.mjs experimental/amlenc/tests/stable-chain-digest.test.mjs`

  Expected: all tests pass; the stable cron remains weekly and its no-update path still skips build/release.

- [ ] **Step 6: Commit**

  ```bash
  git add experimental/amlenc/config/stable-chain.sha256 experimental/amlenc/scripts/verify-stable-chain.sh experimental/amlenc/tests/stable-chain-digest.test.mjs .github/workflows/amlenc-experimental.yml
  git commit -S -m "test(amlenc): 固定已验证稳定构建链路"
  ```

### Task 2: Finish The Reproducible One-KVM ARMv7 Package

**Files:**
- Modify: `experimental/amlenc/patches/one-kvm/0002-pin-armv7-build-inputs.patch`
- Modify: `experimental/amlenc/scripts/build-one-kvm.sh`
- Modify: `experimental/amlenc/scripts/verify-one-kvm.sh`
- Modify: `experimental/amlenc/tests/one-kvm-contract.test.mjs`

**Interfaces:**
- Consumes: pinned One-KVM `a4073d64cb49a1404df49e7813b73dd9f78d0931`, pinned x264/RKMPP/RKRGA inputs and verified local-only `libvpcodec.so`.
- Produces: `one-kvm_0.2.6+ws1608amlenc.<BUILD_NUMBER>_armhf.deb` plus SHA-256 and build metadata.

- [x] **Step 1: Capture the first actionable Docker failure**

  Run the generated `Dockerfile.armv7` with `docker build --platform linux/amd64 --progress=plain`. Preserve the first compiler/configure error in the Actions log; do not accept an outer `cross` exit code as the diagnosis.

- [x] **Step 2: Add a regression assertion for that failure**

  Extend `one-kvm-contract.test.mjs` to assert the exact pinned commit, package/tool required by the failing stage, and the absence of moving Git refs in `Dockerfile.armv7`.

- [x] **Step 3: Apply the smallest build-input correction**

  Change only `0002-pin-armv7-build-inputs.patch` or the experimental build wrapper. Keep upstream S912/GXM code unchanged and retain Meson8b H.264-only registration with the 720p30 limit.

- [x] **Step 4: Build and independently inspect the Deb on Linux amd64**

  Run:

  ```bash
  BUILD_NUMBER="run-${GITHUB_RUN_NUMBER:?}-${GITHUB_RUN_ATTEMPT:?}" experimental/amlenc/scripts/build-one-kvm.sh
  experimental/amlenc/scripts/verify-one-kvm.sh "out/amlenc/one-kvm/one-kvm_0.2.6+ws1608amlenc.run-${GITHUB_RUN_NUMBER}-${GITHUB_RUN_ATTEMPT}_armhf.deb"
  ```

  Expected: package `one-kvm`, version prefix `0.2.6+ws1608amlenc.`, architecture `armhf`, ELF32 ARM, loader `/lib/ld-linux-armhf.so.3`, valid internal SHA-256 and `hardware_encoder_tested=false`.

- [x] **Step 5: Prove byte-for-byte reproducibility**

  Build twice with `BUILD_NUMBER=repro001` and `SOURCE_DATE_EPOCH=1785659915`. After normalizing the package tree timestamps and Debian archive ownership/compression, both outputs must have SHA-256 `06144d80f9f6ed79ebc4519dfe83bf9c8d6ad543d95a912573b6446895530783`, and `cmp` must exit zero.

- [ ] **Step 6: Complete provenance and public-artifact metadata**

  Record compiler identity, Rust version, x264 commit, RKMPP commit and RKRGA commit in `ws1608-amlenc-build.json`, then make `verify-one-kvm.sh` reject missing or mismatched values. While redistribution remains `local-test-only`, exclude the Deb and `libvpcodec` binary from public Actions artifacts and upload only source/build metadata, hashes and validation reports.

- [ ] **Step 7: Commit**

  ```bash
  git add experimental/amlenc/patches/one-kvm experimental/amlenc/scripts/build-one-kvm.sh experimental/amlenc/scripts/verify-one-kvm.sh experimental/amlenc/tests/one-kvm-contract.test.mjs
  git commit -S -m "feat(amlenc): 完成可复现ARMv7软件包"
  ```

### Task 3: Pass The WS1608 Hardware Encoder Stop Gate

**Files:**
- Modify: `experimental/amlenc/config/hardware-limits.json`
- Create: `experimental/amlenc/docs/one-kvm-hardware-validation.md`

**Interfaces:**
- Consumes: immutable diagnostic USB artifact, `amlenc-m8-diag`, NV12 fixtures and the existing `validate-h264.sh`.
- Produces: redacted evidence hashes and a pass/fail result for native S805 H.264 encoding.

- [ ] **Step 1: Boot only the recoverable diagnostic medium**

  Keep the currently working eMMC image unchanged. Confirm `uname -r=3.10.107`, Meson8b compatible strings, `/dev/amvenc_avc`, CMA/ION allocation and absence of boot oops.

- [ ] **Step 2: Execute the fixed probe matrix**

  Run 640x480@30 for 300 frames at 1 Mbps, 1280x720@30 for 1,800 frames at 4 Mbps, then 1280x720@30 for 8 hours at 4 Mbps. Capture a fresh `dmesg` after each probe.

- [ ] **Step 3: Validate every stream**

  Use `validate-h264.sh` to require exact frame count and dimensions, SPS/PPS/IDR, successful FFmpeg decode, nonzero output, no timeout, no CMA failure and no kernel oops.

- [ ] **Step 4: Apply the stop decision**

  On any failure, keep `validated=false` and stop Tasks 4-7. On success, store only public hashes, board family, kernel commit, limits and test date; keep raw logs private.

- [ ] **Step 5: Commit the result**

  ```bash
  git add experimental/amlenc/config/hardware-limits.json experimental/amlenc/docs/one-kvm-hardware-validation.md
  git commit -S -m "test(amlenc): 记录S805硬件编码验收"
  ```

### Task 4: Validate One-KVM With The Hardware Encoder

**Files:**
- Create: `experimental/amlenc/scripts/verify-one-kvm-runtime.sh`
- Modify: `experimental/amlenc/docs/one-kvm-hardware-validation.md`
- Modify: `experimental/amlenc/tests/one-kvm-contract.test.mjs`

**Interfaces:**
- Consumes: Task 2 Deb and Task 3 hardware pass.
- Produces: proof that One-KVM selects `h264_amlenc` and remains usable with live HDMI capture.

- [ ] **Step 1: Add the runtime verifier contract**

  Require service active state, health API success, `h264_amlenc` with `is_hardware=true`, AMLENC smoke-test success in logs, video frames from a real UVC capture device and no software fallback.

- [ ] **Step 2: Install the Deb only in the diagnostic environment**

  Confirm installed version with `dpkg-query`, verify `/usr/share/doc/one-kvm/ws1608-amlenc-build.json`, then start One-KVM with the packaged library path.

- [ ] **Step 3: Exercise the live stream**

  Test 720p30 for 30 minutes, request keyframes, change bitrate, connect two browser sessions, restart One-KVM and reconnect the capture device. Record CPU usage and filtered service/kernel logs.

- [ ] **Step 4: Reject silent fallback**

  Fail when the API omits `h264_amlenc`, logs select x264, output lacks IDR after a keyframe request, One-KVM exits, or the encoder cannot recover after reconnect.

- [ ] **Step 5: Commit**

  ```bash
  git add experimental/amlenc/scripts/verify-one-kvm-runtime.sh experimental/amlenc/docs/one-kvm-hardware-validation.md experimental/amlenc/tests/one-kvm-contract.test.mjs
  git commit -S -m "test(amlenc): 验证One-KVM硬件编码运行"
  ```

### Task 5: Restore HID And MSD On Linux 3.10

**Files:**
- Create: `experimental/amlenc/patches/kernel/0003-configfs-hid-msd.patch`
- Create: `experimental/amlenc/scripts/verify-gadget.sh`
- Create: `experimental/amlenc/tests/gadget-contract.test.mjs`

**Interfaces:**
- Consumes: Meson8b DWC OTG peripheral controller and One-KVM keyboard, mouse and MSD expectations.
- Produces: one composite gadget that survives disconnect, service restart and cold reboot.

- [ ] **Step 1: Write the failing gadget contract test**

  Require ConfigFS/libcomposite, HID keyboard, HID absolute mouse, mass storage, one UDC and an experimental OTG helper. Reject references to the stable 6.12 USB-role path or stable `config/one-kvm-enable-otg`.

- [ ] **Step 2: Add the minimum 3.10 kernel support**

  Backport only the ConfigFS composite functions used by One-KVM. Keep all code and configuration in the experimental kernel patch set.

- [ ] **Step 3: Verify on a controlled host**

  Confirm keyboard and mouse in BIOS and Linux, writable MSD backing storage, unbind/rebind, cable reconnect, One-KVM restart and cold reboot.

- [ ] **Step 4: Run simultaneous video and gadget load**

  Keep 720p30 AMLENC streaming while sending keyboard/mouse input and mounting MSD. Reject USB resets that stop the stream, stuck HID reports or kernel faults.

- [ ] **Step 5: Commit**

  ```bash
  git add experimental/amlenc/patches/kernel/0003-configfs-hid-msd.patch experimental/amlenc/scripts/verify-gadget.sh experimental/amlenc/tests/gadget-contract.test.mjs
  git commit -S -m "feat(amlenc): 恢复旧内核HID与虚拟介质"
  ```

### Task 6: Build And Verify The Experimental Burn Image

**Files:**
- Create: `experimental/amlenc/scripts/build-image.sh`
- Create: `experimental/amlenc/scripts/verify-image.sh`
- Create: `experimental/amlenc/scripts/package-release.sh`
- Create: `experimental/amlenc/tests/image-contract.test.mjs`

**Interfaces:**
- Consumes: Tasks 2-5 verified outputs and a pinned recoverable Amlogic container.
- Produces: experimental `.burn.img`, `.burn.img.xz`, `SHA256SUMS`, manifest and validation report.

- [ ] **Step 1: Write the failing image contract**

  Require experimental schema/tag, exact source and patch digests, kernel/DTB/modules, One-KVM Deb, `libvpcodec`, `hardware_encoder_tested=true` with evidence hash, `stable_channel_modified=false`, and an asset allowlist.

- [ ] **Step 2: Assemble without calling stable build scripts**

  Reuse only stable read-only format libraries whose public interfaces need no modification. Install experimental files under explicit paths and write `/etc/ws1608-amlenc-release`.

- [ ] **Step 3: Independently re-open the finished image**

  Verify Amlogic CRC, all partition SHA-1 values, kernel and DTB identity, ext4 `e2fsck -fn`, armhf loader/dependencies, package version, AMLENC symbols, systemd services and absence of build tools.

- [ ] **Step 4: Verify burn-tool compatibility and real boot**

  Import and flash the raw image with Amlogic USB Burning Tool, then require cold boot, HDMI, DHCP/SSH, eMMC, One-KVM health, hardware video, HID and MSD. A parser/import failure is an image gate failure.

- [ ] **Step 5: Verify packaged assets**

  Run `xz -t`, compare decompressed bytes to the raw image, validate every manifest digest and reject extra files. In a private or local test environment, transfer the complete bundle and repeat the same checks. A public-repository Actions artifact must omit the image, Deb and `libvpcodec` until Task 7 records a redistributable license basis.

- [ ] **Step 6: Commit**

  ```bash
  git add experimental/amlenc/scripts/build-image.sh experimental/amlenc/scripts/verify-image.sh experimental/amlenc/scripts/package-release.sh experimental/amlenc/tests/image-contract.test.mjs
  git commit -S -m "feat(amlenc): 生成实验硬编码直刷镜像"
  ```

### Task 7: Add A Guarded Experimental Prerelease

**Files:**
- Modify: `.github/workflows/amlenc-experimental.yml`
- Create: `experimental/amlenc/docs/release-policy.md`
- Modify: `experimental/amlenc/tests/workflow-policy.test.mjs`

**Interfaces:**
- Consumes: verified five-asset bundle and hardware evidence digest.
- Produces: an immutable GitHub prerelease; never GitHub Latest or a stable tag.

- [ ] **Step 1: Extend the workflow policy test**

  Require `publish=false` by default, an explicit experimental acknowledgement, `contents: write` only in the release job, pinned action SHAs, build dependency, `prerelease=true`, unique tag, no `--clobber`, no schedule and no repository dispatch. While redistribution is `local-test-only`, require the workflow to reject public binary/image upload.

- [ ] **Step 2: Add a release job behind all gates**

  First record the exact license file or written permission that permits redistribution of the packaged `libvpcodec`; change its manifest classification to `redistributable` only when that evidence exists. The release job must otherwise remain disabled. Once permitted, it must download and independently verify the artifact, verify `hardware_encoder_tested=true` and its evidence digest, create the tag at the builder commit, upload exactly five assets and publish only after every upload succeeds.

- [ ] **Step 3: Run the complete local gate**

  ```bash
  node --test experimental/amlenc/tests/*.test.mjs
  npm test
  go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/build.yml .github/workflows/amlenc-experimental.yml
  for script in experimental/amlenc/scripts/*.sh; do bash -n "$script"; done
  experimental/amlenc/scripts/verify-stable-chain.sh
  git diff --check
  ```

  Expected: every command exits zero and the protected stable path diff is empty.

- [ ] **Step 4: Run cloud validation without publication**

  Dispatch with `publish=false`. While redistribution is unresolved, download the source/build metadata artifact and verify that it contains no Deb, image or `libvpcodec`; run full Deb/image/xz checks only in the private or local test environment. Retain the successful run URL in the release policy record.

- [ ] **Step 5: Publish only after explicit review**

  Dispatch with the experimental acknowledgement and `publish=true`. Confirm tag format `ws1608-amlenc-exp-0.2.6-v260802-k3.10.107-bRRRAAA`, prerelease status, five asset digests and `Latest=false`.

- [ ] **Step 6: Commit**

  ```bash
  git add .github/workflows/amlenc-experimental.yml experimental/amlenc/docs/release-policy.md experimental/amlenc/tests/workflow-policy.test.mjs
  git commit -S -m "ci(amlenc): 发布受控实验版本"
  ```

## Final Acceptance

- [ ] Stable chain digest verification passes and protected stable files have zero diff.
- [ ] One-KVM Deb version visibly includes `0.2.6+ws1608amlenc.<BUILD_NUMBER>`.
- [ ] Cloud build and downloaded-artifact revalidation pass.
- [ ] Native S805 H.264 produces valid 720p30 Annex-B output for 8 hours.
- [ ] One-KVM demonstrably selects hardware AMLENC without x264 fallback.
- [ ] HDMI capture, keyboard, mouse and MSD survive reconnect and cold reboot.
- [ ] USB Burning Tool imports and flashes the image; HDMI and LAN work after boot.
- [ ] Release remains an immutable experimental prerelease with exactly five verified assets.
- [ ] The prerelease is enabled only after `libvpcodec` redistribution permission is recorded; otherwise no public binary artifact, tag or Release exists.
- [ ] Any failed item leaves the stable image automation and current stable Releases unchanged.
