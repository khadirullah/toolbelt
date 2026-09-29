# git-recent

List local branches by their last commit, newest first.

## Synopsis

```
git recent [-n count] [options]
git-recent [-n count] [options]
```

## Description

`git branch` lists branches in alphabetical order, which is rarely the order you need. After a week of
switching between tickets, the question is "what was I working on on Tuesday?", and the answer is the branch with
the newest commit.

`git recent` lists your local branches sorted by the date of their last commit, newest first, 10 by default. Each
line has the branch name, how long ago its last commit was, and that commit's subject. A `*` marks the branch you
are on, as in `git branch`.

It only reads. It never switches branches or changes anything.

The dates are commit dates, the time a commit was last written. A rebase or `git commit --amend` writes the
commit again, so a branch you rebased this morning shows as this morning even when the work is older.

It is a script named `git-recent` in toolbelt's `bin` folder. Git runs any program named `git-NAME` on your PATH
as `git NAME`.

## Options

| Option | What it does |
|---|---|
| `-n`, `--count N` | Show N branches. 10 by default. |
| `-a`, `--all` | Show every local branch. |
| `-q`, `--quiet` | Print only the branch names, one per line, for scripts. |
| `-v`, `--verbose` | Show the git command before it runs. |
| `-h`, `--help` | Show the help. |

`-n3` and `--count=3` work the same as `-n 3`.

## Output

```
  main              2 hours ago   tfcheck: add trivy section
* feat/ctx-warn     5 hours ago   ctx: flag production contexts
```

- The first column is `*` for the current branch and a space for the others.
- The columns line up to the longest name and the longest age in the list.
- Ages come from git's own relative dates, such as `26 hours ago`, `3 days ago` or `5 weeks ago`.
- A subject longer than 50 characters is cut to 47 and ends in `...`, so a line fits in 80 columns.

## Help and the man page

`git recent -h` and `git-recent --help` print the help. `git recent --help` makes git open the man page
`git-recent(1)`, which toolbelt installs from this document.

## Pass-through

None. `git recent` runs one `git for-each-ref` command, and `-v` prints it.

## Needs

git 2.30 or newer, from the `git` package on every distro.

## Examples

### What was I working on

```console
$ git recent -n 3
  main              2 hours ago   tfcheck: add trivy section
* feat/ctx-warn     5 hours ago   ctx: flag production contexts
  fix/kwhy-pending  26 hours ago  kwhy: hint for Pending pods
```

### Every branch, oldest at the bottom

```console
$ git recent
  main                 2 hours ago   tfcheck: add trivy section
* feat/ctx-warn        5 hours ago   ctx: flag production contexts
  fix/kwhy-pending     26 hours ago  kwhy: hint for Pending pods
  fix/probe-timeout    3 days ago    kwhy: longer probe timeout
  feat/kres-table      2 weeks ago   kres: table output
  docs/readme-install  5 weeks ago   docs: install steps
```

The three at the bottom are merged already. `git prune-merged` deletes them.

### Names only, for a script

```console
$ git recent -q -n 1
main
$ git switch "$(git recent -q -n 1)"
```

### Pick a branch with fzf

```console
$ git switch "$(git recent -q -a | fzf)"
```

`fzf` shows the list and prints the one you pick. It is a separate tool.

### See the git command

```console
$ git recent -v -n 2
+ git for-each-ref --sort=-committerdate --count=2 '--format=%(HEAD)%09%(refname:short)%09%(committerdate:relative)%09%(subject)' refs/heads/
  main           2 hours ago  tfcheck: add trivy section
* feat/ctx-warn  5 hours ago  ctx: flag production contexts
```

## Troubleshooting

`git-recent: not inside a git repository`
: Change into a folder of the repository first.

`no branches yet, make a first commit`
: A new repository has no branches until its first commit.

A branch I know I used today is far down the list
: `git recent` sorts by the last commit, not by the last checkout. `git reflog` shows every checkout, such as
  `git reflog | grep 'checkout:' | head`.

The ages look wrong after a rebase
: A rebase writes every commit again with a new commit date. That is the date `git recent` shows.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, even when there are no branches yet. |
| 1 | Not a repository, or git failed. |
| 2 | Bad usage, such as `-n 0`. |
| 3 | git is not installed. |

## See also

`git-prune-merged`, `git-sync`, `git-branch(1)`, `git-for-each-ref(1)`
