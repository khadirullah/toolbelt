# Testing toolbelt

Three levels of checks, from seconds to an hour. Run the first two before every commit and the third before a push
that touches install, packages or anything distro specific.

| Check | Command | Needs | Time |
|---|---|---|---|
| One command's tests | `make test T=unpack` | bash 4.4+, make, bats | seconds |
| Lint, every test, the docs | `make check` | bats, shellcheck, python3 | 10 to 15 min |
| CI's test job on all 8 distros | `make distro-test` | Docker, git | 60 to 80 min |

A new machine has none of these. [Setting up a machine](#setting-up-a-machine) installs each one.

CI on GitHub runs the same checks on every push to `main` and on every pull request. See
[.github/workflows/ci.yml](.github/workflows/ci.yml).

## Setting up a machine

Install only what the checks you plan to run need. Each step below says which checks use it. The commands are
for the distros CI tests. Check each tool at the end of its step before you move on.

### git, make and python3, for everything

```console
$ sudo apt install git make python3              # Debian, Ubuntu
$ sudo dnf install git make python3              # Fedora, Rocky
$ sudo pacman -S git make python                 # Arch
$ sudo zypper install git make python3           # openSUSE
```

### bats, for the tests

The tests need bats 1.5.0 or newer. Some distros ship older ones, such as 1.2.1 on Ubuntu 22.04, so clone it
instead. `make test` finds it in this folder, with nothing to install:

```console
$ git clone --depth 1 https://github.com/bats-core/bats-core.git ~/.cache/toolbelt-dev/bats-core
$ ~/.cache/toolbelt-dev/bats-core/bin/bats --version
Bats 1.14.0
```

`make test` prefers a `bats` on your PATH. If an older one is installed there, point make at the clone:
`make test BATS=~/.cache/toolbelt-dev/bats-core/bin/bats`.

### shellcheck, for make lint and make check

```console
$ sudo apt install shellcheck                    # Debian, Ubuntu
$ sudo dnf install ShellCheck                    # Fedora, and Rocky after: sudo dnf install epel-release
$ sudo pacman -S shellcheck                      # Arch
$ sudo zypper install ShellCheck                 # openSUSE
$ shellcheck --version
```

With Docker installed you can skip this and run shellcheck from its image, as [Lint and docs](#lint-and-docs)
shows.

### Docker, for make distro-test

```console
$ sudo apt install docker.io                     # Debian, Ubuntu
$ sudo dnf install moby-engine                   # Fedora
$ sudo pacman -S docker                          # Arch
$ sudo zypper install docker                     # openSUSE
```

Rocky has no Docker in its own repos. Use Docker's packages from <https://docs.docker.com/engine/install/>,
which also cover Debian, Ubuntu and Fedora.

Then start Docker and let your user run it without sudo. The group change takes effect at your next login:

```console
$ sudo systemctl enable --now docker
$ sudo usermod -aG docker "$USER"
```

Log out and back in, then check it and remove the test image:

```console
$ docker run --rm hello-world
Hello from Docker!
...
$ docker rmi hello-world
```

Anyone in the `docker` group can get root on the machine through Docker, so add only users you would trust with
root.

### Disk and memory

- `make test` and `make check` need almost nothing. Fixtures are a few KB and go in a temp folder.
- `make distro-test` needs about 2 GB of free disk for the image and packages of the distro it is running. It
  removes them before the next one. Each container uses up to 1.5 GB of memory. On a small machine, cap it
  with `tools/distro-test -m 1500m`.

## The test suite

Every command has a file in `tests/`, named after it. The tests make their own fixtures of a few KB and stub the
network, systemd, the package manager and kubectl, so they need no network, no root and no cluster.

```console
$ make test T=unpack          # one file
$ make test                   # all 1149 tests
```

`make test` uses `bats` from your PATH, or else the clone in `~/.cache/toolbelt-dev/bats-core`, see
[bats, for the tests](#bats-for-the-tests).

Each test prints `ok` or `not ok` with its number and name. A few say `# skip` and a reason, such as
`zip is not installed`. Those need an optional tool this machine lacks, and they run where it is installed.

A failure looks like this:

```
not ok 911 -b opens a tunnel in the background, --list shows it, --stop closes it
# (from function `not' in file tests/helpers.bash, line 69,
#  in test file tests/sshfwd.bats, line 119)
#   `not kill -0 "$master"' failed
# expected to fail: kill -0 4242
```

The line in backticks is the check that failed, and the lines above it point at the test file and line. Any
lines after it are what the test printed. To rerun only that test, filter by its name with bats:

```console
$ ~/.cache/toolbelt-dev/bats-core/bin/bats -f 'opens a tunnel' tests/sshfwd.bats
```

How to write tests is in [CONTRIBUTING.md](CONTRIBUTING.md#tests).

## Lint and docs

`make lint` runs shellcheck on every script, and `make check` runs lint, every test and `tools/check-docs.py`,
which checks each command's help, docs page and man page against the rules in CONTRIBUTING.md.

CI installs shellcheck 0.9.0 from Ubuntu 24.04. Without shellcheck on your machine, run that version from its
Docker image:

```console
$ docker run --rm -v "$PWD":/mnt:ro -w /mnt koalaman/shellcheck:v0.9.0 -x \
    bin/* lib/common.sh lib/kube.sh shell/functions.sh install.sh completions/toolbelt.bash \
    tools/distro-test
```

`.shellcheckrc` lists the checks the code turns off on purpose, each with its reason. Anything else shellcheck
reports is a real finding. Fix it, or turn it off on that one line with a comment that says why.

After changing a page in `docs/`, run `make man` and commit the man page for that command. `make man` also
bumps the date in every other page. Put those back, here for `unpack`:

```console
$ git diff --name-only man | grep -v '^man/man1/unpack.1$' | xargs -r git checkout --
```

CI's lint job rebuilds the pages and fails when one differs from `docs/` in more than its date.

## Every distro, locally

`tools/distro-test` runs CI's test job in a local container for each distro, one at a time, then installs
toolbelt as a normal user, runs 19 commands and uninstalls it. The image list and the install step come from
`.github/workflows/ci.yml`, so a change there reaches local runs too.

It needs Docker and git, which it uses to fetch bats. `DOCKER=podman` points it at Podman instead.

```console
$ make distro-test                          # all 8 distros
$ make distro-test D=alpine:3               # one
$ tools/distro-test -m 1500m                # cap each container at 1.5 GB of memory
$ tools/distro-test -t tests/epoch.bats alpine:3 fedora:44
$ tools/distro-test --no-smoke debian:13    # tests only, no install check
$ tools/distro-test --list                  # the images CI tests
```

Each distro takes 5 to 14 minutes, most of it installing packages and running the 1149 tests. It prints one line
per distro as it finishes:

```
alpine:3  passed 1149, failed 0, skipped 54, smoke 22 ok 0 failed  388s
```

- `passed` counts every `ok` line, skipped ones included. `failed` must be 0.
- `skipped` counts tests that need a tool CI's install step leaves out on that distro, such as zip.
- `smoke` counts the install check steps. Each step names the command and its exit code when it fails.

It exits 0 when every distro passed. Logs are in `~/.cache/toolbelt-dev/distro-test/`, one per image, such as
`alpine_3.log`, with a `summary.txt` of the lines above. Search a log for `not ok` or `smoke FAIL` to find what
broke. It removes each image it pulled once that distro is done, and keeps images you already had. Ctrl-C
stops the run and removes the container it was using.

The containers start with `tail -f /dev/null` as PID 1, as GitHub Actions does. That matters because `tail` never
reaps a process whose parent has exited, so such a process stays a zombie, and `kill -0` still finds it. A test
that checks a background process has stopped must use `gone PID` from `tests/helpers.bash`, which counts a zombie
as stopped.

## When CI fails

Open the red job on GitHub, then the red step. bats prints each `not ok` where it happens, so search the step's
log for `not ok` rather than reading the end. The end only shows the exit code. To reproduce it here, run the
same distro with the failing test file:

```console
$ tools/distro-test -t tests/sshfwd.bats debian:13
```
