# up

Go up n folders, or to the nearest parent with a name.

## Synopsis

```
up [n | name]
```

## Description

`up` moves your shell up the folder tree. It saves you typing `cd ../../..` and counting the dots.

- `up` goes up one folder, the same as `cd ..`.
- `up 3` goes up three folders.
- `up lab` goes up to the nearest folder above you named `lab`.

```console
$ pwd
/home/me/lab/kind/manifests/base
$ up 2
$ pwd
/home/me/lab/kind
```

`up` never goes above `/`. `up 20` from `/home/me` lands in `/`.

### Up to a name

With a name, `up` walks up from the current folder and stops at the first folder whose own name matches exactly.
It only looks at the folders above you, never the one you are in and never the ones beside you.

```console
$ pwd
/home/me/lab/kind/manifests/base
$ up lab
$ pwd
/home/me/lab
```

When two folders above you have the same name, `up` stops at the nearer one. When none has it, `up` prints an
error and you stay where you were.

The match is exact and case-sensitive. `up Lab` does not find `lab`.

### Numbers and names

A word of digits only is a number of levels. Any other word is a name. To go to a parent folder whose name is all
digits, such as `2026`, use `cd` with its path. Leading zeros do not matter, so `up 03` is `up 3`.

### Why it is a shell function

Every program runs in its own process, and a process can only change its own current folder. A script could work
out the folder, but your shell would stay where it was. So `up` is a shell function that runs inside your shell. It
lives in `shell/functions.sh`, with `mkcd`.

Turn both on once with:

```console
$ toolbelt shell enable functions
```

Then open a new terminal, or run `exec $SHELL`.

### Symlinks

`up` follows the path you see in `pwd`, the same way `cd ..` does. When you entered a folder through a symlink,
`up` goes back up through the symlink's side, not through the real folder's parents.

`cd` keeps the folder you left in `OLDPWD`, so `cd -` takes you back to where you were before `up`.

## Options

| Option | What it does |
|---|---|
| `n` | Go up n folders. 1 when you give nothing. |
| `name` | Go up to the nearest parent folder with this name. |
| `--` | The next word is a name, even when it starts with a dash. |
| `-h`, `--help` | Show the help. |

## Pass-through

None. `up` runs `cd`.

## Needs

bash or zsh. `up` uses only shell builtins.

## Examples

### One level

```console
$ up
$ pwd
/home/me/lab/kind/manifests
```

### Several levels

```console
$ up 2
$ pwd
/home/me/lab
```

### Up to a folder by name

```console
$ up lab
$ pwd
/home/me/lab
```

### And back

```console
$ up lab
$ cd -
/home/me/lab/kind/manifests/base
```

### No such parent

```console
$ up nosuch
up: no parent folder named nosuch
$ echo $?
1
```

### Check that it is loaded

```console
$ type up
up is a function
```

## Troubleshooting

`up: command not found`
: The functions are off, or this shell started before you turned them on. Run
  `toolbelt shell enable functions`, then open a new terminal.

`up: no parent folder named lab`
: No folder above you has that exact name. Check the spelling and the case with `pwd`.

`up: give a number of 1 or more`
: `up 0` would stay where you are, so it counts as a mistake.

`up` is already a command or alias on this machine
: Another tool or your own `~/.bashrc` defines `up` too, and the one loaded last wins. `type up` shows which one you
  have. Load toolbelt later in `~/.bashrc`, or remove the other.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The shell moved. |
| 1 | No parent folder has that name, or `cd` failed. |
| 2 | Bad usage, such as `up 0` or two words. |

## See also

`mkcd`, `toolbelt`, `cd(1)`
