#!/usr/bin/env bats
# Tests for note. HOME is a temp folder, so notes land in a temp ~/notes.

load helpers

setup() {
    tb_setup
    unset NOTES_DIR VISUAL EDITOR
    TODAY=$(date +%F)
    N=$HOME/notes
}

@test "help prints usage and exits 0" {
    run note --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: note "* ]]
}

@test "bad usage exits 2" {
    run note -l x
    [ "$status" -eq 2 ]
    run note -l 0
    [ "$status" -eq 2 ]
    run note -l 3 -e
    [ "$status" -eq 2 ]
    run note -s foo some text
    [ "$status" -eq 2 ]
    run note --nope
    [ "$status" -eq 2 ]
}

@test "adds a timed line to today's file" {
    run note kind needs 4 GB for 3 nodes
    [ "$status" -eq 0 ]
    [ "$output" = "note: added to ~/notes/$TODAY.md" ]
    [ "$(sed -n 1p "$N/$TODAY.md")" = "# $TODAY" ]
    [[ $(sed -n 3p "$N/$TODAY.md") =~ ^-\ [0-9]{2}:[0-9]{2}\ kind\ needs\ 4\ GB\ for\ 3\ nodes$ ]]
    note second line
    [ "$(grep -c '^- ' "$N/$TODAY.md")" -eq 2 ]
}

@test "prints today's notes, or says there are none" {
    run note
    [ "$status" -eq 0 ]
    [[ $output == "note: no notes yet today"* ]]
    note hello
    run note
    [ "${lines[0]}" = "# $TODAY" ]
    [[ ${lines[1]} == *" hello" ]]
}

@test "a line break in the text stays on one line" {
    note "$(printf 'one\ntwo')"
    [[ $(tail -1 "$N/$TODAY.md") == *" one two" ]]
}

@test "text after -- may start with a dash" {
    note -- -5 degrees outside
    [[ $(tail -1 "$N/$TODAY.md") == *" -5 degrees outside" ]]
}

@test "-l prints the last days, oldest first" {
    mkdir -p "$N"
    old=$(date -d '-10 days' +%F)
    y=$(date -d '-1 day' +%F)
    printf '# %s\n\n- 09:00 old\n' "$old" > "$N/$old.md"
    printf '# %s\n\n- 09:00 yesterday\n' "$y" > "$N/$y.md"
    note today
    run note -l 2
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "# $y" ]
    [[ $output != *old* ]]
    [[ ${lines[2]} == "# $TODAY" ]]
    run note -l 30
    [ "${lines[0]}" = "# $old" ]
}

@test "-s searches every note, newest first" {
    mkdir -p "$N"
    printf '# 2026-09-17\n\n- 16:40 grafana CrashLoop, data dir not writable\n' > "$N/2026-09-17.md"
    printf '# 2026-09-18\n\n- 11:02 api crashloop was a missing DATABASE_URL\n- 12:00 api fixed\n- 13:00 crashloop again\n' > "$N/2026-09-18.md"
    run note -s crashloop
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "2026-09-18 13:00 crashloop again" ]
    [ "${lines[1]}" = "2026-09-18 11:02 api crashloop was a missing DATABASE_URL" ]
    [ "${#lines[@]}" -eq 2 ]
    run note -s crashloop -- -i
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[2]}" = "2026-09-17 16:40 grafana CrashLoop, data dir not writable" ]
}

@test "-s with no match exits 1" {
    note hello
    run note -s nothing-here
    [ "$status" -eq 1 ]
    [ "$output" = "note: nothing matches nothing-here" ]
}

@test "-d and NOTES_DIR move the folder" {
    run note -d "$BATS_TEST_TMPDIR/elsewhere" hi
    [ -f "$BATS_TEST_TMPDIR/elsewhere/$TODAY.md" ]
    NOTES_DIR=$BATS_TEST_TMPDIR/env run note hi
    [ -f "$BATS_TEST_TMPDIR/env/$TODAY.md" ]
    [ ! -e "$N" ]
}

@test "-e opens today's file in the editor" {
    tb_stub myeditor 'echo "editing $1" > "$BATS_TEST_TMPDIR/edited"'
    EDITOR=myeditor run note -e
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/edited")" = "editing $N/$TODAY.md" ]
    [ "$(head -1 "$N/$TODAY.md")" = "# $TODAY" ]
}

@test "-e with no editor at all exits 1" {
    tb_without nano vi
    run note -e
    [ "$status" -eq 1 ]
    [[ $output == *"no editor found, set EDITOR"* ]]
}

@test "a missing grep exits 3 for a search" {
    note hello
    tb_without grep
    run note -s hello
    [ "$status" -eq 3 ]
    [[ $output == "note: needs grep."* ]]
}
