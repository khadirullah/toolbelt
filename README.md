# toolbelt

Small Bash commands for the Linux jobs you do every week and never remember the flags for.

```console
$ unpack -k backup.tar.gz
backup.tar.gz -> backup/ (24KB, 4 files, 0.0s)
$ port 8000
8000/tcp  0.0.0.0  pid 4121  me  python3 -m http.server 8000
$ genpass
WVAkbXNkPKGKrX-9kCw!
```

`unpack` works out the format and picks the tool itself. The files land in one folder, so nothing spills into the
current one, and it asks before it moves the archive to the trash. `port` tells you what holds a port, and
`port -k` stops it after asking. `genpass` reads `/dev/urandom` and prints one password. Each of the 70 commands is one
Bash file, or a shell function for `mkcd` and `up`. Each has a help page, a manual page and tests, and runs on the
8 distros CI tests.

## Install

For one user, with no sudo:

```console
$ curl -fsSL https://raw.githubusercontent.com/khadirullah/toolbelt/main/install.sh | bash
```

Or from a clone, which is the same install and lets you read the script first:

```console
$ git clone https://github.com/khadirullah/toolbelt.git
$ cd toolbelt
$ ./install.sh
```

The files go to `~/.local/share/toolbelt`. Each command gets a link in `~/.local/bin`, its man page a link in
`~/.local/share/man/man1`, and its bash completion a link in `~/.local/share/bash-completion/completions`. If
`~/.local/bin` is not on your PATH, the installer prints the line to add to `~/.bashrc`.

`./install.sh --prefix DIR` installs somewhere else. `./install.sh --uninstall`, or `toolbelt uninstall`, removes
every link it made and nothing else. A file of your own with the same name as a command stays untouched.

Then check the machine:

```console
$ toolbelt doctor
```

It lists the optional tools you lack, which commands use them, and the install line for your distro. `toolbelt
setup` installs them after it shows you the exact command and asks.

## Needs

Bash 4.4 or newer and the usual base tools (coreutils, findutils, grep, sed, awk). Most commands also wrap a tool
that does the real work, such as `7z`, `rsync`, `ss`, `journalctl`, `kubectl` or `openssl`. When one is missing,
the command stops with exit 3 and prints the install line for your package manager:

```console
$ unpack photos.7z
unpack: needs 7z. Install it with: sudo apt install 7zip
```

`lib/pkgmap` holds the package name of every tool for apt, dnf, pacman, zypper and apk. CI checks that each name
exists in each distro's repos.

## Where it runs

CI runs the full test suite on Debian 13, Ubuntu 24.04, Ubuntu 22.04, Fedora 44, Rocky Linux 9, Arch Linux,
openSUSE Leap 15 and Alpine 3. On Alpine the base tools are BusyBox, and the commands fall back where BusyBox
lacks an option. Other distros in these families should work. They are not tested.

## The commands

`toolbelt help` prints this list, and `toolbelt help GROUP` adds the descriptions. Every command has
`COMMAND --help` for one screen and `man COMMAND` for the full manual.

### Archives

| Command | What it does |
|---|---|
| [unpack](docs/unpack.md) | Unpack any archive, from a file or a URL. |
| [squash](docs/squash.md) | Pack files and folders into any free format. |
| [archdiff](docs/archdiff.md) | List what changed between two archives. |
| [archmount](docs/archmount.md) | Open an archive as a folder without unpacking. |
| [autounpack](docs/autounpack.md) | Unpack archives as they land in ~/Downloads. |

### Files

| Command | What it does |
|---|---|
| [bak](docs/bak.md) | Copy a file aside before you edit it. |
| [checksum](docs/checksum.md) | Hash a file, or check it against a hash or SUMS file. |
| [bulkrename](docs/bulkrename.md) | Rename many files with a pattern or in your editor. |
| [fixperms](docs/fixperms.md) | Set folders to 755 and files to 644, with a preview. |
| [dupes](docs/dupes.md) | Find duplicate files by content. |
| [bigfiles](docs/bigfiles.md) | List the biggest files or folders under a path. |
| [recent](docs/recent.md) | List the files changed lately, newest first. |
| [mirror](docs/mirror.md) | Make a folder match another, showing the changes first. |
| [lock](docs/lock.md) | Encrypt a file or folder with age, or gpg. |
| [unlock](docs/unlock.md) | Decrypt a file made by lock, age or gpg. |
| [shrink](docs/shrink.md) | Make an image, video or PDF fit a size. |
| [togif](docs/togif.md) | Turn a video clip into a small GIF. |

### System

| Command | What it does |
|---|---|
| [pkg](docs/pkg.md) | One package command on every distro. |
| [mem](docs/mem.md) | Who uses the memory, and who goes first when it runs out. |
| [cleanup](docs/cleanup.md) | See what fills the disk, then clean it safely. |
| [sysinfo](docs/sysinfo.md) | The whole machine on one screen. |
| [proc](docs/proc.md) | Everything about one process. |
| [svc](docs/svc.md) | Systemd services in one place. |
| [logs](docs/logs.md) | Errors and warnings from the journal, grouped by unit. |
| [disks](docs/disks.md) | Drives, partitions, space and health together. |
| [boottime](docs/boottime.md) | Where the boot time went. |
| [temps](docs/temps.md) | CPU, drive and board temperatures, and fan speed. |
| [seccheck](docs/seccheck.md) | A quick security check of this machine, with fixes. |
| [schedules](docs/schedules.md) | Cron jobs and systemd timers in one table. |

### Network

| Command | What it does |
|---|---|
| [port](docs/port.md) | Show who is listening on a port. |
| [myip](docs/myip.md) | Local and public IP addresses, gateway and DNS. |
| [netcheck](docs/netcheck.md) | Find where the network breaks, step by step. |
| [waitfor](docs/waitfor.md) | Wait for a port, a URL or a file. |
| [share](docs/share.md) | Send text, a link, Wi-Fi or a folder to your phone. |
| [lan](docs/lan.md) | Every device on the local network. |
| [httptime](docs/httptime.md) | Where the time goes in one HTTP request. |
| [sshfwd](docs/sshfwd.md) | SSH tunnels without remembering -L, -R and -D. |
| [speed](docs/speed.md) | Download and upload speed test. |

### Everyday

| Command | What it does |
|---|---|
| [again](docs/again.md) | Run a command again until it works. |
| [notify-done](docs/notify-done.md) | Tell you when a long command finishes. |
| [cheats](docs/cheats.md) | Short examples for a command, cached offline. |
| [clip](docs/clip.md) | Copy and paste from the terminal. |
| [genpass](docs/genpass.md) | Random passwords and passphrases. |
| [timer](docs/timer.md) | Countdown or stopwatch in the terminal. |
| [note](docs/note.md) | Jot a line into today's notes file. |
| [epoch](docs/epoch.md) | Convert Unix timestamps and dates both ways. |

### Kubernetes

| Command | What it does |
|---|---|
| [kwhy](docs/kwhy.md) | Show why pods are not Ready, on one screen. |
| [ksecret](docs/ksecret.md) | Show a Secret decoded, one key or all. |
| [kyaml](docs/kyaml.md) | Print clean YAML of a live object, ready to reuse. |
| [kclean](docs/kclean.md) | Delete evicted, completed and crashing pods. |
| [kfwd](docs/kfwd.md) | Port-forward a service to a spare local port. |
| [kres](docs/kres.md) | Compare node requests with real usage. |
| [knodes](docs/knodes.md) | Show node health and pressure at a glance. |
| [kevents](docs/kevents.md) | Show recent events in time order, newest last. |

### DevOps

| Command | What it does |
|---|---|
| [ctx](docs/ctx.md) | Where your commands will land, on one screen. |
| [certcheck](docs/certcheck.md) | Days until a TLS certificate expires. |
| [dnscheck](docs/dnscheck.md) | The DNS records email depends on. |
| [tfcheck](docs/tfcheck.md) | Every Terraform check in one pass. |
| [yamlcheck](docs/yamlcheck.md) | Lint YAML and check Kubernetes manifests. |
| [imgpeek](docs/imgpeek.md) | Look inside a container image. |
| [jwtpeek](docs/jwtpeek.md) | Decode a JWT and show when it expires. |
| [git undo](docs/git-undo.md) | Take back the last commit and keep its changes. |
| [git prune-merged](docs/git-prune-merged.md) | Delete local branches already merged into main. |
| [git recent](docs/git-recent.md) | List local branches by their last commit, newest first. |
| [git wip](docs/git-wip.md) | Save every change as a commit named wip. |
| [git sync](docs/git-sync.md) | Fetch and rebase the current branch onto its upstream. |
| [git whoami](docs/git-whoami.md) | Show the name, email and signing key git will use here. |

The git helpers are programs named `git-undo` and so on, so git finds them and `git undo` works. `git undo -h`
prints their help. `git undo --help` makes git look for the man page, which the install provides.

### Shell

| Command | What it does |
|---|---|
| [mkcd](docs/mkcd.md) | Make a folder with its parents, and move into it. |
| [up](docs/up.md) | Go up n folders, or to the nearest parent with a name. |
| [toolbelt](docs/toolbelt.md) | Help, health check, setup and updates for toolbelt. |

`mkcd` and `up` change the folder of the shell you type them in, which a separate program cannot do. They are shell
functions, off until you turn them on:

```console
$ toolbelt shell enable functions
```

That adds one line ending in `# toolbelt` to `~/.bashrc`, or `~/.zshrc` in zsh. `toolbelt shell` lists two more
opt-in settings, a longer shared history and `cp`/`mv` that ask before overwriting.

## What every command does the same way

Learn one command and you know how the others behave.

**Options.** `-h` prints help, `-q` prints only the result line, `-v` prints each step and each real command
before it runs, as a line you can copy and run yourself, and `-y` answers yes to questions. Short options bundle,
so `-qk` works. Options after `--` go to the tool the command wraps:

```console
$ unpack -v photos.7z -- -mmt=4
```

**`-p` means password.** Only commands that take a password have it, and they always ask for the password. None
takes it on the command line, where `ps` and your shell history would show it.

**Output.** The result goes to stdout, so `$(genpass)` and pipes get only what they need. Progress, questions,
warnings and errors go to stderr. Colour appears only in a terminal and never when `NO_COLOR` is set.

**Asking before a change.** Nothing destructive happens without a question. With no terminal to ask in, the
command refuses with exit 4 unless you gave `-y`. Deleted files go to the desktop trash, the same one your file
manager uses, so you can take them back. After `unpack` and `squash` check their result, they offer to move the
original to the trash. `--rm` does it without asking and `-k` keeps it without asking.

**Never overwriting.** When a name is taken, commands write `name-1.ext` instead.

**Exit codes.**

| Code | Meaning |
|---|---|
| 0 | It worked. |
| 1 | It failed, and the message says why. |
| 2 | Bad usage. The message points at `--help`. |
| 3 | A tool is missing. The message has the install line. |
| 4 | A safety check refused. |
| 5 | You answered no. |

A few commands add a meaning of their own, such as `certcheck` exiting 1 when a certificate expires within the
warning window. Each manual page lists its codes under Exit status.

**Files.** Commands that keep records use `~/.local/state/toolbelt`. Caches go in `~/.cache/toolbelt` and
settings in `~/.config/toolbelt`. The XDG variables move them. Temp folders are removed on exit, Ctrl+C included.

## Documentation

- `COMMAND --help` prints one screen, with examples.
- `man COMMAND` prints the full manual page, with every option, how the command decides, per-distro notes,
  worked examples and troubleshooting.
- [docs/](docs/) holds the same manual pages as Markdown. `make site` builds them into a static website in
  `site/out`, and each push to `main` publishes it to GitHub Pages.

## Working on toolbelt

[CONTRIBUTING.md](CONTRIBUTING.md) is the contract every command follows, from the script header to the help
layout and the tests. `toolbelt new NAME` writes a new command, its tests and its docs page from the same
template.

```console
$ make test            # every test, with bats
$ make test T=unpack   # one command
$ make lint            # shellcheck
$ make check           # lint, every test and the docs check
$ make man             # rebuild man/ from docs/
$ make site            # build the website into site/out
```

Tests make their fixtures on the fly, a few KB each, and stub the network, systemd, the package manager and
kubectl. The suite needs no network, no root and no cluster.

## Credits

`genpass -w` uses the EFF large word list by the Electronic Frontier Foundation, under CC BY 3.0 US
(https://www.eff.org/dice).

## License

MIT. See [LICENSE](LICENSE).
