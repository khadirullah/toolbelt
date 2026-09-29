# cleanup

See what fills the disk, then clean it safely.

## Synopsis

```
cleanup [--clean] [--only ITEM[,ITEM]] [-y] [-- tool options]
```

## Description

A full disk on Linux is rarely your own files. It is the systemd journal, the package manager's download cache,
stopped containers and dangling images, the trash you never emptied, old kernels, and the thumbnail cache. Each
has its own command to clean it, and each is easy to get wrong. `rm -rf /var/log/journal` breaks the journal.
Removing the running kernel leaves the machine unable to load modules. `docker system prune -a` deletes images
you still want.

`cleanup` knows the safe command for each of these on your distro. Run with no options, it measures each item and
shows what `--clean` would do, then lists the four largest folders in your home. It changes nothing.

With `--clean` it goes through the items one by one, shows the size and asks. Only a `y` or `yes` cleans that
item. Anything else skips it. After each clean it measures again and prints what was freed. The last line has the
total and the free space on `/` afterwards.

`cleanup` never touches your documents, downloads or projects. The largest folders list is there so you can see
where the rest of the space went and decide yourself.

## The items

| Item | What it measures | What `--clean` runs |
|---|---|---|
| `journal` | `journalctl --disk-usage` | `sudo journalctl --vacuum-size=200M` |
| `pkgcache` | The package manager's download folder | The package manager's own clean command, with sudo |
| `containers` | `podman system df` and `docker system df`, the reclaimable part | `podman system prune -f` and `docker system prune -f` |
| `trash` | `~/.local/share/Trash` | Deletes the files in it for good |
| `kernels` | `/lib/modules/VERSION` and `/boot/*-VERSION` of each old kernel | The package manager removes the old kernel packages |
| `thumbnails` | `~/.cache/thumbnails` | Deletes the cached thumbnails |

### The journal

The journal keeps logs until it reaches 10% of the filesystem or 4GB, whichever is smaller. On a small disk that
is a lot. `cleanup` shrinks it to 200M by deleting the oldest archived journal files, the only safe way to shrink
it. The active journal files, which hold the newest lines, always stay. When the journal is under 200M already,
the item says so and does nothing.

To keep it small for good, set `SystemMaxUse=200M` in `/etc/systemd/journald.conf` and restart
`systemd-journald`.

### The package cache

Package managers keep every package they download, in case you install it again. Nothing needs those files once
the packages are installed.

| Package manager | Folder | Clean command |
|---|---|---|
| apt | `/var/cache/apt/archives` | `apt-get clean` |
| dnf | `/var/cache/dnf`, `/var/cache/libdnf5` | `dnf clean packages` |
| pacman | `/var/cache/pacman/pkg` | `paccache -rk1`, or `pacman -Sc` without pacman-contrib |
| zypper | `/var/cache/zypp/packages` | `zypper clean` |
| apk | `/var/cache/apk` | `apk cache clean` |

On Arch, `paccache -rk1` keeps the newest cached version of each package, so you can still reinstall it offline.
`pacman -Sc` keeps only the versions that are installed.

### Containers

`podman system prune -f` and `docker system prune -f` remove stopped containers, networks no container uses,
dangling images and the build cache. They keep every image a container uses or that has a tag, and every volume.
Volumes hold data, such as a database, so `cleanup` leaves them alone unless you pass `-- --volumes`.

The size comes from the `RECLAIMABLE` column of `system df`. When podman or docker is not installed, or the
daemon does not answer, that engine is skipped and the table says so.

### The trash

The trash is where file managers and the toolbelt commands move deleted files, so they can be restored.
Emptying it deletes them for good. `cleanup` counts the files first and says how many in the question.

### Old kernels

Most distros keep a few old kernels so you can boot one when a new one breaks. `cleanup` always keeps two of
them. One is the running kernel, and the other is the newest installed one, which the next boot uses. Every other kernel is old.

| Package manager | How it lists kernels | How it removes them |
|---|---|---|
| apt | installed `linux-image-VERSION` packages | `apt-get purge -y linux-image-VERSION ...` |
| dnf | `rpm -q kernel-core` | `dnf remove -y kernel-core-VERSION ...` |
| zypper | the folders in `/lib/modules` | `zypper purge-kernels`, which follows `multiversion.kernels` in `/etc/zypp/zypp.conf` |
| pacman, apk | | Nothing to do. Both keep one kernel per package, and an update replaces it. |

When the running kernel is not among the installed ones, as in a container, where `uname -r` shows the host's
kernel, `cleanup` leaves kernels alone.

### Thumbnails

File managers and image viewers cache a small picture of every image and video they show, in
`~/.cache/thumbnails`. It grows without limit. Deleting it is safe, and the thumbnails come back as you browse.
They are deleted, not moved to the trash, because moving them to the trash frees nothing.

## Options

| Option | What it does |
|---|---|
| `--clean` | Run the cleans, asking before each one. |
| `--only ITEMS` | Only these items, comma separated, such as `--only journal,thumbnails`. They run in the usual order. |
| `-y`, `--yes` | Clean without asking. |
| `-q`, `--quiet` | Only the table in the report. With `--clean`, only the questions and the last line. |
| `-v`, `--verbose` | Show each item as it is measured and each command before it runs. |
| `-h`, `--help` | Show the help. |

## Safety

- Without `--clean`, `cleanup` only measures. It runs `du`, `df`, `journalctl --disk-usage` and `system df`, and
  nothing else.
- With `--clean`, every item needs its own `y`, unless you pass `-y`.
- Without a terminal and without `-y`, `--clean` stops before it touches anything and exits 4. A cron job must say
  `-y` on purpose.
- Answering no to every question exits 5 with `Nothing changed.`.
- The journal, the package cache and kernels are cleaned by the tool that owns them, never with `rm`. Only the
  trash and the thumbnail cache, both in your home, are deleted directly.
- The running kernel and the newest kernel are never removed.
- Container volumes are never removed unless you pass `-- --volumes`.

## Pass-through

With `--only` and one item, options after `--` go to that item's tool.

| Item | Tool | Example |
|---|---|---|
| `journal` | `journalctl` | `cleanup --clean --only journal -- --vacuum-time=2weeks` |
| `pkgcache` | the package manager's clean command | `cleanup --clean --only pkgcache -- -q` |
| `kernels` | the package manager's remove command | `cleanup --clean --only kernels -- --dry-run` |
| `containers` | `podman system prune` and `docker system prune` | `cleanup --clean --only containers -- --volumes` |

`trash` and `thumbnails` have no tool, so options after `--` with them are a usage error.

## Per-distro notes

Debian and Ubuntu
: The package cache often holds gigabytes after a release upgrade. Old kernels stay installed until `apt
  autoremove` or `cleanup` removes them.

Fedora
: dnf keeps three kernels by default, set by `installonly_limit` in `/etc/dnf/dnf.conf`. `cleanup` removes all but
  two. dnf5 on Fedora 41 and later keeps its cache in `/var/cache/libdnf5`.

Arch
: Install `pacman-contrib` for `paccache`. pacman keeps one kernel, so the kernels item has nothing to do.

openSUSE
: `zypper purge-kernels` decides which kernels to keep from `zypp.conf`, usually the running, the latest and the
  one before it.

Alpine
: There is often no journal, since Alpine uses syslog. The journal item is skipped when journalctl is missing.

## Needs

`du` and `df`, from `coreutils`. The rest is per item, and an item whose tool is missing is skipped.

| Tool | Package | Item |
|---|---|---|
| `journalctl` | `systemd` | journal |
| the package manager | installed with the distro | pkgcache, kernels |
| `paccache` | `pacman-contrib` on Arch | pkgcache, optional |
| `podman`, `docker` | `podman`, `docker.io` or `docker-ce` | containers |
| `sudo` | `sudo` | journal, pkgcache, kernels, when you are not root |

## Examples

### See what would be freed

```console
$ cleanup
/ is ext4, 48GB, 43GB used, 2.4GB free (95%)

ITEM         SIZE  WHAT --clean DOES
journal      33MB  under 200M already, nothing to do
pkgcache    3.1GB  apt-get clean
containers      -  skipped, podman and docker are not installed or not reachable
trash          0B  empty, nothing to do
kernels     355MB  removes 6.12.94+deb13-amd64 and 6.12.105+deb13-amd64, keeps 6.12.107+deb13-amd64 (running)
thumbnails   37MB  rm -r ~/.cache/thumbnails/*
total       3.5GB  nothing changed. Run cleanup --clean to choose.

largest folders in /home/test
 3.6GB  .cache
 2.5GB  .mozilla
 1.8GB  .local
 1.6GB  .npm
```

This machine is at 95%. The package cache and two old kernels free 3.5GB, more than doubling the free space.

### Clean, item by item

```console
$ cleanup --clean
journal     1.5GB Shrink the journal to 200M? [y/N] y
[sudo] password for khadir:
            freed 1.3GB
pkgcache    3.1GB Clean the apt-get package cache? [y/N] y
            freed 3.1GB
containers  2.7GB Remove stopped containers, unused networks, dangling images and build cache? [y/N] n
            skipped
trash       20KB  Empty the trash for good, 1 file? [y/N] y
            freed 20KB
kernels     355MB Remove kernel 6.12.94+deb13-amd64 and 6.12.105+deb13-amd64? 6.12.107+deb13-amd64 is running. [y/N] y
            freed 355MB
thumbnails  37MB  Delete cached thumbnails? They come back as needed. [y/N] y
            freed 37MB
cleanup: freed 4.8GB of 7.6GB. / now has 7.2GB free.
```

The containers item was skipped, so its 2.7GB is in the second number but not the first.

### Two items, no questions

```console
$ cleanup --clean --only journal,thumbnails --yes
journal     freed 1.3GB
thumbnails  freed 37MB
cleanup: freed 1.3GB. / now has 3.7GB free.
```

### Only the table

```console
$ cleanup -q --only journal,kernels
ITEM         SIZE  WHAT --clean DOES
journal     1.1GB  journalctl --vacuum-size=200M
kernels     355MB  removes 6.12.94+deb13-amd64 and 6.12.105+deb13-amd64, keeps 6.12.107+deb13-amd64 (running)
total       1.5GB  nothing changed. Run cleanup --clean to choose.
```

### Container volumes too

```console
$ cleanup --clean --only containers --yes -- --volumes
containers  freed 2.7GB
cleanup: freed 2.7GB. / now has 9.9GB free.
```

Check `docker volume ls` first. A volume that belongs to no container right now may still hold a database you
want.

### From a script with no terminal

```console
$ cleanup --clean < /dev/null
cleanup: not asking without a terminal, pass --yes to go ahead
$ echo $?
4
```

### A mistyped item

```console
$ cleanup --only cache
cleanup: unknown item cache. Use journal, pkgcache, containers, trash, kernels or thumbnails.
Try 'cleanup --help' for the options.
```

## Troubleshooting

The journal shows a small size, but `/var/log/journal` is big
: `journalctl --disk-usage` counts only the journal files you can read. Run `sudo cleanup` to see the whole
  journal, or join the `systemd-journal` group.

`skipped, podman and docker are not installed or not reachable` with docker installed
: The docker daemon is not running, or you are not in the `docker` group. Check with `docker info`. Run
  `sudo cleanup --only containers` to use root's access.

`skipped, the running kernel VERSION is not installed here, so kernels are left alone`
: `cleanup` runs in a container, or the running kernel was removed by hand. Reboot into an installed kernel
  first.

`cleanup: not asking without a terminal, pass --yes to go ahead`
: `--clean` runs from cron or a pipe. Add `-y` once a run without `--clean` shows what you expect.

`E: Could not get lock /var/lib/dpkg/lock-frontend`
: Another apt is running, often the automatic updater. Wait and run `cleanup --clean --only pkgcache,kernels`
  again.

`/` has little free space after the clean
: Look at the largest folders list. Run `bigfiles ~` or `du -xh -d 2 ~ | sort -h | tail` to go deeper.

The freed size is smaller than the size in the question
: The journal keeps the files of the current boot, and podman and docker count shared layers once. The report
  measures before and after each clean, so the freed number is what really left the disk.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, including a report and a run with nothing to clean. |
| 1 | A clean command failed. The others still ran. |
| 2 | Bad usage, such as an unknown item or options after `--` without one `--only` item. |
| 3 | `du`, `df`, or sudo for a system item, is missing. |
| 4 | Refused. `--clean` with no terminal and no `-y`. |
| 5 | You answered no to every question. |

## See also

`bigfiles`, `dupes`, `pkg`, `journalctl(1)`, `docker-system-prune(1)`
