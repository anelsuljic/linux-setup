# Arch linux post installation guide

==*Created: 2026-03-24 20:46*==


**For laptop:**

1. Execute `xdg-user-dirs-update` to set up all user directories.
2. Execute `nmtui` to set up an connection.
3. Install `yay`:
	```bash
	git clone https://aur.archlinux.org/yay.git
	```
	```bash
	cd yay 
	```
	```bash
	makepkg -si
	```
4. Install `ml4w` desktop environment: look at its [website](https://ml4w.com/os/) for more details, but for now the command is the below one.

	```bash
	bash <(curl -s https://ml4w.com/os/stable)
	```

5. After reboot and login, enter hyprland by typing `start-hyprland`.
6. On welcome page from `ml4w` go to:
	- `Settings -> Input`: to change keyboard language.
	- `Settings -> Monitors`: to change monitor's scale if needed.
	- `Settings -> Install HyprMod`: to install `hyprmod`.
	- `System -> Display Manager`: to install a login manager.
7. **(Optional)** In case you wanna use `ly` login manager:

	```bash
	sudo systemctl disable sddm.service
	sudo pacman -S ly
	sudo systemctl enable ly@tty2
	```

	To edit its configuration, edit `/etc/ly/config.ini`. Then execute:

	```
	ly --validate-config /etc/ly/config.ini
	```

8. Follow the guide from [asus linux](https://asus-linux.org/guides/arch-guide/). Do not install nvidia drivers nor custom kernel.
9. Clone the repository where you've got your setup scripts and execute them. 

**For desktop:**

1. On grub menu, select the entry you want to boot and hit `e`. Go to the line that starts with `linux` and delete the `quiet` word. This will help us see what is actually loaded and not. Then, add `nomodeset 3` at the end of the line. After that, hit `ctrl + x`.
2. Log in with your user and execute `ip addr show`.
3. Using another device, enter this device through ssh: `ssh <username>@<ipaddress>`, where `<ipaddress>` is the one given by `ip addr show`.
4. Execute `xdg-user-dirs-update` to set up all user directories.
5. Install `yay`:

	```bash
	git clone https://aur.archlinux.org/yay.git
	cd yay 
	makepkg -si
	```

6. Clone the repository where you've got your setup scripts and execute them. 
7. Install `ml4w` desktop environment: look at its [website](https://ml4w.com/os/) for more details, but for now the command is the below one.

	```bash
	bash <(curl -s https://ml4w.com/os/stable)
	```

7. After reboot and login, enter hyprland by typing `start-hyprland`.
8. On welcome page from `ml4w` go to:
	- `Settings -> Input`: to change keyboard language.
	- `Settings -> Monitors`: to change monitor's scale if needed.
	- `Settings -> Install HyprMod`: to install `hyprmod`.
	- `System -> Display Manager`: to install a login manager.

9. **(Optional)** In case you wanna use `ly` login manager:

	```bash
	sudo systemctl disable sddm.service
	sudo pacman -S ly
	sudo systemctl enable ly@tty2
	```

	To edit its configuration, edit `/etc/ly/config.ini`. Then execute:

	```
	ly --validate-config /etc/ly/config.ini
	```


**Setting up secure boot:**

1. Enter UEFI menu an ensure **Secure Boot** settings are in **Setup Mode**. You can force that mode by deleting secure boot keys. Don't worry if you mess up, you can restore secure boot setting by enrolling factory keys.
2. Boot into the system.
3. Execute the following commands:
	- ```
		sudo pacman -S sbctl
	  ```

	- ```
		sbctl status
	  ``` 

		- Ensure it says `Setup Mode: enabled`.

	- ```
		sudo sbctl create-keys
	  ```

	- ```
		sudo sbctl enroll-keys -m
	  ``` 
		- The `-m` flag is mandatory. It includes Microsoft's certificates so your GPU firmware and Windows dual-boots are not blocked.
	- ```
		sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=<personalized id> --modules="normal test efi_gop efi_uga search echo linux all_video gfxmenu gfxterm_background gfxterm loadenv configfile tpm part_gpt ext2 fat" --disable-shim-lock
	  ```

		**Notes about this command:**
		- `<personalized id>` must be the name you want to appear at the UEFI booloader menu.
		- Use `efibootmgr` command to check which name has your grub menu before choosing `<personalized id>`.
	  
	- ```
		sudo sbctl sign -s /boot/efi/EFI/<personalized id>/grubx64.efi
	  ```
		
		**Notes about this command:**
		- `<personalized id>` must be the name you want to appear at the UEFI booloader menu.
		- Use `efibootmgr` command to check which name has your grub menu before choosing `<personalized id>`.

	- For laptop:
	  ```
		sudo sbctl sign -s /boot/vmlinuz-linux-g14
	  ```
	- For PC desktop:
	  ```
		sudo sbctl sign -s /boot/vmlinuz-linux
	  ```
	  
	- ```
		sudo sbctl sign -s /boot/vmlinuz-linux-lts
	  ```
	  
	- ```
		sudo sbctl verify
	  ```
4. Reboot and enter UEFI menu to enable secure boot.


## References

1. 