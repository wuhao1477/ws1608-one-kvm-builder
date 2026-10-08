# Versioned One-KVM Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish immutable, repeatable WS1608 builds whose identity visibly includes the One-KVM Rust version, while skipping unchanged weekly inputs and blocking every unverified Release.

**Architecture:** A pure Node.js discovery module derives the input identity and a collision-free build number from GitHub Release/tag JSON plus the Actions run identity. The build job creates and independently validates the image, then a release-asset module finalizes and validates provenance before a separately permissioned release job publishes it.

**Tech Stack:** Bash, Node.js built-in test runner, GitHub Actions, `gh`, AmlImg, qemu-user-static, ext4 tools, xz.

## Global Constraints

- Schedule exactly one check each Sunday at `02:17 UTC`.
- Do not build when a published Release has the same upstream tag and package SHA-256.
- Use immutable tags `ws1608-one-kvm-<deb-version>-<upstream-tag>-b<run-number><attempt>`.
- A forced rebuild uses an independent run identity and never overwrites an earlier Release.
- Only a post-validation release job may have `contents: write`.
- Keep the physically validated Armbian 26.8 Trixie 6.12.28 base pinned.
- Hosted CI must not claim that physical WS1608 boot, HDMI, video, or HID passed.

---

### Task 1: Release Discovery And Immutable Build Identity

**Files:**
- Create: `scripts/lib/release-discovery.mjs`
- Create: `scripts/discover-release.mjs`
- Modify: `scripts/discover-release.sh`
- Create: `tests/release-discovery.test.mjs`

**Interfaces:**
- Consumes: latest upstream Release JSON and paginated target Release JSON.
- Produces: `discoverRelease({ upstreamRelease, existingReleases, forceBuild })` with `changed`, `releaseTag`, `oneKvmVersion`, `packageDigest`, `buildNumber`, and `buildTag`.

- [ ] **Step 1: Write failing discovery tests**

  Cover first build, unchanged input skip, parallel forced identities, changed
  digest allocation, missing digest rejection, and multiple armhf assets.

- [ ] **Step 2: Run the focused test and observe RED**

  Run: `node --test tests/release-discovery.test.mjs`

  Expected: FAIL because `scripts/lib/release-discovery.mjs` does not exist.

- [ ] **Step 3: Implement the pure discovery module and CLI**

  Validate stable release metadata, exact armhf selection, 64-character
  SHA-256, safe tag components, published marker matching, and numeric build
  sequences. Keep GitHub API calls in the shell wrapper and JSON decisions in
  the pure module.

- [ ] **Step 4: Run focused and complete tests**

  Run: `node --test tests/release-discovery.test.mjs && npm test`

  Expected: all tests pass with zero failures.

### Task 2: Build Identity Inside The Image

**Files:**
- Modify: `scripts/build-image.sh`
- Modify: `scripts/verify-image.sh`
- Create: `tests/image-scripts-policy.test.mjs`

**Interfaces:**
- Consumes: `BUILD_TAG`, `BUILD_NUMBER`, `PACKAGE_DIGEST`, and `BUILDER_COMMIT`.
- Produces: versioned image name, partial manifest, rootfs release metadata,
  and `validation-report.json` after independent verification.

- [ ] **Step 1: Write failing policy tests**

  Assert that the build script requires every provenance input and that the
  verifier checks exact metadata, service target, source configuration files,
  and absence of temporary build tools.

- [ ] **Step 2: Observe RED**

  Run: `node --test tests/image-scripts-policy.test.mjs`

  Expected: FAIL because build sequence and provenance checks are absent.

- [ ] **Step 3: Add the minimum image metadata and verification gates**

  Derive `One-KVM_<version>-<tag>-bRRRAAA_<base>.burn.img` from the validated
  build tag. Write the complete identity to `/etc/ws1608-one-kvm-release` and
  verify every field from the independently unpacked final image.

- [ ] **Step 4: Run policy and syntax tests**

  Run: `node --test tests/image-scripts-policy.test.mjs && for script in scripts/*.sh; do bash -n "$script"; done`

  Expected: all tests and syntax checks pass.

### Task 3: Release Asset Finalization And Tamper Detection

**Files:**
- Create: `scripts/lib/release-metadata.mjs`
- Create: `scripts/finalize-release.mjs`
- Create: `scripts/verify-release-assets.mjs`
- Create: `scripts/package-release.sh`
- Create: `scripts/verify-release-assets.sh`
- Create: `tests/release-metadata.test.mjs`

**Interfaces:**
- Consumes: partial manifest, raw image, xz image, validation report, expected
  workflow identity, package/base digests, builder commit, and run ID.
- Produces: final `manifest.json`, deterministic `SHA256SUMS`, and a successful
  verification result or nonzero exit.

- [ ] **Step 1: Write failing metadata tests**

  Test valid finalization plus rejection of a modified image, incorrect build
  tag, failed validation report, missing checksum, path-bearing checksum, and
  unexpected release file.

- [ ] **Step 2: Observe RED**

  Run: `node --test tests/release-metadata.test.mjs`

  Expected: FAIL because the release metadata module does not exist.

- [ ] **Step 3: Implement finalization and verification**

  Use Node built-ins for JSON, file size, and SHA-256 checks. Use xz only in
  the shell layer to create/test the stream and compare the decompressed hash
  with the raw image hash.

- [ ] **Step 4: Run focused, full, and shell tests**

  Run: `node --test tests/release-metadata.test.mjs && npm test && for script in scripts/*.sh; do bash -n "$script"; done`

  Expected: all checks pass with zero failures.

### Task 4: Permission-Separated GitHub Actions Pipeline

**Files:**
- Modify: `.github/workflows/build.yml`
- Create: `tests/workflow-policy.test.mjs`

**Interfaces:**
- Consumes: discovery outputs and verified workflow artifact.
- Produces: skipped check, validation-only artifact, or immutable GitHub
  Release with a versioned tag.

- [ ] **Step 1: Write failing workflow policy tests**

  Assert weekly cron, pull-request validation, read-only default permission,
  write permission only on `release`, build gating on `changed`, release gating
  on build success and publish mode, pinned action SHAs, and no `--clobber`.

- [ ] **Step 2: Observe RED**

  Run: `node --test tests/workflow-policy.test.mjs`

  Expected: FAIL on current overwrite publishing and broad write permission.

- [ ] **Step 3: Split build and release jobs**

  Pass all identity outputs into the build, run independent image and asset
  verification before upload, download and reverify the artifact in `release`,
  then create a new Release with exact machine-readable markers.

- [ ] **Step 4: Run local workflow validation**

  Run: `npm test && for script in scripts/*.sh; do bash -n "$script"; done && actionlint`

  Expected: all tests pass, all shell files parse, and actionlint reports no
  findings.

### Task 5: Documentation, PR, And Cloud Proof

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/build-pipeline.md`
- Modify: `docs/maintenance.md`
- Modify: `docs/troubleshooting.md`
- Modify: `docs/HANDOFF.md`
- Create: `docs/adr/0002-immutable-versioned-rebuilds.md`

**Interfaces:**
- Consumes: verified implementation and GitHub Actions run results.
- Produces: operator documentation, pull request, validation-only run, first
  immutable Release, and proof that the next unchanged check skips the build.

- [ ] **Step 1: Update documentation and scan stale behavior**

  Run: `rg -n 'overwrite|覆盖同名|ws1608-one-kvm-<upstream-tag>|--clobber|force=true' README.md docs .github scripts`

  Expected: every remaining force reference describes a new build sequence.

- [ ] **Step 2: Run fresh local verification**

  Run: `npm test && for script in scripts/*.sh; do bash -n "$script"; done && actionlint && git diff --check`

  Expected: all commands exit zero.

- [ ] **Step 3: Commit, push, and open a pull request**

  Use a signed Conventional Commit with a Chinese summary, push the feature
  branch, and create a pull request targeting `main`.

- [ ] **Step 4: Run the full cloud build without publishing**

  Dispatch the feature branch with `force=true` and `publish=false`, then
  inspect every job and failed assertion before merge.

- [ ] **Step 5: Merge and prove immutable publishing plus skip behavior**

  Merge only after cloud validation succeeds. Dispatch `main` with
  `force=true,publish=true`, verify the new versioned tag and all five assets, then
  dispatch `force=false` and verify that the build job is skipped.
