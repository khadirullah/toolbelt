# dupes

Find duplicate files by content.

## Synopsis

```
dupes [options] [path ...] [-- tool options]
```

## Description

`dupes` finds files with the same content, whatever their names. Photos copied off a phone twice, the same ISO in
`Downloads` and `Downloads/iso`, and exports saved as `final` and `final-2` all show up as groups. With no path it
looks in the current folder.

It prints each group with the size of one copy and the number of copies, and a total at the end:

```
29KB x 2
  Pictures/export/trip.mp4
  Pictures/trip-final.mp4
8.7KB x 3
  Pictures/2026-09/IMG_4410.jpg
  Pictures/phone/IMG_4410 (1).jpg
  Pictures/phone/IMG_4410.jpg
3 groups, 47KB you could free
```

The groups that waste the most space come first. In each group the oldest file, by modification time, comes first.
The total counts every copy except one per group, which is the space you would get back.

On its own, `dupes` only reads. `--trash` and `--link` act on the groups, and both ask first.

## Options

### What to look at

| Option | What it does |
|---|---|
| `-m`, `--min SIZE` | Skip files smaller than SIZE, such as `100K`, `1M` or `1.5G`. Units are powers of 1024, and `K`, `KB` and `KiB` mean the same. |
| `--only PATTERN` | Look only at names that match, such as `'*.jpg'`. Can repeat. |
| `-x`, `--exclude PAT` | Leave out names that match. A folder that matches is skipped whole. Can repeat. |
| `--fast` | Use `jdupes`, `fdupes` or `rdfind` when one is installed. |

### What to do with them

| Option | What it does |
|---|---|
| `--trash` | Keep the oldest file in each group and move the others to the trash. Asks first. |
| `--link` | Replace each copy with a hard link to the oldest file. Asks first. |
| `-y`, `--yes` | With `--trash` or `--link`, go ahead without asking. |
| `-q`, `--quiet` | Show only the groups and the total. |
| `-v`, `--verbose` | Show each step, and each `find` and tool command before it runs. |
| `-h`, `--help` | Show the help. |

Use `--trash` or `--link`, not both.

A pattern without a `/` matches a file name, the way `find -name` does. A pattern with a `/` matches the whole
path, the way `find -path` does, so `-x '*/node_modules/*'` works too. Quote every pattern so the shell does not
expand it first.

## How it decides

Hashing every file would read every byte on the disk. `dupes` narrows the list in three steps, and each step only
looks at the files the step before could not rule out:

1. **Size.** One `find` lists every file with its size. A file whose size no other file has cannot have a twin, so
   it drops out without being read. On a typical home folder, this step alone rules out most files.
2. **The first 4KB.** For the files left, `dupes` hashes the first 4096 bytes. Two videos of the same length but
   different content almost always differ here.
3. **The whole file.** Only files that still match get a full sha256 hash. Files of 4KB or less skip this step,
   since step 2 already read all of them.

Two files are duplicates when their full sha256 hashes match. `--trash` and `--link` also compare each pair byte
for byte with `cmp` right before they act. A file that changed since the scan is left alone with a warning.

Some files never count:

- Empty files. Every empty file matches every other one, and they take no space.
- Hard links. Names that point to the same data on disk count as one file, since removing one frees nothing.
- Symlinks. `dupes` never follows them.
- Names that hold a line break. They are skipped, because the lists `dupes` builds are one path per line.

## Safety checks

- On its own, `dupes` changes nothing.
- `--trash` keeps the oldest file in each group and moves the others to `~/.local/share/Trash`. Your file manager
  can restore them. `dupes` never deletes a file for good.
- `--link` swaps a copy for a hard link in two steps. It makes the link under a temp name such as `.dupes-4242`,
  then moves the link over the copy. If either step fails, the copy stays as it was.
- `--link` only links files on the same filesystem as the one it keeps. The rest get a `skip ... other filesystem`
  line and stay as they are.
- Both ask once, after the full list of `keep`, `trash` and `link` lines. Without a terminal and without `-y` they
  exit 4. Answering no exits 5.
- Before each change, `cmp` checks that the pair still matches.

Hard links have a catch. After `--link`, all the names share one file. Editing one edits them all, and they all
have the owner, mode and time of the file that was kept. Use `--link` for things you only read, such as backups,
ISO images and photo archives. Use `--trash` for files you edit.

## The --fast tools

`--fast` hands the search to the first one of these it finds:

| Tool | Command it runs | Packages |
|---|---|---|
| `jdupes` | `jdupes -r -q -- PATH` | `jdupes` on Debian, Ubuntu, Fedora, Arch and Alpine |
| `fdupes` | `fdupes -r -q -n -- PATH` | `fdupes` on all of them |
| `rdfind` | `rdfind -makeresultsfile true -outputname TMP PATH` | `rdfind` on Debian, Ubuntu, Fedora and Arch |

These tools are written in C and are faster on large trees. `dupes` reads their output and prints the groups in its
own format, oldest first, so `--trash` and `--link` work the same. It never uses their own delete or link options.
`--min`, `--only` and `-x` still apply to the results.

When none of them is installed, `dupes` says so, names the package, and does the search itself.

## Pass-through

With `--fast`, options after `--` go to the tool it picked. For example, `-Q` makes jdupes skip its final
byte-for-byte check:

```console
$ dupes --fast ~/Pictures -- -Q
```

Without `--fast`, options after `--` are a usage error.

## Needs

`find`, `stat`, `head` and `sha256sum` to search, and `cmp` for `--trash` and `--link`. `find` comes from findutils,
`cmp` from diffutils, and the others from coreutils. BusyBox has all of them. `jdupes`, `fdupes` and `rdfind` are
optional.

## Examples

### Look for copies in a photo folder

```console
$ dupes Pictures
29KB x 2
  Pictures/export/trip.mp4
  Pictures/trip-final.mp4
8.7KB x 3
  Pictures/2026-09/IMG_4410.jpg
  Pictures/phone/IMG_4410 (1).jpg
  Pictures/phone/IMG_4410.jpg
500B x 2
  Pictures/thumb.db
  Pictures/phone/thumb.db
3 groups, 47KB you could free
```

### Skip small files, and see the steps

```console
$ dupes -v -m 10K Pictures
+ find -P Pictures -type f -size +10239c '!' -name $'*\n*' -exec stat -c '%s %Y %d %i %n' -- '{}' +
dupes: 2 files share a size with another file
dupes: 2 files over 4KB match another in their first 4KB, hashing them whole
29KB x 2
  Pictures/export/trip.mp4
  Pictures/trip-final.mp4
1 group, 29KB you could free
```

### Leave some names out

```console
$ dupes -x '*.db' -x '*(1).jpg' Pictures
29KB x 2
  Pictures/export/trip.mp4
  Pictures/trip-final.mp4
8.7KB x 2
  Pictures/2026-09/IMG_4410.jpg
  Pictures/phone/IMG_4410.jpg
2 groups, 38KB you could free
```

### Move the copies to the trash

```console
$ dupes --trash -m 1K Pictures
keep   Pictures/export/trip.mp4  oldest
trash  Pictures/trip-final.mp4
keep   Pictures/2026-09/IMG_4410.jpg  oldest
trash  Pictures/phone/IMG_4410 (1).jpg
trash  Pictures/phone/IMG_4410.jpg
Move 3 files (46KB) to the trash? [y/N] y
3 files in the trash, 46KB freed.
```

### Turn copies into hard links

```console
$ dupes --link -m 10K Pictures
keep   Pictures/export/trip.mp4  oldest
link   Pictures/trip-final.mp4
Replace 1 copy (29KB) with hard links? [y/N] y
1 copy is now a hard link, 29KB freed.
$ dupes -m 10K Pictures
No duplicates.
```

Both names still work. The second run finds nothing, because hard links count as one file.

### Ask for --fast without the tools

```console
$ dupes --fast Pictures
dupes: --fast needs jdupes, fdupes or rdfind, so this run uses find and sha256sum. Install it with: sudo apt install jdupes
29KB x 2
  Pictures/export/trip.mp4
  Pictures/trip-final.mp4
...
```

## Troubleshooting

`dupes: options after -- need --fast and jdupes, fdupes or rdfind`
: The search without `--fast` takes no extra options. Use `--only` and `-x` to pick files instead.

`dupes: Pictures/trip-final.mp4 no longer matches Pictures/export/trip.mp4, left alone`
: The file changed between the scan and the action. Run `dupes` again to see the groups as they are now.

`skip   /mnt/usb/trip.mp4  other filesystem`
: A hard link cannot cross filesystems. Use `--trash` for those, or run `--link` on each drive on its own.

It takes a long time
: The first run reads every candidate file whole. Skip small files with `-m 1M`, which rules out most of a home
  folder, or install `jdupes` and use `--fast`. `-x .git -x node_modules` helps in code folders.

A file you wanted to keep went to the trash
: `--trash` keeps the oldest copy, which may not sit in the folder you prefer. Restore the file from the trash with
  your file manager. To pick the copy that stays, run `--trash` on only the folder that holds the extra copies, such
  as `dupes --trash ~/Downloads ~/Pictures/phone`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, whether it found duplicates or not. |
| 1 | It failed. A path is missing, or some files could not be trashed or linked. |
| 2 | Bad usage, such as `--trash` with `--link`, or a size it cannot read. |
| 3 | A tool it needs, such as `sha256sum`, is missing. |
| 4 | Refused. No terminal to ask in. |
| 5 | You answered no. |

## See also

`bigfiles`, `checksum`, `jdupes(1)`, `fdupes(1)`, `rdfind(1)`
