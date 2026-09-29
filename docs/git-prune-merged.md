# git-prune-merged

Delete local branches already merged into main.

## Synopsis

```
git prune-merged [--into branch] [options]
git-prune-merged [--into branch] [options]
```

## Description

Every feature branch you merged stays on your machine until you delete it. After a few months `git branch` lists
fifty of them, and the few that still matter are hard to find.

`git prune-merged` finds the local branches whose last commit is already part of `main`, lists them, and asks
before it deletes them. After the delete it prints each branch with its commit hash, so you can bring any of them
back with `git branch NAME SHA`.

The base is `main`, or `master` when there is no `main`. `--into` picks another, such as `develop`, or a remote
branch such as `origin/main`.

It only touches local branches. Remote branches, tags and commits stay as they are. A deleted branch's commits
stay in the repository too, which is why the printed hash brings the branch back.

It is a script named `git-prune-merged` in toolbelt's `bin` folder. Git runs any program named `git-NAME` on your
PATH as `git NAME`.

## Options

| Option | What it does |
|---|---|
| `--into BRANCH` | The branch the others were merged into. `main`, else `master`, by default. |
| `-n`, `--dry-run` | List the branches and delete nothing. |
| `-y`, `--yes` | Do not ask. |
| `-q`, `--quiet` | Only the result lines. It still asks, unless you pass `-y`. |
| `-v`, `--verbose` | Show each step and each git command before it runs. |
| `-h`, `--help` | Show the help. |

## How it decides

A branch counts as merged when its last commit is reachable from the base, which is what
`git branch --merged main` shows. `git prune-merged` reads that list with `git for-each-ref --merged`.

It keeps these branches even when they are merged:

- the base itself, and `main` and `master`
- the branch you are on
- a branch checked out in another worktree, since git will not delete it
- with `--into origin/main`, the local twin `main`

### Squash and rebase merges

GitHub and GitLab can merge a pull request as a squash or a rebase. Both write new commits on `main`, so the
branch's own commits never become part of `main`, and `git prune-merged` does not see the branch as merged. Delete
those by hand with `git branch -D NAME` once you are sure the pull request went in.

### Your local main may be behind

The check uses your local `main`. A pull request merged on the server is not in your local `main` until you pull.
Run `git sync` on `main` first, or use `--into origin/main` after a `git fetch`.

## Help and the man page

`git prune-merged -h` and `git-prune-merged --help` print the help. `git prune-merged --help` makes git open the
man page `git-prune-merged(1)`, which toolbelt installs from this document.

## Safety checks

- It asks before it deletes anything. The default answer is no, and a no exits 5.
- With no terminal to ask in, as in a script or a cron job, it refuses with exit 4 unless you pass `-y`.
- It deletes with `git branch -D` only after its own merged check. The branches it keeps, listed above, are never
  on the list.
- It prints every deleted branch with its commit hash. `git branch NAME SHA` brings one back. The commits stay in
  the repository until `git gc` removes unreachable ones, after 2 weeks by default.

## Pass-through

None. `git prune-merged` runs `git for-each-ref` to find the branches and `git branch -D` for each one, and `-v`
prints them.

## Needs

git 2.30 or newer, from the `git` package on every distro.

## Examples

### Clean up after a sprint

```console
$ git prune-merged
merged into main, safe to delete
  docs/readme-install  last commit 5 weeks ago
  feat/kres-table      last commit 2 weeks ago
  fix/probe-timeout    last commit 3 days ago
Delete 3 local branches? [y/N] y
deleted 3 branches. To bring one back, run git branch NAME SHA
  docs/readme-install  d37364b
  feat/kres-table      2f80b1e
  fix/probe-timeout    c6bafb7
```

### Bring one back

```console
$ git branch docs/readme-install d37364b
```

### Look first

```console
$ git prune-merged -n
merged into main, safe to delete
  docs/readme-install  last commit 5 weeks ago
  feat/kres-table      last commit 2 weeks ago
  fix/probe-timeout    last commit 3 days ago
would delete 3 branches, nothing changed
```

### Nothing to delete

```console
$ git prune-merged
no branches merged into main, nothing to delete
```

### In a script

```console
$ git prune-merged </dev/null
merged into main, safe to delete
  docs/readme-install  last commit 5 weeks ago
git-prune-merged: not asking without a terminal, pass --yes to go ahead
$ echo $?
4
```

### See the git commands

```console
$ git prune-merged -v -y
+ git for-each-ref --merged=main '--format=%(refname:short)%09%(objectname:short)%09%(committerdate:relative)' refs/heads/
git-prune-merged: keeping main
merged into main, safe to delete
  docs/readme-install  last commit 5 weeks ago
+ git branch -q -D -- docs/readme-install
deleted 1 branch. To bring one back, run git branch NAME SHA
  docs/readme-install  d37364b
```

### Against the remote main

```console
$ git fetch
$ git prune-merged --into origin/main
```

This catches branches merged on the server before your local `main` has them.

## Troubleshooting

`git-prune-merged: no main or master branch here. Name the base with --into, such as --into develop`
: Your default branch has another name. Pass it with `--into`.

`git-prune-merged: no branch named trunk. List them with: git branch -a`
: The name after `--into` is not a branch here. Remote branches need the remote in front, such as `origin/trunk`.

A branch I merged on GitHub is not on the list
: It was squash merged or rebase merged, or your local `main` is behind. See "How it decides".

`git-prune-merged: could not delete NAME`
: git refused the delete, and its own message above says why. The other branches were still deleted, and the
  exit code is 1.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, or there was nothing to delete. |
| 1 | Not a repository, no base branch, or a delete failed. |
| 2 | Bad usage, such as a branch name without `--into`. |
| 3 | git is not installed. |
| 4 | Refused, because there was no terminal to ask in and no `-y`. |
| 5 | You answered no. |

## See also

`git-recent`, `git-sync`, `git-branch(1)`, `git-for-each-ref(1)`
