#!/usr/bin/env bats
# Tests for bak.

load helpers

setup() {
    tb_setup
    printf 'listen 80;\n' > app.conf
}

stamp_re='^app\.conf\.[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}(-[0-9]+)?\.bak$'

@test "help prints usage and exits 0" {
    run bak --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: bak "* ]]
    [[ $output == *"Exit: 0 ok"* ]]
}

@test "bad usage exits 2" {
    run bak
    [ "$status" -eq 2 ]
    run bak --nope app.conf
    [ "$status" -eq 2 ]
    run bak --prune many app.conf
    [ "$status" -eq 2 ]
    run bak --prune 0 app.conf
    [ "$status" -eq 2 ]
    run bak -l -r app.conf
    [ "$status" -eq 2 ]
    [[ $output == *"only one of"* ]]
}

@test "a missing cp exits 3" {
    tb_without cp
    run bak app.conf
    [ "$status" -eq 3 ]
    [[ $output == "bak: needs cp."* ]]
}

@test "a missing diff exits 3 for -d" {
    cp app.conf app.conf.2026-01-01-100000.bak
    tb_without diff
    run bak -d app.conf
    [ "$status" -eq 3 ]
    [[ $output == "bak: needs diff."* ]]
}

@test "makes a dated copy that keeps mode and times" {
    chmod 640 app.conf
    touch -d '2026-01-02 03:04:05' app.conf
    run bak app.conf
    [ "$status" -eq 0 ]
    copy=${output##* -> }
    [[ $copy =~ $stamp_re ]]
    [ "$(stat -c '%a %Y' "$copy")" = "$(stat -c '%a %Y' app.conf)" ]
    cmp app.conf "$copy"
}

@test "two copies in the same second never overwrite" {
    run bak app.conf
    first=${output##* -> }
    run bak app.conf
    second=${output##* -> }
    [ "$first" != "$second" ]
    [ "$(ls app.conf.*.bak | wc -l)" -eq 2 ]
}

@test "-l lists newest first with age and size" {
    cp app.conf app.conf.2026-01-01-100000.bak
    cp app.conf app.conf.2026-03-01-100000.bak
    touch other.2026-03-01-100000.bak app.conf.notes.bak
    run bak -l app.conf
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [[ ${lines[0]} == *"11B  app.conf.2026-03-01-100000.bak" ]]
    [[ ${lines[1]} == *"ago"*"app.conf.2026-01-01-100000.bak" ]]
}

@test "-l with no copies exits 1" {
    run bak -l app.conf
    [ "$status" -eq 1 ]
    [[ $output == *"no copies of app.conf"* ]]
}

@test "-r refuses without a terminal and a no exits 5" {
    printf 'old\n' > app.conf.2026-01-01-100000.bak
    run bak -r app.conf </dev/null
    [ "$status" -eq 4 ]
    tb_tty
    run bash -c 'echo n | bak -r app.conf'
    [ "$status" -eq 5 ]
    [ "$(cat app.conf)" = "listen 80;" ]
}

@test "-r saves the current file, then restores the newest copy" {
    printf 'old\n' > app.conf.2026-01-01-100000.bak
    printf 'newer\n' > app.conf.2026-02-01-100000.bak
    tb_tty
    run bash -c 'echo y | bak -r app.conf'
    [ "$status" -eq 0 ]
    [[ $output == *"saved the current app.conf as app.conf."* ]]
    [[ $output == *"app.conf.2026-02-01-100000.bak -> app.conf"* ]]
    [ "$(cat app.conf)" = newer ]
    # The saved copy is now the newest, so -r again undoes the restore.
    run bak -y -r app.conf
    [ "$(cat app.conf)" = "listen 80;" ]
}

@test "-r writes through a symlink instead of replacing it" {
    mv app.conf real.conf
    ln -s real.conf app.conf
    printf 'old\n' > app.conf.2026-01-01-100000.bak
    run bak -y -r app.conf
    [ "$status" -eq 0 ]
    [ -L app.conf ]
    [ "$(cat real.conf)" = old ]
}

@test "-d shows a diff, and says so when nothing changed" {
    cp app.conf app.conf.2026-01-01-100000.bak
    run bak -d app.conf
    [ "$status" -eq 0 ]
    [[ $output == *"No changes since app.conf.2026-01-01-100000.bak"* ]]
    printf 'listen 443;\n' > app.conf
    run bak -d app.conf
    [ "$status" -eq 0 ]
    [[ $output == *"-listen 80;"* ]]
    [[ $output == *"+listen 443;"* ]]
}

@test "--dir keeps copies in another folder" {
    run bak --dir store app.conf
    [ "$status" -eq 0 ]
    [ -d store ]
    [ "$(ls store | wc -l)" -eq 1 ]
    [ "$(ls app.conf.* 2>/dev/null | wc -l)" -eq 0 ]
    run bak -l --dir store app.conf
    [[ $output == *"store/app.conf."* ]]
}

@test "--prune keeps the newest N and trashes the rest" {
    for m in 01 02 03 04; do cp app.conf "app.conf.2026-$m-01-100000.bak"; done
    run bak --prune 2 app.conf </dev/null
    [ "$status" -eq 4 ]
    run bak -y --prune 2 app.conf
    [ "$status" -eq 0 ]
    [[ $output == *"2 old copies of app.conf in the trash, 2 kept."* ]]
    [ -e app.conf.2026-04-01-100000.bak ]
    [ -e app.conf.2026-03-01-100000.bak ]
    [ ! -e app.conf.2026-01-01-100000.bak ]
    [ "$(tb_trash_list | wc -l)" -eq 2 ]
}

@test "folders copy whole and restore without stray files" {
    mkdir site
    printf 'a\n' > site/index.html
    run bak site/
    [ "$status" -eq 0 ]
    printf 'b\n' > site/new.html
    run bak -y -r site
    [ "$status" -eq 0 ]
    [ -e site/index.html ]
    [ ! -e site/new.html ]
    # The folder as it was before the restore is kept as a copy.
    ls site.*.bak/new.html
}

@test "-v shows the cp command, -q only the result" {
    run bak -v app.conf
    [[ ${lines[0]} == "+ cp -a -H -- app.conf app.conf."* ]]
    run bak -q app.conf
    [ "${#lines[@]}" -eq 1 ]
}

@test "a missing file fails with exit 1" {
    run bak nothere.conf
    [ "$status" -eq 1 ]
    [[ $output == *"nothere.conf: no such file or folder"* ]]
}
