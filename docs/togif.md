# togif

Turn a video clip into a small GIF.

## Synopsis

```
togif [options] video [-- ffmpeg options]
```

## Description

`togif` cuts a part of a video and writes it as a GIF beside the video. It suits a bug report, a README or a chat
message, where a video would not play inline.

```
demo.mp4 0:12 to 0:16 -> demo.gif (1.7MB, 48 frames, 480px, 2.1s)
```

A GIF holds at most 256 colours per frame. Made the plain way, with `ffmpeg -i demo.mp4 demo.gif`, it uses one fixed
palette for everything, and the picture comes out grainy and banded. `togif` runs ffmpeg twice instead:

1. The first run looks at every frame of the part you picked and builds the best 256 colours for it, with
   ffmpeg's `palettegen` filter.
2. The second run draws each frame with that palette, with `paletteuse`.

It also scales the picture down to 480 pixels wide and drops the frame rate to 12 a second. A GIF has no real
compression between frames, so its size grows with the width squared, the frame rate and the length. Those two
defaults keep a few seconds of screen recording near 1 or 2 MB.

The video itself is never changed. The GIF goes beside it as `name.gif`, or `name-1.gif` when that name is taken.

## Options

| Option | What it does |
|---|---|
| `-s`, `--start TIME` | Where to start. The default is the beginning. |
| `-d`, `--duration SECS` | How long the GIF runs, in seconds, such as `4` or `2.5`. |
| `-t`, `--to TIME` | Where to stop, instead of `-d`. |
| `-w`, `--width PX` | Width in pixels, 480 by default. A narrower video keeps its own width. The height follows. |
| `-f`, `--fps N` | Frames a second, from 1 to 50. The default is 12. |
| `--loop` | Play again and again. By default the GIF plays once and stops on the last frame. |
| `-o`, `--out NAME` | Name the GIF yourself. |
| `-y`, `--yes` | Allow a GIF longer than 60 seconds. |
| `-q`, `--quiet` | Show only the result line. |
| `-v`, `--verbose` | Show both ffmpeg commands before they run. |
| `-h`, `--help` | Show the help. |

With no `-d` and no `-t`, the GIF runs to the end of the video. A length past the end stops at the end.

## Times

| You type | It means |
|---|---|
| `12` | 12 seconds in |
| `12.5` | 12 and a half seconds in |
| `0:12` | 12 seconds in, as a player shows it |
| `1:05` | 1 minute 5 seconds in |
| `1:02:03` | 1 hour, 2 minutes and 3 seconds in |

Copy the times from the player, the way you watched the clip. `togif -s 1:05 -t 1:09` gives the 4 seconds between
them.

## Safety checks

- A GIF over 60 seconds is refused with exit 4 unless you add `-y`. A minute of GIF at the default settings runs to
  tens of MB, which is rarely what anyone wants. Pick the part you need with `-s` and `-d`.
- `togif` never overwrites. Without `-o` it picks a free name. With `-o` and a name that is taken, it stops with
  exit 4.
- ffmpeg writes into a hidden temp folder beside the GIF. The GIF appears under its name only when both runs
  worked, so a failed run leaves nothing behind.

## Size

A GIF has no real compression between frames, so the width counts twice. Half the width gives about a quarter of
the size. The frame rate and the length count once each. Film and camera footage comes out larger than a screen
recording of the same length, since every pixel changes in every frame.

To make a GIF smaller, lower `-w` first, then `-f`, then cut the part shorter.

## Pass-through

Options after `--` go to both ffmpeg runs, as output options. For example:

```console
$ togif -d 4 demo.mp4 -- -threads 2
```

`-threads 2` keeps ffmpeg from taking every core. Do not pass `-vf` or
`-filter_complex`. `togif` builds its own filter, and ffmpeg refuses two.

## Needs

`ffmpeg`, and `ffprobe` from the same package. The package is `ffmpeg` on Debian, Ubuntu, Arch and Alpine,
`ffmpeg-free` on Fedora and `ffmpeg-7` on openSUSE.

## Examples

### Four seconds from the middle

```console
$ togif -s 0:12 -d 4 demo.mp4
demo.mp4 0:12 to 0:16 -> demo.gif (1.7MB, 48 frames, 480px, 2.1s)
```

### From one time to another, looping

```console
$ togif -s 5 -t 9.5 -w 320 -f 10 --loop demo.mp4
demo.mp4 0:05 to 0:09.5 -> demo-1.gif (410KB, 45 frames, 320px, 1.4s)
```

### The ffmpeg commands

```console
$ togif -v -s 0:12 -d 4 demo.mp4
+ ffmpeg -nostdin -hide_banner -loglevel error -y -ss 0:12 -t 4 -i demo.mp4 -vf 'fps=12,scale='\''min(480,iw)'\'':-1:flags=lanczos,palettegen' ./.togif-0dSakf/palette.png
+ ffmpeg -nostdin -hide_banner -loglevel error -y -ss 0:12 -t 4 -i demo.mp4 -i ./.togif-0dSakf/palette.png -lavfi 'fps=12,scale='\''min(480,iw)'\'':-1:flags=lanczos[x];[x][1:v]paletteuse' -loop -1 ./.togif-0dSakf/out.gif
demo.mp4 0:12 to 0:16 -> demo.gif (1.7MB, 48 frames, 480px, 2.1s)
```

### A whole short clip

```console
$ togif bug.webm
bug.webm 0:00 to 0:07.2 -> bug.gif (2.4MB, 86 frames, 480px, 3.0s)
```

### A long video without a part picked

```console
$ togif talk.mp4
togif: talk.mp4 from 0:00 is 9:42 long, over the 60s limit
togif: refused. Pick a part with -s and -d, or add -y
```

### A start past the end

```console
$ togif -s 1:05 -d 3 demo.mp4
togif: demo.mp4 is 0:30.5 long, so a start at 1:05 is past the end
```

### A name of your own

```console
$ togif -s 0:12 -d 4 -o docs/img/login-bug.gif demo.mp4
demo.mp4 0:12 to 0:16 -> docs/img/login-bug.gif (1.7MB, 48 frames, 480px, 2.2s)
```

## Troubleshooting

The GIF is too big
: Lower the width first, since it counts twice. `-w 320` is about half the size of 480. Then lower the frame rate,
  and cut the part shorter.

The GIF looks choppy
: Raise `-f` to 15 or 20. Screen recordings with a moving mouse show it most.

The colours band or flicker
: A GIF has 256 colours per frame, and gradients and video footage need more. Shorter parts help, since the
  palette covers fewer scenes.

`togif: ffmpeg could not read X. Run it with -v to see the command`
: Run the first command from `-v` by hand without `-loglevel error` to see ffmpeg's message.

`togif: ffmpeg wrote an empty GIF, check the start and the length`
: The part holds no video frames, often a start inside the last fraction of a second.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The GIF was written. |
| 1 | It failed. The file is missing, the start is past the end, or ffmpeg failed. |
| 2 | Bad usage, such as `-d` and `-t` together, or a time it cannot read. |
| 3 | ffmpeg or ffprobe is missing. |
| 4 | Refused. Over 60 seconds without `-y`, or the `-o` name is taken. |

## See also

`shrink`, `ffmpeg(1)`, `ffprobe(1)`
