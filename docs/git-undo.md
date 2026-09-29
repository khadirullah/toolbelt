# git-undo

Take back the last commit and keep its changes.

## Synopsis

```
git undo [--hard] [options]
git-undo [--hard] [options]
```

## Description

`git undo` moves your branch back one commit. The files stay as they are and the changes from that commit sit in
the staging area, so a `git commit` puts them back as a new commit. Use it when you committed too early, wrote
the wrong message, or committed to the wrong branch.

`git undo --hard` drops the commit and its changes. It shows the files the commit touched.

Both forms say which commit they will take back and what happens to its changes, then ask. The default answer is
no. `-y` skips the question.

Both forms print the commit they took away, with the command that brings it back. Git also keeps the old commit
in the reflog for 30 days or more, so `git reflog` finds it later too.

`git undo` never rewrites a commit that someone else may already have. It refuses when the commit is already on
the branch's upstream, or on any remote branch you have fetched. For those, `git revert` makes a new commit that
reverses the old one, which is safe to push.

Under the hood `git undo` is `git reset --soft HEAD^`, and `git undo --hard` is `git reset --keep HEAD^`. It is a
script named `git-undo` in toolbelt's `bin` folder. Git runs any program named `git-NAME` on your PATH as
`git NAME`, so it works like a built-in subcommand.

## Options

| Option | What it does |
|---|---|
| `--hard` | Drop the commit's changes too. |
| `-y`, `--yes` | Do not ask. |
| `-q`, `--quiet` | Only the result line. |
| `-v`, `--verbose` | Show each step and each git command before it runs. |
| `-h`, `--help` | Show the help. |

`git undo` takes no other arguments. It always undoes the last commit. Run it twice to undo two.

## Help and the man page

`git undo -h` and `git-undo --help` print the help. `git undo --help` is different, because git turns it into
`git help undo` and opens the man page `git-undo(1)`. toolbelt installs that page, built from this document. When
you run toolbelt from a clone without installing it, the man page is not on the MANPATH and git says
`No manual entry for git-undo`. Use `git undo -h` then.

## Safety checks

- The commit is on the upstream branch, or on any remote-tracking branch such as `origin/main`. `git undo`
  refuses with exit 4 and suggests `git revert`. Run `git fetch` first when you are not sure your remote-tracking
  branches are current.
- A merge, rebase, cherry-pick or revert is half done. `git undo` refuses with exit 4. Finish it or abort it
  first, such as `git rebase --abort`.
- The first commit of a repository has no parent to go back to. `git undo` stops with exit 1.
- It asks before it changes anything, with or without `--hard`. With no terminal to ask in, as in a script, it
  refuses with exit 4 unless you pass `-y`. A no exits 5.
- `--hard` uses `git reset --keep`, not `git reset --hard`. Uncommitted changes in other files survive. When you
  have uncommitted changes in a file the commit also touched, git stops and nothing is dropped.
- A merge commit goes back to its first parent, the branch you merged into. `git undo` says so.

## Pass-through

None. `git undo` runs one fixed `git reset` command, and `-v` prints it.

## Needs

git 2.30 or newer, from the `git` package on every distro.

## Examples

### Undo the last commit

```console
$ git undo
This takes back commit cc9caf3 "ctx: add a --prod option". Its changes stay staged, nothing is lost.
Undo cc9caf3? [y/N] y
undid cc9caf3 "ctx: add a --prod option"
the changes are staged, nothing is lost
to redo the commit, run git reset --soft cc9caf3
```

`git status` now shows `ctx.sh` as staged. Edit it more and commit again, or switch to another branch and commit
it there.

### Answer no

```console
$ git undo
This takes back commit cc9caf3 "ctx: add a --prod option". Its changes stay staged, nothing is lost.
Undo cc9caf3? [y/N] n
Nothing changed.
$ echo $?
5
```

### Without the question

```console
$ git undo -y
This takes back commit cc9caf3 "ctx: add a --prod option". Its changes stay staged, nothing is lost.
undid cc9caf3 "ctx: add a --prod option"
the changes are staged, nothing is lost
to redo the commit, run git reset --soft cc9caf3
```

### In a script

```console
$ git undo </dev/null
This takes back commit cc9caf3 "ctx: add a --prod option". Its changes stay staged, nothing is lost.
git-undo: not asking without a terminal, pass --yes to go ahead
$ echo $?
4
```

### Drop a commit and its changes

```console
$ git undo --hard
This drops commit cc9caf3 "ctx: add a --prod option" and its changes:
 ctx.sh | 1 +
 1 file changed, 1 insertion(+)
Drop cc9caf3 and its changes? [y/N] y
dropped cc9caf3 "ctx: add a --prod option"
to bring it back, run git reset --keep cc9caf3
```

### A commit that is already pushed

```console
$ git undo
git-undo: refused, cc9caf3 is already on origin/main
use git revert cc9caf3 to undo a pushed commit
$ echo $?
4
```

### See the git commands

```console
$ git undo -v -y
git-undo: last commit is cc9caf3 "ctx: add a --prod option"
+ git for-each-ref --contains HEAD '--format=%(refname:short)' refs/remotes
This takes back commit cc9caf3 "ctx: add a --prod option". Its changes stay staged, nothing is lost.
+ git reset -q --soft deb177294adbfc06dcf105a28db1470ea232e66c
undid cc9caf3 "ctx: add a --prod option"
the changes are staged, nothing is lost
to redo the commit, run git reset --soft cc9caf3
git-undo: was cc9caf3789350cf0e13eb6de2f605836f61b1988
```

### Take back a wip commit

```console
$ git wip
saved 1 changed and 1 new files as 085bd00 "wip" on main
git undo brings them back
$ git undo -q -y
undid 085bd00 "wip"
```

## Troubleshooting

`git-undo: refused, 3f2a9c1 is already on origin/main`
: Someone may have pulled that commit. Rewriting it forces them to repair their clone. Run `git revert 3f2a9c1`
  and push the new commit. When the remote branch is yours alone, such as a feature branch nobody else uses, you
  can still run `git reset --soft HEAD^` yourself and push with `git push --force-with-lease`.

`git-undo: refused, a rebase is in progress. Finish it or abort it first`
: Run `git status` to see where the rebase stopped, then `git rebase --continue` or `git rebase --abort`.

`git-undo: git reset stopped, a file you changed is also in 3f2a9c1. Nothing was dropped`
: `--hard` would have lost your uncommitted edits. Commit them, stash them with `git stash`, or run `git undo`
  without `--hard`.

`git-undo: 3f2a9c1 is the first commit, there is nothing before it to go back to`
: To start the history over, run `git update-ref -d HEAD`. Your files stay staged.

`No manual entry for git-undo`
: You ran `git undo --help` without an installed man page. Use `git undo -h`, or run `make man` and install
  toolbelt.

`git-undo: not asking without a terminal, pass --yes to go ahead`
: `git undo` ran in a script, a pipe or a cron job. Add `-y` when the script really should undo the commit.

I undid the wrong commit
: Run the command `git undo` printed, such as `git reset --soft cc9caf3`. When that output is gone,
  `git reflog` lists every commit your branch pointed at.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The commit is undone. |
| 1 | Not a repository, no commits, the first commit, or git failed. |
| 2 | Bad usage, such as an argument. |
| 3 | git is not installed. |
| 4 | Refused. The commit is already pushed, an operation is in progress, or there was no terminal to ask in. |
| 5 | You answered no. |

## See also

`git-wip`, `git-sync`, `git-reset(1)`, `git-revert(1)`, `git-reflog(1)`
