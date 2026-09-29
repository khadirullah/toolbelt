#!/usr/bin/env bats
# Tests for git-whoami. The global config is a temp file, so the owner's
# own config is never read.

load helpers

setup() {
    tb_setup
    export GIT_CONFIG_GLOBAL=$BATS_TEST_TMPDIR/gitconfig GIT_CONFIG_NOSYSTEM=1
    : > "$GIT_CONFIG_GLOBAL"
    export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_DIR GIT_WORK_TREE EMAIL
}

newrepo() {
    git init -q -b main repo
    cd repo || return 1
}

@test "help prints usage and exits 0, as git-whoami and as git whoami" {
    run git-whoami --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: git whoami [options]" ]
    run git whoami -h
    [ "$status" -eq 0 ]
}

@test "bad usage exits 2" {
    run git-whoami me
    [ "$status" -eq 2 ]
    run git-whoami --nope
    [ "$status" -eq 2 ]
}

@test "no git exits 3" {
    tb_without git
    run git-whoami
    [ "$status" -eq 3 ]
    [[ $output == "git-whoami: needs git."* ]]
}

@test "nothing set exits 1 with the lines to set it" {
    run git-whoami
    [ "$status" -eq 1 ]
    [[ ${lines[0]} == 'name     not set. Set it with: git config --global user.name "Your Name"' ]]
    [[ ${lines[1]} == "email    not set. Set it with: git config --global user.email you@example.com" ]]
    [ "${lines[2]}" = "signing  none, commits are not signed" ]
    [[ $output == *"git-whoami: git refuses to commit until user.name and user.email are set"* ]]
    run git-whoami -q
    [ "$status" -eq 1 ]
}

@test "outside a repo it shows the global settings" {
    git config --global user.name "Khadirullah"
    git config --global user.email "khadirullah@example.com"
    run git-whoami
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "name     Khadirullah              $GIT_CONFIG_GLOBAL" ]
    [ "${lines[1]}" = "email    khadirullah@example.com  $GIT_CONFIG_GLOBAL" ]
    [[ $output != *remote* ]]
}

@test "a repo setting wins and says it is for this repo only" {
    git config --global user.name "Khadirullah"
    git config --global user.email "khadirullah@example.com"
    newrepo
    git config user.email "work@example.com"
    git remote add origin git@github.com:khadirullah/toolbelt.git
    run git-whoami
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "email    work@example.com  .git/config, this repo only" ]
    [ "${lines[3]}" = "remote   origin git@github.com:khadirullah/toolbelt.git" ]
}

@test "the files under home show as ~" {
    cp "$GIT_CONFIG_GLOBAL" "$HOME/.gitconfig"
    export GIT_CONFIG_GLOBAL=$HOME/.gitconfig
    git config --global user.name "Khadirullah"
    git config --global user.email "k@example.com"
    run git-whoami
    [[ ${lines[0]} == *"~/.gitconfig" ]]
}

@test "the environment beats the config files" {
    git config --global user.name "Khadirullah"
    git config --global user.email "k@example.com"
    GIT_AUTHOR_NAME="Someone Else" run git-whoami
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "name     Someone Else"*"the GIT_AUTHOR_NAME variable" ]]
}

@test "ssh signing shows the key and whether commits are signed" {
    git config --global user.name "Khadirullah"
    git config --global user.email "k@example.com"
    git config --global gpg.format ssh
    git config --global user.signingkey "$HOME/.ssh/id_ed25519.pub"
    run git-whoami
    [ "${lines[2]}" = "signing  ssh ~/.ssh/id_ed25519.pub, commits are not signed unless you pass -S" ]
    git config --global commit.gpgsign true
    run git-whoami
    [ "${lines[2]}" = "signing  ssh ~/.ssh/id_ed25519.pub, commits are signed" ]
}

@test "-q prints Name <email>" {
    git config --global user.name "Khadirullah"
    git config --global user.email "k@example.com"
    run git-whoami -q
    [ "$status" -eq 0 ]
    [ "$output" = "Khadirullah <k@example.com>" ]
}

@test "-v shows the git commands" {
    git config --global user.name "Khadirullah"
    git config --global user.email "k@example.com"
    run git-whoami -v
    [[ $output == *"+ git config --show-scope --show-origin --get user.name"* ]]
}
