# WS1608 One-KVM Full Codec Software Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a flashable WS1608 experimental burn image whose armhf One-KVM package proves H.264, H.265, VP8 and VP9 software encoding and decoding before reporting those codecs as available.

**Architecture:** Keep the stable 6.12 boot chain unchanged and use the existing experimental stable-rootfs image path for the software-codec burn candidate. Patch the pinned One-KVM source to make software codec discovery truthful and expose a standalone armhf self-check. A separate QEMU gate proves the packaged binary, then the burn-image verifier preserves the codec capability record in the final five-file artifact.

**Tech Stack:** One-KVM Rust `v260802`, FFmpeg Rockchip static ARMv7 build, `libx264`, `libx265`, `libvpx`, Rust/Clap, Bash, Node.js tests, Docker/QEMU, GitHub Actions, AmlImg.

**Spec:** `docs/superpowers/specs/2026-08-25-ws1608-one-kvm-full-codec-software-baseline-design.md`

## Global Constraints

- Target codec set is exactly H.264, H.265, VP8 and VP9; MJPEG and audio are outside this slice.
- Each target codec must use its named software FFmpeg encoder and matching decoder in armhf runtime validation.
- S805 hardware remains H.264-candidate-only; H.265, VP8 and VP9 hardware must remain disabled.
- The stable workflow, `config/base.env`, stable base image and stable-chain manifest must not change.
- GitHub Actions keeps `hardware_boot_tested=false` and `hardware_encoder_tested=false`.
- The final candidate remains an experimental five-file burn artifact with `one_kvm_included=true`.
- Every source input, codec library commit and package capability record is pinned and verified.

---

### Task 1: Pin And Describe The Four Software Codecs

**Files:**
- Create: `experimental/amlenc/config/software-codecs.json`
- Modify: `experimental/amlenc/config/sources.env`
- Modify: `experimental/amlenc/scripts/verify-source-locks.mjs`
- Modify: `experimental/amlenc/patches/one-kvm/0002-pin-armv7-build-inputs.patch`
- Modify: `experimental/amlenc/tests/one-kvm-contract.test.mjs`

**Interfaces:**
- Consumes: pinned One-KVM `v260802` source and its `build/cross/Dockerfile.armv7`.
- Produces: `software-codecs.json` with exactly four codec objects and source-lock keys `ONE_KVM_LIBVPX_COMMIT=1024874c5919305883187e2953de8fcb4c3d7fa6` and `ONE_KVM_X265_COMMIT=07295ba7ab551bb9c1580fdaee3200f1b45711b7`.

- [ ] **Step 1: Write the failing contract test**

Add a test that loads `software-codecs.json` and requires this exact normalized
value:

```js
{
  schema: 1,
  codecs: [
    { id: 'h264', encoder: 'libx264', decoder: 'h264' },
    { id: 'h265', encoder: 'libx265', decoder: 'hevc' },
    { id: 'vp8', encoder: 'libvpx', decoder: 'vp8' },
    { id: 'vp9', encoder: 'libvpx-vp9', decoder: 'vp9' },
  ],
}
```

Require the source-lock verifier to reject missing or malformed x265/libvpx
commits. Require the ARMv7 patch to set both Docker `ARG` values from those
locks and to contain all four `--enable-encoder` plus all four
`--enable-decoder` options.

- [ ] **Step 2: Verify the test fails**

Run:

```bash
node --test experimental/amlenc/tests/one-kvm-contract.test.mjs
```

Expected: failure because the codec manifest, source-lock checks and decoder
options do not yet exist.

- [ ] **Step 3: Implement the locked capability inputs**

Create `software-codecs.json` with the exact four rows above. Add the two
commit keys to `sources.env`. Extend `verify-source-locks.mjs` to require
40 lowercase hexadecimal characters for both values. Extend patch `0002` so its
ARMv7 Dockerfile changes use:

```dockerfile
ARG LIBVPX_REV=1024874c5919305883187e2953de8fcb4c3d7fa6
ARG X265_REV=07295ba7ab551bb9c1580fdaee3200f1b45711b7
```

Replace tag fetches with `git fetch --depth 1 origin "${LIBVPX_REV}"` and
`git fetch --depth 1 origin "${X265_REV}"`, followed by detached checkout of
`FETCH_HEAD`.

and FFmpeg adds:

```text
--enable-decoder=h264
--enable-decoder=hevc
--enable-decoder=vp8
--enable-decoder=vp9
```

Keep all existing static encoder switches unchanged.

- [ ] **Step 4: Verify the contract passes**

Run:

```bash
node --test experimental/amlenc/tests/one-kvm-contract.test.mjs
node experimental/amlenc/scripts/verify-source-locks.mjs experimental/amlenc/config/sources.env
```

Expected: all One-KVM contract cases pass and the source lock verifier reports
four immutable source locks.

- [ ] **Step 5: Commit**

```bash
git add experimental/amlenc/config/software-codecs.json experimental/amlenc/config/sources.env experimental/amlenc/scripts/verify-source-locks.mjs experimental/amlenc/patches/one-kvm/0002-pin-armv7-build-inputs.patch experimental/amlenc/tests/one-kvm-contract.test.mjs
git commit -S -m "feat(amlenc): 锁定四种软件编码输入"
```

### Task 2: Add Truthful Registry And Standalone Software Self-Check

**Files:**
- Create: `experimental/amlenc/patches/one-kvm/0003-software-codec-self-check.patch`
- Modify: `experimental/amlenc/tests/one-kvm-contract.test.mjs`

**Interfaces:**
- Consumes: the four codec contract from Task 1 and the pinned One-KVM source.
- Produces: `one-kvm codec self-check --backend software --json`, returning a
  JSON object with `backend:"software"`, one `320p` row, exactly four result
  cells and nonzero status when any result fails.

- [ ] **Step 1: Write the failing contract test**

Require patch `0003` to add these stable interfaces:

```rust
enum CodecSelfCheckBackend { Software, Hardware }
fn run_codec_self_check(backend: CodecSelfCheckBackend) -> VideoEncoderSelfCheckResponse
fn has_encoder(name: &str) -> bool
```

Require `CliCommand::Codec`, `CodecAction::SelfCheck`,
`--backend software`, `--json`, one JSON row per exact codec id, and tests that
software mode never selects a hardware encoder. Require the patch to call
matching decode helpers after encoding.

- [ ] **Step 2: Verify the test fails**

Run:

```bash
node --test experimental/amlenc/tests/one-kvm-contract.test.mjs
```

Expected: failure because patch `0003` does not exist.

- [ ] **Step 3: Implement the upstream patch**

Generate the patch from a clean copy of the locked One-KVM source. Make these
changes:

```text
libs/hwcodec/cpp/ffmpeg_ram/ffmpeg_ram_ffi.h
    Add int ffmpeg_ram_has_encoder(const char *name).

libs/hwcodec/cpp/ffmpeg_ram/ffmpeg_ram_encode.cpp
    Implement it with avcodec_find_encoder_by_name(name) != NULL.

libs/hwcodec/src/ffmpeg_ram/mod.rs
    Expose pub fn has_encoder(name: &str) -> bool through the generated FFI.

src/video/codec/registry.rs
    Register each CodecInfo::software(format) only when has_encoder(name) is true.
    Keep every accepted hardware backend ahead of software by priority.

src/video/codec/self_check.rs
    Add Software and Hardware selection, use 320x240 at 10 fps for Software,
    encode ten deterministic YUV420P frames, request a keyframe for H.264/H.265,
    decode the packets, compare submitted and decoded frame counts, and return
    sanitized per-codec errors.

src/main.rs
    Add `one-kvm codec self-check --backend software --json`.
```

The JSON response must contain this shape for software mode:

```json
{
  "backend": "software",
  "rows": [{
    "resolution_id": "320p",
    "width": 320,
    "height": 240,
    "cells": [{
      "codec_id": "h264",
      "encoder": "libx264",
      "backend": "software",
      "submitted_frames": 10,
      "decoded_frames": 10,
      "keyframe": true,
      "ok": true
    }]
  }]
}
```

Leave the existing `/video/encoder/self-check` endpoint unchanged and
hardware-only. This task exposes software validation only through the CLI.

- [ ] **Step 4: Verify the source patch applies and unit tests pass**

Run:

```bash
patch_probe_dir=$(mktemp -d /tmp/ws1608-one-kvm-patch.XXXXXX)
curl --fail --location https://codeload.github.com/mofeng-git/One-KVM/tar.gz/a4073d64cb49a1404df49e7813b73dd9f78d0931 -o "$patch_probe_dir/one-kvm.tar.gz"
mkdir "$patch_probe_dir/source"
tar -xzf "$patch_probe_dir/one-kvm.tar.gz" -C "$patch_probe_dir/source" --strip-components=1
git -C "$patch_probe_dir/source" init -q
git -C "$patch_probe_dir/source" add --all
git -C "$patch_probe_dir/source" -c user.name=verify -c user.email=verify@example.invalid -c commit.gpgsign=false commit -qm baseline
node --test experimental/amlenc/tests/one-kvm-contract.test.mjs
git -C "$patch_probe_dir/source" apply --check "$PWD/experimental/amlenc/patches/one-kvm/0003-software-codec-self-check.patch"
```

Expected: contract test passes and the pinned source accepts the patch without
offset or rejection.

- [ ] **Step 5: Commit**

```bash
git add experimental/amlenc/patches/one-kvm/0003-software-codec-self-check.patch experimental/amlenc/tests/one-kvm-contract.test.mjs
git commit -S -m "feat(amlenc): 增加四编码软件自检"
```

### Task 3: Verify The Armhf Package At Runtime

**Files:**
- Create: `experimental/amlenc/scripts/verify-one-kvm-software-codecs.sh`
- Modify: `experimental/amlenc/scripts/build-one-kvm.sh`
- Modify: `experimental/amlenc/scripts/verify-one-kvm.sh`
- Modify: `experimental/amlenc/scripts/verify-one-kvm-metadata.mjs`
- Modify: `experimental/amlenc/tests/one-kvm-contract.test.mjs`
- Modify: `.github/workflows/amlenc-experimental.yml`

**Interfaces:**
- Consumes: `software-codecs.json`, patched armhf Deb and QEMU user emulation.
- Produces: a package metadata field `software_codecs` equal to the four codec
  contract and an executable runtime verifier.

- [ ] **Step 1: Write failing tests for metadata and workflow order**

Extend the metadata fixture with:

```js
software_codecs: [
  { id: 'h264', encoder: 'libx264', decoder: 'h264', hardware: false },
  { id: 'h265', encoder: 'libx265', decoder: 'hevc', hardware: false },
  { id: 'vp8', encoder: 'libvpx', decoder: 'vp8', hardware: false },
  { id: 'vp9', encoder: 'libvpx-vp9', decoder: 'vp9', hardware: false },
]
```

Require `verify-one-kvm.sh` to reject a missing codec or `hardware:true`.
Require the workflow to run `verify-one-kvm-software-codecs.sh` after package
verification and before burn-image assembly.

- [ ] **Step 2: Verify the tests fail**

Run:

```bash
node --test experimental/amlenc/tests/one-kvm-contract.test.mjs experimental/amlenc/tests/workflow-policy.test.mjs
```

Expected: failure because metadata and QEMU runtime verification are absent.

- [ ] **Step 3: Implement package and QEMU validation**

Have `build-one-kvm.sh` load `software-codecs.json` with `jq`, insert its
four rows into `ws1608-amlenc-build.json`, and add that JSON file to package
checksums. Extend both metadata verifiers to require the exact ordered codec
set and `hardware:false` for each item.

Implement the runtime verifier with this execution boundary after it has set
`package=$(realpath "$1")`, `package_dir=$(dirname "$package")` and
`package_name=$(basename "$package")`:

```bash
docker run --rm --platform linux/arm/v7 \
  -e PACKAGE_NAME="$package_name" -v "$package_dir:/input:ro" "$ONE_KVM_ARMV7_OCI_IMAGE" sh -euc '
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates libasound2 libssl1.1 libudev1 libv4l-0
    dpkg -i "/input/$PACKAGE_NAME" || apt-get -fy install
    one-kvm codec self-check --backend software --json >/tmp/codecs.json
    jq -e '\''
      .backend == "software" and
      (.rows | length) == 1 and
      .rows[0].resolution_id == "320p" and
      .rows[0].width == 320 and .rows[0].height == 240 and
      ([.rows[0].cells[].codec_id] | sort) == ["h264", "h265", "vp8", "vp9"] and
      all(.rows[0].cells[];
        .backend == "software" and .ok == true and
        .submitted_frames == 10 and .decoded_frames == 10 and
        (.encoder == "libx264" or .encoder == "libx265" or .encoder == "libvpx" or .encoder == "libvpx-vp9"))
    '\'' /tmp/codecs.json
  '
```

The script must validate the package filename before mounting it, reject a
non-armhf package, and leave no generated artifact inside the repository.

- [ ] **Step 4: Verify the tests pass**

Run:

```bash
node --test experimental/amlenc/tests/one-kvm-contract.test.mjs experimental/amlenc/tests/workflow-policy.test.mjs
bash -n experimental/amlenc/scripts/verify-one-kvm-software-codecs.sh
```

Expected: static tests pass and the script has valid shell syntax. The full
armhf runtime execution occurs in GitHub Actions.

- [ ] **Step 5: Commit**

```bash
git add experimental/amlenc/scripts/verify-one-kvm-software-codecs.sh experimental/amlenc/scripts/build-one-kvm.sh experimental/amlenc/scripts/verify-one-kvm.sh experimental/amlenc/scripts/verify-one-kvm-metadata.mjs experimental/amlenc/tests/one-kvm-contract.test.mjs experimental/amlenc/tests/workflow-policy.test.mjs .github/workflows/amlenc-experimental.yml
git commit -S -m "test(amlenc): 验证 armhf 四编码软件路径"
```

### Task 4: Carry Software Capability Into The Burn Candidate

**Files:**
- Modify: `experimental/amlenc/scripts/build-burn-image.sh`
- Modify: `experimental/amlenc/scripts/verify-burn-image.sh`
- Modify: `experimental/amlenc/scripts/package-burn-release.sh`
- Modify: `experimental/amlenc/scripts/verify-burn-release.sh`
- Modify: `experimental/amlenc/tests/burn-image-contract.test.mjs`
- Modify: `experimental/amlenc/tests/workflow-policy.test.mjs`

**Interfaces:**
- Consumes: verified One-KVM package metadata with exact `software_codecs`.
- Produces: stable-boot experimental burn manifest containing
  `codec_baseline.software` and `hardware_encoder_tested=false`.

- [ ] **Step 1: Write failing burn-image contract tests**

Require the final burn manifest to contain:

```json
"codec_baseline": {
  "software": ["h264", "h265", "vp8", "vp9"],
  "hardware": [],
  "runtime_verified": true
}
```

Require the burn verifier to extract the package metadata from rootfs and
compare its exact four software entries against this manifest. Require the
release verifier to reject an unexpected hardware codec or missing software
codec.

- [ ] **Step 2: Verify the tests fail**

Run:

```bash
node --test experimental/amlenc/tests/burn-image-contract.test.mjs experimental/amlenc/tests/workflow-policy.test.mjs
```

Expected: failure because the burn manifest has no codec baseline.

- [ ] **Step 3: Implement the burn manifest and verifier gate**

`build-burn-image.sh` must read the package metadata before image assembly,
require the four verified software codec entries, and write the exact
`codec_baseline` object above. `verify-burn-image.sh` must extract
`ws1608-amlenc-build.json` from rootfs, verify its checksums, compare the
codec rows, and reject any `hardware:true` baseline entry.

Keep the normal experimental image on the verified stable 6.12 boot path.
Do not add 3.10 boot files, do not alter stable files, and do not set an
AMLENC smoke-test environment variable.

- [ ] **Step 4: Verify the burn contracts pass**

Run:

```bash
node --test experimental/amlenc/tests/burn-image-contract.test.mjs experimental/amlenc/tests/workflow-policy.test.mjs
experimental/amlenc/scripts/verify-stable-chain.sh
```

Expected: the burn contract accepts the exact software baseline and the stable
chain reports its protected file count unchanged.

- [ ] **Step 5: Commit**

```bash
git add experimental/amlenc/scripts/build-burn-image.sh experimental/amlenc/scripts/verify-burn-image.sh experimental/amlenc/scripts/package-burn-release.sh experimental/amlenc/scripts/verify-burn-release.sh experimental/amlenc/tests/burn-image-contract.test.mjs experimental/amlenc/tests/workflow-policy.test.mjs
git commit -S -m "feat(amlenc): 记录 burn 镜像软件编码基线"
```

### Task 5: Build And Reverify The Manual Flash Candidate

**Files:**
- Modify: `docs/superpowers/plans/2026-08-25-ws1608-one-kvm-full-codec-software-baseline-plan.md`

**Interfaces:**
- Consumes: all prior commits and the `amlenc-experimental.yml` workflow.
- Produces: one GitHub Actions artifact containing exactly the raw burn image,
  `.xz`, `manifest.json`, `validation-report.json` and `SHA256SUMS`.

- [ ] **Step 1: Push all implementation commits**

Run:

```bash
git push origin codex/amlenc-legacy-bringup
```

- [ ] **Step 2: Dispatch the experimental workflow without publication**

Run:

```bash
gh workflow run amlenc-experimental.yml \
  --repo wuhao1477/ws1608-one-kvm-builder \
  --ref codex/amlenc-legacy-bringup \
  -f publish=false \
  -f acknowledge_experimental=false
```

Expected: contract, package, QEMU software-codec verification, burn-image
verification, release-asset verification and artifact upload all succeed.

- [ ] **Step 3: Download and reverify outside the worktree**

Run:

```bash
run_id=$(gh run list --repo wuhao1477/ws1608-one-kvm-builder --workflow amlenc-experimental.yml --branch codex/amlenc-legacy-bringup --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')
candidate_dir="/tmp/ws1608-codec-candidate-$run_id"
mkdir -p "$candidate_dir"
gh run download "$run_id" --repo wuhao1477/ws1608-one-kvm-builder --dir "$candidate_dir"
cd "$candidate_dir"
sha256sum --check SHA256SUMS
xz -t *.burn.img.xz
jq '.codec_baseline' manifest.json
```

Expected: exactly five regular files, valid hashes and xz stream, four
software codec ids, empty hardware list and all hardware test fields false.

- [ ] **Step 4: Record evidence and commit**

Add the Actions run URL, artifact id, image filename, both image digests and
codec baseline result to this plan. Commit:

```bash
git add docs/superpowers/plans/2026-08-25-ws1608-one-kvm-full-codec-software-baseline-plan.md
git commit -S -m "docs(amlenc): 记录四编码候选构建证据"
git push origin codex/amlenc-legacy-bringup
```

- [ ] **Step 5: Hand off for physical flash validation**

Provide the absolute local `.burn.img.xz` path and state that manual tests must
verify boot, DHCP/SSH, `/stream/codecs`, the four-codec self-check, each stream
mode and hardware status before any Release or stable-channel change.
