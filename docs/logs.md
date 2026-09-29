# logs

Errors and warnings from the journal, grouped by unit.

## Synopsis

```
logs [options] [UNIT ...] [-- journalctl options]
logs [options] -f FILE
```

## Description

`logs` answers one question. What went wrong on this machine, and where? It reads the systemd journal for the
current boot, keeps the entries at warning level or worse, and groups them by the unit that wrote them. You get
one short table of units with errors and one of units with warnings, each with a count, the time of the last
entry and the newest message.

A plain `journalctl -p warning -b` on a desktop prints hundreds of lines, most of them the same message again
and again. `logs` folds those repeats into one row with a count, so a unit that failed 40 times takes one line,
not 40. The unit that failed most sits at the top of its table.

Without a journal, `logs` reads a classic syslog file instead, such as `/var/log/syslog` on Debian or
`/var/log/messages` on older Red Hat systems. With `-f` it reads any log file you name, such as the nginx error
log, in the same way.

`logs` only reads. It never clears, rotates or vacuums the journal, and it never changes a setting.

### How it groups entries

Each journal entry names the service it came from in the `_SYSTEMD_UNIT` field. `logs` uses that name with
`.service` taken off, so `NetworkManager.service` shows as `NetworkManager`. Other unit kinds keep their suffix,
such as `dev-sda.device` or `backup.timer`.

Some entries come from places that are not a useful unit name.

- Programs in your desktop session run under `user@1000.service`. `logs` uses the user unit instead, such as
  `pipewire.service`, and marks the row with `(user)`, as in `pipewire (user)`.
- Programs in a scope or slice, such as an app started from the desktop, have a random scope name. `logs` uses
  the program name from `SYSLOG_IDENTIFIER` instead.
- Kernel messages have no unit. They all go in one row named `kernel`.

### How it decides what is an error

The journal gives every entry a priority from 0 to 7. `logs` counts priorities 0 to 3 (emerg, alert, crit and
err) as errors and priority 4 (warning) as a warning. It asks journalctl for priority 4 and worse only, so the
lower levels (notice, info, debug) never reach it.

A syslog file has no priority field. There `logs` looks at the words in each message. A line that says error,
fail, fatal, panic, critical, segfault, denied or refused counts as an error. A line that says warn counts as a
warning. Other lines are skipped.

### Log files it reads with `-f`

| Format | A line looks like | Group name | Level from |
|---|---|---|---|
| syslog, RFC 3339 | `2026-09-29T09:12:01+00:00 host sshd[5]: error: ...` | the program, `sshd` | the words |
| syslog, classic | `Sep 29 09:12:01 host sshd[5]: error: ...` | the program, `sshd` | the words |
| nginx error log | `2026/09/29 09:12:01 [error] 812#812: *5 connect() failed ...` | the folder, `nginx` | `[error]` |
| Apache 2.4 error log | `[Tue Sep 29 09:12:01.123456 2026] [proxy:error] [pid 812] ...` | the folder, `apache2` | `[proxy:error]` |

For nginx and Apache the level in brackets decides. emerg, alert, crit and error are errors, warn is a warning,
and notice, info and debug are skipped. The group name is the folder the log sits in, such as `nginx`, `apache2`
or `httpd`, when the file has a plain name such as `error.log` or `error_log`. Otherwise it is the file name
without `.log`, so `/srv/app/worker.log` groups as `worker`.

Lines in any other format are skipped, so a JSON log or a Java stack trace gives "nothing at warning or above".
Classic syslog lines have no year. `logs` takes them as this year.

### What it shows for each unit

For a unit with errors, the row shows the count and the time of the last entry, then the newest message on the
next line, indented. With `-n 3` it shows the 3 newest different messages. The same message repeated counts once
toward that number, so you see 3 different lines, not the same line 3 times.

For a unit with warnings, the row shows the count and the newest message on the same line, to keep the warnings
table short. With `-n`, the other messages go on the lines under it.

Times from today show as `17:27`. Older times show the date, as `Sep 28 21:42`.

Long messages wrap to the width of the terminal. When the output goes to a file or a pipe, lines stay whole,
unless the `COLUMNS` variable sets a width.

### The first line

The first line says which part of the journal `logs` read and how many units it found.

```
this boot, since 00:16. 1 unit with errors, 5 with warnings.
```

With `--since`, the line says `since 15:40` instead. With `-b` it names the boot and when it ran. With
`--priority err` it leaves out the warnings count.

### Earlier boots

`-b -1` reads the boot before this one, `-b -2` the one before that, and so on. For an earlier boot, `logs` adds
one line that says whether the boot ended with a clean shutdown. It reads the last 40 entries of that boot and
looks for the lines systemd writes on the way down, such as `Reached target shutdown.target` or
`Journal stopped`.

```
it did not shut down cleanly, the last entry is Sep 28 21:42:08
```

A boot that did not shut down cleanly lost power, froze, or crashed hard enough that the journal could not
write its last lines. The errors just before that last entry are often the cause.

### Reading only your own entries

On most distros a normal user reads only their own part of the journal. The system part needs membership of the
`systemd-journal` group, or root. When `logs` sees that you cannot read the system journal, it says so and shows
the command that fixes it for good.

```
logs: you can read only your own entries. To see the system ones, run:
  sudo usermod -aG systemd-journal khadir, then log in again
```

It still shows what you can read. Run `sudo logs` for a one-off look instead.

## Options

| Option | What it does |
|---|---|
| `-s`, `--since TIME` | Start at this time instead of at boot. TIME is a count and a unit, such as `30m`, `2h`, `3d` or `1w`, or a word or date that `date -d` reads, such as `today`, `yesterday` or `2026-09-28 18:00`. |
| `-b`, `--boot N` | Read an earlier boot. `0` is this boot, `-1` the one before, `-2` the one before that. A positive number counts from the oldest boot the journal holds, as in journalctl. |
| `--priority P` | The lowest level to show. `warning` is the default. `err` shows errors only. `emerg`, `alert` and `crit` narrow it further. The numbers 0 to 4 work too. |
| `-k`, `--kernel` | Kernel messages only, the same as `journalctl -k`. |
| `-g`, `--grep PATTERN` | Keep only messages that match PATTERN, an extended regular expression. A pattern in lower case matches any case. A pattern with a capital letter matches case exactly. |
| `-n`, `--lines N` | How many different messages to show per unit. 1 by default. |
| `--user` | Read your user journal instead of the system one. |
| `-f`, `--file FILE` | Read a log file instead of the journal. |
| `-q`, `--quiet` | Show only the tables, without the first line or the shutdown line. |
| `-v`, `--verbose` | Show every step, and the journalctl command before it runs. |
| `-h`, `--help` | Show the help. |

Any word that is not an option is a unit name. `logs NetworkManager sshd` reads only those two units. With
`--user`, the names are user units.

Priority is a long option only. In toolbelt `-p` always means password, so `logs -p err` is an unknown option
and exits with status 2.

`-f` works with `--since`, `--priority`, `-k`, `-g` and `-n`. It does not work with `-b`, unit names or options
after `--`, because a plain log file has no boots and no units.

## Pass-through

Options after `--` go to journalctl as they are, after the options `logs` sets itself. Use them for journal
fields that `logs` has no option for.

```
logs -- --facility=auth
logs -- _UID=1000
logs -- --identifier=sudo
```

`logs` still asks for JSON output and still groups the result, so options that change the output format, such
as `-o short`, have no effect.

## Per-distro notes

- **Debian and Ubuntu.** The journal is on disk in `/var/log/journal` on Debian 12 and later and on Ubuntu. On
  Debian 11 and older it lives in `/run/log/journal` and is lost at every reboot, so `-b -1` finds nothing. To
  keep it, run `sudo mkdir -p /var/log/journal` and reboot. Debian 12 and later no longer install rsyslog, so
  there is no `/var/log/syslog` unless you add it.
- **Fedora, RHEL and CentOS Stream.** The journal is on disk. `/var/log/messages` exists only when rsyslog is
  installed.
- **Arch.** The journal is on disk. There is no syslog file by default.
- **openSUSE.** The journal is on disk on current releases. Older Leap versions kept it in memory, like old
  Debian.
- **Alpine.** Alpine uses OpenRC and busybox syslog, not systemd, so there is no journalctl. `logs` reads
  `/var/log/messages` instead, by the message words.
- **Containers.** Most containers have no journal and no syslog file. `logs` exits with status 3 and says it
  needs journalctl. Read the container's output with `docker logs` or `podman logs` on the host.

## Needs

- `journalctl`, from systemd. Every systemd distro has it.
- Without journalctl, a readable `/var/log/syslog`, `/var/log/messages` or, with `-k`, `/var/log/kern.log`.
- `awk`, `sort` and `date`, which every system has.

## Examples

### What went wrong since boot

```console
$ logs
this boot, since 00:16. 1 unit with errors, 5 with warnings.
ERRORS
sudo (user)                   4x  last 17:27
  pam_unix(sudo:auth): auth could not identify password for [test]
WARNINGS
MiniBrowser (user)           28x  Libgcrypt warning: missing initialization - please fix the
                                  application
spice-vdagent                20x  error message: Cannot invoke method; proxy is for the well-known
                                  name org.gnome.Mutter.DisplayConfig without an owner, and proxy
                                  was constructed with the G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START flag
gnome-keyring-daemon          3x  discover_other_daemon: 1
gnome-keyring-daemon (user)   2x  asked to register item
                                  /org/freedesktop/secrets/collection/login/1, but it's already
                                  registered
wireplumber (user)            2x  wp-node: failed to create node from factory 'spa-node-factory'
```

The name column grows to fit the longest unit name, up to 34 characters. The four sudo errors came from a
script that ran `sudo` with no terminal to ask for the password.

### Errors only, with more lines per unit

```console
$ logs --priority err -n 2
this boot, since 11:14. 2 units with errors.
ERRORS
dnf-makecache            3x  last 12:13
  Failed to download metadata
  Curl error (6): Couldn't resolve host name
kernel                   1x  last 12:13
  iwlwifi 0000:03:00.0: Microcode SW error detected. Restarting.
```

The cache refresh failed 3 times with 2 different messages. The Curl error came first, so the network was down,
and the metadata failure followed from it.

### The boot before this one

```console
$ logs -b -1 --priority err
boot -1, Sep 27 10:59 to Sep 28 21:42, 1 day. 2 units with errors.
it did not shut down cleanly, the last entry is Sep 28 21:42:08
ERRORS
dnf-makecache            1x  last Sep 28 21:40
  Failed to download metadata
kernel                   1x  last Sep 28 21:42
  i915 0000:00:02.0: [drm] *ERROR* CPU pipe A FIFO underrun
```

The machine froze. The last kernel error came 6 seconds before the end and names the graphics driver.

### The last two hours of one unit

```console
$ logs --since 2h NetworkManager
since 15:40. 0 units with errors, 1 with warnings.
WARNINGS
NetworkManager           2x  dhcp4 (wlp3s0): request timed out
```

### A web server's own log

```console
$ logs -f /var/log/nginx/error.log --since today
error.log, since 00:00. 1 unit with errors, 1 with warnings.
ERRORS
nginx                    1x  last 09:12
  connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1
WARNINGS
nginx                    1x  an upstream response is buffered to a temporary file
```

nginx writes its own format with a level in brackets, and no program name. `logs` takes the level from the line
and names the group after the log's folder, here `nginx`.

### See the journalctl command

```console
$ logs -v --since 1h
+ journalctl --no-pager -q -o json --output-fields=PRIORITY,_SYSTEMD_UNIT,_SYSTEMD_USER_UNIT,SYSLOG_IDENTIFIER,_COMM,_TRANSPORT,MESSAGE -p 4 --since -1h
since 16:40. 1 unit with errors, 0 with warnings.
ERRORS
sudo (user)                   2x  last 17:27
  pam_unix(sudo:auth): auth could not identify password for [test]
```

Copy the command without the JSON options to read the full entries yourself.

### A quiet journal

```console
$ logs --since 10m
nothing at warning or above, since 17:34.
```

## Troubleshooting

**It shows only a few entries, all marked (user).** You cannot read the system journal. `logs` prints the fix
at the top. Add yourself to the `systemd-journal` group with `sudo usermod -aG systemd-journal $USER`, then log
out and in again. Until then, `sudo logs` reads everything.

**`-b -1` says the boot is not available.** The journal holds only the current boot. Either it lives in memory
(see the Debian note above) or it was vacuumed. `journalctl --list-boots` shows the boots it has.

**`logs: cannot read the time ...`** `--since` did not understand the time. Use a count and unit such as `2h`,
a word such as `yesterday`, or a full date and time such as `2026-09-28 18:00`. Put quotes around a value with a
space in it.

**`logs: needs journalctl.`** There is no journalctl and no syslog file. This is normal in a container. On
Alpine, start the syslog service with `rc-service syslog start` so `/var/log/messages` exists.

**A unit you expect is missing.** It may log at notice or info level, which `logs` does not read. Look at
everything it wrote with `journalctl -u NAME -b`.

**The same problem shows under two names.** A program started by hand and the same program started as a
service write different unit fields. Search both with `-g`, as in `logs -g 'connection refused'`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, whether or not it found errors. |
| 1 | journalctl failed, such as for a boot the journal does not hold, or a `-f` file could not be read. |
| 2 | Bad usage, such as an unknown priority, `-n 0`, a time it cannot read, or `-b` with `-f`. |
| 3 | No journalctl and no syslog file to read instead. |

`logs` exits 0 when it finds errors. It reports, it does not judge. Use `svc` for a check that exits 1 when a
service has failed.

## See also

`svc`, `boottime`, `schedules`, `journalctl(1)`, `systemd.journal-fields(7)`
