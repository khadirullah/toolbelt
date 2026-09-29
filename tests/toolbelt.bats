#!/usr/bin/env bats

load helpers

setup() { tb_setup; }

@test "toolbelt --help prints usage" {
    run toolbelt --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: toolbelt help"* ]]
}

@test "toolbelt help lists every group" {
    run toolbelt help
    [ "$status" -eq 0 ]
    for g in Archives Files System Network Everyday Kubernetes DevOps Shell toolbelt; do
        [[ $output == *"$g"* ]]
    done
    [[ $output == *"git undo prune-merged"* ]]
}

@test "toolbelt help with an unknown name is bad usage" {
    run toolbelt help nosuchthing
    [ "$status" -eq 2 ]
    [[ $output == *"no command or group named nosuchthing"* ]]
}

@test "toolbelt version names toolbelt and bash" {
    run toolbelt version
    [[ $output == "toolbelt $(cat "$TB_REPO/VERSION"), bash "* ]]
}

@test "unknown subcommand is bad usage" {
    run toolbelt frobnicate
    [ "$status" -eq 2 ]
}

@test "doctor reports a clash when another command comes first" {
    tb_stub unpack 'echo other'
    run toolbelt doctor -q
    [ "$status" -eq 1 ]
    [[ $output == *"comes before toolbelt's unpack"* ]]
}

@test "doctor reports an alias in .bashrc" {
    echo "alias squash='echo hi'" > "$HOME/.bashrc"
    run toolbelt doctor
    [[ $output == *"defines squash"* ]]
}

@test "shell enable adds one line and lists the setting" {
    export SHELL=/bin/bash
    run toolbelt shell enable functions history
    [ "$status" -eq 0 ]
    [ "$(grep -c '# toolbelt$' "$HOME/.bashrc")" -eq 1 ]
    run toolbelt shell enable safe
    [ "$(grep -c '# toolbelt$' "$HOME/.bashrc")" -eq 1 ]
    run toolbelt shell
    [[ $output == *"functions  on"* ]]
    [[ $output == *"safe       on"* ]]
    run toolbelt shell disable safe
    run toolbelt shell
    [[ $output == *"safe       off"* ]]
}

@test "shell rejects an unknown setting" {
    run toolbelt shell enable colours
    [ "$status" -eq 2 ]
}

@test "the shell init file loads in bash with every setting on" {
    mkdir -p "$XDG_CONFIG_HOME/toolbelt"
    printf 'history\nsafe\n' > "$XDG_CONFIG_HOME/toolbelt/shell"
    run bash -c "source '$TB_REPO/shell/init.sh'; alias cp; echo \$HISTSIZE"
    [[ $output == *"cp -i"* ]]
    [[ $output == *50000* ]]
}

@test "setup shows the list and a no installs nothing" {
    tb_stub sudo 'echo "sudo ran $*" >> "$HOME/sudo.log"'
    tb_tty
    run bash -c 'echo n | toolbelt setup --only archives'
    [ "$status" -eq 5 ]
    [[ $output == *"recommended tools for"* ]]
    [ ! -e "$HOME/sudo.log" ]
}

@test "setup with an unknown group is bad usage" {
    run toolbelt setup --only nosuch
    [ "$status" -eq 2 ]
}

@test "update --check reports the latest release" {
    tb_stub curl 'echo "{\"tag_name\": \"v9.9.9\"}"'
    run toolbelt update --check
    [ "$status" -eq 0 ]
    [[ $output == *"latest     9.9.9"* ]]
}

@test "update refuses a tarball whose sha256 does not match" {
    cat > "$BATS_TEST_TMPDIR/stubs/curl" <<'SH'
#!/usr/bin/env bash
for a; do url=$a; done
case $url in
  *releases/latest) printf '{"tag_name": "v9.9.9", "assets": [{"browser_download_url": "https://x/t.tar.gz"}, {"browser_download_url": "https://x/t.tar.gz.sha256"}]}' ;;
  *.sha256) echo "0000  t.tar.gz" ;;
  *) printf 'not really a tarball' ;;
esac
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/curl"
    run toolbelt -y update
    [ "$status" -eq 4 ]
    [[ $output == *"sha256 does not match"* ]]
}

@test "new writes a command, a test and a doc inside a clone" {
    mkdir -p clone/bin clone/lib clone/tests clone/docs
    cp "$TB_REPO/lib/common.sh" "$TB_REPO/lib/commands" clone/lib/
    cp "$TB_REPO/VERSION" clone/
    cd clone
    run toolbelt new mytool
    [ "$status" -eq 0 ]
    [ -x bin/mytool ] && [ -f tests/mytool.bats ] && [ -f docs/mytool.md ]
    run ./bin/mytool --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: mytool"* ]]
    run ./bin/mytool
    [ "$status" -eq 2 ]
}

@test "new refuses a name already on PATH" {
    run toolbelt new bash
    [ "$status" -eq 4 ]
    [[ $output == *"already on PATH"* ]]
}
