# M8 Encoder Redistribution Status

Source lock: `khadas/libencoder` commit `bfee62dad4f7ebb6d1705df8522da871dcad861e`.

The repository root and `amvenc_264/bjunion_enc` do not contain the `LICENSE`
file referenced by several source headers. Other headers prohibit
redistribution without Amlogic permission, while `Android.mk` mixes
`SPDX-license-identifier-Apache-2.0`, `legacy_proprietary`, and
`proprietary by_exception_only`. A complete grant was not found.

| Output | Classification | Release policy |
| --- | --- | --- |
| Patch files and build metadata authored here | source-only | May be reviewed as source. |
| `libvpcodec.so` | local-test-only | Must not be attached to a public Release. |
| `amlenc-m8-diag` | local-test-only | Linked use of the vendor ABI; must not be attached to a public Release. |

The experimental packaging step must reject every artifact whose manifest
contains `"redistribution":"local-test-only"`. This classification may change
only after the missing license and redistribution authorization are verified.
