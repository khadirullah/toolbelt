# proc

Everything about one process.

## Synopsis

```
proc [-f] [-e] PID | NAME
```

## Description

`ps` shows a line per process. To learn more about one of them you usually run five more commands. `pstree -s`
for its parents, `systemctl show` for its unit, `dpkg -S` for its package, `ss -ltnp` for its ports and
`ls -l /proc/PID/fd` for its files. `proc` does all of that for one process and prints one line per answer.

| Line | What it shows | Where it comes from |
|---|---|---|
| pid | The pid and the full command line. | `/proc/PID/cmdline` |
| user | Who runs it, when it started and how long ago. | `/proc/PID/status`, `/proc/PID/stat` |
| tree | Every parent up to pid 1, as `name(pid) > name(pid)`. | `/proc/PID/status` of each parent |
| unit | The systemd unit it belongs to, system or user, and whether that unit is active. | `/proc/PID/cgroup`, `systemctl is-active` |
| package | The package that installed the program, with its version. | `pkg owner` on `/proc/PID/exe` |
| memory | RSS, swap and the OOM score. | `/proc/PID/status`, `/proc/PID/oom_score` |
| cpu | CPU use over half a second, total CPU time and the number of threads. | `/proc/PID/stat`, two reads |
| ports | The TCP and UDP ports it listens on. | `ss -l -t -u -n -p` |
| files | How many files it has open, and how many of those were deleted. | `/proc/PID/fd` |

The unit line matters for services. A process under `nginx.service` comes back when you kill it, because systemd
restarts it. Stop the unit instead, with `svc stop nginx`. A process under a `.scope` unit is an app you started,
such as a terminal or a desktop program.

The package line tells you whether the program came from the distro or was installed by hand. When the program
file was replaced on disk after the process started, as after an update, the line says so. The process still
runs the old code until it restarts.

The files line counts files that were deleted while the process kept them open. Their space is only freed when
the process closes them or ends. A big log file deleted under a running service is the usual reason `df` shows a
full disk that `du` cannot explain.

`proc` only reads. It never signals, kills or changes a process.

## Finding the process

Give a pid, or a name. For a name, `proc` tries three things in order and stops at the first that matches.

1. The kernel's name for the process, in `/proc/PID/comm`. The kernel cuts it to 15 characters, and `proc` cuts
   your name the same way, so `proc cinnamon-session-binary` finds `cinnamon-sessio`.
2. The program name, the last part of the first word of the command line. That finds scripts, whose kernel name
   is `python3` or `bash`.
3. Any part of the command line. That finds `java -jar app.jar` from `proc app.jar`.

When more than one process matches, `proc` lists them with their pids and exits 2, so you can pick one. It never
guesses. `proc` leaves itself out of the search, and its parent shell out of the command line search, since that
shell has the name in its own command line.

## Options

| Option | What it does |
|---|---|
| `-f`, `--files` | List every open file and socket, one per line, instead of the count. |
| `-e`, `--env` | Show the process's environment, sorted, with secret values hidden. |
| `-q`, `--quiet` | Print only the pid and the command line. |
| `-v`, `--verbose` | Show each file it reads and each command it runs. |
| `-h`, `--help` | Show the help. |

## Open files

With `-f`, each open file descriptor gets a line with its number, a type and a name.

| Type | What it is |
|---|---|
| `file` | A regular file. A deleted one ends in `(deleted)`. |
| `dir` | A folder, such as the working folder a program keeps open. |
| `dev` | A device, such as `/dev/null` or a disk. |
| `tty` | A terminal. |
| `pipe` | A pipe to another process. |
| `tcp`, `udp` | A network socket, with its address and whether it listens or where it connects to. |
| `unix` | A local socket, with its path. A connected socket with no path of its own shows its peer's path. |
| `anon` | A kernel object with no file, such as `eventfd` or `eventpoll`. |
| `sock` | A socket `ss` does not know about. |

Socket names come from `ss -e`, which shows each socket's inode, the number `/proc/PID/fd` points to.

## Hidden values

With `-e`, a variable whose name contains `KEY`, `TOKEN`, `SECRET`, `PASS`, `AUTH`, `CREDENTIAL` or `COOKIE`
shows as `***`. A URL with a password in it, such as `postgres://app:hunter2@db/app`, shows as
`postgres://app:***@db/app`. Everything else shows as it is. That makes `-e` safe to paste into a chat, but read
it once before you do, since a secret can hide under any name.

## Other users' processes

Anyone can read most of `/proc` for any process. The open files, the environment and the ports of another user's
process need root. For those `proc` prints `unknown, run it with sudo to see them` and shows the rest. With `-f`
or `-e` it stops with a message, since there is nothing else to show.

## Per-distro notes

Debian, Ubuntu, Fedora, Arch and openSUSE
: Everything works. The unit line needs systemd and cgroup v2, which all of them use by default. On older
  releases with cgroup v1, `proc` reads the `name=systemd` line of the cgroup file instead.

Alpine
: There is no systemd, so there is no unit line. BusyBox has no `ss`, so install `iproute2` for the ports line.
  The package line uses `apk info -W`.

Containers
: A container sees only its own processes, and pid 1 is the container's first program. The tree ends there.

WSL
: WSL 2 runs a real Linux kernel, so `proc` works. Windows programs do not show up.

## Needs

`/proc`, which every Linux system has. The rest adds lines and is optional.

| Tool | Package | Adds |
|---|---|---|
| `ss` | `iproute2`, or `iproute` on Fedora | The ports line, and socket names with `-f`. |
| `systemctl` | `systemd` | Whether the unit is active. |
| `pkg` | this toolbelt | The package line, through dpkg, rpm, pacman or apk. |

## Examples

### A service

```console
$ proc cron
pid      1003  /usr/sbin/cron -f
user     root, started Sep 29 00:17, 17h ago
tree     systemd(1) > cron(1003)
unit     cron.service, system unit, active
package  cron 3.0pl1-197
memory   RSS 2.4MB, swap 152KB, oom score 666
cpu      0.0% now, 0.1s in total, 1 thread
ports    unknown, run it with sudo to see them
files    unknown, run it with sudo to see them
```

cron runs as root, so its ports and files need `sudo proc cron`.

### A user service with deleted files

```console
$ proc 1449
pid      1449  /usr/bin/pipewire
user     test, started Sep 29 00:17, 17h ago
tree     systemd(1) > systemd(1426) > pipewire(1449)
unit     pipewire.service, user unit, active
package  pipewire-bin 1.4.2-1
memory   RSS 9MB, swap 2.9MB, oom score 800
cpu      0.0% now, 12s in total, 3 threads
ports    none listening
files    54 open, 5 deleted but still open
```

The second `systemd` in the tree is the user's own service manager, which starts the user units.

### A name that matches several

```console
$ proc pipewire
proc: 2 processes match pipewire. Give a pid.
    1449  /usr/bin/pipewire
    1450  /usr/bin/pipewire -c filter-chain.conf
$ echo $?
2
```

### Every open file and socket

```console
$ proc -f 1449 | head -8
pid 1449  /usr/bin/pipewire
FD    TYPE  NAME
0     dev   /dev/null
1     unix  to /run/systemd/journal/stdout
2     unix  to /run/systemd/journal/stdout
3     unix  /run/user/1000/pipewire-0, listening
4     unix  /run/user/1000/pipewire-0-manager, listening
5     anon  [eventpoll]
```

Its output goes to the journal, and it listens on two sockets in `/run/user/1000`.

### A program installed by hand

```console
$ proc demo-worker
pid      1745412  ./demo-worker 60
user     test, started Sep 29 17:28, 1s ago
tree     systemd(1) > lightdm(1007) > cinnamon(1751) > bash(587807) > demo-worker(1745412)
unit     app-code-2115.scope, user unit, active
package  no package, installed by hand
memory   RSS 1.7MB, swap 0B, oom score 666
cpu      0.0% now, 0.0s in total, 1 thread
ports    none listening
files    4 open
```

### The environment, with secrets hidden

```console
$ proc -e demo-worker | grep -E 'TOKEN|URL|LANG'
APP_TOKEN=***
DATABASE_URL=postgres://app:***@db:5432/app
LANG=C.UTF-8
```

### Just the command line

```console
$ proc -q demo-worker
1745412  ./demo-worker 60
```

## Troubleshooting

`proc: no process matches NAME`
: No kernel name, program name or command line contains NAME. Check the spelling with `ps -e | grep NAME`. The
  process may have ended.

`proc: no process with pid PID`
: The process ended, or the pid is from another machine or container. A process inside a container has a
  different pid on the host.

`ports    unknown, run it with sudo to see them`
: The process belongs to another user. Run `sudo proc NAME`.

`proc: cannot read the open files of PID, it belongs to root. Run it with sudo`
: `-f` and `-e` need to read files only the owner and root can read.

The package line is missing
: `pkg` found no package manager, or the program file could not be found. For a script the line names the
  package of its interpreter, such as `python3`, since that is the program the kernel runs.

`package  unknown, the program file was replaced or deleted`
: An update replaced the program while it ran. Restart it to run the new version. `svc restart NAME` does that
  for a service.

The cpu line says `0.0% now` for a busy process
: `proc` measures over half a second. A process that works in short bursts can be idle in that window. Run it
  again, or watch it with `top -p PID`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked. |
| 1 | No such process, or its files or environment could not be read. |
| 2 | Bad usage, or a name that matches more than one process. |

## See also

`mem`, `svc`, `pkg`, `ps(1)`, `ss(8)`, `proc(5)`
