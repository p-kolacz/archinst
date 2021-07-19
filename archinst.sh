#!/bin/bash

USER_NAME=piotr
USER_SHELL=/bin/fish
ROOT_LABEL=ARCH
ESP_LABEL=ESP
TIMEZONE=Europe/Warsaw
EDITOR=nvim

case $1 in
	prepare)
		[[ -d /sys/firmware/efi/efivars ]] && echo "UEFI mode" || echo "BIOS mode"
		[[ $(ping -c 1 archlinux.org) ]] || { echo "Network down. Use 'iwctl' to connect to WiFi."; exit 1; }
		echo -e "Network is ready\n"
		timedatectl set-ntp true
		timedatectl status
		echo -e "\n1. Use lsblk, gdisk to partition."
		echo "2. Use mkfs.fat -n $ESP_LABEL and mkfs.ext4 -L $ROOT_LABEL to format."
		;;
	install)
		mount /dev/disk/by-label/$ROOT_LABEL /mnt
		mkdir /mnt/boot
		mount /dev/disk/by-label/$ESP_LABEL /mnt/boot
		reflector
		vim /etc/pacman.d/mirrorlist
		ucode=""
		if $(grep -q GenuineIntel /proc/cpuinfo); then
			ucode="intel-ucode"
		elif $(grep -q AuthenticAMD /proc/cpuinfo); then
			ucode="amd-ucode"
		fi
		pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware $ucode networkmanager git stow sudo neovim fish man-db terminus-font
		genfstab -U /mnt > /mnt/etc/fstab
		read -p "Press any key..."
		vim /mnt/etc/fstab
		cp $0 /mnt/
		echo "Chrooting /mnt ..."
		arch-chroot /mnt
		;;
	configure)
		echo "----- [Time & Locale] -----"
		ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
		hwclock --systohc
		systemctl enable systemd-timesyncd.service
		sed -i -e "/#en_US.UTF-8/s/^#//" /etc/locale.gen
		sed -i -e "/#pl_PL.UTF-8/s/^#//" /etc/locale.gen
		locale-gen
		echo "LANG=pl_PL.UTF-8" > /etc/locale.conf
		echo -e "KEYMAP=pl\nFONT=ter-220b" > /etc/vconsole.conf

		echo "----- [Network] -----"
		while [[ -z $HOST ]]; do
			read -p "Enter hostname: " HOST
		done
		echo $HOST > /etc/hostname
		echo -e "127.0.0.1	localhost\n::1		localhost\n127.0.0.1	$HOST.localdomain $HOST" >> /etc/hosts
		systemctl enable NetworkManager.service

		echo "----- [Users] -----"
		echo "Set password for root"
		passwd
		useradd -m -G wheel -s "$USER_SHELL" $USER_NAME
		echo "Set password for $USER_NAME"
		passwd $USER_NAME
		echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10_wheel
		;;
	bootloader)
		echo "----- [Bootloader] -----"
		bootctl install
		echo -e "timeout 0\ndefault arch" > /boot/loader/loader.conf
		echo -e "title Arch Linux\nlinux /vmlinuz-linux-lts\ninitrd /intel-ucode.img\ninitrd /initramfs-linux-lts.img" > /boot/loader/entries/arch.conf
		echo -e "options root=\"LABEL=$ROOT_LABEL\" rw modprobe.blacklist=iTCO_wdt nowatchdog" >> /boot/loader/entries/arch.conf
		read -p "Press any key..."
		$EDITOR /boot/loader/entries/arch.conf
		;;
	exit)
		echo "1. exit"
		echo "2. umount -R /mnt"
		echo "3. reboot"
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

