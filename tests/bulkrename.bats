#!/usr/bin/env bats
# Tests for bulkrename.

load helpers

setup() {
    tb_setup
    touch IMG_4410.jpg IMG_4411.jpg IMG_4412.jpg
}

@test "help prints usage and exits 0" {
    run bulkrename --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: bulkrename "* ]]
}

@test "bad usage exits 2" {
    run bulkrename
    [ "$status" -eq 2 ]
    run bulkrename 's/a/b/'
    [ "$status" -eq 2 ]
    [[ $output == *"name the files"* ]]
    run bulkrename 's/(/x/' IMG_4410.jpg
    [ "$status" -eq 2 ]
    [[ $output == *"sed could not read the expression"* ]]
    run bulkrename --lower --upper IMG_4410.jpg
    [ "$status" -eq 2 ]
    run bulkrename --width 0 IMG_4410.jpg
    [ "$status" -eq 2 ]
}

@test "a missing sed exits 3" {
    tb_without sed
    run bulkrename -y 's/IMG_/trip-/' IMG_4410.jpg
    [ "$status" -eq 3 ]
    [[ $output == "bulkrename: needs sed."* ]]
}

@test "shows the plan and renames with a sed expression" {
    run bulkrename -y 's/^IMG_/trip-/' IMG_*.jpg
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "IMG_4410.jpg -> trip-4410.jpg" ]
    [ "${lines[3]}" = "3 files renamed." ]
    [ -e trip-4410.jpg ] && [ -e trip-4412.jpg ] && [ ! -e IMG_4410.jpg ]
}

@test "asks first: no terminal exits 4, a no exits 5" {
    run bulkrename 's/^IMG_/trip-/' IMG_4410.jpg </dev/null
    [ "$status" -eq 4 ]
    tb_tty
    run bash -c "echo n | bulkrename 's/^IMG_/trip-/' IMG_4410.jpg"
    [ "$status" -eq 5 ]
    [ -e IMG_4410.jpg ]
    run bash -c "echo y | bulkrename 's/^IMG_/trip-/' IMG_4410.jpg"
    [ "$status" -eq 0 ]
    [ -e trip-4410.jpg ]
}

@test "-n shows the plan and changes nothing" {
    run bulkrename -n 's/IMG/img/' IMG_4410.jpg
    [ "$status" -eq 0 ]
    [[ $output == *"IMG_4410.jpg -> img_4410.jpg"* ]]
    [[ $output == *"Dry run"* ]]
    [ -e IMG_4410.jpg ]
}

@test "two files with the same new name are refused with exit 4" {
    touch report-v1.pdf report-v2.pdf
    run bulkrename -y 's/-v[0-9]+//' report-v1.pdf report-v2.pdf
    [ "$status" -eq 4 ]
    [[ $output == *"report-v1.pdf and report-v2.pdf would both become report.pdf"* ]]
    [[ $output == *"refused, nothing renamed."* ]]
    [ -e report-v1.pdf ] && [ -e report-v2.pdf ]
}

@test "an existing file is never overwritten" {
    echo keep > trip-4410.jpg
    run bulkrename -y 's/^IMG_/trip-/' IMG_4410.jpg IMG_4411.jpg
    [ "$status" -eq 4 ]
    [[ $output == *"which already exists"* ]]
    [ "$(cat trip-4410.jpg)" = keep ]
    [ -e IMG_4411.jpg ]
}

@test "a swap goes through temp names" {
    echo A > a
    echo B > b
    run bulkrename -y 's/^a$/X/; s/^b$/a/; s/^X$/b/' a b
    [ "$status" -eq 0 ]
    [ "$(cat a)" = B ]
    [ "$(cat b)" = A ]
    [ -z "$(ls -A | grep bulkrename)" ]
}

@test "a chain renames in a safe order" {
    echo 1 > f1
    echo 2 > f2
    echo 3 > f3
    run bulkrename -y 's/^f([0-9])$/echo \1/; s/^echo 1$/f2/; s/^echo 2$/f3/; s/^echo 3$/f4/' f1 f2 f3
    [ "$status" -eq 0 ]
    [ "$(cat f2)" = 1 ] && [ "$(cat f3)" = 2 ] && [ "$(cat f4)" = 3 ]
    [ ! -e f1 ]
}

@test "--lower, --spaces and --number" {
    touch 'My Photo.JPG' 'Other  Pic.JPG'
    run bulkrename -y --lower --spaces 'My Photo.JPG' 'Other  Pic.JPG'
    [ "$status" -eq 0 ]
    [ -e my-photo.jpg ] && [ -e other-pic.jpg ]
    run bulkrename -y --number --start 9 's/.*\./scan-#./' IMG_4410.jpg IMG_4411.jpg
    [ "$status" -eq 0 ]
    [ -e scan-09.jpg ] && [ -e scan-10.jpg ]
    run bulkrename -y --number --width 3 IMG_4412.jpg
    [ -e 001-IMG_4412.jpg ]
}

@test "-e edits the names in the editor" {
    cat > "$BATS_TEST_TMPDIR/ed" <<'SH'
#!/usr/bin/env bash
sed -i 's/IMG_4411/holiday/' "$1"
SH
    chmod +x "$BATS_TEST_TMPDIR/ed"
    export EDITOR=$BATS_TEST_TMPDIR/ed VISUAL=
    tb_tty
    run bash -c 'echo y | bulkrename -e IMG_*.jpg'
    [ "$status" -eq 0 ]
    [[ $output == *"IMG_4411.jpg -> holiday.jpg"* ]]
    [[ $output == *"2 names stay the same."* ]]
    [ -e holiday.jpg ] && [ -e IMG_4410.jpg ]
}

@test "-e refuses when a line goes missing" {
    printf '#!/usr/bin/env bash\nsed -i 1d "$1"\n' > "$BATS_TEST_TMPDIR/ed"
    chmod +x "$BATS_TEST_TMPDIR/ed"
    export EDITOR=$BATS_TEST_TMPDIR/ed VISUAL=
    tb_tty
    run bash -c 'echo y | bulkrename -e IMG_*.jpg'
    [ "$status" -eq 4 ]
    [[ $output == *"had 3 names and now has 2"* ]]
    [ -e IMG_4410.jpg ]
}

@test "--undo puts the names back, and a second --undo redoes" {
    run bulkrename -y 's/^IMG_/trip-/' IMG_*.jpg
    [ "$status" -eq 0 ]
    [ -s "$XDG_STATE_HOME/toolbelt/bulkrename-undo" ]
    run bulkrename -y --undo
    [ "$status" -eq 0 ]
    [[ $output == *"trip-4410.jpg -> IMG_4410.jpg"* ]]
    [ -e IMG_4410.jpg ] && [ ! -e trip-4410.jpg ]
    run bulkrename -y --undo
    [ -e trip-4410.jpg ]
}

@test "--undo with no record exits 1" {
    run bulkrename --undo
    [ "$status" -eq 1 ]
    [[ $output == *"nothing to undo"* ]]
}

@test "sed commands that write files are refused" {
    run bulkrename -y 's/IMG/x/w written.txt' IMG_4410.jpg
    [ "$status" -eq 2 ]
    [ ! -e written.txt ]
}

@test "without --sandbox only s and y commands run" {
    local real
    real=$(type -P sed)
    tb_stub sed "[ \"\$1\" = --sandbox ] && exit 1; exec $real \"\$@\""
    run bulkrename -y 's/IMG/x/w written.txt' IMG_4410.jpg
    [ "$status" -eq 2 ]
    [[ $output == *"this sed has no --sandbox, so only s and y commands"* ]]
    [ ! -e written.txt ]
    run bulkrename -y '1e touch ran' IMG_4410.jpg
    [ "$status" -eq 2 ]
    [ ! -e ran ]
    run bulkrename -y 's/IMG_/pic-/g; y/j/J/' IMG_4410.jpg
    [ "$status" -eq 0 ]
    [ -e pic-4410.Jpg ]
}

@test "files in a subfolder stay in that folder" {
    mkdir sub
    touch sub/IMG_1.jpg
    run bulkrename -y 's/IMG_/pic-/' sub/IMG_1.jpg
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "sub/IMG_1.jpg -> pic-1.jpg" ]]
    [ -e sub/pic-1.jpg ]
}

@test "a new name with a slash is refused" {
    run bulkrename -y 's|IMG_|a/|' IMG_4410.jpg
    [ "$status" -eq 4 ]
    [[ $output == *"cannot hold a /"* ]]
}

@test "nothing to change exits 0" {
    run bulkrename -y 's/zzz/y/' IMG_4410.jpg
    [ "$status" -eq 0 ]
    [[ $output == *"Nothing to rename"* ]]
}
