#!/usr/bin/env bats
# Tests for unlock. age is not installed here, so a stub stands in for it.
# The gpg path runs the real gpg, with the passphrase on a file descriptor.

load helpers

# A fake age: -d takes the header off, and FAKE_AGE_FAIL makes it fail.
fake_age() {
    tb_stub age 'echo "$*" >> "$BATS_TEST_TMPDIR/age.log"
in=""
while (( $# )); do
    case $1 in
        -i|-o) shift ;;
        --) shift; in=${1:-}; break ;;
        -*) ;;
        *) in=$1 ;;
    esac
    shift
done
[[ -n ${FAKE_AGE_FAIL:-} ]] && { echo "age: error: incorrect passphrase" >&2; exit 1; }
sed "1,/^---/d" -- "${in:-/dev/stdin}"'
}

# An age file of the given stanza type holding stdin.
age_file() {
    { printf 'age-encryption.org/v1\n-> %s abc\nZGF0YQ\n--- mac\n' "$1"; cat; } > "$2"
}

GPG_ARGS=(-- --batch --pinentry-mode loopback --passphrase-fd 3)

setup() {
    tb_setup
    printf 'DB_HOST=db.example.com\n' | age_file "scrypt c2FsdA 18" secrets.env.age
}

teardown() {
    if [[ -d $HOME/.gnupg ]]; then
        gpgconf --kill all 2>/dev/null
        gpgconf --remove-socketdir 2>/dev/null
    fi
    return 0
}

@test "help prints usage and exits 0" {
    run unlock --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: unlock "* ]]
}

@test "bad usage exits 2" {
    run unlock
    [ "$status" -eq 2 ]
    run unlock -o x a.age b.age
    [ "$status" -eq 2 ]
    run unlock -i nokey.txt secrets.env.age
    [ "$status" -eq 2 ]
    run unlock --nope secrets.env.age
    [ "$status" -eq 2 ]
}

@test "a missing age exits 3 for an age file" {
    tb_without age
    run unlock secrets.env.age
    [ "$status" -eq 3 ]
    [[ $output == "unlock: needs age."* ]]
}

@test "unlocks an age file beside itself and keeps it" {
    fake_age
    run unlock secrets.env.age
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "secrets.env.age -> secrets.env (23B, "*")" ]]
    [ "$(cat secrets.env)" = "DB_HOST=db.example.com" ]
    [ -f secrets.env.age ]
    grep -q -- '^-d -- secrets.env.age$' "$BATS_TEST_TMPDIR/age.log"
}

@test "it never overwrites" {
    fake_age
    printf 'mine\n' > secrets.env
    run unlock secrets.env.age
    [ "$status" -eq 4 ]
    [ "$output" = "unlock: secrets.env exists. Use -o for another name, or --cat" ]
    [ "$(cat secrets.env)" = "mine" ]
    run unlock -o copy.env secrets.env.age
    [ "$status" -eq 0 ]
    [ "$(cat copy.env)" = "DB_HOST=db.example.com" ]
}

@test "--cat prints and writes nothing" {
    fake_age
    run unlock --cat secrets.env.age
    [ "$status" -eq 0 ]
    [ "$output" = "DB_HOST=db.example.com" ]
    [ ! -e secrets.env ]
}

@test "a wrong passphrase exits 1 and writes nothing" {
    fake_age
    FAKE_AGE_FAIL=1 run unlock secrets.env.age
    [ "$status" -eq 1 ]
    [[ $output == *"could not decrypt secrets.env.age, wrong passphrase or key. Nothing was written"* ]]
    [ ! -e secrets.env ]
    [ -z "$(ls -A | grep '^\.unlock-')" ]
}

@test "a .tar.age comes out as its folder" {
    fake_age
    mkdir -p src/photos/2026
    printf 'a\n' > src/photos/2026/a.jpg
    printf 'b\n' > src/photos/albums.txt
    tar -cf - -C src photos | age_file "scrypt c2FsdA 18" photos.tar.age
    run unlock photos.tar.age
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "photos.tar.age -> photos/ ("*", 2 files, "*")" ]]
    diff -r src/photos photos
    run unlock photos.tar.age
    [ "$status" -eq 4 ]
}

@test "a file locked to a key uses the usual key, or -i" {
    fake_age
    printf 'hi\n' | age_file "ssh-ed25519 abc" note.txt.age
    run unlock note.txt.age
    [ "$status" -eq 1 ]
    [[ $output == *"note.txt.age is locked to a key"*"Name it with -i"* ]]
    mkdir -p "$HOME/.ssh"
    printf 'key\n' > "$HOME/.ssh/id_ed25519"
    run unlock note.txt.age
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "unlock: using ~/.ssh/id_ed25519" ]]
    grep -q -- "-d -i $HOME/.ssh/id_ed25519 -- note.txt.age" "$BATS_TEST_TMPDIR/age.log"
    printf 'k\n' > work.key
    run unlock -i work.key -o other.txt note.txt.age
    [ "$status" -eq 0 ]
    grep -q -- "-d -i work.key -- note.txt.age" "$BATS_TEST_TMPDIR/age.log"
}

@test "reads a gpg file by its header, armoured or not" {
    printf 'plain text\n' > notes.txt
    gpg --batch --pinentry-mode loopback --passphrase-fd 3 --symmetric -o notes.bin notes.txt 3<<<'pw'
    gpg --batch --pinentry-mode loopback --passphrase-fd 3 --symmetric --armor -o notes.txt.asc notes.txt 3<<<'pw'
    rm notes.txt
    run unlock -o notes.txt notes.bin "${GPG_ARGS[@]}" 3<<<'pw'
    [ "$status" -eq 0 ]
    [ "$(cat notes.txt)" = "plain text" ]
    rm notes.txt
    run unlock notes.txt.asc "${GPG_ARGS[@]}" 3<<<'pw'
    [ "$status" -eq 0 ]
    [ "$(cat notes.txt)" = "plain text" ]
    run unlock --cat notes.bin "${GPG_ARGS[@]}" 3<<<'wrong'
    [ "$status" -eq 1 ]
}

@test "a file that is neither exits 1, and a bare name needs -o" {
    printf 'just text\n' > plain.age
    run unlock plain.age
    [ "$status" -eq 1 ]
    [ "$output" = "unlock: plain.age is not an age or gpg file" ]
    fake_age
    printf 'x\n' | age_file "scrypt s 18" blob
    run unlock blob
    [ "$status" -eq 2 ]
    [[ $output == *"has no .age or .gpg ending, so name the output with -o"* ]]
}
