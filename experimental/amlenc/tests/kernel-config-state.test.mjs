import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const verifier = path.resolve('experimental/amlenc/scripts/verify-kernel-config.sh');

function createFixture(states, cmaSize = 64) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-kernel-config-'));
  const source = path.join(directory, 'source');
  const config = path.join(directory, 'kernel.config');
  const stateFile = path.join(directory, 'states');
  fs.mkdirSync(path.join(source, 'scripts'), { recursive: true });
  fs.writeFileSync(config, `# fixture consumed by scripts/config\nCONFIG_CMA_SIZE_MBYTES=${cmaSize}\n`);
  fs.writeFileSync(
    path.join(source, 'scripts/config'),
    `#!/usr/bin/env bash
set -eu
option=\${4:?missing option}
sed -n "s/^\${option}=//p" "${stateFile}"
`,
    { mode: 0o755 },
  );
  fs.writeFileSync(stateFile, Object.entries(states).map(([key, value]) => `${key}=${value}\n`).join(''));
  return { directory, source, config };
}

function verify(fixture) {
  return spawnSync('bash', [verifier, fixture.source, fixture.config], { encoding: 'utf8' });
}

test('accepts disabled child options that scripts/config reports as undef', (t) => {
  const fixture = createFixture({
    CMA: 'y', AMLOGIC_ION: 'y', USB_GADGET: 'y', AM_ENCODER: 'y',
    MALI400: 'n', MALI450: 'undef', MALI400_UMP: 'undef',
    FB_AMLOGIC_UMP: 'n', FB_TFT: 'n', UMP: 'n',
  });
  t.after(() => fs.rmSync(fixture.directory, { recursive: true, force: true }));

  const result = verify(fixture);

  assert.equal(result.status, 0, result.stderr);
});

test('rejects a required kernel feature that is not enabled', (t) => {
  const fixture = createFixture({
    CMA: 'n', AMLOGIC_ION: 'y', USB_GADGET: 'y', AM_ENCODER: 'y',
    MALI400: 'n', MALI450: 'undef', MALI400_UMP: 'undef',
    FB_AMLOGIC_UMP: 'n', FB_TFT: 'n', UMP: 'n',
  });
  t.after(() => fs.rmSync(fixture.directory, { recursive: true, force: true }));

  assert.notEqual(verify(fixture).status, 0);
});

test('rejects an unwanted kernel feature that remains enabled', (t) => {
  const fixture = createFixture({
    CMA: 'y', AMLOGIC_ION: 'y', USB_GADGET: 'y', AM_ENCODER: 'y',
    MALI400: 'n', MALI450: 'y', MALI400_UMP: 'undef',
    FB_AMLOGIC_UMP: 'n', FB_TFT: 'n', UMP: 'n',
  });
  t.after(() => fs.rmSync(fixture.directory, { recursive: true, force: true }));

  assert.notEqual(verify(fixture).status, 0);
});

test('rejects a CMA pool smaller than the legacy encoder requirement', (t) => {
  const fixture = createFixture({
    CMA: 'y', AMLOGIC_ION: 'y', USB_GADGET: 'y', AM_ENCODER: 'y',
    MALI400: 'n', MALI450: 'n', MALI400_UMP: 'undef',
    FB_AMLOGIC_UMP: 'n', FB_TFT: 'n', UMP: 'n',
  }, 8);
  t.after(() => fs.rmSync(fixture.directory, { recursive: true, force: true }));

  const result = verify(fixture);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /CMA_SIZE_MBYTES must be 64/);
});
