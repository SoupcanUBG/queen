#!/bin/bash
set -e

USER="toby"
HOME="/home/$USER"

echo "Starting Arch gaming setup for user $USER..."

# Update system
pacman -Syu --noconfirm

# Install base system and essentials
pacman -S --noconfirm base base-devel xfce4 xfce4-goodies xorg-server xorg-xinit networkmanager git wget \
    steam heroic-games-launcher-bin wine wine-mono wine-gecko lib32-mesa lib32-nvidia-utils \
    xboxdrv xbindkeys firefox

# Enable and start NetworkManager
systemctl enable NetworkManager
systemctl start NetworkManager

# Setup autologin on tty1
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $USER --noclear %I \$TERM
EOF
systemctl daemon-reexec

# Setup .bash_profile to start X on tty1 login
cat > $HOME/.bash_profile <<EOF
if [[ -z \$DISPLAY ]] && [[ \$(tty) == /dev/tty1 ]]; then
  startx
fi
EOF

# Setup .xinitrc to start XFCE panel, window manager and heroic launcher
cat > $HOME/.xinitrc <<EOF
#!/bin/sh
xfce4-panel &
xfwm4 &
xbindkeys &
heroic
EOF
chmod +x $HOME/.xinitrc

# Setup xbindkeys config for Meta+ shortcuts
cat > $HOME/.xbindkeysrc <<EOF
# Meta+b opens Firefox
"firefox"
  Mod4 + b

# Meta+a opens Assetto Corsa via Steam
"steam steam://rungameid/302550"
  Mod4 + a
EOF

# Clone gaming dotfiles (example repo)
if [ ! -d "$HOME/.dotfiles" ]; then
  git clone https://github.com/dracula/xfce.git $HOME/.dotfiles
  cd $HOME/.dotfiles
  # You can customize dotfiles installation here if needed
fi

# Fix permissions
chown -R $USER:$USER $HOME

# Final system update
pacman -Syu --noconfirm

echo "Setup complete! Reboot your system to start gaming."
