# unlock

Decrypt a file made by lock, age or gpg.

## Synopsis

```
unlock [options] file ... [-- age or gpg options]
```

## Description

`unlock` writes the plain copy of an encrypted file next to it, and keeps the encrypted file. `secrets.env.age`
gives `secrets.env`. A name with `.tar` before the ending holds a folder, so `photos.tar.age` gives the folder
`photos/`.

```
secrets.env.age -> secrets.env (1.3KB, 1.9s)
```

It opens files from `lock`, and any other file made with `age` or `gpg`. It tells the two apart from the first bytes
of the file, not from the name, so a gpg file called `notes.age` still opens with gpg.

| Ending | What `unlock` writes |
|---|---|
| `notes.txt.age`, `.gpg`, `.asc` or `.pgp` | `notes.txt` |
| `photos.tar.age` or `photos.tar.gpg` | the folder `photos/` |
| anything else | nothing until you name the output with `-o`, or print it with `--cat` |

When the file needs a passphrase, age or gpg asks for it. When it is locked to a key, `unlock` finds the key:

- For an age file, it tries `~/.config/age/keys.txt`, `~/.ssh/id_ed25519` and `~/.ssh/id_rsa`, in that order, and
  says which ones it used. `-i` names a key in another place.
- For a gpg file, gpg looks in your keyring as always.

## Options

| Option | What it does |
|---|---|
| `-i`, `--identity FILE` | The private key for an age file. Can repeat. Without it `unlock` tries the usual places above. |
| `-o`, `--out NAME` | Name the output yourself. Only with one file. For a folder, it names the folder. |
| `--cat` | Print the plain content to stdout and write nothing. |
| `-q`, `--quiet` | Show only the result line. |
| `-v`, `--verbose` | Show every step, and each real command before it runs. |
| `-h`, `--help` | Show the help. |

## Safety checks

- `unlock` never overwrites. When the output name is taken, it stops with exit 4 and names `-o` and `--cat` as the
  ways out.
- It decrypts into a hidden temp file or folder beside the output, and renames it only when age or gpg finished
  without an error. A wrong passphrase, a wrong key or a damaged file leaves nothing behind.
- A folder comes out of a temp folder in one rename, so you never see half a folder.
- `--cat` on a folder, with the output going to a terminal, stops with exit 2. A tar stream on screen is noise. Pipe it
  to `tar` instead.

The plain copy lands on disk. For a secret you only need to read once, `--cat` keeps it off the disk.

## Pass-through

Options after `--` go to `age -d` for age files and to `gpg --decrypt` for gpg files:

```console
$ unlock report.pdf.gpg -- --pinentry-mode loopback
$ unlock backup.tar.gpg -- --ignore-mdc-error
```

`--ignore-mdc-error` opens very old gpg files that have no integrity check. Use it only on files you trust.

## Needs

`age` for age files and `gpg` for gpg files. You only need the one your files use. `tar` for folders.

| Distro | age | gpg |
|---|---|---|
| Debian, Ubuntu | `sudo apt install age` | `sudo apt install gnupg` |
| Fedora | `sudo dnf install age` | `sudo dnf install gnupg2` |
| Arch | `sudo pacman -S age` | `sudo pacman -S gnupg` |
| openSUSE | `sudo zypper install age` | `sudo zypper install gpg2` |
| Alpine | `sudo apk add age` | `sudo apk add gnupg` |

## Examples

### A file with a passphrase

```console
$ unlock secrets.env.age
Enter passphrase:
secrets.env.age -> secrets.env (1.3KB, 1.9s)
```

### A folder

```console
$ unlock photos.tar.gpg
photos.tar.gpg -> photos/ (8.7KB, 3 files, 0.1s)
```

### Locked to your SSH key

```console
$ unlock photos.tar.age
unlock: using ~/.ssh/id_ed25519
photos.tar.age -> photos/ (8.9KB, 3 files, 0.0s)
```

### A key somewhere else

```console
$ unlock -i ~/keys/work.txt report.pdf.age
report.pdf.age -> report.pdf (212KB, 0.0s)
```

### Read one line and write nothing

```console
$ unlock --cat secrets.env.age | grep DB_HOST
Enter passphrase:
DB_HOST=db.example.com
```

### See what is in a locked folder

```console
$ unlock --cat photos.tar.age | tar -tv
drwxr-xr-x me/me             0 2026-09-29 16:40 photos/
-rw-r--r-- me/me          4201 2026-09-29 16:40 photos/IMG_4410.jpg
-rw-r--r-- me/me          3890 2026-09-29 16:40 photos/IMG_4411.jpg
-rw-r--r-- me/me            14 2026-09-29 16:40 photos/albums.txt
```

### A gpg file, step by step

```console
$ unlock -v secrets.env.gpg
+ gpg --no-symkey-cache --decrypt -o - -- secrets.env.gpg > secrets.env
gpg: AES256.CFB encrypted data
gpg: encrypted with 1 passphrase
secrets.env.gpg -> secrets.env (1.3KB, 0.1s)
```

### The plain copy is already there

```console
$ unlock secrets.env.gpg
unlock: secrets.env exists. Use -o for another name, or --cat
$ unlock -o secrets.new secrets.env.gpg
secrets.env.gpg -> secrets.new (1.3KB, 0.1s)
```

### A wrong passphrase

```console
$ unlock secrets.env.gpg
gpg: decryption failed: Bad session key
unlock: could not decrypt secrets.env.gpg, wrong passphrase or key. Nothing was written
```

## Troubleshooting

`unlock: X is locked to a key, and there is no key in ~/.config/age/keys.txt or ~/.ssh. Name it with -i`
: The age file needs a private key that is not in the usual places. Pass it with `-i`.

`age: error: no identity matched any of the recipients`
: None of your keys can open it. It was locked for someone else, or for a key you no longer have.

`unlock: X is not an age or gpg file`
: The file does not start like either. It may be damaged, or made by another tool such as `openssl` or `zip -e`.

`gpg: problem with the agent: Inappropriate ioctl for device`
: gpg cannot find the terminal. Run `export GPG_TTY=$(tty)` and try again.

`unlock` did not ask for the gpg passphrase
: gpg-agent remembered it from an earlier run. `lock` and `unlock` turn that off with `--no-symkey-cache`, but plain
  gpg does not. `gpgconf --reload gpg-agent` makes it forget.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every file was unlocked. |
| 1 | It failed. A wrong passphrase or key, no key found, or a file that is not age or gpg. Nothing was written for it. |
| 2 | Bad usage, such as a file with no known ending and no `-o`. |
| 3 | age or gpg is missing, whichever the file needs. |
| 4 | Refused. The output name is taken. |

## See also

`lock`, `age(1)`, `gpg(1)`, `tar(1)`
