# One-KVM Cloud Release Hardening Implementation Plan

**Status:** Completed on 2026-07-20. Physical WS1608 validation remains a separate post-release task.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make WS1608 One-KVM cloud builds immutable, clearly traceable to the One-KVM Rust version, and publishable only after local, artifact, and remote asset verification succeeds.

**Architecture:** Keep the stable Armbian/Amlogic base fixed. Add a pure release-identity module for the short tag and image filename, a standalone artifact verifier for checksum/manifest/xz round-trips, and a draft-release workflow that validates GitHub asset digests before publishing. Existing Amlogic/rootfs verification remains the authoritative image-content check.

**Tech Stack:** Bash, Node.js ESM/node:test, GitHub Actions, GitHub CLI, jq, xz, AmlImg, e2fsprogs.

## Global Constraints

- Tag format is `ws1608-one-kvm-<deb-version>-<upstream-tag>-<UTC-HHMMSS>`.
- The legacy tag `ws1608-one-kvm-v260709` counts as an existing successful build.
- `force=true` creates a new immutable Release and never overwrites an old one.
- Any failed check stops publication.
- CI cannot prove physical WS1608 boot, HDMI, capture, or HID behavior.
- `.codegraph/` is local index data and must remain ignored.

---

### Task 1: Commit approved design and repository hygiene

**Files:**
- Create: `docs/superpowers/specs/2026-07-20-one-kvm-release-identity-design.md`
- Create: `docs/superpowers/plans/2026-07-20-one-kvm-cloud-release-hardening.md`
- Modify: `.gitignore`

- [x] Add `.codegraph/` to `.gitignore`.
- [x] Run `git check-ignore -q .codegraph/ && npm test`; expect exit 0.
- [x] Commit with `git commit -S -m 'docs: 固化云构建发布设计'`.

### Task 2: Add tested release identity formatting

**Files:**
- Create: `scripts/lib/release-identity.mjs`
- Create: `tests/release-identity.test.mjs`
- Modify: `scripts/discover-release.sh`

**Interfaces:**
- `formatReleaseIdentity({ version, upstreamTag, buildTime })` returns `safeUpstreamTag`, `buildTag`, `imageStem`, and `imageName`.
- Discovery outputs `build_tag`, `build_stamp`, `image_stem`, and `image_name`.

- [x] Write a failing test asserting tag `ws1608-one-kvm-0.2.4-v260709-143015`, filename `One-KVM_0.2.4_v260709_143015_Onecloud_trixie_6.12.28_HDMI-test.burn.img`, and rejection of invalid time/tag/version input.
- [x] Run `node --test tests/release-identity.test.mjs`; expect missing-module failure.
- [x] Implement the pure formatter without filesystem, clock, or GitHub access.
- [x] Update discovery to compute UTC `HHMMSS`, recognize legacy/new successful published Releases, and let `FORCE_BUILD=true` override skipping.
- [x] Run `npm test && for script in scripts/*.sh; do bash -n "$script"; done`.
- [x] Commit with `git commit -S -m 'feat: 标准化 One-KVM 构建身份'`.

### Task 3: Make image and manifest self-identifying

**Files:**
- Modify: `scripts/build-image.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Build consumes `BUILD_STAMP`, `BUILD_TAG`, `ONE_KVM_VERSION`, and `UPSTREAM_TAG`.
- Manifest records image hashes, package/base/tool sources, builder commit, complete build time, run ID, and run attempt.

- [x] Pass discovery identity outputs to the build job.
- [x] Replace version-only image names with the identity filename.
- [x] Keep `SHA256SUMS` basename-only and add compressed-image hash/source fields after compression.
- [x] Run `npm test`, all `bash -n` checks, and actionlint.

### Task 4: Add artifact and post-build verification

**Files:**
- Create: `scripts/verify-artifacts.mjs`
- Create: `tests/verify-artifacts.test.mjs`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- CLI positional arguments are `ARTIFACT_DIR`, `EXPECTED_IMAGE_NAME`, and `EXPECTED_JSON` in that order.
- Require exactly the raw image, xz image, `SHA256SUMS`, and `manifest.json`.
- Stream hashes; decompress xz to a temporary file; compare bytes; validate manifest identity/hashes.

- [x] Write a success test and a failing checksum-mutation test.
- [x] Run `node --test tests/verify-artifacts.test.mjs`; expect missing-module failure.
- [x] Implement streaming hashes, strict checksum parsing, xz round-trip, exact file set, and manifest checks.
- [x] Verify locally after compression, upload artifact, download into a fresh directory, then repeat artifact verification and `verify-image.sh`.
- [x] Run all tests, shell syntax checks, diff check, and actionlint.
- [x] Commit with `git commit -S -m 'feat: 增加成品资产验证门槛'`.

### Task 5: Publish immutable draft Releases

**Files:**
- Create: `tests/workflow-release.test.mjs`
- Modify: `.github/workflows/build.yml`
- Modify: `docs/build-pipeline.md`
- Modify: `docs/maintenance.md`
- Modify: `docs/troubleshooting.md`

- [x] Write a failing static test requiring `--draft`, `--draft=false`, artifact download, remote digest verification, and rejecting `--clobber`.
- [x] Run `node --test tests/workflow-release.test.mjs`; expect failure against the overwrite workflow.
- [x] Reject existing build tags, create a draft only after all local gates, compare four GitHub asset digests with local SHA-256, then publish.
- [x] On pre-publication failure, delete the new draft/tag with `gh release delete --yes --cleanup-tag`; never alter an existing published Release.
- [x] Update docs and run the full local verification suite.

### Task 6: Cloud validation and handoff

**Files:**
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/HANDOFF.md`
- Modify: `docs/architecture.md`
- Modify: `docs/hardware-validation.md`
- Modify: `docs/adr/0001-pinned-base-weekly-check.md`
- Create: `/tmp/ws1608-one-kvm-builder-handoff.md`

- [x] Sign, commit, and push all implementation changes.
- [x] Trigger `force=false`; verify the new-format existing build causes the image job to skip (`29697714162`).
- [x] Trigger `force=true`; require all local/artifact/image/draft/remote gates to pass (`29697101081`).
- [x] Re-download the complete Actions artifact and run `verify-artifacts.mjs` plus `verify-image.sh`; independently download Release metadata and compare all four remote asset digests. Local large-image downloads were intentionally avoided because storage was constrained.
- [x] Record actual run IDs, tag, hashes, and physical-test boundary in `docs/HANDOFF.md`.
- [x] Write a redacted temporary handoff with suggested skills and push final documentation.
