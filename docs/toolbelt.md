# toolbelt

Help, health check, setup and updates for toolbelt.

## Synopsis

```
toolbelt help [group | command]
toolbelt doctor
toolbelt setup [--only group] [-y] [-- package manager options]
toolbelt shell [enable | disable] [setting ...]
toolbelt update [--check] [-y]
toolbelt version
toolbelt uninstall [-y]
toolbelt new name
```

## Description

`toolbelt` is the one command that looks after the others. It lists every command, checks your machine for the
tools they use, installs what is missing, turns on the shell settings, and updates or removes toolbelt itself.

Every other command works on its own. You never type `toolbelt unpack`, you type `unpack`. `toolbelt` is only for
finding commands and keeping the install healthy.

`toolbelt doctor` and `toolbelt help` only read. `setup`, `update` and `uninstall` show what they will do and ask
before they change anything. `shell` changes one line in your shell startup file and tells you which.

## Subcommands

### help

`toolbelt help` prints every command, grouped the way this manual groups them. It fits one screen.

`toolbelt help GROUP` adds the one-line description of each command in the group. Groups are archives, files,
system, network, everyday, kubernetes, devops and shell, in any case.

`toolbelt help COMMAND` prints that command's help page, the same as `COMMAND --help`. For the git helpers you can
write `toolbelt help git-undo` or `toolbelt help "git undo"`.

### doctor

`toolbelt doctor` checks the machine and prints one line per topic.

| Line | What it checks |
|---|---|
| `distro` | The distro name and version from `/etc/os-release`, and the package manager toolbelt found. |
| `bash` | The Bash version. toolbelt needs 4.4 or newer. |
| `shell` | Your login shell, and whether oh-my-zsh is installed. |
| `path` | Whether the folder with the toolbelt commands is on your PATH. |
| `missing` | Optional tools that are not installed, which commands use them, and the install line for your distro. |
| `clashes` | Commands that run something other than toolbelt's copy. |
| `note` | Things that look like a clash but are not, such as the oh-my-zsh `extract` plugin. |
| `recommend` | Good tools toolbelt does not replace, such as btop, ncdu, fzf, tldr and dive, when they are missing. |

A clash is either a program with the same name earlier on your PATH, or an alias or function with the same name in
`~/.bashrc`, `~/.zshrc` or `~/.bash_aliases`. doctor names the file. Fix a clash by renaming one of the two, or by
moving `~/.local/bin` earlier in PATH.

With `-q`, doctor prints only problems, so a script can run it and show the output only when there is something to
fix.

### setup

`toolbelt setup` reads the list of optional tools, finds the ones you lack, and looks up each package name for your
package manager. It prints the list grouped by what the tools are for, prints the exact command it will run, and
asks. Tools that your distro does not package are listed at the end with a note to get them from their project.

`--only GROUP` limits the list to one group, such as `--only archives`.

Options after `--` go to the package manager, for example `toolbelt setup -- --no-install-recommends` on apt.

setup runs the package manager with sudo, unless you are root.

### shell

Three opt-in settings, off until you turn them on.

| Setting | What it does |
|---|---|
| `functions` | Loads `mkcd` and `up`. They must run inside your shell to change its folder, so they are shell functions and need this setting. |
| `history` | Keeps 50000 lines of history with a timestamp on each, writes each command at once, and shares history between open terminals. |
| `safe` | Makes `cp` and `mv` ask before they overwrite a file, with aliases to `cp -i` and `mv -i`. |

`toolbelt shell` lists the settings, whether each is on, and the line that loads them.

`toolbelt shell enable functions history` turns settings on. The first time, it adds one line, ending in
`# toolbelt`, to `~/.bashrc`, or to `~/.zshrc` when your shell is zsh. That line loads
`~/.local/share/toolbelt/shell/init.sh`, which reads the settings from `~/.config/toolbelt/shell`. Open a new
terminal, or run `source ~/.bashrc`, to use them.

`toolbelt shell disable safe` turns a setting off. The line stays, and loads nothing that is off.

In zsh, the same line also puts toolbelt's completion folder on `fpath`.

### update

`toolbelt update` asks GitHub for the latest release, prints the installed and latest versions, and asks before
it changes anything. It downloads the release tarball and its `.sha256` file, checks the hash, unpacks it into a
temp folder and runs its installer with your install prefix. When the hash does not match, it stops with exit 4
and changes nothing.

`--check` only prints the two versions.

### version

Prints the toolbelt version, the Bash version and the distro on one line. Paste it into a bug report.

### uninstall

Removes every command link, man page link, completion link and the `# toolbelt` line in your shell startup file,
then the installed files in `~/.local/share/toolbelt`. It asks first. It keeps your notes and anything in
`~/.config/toolbelt`, `~/.local/state/toolbelt` and `~/.cache/toolbelt`, so a later install picks up where you
left off. Delete those folders by hand to remove every trace.

It removes only links that still point into toolbelt. A file of your own with the same name stays.

### new

`toolbelt new NAME` starts a command of your own from the same template the others use, with help, the shared
options, tool checks and exit codes in place.

Inside a clone of the toolbelt repo, it writes `bin/NAME`, `tests/NAME.bats` and `docs/NAME.md`. Anywhere else, it
writes `./NAME`, which loads the installed toolbelt library.

The name must be lower case letters, digits and `-`, starting with a letter. new refuses a name that is already a
command on your PATH, with exit 4, so your command never hides another.

## Options

| Option | What it does |
|---|---|
| `--only GROUP` | setup: only the tools for one group. |
| `--check` | update: only report the installed and latest versions. |
| `-y`, `--yes` | Do not ask in setup, update and uninstall. |
| `-q`, `--quiet` | doctor: print only problems. |
| `-v`, `--verbose` | Every step, and each real command before it runs. |
| `-h`, `--help` | The help page. |

## Pass-through

`toolbelt setup` passes the options after `--` to your package manager. The other subcommands take none.

```console
$ toolbelt setup -- --no-install-recommends
```

## Needs

Bash 4.4 or newer. `update` needs curl or wget. `setup` needs sudo, unless you run it as root.

## Files

| Path | What it holds |
|---|---|
| `~/.local/share/toolbelt/` | The installed commands, library, completion and man pages. |
| `~/.local/share/toolbelt/.installed` | Every link the installer made, so uninstall removes exactly those. |
| `~/.local/bin/` | One link per command. |
| `~/.config/toolbelt/shell` | The shell settings that are on, one per line. |
| `~/.local/state/toolbelt/` | Records some commands keep, such as unpack's history. |
| `~/.cache/toolbelt/` | Caches, such as cheats pages. |

The XDG variables move these folders when they are set.

## Examples

### See every command

```console
$ toolbelt help
Archives    unpack squash archdiff archmount autounpack
Files       bak checksum bulkrename fixperms dupes bigfiles
            recent mirror lock unlock shrink togif
System      pkg mem cleanup sysinfo proc svc logs disks boottime
            temps seccheck schedules
Network     port myip netcheck waitfor share lan httptime sshfwd
            speed
Everyday    again notify-done cheats clip genpass timer note
            epoch
Kubernetes  kwhy ksecret kyaml kclean kfwd kres knodes kevents
DevOps      ctx certcheck dnscheck tfcheck yamlcheck imgpeek
            jwtpeek git undo prune-merged recent wip sync whoami
Shell       mkcd up
toolbelt    help doctor setup shell update version uninstall new

toolbelt help GROUP adds descriptions. COMMAND --help shows one page.
```

### One group, with descriptions

```console
$ toolbelt help kubernetes
kwhy     show why pods are not Ready, on one screen
ksecret  show a Secret decoded, one key or all
kyaml    print clean YAML of a live object, ready to reuse
kclean   delete evicted, completed and crashing pods
kfwd     port-forward a service to a spare local port
kres     compare node requests with real usage
knodes   show node health and pressure at a glance
kevents  show recent events in time order, newest last
```

### Check the machine

```console
$ toolbelt doctor
distro     Debian 13, apt
bash       5.2.37, 4.4 or newer is needed
shell      bash
path       ~/.local/bin is on PATH
missing    3 optional tools
  brotli       unpack squash  sudo apt install brotli
  qrencode     share          sudo apt install qrencode
  tflint       tfcheck        no apt package, get it from its project page
clashes    none
recommend  ncdu fzf tldr dive
```

A clash, printed with `-q` so only problems show:

```console
$ toolbelt doctor -q
clashes    1 clash
! ~/bin/timer comes before toolbelt's timer on PATH
  rename one, or move ~/.local/bin earlier in PATH
```

### Install the optional tools for archives

```console
$ toolbelt setup --only archives
recommended tools for Debian 13, apt
  archives    brotli archivemount
  installed   zstd pigz 7z lz4 lzip lzop unar pv, skipped
will run  sudo apt install -y brotli archivemount
Install 2 packages? [y/N] y
```

### Turn on mkcd and up

```console
$ toolbelt shell enable functions
enabled functions in ~/.bashrc
open a new terminal, or run: source ~/.bashrc
$ toolbelt shell
SETTING    STATE  WHAT IT DOES
functions  on     mkcd and up
history    off    50000 lines, timestamps, shared by terminals
safe       off    cp and mv ask before they overwrite
loaded by  ~/.bashrc line 118
```

### Update

```console
$ toolbelt update
installed  0.1.0
latest     0.2.0
Update to 0.2.0? [y/N] y
checked sha256 of toolbelt-0.2.0.tar.gz
updated to 0.2.0
```

### Start a command of your own

```console
$ toolbelt new mytool
wrote bin/mytool          the command, with help and options
wrote tests/mytool.bats   3 starter tests
wrote docs/mytool.md      the help page
try it: ./bin/mytool --help
$ toolbelt new tree
toolbelt: tree is already on PATH at /usr/bin/tree, pick another name
```

## Troubleshooting

**"command not found" right after install.** `~/.local/bin` is not on your PATH. The installer printed the line to
add. Add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` and open a new terminal.

**A command runs something else.** Run `toolbelt doctor`. It names the program or alias that comes first.

**mkcd says command not found.** Run `toolbelt shell enable functions` and open a new terminal.

**setup says no known package manager.** toolbelt knows apt, dnf, yum, pacman, zypper and apk. On other systems,
install the tools doctor lists by hand.

## Exit status

The shared codes: 0 ok, 1 failed, 2 bad usage, 3 missing tool, 4 refused, 5 answered no.

- `doctor` exits 1 when it finds a clash or the command folder is not on PATH.
- `setup`, `update` and `uninstall` exit 5 when you answer no.
- `update` exits 4 when the sha256 does not match.
- `new` exits 4 when the name is taken.

## See also

`mkcd`, `up`, and each command's own page.
