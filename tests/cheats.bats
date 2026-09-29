#!/usr/bin/env bats
# Tests for cheats. curl is a stub, so nothing touches the network.

load helpers

setup() {
    tb_setup
    # The stub writes a page for the URL, or fails the way curl does.
    # MODE: ok, down (exit 6), unknown (cheat.sh "Unknown topic"), tldr
    # (cheat.sh 404, tldr has it), none (404 everywhere).
    tb_stub curl 'out="" url=""
while (( $# )); do case $1 in -o) out=$2; shift ;; http*) url=$1 ;; esac; shift; done
echo "$url" >> "$BATS_TEST_TMPDIR/urls"
case ${MODE:-ok} in
    ok) printf "# Create a gzip archive\ntar -czf a.tar.gz dir/\n" > "$out" ;;
    down) echo "curl: (6) Could not resolve host" >&2; exit 6 ;;
    unknown) [[ $url == *cheat.sh* ]] && { printf "Unknown topic.\n" > "$out"; exit 0; }; exit 22 ;;
    tldr) [[ $url == */common/* ]] || exit 22
          printf "# tar\n\n> Archiver.\n\n- Create an archive:\n\n\`tar cf {{target.tar}} {{file1}}\`\n" > "$out" ;;
    none) exit 22 ;;
esac'
    CACHE=$XDG_CACHE_HOME/toolbelt/cheats
}

urls() { cat "$BATS_TEST_TMPDIR/urls" 2>/dev/null; }

@test "help prints usage and exits 0" {
    run cheats --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: cheats "* ]]
}

@test "bad usage exits 2" {
    run cheats
    [ "$status" -eq 2 ]
    run cheats ../etc
    [ "$status" -eq 2 ]
    run cheats -u -o tar
    [ "$status" -eq 2 ]
    run cheats -l tar
    [ "$status" -eq 2 ]
    run cheats --nope tar
    [ "$status" -eq 2 ]
}

@test "a missing curl exits 3 when the page is not cached" {
    tb_without curl
    run cheats tar
    [ "$status" -eq 3 ]
    [[ $output == "cheats: needs curl."* ]]
}

@test "fetches from cheat.sh and saves the page" {
    run cheats -v tar
    [ "$status" -eq 0 ]
    [[ $output == *"+ curl -fsSL --max-time 15 -o "*"'https://cheat.sh/tar?T'"* ]]
    [[ $output == *"tar -czf a.tar.gz dir/"* ]]
    [[ $output == *"cheats: saved $CACHE/tar, from cheat.sh"* ]]
    [ -f "$CACHE/tar" ]
}

@test "a topic goes in the URL and the cache name" {
    run cheats kubectl logs
    [ "$status" -eq 0 ]
    [ "$(urls)" = "https://cheat.sh/kubectl/logs?T" ]
    [ -f "$CACHE/kubectl-logs" ]
    run cheats git "undo commit"
    [ "$(urls | tail -1)" = "https://cheat.sh/git/undo+commit?T" ]
    [ -f "$CACHE/git-undo-commit" ]
}

@test "a fresh cached page needs no network" {
    cheats tar
    rm "$BATS_TEST_TMPDIR/urls"
    MODE=down run cheats tar
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "# Create a gzip archive" ]
    [[ ${lines[2]} =~ ^cheats:\ tar,\ cached\ [0-9]s\ ago$ ]]
    [ -z "$(urls)" ]
}

@test "-u fetches again, and an old page refreshes" {
    cheats tar
    run cheats -u tar
    [ "$(urls | wc -l)" -eq 2 ]
    touch -d "$(tb_ago 3456000)" "$CACHE/tar"
    run cheats tar
    [ "$(urls | wc -l)" -eq 3 ]
}

@test "an old page is still shown when the network is down" {
    cheats tar
    touch -d "$(tb_ago 3456000)" "$CACHE/tar"
    MODE=down run cheats tar
    [ "$status" -eq 0 ]
    [[ $output == *"tar -czf"* ]]
    [[ $output == *"cheats: could not refresh tar, showing the copy from 40d ago"* ]]
}

@test "-o uses only the cache" {
    run cheats -o rsync
    [ "$status" -eq 1 ]
    [[ $output == *"cheats: no cached page for rsync"* ]]
    [ -z "$(urls)" ]
}

@test "no page and no network exits 1" {
    MODE=down run cheats rsync
    [ "$status" -eq 1 ]
    [[ $output == *"cheats: no cached page for rsync, and cheat.sh is unreachable"* ]]
    [[ $output == *"cheats: cached pages are listed by cheats -l"* ]]
    [ ! -e "$CACHE/rsync" ]
}

@test "an unknown command exits 1 and saves nothing" {
    MODE=unknown run cheats nosuchtool
    [ "$status" -eq 1 ]
    [[ $output == *"cheats: no page for nosuchtool on cheat.sh or tldr"* ]]
    [ ! -e "$CACHE/nosuchtool" ]
}

@test "falls back to tldr and reshapes the page" {
    MODE=tldr run cheats tar
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "# Create an archive" ]
    [ "${lines[1]}" = "tar cf target.tar file1" ]
    [[ $(urls) == *"/pages/common/tar.md"* ]]
}

@test "-l lists the cached pages" {
    run cheats -l
    [ "$status" -eq 0 ]
    [[ $output == *"no cached pages yet"* ]]
    cheats tar
    cheats kubectl logs
    run cheats -l
    [[ ${lines[0]} =~ ^kubectl-logs\ +[0-9]s\ ago$ ]]
    [[ ${lines[1]} =~ ^tar\ +[0-9]s\ ago$ ]]
}

@test "options after -- go to curl" {
    tb_stub curl 'printf "%s\n" "$@" > "$BATS_TEST_TMPDIR/args"; while (( $# )); do [[ $1 == -o ]] && echo page > "$2"; shift; done'
    run cheats tar -- --proxy http://proxy.example.com:3128
    [ "$status" -eq 0 ]
    grep -qx -- --proxy "$BATS_TEST_TMPDIR/args"
}
