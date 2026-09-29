#!/usr/bin/env bats
# Tests for cleanup. HOME and the system folders live under the test's temp
# folder, and journalctl, apt-get, docker, podman, dpkg-query, uname and sudo
# are stubs, so nothing real is measured as cleaned or deleted.

load helpers

setup() {
    tb_setup
    export TB_PM=apt
    export TB_ROOTFS=$BATS_TEST_TMPDIR/root
    export CALLS=$BATS_TEST_TMPDIR/calls STATE=$BATS_TEST_TMPDIR/state
    : > "$CALLS"
    mkdir -p "$STATE" "$TB_ROOTFS/var/cache/apt/archives" "$TB_ROOTFS/boot" \
        "$HOME/.cache/thumbnails/normal" "$XDG_DATA_HOME/Trash/files" "$XDG_DATA_HOME/Trash/info"
    echo 1.5G > "$STATE/journal"
    echo "3.1kB (40%)" > "$STATE/docker"
    local k
    for k in 6.1.0-10 6.1.0-12 6.1.0-13; do
        mkdir -p "$TB_ROOTFS/lib/modules/$k"
        printf 'k' > "$TB_ROOTFS/lib/modules/$k/mod"
        printf 'k' > "$TB_ROOTFS/boot/vmlinuz-$k"
    done
    printf 'deb' > "$TB_ROOTFS/var/cache/apt/archives/curl.deb"
    printf 'png' > "$HOME/.cache/thumbnails/normal/a.png"
    printf 'old' > "$XDG_DATA_HOME/Trash/files/old.txt"
    printf '[Trash Info]\n' > "$XDG_DATA_HOME/Trash/info/old.txt.trashinfo"

    tb_stub sudo 'echo "sudo $*" >> "$CALLS"; exec "$@"'
    tb_stub uname '[ "$1" = -r ] && echo 6.1.0-12'
    tb_stub dpkg-query 'printf "ii linux-image-6.1.0-13\nii linux-image-6.1.0-10\nii linux-image-6.1.0-12\nrc linux-image-5.10.0-gone\n"'
    tb_stub journalctl 'echo "journalctl $*" >> "$CALLS"
case $* in
    *--disk-usage*) echo "Archived and active journals take up $(cat "$STATE/journal") in the file system." ;;
    *--vacuum-size=*) echo 200M > "$STATE/journal" ;;
esac'
    tb_stub apt-get 'echo "apt-get $*" >> "$CALLS"
[ "$1" = clean ] && rm -f "$TB_ROOTFS"/var/cache/apt/archives/*.deb
if [ "$1" = purge ]; then
    for p in "$@"; do
        case $p in linux-image-*) rm -rf "$TB_ROOTFS/lib/modules/${p#linux-image-}" "$TB_ROOTFS/boot/vmlinuz-${p#linux-image-}" ;; esac
    done
fi
exit 0'
    tb_stub docker 'echo "docker $*" >> "$CALLS"
case $* in
    "system df"*) cat "$STATE/docker" ;;
    "system prune"*) echo "0B (0%)" > "$STATE/docker" ;;
esac'
    tb_stub podman 'exit 1'
}

@test "help prints usage and exits 0" {
    run cleanup --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: cleanup [--clean] [--only ITEM[,ITEM]] [-y] [-- tool options]" ]
}

@test "bad usage exits 2" {
    run cleanup --only cache
    [ "$status" -eq 2 ]
    [[ ${lines[0]} == "cleanup: unknown item cache. Use journal, pkgcache,"* ]]
    run cleanup -- --volumes
    [ "$status" -eq 2 ]
    run cleanup --only trash -- -x
    [ "$status" -eq 2 ]
    run cleanup journal
    [ "$status" -eq 2 ]
    run cleanup --nope
    [ "$status" -eq 2 ]
}

@test "the report lists every item and changes nothing" {
    run cleanup
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "/ is "*" free ("*"%)" ]]
    # bats drops the blank line after the disk line from lines.
    [ "${lines[1]}" = "ITEM         SIZE  WHAT --clean DOES" ]
    [ "${lines[2]}" = "journal     1.5GB  journalctl --vacuum-size=200M" ]
    [[ ${lines[3]} == "pkgcache "*"  apt-get clean" ]]
    [[ ${lines[4]} == "containers "*"  docker system prune, podman is not reachable" ]]
    [[ ${lines[5]} == "trash "*"  empties ~/.local/share/Trash, 1 file" ]]
    [[ ${lines[6]} == "kernels "*"  removes 6.1.0-10, keeps 6.1.0-12 (running), 6.1.0-13" ]]
    [[ ${lines[7]} == "thumbnails "*"  rm -r ~/.cache/thumbnails/*" ]]
    [[ ${lines[8]} == "total "*"  nothing changed. Run cleanup --clean to choose." ]]
    [[ $output == *"largest folders in $HOME"* ]]
    not grep -qE "vacuum|apt-get|prune" "$CALLS"
    [ -e "$XDG_DATA_HOME/Trash/files/old.txt" ]
    [ -e "$HOME/.cache/thumbnails/normal/a.png" ]
    [ -e "$TB_ROOTFS/var/cache/apt/archives/curl.deb" ]
}

@test "-q prints only the table" {
    run cleanup -q --only journal
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[0]}" = "ITEM         SIZE  WHAT --clean DOES" ]
}

@test "--clean without a terminal or --yes exits 4 and changes nothing" {
    run cleanup --clean </dev/null
    [ "$status" -eq 4 ]
    [ "$output" = "cleanup: not asking without a terminal, pass --yes to go ahead" ]
    not grep -qE "vacuum|apt-get|prune" "$CALLS"
    [ -e "$XDG_DATA_HOME/Trash/files/old.txt" ]
}

@test "--clean --yes cleans every item with its own tool" {
    # du counts the folder's own blocks too, and those differ by filesystem.
    local kb
    kb=$(du -sk "$TB_ROOTFS/lib/modules/6.1.0-10" "$TB_ROOTFS/boot/vmlinuz-6.1.0-10" | awk '{ s += $1 } END { print s }')
    run cleanup --clean --yes
    [ "$status" -eq 0 ]
    grep -qx "journalctl --vacuum-size=200M" "$CALLS"
    grep -qx "apt-get clean" "$CALLS"
    grep -qx "docker system prune -f" "$CALLS"
    grep -qx "apt-get purge -y linux-image-6.1.0-10" "$CALLS"
    if [ "$EUID" -ne 0 ]; then
        grep -qx "sudo journalctl --vacuum-size=200M" "$CALLS"
    fi
    [ -z "$(ls -A "$XDG_DATA_HOME/Trash/files")" ]
    [ -z "$(ls -A "$HOME/.cache/thumbnails")" ]
    [ -d "$HOME/.cache/thumbnails" ]
    [ "${lines[0]}" = "journal     freed 1.3GB" ]
    [ "${lines[4]}" = "kernels     freed ${kb}KB" ]
    [ -d "$TB_ROOTFS/lib/modules/6.1.0-12" ]
    [ -d "$TB_ROOTFS/lib/modules/6.1.0-13" ]
    [[ ${lines[-1]} == "cleanup: freed "*". / now has "*" free." ]]
}

@test "answering no to everything exits 5 and changes nothing" {
    tb_tty
    run bash -c 'printf "n\nn\nn\nn\nn\nn\n" | cleanup --clean'
    [ "$status" -eq 5 ]
    [[ $output == *"journal     1.5GB Shrink the journal to 200M? [y/N]"* ]]
    [[ $output == *"Nothing changed."* ]]
    not grep -qE "vacuum|apt-get|prune" "$CALLS"
    [ -e "$XDG_DATA_HOME/Trash/files/old.txt" ]
    [ -e "$HOME/.cache/thumbnails/normal/a.png" ]
}

@test "a yes cleans only that item" {
    tb_tty
    run bash -c 'printf "n\nn\nn\ny\nn\nn\n" | cleanup --clean'
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$XDG_DATA_HOME/Trash/files")" ]
    [ -e "$HOME/.cache/thumbnails/normal/a.png" ]
    not grep -qE "vacuum|apt-get|prune" "$CALLS"
    [[ $output == *"cleanup: freed "*" of "*". / now has "* ]]
}

@test "options after -- go to the one item's tool" {
    run cleanup --clean --yes --only containers -- --volumes
    [ "$status" -eq 0 ]
    grep -qx "docker system prune -f --volumes" "$CALLS"
    [ "${lines[0]}" = "containers  freed 3KB" ]
}

@test "missing tools skip their items" {
    tb_without journalctl docker podman
    run cleanup --only journal,containers
    [ "$status" -eq 0 ]
    [[ ${lines[2]} == "journal         -  skipped, journalctl is not installed" ]]
    [[ ${lines[3]} == "containers      -  skipped, podman and docker are not installed or not reachable" ]]
}

@test "kernels are left alone when the running one is not installed" {
    tb_stub uname '[ "$1" = -r ] && echo 6.8.0-host'
    run cleanup --only kernels
    [ "$status" -eq 0 ]
    [[ $output == *"skipped, the running kernel 6.8.0-host is not installed here"* ]]
    run cleanup --clean --yes --only kernels
    [ "$status" -eq 0 ]
    not grep -q purge "$CALLS"
}

@test "pacman keeps one kernel and cleans its cache with paccache" {
    export TB_PM=pacman
    mkdir -p "$TB_ROOTFS/var/cache/pacman/pkg"
    printf 'pkg' > "$TB_ROOTFS/var/cache/pacman/pkg/curl.pkg.tar.zst"
    tb_stub paccache 'echo "paccache $*" >> "$CALLS"'
    run cleanup --clean --yes --only pkgcache,kernels
    [ "$status" -eq 0 ]
    grep -qx "paccache -rk1" "$CALLS"
    [[ $output == *"kernels     pacman keeps one kernel per package, nothing to do"* ]]
}
