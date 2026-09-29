# timer

Countdown or stopwatch in the terminal.

## Synopsis

```
timer [options] duration [message]
timer [options] --at HH:MM [message]
timer
```

## Description

`timer` counts down from a duration such as `25m`, or to a clock time with `--at 17:30`. The line on screen
updates every second with the time left and the time it ends:

```
timer: 18:42 left, ends at 14:55, stand up
```

At zero it rings the terminal bell, prints a done line, and shows a desktop notice with your message, so you see
it even when the terminal is behind other windows.

With no duration, `timer` is a stopwatch. It shows the time running, Enter records a lap, and Ctrl+C stops it and
prints the total.

`timer` keeps time by the clock, not by counting sleeps. When the laptop sleeps in the middle of a countdown, the
countdown catches up the moment it wakes. A timer that should have ended during the sleep ends right away.

### Durations

| You type | It means |
|---|---|
| `90` | 90 seconds |
| `90s` | 90 seconds |
| `25m` | 25 minutes |
| `2h` | 2 hours |
| `1h30m` | 1 hour and 30 minutes |
| `1m30s` | 1 minute and 30 seconds |

The units go in the order h, m, s, each at most once. A bare number is seconds.

### Clock times

`--at 17:30` counts down to 17:30 today. When 17:30 has already passed, it counts to 17:30 tomorrow. The time is
24-hour, `HH:MM`, in your local time zone. `--at 7:05` works too.

### The time left

Under an hour the time left shows as minutes and seconds, `18:42`. From an hour up it shows hours too, `2:58:10`.

When stderr is not a terminal, such as in a script or with its output sent to a file, `timer` prints the start
line once, instead of rewriting it every second, and the done line at the end.

### The stopwatch

```
00:01:12.4  lap 1
00:03:05.9  lap 2, +00:01:53.5
00:03:40.2  stopped
```

Each lap line shows the total time and, from the second lap on, the time since the lap before. The lap lines and
the stopped line go to stdout, so you can save them with `timer > laps.txt`.

When stdin is not a terminal, each line of input is a lap and the end of input stops the stopwatch.
`printf '\n\n' | timer` records two laps and stops.

## Options

| Option | What it does |
|---|---|
| `--at HH:MM` | Count down to this time today, or tomorrow when it has passed. |
| `--bell` | Ring the bell only, with no desktop notice. |
| `-q`, `--quiet` | Hide the countdown line. The done line still shows. |
| `-v`, `--verbose` | Print the `notify-send` line at the end. |
| `-h`, `--help` | Show the help. |

The words after the duration are the message. It shows on the countdown line, the done line and the notice. With
no message the notice says, for example, `25m is up`. Put `--` before a message that starts with a dash.

## Pass-through

None. Only the notice uses another tool.

## Needs

`date` and `sleep` from coreutils or BusyBox. `notify-send` from libnotify shows the desktop notice. It is optional.
Without it, or with no desktop, you get the bell only.

| Distro | Package for notify-send |
|---|---|
| Debian, Ubuntu | `libnotify-bin` |
| Fedora | `libnotify` |
| Arch | `libnotify` |
| openSUSE | `libnotify-tools` |
| Alpine | `libnotify` |

## Examples

### A pomodoro

```console
$ timer 25m "stand up"
timer: 18:42 left, ends at 14:55, stand up
```

The line counts down in place. At zero:

```console
timer: done at 14:55, stand up
```

### Until a meeting

```console
$ timer --at 17:30 standup call
timer: 2:58:10 left, ends at 17:30, standup call
```

### Stopped early

```console
$ timer --at 23:30 standup call
timer: 2:59:55 left, ends at 23:30, standup call
^C
timer: stopped with 2:59:53 left
$ echo $?
1
```

### A stopwatch with laps

```console
$ timer
timer: Enter records a lap, Ctrl+C stops
00:01:12.4  lap 1
00:03:05.9  lap 2, +00:01:53.5
00:03:40.2  stopped
```

### After another command

```console
$ make build; timer --bell 10m "check the deploy"
```

### A duration it cannot read

```console
$ timer 25x
timer: cannot read 25x. Use 90, 90s, 25m, 1h30m or --at 17:30
Try 'timer --help' for the options.
```

## Troubleshooting

`timer: cannot read 25x. Use 90, 90s, 25m, 1h30m or --at 17:30`
: The duration has a unit `timer` does not know, or the units are out of order. Write `1h30m`, not `30m1h`.

`timer: cannot read 25:00 as a time. Use HH:MM, such as 17:30`
: `--at` takes a clock time from `00:00` to `23:59`. For a duration of 25 minutes, write `25m`.

No notice at zero
: The bell rang but no desktop notice appeared. Either `notify-send` is missing, or there is no desktop, such as
  over SSH. `timer -v` shows the `notify-send` line when it runs. See `notify-done` for more on notices.

The countdown line fills the screen with copies
: The terminal is too narrow for the line, so it wraps. Make the window wider, or use a shorter message.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The countdown reached zero, or the stopwatch stopped. |
| 1 | You stopped a countdown with Ctrl+C before zero. |
| 2 | Bad usage, such as a duration it cannot read. |

## See also

`notify-done`, `again`, `sleep(1)`
