# clip

Copy and paste from the terminal.

## Synopsis

```
command | clip [options] [-- tool options]
clip [options] file
clip -o [--primary]
clip -c [--primary]
```

## Description

`clip` puts text on the clipboard, so you can paste it into a browser, a chat or an editor. It copies whatever you
pipe into it, or the contents of a file you name. `clip -o` prints the clipboard, so you can pipe what you copied
in a browser into a command. `clip -c` empties it.

Every Linux desktop has a different clipboard tool, with different options. `clip` picks the right one for the
session you are in and runs it for you:

| Session | How it knows | Tool |
|---|---|---|
| Wayland | `WAYLAND_DISPLAY` is set | `wl-copy` and `wl-paste` |
| Wayland, `wl-copy` missing | `DISPLAY` is set too | `xclip`, else `xsel`, through XWayland |
| X11 | `DISPLAY` is set | `xclip`, else `xsel` |
| macOS | `pbcopy` exists | `pbcopy` and `pbpaste` |
| SSH, or a console | none of the above | OSC 52, through the terminal |

`clip` copies the bytes exactly. It adds nothing and strips nothing. `echo hello | clip` copies six bytes, with the
newline at the end. Use `printf` when you do not want the newline, such as for a password you will paste into a
login field.

After a copy, one line on stderr says how many bytes went to the clipboard, and with which tool.

### Copying over SSH

On a server you reach over SSH there is no desktop and no clipboard tool. `clip` then sends the text to your
terminal program with an OSC 52 escape code. The terminal on your own machine puts the text on your own clipboard.
That means `cat ~/.ssh/id_ed25519.pub | clip` on a server copies the key to the laptop you are typing on.

Most modern terminals accept OSC 52, among them kitty, WezTerm, Alacritty, foot, iTerm2, Windows Terminal and
xterm. GNOME Terminal and other VTE-based terminals do not. Some turn it off by default for safety. Inside tmux,
`clip` wraps the code so tmux passes it on, and tmux needs `set -g set-clipboard on` or `allow-passthrough on`.

OSC 52 only copies. There is no way to read the clipboard back through the terminal, so `clip -o` over SSH exits 3.
Terminals also limit how much they take, often 100 KB or less of encoded text, so `clip` warns when you send more
than 74 KB.

### Clearing after a while

`--clear-after 30` copies the text, then empties the clipboard 30 seconds later, from a small job in the
background. Use it for a password or a token, so it does not sit on the clipboard for the rest of the day.

Before it clears, the job reads the clipboard back and compares it with what `clip` put there. When you copied
something else in the meantime, it leaves your new copy alone. Over OSC 52 it cannot read the clipboard back, so
it always clears.

## Options

| Option | What it does |
|---|---|
| `-o`, `--out` | Print the clipboard to stdout. |
| `-c`, `--clear` | Empty the clipboard. |
| `--primary` | Use the primary selection instead of the clipboard. That is the text you last selected with the mouse, the one a middle click pastes. macOS has none, and `clip` uses the clipboard there. |
| `--clear-after SECS` | Empty the clipboard again after this many seconds, unless something else was copied by then. |
| `-q`, `--quiet` | Print no lines of its own. Errors still show. |
| `-v`, `--verbose` | Print the tool it picked and the command it runs. |
| `-h`, `--help` | Show the help. |

`--primary` has no short form. In toolbelt `-p` always means a password.

## Pass-through

Options after `--` go to the tool that copies: `wl-copy`, `xclip`, `xsel` or `pbcopy`. Use this for what `clip`
does not cover, such as a type for an image:

```console
$ clip report.png -- --type image/png
```

That line is for `wl-copy`. With `xclip` the same thing is `-- -t image/png`. Nothing goes through with OSC 52.

## Needs

One tool for your session. None over SSH or on macOS.

| Tool | Debian, Ubuntu | Fedora | Arch | openSUSE | Alpine |
|---|---|---|---|---|---|
| `wl-copy`, `wl-paste` | `wl-clipboard` | `wl-clipboard` | `wl-clipboard` | `wl-clipboard` | `wl-clipboard` |
| `xclip` | `xclip` | `xclip` | `xclip` | `xclip` | `xclip` |
| `xsel` | `xsel` | `xsel` | `xsel` | `xsel` | `xsel` |

GNOME and KDE Plasma run Wayland by default on current releases, so `wl-clipboard` is the one most people need.

## Examples

### Copy a public key

```console
$ clip ~/.ssh/id_ed25519.pub
clip: copied 91 bytes with wl-copy
```

### Paste into a command

Copy a manifest in the browser, then:

```console
$ clip -o | kubectl apply -f -
deployment.apps/api configured
service/api unchanged
```

### A secret that does not stay

```console
$ ksecret db-creds DB_PASSWORD | clip --clear-after 30
clip: copied 12 bytes with wl-copy, clearing in 30s
```

### Over SSH

```console
$ echo hello | clip
clip: copied 6 bytes through the terminal with OSC 52
$ clip -o
clip: cannot read the clipboard with no display, OSC 52 only copies
```

### See what it runs

```console
$ echo hi | clip -v
clip: using xclip
+ xclip -selection clipboard -in < /tmp/.clip-uTmXnv/in
clip: copied 3 bytes with xclip
```

### Empty the clipboard

```console
$ clip -c
clip: cleared the clipboard
```

### A missing tool

```console
$ echo hello | clip
clip: needs xclip. Install it with: sudo apt install xclip
```

## Troubleshooting

`clip: needs xclip. Install it with: sudo apt install xclip`
: You are in an X11 session and neither `xclip` nor `xsel` is installed. Install one of them.

`clip: needs wl-copy. Install it with: sudo apt install wl-clipboard`
: You are in a Wayland session with no `wl-copy`. Install `wl-clipboard`.

The copy worked over SSH but nothing is on my clipboard
: Your terminal does not accept OSC 52, or has it turned off. Look for "clipboard" or "OSC 52" in its settings. In
  tmux, add `set -g set-clipboard on` to `~/.tmux.conf`.

`clip: no terminal to send the text to, OSC 52 needs one`
: `clip` ran with no display and no terminal, such as from cron. There is no clipboard to reach.

The text is gone when I close the terminal
: On X11 the program that copied holds the text until something else takes the clipboard. `xclip` and `wl-copy`
  stay in the background for that, so this should not happen. A clipboard manager, such as the one in KDE or
  GNOME, also keeps a copy.

`sudo clip` does not work
: `sudo` drops `DISPLAY` and `WAYLAND_DISPLAY`. Run `clip` as yourself: `sudo cat /etc/file | clip`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It copied, pasted or cleared. |
| 1 | It failed, such as a file that does not exist, or a tool that returned an error. |
| 2 | Bad usage, such as two files, or `-o` with a file. |
| 3 | No clipboard tool fits the session, or `-o` over OSC 52. |

## See also

`genpass`, `ksecret`, `wl-copy(1)`, `xclip(1)`, `xsel(1)`
