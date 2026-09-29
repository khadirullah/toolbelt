# notify-done

Tell you when a long command finishes.

## Synopsis

```
notify-done [options] [--] command [args]
```

## Description

`notify-done` runs a command as normal. When the command ends, it shows a desktop notice with the exit code and
how long the command took, and prints the same on stderr:

```
notify-done: make build finished, exit 0, 4m12s
```

Start a long build, a `terraform apply` or a big copy, switch to another window, and the notice tells you when to
come back. A failed command gets an urgent notice, which most desktops keep on screen until you dismiss it.

Short commands stay silent. When the command took less than 10 seconds, `notify-done` shows nothing at all, so you
can put it in front of anything without getting a notice for every `ls`. `--min` changes the limit.

The command runs in your terminal as it would without `notify-done`. It reads your keyboard, its output goes
straight to the screen, and its exit code comes back to you unchanged. `notify-done` never reads or changes the
output.

### Where the command starts

The command starts at the first word that is not an option of `notify-done`, or right after `--`. Everything from
there on belongs to the command, so `notify-done make -j4 -t` passes `-j4` and `-t` to `make`.

### The title

The notice title is the command, cut short: the command name and the words after it, up to the first option, path
or `name=value`, at most three words. `terraform apply -auto-approve` gives `terraform apply`, and
`rsync -a big/ backup:/srv/big/` gives `rsync`. `-t` sets your own title.

### When there is no desktop

Over SSH, in a console with no graphical session, or when `notify-send` is missing or fails, `notify-done` rings the
terminal bell instead and says so. Most terminal programs flash the tab or the window on a bell, and tmux marks the
window. `--bell` always uses the bell and never tries the desktop.

`notify-done` counts a desktop as present when `DISPLAY` or `WAYLAND_DISPLAY` is set.

## Options

| Option | What it does |
|---|---|
| `-t`, `--title TEXT` | The notice title. The command by default. |
| `--min SECS` | Only notify when the command ran at least this long. 10 by default. `--min 0` always notifies. |
| `--bell` | Ring the terminal bell and skip the desktop notice. |
| `-q`, `--quiet` | Print no lines of its own. The notice or the bell still happens. |
| `-v`, `--verbose` | Print the command line before it runs, and the `notify-send` line. |
| `-h`, `--help` | Show the help. |

## The notice

| The command | Urgency | Text |
|---|---|---|
| exits 0 | normal | `done in 4m12s` |
| exits non-zero | critical | `failed with exit 1 after 17m48s` |

The times use seconds with one decimal under 10 seconds, whole seconds under a minute, then minutes and seconds,
then hours and minutes, as in `0.4s`, `18s`, `4m12s` and `1h07m`.

## Pass-through

None. The words after the options are the command it runs.

## Needs

`notify-send` from libnotify shows the desktop notice. It is optional. Without it you get the bell.

| Distro | Package |
|---|---|
| Debian, Ubuntu | `libnotify-bin` |
| Fedora | `libnotify` |
| Arch | `libnotify` |
| openSUSE | `libnotify-tools` |
| Alpine | `libnotify` |

GNOME, KDE Plasma, Xfce and Cinnamon show the notices with nothing more to set up. A bare window manager such as i3
or sway needs a notification daemon, such as `dunst` or `mako`, running in the session.

## Examples

### A build

```console
$ notify-done make build
go build -o bin/api ./cmd/api
notify-done: make build finished, exit 0, 4m12s
```

The desktop shows "make build" with "done in 4m12s".

### A failure, with your own title

```console
$ notify-done -t "EKS apply" terraform apply -auto-approve
Error: creating EKS Node Group: InvalidParameterException
notify-done: EKS apply failed, exit 1, 17m48s
$ echo $?
1
```

### Over SSH

```console
$ notify-done rsync -a big/ backup:/srv/big/
notify-done: rsync finished, exit 0, 2m03s
notify-done: no desktop, rang the terminal bell instead
```

### A short command stays quiet

```console
$ notify-done -v true
+ true
notify-done: it took 0.0s, under --min 10s, so no notice
```

Without `-v` it prints nothing at all.

### The exact notice it sends

```console
$ notify-done -v --min 0 -t "EKS apply" terraform apply -auto-approve
+ terraform apply -auto-approve
Error: creating EKS Node Group: InvalidParameterException
notify-done: EKS apply failed, exit 1, 17m48s
+ notify-send -u critical -- 'EKS apply' 'failed with exit 1 after 17m48s'
```

### In a pipeline or a script

```console
$ notify-done --min 60 -- ./backup.sh && echo ok
```

`notify-done` exits with the command's code, so `&&`, `||` and `set -e` work as they would without it.

## Troubleshooting

No notice appears, but no bell either
: `notify-send` ran and exited 0, but no daemon showed it. Check that a notification daemon runs, and that your
  desktop does not have "do not disturb" on.

`notify-done: no notify-send, rang the terminal bell instead. Install it with: sudo apt install libnotify-bin`
: You have a desktop, but `notify-send` is missing. Install the package the line names.

`notify-done: no desktop, rang the terminal bell instead` on my own desktop
: `DISPLAY` and `WAYLAND_DISPLAY` are both empty in this terminal, which happens inside `sudo -i`, `su -` and some
  tmux sessions started before you logged in to the desktop. Run `notify-done` as your own user, or update the
  variables with `tmux show-environment`.

The bell makes no sound
: Many terminals turn the audible bell off and show a visual one, or none. Look for "bell" in your terminal's
  settings. The bell goes to stderr, so `2>/dev/null` also hides it.

`notify-done: mycmd: command not found`
: The name is not a program on your `PATH`. Shell aliases and functions only exist in your shell. Run them through
  `bash -ic 'mycmd'`.

## Exit status

| Code | Meaning |
|---|---|
| any | The exit code of the command it ran. |
| 2 | Bad usage, such as no command. |
| 127 | The command does not exist. |

## See also

`again`, `timer`, `notify-send(1)`
