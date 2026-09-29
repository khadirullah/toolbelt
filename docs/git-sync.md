# git-sync

Fetch and rebase the current branch onto its upstream.

## Synopsis

```
git sync [options]
git-sync [options]
```

## Description

Bringing a branch up to date takes four commands when you have uncommitted work. `git stash -u`,
`git fetch --prune`, `git rebase`, then `git stash pop`. Miss the stash and the rebase refuses to start. Miss
`--prune` and branches your team deleted months ago stay in `git branch -r`.

`git sync` runs all four in order and says what each one did. When the rebase hits a conflict it runs
`git rebase --abort`, puts your stashed work back, and tells you. Your branch is then exactly as it was before,
and you can rebase by hand when you have time for the conflict.

The upstream is the branch `git status` compares against, set by `git push -u` or `git branch -u`. A feature
branch can track its own remote branch, such as `origin/feat/ctx-warn`, or `origin/main` so that every sync
replays it on top of the newest `main`.

What happens after the fetch depends on where the two branches stand.

| Your branch | The upstream | What `git sync` does |
|---|---|---|
| no new commits | has new commits | Fast-forwards to the upstream. |
| has new commits | has new commits | Rebases your commits on top of the upstream. |
| has new commits | nothing new | Nothing. It says how many commits you have to push. |
| no new commits | nothing new | Nothing. It says the branch is up to date. |

It never pushes. After a sync that rebased, a branch you pushed before needs `git push --force-with-lease`.

It is a script named `git-sync` in toolbelt's `bin` folder. Git runs any program named `git-NAME` on your PATH as
`git NAME`.

## Options

| Option | What it does |
|---|---|
| `-q`, `--quiet` | Only the result line, and errors. |
| `-v`, `--verbose` | Show each step and each git command before it runs. |
| `-h`, `--help` | Show the help. |

`git sync` takes no arguments. It always syncs the branch you are on with its upstream.

## The steps

1. `git stash push --include-untracked`, when there are uncommitted changes or new files. Ignored files stay
   where they are.
2. `git fetch --prune REMOTE`, for the upstream's remote only. `--prune` removes remote-tracking branches such as
   `origin/fix/old-probe` whose branch is gone from the server.
3. `git merge --ff-only` or `git rebase`, as the table above says.
4. `git stash pop`, when step 1 stashed something.

An upstream on the same repository, set with `git branch -u main`, skips the fetch.

## Help and the man page

`git sync -h` and `git-sync --help` print the help. `git sync --help` makes git open the man page `git-sync(1)`,
which toolbelt installs from this document.

## Safety checks

- A rebase that stops on a conflict is aborted at once. The branch, the files and the stash end as they were
  before `git sync` started, and it exits 1.
- A stash that no longer applies cleanly after the rebase stays in the stash list. `git sync` says so and exits 1.
  Nothing is lost, see `git stash list`.
- A merge, rebase, cherry-pick or revert that is already half done makes it refuse with exit 4.
- A detached HEAD, or a branch with no upstream, stops it with exit 1 and the command to fix that.
- When the upstream branch itself was deleted on the server, the fetch prunes it. `git sync` stops with exit 1
  and tells you to pick another upstream.
- It never pushes, never deletes a local branch, and never drops a stash it could not apply.

## Pass-through

None. `git sync` runs a fixed set of git commands, and `-v` prints each one.

## Needs

git 2.30 or newer, from the `git` package on every distro.

## Examples

### A normal morning

```console
$ git sync
stashed 1 changed file
fetched origin, 3 new commits on main
rebased feat/ctx-warn onto origin/main, 2 commits replayed
restored the stashed file
removed 2 remote branches that are gone from origin
```

`feat/ctx-warn` tracks `origin/main` here, so its two commits now sit on top of the three new ones.

### Nothing new

```console
$ git sync
stashed 1 changed file
fetched origin, nothing new on main
feat/ctx-warn already has everything from origin/main, 2 commits to push
restored the stashed file
```

### On main with no local commits

```console
$ git switch main
$ git sync
fetched origin, nothing new on main
fast-forwarded main to origin/main
```

### A conflict

```console
$ git sync
fetched origin, 1 new commit on main
git-sync: rebasing feat/ctx-warn onto origin/main hit a conflict. The rebase is undone and feat/ctx-warn is as it was
rebase by hand with: git rebase origin/main
$ echo $?
1
```

Run `git rebase origin/main` when you are ready, fix each file it names, `git add` it and run
`git rebase --continue`.

### A new branch

```console
$ git switch -c feat/new
$ git sync
git-sync: feat/new has no upstream branch. Push it with: git push -u origin feat/new
```

### See every git command

```console
$ git sync -v
+ git stash push -q --include-untracked -m 'git-sync on feat/ctx-warn'
stashed 1 changed file
+ git fetch -q --prune origin
git-sync: origin had 2 remote branches before the fetch
fetched origin, nothing new on main
feat/ctx-warn already has everything from origin/main, 2 commits to push
+ git stash pop -q
restored the stashed file
```

### Sync, then push

```console
$ git sync && git push --force-with-lease
```

The `&&` stops the push when the sync failed.

## Troubleshooting

`git-sync: NAME has no upstream branch. Push it with: git push -u origin NAME`
: The branch has never been pushed, or was created without `--track`. Push it with `-u`, or point it at an
  existing branch with `git branch -u origin/main`.

`git-sync: rebasing NAME onto origin/main hit a conflict. The rebase is undone and NAME is as it was`
: The new commits on the upstream and yours change the same lines. Rebase by hand, or merge with
  `git merge origin/main` if you prefer a merge commit.

`git-sync: your stashed changes clash with the new commits. They are still in the stash, see git stash show -p`
: The rebase worked, but your uncommitted changes touch lines the new commits changed. `git status` shows the
  files with conflict markers. Fix them, then `git stash drop` removes the saved copy.

`git-sync: git fetch origin failed, nothing was rebased`
: The remote was not reachable, or it asked for a password with no terminal. The message from git above says
  which. Your stashed work is back in place.

`git-sync: origin/NAME is gone from origin. Point BRANCH at another with: git branch -u REMOTE/BRANCH`
: The branch your branch tracks was deleted on the server, often after its pull request was merged. Switch to
  `main`, or track another branch with `git branch -u origin/main`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The branch is up to date with its upstream. |
| 1 | Not a repository, no upstream, a detached HEAD, a failed fetch, a rebase conflict, or a stash that did not apply. |
| 2 | Bad usage, such as an argument. |
| 3 | git is not installed. |
| 4 | Refused, because a merge, rebase, cherry-pick or revert is in progress. |

## See also

`git-prune-merged`, `git-undo`, `git-wip`, `git-fetch(1)`, `git-rebase(1)`, `git-stash(1)`
