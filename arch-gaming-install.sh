#!/bin/bash
set -euo pipefail

DISK="/dev/nvme0n1"
FREE_PART_START=""
FREE_PART_END=""
USER="toby"
HOSTNAME="gaming"
MNT="/mnt"

fail() {
  echo "[ERROR] $1" >&2
  exit 1
}

echo "[1] Detecting free space on $DISK..."
# Using parted to find free space (start and end sectors)
FREE_START=$(parted -ms $DISK unit s print free | grep "free" | head -1 | cut -d: -f2 | sed 's/s//')
FREE_END=$(parted -ms $DISK unit s print free | grep "free" | head -1 | cut -d: -f3 | sed 's/s//')

if [[ -z "$FREE_START" || -z "$FREE_END" ]]; then
  fail "No free space detected on $DISK"
fi

echo "Free space detected from sector $FREE_START to $FREE_END"

echo "[2] Creating new partitions in free space..."

# Partition sizes in sectors (approx)
SECTOR_SIZE=512
EFI_SIZE_MB=600
BOOT_SIZE_MB=1024

EFI_SIZE_SECTORS=$(( (EFI_SIZE_MB * 1024 * 1024) / SECTOR_SIZE ))
BOOT_SIZE_SECTORS=$(( (BOOT_SIZE_MB * 1024 * 1024) / SECTOR_SIZE ))

EFI_START=$FREE_START
EFI_END=$(( EFI_START + EFI_SIZE_SECTORS - 1 ))

BOOT_START=$(( EFI_END + 1 ))
BOOT_END=$(( BOOT_START + BOOT_SIZE_SECTORS -1 ))

ROOT_START=$(( BOOT_END + 1 ))
ROOT_END=$FREE_END

# Create EFI partition
parted -s $DISK mkpart ESP fat32 "${EFI_START}s" "${EFI_END}s"
parted -s $DISK set 5 boot on
parted -s $DISK set 5 esp on

# Create boot partition
parted -s $DISK mkpart primary ext4 "${BOOT_START}s" "${BOOT_END}s"

# Create root partition
parted -s $DISK mkpart primary btrfs "${ROOT_START}s" "${ROOT_END}s"

# Refresh partition table
partprobe $DISK

EFI_PART="${DISK}p5"
BOOT_PART="${DISK}p6"
ROOT_PART="${DISK}p7"

echo "[3] Formatting partitions..."

mkfs.fat -F32 $EFI_PART || fail "EFI format failed"
mkfs.ext4 $BOOT_PART || fail "Boot format failed"
mkfs.btrfs -f $ROOT_PART || fail "Root format failed"

echo "[4] Creating Btrfs subvolumes..."
mount $ROOT_PART $MNT
btrfs subvolume create $MNT/@ || fail "Failed to create @ subvolume"
btrfs subvolume create $MNT/@home || fail "Failed to create @home subvolume"
umount $MNT

echo "[5] Mounting partitions..."
mount -o noatime,compress=zstd,subvol=@ $ROOT_PART $MNT
mkdir -p $MNT/{boot,home,boot/efi}
mount $BOOT_PART $MNT/boot
mount -o noatime,compress=zstd,subvol=@home $ROOT_PART $MNT/home
mount $EFI_PART $MNT/boot/efi

echo "[6] Installing base system..."
pacstrap -K $MNT base base-devel git sudo btrfs-progs grub efibootmgr networkmanager || fail "pacstrap failed"

echo "[7] Generating fstab..."
genfstab -U $MNT >> $MNT/etc/fstab || fail "fstab failed"

echo "[8] Configuring system inside chroot..."
arch-chroot $MNT /bin/bash <<EOF
set -euo pipefail

ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc
echo "$HOSTNAME" > /etc/hostname
sed -i 's/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo LANG=en_GB.UTF-8 > /etc/locale.conf

useradd -m -G wheel $USER
echo "$USER:password" | chpasswd
echo "root:root" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager

echo "[9] Installing yay from source..."
cd /opt
git clone https://aur.archlinux.org/yay-git.git
chown -R $USER:$USER yay-git
cd yay-git
sudo -u $USER makepkg -si --noconfirm

echo "[10] Installing gaming packages..."
sudo -u $USER yay -S --noconfirm --builddir /home/$USER/.builddir \\
  xorg xorg-xinit xfce4 xfce4-goodies firefox xbindkeys \\
  heroic-games-launcher-git steam protonup-qt wine-staging winetricks \\
  lib32-mesa lib32-nvidia-utils dxvk-bin vkd3 gamemode pipewire pulseaudio-alsa \\
  xboxdrv

echo "[11] Setting up autologin desktop config..."
echo '[[ -z \\$DISPLAY && \$(tty) == /dev/tty1 ]] && exec startx' > /home/$USER/.bash_profile

cat > /home/$USER/.xinitrc <<EOT
xfce4-panel &
xfwm4 &
xbindkeys &
heroic
EOT

chmod +x /home/$USER/.xinitrc

cat > /home/$USER/.xbindkeysrc <<EOB
"firefox"
  Mod4 + b

"steam steam://rungameid/302550"
  Mod4 + a
EOB

chown -R $USER:$USER /home/$USER

EOF

echo "[✓] Installation complete. Rebooting in 5 seconds..."
sleep 5
reboot
