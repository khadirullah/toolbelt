#!/usr/bin/env bats
# Tests for git-prune-merged, in throwaway repos with an empty global config.
# The remote is a bare repo in the test folder.

load helpers

setup() {
    tb_setup
    export GIT_CONFIG_GLOBAL=$BATS_TEST_TMPDIR/gitconfig GIT_CONFIG_NOSYSTEM=1
    : > "$GIT_CONFIG_GLOBAL"
    export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_DIR GIT_WORK_TREE
}

commit() {
    echo "$1" >> notes.txt
    git add notes.txt
    git commit -q -m "$1"
}

# main with two merged branches, one unmerged, and one merged into develop only.
newrepo() {
    git init -q -b main repo
    cd repo || return 1
    git config user.name Tester
    git config user.email tester@example.com
    git config commit.gpgsign false
    commit first
    git branch fix/probe-timeout
    git branch feat/kres-table
    git switch -q -c feat/unmerged
    commit unmerged
    git switch -q -c develop main
    commit on-develop
    git branch feat/in-develop
    git switch -q main
}

@test "help prints usage and exits 0, as git-prune-merged and as git prune-merged" {
    run git-prune-merged --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: git prune-merged [--into branch] [options]" ]
    run git prune-merged -h
    [ "$status" -eq 0 ]
}

@test "bad usage exits 2" {
    run git-prune-merged main
    [ "$status" -eq 2 ]
    [[ $output == *"--into main"* ]]
    run git-prune-merged --into
    [ "$status" -eq 2 ]
    run git-prune-merged --nope
    [ "$status" -eq 2 ]
}

@test "no git exits 3" {
    tb_without git
    run git-prune-merged
    [ "$status" -eq 3 ]
    [[ $output == "git-prune-merged: needs git."* ]]
}

@test "outside a repository it fails" {
    run git-prune-merged
    [ "$status" -eq 1 ]
    [ "$output" = "git-prune-merged: not inside a git repository" ]
}

@test "a base that does not exist fails with exit 1" {
    newrepo
    run git-prune-merged --into trunk
    [ "$status" -eq 1 ]
    [[ $output == *"no branch named trunk"* ]]
    git branch -q -m main trunk
    git branch -q -D feat/in-develop
    run git-prune-merged
    [ "$status" -eq 1 ]
    [[ $output == *"no main or master branch here"* ]]
}

@test "--dry-run lists the merged branches and deletes nothing" {
    newrepo
    run git-prune-merged -n
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "merged into main, safe to delete" ]
    [[ $output == *"  feat/kres-table    last commit "* ]]
    [[ $output == *"  fix/probe-timeout  last commit "* ]]
    [[ $output != *"feat/unmerged"* ]]
    [[ $output != *"develop"* ]]
    [[ $output == *"would delete 2 branches, nothing changed"* ]]
    [ "$(git branch --list | wc -l)" -eq 6 ]
}

@test "without a terminal it refuses with exit 4" {
    newrepo
    run git-prune-merged
    [ "$status" -eq 4 ]
    git rev-parse -q --verify fix/probe-timeout
}

@test "answering no exits 5 and keeps the branches" {
    newrepo
    tb_tty
    run bash -c 'echo n | git-prune-merged'
    [ "$status" -eq 5 ]
    [[ $output == *"Delete 2 local branches? [y/N]"* ]]
    git rev-parse -q --verify fix/probe-timeout
}

@test "answering yes deletes them and prints how to bring one back" {
    newrepo
    sha=$(git rev-parse --short fix/probe-timeout)
    tb_tty
    run bash -c 'echo y | git-prune-merged'
    [ "$status" -eq 0 ]
    [[ $output == *"deleted 2 branches. To bring one back, run git branch NAME SHA"* ]]
    [[ $output == *"  fix/probe-timeout  $sha"* ]]
    ! git rev-parse -q --verify fix/probe-timeout
    ! git rev-parse -q --verify feat/kres-table
    git rev-parse -q --verify feat/unmerged
    git rev-parse -q --verify develop
    git branch fix/probe-timeout "$sha"
}

@test "it never deletes the current branch, main, master or one in another worktree" {
    newrepo
    git branch master
    git switch -q fix/probe-timeout
    git worktree add -q ../wt feat/kres-table
    run git-prune-merged -y --into develop
    [ "$status" -eq 0 ]
    [[ $output == *"feat/in-develop"* ]]
    [[ $output != *"  main "* && $output != *"  master "* ]]
    git rev-parse -q --verify main
    git rev-parse -q --verify master
    git rev-parse -q --verify fix/probe-timeout
    git rev-parse -q --verify feat/kres-table
    ! git rev-parse -q --verify feat/in-develop
    git worktree remove ../wt
}

@test "--into a remote branch keeps its local twin" {
    git init -q --bare -b main origin.git
    newrepo
    git remote add origin ../origin.git
    git push -q origin main develop 2>/dev/null
    git switch -q feat/unmerged
    run git-prune-merged -y --into origin/develop
    [ "$status" -eq 0 ]
    git rev-parse -q --verify develop
    git rev-parse -q --verify main
    ! git rev-parse -q --verify feat/in-develop
}

@test "nothing merged says so and exits 0" {
    newrepo
    git branch -q -D fix/probe-timeout feat/kres-table
    run git-prune-merged
    [ "$status" -eq 0 ]
    [ "$output" = "no branches merged into main, nothing to delete" ]
}

@test "-v shows the git commands" {
    newrepo
    run git-prune-merged -v -y
    [ "$status" -eq 0 ]
    [[ $output == *"+ git for-each-ref --merged=main "* ]]
    [[ $output == *"+ git branch -q -D -- fix/probe-timeout"* ]]
}
