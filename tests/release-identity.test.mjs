import test from 'node:test';
import assert from 'node:assert/strict';

import { formatReleaseIdentity } from '../scripts/lib/release-identity.mjs';

test('formats a short sortable WS1608 One-KVM identity', () => {
  const identity = formatReleaseIdentity({
    version: '0.2.4',
    upstreamTag: 'v260709',
    buildTime: '143015',
  });

  assert.deepEqual(identity, {
    safeUpstreamTag: 'v260709',
    buildTag: 'ws1608-one-kvm-0.2.4-v260709-143015',
    imageStem: 'One-KVM_0.2.4_v260709_143015_Onecloud_trixie_6.12.28_HDMI-test',
    imageName: 'One-KVM_0.2.4_v260709_143015_Onecloud_trixie_6.12.28_HDMI-test.burn.img',
  });
});

test('rejects ambiguous or unsafe identity components', () => {
  assert.throws(() => formatReleaseIdentity({}), /version/);
  assert.throws(
    () => formatReleaseIdentity({
      version: '0.2.4',
      upstreamTag: 'v260709',
      buildTime: '1430',
    }),
    /build time/,
  );
  assert.throws(
    () => formatReleaseIdentity({
      version: '0.2.4',
      upstreamTag: 'v260709',
      buildTime: '250000',
    }),
    /build time/,
  );
  assert.throws(
    () => formatReleaseIdentity({
      version: '0.2.4',
      upstreamTag: 'bad tag',
      buildTime: '143015',
    }),
    /upstream tag/,
  );
  assert.throws(
    () => formatReleaseIdentity({
      version: '0.2.4;rm',
      upstreamTag: 'v260709',
      buildTime: '143015',
    }),
    /version/,
  );
});
