# note

Jot a line into today's notes file.

## Synopsis

```
note [options] text ...
note [options] [-l days | -s pattern [-- grep options] | -e]
```

## Description

`note` writes one line, with the time, into a notes file for today. You type `note` and the thought, and go back
to work. No editor opens and no app starts.

```console
$ note api crashloop was a missing DATABASE_URL
note: added to ~/notes/2026-09-29.md
```

With no text, `note` prints today's notes. `-l` prints the last few days, `-s` searches every note you have ever
written, and `-e` opens today's file in your editor.

### The files

Notes live in `~/notes`, one Markdown file per day, named by the date:

```
~/notes/2026-09-28.md
~/notes/2026-09-29.md
```

Each file starts with the date as a heading, then one bullet per note, with the time it was written:

```
# 2026-09-29

- 09:14 renew the example.com cert before 2026-10-11
- 11:02 api crashloop was a missing DATABASE_URL
```

They are plain text. `grep`, `git`, any editor and any Markdown viewer work on them. You can edit or delete lines
by hand, add headings or paragraphs, and `note` keeps working. Put the folder in a git repository, or in a synced
folder, and your notes follow you.

`-d` or the `NOTES_DIR` variable moves the folder. `note` makes it on the first note. It reads only files named
`YYYY-MM-DD.md` and leaves anything else in the folder alone.

### Adding

All words after the options become one note, joined with spaces, so you rarely need quotes. Quote the text when it
holds characters your shell treats specially, such as `#`, `*`, `?`, `;`, `&`, `(`, `$` or a quote:

```console
$ note 'check why $PATH lost /usr/local/bin'
```

A note is always one line. Line breaks in the text become spaces. `note` appends, so it never changes or removes a
line that is already there.

Text that starts with a dash goes after `--`: `note -- -5 degrees in the server room`.

### Searching

`-s` searches every day file with `grep`, newest day first, and newest note first within a day. Each match prints
as the date, the time and the text, one line each, so the result reads well and pipes well:

```
2026-09-29 11:02 api crashloop was a missing DATABASE_URL
2026-09-17 16:40 grafana crashloop, data dir not writable
```

The pattern is a `grep` basic regular expression, and it matches case as you typed it. Options after `--` go to
`grep`, so `-- -i` ignores case, `-- -w` matches whole words and `-- -E` takes an extended pattern.

## Options

| Option | What it does |
|---|---|
| `-l`, `--last DAYS` | Print the notes of the last DAYS days, today included, oldest first. `-l 1` is today, `-l 7` the last week. |
| `-s`, `--search PAT` | Search every note, newest first. Exits 1 when nothing matches. |
| `-e`, `--edit` | Open today's file in your editor. `note` makes the file first when it is new. |
| `-d`, `--dir PATH` | Keep notes in this folder instead of `~/notes`. |
| `-q`, `--quiet` | Print no lines of its own. The notes and search results still print. |
| `-v`, `--verbose` | Print the file it reads or writes, in full. |
| `-h`, `--help` | Show the help. |

Only one of `-l`, `-s` and `-e` at a time, and none of them with text to add.

## Environment

| Variable | What it does |
|---|---|
| `NOTES_DIR` | The notes folder, when `-d` is not given. `~/notes` by default. |
| `VISUAL`, `EDITOR` | The editor `-e` opens, in that order. It may have options, such as `code -w`. Without either, `note` tries `nano`, then `vi`. |

## Pass-through

Options after `--` go to `grep` for `-s`:

```console
$ note -s kind -- -i
```

Without `-s`, the words after `--` are text for a new note.

## Needs

`grep`, and `date` and `awk`, which every Linux system has, BusyBox included. `-l` works out the dates with
`date -d`, which BusyBox reads too.

## Examples

### Add a note

```console
$ note renew the example.com cert before 2026-10-11
note: added to ~/notes/2026-09-29.md
```

### Read today's notes

```console
$ note
# 2026-09-29

- 09:14 renew the example.com cert before 2026-10-11
- 11:02 api crashloop was a missing DATABASE_URL
```

### The last two days

```console
$ note -l 2
# 2026-09-28

- 17:05 kind cluster needs 4 GB for 3 nodes

# 2026-09-29

- 09:14 renew the example.com cert before 2026-10-11
- 11:02 api crashloop was a missing DATABASE_URL
```

### Search every note

```console
$ note -s crashloop
2026-09-29 11:02 api crashloop was a missing DATABASE_URL
2026-09-17 16:40 grafana crashloop, data dir not writable
```

### Search with any case

```console
$ note -s CRASH -- -i
2026-09-29 11:02 api crashloop was a missing DATABASE_URL
2026-09-17 16:40 grafana crashloop, data dir not writable
```

### Nothing found

```console
$ note -s nothing
note: nothing matches nothing
$ echo $?
1
```

### Notes for one project

```console
$ note -d ~/work/eks-notes node group needs the AmazonEKS_CNI_Policy
note: added to ~/work/eks-notes/2026-09-29.md
```

Put `export NOTES_DIR=~/work/eks-notes` in a project's `.envrc` to make it the default there.

### Write more in the editor

```console
$ note -e
```

## Troubleshooting

`note: no editor found, set EDITOR, such as EDITOR=nano`
: `VISUAL` and `EDITOR` are empty, and neither `nano` nor `vi` is installed. Add `export EDITOR=nano`, or the
  editor you use, to `~/.bashrc`.

My note lost a word such as `$HOME` or `*`
: The shell expanded it before `note` saw it. Put the text in single quotes.

`note -l 7` shows fewer days than 7
: It shows only the days that have a file. Days with no notes have none.

A note has the wrong time
: `note` uses the time zone of the machine. Check it with `date`. On a server, `TZ=Asia/Kolkata note ...` sets it
  for one note.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, including when there are no notes to show. |
| 1 | A search found nothing, or a file could not be written. |
| 2 | Bad usage, such as `-l 0` or `-s` together with text. |
| 3 | `grep` is missing, for `-s`. |

## See also

`recent`, `grep(1)`
