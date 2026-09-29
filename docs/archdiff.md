# archdiff

List what changed between two archives.

## Synopsis

```
archdiff [options] old new [-- diff options]
```

## Description

`archdiff` compares the files inside two archives without unpacking them to disk. It prints one line for each
file that was added, removed or changed, then a count:

```
+ templates/hpa.yaml         216B
- templates/NOTES.txt         10B
~ Chart.yaml                  25B -> 25B
~ templates/service.yaml     261B -> 270B
~ values.yaml                 73B -> 73B
1 added, 1 removed, 3 changed, 1 the same
```

`+` is a file only in the new archive, `-` a file only in the old one, and `~` a file in both whose content
differs, with its size in each. Files that are the same are only counted.

The two archives can be in different formats. A `tgz` against a `tar.zst`, or a `zip` against a `7z`, works the
same as two of a kind, since `archdiff` compares the files and not the bytes of the archive.

It reads, and writes nothing. The old archive goes first, like `diff`.

## Options

| Option | What it does |
|---|---|
| `-c`, `--content` | Print a unified diff under each changed text file. Binary files get `binary files differ`. |
| `--only PAT` | Compare only the files that match. Can repeat. |
| `-x`, `--exclude PAT` | Leave out the files that match. Can repeat. |
| `-q`, `--quiet` | Print only the count line. |
| `-v`, `--verbose` | Print each step, and each real command before it runs. |
| `-h`, `--help` | Print the help. |

A pattern matches a file when it matches the whole path, the file name, or any folder in the path. So
`-x templates` leaves out everything under any `templates/` folder, and `--only '*.yaml'` keeps every YAML file
at any depth. Quote each pattern so the shell does not expand it first. `--only` runs first, then `-x` removes
from what is left.

## How it compares

Two files are the same when their sizes and their sha256 hashes match. Names are compared as paths inside the
archive, with a leading `./` removed.

- **tar formats.** `archdiff` streams each archive once through the decompressor and GNU tar. tar hands every
  file to `sha256sum` as it goes past, with `--to-command`, so nothing lands on disk and a large archive costs
  only the time to read it.
- **zip and 7z.** These have an index, so `archdiff` reads the names and sizes from it first. It hashes only the
  files whose sizes match on both sides, one at a time, since a different size already means a change.
- **A single compressed file**, such as `notes.txt.gz`, counts as one file named without the extension. Two of
  them compare as one file each.

Folders, symlinks and empty folders are not compared. Permissions, owners and times are not compared either, only
content.

### Top folder

Release archives often put everything under a folder named after the version, such as `app-1.4/` and `app-1.5/`.
When each archive has exactly one top folder and the names differ, `archdiff` strips them, so
`app-1.4/values.yaml` lines up with `app-1.5/values.yaml`. `-v` says when it does this.

### Format detection

The name decides first, such as `.tar.zst`, `.tgz`, `.zip`, `.jar`, `.whl`, `.7z` or `.iso`. When the name says
nothing, `archdiff` reads the first bytes, so a renamed `download.bin` that is really a `tgz` still works. A
compressed stream counts as a tar when the decompressed bytes carry the tar header.

### Content diffs

With `-c`, each changed file is pulled out of both archives into a private temporary folder, compared with
`diff -u`, and deleted straight away. The temporary folder is gone when `archdiff` exits, on Ctrl+C too. The diff
headers name the archive and the path, as in `--- app-1.4.tgz/values.yaml`, so the output reads well in a review
or a ticket.

A file is text when its first 8KB hold no NUL byte.

## Pass-through

With `-c`, options after `--` go to `diff`. `-U 0` shows only the changed lines, `-w` ignores whitespace, and
`--color=always` colours the output for a pager.

```
archdiff -c app-1.4.tgz app-1.5.tgz -- -U 0
archdiff -c old.zip new.zip -- -w
```

Without `-c` there is no diff to pass them to, so `--` exits 2.

## Needs

`sha256sum`, and the tools for the formats you compare. `diff` for `-c`.

| Format | Tool | apt | dnf | pacman | zypper | apk |
|---|---|---|---|---|---|---|
| tar formats | tar | tar | tar | tar | tar | tar |
| `.gz` | gzip | gzip | gzip | gzip | gzip | gzip |
| `.bz2` | bzip2 | bzip2 | bzip2 | bzip2 | bzip2 | bzip2 |
| `.xz`, `.lzma` | xz | xz-utils | xz | xz | xz | xz |
| `.zst` | zstd | zstd | zstd | zstd | zstd | zstd |
| `.lz4` | lz4 | lz4 | lz4 | lz4 | lz4 | lz4 |
| zip | unzip, or 7z | unzip | unzip | unzip | unzip | unzip |
| 7z, rar, iso | 7z | 7zip | 7zip | 7zip | 7zip | 7zip |
| `-c` | diff | diffutils | diffutils | diffutils | diffutils | diffutils |

`archdiff` needs GNU tar for `--to-command`. On Alpine, install the `tar` package, since BusyBox tar lacks it.
On Debian and Ubuntu releases before `7zip` was packaged, `p7zip-full` gives the same `7z`.

## Examples

### Two releases of a Helm chart

```console
$ archdiff app-1.4.tgz app-1.5.tgz
+ templates/hpa.yaml         216B
- templates/NOTES.txt         10B
~ Chart.yaml                  25B -> 25B
~ templates/service.yaml     261B -> 270B
~ values.yaml                 73B -> 73B
1 added, 1 removed, 3 changed, 1 the same
```

### What changed in one file

```console
$ archdiff -c --only values.yaml app-1.4.tgz app-1.5.tgz
~ values.yaml      73B -> 73B
--- app-1.4.tgz/values.yaml
+++ app-1.5.tgz/values.yaml
@@ -1,6 +1,6 @@
-replicas: 2
+replicas: 3
 image:
-  tag: "1.4.0"
+  tag: "1.5.0"
 resources:
   limits:
-    memory: 256Mi
+    memory: 512Mi
0 added, 0 removed, 1 changed, 0 the same
```

### Only the changed lines

```console
$ archdiff -c --only values.yaml app-1.4.tgz app-1.5.tgz -- -U 0
~ values.yaml      73B -> 73B
--- app-1.4.tgz/values.yaml
+++ app-1.5.tgz/values.yaml
@@ -1 +1 @@
-replicas: 2
+replicas: 3
@@ -3 +3 @@
-  tag: "1.4.0"
+  tag: "1.5.0"
@@ -6 +6 @@
-    memory: 256Mi
+    memory: 512Mi
0 added, 0 removed, 1 changed, 0 the same
```

### A zip against a tar.zst of the same folder

```console
$ archdiff site.zip site.tar.zst
no differences, 3 files
```

### Leave out the templates

```console
$ archdiff -x templates app-1.4.tgz app-1.5.tgz
~ Chart.yaml       25B -> 25B
~ values.yaml      73B -> 73B
0 added, 0 removed, 2 changed, 0 the same
```

### In a script

The exit status says whether anything changed, and `-q` keeps the output to one line:

```console
$ archdiff -q app-1.4.tgz app-1.5.tgz
1 added, 1 removed, 3 changed, 1 the same
$ echo $?
1
```

### The commands it runs

```console
$ archdiff -v --only Chart.yaml app-1.4.tgz app-1.5.tgz
archdiff: app-1.4.tgz: tar.gz
archdiff: app-1.5.tgz: tar.gz
+ gzip -dc < app-1.4.tgz | tar -xf - --to-command='h=$(sha256sum) && printf "%s\t%s\t%s\n" "${h%% *}" "$TAR_SIZE" "$TAR_FILENAME"'
+ gzip -dc < app-1.5.tgz | tar -xf - --to-command='h=$(sha256sum) && printf "%s\t%s\t%s\n" "${h%% *}" "$TAR_SIZE" "$TAR_FILENAME"'
archdiff: comparing app-1.4/ with app-1.5/
~ Chart.yaml      25B -> 25B
0 added, 0 removed, 1 changed, 0 the same
```

## Troubleshooting

**"not an archive archdiff can read"** Neither the name nor the first bytes match a format `archdiff` knows. Check
the file with `file NAME`. A download that stopped halfway is often an HTML error page.

**"could not read the archive"** The tool failed part way, and its own message is printed above. The archive is
damaged or cut short. `unpack -t` tests it on its own.

**Every file shows as removed and added.** The two archives have different top folders, and one of them has more
than one, so `archdiff` cannot line them up. Compare with `--only` on the part you care about, or repack one side.

**A file shows as changed but the diff is empty.** Only the line endings or trailing whitespace changed. Run with
`-c -- -w` or `--strip-trailing-cr` to confirm.

**It is slow on a large zip.** Files with the same size on both sides get hashed, which means reading them.
Narrow the list with `--only`.

## Exit status

`archdiff` follows `diff`.

| Code | Meaning |
|---|---|
| 0 | The archives hold the same files, after `--only` and `-x`. |
| 1 | At least one file was added, removed or changed. |
| 2 | Bad usage, or an archive is missing, unreadable, damaged or in no known format. |
| 3 | A tool for one of the formats is missing. The message has the install line. |

## See also

`squash`, `unpack`, `archmount`, `diff(1)`, `tar(1)`
