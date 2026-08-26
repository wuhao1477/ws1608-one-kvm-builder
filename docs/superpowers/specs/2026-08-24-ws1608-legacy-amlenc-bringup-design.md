# WS1608 Legacy AMLENC Bring-up Design

**Date:** 2026-08-24

**Status:** Approved for implementation planning

## Goal

Restore the Meson8b/S805 vendor H.264 encoder stack on WS1608, prove
`1280x720@30` NV12 to Annex-B H.264 encoding, and then connect it to One-KVM
Rust. A temporary dual-kernel image provides recovery while there is no serial
console. The final experimental release contains only the validated 3.10.107
kernel.

## Current Evidence

- The verified recovery image boots Armbian Trixie with
  `6.12.28-current-meson`, HDMI, Ethernet, SSH and One-KVM
  `0.2.6+ws1608amlenc.run-36-1`.
- The live One-KVM API lists only software encoders. `h264_amlenc` is absent
  because Linux 6.12 has no Meson8b encoder driver.
- The earlier 3.10.107 candidate reached U-Boot but did not provide HDMI or
  Ethernet. It adapted `meson8b_odroidc.dts` instead of using the measured
  OneCloud power and pin configuration.
- The boot addresses used by that candidate (`0x20800000` for `uImage` and
  `0x21800000` for DTB) match the verified OneCloud Armbian boot script. They
  are not the leading failure hypothesis.

## Locked Sources

| Purpose | Source | Locked revision |
| --- | --- | --- |
| S805 encoder kernel and M8 microcode | [hardkernel/linux](https://github.com/hardkernel/linux/tree/odroidc-3.10.y) | `5aed95d35d252cafc75ce613a3a0052285662de2` |
| OneCloud bootloader behavior | [hzyitc/u-boot](https://github.com/hzyitc/u-boot/tree/onecloud) | `0038d741ed1c77a77570c3a6bf88fe6189c11733` |
| Measured OneCloud board wiring | [coolsnowwolf/lede OneCloud DTS](https://github.com/coolsnowwolf/lede/blob/f7fd86eaa58c29fed97da04ab219c74a835a9358/target/linux/amlogic/files/arch/arm/boot/dts/amlogic/meson8b-onecloud.dts) | `f7fd86eaa58c29fed97da04ab219c74a835a9358` |
| M8 userspace encoder | [khadas/libencoder](https://github.com/khadas/libencoder) | `bfee62dad4f7ebb6d1705df8522da871dcad861e` |
| One-KVM Rust | [mofeng-git/One-KVM](https://github.com/mofeng-git/One-KVM) | `v260802`, `a4073d64cb49a1404df49e7813b73dd9f78d0931` |

The current 6.12 recovery image and its bootloader, resource partition and
partition table remain immutable inputs. A new source revision requires a
separate source-lock change and a fresh hardware run.

## Findings That Change The Previous Design

### VCCK power control

The old experimental DTS retains the ODROID-C VCCK path:

- controller: `PWM_C`
- pin: `GPIODV_9`

The measured OneCloud DTS uses:

- controller: `PWM_D`
- pin: `GPIODV_28`
- range: `860000` to `1140000` microvolts

The vendor Meson8b pinmux maps PWM_D on `GPIODV_28` to mux register 3 bit 26.
Leaving the ODROID-C path can make the kernel fail when cpufreq changes the
core voltage.

### Encoder memory

The 3.10.107 ODROID-C defconfig enables CMA but allocates only 8 MiB. The M8
encoder opens with the 1080p buffer class even for a 720p session and requires
approximately 18 MiB.

The vendor reserved-memory path also contains this defect in `encoder.c`:

```c
reserve_buff[i].buf_size = encode_manager.reserve_mem.buf_start;
```

Userspace calls `AMVENC_AVC_IOC_GET_BUFFINFO` and uses the returned value as
the `mmap()` length. Returning a physical address instead of a size is unsafe.

The first hardware candidate therefore uses global CMA instead of binding an
encoder-specific contiguous-region:

- `CONFIG_CMA=y`
- `CONFIG_CMA_SIZE_MBYTES=64`
- `CONFIG_CMA_SIZE_SEL_MBYTES=y`
- the `amvenc_avc` node is enabled without `linux,contiguous-region`

The vendor assignment is corrected as a defensive source fix even though the
initial candidate does not use that path.

### USB Gadget support

The 3.10 tree already contains `libcomposite`, `f_hid`, `f_mass_storage`,
`g_hid`, `g_mass_storage` and a ConfigFS gadget core. The ConfigFS core is not
linked, and the HID/mass-storage functions do not implement the newer
`usb_function_instance` interface expected by ConfigFS.

For the final One-KVM image, the preferred implementation is a fixed composite
gadget containing keyboard HID, mouse HID and mass storage. This reuses the
existing 3.10 function drivers and avoids a full ConfigFS function backport.
ConfigFS backporting is not part of the first bring-up.

## Architecture

### Protected recovery path

The DDR/U-Boot USB items, OneCloud bootloader, resource partition, burn
package structure, and stable 6.12 kernel/initrd/DTB are copied unchanged from
`base-20260804-consolefix`.

The current stable workflow, `config/base.env`, stable tags and stable Releases
are not modified.

### Temporary dual-kernel candidate

The boot FAT contains the verified 6.12 `uImage`, `uInitrd` and DTB, the
experimental 3.10.107 `uImage` and DTB, plus one revisioned `boot.scr` state
machine and `armbianEnv.txt`.

Both kernels boot one Debian Bullseye armhf SysV rootfs. The rootfs contains
both module trees and the firmware required by the recovery kernel. The first
candidate does not install or start One-KVM.

### Boot state machine

Each candidate has an immutable `build_revision`. The U-Boot environment flag
is namespaced by that revision so stale state from an older image cannot skip a
new test.

```text
if nonempty /amlenc-force-recovery exists:
    boot recovery Linux 6.12.28
else if nonempty /amlenc-3.10.ok exists:
    boot Linux 3.10.107
else if amlenc_trial_revision equals this build_revision:
    boot recovery Linux 6.12.28
else:
    set amlenc_trial_revision to this build_revision
    saveenv; on save failure boot recovery
    boot Linux 3.10.107
```

Every new candidate ships with `/amlenc-force-recovery`. After the recovery
kernel has DHCP and SSH, the operator runs
`/usr/local/sbin/ws1608-amlenc-arm-trial`; it verifies recovery health and
writes an armed marker without removing the recovery marker. On the next cold
boot U-Boot checks that marker, stores this candidate's `amlenc_trial_revision`
with `saveenv`, and boots 3.10 only when that save succeeds. A repeated boot
with the same revision, or a save failure, selects recovery instead.
The 3.10 `uInitrd.amlenc` keeps the marker available before mounting the rootfs.
The SysV `firstboot` helper removes it only after a 3.10 userspace boot has
created host keys, validated `sshd` and started the service.

The marker remains in the FAT filesystem for an early failure. Because U-Boot
cannot delete FAT files, the saved revision is the one-shot consumption guard:
after a failed 3.10 boot, the next cold boot sees the same revision and enters
recovery. A failure before U-Boot can save the revision remains an unverified
hardware risk and requires a power cycle or USB reflash.

The recovery rootfs does not install `kexec-tools`. A controlled test on
2026-08-27 loaded the same 6.12 recovery kernel through kexec and lost both
HDMI progress and SSH; the 3.10 target behaved identically. This proves that
the recovery kernel cannot replace the SoC cold-start sequence on WS1608, so
kexec is prohibited for this bring-up.

The 3.10 kernel uses `panic=10`; after the initramfs guard has run, a panic
reboot selects recovery. If it hangs before the guard, a power cycle or USB
reflash is required.

The success marker is not written automatically. After DHCP, SSH, eMMC and
60-second stability checks pass, the operator runs:

```sh
/usr/local/sbin/ws1608-amlenc-mark-success
```

That helper verifies the expected 3.10.107 build, IPv4, sshd and writable
eMMC, then syncs and writes a nonempty marker to the boot FAT. A partial boot
cannot make 3.10 permanent.

### Rootfs and access

- Debian Bullseye armhf with SysV, udev, kmod, ifupdown, DHCP and OpenSSH
- root password uses SHA-512 rather than yescrypt because yescrypt verification
  is too slow on the S805
- the fixed 1,400,897,536-byte rootfs prunes legacy Wi-Fi backports and
  unrelated SoC firmware; WS1608 Ethernet, eMMC, HDMI and USB inputs remain
- PR builds use a CI-only key with no retained private key and are not flashable

The manual workflow accepts a base64 public key and records only its SHA-256.

## Board Adaptation

The 3.10 DT must retain the vendor multimedia nodes but take physical board
facts from the measured OneCloud DTS and OneCloud U-Boot:

- VCCK on PWM_D/GPIODV_28
- CPU voltage range 860 to 1140 mV
- Ethernet RGMII and PHY reset on GPIOH_4
- 80 ms PHY reset delay
- 8-bit eMMC on BOOT pins with reset on BOOT_9
- SD card detect on CARD_6
- USB0 as OTG/device-capable and USB1 as host
- HDMI HPD/SDA/SCL on GPIOH_0/1/2
- red/green/blue LEDs on GPIOAO_2/3/4
- reset button on GPIOAO_5
- one enabled `amvenc_avc` instance

The old ODROID touchscreen, DAC, GPIO header, fan/PWM and board LED nodes are
removed. The vendor memory model is retained; the modern mainline
`memory@0x40000000` representation is not copied into the 3.10 DT.

## Bring-up Stages

### Stage A: Hosted build gates

GitHub Actions verifies the ARM kernel identity, corrected OneCloud DT,
PWM_D/VCCK path, CMA policy, encoder microcode, both boot paths, Bullseye
ext4, both module trees, SSH-key digest, Amlogic CRC and partition VERIFY
values. The boot state machine is tested with revision-isolated fixtures.

Hosted CI leaves all hardware status fields false.

### Stage B: Boot and network

The first flashable candidate passes only when all of these are observed:

- U-Boot HDMI output
- forced recovery boots 6.12 with DHCP, SSH and writable eMMC
- `ws1608-amlenc-arm-trial` enables exactly one 3.10 attempt
- 3.10 provides HDMI console or a documented HDMI-only limitation
- 3.10 provides DHCP, SSH, expected `uname -r` and writable eMMC
- no reboot for 60 seconds under 3.10
- manual success marker creation
- cold reboot returns to 3.10

If Stage B fails, One-KVM and hardware encoder probing remain disabled.

### Stage C: Encoder device ABI

Read-only checks require:

- `/dev/amvenc_avc` exists
- driver reports `AML-M8`
- CMA reports at least one 18 MiB allocation
- `GET_BUFFINFO` returns a bounded size
- mapping and unmapping one buffer succeeds
- no kernel warning, oops or CMA failure

### Stage D: Independent H.264 encoding

The standalone diagnostic runs 640x480@30 for 300 frames, then 1280x720@30
for 300 frames, then 1280x720@30 for 1800 frames.

Every stream must contain SPS, PPS and IDR units, decode with FFmpeg without
errors, match the exact frame count and resolution, and produce no encoder
timeout or kernel fault.

### Stage E: One-KVM integration

Only after Stage D passes:

- install the patched One-KVM armhf package
- enable AMLENC registration with an explicit hardware gate
- require `/api/stream/codecs` to list H.264 AMLENC as hardware
- verify software H.264 remains available as fallback
- verify WebRTC streaming from an attached capture device

### Stage F: USB Gadget

Add the fixed composite gadget and verify:

- keyboard HID
- mouse HID
- mass-storage backing file
- USB disconnect/reconnect
- simultaneous H.264 streaming and HID activity

### Stage G: Final single-kernel image

After repeated cold boot, reboot, 720p30 encoding, One-KVM and USB tests pass:

- remove recovery kernel files
- remove trial state-machine logic and success marker helper
- keep only Linux 3.10.107 and its DTB/modules
- publish under an immutable experimental prerelease tag

The 6.12 stable image remains a separate recovery download and is not changed.

## Failure Handling

- U-Boot environment save failure boots recovery immediately.
- A 3.10 panic reboots after 10 seconds; a hang requires a power cycle. Both
  paths select recovery next.
- DHCP or SSH failure leaves the success marker absent, so recovery is next.
- Encoder probe or CMA failure: keep the device online and stop before mmap.
- Encoder timeout or malformed H.264: stop One-KVM integration and retain all
  evidence privately.
- Recovery kernel failure on Bullseye rootfs: reject the dual-kernel image in
  hardware testing and reflash the existing stable image.

## Security And Evidence

- Root password login is enabled for this candidate with the fixed password
  `ws1608`; it is not a stable-release credential.
- No private SSH key is uploaded to GitHub Actions or included in an artifact.
- LAN addresses, device identifiers and raw logs are not committed.
- Public artifacts contain hashes and status summaries only.
- Hardware pass fields can be changed only from a manually reviewed evidence
  record after physical testing.

## Out Of Scope

H.265, 1080p claims, a complete ConfigFS backport, direct 6.12 AMLENC porting,
stable-path replacement, and promotion before physical validation are out of
scope.

## Assumptions

- The board is a 1 GiB WS1608/Thunder OneCloud variant supported by the
  measured OneCloud U-Boot and DTS.
- The current OneCloud bootloader remains functional after burn packaging.
- The operator can reflash the verified 6.12 image if both boot paths fail.
- The operator supplies an SSH public key for every physical candidate.
- The first objective is reliable boot and Ethernet, not immediate One-KVM
  availability.
