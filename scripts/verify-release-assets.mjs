import { validateReleaseAssets } from './lib/release-metadata.mjs';

function env(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

const outputDir = process.argv[2];
if (!outputDir) throw new Error('output directory is required');
const imageName = env('IMAGE_NAME');
const validationReportName = process.env.VALIDATION_REPORT_NAME ?? 'validation-report.json';

await validateReleaseAssets({
  outputDir,
  expected: {
    board: env('BASE_BOARD'),
    base: env('BASE_ID'),
    kernel: env('BASE_KERNEL'),
    one_kvm_version: env('ONE_KVM_VERSION'),
    one_kvm_release: env('UPSTREAM_TAG'),
    package_url: env('PACKAGE_URL'),
    package_sha256: env('PACKAGE_DIGEST'),
    base_sha256: env('BASE_IMAGE_SHA256'),
    build_tag: env('BUILD_TAG'),
    build_number: Number(env('BUILD_NUMBER')),
    builder_commit: env('BUILDER_COMMIT'),
    github_run_id: env('GITHUB_RUN_ID'),
    image: imageName,
    compressed_image: `${imageName}.xz`,
    validation_report: validationReportName,
  },
});

process.stdout.write(`Verified release assets in ${outputDir}\n`);
