# Printing and scanning over wifi

How to set up the Canon PIXMA MG3650 on the home wifi with cups on Arch with
hyprland, for printing, scanning and the maintenance tasks that the Canon
software does on windows (ink levels, nozzle check, cleaning, quiet mode).
Three steps: install the packages, enable two services, do the rest in a gui.
Nothing depends on the address of the printer, so on a fresh host the same
three steps are repeated.

Why it is that short:

- **The printer needs no driver.** The MG3650 speaks ipp everywhere (what
  AirPrint uses) and cups builds the queue from what the printer reports
  about itself ([Arch wiki: CUPS, Driverless](https://wiki.archlinux.org/title/CUPS/Printer-specific_problems#Driverless)).
  The scanner works the same way over escl, through `sane-airscan`.
- **The printer is found by name, not by ip.** avahi picks up the name the
  printer announces on the network, `Canon MG3600 series`, and cups stores
  that name in the queue. An ip that changes with the next dhcp lease does
  not matter.
- **Maintenance is a web page served by the printer** (the Remote UI). It
  is what the Canon windows utility talks to, so nothing of that software is
  missing.

## 1. Install

```bash
sudo pacman -S --needed cups avahi nss-mdns system-config-printer sane-airscan simple-scan
sudo systemctl enable --now cups.service avahi-daemon.service
```

- `cups`: the print server. `avahi`: finds the printer on the network.
  `nss-mdns`: lets the browser open the printer by its name (`Remote UI`
  below). `system-config-printer`: the gui of cups. `sane-airscan` and
  `simple-scan`: scanner backend and gui.
- Not `cups-browsed` (creates queues on its own), not `gutenprint`,
  `foomatic` or anything from Canon: the printer needs no driver.

One line for `nss-mdns`: in `/etc/nsswitch.conf`, on the `hosts` line, add
`mdns_minimal [NOTFOUND=return]` right before `resolve`
([Arch wiki: Avahi, Hostname resolution](https://wiki.archlinux.org/title/Avahi#Hostname_resolution)):

```
hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns
```

## 2. Add the printer

Printer on, `system-config-printer`:

1. `Add`. It asks for a password, the own user and password work (the user
   is in `wheel`, which cups accepts as admin group on Arch).
2. Under `Network Printer` the printer shows up as `Canon MG3600 series`
   after a moment. Select it. If it is listed more than once, take the entry
   whose connection on the right says `driverless` or `IPP`, not `AppSocket`
   or `LPD`.
3. `Forward`. For a driverless printer the driver page is skipped. If it
   shows anyway, keep the proposed `Canon MG3600 series, driverless` entry
   or pick `Generic > IPP Everywhere`, never a Canon ppd.
4. Name `Canon_MG3650`, description `Canon PIXMA MG3650`, location `Home`,
   `Apply`. Skip the test page, it costs ink.
5. Right click the new printer, `Set As Default`.

Everything about the queue is in `Properties` of that printer:

| Tab | What |
|---|---|
| `Printer Options` | Defaults for every job: paper size, paper type (plain, photo, envelope), quality (draft, normal, high), colour or grey, duplex. The print dialog of an application overrides them per job. |
| `Ink/Toner Levels` | The two cartridges. Empty until the first job: cups only reads the levels from the printer while it prints, and shows what it read last. The Remote UI ([4](#4-printer-control-the-remote-ui)) has them without a job. |
| `Policies` | Enabled, accepting jobs. `Retry job` is what makes a job wait while the printer is off. |

`View Print Queue` shows and cancels jobs. The same is available in the
browser at `http://localhost:631` if system-config-printer is not at hand.

## 3. Add the scanner

`simple-scan`, printer on. It finds the scanner by itself and shows
`Canon MG3600 series` in `Preferences > Scanner`. `Text` and `Photo` at the
top are the two presets, every scan adds a page to the current document,
`Save` writes pdf, jpeg or png.

## 4. Printer control (the Remote UI)

The printer announces a hostname next to its name; the browser can open it
thanks to `nss-mdns`:

```bash
avahi-browse -rt _ipp._tcp | grep hostname     # something like [xxxxxxxxxxxx.local]
```

Open `http://<that hostname>` in the browser (or the ip of the printer from
the router's device list). The login password is the one Canon set at the
factory, the **serial number of the printer** (label on the back, or on the
sticker inside the front cover); the first login asks to change it.

What is in there, and what the windows software would have called it:

| Remote UI | What it does |
|---|---|
| `Printer status` | Ink levels, error state, page counter. |
| `Utilities > Nozzle check` | Prints the pattern that shows missing lines. |
| `Utilities > Cleaning`, `Deep cleaning` | Print head cleaning. Deep cleaning uses a lot of ink, only when a normal one did not help. |
| `Utilities > Bottom plate cleaning`, `Roller cleaning` | Smudges on the back of pages; paper not picked up. |
| `Device settings > Quiet setting` | Quiet mode. |
| `Device settings > Auto power` | Auto power on when a job arrives, auto power off delay. |
| `Device settings > Print settings`, `LAN settings` | Paper abrasion, ink drying time; wifi and ip. |
| `Firmware update` | Over the wifi, from Canon's server. |

Print head alignment is done with the buttons of the printer (hold `Stop`
until the alarm lamp has flashed a set number of times, with a sheet of A4
in the tray), the [Canon manual](https://ij.manual.canon/) for the
`MG3600 series` has the count. The one thing the windows driver has and
driverless has not is Canon's named paper list (`Photo Paper Plus Glossy II`
and so on); driverless knows plain, photo and envelope. If that ever matters,
Canon's linux driver is in the aur as `cnijfilter2` (and `scangearmp2` for
the scanner) and is added in system-config-printer as a second queue, with
the `Canon network printer` connection and the `Canon > MG3600 series` driver.

## 5. Troubleshooting

- **The printer is not in the list.** It is off (auto power off after some
  idle time, the `ON` lamp is out) or on another wifi. Turn it on and press
  `Refresh`. `systemctl is-active avahi-daemon` must say `active`. If the
  router's device list has the printer but avahi never sees it, the router
  blocks traffic between wifi clients (ap isolation, guest network), fix that
  in the router.
- **`Ink/Toner Levels` is empty.** No job has gone through the queue yet.
  Print anything small; cups reads the levels during the job and keeps
  them from then on.
- **A job waits and nothing happens.** The printer is off. Turn it on, cups
  retries by itself. If it happens all the time, `Auto power` in the Remote
  UI is set to a longer delay or off.
- **The password is refused when adding.** The user is not in `wheel`
  (`id -nG`).
- **Adding fails with an error about the ppd or attributes.** The printer
  went to sleep during the query. Wake it (press a button) and try again.
- **A tls or certificate error stops the queue**, after a firmware update or
  a factory reset of the printer: its self-signed certificate is new. Delete
  the file in `/etc/cups/ssl/` that carries the name of the printer, set the
  queue to `Enabled` again in `Properties > Policies`.
- **simple-scan finds no scanner** while printing works. The printer does not
  always announce the scanner over mdns. Give it by hand in
  `/etc/sane.d/airscan.conf`, with the hostname of [4](#4-printer-control-the-remote-ui):
  ```ini
  [devices]
  "Canon MG3650" = http://<hostname>/eSCL, escl
  ```
- **A cartridge is empty and the printer stops.** Hold `Stop` for at least
  five seconds, the printer prints on without level detection for that
  cartridge until it is replaced.
- **Blank pages or missing lines.** Nozzle check, cleaning, deep cleaning,
  in that order, all in the Remote UI.
