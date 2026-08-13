import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import test from 'node:test';

const workflowPath = '.github/workflows/build.yml';
const baseConfigPath = 'config/base.env';
const sourcesPath = 'experimental/amlenc/config/sources.env';
const validatorPath = 'experimental/amlenc/scripts/verify-source-locks.mjs';

test('preserves the verified stable image channel', () => {
  const workflow = fs.readFileSync(workflowPath, 'utf8');
  const baseConfig = fs.readFileSync(baseConfigPath, 'utf8');

  assert.match(workflow, /cron: "17 2 \* \* 0"/);
  assert.match(workflow, /source config\/base\.env/);
  assert.match(workflow, /ws1608-one-kvm-/);
  assert.doesNotMatch(workflow, /experimental\/amlenc/);
  assert.match(baseConfig, /^BASE_RELEASE_TAG=base-20260804-consolefix$/m);
});

test('accepts only immutable experimental source inputs', () => {
  assert.equal(fs.existsSync(sourcesPath), true, `${sourcesPath} must exist`);
  assert.equal(fs.existsSync(validatorPath), true, `${validatorPath} must exist`);

  const result = spawnSync(process.execPath, [validatorPath, sourcesPath], {
    cwd: process.cwd(),
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /verified 4 immutable source locks/);
  const sources = fs.readFileSync(sourcesPath, 'utf8');
  assert.match(sources, /^BULLSEYE_ARMV7_OCI_IMAGE=debian:bullseye@sha256:[a-f0-9]{64}$/m);
  assert.match(sources, /^IMAGE_TOOLS_ARM64_OCI_IMAGE=debian:bookworm-slim@sha256:[a-f0-9]{64}$/m);
});
