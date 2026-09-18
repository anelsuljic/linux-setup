# Arch linux installation guide

==*Created: 2026-03-24 19:43*==



1. Set the console keyboard layout (only during installation).

	```
	loadkeys es
	```

2. Connect to wifi.

	```
	ip addr show
	```

	**Notes about this command:**
	- To get the info of all network interfaces.

	---

	```
	iwctl
	```

	```
	station <interface name> scan
	```

	**Notes about this command:**
	- Wait at least 5 seconds before executing the next command.

	```
	station <interface name> get-networks
	```

	**Notes about this command:**
	- Lists available networks through the wireless interface specificed.

	---

	```
	station <interface name> connect <network name>
	```

	```
	exit
	```

	```
	ip addr show
	```

	**Notes about this command:**
	- It is good to check if the connection succeded :)

	---

3. **(optional)** Continue installation process from another PC using `ssh`.

	- On local PC (let's name it `PC A`):
	
		```
		passwd
		```
		**Notes about the command:**
			- Set a temporary root password on `PC A`.

		---

		```
		ip addr show
		```
		**Notes about the command:**
			- Obtain `PC A` IP address.

		---

	- On remote PC (let's name it `PC B`):
		```
		ssh root@<the-ip-address-of-pc-a>
		```

4. Partitioning our disk.

	```
	lsblk
	```

	**Notes about this command:**
	- Lists all disk devices and their partitions, among other information.

	---

	```
	cfdisk /dev/<disk device name>
	```

	**Notes about this command:**
	- Opens the partition table menu for the device selected. It's an intuitive menu, so it doesn't need any explanation.
	
	**Partitions to create:**
	
	- EFI partition: 1 GB, type: `EFI System`
	- Boot partition: 2 GB, type: `Linux Filesystem`
	- Rest of storage (main partition): X GB (X = the amount of storage left), type: `Linux LVM`

5. Encrypting main partiton.

	```
	cryptsetup luksFormat /dev/<main partition name>
	```
	
	```
	cryptsetup open --type luks /dev/<main partition name> lvm
	```

	```
	pvcreate /dev/mapper/lvm
	```

	```
	vgcreate volgroup0 /dev/mapper/lvm
	```

	```
	lvcreate -L XGB volgroup0 -n <name>
	```

	**Notes about `lvcreate`:**
	- Creates the logical partition `<name>` of `X GB` within `volgroup0`. You need at least to create a logical partition for root. 
	- Some names for logical partitions: `lv_root`, `lv_home`, `lv_swap`, etc.
	- Some examples of `XGB`: `30GB`.

	---

	```
	vgdisplay
	```

	**Notes about `vgdisplay`:**
	- Displays volume groups.

	---

	```
	lvdisplay
	```

	**Notes about `lvdisplay`:**
	- Displays logical volumes.

	---

	```
	modprobe dm_mod
	```

	```
	vgscan
	```

	```
	vgchange -ay
	```

	
6. Formatting our new partitions.

	```
	mkfs.fat -F32 /dev/<efi partition name>
	```

	```
	mkfs.ext4 /dev/<boot partition name>
	```

	```
	mkfs.ext4 /dev/volgroup0/<logical partition name>
	```

	**Notes about this command:**
	- This command should be executed for all logical partitions created, except for `lv_swap`. 

	```
	mkswap /dev/volgroup0/lv_swap
	```

	---

7. Mounting file systems.

	```
	mount /dev/volgroup0/<logical root partition name> /mnt
	```

	```
	mkdir /mnt/boot
	```

	```
	mount /dev/<boot partition name> /mnt/boot
	```

	```
	mkdir /mnt/boot/efi
	```

	```
	mount /dev/<efi partition name> /mnt/boot/efi
	```

	```
	swapon /dev/volgroup0/lv_swap
	```

8. Installing required packages.

	```
	pacstrap -i /mnt base
	```

9. Generating the `fstab` file.

	```
	genfstab -U -p /mnt >> /mnt/etc/fstab
	```

10. Using `arch-chroot` to finish our installation.

	```
	arch-chroot /mnt
	```

11. Setting up users.

	```
	passwd
	```

	**Notes about this command:**
	- Set up root password.

	---

	```
	useradd -m -g users -G wheel <user name>
	```

	**Notes about this command:**
	- Creates a new user.

	---

	```
	passwd <user name>
	```

	**Notes about this command:**
	- Sets a password for the user specified.

	---

12. Naming the computer.

	```
	echo "<your computer name>" > /etc/hostname
	```

13. Installing additional packages.

	```
	pacman -S base-devel amd-ucode cryptsetup dosfstools mtools lvm2 grub efibootmgr os-prober nano sudo networkmanager openssh git bluez bluez-utils bluez-deprecated-tools pipewire wireplumber pipewire-audio pipewire-alsa pipewire-pulse pipewire-jack ntfs-3g exfatprogs xdg-user-dirs cups man-db man-pages reflector
	```

	```
	systemctl enable NetworkManager
	```

	```
	systemctl enable sshd
	```

	```
	systemctl enable bluetooth
	```

	```
	systemctl enable cups
	```

14. Installing kernel.

	```
	pacman -S linux linux-headers linux-lts linux-lts-headers linux-firmware
	```

15. Installing GPU drivers.

	- For desktop computer (ryzen 7 2700x + 1070 ti):

		```
		pacman -S mesa
		```

	- For laptop computer (ryzen 9 6900hx + 3070 ti):

		```
		pacman -S mesa libva-mesa-driver
		```

16. Installing a graphical user interface.

	- For GNOME (minimal but stable setup without bloatware apps):

		```
		pacman -S gnome-shell gnome-control-center gdm nautilus gnome-console gnome-text-editor gnome-tweaks
		```

		```
		systemctl enable gdm
		```

	- For GNOME (standard group with essential default apps):

		```
		pacman -S gnome gdm gnome-tweaks
		```

		```
		systemctl enable gdm
		```

	- For GNOME (full installation with all GNOME extra applications and games):

		```
		pacman -S gnome gnome-extra gdm
		```

		```
		systemctl enable gdm
		```

	- For KDE Plasma (minimal but stable setup with X11 support):

		```
		pacman -S plasma-desktop plasma-x11-session sddm plasma-nm plasma-pa powerdevil bluedevil konsole dolphin
		```

		```
		systemctl enable sddm
		```

	- For KDE Plasma (standard group with essential apps and X11 support):

		```
		pacman -S plasma plasma-x11-session sddm kde-system kde-utilities
		```

		```
		systemctl enable sddm
		```

	- For KDE Plasma (full installation with all KDE applications and X11 support):

		```
		pacman -S plasma plasma-x11-session sddm kde-applications
		```

		```
		systemctl enable sddm
		```

17. Edit the file `/etc/locale.gen` and uncomment the locale you want. Then, execute:

	```
	locale-gen
	```

18. Set up your computer's language and keyboard layout (it would be necessary to set it up on gnome gui, too):

	```
	echo "LANG=en_US.UTF-8" > /etc/locale.conf
	```

	```
	echo "KEYMAP=es" > /etc/vconsole.conf
	```

19. Edit the file `/etc/mkinitcpio.conf`, and update the `HOOKS` line as follows:
	
	```
	HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt lvm2 filesystems fsck)
	```

	Then execute the following command:

	```
	mkinitcpio -P
	```
	
20. Edit the file `/etc/default/grub` and edit the following lines:

	```
	GRUB_DEFAULT=X
	```

	**Notes about this line:**
	- Tells that X entry will be selected by default.

	---

	```
	GRUB_CMD_LINE_LINUX_DEFAULT="... rd.luks.name=<YOUR-LUKS-UUID>=lvm root=/dev/volgroup0/lv_root quiet"
	```

	**Notes about this line:**
	- `<YOUR-LUKS-UUID>`: is the UUID of the `lv_root` **physical encrypted partition**. You can obtain it with `blkid`.

	---

	```
	GRUB_DISABLE_SUBMENU=y
	```

	**Notes about this line:**
	- Uncomment it. Remove the #.

21. Edit the file `/etc/sudoers` and uncomment the following line:

	```
	%wheel ALL=(ALL:ALL) ALL
	```

	**Notes about this line:**
	- Uncomment it. Remove the #.

22. Install grub.

	```
	grub-install --target=x86_64-efi --bootloader-id=<personalized id> --recheck
	```

	**Notes about this command:**
	- `<personalized id>` must be the name you want to appear at the UEFI booloader menu.

23. Additional steps.

	```
	cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
	```
	
	```
	grub-mkconfig -o /boot/grub/grub.cfg
	```

	```
	exit
	```

	```
	umount -R /mnt
	```



## References

1. 