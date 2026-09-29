#!/usr/bin/env bats
# Tests for disks. lsblk, findmnt, df, smartctl and sudo are stubs, so no
# test reads or touches a real device.

load helpers

setup() {
    tb_setup
    export LANG=C.UTF-8 LC_ALL=C.UTF-8
    local f=$BATS_TEST_TMPDIR
    cat > "$f/lsblk.out" <<'EOF'
NAME="loop0" KNAME="loop0" PKNAME="" TYPE="loop" SIZE="4194304" FSTYPE="squashfs" MOUNTPOINT="/snap/core/1" MODEL="" PATH="/dev/loop0" TRAN=""
NAME="nvme0n1" KNAME="nvme0n1" PKNAME="" TYPE="disk" SIZE="256060514304" FSTYPE="" MOUNTPOINT="" MODEL="SAMSUNG MZVLB256HAHQ-000L7" PATH="/dev/nvme0n1" TRAN="nvme"
NAME="nvme0n1p1" KNAME="nvme0n1p1" PKNAME="nvme0n1" TYPE="part" SIZE="629145600" FSTYPE="vfat" MOUNTPOINT="/boot/efi" MODEL="" PATH="/dev/nvme0n1p1" TRAN="nvme"
NAME="nvme0n1p2" KNAME="nvme0n1p2" PKNAME="nvme0n1" TYPE="part" SIZE="1073741824" FSTYPE="ext4" MOUNTPOINT="/boot" MODEL="" PATH="/dev/nvme0n1p2" TRAN="nvme"
NAME="nvme0n1p3" KNAME="nvme0n1p3" PKNAME="nvme0n1" TYPE="part" SIZE="254356226048" FSTYPE="btrfs" MOUNTPOINT="/" MODEL="" PATH="/dev/nvme0n1p3" TRAN="nvme"
NAME="sda" KNAME="sda" PKNAME="" TYPE="disk" SIZE="62277025792" FSTYPE="" MOUNTPOINT="" MODEL="SanDisk Ultra" PATH="/dev/sda" TRAN="usb"
NAME="sda1" KNAME="sda1" PKNAME="sda" TYPE="part" SIZE="62276025792" FSTYPE="exfat" MOUNTPOINT="/run/media/khadir/USB" MODEL="" PATH="/dev/sda1" TRAN="usb"
NAME="zram0" KNAME="zram0" PKNAME="" TYPE="disk" SIZE="8160000000" FSTYPE="swap" MOUNTPOINT="[SWAP]" MODEL="" PATH="/dev/zram0" TRAN=""
EOF
    cat > "$f/findmnt.out" <<'EOF'
/dev/nvme0n1p3[/root] / btrfs
/dev/nvme0n1p1 /boot/efi vfat
/dev/nvme0n1p2 /boot ext4
/dev/nvme0n1p3[/home] /home btrfs
/dev/sda1 /run/media/khadir/USB exfat
tmpfs /tmp tmpfs
/dev/loop0 /snap/core/1 squashfs
EOF
    cat > "$f/df.out" <<'EOF'
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/nvme0n1p1      614400     19456    594944       4% /boot/efi
/dev/nvme0n1p2     1048576    421888    489472      47% /boot
/dev/nvme0n1p3   248395776 224395776  24000000      91% /
/dev/sda1         60817408  32505856  28311552      54% /run/media/khadir/USB
tmpfs              4069012    118888   3950124       3% /tmp
/dev/loop0            4096      4096         0     100% /snap/core/1
EOF
    tb_stub lsblk "echo \"\$*\" >> '$f/args'; cat '$f/lsblk.out'"
    tb_stub findmnt "cat '$f/findmnt.out'"
    tb_stub df "echo \"df \$*\" >> '$f/args'; cat '$f/df.out'"
    # sudo only passes the command on, so no test can reach the real one.
    tb_stub sudo "echo \"sudo \$*\" >> '$f/args'; [[ \$1 == -n ]] && shift; exec \"\$@\""
    cat > "$f/smart-nvme" <<'EOF'
=== START OF SMART DATA SECTION ===
SMART overall-health self-assessment test result: PASSED
Temperature:                        38 Celsius
Percentage Used:                    11%
Data Units Written:                 94,208,000 [48.2 TB]
Power On Hours:                     9,412
Unsafe Shutdowns:                   71
Media and Data Integrity Errors:    0
EOF
    printf '/dev/sda: Unknown USB bridge [0x0781:0x5581 (0x100)]\nPlease specify device type with the -d option.\n' > "$f/smart-sda"
    tb_stub smartctl "echo \"smartctl \$*\" >> '$f/args'
case \"\$*\" in
    *nvme0n1*) cat '$f/smart-nvme' ;;
    *sda*) cat '$f/smart-sda'; exit 1 ;;
esac"
}

@test "help prints usage and exits 0" {
    run disks --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: disks "* ]]
}

@test "bad usage exits 2" {
    run disks --warn lots
    [ "$status" -eq 2 ]
    run disks --warn 101
    [ "$status" -eq 2 ]
    run disks sda
    [ "$status" -eq 2 ]
    run disks -- -d sat
    [ "$status" -eq 2 ]
}

@test "a missing lsblk exits 3" {
    tb_without lsblk
    run disks
    [ "$status" -eq 3 ]
    [[ $output == "disks: needs lsblk."* ]]
}

@test "shows drives, partitions, mounts and use in one tree" {
    run disks
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "DEVICE       SIZE  FS       MOUNTED ON    USED   FREE   USE" ]
    [ "${lines[1]}" = "nvme0n1      239G           SAMSUNG MZVLB256HAHQ-000L7" ]
    [ "${lines[2]}" = "├ nvme0n1p1  600M  vfat     /boot/efi      19M   581M    4%" ]
    [ "${lines[4]}" = "└ nvme0n1p3  237G  btrfs    /, /home      214G    23G   91% low" ]
    [ "${lines[5]}" = "sda           58G           SanDisk Ultra" ]
    [ "${lines[6]}" = "└ sda1        58G  exfat    /run/media/khadir/USB" ]
    [ "${lines[7]}" = "                                           31G    27G   54%" ]
    [ "${lines[8]}" = "zram0        7.6G  swap     [SWAP]" ]
    [[ $output != *loop0* ]]
    [[ $output == *"health  run disks --health, it needs sudo"* ]]
}

@test "plain ASCII tree without a UTF-8 locale" {
    LC_ALL=C LANG=C run disks -q
    [ "${lines[2]}" = "|-nvme0n1p1  600M  vfat     /boot/efi      19M   581M    4%" ]
    [ "${lines[4]}" = "\`-nvme0n1p3  237G  btrfs    /, /home      214G    23G   91% low" ]
}

@test "-a adds loop devices and tmpfs mounts" {
    run disks -a
    [[ $output == *"loop0"*"squashfs"*"/snap/core/1"* ]]
    [[ $output == *"tmpfs"*"/tmp"*"3%"* ]]
}

@test "--warn exits 1 and names each mount over the level" {
    run disks --warn 85
    [ "$status" -eq 1 ]
    [ "${lines[-1]}" = "/ is 91% full, 23G free" ]
    run disks -q --warn 50
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "/ is 91% full, 23G free" ]
    [ "${lines[1]}" = "/run/media/khadir/USB is 54% full, 27G free" ]
    run disks -q --warn 95
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "--health shows SMART data through sudo, and says when a bridge hides it" {
    run disks --health -v
    [ "$status" -eq 0 ]
    [[ $output == *"+ sudo -n smartctl -H -i -A /dev/nvme0n1"* ]]
    [[ $output == *"nvme0n1   SAMSUNG MZVLB256HAHQ-000L7"* ]]
    [[ $output == *"  smart             PASSED"* ]]
    [[ $output == *"  wear              11% used"* ]]
    [[ $output == *"  power on          9,412 hours"* ]]
    [[ $output == *"  written           48.2 TB"* ]]
    [[ $output == *"  temperature       38 C"* ]]
    [[ $output == *"  media errors      0"* ]]
    [[ $output == *"  unsafe shutdowns  71"* ]]
    [[ $output == *"  smart             not available over this USB bridge"* ]]
    [[ $output != *zram0* ]]
}

@test "options after -- go to smartctl" {
    run disks --health -- -d sat
    grep -q 'smartctl -H -i -A -d sat /dev/sda' "$BATS_TEST_TMPDIR/args"
}

@test "a failing drive exits 1" {
    sed -i 's/PASSED/FAILED!/' "$BATS_TEST_TMPDIR/smart-nvme"
    run disks --health
    [ "$status" -eq 1 ]
    [[ $output == *"smart             FAILED!"* ]]
}

@test "--health without a sudo password exits 1 and says why" {
    tb_stub sudo 'echo "sudo: a password is required" >&2; exit 1'
    run disks --health
    [ "$status" -eq 1 ]
    [[ $output == *"disks: --health needs root"* ]]
}

@test "--health without smartctl exits 3" {
    rm "$BATS_TEST_TMPDIR/stubs/smartctl"
    tb_without smartctl
    run disks --health
    [ "$status" -eq 3 ]
    [[ $output == "disks: needs smartctl."* ]]
}
