# git-whoami

Show the name, email and signing key git will use here.

## Synopsis

```
git whoami [options]
git-whoami [options]
```

## Description

Git takes the author of every commit from its config, and that config comes in layers. The system file, your
global `~/.gitconfig`, files it includes with `includeIf`, and the repository's own `.git/config` can all set
`user.email`, and the last one wins. The first sign of a mix-up is a work commit pushed under your personal email,
and by then it is in the history.

`git whoami` shows what git will use in the folder you are in, and which file set each value.

- `name` and `email`, the author of your next commit
- `signing`, the key and format, and whether commits are signed without `-S`
- `remote`, one line per remote, with its URL

Run it in a new clone before the first commit, or after you change `includeIf` rules.

It only reads. It works outside a repository too, and then shows the global settings and no remotes.

It is a script named `git-whoami` in toolbelt's `bin` folder. Git runs any program named `git-NAME` on your PATH
as `git NAME`.

## Options

| Option | What it does |
|---|---|
| `-q`, `--quiet` | One line, `Name <email>`, for scripts and prompts. |
| `-v`, `--verbose` | Show each git command before it runs. |
| `-h`, `--help` | Show the help. |

## Where each value comes from

The third column names the file, from `git config --show-origin --show-scope`.

| It says | Meaning |
|---|---|
| `~/.gitconfig` | Your global config. `~/.config/git/config` is the other place git reads it from. |
| `.git/config, this repo only` | The repository's own config. It beats the global one here. |
| `.git/config.worktree, this worktree only` | A worktree's own config, when `extensions.worktreeConfig` is on. |
| `/etc/gitconfig, every user` | The system config. |
| `~/.gitconfig-work` or another file | A file pulled in by `include` or `includeIf`. |
| `git -c or GIT_CONFIG_* variables` | A value set on the command line or through the `GIT_CONFIG_COUNT` variables. |
| `the GIT_AUTHOR_NAME variable` | The environment. It beats every config file. |

Git uses `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL` over `user.name` and `user.email` when they are set, and falls
back to the `EMAIL` variable when no config sets an email. `git whoami` follows the same order.

## The signing line

| It says | Meaning |
|---|---|
| `none, commits are not signed` | No signing key and `commit.gpgsign` is off. |
| `ssh ~/.ssh/id_ed25519.pub, commits are signed` | `gpg.format` is `ssh`, the key is set and `commit.gpgsign` is on. |
| `openpgp ABCD1234, commits are not signed unless you pass -S` | A key is set, but git signs only with `git commit -S`. |
| `openpgp, the key that matches your email` | Signing is on and no key is set, so gpg picks the key for your email. |

Turn signing on for every commit with `git config --global commit.gpgsign true`.

## Help and the man page

`git whoami -h` and `git-whoami --help` print the help. `git whoami --help` makes git open the man page
`git-whoami(1)`, which toolbelt installs from this document.

## Pass-through

None. `git whoami` runs `git config --get` for each key and `git remote`, and `-v` prints them.

## Needs

git 2.30 or newer, from the `git` package on every distro. `--show-scope` needs git 2.26.

## Examples

### In a work repository

```console
$ git whoami
name     Khadirullah                   ~/.gitconfig
email    khadirullah@work.example.com  .git/config, this repo only
signing  ssh ~/.ssh/id_ed25519.pub, commits are signed
remote   origin git@github.com:khadirullah/toolbelt.git
```

The email comes from this repository's own config, so commits here use the work address.

### Outside any repository

```console
$ cd ~
$ git whoami
name     Khadirullah              ~/.gitconfig
email    khadirullah@example.com  ~/.gitconfig
signing  none, commits are not signed
```

### One line for a script

```console
$ git whoami -q
Khadirullah <khadirullah@work.example.com>
```

### The environment wins

```console
$ GIT_AUTHOR_NAME="Build Bot" git whoami
name     Build Bot                the GIT_AUTHOR_NAME variable
email    khadirullah@example.com  ~/.gitconfig
signing  none, commits are not signed
```

### Nothing set yet

```console
$ git whoami
name     not set. Set it with: git config --global user.name "Your Name"
email    not set. Set it with: git config --global user.email you@example.com
signing  none, commits are not signed
git-whoami: git refuses to commit until user.name and user.email are set
$ echo $?
1
```

### See the git commands

```console
$ git whoami -v
+ git config --show-scope --show-origin --get user.name
+ git config --show-scope --show-origin --get user.email
name     Khadirullah                   ~/.gitconfig
email    khadirullah@work.example.com  .git/config, this repo only
+ git config --show-scope --show-origin --get gpg.format
+ git config --show-scope --show-origin --get user.signingkey
+ git config --show-scope --show-origin --get commit.gpgsign
signing  ssh ~/.ssh/id_ed25519.pub, commits are signed
+ git remote
remote   origin git@github.com:khadirullah/toolbelt.git
```

## Troubleshooting

The email is my personal one in a work repository
: Set it for this repository with `git config user.email you@work.example.com`. For every repository under one
  folder, add an `includeIf` block to `~/.gitconfig`, such as `[includeIf "gitdir:~/work/"]` with
  `path = ~/.gitconfig-work`, and put the work email in that file.

Commits already went out with the wrong email
: `git whoami` only shows what comes next. Fixing old commits means rewriting them, which is only safe before they
  are pushed. `git commit --amend --reset-author` fixes the last one.

`commits are signed` but GitHub shows them as unverified
: GitHub needs the same public key under Settings, SSH and GPG keys, added as a signing key, and the email on the
  commit must be one of your verified emails.

`git-whoami: user.name or user.email is not set, git refuses to commit`
: `-q` found no name or email. Set both with `git config --global`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Name and email are both set. |
| 1 | The name or the email is not set, so git refuses to commit. |
| 2 | Bad usage, such as an argument. |
| 3 | git is not installed. |

## See also

`git-sync`, `git-undo`, `git-config(1)`
