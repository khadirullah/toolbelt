#!/usr/bin/env bats
# Tests for dupes.

load helpers

setup() {
    tb_setup
    mkdir -p pics/phone pics/2026 docs
    head -c 6000 /dev/urandom > pics/2026/IMG_4410.jpg
    cp pics/2026/IMG_4410.jpg pics/phone/IMG_4410.jpg
    cp pics/2026/IMG_4410.jpg 'pics/phone/IMG_4410 (1).jpg'
    touch -d '2026-01-01' pics/2026/IMG_4410.jpg
    printf 'same text\n' > docs/a.txt
    cp docs/a.txt docs/b.txt
    touch -d '2026-02-01' docs/b.txt
    # Same size and the same first 4KB, but a different end.
    { head -c 4096 pics/2026/IMG_4410.jpg; head -c 1904 /dev/urandom; } > pics/near.jpg
    # Empty files and hard links are never reported.
    : > docs/e1
    : > docs/e2
    ln docs/a.txt docs/link.txt
}

@test "help prints usage and exits 0" {
    run dupes --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: dupes "* ]]
}

@test "bad usage exits 2" {
    run dupes --trash --link
    [ "$status" -eq 2 ]
    run dupes -m lots
    [ "$status" -eq 2 ]
    [[ $output == *"--min needs a size"* ]]
    run dupes . -- -r
    [ "$status" -eq 2 ]
    run dupes --nope
    [ "$status" -eq 2 ]
}

@test "a missing sha256sum exits 3" {
    tb_without sha256sum
    run dupes .
    [ "$status" -eq 3 ]
    [[ $output == "dupes: needs sha256sum."* ]]
}

@test "finds groups by content, oldest first, with the total" {
    run dupes
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "5.9KB x 3" ]
    [ "${lines[1]}" = "  ./pics/2026/IMG_4410.jpg" ]
    [ "${lines[4]}" = "10B x 2" ]
    [ "${lines[7]}" = "2 groups, 12KB you could free" ]
    [[ $output != *near.jpg* ]]
    [[ $output != *e1* ]]
    [ "$(grep -c 'a.txt\|link.txt' <<<"$output")" -eq 1 ]
}

@test "--min, -x and --only filter the files" {
    run dupes -m 1K .
    [ "${lines[0]}" = "5.9KB x 3" ]
    [ "${lines[4]}" = "1 group, 12KB you could free" ]
    run dupes -x '*(1).jpg' pics
    [ "${lines[0]}" = "5.9KB x 2" ]
    run dupes --only '*.txt' .
    [ "${lines[0]}" = "10B x 2" ]
    [ "${#lines[@]}" -eq 4 ]
}

@test "no duplicates still exits 0" {
    run dupes docs/e1 pics/near.jpg
    [ "$status" -eq 0 ]
    [ "$output" = "No duplicates." ]
}

@test "--trash asks, keeps the oldest and trashes the rest" {
    run dupes --trash pics </dev/null
    [ "$status" -eq 4 ]
    tb_tty
    run bash -c 'echo n | dupes --trash pics'
    [ "$status" -eq 5 ]
    run bash -c 'echo y | dupes --trash pics'
    [ "$status" -eq 0 ]
    [[ $output == *"keep   pics/2026/IMG_4410.jpg  oldest"* ]]
    [[ $output == *"2 files in the trash, 12KB freed."* ]]
    [ -e pics/2026/IMG_4410.jpg ]
    [ ! -e pics/phone/IMG_4410.jpg ]
    [ "$(tb_trash_list | wc -l)" -eq 2 ]
}

@test "--link swaps copies for hard links to the oldest" {
    run dupes -y --link pics
    [ "$status" -eq 0 ]
    [[ $output == *"2 copies are now hard links, 12KB freed."* ]]
    [ pics/phone/IMG_4410.jpg -ef pics/2026/IMG_4410.jpg ]
    [ "pics/phone/IMG_4410 (1).jpg" -ef pics/2026/IMG_4410.jpg ]
    run dupes pics
    [ "$output" = "No duplicates." ]
}

@test "--fast reads groups from jdupes" {
    tb_stub jdupes 'printf "%s\n" ./docs/a.txt ./docs/b.txt "" ./pics/2026/IMG_4410.jpg ./pics/phone/IMG_4410.jpg ""'
    run dupes -v --fast . -- -Q
    [ "$status" -eq 0 ]
    [[ $output == *"+ jdupes -r -q -Q -- ."* ]]
    [[ $output == *"5.9KB x 2"* ]]
    [[ $output == *"2 groups"* ]]
}

@test "--fast reads the rdfind results file" {
    tb_stub rdfind '
out=""
while (( $# )); do [[ $1 == -outputname ]] && out=$2; shift; done
cat > "$out" <<EOF
# Automatically generated
# duptype id depth size device inode priority name
DUPTYPE_FIRST_OCCURRENCE 7 1 10 1 1 1 ./docs/a.txt
DUPTYPE_WITHIN_SAME_TREE -7 1 10 1 2 1 ./docs/b.txt
# end of file
EOF'
    tb_without jdupes fdupes
    run dupes --fast .
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "10B x 2" ]]
    [[ ${lines[1]} == "  ./docs/b.txt" ]]
}

@test "--fast without a tool falls back to sha256sum" {
    tb_without jdupes fdupes rdfind
    run dupes --fast .
    [ "$status" -eq 0 ]
    [[ $output == *"--fast needs jdupes, fdupes or rdfind"* ]]
    [[ $output == *"2 groups"* ]]
}
