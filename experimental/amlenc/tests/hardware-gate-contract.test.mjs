import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const validator = 'experimental/amlenc/scripts/validate-h264.sh';
const limits = 'experimental/amlenc/config/hardware-limits.json';

function writeExecutable(filePath, contents) {
  fs.writeFileSync(filePath, contents, { mode: 0o755 });
}

function createFixture(t, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-hardware-gate-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const bin = path.join(root, 'bin');
  const output = path.join(root, 'result');
  const stream = path.join(root, 'probe.h264');
  const kernelLog = path.join(root, 'kernel.log');
  fs.mkdirSync(bin);
  fs.writeFileSync(stream, 'annex-b-fixture');
  fs.writeFileSync(kernelLog, options.kernelLog ?? 'amvenc_avc: encoder ready\n');

  const profile = options.profile ?? {
    id: '640x480-300f', width: 640, height: 480, frames: 300,
  };
  const metadata = options.metadata ?? {
    streams: [{
      codec_name: 'h264',
      width: profile.width,
      height: profile.height,
      r_frame_rate: '30/1',
      avg_frame_rate: '30/1',
      nb_read_frames: String(profile.frames),
    }],
  };
  writeExecutable(path.join(bin, 'ffprobe'), `#!/usr/bin/env bash\nprintf '%s\\n' '${JSON.stringify(metadata)}'\n`);
  writeExecutable(path.join(bin, 'ffmpeg'), `#!/usr/bin/env bash
set -eu
case " $* " in
  *" trace_headers "*)
    printf '%s\\n' '${options.headers ?? 'Sequence Parameter Set|Picture Parameter Set|IDR'}' >&2
    ;;
  *)
    ${options.decodeFailure ? "echo 'decode corruption' >&2; exit 1" : ':'}
    ;;
esac
`);

  return { root, bin, output, stream, kernelLog, profile };
}

function runGate(fixture) {
  return spawnSync('bash', [
    validator,
    '--probe', fixture.profile.id,
    '--input', fixture.stream,
    '--kernel-log', fixture.kernelLog,
    '--output-dir', fixture.output,
  ], {
    cwd: process.cwd(),
    env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}` },
    encoding: 'utf8',
  });
}

test('accepts all fixed probes only after independent stream and kernel checks', async (t) => {
  assert.equal(fs.existsSync(validator), true, `${validator} must exist`);
  assert.equal(fs.existsSync(limits), true, `${limits} must exist`);
  const profiles = [
    { id: '640x480-300f', width: 640, height: 480, frames: 300, bitrate: 1000000, duration: 10 },
    { id: '1280x720-1800f', width: 1280, height: 720, frames: 1800, bitrate: 4000000, duration: 60 },
    { id: '1280x720-8h', width: 1280, height: 720, frames: 864000, bitrate: 4000000, duration: 28800 },
  ];

  for (const profile of profiles) {
    await t.test(profile.id, () => {
      const fixture = createFixture(t, { profile });
      const result = runGate(fixture);
      assert.equal(result.status, 0, result.stderr || result.stdout);
      const report = JSON.parse(fs.readFileSync(path.join(fixture.output, 'validation.json')));
      assert.deepEqual(report.expected, {
        width: profile.width, height: profile.height, fps: 30, frames: profile.frames,
        bitrate: profile.bitrate, duration_seconds: profile.duration,
      });
      assert.deepEqual(report.observed, {
        codec: 'h264', width: profile.width, height: profile.height,
        fps: 30, frames: profile.frames, duration_seconds: profile.duration,
      });
      assert.deepEqual(report.annex_b, { sps: true, pps: true, idr: true });
      assert.equal(report.kernel_errors, 0);
      assert.equal(report.decode_errors, 0);
      assert.equal(report.status, 'passed');
      assert.match(report.stream_sha256, /^[a-f0-9]{64}$/);
      assert.match(fs.readFileSync(path.join(fixture.output, 'SHA256SUMS'), 'utf8'), /  validation\.json$/m);
    });
  }
});

test('rejects an incorrect decoded frame count', (t) => {
  const fixture = createFixture(t, {
    metadata: {
      streams: [{
        codec_name: 'h264', width: 640, height: 480,
        r_frame_rate: '30/1', avg_frame_rate: '30/1', nb_read_frames: '299',
      }],
    },
  });

  const result = runGate(fixture);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /frame count/i);
});

test('uses r_frame_rate when raw H.264 reports avg_frame_rate as zero', (t) => {
  const fixture = createFixture(t, {
    metadata: {
      streams: [{
        codec_name: 'h264', width: 640, height: 480,
        r_frame_rate: '30/1', avg_frame_rate: '0/0', nb_read_frames: '300',
      }],
    },
  });

  const result = runGate(fixture);

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const report = JSON.parse(fs.readFileSync(path.join(fixture.output, 'validation.json')));
  assert.equal(report.observed.fps, 30);
});

test('rejects a stream without SPS, PPS, and IDR units', (t) => {
  const fixture = createFixture(t, { headers: 'Sequence Parameter Set|IDR' });

  const result = runGate(fixture);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /PPS/i);
});

test('rejects decoder failures and kernel encoder faults', async (t) => {
  await t.test('decoder failure', () => {
    const fixture = createFixture(t, { decodeFailure: true });
    const result = runGate(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /decode/i);
  });

  await t.test('kernel fault', () => {
    const fixture = createFixture(t, { kernelLog: 'Internal error: Oops: 5 [#1] SMP ARM\n' });
    const result = runGate(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /kernel/i);
  });
});

test('redacts network and device identifiers from kernel evidence', (t) => {
  const address = [192, 0, 2, 10].join('.');
  const fixture = createFixture(t, {
    kernelLog: `amvenc_avc: peer=${address} mac=aa:bb:cc:dd:ee:ff serial=SECRET123 ready\n`,
  });

  const result = runGate(fixture);

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const evidence = fs.readFileSync(path.join(fixture.output, 'kernel-encoder.log'), 'utf8');
  assert.equal(evidence.includes(address), false);
  assert.doesNotMatch(evidence, /aa:bb:cc:dd:ee:ff|SECRET123/);
  assert.match(evidence, /\[REDACTED_IPV4\]/);
  assert.match(evidence, /\[REDACTED_MAC\]/);
  assert.match(evidence, /serial=\[REDACTED_SERIAL\]/);
});

test('redacts secrets from a failed kernel evidence bundle', (t) => {
  const address = [192, 0, 2, 10].join('.');
  const fixture = createFixture(t, {
    kernelLog: `amvenc_avc: encoder timeout peer=${address} password=SECRET token=TOKEN123\n`,
  });

  const result = runGate(fixture);

  assert.notEqual(result.status, 0);
  const evidence = fs.readFileSync(path.join(fixture.output, 'kernel-errors.log'), 'utf8');
  assert.equal(evidence.includes(address), false);
  assert.doesNotMatch(evidence, /password=SECRET(?:\s|$)|token=TOKEN123(?:\s|$)/);
  assert.match(evidence, /\[REDACTED_IPV4\]/);
  assert.match(evidence, /password=\[REDACTED_SECRET\]/);
  assert.match(evidence, /token=\[REDACTED_SECRET\]/);
});

test('refuses to mix current evidence with a nonempty output directory', (t) => {
  const fixture = createFixture(t);
  fs.mkdirSync(fixture.output);
  fs.writeFileSync(path.join(fixture.output, 'validation.json'), '{"status":"passed"}\n');

  const result = runGate(fixture);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /output directory.*empty/i);
});
