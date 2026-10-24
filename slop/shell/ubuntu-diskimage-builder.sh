#!/usr/bin/env bash
set -euo pipefail

### CONFIGURATION ###########################################################

RELEASE="noble"                         # Ubuntu release
MIRROR="http://archive.ubuntu.com/ubuntu"
WORKDIR="$HOME/ubuntu-build"
ROOTFS="$WORKDIR/rootfs"
IMG="$WORKDIR/ubuntu-custom.img"
IMG_SIZE_MB=4096                        # initial image size (will grow on first boot)

EFI_SIZE_MB=512                         # EFI partition size
ROOT_LABEL="rootfs"
EFI_LABEL="EFI"

###########################################################################
### STEP 0: PREPARE BUILD ENVIRONMENT #####################################
###########################################################################

mkdir -p "$WORKDIR"
sudo apt-get update
sudo apt-get install -y \
  debootstrap \
  gdisk \
  parted \
  dosfstools \
  rsync \
  grub-pc-bin grub-efi-amd64-bin \
  cloud-guest-utils \
  x11-apps synaptic

###########################################################################
### STEP 1: CREATE BASE SYSTEM WITH DEBOOTSTRAP ###########################
###########################################################################

if [ ! -d "$ROOTFS" ]; then
  echo "[*] Bootstrapping Ubuntu $RELEASE into $ROOTFS"
  sudo debootstrap --arch=amd64 "$RELEASE" "$ROOTFS" "$MIRROR"
fi

###########################################################################
### STEP 2: PREPARE CHROOT AND RUN SYNAPTIC ###############################
###########################################################################

echo "[*] Preparing chroot mounts"
for dir in dev proc sys run; do
  sudo mount --rbind "/$dir" "$ROOTFS/$dir"
  sudo mount --make-rslave "$ROOTFS/$dir"
done

sudo cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

# Basic config (hostname, locales, etc.) – adjust as needed
echo "[*] Basic configuration inside chroot"
sudo chroot "$ROOTFS" bash -c "
set -e
echo 'ubuntu-custom' > /etc/hostname
sed -i 's/^127.0.1.1.*/127.0.1.1 ubuntu-custom/' /etc/hosts || true
apt-get update
apt-get install -y locales sudo systemd-sysv linux-image-generic \
                   grub-efi-amd64 grub-pc cloud-guest-utils
dpkg-reconfigure locales
"

echo
echo "=================================================================="
echo "  Now customizing the system with Synaptic inside the chroot."
echo "  X11 must be available on the host (run from a graphical session)."
echo "=================================================================="
echo

# Allow local root to use X
xhost +local:root >/dev/null 2>&1 || true

sudo chroot "$ROOTFS" bash -c "
export DISPLAY=${DISPLAY:-:0}
export XAUTHORITY=/root/.Xauthority
apt-get install -y synaptic
synaptic
"

echo "[*] Synaptic customization finished (assuming you closed Synaptic)."

###########################################################################
### STEP 3: ADD FIRST-BOOT AUTO-RESIZE LOGIC ##############################
###########################################################################

echo "[*] Installing first-boot auto-resize service"

sudo chroot "$ROOTFS" bash -c '
set -e

cat >/usr/local/sbin/grow-rootfs.sh <<EOF
#!/bin/bash
set -euo pipefail

# Detect root device and partition
ROOT_DEV=\$(findmnt -no SOURCE /)
FSTYPE=\$(findmnt -no FSTYPE /)

# Expect something like /dev/sda2 or /dev/vda1
DISK=\$(echo "\$ROOT_DEV" | sed -E "s/[0-9]+$//")

echo "[grow-rootfs] Root device: \$ROOT_DEV, disk: \$DISK, fstype: \$FSTYPE"

# Grow partition (assumes root is last partition)
growpart "\$DISK" "\${ROOT_DEV##*[^0-9]}"

# Grow filesystem
case "\$FSTYPE" in
  ext4)
    resize2fs "\$ROOT_DEV"
    ;;
  xfs)
    xfs_growfs /
    ;;
  *)
    echo "[grow-rootfs] Unsupported filesystem \$FSTYPE, skipping."
    ;;
esac

# Disable this service after successful run
systemctl disable grow-rootfs.service || true
EOF

chmod +x /usr/local/sbin/grow-rootfs.sh

cat >/etc/systemd/system/grow-rootfs.service <<EOF
[Unit]
Description=Grow root partition and filesystem on first boot
After=local-fs.target
ConditionPathExists=/usr/local/sbin/grow-rootfs.sh

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/grow-rootfs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable grow-rootfs.service
'

###########################################################################
### STEP 4: CREATE RAW DISK IMAGE AND PARTITION IT ########################
###########################################################################

echo "[*] Creating raw disk image: $IMG (${IMG_SIZE_MB}MB)"
mkdir -p "$(dirname "$IMG")"
if [ ! -f "$IMG" ]; then
  dd if=/dev/zero of="$IMG" bs=1M count="$IMG_SIZE_MB"
fi

echo "[*] Attaching loop device"
LOOPDEV=$(sudo losetup --show -f "$IMG")
echo "    Loop device: $LOOPDEV"

echo "[*] Creating GPT partition table"
sudo parted -s "$LOOPDEV" mklabel gpt

# EFI partition
EFI_START_MB=1
EFI_END_MB=$((EFI_START_MB + EFI_SIZE_MB))
ROOT_START_MB=$EFI_END_MB
ROOT_END_MB=100%  # use rest of disk

sudo parted -s "$LOOPDEV" mkpart EFI fat32 "${EFI_START_MB}MiB" "${EFI_END_MB}MiB"
sudo parted -s "$LOOPDEV" set 1 esp on

sudo parted -s "$LOOPDEV" mkpart ROOT ext4 "${ROOT_START_MB}MiB" "${ROOT_END_MB}"

echo "[*] Refreshing partition table"
sudo partprobe "$LOOPDEV"

EFI_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"

echo "[*] Creating filesystems"
sudo mkfs.vfat -n "$EFI_LABEL" "$EFI_PART"
sudo mkfs.ext4 -L "$ROOT_LABEL" "$ROOT_PART"

###########################################################################
### STEP 5: INSTALL ROOTFS INTO IMAGE AND SETUP BOOT ######################
###########################################################################

MNT_ROOT="$WORKDIR/mnt-root"
MNT_EFI="$WORKDIR/mnt-efi"
mkdir -p "$MNT_ROOT" "$MNT_EFI"

echo "[*] Mounting image partitions"
sudo mount "$ROOT_PART" "$MNT_ROOT"
sudo mount "$EFI_PART" "$MNT_EFI"

echo "[*] Copying root filesystem into image"
sudo rsync -aHAX --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' \
  --exclude='/run/*' --exclude='/tmp/*' \
  "$ROOTFS/" "$MNT_ROOT/"

echo "[*] Creating fstab"
sudo bash -c "cat > '$MNT_ROOT/etc/fstab' <<EOF
# /etc/fstab
LABEL=$ROOT_LABEL  /        ext4  defaults  0 1
LABEL=$EFI_LABEL   /boot/efi vfat  umask=0077  0 1
EOF
"

echo "[*] Bind-mounting for grub installation"
for dir in dev proc sys run; do
  sudo mount --rbind "/$dir" "$MNT_ROOT/$dir"
  sudo mount --make-rslave "$MNT_ROOT/$dir"
done
sudo mount --bind "$MNT_EFI" "$MNT_ROOT/boot/efi"

echo "[*] Installing GRUB into image"
sudo chroot "$MNT_ROOT" bash -c "
set -e
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=UBUNTU-CUSTOM --recheck
grub-install --target=i386-pc --recheck $LOOPDEV
update-grub
"

echo "[*] Cleaning up mounts"
sudo umount -R "$MNT_ROOT" || true
sudo umount "$MNT_EFI" || true
sudo losetup -d "$LOOPDEV" || true

echo "[*] Cleaning chroot mounts"
for dir in dev proc sys run; do
  sudo umount -R "$ROOTFS/$dir" || true
done

echo
echo "=================================================================="
echo " DONE."
echo
echo " Image: $IMG"
echo " Flash it to a disk (e.g. with dd, Etcher, etc.)."
echo " On first boot, the root partition and filesystem will grow to"
echo " fill the target disk, thanks to grow-rootfs.service."
echo "=================================================================="
echo
