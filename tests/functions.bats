#!/usr/bin/env bats
# Tests for mkcd and up in shell/functions.sh, sourced in a bash subshell.
# zsh runs the same checks when it is installed.

load helpers

setup() {
    tb_setup
    FN=$TB_REPO/shell/functions.sh
    mkdir -p "$HOME/lab/kind/manifests/base"
}

# Run shell code with the functions loaded, starting in a folder.
in_bash() { run bash -c "source '$FN'; cd '$1' || exit 9; $2"; }

@test "help for both, in the usage, blank, one-liner layout" {
    in_bash . 'mkcd --help'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: mkcd [--] folder" ]
    [[ $output == *$'\n\nMake a folder with its parents, and move into it.\n'* ]]
    in_bash . 'up -h'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: up [n | name]" ]
}

@test "mkcd makes the folder with its parents and enters it" {
    in_bash "$HOME" 'mkcd new/a/b && pwd'
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/new/a/b" ]
    in_bash "$HOME" 'mkcd lab && pwd'
    [ "$output" = "$HOME/lab" ]
}

@test "mkcd takes an absolute path and a name after --" {
    in_bash "$HOME" "mkcd '$BATS_TEST_TMPDIR/abs' && pwd"
    [ "$output" = "$BATS_TEST_TMPDIR/abs" ]
    in_bash "$HOME" 'mkcd -- -odd && pwd'
    [ "$output" = "$HOME/-odd" ]
}

@test "mkcd ignores CDPATH" {
    mkdir -p "$BATS_TEST_TMPDIR/cdp/x"
    in_bash "$HOME" "CDPATH='$BATS_TEST_TMPDIR/cdp'; mkcd x && pwd"
    [ "$output" = "$HOME/x" ]
}

@test "mkcd bad usage returns 2" {
    in_bash "$HOME" 'mkcd'
    [ "$status" -eq 2 ]
    in_bash "$HOME" 'mkcd a b'
    [ "$status" -eq 2 ]
    in_bash "$HOME" 'mkcd -x'
    [ "$status" -eq 2 ]
    [[ $output == "mkcd: unknown option -x"* ]]
}

@test "mkcd refuses a file and a folder it cannot make" {
    touch "$HOME/afile"
    in_bash "$HOME" 'mkcd afile; echo "rc=$? $PWD"'
    [[ $output == *"mkcd: afile exists and is not a folder"* ]]
    [[ $output == *"rc=1 $HOME" ]]
    chmod 500 "$HOME/lab"
    in_bash "$HOME" 'mkcd lab/nope 2>/dev/null; echo "rc=$?"'
    chmod 700 "$HOME/lab"
    [ "$output" = "rc=1" ] || [ "$(id -u)" -eq 0 ]
}

@test "up goes up one, or n levels" {
    in_bash "$HOME/lab/kind/manifests/base" 'up && pwd'
    [ "$output" = "$HOME/lab/kind/manifests" ]
    in_bash "$HOME/lab/kind/manifests/base" 'up 3 && pwd'
    [ "$output" = "$HOME/lab" ]
    in_bash "$HOME/lab/kind/manifests/base" 'up 09 && pwd'
    [ "$output" = / ]
    in_bash "$HOME" 'up 99999 && pwd'
    [ "$output" = / ]
}

@test "up with a name goes to the nearest parent of that name" {
    mkdir -p "$HOME/lab/kind/lab/deep"
    in_bash "$HOME/lab/kind/lab/deep" 'up lab && pwd'
    [ "$output" = "$HOME/lab/kind/lab" ]
    in_bash "$HOME/lab/kind/manifests/base" 'up kind && pwd'
    [ "$output" = "$HOME/lab/kind" ]
}

@test "up sets OLDPWD so cd - comes back" {
    in_bash "$HOME/lab/kind" 'up 2 && cd - >/dev/null && pwd'
    [ "$output" = "$HOME/lab/kind" ]
}

@test "up with no such parent returns 1 and stays put" {
    in_bash "$HOME/lab" 'up nosuch; echo "rc=$? $PWD"'
    [ "${lines[0]}" = "up: no parent folder named nosuch" ]
    [ "${lines[1]}" = "rc=1 $HOME/lab" ]
}

@test "up bad usage returns 2" {
    in_bash "$HOME" 'up 0'
    [ "$status" -eq 2 ]
    in_bash "$HOME" 'up a b'
    [ "$status" -eq 2 ]
    in_bash "$HOME" 'up -x'
    [ "$status" -eq 2 ]
}

@test "both are functions after sourcing, and the file is quiet" {
    run bash -c "source '$FN'; type -t mkcd; type -t up"
    [ "$output" = $'function\nfunction' ]
}

@test "zsh runs them the same way" {
    command -v zsh >/dev/null || skip "zsh is not installed"
    run zsh -fc "source '$FN'; cd '$HOME/lab/kind/manifests/base' && up kind && pwd && mkcd z/y && pwd && up 2 && pwd && mkcd --help | head -1"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$HOME/lab/kind" ]
    [ "${lines[1]}" = "$HOME/lab/kind/z/y" ]
    [ "${lines[2]}" = "$HOME/lab/kind" ]
    [ "${lines[3]}" = "usage: mkcd [--] folder" ]
}

@test "shell/init.sh loads them when the functions setting is on" {
    mkdir -p "$XDG_CONFIG_HOME/toolbelt"
    run bash -c "source '$TB_REPO/shell/init.sh'; type -t mkcd"
    [ -z "$output" ]
    echo functions > "$XDG_CONFIG_HOME/toolbelt/shell"
    run bash -c "source '$TB_REPO/shell/init.sh'; type -t mkcd; type -t up"
    [ "$output" = $'function\nfunction' ]
}
