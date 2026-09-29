#!/usr/bin/env bats
# Tests for togif. ffmpeg is not installed here, so stubs stand in for it.

load helpers

# A fake ffprobe for a clip FAKE_LEN seconds long and 1920 wide, and a fake
# ffmpeg that logs its arguments and writes a few bytes to its output.
fake_ffmpeg() {
    tb_stub ffprobe 'case "$*" in
    *format=duration*) echo "${FAKE_LEN:-30.5}" ;;
    *stream=width*) echo "${FAKE_W:-1920}" ;;
esac'
    tb_stub ffmpeg 'echo "$*" >> "$BATS_TEST_TMPDIR/ffmpeg.log"
[[ -n ${FAKE_FAIL:-} ]] && exit 1
head -c 3072 /dev/zero > "${!#}"'
}

setup() {
    tb_setup
    head -c 4096 /dev/urandom > demo.mp4
}

@test "help prints usage and exits 0" {
    run togif --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: togif "* ]]
}

@test "bad usage exits 2" {
    run togif
    [ "$status" -eq 2 ]
    run togif -s soon demo.mp4
    [ "$status" -eq 2 ]
    run togif -d 4 -t 10 demo.mp4
    [ "$status" -eq 2 ]
    run togif -f 0 demo.mp4
    [ "$status" -eq 2 ]
    run togif -w 2 demo.mp4
    [ "$status" -eq 2 ]
    run togif a.mp4 b.mp4
    [ "$status" -eq 2 ]
}

@test "a missing ffmpeg exits 3" {
    tb_without ffmpeg ffprobe
    run togif -d 4 demo.mp4
    [ "$status" -eq 3 ]
    [[ $output == "togif: needs ffmpeg."* ]]
}

@test "makes a GIF with a palette in two runs" {
    fake_ffmpeg
    run togif -s 0:12 -d 4 demo.mp4
    [ "$status" -eq 0 ]
    [[ $output == "demo.mp4 0:12 to 0:16 -> demo.gif (3KB, 48 frames, 480px, "* ]]
    [ -f demo.gif ]
    run cat "$BATS_TEST_TMPDIR/ffmpeg.log"
    [[ ${lines[0]} == *"-ss 0:12 -t 4 -i demo.mp4 -vf fps=12,scale='min(480,iw)':-1:flags=lanczos,palettegen "*/palette.png ]]
    [[ ${lines[1]} == *"-lavfi fps=12,scale='min(480,iw)':-1:flags=lanczos[x];[x][1:v]paletteuse -loop -1 "*/out.gif ]]
}

@test "-w, --fps, --loop and -t" {
    fake_ffmpeg
    run togif -s 5 -t 7.5 -w 320 --fps 10 --loop demo.mp4
    [ "$status" -eq 0 ]
    [[ $output == "demo.mp4 0:05 to 0:07.5 -> demo.gif (3KB, 25 frames, 320px, "* ]]
    grep -q -- "-ss 5 -t 2.5 " "$BATS_TEST_TMPDIR/ffmpeg.log"
    grep -q -- "fps=10,scale='min(320,iw)'" "$BATS_TEST_TMPDIR/ffmpeg.log"
    grep -q -- "-loop 0 " "$BATS_TEST_TMPDIR/ffmpeg.log"
    run togif -s 5 -t 5 demo.mp4
    [ "$status" -eq 2 ]
}

@test "a clip over 60 seconds needs -y" {
    fake_ffmpeg
    FAKE_LEN=582 run togif demo.mp4
    [ "$status" -eq 4 ]
    [ "${lines[0]}" = "togif: demo.mp4 from 0:00 is 9:42 long, over the 60s limit" ]
    [ "${lines[1]}" = "togif: refused. Pick a part with -s and -d, or add -y" ]
    [ ! -e demo.gif ]
    run togif -d 90 demo.mp4
    [ "$status" -eq 0 ]
    FAKE_LEN=582 run togif -y demo.mp4
    [ "$status" -eq 0 ]
    [[ $output == *"demo.mp4 0:00 to 9:42 -> demo-1.gif"* ]]
}

@test "the whole clip when no length is given, and a narrow clip keeps its width" {
    fake_ffmpeg
    FAKE_W=200 run togif -s 10 demo.mp4
    [ "$status" -eq 0 ]
    [[ $output == "demo.mp4 0:10 to 0:30.5 -> demo.gif (3KB, 246 frames, 200px, "* ]]
    FAKE_LEN=8 run togif -s 10 demo.mp4
    [ "$status" -eq 1 ]
    [[ $output == *"past the end"* ]]
}

@test "never overwrites, and -o names the GIF" {
    fake_ffmpeg
    printf 'mine\n' > demo.gif
    run togif -d 2 demo.mp4
    [ "$status" -eq 0 ]
    [ "$(cat demo.gif)" = "mine" ]
    [ -f demo-1.gif ]
    run togif -d 2 -o demo.gif demo.mp4
    [ "$status" -eq 4 ]
    run togif -d 2 -o clip.gif demo.mp4
    [ "$status" -eq 0 ]
    [ -f clip.gif ]
}

@test "options after -- reach both runs, and a failed run writes nothing" {
    fake_ffmpeg
    run togif -d 2 demo.mp4 -- -stats
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '-stats' "$BATS_TEST_TMPDIR/ffmpeg.log")" -eq 2 ]
    rm demo.gif
    FAKE_FAIL=1 run togif -d 2 demo.mp4
    [ "$status" -eq 1 ]
    [ ! -e demo.gif ]
}
