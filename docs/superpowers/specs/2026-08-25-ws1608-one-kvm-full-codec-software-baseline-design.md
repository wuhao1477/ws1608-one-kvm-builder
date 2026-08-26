# WS1608 One-KVM Full Codec Software Baseline Design

**Date:** 2026-08-25

**Status:** Awaiting user review

**Parent:** [Issue #9](https://github.com/wuhao1477/ws1608-one-kvm-builder/issues/9)

## Goal

Make the current One-KVM video codec set usable on WS1608: H.264/AVC,
H.265/HEVC, VP8 and VP9. Every codec must have a real software encode and
decode proof on armhf before One-KVM reports it as available. Hardware
registration remains separate and evidence-gated.

## Scope

This design implements the first vertical slice of Issue #9: the four-video-
codec software baseline. MJPEG stays on its existing HTTP path and is not one
of the WebRTC codec gates. Audio codecs and any future upstream video codec
are outside this slice.

## Fixed Facts

- One-KVM `v260802` defines four `VideoEncoderType` values: H.264, H.265,
  VP8 and VP9.
- Its ARMv7 Dockerfile already builds static `libx264`, `libx265` and
  `libvpx`, and configures FFmpeg for the `libx264`, `libx265`,
  `libvpx_vp8` and `libvpx_vp9` build components. Their runtime encoder names
  are `libx264`, `libx265`, `libvpx` and `libvpx-vp9`.
- The current registry registers these names as fallbacks even when a runtime
  probe has not proved the matching FFmpeg encoder exists. That can make
  `/stream/codecs` claim a codec that fails during stream creation.
- The current self-check endpoint chooses only hardware encoders and checks
  for nonempty output. It cannot prove the four software paths or decode them.
- WS1608/S805 has no accepted H.265, VP8 or VP9 hardware encoder evidence.
  `amvenc_avc` remains a separate H.264-only hardware candidate.

## Invariants

- The stable 6.12 image workflow, base image, burn container, stable tags and
  stable Releases remain unchanged.
- H.264, H.265, VP8 and VP9 software paths stay available regardless of any
  Amlogic hardware probe result.
- A codec is not reported as available merely because its expected name is
  known. The embedded FFmpeg encoder must exist and a runtime self-check must
  create and decode a stream.
- S805 must not register `hevc_amlenc`, VP8 AMLENC or VP9 AMLENC without a
  separately accepted hardware capability record.
- GitHub Actions reports only build and emulated armhf validation. It never
  changes any hardware test field to true.

## Architecture

### Build capability contract

The ARMv7 build inputs must pin the x265 and libvpx source versions alongside
the existing x264 pin. The patched ARMv7 Dockerfile must build all three static
libraries, enable the four software encoders, and enable the matching H.264,
HEVC, VP8 and VP9 decoders required by the self-check.

The package metadata gains a codec capability section with exactly these four
software entries:

| Codec id | FFmpeg encoder | FFmpeg decoder | Backend |
| --- | --- | --- | --- |
| `h264` | `libx264` | `h264` | `Software` |
| `h265` | `libx265` | `hevc` | `Software` |
| `vp8` | `libvpx` | `vp8` | `Software` |
| `vp9` | `libvpx-vp9` | `vp9` | `Software` |

The metadata records the pinned dependency identities and `hardware=false` for
every baseline entry. No password, device address or private runtime log is
stored in it.

### Truthful registry

The One-KVM codec registry gains an FFmpeg-backed `has_encoder(name)` query.
Software fallback registration calls that query for every expected encoder.
It adds a fallback only when the embedded FFmpeg binary actually contains the
encoder. The registry retains all detected hardware encoders and ranks them
before software encoders, but it never removes a verified software entry.

`/stream/codecs` continues to return H.264, H.265, VP8 and VP9. For this
baseline its selected backend must be `Software`, `hardware=false`, and
`available=true`. Later hardware registration may change the selected backend
for a codec only after its separate evidence gate passes; the software backend
remains listed in the registry.

### Software self-check

One-KVM gains a `codec self-check --backend software --json` command. It runs
without starting the web server, capture device, OTG service or database.

For each of the four codecs it must:

1. construct a deterministic YUV420P `320x240` test sequence at 10 fps;
2. encode at least ten frames with the required software encoder;
3. force a keyframe where the codec supports it;
4. reject empty output, timeout, invalid packet sequence or unsupported
   encoder;
5. decode the encoded packets with the matching embedded FFmpeg decoder;
6. require decoded frame count equal to submitted frame count; and
7. emit one JSON result row containing codec id, encoder name, backend,
   frame counts, keyframe result, elapsed time and a sanitized error value.

The command exits zero only when all four rows pass. A failed codec reports its
own failure but makes the command nonzero. This slice leaves the existing
hardware-only endpoint unchanged.

### Build and runtime verification

The package verifier first checks that the metadata describes exactly the four
software codec entries and that the binary contains no dynamic dependency on
the three static codec libraries. GitHub Actions then installs the armhf Deb
inside a `linux/arm/v7` runtime under QEMU and runs:

```text
one-kvm codec self-check --backend software --json
```

The workflow parses the JSON and rejects missing codecs, a hardware backend,
an encoder mismatch, failed decode, zero output, a frame count mismatch or an
unexpected result row. It does not need a capture device or WS1608 hardware.

The physical WS1608 test later repeats the same command, requests every mode
through `/stream/mode`, checks `/stream/codecs`, and records measured CPU and
frame rate separately. Passing the smoke check proves functional availability,
not a 720p30 performance claim for software H.265 or VP9.

## Hardware Boundary

Hardware registration follows only after this software baseline:

- S805 H.264 AMLENC is evaluated only on the recoverable 3.10.107 trial path.
- S805 H.265, VP8 and VP9 remain software-only until a driver, userspace ABI,
  valid hardware bitstream and error-free physical test exist.
- A hardware creation or encoding failure retries the selected verified
  software encoder for the same codec before surfacing a stream failure.
- Hardware tests are separately versioned and cannot alter the stable image
  channel.

## Error Handling

- Missing static FFmpeg encoder or decoder fails the cloud package gate.
- A self-check timeout, zero packet, invalid keyframe, decoder error or frame
  count mismatch fails that codec and returns a nonzero command status.
- The API reports a codec unavailable when its FFmpeg encoder is absent;
  it never substitutes a fabricated fallback name.
- A failed hardware probe logs the backend failure and selects the verified
  software encoder. It does not change the hardware capability record.

## Acceptance Criteria

- [ ] ARMv7 FFmpeg is built with `libx264`, `libx265`, the `libvpx_vp8` and
  `libvpx_vp9` build components, plus H.264, HEVC, VP8 and VP9 decoders.
- [ ] The armhf self-check verifies encode, keyframe and decode for all four
  codecs under QEMU.
- [ ] `/stream/codecs` reports all four codecs as software available when no
  hardware backend is accepted.
- [ ] One failed software codec makes package verification fail and identifies
  the failing codec without exposing sensitive runtime data.
- [ ] Existing S805 AMLENC policy remains H.264-only and disabled until its
  separate physical evidence gate passes.
- [ ] Stable image workflow and stable-chain digest checks remain unchanged.
