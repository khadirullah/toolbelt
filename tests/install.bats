#!/usr/bin/env bats

load helpers

setup() {
    tb_setup
    PREFIX=$BATS_TEST_TMPDIR/prefix
}

@test "install links every command and records it" {
    run "$TB_REPO/install.sh" --prefix "$PREFIX"
    [ "$status" -eq 0 ]
    [[ $output == *"installed toolbelt"* ]]
    [ -L "$PREFIX/bin/toolbelt" ]
    [ -f "$PREFIX/share/toolbelt/lib/common.sh" ]
    [ -f "$PREFIX/share/toolbelt/.installed" ]
    run "$PREFIX/bin/toolbelt" version
    [ "$status" -eq 0 ]
    [ -L "$PREFIX/share/bash-completion/completions/toolbelt" ]
}

@test "install never replaces a file that is not its own" {
    mkdir -p "$PREFIX/bin"
    echo mine > "$PREFIX/bin/toolbelt"
    run "$TB_REPO/install.sh" --prefix "$PREFIX"
    [[ $output == *"skipped toolbelt"* ]]
    [ "$(cat "$PREFIX/bin/toolbelt")" = mine ]
}

@test "installing twice is safe" {
    "$TB_REPO/install.sh" --prefix "$PREFIX" -q
    run "$TB_REPO/install.sh" --prefix "$PREFIX"
    [ "$status" -eq 0 ]
    [ -L "$PREFIX/bin/toolbelt" ]
}

@test "uninstall removes links, the rc line and the files" {
    "$TB_REPO/install.sh" --prefix "$PREFIX" -q
    printf 'keep me\n[ -f x ] && . x  # toolbelt\n' > "$HOME/.bashrc"
    echo mine > "$PREFIX/bin/other"
    run "$TB_REPO/install.sh" --prefix "$PREFIX" --uninstall
    [ "$status" -eq 0 ]
    [[ ${lines[-1]} =~ ^"toolbelt removed, "[0-9]+" commands, "[0-9]+" man pages and "[0-9]+" completion files. Open a new terminal" ]]
    [ ! -e "$PREFIX/bin/toolbelt" ]
    [ ! -d "$PREFIX/share/toolbelt" ]
    [ -f "$PREFIX/bin/other" ]
    [ "$(cat "$HOME/.bashrc")" = "keep me" ]
}

@test "toolbelt uninstall asks, and a no keeps everything" {
    "$TB_REPO/install.sh" --prefix "$PREFIX" -q
    tb_tty
    run bash -c "echo n | '$PREFIX/bin/toolbelt' uninstall"
    [ "$status" -eq 5 ]
    [ -L "$PREFIX/bin/toolbelt" ]
    run bash -c "echo y | '$PREFIX/bin/toolbelt' uninstall"
    [ "$status" -eq 0 ]
    [ ! -e "$PREFIX/bin/toolbelt" ]
}
