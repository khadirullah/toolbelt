# recent

List the files changed lately, newest first.

## Synopsis

```
recent [options] [time] [path ...] [-- find tests]
```

## Description

`recent` answers the question "what did I just touch?" It lists the files under a folder that changed in the last
hour, newest first, with the clock time, the age, the size and the path. With no path it looks in the current
folder.

```
17:10   3m ago     360B  src/app.py
17:01  12m ago     600B  tests/test_app.py
16:44  29m ago    1.3KB  README.md
16:27  46m ago     600B  pyproject.toml
4 files changed in the last 1h
```

The time can be any window. `recent 30m` looks back 30 minutes, `recent 2d` two days. `--since` takes a date or
a time of day instead, such as `--since 2026-09-01` or `--since "yesterday 18:00"`.

The clock time shows only the hour and minute when the whole window falls on today. When the window reaches back
into an earlier day, every line shows the month and day too, as in `09-28 20:15`.

"Changed" means the content changed. `recent` reads the modification time, the one `ls -l` shows. Reading a file
does not count, and neither does a change of owner or permissions.

`recent` only reads. It never deletes, moves or changes a file.

## Options

| Option | What it does |
|---|---|
| `time` | How far back to look, as a number and a unit. The default is `1h`. |
| `--since WHEN` | Look back to a date or a time, anything `date -d` understands, such as `2026-09-01`, `"2026-09-01 14:00"` or `yesterday`. A window such as `3d` works here too. |
| `-n`, `--count N` | Show at most N entries. The default is 50. The last line says how many there were in all. |
| `-a`, `--all` | Include hidden files and folders, `.git`, `node_modules`, `.cache` and the trash. |
| `-t`, `--type f\|d` | `f` lists files, the default. `d` lists folders. |
| `--only PATTERN` | Show only names that match, such as `'*.conf'`. Can repeat. |
| `-x`, `--exclude PAT` | Leave out names that match. A folder that matches is skipped whole. Can repeat. |
| `-q`, `--quiet` | Show only the list and the summary line. |
| `-v`, `--verbose` | Show the start of the window and the `find` command before it runs. |
| `-h`, `--help` | Show the help. |

A pattern without a `/` matches a name, the way `find -name` does. A pattern with a `/` matches the whole path, the
way `find -path` does. Quote patterns that hold `*`, so the shell does not expand them first.

## Times

| You type | It means |
|---|---|
| `45s` | the last 45 seconds |
| `30m` or `30` | the last 30 minutes |
| `2h` | the last 2 hours |
| `3d` | the last 3 days |
| `1w` | the last 7 days |
| `2026-09-28` | since midnight at the start of that day |

A bare number counts minutes. A date as the first word works like `--since`.

The first word that looks like a time is the time, unless a file or folder of that name exists. When you have a
folder called `2d`, `recent 2d` lists what changed inside it in the last hour. Write `recent 1h 2d` or
`recent --since 2d 2d` to mean both.

## What it skips

By default `recent` leaves out:

- Every hidden file and folder, whose name starts with a dot. That covers `.git`, `.cache`, `.venv`, `.local` and
  the rest.
- `node_modules`.
- Your trash, `~/.local/share/Trash`, even when you run `recent` on `~/.local/share`.

A build or a `git pull` rewrites hundreds of files in those places, and they would push your own edits off the
list. `-a` brings them all back.

`recent` also stays on one filesystem. `recent /` looks at your root filesystem and skips `/home` when that is a
separate partition, along with USB drives and network shares. `/proc` and `/sys` are always skipped. They hold no
real files.

## Safety checks

- `recent` never changes anything.
- It never follows symlinks.
- Options after `--` go to `find` as extra tests. The ones that act on files, `-delete`, `-exec`, `-execdir`,
  `-ok`, `-okdir`, `-fprint`, `-fprint0`, `-fprintf` and `-fls`, are refused with exit 4.
- Folders you cannot read are skipped. At the end, `recent` says how many it could not read, so a short list is
  never a silent one.

## Pass-through

Options after `--` go to `find` as extra tests. This lists files in `/var/log` that changed today and are over
10 MB:

```console
$ recent 1d /var/log -- -size +10M
```

Other useful tests are `-user www-data`, `-perm -o+w` and `-newer file`.

## Needs

`find`, `stat` and `sort`, from findutils and coreutils, plus `date` and `awk`. Every distro ships them, and
BusyBox has them too. BusyBox `date -d` reads fewer date formats than GNU date, so on Alpine use plain dates such
as `2026-09-01` or `"2026-09-01 14:00"` with `--since`.

## Examples

### What changed in the last hour

```console
$ recent
17:10   3m ago     360B  src/app.py
17:01  12m ago     600B  tests/test_app.py
16:44  29m ago    1.3KB  README.md
16:27  46m ago     600B  pyproject.toml
4 files changed in the last 1h
```

### Hidden files too

```console
$ recent -a 4h
17:10   3m ago     360B  src/app.py
17:01  12m ago     600B  tests/test_app.py
16:44  29m ago    1.3KB  README.md
16:27  46m ago     600B  pyproject.toml
14:13   3h ago       1B  .git/index
5 files changed in the last 4h
```

### A longer window, with the command it runs

```console
$ recent -v 2d
recent: looking for files changed since 2026-09-27 17:13:23
+ find -P . -mindepth 1 -xdev '(' -path /proc -o -path /sys -o -name '.*' -o -name node_modules -o -path /home/me/.local/share/Trash ')' -prune -o -type f -mmin -2882 -exec stat -c '%Y %s %n' -- '{}' +
09-29 17:10   3m ago     360B  src/app.py
09-29 17:01  12m ago     600B  tests/test_app.py
09-29 16:44  29m ago    1.3KB  README.md
09-29 16:27  46m ago     600B  pyproject.toml
4 files changed in the last 2d
```

### Only a few

```console
$ recent -n 2
17:10   3m ago     360B  src/app.py
17:01  12m ago     600B  tests/test_app.py
2 of 4 files changed in the last 1h, use -n for more
```

### What changed in /etc after an upgrade

```console
$ sudo recent 30m /etc
15:02   4m ago     44KB  ld.so.cache
15:01   5m ago      98B  apt/sources.list.d/debian.sources
15:01   5m ago      31B  ssh/sshd_config.d/50-cloud-init.conf
3 files changed in the last 30m
```

### Folders that gained or lost files

```console
$ recent --since 2026-09-01 -t d
09-27 17:13   2d ago      60B  src
09-27 17:13   2d ago      60B  tests
2 folders changed since 2026-09-01
```

A folder's time changes when a name inside it is added, removed or renamed. Editing a file inside does not change
it.

### Only Python, without the tests

```console
$ recent --only '*.py' -x tests
17:10   3m ago     360B  src/app.py
1 file changed in the last 1h
```

### Nothing new

```console
$ recent 5s
No files changed in the last 5s.
```

## Troubleshooting

`recent: 2x is not a time. Use 10m, 2h, 3d, 1w or a date such as 2026-09-28`
: The first word looked like a time but was not one. Use a number and one of `s`, `m`, `h`, `d` or `w`.

`recent: could not read 3 paths, run it with sudo to include them`
: Some folders belong to root or another user. Run `sudo recent` for system folders such as `/etc` or `/var`.

A file I just saved is missing
: It may sit in a hidden folder, or in a folder a pattern skipped. Try `recent -a`. Some editors also keep the old
  time when they save, and some copy tools such as `cp -p` and `rsync -a` keep the time of the original.

A file shows up with an age of `0s` but I did not touch it
: Its time is in the future, for example a file unpacked from an archive made on a machine with a wrong clock.
  `recent` counts a future time as now.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, including when nothing changed. |
| 1 | It failed, for example a path does not exist. |
| 2 | Bad usage, such as a time it cannot read or `-n 0`. |
| 3 | `find`, `stat` or `sort` is missing. |
| 4 | Refused. An action such as `-delete` after `--`. |

## See also

`bigfiles`, `find(1)`, `stat(1)`
