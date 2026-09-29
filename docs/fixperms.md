# fixperms

Set folders to 755 and files to 644, with a preview.

## Synopsis

```
fixperms [options] path ...
```

## Description

Files copied from a USB stick, a Windows share or a zip file often arrive with the wrong modes. Everything is
`777`, or everything is `600` and the web server cannot read it. `fixperms` puts a tree back to the usual modes.
Folders get `755`, files get `644`, and scripts and programs keep their execute bit and get `755`.

It never changes anything before you see what will change. It counts the folders and files, shows how many of each
would change and what modes they have now, and asks once:

```
site has 4 folders and 5 files.
  folders to 755        3  now 777
  files to 644          3  now 666, 600
  files to 755          2  deploy.sh, css/main.css
Change 8 modes? [y/N]
```

The `now` column lists the most common current modes, up to three. The `files to 755` line lists the first
three names instead, because those are the files it treats as programs, and you should see which ones.

A path that already has the right mode is left alone, so a second run prints `Nothing to change`.

## Options

### What changes

| Option | What it does |
|---|---|
| `-d`, `--dirs` | Change folders only. |
| `-f`, `--files` | Change files only. With both `-d` and `-f`, it changes both. |
| `--private` | Use `700` for folders and `600` for files, and `700` for programs. For notes, keys and anything only you should read. |
| `--dir-mode MODE` | The mode for folders, `755` by default. Three octal digits, such as `750`. |
| `--file-mode MODE` | The mode for files, `644` by default. |
| `--no-exec` | Give every file the file mode, scripts too. |
| `-x`, `--exclude PAT` | Leave matching names alone, and everything inside a matching folder. Can repeat. |

### Running

| Option | What it does |
|---|---|
| `-n`, `--dry-run` | Show what would change and stop. |
| `--force` | Allow a system folder or your home folder. |
| `-y`, `--yes` | Change without asking. The safety checks still refuse. |
| `-q`, `--quiet` | Show only the result line. |
| `-v`, `--verbose` | Show each step, and each `find` command before it runs. |
| `-h`, `--help` | Show the help. |

## How it decides

- A folder gets the folder mode.
- A file with any execute bit, for the owner, the group or others, counts as a program. It gets the file mode with
  an `x` added wherever there is an `r`. So `644` becomes `755`, `600` becomes `700`, and `640` becomes `750`.
- Any other file gets the file mode.
- With `--no-exec`, every file gets the file mode.

The execute rule has one catch. A file that arrived as `777`, such as `main.css` above, has execute bits too, so it
counts as a program and gets `755`. When a whole tree came in as `777`, run it with `--no-exec` first, then
`chmod +x` the few scripts that need it:

```console
$ fixperms -y --no-exec site
$ chmod +x site/deploy.sh
```

With `-x`, a pattern without a `/` matches a name anywhere in the tree, the way `find -name` does. A pattern with a
`/` matches the path, the way `find -path` does. Quote patterns with `*` so the shell leaves them alone.

`fixperms` also takes a single file. `fixperms notes.txt` sets that one file.

## Safety checks

- **System folders.** `/`, `/bin`, `/boot`, `/dev`, `/etc`, `/home`, `/lib`, `/lib32`, `/lib64`, `/libx32`, `/opt`,
  `/proc`, `/root`, `/run`, `/sbin`, `/srv`, `/sys`, `/usr`, `/usr/bin`, `/usr/lib`, `/usr/local`, `/usr/sbin` and
  `/var` are refused with exit 4. Their modes come from your packages, and `sudo fixperms /usr` would break `sudo`
  itself. A folder inside them, such as `/srv/www/shop`, is fine.
- **Your home folder.** `fixperms ~` is refused with exit 4, because `~/.ssh` needs `700` and `600` and `ssh` stops
  working with `755`. Pick a folder inside your home instead.
- **`--force`** skips both of those checks. Nothing skips the next ones.
- **Symlinks.** `fixperms` never follows a symlink. A path you name that is a link is refused with exit 4.
  Links inside the tree are skipped, so a link to `/etc` inside your project cannot lead `fixperms` there.
- **Special bits.** A folder or file with setuid, setgid or the sticky bit is left alone and counted as
  `left alone`. A shared folder with setgid, such as `2775`, keeps its mode.
- **The question.** Without a terminal and without `-y`, `fixperms` exits 4. Answering no exits 5.

The checks look at the path you type and at the real path behind it. `/bin` on Debian 13 is a link to `/usr/bin`,
and both are refused as system folders.

## Pass-through

`fixperms` takes no options for `find` or `chmod`. Use `-x` to skip names.

## Needs

`find`, `chmod` and `stat`, from findutils and coreutils. Every distro has them. BusyBox has all three, and its
`find` supports the `-perm /mode` tests that `fixperms` uses.

## Examples

### Fix a site copied from a USB stick

```console
$ fixperms site
site has 4 folders and 5 files.
  folders to 755        3  now 777
  files to 644          3  now 666, 600
  files to 755          2  deploy.sh, css/main.css
Change 8 modes? [y/N] y
8 changed.
$ fixperms site
site has 4 folders and 5 files.
Nothing to change, every mode is already right.
```

### Only the files, with no programs

```console
$ fixperms -n --files --no-exec site
site has 4 folders and 5 files.
  files to 644          5  now 666, 777, 775
Dry run, nothing changed.
```

### Leave the git folder and the scripts alone

```console
$ fixperms -n -x .git -x '*.sh' site
site has 3 folders and 4 files.
  folders to 755        3  now 777
  files to 644          3  now 666, 600
  files to 755          1  css/main.css
Dry run, nothing changed.
```

### Make a folder private

```console
$ fixperms -v --private site
fixperms: counting what would change
site has 4 folders and 5 files.
  folders to 700        4  now 777, 755
  files to 600          2  now 666
  files to 700          2  deploy.sh, css/main.css
Change 8 modes? [y/N] y
+ find -P site -type d '!' -perm /7000 '!' -perm 700 -exec chmod 700 '{}' +
+ find -P site -type f '!' -perm /7000 -perm /111 '!' -perm 700 -exec chmod 700 '{}' +
+ find -P site -type f '!' -perm /7000 '!' -perm /111 '!' -perm 600 -exec chmod 600 '{}' +
8 changed.
```

### A shared folder keeps its setgid bit

```console
$ fixperms -n site
site has 5 folders and 5 files.
  folders to 755        3  now 777
  files to 644          3  now 666, 600
  files to 755          2  deploy.sh, css/main.css
  left alone            1  setuid, setgid or sticky bit
Dry run, nothing changed.
```

### Refusals

```console
$ fixperms /etc
fixperms: refused, /etc is a system folder and its modes come from your packages. Pass --force if you are sure
$ fixperms ~
fixperms: refused, /home/khadir is your home folder and ~/.ssh needs 700 and 600. Pick a folder inside it, or pass --force
$ fixperms link
fixperms: refused, link is a symlink to site. fixperms never follows links, give the real path
```

## Troubleshooting

`fixperms: 12 changed, 3 could not change. They belong to another user, so run it with sudo`
: Only the owner and root can change a mode. For a tree that belongs to `www-data`, run `sudo fixperms /srv/www/shop`.

A web server still returns 403
: Every folder above the site needs the `x` bit for the server's user too. `namei -l /srv/www/shop/index.html`
  shows the mode of each folder on the way. On Fedora and RHEL, SELinux can also block reads. Check with
  `ls -Z` and fix the label with `restorecon -R /srv/www/shop`.

A script stopped running after `--no-exec`
: `--no-exec` takes the `x` bit off every file. Put it back with `chmod +x script.sh`.

`ssh` says `bad permissions` after `--force` on your home
: Run `fixperms -y --private ~/.ssh`, which sets the folder to `700` and the keys to `600`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, or there was nothing to change. |
| 1 | It failed. A path is missing, or some modes could not change. |
| 2 | Bad usage, such as a mode like `7777` or no path. |
| 3 | `find`, `chmod` or `stat` is missing. |
| 4 | Refused. A system folder, your home folder, a symlink, or no terminal to ask in. |
| 5 | You answered no. |

## See also

`chmod(1)`, `find(1)`, `namei(1)`
