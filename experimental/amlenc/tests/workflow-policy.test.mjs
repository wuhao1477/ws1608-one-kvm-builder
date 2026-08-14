import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const workflowPath = '.github/workflows/amlenc-experimental.yml';

test('keeps AMLENC builds isolated from the stable image workflow', () => {
  assert.equal(fs.existsSync(workflowPath), true, `${workflowPath} must exist`);
  const workflow = fs.readFileSync(workflowPath, 'utf8');

  assert.match(workflow, /pull_request:/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.doesNotMatch(workflow, /schedule:/);
  assert.doesNotMatch(workflow, /repository_dispatch:/);
  assert.match(workflow, /experimental\/amlenc\/scripts\/verify-source-locks\.mjs/);
  assert.equal(
    workflow.match(/experimental\/amlenc\/scripts\/verify-stable-chain\.sh/g)?.length,
    2,
    'the stable chain must be verified before builds and again before upload',
  );
  assert.match(workflow, /experimental\/amlenc\/scripts\/build-kernel\.sh/);
  assert.match(workflow, /experimental\/amlenc\/scripts\/build-libvpcodec\.sh/);
  assert.match(workflow, /experimental\/amlenc\/scripts\/build-one-kvm\.sh/);
  assert.match(workflow, /AMLENC_CROSS_IMAGE: ws1608-one-kvm-armv7:\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}/);
  assert.match(workflow, /DOCKER_BUILDKIT[^\n]*1/);
  assert.doesNotMatch(workflow, /apt-get install[^\n]*docker\.io/);
  assert.match(workflow, /docker version/);
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
  assert.match(workflow, /local-test-only/);
  assert.match(workflow, /experimental\/amlenc\/scripts\/prepare-public-artifact\.sh/);
  assert.match(workflow, /path: out\/amlenc-public/);
  assert.doesNotMatch(workflow, /path: out\/amlenc\s*$/m);
  assert.match(workflow, /\.github\/workflows\/build\.yml/);
});
