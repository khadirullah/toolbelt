#!/usr/bin/env bats
# Tests for git-wip, in throwaway repos with an empty global config.

load helpers

setup() {
    tb_setup
    export GIT_CONFIG_GLOBAL=$BATS_TEST_TMPDIR/gitconfig GIT_CONFIG_NOSYSTEM=1
    : > "$GIT_CONFIG_GLOBAL"
    export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_DIR GIT_WORK_TREE
}

newrepo() {
    git init -q -b main repo
    cd repo || return 1
    git config user.name Tester
    git config user.email tester@example.com
    git config commit.gpgsign false
    printf 'one\n' > a.txt
    printf 'two\n' > b.txt
    git add a.txt b.txt
    git commit -q -m first
}

@test "help prints usage and exits 0, as git-wip and as git wip" {
    run git-wip --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: git wip [options]" ]
    run git wip -h
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "Save every change as a commit named wip." ]
}

@test "bad usage exits 2" {
    run git-wip "my message"
    [ "$status" -eq 2 ]
    [[ $output == *"takes no arguments"* ]]
    run git-wip --nope
    [ "$status" -eq 2 ]
}

@test "no git exits 3" {
    tb_without git
    run git-wip
    [ "$status" -eq 3 ]
    [[ $output == "git-wip: needs git."* ]]
}

@test "outside a repository it fails" {
    run git-wip
    [ "$status" -eq 1 ]
    [ "$output" = "git-wip: not inside a git repository" ]
}

@test "a clean tree has nothing to save" {
    newrepo
    run git-wip
    [ "$status" -eq 1 ]
    [ "$output" = "git-wip: nothing to save, the working tree is clean" ]
}

@test "saves changed, deleted and new files, even from a subfolder" {
    newrepo
    echo more >> a.txt
    rm b.txt
    mkdir -p sub/deep
    echo new > sub/deep/c.txt
    echo new > d.txt
    printf 'ignored.log\n' > .git/info/exclude
    echo skip > ignored.log
    cd sub
    run git-wip
    [ "$status" -eq 0 ]
    [[ ${lines[0]} =~ ^saved\ 2\ changed\ and\ 2\ new\ files\ as\ [0-9a-f]+\ \"wip\"\ on\ main$ ]]
    [ "${lines[1]}" = "git undo brings them back" ]
    cd ..
    [ "$(git log -1 --format=%s)" = "wip" ]
    [ -z "$(git status --porcelain)" ] || [ "$(git status --porcelain)" = "" ]
    [ "$(git show --name-only --format= HEAD | sort | tr '\n' ' ')" = "a.txt b.txt d.txt sub/deep/c.txt " ]
    [ -f ignored.log ]
}

@test "one new file reads as singular" {
    newrepo
    echo x > only.txt
    run git-wip -q
    [ "$status" -eq 0 ]
    [[ $output =~ ^saved\ 1\ new\ file\ as ]]
}

@test "commit hooks do not block it" {
    newrepo
    printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo more >> a.txt
    run git-wip
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "wip" ]
}

@test "git undo takes a wip commit back" {
    newrepo
    echo more >> a.txt
    echo new > n.txt
    git-wip -q
    run git-undo -q -y
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "first" ]
    [ "$(git status --porcelain | sort | tr '\n' ' ')" = "A  n.txt M  a.txt " ]
}

@test "a detached HEAD says so" {
    newrepo
    git checkout -q --detach
    echo more >> a.txt
    run git-wip
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == *'"wip" on a detached HEAD' ]]
}

@test "a rebase in progress is refused with exit 4" {
    newrepo
    mkdir "$(git rev-parse --git-path rebase-merge)"
    echo more >> a.txt
    run git-wip
    [ "$status" -eq 4 ]
    [[ $output == *"a rebase is in progress"* ]]
}

@test "-v shows the git commands" {
    newrepo
    echo more >> a.txt
    run git-wip -v
    [ "$status" -eq 0 ]
    [[ $output == *"+ git add -A"* ]]
    [[ $output == *"+ git commit -q --no-verify -m wip"* ]]
}
