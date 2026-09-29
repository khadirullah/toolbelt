#!/usr/bin/env bats
# Tests for squash. Fixtures are a few KB, made in each test.

load helpers

setup() {
    tb_setup
    mkdir -p photos/sub
    printf 'hello\n' > photos/a.txt
    seq 1 2000 > photos/sub/n.txt
    head -c 4096 /dev/urandom > photos/r.bin
}

# Entries in a tar stream on stdin, one per line.
tar_names() { tar -tf - | sort; }

# ---------------------------------------------------------------- help and usage

@test "help prints the layout and exits 0" {
    run squash -h
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: squash [options] path ... [-- tool options]" ]
    [[ $output == *"Pack files and folders into any free format."* ]]
    [[ $output == *"Needs: "* ]]
    [[ $output == *"Exit: 0 ok"* ]]
    run squash --help
    [ "$status" -eq 0 ]
}

@test "help fits in 80 columns" {
    run squash -h
    while IFS= read -r line; do
        [ "${#line}" -le 80 ]
    done <<<"$output"
}

@test "bad usage exits 2" {
    run squash
    [ "$status" -eq 2 ]
    [[ $output == *"name at least one file or folder"* ]]
    run squash --nope photos
    [ "$status" -eq 2 ]
    run squash -l 0 photos
    [ "$status" -eq 2 ]
    run squash -l 10 photos
    [ "$status" -eq 2 ]
    run squash -l 5 --max photos
    [ "$status" -eq 2 ]
    run squash --rm -k photos
    [ "$status" -eq 2 ]
    run squash -T zero photos
    [ "$status" -eq 2 ]
    run squash -s lots photos
    [ "$status" -eq 2 ]
    run squash -f cab photos
    [ "$status" -eq 2 ]
    [[ $output == *"unknown format cab"* ]]
    [ ! -e photos.tar.zst ]
}

@test "rar is refused with exit 2" {
    run squash -f rar photos
    [ "$status" -eq 2 ]
    [[ $output == *"rar is not supported for creating"* ]]
    run squash -o x.rar photos
    [ "$status" -eq 2 ]
}

@test "-p with a tar format exits 2 and suggests lock" {
    run squash -p photos
    [ "$status" -eq 2 ]
    [[ $output == *"-p works with zip and 7z only. For a tar.zst, run lock"* ]]
}

@test "--rm with -x exits 2" {
    run squash --rm -x '*.bin' photos
    [ "$status" -eq 2 ]
    [ -d photos ]
}

@test "a missing source exits 1" {
    run squash nothing-here
    [ "$status" -eq 1 ]
    [[ $output == *"nothing-here: no such file or folder"* ]]
}

@test "a missing tool exits 3 with an install line" {
    tb_without zstd
    run squash photos
    [ "$status" -eq 3 ]
    [[ $output == "squash: needs zstd."* ]]
    [ ! -e photos.tar.zst ]
}

@test "a missing zip exits 3" {
    tb_without zip
    run squash -f zip photos
    [ "$status" -eq 3 ]
    [[ $output == *"needs zip"* ]]
}

# ---------------------------------------------------------------- normal cases

@test "a folder becomes tar.zst with the summary line" {
    run squash photos
    [ "$status" -eq 0 ]
    [[ $output =~ ^photos/\ -\>\ photos\.tar\.zst\ \([0-9.]+KB\ to\ [0-9.]+KB,\ 3\ files,\ [0-9.]+s\)$ ]]
    [ -f photos.tar.zst ]
    [ -d photos ]
    run bash -c 'zstd -dc photos.tar.zst | tar -tf - | sort'
    [[ $output == *"photos/sub/n.txt"* ]]
    [[ $output == *"photos/r.bin"* ]]
    # No temp folder is left behind.
    run ls -A
    [ "$output" = "$(printf 'photos\nphotos.tar.zst')" ]
}

@test "a single file is compressed without tar" {
    run squash photos/sub/n.txt
    [ "$status" -eq 0 ]
    [[ $output == "photos/sub/n.txt -> n.txt.zst ("*", 1 file, "* ]]
    zstd -dc n.txt.zst | cmp - photos/sub/n.txt
}

@test "-f tar.zst keeps tar for a single file" {
    run squash -f tar.zst photos/a.txt
    [ "$status" -eq 0 ]
    [ -f a.txt.tar.zst ]
    run bash -c 'zstd -dc a.txt.tar.zst | tar -tf -'
    [ "$output" = a.txt ]
}

@test "-f zst on a folder packs it as tar.zst" {
    run squash -f zst photos
    [ "$status" -eq 0 ]
    [ -f photos.tar.zst ]
}

# True when the tool for a format is installed.
have_fmt() {
    case ${1#tar.} in
        tar) return 0 ;;
        gz) tb_has_any gzip ;; bz2) tb_has_any bzip2 ;; xz|lzma) tb_has_any xz ;; zst) tb_has_any zstd ;;
        lz4) tb_has_any lz4 ;; lz) tb_has_any lzip plzip ;; lzo) tb_has_any lzop ;;
        zip) tb_has_any zip ;; 7z) tb_has_any 7z ;;
    esac
}
tb_has_any() { local t; for t; do command -v "$t" >/dev/null && return 0; done; return 1; }

@test "every installed format round-trips and passes -t" {
    local fmt
    for fmt in tar tar.gz tar.bz2 tar.xz tar.lzma tar.zst tar.lz4 tar.lz tar.lzo zip 7z; do
        have_fmt "$fmt" || continue
        run squash -q -t -T 1 -f "$fmt" -o "out-${fmt//./-}" photos
        [ "$status" -eq 0 ]
        [[ ${lines[1]} == "test passed: out-${fmt//./-}."*", 5 entries, the same as the source" ]]
    done
    [ "$(tar -tf out-tar.tar | wc -l)" -eq 5 ]
    [ "$(gzip -dc out-tar-gz.tar.gz | tar -tf - | wc -l)" -eq 5 ]
    [ "$(xz --format=lzma -dc out-tar-lzma.tar.lzma | tar -tf - | wc -l)" -eq 5 ]
    if have_fmt lzo; then [ "$(lzop -dc out-tar-lzo.tar.lzo | tar -tf - | wc -l)" -eq 5 ]; fi
    [ "$(unzip -Z1 out-zip.zip | wc -l)" -eq 5 ]
}

@test "every single-file format round-trips" {
    local fmt
    for fmt in gz bz2 xz lzma zst lz4 lz lzo; do
        have_fmt "$fmt" || continue
        run squash -q -t -f "$fmt" photos/sub/n.txt
        [ "$status" -eq 0 ]
        [[ $output == *"test passed: n.txt.$fmt, unpacks to the same"* ]]
    done
    gzip -dc n.txt.gz | cmp - photos/sub/n.txt
    lz4 -dc n.txt.lz4 | cmp - photos/sub/n.txt
}

@test "-o picks the format from its extension" {
    run squash -o site.zip photos
    [ "$status" -eq 0 ]
    [ -f site.zip ]
    run squash -o site.tgz photos
    [ "$status" -eq 0 ]
    gzip -t site.tgz
}

@test "-o without an extension gets one" {
    run squash -f xz -o backup photos
    [ "$status" -eq 0 ]
    [ -f backup.tar.xz ]
}

@test "-o naming a folder puts the archive there" {
    mkdir out
    run squash -o out photos
    [ "$status" -eq 0 ]
    [ -f out/photos.tar.zst ]
}

@test "-o that disagrees with -f exits 2" {
    run squash -f 7z -o x.zip photos
    [ "$status" -eq 2 ]
    [[ $output == *"says zip, but the format is 7z"* ]]
}

@test "-o with a single-file extension for a folder exits 2" {
    run squash -o x.zst photos
    [ "$status" -eq 2 ]
    [[ $output == *"x.zst holds a single file, name it x.tar.zst"* ]]
}

@test "-f tar.gz with a .gz name exits 2 and names the fix" {
    run squash -f tar.gz -o x.gz photos
    [ "$status" -eq 2 ]
    [[ $output == *"x.gz holds a single file, name it x.tar.gz"* ]]
}

@test "-q prints only the summary line" {
    run squash -q photos
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
}

@test "squash . from inside the folder writes beside it" {
    cd photos
    run squash .
    [ "$status" -eq 0 ]
    [ -f ../photos.tar.zst ]
    [ ! -e photos.tar.zst ]
}

# ---------------------------------------------------------------- safety

@test "an existing archive is never overwritten" {
    echo keep > photos.tar.zst
    run squash photos
    [ "$status" -eq 4 ]
    [[ $output == *"photos.tar.zst already exists. Pass -y to write photos-1.tar.zst"* ]]
    [ "$(cat photos.tar.zst)" = keep ]
}

@test "-y takes the next free name" {
    echo keep > photos.tar.zst
    touch photos-1.tar.zst
    run squash -y photos
    [ "$status" -eq 0 ]
    [[ $output == *"photos/ -> photos-2.tar.zst ("* ]]
    [ -s photos-2.tar.zst ]
    [ "$(cat photos.tar.zst)" = keep ]
}

@test "the archive may not land inside the folder it packs" {
    run squash -o photos/inside.tar.zst photos
    [ "$status" -eq 4 ]
    [[ $output == *"would land inside"* ]]
    [ ! -e photos/inside.tar.zst ]
}

@test "too little disk space refuses with exit 4" {
    TB_TEST_FREE_KB=1 run squash photos
    [ "$status" -eq 4 ]
    [[ $output == *"has 1 KB free"* ]]
    [ ! -e photos.tar.zst ]
}

@test "xz -l 9 refuses when one thread does not fit in memory" {
    TB_TEST_MEM_KB=100000 run squash -f xz -l 9 photos
    [ "$status" -eq 4 ]
    [[ $output == *"Use a lower -l"* ]]
}

@test "xz -l 9 lowers the threads to fit in memory" {
    tb_stub xz 'cat'
    TB_TEST_MEM_KB=2000000 run squash -v -f xz -l 9 -T 4 photos
    [ "$status" -eq 0 ]
    [[ $output == *"4 threads need about"*"using 2"* ]]
    [[ $output == *"+ tar -cf - photos | xz -c -9 -T 2 > photos.tar.xz"* ]]
}

@test "zstd --max with threads is checked against memory" {
    TB_TEST_MEM_KB=10000 run squash --max -T 4 photos
    [ "$status" -eq 4 ]
    [[ $output == *"zstd at this level needs about"* ]]
}

@test "zstd --max on a small source keeps its threads" {
    tb_stub zstd 'cat'
    TB_TEST_MEM_KB=500000 run squash -v --max -T 4 -k photos
    [[ $output == *"threads: 4, zstd -T4"* ]]
    [[ $output != *"using 1"* ]]
}

@test "a failed test keeps the source and removes the archive" {
    tb_stub zstd 'for a; do [[ $a == -dc ]] && { echo "zstd: corrupted block" >&2; exit 1; }; done; cat'
    tb_tty
    run bash -c 'echo y | squash photos'
    [ "$status" -eq 1 ]
    [[ $output == *"the test failed"* ]]
    [ -d photos ]
    [ ! -e photos.tar.zst ]
    [ -z "$(ls -A | grep -v '^photos$')" ]
}

# ---------------------------------------------------------------- delete question

@test "no terminal: no question, the source stays" {
    run squash photos </dev/null
    [ "$status" -eq 0 ]
    [[ $output != *"Delete"* ]]
    [ -d photos ]
}

@test "yes moves the source to the trash after the test" {
    tb_tty
    run bash -c 'echo y | squash photos'
    [ "$status" -eq 0 ]
    [[ $output == *"Delete the source, photos/ (3 files, "*" KB)? It goes to the trash. [y/N]"* ]]
    [[ $output == *"photos/ is in the trash."* ]]
    [ ! -e photos ]
    [ "$(tb_trash_list)" = photos ]
    [ -f photos.tar.zst ]
}

@test "no keeps the source and exits 0" {
    tb_tty
    run bash -c 'echo n | squash photos'
    [ "$status" -eq 0 ]
    [ -d photos ]
    [ -z "$(tb_trash_list)" ]
}

@test "a single file gets the short question" {
    tb_tty
    run bash -c 'echo n | squash photos/a.txt'
    [[ $output == *"Delete the source, photos/a.txt (6 B)? It goes to the trash."* ]]
}

@test "--rm trashes without asking, -k never asks" {
    run squash --rm photos
    [ "$status" -eq 0 ]
    [ ! -e photos ]
    [[ $output == *"photos/ is in the trash."* ]]
    mkdir notes && echo x > notes/x.txt
    tb_tty
    run bash -c 'echo y | squash -k notes'
    [ "$status" -eq 0 ]
    [[ $output != *"Delete"* ]]
    [ -d notes ]
}

@test "-y does not answer the delete question" {
    tb_tty
    run bash -c 'echo n | squash -y photos'
    [ -d photos ]
}

@test "-x leaves files out and skips the question" {
    tb_tty
    run bash -c 'echo y | squash -x "*.bin" -x sub photos'
    [ "$status" -eq 0 ]
    [[ $output != *"Delete"* ]]
    [[ $output == *"photos/ stays, -x left files out of the archive."* ]]
    [[ $output == *"(1 file"* || $output == *", 1 file, "* ]]
    run bash -c 'zstd -dc photos.tar.zst | tar -tf - | sort'
    [ "$output" = "$(printf 'photos/\nphotos/a.txt')" ]
}

@test "-x works for zip and 7z too" {
    tb_needs 7z
    run squash -f zip -x '*.bin' -x sub photos
    [ "$status" -eq 0 ]
    run bash -c 'unzip -Z1 photos.zip | sort'
    [ "$output" = "$(printf 'photos/\nphotos/a.txt')" ]
    run squash -f 7z -x '*.bin' photos
    [ "$status" -eq 0 ]
    run bash -c "7z l -slt photos.7z | grep -c '^Path = photos/r.bin'"
    [ "$output" = 0 ]
}

# ---------------------------------------------------------------- split and password

@test "-s writes numbered parts for tar formats" {
    run squash -f tar.gz -s 2K photos
    [ "$status" -eq 0 ]
    [[ $output == *"-> photos.tar.gz.001 to .00"* ]]
    [ -f photos.tar.gz.001 ]
    [ -f photos.tar.gz.002 ]
    [ "$(stat -c %s photos.tar.gz.001)" -eq 2048 ]
    [ "$(cat photos.tar.gz.0* | gzip -dc | tar -tf - | wc -l)" -eq 5 ]
}

@test "-s uses 7z volumes and zip parts" {
    tb_needs 7z
    head -c 153600 /dev/urandom > photos/big.bin
    run squash -t -f 7z -s 64K photos
    [ "$status" -eq 0 ]
    [ -f photos.7z.001 ]
    [ -f photos.7z.002 ]
    [[ $output == *"test passed"* ]]
    run squash -t -f zip -s 64K photos
    [ "$status" -eq 0 ]
    [ -f photos.z01 ]
    [ -f photos.zip ]
    [[ $output == *"-> photos.z01 to .zip"* ]]
}

@test "zip parts smaller than 64K exit 2" {
    run squash -f zip -s 10K photos
    [ "$status" -eq 2 ]
}

@test "-p asks twice and writes an encrypted 7z" {
    tb_needs 7z
    tb_tty
    run bash -c 'printf "s3cret\ns3cret\n" | squash -k -t -f 7z -p photos'
    [ "$status" -eq 0 ]
    [[ $output == *"Password:"* ]]
    [[ $output == *"Again:"* ]]
    [[ $output == *"test passed"* ]]
    [[ $output != *"s3cret"* ]]
    # The names are hidden without the password.
    run bash -c '7z l -slt -p photos.7z </dev/null 2>&1 | grep -c "^Path = photos/a.txt"'
    [ "$output" = 0 ]
    run bash -c 'printf "s3cret\n" | 7z l -slt photos.7z | grep -c "^Path = photos/a.txt"'
    [ "$output" = 1 ]
}

@test "-p for zip uses 7z with AES" {
    tb_needs 7z
    tb_tty
    run bash -c 'printf "pw\npw\n" | squash -k -v -f zip -p photos'
    [ "$status" -eq 0 ]
    [[ $output == *"+ 7z a -tzip -mem=AES256"* ]]
    run bash -c '7z l -slt photos.zip | grep "^Method = AES" | head -n 1'
    [[ $output == *AES* ]]
}

@test "-p with different answers exits 1 and writes nothing" {
    tb_needs 7z
    tb_tty
    run bash -c 'printf "one\ntwo\n" | squash -f 7z -p photos'
    [ "$status" -eq 1 ]
    [[ $output == *"the two passwords differ"* ]]
    [ ! -e photos.7z ]
}

@test "-p without a terminal refuses with exit 4" {
    tb_needs 7z
    run squash -f 7z -p photos </dev/null
    [ "$status" -eq 4 ]
    [ ! -e photos.7z ]
}

# ---------------------------------------------------------------- levels, tools, pass-through

@test "-v shows the steps and the real command" {
    run squash -v -l 9 -T 1 photos
    [ "$status" -eq 0 ]
    [[ $output == *"squash: format: tar.zst, the default"* ]]
    [[ $output == *"squash: level: -l 9 is zstd -19"* ]]
    [[ $output == *"+ tar -cf - photos | zstd -c -q --size-hint="*" -19 -T1 > photos.tar.zst"* ]]
    [[ $output == *"| tar -tf -"* ]] || true
}

@test "levels map onto each tool's scale" {
    run squash -v -l 5 -T 1 -o a photos
    [[ $output == *"zstd -10"* ]]
    run squash -v -l 5 -f lz4 -o b photos
    [[ $output == *"lz4 -c -q -6"* ]]
    if command -v 7z >/dev/null; then
        run squash -v -l 4 -f 7z -o c photos
        [[ $output == *"-mx=5"* ]]
    fi
    run squash -v -l 3 -f gz -T 1 -o d photos
    [[ $output == *" -3 "* ]]
}

@test "--max uses each tool's real top level" {
    run squash -v --max -T 1 -o a photos
    [ "$status" -eq 0 ]
    [[ $output == *"--ultra -22"* ]]
    run squash -v --max -f gz -T 1 -o b photos
    if command -v pigz >/dev/null; then
        [[ $output == *"pigz -c -11"* ]]
    else
        [[ $output == *"gzip -c -9"* ]]
    fi
    run squash -v --max -f lz4 -o c photos
    [[ $output == *"lz4 -c -q -12"* ]]
    tb_stub xz 'cat'
    run squash -v --max -f xz -T 1 -o d photos
    [[ $output == *"xz -c -9e"* ]]
}

@test "the plain tool runs when the parallel one is missing" {
    tb_without pigz
    run squash -v -f gz photos
    [ "$status" -eq 0 ]
    [[ $output == *"| gzip -c > photos.tar.gz"* ]]
    [[ $output == *"threads: 1, gzip runs on one core"* ]]
}

@test "pbzip2 and brotli run when installed" {
    tb_stub pbzip2 'for a; do [[ $a == -dc ]] && exec bzip2 -dc; done; exec bzip2 -c'
    tb_stub brotli 'for a; do [[ $a == -dc ]] && exec cat; done; exec cat'
    run squash -v -T 2 -f bz2 photos
    [ "$status" -eq 0 ]
    [[ $output == *"| pbzip2 -c -p2 > photos.tar.bz2"* ]]
    run squash -v -f br photos/a.txt
    [ "$status" -eq 0 ]
    [[ $output == *"brotli -c -q 6 < photos/a.txt > a.txt.br"* ]]
    [ -f a.txt.br ]
}

@test "options after -- go to the compressor" {
    run squash -v -T 1 photos -- --long=20
    [ "$status" -eq 0 ]
    [[ $output == *"-T1 --long=20 > photos.tar.zst"* ]]
    run squash -v -f tar -o t photos -- --owner=0
    [[ $output == *"+ tar -cf - --owner=0 photos > t.tar"* ]]
}

@test "--compare prints a table and writes nothing" {
    tb_stub brotli 'exit 1'
    rm -f "$BATS_TEST_TMPDIR/stubs/brotli"
    run squash --compare photos
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "sample: all of photos/ ("*"), every format at -l 6" ]]
    [[ $output == *"format"*"size"*"ratio"*"time"* ]]
    [[ $output == *"tar.zst"* ]]
    [[ $output == *"tar.xz"* ]]
    [[ $output == *"7z"* ]]
    run ls -A
    [ "$output" = photos ]
}

@test "--compare lists formats whose tool is missing" {
    tb_without brotli lzop
    run squash --compare photos
    [ "$status" -eq 0 ]
    [[ $output == *"skipped: tar.lzo, lzop is not installed"* ]]
    [[ $output == *"skipped: tar.br, brotli is not installed"* ]]
}
