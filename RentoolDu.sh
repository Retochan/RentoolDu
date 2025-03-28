#!/bin/bash

# RentooDu - Gentoo Installation Utility
# Part of the Duck-1Go Project
# This script automates Gentoo installation with strict user-defined options.
# Run from a Gentoo LiveCD as root.

# Functions for output
log() { echo "[INFO] $1"; }
error() { echo "[ERROR] $1"; exit 1; }
warn() { echo "[WARNING] $1"; }

# Root check
[ "$EUID" -ne 0 ] && error "This script must be run as root."

# Introduction
log "RentooDu - Gentoo Installation Utility (Duck-1Go Project)"
log "Starting Gentoo installation process..."

# Step 1: Disk selection and partitioning
log "Select disk for partitioning:"
lsblk
read -p "Enter disk name (e.g., /dev/sda): " DISK
[ ! -b "$DISK" ] && error "Invalid disk specified. Check lsblk output."

read -p "Partition manually (custom) or use a template? (c/t): " PARTITION_MODE
if [ "$PARTITION_MODE" == "c" ]; then
    log "Launching fdisk for manual partitioning."
    fdisk "$DISK"
    log "Manually configure mount points after partitioning if needed."
else
    read -p "UEFI or BIOS? (u/b): " BOOT_TYPE
    read -p "Specify partition size in GiB (e.g., 50, or 'all' for full disk): " DISK_SIZE
    log "Select partitioning template:"
    if [ "$BOOT_TYPE" == "u" ]; then
        echo "1) Full UEFI: /efi, /boot, /, /home, /var, /tmp"
        echo "2) Minimal UEFI: /efi, /"
        echo "3) Medium UEFI: /efi, /, /home"
    else
        echo "1) Full BIOS: /boot, /, /home, /var, /tmp"
        echo "2) Minimal BIOS: /"
        echo "3) Medium BIOS: /boot, /, /home"
    fi
    read -p "Template number: " TEMPLATE

    # Partitioning based on template
    if [ "$BOOT_TYPE" == "u" ] && [ "$TEMPLATE" == "1" ]; then
        fdisk "$DISK" <<EOF
g
n
1

+512M
t
1
n
2

+1G
n
3

+20G
n
4

+20G
n
5

+5G
n
6

w
EOF
        mkfs.fat -F 32 ${DISK}1
        mkfs.ext4 ${DISK}2
        mkfs.ext4 ${DISK}3
        mkfs.ext4 ${DISK}4
        mkfs.ext4 ${DISK}5
        mkfs.ext4 ${DISK}6
        mount ${DISK}3 /mnt/gentoo
        mkdir -p /mnt/gentoo/{boot,home,var,tmp}
        mount ${DISK}1 /mnt/gentoo/boot/efi
        mount ${DISK}2 /mnt/gentoo/boot
        mount ${DISK}4 /mnt/gentoo/home
        mount ${DISK}5 /mnt/gentoo/var
        mount ${DISK}6 /mnt/gentoo/tmp
    elif [ "$BOOT_TYPE" == "b" ] && [ "$TEMPLATE" == "1" ]; then
        fdisk "$DISK" <<EOF
o
n
p
1

+1G
a
1
n
p
2

+20G
n
p
3

+20G
n
p

+5G
w
EOF
        mkfs.ext4 ${DISK}1
        mkfs.ext4 ${DISK}2
        mkfs.ext4 ${DISK}3
        mkfs.ext4 ${DISK}4
        mount ${DISK}2 /mnt/gentoo
        mkdir -p /mnt/gentoo/{boot,home,var,tmp}
        mount ${DISK}1 /mnt/gentoo/boot
        mount ${DISK}3 /mnt/gentoo/home
        mount ${DISK}4 /mnt/gentoo/var
    elif [ "$BOOT_TYPE" == "u" ] && [ "$TEMPLATE" == "2" ]; then
        fdisk "$DISK" <<EOF
g
n
1

+512M
t
1
n
2


w
EOF
        mkfs.fat -F 32 ${DISK}1
        mkfs.ext4 ${DISK}2
        mount ${DISK}2 /mnt/gentoo
        mkdir -p /mnt/gentoo/boot/efi
        mount ${DISK}1 /mnt/gentoo/boot/efi
    elif [ "$BOOT_TYPE" == "b" ] && [ "$TEMPLATE" == "2" ]; then
        fdisk "$DISK" <<EOF
o
n
p
1


w
EOF
        mkfs.ext4 ${DISK}1
        mount ${DISK}1 /mnt/gentoo
    elif [ "$BOOT_TYPE" == "u" ] && [ "$TEMPLATE" == "3" ]; then
        fdisk "$DISK" <<EOF
g
n
1

+512M
t
1
n
2

+20G
n
3


w
EOF
        mkfs.fat -F 32 ${DISK}1
        mkfs.ext4 ${DISK}2
        mkfs.ext4 ${DISK}3
        mount ${DISK}2 /mnt/gentoo
        mkdir -p /mnt/gentoo/{boot/efi,home}
        mount ${DISK}1 /mnt/gentoo/boot/efi
        mount ${DISK}3 /mnt/gentoo/home
    elif [ "$BOOT_TYPE" == "b" ] && [ "$TEMPLATE" == "3" ]; then
        fdisk "$DISK" <<EOF
o
n
p
1

+1G
a
1
n
p
2

+20G
n
p


w
EOF
        mkfs.ext4 ${DISK}1
        mkfs.ext4 ${DISK}2
        mkfs.ext4 ${DISK}3
        mount ${DISK}2 /mnt/gentoo
        mkdir -p /mnt/gentoo/{boot,home}
        mount ${DISK}1 /mnt/gentoo/boot
        mount ${DISK}3 /mnt/gentoo/home
    else
        error "Invalid template selection."
    fi
fi

# Step 2: Download stage3 and enter chroot
log "Downloading stage3 tarball..."
cd /mnt/gentoo
wget -q --show-progress "$(curl -s https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/ | grep -o 'stage3-amd64-.*\.tar\.xz' | head -n1 | awk '{print "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/"$1}')"
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

# Step 3: Configure system in chroot
log "Entering chroot environment..."
chroot /mnt/gentoo /bin/bash <<EOF
source /etc/profile
export PS1="(chroot) \$PS1"

# Select system profile
log "Select system profile:"
eselect profile list
read -p "Profile number: " PROFILE_NUM
eselect profile set \$PROFILE_NUM

# Configure Portage mirrors
log "Configuring Portage mirrors..."
echo "GENTOO_MIRRORS=\"https://distfiles.gentoo.org\"" >> /etc/portage/make.conf
echo "CFLAGS=\"-march=native -O2 -pipe\"" >> /etc/portage/make.conf
echo "CXXFLAGS=\"\${CFLAGS}\"" >> /etc/portage/make.conf
echo "MAKEOPTS=\"-j$(nproc)\"" >> /etc/portage/make.conf
emerge-webrsync

# Configure locales
log "Configuring locales..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
read -p "Add additional locale? (e.g., ru_RU.UTF-8): " EXTRA_LOCALE
[ -n "\$EXTRA_LOCALE" ] && echo "\$EXTRA_LOCALE UTF-8" >> /etc/locale.gen
locale-gen
eselect locale list
read -p "Select locale number: " LOCALE_NUM
eselect locale set \$LOCALE_NUM

# Configure keymaps
log "Configuring keymaps..."
echo "KEYMAP=\"us\"" > /etc/vconsole.conf
read -p "Add additional keymap? (e.g., ru): " EXTRA_KEYMAP
[ -n "\$EXTRA_KEYMAP" ] && echo "KEYMAP=\"us \$EXTRA_KEYMAP\"" > /etc/vconsole.conf

# Install kernel
log "Select kernel installation method:"
echo "1) Manual build (make menuconfig)"
echo "2) Binary kernel (gentoo-kernel-bin)"
echo "3) Genkernel (automated)"
read -p "Option number: " KERNEL_MODE
case \$KERNEL_MODE in
    1) emerge sys-kernel/gentoo-sources
       cd /usr/src/linux
       make menuconfig
       make && make modules_install && make install;;
    2) emerge sys-kernel/gentoo-kernel-bin;;
    3) emerge sys-kernel/genkernel gentoo-sources
       genkernel all;;
esac

# Install bootloader
log "Select bootloader:"
echo "1) GRUB" && echo "2) systemd-boot" && echo "3) None"
read -p "Option number: " BOOTLOADER
if [ "\$BOOTLOADER" == "1" ]; then
    emerge sys-boot/grub
    [ "$BOOT_TYPE" == "u" ] && grub-install --target=x86_64-efi --efi-directory=/boot/efi || grub-install $DISK
    grub-mkconfig -o /boot/grub/grub.cfg
elif [ "\$BOOTLOADER" == "2" ] && [ "$BOOT_TYPE" == "u" ]; then
    emerge sys-boot/systemd-boot
    bootctl install
fi

# Install desktop environment or window manager
log "Select desktop environment or window manager:"
echo "1) KDE Plasma" && echo "2) GNOME" && echo "3) Unity" && echo "4) Budgie"
echo "5) Sway" && echo "6) dwm" && echo "7) Hyprland" && echo "8) None"
read -p "Option number: " DE_WM
case \$DE_WM in
    1) echo "USE=\"X kde plasma qt5\"" >> /etc/portage/make.conf; emerge kde-plasma/plasma-meta;;
    2) echo "USE=\"X gnome\"" >> /etc/portage/make.conf; emerge gnome-base/gnome;;
    3) echo "USE=\"X unity\"" >> /etc/portage/make.conf; emerge unity-base/unity;;
    4) echo "USE=\"X budgie\"" >> /etc/portage/make.conf; emerge budgie-desktop/budgie-desktop;;
    5) echo "USE=\"X wayland sway\"" >> /etc/portage/make.conf; emerge gui-wm/sway;;
    6) echo "USE=\"X\"" >> /etc/portage/make.conf; emerge x11-wm/dwm;;
    7) echo "USE=\"X wayland\"" >> /etc/portage/make.conf; emerge gui-wm/hyprland;;
    8) log "No DE/WM selected.";;
esac
emerge x11-base/xorg-server

# Install display manager
log "Select display manager (skip for WM):"
echo "1) SDDM" && echo "2) LightDM" && echo "3) GDM" && echo "4) None"
read -p "Option number: " DM
case \$DM in
    1) emerge x11-misc/sddm; rc-update add sddm default;;
    2) emerge x11-misc/lightdm; rc-update add lightdm default;;
    3) emerge gnome-base/gdm; rc-update add gdm default;;
    4) log "No display manager selected.";;
esac

# Install additional packages
log "Installing base utilities..."
emerge app-editors/emacs www-client/firefox
read -p "Enter additional packages (space-separated, or leave blank): " EXTRA_PACKAGES
[ -n "\$EXTRA_PACKAGES" ] && emerge \$EXTRA_PACKAGES

# Final configuration
log "Configuring fstab and users..."
echo "root:toor" | chpasswd
read -p "Enter username: " USERNAME
useradd -m -G users,wheel,audio,video -s /bin/bash \$USERNAME
echo "\$USERNAME:toor" | chpasswd
log "Generating fstab..."
genfstab -U /mnt/gentoo >> /etc/fstab

log "Installation complete. Exiting chroot."
exit
EOF

# Step 4: Unmount and reboot
log "Unmounting filesystems and rebooting..."
cd
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
