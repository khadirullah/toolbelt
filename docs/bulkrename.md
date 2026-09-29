# bulkrename

Rename many files with a pattern or in your editor.

## Synopsis

```
bulkrename [options] 's/from/to/' file ...
bulkrename [options] -e | --lower | --upper | --spaces | --number file ...
bulkrename --undo
```

## Description

`bulkrename` gives many files new names in one go. You describe the new names with a sed expression, with your
editor, or with a few ready transforms such as `--lower`. It then shows every old and new name, asks once, and
renames them all.

It checks every rename before it moves anything. Two files that would get the same name, a new name that
already belongs to another file, and a name with a `/` in it all stop the run with exit 4, and nothing is renamed.
A rename never overwrites a file.

Only the file name changes. A file in `photos/2026/` stays in that folder, and the expression never sees the
folder part, so `s/^IMG_/trip-/` works on `photos/2026/IMG_4410.jpg` the same as on `IMG_4410.jpg`.

After each run, `bulkrename` saves the list of renames. `bulkrename --undo` puts the old names back, from any
folder.

## Options

### How the new names are made

| Option | What it does |
|---|---|
| `'s/from/to/'` | A sed expression. It runs once per name, with extended regular expressions, as in `sed -E`. |
| `-e`, `--edit` | Open the names in `$VISUAL` or `$EDITOR`, or `vi` when neither is set. Change the names, keep one per line and the same order, then save and quit. |
| `--lower` | Make names lower case. |
| `--upper` | Make names upper case. |
| `--spaces` | Turn each run of spaces into one `-`. |
| `--number` | Add a counter at the first `#` in the name, or in front as `01-name`. |
| `--start N` | The first number, 1 by default. Turns on `--number`. |
| `--width N` | Pad numbers to N digits, from 1 to 9. Turns on `--number`. |

### Running

| Option | What it does |
|---|---|
| `-n`, `--dry-run` | Show the old and new names and stop. |
| `-y`, `--yes` | Rename without asking. The checks still refuse a clash. |
| `--undo` | Put back the names from the last run. |
| `-q`, `--quiet` | Show only the result line. |
| `-v`, `--verbose` | Show each step, and each `sed` and `mv` before it runs. |
| `-h`, `--help` | Show the help. |

## How it makes the names

The steps run in a fixed order, so you can combine them:

1. The sed expression, or the names you typed in the editor.
2. `--spaces`.
3. `--lower` or `--upper`.
4. `--number`.

So `bulkrename --lower --spaces 'Tax Return 2025.PDF'` gives `tax-return-2025.pdf`.

With `--number`, the counter takes the place of the first `#` in the new name. That is why the sed expression in
`--number 's/.*\./scan-#./'` puts a `#` where the number goes. With no `#`, the counter goes in front, followed by a
`-`. Files are numbered in the order you name them, and a shell glob such as `*.png` sorts them by name.

The default width is the number of digits in the last number, and at least 2. Ten files get `01` to `10`. A
hundred get `001` to `100`. With `--width 1`, numbers have no padding.

A sed expression is anything that looks like `s/a/b/` or `y/abc/xyz/`, with any delimiter, such as `s|a|b|`. You
can chain commands with `;`. The expression must give exactly one line per name. `bulkrename` refuses with exit 4
when it gives more or fewer, for example after a `d` or an `a` command.

## Safety checks

`bulkrename` checks every rename first, and refuses the run with exit 4 when any of these is true:

- Two files would get the same new name.
- A new name belongs to a file that exists and is not part of the rename.
- A new name is empty, `.` or `..`.
- A new name holds a `/`. Moving files to another folder is a job for `mv`.
- A name you gave holds a line break.

It prints each problem, then `refused, nothing renamed.` You fix the pattern and run it again.

Some renames depend on each other. Swapping `a.txt` and `b.txt`, or turning `f1 f2 f3` into `f2 f3 f4`, would
overwrite a file if done in the wrong order. `bulkrename` sees these swaps and chains. It moves the files that are
in the way to a temp name such as `.bulkrename-1087492-0` in the same folder first, then gives every file its
new name. A rename that changes only the case, such as `README.MD` to `readme.md`, also goes through a temp name
on file systems that ignore case, such as a USB stick with FAT or exFAT.

Every move runs as `mv -n`, which never overwrites. After each move, `bulkrename` checks that the file really moved.
When a move fails halfway, it moves the files it already renamed back and exits 1.

The sed expression runs with `sed --sandbox` when your sed has it, which GNU sed does. The sandbox refuses the `w`,
`r` and `e` commands, so an expression cannot write files or run programs. BusyBox sed, on Alpine, has no sandbox.
There `bulkrename` runs only `s` and `y` commands, split by `;`, with the `g`, `p`, `i`, `I`, `m`, `M` or number
flags. Anything else exits 2 before sed runs.

The question needs a terminal. In a script, pass `-y`. Without a terminal and without `-y`, `bulkrename` exits 4.

## The undo list

Each run that renames something saves the pairs of old and new full paths to
`~/.local/state/toolbelt/bulkrename-undo`, or `$XDG_STATE_HOME/toolbelt/bulkrename-undo` when that is set. Only the
last run is kept.

`bulkrename --undo` reads it, shows the renames, asks, and renames back through the same checks. The undo is a
rename run of its own, so it saves a new list. A second `--undo` redoes the first run.

When a file from the last run has gone, `--undo` warns and skips it. When a file with the old name has since
appeared, the check refuses, the same as for any other clash.

## Pass-through

`bulkrename` takes no options for `sed` or `mv`. Put `--` before file names that start with a dash.

```console
$ bulkrename 's/^-//' -- -old.txt
```

## Needs

`sed` and `mv`. Both come with every distro, from the `sed` and `coreutils` packages, and BusyBox has both. `-e`
needs a terminal and an editor. Set `EDITOR=nano` in `~/.bashrc` if you do not use vi. For VS Code, use
`EDITOR="code --wait"`, so `bulkrename` waits until you close the file.

## Examples

### Rename camera files

```console
$ bulkrename 's/^IMG_/trip-/' IMG_*.jpg
IMG_4410.jpg -> trip-4410.jpg
IMG_4411.jpg -> trip-4411.jpg
IMG_4412.jpg -> trip-4412.jpg
Rename 3 files? [y/N] y
3 files renamed.
```

### Undo it

```console
$ bulkrename --undo
trip-4410.jpg -> IMG_4410.jpg
trip-4411.jpg -> IMG_4411.jpg
trip-4412.jpg -> IMG_4412.jpg
Rename 3 files? [y/N] y
3 files renamed.
```

### Clean up names from a scanner or a bank

```console
$ bulkrename -n --lower --spaces *.PDF
Bank  Statement.PDF -> bank-statement.pdf
Tax Return 2025.PDF -> tax-return-2025.pdf
Dry run, nothing renamed.
```

The two spaces in `Bank  Statement` became one `-`.

### Number files

```console
$ bulkrename --number 's/.*\./scan-#./' scan*.png
scan3.png -> scan-01.png
scan4.png -> scan-02.png
Rename 2 files? [y/N] y
2 files renamed.
$ bulkrename -n --start 7 --width 3 IMG_4410.jpg IMG_4411.jpg
IMG_4410.jpg -> 007-IMG_4410.jpg
IMG_4411.jpg -> 008-IMG_4411.jpg
Dry run, nothing renamed.
```

### Rename in your editor

```console
$ bulkrename -e IMG_*.jpg
IMG_4411.jpg -> beach.jpg
IMG_4412.jpg -> sunset.jpg
1 name stays the same.
Rename 2 files? [y/N] y
2 files renamed.
```

The editor showed three lines. Two were changed, and the line for `IMG_4410.jpg` was left as it was.

### Swap two names

```console
$ bulkrename -v 's/^a/X/; s/^b/a/; s/^X/b/' a.txt b.txt
+ sed --sandbox -E -e 's/^a/X/; s/^b/a/; s/^X/b/'
a.txt -> b.txt
b.txt -> a.txt
Rename 2 files? [y/N] y
+ mv -n -- /home/khadir/notes/b.txt /home/khadir/notes/.bulkrename-1087492-1
+ mv -n -- /home/khadir/notes/a.txt /home/khadir/notes/.bulkrename-1087492-0
+ mv -n -- /home/khadir/notes/.bulkrename-1087492-0 /home/khadir/notes/b.txt
+ mv -n -- /home/khadir/notes/.bulkrename-1087492-1 /home/khadir/notes/a.txt
2 files renamed.
```

### A clash is refused

```console
$ bulkrename 's/-v[0-9]+//' report-v1.pdf report-v2.pdf
bulkrename: report-v1.pdf and report-v2.pdf would both become report.pdf
bulkrename: refused, nothing renamed.
$ echo $?
4
```

## Troubleshooting

`bulkrename: IMG_4410.jpg would become trip-4410.jpg, which already exists`
: Another file already has that name. Move it, or change the pattern so the names differ.

``bulkrename: sed could not read the expression: -e expression #1, char 6: unterminated `s' command``
: The expression has a mistake. Quote it with single quotes, so the shell leaves `*`, `$` and `\` alone.

`bulkrename: sed could not read the expression: ... e/r/w commands disabled in sandbox mode`
: The expression tried to write a file or run a command. Use only `s` and `y`.

`bulkrename: the list had 3 names and now has 2. Keep one name per line, nothing renamed`
: A line was deleted in the editor. Keep a line for each file, and leave the ones you do not want to change as
  they are.

`bulkrename: nothing to undo, no run is recorded in /home/khadir/.local/state/toolbelt/bulkrename-undo`
: No run has renamed anything yet, or the state folder was cleaned.

Nothing matched
: `sed -E` uses extended regular expressions. Write `s/(IMG)_([0-9]+)/\2-\1/`, not `s/\(IMG\)_/.../`. Test the
  pattern with `-n` first.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, or there was nothing to rename. |
| 1 | It failed. A file is missing, a move failed, or there is nothing to undo. |
| 2 | Bad usage, such as a broken sed expression or `--lower` with `--upper`. |
| 3 | `sed` or `mv` is missing. |
| 4 | Refused. The names clash, the editor list changed length, or there is no terminal to ask in. |
| 5 | You answered no. |

## See also

`mv(1)`, `sed(1)`, `rename(1)`
