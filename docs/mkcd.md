# mkcd

Make a folder with its parents, and move into it.

## Synopsis

```
mkcd [--] folder
```

## Description

`mkcd` does in one step what you would otherwise type as `mkdir -p folder && cd folder`. It makes the folder,
together with every missing folder above it, and moves your shell into it.

```console
$ mkcd ~/lab/kind/manifests
$ pwd
/home/me/lab/kind/manifests
```

When the folder already exists, `mkcd` just moves into it. It never empties, replaces or changes a folder that is
already there.

### Why it is a shell function

Every program runs in its own process, and a process can only change its own current folder. A script called
`mkcd` could make the folder and move into it, but your shell would stay where it was the moment the script ended.
So `mkcd` is a shell function. It runs inside your shell and moves the shell itself.

That is also why `mkcd` has no file in `bin/`. It lives in `shell/functions.sh`, with `up`, and your shell loads
that file when it starts.

### Turning it on

Run this once:

```console
$ toolbelt shell enable functions
```

That adds the `functions` setting to `~/.config/toolbelt/shell` and makes sure `~/.bashrc` or `~/.zshrc` loads
toolbelt's `shell/init.sh`. Open a new terminal, or run `exec $SHELL`, and `mkcd` is there:

```console
$ type mkcd
mkcd is a function
```

`toolbelt shell disable functions` turns it off again.

### How it treats the name

- A name with no `/` at the start is inside the current folder. `mkcd` puts `./` in front of it before it runs `cd`,
  so a `CDPATH` you have set never sends you to a folder of the same name somewhere else.
- `~`, `$HOME` and globs are expanded by your shell before `mkcd` sees them, as with any command.
- A name that starts with a dash goes after `--`: `mkcd -- -drafts`.
- When a file, not a folder, has the name already, `mkcd` stops with an error and changes nothing.
- When `mkdir` fails, such as for a folder you have no rights to write in, `mkcd` stops and you stay where you
  were.

`cd` keeps the folder you left in `OLDPWD`, so `cd -` takes you back.

## Options

| Option | What it does |
|---|---|
| `--` | The next word is the folder, even when it starts with a dash. |
| `-h`, `--help` | Show the help. |

## Pass-through

None. `mkcd` runs `mkdir -p` and `cd`.

## Needs

bash or zsh, and `mkdir` from coreutils. `shell/functions.sh` uses only syntax both shells share, so the same file
works in either.

## Examples

### A new project folder

```console
$ mkcd ~/lab/kind/manifests
$ pwd
/home/me/lab/kind/manifests
```

### A folder that exists already

```console
$ mkcd /tmp
$ pwd
/tmp
```

### A name that starts with a dash

```console
$ mkcd -- -drafts
$ pwd
/home/me/-drafts
```

### A file is in the way

```console
$ touch notes
$ mkcd notes
mkcd: notes exists and is not a folder
```

### No rights to write

```console
$ mkcd /opt/tools
mkdir: cannot create directory '/opt/tools': Permission denied
mkcd: cannot make /opt/tools
```

### Check that it is loaded

```console
$ type mkcd
mkcd is a function
```

## Troubleshooting

`mkcd: command not found`
: The functions are off, or this shell started before you turned them on. Run
  `toolbelt shell enable functions`, then open a new terminal.

`mkcd: give one folder name`
: `mkcd` takes exactly one folder. Quote a name with spaces: `mkcd "my project"`.

`sudo mkcd` does not work
: `sudo` runs programs, and `mkcd` is a function in your shell. Make the folder with `sudo mkdir -p`, then `cd`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The folder exists and the shell is in it. |
| 1 | The folder could not be made or entered. |
| 2 | Bad usage, such as no folder or two folders. |

## See also

`up`, `toolbelt`, `mkdir(1)`
