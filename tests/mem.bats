#!/usr/bin/env bats
# Tests for mem. Most tests read a fake /proc tree through TB_ROOTFS, one
# reads the real /proc.

load helpers

# A process in the fake tree: pid, name, rss kB, swap kB, oom score, adj.
fake_proc() {
    local d=$TB_ROOTFS/proc/$1
    mkdir -p "$d"
    printf 'Name:\t%s\nUmask:\t0022\nVmRSS:\t%8s kB\nVmSwap:\t%8s kB\n' "$2" "$3" "$4" > "$d/status"
    echo "$5" > "$d/oom_score"
    echo "$6" > "$d/oom_score_adj"
}

setup() {
    tb_setup
    export TB_ROOTFS=$BATS_TEST_TMPDIR/root
    mkdir -p "$TB_ROOTFS/proc/pressure" "$TB_ROOTFS/sys/block/zram0" "$TB_ROOTFS/proc/7"
    printf 'MemTotal:        8000000 kB\nMemFree:          100000 kB\nMemAvailable:     500000 kB\nSwapTotal:       6000000 kB\nSwapFree:        2000000 kB\n' \
        > "$TB_ROOTFS/proc/meminfo"
    printf 'some avg10=38.12 avg60=20.00 avg300=5.00 total=1\nfull avg10=1.00 avg60=0.00 avg300=0.00 total=1\n' \
        > "$TB_ROOTFS/proc/pressure/memory"
    printf 'Filename\tType\tSize\tUsed\tPriority\n/dev/zram0 partition\t4000000\t3000000\t100\n/swapfile file\t2000000\t1000000\t-2\n' \
        > "$TB_ROOTFS/proc/swaps"
    echo '3000000000 1000000000 1000000000 0 0 0 0 0 0' > "$TB_ROOTFS/sys/block/zram0/mm_stat"
    echo 'lzo lzo-rle [zstd]' > "$TB_ROOTFS/sys/block/zram0/comp_algorithm"
    fake_proc 2231 firefox 1400000 410000 194 100
    fake_proc 4410 'Isolated Web Co' 1100000 620000 257 167
    fake_proc 3120 code 980000 210000 162 0
    fake_proc 1811 postgres 610000 95000 137 0
    # A kernel thread, with no memory of its own.
    printf 'Name:\tkthreadd\n' > "$TB_ROOTFS/proc/7/status"
    tb_stub systemctl 'exit 3'
    tb_stub journalctl 'exit 0'
}

@test "help prints usage and exits 0" {
    run mem --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: mem [-n COUNT] [-o] [-w [SECONDS]]" ]
}

@test "bad usage exits 2" {
    run mem -n 0
    [ "$status" -eq 2 ]
    run mem --top lots
    [ "$status" -eq 2 ]
    run mem -w 0
    [ "$status" -eq 2 ]
    run mem firefox
    [ "$status" -eq 2 ]
    run mem -- -x
    [ "$status" -eq 2 ]
}

@test "a missing /proc/meminfo exits 1" {
    rm "$TB_ROOTFS/proc/meminfo"
    run mem
    [ "$status" -eq 1 ]
    [[ $output == *"cannot read"*"meminfo"* ]]
}

@test "shows memory, zram, swap and the top users" {
    run mem
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "memory  7.2GB used of 7.6GB, 488MB available, pressure 38% (10s)" ]
    [ "${lines[1]}" = "zram    zram0 zstd, 2.8GB of pages stored in 954MB of RAM, 3.0x" ]
    [ "${lines[2]}" = "swap    zram0      2.9GB of 3.8GB   priority 100" ]
    [ "${lines[3]}" = "        /swapfile  977MB of 1.9GB   priority -2" ]
    [ "${lines[4]}" = "    RSS    SWAP   OOM     PID  COMMAND" ]
    [ "${lines[5]}" = "  1.3GB   400MB   194    2231  firefox" ]
    [ "${lines[6]}" = "    1GB   606MB   257    4410  Isolated Web Co" ]
    [ "${lines[-1]}" = "oom first  Isolated Web Co, pid 4410, score 257, frees about 1.6GB" ]
    [[ $output != *kthreadd* ]]
}

@test "-n and --oom rank by OOM score" {
    run mem --oom -n 2
    [ "$status" -eq 0 ]
    [ "${lines[4]}" = "  OOM  ADJ     RSS    SWAP     PID  COMMAND" ]
    [ "${lines[5]}" = "  257  167     1GB   606MB    4410  Isolated Web Co" ]
    [ "${lines[6]}" = "  194  100   1.3GB   400MB    2231  firefox" ]
    [[ ${lines[7]} == "oom first"* ]]
}

@test "-q prints one line" {
    run mem -q
    [ "$status" -eq 0 ]
    [ "$output" = "7.2GB of 7.6GB used, 488MB available, swap 3.8GB of 5.7GB" ]
}

@test "no swap and no pressure file" {
    printf 'Filename\tType\tSize\tUsed\tPriority\n' > "$TB_ROOTFS/proc/swaps"
    rm "$TB_ROOTFS/proc/pressure/memory" "$TB_ROOTFS/sys/block/zram0/mm_stat"
    run mem
    [ "${lines[0]}" = "memory  7.2GB used of 7.6GB, 488MB available" ]
    [ "${lines[1]}" = "swap    none" ]
}

@test "names systemd-oomd and the last kills from the journal" {
    tb_stub systemctl 'exit 0'
    mkdir -p "$TB_ROOTFS/etc/systemd"
    printf '[OOM]\nDefaultMemoryPressureLimit=50%%\nDefaultMemoryPressureDurationSec=20s\n' > "$TB_ROOTFS/etc/systemd/oomd.conf"
    local t
    t=$(date +%s)
    tb_stub journalctl "
if [[ \$* == *-k* ]]; then
    echo '$t.123 box kernel: Out of memory: Killed process 3877 (Isolated Web Co) total-vm:3214580kB, anon-rss:2291044kB, file-rss:0kB, UID:1000 pgtables:5000kB oom_score_adj:167'
else
    echo '$t.456 box systemd-oomd[640]: Killed /user.slice/app-firefox.scope due to memory pressure for /user.slice being 71% > 50%'
fi"
    run mem
    [ "$status" -eq 0 ]
    [[ $output == *"oomd    systemd-oomd on, kills in a watched slice at 50% pressure for 20s"* ]]
    [[ $output == *"last kill  "*" today, from the kernel log"* ]]
    [[ $output == *"  Out of memory: Killed process 3877 (Isolated Web Co)"* ]]
    [[ $output == *"  total-vm:3214580kB, anon-rss:2291044kB, oom_score_adj:167"* ]]
    [[ $output == *"  Killed /user.slice/app-firefox.scope"* ]]
}

@test "works without journalctl" {
    tb_without journalctl
    run mem
    [ "$status" -eq 0 ]
    [[ ${lines[-1]} == "oom first"* ]]
}

@test "-w redraws until stopped" {
    run timeout 2 mem -q -w 0.5
    # GNU timeout exits 124. BusyBox timeout passes on the exit code of what it stopped.
    [[ $status == 124 || $status == 143 ]]
    [ "$(grep -c 'used, 488MB available' <<<"$output")" -ge 2 ]
}

@test "reads the real /proc" {
    unset TB_ROOTFS
    run mem -n 3
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "memory  "*" used of "* ]]
    [[ $output == *"oom first  "* ]]
}
