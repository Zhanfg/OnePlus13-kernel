#!/bin/bash
# Pack AK3: replace Image in 144 template, update kernel.string, repack
set -e

TEMPLATE="/mnt/d/OnePlus13-kernel/releases/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip"
IMAGE="/home/axymorrsen/op13-oki/kernel_platform/out/msm-kernel-sun-perf/dist/Image"
RELEASES="/mnt/d/OnePlus13-kernel/releases"

STAMP=$(date +%Y%m%d_%H%M)
ZIP_NAME="v6.6.118-OnePlus13-sun-AK3-OKI-VANILLA-${STAMP}.zip"

WORKDIR=$(mktemp -d)
echo "Workdir: $WORKDIR"

# Extract template
unzip -o "$TEMPLATE" -d "$WORKDIR" > /dev/null

# Replace Image
cp "$IMAGE" "$WORKDIR/Image"

# Update kernel.string
sed -i 's|kernel.string=.*|kernel.string=OnePlus13 (PJZ110/sun) Vanilla OKI 6.6.118 - OnePlusOSS official tree|' "$WORKDIR/anykernel.sh"

# Repack
cd "$WORKDIR"
zip -r "$ZIP_NAME" . -x '.*' > /dev/null
ls -lh "$ZIP_NAME"
cp "$ZIP_NAME" "$RELEASES/"

echo "---"
echo "SHA256:"
sha256sum "$RELEASES/$ZIP_NAME"
echo "---"
echo "ZIP: $RELEASES/$ZIP_NAME"

# Verify
echo "---"
echo "Verifying Image version:"
unzip -p "$RELEASES/$ZIP_NAME" Image | strings | grep -m1 'Linux version'
echo "Verifying kernel.string:"
unzip -p "$RELEASES/$ZIP_NAME" anykernel.sh | grep 'kernel.string'

# Cleanup
rm -rf "$WORKDIR"
echo "Done!"
