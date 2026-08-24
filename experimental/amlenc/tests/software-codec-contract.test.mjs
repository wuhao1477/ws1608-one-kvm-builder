import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const patchPath = 'experimental/amlenc/patches/one-kvm/0003-software-codec-self-check.patch';
const packageBuildPath = 'experimental/amlenc/scripts/build-one-kvm.sh';
const packageVerifyPath = 'experimental/amlenc/scripts/verify-one-kvm.sh';
const metadataVerifyPath = 'experimental/amlenc/scripts/verify-one-kvm-metadata.mjs';
const runtimeVerifyPath = 'experimental/amlenc/scripts/verify-one-kvm-software-codecs.sh';
const workflowPath = '.github/workflows/amlenc-experimental.yml';

function readRequired(filePath) {
  assert.equal(fs.existsSync(filePath), true, `${filePath} must exist`);
  return fs.readFileSync(filePath, 'utf8');
}

test('adds a truthful four-codec software self-check command', () => {
  const patch = readRequired(patchPath);

  for (const token of [
    'ffmpeg_ram_has_encoder',
    'pub fn has_encoder(name: &str) -> bool',
    'CodecSelfCheckBackend',
    'Software',
    'run_codec_self_check',
    'CliCommand::Codec',
    'CodecAction::SelfCheck',
    'backend: CodecSelfCheckBackend',
    'SOFTWARE_SELF_CHECK_WIDTH: u32 = 320',
    'SOFTWARE_SELF_CHECK_HEIGHT: u32 = 240',
    'SOFTWARE_SELF_CHECK_FRAME_COUNT: u32 = 10',
    'libx264',
    'libx265',
    'libvpx_vp8',
    'libvpx_vp9',
    'h264',
    'hevc',
    'vp8',
    'vp9',
    'decoded_frames',
    'submitted_frames',
  ]) assert.match(patch, new RegExp(token.replaceAll(/[.*+?^${}()|[\]\\]/g, '\\$&')));

  assert.match(patch, /avcodec_find_encoder_by_name/);
  assert.match(patch, /Decoder::new/);
  assert.match(patch, /\.decode\(&packet\.data\)/);
  assert.match(patch, /all\(\|cell\| cell\.ok\)/);
  assert.match(patch, /serde_json::to_string/);
  assert.doesNotMatch(patch, /Meson8bS805\s*=>\s*codec\s*==\s*AmlencCodec::H265/);
});

test('requires armhf runtime verification before experimental burn assembly', () => {
  const build = readRequired(packageBuildPath);
  const verify = readRequired(packageVerifyPath);
  const metadata = readRequired(metadataVerifyPath);
  const runtime = readRequired(runtimeVerifyPath);
  const workflow = readRequired(workflowPath);

  for (const source of [build, verify, metadata]) assert.match(source, /software_codecs/);
  for (const codec of ['h264', 'h265', 'vp8', 'vp9']) assert.match(runtime, new RegExp(codec));
  assert.match(runtime, /--platform linux\/arm\/v7/);
  assert.match(runtime, /one-kvm codec self-check --backend software --json/);
  assert.match(runtime, /submitted_frames == 10/);
  assert.match(runtime, /decoded_frames == 10/);
  const packageVerify = workflow.indexOf('Verify One-KVM armhf package');
  const runtimeVerify = workflow.indexOf('Verify armhf software codecs');
  const imageIdentity = workflow.indexOf('Prepare experimental image identity');
  assert.ok(packageVerify >= 0 && runtimeVerify > packageVerify && imageIdentity > runtimeVerify);
});
