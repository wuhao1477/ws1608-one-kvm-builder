import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const workflowPath = '.github/workflows/amlenc-legacy-bringup.yml';

test('keeps legacy bring-up contract-only on pull requests', () => {
  assert.equal(fs.existsSync(workflowPath), true, 'legacy bring-up workflow is required');
  const workflow = fs.readFileSync(workflowPath, 'utf8');
  const contract = workflow.slice(workflow.indexOf('\n  contract:'), workflow.indexOf('\n  build:'));
  assert.match(workflow, /pull_request:/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(contract, /actions\/checkout@[\s\S]*fetch-depth: 0/);
  assert.doesNotMatch(workflow, /schedule:|repository_dispatch:/);
  assert.match(workflow, /^permissions:\n  contents: read$/m);
  assert.match(workflow, /if: github\.event_name == 'workflow_dispatch'/);
  assert.match(workflow, /verify-stable-chain\.sh/);
  assert.match(workflow, /git diff --exit-code -- \.github\/workflows\/build\.yml config\/base\.env/);
});

test('requires a public key and derives an immutable build revision', () => {
  const workflow = fs.readFileSync(workflowPath, 'utf8');
  assert.match(workflow, /^      ssh_public_key_b64:\n        description:/m);
  assert.match(workflow, /required: true[\s\S]*type: string/);
  assert.match(workflow, /base64 --decode/);
  assert.match(workflow, /ssh-keygen -l -f/);
  assert.match(workflow, /GITHUB_RUN_NUMBER \* 1000 \+ GITHUB_RUN_ATTEMPT/);
  assert.match(workflow, /printf 'b%06d'/);
  assert.doesNotMatch(workflow, /ssh-keygen[^\n]* -t /);
});

test('builds, independently verifies and downloads exactly one candidate artifact', () => {
  const workflow = fs.readFileSync(workflowPath, 'utf8');
  const hostTools = workflow.slice(
    workflow.indexOf('- name: Install build tools'),
    workflow.indexOf('- uses: actions/setup-go'),
  );
  for (const command of [
    'build-kernel.sh', 'verify-build.sh kernel', 'build-legacy-bringup-image.sh',
    'verify-legacy-bringup-image.sh', 'sha256sum --check', 'xz -t',
  ]) assert.match(workflow, new RegExp(command.replaceAll('.', '\\.')));
  assert.match(hostTools, /apt-get install[\s\S]*binutils-arm-linux-gnueabihf/);
  assert.match(workflow, /actions\/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a/);
  assert.match(workflow, /actions\/download-artifact@37930b1c2abaa49bbe596cd826c3c89aef350131/);
  assert.match(workflow, /retention-days: 14/);
  assert.match(workflow, /hardware_boot_tested.*false/);
  assert.match(workflow, /hardware_encoder_tested.*false/);
  assert.match(workflow, /one_kvm_included.*false/);
  assert.doesNotMatch(workflow, /gh release|contents: write|RELEASE_PRERELEASE|publish:/);
  const buildImage = workflow.indexOf('Build recovery-first image');
  const verify = workflow.indexOf('Verify recovery-first image');
  const upload = workflow.indexOf('Upload recovery-first artifact');
  const download = workflow.indexOf('Download recovery-first artifact');
  const reverify = workflow.indexOf('Reverify downloaded candidate');
  assert.ok(buildImage >= 0 && verify > buildImage && upload > verify && download > upload && reverify > download);
});
