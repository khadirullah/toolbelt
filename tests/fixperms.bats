#!/usr/bin/env bats
# Tests for fixperms.

load helpers

setup() {
    tb_setup
    umask 022
    mkdir -p site/css site/bin
    printf '<html>\n' > site/index.html
    printf 'body{}\n' > site/css/a.css
    printf '#!/bin/sh\n' > site/deploy.sh
    chmod 777 site site/css
    chmod 666 site/index.html
    chmod 700 site/bin
    chmod 775 site/deploy.sh
}

mode() { stat -c %a "$1"; }

@test "help prints usage and exits 0" {
    run fixperms -h
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: fixperms "* ]]
}

@test "bad usage exits 2" {
    run fixperms
    [ "$status" -eq 2 ]
    run fixperms --dir-mode 7777 site
    [ "$status" -eq 2 ]
    [[ $output == *"--dir-mode needs a mode such as 755"* ]]
    run fixperms --file-mode abc site
    [ "$status" -eq 2 ]
    run fixperms --bogus site
    [ "$status" -eq 2 ]
}

@test "a missing find exits 3" {
    tb_without find
    run fixperms -y site
    [ "$status" -eq 3 ]
    [[ $output == "fixperms: needs find."* ]]
}

@test "previews the counts, then sets 755 and 644, scripts keep x" {
    run fixperms -y site
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "site has 3 folders and 3 files." ]
    [[ ${lines[1]} == "  folders to 755"*"3  now 777, 700" ]]
    [[ ${lines[2]} == "  files to 644"*"1  now 666" ]]
    [[ ${lines[3]} == "  files to 755"*"1  deploy.sh" ]]
    [ "${lines[4]}" = "5 changed." ]
    [ "$(mode site)" = 755 ] && [ "$(mode site/bin)" = 755 ]
    [ "$(mode site/index.html)" = 644 ] && [ "$(mode site/css/a.css)" = 644 ]
    [ "$(mode site/deploy.sh)" = 755 ]
}

@test "asks first: no terminal exits 4, a no exits 5" {
    run fixperms site </dev/null
    [ "$status" -eq 4 ]
    [ "$(mode site)" = 777 ]
    tb_tty
    run bash -c 'echo n | fixperms site'
    [ "$status" -eq 5 ]
    [ "$(mode site)" = 777 ]
}

@test "-n shows the preview and changes nothing" {
    run fixperms -n site
    [ "$status" -eq 0 ]
    [[ $output == *"Dry run, nothing changed."* ]]
    [ "$(mode site)" = 777 ]
}

@test "a second run has nothing to change" {
    fixperms -y site
    run fixperms site
    [ "$status" -eq 0 ]
    [[ $output == *"Nothing to change"* ]]
}

@test "--private gives 700 and 600" {
    run fixperms -y --private site
    [ "$status" -eq 0 ]
    [ "$(mode site)" = 700 ]
    [ "$(mode site/index.html)" = 600 ]
    [ "$(mode site/deploy.sh)" = 700 ]
}

@test "--dirs and --files change one kind only" {
    run fixperms -y --dirs site
    [ "$(mode site)" = 755 ]
    [ "$(mode site/index.html)" = 666 ]
    run fixperms -y --files site/css
    [ "$(mode site/css/a.css)" = 644 ]
}

@test "--no-exec and custom modes" {
    run fixperms -y --no-exec site
    [ "$(mode site/deploy.sh)" = 644 ]
    run fixperms -y --dir-mode 750 --file-mode 640 site
    [ "$(mode site)" = 750 ]
    [ "$(mode site/index.html)" = 640 ]
}

@test "-x leaves matching names alone" {
    mkdir site/.git
    chmod 777 site/.git
    run fixperms -y -x .git site
    [ "$status" -eq 0 ]
    [ "$(mode site/.git)" = 777 ]
}

@test "setuid, setgid and sticky bits are left alone" {
    mkdir site/shared
    chmod 2777 site/shared
    run fixperms -y site
    [[ $output == *"left alone"*"1  setuid, setgid or sticky bit"* ]]
    [ "$(mode site/shared)" = 2777 ]
}

@test "system folders and home are refused with exit 4" {
    # -n, so a broken check could never change a real system folder.
    for p in / /etc /usr /bin /boot /etc/ /usr/bin; do
        # Containers often have no /boot.
        [ -e "$p" ] || continue
        run fixperms -n "$p"
        [ "$status" -eq 4 ]
        [[ $output == *"system folder"* ]]
    done
    run fixperms -n "$HOME"
    [ "$status" -eq 4 ]
    [[ $output == *"your home folder"* ]]
}

@test "--force allows the home folder" {
    mkdir -p "$HOME/docs"
    chmod 777 "$HOME/docs"
    run fixperms -y --force "$HOME"
    [ "$status" -eq 0 ]
    [ "$(mode "$HOME/docs")" = 755 ]
}

@test "symlinks are never followed" {
    ln -s site link
    run fixperms -y link
    [ "$status" -eq 4 ]
    [[ $output == *"link is a symlink"* ]]
    printf 'x\n' > outside.txt
    chmod 666 outside.txt
    ln -s ../outside.txt site/out
    run fixperms -y site
    [ "$status" -eq 0 ]
    [ "$(mode outside.txt)" = 666 ]
}

@test "-v shows each find command" {
    run fixperms -v -y site
    [[ $output == *"+ find -P site -type d '!' -perm /7000 '!' -perm 755 -exec chmod 755 '{}' +"* ]]
}

@test "a missing path exits 1" {
    run fixperms nothere
    [ "$status" -eq 1 ]
}
