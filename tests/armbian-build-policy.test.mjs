import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const workflow = fs.readFileSync('.github/workflows/build-base.yml', 'utf8');
const config = fs.readFileSync('config/armbian-build.env', 'utf8');
const script = fs.readFileSync('scripts/build-armbian-base.sh', 'utf8');
const source = `${workflow}\n${config}\n${script}`;

test('builds one fixed Trixie OneCloud burn image from pinned sources', () => {
  assert.match(source, /BOARD=onecloud/);
  assert.match(source, /BRANCH=current/);
  assert.match(source, /RELEASE=trixie/);
  assert.match(config, /ARMBIAN_COMMIT=[0-9a-f]{40}/);
  assert.match(config, /UBOOT_SHA256=[0-9a-f]{64}/);
  assert.match(config, /ARMBIAN_HDMI_PATCH_SHA256=[0-9a-f]{64}/);
  assert.match(source, /\.burn\.img/);
  assert.doesNotMatch(workflow, /matrix:/);
  assert.doesNotMatch(workflow, /strategy:/);
  assert.doesNotMatch(workflow, /bookworm|noble|sid|server|cli/);
});

test('keeps source-image builds separate from the stable One-KVM workflow', () => {
  assert.match(workflow, /workflow_dispatch/);
  assert.doesNotMatch(workflow, /publish-release\.sh/);
  assert.doesNotMatch(workflow, /config\/base\.env/);
  assert.doesNotMatch(script, /publish-release\.sh/);
});
