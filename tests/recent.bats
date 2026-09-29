#!/usr/bin/env bats
# Tests for recent.

load helpers

setup() {
    tb_setup
    mkdir -p src tests .git node_modules/pkg .cache
    printf 'print(1)\n' > src/app.py
    printf 'x\n' > tests/test_app.py
    head -c 3072 /dev/zero > README.md
    printf 'old\n' > old.txt
    printf 'ref\n' > .git/HEAD
    printf 'js\n' > node_modules/pkg/index.js
    printf 'c\n' > .cache/blob
    printf 'h\n' > .hidden
    touch -d "$(tb_ago 300)" src/app.py .git/HEAD node_modules/pkg/index.js .cache/blob .hidden
    touch -d "$(tb_ago 1200)" tests/test_app.py
    touch -d "$(tb_ago 2400)" README.md
    touch -d "$(tb_ago 259200)" old.txt
    # Folders changed when the files went in. Set them apart from the files.
    touch -d "$(tb_ago 7200)" src tests
}

@test "help prints usage and exits 0" {
    run recent --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: recent "* ]]
}

@test "bad usage exits 2" {
    run recent 2x
    [ "$status" -eq 2 ]
    [[ $output == *"recent: 2x is not a time. Use 10m, 2h, 3d, 1w or a date"* ]]
    run recent -n 0
    [ "$status" -eq 2 ]
    run recent --type x
    [ "$status" -eq 2 ]
    run recent --since nonsense-words
    [ "$status" -eq 2 ]
    run recent --nope
    [ "$status" -eq 2 ]
}

@test "a missing find exits 3" {
    tb_without find
    run recent
    [ "$status" -eq 3 ]
    [[ $output == "recent: needs find."* ]]
}

@test "lists the last hour newest first, with age, size and path" {
    run recent
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 4 ]
    [[ ${lines[0]} =~ ^([0-9]{2}-[0-9]{2}\ )?[0-9]{2}:[0-9]{2}\ +5m\ ago\ +9B\ +src/app.py$ ]]
    [[ ${lines[1]} == *"20m ago"*"tests/test_app.py" ]]
    [[ ${lines[2]} == *"40m ago      3KB  README.md" ]]
    [ "${lines[3]}" = "3 files changed in the last 1h" ]
}

@test "skips hidden folders, .git, node_modules and the trash by default" {
    mkdir -p "$XDG_DATA_HOME/Trash/files" "$XDG_DATA_HOME/notes"
    printf 'gone\n' > "$XDG_DATA_HOME/Trash/files/deleted.txt"
    printf 'kept\n' > "$XDG_DATA_HOME/notes/kept.txt"
    run recent
    [[ $output != *HEAD* ]]
    [[ $output != *index.js* ]]
    [[ $output != *blob* ]]
    [[ $output != *.hidden* ]]
    run recent 1h "$XDG_DATA_HOME"
    [[ $output == *kept.txt* ]]
    [[ $output != *deleted.txt* ]]
}

@test "-a includes hidden files and folders" {
    run recent -a
    [ "$status" -eq 0 ]
    [[ $output == *".git/HEAD"* ]]
    [[ $output == *"node_modules/pkg/index.js"* ]]
    [[ $output == *".cache/blob"* ]]
    [[ $output == *".hidden"* ]]
    [ "${lines[-1]}" = "7 files changed in the last 1h" ]
}

@test "any window, as a word or with --since" {
    run recent 4d
    [ "${lines[-1]}" = "4 files changed in the last 4d" ]
    [[ ${lines[3]} =~ ^[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}\ +3d\ ago.*old.txt$ ]]
    run recent 30m
    [ "${lines[-1]}" = "2 files changed in the last 30m" ]
    run recent --since "$(date -d "$(tb_ago 172800)" +%F)"
    [[ ${lines[-1]} == "3 files changed since "* ]]
    run recent 10s
    [ "$output" = "No files changed in the last 10s." ]
}

@test "-n shows fewer and says so" {
    run recent -n 2
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[2]}" = "2 of 3 files changed in the last 1h, use -n for more" ]
}

@test "--type d lists folders" {
    run recent 3h --type d
    [ "$status" -eq 0 ]
    [[ $output == *"  src"* ]]
    [[ $output == *"  tests"* ]]
    [[ ${lines[-1]} == "2 folders changed in the last 3h" ]]
}

@test "--only and -x pick names" {
    run recent --only '*.py'
    [ "${lines[-1]}" = "2 files changed in the last 1h" ]
    run recent -x tests -x '*.md'
    [ "${lines[-1]}" = "1 file changed in the last 1h" ]
}

@test "a path after the time, and a folder named like a time" {
    run recent 1h src
    [ "${lines[0]##* }" = "src/app.py" ]
    [ "${lines[-1]}" = "1 file changed in the last 1h" ]
    mkdir 2d
    printf 'x\n' > 2d/file
    run recent 2d
    [[ $output == *"2d/file"* ]]
}

@test "stays on one filesystem, and tests after -- go to find" {
    run recent -v
    [[ $output == *"+ find -P . -mindepth 1 -xdev"* ]]
    run recent -- -size +1k
    [ "${#lines[@]}" -eq 2 ]
    [[ ${lines[0]} == *README.md ]]
}

@test "find actions after -- are refused" {
    run recent -- -delete
    [ "$status" -eq 4 ]
    [ -e src/app.py ]
}

@test "a missing path exits 1" {
    run recent 1h nothere
    [ "$status" -eq 1 ]
}
