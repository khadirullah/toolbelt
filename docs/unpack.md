# unpack

Unpack any archive, from a file or a URL.

## Synopsis

```
unpack [options] archive|url ... [-- tool options]
unpack --undo | --history
```

## Description

`unpack` takes an archive and turns it into files, whatever the format. You do not need to remember that a
`.tar.zst` wants `tar --zstd -xf`, that a `.7z.001` wants `7z x` on the first part, or that a `.deb` is an `ar`
file with a tar inside. `unpack` works that out, picks the tool, and runs it.

It reads the archive twice. The first pass lists every entry without writing anything. `unpack` checks that list
for paths that would land outside the target folder, for links that point out of it, for disk space, for memory,
and for archives that grow more than 100 times their size. Only when every check passes does the second pass write
files.

The files go into a hidden temp folder first, such as `.unpack-GttVuf`, in the folder where they will end up. When
the tool finishes, `unpack` counts the files on disk and compares the count with the listing. Then it moves the
result into place with one rename. If anything fails before that rename, the temp folder is removed and nothing
you can see has changed.

After a checked unpack in a terminal, `unpack` asks whether to move the archive to the trash. It never deletes
anything for good. Every run is recorded, and `unpack --undo` moves the last result to the trash and brings a
trashed archive back.

`unpack` never overwrites a file or folder that already exists. It never runs as root on its own, never follows a
link out of the target, and never reads a password from the command line.

## Options

| Option | What it does |
|---|---|
| `-H`, `--here` | Put the files in the current folder, or in the `-o` folder. Falls back to a new folder when a name would clash. |
| `-d`, `--dir` | Always make a new folder named after the archive, even when the archive holds one top folder. |
| `-o`, `--out DIR` | Unpack into DIR instead of the current folder. `unpack` makes DIR when it does not exist. Combines with `-H` and `-d`. |
| `-l`, `--list` | List the contents and unpack nothing. |
| `-t`, `--test` | Read every file to check the archive, and unpack nothing. |
| `--only PATTERN` | Unpack only the entries that match a shell pattern, such as `'*.yaml'`. Repeat it for more patterns. |
| `--cat FILE` | Print one file from the archive to stdout. FILE is the path as `-l` shows it. |
| `-p`, `--password` | Ask for the password of a zip, 7z or rar. In a terminal it asks without echo. In a script it reads one line of stdin. |
| `-r`, `--recursive` | Also unpack archives found inside, up to 3 levels deep. Each inner archive is replaced by its contents. |
| `--sandbox` | Run the unpack inside a podman container with no network and the archive mounted read-only. Uses docker when podman is missing. |
| `--rm` | Move the archive to the trash after a checked unpack, without asking. |
| `-k`, `--keep` | Keep the archive and never ask. |
| `-y`, `--yes` | Go past the memory check and the size ratio check. With `--undo`, undo without asking. |
| `--undo` | Move what the last unpack made to the trash, and bring its archive back if it went to the trash. |
| `--history` | List past unpacks, newest first. |
| `-q`, `--quiet` | Show only the result line. |
| `-v`, `--verbose` | Show every step, and each real command before it runs. |
| `-h`, `--help` | Show the help. |

Use only one of `-l`, `-t`, `--cat`, `--undo` and `--history` at a time. `--rm` and `-k` cannot go together.
`--cat` reads one archive. `--sandbox` works for a normal unpack only, not with `-l`, `-t` or `--cat`.

## Formats

`unpack` knows these formats. Each compressor works on its own, for a single file, and around a tar.

| Format | Names | Tool | Debian 13 package |
|---|---|---|---|
| tar | `.tar` | tar | `tar` |
| gzip | `.gz`, `.tar.gz`, `.tgz`, `.taz` | pigz, or gzip | `pigz`, `gzip` |
| bzip2 | `.bz2`, `.bz`, `.tar.bz2`, `.tbz2`, `.tbz`, `.tb2` | pbzip2, or bzip2 | `pbzip2`, `bzip2` |
| xz | `.xz`, `.tar.xz`, `.txz` | xz | `xz-utils` |
| lzma | `.lzma`, `.tar.lzma`, `.tlzma` | `xz --format=lzma` | `xz-utils` |
| zstd | `.zst`, `.zstd`, `.tar.zst`, `.tzst` | zstd | `zstd` |
| lz4 | `.lz4`, `.tar.lz4`, `.tlz4` | lz4 | `lz4` |
| lzip | `.lz`, `.tar.lz`, `.tlz` | plzip, or lzip | `plzip`, `lzip` |
| lzop | `.lzo`, `.tar.lzo`, `.tzo` | lzop | `lzop` |
| brotli | `.br`, `.tar.br`, `.tbr` | brotli | `brotli` |
| compress | `.Z`, `.tar.Z`, `.tz` | gzip, or uncompress | `gzip`, `ncompress` |
| zip | `.zip`, `.jar`, `.war`, `.ear`, `.whl` | unzip, or 7z | `unzip`, `7zip` |
| 7z | `.7z` | 7z | `7zip` |
| rar | `.rar` | unrar, or 7z, or unar | `unrar`, `7zip`, `unar` |
| deb | `.deb`, `.udeb`, `.ddeb` | dpkg-deb, or ar and tar | `dpkg`, `binutils` |
| rpm | `.rpm` | rpm2cpio and cpio | `rpm2cpio`, `cpio` |
| cpio | `.cpio`, `.cpio.gz` and the other compressors | cpio | `cpio` |
| iso | `.iso` | 7z, or bsdtar | `7zip`, `libarchive-tools` |
| initramfs | `initrd.img-*`, `initrd-*`, `initramfs*` | unmkinitramfs, or cpio | `initramfs-tools-bin`, `cpio` |
| URL | `http://`, `https://`, `file://` | curl | `curl` |

When two tools can do the job, `unpack` takes the faster one. pigz, pbzip2 and plzip use every core, so they win
over gzip, bzip2 and lzip when installed. `-v` says so in a line such as `tool: pigz, in place of gzip`.

For zip, `unpack` uses unzip when it can, because unzip is on almost every machine. It switches to 7z for a zip
with a password, since unzip cannot read AES encryption, and for split zips.

For rar, unrar comes first. On distros that do not ship unrar, the 7z from the `7zip` package reads rar too.
unar is the last choice.

A deb goes to `dpkg-deb --fsys-tarfile`, which reads every compression a deb can use. Without dpkg-deb, `unpack`
pulls `data.tar.*` out with `ar p` and decompresses it itself. Only the files of the package come out, not the
control scripts.

## How it recognises a file

`unpack` looks at the name first. A name it does not know, such as `backup.bin` or `download`, gets a second look
at the content with `file -z`, which also looks inside a compressed stream. When `file` sees gzip and nothing more,
`unpack` decompresses the first 8KB and asks `file` again, so a tar inside a plain `.gz` is found too.

When the name and the content disagree, the content wins if the outer layer differs. A file called `site.tar.gz`
that is really a zip is unpacked as a zip. A plain `.gz` that holds a tar is unpacked as a tar. `-v` shows which
one decided:

```console
$ unpack -v backup.bin
unpack: backup.bin: tar.gz, from the content, the name did not say
```

A name with no known extension and a single compressor around a non-archive, such as `access.log.gz`, becomes that
one file, `access.log`.

## Multi-part sets

A large archive often comes in parts. Give `unpack` any one part and it finds the rest in the same folder, puts
them in order, and reads them as one stream. It never joins them into a big temp file on disk, except for split
zips when only unzip is there, because unzip needs one file it can seek in.

| Pattern | Example | First part | How it reads them |
|---|---|---|---|
| `.partN.rar` | `film.part1.rar`, `film.part2.rar` | `.part1.rar` | The rar tool follows the parts itself. |
| `.rNN` | `old.rar`, `old.r00`, `old.r01` | `.rar` | The rar tool follows the parts itself. |
| `.7z.NNN` | `photos.7z.001`, `photos.7z.002` | `.001` | 7z follows the parts itself. |
| `.zip.NNN` | `site.zip.001`, `site.zip.002` | `.001` | 7z follows the parts. Without 7z, `cat` joins them into a temp zip for unzip. |
| `.zNN` | `mail.z01`, `mail.z02`, `mail.zip` | `.z01` | 7z reads the set. Without 7z, `zip -s 0` joins it for unzip. The `.zip` is the last part. |
| `.aa` | `backup.tar.gz.aa`, `backup.tar.gz.ab` | `.aa` | `cat` joins them into the decompressor. This is what `split` makes. |
| `.NNN` | `backup.tar.001`, `backup.tar.002` | `.001` | `cat` joins them. This is what `split -d -a 3` and many tools make. |
| `.NN` | `backup.tar.gz.00`, `backup.tar.gz.01` | `.00` | `cat` joins them. This is what `split -d` makes. |

For `.aa` and `.NN`, the name in front must be an archive name `unpack` knows, such as `backup.tar.gz`. Otherwise
`notes.ab` would count as a part.

Every part in the middle must be there. A gap is an error that names the missing part and lists what was found:

```console
$ unpack site.tar.gz.001
unpack: site.tar.gz: part .003 is missing, found .001 .002 .004 .005
```

A few gaps have their own messages:

```console
$ unpack old.r00
unpack: old.rar: the first part old.rar is missing
$ unpack mail.z01
unpack: mail.zip: the last part mail.zip is missing
$ unpack mail.zip
unpack: mail.zip: part .z01 is missing, found .zip
```

The last one works because a split zip records how many disks the set has. `unpack` reads that number from the end
of the `.zip`.

A missing part at the end of a `.aa` or `.001` set cannot be seen from the names, because nothing records how many
parts there were. The decompressor then stops early, and `unpack` reports that the archive may be damaged or
incomplete. Nothing is written in that case.

The result line counts the parts:

```console
$ unpack -k backup.tar.gz.ab
backup.tar.gz (4 parts) -> backup/ (24KB, 4 files, 0.0s)
```

## Where the files go

`unpack` has three ways to place the result. The default is smart placement.

Smart placement looks at the top of the listing:

- One top folder, such as `backup/`, comes out as that folder.
- One single file comes out as that file.
- Several entries at the top get a new folder named after the archive, so they do not spill into the current
  folder. `site-2026-09.zip` holding `index.html` and `css/` becomes `site-2026-09/index.html` and
  `site-2026-09/css/`.

The folder name drops every archive extension, so `backup.tar.gz`, `backup.tgz` and `backup.tar.gz.aa` all become
`backup`. A deb, an rpm and an initramfs image always get a folder of their own. `initrd.img-6.12.48-amd64` becomes
`initrd-6.12.48-amd64/`.

`-H` puts the entries right in the current folder, or in the `-o` folder. If any top entry already exists there,
`unpack` falls back to a new folder and says so:

```console
$ unpack -H site.tar
unpack: index.html already exists in ./, using a folder instead
site.tar -> site/ (412KB, 38 files, 0.1s)
```

`-d` always makes a new folder named after the archive, even when the archive holds one top folder. `unpack -d
backup.tar.gz` gives `backup/backup/`.

`-o DIR` changes where all of this happens. `unpack -o ~/restore backup.tar.gz` gives `~/restore/backup/`.

`unpack` never writes over anything. When the name it wants is taken, it adds a number, as in `backup-1/` and
`notes-1.txt`. For a file, the number goes before the extension.

## Safety checks

Every check runs on the listing, before a single file is written. A refusal exits with status 4 and leaves the
disk as it was.

### Paths that escape

An entry whose path leaves the target folder is refused. That covers `../` anywhere in the path, absolute paths
such as `/etc/cron.d/job`, links that point outside the target, and files written through a link that an earlier
entry made. `unpack` shows up to 10 of them:

```console
$ unpack evil.tar
unpack: evil.tar: link x/sh -> /etc/shadow points outside
unpack: evil.tar: ../../.bashrc escapes the target folder
unpack: refused, 2 unsafe paths. Nothing was written.
```

The other messages are `X is an absolute path` and `X is written through a link`.

A deb, an rpm and an initramfs image hold a whole system tree, where links such as `/usr/bin/python3 ->
python3.13` are normal. For those three formats, links with absolute targets are allowed, because they point into
the unpacked tree when you look at it as a root. Paths with `..` are still refused.

### Disk space

`unpack` adds up the size of every entry, plus 4KB for each entry to cover the file system blocks. When the
target disk has less free space than that, it stops:

```console
$ unpack backup.tar.gz
unpack: backup.tar.gz: needs 52KB, /data has 1KB free
unpack: refused. Use -o to unpack onto a disk with more room.
```

### Memory

xz, zstd and 7z can need a lot of RAM to decompress, set by the dictionary or window size the archive was made
with. `unpack` reads that size from the archive and compares it with `MemAvailable` in `/proc/meminfo`.

- For xz it asks `xz --robot --list -vv`.
- For lzma it reads the dictionary size from the header.
- For zstd it reads the window size from `zstd -lv`.
- For 7z it reads the LZMA and LZMA2 dictionary and the PPMd memory from `7z l -slt`.

```console
$ unpack dump.tar.xz
unpack: dump.tar.xz: xz needs 12GB of RAM for this archive, and 3.1GB is free
unpack: refused. Free some memory, or add -y to try anyway.
```

With `-y` it warns and goes on. On a machine with swap, that can work, slowly.

### Size ratio

An archive that grows more than 100 times its size is suspicious. Real data rarely compresses that well, and zip
bombs do. Anything that unpacks to less than 1MB is never flagged.

In a terminal, `unpack` asks:

```console
$ unpack zeros.gz
unpack: zeros.gz: 1.3MB unpacks to 300MB, 229x the archive
Unpack it anyway? [y/N] n
Nothing changed.
```

A no exits with status 5. In a script there is nobody to ask, so it refuses unless `-y` is given:

```console
$ unpack zeros.gz < /dev/null
unpack: zeros.gz: 1.3MB unpacks to 300MB, 229x the archive
unpack: refused, over 100x with no terminal to ask. Add -y.
```

### The file count

After the tool finishes, `unpack` counts the files and links in the temp folder and compares that with the listing.
A mismatch is a warning, not an error, because the files did come out. The archive is then never offered for
deletion, since the result was not verified.

```console
unpack: backup.tar.gz: 199 files on disk, 201 in the listing. The archive stays.
```

## The delete question

After a verified unpack in a terminal, `unpack` offers to move the archive to the trash:

```console
$ unpack backup.tar.gz
backup.tar.gz -> backup/ (31MB, 201 files, 3.1s)
Delete backup.tar.gz (31 MB)? It goes to the trash. [y/N] y
backup.tar.gz is in the trash.
```

For a multi-part set it asks once for every part:

```console
$ unpack backup.tar.gz.aa
backup.tar.gz (4 parts) -> backup/ (31MB, 201 files, 3.4s)
Delete the 4 parts of backup (31 MB)? They go to the trash. [y/N] y
The 4 parts of backup are in the trash.
```

The size is the size of the archive, or of all parts together. The default is no. A no keeps the archive, prints
`Kept backup.tar.gz.` and still exits with status 0, because the unpack worked.

The rules:

- It asks only when the file count matched the listing.
- `--rm` moves the archive to the trash without asking.
- `-k` never asks and keeps the archive.
- In a script, with no terminal, it never asks and keeps the archive, unless `--rm` is given.
- It never asks after `--only`, since the archive still holds files you did not take.
- It never asks after `--cat`, `-l` or `-t`, which write nothing.
- It never asks for a URL. The download was a temp file, and it is already gone.
- It never asks for a file under `/boot`. An initramfs image there belongs to the system.

The trash is `~/.local/share/Trash`, the same one your file manager uses. Restore from there, or with `unpack
--undo`.

## Undo and history

Every unpack writes one line to `~/.local/state/toolbelt/unpack.log`. The line holds the time, the archive path,
the target, the number of files, and whether the archive went to the trash, with its name in the trash. Next to
it, `~/.local/state/toolbelt/unpack/` keeps the size and modification time of each file that came out. `unpack`
keeps the last 200 runs.

`--history` lists them, newest first:

```console
$ unpack --history
2026-09-29 14:02  backup.tar.gz (4)  ~/restore/backup/  201 files  archive in the trash
2026-09-29 11:47  web-1.4.2.tgz      ~/lab/chart/        14 files
2026-09-28 22:10  notes.zip          ~/Documents/notes/  12 files  undone
```

`--undo` takes the last run that was not undone yet. It shows what it found and asks first:

```console
$ unpack --undo
last run  2026-09-29 14:02
archive   backup.tar.gz, 4 parts, now in the trash
created   ~/restore/backup/, 201 files, 31 MB
Move backup/ to the trash and bring back the 4 parts? [y/N] y
backup/ is in the trash, except 1 file you changed since:
  backup/notes.txt
4 parts are back in ~/restore/.
```

Before it moves anything, `--undo` compares every file with the record. A file you edited or added since the
unpack is not yours to lose, so it stays where it is. The rest of the folder goes to the trash.

When the archive went to the trash after the unpack, `--undo` brings it back to where it was. When it was kept,
there is nothing to bring back and the question is only `Move backup/ to the trash?`.

In a script, `--undo` needs `-y`, like every other question. A no exits with status 5 and changes nothing.

## Sandbox

`--sandbox` runs the unpack in a throwaway container. Use it for an archive from a place you do not trust, or to
keep a bug in a decompressor away from your files.

```console
$ unpack --sandbox tool-1.4.2.tar.gz
unpack: sandbox: podman, no network, archive read-only
tool-1.4.2.tar.gz -> tool-1.4.2/ (3.2MB, 88 files, 1.9s)
```

The outer `unpack` does the listing and every safety check on the host first. Then it starts:

```
podman run --rm -i --network=none --security-opt label=disable --userns=keep-id
  -v <toolbelt>:/opt/toolbelt:ro -v <archive>:/in/<name>:ro -v <temp folder>:/out
  docker.io/library/debian:stable-slim /opt/toolbelt/bin/unpack -H -k -y -q -o /out /in/<name>
```

The container has no network. It sees the archive and toolbelt read-only, and it can write only into the temp
folder. After it exits, the outer `unpack` counts the files, places them and asks the delete question as usual.

podman runs rootless and maps your user in with `--userns=keep-id`, so the files belong to you. docker is the
fallback when podman is missing, with `--user` set to your uid and gid.

The image needs the tools for the format. `debian:stable-slim` has tar, gzip and xz. For other formats, set
`UNPACK_SANDBOX_IMAGE` to an image that has them:

```console
$ UNPACK_SANDBOX_IMAGE=localhost/unpack-tools unpack --sandbox photos.7z
```

## Passwords

`-p` asks for the password of a zip, 7z or rar. In a terminal the typing does not show:

```console
$ unpack -p keys.7z
Password for keys.7z:
keys.7z -> keys/ (2KB, 3 files, 0.1s)
```

In a script, `unpack -p` reads one line of stdin, so `pass show backup | unpack -p backup.7z` works. The password
never goes on the `unpack` command line, where `ps` would show it to every user.

7z reads the password on stdin, so `unpack` picks 7z for any zip or rar with a password when 7z is installed. unzip,
unrar and unar only take a password as an option, which `ps` shows while they run. `unpack` falls back to them only
when 7z is missing, and `-v` prints the password as `***`.

Without `-p`, an encrypted archive stops with a hint:

```console
$ unpack keys.7z
unpack: keys.7z: the archive is encrypted, add -p to type the password
```

A wrong password gives `wrong password` and exit status 1. `-p` on a format without passwords, such as a tar,
prints a warning and goes on.

## URLs

A URL is downloaded with `curl -fL` into a temp folder, unpacked, and the download removed. The file name comes from
the last part of the URL.

```console
$ unpack https://example.com/tool-1.4.2.tar.gz
unpack: downloaded 3.1MB from example.com
tool-1.4.2.tar.gz -> tool-1.4.2/ (9.8MB, 88 files, 2.7s)
```

curl only follows `http`, `https` and `file` URLs, including after a redirect. `file://` URLs work the same way,
which is how the tests check this without a network. A URL is never offered for deletion, and `--history` shows
the URL.

## Archives inside archives

`-r` unpacks every archive it finds in the result, and every archive inside those, up to 3 levels deep. Each inner
archive is replaced by its contents, in place.

```console
$ unpack -r web-1.4.2.tgz
  inner: 1 archive unpacked in place
web-1.4.2.tgz -> chart/ (22KB, 14 files, 0.1s)
```

`charts/redis-18.1.0.tgz` inside the chart became `charts/redis/`. Every inner unpack goes through the same safety
checks.

Some archives stay as they are, because unpacking them would break what they are for. Those are jar, war, ear and
whl files, debs, rpms, isos, initramfs images, and parts of multi-part sets.

## Initramfs images

A Linux initramfs image is not one archive. It is one or more plain cpio archives, often with CPU microcode,
followed by one compressed cpio with the real root file system. `file` sees only the first one, and `cpio -i` stops
after it.

`unpack` uses `unmkinitramfs` from `initramfs-tools-bin` when it is installed. That is the tool Debian and Ubuntu
ship for this. Without it, `unpack` walks the image itself. It reads each plain cpio, finds its `TRAILER!!!`
entry, skips the zero padding, and repeats until it finds the compressed part. It recognises that part by its magic
bytes, so gzip, xz, lzma, zstd, lz4, lzop and bzip2 all work.

With more than one layer, the first layers go into `early/`, `early2/` and so on, and the compressed layer into
`main/`. That is the same layout `unmkinitramfs` makes.

```console
$ unpack /boot/initrd.img-6.12.48-amd64
unpack: initrd.img-6.12.48-amd64: initramfs, 2 layers
  layer 1: cpio -> early/, 1 file
  layer 2: cpio.zst -> main/, 2,114 files
initrd.img-6.12.48-amd64 -> initrd-6.12.48-amd64/ (78MB, 2,115 files, 2.2s)
```

Files in an initramfs keep their owners only when you unpack as root. As a normal user they belong to you, which is
fine for reading them. The image in `/boot` is never offered for deletion.

## Progress and output

In a terminal, `pv` draws a progress bar for every format that goes through a pipe, such as a tar or a single
compressed file. 7z shows its own percentage. Without `pv`, `unpack` prints a hint with the install line and works
without the bar. `-q` hides the hint.

The result line goes to stdout. Everything else, such as questions, warnings and `-v` steps, goes to stderr. That
keeps `unpack -q x.tar.gz > done.log` clean, and `--cat` output is exactly the file.

The result line is always the same shape:

```
ARCHIVE[ (N parts)] -> TARGET (SIZE, N files, TIME)
```

With `--only` the count reads `2 of 201 files`.

`-v` shows every step. Each real command starts with `+`, in a form you can paste into a shell:

```console
$ unpack -v backup.tar.gz
unpack: backup.tar.gz: tar.gz, from the name
unpack: tool: pigz, in place of gzip
unpack: listing: 4 files, 24KB, one top folder backup/
unpack: paths: ok, none escape
unpack: disk: 52KB needed, 725MB free on /home
unpack: memory: ok, pigz needs under 1MB
unpack: ratio: 1.4x, the limit is 100x
+ cat backup.tar.gz | pigz -dc | tar -xf - -C .unpack-GttVuf
unpack: verify: 4 files on disk, 4 in the listing
unpack: move: .unpack-GttVuf/backup -> backup
backup.tar.gz -> backup/ (24KB, 4 files, 0.0s)
```

## Pass-through

Options after `--` go to the tool that writes the files. Which tool that is depends on the format:

| Format | Gets the options | Example |
|---|---|---|
| tar with any compressor, deb | tar | `unpack site.tar.gz -- --no-same-owner` |
| a single compressed file | the decompressor | `unpack dump.sql.zst -- --memory=2048MB` |
| cpio, rpm | cpio | `unpack root.cpio -- --no-preserve-owner` |
| zip | unzip, or 7z | `unpack notes.zip -- -LL` |
| 7z, split zip, iso | 7z | `unpack photos.7z -- -mmt=4` |
| rar | unrar, 7z or unar | `unpack film.part1.rar -- -ai` |
| initramfs | unmkinitramfs, or cpio | `unpack initrd.img -- --no-preserve-owner` |

`unpack` does not check these options. An option that changes which files come out, such as tar's `--exclude`,
makes the file count differ from the listing. That shows as a warning, and the archive is then not offered for
deletion.

## Needs

tar, gzip and xz, which every distro has, and `file` for archives with unknown names. Every other tool is needed
only for its own format, as the table in Formats shows. When one is missing, `unpack` names it with the install
line for your package manager and exits with status 3:

```console
$ unpack logs.tar.zst
unpack: needs zstd. Install it with: sudo apt install zstd
```

Optional tools:

- `pv` draws the progress bar. Package `pv`.
- `pigz`, `pbzip2` and `plzip` decompress on every core.
- `curl` fetches URLs. Package `curl`.
- `podman` or `docker` runs `--sandbox`. Packages `podman`, `docker.io`.
- `unmkinitramfs` splits initramfs images. Package `initramfs-tools-bin`.
- `bsdtar` reads isos when 7z is missing. Package `libarchive-tools`.

Package names on other distros:

| Tool | apt | dnf | pacman | zypper | apk |
|---|---|---|---|---|---|
| 7z | `7zip` | `7zip` | `7zip` | `7zip` | `7zip` |
| unrar | `unrar` | none | `unrar` | `unrar` | `unrar` |
| unar | `unar` | `unar` | `unarchiver` | `unar` | `unar` |
| rpm2cpio | `rpm2cpio` | `rpm` | `rpmextract` | `rpm` | `rpm` |
| dpkg-deb | `dpkg` | `dpkg` | `dpkg` | `dpkg` | `dpkg` |
| bsdtar | `libarchive-tools` | `bsdtar` | `libarchive` | `bsdtar` | `libarchive-tools` |
| unmkinitramfs | `initramfs-tools-bin` | none | none | none | none |

## Examples

### Unpack a backup and keep the archive

```console
$ unpack -k backup.tar.gz
backup.tar.gz -> backup/ (24KB, 4 files, 0.0s)
```

### Unpack a split backup into another folder

```console
$ unpack -o ~/restore backup.tar.gz.aa
backup.tar.gz (4 parts) -> ~/restore/backup/ (31MB, 201 files, 3.4s)
```

### Look inside before unpacking

```console
$ unpack -l backup.tar.gz
          backup/
      2B  backup/notes.txt
          backup/db/
     6KB  backup/db/blob.bin
    18KB  backup/db/dump.sql
          backup/etc/
     10B  backup/etc/nginx.conf
backup.tar.gz: 4 files, 24KB
```

### Check an archive

```console
$ unpack -t backup.tar.gz
backup.tar.gz: ok, 4 files, 24KB
```

### Read one file without unpacking

```console
$ unpack --cat backup/etc/nginx.conf backup.tar.gz
server {}
```

### Take only the config files

```console
$ unpack --only '*.conf' backup.tar.gz
backup.tar.gz -> backup/ (10B, 1 of 4 files, 0.0s)
```

### Pass options to 7z

```console
$ unpack -v photos.7z -- -mmt=4
unpack: photos.7z: 7z, from the name
unpack: tool: 7z
unpack: listing: 811 files, 1.2GB, one top folder photos/
unpack: paths: ok, none escape
unpack: disk: 1.2GB needed, 38GB free on /home
unpack: memory: ok, 7z needs 16MB, 5.2GB is free
unpack: ratio: 1.0x, the limit is 100x
+ 7z x -o.unpack-fc0aKD -y -mmt=4 photos.7z
unpack: verify: 811 files on disk, 811 in the listing
unpack: move: .unpack-fc0aKD/photos -> photos
photos.7z -> photos/ (1.2GB, 811 files, 14.2s)
```

### Undo the last unpack

```console
$ unpack --undo
last run  2026-09-29 16:56
archive   backup.tar.gz, now in the trash
created   backup/, 4 files, 24 KB
Move backup/ to the trash and bring back backup.tar.gz? [y/N] y
backup/ is in the trash.
backup.tar.gz is back in ./.
```

## Troubleshooting

**`could not read the archive, it may be damaged or incomplete`.** The tool failed while listing. For a download,
check the size against the source and download it again. For a `.aa` or `.001` set, check that the last part is
there. The lines above the message are the tool's own error.

**`unpacking failed, nothing was changed`.** The listing worked but writing did not. The tool's error is above the
message. A full disk and a file that is damaged halfway are the usual causes. The temp folder is already removed.

**`not an initramfs image this command can read`.** The image has a layout `unpack` does not know, such as a
compressed layer in the middle. Install `initramfs-tools-bin` for `unmkinitramfs`.

**`unknown archive type`.** Neither the name nor the content matched a format. `file notes.txt` shows what the
file really is. Without `file` installed, only the name counts, and the message names the package to install.

**A folder called `backup-1` instead of `backup`.** `backup` already existed. `unpack` never writes into an
existing folder. Move the old one away and run `unpack` again, or compare the two with `diff -r`.

**Owners and permissions.** tar keeps the modes in the archive. As a normal user you own every file. As root, tar
also restores the owners. Pass `-- --no-same-owner` to stop that.

**The progress bar does not show.** Install `pv`. The bar only shows in a terminal, and never with `-q`.

**The delete question never comes.** It needs a terminal, a verified count, a local file and no `--only`. `-v`
shows the verify line. In a script, add `--rm`.

**`--undo` keeps some files.** Those are files you changed or added after the unpack. They are listed, and you can
remove them yourself.

**A sandbox run fails with `needs 7z`.** The container image lacks the tool. Set `UNPACK_SANDBOX_IMAGE` to an image
that has it.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Everything unpacked. Also when you answered no to the delete question. |
| 1 | An archive failed, a part is missing, a password was wrong, or `--cat` did not find the file. With several archives, 1 when any of them failed. |
| 2 | Bad usage, such as an unknown option or two actions at once. |
| 3 | A tool is missing. The message names it and the package. |
| 4 | Refused by a safety check. Nothing was written. |
| 5 | You answered no to the ratio question or to `--undo`. |

With several archives, `unpack` goes on after a failure and exits with 1 at the end. Ctrl+C stops the whole run and
removes the temp folder.

## See also

`squash`, `archdiff`, `archmount`, `autounpack`, `tar(1)`, `7z(1)`, `unzip(1)`, `unmkinitramfs(8)`
