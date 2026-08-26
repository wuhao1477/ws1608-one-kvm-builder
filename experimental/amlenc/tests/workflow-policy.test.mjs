import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const workflowPath = '.github/workflows/amlenc-experimental.yml';

test('keeps AMLENC builds isolated from the stable image workflow', () => {
  assert.equal(fs.existsSync(workflowPath), true, `${workflowPath} must exist`);
  const workflow = fs.readFileSync(workflowPath, 'utf8');
  const contract = workflow.slice(workflow.indexOf('\n  contract:'), workflow.indexOf('\n  build:'));

  assert.match(workflow, /pull_request:/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(contract, /actions\/checkout@[\s\S]*fetch-depth: 0/);
  assert.doesNotMatch(workflow, /schedule:/);
  assert.doesNotMatch(workflow, /repository_dispatch:/);
  assert.match(workflow, /experimental\/amlenc\/scripts\/verify-source-locks\.mjs/);
  assert.match(workflow, /experimental\/amlenc\/scripts\/verify-stable-kernel-boundary\.sh/);
  assert.equal(
    workflow.match(/experimental\/amlenc\/scripts\/verify-stable-chain\.sh/g)?.length,
    2,
    'the stable chain must be verified before builds and again before upload',
  );
  assert.match(workflow, /experimental\/amlenc\/scripts\/build-kernel\.sh/);
  assert.match(workflow, /experimental\/amlenc\/scripts\/build-libvpcodec\.sh/);
  assert.match(workflow, /experimental\/amlenc\/scripts\/build-diagnostic-image\.sh --build/);
  assert.match(workflow, /ssh-keygen -q -t ed25519 -N ''/);
  assert.match(workflow, /AMLENC_SSH_PUBLIC_KEY=.*key_file\.pub/);
  assert.match(workflow, /experimental\/amlenc\/scripts\/build-one-kvm\.sh/);
  assert.match(workflow, /AMLENC_CROSS_IMAGE: ws1608-one-kvm-armv7:\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}/);
  assert.match(workflow, /DOCKER_BUILDKIT[^\n]*1/);
  assert.doesNotMatch(workflow, /apt-get install[^\n]*docker\.io/);
  assert.match(workflow, /docker version/);
  assert.match(workflow, /source experimental\/amlenc\/config\/sources\.env/);
  assert.match(workflow, /--default-toolchain "\$ONE_KVM_RUST_TOOLCHAIN"/);
  assert.match(workflow, /rustup default "\$ONE_KVM_RUST_TOOLCHAIN"/);
  assert.doesNotMatch(workflow, /--default-toolchain stable/);
  assert.equal(workflow.match(/qemu-user-static/g)?.length, 2);
  assert.match(workflow, /gcc-arm-linux-gnueabihf/);
  assert.match(workflow, /Verify encoder library[\s\S]*CC: arm-linux-gnueabihf-gcc/);
  assert.match(workflow, /g\+\+-7-arm-linux-gnueabihf/);
  assert.match(workflow, /ln -sf.*arm-linux-gnueabihf-gcc-7.*arm-linux-gnueabihf-gcc/);
  assert.equal(workflow.match(/ln -sf.*command -v gcc-7.*\/usr\/local\/bin\/gcc/g)?.length, 2);
  assert.equal(
    workflow.match(/apt-get install -y bc curl file git lzop/g)?.length,
    2,
    'both legacy build containers must install the file utility used by artifact verification',
  );
  assert.match(workflow, /experimental\/amlenc\/scripts\/verify-one-kvm\.sh/);
  assert.match(workflow, /ONE_KVM_DEB:/);
  assert.doesNotMatch(workflow, /DIAGNOSTIC_IMAGE:|DIAGNOSTIC_MANIFEST:/);
  assert.match(workflow, /stable_base_preserved == true/);
  assert.match(workflow, /kernel\.version == "6\.12\.28-current-meson"/);
  assert.match(workflow, /Upload legacy research artifacts/);
  assert.match(workflow, /path: \|\s*out\/amlenc\/kernel\//);
  assert.equal(
    workflow.match(/sudo chown -R "\$\(id -u\):\$\(id -g\)" \.build\/amlenc out\/amlenc/g)?.length,
    2,
    'both root-owned container build stages must return artifacts to the runner user',
  );
  assert.equal(
    workflow.match(/ubuntu:18\.04 bash -lc '\s*set -euo pipefail/g)?.length,
    2,
    'both legacy toolchain containers must propagate command failures',
  );
  assert.match(workflow, /hardware_encoder_tested.*false|hardware_encoder_tested=false/);
  assert.match(workflow, /stable_channel_modified.*false|stable_channel_modified=false/);
  assert.match(workflow, /ws1608-amlenc-exp-/);
  assert.doesNotMatch(workflow, /gh release create/);
  assert.match(workflow, /experimental\/amlenc\/scripts\/verify-burn-release\.sh/);
  assert.match(workflow, /path: out\/amlenc\/burn\//);
  assert.match(workflow, /\.github\/workflows\/build\.yml/);
});

test('publishes an explicitly acknowledged immutable experimental prerelease', () => {
  const workflow = fs.readFileSync(workflowPath, 'utf8');
  const buildJob = workflow.slice(workflow.indexOf('\n  build:'), workflow.indexOf('\n  release:'));
  const releaseJob = workflow.slice(workflow.indexOf('\n  release:'));

  assert.match(workflow, /^      publish:\n        description:/m);
  assert.equal(workflow.match(/^        default: false$/gm)?.length, 2);
  assert.match(workflow, /^      acknowledge_experimental:\n        description:/m);
  assert.match(workflow, /inputs\.publish && inputs\.acknowledge_experimental/);
  assert.match(workflow, /github\.ref == format\('refs\/heads\/\{0\}', github\.event\.repository\.default_branch\)/);
  assert.match(releaseJob, /^    permissions:\n      contents: write$/m);
  assert.match(releaseJob, /needs: \[contract, build, reverify\]/);
  assert.match(buildJob, /path: out\/amlenc\/burn\//);
  assert.match(releaseJob, /actions\/download-artifact@37930b1c2abaa49bbe596cd826c3c89aef350131/);
  assert.match(releaseJob, /experimental\/amlenc\/scripts\/verify-burn-release\.sh/);
  assert.match(releaseJob, /experimental\/amlenc\/scripts\/verify-burn-image\.sh/);
  assert.match(releaseJob, /scripts\/publish-release\.sh/);
  assert.match(releaseJob, /RELEASE_PRERELEASE: 'true'/);
  assert.match(releaseJob, /ws1608-amlenc-exp-0\.2\.6-v260802-k6\.12\.28-\$build_revision/);
  assert.doesNotMatch(releaseJob, /Kernel: 3\.10\.107/);
  assert.doesNotMatch(releaseJob, /--clobber|--latest/);
});

test('reverifies every uploaded candidate before handoff or publication', () => {
  const workflow = fs.readFileSync(workflowPath, 'utf8');
  const reverifyStart = workflow.indexOf('\n  reverify:');
  const releaseStart = workflow.indexOf('\n  release:');

  assert.ok(reverifyStart >= 0, 'a post-upload reverify job is required');
  assert.ok(releaseStart > reverifyStart, 'reverify must precede release');
  const reverifyJob = workflow.slice(reverifyStart, releaseStart);

  assert.match(reverifyJob, /needs: build/);
  assert.match(reverifyJob, /actions\/download-artifact@37930b1c2abaa49bbe596cd826c3c89aef350131/);
  assert.match(reverifyJob, /artifact_name=ws1608-amlenc-exp-release-\$\{RUN_NUMBER\}-\$\{RUN_ATTEMPT\}/);
  assert.match(reverifyJob, /sha256sum --check SHA256SUMS/);
  assert.match(reverifyJob, /xz -t/);
  assert.match(reverifyJob, /experimental\/amlenc\/scripts\/verify-burn-release\.sh/);
  assert.match(reverifyJob, /experimental\/amlenc\/scripts\/verify-burn-image\.sh/);
  assert.match(reverifyJob, /hardware_encoder_tested == false/);
  assert.match(reverifyJob, /hardware_boot_tested == false/);
  assert.match(reverifyJob, /one_kvm_included == true/);
  assert.match(workflow.slice(releaseStart), /needs: \[contract, build, reverify\]/);
});
