import fs from 'node:fs';

import { createImageMetadata } from './lib/image-metadata.mjs';

const outputPath = process.argv[2];
if (!outputPath) throw new Error('metadata output path is required');

const metadata = createImageMetadata({
  schemaVersion: 1,
  board: process.env.BASE_BOARD,
  base: process.env.BASE_ID,
  kernel: process.env.BASE_KERNEL,
  oneKvmVersion: process.env.ONE_KVM_VERSION,
  upstreamTag: process.env.UPSTREAM_TAG,
  packageDigest: process.env.PACKAGE_DIGEST,
  buildTag: process.env.BUILD_TAG,
  buildNumber: Number(process.env.BUILD_NUMBER),
  builderCommit: process.env.BUILDER_COMMIT,
});

fs.writeFileSync(outputPath, metadata, 'utf8');
