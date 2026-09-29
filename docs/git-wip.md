# git-wip

Save every change as a commit named wip.

## Synopsis

```
git wip [options]
git-wip [options]
```

## Description

`git wip` puts everything you have not committed into one commit named `wip`, short for work in progress. That
covers changed files, deleted files and new files git has never seen. Files that `.gitignore` names stay out.

Use it when you have to leave a branch in a hurry, to review a pull request or fix something on `main`.
`git stash` does a similar job, but a stash is easy to forget, it belongs to no branch, and it skips new files unless
you remember `-u`. A wip commit stays on the branch you were on, and `git log` shows it the next time you look.

When you come back, `git undo` asks, then takes the commit back and leaves all its changes staged. You carry on as if you
never left.

`git wip` works from any folder inside the repository. It always saves the whole working tree, not only the
folder you are in.

It commits with `--no-verify`, so pre-commit and commit-msg hooks do not run. A linter or test hook would
otherwise block exactly the half-done work `git wip` is for. The hooks run as usual when you make the real commit.

It is a script named `git-wip` in toolbelt's `bin` folder. Git runs any program named `git-NAME` on your PATH as
`git NAME`.

## Options

| Option | What it does |
|---|---|
| `-q`, `--quiet` | Only the result line. |
| `-v`, `--verbose` | Show the count and each git command before it runs. |
| `-h`, `--help` | Show the help. |

`git wip` takes no arguments. The commit is always named `wip`, so you can spot it in `git log` and scripts can
look for it.

## How it counts files

The result line counts files from `git status --porcelain --untracked-files=all`.

- A file git knows that you changed, deleted or renamed counts as changed.
- A file git has never seen, or one you added with `git add` but never committed, counts as new.
- Every file inside a new folder counts on its own, so a new folder with 3 files adds 3.

## Help and the man page

`git wip -h` and `git-wip --help` print the help. `git wip --help` makes git open the man page `git-wip(1)`, which
toolbelt installs from this document. Without an installed man page git says `No manual entry for git-wip`.

## Safety checks

- A clean working tree has nothing to save. `git wip` exits 1 and makes no empty commit.
- A merge, rebase, cherry-pick or revert that is half done makes `git wip` refuse with exit 4. A wip commit in
  the middle of a rebase would end up inside the rebased history.
- A bare repository has no files to save. `git wip` exits 1.
- It never pushes. The wip commit stays on your machine until you push it yourself.

## Pass-through

None. `git wip` runs `git add -A` and `git commit -q --no-verify -m wip`, and `-v` prints both.

## Needs

git 2.30 or newer, from the `git` package on every distro.

## Examples

### Save and leave

```console
$ git wip
saved 1 changed and 2 new files as 378f844 "wip" on feat/ctx-warn
git undo brings them back
$ git switch main
```

### Come back

```console
$ git switch feat/ctx-warn
Switched to branch 'feat/ctx-warn'
Your branch is ahead of 'origin/feat/ctx-warn' by 2 commits.
  (use "git push" to publish your local commits)
$ git undo -q -y
undid 378f844 "wip"
$ git status --short
M  ctx.sh
A  lib/prod.sh
A  notes.md
```

The two new files are staged, so they are safe from `git clean` from now on.

### See the steps

```console
$ git wip -v
+ git status --porcelain --untracked-files=all
git-wip: 1 changed and 2 new files to save
+ git add -A
+ git commit -q --no-verify -m wip
saved 1 changed and 2 new files as 378f844 "wip" on feat/ctx-warn
git undo brings them back
```

### Nothing to save

```console
$ git wip
git-wip: nothing to save, the working tree is clean
$ echo $?
1
```

### On a detached HEAD

```console
$ git wip
saved 1 changed file as e8c02a8 "wip" on a detached HEAD
git undo brings them back
```

A commit on a detached HEAD belongs to no branch. Run `git switch -c NAME` before you leave, or note the hash.

### Save before switching, in one line

```console
$ git wip && git switch main
saved 1 changed file as fc45a11 "wip" on feat/ctx-warn
git undo brings them back
Switched to branch 'main'
Your branch is up to date with 'origin/main'.
```

The `&&` means the switch only happens when the save worked.

## Troubleshooting

`git-wip: nothing to save, the working tree is clean`
: Everything is committed already. Check with `git status`. Files that `.gitignore` names never count.

`git-wip: refused, a rebase is in progress. Finish it or abort it first`
: Run `git status` to see where it stopped, then `git rebase --continue` or `git rebase --abort`.

`git-wip: git commit failed. The changes are staged, see git status`
: Most often git has no name or email to commit with. `git whoami` shows what is set. Commit signing that needs a
  passphrase can fail here too when no agent is running.

A wip commit ended up on the remote
: `git undo` refuses a pushed commit. Make the real commit on top instead, or squash the two with
  `git rebase -i` before the branch is merged.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The changes are saved as a wip commit. |
| 1 | Nothing to save, not a repository, or git failed. |
| 2 | Bad usage, such as a message after `git wip`. |
| 3 | git is not installed. |
| 4 | Refused, because a merge, rebase, cherry-pick or revert is in progress. |

## See also

`git-undo`, `git-sync`, `git-stash(1)`, `git-commit(1)`
