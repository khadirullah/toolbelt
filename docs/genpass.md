# genpass

Random passwords and passphrases.

## Synopsis

```
genpass [-l length] [-n count] [--no-symbols] [-c]
genpass -w words [-s separator] [-n count] [-c]
```

## Description

`genpass` prints a random password, 20 characters long by default. `-w` prints a passphrase of whole words
instead, such as `blot-geriatric-robin-germinate-undated`, which is easier to read out or to type on a phone.

Everything happens on your machine. `genpass` reads random bytes from `/dev/urandom`, the kernel's random source,
the same one `ssh-keygen` and `openssl` use. Nothing goes over the network, and nothing is saved or logged.

The result goes to stdout, one per line, so a script can catch it with `$(genpass)`. `-c` puts it on the
clipboard instead and prints nothing, so the password never shows on the screen or in your scrollback.

### What a password is made of

A password draws from 74 characters: 26 lower case letters, 26 capitals, 10 digits and 12 symbols.

```
!#%*+=?@^_~-
```

The symbols leave out quotes, backslashes, `$`, backticks, spaces, `&`, `;`, `|`, `<` and `>`. Those break shell
commands, YAML, `.env` files and URLs, and many login forms reject them. With `--no-symbols` the set is 62 letters
and digits.

Every password has at least one lower case letter, one capital and one digit, and one symbol unless you gave
`--no-symbols`. Many sites refuse a password without them. When a draw misses one, `genpass` throws it away and
draws again. That costs about 0.1 bits at 20 characters, and about 1 bit at the minimum of 8.

### How it stays fair

For a password, `tr` reads random bytes and keeps only the ones that are in the set, so every character in the set
is equally likely. A shortcut such as "random byte modulo 74" would favour some characters.

For a passphrase, `genpass` reads two random bytes per word, a number from 0 to 65535. It drops numbers from 62208
up and takes the rest modulo 7776, so every word is equally likely.

### The word list

The words come from the EFF large word list, 7776 common English words from 3 to 9 letters, made by the
Electronic Frontier Foundation for dice passphrases. It ships with toolbelt as `lib/words`. The list avoids words
that are hard to spell, and no word is the start of another, so a phrase with no separator still reads only one
way.

Four words differ from the EFF original, since a hyphen inside a word would look like the separator. drop-down,
felt-tip and t-shirt lose the hyphen, and yo-yo becomes yeti, because yoyo is already in the list. The list still
has 7776 words, so a passphrase is as strong as before.

### How strong it is

`-v` prints the strength in bits. Each bit doubles the guesses an attacker needs.

| What you ask for | Bits |
|---|---|
| `genpass` (20 characters with symbols) | 124 |
| `genpass -l 16` | 99 |
| `genpass -l 12 --no-symbols` | 71 |
| `genpass -w 4` | 51 |
| `genpass -w 5` | 64 |
| `genpass -w 6` | 77 |

For a password a program stores, such as a database password, the default is plenty. For one you type, 5 or 6
words is a good trade. For a disk or a password manager's main password, use 6 or 7 words.

## Options

| Option | What it does |
|---|---|
| `-l`, `--length N` | Characters per password. 20 by default, 8 at least, 1024 at most. |
| `-n`, `--count N` | How many to print, one per line. 1 by default, 1000 at most. |
| `--no-symbols` | Letters and digits only, for systems that reject symbols. |
| `-w`, `--words N` | A passphrase of N words, from 3 to 64, instead of a password. |
| `-s`, `--sep TEXT` | What goes between the words. A hyphen by default. It can be empty, a space or several characters. |
| `-c`, `--copy` | Copy the result with `clip` and print nothing. Takes one password, not `-n`. |
| `-q`, `--quiet` | Print no lines of its own. With `-c`, hides the line from `clip` too. |
| `-v`, `--verbose` | Print the strength in bits after the result, on stderr. |
| `-h`, `--help` | Show the help. |

`--length` and `--no-symbols` are for passwords, and `--sep` is for passphrases. Mixing them exits 2.

`genpass` has no `-p`. In toolbelt `-p` always means a password you type in, and `genpass` takes none.

## Pass-through

None. It reads `/dev/urandom` directly.

## Needs

`od`, `tr` and `head` from coreutils, and `awk`. Every Linux system has them, BusyBox too. `-c` needs whatever
`clip` needs for your session, such as `wl-clipboard` or `xclip`.

## Examples

### A password

```console
$ genpass
WVAkbXNkPKGKrX-9kCw!
```

### With its strength

```console
$ genpass -v
EpKLuELzveKgGps=rm-9
genpass: 20 characters from 74, about 124 bits
```

### Several long ones with no symbols

```console
$ genpass -n 3 -l 32 --no-symbols
HW6V38wJWkD1DLe1nIbCtk63hGMhRQ9i
RW1AYQEQnTtz5JUlppHCDKtIbGiqTKXc
DYGNMZxM2hoR6tWGiflOLqWzf7p42iMw
```

### A passphrase

```console
$ genpass -v -w 5
blot-geriatric-robin-germinate-undated
genpass: 5 words from 7776, about 64 bits
```

### Another separator

```console
$ genpass -w 4 -s .
turbojet.identity.bobsled.glowworm
$ genpass -w 6 -s ' '
trustful imprison squash evasion liver daycare
```

### Straight to the clipboard

```console
$ genpass -c
clip: copied 20 bytes with wl-copy
```

The clipboard holds the password with no newline, ready to paste into a form.

### In a script

```console
$ kubectl create secret generic db-creds --from-literal=password="$(genpass -l 32)"
secret/db-creds created
```

### Too short

```console
$ genpass -l 4
genpass: length 4 is below the minimum of 8
Try 'genpass --help' for the options.
```

## Troubleshooting

`genpass: length 4 is below the minimum of 8`
: Passwords under 8 characters fall to a guessing attack in minutes. If a system caps the length, use the longest
  it takes.

A site says the password has a character it does not allow
: Use `--no-symbols`, and make it longer to keep the strength, such as `genpass -l 24 --no-symbols`.

`genpass: could not copy, nothing was printed`
: `clip` found no clipboard tool. The line above it says which one to install. `genpass` prints nothing in this
  case, on purpose, so the password never lands on the screen by surprise. Run it without `-c` if you want to see
  it.

`genpass: the word list /home/me/.local/share/toolbelt/lib/words is missing, reinstall toolbelt`
: The install is broken. Run `toolbelt update`, or install toolbelt again.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked. |
| 1 | It failed, such as `/dev/urandom` not readable, or `-c` could not copy. |
| 2 | Bad usage, such as a length under 8 or `-l` with `-w`. |

## See also

`clip`, `lock`, `ksecret`, `openssl-rand(1)`, https://www.eff.org/dice
