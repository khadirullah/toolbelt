#!/usr/bin/env bats
# Tests for sysinfo. A fake tree through TB_ROOTFS stands in for /etc, /proc
# and /sys, and stubs stand in for lscpu, df, ip and systemd.

load helpers

setup() {
    tb_setup
    export TB_ROOTFS=$BATS_TEST_TMPDIR/root
    local r=$TB_ROOTFS
    mkdir -p "$r/etc" "$r/proc/sys/kernel" "$r/proc/1" "$r/sys/class/dmi/id" "$r/sys/class/net/wlp3s0/device"
    printf 'NAME="Fedora Linux"\nVERSION_ID=44\nPRETTY_NAME="Fedora Linux 44 (Workstation Edition)"\n' > "$r/etc/os-release"
    echo km-laptop > "$r/proc/sys/kernel/hostname"
    echo 6.19.8-200.fc44.x86_64 > "$r/proc/sys/kernel/osrelease"
    echo LENOVO > "$r/sys/class/dmi/id/sys_vendor"
    echo 20L5CTO1WW > "$r/sys/class/dmi/id/product_name"
    echo 'ThinkPad T480' > "$r/sys/class/dmi/id/product_version"
    printf 'MemTotal:        8000000 kB\nMemAvailable:    2500000 kB\n' > "$r/proc/meminfo"
    printf 'Filename\tType\tSize\tUsed\tPriority\n/dev/zram0 partition\t8000000\t0\t100\n' > "$r/proc/swaps"
    printf '/dev/nvme0n1p3 / btrfs rw 0 0\n/dev/nvme0n1p3 /home btrfs rw 0 0\n' > "$r/proc/mounts"
    echo '283000.52 1000.00' > "$r/proc/uptime"
    echo systemd > "$r/proc/1/comm"
    printf 'processor\t: 0\nmodel name\t: Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz\nphysical id\t: 0\ncpu cores\t: 4\nprocessor\t: 1\nprocessor\t: 2\nprocessor\t: 3\n' \
        > "$r/proc/cpuinfo"
    tb_stub lscpu 'printf "Architecture:        x86_64\nCPU(s):              8\nModel name:          Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz\nCore(s) per socket:  4\nSocket(s):           1\nNUMA node0 CPU(s):   0-7\n"'
    tb_stub df 'printf "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/nvme0n1p3 248512512 224395264 24117248 90%% /\n"'
    tb_stub ip '
case "$*" in
    "route show default") echo "default via 192.168.1.1 dev wlp3s0 proto dhcp metric 600" ;;
    *) printf "lo UNKNOWN 127.0.0.1/8\nwlp3s0 UP 192.168.1.24/24\ndocker0 DOWN 172.17.0.1/16\n" ;;
esac'
    tb_stub systemctl 'echo "systemd 258 (258.1-1.fc44)"'
    tb_stub systemd-detect-virt 'echo none; exit 1'
    export XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_TYPE=wayland
}

@test "help prints usage and exits 0" {
    run sysinfo --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: sysinfo [-q | -v]" ]
}

@test "bad usage exits 2" {
    run sysinfo extra
    [ "$status" -eq 2 ]
    run sysinfo --nope
    [ "$status" -eq 2 ]
    run sysinfo -- -x
    [ "$status" -eq 2 ]
}

@test "shows the whole machine" {
    run sysinfo
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "host     km-laptop, Lenovo ThinkPad T480" ]
    [ "${lines[1]}" = "distro   Fedora Linux 44 (Workstation Edition)" ]
    [ "${lines[2]}" = "kernel   6.19.8-200.fc44.x86_64" ]
    [ "${lines[3]}" = "cpu      Intel Core i5-8250U, 4 cores, 8 threads" ]
    [ "${lines[4]}" = "ram      7.6GB, 5.2GB used, zram swap 7.6GB" ]
    [ "${lines[5]}" = "disk     /  237GB btrfs, 214GB used (90%)" ]
    [ "${lines[6]}" = "uptime   3 days, 6 hours" ]
    [ "${lines[7]}" = "ip       192.168.1.24/24 on wlp3s0, gateway 192.168.1.1" ]
    [[ ${lines[8]} == "pkg      "* ]]
    [ "${lines[9]}" = "init     systemd 258" ]
    [ "${lines[10]}" = "session  GNOME on Wayland" ]
    [[ $output != *docker0* ]]
}

@test "-q prints one line" {
    run sysinfo -q
    [ "$status" -eq 0 ]
    [ "$output" = "km-laptop  Fedora 44  6.19.8-200.fc44.x86_64  i5-8250U  7.6GB  up 3d 6h" ]
}

@test "-v shows what it reads" {
    run sysinfo -v
    [[ $output == *"+ cat /etc/os-release"* || $output == *"+ cat /proc/sys/kernel/hostname"* ]]
    [[ $output == *"+ lscpu"* ]]
    [[ $output == *"+ df -Pk /"* ]]
    [[ $output == *"+ ip -brief -4 addr show up"* ]]
}

@test "falls back to /proc/cpuinfo without lscpu" {
    tb_without lscpu
    run sysinfo
    [ "$status" -eq 0 ]
    [ "${lines[3]}" = "cpu      Intel Core i5-8250U, 4 cores, 4 threads" ]
}

@test "works without ip, df or systemd, as in a container" {
    tb_without ip df systemctl systemd-detect-virt
    echo bash > "$TB_ROOTFS/proc/1/comm"
    touch "$TB_ROOTFS/.dockerenv"
    rm -r "$TB_ROOTFS/sys/class/dmi"
    unset XDG_CURRENT_DESKTOP DESKTOP_SESSION XDG_SESSION_TYPE DISPLAY WAYLAND_DISPLAY SSH_CONNECTION
    run sysinfo
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "host     km-laptop, container, docker" ]
    [[ $output != *"disk "* ]]
    [[ $output == *"ip       unknown, the ip command is not installed"* ]]
    [[ $output == *"init     bash"* ]]
    [[ $output == *"session  none, text console"* ]]
}

@test "names a virtual machine and a missing os-release" {
    tb_stub systemd-detect-virt '[[ $1 == -c ]] && { echo none; exit 1; }; echo kvm'
    rm "$TB_ROOTFS/etc/os-release"
    echo QEMU > "$TB_ROOTFS/sys/class/dmi/id/sys_vendor"
    echo 'Standard PC (Q35 + ICH9, 2009)' > "$TB_ROOTFS/sys/class/dmi/id/product_name"
    run sysinfo
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "host     km-laptop, QEMU Standard PC (Q35 + ICH9, 2009), virtual machine, kvm" ]
    [ "${lines[1]}" = "distro   Linux" ]
}

@test "reads the real machine" {
    unset TB_ROOTFS
    rm "$BATS_TEST_TMPDIR"/stubs/*
    run sysinfo
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "host     "* ]]
    [[ $output == *"kernel   $(uname -r)"* ]]
}
