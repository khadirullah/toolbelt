# bak

Copy a file aside before you edit it.

## Synopsis

```
bak [options] file ... [-- cp options]
bak -l | -r | -d | --prune N file ...
```

## Description

`bak` makes a dated copy of a file right next to it, so you can edit the file and still get the old version back.
The copy of `nginx.conf` made at 14:30:12 on 29 September 2026 is called `nginx.conf.2026-09-29-143012.bak`. The
copy keeps the owner, the mode and the times of the original, because `bak` copies with `cp -a`.

`bak` never overwrites a copy. When you make two copies in the same second, the second one gets a number, as in
`nginx.conf.2026-09-29-143012-1.bak`, and it counts as the newer one.

It works on folders too. `bak site` copies the whole `site` folder to `site.2026-09-29-143012.bak` with `cp -a`, which
keeps symlinks inside the folder as symlinks.

When the file you name is a symlink, such as a dotfile linked from a dotfiles repo, `bak` copies the file the link
points to. The copy is a real file with the content, not a second link.

The other modes work on the copies that already exist:

- `-l` lists them, newest first, with their age and size.
- `-r` puts the newest copy back. Before it does, it saves the current file as a new copy, so a restore can be undone
  with another `bak -r`.
- `-d` shows what changed between the newest copy and the file as it is now.
- `--prune N` keeps the newest N copies and moves the older ones to the trash.

`bak` finds the copies of a file by name. A copy is any file beside it called `name.YYYY-MM-DD-HHMMSS.bak` or
`name.YYYY-MM-DD-HHMMSS-N.bak`. Other files that end in `.bak`, such as `nginx.conf.old.bak`, are left alone.

## Options

| Option | What it does |
|---|---|
| `-l`, `--list` | List the copies of each file, newest first, with age and size. |
| `-r`, `--restore` | Put the newest copy back, after saving the current file as a new copy. Asks first. |
| `-d`, `--diff` | Show a unified diff from the newest copy to the current file. |
| `--dir DIR` | Keep the copies in DIR instead of beside the file. `bak` makes DIR when it does not exist. Use the same `--dir` with `-l`, `-r`, `-d` and `--prune`. |
| `--prune N` | Keep the newest N copies and move the rest to the trash. Asks first. N is 1 or more. |
| `-y`, `--yes` | Restore or prune without asking. |
| `-q`, `--quiet` | Show only the result line. |
| `-v`, `--verbose` | Show each step, and each `cp`, `mv` and `diff` before it runs. |
| `-h`, `--help` | Show the help. |

Use only one of `-l`, `-r`, `-d` and `--prune` at a time. With none of them, `bak` makes a copy.

## Restoring

`bak -r nginx.conf` does three things, in this order:

1. It finds the newest copy, for example `nginx.conf.2026-09-29-143012.bak`, and asks
   `Restore nginx.conf from the copy made 3h ago? The current one is saved first. [y/N]`.
2. It saves the current `nginx.conf` as a new copy. That copy is now the newest.
3. It copies the old version back over `nginx.conf` with `cp -a`, so the mode and times come back too.

Because step 2 makes the current file the newest copy, running `bak -r` a second time puts back the version you had
before the first restore. Restores never lose anything.

For a file, the copy goes back through `cp`, which writes into the existing file. A symlinked dotfile stays a
symlink, and the file it points to gets the old content.

For a folder, the current folder moves aside whole with `mv` and becomes the new copy, and then the old copy is
copied into place. Files you added after the copy was made do not linger in the restored folder. They are still in
the copy that step 2 made.

When the file no longer exists, `bak -r` copies the newest copy back without saving anything first.

## Where the copies go

By default each copy sits beside its file, in the same folder. That keeps it easy to find, and it means you need
write access to that folder. For files under `/etc` you need `sudo`, the same as for editing them.

`--dir DIR` puts the copies in another folder, such as `~/.bak`. The copy keeps only the file name, so
`/etc/hosts` and `~/projects/hosts` would share names in the same `--dir`. Give each group of files its own folder
if that matters to you.

## Safety checks

- `bak` never overwrites a copy. A copy made in the same second gets a `-1`, `-2` and so on before `.bak`.
- `-r` and `--prune` ask before they change anything. Without a terminal they refuse with exit 4 unless you pass
  `-y`. Answering no exits 5.
- `--prune` moves old copies to the trash in `~/.local/share/Trash`, where your file manager can restore them. It
  never deletes them for good.
- `-r` refuses when the file is a folder and the copy is not, or the other way round.
- `bak /` is refused with exit 4.

## Pass-through

Options after `--` go to `cp` when `bak` makes a copy, and to `diff` with `-d`.

```console
$ bak disk.img -- --reflink=auto
$ bak -d nginx.conf -- -w
```

`--reflink=auto` makes the copy instant on Btrfs and XFS, because the copy shares blocks with the original until
one of them changes. `-w` makes `diff` ignore changes in white space.

## Needs

`cp` from coreutils, or the `cp` in BusyBox. `-d` also needs `diff`, from the `diffutils` package on every
distro. Debian and Ubuntu install it by default. On Alpine, `apk add diffutils` gives the full `diff`, and the
BusyBox one also works.

## Examples

### Copy a config file before you edit it

```console
$ bak nginx.conf
nginx.conf -> nginx.conf.2026-09-29-143012.bak
```

### See what you changed

```console
$ bak -d nginx.conf
--- nginx.conf.2026-09-29-143012.bak	2026-09-29 14:30:12.394283532 +0530
+++ nginx.conf	2026-09-29 14:41:56.426271431 +0530
@@ -1,4 +1,4 @@
 server {
-    listen 80;
+    listen 443 ssl;
     server_name example.com;
 }
```

### List the copies

```console
$ bak -l nginx.conf
2h ago       60B  nginx.conf.2026-09-29-143012.bak
2d ago       55B  nginx.conf.2026-09-27-091200.bak
```

The age comes from the date in the name, which is when the copy was made. The file's own time is the time of the
original, because `cp -a` keeps it.

### Put the old version back

```console
$ bak -r nginx.conf
Restore nginx.conf from the copy made 2h ago? The current one is saved first. [y/N] y
saved the current nginx.conf as nginx.conf.2026-09-29-164356.bak
nginx.conf.2026-09-29-143012.bak -> nginx.conf
```

### Keep copies of dotfiles in one folder

```console
$ bak -v --dir ~/.bak ~/.bashrc
bak: making /home/khadir/.bak
+ cp -a -H -- /home/khadir/.bashrc /home/khadir/.bak/.bashrc.2026-09-29-164356.bak
/home/khadir/.bashrc -> /home/khadir/.bak/.bashrc.2026-09-29-164356.bak
```

### Keep only the newest two copies

```console
$ bak --prune 2 nginx.conf
trash  nginx.conf.2026-09-27-091200.bak
Move 1 old copy of nginx.conf (55B) to the trash? [y/N] y
1 old copy of nginx.conf in the trash, 2 kept.
```

### Copy a whole folder

```console
$ bak site
site -> site.2026-09-29-164356.bak
```

## Troubleshooting

`bak: /etc: permission denied, run it with sudo`
: The copy goes beside the file, and you cannot write to that folder. Run `sudo bak /etc/fstab`, or keep the copy
  somewhere you can write with `--dir ~/.bak`.

`bak: no copies of nginx.conf in .`
: There are no copies with the `name.YYYY-MM-DD-HHMMSS.bak` pattern in that folder. If you made them with `--dir`,
  pass the same `--dir` again.

`bak: not asking without a terminal, pass --yes to go ahead`
: `-r` and `--prune` ask before they change anything. In a script or a cron job, add `-y`.

`bak: nginx.conf and nginx.conf.2026-09-29-143012.bak are not the same kind, one is a folder. Restore it by hand`
: The name now belongs to a folder and the copy is a file, or the other way round. Move one of them and restore by
  hand with `cp -a`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked. With `-d`, the files may or may not differ. |
| 1 | It failed, for example no copies exist, or the folder is not writable. |
| 2 | Bad usage, such as two modes at once or `--prune` without a number. |
| 3 | `cp` or `diff` is missing. |
| 4 | Refused. No terminal to ask in, or `bak /`. |
| 5 | You answered no. |

## See also

`mirror`, `lock`, `cp(1)`, `diff(1)`
