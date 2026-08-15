# M8 Encoder Redistribution Status

Source lock: `khadas/libencoder` commit `bfee62dad4f7ebb6d1705df8522da871dcad861e`.

The repository root and `amvenc_264/bjunion_enc` do not contain the `LICENSE`
file referenced by several source headers. Other headers prohibit
redistribution without Amlogic permission, while `Android.mk` mixes
`SPDX-license-identifier-Apache-2.0`, `legacy_proprietary`, and
`proprietary by_exception_only`. A complete grant was not found.

| Output | Classification | Repository policy |
| --- | --- | --- |
| Patch files and build metadata authored here | source-only | May be reviewed as source. |
| `libvpcodec.so` | local-test-only | Classification is retained as provenance metadata. |
| `amlenc-m8-diag` | local-test-only | Classification is retained as provenance metadata. |

The repository owner has explicitly chosen not to use this classification as a
release gate. Experimental releases must still preserve the classification in
their manifests and must not claim that redistribution authorization was
verified.
