#!/bin/bash

USERNAME=piotr
USERSHELL=/bin/fish
DISK_LABEL=ARCH
EDITOR=nvim

case $1 in
	prepare)
		[[ -d /sys/firmware/efi/efivars ]] && echo "UEFI mode" || echo "BIOS mode"
		[[ $(ping -c 1 archlinux.org) ]] || { echo "Network down. Use 'iwctl' to connect to WiFi."; exit 1; }
		echo -e "Network is ready\n"
		timedatectl set-ntp true
		timedatectl status
		echo -e "\n1. Use lsblk, gdisk and mkfs.ext4 to partition and format."
		echo "2. mount /dev/root_partition /mnt"
		;;
	install)
		reflector
		vim /etc/pacman.d/mirrorlist
		ucode=""
		if $(grep -q GenuineIntel /proc/cpuinfo); then
			ucode="intel-ucode"
		elif $(grep -q AuthenticAMD /proc/cpuinfo); then
			ucode="amd-ucode"
		fi
		pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware $ucode git stow sudo neovim fish man-db terminus-font
		genfstab -U /mnt > /mnt/etc/fstab
		read -p "Press any key..."
		vim /mnt/etc/fstab
		cp $0 /mnt/
		arch-chroot /mnt
		;;
	configure)
		echo "----- [Time & Locale] -----"
		ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime
		hwclock --systohc
		systemctl enable systemd-timesyncd.service
		systemctl start systemd-timesyncd.service
		sed -i -e "/#en_US.UTF-8/s/^#//" /etc/locale.gen
		sed -i -e "/#pl_PL.UTF-8/s/^#//" /etc/locale.gen
		locale-gen
		echo "LANG=pl_PL.UTF-8" > /etc/locale.conf
		echo -e "KEYMAP=pl\nFONT=ter-220b" > /etc/vconsole.conf

		echo "----- [Host] -----"
		while [[ -z $HOST ]]; do
			read -p "Enter hostname: " HOST
		done
		echo $HOST > /etc/hostname
		echo -e "127.0.0.1	localhost\n::1		localhost\n127.0.0.1	$HOST.localdomain $HOST" >> /etc/hosts

		echo "----- [Users] -----"
		echo "Set password for root:"
		passwd
		useradd -m -G wheel -s "$USERSHELL" $USERNAME
		echo "Set password for $USERNAME:"
		passwd $USERNAME
		echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10_wheel

		# TODO: move elsewere
		echo "----- [Installing YAY] -----"
		git clone https://aur.archlinux.org/yay.git /tmp/yay
		cd /tmp/yay && makepkg -si
		;;
	bootloader)
		echo "----- [Bootloader] -----"
		bootctl install
		echo -e "timeout 0\ndefault arch" > /boot/loader/loader.conf
		echo -e "title Arch Linux\nlinux /vmlinuz-linux-lts\ninitrd /intel-ucode.img\ninitrd /initramfs-linux-lts.img" > /boot/loader/entries/arch.conf
		echo -e "options root=\"LABEL=$DISK_LABEL\" rw modprobe.blacklist=iTCO_wdt nowatchdog" >> /boot/loader/entries/arch.conf
		read -p "Press any key..."
		$EDITOR /boot/loader/entries/arch.conf
		;;
	exit)
		exit && umount -R /mnt
		;;
	*)
		echo "Arch auto installer"
		echo "-------------------"
		echo "archinst.sh prepare"
		echo "archinst.sh install"
		echo "archinst.sh configure"
		echo "archinst.sh bootloader"
		echo "archinst.sh exit"
esac

