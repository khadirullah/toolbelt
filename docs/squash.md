# squash

Pack files and folders into any free format.

## Synopsis

```
squash [options] path ... [-- tool options]
squash --compare path ...
```

## Description

`squash` packs one or more files and folders into one archive. It picks the tool, the level and the thread count,
writes the archive, reads it back to test it, and prints one line:

```
site/ -> site.tar.zst (60KB to 26KB, 3 files, 0.0s)
```

The line gives the source, the archive, the size before and after, the number of files and the time it took.

With no options the archive is a `tar.zst` in the current folder. zstd packs about as small as gzip at its best
level and runs many times faster, and every Linux release from the last few years can open it. Pick another
format with `-f`, or name the archive with `-o` and let its extension pick the format.

`squash` never overwrites anything. When the archive name is taken it stops and says which name `-y` would use.
It checks free disk space before it starts. For the levels that need a lot of memory, it checks free memory too
and lowers the thread count to fit.

Every archive is tested before `squash` offers to delete anything. The test reads the whole archive back through
the same tool and counts the entries. When the count differs from the source, or the tool reports damage, the
archive is removed and the source stays. When the test passes and you run `squash` in a terminal, it asks whether
to move the source to the trash. The answer defaults to no, and a no still exits 0. The source goes to the trash,
never straight to `rm`.

A single file with a plain compressor format, such as `-f xz` on a log file, skips tar and becomes `server.log.xz`.
A folder always goes through tar, zip or 7z, since a plain compressor holds one file.

## Options

### Format and strength

| Option | What it does |
|---|---|
| `-f`, `--format FMT` | The format. `tar.zst` by default. The table under Formats lists every name. |
| `-l`, `--level 1..9` | 1 is the fastest and 9 the smallest, in every format. `squash` maps it onto the tool's own scale. |
| `--max` | The tool's real top level, past what `-l 9` gives, such as `zstd --ultra -22`. Slow, and hungry for memory. |
| `-T`, `--threads N` | Threads for the tools that can use them. The default is every CPU, from `nproc`. |
| `--compare` | Pack a sample in every installed format and print a table of size, ratio and time. Writes no archive. |

### What goes in

| Option | What it does |
|---|---|
| `-x`, `--exclude PAT` | Leave out files and folders whose name matches, at any depth. Can repeat. |
| `-o`, `--out NAME` | Name the archive. Its extension picks the format when there is no `-f`. A folder puts the archive there. |
| `-s`, `--split SIZE` | Write parts of SIZE, such as `25M`, `700M` or `4G`. Units are powers of 1024. |
| `-p`, `--password` | Ask for a password, twice. zip and 7z only. |

### After writing

| Option | What it does |
|---|---|
| `-t`, `--test` | Print the test result. The test runs anyway when `squash` would offer to delete the source. |
| `--rm` | Move the source to the trash once the test passes, without asking. |
| `-k`, `--keep` | Keep the source and never ask. |
| `-y`, `--yes` | When the archive exists, write the next free name, such as `site-1.tar.zst`. |
| `-q`, `--quiet` | Print only the summary line and errors. |
| `-v`, `--verbose` | Print each step, and each real command before it runs. |
| `-h`, `--help` | Print the help. |

`--rm` and `-k` contradict each other, and so do `-l` and `--max`. `--rm` with `-x` is refused, since it would
delete the files that `-x` left out of the archive. With `-x`, `squash` never offers to delete the source.

## Formats

| Format | Extension | Tool, first choice then fallback | Package (apt) | Threads | `-l 1..9` becomes |
|---|---|---|---|---|---|
| `tar.zst` | `.tar.zst` | zstd | zstd | yes | zstd 1, 3, 5, 7, 10, 12, 14, 16, 19 |
| `tar.gz` | `.tar.gz` | pigz, then gzip | pigz, gzip | pigz only | 1 to 9 |
| `tar.bz2` | `.tar.bz2` | pbzip2, then bzip2 | pbzip2, bzip2 | pbzip2 only | 1 to 9 |
| `tar.xz` | `.tar.xz` | xz | xz-utils | yes | 1 to 9 |
| `tar.lzma` | `.tar.lzma` | `xz --format=lzma` | xz-utils | no | 1 to 9 |
| `tar.lz4` | `.tar.lz4` | lz4 | lz4 | no | lz4 1, 2, 3, 5, 6, 7, 9, 10, 12 |
| `tar.lz` | `.tar.lz` | plzip, then lzip | plzip, lzip | plzip only | 1 to 9 |
| `tar.lzo` | `.tar.lzo` | lzop | lzop | no | 1 to 9 |
| `tar.br` | `.tar.br` | brotli | brotli | no | brotli 1, 2, 3, 4, 6, 7, 8, 9, 11 |
| `zip` | `.zip` | zip, or 7z for a password | zip, 7zip | no | 1 to 9 |
| `7z` | `.7z` | 7z | 7zip | yes | 7z 1, 3, 3, 5, 5, 7, 7, 9, 9 |
| `tar` | `.tar` | tar | tar | no | no compression |

The plain forms `zst`, `gz`, `bz2`, `xz`, `lzma`, `lz4`, `lz`, `lzo` and `br` compress one file without tar. On
a folder they become the tar form, so `-f zst` on a folder writes a `.tar.zst`. `-f` also takes the short names
`tgz`, `tbz2`, `txz`, `tzst` and `tzo`, and the tool names `gzip`, `zstd`, `lzip`, `lzop` and `brotli`.

rar is refused. Only the paid WinRAR tool can write rar, and `squash` sticks to free tools. `unpack` still opens
rar archives.

With no `-l`, each tool runs at its own default level. zstd uses 3, gzip and xz use 6, bzip2 uses 9, lz4 uses 1,
and 7z uses 5. brotli defaults to 11, which is far too slow for an archive, so `squash` gives it `-q 6` instead.

`--max` means the level past 9 where a tool has one.

| Format | `--max` runs |
|---|---|
| `tar.zst` | `zstd --ultra -22` |
| `tar.gz` | `pigz -11`, which runs zopfli, or `gzip -9` without pigz |
| `tar.xz`, `tar.lzma` | `xz -9e` |
| `tar.lz4` | `lz4 -12` |
| `tar.br` | `brotli -q 11 -w 24` |
| the others | the same as `-l 9` |

### Which one to pick

- **tar.zst** for almost everything. Fast at every level, small at `-l 9`, and it uses every CPU.
- **zip** for someone on Windows or macOS. Both open it without installing anything. It compresses each file on
  its own, so many small similar files pack worse than in a tar format.
- **7z** for the smallest archive a Windows user can still open, and for a password that also hides the file
  names.
- **tar.xz** for a source release, where people expect it, or when size matters more than time. `-l 9` needs about
  674MB of memory a thread.
- **tar.gz** for an old machine or a tool that only knows gzip. With pigz installed it uses every CPU.
- **tar.lz4** when speed is all that matters, such as a backup piped to another disk. It packs worst of all.
- **tar.bz2**, **tar.lz**, **tar.lzo**, **tar.lzma** and **tar.br** when someone asks for them. None of them
  beats zstd or xz for a new archive.
- **tar** with no compression for files that are already compressed, such as photos, videos and other archives.
  It is the fastest, and compressing a JPEG again saves almost nothing.

`--compare` answers the question for your own files. See the example below.

## Output name

With no `-o`, the archive goes in the current folder and takes the source's name plus the extension, so
`squash site/` writes `site.tar.zst`. When the current folder is inside the source, as with `squash .`, the
archive goes next to the source instead, since it must not land inside what it packs. Several sources share one
archive named after the first, as in `site/, server.log -> site.tar.zst`.

With `-o NAME`, the name's extension picks the format when there is no `-f`. `-o site.zip` writes a zip.

- When the name has no archive extension, `squash` adds one, so `-f 7z -o backup` writes `backup.7z`.
- When the name ends in a folder, the archive goes there under its default name.
- When `-f` and the extension disagree, `squash` stops, since one of them is a typo.
- When the name holds a single file, such as `-o site.zst` for a folder, `squash` stops and names the fix,
  `site.tar.zst`.

## Split archives

`-s SIZE` writes the archive in parts no bigger than SIZE, for a file host with a size limit or a FAT32 stick.

| Format | Parts | Join or open with |
|---|---|---|
| tar formats | `name.tar.zst.001`, `.002`, ... | `cat name.tar.zst.0* > name.tar.zst`, or `unpack name.tar.zst.001` |
| `7z` | `name.7z.001`, `.002`, ... | `7z x name.7z.001`, or `unpack name.7z.001` |
| `zip` | `name.z01`, `name.z02`, ..., `name.zip` | `7z x name.zip`, or `unpack name.zip` |

zip parts must be 64K or larger, a limit of zip itself. The test reads every part back, and the summary line
names the first and last part.

## Passwords

`-p` asks for the password twice, with no echo. The two answers must match, and an empty password is refused.
Nothing is written until the password is settled. `-p` needs a terminal, so a script or cron job gets exit 4 and
never hangs on a prompt.

- **7z** uses AES-256 and hides the file names too (`-mhe=on`). Nobody can list the archive without the password.
- **zip** uses AES-256 through 7z, since the zip tool only knows the old ZipCrypto, which known attacks break.
  The names inside stay visible. 7-Zip and `unpack` open AES zips, and Windows Explorer on Windows 10 does not.

tar formats have no password. `-p` with a tar format exits 2 and points to `lock`, which encrypts any file with
age or gpg:

```console
$ squash -p site/
squash: -p works with zip and 7z only. For a tar.zst, run lock on the archive afterwards
Try 'squash --help' for the options.
```

## Excluding files

`-x PAT` leaves out files and folders whose name matches, at any depth. Repeat it for more patterns. Quote each
pattern so the shell does not expand it first.

```
squash -x node_modules -x '*.o' -x .git src/
```

tar gets `--exclude`, zip gets `-x` with the same pattern at every depth, and 7z gets `-xr!`. Since the archive
now holds less than the source, the entry count cannot be checked. The test still reads every byte back.

## Checks before writing

- **Disk space.** `squash` adds up the source and compares it with the free space where the archive goes. When
  the source is bigger, it stops with exit 4 and names both sizes. The archive is almost always smaller, so this
  check is strict on purpose.
- **Memory.** `xz -l 7` and above, and `zstd --max`, need a lot of memory for each thread. `squash` reads
  `MemAvailable` and uses the most threads that fit in 90% of it. When even one thread does not fit, it stops
  with exit 4 and asks for a lower `-l`.
- **Place.** The archive may not land inside a folder it packs.
- **Name.** An existing file is never replaced. With `-y` the archive takes the next free name.

`squash` writes into a temporary file next to the final one and renames it only after the test passes. A failed
or interrupted run leaves no half-written archive behind.

## Pass-through

Options after `--` go to the tool that compresses, placed after the options `squash` builds, so they win.

| Format | Gets the options | Example |
|---|---|---|
| tar formats | the compressor | `squash -f xz src/ -- --check=sha256` |
| `tar.zst` | zstd | `squash photos/ -- --long=27` |
| `tar` | tar | `squash -f tar src/ -- --owner=0 --group=0` |
| `zip` | zip | `squash -f zip site/ -- -9` |
| `7z` | 7z | `squash -f 7z data/ -- -ms=off` |

`-v` shows where they went:

```console
$ squash -v -f 7z -o p.7z site/ -- -mx=9 -ms=off 2>&1 | grep '^+'
+ 7z a -t7z -bso0 -bsp0 -snl -mmt=4 -mx=9 -ms=off p.7z /home/sam/site
$ squash -v -f tar.xz -o q.tar.xz site/ -- --check=sha256 2>&1 | grep '^+'
+ tar -cf - site | xz -c -T 4 --check=sha256 > q.tar.xz
$ squash -v -f tar -o q.tar site/ -- --owner=0 --group=0 2>&1 | grep '^+'
+ tar -cf - --owner=0 --group=0 site > q.tar
```

With `--compare`, options after `--` are ignored.

## Needs

`tar` and the tool for the format you pick. zstd is the default, so install it at least. `pv` is optional and
draws a progress bar in a terminal.

| Tool | apt | dnf | pacman | zypper | apk |
|---|---|---|---|---|---|
| zstd | zstd | zstd | zstd | zstd | zstd |
| gzip | gzip | gzip | gzip | gzip | gzip |
| pigz | pigz | pigz | pigz | pigz | pigz |
| bzip2 | bzip2 | bzip2 | bzip2 | bzip2 | bzip2 |
| pbzip2 | pbzip2 | pbzip2 | pbzip2 | pbzip2 | pbzip2 |
| xz | xz-utils | xz | xz | xz | xz |
| lz4 | lz4 | lz4 | lz4 | lz4 | lz4 |
| lzip | lzip | lzip | lzip | lzip | lzip |
| plzip | plzip | plzip | plzip | plzip | none |
| lzop | lzop | lzop | lzop | lzop | lzop |
| brotli | brotli | brotli | brotli | brotli | brotli |
| zip, unzip | zip, unzip | zip, unzip | zip, unzip | zip, unzip | zip, unzip |
| 7z | 7zip | 7zip | 7zip | 7zip | 7zip |

Per distro:

- **Debian and Ubuntu.** Newer releases have `7zip`. Older ones name the package `p7zip-full`, and its `7z` works
  the same way here.
- **Fedora and RHEL.** Fedora has every tool. On RHEL and its rebuilds, several of them come from EPEL.
- **Arch.** Every tool is in the main repos.
- **openSUSE.** `7zip` on newer releases, `p7zip-full` on older Leap.
- **Alpine.** plzip has no package, so `tar.lz` uses lzip with one thread. `squash` needs GNU `tar`, so install
  the `tar` package rather than relying on BusyBox.

When a tool is missing, `squash` exits 3 and prints the install line for your package manager.

## Examples

### Pack a folder

```console
$ squash site/
site/ -> site.tar.zst (60KB to 26KB, 3 files, 0.0s)
```

### A zip for someone on Windows

```console
$ squash -f zip -o site.zip site/
site/ -> site.zip (60KB to 29KB, 3 files, 0.0s)
```

### Compress one log file

A single file with a plain format skips tar:

```console
$ squash -f xz server.log
server.log -> server.log.xz (106KB to 4.8KB, 1 file, 0.0s)
```

### Keep or trash the source

In a terminal, `squash` asks once the test passes:

```console
$ squash -f 7z site2/
site2/ -> site2.7z (60KB to 22KB, 3 files, 0.0s)
Delete the source, site2/ (3 files, 60 KB)? It goes to the trash. [y/N] y
site2/ is in the trash.
```

### An archive name that is taken

```console
$ squash site/
squash: site.tar.zst already exists. Pass -y to write site-1.tar.zst, or pick a name with -o
$ squash -y site/
site.tar.zst exists, writing site-1.tar.zst
site/ -> site-1.tar.zst (60KB to 26KB, 3 files, 0.0s)
```

### Leave out build output and print the test

```console
$ squash -t -x node_modules -x '*.o' -f 7z src/
src/ -> src.7z (40KB to 1.9KB, 3 files, 0.0s)
test passed: src.7z, 3 entries
src/ stays, -x left files out of the archive.
```

### Split into parts

```console
$ squash -s 10K -f tar.gz -o parts site/
site/ -> parts.tar.gz.001 to .004 (60KB to 31KB, 3 files, 0.0s)
$ ls parts*
parts.tar.gz.001  parts.tar.gz.002  parts.tar.gz.003  parts.tar.gz.004
```

### A 7z with a password

```console
$ squash -f 7z -p -o secret.7z site/
Password:
Again:
site/ -> secret.7z (60KB to 22KB, 3 files, 0.0s)
```

### Every step, with the real commands

```console
$ squash -v -l 9 -o v.tar.zst site/
squash: site/: 3 files, 60KB
squash: format: tar.zst, from the name v.tar.zst
squash: level: -l 9 is zstd -19
squash: threads: 4, zstd -T4
+ tar -cf - site | zstd -c -q --size-hint=61465 -19 -T4 > v.tar.zst
site/ -> v.tar.zst (60KB to 25KB, 3 files, 0.0s)
```

### Compare every format on your own files

`--compare` packs up to the first 8MB of the source in each installed format at `-l 6`, sorts the table by size,
and writes no archive. When the source is bigger, the last line estimates the time for all of it.

```console
$ squash --compare site/
sample: all of site/ (60KB), every format at -l 6
format        size   ratio    time
tar.lz        21KB    3.2x    0.0s
tar.lzma      22KB    3.2x    0.0s
tar.xz        22KB    3.2x    0.0s
7z            22KB    3.2x    0.0s
tar.bz2       26KB    2.7x    0.0s
tar.zst       26KB    2.7x    0.0s
zip           30KB    2.3x    0.0s
tar.gz        31KB    2.2x    0.0s
tar.lz4       33KB    2.1x    0.0s
tar.lzo       36KB    1.9x    0.0s
skipped: tar.br, brotli is not installed
```

### rar is refused

```console
$ squash -f rar site/
squash: rar is not supported for creating, it needs the paid WinRAR tool. Use -f 7z or -f zip. unpack still opens rar
Try 'squash --help' for the options.
```

## Troubleshooting

**"already exists. Pass -y to write ..."** An archive with that name is there. Pass `-y` to take the next free
name, pick one with `-o`, or move the old archive away first. `squash` never replaces a file.

**"... is 2.1 GB and . has 1.4 GB free"** The disk check compares the whole source with the free space. Write
somewhere else with `-o /other/disk/`, or free some space.

**"xz at this level needs about 674 MB and 512 MB of memory is free. Use a lower -l"** Even one thread does not
fit. Use `-l 6` or lower, close some programs, or pick `tar.zst`, which needs far less memory at `-l 9`.

**"4 threads need about 3.4 GB of memory and 2.1 GB is free, using 2"** A warning, not an error. The archive
comes out the same, only slower. Pass `-T 1` to use one thread from the start.

**"the test failed. The archive was not kept and the source stays"** The tool wrote an archive it could not read
back, or the entry count differs from the source. The message above it says which. The usual causes are a
failing disk, too little space in the middle of the write, or a file removed while `squash` read the folder. Run
again with `-v` to see each command.

**"a file changed while squash read it"** A log or database was written to during the pack. The archive holds the
version tar saw. Stop the program that writes, or copy the file first, for a clean copy.

**"zip needs every path in one folder"** zip stores paths relative to one folder. Move the sources into one
folder, or use a tar format, which handles paths from anywhere.

**"-p asks for the password in a terminal, and there is none"** `-p` never reads a password from a pipe. For a
script, write a tar format and encrypt it with `lock`, which can read a key file.

**A zip with a password does not open in Windows Explorer.** Older Explorer versions only know ZipCrypto, and
`squash` uses AES-256. Send a 7z instead, or tell the person to use 7-Zip.

**The archive is barely smaller than the source.** The files are already compressed, such as JPEG, MP4 or other
archives. Use `-f tar`, which is faster and comes out almost the same size.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The archive is written and tested. Also 0 when you answer no to the delete question. |
| 1 | Packing or the test failed, the passwords differ, or a source is missing. Nothing was kept. |
| 2 | Bad usage, including rar, `-p` with a tar format, and a name whose extension disagrees with `-f`. |
| 3 | The tool for the format is missing. The message has the install line. |
| 4 | A safety check refused, such as an existing name, too little disk or memory, or no terminal for `-p`. |

## See also

`unpack`, `archdiff`, `archmount`, `lock`, `tar(1)`, `zstd(1)`, `xz(1)`, `7z(1)`
