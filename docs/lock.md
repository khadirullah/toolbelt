# lock

Encrypt a file or folder with age, or gpg.

## Synopsis

```
lock [options] path ... [-- age or gpg options]
```

## Description

`lock` writes an encrypted copy of each file or folder next to it. A file `secrets.env` becomes `secrets.env.age`.
A folder `photos/` goes into a tar archive first and becomes `photos.tar.age`. `unlock` turns them back.

```
secrets.env -> secrets.env.age (1.5KB, 2.4s)
The plain file is still there. Once unlock works on the copy, remove it with: shred -u secrets.env
```

`lock` uses [age](https://age-encryption.org) when it is installed. age has no settings to get wrong and its files
are small. When age is missing, `lock` says so and uses gpg with AES256, and the file ends in `.gpg` instead. `--gpg`
picks gpg on purpose, for someone who only has gpg.

There are two ways to lock:

- With a passphrase, the default. `lock` asks for it twice, through age or gpg. It never takes a passphrase as an
  argument, since an argument shows up in `ps` and in the shell history.
- With public keys, using `-r` or `-R`. Only the matching private key opens the file, and nobody types anything.
  age takes age keys, which start with `age1`, and SSH keys, such as `~/.ssh/id_ed25519.pub`. gpg takes the key id
  or email of a key in your gpg keyring.

The plain file stays where it is. `lock` prints the command that removes it safely, or does it for you with
`--shred` after a check.

## Options

| Option | What it does |
|---|---|
| `-r`, `--recipient KEY` | Lock to a public key. An age key, an SSH key, or with gpg a key id or email. A path to a key file works too. Can repeat. |
| `-R`, `--key-file FILE` | Lock to every public key in a file, one per line. `~/.ssh/authorized_keys` works. Can repeat. |
| `-o`, `--out NAME` | Name the encrypted file yourself. Only with one path. |
| `-a`, `--armor` | Write text instead of binary, so the file survives mail and chat. It is a third bigger. |
| `--gpg` | Use gpg even when age is installed. |
| `--shred` | After the copy is written, decrypt it, compare it with the plain one, then shred the plain one. |
| `-y`, `--yes` | Shred without asking. |
| `-q`, `--quiet` | Show only the result line. |
| `-v`, `--verbose` | Show every step, and each real command before it runs. |
| `-h`, `--help` | Show the help. |

With more than one `-r` or `-R`, any one of the private keys opens the file. Add your own key when you lock a file
for someone else, or you cannot open it either.

## Output names

| You lock | You get, with age | With gpg |
|---|---|---|
| `notes.txt` | `notes.txt.age` | `notes.txt.gpg` |
| `photos/` | `photos.tar.age` | `photos.tar.gpg` |
| `notes.txt` with `-o /mnt/usb/n.age` | `/mnt/usb/n.age` | `/mnt/usb/n.age` |

`lock` never overwrites. When the name is taken it stops with exit 4 and leaves both files alone. It writes to a
hidden temp file beside the output and renames it at the end, so a failed or stopped run leaves no half file under
the real name.

## Safety checks

- A passphrase after `--`, such as `-- --passphrase hunter2`, is refused with exit 4.
- `--shred` never shreds until the copy has opened and matched the plain file byte for byte. For a folder it
  checks every file with `tar -d`. A copy locked to someone else's key cannot be checked here, so `--shred` refuses
  and keeps the plain copy.
- With `--shred`, `lock` asks once more for the passphrase, since it has to open the copy to check it.
- When gpg is the fallback and you name an age or SSH key, `lock` stops. gpg cannot use those keys.

`shred` overwrites a file before it deletes it. On SSDs, on copy-on-write filesystems such as btrfs, and on
journalled ones such as ext4 in `data=journal` mode, old blocks may survive anyway. Lock a secret before it lands on
disk if you can, and use full disk encryption for the rest.

## Pass-through

Options after `--` go to age, or to gpg. Some useful ones with gpg:

```console
$ lock --gpg taxes.pdf -- --cipher-algo CAMELLIA256
$ lock --gpg -r alice@example.com report.pdf -- --trust-model always
$ lock --gpg -r 0x1234ABCD notes.txt -- --hidden-recipient 0x1234ABCD
```

age has few options of its own. `-r`, `-R` and `-a` already cover them.

## Needs

`age`, or `gpg` as the fallback. `tar` for folders and `shred` for `--shred`, both installed everywhere.

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
$ lock secrets.env
Enter passphrase (leave empty to autogenerate a secure one):
Confirm passphrase:
secrets.env -> secrets.env.age (1.5KB, 2.4s)
The plain file is still there. Once unlock works on the copy, remove it with: shred -u secrets.env
```

### A folder, for your own SSH key

```console
$ lock -r ~/.ssh/id_ed25519.pub photos/
photos/ -> photos.tar.age (9.3KB, 3 files, 0.1s)
Only the private key for /home/me/.ssh/id_ed25519.pub can open it.
The plain folder is still there. Once unlock works on the copy, remove it with:
  find photos -type f -exec shred -u {} + && rm -r photos
```

### With gpg, when age is missing

```console
$ lock -v secrets.env
lock: age not found, using gpg
+ gpg --no-symkey-cache --symmetric --cipher-algo AES256 -o - -- secrets.env > secrets.env.gpg
secrets.env -> secrets.env.gpg (1.4KB, 0.8s)
The plain file is still there. Once unlock works on the copy, remove it with: shred -u secrets.env
```

### A folder with gpg

```console
$ lock --gpg photos/
photos/ -> photos.tar.gpg (9.1KB, 3 files, 0.1s)
The plain folder is still there. Once unlock works on the copy, remove it with:
  find photos -type f -exec shred -u {} + && rm -r photos
```

### Lock and shred in one go

```console
$ lock --shred notes.txt
Enter passphrase (leave empty to autogenerate a secure one):
Confirm passphrase:
notes.txt -> notes.txt.age (412B, 3.1s)
Type the passphrase once more, to check that notes.txt.age opens.
Enter passphrase:
notes.txt.age opens and matches notes.txt.
Shred notes.txt? It cannot be undone. [y/N] y
notes.txt is shredded.
```

### Text to paste in a chat

```console
$ lock -a -r age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p wifi.txt
wifi.txt -> wifi.txt.age (403B, 0.0s)
Only the private key for age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p can open it.
$ head -1 wifi.txt.age
-----BEGIN AGE ENCRYPTED FILE-----
```

### The name is taken

```console
$ lock secrets.env
lock: secrets.env.age exists. Use -o for another name
```

## Troubleshooting

`lock: needs age or gpg. Install age with: sudo apt install age`
: Neither tool is installed. Install one, age for preference.

`lock: age1... is an age or SSH key, and only age can use it`
: gpg is the fallback and cannot use that key. Install age, or lock to a gpg key instead.

`gpg: problem with the agent: Inappropriate ioctl for device`
: gpg cannot find the terminal to ask for the passphrase. Run `export GPG_TTY=$(tty)` and try again. `lock` sets it
  when it runs in a terminal, but not inside some editors or multiplexers.

`gpg: alice@example.com: skipped: No public key`
: The key is not in your keyring. Import it with `gpg --import alice.asc` first.

`lock: refused --shred, there is no private key here to check that X opens`
: The file is locked to someone else's key. Check it on their side, then remove the plain copy yourself.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every path was locked. |
| 1 | A path is missing, or age or gpg failed. Nothing was written for it. |
| 2 | Bad usage, such as `-o` with two paths. |
| 3 | Neither age nor gpg is installed, or the key needs age. |
| 4 | Refused. The output name is taken, a passphrase came after `--`, or `--shred` could not check. |
| 5 | You answered no to the shred question. |

## See also

`unlock`, `age(1)`, `gpg(1)`, `shred(1)`
