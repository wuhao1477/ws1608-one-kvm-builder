import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const script = path.resolve('experimental/amlenc/scripts/prepare-public-artifact.sh');

test('publishes only metadata for local-test-only AMLENC outputs', (t) => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-public-artifact-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  const source = path.join(fixture, 'out/amlenc');
  const destination = path.join(fixture, 'out/amlenc-public');
  fs.mkdirSync(path.join(source, 'libvpcodec'), { recursive: true });
  fs.mkdirSync(path.join(source, 'one-kvm'), { recursive: true });
  fs.mkdirSync(path.join(source, 'diagnostic-image'), { recursive: true });
  fs.writeFileSync(path.join(source, 'libvpcodec/source-manifest.json'), '{"redistribution":"local-test-only"}\n');
  fs.writeFileSync(path.join(source, 'libvpcodec/SHA256SUMS'), 'a'.repeat(64) + '  libvpcodec.so\n');
  fs.writeFileSync(path.join(source, 'libvpcodec/libvpcodec.so'), 'private binary');
  fs.writeFileSync(path.join(source, 'one-kvm/package.deb'), 'private package');
  fs.writeFileSync(path.join(source, 'one-kvm/package.deb.sha256'), 'b'.repeat(64) + '  package.deb\n');
  fs.writeFileSync(path.join(source, 'diagnostic-image/image.usb.img'), 'private image');
  fs.writeFileSync(path.join(source, 'diagnostic-image/manifest.json'), '{"hardware_encoder_tested":false}\n');

  const result = spawnSync('bash', [script, source, destination], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const files = fs.readdirSync(destination, { recursive: true })
    .filter((entry) => fs.statSync(path.join(destination, entry)).isFile())
    .sort();
  assert.deepEqual(files, [
    'diagnostic-image/manifest.json',
    'libvpcodec/SHA256SUMS',
    'libvpcodec/source-manifest.json',
    'one-kvm/package.deb.sha256',
  ]);
  assert.match(result.stdout, /prepared 4 public metadata files/);
});

test('rejects encoder metadata that claims redistribution is permitted', (t) => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-public-artifact-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  const source = path.join(fixture, 'source');
  const destination = path.join(fixture, 'destination');
  fs.mkdirSync(path.join(source, 'libvpcodec'), { recursive: true });
  fs.writeFileSync(path.join(source, 'libvpcodec/source-manifest.json'), '{"redistribution":"redistributable"}\n');

  const result = spawnSync('bash', [script, source, destination], { encoding: 'utf8' });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /expected local-test-only redistribution/);
});
