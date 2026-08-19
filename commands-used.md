# Commands used

A guide of every linux command that the scripts of this repository run, grouped
by what it is used for. Each entry says what the command does, what its flags
mean and which script uses it.

It covers `setup.sh`, every script under `setups/`, the helper commands under
`files/` and the aliases of `setup-bashrc.txt`, which becomes `.bashrc_custom`.

## The skeleton that every script shares

### Finding its own folder

```bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
```

- **`dirname <path>`** removes the last part of a path, so
  `dirname /home/user/setup.sh` prints `/home/user`. `${BASH_SOURCE[0]}` is the
  path of the running script, so both together give the folder it lives in.
- **`cd <folder> && pwd`** enters that folder and prints its absolute path.
  `dirname` can return something relative like `.`, and `pwd` turns it into a
  full path.
- **`--`** marks the end of the flags, so a path that starts with `-` is taken
  as a path and not as an option.
- **`&> /dev/null`** throws away everything the command prints, the normal
  output and the errors. `cd` prints the folder it entered when `CDPATH` is set,
  and that text would end up inside `SCRIPT_DIR`.

The result is the folder of the script itself, which is what lets it find its
own files no matter from where it is called.

### Asking whether to run

```bash
printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
read -p "Do you want to set up git? [y/n]: " choice
printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

[[ "$choice" != "y" ]] && exit 0
```

- **`printf <format> <arguments>`** prints text following a format, and unlike
  `echo` it adds no newline of its own. `%*s` prints a string padded to a given
  width and eats two arguments, the width `40` and the empty string `''`, so it
  prints 40 spaces. The `\n` are the blank lines around them.
- **`tr <from> <to>`** replaces characters one by one, here every space by a
  dash, which turns those 40 spaces into a separator line.
- **`|`** sends the output of the command on its left into the input of the one
  on its right.
- **`read -p <prompt> <variable>`** prints the prompt, waits for a line of input
  and stores it in the variable. `setup-graphics.sh` also uses a bare
  `read model`, without `-p`, so its question is printed by an `echo` before it.
- **`exit <number>`** ends the script, `0` means success and anything else an
  error.

## Running other things

- **`bash <script>`** runs a script in a new shell. Whatever it defines is lost
  when it ends, which is why `setup.sh` can call the eight setups one after
  another without them interfering with each other.
  (`setup.sh`, `setup-graphics.sh`, `setup-proglang.sh`)
- **`source <file>`** runs a file in the current shell, so what it defines stays
  afterwards. `setup-bashrc.sh` uses it to apply the new aliases without having
  to open a new terminal.
- **`exec <command>`** replaces the current shell with the command instead of
  starting a second process, so the command keeps the same pid. `gpu-run` uses
  it so the app it launches inherits the exported variables and no shell is left
  behind, and `sddm-hyprland` uses it so sddm keeps tracking the process it
  started. `"$@"` is the list of arguments the script received.
- **`command -v <name>`** prints the path of a command and fails if it does not
  exist, so it is the way to check that something is installed before using it.
  (`setup-sddm.sh`)
- **`sudo <command>`** runs a command as root. The scripts are meant to be run
  as the normal user and call `sudo` only on the lines that need it, so the
  files they write into `$HOME` keep belonging to the user.
- **`set -e`** stops the script at the first command that fails. (`gpu-mux`)
- **`echo <text>`** prints a line of text. Used all over to say what is going on.

## Packages

Arch has `pacman` for the official repositories and `yay` for those plus the
aur. `yay` is never called with `sudo`, it asks for the password on its own.

- **`sudo pacman -S --needed --noconfirm <packages>`** installs packages.
  `--needed` skips the ones that are already installed and `--noconfirm`
  answers yes to every question, so the script never stops to ask.
  (`setup-graphics-rog.sh`, `setup-sddm.sh`)
- **`yay -S --needed --noconfirm <packages>`** the same, but it can also build
  packages from the aur. (`setup-graphics.sh`)
- **`yay -S --needed --noconfirm - < install-list.txt`** the `-` means "read the
  names from the standard input" and `<` feeds the file into it, so the whole
  list is installed with one call. (`setup-apps.sh`)
- **`pacman -Qq <package>`** asks the local database whether a package is
  installed, `-q` prints only the name. `setup-graphics-rog.sh` uses it as a
  test, to add the headers of every kernel that is installed and of no other.
- **`pacman -Si <package>`** asks the repositories for the information of a
  package and fails if it is not there. `install_pkg` uses it to decide between
  pacman and yay. (`.bashrc_custom`)
- **`sudo pacman -D --asexplicit <packages>`** marks packages as installed on
  purpose. A package installed as a dependency of another one is removed once
  nothing needs it anymore, and this is what keeps the wanted ones.
  (`setup-apps.sh`)

## Files, folders and links

- **`sudo install -Dm755 <source> <destination>`** copies a file and sets its
  permissions in one go. `-D` creates the folders of the destination if they are
  missing and `-m` sets the mode, `755` for something executable and `644` for a
  configuration file. (`setup-graphics-rog.sh`, `setup-sddm.sh`)
- **`mkdir -p <folder>`** creates a folder, `-p` creates the parents it needs and
  does not complain if it already exists. (`setup-graphics-rog.sh`)
- **`sudo cp -r <source> <destination>`** copies, `-r` for a whole folder.
  (`setup-sddm.sh`)
- **`sudo chmod -R a+rX <folder>`** gives everybody (`a`) permission to read
  (`r`) and to enter folders (`X`). The capital `X` is what matters: it adds the
  execute permission only to folders and to files that already had it, so it
  does not turn images into programs. `-R` walks the whole tree.
  (`setup-sddm.sh`)
- **`sudo ln -s <target> <name>`** creates a symbolic link, a name that points to
  another file. `setup-simlinks.sh` uses it to call `gnome-text-editor` by
  typing `gte`.

## Writing files

- **`cat <file>`** prints a file. `cat "$SETUP_BASH" > "$BASHRC"` prints it into
  another file, where `>` overwrites and `>>` would append. (`setup-bashrc.sh`)
- **`cat > <file> << EOF ... EOF`** writes everything between the two `EOF` marks
  into a file. It is called a heredoc and it is the way to write a whole block of
  text from a script. (`setup-graphics-rog.sh`)
- **`sudo tee <file> > /dev/null << EOF ... EOF`** the same, but for a file that
  belongs to root. `sudo cat > /etc/...` does not work, because the shell opens
  the file before sudo runs and it does so as the normal user. `tee` receives the
  text and writes the file itself, already as root, and `> /dev/null` hides the
  copy that it also prints on screen. (`setup-graphics-rog.sh`)
- **`<< 'EOF'` and `<< EOF` are not the same.** With the quotes nothing inside is
  expanded and `$VAR` is written as it is, without them the shell replaces the
  variables first, which is how the pci address of the dgpu ends up inside
  `/etc/tmpfiles.d/nvidia-runtime-pm.conf`. (`setup-graphics-rog.sh`)

## Searching and editing text

- **`grep -v '^#' <file>`** prints the lines that do not match the pattern, `-v`
  is what inverts it and `^#` means "starts with a #", so this drops the comments
  of the package lists. (`setup-apps.sh`)
- **`grep -q <pattern>`** prints nothing and answers only through its exit
  status, which is what a condition needs. `-E` on top of it allows the extended
  regular expressions, like the `\b` word boundaries of `'^HOOKS=.*\bkms\b'`.
  (`setup-graphics-rog.sh`, `setup-sddm.sh`)
- **`sed -E 's/^pci-(.*)-card$/\1/'`** replaces text. `s/old/new/` is the
  substitution, the parentheses remember a piece and `\1` puts it back, so this
  keeps only the pci address out of a name like `pci-0000:01:00.0-card`.
  (`setup-graphics-rog.sh`)
- **`sed -n 's/^CursorTheme=//p'`** reads a value out of a configuration file.
  `-n` silences the normal output and the `p` at the end prints only the lines
  that did match, without their prefix. (`setup-sddm.sh`, `sddm-hyprland`)
- **`sed '/^$/d'`** deletes the lines that match, here the empty ones.
  (`setup-apps.sh`)
- **`sed -i.bak -E '...'`** edits the file in place instead of printing the
  result, and keeps the original as `<file>.bak`. This is how the `kms` hook is
  taken out of `/etc/mkinitcpio.conf`. (`setup-graphics-rog.sh`)
- **`sort -u -o <file> <file>`** sorts the lines and `-u` keeps only one copy of
  each. `-o` writes the result back into the same file, which is safe here while
  a plain `>` would empty it. (`.bashrc_custom`)
- **`xargs -r <command>`** takes the lines it receives and puts them as arguments
  of a command, so a whole list is handled with one call instead of one call per
  line. `-r` does not run the command at all when the input is empty.
  (`setup-apps.sh`)

## Paths and devices

- **`basename <path>`** keeps only the last part of a path, the opposite of
  `dirname`. (`setup-graphics-rog.sh`)
- **`readlink -f <path>`** follows a symbolic link until the end and prints the
  real file. `/dev/dri/by-path/pci-...-card` is a link, and this is what turns it
  into the `/dev/dri/cardN` node that hyprland needs. (`setup-graphics-rog.sh`)
- **`cat /sys/bus/pci/devices/<address>/vendor`** reads a file of `/sys`, the
  folder where the kernel exposes the hardware. `0x1002` is amd and `0x10de` is
  nvidia, which is how the script tells both gpus apart. (`setup-graphics-rog.sh`)
- **`$(<file)`** is the shell reading a file by itself, without calling `cat`.
  The `dgpu` function uses it on the power files of `/sys`. (`.bashrc_custom`)

## System configuration

- **`sudo mkinitcpio -P`** builds the initramfs again, the small system that the
  kernel loads before the real root. `-P` does it for every preset, that is, for
  every installed kernel. It is needed after touching the modules or the hooks.
  (`setup-graphics-rog.sh`)
- **`sudo systemctl enable <services>`** makes services start on their own at
  boot. `systemctl` is the command of systemd, the thing that starts everything
  on the machine. (`setup-graphics-rog.sh`)
- **`sudo systemd-tmpfiles --create <file>`** applies now the given file of
  `/etc/tmpfiles.d`, which otherwise would only be applied at the next boot.
  Those files describe files to create and values to write, and here they are
  what enables the runtime power management of the dgpu.
  (`setup-graphics-rog.sh`)
- **`timedatectl set-local-rtc 1 --adjust-system-clock`** tells the system that
  the hardware clock keeps local time instead of utc, which is what windows
  assumes, so the hour stops jumping when dual booting. `--adjust-system-clock`
  fixes the clock right away. (`setup-time.sh`)

## Graphics and hardware

- **`export <VARIABLE>=<value>`** puts a variable into the environment, so the
  programs started afterwards can read it. `gpu-run` exports the five variables
  that send an app to the nvidia dgpu and `sddm-hyprland` the ones of the
  greeter. (`gpu-run`, `sddm-hyprland`, `.bashrc_custom`)
- **`asusctl armoury set gpu_mux_mode <0|1>`** switches the hardware mux of the
  laptop, `0` is ultimate, where the dgpu drives everything, and `1` is hybrid.
  `asusctl armoury get gpu_mux_mode` reads the current one. A reboot is needed
  after every change. (`gpu-mux`)
- **`Hyprland --verify-config -c <file>`** parses a configuration and says
  whether it is correct, without starting anything. (`setup-sddm.sh`)
- **`start-hyprland -- -c <file>`** starts hyprland the way it is meant to be
  started, with a parent process that stays in the foreground watching over it.
  What comes after `--` is passed to hyprland itself. (`sddm-hyprland`)

## Network

- **`curl --proto '=https' --tlsv1.2 -sSf <url> | sh`** downloads the installer of
  ghcup and runs it. `--proto '=https'` allows nothing but https, `--tlsv1.2`
  sets the minimum version of tls, `-s` hides the progress bar, `-S` brings the
  errors back and `-f` fails instead of saving the error page of the server. The
  `| sh` is what runs the downloaded script. (`setup-haskell.sh`)

## Git

- **`git config --global <key> <value>`** writes an option into `~/.gitconfig`,
  and `--global` is what makes it apply to every repository of the user instead
  of only to the current one. `setup-git.sh` sets the name and the email of the
  commits, the default branch, the editor and the diff tool.
- **`git config --global -e`** opens that file to check it.

## Tests and conditions

They are not commands of their own, but they appear in every script.

- **`[[ "$choice" != "y" ]] && exit 0`** runs the right side only when the left
  one is true, so the script leaves when the answer was not `y`.
- **`[ -f <file> ]`** is true when the file exists, **`[ -d <folder> ]`** when the
  folder exists and **`[ -e <path> ]`** when anything is there.
- **`[ -z "$var" ]`** is true when the variable is empty and **`[ -n "$var" ]`**
  when it is not.
- **`$?`** is the exit status of the last command, `0` when it worked.
- **`case <value> in ... esac`** chooses between several patterns, which is how
  the vendor of a gpu and the argument of `gpu-mux` are read.

## The aliases of .bashrc_custom

`setup-bashrc.txt` becomes `~/.bashrc_custom`, and these are the commands behind
its aliases and functions.

- **`clear`** empties the screen, **`history -c`** the list of commands of the
  running shell and **`cat /dev/null > ~/.bash_history`** the file where that
  list is saved. The `clean`, `cexit`, `creboot` and `cpoweroff` aliases chain
  them with `exit`, **`reboot`** and **`poweroff`**.
- **`g++ <flags>`** is the c++ compiler. `-O2` optimizes, `-Wall -Wextra` turn on
  the warnings, `-Werror` turns them into errors, `-D_GLIBCXX_DEBUG` checks the
  standard library while the program runs and `-std=c++11` or `-std=c++17` pick
  the version of the language.
- **`java -jar <file>`** runs a program packed into a jar, which is how `antlr4`
  is called, and **`java <class>`** runs a class found through `CLASSPATH`, which
  is how `grun` starts the test rig of antlr.
- **`wl-copy`** copies its standard input into the clipboard of wayland.
- **`eval "$(keychain --eval ...)"`** — `keychain` prints the variables of an ssh
  agent and `eval` runs that text as if it had been typed, so every terminal
  reuses the same agent and the passphrase is asked only once.
- **`sudo openfortivpn <host>:<port> --saml-login`** connects to a fortinet vpn.
- **`TERM=xterm-256color ssh`** sets a variable for that command alone, so the
  remote machine gets a terminal name that it knows.
- **`install_pkg <packages>`** is a function, not a command: it looks each
  package up with `pacman -Si` and `yay -Si`, installs it with whichever knows
  it and appends the name to `install-list.txt`, so what is installed by hand is
  not lost on the next installation.
- **`dgpu`** prints the power state of the nvidia card by reading three files of
  `/sys`.

## Only in the old scripts

`old-scripts/` keeps the previous versions, which used two commands that are not
used anymore.

- **`grep -v '^#' remove-list.txt | xargs -r sudo pacman -Rns --noconfirm`**
  removed the bloatware. `-R` removes, `-s` takes with it the dependencies that
  nothing else needs and `-n` also deletes the configuration files that would be
  left behind.
- **`gsettings set <schema> <key> <value>`** writes a setting of gnome, here the
  tracking options of its magnifier.
