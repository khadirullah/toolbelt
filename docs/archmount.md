# archmount

Open an archive as a folder without unpacking.

## Synopsis

```
archmount [options] archive [dir] [-- fuse options]
archmount -u dir
archmount --list
```

## Description

`archmount` mounts an archive read-only through FUSE, so you can `cd` into it, `grep` it, open files in an editor
and copy out what you need. Nothing is unpacked to disk, and the archive is never changed.

With no folder named, it mounts next to the archive in a folder named after it, so `backup.tar.zst` opens on
`backup/`. When that name is taken by a file or a folder with files in it, it uses `backup-1/`, and so on.
`archmount` makes the folder, and removes it again on unmount. A folder you name yourself stays after unmount.

There are three ways to run it.

- **In a terminal, with no option**, it opens a new shell inside the mounted folder. Type `exit` and it unmounts.
  Ctrl+C inside that shell only stops the program running there, not the mount.
- **With `-w`**, it stays in the foreground with no shell and unmounts on Ctrl+C. Use this from a script, or when
  you want to use the folder from another terminal.
- **With `-b`**, it mounts and returns to the prompt. The mount stays until `archmount -u DIR` or a reboot. It
  prints the unmount line on stdout, so a script can capture it.

When not in a terminal and without `-b`, it behaves as with `-w`.

`archmount` keeps a list of what it mounted in `~/.local/state/toolbelt/archmount.mounts`. `--list` reads it,
drops the entries that are gone, and adds archive mounts made by hand with fuse-archive, archivemount or
ratarmount.

## Options

| Option | What it does |
|---|---|
| `-b`, `--background` | Mount and return to the prompt. Unmount later with `-u`. |
| `-w`, `--wait` | Stay in the foreground without a shell, until Ctrl+C. |
| `-u`, `--unmount DIR` | Unmount a folder, and remove it when `archmount` made it. |
| `--list` | Show the archives mounted now, with the folder, the tool and the archive. |
| `-q`, `--quiet` | Print only errors, and the unmount line with `-b`. |
| `-v`, `--verbose` | Print each step, and each real command before it runs. |
| `-h`, `--help` | Print the help. |

`-b` and `-w` contradict each other.

## Tools

`archmount` uses the first of these that is installed.

| Tool | Formats | Notes |
|---|---|---|
| fuse-archive | tar and compressed tars, zip, 7z, rar, iso, cpio | Built on libarchive, and read-only by design. |
| archivemount | the same, also through libarchive | The most widely packaged. Mounted with `-o readonly`. |
| ratarmount | tar and compressed tars, zip, rar | Python. Saves an index on the first mount, so later mounts of the same archive are instant. |

A zip, 7z or iso has an index, so mounting is instant and opening a file reads only that file. A `tar.gz`,
`tar.zst` or other compressed tar has no index, so the tool reads the whole archive once at mount time to find
where each file starts. For an archive over 64MB `archmount` says so first, since the mount can take a while.
ratarmount saves that index and skips the read next time.

## Unmounting and busy folders

`-u DIR` runs `fusermount3 -u`, or `fusermount -u` on systems with FUSE 2, or `umount` as a last resort. When a
program still has a file open or a shell sits inside the folder, the unmount fails. `archmount` then names the
programs, using `lsof` when it is installed:

```
archmount: mnt/site is busy, used by less (pid 48213)
archmount: close it and run archmount -u mnt/site again
```

It never forces an unmount, since that can leave a program reading from a folder that vanished.

## Pass-through

Options after `--` go to the FUSE tool, before the archive and folder. `-o allow_other` lets other users read the
mount, when `/etc/fuse.conf` has `user_allow_other`. fuse-archive and archivemount take the FUSE `-o` options,
and ratarmount takes its own, such as `--recursive` to open archives inside the archive.

```
archmount -b logs.zip -- -o allow_other
archmount -b nested.tar -- --recursive
```

## Needs

One of fuse-archive, archivemount or ratarmount, and `fusermount3` or `fusermount` to unmount. The kernel needs
FUSE, which every desktop distro has. `lsof` is optional and names the programs that keep a folder busy.

| Tool | apt | dnf | pacman | zypper | apk |
|---|---|---|---|---|---|
| archivemount | archivemount | archivemount | archivemount | archivemount | none |
| fusermount3 | fuse3 | fuse3 | fuse3 | fuse3 | fuse3 |
| fusermount | fuse | fuse | fuse2 | fuse | fuse |
| lsof | lsof | lsof | lsof | lsof | lsof |

ratarmount is on PyPI and installs on any distro with `pipx install ratarmount`. fuse-archive comes from its
project's releases, or from your distro where it has a package.

Per distro:

- **Debian, Ubuntu, Fedora, Arch and openSUSE.** Install archivemount from the main repos. It is the simplest
  choice.
- **Alpine.** archivemount has no package. Install ratarmount with pipx, and `fuse3` for the unmount tool.
- **Containers.** FUSE needs `/dev/fuse`, and a container often lacks it. `archmount` says so when it is
  missing. Use `unpack -l` to list the archive instead, or `unpack --only` to pull out one file.

When no tool is installed, `archmount` exits 3 and prints the install line for archivemount.

## Examples

### Look inside a backup, then return

In a terminal, with no option:

```console
$ archmount backup.tar.zst
archmount: backup.tar.zst on backup/, read-only
archmount: new shell in backup/. Type exit to unmount.
$ exit
archmount: unmounted backup
```

### Mount in the background

```console
$ archmount -b backup.tar.zst
archmount: backup.tar.zst on backup/, read-only
Unmount with: archmount -u backup
```

### Mount on a folder you pick

```console
$ archmount -b site.zip mnt/site
archmount: site.zip on mnt/site/, read-only
Unmount with: archmount -u mnt/site
```

### What is mounted

```console
$ archmount --list
FOLDER                           TOOL         ARCHIVE
/home/sam/backup                 fuse-archive /home/sam/backup.tar.zst
/home/sam/mnt/site               fuse-archive /home/sam/site.zip
```

### A busy folder

```console
$ archmount -u mnt/site
archmount: mnt/site is busy, used by less (pid 48213)
archmount: close it and run archmount -u mnt/site again
$ archmount -u mnt/site
archmount: unmounted mnt/site
```

### Wait in the foreground

```console
$ archmount -w backup.tar.zst
archmount: backup.tar.zst on backup/, read-only
archmount: press Ctrl+C to unmount.
^Carchmount: unmounted backup
```

### A folder with files in it

```console
$ archmount -b backup.tar.zst full
archmount: full is not empty, and mounting would hide its files. Pick an empty folder
```

### Pass options and see the command

```console
$ archmount -v -b site.zip -- -o allow_other
archmount: tool: fuse-archive
+ fuse-archive -o allow_other /home/sam/site.zip /home/sam/site-1
archmount: mounted in 0.0s
archmount: site.zip on site-1/, read-only
Unmount with: archmount -u site-1
```

The default folder `site/` already held files, so the mount went to `site-1/`.

## Troubleshooting

**"needs fuse-archive, archivemount or ratarmount"** None is installed. Install archivemount from your package
manager, or ratarmount with pipx.

**"this machine has no /dev/fuse, so FUSE cannot run here"** The kernel module is not loaded, or you are in a
container started without `--device /dev/fuse`. On a normal machine, `sudo modprobe fuse` loads it.

**"fusermount3: mount failed: Operation not permitted"** Your user may not be allowed to mount. On older
systems, add yourself to the `fuse` group and log in again.

**The mount takes a long time.** A compressed tar has no index, so the tool reads it all once. Use ratarmount,
which keeps the index for next time, or repack as zip or 7z with `squash` if you mount it often.

**"is busy"** A program has a file open inside, or a shell has it as its current folder. Close it, `cd` out, and
run `archmount -u` again.

**"is not mounted"** The mount is already gone, perhaps after a reboot. `archmount` drops it from its list.

**A mount stays after a crash.** Run `archmount -u DIR`. When that fails too, `fusermount3 -uz DIR` detaches it
once nothing uses it.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Mounted, unmounted, or listed. |
| 1 | The tool could not mount the archive, the folder is busy, or the folder is not mounted. |
| 2 | Bad usage. |
| 3 | No FUSE tool is installed. |
| 4 | Refused, since the folder holds files, is already a mount point, or is a file. |

After Ctrl+C in `-w` mode, `archmount` unmounts and exits 130, like any command stopped with Ctrl+C.

## See also

`unpack`, `archdiff`, `squash`, `fusermount3(1)`, `archivemount(1)`, `ratarmount(1)`
