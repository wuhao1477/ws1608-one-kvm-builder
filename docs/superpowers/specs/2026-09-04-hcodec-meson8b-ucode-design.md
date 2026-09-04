# Meson8b HCODEC Microcode Design

## Status

Approved for implementation on branch `codex/hcodec-meson8b-ucode`.

## Problem

The `run-12-1` Armbian/Linux 6.12 candidate boots and registers `/dev/video0`,
but a 640x480 MMAP encode fails at the first IDR command. The device log shows
that `SEQUENCE` and `PICTURE` complete, while IDR writes seven bytes and then
times out with `-ETIMEDOUT`. CMA remains available and the system continues to
run normally.

The candidate currently extracts a 24 KiB `gxl_h264_enc.bin` record from the
stable image's `h264_enc.bin` container and installs it under the Meson8b
firmware name. Hardkernel's fixed Linux source for the Meson8/Meson8b encoder
contains a separate `mix_dump_mc_dblk` microcode path of about 9.5 KiB and
initializes additional Assist DMA interrupt registers. The current candidate
does not use that Meson8b source path.

## Goal

Build a new ARMv7 candidate whose Meson8b firmware and register initialization
match the Hardkernel M8 encoder source closely enough to retest the first IDR
command on WS1608.

## Non-goals

- Do not revive the Linux 3.10 user-space ABI or `/dev/amvenc_avc`.
- Do not change the stable Armbian image or One-KVM service configuration.
- Do not test 720p or 1080p before a 640x480 single-frame probe passes.
- Do not create or merge a pull request before the new candidate is flashed and
  hardware-tested.
- Do not use the old GXL 24 KiB firmware as the Meson8b candidate input.

## Design

### Firmware source

Use the pinned Hardkernel Linux commit
`5aed95d35d252cafc75ce613a3a0052285662de2` as the reproducible GPL source.
Fetch `drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h` in the
cloud build and convert its `MicroCode[]` word array to little-endian raw bytes.
The expected source contains 2384 words, or 9536 bytes. The generated digest is
recorded in the kernel source manifest and in the artifact manifest.

The generated `meson8b_h264.bin` is a build output, not a checked-in binary.
The artifact verifier must allow this exact generated file and reject any other
firmware binary. The source URL, commit, input path, word count, output size,
and output SHA-256 remain part of the manifest.

### Driver protocol

Keep the existing Meson8b V4L2 M2M interface, Canvas setup, power sequencing,
and Armbian resource ownership. Add the M8 initialization required before the
first command:

- Define the Meson8b Assist DMA interrupt mask registers used by the vendor
  encoder.
- Program both DMA masks to the M8 full-microcode defaults before loading the
  frame command.
- Preserve the existing Meson8b-specific MFDIN bank and non-GXL protocol
  fields.
- Remove the run-12 offset VLC ring-base workaround; it was disproved by the
  hardware log and must not remain in the candidate path.

The Meson8b firmware minimum-size check must match the selected dblk source
length. The driver must continue rejecting truncated or oversized microcode.

### Build and artifact flow

The GitHub Actions candidate workflow remains the only build path for the
kernel and generated firmware. The workflow will:

1. Run the existing contract tests plus the new microcode-source contracts.
2. Download and verify the pinned Hardkernel source archive.
3. Extract the dblk word array and generate the raw firmware in the build
   workspace.
4. Build the ARMv7 kernel, module, DTB, and tools.
5. Package the generated firmware with the candidate artifact.
6. Re-verify the uploaded and downloaded artifact before device transfer.

The installer will copy the generated `meson8b_h264.bin` into
`/lib/firmware/meson/venc/` and will continue staging modules on the target
root partition rather than `/tmp`.

## Verification

### Automated

- Contract test proves the pinned source path, commit, word count, output size,
  and generated firmware manifest fields.
- Contract test proves the driver defines and writes both Assist DMA masks and
  no longer contains the offset VLC ring-base workaround.
- Existing HCODEC test suite remains green.
- `bash -n experimental/hcodec/scripts/*.sh` remains green.
- GitHub Actions artifact verification passes after upload/download.

### Hardware

After artifact verification, install on `192.168.100.73` using the target-root
staging installer and reboot. Record kernel, DTB, firmware, `/lib` symlink,
CMA, and `/dev/video0` state. Run exactly one command:

```sh
/root/hcodec/<run>/artifact/tools/meson-venc-smoke \
  /dev/video0 /root/hcodec/<run>/results/640x480-1f.h264 \
  640 480 1
```

A pass requires a zero exit status, non-empty Annex-B output, SPS/PPS, an IDR
NAL, and no HCODEC timeout, firmware error, DMA fault, oops, or panic. A
failure stops the candidate sequence and leaves the stable backup available.

## Rollout boundary

No PR is created from this branch until the new candidate completes the single
640x480 hardware probe. A failed probe produces a diagnostic report and a new
design decision; it does not trigger another unverified parameter change.
