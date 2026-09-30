# pkg

One package command on every distro.

## Synopsis

```
pkg install|remove|search|info NAME ... [-- tool options]
pkg owner PATH ...
pkg files NAME
pkg upgrade [--all] [-- tool options]
```

## Description

Every Linux family has its own package manager with its own words. Debian and Ubuntu use `apt`, Fedora and RHEL
use `dnf`, Arch uses `pacman`, openSUSE uses `zypper` and Alpine uses `apk`. The same job has five spellings.
Searching is `apt search`, `dnf search`, `pacman -Ss`, `zypper search` and `apk search`. The list of files in a
package is `dpkg -L`, `rpm -ql`, `pacman -Qlq` and `apk info -L`.

`pkg` gives you one set of words and runs the real command for the machine it is on. It does not install anything
by itself and it has no package list of its own. The distro's package manager does all the work, prints its own
output and asks its own questions. `pkg` adds three things on top.

1. It finds the package manager by looking for the commands themselves, in the order apt-get, dnf, yum, pacman,
   zypper and apk. The first one found wins. That makes Linux Mint and Pop!_OS count as apt, Rocky and Alma as
   dnf, and Manjaro and EndeavourOS as pacman, with no list of distros to keep up to date.
2. It puts `sudo` in front of the commands that change the system, unless you are root. `search`, `info`,
   `owner` and `files` only read, so they never use sudo.
3. After an install or a remove it prints one line you can trust, such as `pkg: installed ripgrep 14.1.1-1+b4`,
   with the version read back from the package database. The package manager's own output can run to a hundred
   lines, and that line is the one that matters.

`pkg owner` answers "which package put this file here?". It takes a path or a bare command name. For a bare name
it looks the command up on your `PATH` first, so `pkg owner ss` means `pkg owner /usr/bin/ss`. It also handles
merged `/usr`, where `/bin` is a link to `/usr/bin`. The database may know the file as `/bin/ss` or as
`/usr/bin/ss`, so `pkg` asks about both, then about the real file behind a symlink. A file no package owns
shows as `no package, installed by hand`. That is how you spot a binary someone copied into `/usr/local/bin`.

`pkg upgrade` refreshes the package lists and updates everything the package manager installed. With `--all` it
also updates flatpak apps, snaps and device firmware through fwupd, each one skipped when it is not installed.
When the update brought a newer kernel than the one running, the last line says so, because the new kernel only
takes effect after a reboot.

## Options

| Option | What it does |
|---|---|
| `--all` | With `upgrade`, also run `flatpak update`, `snap refresh` and `fwupdmgr update`. |
| `-n`, `--dry-run` | Print the commands `pkg` would run, one per line, then stop. Nothing runs, not even sudo. |
| `-y`, `--yes` | Pass the package manager's own yes flag, so it does not ask. |
| `-q`, `--quiet` | Only the result lines. The package manager's output still shows, since it is theirs. |
| `-v`, `--verbose` | Say which distro and package manager it found, and show each command before it runs. |
| `-h`, `--help` | Show the help. |

Options can go anywhere before `--`. `pkg install htop -y` and `pkg -y install htop` are the same.

## Actions

| Action | What it does | Needs root |
|---|---|---|
| `install NAME ...` | Install one or more packages, then print the installed version of each. | yes |
| `remove NAME ...` | Remove one or more packages. | yes |
| `search WORD` | Search the package names and descriptions in the repos. | no |
| `info NAME` | Show a package's version, size, dependencies and description. | no |
| `owner PATH ...` | Show which installed package owns each file, with its version. | no |
| `files NAME` | List every file an installed package put on the disk. | no |
| `upgrade` | Refresh the package lists and update everything. | yes |

## The commands it runs

This is the whole translation table. `-n` prints the same commands for your machine.

| Action | apt | dnf | pacman | zypper | apk |
|---|---|---|---|---|---|
| install | `apt install` | `dnf install` | `pacman -S` | `zypper install` | `apk add` |
| remove | `apt remove` | `dnf remove` | `pacman -Rs` | `zypper remove` | `apk del` |
| search | `apt search` | `dnf search` | `pacman -Ss` | `zypper search` | `apk search` |
| info | `apt show` | `dnf info` | `pacman -Si` | `zypper info` | `apk info` |
| owner | `dpkg -S` | `rpm -qf` | `pacman -Qo` | `rpm -qf` | `apk info -W` |
| files | `dpkg -L` | `rpm -ql` | `pacman -Qlq` | `rpm -ql` | `apk info -L` |
| upgrade | `apt update`, `apt upgrade` | `dnf upgrade` | `pacman -Syu` | `zypper update` | `apk update`, `apk upgrade` |

With `-y`, apt and dnf get `-y`, pacman gets `--noconfirm` and zypper gets `--non-interactive` before the
subcommand, which is where zypper wants it. apk never asks, so it gets nothing.

`pacman -Rs` removes the package and the dependencies nothing else needs, which is what most people expect from
"remove". `apt remove` keeps the config files in `/etc`. Pass `-- --purge` to drop them too.

## Per-distro notes

Debian and Ubuntu
: `pkg` uses `apt` when it is there and `apt-get` and `apt-cache` when it is not, as on minimal images. When
  the output of `search` or `info` goes to a pipe or a file, `pkg` runs `apt-cache` even where `apt` exists. Piped
  `apt` adds a warning about its CLI and "Sorting..." lines, and `apt-cache` prints the same packages without
  them.

Fedora, RHEL, Rocky and Alma
: `pkg` uses `dnf`, or `yum` on old releases without it. `dnf upgrade` refreshes the metadata on its own, so there
  is no separate update step.

Arch, Manjaro and EndeavourOS
: `pkg upgrade` runs `pacman -Syu`, the only supported way to update Arch. `pkg install` runs `pacman -S` without
  `-y`, so it never does a partial upgrade. AUR packages are out of scope. Use your AUR helper for those.

openSUSE
: Tumbleweed is updated with `zypper dup`, not `zypper update`. `pkg upgrade` runs `zypper update`, which is right
  for Leap. On Tumbleweed run `sudo zypper dup` yourself instead of `pkg upgrade`.

Alpine
: `apk` never asks questions, so `-y` changes nothing. `pkg files` needs the package installed.

## Safety

- `pkg` never runs a package manager command you did not ask for. `-n` shows the exact commands first.
- `search`, `info`, `owner` and `files` never use sudo and never change anything.
- The package manager asks its usual "Do you want to continue?" question. `pkg` does not answer it for you unless
  you pass `-y`.
- When the package manager fails, `pkg` stops and exits 1 with its exit code, and does not run the next step.
  A failed `apt update` means no `apt upgrade`.

## Pass-through

Options after `--` go to the package manager, in the right place for `install`, `remove`, `search`, `info` and
`upgrade`. `owner` and `files` take none.

```console
$ pkg -n install nginx -- --no-install-recommends
sudo apt install --no-install-recommends nginx
```

On Fedora the same idea is `pkg install nginx -- --setopt=install_weak_deps=False`.

## Needs

One of apt, dnf, yum, pacman, zypper or apk, which every distro has. sudo for `install`, `remove` and `upgrade`
when you are not root, from the `sudo` package. flatpak, snapd and fwupd are optional, for `upgrade --all`.

## Examples

### Install a package

```console
$ pkg install ripgrep
Reading package lists... Done
Building dependency tree... Done
The following NEW packages will be installed:
  ripgrep
Do you want to continue? [Y/n] y
Setting up ripgrep (14.1.1-1+b4) ...
pkg: installed ripgrep 14.1.1-1+b4
```

The lines above the last are apt's own. The last line is read back from the package database, so it only says
installed when the package really is.

### See the commands first

```console
$ pkg -n install ripgrep
sudo apt install ripgrep
$ pkg -n upgrade --all
sudo apt update
sudo apt upgrade
fwupdmgr refresh
fwupdmgr update
```

The same line on Fedora prints `sudo dnf install ripgrep`, and on Arch `sudo pacman -S ripgrep`.

### Which package owns a file

```console
$ pkg owner /usr/bin/curl ls
/usr/bin/curl  curl 8.14.1-2+deb13u4
/usr/bin/ls    coreutils 9.7-3
```

`ls` is a bare name, so `pkg` found it on the `PATH` first. On Debian the database lists `ls` as `/bin/ls` and
`pkg` still finds it.

### A binary nobody installed

```console
$ pkg owner /usr/local/bin/k9s /usr/bin/curl
/usr/local/bin/k9s  no package, installed by hand
/usr/bin/curl       curl 8.14.1-2+deb13u4
$ echo $?
1
```

The exit code is 1 when any path has no package, so a script can check a machine for hand-copied binaries.

### Update everything

```console
$ pkg upgrade --all
Hit:1 http://deb.debian.org/debian trixie InRelease
...
apt       updated
Looking for updates...
Nothing to do.
flatpak   updated
snap      not installed, skipped
No updatable devices
fwupd     updated
pkg: all updated in 48.2s.
     Reboot to use kernel 6.12.107+deb13-amd64.
```

fwupd exits with code 2 when no device has an update. `pkg` counts that as updated.

### List a package's files

```console
$ pkg files coreutils | head -5
/.
/usr
/usr/bin
/usr/bin/[
/usr/bin/arch
```

### See what it found

```console
$ pkg -v install htop
pkg: Debian GNU/Linux 13 (trixie), package manager apt
+ sudo apt install htop
...
pkg: installed htop 3.4.1-5
```

## Troubleshooting

`pkg: no known package manager found, looked for apt, dnf, yum, pacman, zypper and apk`
: The machine has none of them on the `PATH`, as in a distroless container or on NixOS. Use the image's own way
  to add software.

`pkg: apt install stopped with exit 100, see its message above`
: apt printed why above this line. The usual causes are a typo in the name (`E: Unable to locate package`), stale
  package lists (run `pkg upgrade` or `sudo apt update`), or another apt holding the lock.

`Could not get lock /var/lib/dpkg/lock-frontend`
: Another apt is running, often the automatic updater after boot. Wait a minute and try again. Do not delete the
  lock file.

`sudo: a terminal is required to read the password`
: `pkg` ran from a script with no terminal. Run it as root, or give the user a sudo rule for the package manager.

`pkg: installed NAME` with no version
: The package has a different name in the database than the one you typed, such as a virtual package on apt or a
  group on dnf. The install still worked.

`error: target not found` on Arch
: The package is in the AUR, not in the repos. `pkg` does not handle the AUR.

`pkg owner` says `no such file or command`
: The path does not exist, or the bare name is not on your `PATH`. Give the full path.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked. |
| 1 | The package manager failed, with its exit code in the message. For `owner`, a path has no package. For `upgrade --all`, one of the others failed. |
| 2 | Bad usage, such as `install` with no name or `--all` without `upgrade`. |
| 3 | No known package manager, or sudo is missing when it is needed. |

## See also

`cleanup`, `sysinfo`, `apt(8)`, `dnf(8)`, `pacman(8)`, `zypper(8)`, `apk(8)`
