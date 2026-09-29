#!/usr/bin/env bats
# Tests for checksum.

load helpers

setup() {
    tb_setup
    printf 'hello\n' > a.txt
    printf 'world\n' > 'b c.txt'
    sha_a=$(sha256sum < a.txt | cut -d' ' -f1)
}

@test "help prints usage and exits 0" {
    run checksum -h
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: checksum "* ]]
}

@test "bad usage exits 2" {
    run checksum
    [ "$status" -eq 2 ]
    run checksum -a sha9 a.txt
    [ "$status" -eq 2 ]
    [[ $output == *"unknown algorithm sha9"* ]]
    run checksum a.txt abcdef012345
    [ "$status" -eq 2 ]
    [[ $output == *"12 hex digits"* ]]
    run checksum -c SUMS a.txt
    [ "$status" -eq 2 ]
}

@test "a missing hash tool exits 3" {
    tb_without sha256sum
    run checksum a.txt
    [ "$status" -eq 3 ]
    [[ $output == "checksum: needs sha256sum."* ]]
}

@test "b3 needs b3sum, and uses it when it is there" {
    tb_without b3sum
    run checksum -a b3 a.txt
    [ "$status" -eq 3 ]
    [[ $output == "checksum: needs b3sum."* ]]
}

@test "b3 runs b3sum with the file on stdin" {
    tb_stub b3sum 'cat >/dev/null; echo "b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3  -"'
    run checksum -a b3 a.txt
    [ "$status" -eq 0 ]
    [ "$output" = "b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3  a.txt" ]
}

@test "hashes files in the sha256sum format" {
    run checksum a.txt 'b c.txt'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$sha_a  a.txt" ]
    [ "${lines[1]}" = "$(sha256sum < 'b c.txt' | cut -d' ' -f1)  b c.txt" ]
}

@test "-a picks the algorithm" {
    run checksum -a md5 a.txt
    [ "$output" = "$(md5sum < a.txt | cut -d' ' -f1)  a.txt" ]
    run checksum -a sha1 a.txt
    [ "$output" = "$(sha1sum < a.txt | cut -d' ' -f1)  a.txt" ]
    run checksum -a sha512 a.txt
    [ "$output" = "$(sha512sum < a.txt | cut -d' ' -f1)  a.txt" ]
    # BusyBox, on Alpine, has no b2sum.
    command -v b2sum >/dev/null || return 0
    run checksum --algo=b2 a.txt
    [ "$output" = "$(b2sum < a.txt | cut -d' ' -f1)  a.txt" ]
}

@test "a pasted hash matches in any case, and the length picks the algorithm" {
    run checksum a.txt "$(echo "$sha_a" | tr a-f A-F)"
    [ "$status" -eq 0 ]
    [ "$output" = "OK       a.txt  (sha256)" ]
    run checksum a.txt "$(md5sum < a.txt | cut -d' ' -f1)"
    [ "$output" = "OK       a.txt  (md5)" ]
    run checksum a.txt "sha1:$(sha1sum < a.txt | cut -d' ' -f1)"
    [ "$output" = "OK       a.txt  (sha1)" ]
}

@test "a 128 digit hash tries sha512, then b2" {
    tb_needs b2sum
    run checksum -v a.txt "$(b2sum < a.txt | cut -d' ' -f1)"
    [ "$status" -eq 0 ]
    [[ $output == *"no match with sha512, trying b2"* ]]
    [[ $output == *"OK       a.txt  (b2)" ]]
}

@test "a wrong hash prints FAILED with both hashes and exits 1" {
    bad=$(printf '0%.0s' {1..64})
    run checksum a.txt "$bad"
    [ "$status" -eq 1 ]
    [[ $output == *"FAILED   a.txt  (sha256)"* ]]
    [[ $output == *"want $bad"* ]]
    [[ $output == *"got  $sha_a"* ]]
}

@test "-c checks every file and counts the result" {
    sha256sum a.txt 'b c.txt' > SHA256SUMS
    run checksum -c SHA256SUMS
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "OK       a.txt" ]
    [ "${lines[1]}" = "OK       b c.txt" ]
    [ "${lines[2]}" = "2 OK, 0 failed" ]
}

@test "-c reports FAILED and MISSING and exits 1" {
    sha256sum a.txt 'b c.txt' > SHA256SUMS
    echo "$sha_a  gone.iso" >> SHA256SUMS
    echo changed > 'b c.txt'
    run checksum -c SHA256SUMS
    [ "$status" -eq 1 ]
    [[ $output == *"FAILED   b c.txt"* ]]
    [[ $output == *"MISSING  gone.iso"* ]]
    [[ $output == *"1 OK, 1 failed, 1 missing" ]]
}

@test "--ignore-missing skips files that are not here" {
    sha256sum a.txt > SHA256SUMS
    echo "$sha_a  gone.iso" >> SHA256SUMS
    run checksum --ignore-missing -c SHA256SUMS
    [ "$status" -eq 0 ]
    [[ $output == *"1 OK, 0 failed, 1 not here and skipped" ]]
}

@test "-c reads names relative to the SUMS file and BSD lines" {
    mkdir dl
    cp a.txt dl/
    # The BSD line sha512sum --tag writes. BusyBox sha512sum has no --tag.
    printf 'SHA512 (a.txt) = %s\n' "$(sha512sum < a.txt | cut -d' ' -f1)" > dl/Fedora-CHECKSUM
    run checksum -c dl/Fedora-CHECKSUM
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "OK       a.txt" ]
}

@test "finds a SHA256SUMS file beside a download" {
    sha256sum a.txt > SHA256SUMS
    run checksum a.txt
    [ "$status" -eq 0 ]
    [ "$output" = "OK       a.txt  (sha256, SHA256SUMS)" ]
    echo tampered > a.txt
    run checksum a.txt
    [ "$status" -eq 1 ]
    [[ $output == *"FAILED   a.txt  (sha256, SHA256SUMS)"* ]]
}

@test "finds a name.sha256 file with a bare hash" {
    echo "$sha_a" > a.txt.sha256
    run checksum a.txt
    [ "$output" = "OK       a.txt  (sha256, a.txt.sha256)" ]
    run checksum --no-sums a.txt
    [ "$output" = "$sha_a  a.txt" ]
}

@test "a folder or a missing file exits 1" {
    mkdir d
    run checksum d
    [ "$status" -eq 1 ]
    [[ $output == *"d is a folder"* ]]
    run checksum nothere.iso
    [ "$status" -eq 1 ]
}
