#!/usr/bin/env bats
# Tests for pkg. Every package manager is a stub that only logs its arguments.

load helpers

setup() {
    tb_setup
    export CALLS=$BATS_TEST_TMPDIR/calls
    : > "$CALLS"
    local t
    for t in apt apt-get dnf pacman zypper apk flatpak fwupdmgr; do
        tb_stub "$t" "echo \"$t \$*\" >> \"\$CALLS\""
    done
    tb_stub sudo 'echo "sudo $*" >> "$CALLS"; exec "$@"'
    tb_stub dpkg-query 'echo "ii  3.4.1-1"'
    export TB_PM=apt
}

@test "help prints usage and exits 0" {
    run pkg --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: pkg install|remove|search|info NAME"* ]]
}

@test "bad usage exits 2" {
    run pkg
    [ "$status" -eq 2 ]
    run pkg frobnicate htop
    [ "$status" -eq 2 ]
    [[ $output == *"unknown action frobnicate"* ]]
    run pkg install
    [ "$status" -eq 2 ]
    run pkg install --all htop
    [ "$status" -eq 2 ]
    run pkg upgrade htop
    [ "$status" -eq 2 ]
    run pkg owner /bin/sh -- -x
    [ "$status" -eq 2 ]
    run pkg --nope
    [ "$status" -eq 2 ]
    [ ! -s "$CALLS" ]
}

@test "no package manager exits 3" {
    unset TB_PM
    tb_without apt-get dnf yum pacman zypper apk
    run pkg search htop
    [ "$status" -eq 3 ]
    [[ $output == "pkg: no known package manager found"* ]]
}

@test "a missing sudo exits 3 before anything runs" {
    [ "$EUID" -eq 0 ] && skip "root needs no sudo"
    tb_without sudo
    run pkg install htop
    [ "$status" -eq 3 ]
    [[ $output == "pkg: needs sudo."* ]]
    [ ! -s "$CALLS" ]
}

@test "install runs apt with sudo and names the version" {
    run pkg install htop
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "pkg: installed htop 3.4.1-1" ]
    grep -qx "apt install htop" "$CALLS"
}

@test "the same words map to each package manager" {
    local s
    [ "$EUID" -eq 0 ] && s="" || s="sudo "
    TB_PM=apt run pkg -n install htop
    [ "$output" = "${s}apt install htop" ]
    TB_PM=dnf run pkg -n remove htop
    [ "$output" = "${s}dnf remove htop" ]
    TB_PM=pacman run pkg -n remove htop
    [ "$output" = "${s}pacman -Rs htop" ]
    TB_PM=zypper run pkg -n search htop
    [ "$output" = "zypper search htop" ]
    TB_PM=apk run pkg -n install htop
    [ "$output" = "${s}apk add htop" ]
    TB_PM=apt run pkg -n info htop
    [ "$output" = "apt show htop" ]
    TB_PM=pacman run pkg -n files htop
    [ "$output" = "pacman -Qlq htop" ]
    TB_PM=apk run pkg -n files htop
    [ "$output" = "apk info -L htop" ]
    [ ! -s "$CALLS" ]
}

@test "yum stands in for dnf on older systems" {
    rm "$BATS_TEST_TMPDIR/stubs/dnf"
    tb_without dnf
    TB_PM=dnf run pkg -n search htop
    [ "$output" = "yum search htop" ]
}

@test "-y passes each manager's own yes flag" {
    local s
    [ "$EUID" -eq 0 ] && s="" || s="sudo "
    TB_PM=apt run pkg -n -y install htop
    [ "$output" = "${s}apt install -y htop" ]
    TB_PM=pacman run pkg -n -y install htop
    [ "$output" = "${s}pacman -S --noconfirm htop" ]
    TB_PM=zypper run pkg -n -y install htop
    [ "$output" = "${s}zypper --non-interactive install htop" ]
    TB_PM=dnf run pkg -n -y upgrade
    [ "$output" = "${s}dnf upgrade -y" ]
}

@test "options after -- go to the package manager" {
    TB_PM=dnf run pkg install nginx -- --setopt=install_weak_deps=False
    [ "$status" -eq 0 ]
    grep -qx "dnf install --setopt=install_weak_deps=False nginx" "$CALLS"
}

@test "-v names the distro and shows the real command" {
    run pkg -v search ripgrep
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "pkg: "*", package manager apt" ]]
    [ "${lines[1]}" = "+ apt search ripgrep" ]
}

@test "a failing package manager exits 1" {
    tb_stub apt 'echo "E: Unable to locate package nosuch" >&2; exit 100'
    run pkg install nosuch
    [ "$status" -eq 1 ]
    [[ $output == *"pkg: apt install stopped with exit 100"* ]]
    [[ $output != *"installed nosuch"* ]]
}

@test "owner names the package, or says installed by hand" {
    printf 'x\n' > tool
    printf 'y\n' > mine
    tb_stub dpkg '[[ $1 == -S && $3 == */tool ]] || exit 1; echo "iproute2: $3"'
    run pkg owner tool mine
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "$PWD/tool  iproute2 3.4.1-1" ]
    [ "${lines[1]}" = "$PWD/mine  no package, installed by hand" ]
    run pkg owner tool
    [ "$status" -eq 0 ]
}

@test "owner reads rpm, pacman and apk answers" {
    printf 'x\n' > ss
    tb_stub rpm 'echo "iproute 6.14.0-2.fc44"'
    TB_PM=dnf run pkg owner ./ss
    [ "$output" = "$PWD/ss  iproute 6.14.0-2.fc44" ]
    tb_stub pacman 'echo "$2 is owned by iproute2 6.14.0-1"'
    TB_PM=pacman run pkg owner ss
    [ "$output" = "$PWD/ss  iproute2 6.14.0-1" ]
    tb_stub apk 'echo "$3 is owned by iproute2-ss-6.14.0-r0"'
    TB_PM=apk run pkg owner ss
    [ "$output" = "$PWD/ss  iproute2-ss 6.14.0-r0" ]
}

@test "owner looks up a bare command name on PATH" {
    tb_stub dpkg '[[ $3 == */stubs/fwupdmgr ]] && echo "fwupd: $3"'
    run pkg owner fwupdmgr
    [ "$status" -eq 0 ]
    [[ $output == *"/stubs/fwupdmgr  fwupd 3.4.1-1" ]]
    run pkg owner no-such-command-here
    [ "$status" -eq 1 ]
    [[ $output == *"no such file or command"* ]]
}

@test "files lists what a package installed" {
    tb_stub dpkg 'printf "/usr/bin/htop\n/usr/share/man/man1/htop.1.gz\n"'
    run pkg files htop
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "/usr/bin/htop" ]
}

@test "upgrade --all updates the extras and skips missing ones" {
    tb_stub fwupdmgr 'echo "fwupdmgr $*" >> "$CALLS"; [[ $1 == refresh ]] && exit 2; exit 0'
    tb_without snap
    run pkg upgrade --all
    [ "$status" -eq 0 ]
    grep -qx "apt update" "$CALLS"
    grep -qx "apt upgrade" "$CALLS"
    grep -qx "flatpak update" "$CALLS"
    grep -qx "fwupdmgr update" "$CALLS"
    [[ $output == *"snap      not installed, skipped"* ]]
    [[ $output == *"fwupd     updated"* ]]
    [[ $output == *"pkg: all updated in "* ]]
}

@test "upgrade reports a failing extra and exits 1" {
    tb_stub flatpak 'exit 1'
    run pkg upgrade --all
    [ "$status" -eq 1 ]
    [[ $output == *"flatpak   failed with exit 1"* ]]
}
