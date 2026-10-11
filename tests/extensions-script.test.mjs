import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const script = 'config/one-kvm-extensions.sh';
const binaries = { frpc: '/usr/bin/frpc', easytier: '/usr/bin/easytier-core', gostc: '/usr/bin/gostc' };

test('the login hint lists exactly the extensions One-KVM cannot find', () => {
  const result = spawnSync('bash', [script, '--hint'], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const missing = Object.keys(binaries).filter((name) => !fs.existsSync(binaries[name]));
  if (missing.length === 0) return assert.equal(result.stdout, '');
  assert.match(result.stdout, new RegExp(`未安装：${missing.join(' ')}\\n`));
  assert.match(result.stdout, /~\/one-kvm-extensions\.sh/);
});

test('installs only as root and pins every download by sha256', { skip: process.getuid?.() === 0 }, () => {
  const result = spawnSync('bash', [script, 'frpc'], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  const source = fs.readFileSync(script, 'utf8');
  for (const [name, path] of Object.entries(binaries)) {
    assert.match(source, new RegExp(`${name}\\) echo ${path} \\\\\\n\\s+https://github\\.com/\\S+ \\\\\\n\\s+[0-9a-f]{64} \\S+ ;;`));
  }
  assert.match(source, /sha256sum --check/);
  assert.match(source, /systemctl --no-block restart one-kvm/);
});

test('verifies selected extensions inside a build root without restarting One-KVM', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'one-kvm-extensions-'));
  try {
    const result = spawnSync('bash', [script, '--verify-root', root, 'frpc'], { encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.stderr, /systemctl/);

    const source = fs.readFileSync(script, 'utf8');
    assert.match(source, /ONE_KVM_EXTENSIONS_ROOT/);
    assert.match(source, /--verify-root/);
    assert.match(source, /read -r path url sha member <<<"\$\(spec "\$name"\)"/);
    assert.match(source, /sha256sum --check/);

    fs.mkdirSync(path.join(root, 'usr/bin'), { recursive: true });
    fs.writeFileSync(path.join(root, 'usr/bin/frpc'), 'wrong');
    fs.chmodSync(path.join(root, 'usr/bin/frpc'), 0o755);
    const wrongDigest = spawnSync('bash', [script, '--verify-root', root, 'frpc'], { encoding: 'utf8' });
    assert.notEqual(wrongDigest.status, 0);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
