#!/bin/bash
set -e
exec > >(tee archinst.log) 2>&1

USER_SHELL=/usr/bin/zsh
ROOT_LABEL=ARCH
ESP_LABEL=ESP
TIMEZONE=Europe/Warsaw
EDITOR=vim
INITIAL_APPS=(base base-devel linux-lts linux-lts-headers linux-firmware networkmanager git man-db terminus-font zsh zsh-autosuggestions zsh-syntax-highlighting)
SCRIPT=${0##*/}

if grep -q GenuineIntel /proc/cpuinfo; then
	CPU="intel"
elif grep -q AuthenticAMD /proc/cpuinfo; then
	CPU="amd"
fi
[[ -z $CPU ]] && { echo "Can't determine CPU vendor, exiting."; exit 1; }

wait_any_key() {
	read -rs -n1 -p "${1:-Press any key...}"
}

prompt() {      # prompts for exacly one word
	echo
	local INPUT
	while [[ ${#INPUT[@]} -ne 1 ]]; do
		read -r -p "$1" -a INPUT
	done
	local -n ref=$2
	# shellcheck disable=SC2034
	ref=${INPUT[0]}
}

case $1 in
	prepare)
		[[ -d /sys/firmware/efi/efivars ]] && echo "UEFI mode" || echo "BIOS mode"
		echo "${CPU^^} CPU detected"
		[[ $(ping -c 1 archlinux.org) ]] || { echo "Network down. Use 'iwctl' to connect to WiFi."; exit 1; }
		echo "Network is ready"
		timedatectl set-ntp true
		timedatectl status
		echo -e "\n1. Use lsblk, fdisk/gdisk to partition."
		echo "2. Use mkfs.fat -n $ESP_LABEL and mkfs.ext4 -L $ROOT_LABEL to format."
		echo "3. When ready, run ./$SCRIPT install"
		;;
	install)
		mount /dev/disk/by-label/$ROOT_LABEL /mnt
		mkdir /mnt/boot
		mount /dev/disk/by-label/$ESP_LABEL /mnt/boot
		pacstrap /mnt "${INITIAL_APPS[@]}" "$CPU-ucode"
		genfstab -U /mnt > /mnt/etc/fstab
		wait_any_key
		$EDITOR /mnt/etc/fstab
		cp "$0" /mnt/
		echo "Installaction complete. Run /$SCRIPT configure"
		echo "Chrooting /mnt ..."
		arch-chroot /mnt
		#
		# Here script will wait for exiting chroot
		#
		echo "Unmounting /mnt"
		umount -R /mnt || { echo "Did you exited chroot?"; exit 2; }
		wait_any_key "All done! Press any key to reboot..."
		reboot
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

		echo "----- [SSD trim] -----"
		systemctl enable fstrim.timer

		echo "----- [Network] -----"
		prompt "Enter hostname:" HOST
		echo "$HOST" > /etc/hostname
		echo -e "127.0.0.1	localhost\n::1		localhost\n127.0.0.1	$HOST.localdomain $HOST" >> /etc/hosts
		systemctl enable NetworkManager.service

		echo "----- [Users] -----"
		echo "Set password for root"
		passwd
		prompt "Enter username: " USER_NAME
		useradd -m -G wheel -s "$USER_SHELL" "$USER_NAME"
		echo "Set password for $USER_NAME"
		passwd "$USER_NAME"
		echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10_wheel

		prompt "Enable 4GB swap file (y/n)?" ENABLE_SWAP
		[[ $ENABLE_SWAP == "y" ]] && {
			echo "----- [Swap] -----"
			dd if=/dev/zero of=/swapfile bs=1G count=4 status=progress
			chmod 0600 /swapfile
			mkswap -U clear /swapfile
			swapon /swapfile
			echo "/swapfile none swap defaults 0 0" >> /etc/fstab
			wait_any_key
		}

		prompt "Install bootloader (y/n)?" INSTALL_BL
		[[ $INSTALL_BL == "y" ]] && {
			echo "----- [Bootloader] -----"
			bootctl install
			echo -e "timeout 0\ndefault arch" > /boot/loader/loader.conf
			echo -e "title Arch Linux\nlinux /vmlinuz-linux-lts\ninitrd /$CPU-ucode.img\ninitrd /initramfs-linux-lts.img" > /boot/loader/entries/arch.conf
			echo -e "options root=\"LABEL=$ROOT_LABEL\" rw modprobe.blacklist=iTCO_wdt nowatchdog" >> /boot/loader/entries/arch.conf
			wait_any_key
		}
		echo "Configuration complete. Press Ctrl+D to exit chroot."
		;;
	*)
		echo "Arch auto installer"
		echo "USAGE: $SCRIPT [prepare|install|configure]"
esac

