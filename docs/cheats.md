# cheats

Short examples for a command, cached offline.

## Synopsis

```
cheats [options] command [topic] [-- curl options]
cheats -l
```

## Description

`cheats` prints a page of short, ready-to-copy examples for a command. It fetches the page from cheat.sh, a free
service that gathers community cheat sheets, and keeps a copy on disk. The next time you ask for the same page,
`cheats` prints the copy and never touches the network, so the pages you have looked at once work on a train or in
a data centre with no internet.

```
# Create a gzip archive of a folder
tar -czvf archive.tar.gz folder/

# List what is inside an archive
tar -tvf archive.tar.gz
```

A man page tells you every option. A cheat page shows the five things people do with a command. The two go well
together.

A second word is a topic. `cheats kubectl logs` asks cheat.sh for the `logs` page under `kubectl`. A topic of
several words, such as `cheats git "undo commit"`, asks cheat.sh to search its answers for those words.

### How it decides

1. When a copy is on disk and is less than 30 days old, `cheats` prints it and stops. The line
   `cheats: tar, cached 3d ago` on stderr tells you it came from the disk.
2. Otherwise it fetches the page from `https://cheat.sh/<command>/<topic>?T`. The `?T` asks for plain text with no
   colour codes.
3. When cheat.sh has no page, or cannot be reached, it tries the tldr pages on GitHub, first the `common` set, then
   `linux`, then `osx`. For a topic it looks for the page `<command>-<topic>.md`, the way tldr names subcommands.
   A topic of several words skips tldr, which has no search.
   `cheats` turns a tldr page into the same shape as a cheat.sh page, with `#` comment lines above each command.
4. It saves the page in `~/.cache/toolbelt/cheats` and prints it.
5. When both are unreachable and an old copy exists, it prints the old copy with a warning. An old page beats no
   page.

`-u` skips step 1 and always fetches. `-o` stops after step 1 and never uses the network.

### Where the pages live

Pages go in `$XDG_CACHE_HOME/toolbelt/cheats`, which is `~/.cache/toolbelt/cheats` on most systems. Each page is
one plain text file, named after the command and the topic joined with a hyphen: `tar`, `kubectl-logs`,
`git-undo-commit`. You can read, `grep` or delete them as you like. Deleting the folder loses nothing you cannot
fetch again.

### What it checks

A command name must be letters, digits, dots, plus signs, underscores and hyphens, and start with a letter or
digit. A topic may also have spaces. Anything else, such as a slash, exits 2, so the name can never reach outside
the cache folder or change the URL.

## Options

| Option | What it does |
|---|---|
| `-u`, `--update` | Fetch the page again, even when the copy on disk is fresh. |
| `-o`, `--offline` | Use the copy on disk only, and never touch the network. An old copy is fine. No copy exits 1. |
| `-l`, `--list` | List the cached pages, one per line, with their age. |
| `-q`, `--quiet` | Print only the page. |
| `-v`, `--verbose` | Print the `curl` line before each fetch, where the page was saved, and curl's own errors. |
| `-h`, `--help` | Show the help. |

## Pass-through

Options after `--` go to `curl`, on every fetch. Use this for a proxy, or for a longer timeout on a slow link:

```console
$ cheats tar -- --proxy http://proxy.example.com:3128
$ cheats kubectl -- --max-time 60
```

`curl` also reads `https_proxy` from the environment, so a proxy you set for your shell works with no options.

## Needs

`curl` to fetch a page. Pages already on disk need nothing.

| Distro | Package |
|---|---|
| Debian, Ubuntu, Fedora, Arch, openSUSE, Alpine | `curl` |

`cheats` connects to `cheat.sh` and `raw.githubusercontent.com` on port 443. A firewall that blocks them leaves you
with the cache only.

## Examples

### A first look at tar

```console
$ cheats tar
# Create a gzip archive of a folder
tar -czvf archive.tar.gz folder/

# List what is inside an archive
tar -tvf archive.tar.gz
```

### The same page later, from the disk

```console
$ cheats tar
# Create a gzip archive of a folder
tar -czvf archive.tar.gz folder/

# List what is inside an archive
tar -tvf archive.tar.gz
cheats: tar, cached 3d ago
```

### A topic, with the fetch shown

```console
$ cheats -v kubectl logs
+ curl -fsSL --max-time 15 -o /tmp/.cheats-5y4ytW/page 'https://cheat.sh/kubectl/logs?T'
# Logs of the previous container, after a crash
kubectl logs -p pod-name
# Follow the logs of every pod with a label
kubectl logs -f -l app=api --all-containers
cheats: saved /home/me/.cache/toolbelt/cheats/kubectl-logs, from cheat.sh
```

### What is cached

```console
$ cheats -l
kubectl-logs                 2h ago
tar                          3d ago
```

### No network and no copy

```console
$ cheats rsync
cheats: no cached page for rsync, and cheat.sh is unreachable
cheats: cached pages are listed by cheats -l
```

### No network, but an old copy

```console
$ cheats tar
# Create a gzip archive of a folder
tar -czvf archive.tar.gz folder/
...
cheats: could not refresh tar, showing the copy from 40d ago
```

### Pages for later

Fetch the pages you expect to need while you still have a network:

```console
$ for c in tar rsync ss journalctl kubectl; do cheats -q -u "$c" >/dev/null; done
```

## Troubleshooting

`cheats: no cached page for rsync, and cheat.sh is unreachable`
: Neither cheat.sh nor GitHub answered, and there is no copy on disk. Check the network with `netcheck`, or pass a
  proxy after `--`. `-v` shows curl's own error.

`cheats: no page for foo on cheat.sh or tldr`
: Both answered, and neither has a page with that name. Check the spelling, or try the command without the topic.

`cheats: needs curl. Install it with: sudo apt install curl`
: The page is not on disk, and `curl` is missing to fetch it.

A page shows old options
: Pages come from the community and some lag behind new releases. `cheats -u` fetches the newest copy.

The page for a topic is a long answer instead of examples
: For a topic that is not a known page, cheat.sh searches its answers and returns the best match. Try the command
  on its own first.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It printed a page, or the list. |
| 1 | No page, from the disk or the network. |
| 2 | Bad usage, such as no command, or `-u` with `-o`. |
| 3 | `curl` is missing and the page is not on disk. |

## See also

`man(1)`, `curl(1)`, https://cheat.sh, https://tldr.sh
