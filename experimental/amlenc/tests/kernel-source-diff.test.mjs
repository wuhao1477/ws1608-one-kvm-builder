import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const verifier = path.resolve('experimental/amlenc/scripts/verify-kernel-source-diff.sh');

function createRepository() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-kernel-source-'));
  const dts = path.join(directory, 'arch/arm/boot/dts/meson8b_odroidc.dts');
  const encoder = path.join(directory, 'drivers/amlogic/amports/encoder.c');
  fs.mkdirSync(path.dirname(dts), { recursive: true });
  fs.mkdirSync(path.dirname(encoder), { recursive: true });
  fs.writeFileSync(dts, 'model = "ODROID-C";\n');
  fs.writeFileSync(encoder, 'reserve_buff[i].buf_size = reserve_mem.buf_start;\n');
  execFileSync('git', ['init', '-q'], { cwd: directory });
  execFileSync('git', ['add', '.'], { cwd: directory });
  execFileSync(
    'git',
    ['-c', 'user.name=test', '-c', 'user.email=test@example.invalid', 'commit', '-q', '-m', 'baseline'],
    { cwd: directory },
  );
  return { directory, dts, encoder };
}

function verify(directory) {
  return spawnSync('bash', [verifier, directory], { encoding: 'utf8' });
}

test('accepts the expected clean WS1608 DTS patch', (t) => {
  const repository = createRepository();
  t.after(() => fs.rmSync(repository.directory, { recursive: true, force: true }));
  fs.writeFileSync(repository.dts, 'model = "WS1608 OneCloud";\n');
  fs.writeFileSync(repository.encoder, 'reserve_buff[i].buf_size = min_buffsize;\n');

  const result = verify(repository.directory);

  assert.equal(result.status, 0, result.stderr);
});

test('rejects whitespace errors in the expected DTS patch', (t) => {
  const repository = createRepository();
  t.after(() => fs.rmSync(repository.directory, { recursive: true, force: true }));
  fs.writeFileSync(repository.dts, 'model = "WS1608 OneCloud";  \n');
  fs.writeFileSync(repository.encoder, 'reserve_buff[i].buf_size = min_buffsize;\n');

  assert.notEqual(verify(repository.directory).status, 0);
});

test('rejects source changes outside the expected DTS', (t) => {
  const repository = createRepository();
  t.after(() => fs.rmSync(repository.directory, { recursive: true, force: true }));
  fs.writeFileSync(repository.dts, 'model = "WS1608 OneCloud";\n');
  fs.writeFileSync(repository.encoder, 'reserve_buff[i].buf_size = min_buffsize;\n');
  fs.writeFileSync(path.join(repository.directory, 'unexpected.txt'), 'unexpected\n');

  assert.notEqual(verify(repository.directory).status, 0);
});
