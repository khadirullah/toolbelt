#!/usr/bin/env bats
# Tests for share. qrencode and nmcli are stubs. The folder tests start share
# on a spare port for two seconds in the background and kill it by pid.

load helpers

setup() {
    tb_setup
    SHARE_PID=""
    # The stub records its options and the text it got on stdin.
    tb_stub qrencode '
echo "$*" > "$BATS_TEST_TMPDIR/qr.args"
cat > "$BATS_TEST_TMPDIR/qr.text"
prev=""
for a in "$@"; do
    if [[ $prev == -o ]]; then
        printf "\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\x01\x4a\0\0\x01\x4a" > "$a"
        exit 0
    fi
    prev=$a
done
echo "QR"'
}

teardown() {
    if [[ -n $SHARE_PID ]] && kill -0 "$SHARE_PID" 2>/dev/null; then
        kill "$SHARE_PID"
    fi
}

spare_port() {
    bash -c "source '$TB_REPO/lib/common.sh'; tb_free_port $((20000 + RANDOM % 20000))"
}

# Start share in the background, wait for its port, and save its pid.
start_share() {
    PORT=$(spare_port)
    nohup share -P "$PORT" "$@" > "$BATS_TEST_TMPDIR/share.out" 2>&1 &
    SHARE_PID=$!
    waitfor -q -t 5 -i 0.1 "127.0.0.1:$PORT" > /dev/null
}

wait_share() {
    wait "$SHARE_PID"
    SHARE_RC=$?
    SHARE_PID=""
}

@test "help prints usage and exits 0" {
    run share --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: share "* ]]
}

@test "bad usage exits 2" {
    run share -P 99999 .
    [ "$status" -eq 2 ]
    run share -t soon .
    [ "$status" -eq 2 ]
    run share -t 5m hello
    [ "$status" -eq 2 ]
    [[ $output == *"--port and --time only go with a folder or a file, and hello is neither"* ]]
    run share --png
    [ "$status" -eq 2 ]
}

@test "a missing qrencode exits 3" {
    rm "$BATS_TEST_TMPDIR/stubs/qrencode"
    tb_without qrencode
    run share https://example.com/
    [ "$status" -eq 3 ]
    [[ $output == "share: needs qrencode."* ]]
}

@test "text goes to qrencode on stdin, with pass-through options" {
    run share -v https://example.com/r/8Kd2 -- -l H
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "+ qrencode -t UTF8 -m 2 -l H https://example.com/r/8Kd2" ]
    [ "$(cat "$BATS_TEST_TMPDIR/qr.text")" = "https://example.com/r/8Kd2" ]
    [ "$(cat "$BATS_TEST_TMPDIR/qr.args")" = "-t UTF8 -m 2 -l H" ]
}

@test "text too long for a code exits 2" {
    head -c 3412 /dev/zero | tr '\0' a > notes.txt
    run share < notes.txt
    [ "$status" -eq 2 ]
    [ "${lines[0]}" = "share: 3,412 bytes is too long for one QR code, the limit is 2,953." ]
    [ "${lines[1]}" = "       Share it as a file instead: share FILE" ]
    [ ! -e "$BATS_TEST_TMPDIR/qr.args" ]
}

@test "--png writes a file and never overwrites one" {
    run share https://example.com/ --png link.png
    [ "$status" -eq 0 ]
    [ "$output" = "wrote link.png, 25 x 25 modules, 330 x 330 px" ]
    run share https://example.com/ --png link.png
    [[ $output == *"link.png exists, writing link-1.png instead"* ]]
    [ -f link-1.png ]
}

@test "--wifi builds a join code and never prints the password" {
    tb_stub nmcli '
case "$*" in
    "-t -f TYPE,NAME connection show --active") printf "802-3-ethernet:Wired\n802-11-wireless:Home-5G\n" ;;
    "-g 802-11-wireless.ssid connection show id Home-5G") echo "Home-5G" ;;
    "-g 802-11-wireless-security.key-mgmt connection show id Home-5G") echo "wpa-psk" ;;
    "-g 802-11-wireless.hidden connection show id Home-5G") echo "no" ;;
    "-s -g 802-11-wireless-security.psk connection show id Home-5G") echo "s3cret;pass" ;;
    *) exit 10 ;;
esac'
    run share -v --wifi
    [ "$status" -eq 0 ]
    [[ $output == *"Wi-Fi Home-5G, WPA2, password from NetworkManager"* ]]
    [[ $output != *s3cret* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/qr.text")" = 'WIFI:T:WPA;S:Home-5G;P:s3cret\;pass;;' ]
}

@test "--wifi without Wi-Fi exits 1" {
    tb_stub nmcli 'printf "802-3-ethernet:Wired\n"'
    run share --wifi
    [ "$status" -eq 1 ]
    [[ $output == *"not connected to any Wi-Fi"* ]]
}

@test "refuses to share /" {
    run share /
    [ "$status" -eq 4 ]
    [[ $output == *"refused, sharing / would put the whole system on the network"* ]]
}

@test "a folder with keys needs a yes" {
    mkdir -p pics/.ssh
    run share -t 1s pics < /dev/null
    [ "$status" -eq 4 ]
    [[ $output == *"look like keys or secrets"* ]]
    tb_tty
    run share -t 1s pics <<< "n"
    [ "$status" -eq 5 ]
}

@test "a folder is served, logged and stopped by --time" {
    mkdir -p trip/sub
    printf 'hello\n' > trip/a.txt
    printf 'xy\n' > "trip/sub/b c.txt"
    start_share -t 2s trip
    curl -s -o /dev/null "http://127.0.0.1:$PORT/a.txt"
    curl -s -o /dev/null "http://127.0.0.1:$PORT/sub/b%20c.txt"
    curl -s -o /dev/null "http://127.0.0.1:$PORT/nope"
    wait_share
    [ "$SHARE_RC" -eq 0 ]
    out=$(cat "$BATS_TEST_TMPDIR/share.out")
    [[ $out == *"sharing $PWD/trip, 2 files, 9 B"* ]]
    [[ $out == *"open http://"*":$PORT/ on any device on"* ]]
    [[ $out == *"  127.0.0.1  GET /a.txt               200  6 B"* ]]
    [[ $out == *"  127.0.0.1  GET /nope                404"* ]]
    [[ $out == *"share: stopped after 2s. 1 device, 2 files, 9 B sent."* ]]
    run port "$PORT"
    [ "$status" -eq 1 ]
}

@test "a single file is served alone" {
    mkdir d
    printf 'secret\n' > d/other.txt
    printf 'report\n' > d/report.pdf
    start_share -t 2s d/report.pdf
    run curl -s "http://127.0.0.1:$PORT/report.pdf"
    [ "$output" = "report" ]
    run curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/other.txt"
    [ "$output" = "404" ]
    wait_share
    [ "$SHARE_RC" -eq 0 ]
}

@test "a port in use exits 1" {
    mkdir d
    start_share -t 3s d
    run share -P "$PORT" d
    [ "$status" -eq 1 ]
    [[ $output == *"port $PORT is in use"* ]]
}
