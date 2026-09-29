# checksum

Hash a file, or check it against a hash or SUMS file.

## Synopsis

```
checksum [options] file ...
checksum [options] file hash
checksum [options] -c sums-file
```

## Description

`checksum` answers one question after a download. Is this file the one the project published? It works three ways.

With only file names, it hashes each file with sha256. Before that, it looks beside the file for a SUMS file that
lists it, such as the `SHA256SUMS` next to a Debian ISO. When it finds one, it checks the file against it and prints
`OK` or `FAILED` instead of a bare hash. When there is none, it prints the hash in the same format as `sha256sum`,
so you can save the output as a SUMS file of your own.

With a file and a hash, such as one you copied from a download page, it compares the two. You do not have to say
which algorithm the hash is. `checksum` works it out from the length.

With `-c SUMS`, it checks every file the SUMS file lists and prints one line per file with a count at the end.

Every check prints one line per file:

```
OK       debian-13.1.0-amd64-netinst.iso
FAILED   debian-13.1.0-amd64-DVD-1.iso
MISSING  debian-13.1.0-amd64-DVD-2.iso
```

In a terminal, `OK` is green and the other two are red. `checksum` exits 1 when any file fails or is missing, so
a script can stop on a bad download.

## Options

| Option | What it does |
|---|---|
| `-a`, `--algo NAME` | Use md5, sha1, sha256, sha512, b2 or b3. The default is sha256. `blake2b`, `sha256sum` and upper case names work too. |
| `-c`, `--check FILE` | Check every file listed in a SUMS file. |
| `--ignore-missing` | With `-c`, skip listed files that are not here instead of calling them missing. |
| `--no-sums` | Print hashes only. Never look for a SUMS file. |
| `-q`, `--quiet` | Show only the result lines. |
| `-v`, `--verbose` | Show each step, the SUMS file it found, and each hash command before it runs. |
| `-h`, `--help` | Show the help. |

## How it picks the algorithm

For `checksum FILE HASH`, the length of the hash decides.

| Hex digits | Algorithm |
|---|---|
| 32 | md5 |
| 40 | sha1 |
| 64 | sha256, then b3 when `b3sum` is installed |
| 128 | sha512, then b2 |

Two algorithms make 64 digit hashes, and two make 128 digit ones. `checksum` tries the common one first. When that
does not match, it tries the other, and `-v` shows `no match with sha256, trying b3`. The result line names the
algorithm that matched.

A pasted hash may start with a label such as `sha256:` or `SHA512:`, the way Docker and many download pages print
it. `checksum` reads the label as `-a` and drops it. It also drops spaces, so a hash split across two lines still
works when you quote it.

For a SUMS file, the choice goes in this order:

1. `-a`, when you give it.
2. The tag on a BSD style line, such as `SHA256 (file.iso) = ...`. Fedora and FreeBSD use this format.
3. The name of the SUMS file, such as `SHA512SUMS` or `file.iso.sha256`, when the hash has the right length for it.
4. The length of the hash, as above.

## How it finds a SUMS file

For each file, `checksum` looks for these files beside it, in this order, and uses the first one that lists the
file by name:

1. `file.sha256`, `file.sha256sum`, and the same with sha512, b2, sha1, md5 and b3.
2. `SHA256SUMS`, `SHA512SUMS`, `B2SUMS`, `SHA1SUMS`, `MD5SUMS` and `B3SUMS`, each also as `NAME.txt` and in lower
   case as `sha256sums.txt`.
3. Files ending in `CHECKSUM` or `-CHECKSUMS`, which is how Fedora names them.

A `file.sha256` that holds only a bare hash, with no name after it, counts as the hash for `file`. With `-a`, only
the SUMS files for that algorithm count.

It reads three line formats:

```
ff0b18e3...  debian-13.1.0-amd64-netinst.iso        GNU, from sha256sum
ff0b18e3... *debian-13.1.0-amd64-netinst.iso        GNU, binary mode
SHA256 (Fedora-Workstation-Live-42-1.1.x86_64.iso) = 26551053...   BSD
```

Blank lines, lines that start with `#`, and Windows line endings are fine. The PGP signature lines around a
Fedora CHECKSUM file are skipped, because they match none of the formats.

## Safety checks

- `checksum` only reads. It never changes, moves or deletes a file.
- It feeds each file to the hash tool on standard input, so a file named `-c` or with a newline in its name
  cannot change what the tool does.
- A hash of the wrong length is a usage error with exit 2. It never counts as a failed file.
- `checksum` does not check the PGP signature on a SUMS file. When the SUMS file comes from the same mirror as the
  ISO, a hacked mirror can change both. For that, run `gpg --verify SHA256SUMS.sign SHA256SUMS` first.

## Pass-through

`checksum` takes no options for the hash tools. Everything after `--` is a file name, which lets you hash a file
whose name starts with a dash.

```console
$ checksum -- -weird-name.txt
```

## Needs

`sha256sum`, `md5sum`, `sha1sum`, `sha512sum` and `b2sum`, all from coreutils. BusyBox has all of them except
`b2sum`, so on Alpine `-a b2` needs `apk add coreutils`. `b3` needs `b3sum`, which is a package called `b3sum` on
Debian, Ubuntu, Fedora, Arch and Alpine. When it is missing, `checksum` names the package and exits 3.

## Examples

### Check a download against the SUMS file beside it

```console
$ ls
SHA256SUMS  debian-13.1.0-amd64-netinst.iso
$ checksum debian-13.1.0-amd64-netinst.iso
OK       debian-13.1.0-amd64-netinst.iso  (sha256, SHA256SUMS)
```

### A download that went wrong

```console
$ checksum debian-13.1.0-amd64-DVD-1.iso
FAILED   debian-13.1.0-amd64-DVD-1.iso  (sha256, SHA256SUMS)
  want c36abfca184c4d3b5458a864bef2686b57725a890268c01a86d92784704335aa
  got  b690c618f7ef137b4834057d41779be6049ad31bc5d353e616693c46213f0a44
$ echo $?
1
```

Download it again. A partial download or a bad mirror gives a different hash every time.

### Check everything in a SUMS file

```console
$ checksum -c SHA256SUMS
OK       debian-13.1.0-amd64-netinst.iso
OK       debian-13.1.0-amd64-DVD-1.iso
MISSING  debian-13.1.0-amd64-DVD-2.iso
2 OK, 0 failed, 1 missing
$ checksum -c SHA256SUMS --ignore-missing
OK       debian-13.1.0-amd64-netinst.iso
OK       debian-13.1.0-amd64-DVD-1.iso
2 OK, 0 failed, 1 not here and skipped
```

The first run exits 1 because of the missing file. The second exits 0.

### Compare with a hash from a web page

```console
$ checksum notes.txt 9c345463e1fec644c6eee8e6158d953f
OK       notes.txt  (md5)
```

The 32 digits told `checksum` to use md5.

### A Fedora CHECKSUM file

```console
$ checksum -v Fedora-Workstation-Live-42-1.1.x86_64.iso
checksum: found Fedora-Workstation-Live-42-1.1.x86_64.iso in ./Fedora-Workstation-42-1.1-x86_64-CHECKSUM
+ sha256sum < Fedora-Workstation-Live-42-1.1.x86_64.iso
OK       Fedora-Workstation-Live-42-1.1.x86_64.iso  (sha256, Fedora-Workstation-42-1.1-x86_64-CHECKSUM)
```

### Make a SUMS file of your own

```console
$ checksum --no-sums *.iso > SHA256SUMS
$ checksum -a md5 notes.txt ubuntu-24.04.3-desktop-amd64.iso
9c345463e1fec644c6eee8e6158d953f  notes.txt
3bee204ae8e1ed05ba6ab8e448ef40be  ubuntu-24.04.3-desktop-amd64.iso
```

The output has the same format as `sha256sum`, so `sha256sum -c` reads it too.

## Troubleshooting

`checksum: the hash has 6 hex digits, a hash has 32, 40, 64 or 128`
: Part of the hash is missing. Copy it again. When it came from a page that wraps long lines, quote it so both
  halves reach `checksum`.

`checksum: needs b3sum. Install it with: sudo apt install b3sum`
: The line names the package for your distro. Install it, or use another algorithm.

`MISSING  debian-13.1.0-amd64-DVD-2.iso`
: The SUMS file lists files for a whole release, and you downloaded only some. Add `--ignore-missing`.

`checksum: none of the files in SHA256SUMS is here`
: Run it from the folder that holds the files, or keep the SUMS file in that folder. `checksum` looks for the
  listed names beside the SUMS file.

A plain hash instead of `OK`
: No SUMS file beside the file lists it by that name. A renamed download, such as `debian.iso`, no longer matches
  the name in `SHA256SUMS`. Use `checksum -c SHA256SUMS` after renaming it back, or compare with the hash directly.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every file matched, or it printed the hashes. |
| 1 | A hash did not match, or a file is missing or unreadable. |
| 2 | Bad usage, such as a hash of the wrong length or an unknown algorithm. |
| 3 | The hash tool is missing. |
| 4 | Refused. |

## See also

`dupes`, `sha256sum(1)`, `b2sum(1)`, `gpg(1)`
