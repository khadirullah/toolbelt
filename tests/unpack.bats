#!/usr/bin/env bats
# Tests for unpack. Every fixture is a few KB, built in the test.

load helpers

setup() {
    tb_setup
    mkdir -p backup/sub
    seq 1 500 > backup/nums.txt
    echo hi > backup/sub/a.yaml
    echo x > backup/b.yaml
}

# A tar of backup/, then backup/ is gone so unpack has to make it.
mk_tar() { tar -cf backup.tar backup && rm -rf backup; }

# Pack backup/ as a tar squeezed by one tool, into backup.tar.EXT.
# Usage: mk_tar_with xz xz, mk_tar_with lz4 'lz4 -q'
mk_tar_with() {
    local ext=$1 tool=$2
    command -v "${tool%% *}" >/dev/null || skip "${tool%% *} is not installed"
    tar -cf - backup | $tool -c > "backup.tar.$ext"
    rm -rf backup
}

# A .Z file made with a small LZW encoder, since compress is rarely installed.
lzw() {
    python3 -c '
import sys
data = sys.stdin.buffer.read()
d = {bytes([i]): i for i in range(256)}
nxt, w, codes = 257, b"", []
for c in data:
    wc = w + bytes([c])
    if wc in d:
        w = wc
    else:
        codes.append(d[w])
        if nxt < 65536:
            d[wc] = nxt; nxt += 1
        w = bytes([c])
if w:
    codes.append(d[w])
bits, width, seg = [], 9, 0
for i, code in enumerate(codes):
    free = min(257 + max(0, i - 1), 65536)
    while width < 16 and free > (1 << width) - 1:
        bits += [0] * ((-(len(bits) - seg)) % (width * 8))
        seg = len(bits); width += 1
    bits += [(code >> b) & 1 for b in range(width)]
bits += [0] * (-len(bits) % 8)
out = bytearray(b"\x1f\x9d\x90")
for j in range(0, len(bits), 8):
    out.append(sum(bits[j + b] << b for b in range(8)))
sys.stdout.buffer.write(out)'
}

need_7z() { command -v 7z >/dev/null || skip "7z is not installed"; }

# Checks that backup/ came back whole.
restored() {
    [ -f backup/nums.txt ]
    [ "$(tail -1 backup/nums.txt)" = 500 ]
    [ "$(cat backup/sub/a.yaml)" = hi ]
    [ "$(cat backup/b.yaml)" = x ]
}

# A podman or docker stand-in. It maps the -v mounts back to host paths and
# runs the inner command on the host, so no container ever starts.
stub_engine() {
    tb_stub "$1" '
printf "%s\n" "$@" > "$BATS_TEST_TMPDIR/engine.args"
shift
maps=()
while (( $# )); do
    case $1 in
        -v) maps+=("$2"); shift 2 ;;
        -e) export "${2?}"; shift 2 ;;
        --security-opt|--user) shift 2 ;;
        -*) shift ;;
        *) break ;;
    esac
done
shift
args=()
for a in "$@"; do
    for m in "${maps[@]}"; do
        IFS=: read -r h c _ <<<"$m"
        if [[ $a == "$c" || $a == "$c"/* ]]; then a=$h${a#"$c"}; fi
    done
    args+=("$a")
done
exec "${args[@]}"'
}

# ---------------------------------------------------------------- help and usage

@test "help prints the layout and exits 0" {
    run unpack -h
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: unpack [options] archive|url ... [-- tool options]" ]
    [[ $output == *"Unpack any archive, from a file or a URL."* ]]
    [[ $output == *"Pass-through:"* ]]
    [[ $output == *"Examples:"* ]]
    [[ $output == *"Needs: "* ]]
    [[ $output == *"Exit: 0 ok, 1 failed"* ]]
}

@test "help fits in 80 columns" {
    run unpack --help
    while IFS= read -r line; do
        [ "${#line}" -le 80 ]
    done <<<"$output"
}

@test "no archive is bad usage" {
    run unpack
    [ "$status" -eq 2 ]
    [[ $output == *"no archive given"* ]]
}

@test "an unknown option is bad usage" {
    mk_tar
    run unpack --nope backup.tar
    [ "$status" -eq 2 ]
    [[ $output == *"unknown option --nope"* ]]
}

@test "two actions at once are bad usage" {
    mk_tar
    run unpack -l -t backup.tar
    [ "$status" -eq 2 ]
    run unpack --cat backup/b.yaml -l backup.tar
    [ "$status" -eq 2 ]
    run unpack --history --undo
    [ "$status" -eq 2 ]
}

@test "--rm with -k is bad usage" {
    mk_tar
    run unpack --rm -k backup.tar
    [ "$status" -eq 2 ]
}

@test "--undo and --history take no archive" {
    mk_tar
    run unpack --undo backup.tar
    [ "$status" -eq 2 ]
    run unpack --history backup.tar
    [ "$status" -eq 2 ]
}

@test "--cat reads one archive only" {
    mk_tar
    cp backup.tar two.tar
    run unpack --cat backup/b.yaml backup.tar two.tar
    [ "$status" -eq 2 ]
}

@test "--sandbox works only for a normal unpack" {
    mk_tar
    run unpack --sandbox -l backup.tar
    [ "$status" -eq 2 ]
}

@test "a missing archive fails with its name" {
    run unpack nope.tar.gz
    [ "$status" -eq 1 ]
    [[ $output == *"nope.tar.gz: no such file"* ]]
}

@test "a folder is not an archive" {
    run unpack backup
    [ "$status" -eq 1 ]
    [[ $output == *"backup: is a folder, not an archive"* ]]
}

# ---------------------------------------------------------------- missing tools

@test "a missing decompressor exits 3 with the install line" {
    command -v zstd >/dev/null || skip "zstd is not installed"
    mk_tar_with zst 'zstd -q'
    tb_without zstd
    run unpack backup.tar.zst
    [ "$status" -eq 3 ]
    [[ $output == *"unpack: needs zstd. Install it with: "* ]]
    [ ! -e backup ]
}

@test "a missing 7z exits 3" {
    need_7z
    7z a -bd -bso0 backup.7z backup
    rm -rf backup
    tb_without 7z 7zz 7za
    run unpack backup.7z
    [ "$status" -eq 3 ]
    [[ $output == *"needs 7z"* ]]
}

@test "a URL without curl exits 3" {
    mk_tar
    tb_without curl
    run unpack "file://$PWD/backup.tar"
    [ "$status" -eq 3 ]
    [[ $output == *"needs curl"* ]]
}

# ---------------------------------------------------------------- formats

@test "tar" {
    mk_tar
    run unpack backup.tar
    [ "$status" -eq 0 ]
    [[ $output == "backup.tar -> backup/ ("*", 3 files, "* ]]
    restored
    [ -f backup.tar ]
}

@test "tar.gz" {
    tar -czf backup.tar.gz backup && rm -rf backup
    run unpack backup.tar.gz
    [ "$status" -eq 0 ]
    restored
}

@test "tgz" {
    tar -czf backup.tgz backup && rm -rf backup
    run unpack backup.tgz
    [ "$status" -eq 0 ]
    restored
}

@test "tar.bz2" {
    mk_tar_with bz2 bzip2
    run unpack backup.tar.bz2
    [ "$status" -eq 0 ]
    restored
}

@test "tar.xz" {
    mk_tar_with xz xz
    run unpack backup.tar.xz
    [ "$status" -eq 0 ]
    restored
}

@test "tar.lzma" {
    mk_tar_with lzma 'xz --format=lzma'
    run unpack backup.tar.lzma
    [ "$status" -eq 0 ]
    restored
}

@test "tar.zst" {
    mk_tar_with zst 'zstd -q'
    run unpack backup.tar.zst
    [ "$status" -eq 0 ]
    restored
}

@test "tar.lz4" {
    mk_tar_with lz4 'lz4 -q'
    run unpack backup.tar.lz4
    [ "$status" -eq 0 ]
    restored
}

@test "tar.lz" {
    mk_tar_with lz lzip
    run unpack backup.tar.lz
    [ "$status" -eq 0 ]
    restored
}

@test "tar.lzo" {
    mk_tar_with lzo lzop
    run unpack backup.tar.lzo
    [ "$status" -eq 0 ]
    restored
}

@test "tar.Z" {
    command -v python3 >/dev/null || skip "python3 builds the .Z fixture"
    tar -cf - backup | lzw > backup.tar.Z
    rm -rf backup
    run unpack backup.tar.Z
    [ "$status" -eq 0 ]
    restored
}

@test "tar.br, with brotli stubbed" {
    # brotli is not installed here. The stub decodes base64, which stands in
    # for the brotli stream and keeps file(1) from calling it a tar.
    tar -cf - backup | base64 > backup.tar.br
    rm -rf backup
    tb_stub brotli '[[ " $* " == *" -dc "* || " $* " == *" -d "* ]] || exit 1; exec base64 -d'
    run unpack backup.tar.br
    [ "$status" -eq 0 ]
    restored
}

@test "a single gz file becomes the file" {
    seq 1 50 > notes.txt
    gzip notes.txt
    run unpack notes.txt.gz
    [ "$status" -eq 0 ]
    [[ $output == "notes.txt.gz -> notes.txt ("* ]]
    [ "$(tail -1 notes.txt)" = 50 ]
}

@test "a single xz, zst and Z file" {
    seq 1 50 > a.txt
    xz -k a.txt
    run unpack -k a.txt.xz
    [ "$status" -eq 0 ]
    [ -f a-1.txt ]
    if command -v zstd >/dev/null; then
        zstd -q a.txt -o b.txt.zst
        run unpack -k b.txt.zst
        [ "$status" -eq 0 ]
        [ "$(tail -1 b.txt)" = 50 ]
    fi
    lzw < a.txt > c.txt.Z
    run unpack -k c.txt.Z
    [ "$status" -eq 0 ]
    cmp a.txt c.txt
}

@test "zip" {
    command -v zip >/dev/null || skip "zip is not installed"
    zip -q -r backup.zip backup && rm -rf backup
    run unpack backup.zip
    [ "$status" -eq 0 ]
    restored
}

@test "jar and whl open as zip" {
    command -v zip >/dev/null || skip "zip is not installed"
    zip -q -r app.jar backup
    zip -q -r tool-1.0-py3-none-any.whl backup
    rm -rf backup
    run unpack -d app.jar
    [ "$status" -eq 0 ]
    [ -f app/backup/nums.txt ]
    run unpack -k tool-1.0-py3-none-any.whl
    [ "$status" -eq 0 ]
    restored
}

@test "7z" {
    need_7z
    7z a -bd -bso0 backup.7z backup && rm -rf backup
    run unpack backup.7z
    [ "$status" -eq 0 ]
    restored
}

@test "deb, built with dpkg-deb" {
    command -v dpkg-deb >/dev/null || skip "dpkg-deb is not installed"
    mkdir -p pkg/DEBIAN pkg/usr/share/demo
    printf 'Package: demo\nVersion: 1.0\nArchitecture: all\nMaintainer: a <a@example.com>\nDescription: demo\n' \
        > pkg/DEBIAN/control
    echo data > pkg/usr/share/demo/readme
    dpkg-deb -b --root-owner-group pkg demo_1.0_all.deb >/dev/null
    rm -rf pkg
    run unpack demo_1.0_all.deb
    [ "$status" -eq 0 ]
    [ "$(cat demo_1.0_all/usr/share/demo/readme)" = data ]
}

@test "cpio" {
    find backup | cpio -o -H newc --quiet > backup.cpio
    rm -rf backup
    run unpack backup.cpio
    [ "$status" -eq 0 ]
    restored
}

@test "rpm, with rpm2cpio stubbed" {
    # No rpm builder here. The fixture has a real rpm lead, and the stub
    # prints a cpio payload the way rpm2cpio does.
    mkdir -p payload/usr/bin
    echo tool > payload/usr/bin/demo
    (cd payload && find . | cpio -o -H newc --quiet > "$BATS_TEST_TMPDIR/payload.cpio")
    rm -rf payload
    { printf '\xed\xab\xee\xdb\x03\x00\x00\x00\x00\x01demo-1.0-1'; head -c 86 /dev/zero; } > demo-1.0-1.x86_64.rpm
    tb_stub rpm2cpio 'cat "$BATS_TEST_TMPDIR/payload.cpio"'
    run unpack demo-1.0-1.x86_64.rpm
    [ "$status" -eq 0 ]
    [ "$(cat demo-1.0-1.x86_64/usr/bin/demo)" = tool ]
}

@test "rar is not built here" {
    skip "no free tool makes rar archives. Part names are tested below"
}

@test "iso, when genisoimage is installed" {
    command -v genisoimage >/dev/null || skip "genisoimage is not installed"
    command -v 7z >/dev/null || command -v bsdtar >/dev/null || skip "no iso reader"
    genisoimage -quiet -R -o disk.iso backup 2>/dev/null
    rm -rf backup
    run unpack disk.iso
    [ "$status" -eq 0 ]
    [ "$(tail -1 disk/nums.txt)" = 500 ]
}

# An initramfs image: a plain cpio, then a gzip cpio, like a real one.
mk_initrd() {
    mkdir -p early/kernel/x86 main/etc
    echo ucode > early/kernel/x86/ucode.bin
    echo init > main/init
    echo host > main/etc/hostname
    (cd early && find . | cpio -o -H newc --quiet) > initrd.img-6.1.0
    (cd main && find . | cpio -o -H newc --quiet | gzip) >> initrd.img-6.1.0
    rm -rf early main
}

@test "initramfs, with unmkinitramfs" {
    command -v unmkinitramfs >/dev/null || skip "unmkinitramfs is not installed"
    mk_initrd
    run unpack initrd.img-6.1.0
    [ "$status" -eq 0 ]
    [ "$(cat initrd-6.1.0/main/init)" = init ]
    [ "$(cat initrd-6.1.0/early/kernel/x86/ucode.bin)" = ucode ]
}

@test "initramfs, with the cpio fallback" {
    mk_initrd
    tb_without unmkinitramfs
    run unpack -v initrd.img-6.1.0
    [ "$status" -eq 0 ]
    [[ $output == *"2 layers"* ]]
    [ "$(cat initrd-6.1.0/main/etc/hostname)" = host ]
    [ "$(cat initrd-6.1.0/early/kernel/x86/ucode.bin)" = ucode ]
}

@test "the content wins over a wrong name" {
    tar -czf backup.bin backup && rm -rf backup
    run unpack -v backup.bin
    [ "$status" -eq 0 ]
    [[ $output == *"tar.gz"* ]]
    restored
}

@test "a file that cannot look inside compressed data still finds the tar" {
    # file 5.46 and later in a sandbox, as on Arch, cannot fork a decompressor.
    local real
    real=$(type -P file)
    tb_stub file "case \" \$* \" in
    *' -z '*) echo application/x-decompression-error-zlib-Fork-is-required-to-uncompress--but-disabled ;;
    *) exec '$real' \"\$@\" ;;
esac"
    tar -czf backup.bin backup && rm -rf backup
    run unpack -v backup.bin
    [ "$status" -eq 0 ]
    [[ $output == *"backup.bin: tar.gz, from the content"* ]]
    restored
}

@test "a plain gz with a tar inside unpacks the tar" {
    tar -cf - backup | gzip > backup.gz
    rm -rf backup
    run unpack backup.gz
    [ "$status" -eq 0 ]
    restored
}

# ---------------------------------------------------------------- multi-part sets

@test "a .aa set, started from any part" {
    tar -czf backup.tar.gz backup && rm -rf backup
    split -b 1k backup.tar.gz backup.tar.gz.
    rm backup.tar.gz
    run unpack -k backup.tar.gz.ab
    [ "$status" -eq 0 ]
    [[ $output == "backup.tar.gz ("*" parts) -> backup/"* ]]
    restored
}

@test "a .001 set" {
    head -c 4K /dev/urandom > backup/rand
    tar -cf backup.tar backup && rm -rf backup
    split -b 3k -d -a 3 --numeric-suffixes=1 backup.tar backup.tar.
    rm backup.tar
    run unpack -k backup.tar.001
    [ "$status" -eq 0 ]
    restored
}

@test "a .00 set" {
    tar -czf backup.tar.gz backup && rm -rf backup
    split -b 1k -d backup.tar.gz backup.tar.gz.
    rm backup.tar.gz
    run unpack -k backup.tar.gz.00
    [ "$status" -eq 0 ]
    restored
}

@test "a .7z.001 set" {
    need_7z
    head -c 8K /dev/urandom > backup/rand
    7z a -v4k -bd -bso0 backup.7z backup >/dev/null && rm -rf backup
    [ -f backup.7z.002 ]
    run unpack -k backup.7z.002
    [ "$status" -eq 0 ]
    [[ $output == "backup.7z ("*" parts) -> backup/"* ]]
    restored
}

@test "a .zip.001 set" {
    command -v zip >/dev/null || skip "zip is not installed"
    head -c 4K /dev/urandom > backup/rand
    zip -q -r backup.zip backup && rm -rf backup
    split -b 2k -d -a 3 --numeric-suffixes=1 backup.zip backup.zip.
    rm backup.zip
    run unpack -k backup.zip.001
    [ "$status" -eq 0 ]
    restored
}

@test "a .z01 set, and a lone last part" {
    command -v zip >/dev/null || skip "zip is not installed"
    head -c 70K /dev/urandom > backup/rand
    zip -q -r -s 64k backup.zip backup && rm -rf backup
    [ -f backup.z01 ]
    mv backup.z01 aside
    run unpack backup.zip
    [ "$status" -eq 1 ]
    [[ $output == *"backup.zip: part .z01 is missing, found .zip"* ]]
    mv aside backup.z01
    run unpack -k backup.z01
    [ "$status" -eq 0 ]
    [[ $output == "backup.zip (2 parts) -> backup/"* ]]
    restored
}

@test "a missing middle part is named" {
    tar -czf backup.tar.gz backup && rm -rf backup
    split -b 500 -d -a 3 --numeric-suffixes=1 backup.tar.gz backup.tar.gz.
    rm backup.tar.gz backup.tar.gz.002
    run unpack backup.tar.gz.001
    [ "$status" -eq 1 ]
    [[ $output == *"backup.tar.gz: part .002 is missing, found .001 .003"* ]]
    [ ! -e backup ]
}

@test "rar part names are checked before any tool runs" {
    printf 'Rar!\x1a\x07\x00' > film.part1.rar
    printf 'x' > film.part3.rar
    run unpack film.part1.rar
    [ "$status" -eq 1 ]
    [[ $output == *"film.rar: part .part2.rar is missing, found .part1.rar .part3.rar"* ]]
    printf 'x' > old.r00
    run unpack old.r00
    [ "$status" -eq 1 ]
    [[ $output == *"old.rar: the first part old.rar is missing"* ]]
}

@test "a z01 without its .zip names the last part" {
    printf 'PK\x07\x08' > set.z01
    run unpack set.z01
    [ "$status" -eq 1 ]
    [[ $output == *"set.zip: the last part set.zip is missing"* ]]
}

# ---------------------------------------------------------------- placement

@test "one top folder comes out as that folder" {
    mk_tar
    mv backup.tar data.tar
    run unpack data.tar
    [ "$status" -eq 0 ]
    [[ $output == "data.tar -> backup/"* ]]
    restored
}

@test "loose files get a folder named after the archive" {
    (cd backup && tar -cf ../loose.tar nums.txt b.yaml)
    run unpack loose.tar
    [ "$status" -eq 0 ]
    [[ $output == "loose.tar -> loose/"* ]]
    [ -f loose/nums.txt ]
    [ -f loose/b.yaml ]
}

@test "-H puts loose files here" {
    (cd backup && tar -cf ../loose.tar nums.txt b.yaml)
    mkdir here && mv loose.tar here/
    cd here
    run unpack -H loose.tar
    [ "$status" -eq 0 ]
    [ -f nums.txt ]
    [ -f b.yaml ]
}

@test "-H falls back to a folder on a name clash" {
    (cd backup && tar -cf ../loose.tar nums.txt b.yaml)
    cp backup/b.yaml .
    run unpack -H loose.tar
    [ "$status" -eq 0 ]
    [[ $output == *"b.yaml already exists"* ]]
    [ -f loose/b.yaml ]
}

@test "-d always makes a folder" {
    mk_tar
    run unpack -d backup.tar
    [ "$status" -eq 0 ]
    [ -f backup/backup/nums.txt ]
}

@test "an existing name gets a number" {
    mk_tar
    mkdir backup
    run unpack backup.tar
    [ "$status" -eq 0 ]
    [[ $output == "backup.tar -> backup-1/"* ]]
    [ -f backup-1/nums.txt ]
}

@test "-o unpacks into another folder and makes it" {
    mk_tar
    run unpack -o restore/today backup.tar
    [ "$status" -eq 0 ]
    [ -f restore/today/backup/nums.txt ]
}

@test "no temp folder is left behind" {
    mk_tar
    run unpack backup.tar
    [ "$status" -eq 0 ]
    [ -z "$(find . -name '.unpack-*')" ]
}

# ---------------------------------------------------------------- actions

@test "-l lists and writes nothing" {
    mk_tar
    run unpack -l backup.tar
    [ "$status" -eq 0 ]
    [[ $output == *"backup/nums.txt"* ]]
    [[ $output == *"backup/sub/"* ]]
    [ ! -e backup ]
}

@test "-l shows links with their target" {
    ln -s nums.txt backup/latest
    mk_tar
    run unpack -l backup.tar
    [[ $output == *"backup/latest -> nums.txt"* ]]
}

@test "-t passes a good archive" {
    tar -czf backup.tgz backup && rm -rf backup
    run unpack -t backup.tgz
    [ "$status" -eq 0 ]
    [[ $output == *"backup.tgz: ok, 3 files"* ]]
    [ ! -e backup ]
}

@test "-t fails a cut archive" {
    head -c 8K /dev/urandom > backup/rand
    tar -czf full.tgz backup && rm -rf backup
    head -c 5000 full.tgz > cut.tgz
    run unpack -t cut.tgz
    [ "$status" -eq 1 ]
}

@test "--cat prints one file" {
    tar -czf backup.tgz backup && rm -rf backup
    run unpack --cat backup/sub/a.yaml backup.tgz
    [ "$status" -eq 0 ]
    [ "$output" = hi ]
    [ ! -e backup ]
}

@test "--cat from a zip and a 7z" {
    command -v zip >/dev/null || skip "zip is not installed"
    zip -q -r backup.zip backup
    run unpack --cat backup/b.yaml backup.zip
    [ "$status" -eq 0 ]
    [ "$output" = x ]
    if command -v 7z >/dev/null; then
        7z a -bd -bso0 backup.7z backup
        run unpack --cat backup/b.yaml backup.7z
        [ "$status" -eq 0 ]
        [ "$output" = x ]
    fi
}

@test "--cat of a missing name fails" {
    mk_tar
    run unpack --cat backup/nope backup.tar
    [ "$status" -eq 1 ]
    [[ $output == *"backup/nope is not in the archive"* ]]
}

@test "--only unpacks the matches" {
    tar -czf backup.tgz backup && rm -rf backup
    run unpack --only '*.yaml' backup.tgz
    [ "$status" -eq 0 ]
    [[ $output == *"2 of 3 files"* ]]
    [ -f backup/b.yaml ]
    [ -f backup/sub/a.yaml ]
    [ ! -e backup/nums.txt ]
}

@test "--only repeats" {
    command -v zip >/dev/null || skip "zip is not installed"
    zip -q -r backup.zip backup && rm -rf backup
    run unpack --only '*/b.yaml' --only '*/nums.txt' backup.zip
    [ "$status" -eq 0 ]
    [ -f backup/b.yaml ]
    [ -f backup/nums.txt ]
    [ ! -e backup/sub ]
}

@test "--only with no match fails" {
    mk_tar
    run unpack --only '*.png' backup.tar
    [ "$status" -eq 1 ]
    [ ! -e backup ]
}

@test "-q prints only the result line" {
    mk_tar
    run unpack -q backup.tar
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ ${lines[0]} == "backup.tar -> backup/"* ]]
}

@test "-v shows each step and the real command" {
    tar -czf backup.tgz backup && rm -rf backup
    run unpack -v backup.tgz
    [ "$status" -eq 0 ]
    [[ $output == *"backup.tgz: tar.gz, from the name"* ]]
    [[ $output == *"paths: ok, none escape"* ]]
    [[ $output == *"+ "*"tar -xf - -C "* ]]
    [[ $output == *"verify: 3 files on disk, 3 in the listing"* ]]
}

@test "options after -- go to tar" {
    tar -czf backup.tgz backup && rm -rf backup
    run unpack -v backup.tgz -- --exclude=nums.txt
    [[ $output == *"--exclude=nums.txt"* ]]
    [ -f backup/b.yaml ]
    [ ! -e backup/nums.txt ]
}

@test "-p reads the password of a zip" {
    command -v zip >/dev/null || skip "zip is not installed"
    zip -q -r -P hunter2 backup.zip backup && rm -rf backup
    run unpack backup.zip
    [ "$status" -eq 1 ]
    [[ $output == *"the archive is encrypted, add -p"* ]]
    run bash -c 'echo hunter2 | unpack -p backup.zip'
    [ "$status" -eq 0 ]
    [[ $output != *hunter2* ]]
    restored
}

@test "-p with a 7z and a wrong password" {
    need_7z
    7z a -phunter2 -mhe=on -bd -bso0 backup.7z backup && rm -rf backup
    run bash -c 'echo wrong | unpack -p backup.7z'
    [ "$status" -eq 1 ]
    [[ $output == *"wrong password"* ]]
    run bash -c 'echo hunter2 | unpack -p backup.7z'
    [ "$status" -eq 0 ]
    restored
}

@test "file:// URLs download to a temp file" {
    tar -czf backup.tgz backup && rm -rf backup
    mkdir out
    run unpack -o out "file://$PWD/backup.tgz"
    [ "$status" -eq 0 ]
    [ -f out/backup/nums.txt ]
    [ "$(ls out)" = backup ]
    [ -f backup.tgz ]
}

@test "-r unpacks archives inside" {
    mkdir -p outer/x
    echo a > outer/x/a
    (cd outer && tar -czf inner.tgz x && rm -rf x)
    tar -cf outer.tar outer && rm -rf outer
    run unpack -r outer.tar
    [ "$status" -eq 0 ]
    [[ $output == *"inner: 1 archive unpacked in place"* ]]
    [ "$(cat outer/x/a)" = a ]
    [ ! -e outer/inner.tgz ]
}

@test "several archives in one run" {
    tar -czf one.tgz backup
    cp -r backup two && tar -cf two.tar two && rm -rf two backup
    run unpack one.tgz two.tar
    [ "$status" -eq 0 ]
    [ -f backup/nums.txt ]
    [ -f two/nums.txt ]
}

@test "one failure among several exits 1 and the rest still unpack" {
    tar -czf one.tgz backup && rm -rf backup
    run unpack nope.tgz one.tgz
    [ "$status" -eq 1 ]
    [ -f backup/nums.txt ]
}

# ---------------------------------------------------------------- safety checks

@test "a path with .. is refused" {
    tar -cf evil.tar --transform 's,^,../,' backup/b.yaml
    rm -rf backup
    run unpack evil.tar
    [ "$status" -eq 4 ]
    [[ $output == *"escapes the target folder"* ]]
    [[ $output == *"Nothing was written."* ]]
    [ ! -e ../backup ]
}

@test "an absolute path is refused" {
    tar -cPf evil.tar --transform "s,^,$BATS_TEST_TMPDIR/abs/," backup/b.yaml
    run unpack evil.tar
    [ "$status" -eq 4 ]
    [[ $output == *"is an absolute path"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/abs" ]
}

@test "a link that points out is refused" {
    ln -s /etc/passwd backup/pw
    mk_tar
    run unpack backup.tar
    [ "$status" -eq 4 ]
    [[ $output == *"link backup/pw -> /etc/passwd points outside"* ]]
    [ ! -e backup ]
}

@test "a link out is refused in a zip too" {
    command -v zip >/dev/null || skip "zip is not installed"
    ln -s ../../x backup/up
    zip -q -r -y backup.zip backup && rm -rf backup
    run unpack backup.zip
    [ "$status" -eq 4 ]
    [[ $output == *"points outside"* ]]
}

@test "too little disk space is refused" {
    mk_tar
    tb_stub df 'printf "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 100 99 1 99%% /data\n"'
    run unpack backup.tar
    [ "$status" -eq 4 ]
    [[ $output == *"/data has 1.0KB free"* || $output == *"/data has 1KB free"* ]]
    [[ $output == *"Use -o to unpack onto a disk with more room."* ]]
}

@test "too little memory is refused, and -y goes on" {
    mk_tar_with xz xz
    real=$(command -v xz)
    tb_stub xz "
if [[ \" \$* \" == *' --robot '* ]]; then
    printf 'summary\t999999999999999\t5.4.1\tno\n'
    exit 0
fi
exec $real \"\$@\""
    run unpack backup.tar.xz
    [ "$status" -eq 4 ]
    [[ $output == *"of RAM for this archive"* ]]
    [[ $output == *"add -y to try anyway"* ]]
    run unpack -y backup.tar.xz
    [ "$status" -eq 0 ]
    restored
}

# Zeros squeeze far past 100x.
mk_bomb() { head -c 2M /dev/zero > zeros; gzip -c zeros > zeros.gz; rm zeros; }

@test "over 100x with no terminal is refused" {
    mk_bomb
    run unpack zeros.gz
    [ "$status" -eq 4 ]
    [[ $output == *"x the archive"* ]]
    [[ $output == *"over 100x with no terminal to ask. Add -y."* ]]
    [ ! -e zeros ]
}

@test "over 100x asks in a terminal, and no exits 5" {
    mk_bomb
    tb_tty
    run bash -c 'echo n | unpack zeros.gz'
    [ "$status" -eq 5 ]
    [[ $output == *"Unpack it anyway?"* ]]
    [ ! -e zeros ]
}

@test "over 100x with -y unpacks" {
    mk_bomb
    run unpack -y -k zeros.gz
    [ "$status" -eq 0 ]
    [ "$(stat -c %s zeros)" -eq 2097152 ]
}

# ---------------------------------------------------------------- the delete question

@test "yes moves the archive to the trash" {
    tar -czf backup.tar.gz backup && rm -rf backup
    tb_tty
    run bash -c 'echo y | unpack backup.tar.gz'
    [ "$status" -eq 0 ]
    [[ $output =~ Delete\ backup\.tar\.gz\ \([0-9.]+\ [KB]+\)\?\ It\ goes\ to\ the\ trash\. ]]
    [[ $output == *"backup.tar.gz is in the trash."* ]]
    [ ! -e backup.tar.gz ]
    [ "$(tb_trash_list)" = backup.tar.gz ]
    restored
}

@test "no keeps the archive and exits 0" {
    mk_tar
    tb_tty
    run bash -c 'echo n | unpack backup.tar'
    [ "$status" -eq 0 ]
    [[ $output == *"Kept backup.tar."* ]]
    [ -f backup.tar ]
    [ -z "$(tb_trash_list)" ]
}

@test "a set is asked about once, for every part" {
    tar -czf backup.tar.gz backup && rm -rf backup
    split -b 1k backup.tar.gz backup.tar.gz.
    rm backup.tar.gz
    n=$(ls backup.tar.gz.* | wc -l)
    tb_tty
    run bash -c 'echo y | unpack backup.tar.gz.aa'
    [ "$status" -eq 0 ]
    [ "$(grep -o 'Delete the' <<<"$output" | wc -l)" -eq 1 ]
    [[ $output == *"Delete the $n parts of backup ("* ]]
    [[ $output == *"They go to the trash."* ]]
    [ -z "$(ls backup.tar.gz.* 2>/dev/null)" ]
    [ "$(tb_trash_list | wc -l)" -eq "$n" ]
}

@test "--rm trashes without asking" {
    mk_tar
    run unpack --rm backup.tar
    [ "$status" -eq 0 ]
    [[ $output != *"Delete "* ]]
    [ ! -e backup.tar ]
    [ "$(tb_trash_list)" = backup.tar ]
}

@test "-k never asks" {
    mk_tar
    tb_tty
    run bash -c 'echo y | unpack -k backup.tar'
    [ "$status" -eq 0 ]
    [[ $output != *"Delete "* ]]
    [ -f backup.tar ]
}

@test "with no terminal it never asks and keeps the archive" {
    mk_tar
    run bash -c 'echo y | unpack backup.tar'
    [ "$status" -eq 0 ]
    [[ $output != *"Delete "* ]]
    [ -f backup.tar ]
}

@test "--only, --cat and URLs never ask" {
    tar -czf backup.tgz backup && rm -rf backup
    tb_tty
    run bash -c 'echo y | unpack --only "*.yaml" backup.tgz'
    [[ $output != *"Delete "* ]]
    rm -rf backup
    run bash -c 'echo y | unpack --cat backup/b.yaml backup.tgz'
    [[ $output != *"Delete "* ]]
    run bash -c "echo y | unpack file://$PWD/backup.tgz"
    [ "$status" -eq 0 ]
    [[ $output != *"Delete "* ]]
    [ -f backup.tgz ]
}

# ---------------------------------------------------------------- history and undo

@test "--history with nothing recorded" {
    run unpack --history
    [ "$status" -eq 0 ]
    [[ $output == *"No unpacks recorded yet."* ]]
}

@test "--history lists runs newest first" {
    tar -czf one.tgz backup
    tar -cf two.tar backup
    rm -rf backup
    unpack one.tgz
    mv backup first
    unpack two.tar
    run unpack --history
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == *"two.tar"*"backup/"*"3 files"* ]]
    [[ ${lines[1]} == *"one.tgz"* ]]
}

@test "--undo with nothing recorded fails" {
    run unpack --undo
    [ "$status" -eq 1 ]
    [[ $output == *"nothing to undo"* ]]
}

@test "--undo moves the last unpack to the trash" {
    mk_tar
    unpack backup.tar
    tb_tty
    run bash -c 'echo y | unpack --undo'
    [ "$status" -eq 0 ]
    [[ $output == *"archive   backup.tar"* ]]
    [[ $output == *"Move backup/ to the trash? [y/N]"* ]]
    [ ! -e backup ]
    [ "$(tb_trash_list)" = backup ]
    run unpack --history
    [[ $output == *undone* ]]
}

@test "--undo answered no changes nothing" {
    mk_tar
    unpack backup.tar
    tb_tty
    run bash -c 'echo n | unpack --undo'
    [ "$status" -eq 5 ]
    [ -d backup ]
}

@test "--undo keeps files changed since, and brings the archive back" {
    tar -czf backup.tar.gz backup && rm -rf backup
    tb_tty
    echo y | unpack backup.tar.gz
    [ ! -e backup.tar.gz ]
    echo changed >> backup/b.yaml
    echo mine > backup/new.txt
    run bash -c 'echo y | unpack --undo'
    [ "$status" -eq 0 ]
    [[ $output == *"archive   backup.tar.gz, now in the trash"* ]]
    [[ $output == *"bring back backup.tar.gz?"* ]]
    [[ $output == *"backup/ is in the trash, except 2 files you changed since:"* ]]
    [[ $output == *"backup/b.yaml"* ]]
    [[ $output == *"backup.tar.gz is back in ./."* ]]
    [ -f backup.tar.gz ]
    [ -f backup/new.txt ]
    [ -f backup/b.yaml ]
    [ ! -e backup/nums.txt ]
}

@test "--undo of a set brings every part back" {
    tar -czf backup.tar.gz backup && rm -rf backup
    split -b 1k backup.tar.gz backup.tar.gz.
    rm backup.tar.gz
    n=$(ls backup.tar.gz.* | wc -l)
    tb_tty
    echo y | unpack backup.tar.gz.aa
    run bash -c 'echo y | unpack --undo'
    [ "$status" -eq 0 ]
    [[ $output == *"archive   backup.tar.gz, $n parts, now in the trash"* ]]
    [[ $output == *"$n parts are back in ./."* ]]
    [ "$(ls backup.tar.gz.* | wc -l)" -eq "$n" ]
    [ ! -e backup ]
}

@test "--undo without a terminal needs -y" {
    mk_tar
    unpack backup.tar
    run unpack --undo
    [ "$status" -ne 0 ]
    [ -d backup ]
    run unpack -y --undo
    [ "$status" -eq 0 ]
    [ ! -e backup ]
}

# ---------------------------------------------------------------- sandbox

@test "--sandbox runs podman with no network and a read-only archive" {
    tar -czf backup.tgz backup && rm -rf backup
    stub_engine podman
    run unpack --sandbox backup.tgz
    [ "$status" -eq 0 ]
    [[ $output == *"sandbox: podman, no network, archive read-only"* ]]
    grep -qx -- '--network=none' "$BATS_TEST_TMPDIR/engine.args"
    grep -q -- "backup.tgz:/in/backup.tgz:ro" "$BATS_TEST_TMPDIR/engine.args"
    restored
}

@test "--sandbox falls back to docker" {
    tar -czf backup.tgz backup && rm -rf backup
    stub_engine docker
    tb_without podman
    run unpack --sandbox backup.tgz
    [ "$status" -eq 0 ]
    [[ $output == *"sandbox: docker"* ]]
    grep -qx -- '--user' "$BATS_TEST_TMPDIR/engine.args"
    restored
}

@test "--sandbox with neither engine exits 3" {
    mk_tar
    tb_without podman docker
    run unpack --sandbox backup.tar
    [ "$status" -eq 3 ]
    [[ $output == *"needs podman"* ]]
}
