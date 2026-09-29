#!/usr/bin/env bats
# Tests for lock. age is not installed here, so a stub stands in for it.
# The gpg path runs the real gpg, with the passphrase on a file descriptor.

load helpers

# A fake age: -e writes a header and the data, -d takes the header off.
fake_age() {
    tb_stub age 'echo "$*" >> "$BATS_TEST_TMPDIR/age.log"
mode=e in=""
while (( $# )); do
    case $1 in
        -d|--decrypt) mode=d ;;
        -r|-R|-i|-o) shift ;;
        --) shift; in=${1:-}; break ;;
        -*) ;;
        *) in=$1 ;;
    esac
    shift
done
[[ -n ${FAKE_AGE_FAIL:-} ]] && { echo "age: error: incorrect passphrase" >&2; exit 1; }
if [[ $mode == e ]]; then
    printf "age-encryption.org/v1\n-> scrypt c2FsdA 18\nYmFzZTY0\n--- mac\n"
    cat -- "${in:-/dev/stdin}"
else
    sed "1,/^---/d" -- "${in:-/dev/stdin}"
fi'
}

GPG_ARGS=(-- --batch --pinentry-mode loopback --passphrase-fd 3)

setup() {
    tb_setup
    printf 'DB_HOST=db.example.com\n' > secrets.env
    mkdir -p photos/2026
    head -c 2K /dev/urandom > photos/2026/a.jpg
    printf 'album\n' > photos/albums.txt
}

teardown() {
    if [[ -d $HOME/.gnupg ]]; then
        gpgconf --kill all 2>/dev/null
        gpgconf --remove-socketdir 2>/dev/null
    fi
    return 0
}

@test "help prints usage and exits 0" {
    run lock --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: lock "* ]]
}

@test "bad usage exits 2" {
    run lock
    [ "$status" -eq 2 ]
    run lock -o x.age secrets.env photos
    [ "$status" -eq 2 ]
    run lock -R nokeys.txt secrets.env
    [ "$status" -eq 2 ]
    run lock --nope secrets.env
    [ "$status" -eq 2 ]
}

@test "with neither age nor gpg it exits 3" {
    tb_without age gpg
    run lock secrets.env
    [ "$status" -eq 3 ]
    [[ $output == "lock: needs age or gpg. Install age with: "* ]]
}

@test "age locks a file with a passphrase and keeps the plain file" {
    fake_age
    run lock secrets.env
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "secrets.env -> secrets.env.age ("*")" ]]
    [[ $output == *"The plain file is still there. Once unlock works on the copy, remove it with: shred -u secrets.env"* ]]
    [ -f secrets.env ]
    [ "$(head -n 1 secrets.env.age)" = "age-encryption.org/v1" ]
    grep -q -- '^-e -p -- secrets.env$' "$BATS_TEST_TMPDIR/age.log"
}

@test "age locks a folder through tar" {
    fake_age
    run lock photos/
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "photos/ -> photos.tar.age ("*", 2 files, "*")" ]]
    sed '1,/^---/d' photos.tar.age | tar -t | grep -q '^photos/2026/a.jpg$'
    [ -d photos ]
}

@test "-r and -R lock to keys, and a .pub path counts as a key file" {
    fake_age
    printf 'ssh-ed25519 AAAAC3Nz me@laptop\n' > id.pub
    run lock -r age1qqqexample -r id.pub -a secrets.env
    [ "$status" -eq 0 ]
    grep -q -- '^-e -a -r age1qqqexample -R id.pub -- secrets.env$' "$BATS_TEST_TMPDIR/age.log"
    [[ $output == *"Only the private key for age1qqqexample, id.pub can open it."* ]]
}

@test "it never overwrites, and a failed run leaves nothing" {
    fake_age
    printf 'old\n' > secrets.env.age
    run lock secrets.env
    [ "$status" -eq 4 ]
    [[ $output == *"secrets.env.age exists. Use -o for another name"* ]]
    [ "$(cat secrets.env.age)" = "old" ]
    FAKE_AGE_FAIL=1 run lock -o other.age secrets.env
    [ "$status" -eq 1 ]
    [ ! -e other.age ]
    [ -z "$(ls -A | grep '^\.lock-')" ]
}

@test "a passphrase after -- is refused" {
    fake_age
    run lock secrets.env -- --passphrase hunter2
    [ "$status" -eq 4 ]
    [ ! -e secrets.env.age ]
}

@test "gpg is the fallback, and unlock opens the result" {
    tb_without age
    run lock -v secrets.env "${GPG_ARGS[@]}" 3<<<'correct horse'
    [ "$status" -eq 0 ]
    [[ $output == *"lock: age not found, using gpg"* ]]
    [[ $output == *"+ gpg --no-symkey-cache --symmetric --cipher-algo AES256 -o - --batch"* ]]
    [[ $output == *"secrets.env -> secrets.env.gpg ("* ]]
    mv secrets.env plain.env
    run unlock secrets.env.gpg "${GPG_ARGS[@]}" 3<<<'correct horse'
    [ "$status" -eq 0 ]
    cmp secrets.env plain.env
}

@test "gpg locks a folder, and unlock gives the folder back" {
    tb_without age
    run lock photos "${GPG_ARGS[@]}" 3<<<'pw'
    [ "$status" -eq 0 ]
    [ -s photos.tar.gpg ]
    mv photos orig
    run unlock photos.tar.gpg "${GPG_ARGS[@]}" 3<<<'pw'
    [ "$status" -eq 0 ]
    [[ ${lines[-1]} == "photos.tar.gpg -> photos/ ("*", 2 files, "*")" ]]
    diff -r orig photos
}

@test "an age key with only gpg exits 3" {
    tb_without age
    run lock -r age1qqqexample secrets.env
    [ "$status" -eq 3 ]
    [[ $output == *"only age can use it"* ]]
}

@test "--shred removes the plain copy after a checked round trip" {
    tb_without age
    printf 'pw\n' > "$BATS_TEST_TMPDIR/pass"
    local p=(-- --batch --pinentry-mode loopback --passphrase-file "$BATS_TEST_TMPDIR/pass")
    run lock --shred -y secrets.env "${p[@]}"
    [ "$status" -eq 0 ]
    [[ $output == *"secrets.env.gpg opens and matches secrets.env."* ]]
    [ ! -e secrets.env ]
    run lock --shred -y photos "${p[@]}"
    [ "$status" -eq 0 ]
    [ ! -e photos ]
    run unlock photos.tar.gpg "${p[@]}"
    [ -f photos/2026/a.jpg ]
}

@test "--shred asks, and without a terminal it keeps the file" {
    tb_without age
    printf 'pw\n' > "$BATS_TEST_TMPDIR/pass"
    run lock --shred secrets.env -- --batch --pinentry-mode loopback --passphrase-file "$BATS_TEST_TMPDIR/pass" </dev/null
    [ "$status" -eq 4 ]
    [ -f secrets.env ]
    [ -f secrets.env.gpg ]
}

@test "--shred with a key and no private key refuses" {
    fake_age
    run lock --shred -y -r age1qqqexample secrets.env
    [ "$status" -eq 4 ]
    [[ $output == *"no private key here"* ]]
    [ -f secrets.env ]
}
