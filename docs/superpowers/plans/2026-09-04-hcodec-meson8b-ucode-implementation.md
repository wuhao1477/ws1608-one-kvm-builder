# Meson8b HCODEC Microcode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the incorrect GXL firmware path with the pinned Hardkernel Meson8b dblk microcode and matching Assist DMA initialization, then produce a cloud-built candidate for one 640x480 hardware probe.

**Architecture:** A dedicated cloud-only firmware builder downloads the pinned Hardkernel source archive, extracts `h264_enc_mix_dump_dblk.h`, and emits a raw `meson8b_h264.bin` plus provenance manifest. The artifact packages that firmware explicitly, and the installer copies it directly into the target firmware directory. The Meson8b driver patch series restores the original non-offset VLC behavior and adds the vendor DMA interrupt defaults while leaving the Armbian 6.12 V4L2 interface unchanged.

**Tech Stack:** Bash, Node.js built-in test runner, Python 3 standard library, GitHub Actions, Linux 6.12.28, Armbian build, ARMv7 cross compiler.

**Spec:** `docs/superpowers/specs/2026-09-04-hcodec-meson8b-ucode-design.md`

## Global Constraints

- Build kernel and firmware through GitHub Actions; do not build the candidate kernel locally.
- Keep Linux `6.12.28`, Armbian commit `fa7a7b2294d9e760a77630950afd460b7a0b2a26`, and Ubuntu image digest `sha256:1e0a86e57d247923571b75e0aaf48a1449cf8c543d51fb3e07a4a7d7bfa79316`.
- Use Hardkernel Linux commit `5aed95d35d252cafc75ce613a3a0052285662de2` and input path `drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h`.
- Expect 2384 microcode words, 9536 output bytes, and SHA-256 `2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368`.
- Use Meson8b Assist DMA mask offsets `0x4194` and `0x419c`, values `0xfd` and `0xff`, plus Assist interrupt register `0x40a4` value `0x18`.
- Remove `0022-media-meson-use-offset-VLC-ring-base-on-Meson8b.patch`; do not carry the disproved offset ring-base workaround.
- Preserve target-root module staging at `TARGET_ROOT/root/hcodec-modules-stage.*`; never extract modules into `/tmp` or `/`.
- Do not create or merge a PR before the new candidate is flashed and the 640x480 single-frame probe passes.
- Do not test 720p, 1080p, DMABUF, or One-KVM integration before that probe passes.
- Never add generated firmware binaries, `Downloads/`, device credentials, or probe logs to Git.

### Task 1: Lock The Meson8b Firmware Source

**Files:**
- Modify: `experimental/hcodec/config/sources.env:32-36`
- Modify: `experimental/hcodec/scripts/verify-source-locks.mjs:35-55`
- Test: `experimental/hcodec/tests/source-lock.test.mjs`
- Create: `experimental/hcodec/tests/firmware-contract.test.mjs`

**Interfaces:**
- Produces immutable values `FIRMWARE_INPUT_PATH`, `FIRMWARE_WORD_COUNT`, `FIRMWARE_OUTPUT_SIZE`, and `FIRMWARE_OUTPUT_SHA256` for the builder and verifier.

- [ ] **Step 1: Write the failing contracts.** Add these exact expected lines to the source-lock test fixture:

```js
'FIRMWARE_INPUT_PATH=drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h',
'FIRMWARE_WORD_COUNT=2384',
'FIRMWARE_OUTPUT_SIZE=9536',
'FIRMWARE_OUTPUT_SHA256=2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368',
```

In `firmware-contract.test.mjs`, assert that `sources.env` contains those values and that no active builder input is `gxl_h264_enc` or `h264_enc.bin`.

- [ ] **Step 2: Run the focused tests and verify RED.**

```bash
node --test experimental/hcodec/tests/source-lock.test.mjs experimental/hcodec/tests/firmware-contract.test.mjs
```

Expected: failure because the four new source-lock keys and the new test file are not implemented.

- [ ] **Step 3: Add the four lock values and validator checks.** Extend `sources.env` with the exact values above. In `verify-source-locks.mjs`, require the path, parse the three numeric fields as positive integers, require the output digest to match `/^[0-9a-f]{64}$/`, and reject any output size other than `9536` or word count other than `2384`.

- [ ] **Step 4: Run the focused tests and verify GREEN.**

```bash
node --test experimental/hcodec/tests/source-lock.test.mjs experimental/hcodec/tests/firmware-contract.test.mjs
```

Expected: all focused tests pass.

- [ ] **Step 5: Commit the source-lock change.**

```bash
git add experimental/hcodec/config/sources.env experimental/hcodec/scripts/verify-source-locks.mjs experimental/hcodec/tests/source-lock.test.mjs experimental/hcodec/tests/firmware-contract.test.mjs
git commit -m "fix(hcodec): 锁定Meson8b微码来源"
```

### Task 2: Generate And Verify Firmware In CI

**Files:**
- Create: `experimental/hcodec/scripts/build-firmware.sh`
- Modify: `.github/workflows/hcodec-candidate.yml:20-86`
- Modify: `experimental/hcodec/tests/firmware-contract.test.mjs`
- Modify: `experimental/hcodec/tests/artifact-contract.test.mjs`

**Interfaces:**
- `build-firmware.sh OUTPUT_DIR` creates `OUTPUT_DIR/meson8b_h264.bin` and `OUTPUT_DIR/firmware-manifest.json`.
- The manifest contains `schema:1`, the pinned repository/commit/archive SHA, `input_path`, `word_count:2384`, `output_size:9536`, `output_sha256`, `binary_included:true`, and `variant:"meson8b_dblk"`.

- [ ] **Step 1: Write the failing script and workflow contracts.** Assert that the script downloads `FIRMWARE_ARCHIVE_URL`, checks `FIRMWARE_ARCHIVE_SHA256`, extracts exactly `FIRMWARE_INPUT_PATH`, invokes `extract-meson8b-ucode.py`, checks the four expected output values, and writes the manifest. Assert that the workflow installs/runs `build-firmware.sh` before packaging and passes its output directory to the package script.

- [ ] **Step 2: Run the focused contracts and verify RED.**

```bash
node --test experimental/hcodec/tests/firmware-contract.test.mjs experimental/hcodec/tests/artifact-contract.test.mjs
```

Expected: failure because `build-firmware.sh` and the workflow integration do not exist.

- [ ] **Step 3: Implement the minimal cloud builder.** Use a temporary directory under `${HCODEC_WORK_DIR:-$ROOT_DIR/.build/hcodec}/firmware-source`, download the pinned tarball with `curl --fail --location --retry 5`, verify its SHA-256, locate the single exact header path beneath the extracted top directory, run the existing Python extractor, and compare size and SHA-256 with the lock values before writing `firmware-manifest.json`.

- [ ] **Step 4: Wire the workflow.** Add `mkdir -p out/hcodec/firmware`, invoke `experimental/hcodec/scripts/build-firmware.sh out/hcodec/firmware` after the kernel/tools builds, and pass `out/hcodec/firmware` to `package-artifact.sh`.

- [ ] **Step 5: Run focused tests and shell validation.**

```bash
node --test experimental/hcodec/tests/firmware-contract.test.mjs experimental/hcodec/tests/artifact-contract.test.mjs
bash -n experimental/hcodec/scripts/build-firmware.sh
```

Expected: Node contracts pass; YAML is checked by the workflow contract and the existing shell glob check. Do not claim CI success until GitHub Actions runs.

- [ ] **Step 6: Commit the CI firmware builder.**

```bash
git add experimental/hcodec/scripts/build-firmware.sh .github/workflows/hcodec-candidate.yml experimental/hcodec/tests/firmware-contract.test.mjs experimental/hcodec/tests/artifact-contract.test.mjs
git commit -m "feat(hcodec): 在云端生成Meson8b微码"
```

### Task 3: Package And Install The Explicit Firmware

**Files:**
- Modify: `experimental/hcodec/scripts/package-artifact.sh:7-67`
- Modify: `experimental/hcodec/scripts/verify-artifact.sh:18-62`
- Modify: `experimental/hcodec/scripts/install-artifact.sh:4-104`
- Modify: `experimental/hcodec/tests/artifact-contract.test.mjs`
- Modify: `experimental/hcodec/tests/install-contract.test.mjs`

**Interfaces:**
- `package-artifact.sh KERNEL_DIR TOOLS_DIR FIRMWARE_DIR OUTPUT_DIR RUN_NUMBER RUN_ATTEMPT` packages `firmware/meson8b_h264.bin` and `firmware/firmware-manifest.json`.
- `install-artifact.sh` requires and copies `firmware/meson8b_h264.bin`; it never parses or falls back to `/lib/firmware/video/h264_enc.bin`.

- [ ] **Step 1: Write failing artifact and installer assertions.** Require the firmware directory argument, exact artifact whitelist entries `./firmware/firmware-manifest.json` and `./firmware/meson8b_h264.bin`, `binary_included:true` in the firmware manifest, and installer logic that copies the artifact firmware. Add a negative assertion that the installer no longer contains `h264_enc.bin`, `gxl_h264_enc`, or the embedded Python extraction block.

- [ ] **Step 2: Run focused tests and verify RED.**

```bash
node --test experimental/hcodec/tests/artifact-contract.test.mjs experimental/hcodec/tests/install-contract.test.mjs
```

Expected: failure because the current package, verifier, and installer still use the old source-image extraction path.

- [ ] **Step 3: Update packaging and manifest generation.** Copy the two firmware files into `stage/firmware`, include the firmware digest from `firmware-manifest.json` in the top-level manifest, and remove the blanket deletion that would remove the explicitly allowed firmware binary. Keep all other artifact files unchanged.

- [ ] **Step 4: Update artifact verification.** Permit only the exact firmware binary and manifest, verify both internal and top-level SHA-256 files, require the manifest fields listed in Task 2, and reject any additional `*.bin` or `*.fw` file.

- [ ] **Step 5: Update the installer.** Validate `firmware/meson8b_h264.bin`, install it to `$TARGET_ROOT/lib/firmware/meson/venc/meson8b_h264.bin`, retain target-root module staging and backups, and delete the old Python container parser entirely.

- [ ] **Step 6: Run focused tests, all HCODEC tests, and shell syntax checks.**

```bash
node --test experimental/hcodec/tests/artifact-contract.test.mjs experimental/hcodec/tests/install-contract.test.mjs
node --test experimental/hcodec/tests/*.test.mjs
bash -n experimental/hcodec/scripts/*.sh
```

Expected: all tests pass with zero shell syntax errors.

- [ ] **Step 7: Commit the artifact/install path.**

```bash
git add experimental/hcodec/scripts/package-artifact.sh experimental/hcodec/scripts/verify-artifact.sh experimental/hcodec/scripts/install-artifact.sh experimental/hcodec/tests/artifact-contract.test.mjs experimental/hcodec/tests/install-contract.test.mjs
git commit -m "fix(hcodec): 直接安装Meson8b生成微码"
```

### Task 4: Match The Meson8b Driver Protocol

**Files:**
- Delete: `experimental/hcodec/patches/linux-6.12/0022-media-meson-use-offset-VLC-ring-base-on-Meson8b.patch`
- Create: `experimental/hcodec/patches/linux-6.12/0023-media-meson-match-Meson8b-microcode-protocol.patch`
- Modify: `experimental/hcodec/tests/patch-series.test.mjs`
- Modify: `experimental/hcodec/tests/meson8b-resource-contract.test.mjs`

**Interfaces:**
- The resulting driver defines `HCODEC_ASSIST_DMA_INT_MSK 0x4194`, `HCODEC_ASSIST_DMA_INT_MSK2 0x419c`, and `HCODEC_ASSIST_AMR1_INT4 0x40a4`.
- Meson8b initialization writes `0xfd`, `0xff`, and `0x18` respectively before command submission.
- `HCODEC_VLC_VB_START_PTR` and `HCODEC_VLC_VB_SW_RD_PTR` use the capture buffer base again; no `dst_base_dma` or `dst_ring_size` workaround remains.

- [ ] **Step 1: Write failing patch contracts.** Change the patch-series expectation from file `0022-...` to `0023-...`, require the three register definitions and writes above, and require the absence of `dst_base_dma`, `dst_ring_size`, and `dst_offset && !venc->variant->has_gx_protocol` in the active patch set.

- [ ] **Step 2: Run patch contracts and verify RED.**

```bash
node --test experimental/hcodec/tests/patch-series.test.mjs experimental/hcodec/tests/meson8b-resource-contract.test.mjs
```

Expected: failure because `0022` is still present and the DMA initialization patch is missing.

- [ ] **Step 3: Add the single focused driver patch.** Base its context on the post-`0017` driver and add the exact offsets/values above in the Meson8b branch of `meson_venc_protocol_init` or its equivalent per-command initialization. Do not change the GXL/GXM branch.

- [ ] **Step 4: Apply the patch series in an isolated temporary kernel tree.**

```bash
tmp_kernel=$(mktemp -d /tmp/hcodec-patch-check.XXXXXX)
git clone --filter=blob:none --no-checkout https://github.com/torvalds/linux.git "$tmp_kernel/linux"
git -C "$tmp_kernel/linux" checkout f08cdc6cc92e3d23a05745f0f12f8caa348a27b4
experimental/hcodec/scripts/apply-patches.sh "$tmp_kernel/linux" experimental/hcodec/patches/linux-6.12
rg -n '0x4194|0x419c|0x40a4|0xfd|0xff|0x18' "$tmp_kernel/linux/drivers/media/platform/amlogic/meson-venc/meson-venc.c"
```

Expected: every patch applies and the resulting source contains the exact Meson8b initialization without the offset workaround.

- [ ] **Step 5: Run all tests and shell checks.**

```bash
node --test experimental/hcodec/tests/*.test.mjs
bash -n experimental/hcodec/scripts/*.sh
```

- [ ] **Step 6: Commit the driver protocol change.**

```bash
git add -u experimental/hcodec/patches/linux-6.12/0022-media-meson-use-offset-VLC-ring-base-on-Meson8b.patch
git add experimental/hcodec/patches/linux-6.12/0023-media-meson-match-Meson8b-microcode-protocol.patch experimental/hcodec/tests/patch-series.test.mjs experimental/hcodec/tests/meson8b-resource-contract.test.mjs
git commit -m "fix(hcodec): 匹配Meson8b微码协议"
```

### Task 5: Update Evidence, Build In GitHub, And Hardware-Test

**Files:**
- Modify: `experimental/hcodec/docs/build.md`
- Modify: `experimental/hcodec/docs/artifact.md`
- Modify: `docs/HANDOFF.md`
- Modify: `README.md`
- Modify: `docs/troubleshooting.md`

**Interfaces:**
- Documentation records `run-12-1` as the failed GXL-firmware/IDR-offset candidate and identifies the new Meson8b microcode candidate as unverified until hardware testing.
- GitHub Actions produces and re-verifies one artifact from branch `codex/hcodec-meson8b-ucode`.

- [ ] **Step 1: Write documentation contracts.** Add assertions that the docs mention the `2a5b...` Meson8b dblk digest, the Hardkernel commit, the failed `run-12-1` IDR result, and the rule that no PR is created before 640x480 success. Remove stale text claiming the offset workaround is the current next step.

- [ ] **Step 2: Run docs contracts and the complete local suite.**

```bash
node --test experimental/hcodec/tests/*.test.mjs
bash -n experimental/hcodec/scripts/*.sh
```

- [ ] **Step 3: Push the implementation branch and wait for GitHub Actions.**

```bash
git push -u origin codex/hcodec-meson8b-ucode
gh run list --workflow hcodec-candidate.yml --branch codex/hcodec-meson8b-ucode --limit 3
gh run watch <new-run-id> --exit-status
```

Expected: contract, build, upload, download, and re-verification jobs all succeed. Download the artifact and run `experimental/hcodec/scripts/verify-artifact.sh` independently before device transfer.

- [ ] **Step 4: Transfer and verify on WS1608.** Use `/root/hcodec/run-<run>-<attempt>` on `192.168.100.73`, verify the top-level SHA-256 and artifact manifest on the device, and run `install-artifact.sh . /`. Confirm the firmware file size is `9536`, its SHA-256 is `2a5b...`, `/lib -> usr/lib`, and the module staging directory is removed.

- [ ] **Step 5: Reboot and record boot evidence.** Confirm `uname -r` is `6.12.28-current-meson`, `/dev/video0` exists, `cma=128M` is active, `modinfo meson-venc` reports `meson8b_h264.bin`, and no boot panic/oops exists.

- [ ] **Step 6: Run exactly one hardware probe.** Save before/after CMA and `dmesg`, then run only:

```sh
/root/hcodec/run-<run>-<attempt>/artifact/tools/meson-venc-smoke \
  /dev/video0 /root/hcodec/run-<run>-<attempt>/results/640x480-1f.h264 \
  640 480 1
```

Expected pass: exit `0`, non-empty Annex-B H.264 containing SPS, PPS, and IDR, with no timeout, firmware error, DMA fault, oops, or panic. On failure, stop testing and update the evidence docs; do not create a PR.

- [ ] **Step 7: Commit documentation only after evidence is collected.**

```bash
git add README.md docs/HANDOFF.md docs/troubleshooting.md experimental/hcodec/docs/build.md experimental/hcodec/docs/artifact.md
git commit -m "docs(hcodec): 记录Meson8b微码验证边界"
```
