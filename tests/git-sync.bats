#!/usr/bin/env bats
# Tests for git-sync. The remote is a bare repo in the test folder, and a
# second clone plays the teammate who pushes to it.

load helpers

setup() {
    tb_setup
    export GIT_CONFIG_GLOBAL=$BATS_TEST_TMPDIR/gitconfig GIT_CONFIG_NOSYSTEM=1
    printf '[user]\n\tname = Tester\n\temail = tester@example.com\n[commit]\n\tgpgsign = false\n' > "$GIT_CONFIG_GLOBAL"
    export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_DIR GIT_WORK_TREE
    W=$BATS_TEST_TMPDIR/work
}

# Append a line to a file and commit it.
commit() {
    echo "$2" >> "$1"
    git add "$1"
    git commit -q -m "$2"
}

# origin.git, a clone "mine" to sync, and a clone "theirs" that pushes.
newrepos() {
    git init -q --bare -b main "$W/origin.git"
    git clone -q "$W/origin.git" "$W/theirs" 2>/dev/null
    cd "$W/theirs" || return 1
    git config user.name Theirs
    commit base.txt first
    git push -q origin main 2>/dev/null
    git clone -q "$W/origin.git" "$W/mine" 2>/dev/null
    cd "$W/mine" || return 1
    git config user.name Tester
    git config user.email tester@example.com
}

# The teammate pushes commits, and creates or deletes branches.
theirs() { (cd "$W/theirs" && "$@") >/dev/null 2>&1; }

@test "help prints usage and exits 0, as git-sync and as git sync" {
    run git-sync --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: git sync [options]" ]
    run git sync -h
    [ "$status" -eq 0 ]
}

@test "bad usage exits 2" {
    run git-sync origin
    [ "$status" -eq 2 ]
    run git-sync --nope
    [ "$status" -eq 2 ]
}

@test "no git exits 3" {
    tb_without git
    run git-sync
    [ "$status" -eq 3 ]
    [[ $output == "git-sync: needs git."* ]]
}

@test "outside a repository it fails" {
    run git-sync
    [ "$status" -eq 1 ]
    [ "$output" = "git-sync: not inside a git repository" ]
}

@test "a branch with no upstream is refused with a push hint" {
    newrepos
    git switch -q -c feat/new
    run git-sync
    [ "$status" -eq 1 ]
    [ "$output" = "git-sync: feat/new has no upstream branch. Push it with: git push -u origin feat/new" ]
}

@test "a detached HEAD is refused" {
    newrepos
    git checkout -q --detach
    run git-sync
    [ "$status" -eq 1 ]
    [[ $output == *"HEAD is detached"* ]]
}

@test "up to date says so" {
    newrepos
    run git-sync
    [ "$status" -eq 0 ]
    [[ $output == *"fetched origin, nothing new on main"* ]]
    [[ $output == *"main is up to date with origin/main"* ]]
}

@test "no local commits fast-forwards" {
    newrepos
    theirs commit base.txt second
    theirs git push -q origin main
    run git-sync
    [ "$status" -eq 0 ]
    [[ $output == *"fetched origin, 1 new commit on main"* ]]
    [[ $output == *"fast-forwarded main to origin/main"* ]]
    [ "$(git log -1 --format=%s)" = "second" ]
}

@test "stashes, rebases, restores and reports pruned branches" {
    newrepos
    theirs git push -q origin main:old-feature
    git fetch -q
    theirs git push -q origin --delete old-feature
    theirs commit base.txt second
    theirs commit base.txt third
    theirs git push -q origin main
    commit mine.txt "my work"
    echo dirty >> mine.txt
    echo new > new.txt
    run git-sync
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "stashed 2 changed files" ]
    [ "${lines[1]}" = "fetched origin, 2 new commits on main" ]
    [ "${lines[2]}" = "rebased main onto origin/main, 1 commit replayed" ]
    [ "${lines[3]}" = "restored the stashed files" ]
    [ "${lines[4]}" = "removed 1 remote branch that is gone from origin" ]
    [ "$(git log --format=%s | tr '\n' ,)" = "my work,third,second,first," ]
    [ "$(tail -n 1 mine.txt)" = "dirty" ]
    [ -f new.txt ]
    [ -z "$(git stash list)" ]
    ! git rev-parse -q --verify origin/old-feature
}

@test "a rebase conflict is undone and exits 1" {
    newrepos
    theirs commit base.txt theirs-line
    theirs git push -q origin main
    commit base.txt my-line
    head=$(git rev-parse HEAD)
    echo dirty > other.txt
    run git-sync
    [ "$status" -eq 1 ]
    [[ $output == *"hit a conflict. The rebase is undone and main is as it was"* ]]
    [[ $output == *"git rebase origin/main"* ]]
    [ "$(git rev-parse HEAD)" = "$head" ]
    [ ! -d "$(git rev-parse --git-path rebase-merge)" ]
    [ "$(cat other.txt)" = "dirty" ]
    [ -z "$(git stash list)" ]
}

@test "local commits ahead of the upstream are left alone" {
    newrepos
    commit mine.txt "not pushed"
    run git-sync -q
    [ "$status" -eq 0 ]
    [ "$output" = "main already has everything from origin/main, 1 commit to push" ]
}

@test "a rebase in progress is refused with exit 4" {
    newrepos
    mkdir "$(git rev-parse --git-path rebase-merge)"
    run git-sync
    [ "$status" -eq 4 ]
}

@test "-v shows the git commands" {
    newrepos
    run git-sync -v
    [ "$status" -eq 0 ]
    [[ $output == *"+ git fetch -q --prune origin"* ]]
}
