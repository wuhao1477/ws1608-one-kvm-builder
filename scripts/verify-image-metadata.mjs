import fs from 'node:fs';

import { assertImageMetadata } from './lib/image-metadata.mjs';

const inputPath = process.argv[2];
if (!inputPath) throw new Error('metadata input path is required');

assertImageMetadata(fs.readFileSync(inputPath, 'utf8'), {
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

process.stdout.write(`verified image metadata: ${inputPath}\n`);
