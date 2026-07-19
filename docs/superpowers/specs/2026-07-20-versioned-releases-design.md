# Versioned One-KVM Releases Design

## Goal

Build and publish a WS1608 burn image only when the latest stable One-KVM
input has not already been published. Preserve every intentional rebuild and
make the One-KVM Rust version visible in the tag, title, file name, image
metadata, and manifest.

## Stability Boundary

The stable channel continues to use the newest Armbian base that has completed
physical WS1608 validation. It does not automatically replace the kernel, DTB,
U-Boot, or HDMI configuration. A cloud runner can validate the image structure
and root filesystem, but cannot prove that an untested boot chain starts on
physical hardware.

## Release Identity

An immutable build tag has this form:

```text
ws1608-one-kvm-<deb-version>-<upstream-tag>-b<run-number><attempt>
```

For example, Actions run 14 attempt 1 produces:

```text
ws1608-one-kvm-0.2.4-v260709-b014001
```

The image file uses the same human-readable identity:

```text
One-KVM_0.2.4-v260709-b014001_Onecloud_trixie_6.12.28_HDMI-test.burn.img
```

The run number is padded to at least three digits and the attempt to exactly
three digits. Forced dispatches use independent concurrency groups and create
new immutable Releases; they never replace assets from an earlier build.

## Update Detection

The discovery job obtains the latest non-draft, non-prerelease One-KVM
Release and requires exactly one `one-kvm_*_armhf.deb` asset with a GitHub
SHA-256 digest. It then reads this repository's published Releases and tags.

A scheduled or ordinary manual check skips the image build when a published
Release contains the same upstream tag and package digest. A changed upstream
tag, changed Deb version, or changed package digest starts the next build.
Manual `force=true` also starts the next build, even when the input digest is
unchanged. Release notes contain exact machine-readable identity markers so
the next discovery can make this decision without mutable state files.

## Pipeline And Permissions

The workflow runs once each Sunday at 02:17 UTC, which is one check every seven
days. Pull requests and manual validation runs may execute the complete build
without publishing.

The jobs are separated by responsibility:

1. `discover` validates scripts and resolves the immutable build identity.
2. `build` downloads pinned inputs, builds the image, independently verifies
   it, packages it, verifies every release asset, and uploads one artifact.
3. `release` downloads the verified artifact, repeats release-asset checks,
   atomically creates and verifies the tag, then creates the draft Release.
4. `skipped` records that the exact upstream input was already published.

Repository contents are read-only by default. Only the `release` job receives
`contents: write`, and that job never runs for a pull request or a manual
validation-only run.

## Validation Gates

The existing independent image verification remains mandatory and is extended
to check exact service links, installed configuration files, build metadata,
and absence of build-only files. It continues to verify Amlogic unpacking,
partition layout, unchanged non-rootfs partitions, every partition SHA-1,
sparse conversion, ext4 consistency, Deb version and architecture, ARM ELF,
systemd, and WS1608 OTG integration.

After image validation succeeds, packaging creates a validation report,
compressed image, manifest, and `SHA256SUMS`. A separate asset verifier checks:

- every expected file exists and no unexpected release file is present;
- all manifest identities match workflow inputs;
- all recorded file sizes and SHA-256 digests match the downloaded bytes;
- `SHA256SUMS` is complete and uses base names only;
- the xz stream is valid and decompresses to the raw image digest;
- the validation report says `passed` and explicitly says hardware boot was
  not tested by the hosted runner.

Any failed command or assertion fails the job. The Release job depends on the
successful build job, repeats the asset verifier after artifact download, and
therefore cannot publish a failed or incomplete build.

## Provenance

The root filesystem metadata, manifest, validation report, Release notes, and
Release tag record the One-KVM Deb version, upstream tag, package SHA-256,
build sequence, build tag, builder commit, base image SHA-256, and GitHub run.
The manifest remains the machine-readable source of artifact hashes. Physical
boot, HDMI, video capture, and HID validation stay in the separate hardware
acceptance procedure.

## Verification Strategy

Pure Node.js tests cover release discovery, immutable sequence allocation,
digest-change detection, manifest finalization, and tamper detection. Shell
syntax and workflow policy tests cover the orchestration. A validation-only
GitHub Actions run on the feature branch must complete the full image build
before the pull request is merged. After merge, a publishing run must create
the new versioned Release, and a following ordinary check must skip the build.
