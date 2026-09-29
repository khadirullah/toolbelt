# svc

Systemd services in one place.

## Synopsis

```
svc [--user]
svc [--user] NAME
svc [--user] logs NAME [--since TIME] [-- journalctl options]
svc [--user] start|stop|restart|enable|disable NAME [-- options]
```

## Description

systemd splits the work on a service between two commands. `systemctl` starts and stops it and shows its state,
and `journalctl` shows its logs. Each one has a long list of options, and the one screen you want is spread over
both. `svc` gives you that screen, and runs the same two commands underneath.

`svc` with no name lists the units that failed, system and user, each with when it failed, why, and the last error
line from its log. A healthy machine prints `svc: no failed units`. That makes `svc` a good first command after a
boot that felt wrong.

`svc NAME` shows one unit on one screen. It shows the state and since when, whether it starts at boot, the main
process, the memory it uses, how often it restarted, the unit file and any drop-in files that change it, and the
last 4 log lines. The drop-ins matter. A file in `/etc/systemd/system/NAME.service.d/` can change a service
without touching its unit file, and `systemctl cat` is the only other place you would see it.

`svc logs NAME` shows the unit's log, 50 lines by default, or everything since a time with `--since`.

`svc start`, `stop`, `restart`, `enable` and `disable` run `systemctl` with sudo for system units, then read the
unit back and print one line with the result. `systemctl restart` prints nothing when it works and nothing when
the service dies a second later. `svc restart` tells you which of the two happened.

## Unit names

A name without a type means a service, so `svc sshd` means `sshd.service`. Give the type for anything else, such
as `svc logs fstrim.timer` or `svc home.mount`.

When no unit has that name, `svc` looks for the closest name among the unit files and loaded units and suggests
it. It never runs the suggestion.

```console
$ svc crn
svc: no unit named crn. Did you mean cron.service?
```

Debian and Ubuntu call the SSH service `ssh`, while Fedora, Arch and openSUSE call it `sshd`. On Debian `sshd` is
an alias of `ssh`, so both names work there.

## System and user units

System units run for the whole machine and start at boot. User units run for you, start when you log in, and live
in `~/.config/systemd/user/` and `/usr/lib/systemd/user/`. Syncthing, pipewire and many desktop helpers are user
units. `--user` switches every form of `svc` to your user units, and those never need sudo.

With no name, `svc` lists failed units in both. With a name, it looks in the system units unless you pass
`--user`.

## Options

| Option | What it does |
|---|---|
| `--user` | Work on your user units instead of system units. |
| `-n`, `--lines N` | How many log lines to show. 4 with a name, 50 with `logs`. |
| `-s`, `--since TIME` | With `logs`, start at TIME. `1h`, `30min`, `2d`, `today`, `yesterday`, `09:00` and `2026-09-29 09:00` all work. |
| `-y`, `--yes` | Do not ask before stopping ssh or the network over ssh. |
| `-q`, `--quiet` | Only the result line. With a name, one line with the state. |
| `-v`, `--verbose` | Show each `systemctl` and `journalctl` command before it runs. |
| `-h`, `--help` | Show the help. |

A bare number and unit in `--since`, such as `1h`, means that long ago. `svc` passes it to journalctl as `-1h`.
Anything else goes to journalctl as it is.

## What the result words mean

A failed unit shows why it failed, in words, from systemd's `Result` property.

| Result | What `svc` says | What happened |
|---|---|---|
| `exit-code` | `exit code N` | The program ended with an error code. Its log says why. |
| `signal` | `killed by signal N` | Something killed it, often a stop that took too long. |
| `core-dump` | `crashed, signal N` | It crashed. `coredumpctl list` has the dump. |
| `timeout` | `timed out` | It took too long to start or stop. |
| `watchdog` | `watchdog timeout` | It stopped answering systemd's watchdog. |
| `start-limit-hit` | `restarted too often` | It failed and restarted so often that systemd gave up. Run `sudo systemctl reset-failed NAME` after fixing it. |
| `oom-kill` | `killed for using too much memory` | The kernel or systemd-oomd killed it. `mem` shows the kill. |
| `resources` | `could not get its resources` | A folder, user or socket it needs is missing. |

## Safety

- Reading never needs root. `svc`, `svc NAME` and `svc logs NAME` only read.
- Changes to system units go through `sudo systemctl`, so sudo asks for your password as usual.
- When you are logged in over ssh and stop `ssh`, `sshd`, NetworkManager, systemd-networkd or the network
  service, `svc` asks first, since that can cut off the session you are typing in. Without a terminal it
  refuses and exits 4, unless you pass `-y`. `restart` does not ask, because the service comes back and open
  ssh sessions survive it.
- After `start` and `restart`, `svc` reads the state back. A unit that failed right away makes it exit 1 with a
  pointer to `svc NAME`.

## Pass-through

Options after `--` go to journalctl for `logs`, and to systemctl for the actions.

```console
$ svc logs nginx --since 1h -- -o short-precise --grep 'upstream'
$ svc enable syncthing --user -- --now
```

`enable -- --now` enables the unit and starts it in one step.

## Per-distro notes

Debian and Ubuntu
: The SSH service is `ssh`. A user can read the system journal only in the `adm` or `systemd-journal` group.

Fedora, RHEL and openSUSE
: The SSH service is `sshd`. Members of `wheel`, `adm` and `systemd-journal` can read the system journal.

Arch
: The SSH service is `sshd`. Members of `wheel`, `adm` and `systemd-journal` can read the system journal.

Alpine, Void, Gentoo with OpenRC, and containers
: There is no systemd. `svc` exits 3 with `svc: this system does not run systemd, so there are no units to show`.
  Use `rc-service` and `rc-update` on OpenRC.

WSL
: WSL 2 runs systemd only when `systemd=true` is set in `/etc/wsl.conf`.

## Needs

`systemctl` and `journalctl`, from the `systemd` package, on a machine that booted with systemd. `sudo` for
changes to system units.

## Examples

### Anything broken?

```console
$ svc
failed, system
  dnf-makecache.service   Sep 26 15:40, exit code 1
    Curl error (6): Could not resolve host name
failed, user
  none
svc: 1 failed unit. Look closer with: svc dnf-makecache
$ echo $?
1
```

The network was down when the cache refresh ran. That one fixes itself on the next run.

### A healthy machine

```console
$ svc
failed, system
  none
failed, user
  none
svc: no failed units
```

### One unit on one screen

```console
$ sudo svc sshd
sshd.service, OpenSSH server daemon
state     active (running) since Sep 26 09:11, 3d 8h
enabled   yes, vendor preset disabled
main pid  812  /usr/sbin/sshd -D
memory    4.2MB, restarted 0 times
unit      /usr/lib/systemd/system/sshd.service
drop-in   /etc/systemd/system/sshd.service.d/override.conf

last 4 log lines
Sep 29 10:02:11 sshd[48210]: Accepted publickey for khadir
Sep 29 10:02:11 sshd[48210]: session opened
```

The drop-in line shows that someone changed this service outside its unit file.

### Without read access to the journal

```console
$ svc cron
cron.service, Regular background program processing daemon
state     active (running) since 00:17 today, 17h
enabled   yes, vendor preset enabled
main pid  1003  /usr/sbin/cron -f
memory    544KB, restarted 0 times
unit      /usr/lib/systemd/system/cron.service

last 4 log lines
none you can read. Run it with sudo, or join the systemd-journal group.
```

### Logs of a user unit

```console
$ svc --user logs pipewire -n 3
Sep 28 21:42:07 debian systemd[1428]: Stopped pipewire.service - PipeWire Multimedia Service.
-- Boot ec65a11bcba54f11ba663730f12401bc --
Sep 29 00:17:33 debian systemd[1426]: Started pipewire.service - PipeWire Multimedia Service.
```

### Restart and see the result

```console
$ svc -v restart sshd
+ systemctl show -p LoadState --value sshd.service
+ sudo systemctl restart sshd.service
+ systemctl is-active sshd.service
sshd.service restarted, active (running), pid 51203
```

### A restart that fails

```console
$ svc start nginx
nginx.service started, failed (failed)
svc: nginx.service failed right after it started. See why with: svc nginx
$ echo $?
1
```

### Start at boot, now too

```console
$ svc enable syncthing --user -- --now
syncthing.service enabled, it starts at boot
```

### Stopping ssh over ssh

```console
$ svc stop sshd
You are logged in over ssh. Stopping sshd.service may cut this session off. Stop it? [y/N] n
Nothing changed.
```

## Troubleshooting

`svc: this system does not run systemd, so there are no units to show`
: The machine booted with another init, or `svc` runs in a container. `systemctl` may be installed and still
  have no systemd to talk to.

`svc: no unit named NAME. List them with: systemctl list-unit-files`
: No unit is close to that name. Try `systemctl list-unit-files | grep -i PART`. For a user unit, add `--user`.

`none you can read. Run it with sudo, or join the systemd-journal group.`
: System logs are for root and a few groups. Run `sudo svc NAME`, or `sudo usermod -aG systemd-journal $USER` and
  log in again.

`Hint: You are currently not seeing messages from the system.`
: journalctl prints this over `svc --user logs` when you are not in the journal groups. The user unit's own
  lines still show.

`svc: systemctl restart nginx.service failed with exit 1. See why with: svc nginx`
: The unit failed to start. `svc nginx` shows the last log lines, and `svc logs nginx -n 100` more of them.

`Failed to connect to bus` with `--user`
: No user session runs for you, as in `sudo -u otheruser` or a cron job. Log in as that user, or run
  `loginctl enable-linger USER` so their units run without a login.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, and nothing has failed. |
| 1 | A unit has failed, no unit has that name, or a `systemctl` or `journalctl` command failed. |
| 2 | Bad usage, such as an action without a name, or `--since` without `logs`. |
| 3 | No systemctl, or a system that did not boot with systemd. |
| 4 | Refused. Stopping ssh or the network over ssh with no terminal to ask and no `-y`. |
| 5 | You answered no. |

## See also

`proc`, `mem`, `systemctl(1)`, `journalctl(1)`, `systemd.unit(5)`
