#!/usr/bin/env bats
# Tests for git-recent, in throwaway repos with an empty global config.

load helpers

setup() {
    tb_setup
    export GIT_CONFIG_GLOBAL=$BATS_TEST_TMPDIR/gitconfig GIT_CONFIG_NOSYSTEM=1
    : > "$GIT_CONFIG_GLOBAL"
    export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_DIR GIT_WORK_TREE
}

# A commit on a branch, made a number of hours ago.
commit_on() {
    local branch=$1 hours=$2 subject=$3 when
    when=$(( $(date +%s) - hours * 3600 ))
    if [[ $(git symbolic-ref --short HEAD) != "$branch" ]]; then
        git switch -q "$branch" 2>/dev/null || git switch -q -c "$branch" main
    fi
    echo "$subject" >> "${branch//\//-}.txt"
    git add "${branch//\//-}.txt"
    GIT_COMMITTER_DATE="@$when" GIT_AUTHOR_DATE="@$when" git commit -q -m "$subject"
}

newrepo() {
    git init -q -b main repo
    cd repo || return 1
    git config user.name Tester
    git config user.email tester@example.com
    git config commit.gpgsign false
    commit_on main 50 "first"
    commit_on fix/kwhy-pending 30 "kwhy: hint for Pending pods"
    commit_on feat/ctx-warn 5 "ctx: flag production contexts"
    commit_on main 2 "tfcheck: add trivy section"
    git switch -q feat/ctx-warn
}

@test "help prints usage and exits 0, as git-recent and as git recent" {
    run git-recent --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: git recent [-n count] [options]" ]
    run git recent -h
    [ "$status" -eq 0 ]
}

@test "bad usage exits 2" {
    run git-recent -n 0
    [ "$status" -eq 2 ]
    [[ $output == *"-n needs a number of 1 or more"* ]]
    run git-recent -n many
    [ "$status" -eq 2 ]
    run git-recent main
    [ "$status" -eq 2 ]
    run git-recent -n
    [ "$status" -eq 2 ]
}

@test "no git exits 3" {
    tb_without git
    run git-recent
    [ "$status" -eq 3 ]
    [[ $output == "git-recent: needs git."* ]]
}

@test "outside a repository it fails" {
    run git-recent
    [ "$status" -eq 1 ]
    [ "$output" = "git-recent: not inside a git repository" ]
}

@test "lists branches newest first and marks the current one" {
    newrepo
    run git-recent
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[0]}" = "  main              2 hours ago   tfcheck: add trivy section" ]
    [ "${lines[1]}" = "* feat/ctx-warn     5 hours ago   ctx: flag production contexts" ]
    [[ ${lines[2]} == "  fix/kwhy-pending  "*"kwhy: hint for Pending pods" ]]
}

@test "-n limits the count and -a lifts it" {
    newrepo
    run git-recent -n 2
    [ "${#lines[@]}" -eq 2 ]
    run git-recent -n2
    [ "${#lines[@]}" -eq 2 ]
    for i in $(seq 1 11); do git branch "b$i"; done
    run git-recent
    [ "${#lines[@]}" -eq 10 ]
    run git-recent -a
    [ "${#lines[@]}" -eq 14 ]
}

@test "-q prints branch names only, for scripts" {
    newrepo
    run git-recent -q -n 2
    [ "$status" -eq 0 ]
    [ "$output" = $'main\nfeat/ctx-warn' ]
}

@test "a long subject is cut to fit" {
    newrepo
    commit_on main 1 "$(printf 'word %.0s' $(seq 1 20))"
    run git-recent -n 1
    [[ ${lines[0]} == *"..." ]]
    [ "${#lines[0]}" -le 80 ]
}

@test "a repo with no commits has no branches yet" {
    git init -q -b main repo
    cd repo
    run git-recent
    [ "$status" -eq 0 ]
    [[ $output == *"no branches yet"* ]]
}

@test "-v shows the git command" {
    newrepo
    run git-recent -v -n 1
    [[ ${lines[0]} == "+ git for-each-ref --sort=-committerdate --count=1 "* ]]
}
