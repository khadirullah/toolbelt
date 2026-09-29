# Contributing

Every command in toolbelt follows the same rules. Someone who has used one command should never be surprised by
another. This file is the contract. Read it before you add or change a command.

## Layout

```
bin/<command>          the command, one Bash file, executable
lib/common.sh          shared helpers, sourced by every command
lib/kube.sh            kubectl helpers, sourced by the k* commands
lib/words              the EFF word list for genpass -w
lib/pkgmap             command to package name, per package manager
lib/commands           every command by group, in help order
shell/functions.sh     mkcd and up, which must run inside your shell
docs/<command>.md      the full manual page, also the source for man/ and site/
man/man1/<command>.1   built from docs by `make man`, committed
completions/           bash and zsh completion
tests/<command>.bats   tests, with fixtures of a few KB made on the fly
tools/                 build and check scripts for the repo, never installed
site/                  the website, built from docs by `make site`
```

## A command, start to end

```bash
#!/usr/bin/env bash
# unpack: unpack any archive, from a file or a URL.
set -uo pipefail
TB_CMD=unpack
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

usage() {
    cat <<'EOF'
usage: unpack [options] archive ... [-- tool options]

Unpack any archive, from a file or a URL.

Options:
  -H, --here          put the files in the current folder
  ...
  -q, --quiet         only the result line
  -v, --verbose       every step, and each real command before it runs
  -h, --help          this help

Examples:
  unpack backup.tar.gz
  unpack -v photos.7z -- -mmt=4

Needs: tar, plus the tool for each format. See man unpack.
Exit: 0 ok, 1 failed, 2 bad usage, 3 missing tool, 4 refused, 5 answered no.
EOF
}

tb_expand "o" "$@"          # letters whose short option takes a value
set -- "${TB_EXPANDED[@]}"
files=()
while (( $# )); do
    case $1 in
        -H|--here) mode=here ;;
        -o|--out)  tb_optarg "$@"; outdir=$2; shift ;;
        --)        shift; TB_PASS=("$@"); break ;;
        -*)        tb_common_opt "$1" || tb_unknown "$1" ;;
        *)         files+=("$1") ;;
    esac
    shift
done
```

- `set -uo pipefail`, never `set -e`. Check the result of each step that can fail.
- `TB_CMD` is the command name, used in every message.
- Put all logic in functions. Keep the top level to option parsing and one call to `main`.
- Target Bash 4.4, the oldest in the CI images (openSUSE Leap 15). An empty `"${arr[@]}"` is safe under `set -u`
  from 4.4 on, so no workarounds for it. No `${var@Q}` or `mapfile -d` without a fallback, and no `wait -p` (5.1).
- BusyBox has no `numfmt`, `du -b`, `date +%N`, `find -printf`, `sort -h` or `stat --printf`. Use the helpers in
  `lib/common.sh` or give a fallback.

## Help

`-h` and `--help` always print help to stdout and exit 0. The layout is fixed:

1. `usage:` line, and more usage lines indented under it when the command has several forms.
2. A blank line.
3. One line on what the command does, starting with a capital and ending with a full stop. `toolbelt help` shows
   this line, so keep it under 60 characters.
4. Option sections. Use `Options:` for a short list, or several titled sections such as `Where it goes:` for a
   long one. Each option is a line: two spaces, the flags, spaces to column 23, then lower-case text with no
   full stop.
5. `Pass-through:` when the command wraps a tool, saying which tool gets the options after `--`.
6. `Examples:` with 2 to 6 lines.
7. `Needs:` and `Exit:` lines.

Help fits in 80 columns and, for most commands, one screen. The long form lives in the docs page.

## Output

- **stdout** carries the result, the thing a script would capture. Tables, the summary line, a password, a URL.
- **stderr** carries everything for a person. Progress, steps, questions, warnings and errors.
- Errors are `command: what happened`, with no full stop, from `tb_err` or `tb_die`. Say what to do next when
  there is a clear next step.
- `-q` shows only the result line and errors. `-v` shows every step with `tb_say`, and every real command with
  `tb_show` or `tb_run`, as `+ tar -xf - -C out`. A reader must be able to copy that line and run it.
- Colour only through `C_RED` and the other variables from `lib/common.sh`. They are empty when output is not a
  terminal or when `NO_COLOR` is set. Never put colour in a line a script would parse.
- Progress bars only when `tb_progress` is true.
- Sizes from `tb_human`, times from `tb_elapsed`, ages from `tb_age`, counts from `tb_plural`. Read sizes the user
  types, such as `100K` or `1.5G`, with `tb_parse_size`.
- A status line that rewrites itself uses `tb_line` and `tb_line_end`.

## Exit codes

| Code | Meaning | Helper |
|---|---|---|
| 0 | It worked | |
| 1 | It failed, the message says why | `tb_die 1` |
| 2 | Bad usage | `tb_usage_error` |
| 3 | A tool is missing, the message has the install line | `tb_need`, `tb_need_any` |
| 4 | A safety check refused | `tb_die "$E_SAFE"` |
| 5 | The user answered no to the change they asked for | `tb_confirm` |

A command may give a code its own meaning, such as `certcheck` exiting 1 when a certificate expires soon. Its docs
page says so under Exit status.

## Missing tools

- Call `tb_need tool` before the first use. It prints `unpack: needs 7z. Install it with: sudo apt install 7zip`
  for the machine's package manager and exits 3.
- `tb_need_any var 7z 7zz 7za` picks the first that exists.
- Optional tools that only make things nicer get one line from `tb_hint`, never an exit.
- Every tool a command uses has a row in `lib/pkgmap`. CI checks each name exists in each distro's repos.

## Questions, deletes and the trash

- Nothing destructive without asking. `tb_confirm "Delete 12 pods?"` asks. A no exits 5, and with no terminal it
  refuses with exit 4 unless `-y` was given.
- Deletes go to the trash with `tb_trash`, never `rm`, unless the file is a temp file the command made itself.
- `unpack` and `squash` call `tb_offer_delete` after the result is checked. It asks only in a terminal, `--rm` sets
  `TB_RM=1` to skip the question, and `-k` sets `TB_KEEP=1` to never ask. A no here is not an error. The job
  worked, so the exit code stays 0.
- Never overwrite a file the user owns. Use `tb_free_name` to find `name-1.ext`.

## State and temp files

- Temp folders come from `tb_tmpdir var [parent]`, which removes them on exit, including Ctrl+C.
- Records live in `tb_state_dir`, caches in `tb_cache_dir`, and settings in `tb_config_dir`. All follow the XDG
  variables.

## Memory

Stream data through pipes. Never read a whole file into a variable. Check `tb_mem_avail_kb` before work that
needs a lot of RAM, such as xz at level 9 with threads, and `tb_free_kb` before writing a lot to disk.

## Docs page

`docs/<command>.md` is the manual. `make man` turns it into the man page and `make site` into the website, so
keep to this layout exactly.

````markdown
# unpack

Unpack any archive, from a file or a URL.

## Synopsis

```
unpack [options] archive ... [-- tool options]
```

## Description

Paragraphs in plain words. What it does, how it decides, what it never does.

## Options

| Option | What it does |
|---|---|
| `-H`, `--here` | Put the files in the current folder. |

(More `##` sections for the topics a command needs, such as Formats, Multi-part sets or Safety checks.)

## Pass-through

Which tool gets the options after `--`, per case, with an example.

## Needs

What must be installed, what is optional and what it adds, with the package names.

## Examples

### Unpack a backup

```console
$ unpack backup.tar.gz
backup.tar.gz -> backup/ (31MB, 201 files, 3.1s)
```

## Exit status

The shared codes, and any meaning this command adds.

## See also

`squash`, `archdiff`, `tar(1)`
````

- The line after the title is the same one-liner as the help text.
- Every example output is real, copied from a run, with names and sizes changed only to be readable.
- Headings are sentence case. No em dashes or en dashes, use commas or full stops. Straight quotes. No emoji.
- Describe what exists. No plans, versions to come or status words.

## Tests

- `tests/<command>.bats`, loading `helpers`, calling `tb_setup` in `setup()`.
- Build fixtures in the test with `printf`, `seq` or `head -c 4K /dev/urandom`. Nothing over a few hundred KB.
- Test help, bad usage (exit 2), the missing tool message (`tb_without`), the normal case, and each refusal.
- Replace network, systemd, kubectl and other outside tools with `tb_stub`, so tests run in a container with no
  network and no cluster.
- Answer questions with `tb_tty` and `echo y |`.
- `make test` runs everything, and `make test T=unpack` runs one file.

## Commits

One commit per command, or per fix. The subject says what changed for a user, such as
`unpack: ask before deleting the archive`.
