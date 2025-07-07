#!/bin/bash
set -e

# ---- USER CONFIG ----
DISK="/dev/nvme0n1p4"   # ONLY THIS PARTITION WILL BE USED
MNT="/mnt"
EFI="/dev/nvme0n1p1"
HOST="archgame"
USER="toby"

# ---- FORMAT AND MOUNT ----
echo "[1] Formatting $DISK with Btrfs..."
mkfs.btrfs -f $DISK
mount $DISK $MNT
btrfs subvolume create $MNT/@
btrfs subvolume create $MNT/@home
umount $MNT

echo "[2] Mounting subvolumes..."
mount -o noatime,compress=zstd,subvol=@ $DISK $MNT
mkdir -p $MNT/{boot/efi,home}
mount -o noatime,compress=zstd,subvol=@home $DISK $MNT/home

echo "[3] Mounting EFI system partition..."
mount $EFI $MNT/boot/efi

# ---- INSTALL BASE SYSTEM ----
echo "[4] Installing Arch system..."
pacstrap -K $MNT base base-devel linux linux-firmware btrfs-progs grub efibootmgr sudo networkmanager \
    xorg xorg-xinit xfce4 xfce4-goodies firefox xbindkeys steam heroic-games-launcher-bin \
    wine wine-mono wine-gecko lib32-mesa lib32-nvidia-utils xboxdrv git

# ---- FSTAB + CHROOT CONFIG ----
genfstab -U $MNT >> $MNT/etc/fstab

arch-chroot $MNT /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc
echo "$HOST" > /etc/hostname
sed -i 's/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf

echo "[5] Setting up users and sudo..."
useradd -m -G wheel $USER
echo "$USER:password" | chpasswd
echo "root:root" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

echo "[6] Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
EOF

# ---- USER CONFIG ----
echo "[7] Creating user desktop config..."
cat > $MNT/home/$USER/.bash_profile <<EOP
if [[ -z \$DISPLAY ]] && [[ \$(tty) == /dev/tty1 ]]; then
  startx
fi
EOP

cat > $MNT/home/$USER/.xinitrc <<EOT
#!/bin/sh
xfce4-panel &
xfwm4 &
xbindkeys &
heroic
EOT

cat > $MNT/home/$USER/.xbindkeysrc <<EOS
"firefox"
  Mod4 + b

"steam steam://rungameid/302550"
  Mod4 + a
EOS

arch-chroot $MNT /bin/bash <<EOF
chown -R $USER:$USER /home/$USER
EOF

echo "[8] Setup complete. You can now reboot!"
