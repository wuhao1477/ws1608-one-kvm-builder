import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const script = 'experimental/hcodec/scripts/capture-probe.sh';

function executable(file, source) {
  fs.writeFileSync(file, source, { mode: 0o755 });
}

function fixture(t, smokeExit) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-probe-capture-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const bin = path.join(root, 'bin');
  const results = path.join(root, 'results');
  const smoke = path.join(root, 'smoke');
  fs.mkdirSync(bin);
  executable(path.join(bin, 'dmesg'), `#!/bin/sh
case "$*" in
  *--follow*)
    printf 'live kernel trace\\n'
    trap 'exit 0' TERM
    while :; do sleep 1; done
    ;;
  *) printf 'kernel snapshot\\n' ;;
esac
`);
  executable(path.join(bin, 'sync'), '#!/bin/sh\nexit 0\n');
  executable(smoke, `#!/bin/sh
printf 'smoke stdout\\n'
printf 'smoke stderr\\n' >&2
printf 'h264' >"$2"
exit ${smokeExit}
`);
  return { bin, results, smoke };
}

function runProbe(fixture) {
  return spawnSync('bash', [script, fixture.results, fixture.smoke,
    '/dev/video0', path.join(fixture.results, 'stream.h264'), '640', '480', '1'], {
    encoding: 'utf8',
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}` },
  });
}

test('persists live and post-probe kernel evidence after a successful smoke run', (t) => {
  const data = fixture(t, 0);
  const result = runProbe(data);
  const { results } = data;

  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(path.join(results, 'exit-status'), 'utf8'), '0\n');
  assert.match(fs.readFileSync(path.join(results, 'kernel.before.log'), 'utf8'), /snapshot/);
  assert.match(fs.readFileSync(path.join(results, 'kernel.live.log'), 'utf8'), /live kernel trace/);
  assert.match(fs.readFileSync(path.join(results, 'kernel.after.log'), 'utf8'), /snapshot/);
  assert.equal(fs.readFileSync(path.join(results, 'probe.stdout.log'), 'utf8'), 'smoke stdout\n');
  assert.equal(fs.readFileSync(path.join(results, 'probe.stderr.log'), 'utf8'), 'smoke stderr\n');
  assert.match(fs.readFileSync(script, 'utf8'), /dmesg --follow-new --time-format iso/);
});

test('persists an unsuccessful smoke exit status', (t) => {
  const data = fixture(t, 7);
  const result = runProbe(data);

  assert.equal(result.status, 7, result.stderr);
  assert.equal(fs.readFileSync(path.join(data.results, 'exit-status'), 'utf8'), '7\n');
});
