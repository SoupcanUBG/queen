#!/bin/bash
set -e

DISK="/dev/nvme0n1p4"
MNT="/mnt"
EFI="/dev/nvme0n1p1"
HOST="archgame"
USER="toby"

# Format and mount
mkfs.btrfs -f $DISK
mount $DISK $MNT
btrfs subvolume create $MNT/@
btrfs subvolume create $MNT/@home
umount $MNT

mount -o noatime,compress=zstd,subvol=@ $DISK $MNT
mkdir -p $MNT/{boot/efi,home}
mount -o noatime,compress=zstd,subvol=@home $DISK $MNT/home
mount $EFI $MNT/boot/efi

# Install system
pacstrap -K $MNT base base-devel linux linux-firmware btrfs-progs grub efibootmgr sudo networkmanager \
  xorg xorg-xinit xfce4 xfce4-goodies firefox xbindkeys steam heroic-games-launcher-bin \
  wine wine-mono wine-gecko lib32-mesa lib32-nvidia-utils xboxdrv git

# Generate fstab
genfstab -U $MNT >> $MNT/etc/fstab

# Chroot and configure system
arch-chroot $MNT /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc
echo "$HOST" > /etc/hostname
sed -i 's/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf

useradd -m -G wheel $USER
echo "$USER:password" | chpasswd
echo "root:root" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
EOF

# User desktop setup
cat > $MNT/home/$USER/.bash_profile <<EOP
[[ -z \$DISPLAY && \$(tty) == /dev/tty1 ]] && exec startx
EOP

cat > $MNT/home/$USER/.xinitrc <<EOT
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

echo "[✓] Setup complete. You can now reboot."
