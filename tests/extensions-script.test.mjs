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
    assert.match(source, /binary_sha/);
    assert.match(source, /sha256sum --check/);
    assert.match(source, /0308f2f32d885ed8414a220120a61dac717be2d666ba7314fee0bdd7a6dbdc90/);

    fs.mkdirSync(path.join(root, 'usr/bin'), { recursive: true });
    fs.writeFileSync(path.join(root, 'usr/bin/frpc'), 'wrong');
    fs.chmodSync(path.join(root, 'usr/bin/frpc'), 0o755);
    const wrongDigest = spawnSync('bash', [script, '--verify-root', root, 'frpc'], { encoding: 'utf8' });
    assert.notEqual(wrongDigest.status, 0);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('offers interactive extension and mirror selection before root validation', () => {
  const result = spawnSync('bash', [script], {
    input: '1\n2\n',
    encoding: 'utf8',
    env: { ...process.env, ONE_KVM_EXTENSIONS_INTERACTIVE: '1' },
  });

  assert.equal(result.status, 1);
  assert.match(result.stdout, /选择要安装的扩展/);
  assert.match(result.stdout, /选择下载源/);
  assert.match(result.stdout, /GitHub 镜像（ghfast\.top）/);
  assert.match(result.stdout, /GitHub 镜像（ghproxy\.net）/);
  assert.match(result.stdout, /自定义镜像前缀/);
  assert.match(result.stderr, /请用 root 运行/);
});

test('cancels interactive installation without requiring root', () => {
  const result = spawnSync('bash', [script], {
    input: '0\n',
    encoding: 'utf8',
    env: { ...process.env, ONE_KVM_EXTENSIONS_INTERACTIVE: '1' },
  });

  assert.equal(result.status, 0);
  assert.match(result.stdout, /已取消安装/);
  assert.equal(result.stderr, '');
});

test('supports mirror prefixes for non-interactive downloads', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'one-kvm-extensions-bin-'));
  const id = path.join(directory, 'id');
  const curl = path.join(directory, 'curl');
  const log = path.join(directory, 'curl.log');
  try {
    fs.writeFileSync(id, '#!/bin/sh\n[ "$1" = -u ] && { echo 0; exit; }\nexec /usr/bin/id "$@"\n');
    fs.chmodSync(id, 0o755);
    fs.writeFileSync(curl, '#!/bin/sh\nprintf "%s\\n" "$*" > "$CURL_LOG"\nexit 1\n');
    fs.chmodSync(curl, 0o755);
    const result = spawnSync('bash', [script, 'frpc'], {
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${directory}:/usr/bin:/bin`,
        CURL_LOG: log,
        MIRROR_PREFIX: 'https://mirror.example',
      },
    });

    assert.equal(result.status, 1);
    assert.match(fs.readFileSync(log, 'utf8'), /https:\/\/mirror\.example\/https:\/\/github\.com\/fatedier\/frp/);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
