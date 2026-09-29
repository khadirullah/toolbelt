# autounpack

Unpack archives as they land in ~/Downloads.

## Synopsis

```
autounpack [status]
autounpack enable [dir] [-- unpack options]
autounpack disable | log
autounpack run dir [-- unpack options]
```

## Description

`autounpack` watches a folder and runs `unpack` on each archive that lands in it. Download a `.zip` and a moment
later its folder sits next to it. The archive always stays. `autounpack` passes `-k` to `unpack` every time and
refuses `--rm`, so a file it did not expect never disappears.

`autounpack enable` writes a systemd user service and starts it, so the watch runs whenever you are logged in,
with no terminal open and no root. `disable` stops it and removes the service. `status` says whether it is on,
which folder it watches and what it did last. `log` shows what it unpacked, and what `unpack` refused.

The folder is `~/Downloads` by default, or the download folder your desktop set in `~/.config/user-dirs.dirs`.
Name another with `autounpack enable DIR`.

`autounpack run DIR` is the watch itself. The service runs it, and you can run it in a terminal to try a folder
out before you enable it. Ctrl+C stops it.

## Commands

| Command | What it does |
|---|---|
| `status` | On or off, the folder, the unpack options and the last run. The default command. |
| `enable [DIR]` | Write the service for DIR, or `~/Downloads`, then enable and start it. Run it again to change the folder or options. |
| `disable` | Stop the service and remove it. Archives and folders already unpacked stay. |
| `log` | The last lines of the log, one per archive. |
| `run DIR` | Watch DIR in this terminal until Ctrl+C. |

## Options

| Option | What it does |
|---|---|
| `-n`, `--lines N` | With `log`, how many lines to show. The default is 20. |
| `-q`, `--quiet` | Print only errors. |
| `-v`, `--verbose` | Print each step, and each real command before it runs. |
| `-h`, `--help` | Print the help. |

## What it unpacks

`autounpack` reacts when a file is closed after writing, or moved into the folder. Browsers write a download to a
temporary name and rename it at the end, and the rename is the moment `autounpack` sees it.

It skips these:

- partial downloads, ending in `.part`, `.crdownload`, `.download`, `.partial`, `.opdownload` or `.tmp`
- hidden files, whose names start with a dot
- later parts of a split set, such as `.part2.rar`, `.r00`, `.z01` or `.002`. The first part, `.part1.rar` or
  `.001`, unpacks the whole set.
- files that are not archives, by extension

For everything else, it waits until the size stops changing for two seconds, then runs `unpack -k ./NAME` inside
the folder. The same file with the same size and time is only unpacked once, even when two events arrive for it.

`unpack` decides where the files go, by its usual rules. An archive with one top folder unpacks to that folder,
and a loose one gets a folder named after the archive. When the name is taken, `unpack` picks the next free name
such as `photos-1/`, so nothing is overwritten.

## The log

Each archive gets one line in `~/.local/state/toolbelt/autounpack.log`, with the time, the name and what
happened:

```
2026-09-29 17:04  app-1.4.tgz  -> app-1.4/ (920B, 5 files, 0.0s)
2026-09-29 17:04  evil.tar  refused, 1 unsafe path. Nothing was written.
```

`refused` means `unpack` stopped at a safety check, and `failed` means the archive or the tool failed. Both come
with `unpack`'s own message. When `notify-send` is installed, a refusal or failure also pops up a desktop
notice, since nobody is watching the terminal.

## The service

`enable` writes `~/.config/systemd/user/autounpack.service` and runs `systemctl --user daemon-reload`, then
`enable` and `restart` on it. The unit runs `autounpack run DIR` with any unpack options, and systemd restarts it
if it stops. It starts at login, from `default.target`.

A user service runs only while you are logged in. To keep it running after logout, or on a machine you only reach
over SSH, turn on lingering once with `loginctl enable-linger $USER`.

The service writes nothing outside the watched folder, the log and the unit. `disable` removes the unit, so
nothing is left behind.

## Pass-through

Options after `--` go to `unpack` on every run, after `-k`. `enable` stores them in the service, and `status`
shows them.

```
autounpack enable -- -d
autounpack enable ~/Inbox -- --only '*.pdf'
```

`--rm` is refused, since `autounpack` never deletes an archive. `-k` is always there already.

## Needs

A systemd user session for `enable`, `inotifywait` from inotify-tools, and `unpack` from toolbelt with the tools
for the formats you download. `notify-send` is optional and shows desktop notices for refusals and failures.

| Tool | apt | dnf | pacman | zypper | apk |
|---|---|---|---|---|---|
| inotifywait | inotify-tools | inotify-tools | inotify-tools | inotify-tools | inotify-tools |
| systemctl | systemd | systemd | systemd | systemd | none |
| notify-send | libnotify-bin | libnotify | libnotify | libnotify-tools | libnotify |

Per distro:

- **Debian, Ubuntu, Fedora, Arch and openSUSE.** systemd runs a user session for every desktop login, so `enable`
  works out of the box. On a server, turn on lingering first.
- **Alpine, Void, Gentoo with OpenRC, and other systems without systemd.** `enable` exits 3 and names the init
  system. Run `autounpack run ~/Downloads` from your session's autostart instead, such as a line in
  `~/.xprofile` or your desktop's autostart settings.
- **WSL.** systemd runs only when `/etc/wsl.conf` turns it on. Without it, use `autounpack run` in a terminal.

## Examples

### Turn it on

```console
$ autounpack enable
autounpack: enabled autounpack.service for your user
autounpack: watching ~/Downloads. Archives stay after unpacking.
```

### Check on it

```console
$ autounpack
autounpack: on, watching ~/Downloads
autounpack: unpack options: -d
autounpack: last run 2026-09-29 17:04, evil.tar
```

### See what it did

`evil.tar` held a path that climbs out of the folder, `../evil.txt`, so `unpack` refused it and wrote nothing.

```console
$ autounpack log
2026-09-29 17:02  site.zip  -> site/ (60KB, 3 files, 0.0s)
2026-09-29 17:04  app-1.4.tgz  -> app-1.4/ (920B, 5 files, 0.0s)
2026-09-29 17:04  evil.tar  refused, 1 unsafe path. Nothing was written.
```

### Try a folder in the terminal first

```console
$ autounpack run ~/Downloads
autounpack: watching ~/Downloads with ~/toolbelt/bin/unpack -k. Ctrl+C stops.
2026-09-29 17:02  app-1.4.tgz  -> app-1.4/ (920B, 5 files, 0.0s)
2026-09-29 17:02  site.zip  -> site/ (60KB, 3 files, 0.0s)
```

`big.iso.part` landed in the same folder while the browser was still downloading, and `autounpack` left it alone.

### Every step of enable

```console
$ autounpack -v enable ~/Downloads -- -d
autounpack: writing ~/.config/systemd/user/autounpack.service
+ systemctl --user daemon-reload
+ systemctl --user enable autounpack.service
Created symlink ~/.config/systemd/user/default.target.wants/autounpack.service -> ~/.config/systemd/user/autounpack.service.
+ systemctl --user restart autounpack.service
autounpack: enabled autounpack.service for your user
autounpack: watching ~/Downloads. Archives stay after unpacking.
```

### It never deletes

```console
$ autounpack enable -- --rm
autounpack: autounpack never deletes archives, so it does not pass --rm to unpack
Try 'autounpack --help' for the options.
```

### Turn it off

```console
$ autounpack disable
autounpack: off. Archives already unpacked stay where they are.
$ autounpack
autounpack: off
autounpack: last run 2026-09-29 17:04, evil.tar
```

## Troubleshooting

**"needs a systemd user session, this machine runs openrc"** There is no systemd here. Start
`autounpack run DIR` from your login or desktop autostart instead.

**"systemctl --user cannot reach one"** You are logged in over SSH or from a script with no user session. Run
`loginctl enable-linger $USER` once, log in again, and repeat `enable`.

**"~/Inbox does not exist. Make it first, or name another folder"** `enable` only watches a folder that is there.

**status says "enabled for ~/Downloads, but the service is failed"** The watch stopped. Run
`journalctl --user -u autounpack.service` to see why. A missing `inotifywait` or a folder that was deleted are
the usual causes.

**An archive did not unpack.** Check `autounpack log` first. When it has no line for the file, the name was
skipped as a partial download, a later part or not an archive. When the browser saved it straight to the final
name without a rename, `autounpack` still sees the close, but only if the watch was running at the time.

**inotifywait says the upper limit on inotify watches is reached.** Raise `fs.inotify.max_user_watches` with sysctl.
`autounpack` watches only one folder, so another program is using up the limit.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The command worked. A refused or failed archive during `run` is logged, and the watch goes on. |
| 1 | The folder does not exist, or systemctl failed to enable or start the service. |
| 2 | Bad usage, including an unknown command and `--rm` after `--`. |
| 3 | inotifywait or unpack is missing, or there is no systemd user session. |

## See also

`unpack`, `squash`, `inotifywait(1)`, `systemctl(1)`, `systemd.unit(5)`
