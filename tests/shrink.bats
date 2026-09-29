#!/usr/bin/env bats
# Tests for shrink. PDFs go through the real Ghostscript. ImageMagick and
# ffmpeg are not installed here, so stubs stand in for them.

load helpers

# A fake magick: the output is the input size times the scale squared and
# the quality, so each setting gives a known size.
fake_magick() {
    tb_stub "${1:-magick}" 'echo "$*" >> "$BATS_TEST_TMPDIR/magick.log"
in=$1 q=100 s=100 prev=""
for a in "$@"; do
    case $prev in
        -quality) q=$a ;;
        -resize) [[ $a == *% ]] && s=${a%\%} ;;
    esac
    prev=$a
done
out=${!#}
n=$(stat -c %s "$in")
head -c $(( n * s * s / 10000 * q / 100 )) /dev/zero > "$out"'
}

# A fake ffprobe for a 2 second clip with sound, and a fake ffmpeg whose
# output is the bitrate times the length, times FAKE_OVER percent.
fake_ffmpeg() {
    tb_stub ffprobe 'case "$*" in
    *format=duration*) echo 2.000000 ;;
    *"-select_streams a"*) [[ -z ${FAKE_SILENT:-} ]] && echo 1 ;;
esac'
    tb_stub ffmpeg 'echo "$*" >> "$BATS_TEST_TMPDIR/ffmpeg.log"
out=${!#}
[[ $out == /dev/null ]] && exit 0
k=0 prev=""
for a in "$@"; do [[ $prev == -b:v ]] && k=${a%k}; prev=$a; done
head -c $(( (k + 96) * 250 * ${FAKE_OVER:-100} / 100 )) /dev/zero > "$out"'
}

# A small PDF with an uncompressed font, which Ghostscript can squeeze.
make_pdf() {
    gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -dCompressPages=false -dCompressFonts=false \
        -sOutputFile="$1" -c "/Times-Roman findfont 14 scalefont setfont 1 1 40 { 72 exch 18 mul moveto (The quick brown fox jumps over the lazy dog 0123456789) show } for showpage"
}

setup() {
    tb_setup
    head -c 100K /dev/zero > photo.jpg
    head -c 100K /dev/zero > shot.png
}

@test "help prints usage and exits 0" {
    run shrink --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: shrink "* ]]
}

@test "bad usage exits 2" {
    run shrink photo.jpg
    [ "$status" -eq 2 ]
    [[ $output == *"give a target size, such as: shrink photo.jpg 500K"* ]]
    run shrink -s huge photo.jpg
    [ "$status" -eq 2 ]
    run shrink -s 500 photo.jpg
    [ "$status" -eq 2 ]
    run shrink -s 50K -o x.jpg photo.jpg shot.png
    [ "$status" -eq 2 ]
    run shrink -w 0 photo.jpg 50K
    [ "$status" -eq 2 ]
}

@test "a missing tool exits 3, per file type" {
    tb_without magick convert ffmpeg ffprobe
    run shrink photo.jpg 50K
    [ "$status" -eq 3 ]
    [[ $output == "shrink: needs magick."* ]]
    head -c 20K /dev/zero > clip.mp4
    run shrink clip.mp4 10K
    [ "$status" -eq 3 ]
    [[ $output == "shrink: needs ffmpeg."* ]]
}

@test "a missing gs exits 3 for a PDF" {
    make_pdf scan.pdf
    tb_without gs
    run shrink scan.pdf 4K
    [ "$status" -eq 3 ]
    [[ $output == "shrink: needs gs."* ]]
}

@test "a PDF steps from /printer down and stops at the first that fits" {
    make_pdf scan.pdf
    run shrink scan.pdf 4K
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "shrink: scan.pdf: /printer gives "*", trying the next" ]]
    [[ ${lines[1]} == "scan.pdf -> scan-small.pdf ("*" -> 3."*"KB, /ebook, "*")" ]]
    [ -f scan.pdf ]
    [ "$(stat -c %s scan-small.pdf)" -le 4096 ]
}

@test "a PDF target out of reach writes nothing and exits 1" {
    make_pdf scan.pdf
    run shrink -v scan.pdf 1K
    [ "$status" -eq 1 ]
    [[ $output == *"+ gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/screen"* ]]
    [[ $output == *"shrink: wrote nothing. The smallest Ghostscript gets for scan.pdf is "* ]]
    [ ! -e scan-small.pdf ]
}

@test "a file that already fits is left alone" {
    run shrink photo.jpg 1M
    [ "$status" -eq 0 ]
    [ "$output" = "photo.jpg is already 100KB, which fits 1MB. Nothing written." ]
    [ ! -e photo-small.jpg ]
}

@test "an image keeps the best quality that fits" {
    fake_magick
    run shrink photo.jpg 60K
    [ "$status" -eq 0 ]
    [ "$output" = "photo.jpg -> photo-small.jpg (100KB -> 55KB, quality 55, 0.${output##*, 0.}" ]
    grep -q -- '^photo.jpg -auto-orient -strip -quality 55 ' "$BATS_TEST_TMPDIR/magick.log"
    [ "$(stat -c %s photo.jpg)" -eq 102400 ]
}

@test "an image steps down in scale when quality is not enough" {
    fake_magick
    run shrink -s 20K photo.jpg
    [ "$status" -eq 0 ]
    [[ $output == "photo.jpg -> photo-small.jpg (100KB -> 20KB, quality 65, 55% wide, "* ]]
}

@test "a PNG only changes scale, and the name never clashes" {
    fake_magick
    printf 'mine\n' > shot-small.png
    run shrink shot.png 40K
    [ "$status" -eq 0 ]
    [[ $output == "shot.png -> shot-small-1.png (100KB -> 30KB, 55% wide, "* ]]
    [ "$(cat shot-small.png)" = "mine" ]
    ! grep -q -- -quality "$BATS_TEST_TMPDIR/magick.log"
}

@test "convert works when magick is missing, and -w caps the width" {
    fake_magick convert
    tb_without magick
    run shrink -w 1920 photo.jpg 60K
    [ "$status" -eq 0 ]
    grep -q -- '-resize 1920x>' "$BATS_TEST_TMPDIR/magick.log"
}

@test "an image that cannot fit writes nothing" {
    fake_magick
    head -c 300K /dev/zero > big.jpg
    run shrink big.jpg 1K
    [ "$status" -eq 1 ]
    [[ $output == *"wrote nothing. The smallest ImageMagick gets for big.jpg is 1.3KB, at 10% wide"* ]]
    [ ! -e big-small.jpg ]
}

@test "-o names the copy and never overwrites" {
    fake_magick
    printf 'mine\n' > taken.jpg
    run shrink -o taken.jpg photo.jpg 60K
    [ "$status" -eq 4 ]
    [ "$(cat taken.jpg)" = "mine" ]
    run shrink -o small.jpg photo.jpg 60K
    [ "$status" -eq 0 ]
    [ -f small.jpg ]
    run shrink -o shot.webp shot.png 60K
    [ "$status" -eq 0 ]
    [ -f shot.webp ]
    grep -q -- '^shot.png -auto-orient -strip -quality .*/low.webp$' "$BATS_TEST_TMPDIR/magick.log"
}

@test "a video gets two passes at a bitrate from its length" {
    fake_ffmpeg
    head -c 150K /dev/zero > clip.mp4
    run shrink -v clip.mp4 100K -- -preset slow
    [ "$status" -eq 0 ]
    [[ $output == *"shrink: bitrate: 100KB over 2s, less 96k for sound, is 301k"* ]]
    [[ ${lines[-1]} == "clip.mp4 -> clip-small.mp4 (150KB -> 97KB, 301k, 2 passes, "* ]]
    grep -q -- '-c:v libx264 -preset medium -b:v 301k -pass 1 .* -preset slow -an -f null /dev/null' "$BATS_TEST_TMPDIR/ffmpeg.log"
    grep -q -- '-pass 2 .* -preset slow -c:a aac -b:a 96k -movflags +faststart ' "$BATS_TEST_TMPDIR/ffmpeg.log"
}

@test "a video that overshoots gets one more try" {
    fake_ffmpeg
    head -c 150K /dev/zero > clip.mp4
    FAKE_OVER=110 run shrink clip.mp4 100K
    [ "$status" -eq 0 ]
    [[ $output == *"trying again at 268k"* ]]
    [[ ${lines[-1]} == "clip.mp4 -> clip-small.mp4 (150KB -> 98KB, 268k, 2 passes, "* ]]
    FAKE_OVER=130 run shrink clip.mp4 100K
    [ "$status" -eq 1 ]
    [[ $output == *"wrote nothing"* ]]
}

@test "a webm stays webm, an avi becomes mp4, and a tiny target is refused" {
    fake_ffmpeg
    head -c 150K /dev/zero > clip.webm
    head -c 150K /dev/zero > old.avi
    FAKE_SILENT=1 run shrink -s 100K clip.webm old.avi
    [ "$status" -eq 0 ]
    [ -f clip-small.webm ]
    [ -f old-small.mp4 ]
    grep -q -- '-c:v libvpx-vp9' "$BATS_TEST_TMPDIR/ffmpeg.log"
    grep -q -- '-pass 2 .* -an ' "$BATS_TEST_TMPDIR/ffmpeg.log"
    run shrink clip.webm 10K
    [ "$status" -eq 1 ]
    [[ $output == *"is too small for 0:02 of video"* ]]
}

@test "a file of another kind exits 1" {
    printf 'text\n' > notes.txt
    head -c 2K /dev/zero >> notes.txt
    run shrink notes.txt 1K
    [ "$status" -eq 1 ]
    [[ $output == *"notes.txt is not an image, a video or a PDF"* ]]
}
