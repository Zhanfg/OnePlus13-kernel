# OnePlus 13 KSU + SUSFS: AK3 release gate (2026-10-14)

Status: packaging integration and host-side regression are complete. A **newly compiled and verified KSU+SUSFS kernel Image is not yet available**, so **no current Fusion V2 flashable AK3 artifact exists**.

## How the package is produced

- Launch workflow on main: https://github.com/Zhanfg/OnePlus13-kernel/actions/workflows/build-op13-fusion-ak3.yml
- Source workflow on integration branch: .github/workflows/fusion-v2-self-hosted.yml
- Pinned source configuration: configs/fusion_v2_sources.lock, configs/oneplus_13_16.0.9.401.lock
- Execution path: complete OKI sync, ReSukiSU+SUSFS integration, kernel build, KPatch-Next post-build patch, strict Image checks, verified AnyKernel3 packaging
- Output after successful job: experimental AK3 ZIP, .zip.sha256, raw and patched Image, source manifest, .config and build log in GitHub Actions artifacts.

## Required runner

Full official OnePlus OKI requires Linux x86_64 self-hosted runner labeled self-hosted/linux/x64/op13-oki; 80 GiB of free storage minimum, 150 GiB recommended. Standard GitHub-hosted preflight cannot satisfy this. Host-only tests cannot generate a valid kernel Image.

## Verified AK3 safety measures

1. The old verified-reference AK3 template had do.devicecheck=0 and blank device names. Every newly packed ZIP now enforces sun/PJZ110 and revalidates its final properties.
2. Only a real Image.kpatch-next with a matching raw Image, KPatch metadata, independent IKCONFIG verification and source provenance passes packaging.
3. Installer must be block=boot and Image-only. Partition payloads for vendor_boot, dtbo, init_boot and vbmeta are forbidden.
4. ZIP traversal, duplicated entries, symlinks, bad CRC, missing updater components and payload hash mismatches fail closed.
5. Status remains EXPERIMENTAL. Official OSS source is from 16.0.9.401; current device Android 17 .103 vendor ABI/KMI, boot stability, SELinux and rollback are unverified. Do not flash this candidate on Android 17 .103 until actual testing.

## Known security gaps before stable release

- Current ReSukiSU source is pinned to 2026-09-05. The newer manager APK-signature parser and SELinux compatibility fixes need independent review.
- Current SUSFS source is pinned to 2026-08-29 v2.3.0. Later KSTAT, VFS lifecycle and mount-race fixes in our SUSFS fork need independent review.
- The package build does not automatically resolve these source vulnerabilities. KPatch-Next is optional post-build Image patching, not a second Root core.

Host AK3 safety CI: https://github.com/Zhanfg/OnePlus13-kernel/actions/runs/38541725296
Integrated via PR #18: https://github.com/Zhanfg/OnePlus13-kernel/pull/18
