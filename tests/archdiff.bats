#!/usr/bin/env bats
# Tests for archdiff. Two tiny chart folders, packed in each test.

load helpers

setup() {
    tb_setup
    mkdir -p v1/app/templates v2/app/templates
    printf 'a: 1\nb: 2\n' > v1/app/values.yaml
    printf 'a: 1\nb: 3\n' > v2/app/values.yaml
    echo dep > v1/app/templates/dep.yaml
    cp v1/app/templates/dep.yaml v2/app/templates/dep.yaml
    echo old > v1/app/NOTES.txt
    echo hpa > v2/app/templates/hpa.yaml
    printf '\0\1\2' > v1/app/logo.bin
    printf '\0\1\3' > v2/app/logo.bin
}

tgz_pair() {
    (cd v1 && tar -czf ../a.tgz app)
    (cd v2 && tar -cf - app | zstd -q -o ../b.tar.zst)
}

# ---------------------------------------------------------------- help and usage

@test "help prints the layout and exits 0" {
    run archdiff -h
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: archdiff [options] old new [-- diff options]" ]
    [[ $output == *"List what changed between two archives."* ]]
    [[ $output == *"Needs: "* ]]
    [[ $output == *"Exit: 0 the same"* ]]
}

@test "help fits in 80 columns" {
    run archdiff -h
    while IFS= read -r line; do
        [ "${#line}" -le 80 ]
    done <<<"$output"
}

@test "bad usage exits 2" {
    tgz_pair
    run archdiff a.tgz
    [ "$status" -eq 2 ]
    [[ $output == *"name two archives, the old one first"* ]]
    run archdiff a.tgz b.tar.zst c.tgz
    [ "$status" -eq 2 ]
    run archdiff --nope a.tgz b.tar.zst
    [ "$status" -eq 2 ]
    run archdiff a.tgz b.tar.zst -- -U 0
    [ "$status" -eq 2 ]
    [[ $output == *"only with -c"* ]]
}

@test "a missing archive exits 2" {
    tgz_pair
    run archdiff a.tgz nope.tgz
    [ "$status" -eq 2 ]
    [[ $output == *"nope.tgz: no such file"* ]]
}

@test "a file that is not an archive exits 2" {
    tgz_pair
    echo hi > plain.txt
    run archdiff plain.txt a.tgz
    [ "$status" -eq 2 ]
    [[ $output == *"plain.txt: not an archive archdiff can read"* ]]
}

@test "a corrupt archive exits 2" {
    tgz_pair
    head -c 100 a.tgz > bad.tgz
    run archdiff bad.tgz a.tgz
    [ "$status" -eq 2 ]
    [[ $output == *"bad.tgz: could not read the archive"* ]]
}

# ---------------------------------------------------------------- comparing

@test "the same archive twice has no differences and exits 0" {
    tgz_pair
    run archdiff a.tgz a.tgz
    [ "$status" -eq 0 ]
    [ "$output" = "no differences, 4 files" ]
}

@test "tgz against tar.zst lists added, removed and changed files" {
    tgz_pair
    run archdiff a.tgz b.tar.zst
    [ "$status" -eq 1 ]
    [[ ${lines[0]} == "+ app/templates/hpa.yaml "*"4B" ]]
    [[ ${lines[1]} == "- app/NOTES.txt "*"4B" ]]
    [[ ${lines[2]} == "~ app/logo.bin "*"3B -> 3B" ]]
    [[ ${lines[3]} == "~ app/values.yaml "*"10B -> 10B" ]]
    [ "${lines[4]}" = "1 added, 1 removed, 2 changed, 1 the same" ]
}

@test "different top folders are lined up" {
    mv v1/app v1/app-1.4
    mv v2/app v2/app-1.5
    (cd v1 && tar -czf ../a.tgz app-1.4)
    (cd v2 && tar -czf ../b.tgz app-1.5)
    run archdiff a.tgz b.tgz
    [ "$status" -eq 1 ]
    [[ $output == *"+ templates/hpa.yaml"* ]]
    [[ $output == *"1 added, 1 removed, 2 changed, 1 the same"* ]]
}

@test "zip against 7z" {
    (cd v1 && zip -qr ../a.zip app)
    (cd v2 && 7z a -bso0 -bsp0 ../b.7z app)
    run archdiff a.zip b.7z
    [ "$status" -eq 1 ]
    [[ $output == *"+ app/templates/hpa.yaml"* ]]
    [[ ${lines[-1]} == "1 added, 1 removed, 2 changed, 1 the same" ]]
}

@test "zip against tar with the same files has no differences" {
    (cd v1 && zip -qr ../a.zip app && tar -cf ../a.tar app)
    run archdiff a.zip a.tar
    [ "$status" -eq 0 ]
    [ "$output" = "no differences, 4 files" ]
}

@test "a renamed tgz is found by its first bytes" {
    tgz_pair
    cp a.tgz renamed.bin
    run archdiff renamed.bin a.tgz
    [ "$status" -eq 0 ]
    [ "$output" = "no differences, 4 files" ]
}

@test "two single compressed files compare as one file each" {
    printf 'one\ntwo\n' > f.txt
    gzip -c f.txt > f.txt.gz
    printf 'one\nthree\n' | zstd -q -c > f.txt.zst
    run archdiff f.txt.gz f.txt.zst
    [ "$status" -eq 1 ]
    [[ ${lines[0]} == "~ f.txt "*"8B -> 10B" ]]
}

# ---------------------------------------------------------------- filters and content

@test "--only keeps the matching files" {
    tgz_pair
    run archdiff --only '*.yaml' a.tgz b.tar.zst
    [ "$status" -eq 1 ]
    [[ $output != *"NOTES.txt"* ]]
    [[ $output != *"logo.bin"* ]]
    [ "${lines[-1]}" = "1 added, 0 removed, 1 changed, 1 the same" ]
}

@test "-x matches a folder name anywhere in the path" {
    tgz_pair
    run archdiff -x templates a.tgz b.tar.zst
    [ "$status" -eq 1 ]
    [[ $output != *"templates"* ]]
    [ "${lines[-1]}" = "0 added, 1 removed, 2 changed, 0 the same" ]
}

@test "--only that leaves the same files exits 0" {
    tgz_pair
    run archdiff --only dep.yaml a.tgz b.tar.zst
    [ "$status" -eq 0 ]
    [ "$output" = "no differences, 1 file" ]
}

@test "-c prints a labelled unified diff for text files" {
    tgz_pair
    run archdiff -c a.tgz b.tar.zst
    [ "$status" -eq 1 ]
    [[ $output == *"--- a.tgz/app/values.yaml"* ]]
    [[ $output == *"+++ b.tar.zst/app/values.yaml"* ]]
    [[ $output == *"-b: 2"* ]]
    [[ $output == *"+b: 3"* ]]
}

@test "-c says binary files differ for binary files" {
    tgz_pair
    run archdiff -c --only logo.bin a.tgz b.tar.zst
    [ "$status" -eq 1 ]
    [[ $output == *"binary files differ"* ]]
}

@test "-c passes options after -- to diff" {
    tgz_pair
    run archdiff -c --only values.yaml a.tgz b.tar.zst -- -U 0
    [ "$status" -eq 1 ]
    [[ $output == *"@@ -2 +2 @@"* ]]
    [[ $output != *" a: 1"* ]]
}

@test "-c works on zip members with odd names" {
    mkdir -p z1 z2
    echo one > 'z1/a [1].txt'
    echo two > 'z2/a [1].txt'
    (cd z1 && zip -q ../a.zip 'a [1].txt')
    (cd z2 && zip -q ../b.zip 'a [1].txt')
    run archdiff -c a.zip b.zip
    [ "$status" -eq 1 ]
    [[ $output == *"+two"* ]]
}

@test "-q prints only the summary" {
    tgz_pair
    run archdiff -q a.tgz b.tar.zst
    [ "$status" -eq 1 ]
    [ "$output" = "1 added, 1 removed, 2 changed, 1 the same" ]
}

@test "-v shows the real commands" {
    tgz_pair
    run archdiff -v a.tgz b.tar.zst
    [ "$status" -eq 1 ]
    [[ $output == *"+ zstd -dc -q < b.tar.zst | tar -xf - --to-command="* ]]
}

@test "the temp folder for -c is removed" {
    tgz_pair
    export TMPDIR=$BATS_TEST_TMPDIR/tmp
    mkdir -p "$TMPDIR"
    run archdiff -c a.tgz b.tar.zst
    [ "$status" -eq 1 ]
    [ -z "$(ls -A "$TMPDIR")" ]
    [ -z "$(ls -A . | grep -v -e '^v[12]$' -e '^a.tgz$' -e '^b.tar.zst$')" ]
}

# ---------------------------------------------------------------- missing tools

@test "a missing 7z exits 3 with an install line" {
    (cd v1 && 7z a -bso0 -bsp0 ../a.7z app)
    tb_without 7z
    run archdiff a.7z a.7z
    [ "$status" -eq 3 ]
    [[ $output == *"7z"* ]]
}

@test "a missing zstd exits 3" {
    tgz_pair
    tb_without zstd
    run archdiff a.tgz b.tar.zst
    [ "$status" -eq 3 ]
    [[ $output == *"zstd"* ]]
}

@test "a missing sha256sum exits 3" {
    tgz_pair
    tb_without sha256sum
    run archdiff a.tgz b.tar.zst
    [ "$status" -eq 3 ]
    [[ $output == *"sha256sum"* ]]
}
