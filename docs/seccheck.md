# seccheck

A quick security check of this machine, with fixes.

## Synopsis

```
seccheck [options]
```

## Description

`seccheck` runs 12 checks on the settings that matter most on a Linux desktop or small server, and gives each
one a verdict. PASS means the setting is safe. WARN means it is weaker than it should be. FAIL means it leaves a
real hole. SKIP means the check could not run here. Every WARN and FAIL comes with the exact command or setting
that fixes it.

It is a first look, not an audit. It checks the common mistakes, such as a firewall that is off, sshd taking
passwords, a private key others can read, or security updates left waiting. It does not scan for malware, read
every config file, or test services from the outside.

`seccheck` only reads. It never changes a setting, never installs anything, never runs `sudo` itself, and never
talks to the network. The fix lines are for you to run once you have read them.

### Running as root or not

Most checks work as a normal user. Two need root to read their files on most distros, `sudo` (for
`/etc/sudoers`) and sometimes `ssh` (when `/etc/ssh/sshd_config` or an included file is private). As a normal
user those checks say SKIP and name the file they could not read, and the summary counts them.

```
SKIP  sudo          needs root to read /etc/sudoers
12 checks: 5 pass, 4 warn, 1 fail, 2 skipped (1 need root)
To run them too: sudo seccheck
```

Run `sudo seccheck` for the full picture. As root, the `~/.ssh` check looks at the home folder of the user who
ran sudo, not at root's own.

### The output

Each result is one line with the verdict, the check name and what it found. Fix lines follow under a WARN or
FAIL, marked `fix`. A check that found several things, such as open ports, lists them under each other.

The last line counts the verdicts. With `-q` it is the only line.

## Checks

| Check | Label | What it reads |
|---|---|---|
| `firewall` | firewall | firewalld, ufw or nftables, whichever is installed |
| `mac` | selinux, apparmor or mac | SELinux mode or the AppArmor module |
| `updates` | updates | pending security updates, from the package lists on disk |
| `ssh` | ssh password, ssh root | the sshd config and every file it includes |
| `secureboot` | secure boot | the UEFI secure boot state |
| `encryption` | encryption | whether `/` sits on a LUKS encrypted device |
| `ports` | open ports | TCP ports listening on the network |
| `sudo` | sudo | sudo rules that need no password |
| `sshdir` | ~/.ssh | modes of `~/.ssh`, private keys and `authorized_keys` |
| `screenlock` | screen lock | the desktop's lock and idle settings |
| `path` | PATH | folders in PATH others can write to |
| `etc` | /etc files | files in `/etc` others can write to |

`seccheck --list` prints the same list with a line on each.

### firewall

`seccheck` looks for firewalld first, then ufw, then an nftables service.

- **firewalld** must be running. The default zone must not be `trusted`, which lets everything in, and must not
  open a range of 100 or more ports. PASS names the zone.
- **ufw** must say `ENABLED=yes` in `/etc/ufw/ufw.conf`.
- **nftables** passes when `nftables.service` is active.

With none of them running, it is a WARN, with the install line for the firewall your distro ships, firewalld on
Fedora and openSUSE and ufw elsewhere.

A firewall matters most on a laptop that joins other people's networks. On a machine behind a home router, it is
a second wall behind the first.

### mac

Mandatory access control limits what a program can do even when it runs as root. Fedora and RHEL use SELinux.
Debian, Ubuntu and openSUSE use AppArmor.

- SELinux `Enforcing` passes. `Permissive` is a WARN, because it logs what it would block but blocks nothing.
  `Disabled` is a WARN with the steps to turn it back on, which include a relabel at the next boot.
- AppArmor passes when the kernel module says it is enabled.
- Neither is a WARN.

`--only selinux` and `--only apparmor` both run this check.

### updates

This check asks the package manager what it would upgrade, without downloading anything and without taking the
package lock, so it is safe to run while an update runs.

| Package manager | Command | Security updates are |
|---|---|---|
| apt | `apt-get -s dist-upgrade` | packages from a `-security` suite |
| dnf | `dnf -C updateinfo list --security` | advisories marked `/Sec.` |
| zypper | `zypper list-patches --category security` | patches marked needed |
| pacman | `pacman -Qu` | not marked, every update counts |
| apk | `apk version -l '<'` | not marked, every update counts |

Any pending security update is a FAIL. The fix is `pkg upgrade`. On apt, `seccheck` also warns when the package
lists are more than 3 days old, because then it cannot know about new updates. On pacman and apk, pending
updates are a WARN, because those tools do not say which ones fix security problems.

The check reads the lists already on disk. It does not refresh them, so run `sudo apt update` or its equal first
for a current answer.

### ssh

This check runs only when sshd is running, as `ssh.service`, `sshd.service` or a socket unit. With no sshd, it
passes.

`seccheck` reads `/etc/ssh/sshd_config` the way sshd does. It follows each `Include` line in place, in order,
and keeps the first value it finds for each setting, because sshd does the same. Lines inside a `Match` block
apply only to some connections, so they are skipped.

- `PasswordAuthentication` must be `no`. The default is yes, so a config that never sets it is a WARN. Password
  logins let anyone on the internet guess passwords. Keys cannot be guessed.
- `PermitRootLogin yes` is a FAIL. The default, `prohibit-password`, lets root in with a key only, which passes.

The fix tells you where to put the line. When the config includes `/etc/ssh/sshd_config.d/`, the fix names
`/etc/ssh/sshd_config.d/00-local.conf`. The `00` matters. sshd keeps the first value it reads, and files in that
folder load in name order, so a line in `50-local.conf` would lose to a `50-cloud-init.conf` that sets the
opposite. After the change, `svc restart ssh` applies it. Keep your current session open until you have tested a
new login.

### secureboot

On a UEFI machine, secure boot must be on. It stops a changed boot loader or kernel from starting. `seccheck`
asks `mokutil --sb-state`, or reads the `SecureBoot` EFI variable when mokutil is missing. A BIOS machine has no
secure boot, so the check says SKIP.

Turning it on is a firmware setting. With it on, kernel modules you build yourself, such as the NVIDIA driver or
VirtualBox, must be signed, which most distros set up for you through a MOK key.

### encryption

`/` must sit on a LUKS encrypted device. `seccheck` asks `findmnt` which device holds `/`, and `lsblk` whether a
`crypt` device is among its parents, which covers LUKS alone, LVM on LUKS and LUKS on LVM.

Without encryption, anyone who takes the laptop or the drive can read every file. The fix is only possible at
reinstall, in the installer, so this is a WARN, not a FAIL.

### ports

`seccheck` runs `ss -Htlnp` and lists every TCP port that listens on the network. Ports on `127.0.0.1` and `::1`
only take connections from this machine, so it leaves them out. sshd is left out too, because the ssh check
covers it.

Each port shows the address, the program and its pid. As a normal user, `ss` cannot see the owner of a port
started by another user, so that line says `owner hidden, root can see it`.

Any such port is a WARN. The fix is to bind the program to `127.0.0.1` in its own config, or to stop it with
`port NUMBER --kill`. A web server meant for the network is fine, and the WARN is the reminder that it is open.

### sudo

Every sudo rule should ask for a password. A `NOPASSWD` rule lets anything that runs as your user become root at
once, including a malicious script or a browser exploit. `seccheck` reads `/etc/sudoers` and every file in
`/etc/sudoers.d`, and fails on the first `NOPASSWD` or `!authenticate` it finds. It also fails when a sudoers
file is writable by anyone but root.

The fix is `sudo visudo -f FILE`, which checks the syntax before it saves. Never edit sudoers with a plain
editor, because one typo locks you out of sudo.

### sshdir

`~/.ssh` should be mode 700 and each private key 600.

- A folder others can write to is a FAIL, because they could add a key to `authorized_keys`.
- A private key others can read is a FAIL. ssh refuses such a key anyway.
- `authorized_keys` writable by others is a FAIL.
- A folder others can list, such as 755, is a WARN.

`seccheck` finds private keys by their first line, which contains `PRIVATE KEY`. It reads only that line, never
the key.

### screenlock

The screen should lock on its own when you walk away. `seccheck` reads the desktop's settings.

| Desktop | Where it reads |
|---|---|
| GNOME, Budgie, Pantheon, Unity | `org.gnome.desktop.screensaver lock-enabled` and `org.gnome.desktop.session idle-delay`, through gsettings |
| Cinnamon | the `org.cinnamon.desktop` keys of the same names |
| MATE | `org.mate.screensaver` |
| KDE Plasma | `Autolock` and `Timeout` in `kscreenlockerrc`, through kreadconfig5 or kreadconfig6 |

A lock that is off, or a screen that never goes idle, is a WARN. So is an idle time over 15 minutes. With no
known desktop, such as on a server or over ssh, the check says SKIP.

### path

No folder in PATH may be writable by others, because anyone could put a program there named `ls` or `sudo`. An
empty entry or `.` in PATH is a WARN, because then a command in the current folder runs before the real one.

### etc

No file in `/etc` may be writable by others. `seccheck` runs `find /etc -xdev -type f -perm -0002` and fails on
the first file it finds. Such a file is almost always a mistake from a `chmod 777`.

## Options

| Option | What it does |
|---|---|
| `--only CHECKS` | Run only these checks, comma separated, such as `ssh,ports`. The names are in the table above. `selinux` and `apparmor` run `mac`. `secure-boot`, `ssh-dir` and `screen-lock` work too. |
| `--strict` | Exit 1 on a WARN as well as on a FAIL. |
| `--list` | List the checks and what each one reads, and run none. |
| `-q`, `--quiet` | Show only the summary line. |
| `-v`, `--verbose` | Show each check as it starts, and each command before it runs. |
| `-h`, `--help` | Show the help. |

## Per-distro notes

- **Debian and Ubuntu.** No firewall is on by default, except Ubuntu, which installs ufw but leaves it off. Both
  pass for AppArmor. The ssh service is `ssh.service`.
- **Fedora.** firewalld and SELinux are on by default. The ssh service is `sshd.service`. The updates check uses
  dnf's cached advisories, so run `sudo dnf check-update` first when the cache is old.
- **RHEL, Rocky and Alma.** As Fedora. Security advisories are marked Important or Critical, which the updates
  line counts separately.
- **Arch.** Nothing is on by default. pacman does not mark security updates, so every pending update is a WARN.
  `arch-audit` gives a security-only list.
- **openSUSE.** firewalld and AppArmor are on by default. zypper marks security patches.
- **Alpine.** The updates check uses apk and counts every update. There is no desktop, so the screen lock check
  says SKIP.

## Needs

Nothing is required. Each check uses the tool it needs when it is present and says SKIP when it is not.

- `ss`, from iproute2, for ports.
- `systemctl`, for firewall, ssh and nftables state.
- `findmnt` and `lsblk`, from util-linux, for encryption.
- `mokutil`, for secure boot, or the EFI variables when it is missing.
- `gsettings` or `kreadconfig5`/`kreadconfig6`, for the screen lock.
- The package manager, for updates.

## Examples

### A desktop virtual machine

```console
$ seccheck
WARN  firewall      no firewall is running
      fix  sudo apt install ufw, then
           sudo ufw enable
PASS  apparmor      enabled
FAIL  updates       60 security updates pending
      fix  pkg upgrade
PASS  ssh           sshd is not running
SKIP  secure boot   this machine boots with BIOS, not UEFI
WARN  encryption    / is not on LUKS
      fix  only at reinstall, turn on disk encryption
           in the installer
WARN  open ports    8820/tcp on 0.0.0.0, python pid 390057
                    8870/tcp on 0.0.0.0, python pid 969585
                    8894/tcp on 0.0.0.0, python3 pid 1750199
                    8840/tcp on 0.0.0.0, python3 pid 649883
      fix  bind them to 127.0.0.1, or stop them: port 8820 --kill
SKIP  sudo          needs root to read /etc/sudoers
PASS  ~/.ssh        no ~/.ssh folder
WARN  screen lock   the screen never goes idle, so it never locks
      fix  set a blank screen delay in the desktop settings
PASS  PATH          no world-writable folders
PASS  /etc files    no world-writable files
12 checks: 5 pass, 4 warn, 1 fail, 2 skipped (1 need root)
To run them too: sudo seccheck
$ echo $?
1
```

The 60 security updates are the one FAIL. Four development web servers listen on every address, which the ports
check points out.

### A cloud server with a risky sshd and sudo setup

```console
$ sudo seccheck --only ssh,sudo
WARN  ssh password  sshd is running and takes passwords
      fix  add "PasswordAuthentication no" to
           /etc/ssh/sshd_config.d/00-local.conf, then
           svc restart ssh
FAIL  ssh root      PermitRootLogin yes, root can log in with a password
      fix  add "PermitRootLogin prohibit-password" to
           /etc/ssh/sshd_config.d/00-local.conf, then
           svc restart ssh
FAIL  sudo          NOPASSWD for %wheel in /etc/sudoers.d/90-wheel
      fix  sudo visudo -f /etc/sudoers.d/90-wheel, drop NOPASSWD
3 checks: 0 pass, 1 warn, 2 fail
```

`PermitRootLogin yes` came from `50-cloud-init.conf`. The fix goes in `00-local.conf` so sshd reads it first.

### Just the ssh folder and PATH

```console
$ seccheck --only sshdir,path
WARN  ~/.ssh        folder 755, others can list it
      fix  chmod 700 /home/khadir/.ssh
PASS  PATH          no world-writable folders
2 checks: 1 pass, 1 warn, 0 fail
```

### See what a check runs

```console
$ seccheck -v --only ports
seccheck: checking ports
+ ss -Htlnp
WARN  open ports    3000/tcp on 0.0.0.0, node pid 8120
                    8080/tcp on *, owner hidden, root can see it
      fix  bind them to 127.0.0.1, or stop them: port 3000 --kill
1 check: 0 pass, 1 warn, 0 fail
```

Port 8080 belongs to another user, so a normal user cannot see its owner.

### A one-line result for a script

```console
$ seccheck -q; echo $?
12 checks: 5 pass, 4 warn, 1 fail, 2 skipped (1 need root)
1
$ seccheck -q --only ssh,path --strict; echo $?
2 checks: 2 pass, 0 warn, 0 fail
0
```

### The list of checks

```console
$ seccheck --list
firewall    firewalld, ufw or nftables is on, and lets in little
mac         SELinux is enforcing or AppArmor is on
updates     no security updates wait, from the package lists on disk
ssh         sshd takes no passwords and no root password logins
secureboot  secure boot is on, on a UEFI machine
encryption  / sits on a LUKS encrypted device
ports       no TCP port listens on the network, other than sshd
sudo        every sudo rule asks for a password, needs root to read
sshdir      ~/.ssh is 700 and private keys are 600
screenlock  the desktop locks the screen when idle
path        no folder in PATH is world-writable, and . is not in it
etc         no file in /etc is world-writable
```

## Troubleshooting

**`seccheck: no check named X`** The name is not in the list. Run `seccheck --list` for the names.

**The ssh check says SKIP, needs root.** One of the sshd config files is readable by root only, which is common
for files that cloud-init writes. Run `sudo seccheck --only ssh`.

**The updates check passes, but I know updates are out.** The package lists on disk are old. Refresh them with
`sudo apt update`, `sudo dnf check-update` or `sudo zypper refresh`, then run the check again.

**A port I need shows as open.** That is the point of the WARN. If the service is meant for the network, keep
it, and make sure the firewall only lets in the addresses that should reach it.

**The screen lock check says SKIP over ssh.** It needs the desktop session's settings, which an ssh session
cannot see. Run it in a terminal on the desktop.

**I fixed PasswordAuthentication, but it still warns.** An earlier file sets it to yes, and sshd keeps the
first value. Put your line in `00-local.conf` as the fix says, and check with `sudo sshd -T | grep -i password`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | No check failed. With `--strict`, no check failed or warned. |
| 1 | A check failed. With `--strict`, a check failed or warned. |
| 2 | Bad usage, such as an unknown check name or a word that is not an option. |

SKIP never changes the exit status.

## See also

`port`, `svc`, `pkg`, `fixperms`, `sshd_config(5)`, `sudoers(5)`, `ss(8)`
