# mirror

Make a folder match another, showing the changes first.

## Synopsis

```
mirror [options] source dest [-- rsync options]
```

## Description

`mirror` makes `dest` an exact copy of `source` with rsync. Files that are new in the source get copied, files that
changed get updated, and files that exist only in the dest get deleted. That last part is what makes rsync
dangerous. One wrong path and a backup drive is empty.

So `mirror` never runs rsync blind. Every run goes like this:

1. It says in words what it is about to do, such as `the contents of photos/ into /mnt/usb/photos/`.
2. It runs rsync as a dry run, which changes nothing, and counts what would happen.
3. It prints a summary line with the number of new, changed and deleted files and their sizes, then the first 20
   paths of each kind.
4. It asks `Go ahead?`. Only a `y` or `yes` goes on.
5. It runs rsync for real. Every file the run deletes or replaces in the dest goes to a dated backup folder first,
   so a wrong run can be undone.

```
mirror: the contents of photos/ into usb/photos/
2 new (7.9KB), 1 changed (14B), 1 deleted (8.5KB)
  new        4.1KB  2026-09/IMG_4410.jpg
  new        3.8KB  2026-09/IMG_4411.jpg
  changed      14B  albums.txt
  delete     8.5KB  old/export-2025.zip
Go ahead? Deleted and replaced files go to the trash in /home/me/.local/share/Trash. [y/N] y
done in 0.4s, 2 old files kept in /home/me/.local/share/Trash/files/mirror-20260929-171331
```

`mirror` copies with `rsync -a`. That keeps the times, the permissions and the symlinks. It keeps the owner too
when you run it as root.

## Options

| Option | What it does |
|---|---|
| `-n`, `--dry-run` | Show the summary and the paths, then stop. Nothing changes. |
| `--no-delete` | Copy and update only. Never remove anything from the dest. |
| `-c`, `--checksum` | Compare the content of each file, not its size and time. Slower, since it reads every file on both sides. |
| `-x`, `--exclude PAT` | Leave out paths that match, in rsync's pattern rules. Can repeat. |
| `--backup-in-dest` | Keep deleted and replaced files in `dest/.mirror-backup/DATE` instead of the trash. |
| `-y`, `--yes` | Go ahead without asking. The safety checks below still apply. |
| `-q`, `--quiet` | Show only the summary, the paths and the result line. |
| `-v`, `--verbose` | Show both rsync commands before they run. |
| `-h`, `--help` | Show the help. |

A file you leave out with `-x` is also safe from deletion in the dest, because rsync does not delete excluded
files. `-x '*.tmp'` leaves every `.tmp` file in the dest where it is.

## The trailing slash

rsync reads a slash at the end of the source as "what is inside". It is the rule people trip on most.

| Command | Result |
|---|---|
| `mirror photos/ /mnt/usb/photos` | What is inside `photos/` goes into `/mnt/usb/photos/`. |
| `mirror photos /mnt/usb` | The folder `photos` itself goes into `/mnt/usb`, as `/mnt/usb/photos/`. |
| `mirror photos /mnt/usb/photos` | The folder `photos` goes inside `/mnt/usb/photos`, as `/mnt/usb/photos/photos/`. Usually a mistake. |

The first line of every run says which of these it is. When the source has no trailing slash and the dest already
ends in the source's name, as in the last row, `mirror` warns:

```
mirror: usb/photos already ends in photos, so this makes usb/photos/photos/. Write photos/ to copy what is inside it instead
```

A slash at the end of the dest makes no difference.

## Where old files go

rsync's `--backup` and `--backup-dir` options move each file it would delete or overwrite into a backup folder,
under the same relative path. `mirror` always sets them. The folder is named after the time of the run, such as
`mirror-20260929-171331`, and `mirror` picks it like this:

- When the dest is on the same disk as your home folder, the backup folder goes in your trash,
  `~/.local/share/Trash/files/`. `mirror` writes a `.trashinfo` file next to it, so a file manager lists it in the
  trash and you empty it the usual way.
- When the dest is on another disk, such as a USB drive mounted at `/mnt/usb`, it goes in that disk's own trash,
  `/mnt/usb/.Trash-1000/files/`, where 1000 is your user id. That is the same place a file manager puts files you
  delete from that disk. It keeps the move a rename on the same disk, so it costs no copying and no space on your
  home disk.
- With `--backup-in-dest`, or when the dest is on another host, it goes in `dest/.mirror-backup/DATE`.
- When the disk's trash cannot be made, for example on a disk where you may only write inside the dest, `mirror`
  says so and uses `dest/.mirror-backup/DATE`.

`mirror` never deletes the `.mirror-backup` folder, or a trash folder that sits inside the dest, on a later run.
When a run replaced and deleted nothing, `mirror` removes the empty backup folder and says so.

To undo a run, copy the files back from the backup folder:

```console
$ rsync -a ~/.local/share/Trash/files/mirror-20260929-171331/ /mnt/usb/photos/
```

## Safety checks

`mirror` refuses with exit 4, before it changes anything, when:

- The source is empty and the run would delete files in the dest. This is the classic accident. A network share or
  USB drive was not mounted, its mount point is an empty folder, and a mirror from it would wipe the backup.
  `-y` does not skip this check. When you really mean to empty the dest, use `--no-delete` to see it, then delete
  by hand.
- The source and the dest are the same folder.
- The dest is inside the source, such as `mirror ~/ ~/backup`. Each run would copy the last copy again.
- The source is inside the dest, such as `mirror /mnt/usb/photos/ /mnt/usb`. The run would delete the source.
- There is no terminal to ask in and no `-y`. A cron job needs `-y`.

The last three checks compare real paths, after symlinks, so `mirror photos/ ./photos` is caught too. They only run
when both sides are on this machine.

## Other hosts

A path such as `nas:/srv/photos` or `me@nas:backups/` is on another host, the way rsync reads it. rsync connects
through ssh, so the host needs rsync installed and you need ssh access to it. Everything works the same, with two
differences:

- Old files go to `dest/.mirror-backup/DATE` on that host.
- The dry run shows 0B for deleted files there, since `mirror` cannot measure them from here.

A local path with a colon in the name, such as `a:b`, reads as a host too. Write `./a:b` for a local one.

## Pass-through

Options after `--` go to rsync, in the dry run and in the real run. Some useful ones:

```console
$ mirror photos/ /mnt/usb/photos -- --bwlimit=20M
$ mirror photos/ nas:/srv/photos -- -e 'ssh -p 2222'
$ mirror src/ /mnt/usb/src -- --exclude-from=.gitignore
$ mirror data/ /mnt/usb/data -- -H
```

`--bwlimit` caps the speed, `-e` sets the ssh command, and `-H` keeps hard links. Do not pass `--delete-excluded`
unless you mean it. It lets rsync delete the files `-x` protects.

## Needs

`rsync`, and on the other host too when a side is remote, plus `ssh` for that. The package is `rsync` on Debian,
Ubuntu, Fedora, Arch, openSUSE and Alpine. `df`, `find` and `stat` come with coreutils and findutils.

## Examples

### See what would change

```console
$ mirror -n photos/ usb/photos
mirror: the contents of photos/ into usb/photos/
2 new (7.9KB), 1 changed (14B), 1 deleted (8.5KB)
  new        4.1KB  2026-09/IMG_4410.jpg
  new        3.8KB  2026-09/IMG_4411.jpg
  changed      14B  albums.txt
  delete     8.5KB  old/export-2025.zip
```

### Make the copy

```console
$ mirror photos/ usb/photos
mirror: the contents of photos/ into usb/photos/
2 new (7.9KB), 1 changed (14B), 1 deleted (8.5KB)
  new        4.1KB  2026-09/IMG_4410.jpg
  new        3.8KB  2026-09/IMG_4411.jpg
  changed      14B  albums.txt
  delete     8.5KB  old/export-2025.zip
Go ahead? Deleted and replaced files go to the trash in /home/me/.local/share/Trash. [y/N] y
done in 0.4s, 2 old files kept in /home/me/.local/share/Trash/files/mirror-20260929-171331
```

### Run it again

```console
$ mirror photos/ usb/photos
mirror: the contents of photos/ into usb/photos/
0 new (0B), 0 changed (0B), 0 deleted (0B)
Nothing to change, usb/photos already matches photos/.
```

### The folder itself, by mistake

```console
$ mirror -n photos usb/photos
mirror: the folder photos itself into usb/photos/, as usb/photos/photos/
mirror: usb/photos already ends in photos, so this makes usb/photos/photos/. Write photos/ to copy what is inside it instead
3 new (7.9KB), 0 changed (0B), 0 deleted (0B)
  new          14B  photos/albums.txt
  new        4.1KB  photos/2026-09/IMG_4410.jpg
  new        3.8KB  photos/2026-09/IMG_4411.jpg
```

### The drive was not mounted

```console
$ mirror /mnt/nas/drop/ backup/
mirror: the contents of /mnt/nas/drop/ into backup/
mirror: refused, /mnt/nas/drop/ is empty, so this would delete all 1204 files in backup/. Check the path, or use --no-delete
```

### A backup inside the source

```console
$ mirror photos/ photos/backup
mirror: the contents of photos/ into photos/backup/
mirror: refused, photos/backup is inside photos/, so every run would copy the copy again
```

### See the rsync commands

```console
$ mirror -v -y photos/ usb/photos
mirror: the contents of photos/ into usb/photos/
+ rsync -a --dry-run '--out-format=%i %l %n' --delete '--filter=P /.mirror-backup/' -- photos/ usb/photos
1 new (4B), 0 changed (0B), 0 deleted (0B)
  new           4B  notes.md
+ rsync -a --backup --backup-dir=/home/me/.local/share/Trash/files/mirror-20260929-171332 --delete '--filter=P /.mirror-backup/' -- photos/ usb/photos
done in 0.1s, nothing was replaced or deleted
```

### Add only, keep old files in the dest

```console
$ mirror -y --no-delete --backup-in-dest photos/ usb/photos
mirror: the contents of photos/ into usb/photos/
1 new (2B), 0 changed (0B), 0 deleted (0B)
  new           2B  n.txt
done in 0.1s, nothing was replaced or deleted
```

## Troubleshooting

`mirror: refused, SRC is empty, so this would delete all N files in DEST`
: Check that the source is mounted, with `ls SRC` and `findmnt SRC`. When you want to add files and keep the rest,
  use `--no-delete`.

`mirror: not asking without a terminal, pass --yes to go ahead`
: `mirror` runs from a script or cron. Add `-y` once a dry run with `-n` shows what you expect.

`rsync: connection unexpectedly closed` or `rsync: command not found` on another host
: rsync must be installed on both machines. Install it on the other host, and check `ssh host` works on its own.

`rsync: [generator] failed to set times` or `Operation not permitted` on a USB drive
: FAT32 and exFAT drives cannot store Linux owners and permissions. Pass `-- --no-perms --no-owner --no-group
  --modify-window=2`, and every run after the first will stop showing every file as changed.

Every file shows as changed on each run
: The times differ between the two sides, often on FAT drives or network shares. Use `-c` to compare content, or
  `--modify-window=2` after `--` as above.

The trash on the USB drive fills up
: Empty it from the file manager, or delete `/mnt/usb/.Trash-1000/files/mirror-*` and the matching files in
  `/mnt/usb/.Trash-1000/info/`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, including a dry run and a run with nothing to change. |
| 1 | rsync failed. The message has its exit code, and rsync's own message is above it. |
| 2 | Bad usage, such as a missing dest. |
| 3 | rsync is missing. |
| 4 | Refused. An empty source, nested folders, or no terminal and no `-y`. |
| 5 | You answered no. |

When some source files vanish while rsync runs, rsync exits 24. `mirror` warns and still exits 0.

## See also

`bak`, `rsync(1)`, `cp(1)`
