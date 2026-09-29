#!/usr/bin/env bats
# Tests for git-undo. Every repo is a throwaway one in the test folder, and
# git reads an empty global config, never the owner's.

load helpers

setup() {
    tb_setup
    export GIT_CONFIG_GLOBAL=$BATS_TEST_TMPDIR/gitconfig GIT_CONFIG_NOSYSTEM=1
    : > "$GIT_CONFIG_GLOBAL"
    export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_DIR GIT_WORK_TREE
}


# Commit a line to notes.txt with a subject.
commit() {
    echo "$1" >> notes.txt
    git add notes.txt
    git commit -q -m "$1"
}

newrepo() {
    git init -q -b main repo
    cd repo || return 1
    git config user.name Tester
    git config user.email tester@example.com
    git config commit.gpgsign false
}

@test "help prints usage and exits 0, as git-undo and as git undo" {
    run git-undo --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: git undo [--hard] [options]" ]
    run git undo -h
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "Take back the last commit and keep its changes." ]
}

@test "bad usage exits 2" {
    run git-undo HEAD~2
    [ "$status" -eq 2 ]
    [[ $output == *"takes no arguments"* ]]
    run git-undo --nope
    [ "$status" -eq 2 ]
}

@test "no git exits 3" {
    tb_without git
    run git-undo
    [ "$status" -eq 3 ]
    [[ $output == "git-undo: needs git."* ]]
}

@test "outside a repository it fails with a clear line" {
    run git-undo
    [ "$status" -eq 1 ]
    [ "$output" = "git-undo: not inside a git repository" ]
}

@test "an empty repo and the first commit have nothing to undo" {
    newrepo
    run git-undo
    [ "$status" -eq 1 ]
    [[ $output == *"no commits yet"* ]]
    commit first
    run git-undo
    [ "$status" -eq 1 ]
    [[ $output == *"is the first commit"* ]]
}

@test "undo keeps the changes staged and prints the way back" {
    newrepo
    commit first
    commit second
    old=$(git rev-parse --short HEAD)
    tb_tty
    run bash -c 'echo y | git-undo'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "This takes back commit $old \"second\". Its changes stay staged, nothing is lost." ]
    [ "${lines[1]}" = "Undo $old? [y/N] undid $old \"second\"" ]
    [[ $output == *"git reset --soft $old"* ]]
    [ "$(git log --format=%s)" = "first" ]
    [ "$(git status --porcelain)" = "M  notes.txt" ]
    git reset -q --soft "$old"
    [ "$(git log -1 --format=%s)" = "second" ]
}

@test "-q prints only the result line" {
    newrepo
    commit first
    commit second
    run git-undo -q -y
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ ${lines[0]} == "undid "* ]]
}

@test "a commit already on the upstream is refused with exit 4" {
    git init -q --bare -b main origin.git
    newrepo
    commit first
    commit second
    git remote add origin ../origin.git
    git push -q -u origin main 2>/dev/null
    head=$(git rev-parse HEAD)
    run git-undo
    [ "$status" -eq 4 ]
    [[ $output == *"refused, $(git rev-parse --short HEAD) is already on origin/main"* ]]
    [[ $output == *"git revert"* ]]
    [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "a commit on any remote branch is refused, even without an upstream" {
    git init -q --bare -b main origin.git
    newrepo
    commit first
    commit second
    git remote add origin ../origin.git
    git push -q origin main:elsewhere 2>/dev/null
    run git-undo
    [ "$status" -eq 4 ]
    [[ $output == *"is already on origin/elsewhere"* ]]
}

@test "an unpushed commit on top of a pushed one can be undone" {
    git init -q --bare -b main origin.git
    newrepo
    commit first
    git remote add origin ../origin.git
    git push -q -u origin main 2>/dev/null
    commit local
    run git-undo -y
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "first" ]
}

@test "a plain undo without a terminal refuses with exit 4" {
    newrepo
    commit first
    commit second
    run git-undo
    [ "$status" -eq 4 ]
    [[ $output == *"not asking without a terminal, pass --yes to go ahead"* ]]
    [ "$(git log -1 --format=%s)" = "second" ]
}

@test "a plain undo answered no exits 5 and changes nothing" {
    newrepo
    commit first
    commit second
    tb_tty
    run bash -c 'echo n | git-undo'
    [ "$status" -eq 5 ]
    [[ $output == *"Undo $(git rev-parse --short HEAD)? [y/N]"* ]]
    [[ $output == *"Nothing changed."* ]]
    [ "$(git log -1 --format=%s)" = "second" ]
    [ -z "$(git status --porcelain)" ]
}

@test "--hard without a terminal refuses with exit 4" {
    newrepo
    commit first
    commit second
    run git-undo --hard
    [ "$status" -eq 4 ]
    [ "$(git log -1 --format=%s)" = "second" ]
}

@test "--hard answered no exits 5 and changes nothing" {
    newrepo
    commit first
    commit second
    tb_tty
    run bash -c 'echo n | git-undo --hard'
    [ "$status" -eq 5 ]
    [[ $output == *"Drop "*" and its changes? [y/N]"* ]]
    [ "$(git log -1 --format=%s)" = "second" ]
}

@test "--hard answered yes drops the commit and keeps other work" {
    newrepo
    commit first
    printf 'x\n' > other.txt
    git add other.txt
    git commit -q -m other
    commit second
    old=$(git rev-parse --short HEAD)
    echo "uncommitted" >> other.txt
    tb_tty
    run bash -c 'echo y | git-undo --hard'
    [ "$status" -eq 0 ]
    [[ $output == *"dropped $old \"second\""* ]]
    [[ $output == *"git reset --keep $old"* ]]
    [ "$(git log -1 --format=%s)" = "other" ]
    [ "$(tail -n 1 notes.txt)" = "first" ]
    [ "$(tail -n 1 other.txt)" = "uncommitted" ]
}

@test "--hard -y stops when an uncommitted change touches the same file" {
    newrepo
    commit first
    commit second
    echo "not saved" >> notes.txt
    run git-undo --hard -y
    [ "$status" -eq 1 ]
    [[ $output == *"Nothing was dropped"* ]]
    [ "$(git log -1 --format=%s)" = "second" ]
    [ "$(tail -n 1 notes.txt)" = "not saved" ]
}

@test "a merge in progress is refused with exit 4" {
    newrepo
    commit first
    commit second
    touch "$(git rev-parse --git-path MERGE_HEAD)"
    run git-undo
    [ "$status" -eq 4 ]
    [[ $output == *"a merge is in progress"* ]]
}

@test "-v shows the git commands" {
    newrepo
    commit first
    commit second
    run git-undo -v -y
    [ "$status" -eq 0 ]
    [[ $output == *"+ git reset -q --soft "* ]]
}
