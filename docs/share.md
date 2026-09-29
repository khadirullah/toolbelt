# share

Send text, a link, Wi-Fi or a folder to your phone.

## Synopsis

```
share [options] TEXT | URL
share [options] < FILE
share [options] --wifi [NAME]
share [options] FOLDER | FILE
```

## Description

Getting a link, a password or a few photos from a Linux machine to a phone usually means mailing them to yourself.
`share` does it with the phone camera instead. It has two modes.

Given text or a URL, it draws a QR code in the terminal. Point the phone camera at it and the phone offers to open the
link or copy the text. Nothing leaves the machine. The code is built locally by `qrencode`.

Given a folder or a file, it starts a small web server on a free port, prints the address other devices on the
network can open, with a QR code for it, and logs each download. Ctrl+C stops the server. With `-t 30m` it also stops
by itself after thirty minutes.

```console
$ share ~/Pictures/trip
sharing /home/khadir/Pictures/trip, 212 files, 48 MB
open http://192.168.1.24:8013/ on any device on Home-5G

  (QR code)

Ctrl+C stops it.
16:04:12  192.168.1.31  GET /                    200
16:04:19  192.168.1.31  GET /IMG_2041.jpg        200  3.1 MB
^C
share: stopped. 1 device, 14 files, 41 MB sent.
```

`share` decides the mode from the argument. When it names a folder or a file that exists, the folder or file is
served. Anything else is text. To send the name of a file that exists as text, pipe it in with `echo NAME | share`.

## Text and links

The text can come from the arguments or from stdin. Several arguments are joined with spaces, the way `echo` joins
them.

```console
$ share https://example.com/r/8Kd2
$ share "meet at gate 4, 18:30"
$ share < notes.txt
$ kubectl get secret web -o jsonpath='{.data.token}' | base64 -d | share
```

The text goes to `qrencode` on its stdin, never on its command line. Another user on the machine could read a
command line with `ps`, so a token piped into `share` stays out of sight. `-v` prints the qrencode command, and it
shows the text only when you typed the text as an argument.

### The size limit

One QR code holds at most 2,953 bytes, at the lowest error correction. `share` counts the bytes first and refuses
anything longer with exit 2, before it draws anything:

```
share: 3,412 bytes is too long for one QR code, the limit is 2,953.
       Share it as a file instead: share FILE
```

Long codes are also hard for a phone to read on a small terminal. A code with a few hundred characters works well, and
past about 1,000 the modules get too small unless the terminal font is large. Serve the file instead, as the message
says, or use `--png` and open the picture full screen.

`share` reads at most 2,954 bytes of stdin into memory and only counts the rest, so piping a large file in by mistake
costs nothing.

## Wi-Fi

`--wifi` builds the code phones use to join a network. It has the network name, the security type and the password.
Android and iOS both join from it with one tap, without typing the password.

```console
$ share --wifi
Wi-Fi Home-5G, WPA2, password from NetworkManager

  (QR code)
```

With no name, it uses the Wi-Fi network the machine is on now. With a name, it uses a network NetworkManager saved
earlier, such as `share --wifi Office`. The name is the connection name from `nmcli connection show`, which is
usually the network name too.

It reads the details from NetworkManager with `nmcli`:

| Field | Where it comes from |
|---|---|
| Network name | `802-11-wireless.ssid` |
| Security | `802-11-wireless-security.key-mgmt`. `wpa-psk` shows as WPA2, `sae` as WPA3, `none` as WEP, and no value as open. |
| Password | `802-11-wireless-security.psk`, or `wep-key0` for WEP, read with `nmcli -s`. |
| Hidden | `802-11-wireless.hidden`. A hidden network gets `H:true` in the code so the phone looks for it. |

The password never appears on screen, in `-v` output or on any command line. It goes into a temp file readable only
by you, which `share` deletes when it exits, and from there into `qrencode` on stdin. Characters the code format
reserves, such as `;`, `,`, `:` and `\`, get a backslash in front, so a password like `s3cret;pass` still works.

Networks with 802.1X logins, such as `wpa-eap` at work or eduroam, cannot be joined from a code. `share` says so and
exits 1.

NetworkManager hands out the password without root only when it is stored for all users, which is the default for
networks you join from the desktop. When the password is kept in your keyring instead, `nmcli -s` returns nothing
outside the desktop session, and `share` exits 1 with the hint to run it with `sudo`.

## Folders and files

A folder is served as it is, with a plain listing page for each subfolder. Phones show the listing and download a
file when you tap it.

A single file is served alone. `share` makes a temp folder that holds only a link to the file and serves that, so
the files next to it stay private. The address then points straight at the file:

```console
$ share -t 30m report.pdf
sharing /home/khadir/report.pdf, 2.1 MB
open http://192.168.1.24:8000/report.pdf on any device on Home-5G
```

### The server

`share` runs `python3 -m http.server`, bound to every address on a free port from 8000 up, or the port from `-P`.
When Python is missing it falls back to `busybox httpd`, which serves the same way but writes no log, so there is no
download log and the summary shows nothing sent.

The server only reads. Nobody can upload, delete or change a file through it. It has no password, though, and no
TLS, so anyone on the same network who knows or guesses the address can download what it serves while it runs. Use it
on a home network or a hotspot, not on cafe Wi-Fi.

### The address

The address is the one this machine uses to reach the internet, from `ip route get 1.1.1.1`. On a laptop with Wi-Fi
and a VPN, that can be the VPN address, which the phone cannot reach. Look at `myip` for the Wi-Fi address and open
that one with the same port instead.

The line also names the Wi-Fi network when there is one, so you can check the phone is on the same network. On a
wired machine it says "this network".

### The download log

Each request the server gets becomes one line: the time, the address of the device, the method, the path, the HTTP
code and, for a file that was sent, its size.

```
16:04:12  192.168.1.31  GET /                    200
16:04:19  192.168.1.31  GET /IMG_2041.jpg        200  3.1 MB
16:04:25  192.168.1.31  GET /favicon.ico         404
```

Long paths are cut from the left, so the file name stays visible. When the server stops, the summary counts the
devices by address, the files sent with code 200, and their size. A download the phone gave up halfway still counts in
full, since the server log does not say how much went out.

### Safety checks

`share` looks through the folder, three levels deep, for things that should not go to every device on the network.

| Found | What happens |
|---|---|
| `/` | Refused, exit 4. There is no way around it. |
| `.ssh`, `.gnupg`, `.aws`, `.kube`, `.password-store`, `.env`, `.netrc`, `.git-credentials` | It lists the first five and asks. |
| Private key files, such as `id_rsa`, `id_ed25519`, `*.pem`, `*.key`, or a KeePass `*.kdbx` | It lists them and asks. |
| Your home folder | It asks, even when nothing above matched. |

With no terminal to ask in, it refuses with exit 4. `-y` answers yes for scripts. Answering no exits 5 and serves
nothing.

The same check runs for a single file, so `share ~/.ssh/id_ed25519` asks first too.

## Options

| Option | What it does |
|---|---|
| `--wifi [NAME]` | Draw a join code for the current Wi-Fi, or for the saved network NAME. |
| `-P`, `--port PORT` | With a folder or a file, serve on this port. `share` exits 1 when the port is taken. |
| `-t`, `--time TIME` | With a folder or a file, stop after this long. `90`, `90s`, `30m`, `2h` and `1d` all work. |
| `--png FILE` | Write the code to a PNG file instead of the terminal. With a folder, the code for its address. |
| `-y`, `--yes` | Share a folder that holds keys or secrets without asking. |
| `-q`, `--quiet` | Only the address, the code, the download log and the summary. |
| `-v`, `--verbose` | Print each real command before it runs. |
| `-h`, `--help` | Show the help. |

`--png` never overwrites a file. When the name exists it writes `NAME-1.png` and says so. The picture has 10 pixels
per module and a quiet border of 4 modules, big enough to print.

## Pass-through

Options after `--` go to `qrencode`. The useful ones are the error correction level and the version:

```console
$ share https://example.com/r/8Kd2 -- -l H
$ share --wifi --png guest.png -- -l Q
```

`-l H` lets a phone read the code with up to 30 percent of it damaged or covered, at the cost of a bigger code. It
suits a code you print and stick on a wall. `-l L`, the default, gives the smallest code.

## Needs

`qrencode` for every code. It comes from the `qrencode` package on Debian, Ubuntu, Fedora, Arch and openSUSE, and
`libqrencode-tools` on Alpine. Without it, serving a folder still works and prints the address without a code.

`python3` to serve a folder or a file, or `busybox` as the fallback.

`nmcli` for `--wifi`, from NetworkManager. Machines that use `iwd`, `wpa_supplicant` or `systemd-networkd` alone have
no `nmcli`, and `--wifi` does not work there.

`ip` from iproute2 finds the address to print, with `hostname -I` as the fallback.

On Alpine, install `python3` separately, since the base image has none.

## Examples

### A link to the phone

```console
$ share https://example.com/r/8Kd2

  (QR code)
```

### The code as a picture, with every step shown

```console
$ share -v https://example.com/r/8Kd2 --png link.png
+ qrencode -o link.png -s 10 -m 4 https://example.com/r/8Kd2
wrote link.png, 25 x 25 modules, 330 x 330 px
```

### A guest Wi-Fi card to print

```console
$ share --wifi Guest --png guest-wifi.png -- -l H
Wi-Fi Guest, WPA2, password from NetworkManager
wrote guest-wifi.png, 29 x 29 modules, 370 x 370 px
The password is in the code and is not printed here.
```

### A file for half an hour

```console
$ share -t 30m report.pdf
sharing /home/khadir/report.pdf, 2.1 MB
open http://192.168.1.24:8000/report.pdf on any device on Home-5G

  (QR code)

Stops in 30m, or on Ctrl+C.
16:10:02  192.168.1.31  GET /report.pdf          200  2.1 MB
share: stopped after 30m. 1 device, 1 file, 2.1 MB sent.
```

### A folder, stopped after two seconds

```console
$ share -t 2s /tmp/shr/d
sharing /tmp/shr/d, 2 files, 7 B
open http://192.168.122.210:23456/ on any device on this network

  (QR code)

Stops in 2s, or on Ctrl+C.
17:47:44  127.0.0.1  GET /a.txt               200  3 B
17:47:44  127.0.0.1  GET /sub/b%20c.txt       200  4 B
17:47:44  127.0.0.1  GET /nope                404
share: stopped after 2s. 1 device, 2 files, 7 B sent.
```

### Text that is too long

```console
$ share < notes.txt
share: 3,412 bytes is too long for one QR code, the limit is 2,953.
       Share it as a file instead: share FILE
```

### A folder with SSH keys in it

```console
$ share ~/backup
share: this shares files that look like keys or secrets:
  /home/khadir/backup/.ssh
Anyone on the network can download them. Share anyway? [y/N] n
Nothing changed.
```

## Troubleshooting

The phone cannot open the address
: Check the phone is on the same network, named on the `open` line. Guest networks and some routers keep devices
  apart, so they cannot reach each other. A firewall on this machine may also block the port. On Fedora and openSUSE,
  firewalld blocks it by default. Open it for the session with `sudo firewall-cmd --add-port=8000/tcp`, and on
  Ubuntu with ufw, `sudo ufw allow 8000/tcp`.

The address is a VPN or Docker address
: `share` takes the address of the default route. Run `myip` and use the Wi-Fi or wired address with the same port.

`port N is in use`
: Another program holds the port. Leave out `-P` to take a free one, or see who holds it with `port N`.

The phone camera does not see the code
: The terminal font may be too small or the colours inverted. Make the font bigger, or write a PNG with `--png` and
  open it full screen. A light terminal theme works best.

`NetworkManager did not give the password`
: The password lives in your keyring. Run `sudo share --wifi NAME`, or open the network settings on the desktop, which
  offer a code of their own on GNOME.

`uses wpa-eap, which a phone cannot join from a QR code`
: Enterprise networks need a user name and a certificate, which the code format cannot hold.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The code was drawn or written, or the server ran and stopped on Ctrl+C or `--time`. |
| 1 | It failed, such as no Wi-Fi, a taken port, or a server that would not start. |
| 2 | Bad usage, or the text is too long for one QR code. |
| 3 | `qrencode`, `nmcli`, or both `python3` and `busybox` are missing. |
| 4 | Refused, for `/` or a folder with secrets and no terminal to ask in. |
| 5 | You answered no. |

## See also

`myip`, `port`, `lan`, `qrencode(1)`, `nmcli(1)`
