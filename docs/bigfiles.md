# bigfiles

List the biggest files or folders under a path.

## Synopsis

```
bigfiles [options] [path ...] [-- find tests]
```

## Description

When a disk fills up, the first question is what is taking the space. `bigfiles` answers it. It lists the 20
biggest files under a path, biggest first, with the size, the age and the path. With no path it looks in the
current folder.

```
   90KB    40d  ./VMs/debian-13.qcow2
   60KB   120d  ./Downloads/iso/debian-13.1.0-amd64-DVD-1.iso
   60KB     3d  ./Downloads/ubuntu-24.04.3-desktop-amd64.iso
3 files, 210KB together
```

The age is the time since the file last changed, in seconds, minutes, hours, days or years (`s`, `m`, `h`, `d`,
`y`). A 40 GB VM image last changed a year ago is a better thing to clean up than one you used this morning.

With `-d`, it lists the folders one level down instead, by the total size of everything in them. Run it on `/var`,
find the biggest folder, then run it again on that folder.

`bigfiles` only reads. It never deletes, moves or changes a file.

## Options

| Option | What it does |
|---|---|
| `-n`, `--count N` | Show N entries. The default is 20. |
| `-d`, `--dirs` | List the folders one level down by total size, instead of files. |
| `-m`, `--min SIZE` | Show only entries of SIZE or more, such as `500M` or `1.5G`. Units are powers of 1024. |
| `-x`, `--exclude PAT` | Leave out names that match. A folder that matches is skipped whole. Can repeat. |
| `-a`, `--all-fs` | Cross into other filesystems too, such as a USB drive mounted under the path. |
| `-q`, `--quiet` | Show only the list. |
| `-v`, `--verbose` | Show each step, and each `find` and `du` command before it runs. |
| `-h`, `--help` | Show the help. |

A pattern without a `/` matches a name, the way `find -name` does, so `-x .git` skips every `.git` folder. A pattern
with a `/` matches the path, the way `find -path` does. Quote patterns with `*` so the shell does not expand them.

## How it measures

For files, the size is the size of the content, from `stat`. That is the number `ls -l` shows.

For folders, `-d` asks `du -s` for the space the folder takes on disk. The two can differ. A sparse VM image of
40 GB may take only 8 GB on disk, and a folder of many tiny files takes more than their sizes add up to, because
each file uses at least one 4 KB block. Both numbers are right. They answer different questions.

For a folder, the age is the time since a name in it was added, removed or renamed. It does not change when a file
inside is edited.

## One filesystem at a time

By default `bigfiles` stays on the filesystem the path is on. `bigfiles /` looks at your root filesystem and skips
`/home` when that is a separate partition, along with USB drives, network shares and `/boot/efi`. Run it again on
`/home` to see that one. `-a` crosses into all of them.

`/proc` and `/sys` are always skipped, even with `-a`. They hold no real files, and the sizes they report are
meaningless, such as the 128 TB that `/proc/kcore` claims.

## Safety checks

- `bigfiles` never changes anything.
- It never follows symlinks, so a link to another disk cannot count that disk twice.
- Options after `--` go to `find` as extra tests. The ones that act on files, `-delete`, `-exec`, `-execdir`, `-ok`,
  `-okdir`, `-fprint`, `-fprint0`, `-fprintf` and `-fls`, are refused with exit 4.
- Folders you cannot read are skipped. At the end, `bigfiles` says how many it could not read, so a short list is
  never a silent one.

## Distro notes

On Debian and Ubuntu, `/var/cache/apt/archives` often holds a few GB of old packages. `sudo apt clean` empties it.
On Fedora, `sudo dnf clean all` does the same for `/var/cache/dnf`, and on Arch, `paccache -r` trims
`/var/cache/pacman/pkg`.

On every systemd distro, the journal in `/var/log/journal` can grow to several GB. `journalctl --disk-usage` shows
its size, and `sudo journalctl --vacuum-size=200M` trims it.

On a machine with Docker, most of the space sits in `/var/lib/docker`, which `bigfiles` shows as one large folder.
`docker system df` explains it better, and `docker system prune` frees it.

## Pass-through

For files, options after `--` go to `find` as extra tests. This finds big files that have not changed in 90 days:

```console
$ bigfiles ~/Downloads -- -mtime +90
```

Other useful tests are `-name '*.iso'`, `-user www-data` and `-newer file`. They do not work with `-d`.

## Needs

`find`, `stat` and `sort`, plus `du` for `-d`. Every distro ships them in findutils and coreutils, and BusyBox has
all four.

`ncdu` is optional. When it is installed, `bigfiles` ends with a line that suggests it:

```
To browse the tree, run: ncdu -x .
```

`ncdu` lets you walk the tree with the arrow keys and delete from inside it. The package is `ncdu` on Debian,
Ubuntu, Fedora, Arch and Alpine. On RHEL, Rocky and Alma it is in EPEL.

## Examples

### The biggest files here

```console
$ bigfiles -n 3
   90KB    40d  ./VMs/debian-13.qcow2
   60KB   120d  ./Downloads/iso/debian-13.1.0-amd64-DVD-1.iso
   60KB     3d  ./Downloads/ubuntu-24.04.3-desktop-amd64.iso
3 files, 210KB together
```

### Which folder is biggest

```console
$ bigfiles -d
  120KB     6m  ./Downloads
   92KB     6m  ./VMs
   32KB     6m  ./Videos
   12KB     6m  ./.cache
4 folders, 256KB together
```

### Leave some names out

```console
$ bigfiles -x '*.iso'
   90KB    40d  ./VMs/debian-13.qcow2
   30KB     5h  ./Videos/talk-raw.mp4
   12KB     6m  ./.cache/pip/wheel.whl
     2B     6m  ./notes.txt
4 files, 132KB together
```

### Only old files

```console
$ bigfiles -- -mtime +30
   90KB    40d  ./VMs/debian-13.qcow2
   60KB   120d  ./Downloads/iso/debian-13.1.0-amd64-DVD-1.iso
2 files, 150KB together
```

### See the command it runs

```console
$ bigfiles -v -n 2 Downloads
+ find -P Downloads -xdev '(' -path /proc -o -path /sys ')' -prune -o -type f -exec stat -c '%s %Y %n' -- '{}' +
   60KB   120d  Downloads/iso/debian-13.1.0-amd64-DVD-1.iso
   60KB     3d  Downloads/ubuntu-24.04.3-desktop-amd64.iso
2 files, 120KB together
```

### Folders it could not read

```console
$ bigfiles -n 2
   90KB    40d  ./VMs/debian-13.qcow2
   60KB   120d  ./Downloads/iso/debian-13.1.0-amd64-DVD-1.iso
bigfiles: could not read 1 path, run it with sudo to include them
2 files, 150KB together
```

### Nothing that big

```console
$ bigfiles -m 1G ~/projects
No files of 1GB or more.
```

## Troubleshooting

`bigfiles: could not read 3 paths, run it with sudo to include them`
: Some folders belong to root or another user. For system folders such as `/var`, run `sudo bigfiles -d /var`.

`bigfiles: refused, -delete after -- would act on files, and bigfiles only lists them`
: `bigfiles` only lists. Delete what you choose with `rm`, or move it to the trash with `gio trash`.

`bigfiles: options after -- work for files, not with -d`
: `du` measures whole folders, so `find` tests have nothing to filter. Drop `-d`, or drop the options after `--`.

`df` says the disk is full, but `bigfiles /` finds little
: The space may be on another filesystem, so run it on `/home` or `/var` too. It may also be held by a deleted file
  that a program still has open, such as a log file. `sudo lsof +L1` lists those. Restarting the program frees the
  space.

It is slow on `/`
: The first run reads every folder on the disk. Start with `bigfiles -d /`, then look inside the biggest folder.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, including when nothing was big enough to list. |
| 1 | It failed, for example a path does not exist. |
| 2 | Bad usage, such as `-n 0` or a size it cannot read. |
| 3 | `find`, `stat`, `du` or `sort` is missing. |
| 4 | Refused. An action such as `-delete` after `--`. |

## See also

`dupes`, `du(1)`, `df(1)`, `ncdu(1)`
