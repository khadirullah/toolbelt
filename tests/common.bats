#!/usr/bin/env bats
# Tests for lib/common.sh, through a small command built in each test.

load helpers

setup() {
    tb_setup
    cat > "$BATS_TEST_TMPDIR/stubs/demo" <<SH
#!/usr/bin/env bash
TB_CMD=demo
source "$TB_REPO/lib/common.sh"
usage() { echo "usage: demo [options]"; }
tb_expand "o" "\$@"; set -- "\${TB_EXPANDED[@]}"
out=""
while (( \$# )); do
    case \$1 in
        -o|--out) tb_optarg "\$@"; out=\$2; shift ;;
        --) shift; TB_PASS=("\$@"); break ;;
        -*) tb_common_opt "\$1" || tb_unknown "\$1" ;;
        *) break ;;
    esac
    shift
done
cmd=\${1:-}; shift || true
case \$cmd in
    args)   echo "out=\$out quiet=\$TB_QUIET verbose=\$TB_VERBOSE pass=\${TB_PASS[*]}" ;;
    need)   tb_need "\$@"; echo found ;;
    any)    tb_need_any got "\$@"; echo "got=\$got" ;;
    human)  tb_human "\$@" ;;
    ask)    tb_ask "Go on?"; echo "rc=\$?" ;;
    confirm) tb_confirm "Go on?"; echo went ;;
    trash)  tb_trash "\$@" && echo "\${TB_TRASHED[*]}" ;;
    offer)  TB_RM=\${RM:-0}; TB_KEEP=\${KEEP:-0}; tb_offer_delete "Delete \$1?" "\$1 is in the trash." "\$1"; echo "rc=\$?" ;;
    run)    tb_run "\$@" ;;
    tmp)    tb_tmpdir d; echo "\$d" ;;
    freename) tb_free_name "\$@" ;;
esac
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/demo"
}

@test "short flags bundle and values attach" {
    run demo -qvo dir args
    [ "$status" -eq 0 ]
    [ "$output" = "out=dir quiet=1 verbose=1 pass=" ]
}

@test "long options take =value and -- passes the rest" {
    run demo --out=x args -- -a --b
    [ "$output" = "out=x quiet=0 verbose=0 pass=" ]
    run demo --out x -- args
    [ "$status" -eq 0 ]
}

@test "unknown option exits 2 and points at --help" {
    run demo --nope
    [ "$status" -eq 2 ]
    [[ $output == *"unknown option --nope"* ]]
    [[ $output == *"demo --help"* ]]
}

@test "missing value exits 2" {
    run demo --out
    [ "$status" -eq 2 ]
    [[ $output == *"--out needs a value"* ]]
}

@test "-h prints usage and exits 0" {
    run demo -h
    [ "$status" -eq 0 ]
    [ "$output" = "usage: demo [options]" ]
}

@test "a missing tool exits 3 with an install line" {
    run demo need definitely-not-a-tool
    [ "$status" -eq 3 ]
    [[ $output == "demo: needs definitely-not-a-tool."* ]]
    run demo need bash
    [ "$output" = found ]
}

@test "need_any picks the first tool that exists" {
    run demo any no-such-tool bash sh
    [ "$output" = "got=bash" ]
    run demo any no-such-a no-such-b
    [ "$status" -eq 3 ]
}

@test "human sizes" {
    run demo human 512;       [ "$output" = 512B ]
    run demo human 2560;      [ "$output" = 2.5KB ]
    run demo human 32505856;  [ "$output" = 31MB ]
    run demo human 32505856 " "; [ "$output" = "31 MB" ]
    run demo human 1288490188; [ "$output" = 1.2GB ]
    run demo human 1048575;   [ "$output" = 1MB ]
}

@test "ask returns 2 without a terminal and never reads" {
    run bash -c 'echo y | demo ask'
    [ "$output" = "rc=2" ]
}

@test "ask reads y and n through the test terminal" {
    tb_tty
    run bash -c 'echo y | demo ask'
    [[ $output == *"rc=0"* ]]
    run bash -c 'echo n | demo ask'
    [[ $output == *"rc=1"* ]]
    run bash -c 'echo | demo ask'
    [[ $output == *"rc=1"* ]]
}

@test "confirm: no exits 5, no terminal exits 4, --yes goes on" {
    tb_tty
    run bash -c 'echo n | demo confirm'
    [ "$status" -eq 5 ]
    unset TB_TEST_TTY
    run bash -c 'demo confirm </dev/null'
    [ "$status" -eq 4 ]
    run demo -y confirm
    [ "$output" = went ]
}

@test "trash moves a file and writes trashinfo" {
    echo hi > "a b.txt"
    run demo trash "a b.txt"
    [ "$status" -eq 0 ]
    [ ! -e "a b.txt" ]
    [ -f "$XDG_DATA_HOME/Trash/files/a b.txt" ]
    grep -q '^Path=.*/a%20b.txt$' "$XDG_DATA_HOME/Trash/info/a b.txt.trashinfo"
    echo again > "a b.txt"
    run demo trash "a b.txt"
    [ "$output" = "a b.txt.2" ]
}

@test "offer_delete keeps files without a terminal" {
    echo x > f.zip
    run demo offer f.zip
    [ "$output" = "rc=0" ]
    [ -e f.zip ]
}

@test "offer_delete asks, and y moves to the trash" {
    echo x > f.zip
    tb_tty
    run bash -c 'echo y | demo offer f.zip'
    [[ $output == *"f.zip is in the trash."* ]]
    [ ! -e f.zip ]
    echo x > g.zip
    run bash -c 'echo n | demo offer g.zip'
    [[ $output == *"rc=0"* ]]
    [ -e g.zip ]
}

@test "offer_delete: --rm skips the question, --keep never deletes" {
    echo x > f.zip
    RM=1 run demo offer f.zip
    [ ! -e f.zip ]
    echo x > g.zip
    tb_tty
    KEEP=1 run bash -c 'echo y | demo offer g.zip'
    [ -e g.zip ]
}

@test "-v shows the real command" {
    run demo -v run echo "two words"
    [ "${lines[0]}" = "+ echo 'two words'" ]
    [ "${lines[1]}" = "two words" ]
}

@test "temp folders are gone after exit" {
    run demo tmp
    [ -n "$output" ]
    [ ! -e "$output" ]
}

@test "free_name numbers before the extension" {
    touch notes.txt notes-1.txt
    run demo freename notes.txt file
    [ "$output" = notes-2.txt ]
    mkdir out
    run demo freename out dir
    [ "$output" = out-1 ]
}
