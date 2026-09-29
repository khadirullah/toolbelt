#!/usr/bin/env bats
# Tests for seccheck. Config files are tiny fixtures in a fake tree through
# TB_ROOTFS, and systemctl, ss and the rest are stubs. Nothing runs sudo.

load helpers

setup() {
    tb_setup
    export TB_ROOTFS=$BATS_TEST_TMPDIR/root TB_PM=apt
    mkdir -p "$TB_ROOTFS/etc/ssh/sshd_config.d" "$TB_ROOTFS/etc/sudoers.d"
    # Units named in ACTIVE count as running.
    export ACTIVE="ssh.service"
    tb_stub systemctl 'for a; do u=$a; done; [[ " $ACTIVE " == *" $u "* ]]'
    cat > "$TB_ROOTFS/etc/ssh/sshd_config" <<'EOF'
Include /etc/ssh/sshd_config.d/*.conf
PermitRootLogin prohibit-password
Match User backup
    PasswordAuthentication yes
EOF
    printf 'root ALL=(ALL:ALL) ALL\n%%sudo ALL=(ALL:ALL) ALL\n' > "$TB_ROOTFS/etc/sudoers"
    chmod 440 "$TB_ROOTFS/etc/sudoers"
    tb_stub ss 'cat <<EOF
LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=701,fd=3))
LISTEN 0 128 [::]:22 [::]:* users:(("sshd",pid=701,fd=4))
LISTEN 0 4096 127.0.0.1:631 0.0.0.0:* users:(("cupsd",pid=640,fd=7))
LISTEN 0 511 0.0.0.0:3000 0.0.0.0:* users:(("node",pid=8120,fd=21))
LISTEN 0 50 *:8080 *:*
EOF'
}

@test "help prints usage and exits 0" {
    run seccheck --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: seccheck "* ]]
}

@test "bad usage exits 2" {
    run seccheck --only nope
    [ "$status" -eq 2 ]
    [[ $output == *"no check named nope. The checks are: firewall mac updates"* ]]
    run seccheck ssh
    [ "$status" -eq 2 ]
    [[ $output == *"use --only ssh"* ]]
    run seccheck --only
    [ "$status" -eq 2 ]
}

@test "--list names every check and what it reads" {
    run seccheck --list
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 12 ]
    [ "${lines[0]}" = "firewall    firewalld, ufw or nftables is on, and lets in little" ]
}

@test "a check whose tool is missing is skipped, not failed" {
    tb_without ss
    run seccheck --only ports
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "SKIP  open ports    needs ss" ]
    [ "${lines[1]}" = "1 check: 0 pass, 0 warn, 0 fail, 1 skipped" ]
}

@test "ssh keeps the first value, follows Include and skips Match blocks" {
    echo "PasswordAuthentication no" > "$TB_ROOTFS/etc/ssh/sshd_config.d/10-cloud.conf"
    echo "PermitRootLogin yes" > "$TB_ROOTFS/etc/ssh/sshd_config.d/20-root.conf"
    run seccheck --only ssh
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "PASS  ssh password  PasswordAuthentication no" ]
    [ "${lines[1]}" = "FAIL  ssh root      PermitRootLogin yes, root can log in with a password" ]
    [ "${lines[2]}" = "      fix  add \"PermitRootLogin prohibit-password\" to" ]
    [ "${lines[3]}" = "           /etc/ssh/sshd_config.d/00-local.conf, then" ]
    [ "${lines[4]}" = "           svc restart ssh" ]
    [ "${lines[5]}" = "2 checks: 1 pass, 0 warn, 1 fail" ]
}

@test "ssh with passwords on warns, and --strict turns that into exit 1" {
    run seccheck --only ssh
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "WARN  ssh password  sshd is running and takes passwords" ]
    run seccheck --only ssh --strict
    [ "$status" -eq 1 ]
}

@test "ssh passes when sshd is not running" {
    ACTIVE=""
    run seccheck --only ssh
    [ "$output" = "PASS  ssh           sshd is not running
1 check: 1 pass, 0 warn, 0 fail" ]
}

@test "a config it cannot read is skipped as needing root" {
    [ "$EUID" -ne 0 ] || skip "root can read everything"
    echo "PasswordAuthentication no" > "$TB_ROOTFS/etc/ssh/sshd_config.d/10-cloud.conf"
    chmod 000 "$TB_ROOTFS/etc/ssh/sshd_config.d/10-cloud.conf"
    run seccheck --only ssh
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "SKIP  ssh           needs root to read /etc/ssh/sshd_config.d/10-cloud.conf" ]
    [ "${lines[1]}" = "1 check: 0 pass, 0 warn, 0 fail, 1 skipped (1 need root)" ]
    [[ ${lines[2]} == "To run them too: sudo "*seccheck ]]
    chmod 600 "$TB_ROOTFS/etc/ssh/sshd_config.d/10-cloud.conf"
}

@test "sudo fails on a NOPASSWD rule and names the file" {
    echo "khadir ALL=(ALL) NOPASSWD: ALL" > "$TB_ROOTFS/etc/sudoers.d/90-khadir"
    chmod 440 "$TB_ROOTFS/etc/sudoers.d/90-khadir"
    run seccheck --only sudo
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "FAIL  sudo          NOPASSWD for khadir in /etc/sudoers.d/90-khadir" ]
    [ "${lines[1]}" = "      fix  sudo visudo -f /etc/sudoers.d/90-khadir, drop NOPASSWD" ]
    rm -f "$TB_ROOTFS/etc/sudoers.d/90-khadir"
    run seccheck --only sudo
    [ "${lines[0]}" = "PASS  sudo          every rule asks for a password" ]
}

@test "ports lists what listens on the network, not loopback or sshd" {
    run seccheck --only ports
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "WARN  open ports    3000/tcp on 0.0.0.0, node pid 8120" ]
    [ "${lines[1]}" = "                    8080/tcp on *, owner hidden, root can see it" ]
    [ "${lines[2]}" = "      fix  bind them to 127.0.0.1, or stop them: port 3000 --kill" ]
}

@test "ports passes with only sshd listening" {
    tb_stub ss 'echo "LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:((\"sshd\",pid=701,fd=3))"'
    run seccheck --only ports
    [ "${lines[0]}" = "PASS  open ports    only 22/tcp, for sshd" ]
}

@test "firewall reads firewalld, then ufw" {
    ACTIVE="firewalld.service"
    tb_stub firewall-cmd 'case $1 in --get-default-zone) echo public ;; *) echo "1025-65535/tcp" ;; esac'
    run seccheck --only firewall
    [ "${lines[0]}" = "WARN  firewall      zone public lets in ports 1025-65535" ]
    tb_stub firewall-cmd 'case $1 in --get-default-zone) echo trusted ;; esac'
    run seccheck --only firewall
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "FAIL  firewall      zone trusted lets everything in" ]
    rm "$BATS_TEST_TMPDIR/stubs/firewall-cmd"
    tb_without firewall-cmd
    mkdir -p "$TB_ROOTFS/etc/ufw"
    echo "ENABLED=no" > "$TB_ROOTFS/etc/ufw/ufw.conf"
    run seccheck --only firewall
    [ "${lines[0]}" = "FAIL  firewall      ufw is installed but off" ]
    [ "${lines[1]}" = "      fix  sudo ufw enable" ]
}

@test "updates counts security updates from a dry run" {
    tb_stub apt-get 'cat <<EOF
Inst openssl [3.5.1-1] (3.5.1-1+deb13u1 Debian-Security:13/stable-security [amd64])
Inst libssl3t64 [3.5.1-1] (3.5.1-1+deb13u1 Debian-Security:13/stable-security [amd64])
Inst tzdata [2025b-4] (2025b-4+deb13u1 Debian:13.1/stable [all])
EOF'
    run seccheck --only updates -v
    [ "$status" -eq 1 ]
    [[ $output == *"+ apt-get -s -o Debug::NoLocking=1 dist-upgrade"* ]]
    [[ $output == *"FAIL  updates       2 security updates pending"* ]]
    [[ $output == *"      fix  pkg upgrade"* ]]
}

@test "mac reads SELinux first, then AppArmor" {
    tb_stub getenforce 'echo Permissive'
    run seccheck --only selinux
    [ "${lines[0]}" = "WARN  selinux       permissive, it logs but blocks nothing" ]
    tb_without getenforce
    mkdir -p "$TB_ROOTFS/sys/module/apparmor/parameters"
    echo Y > "$TB_ROOTFS/sys/module/apparmor/parameters/enabled"
    run seccheck --only apparmor
    [ "${lines[0]}" = "PASS  apparmor      enabled" ]
}

@test "sshdir fails on a private key others can read" {
    mkdir -m 700 "$HOME/.ssh"
    printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n' > "$HOME/.ssh/id_ed25519"
    chmod 644 "$HOME/.ssh/id_ed25519"
    run seccheck --only sshdir
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "FAIL  ~/.ssh        id_ed25519 is 644, others can read this private key" ]
    [ "${lines[1]}" = "      fix  chmod 600 $HOME/.ssh/id_ed25519" ]
    chmod 600 "$HOME/.ssh/id_ed25519"
    run seccheck --only sshdir
    [ "${lines[0]}" = "PASS  ~/.ssh        folder 700, 1 private key 600" ]
}

@test "path fails on a world-writable folder in PATH" {
    mkdir -m 777 "$BATS_TEST_TMPDIR/open"
    chmod 777 "$BATS_TEST_TMPDIR/open"
    PATH=$BATS_TEST_TMPDIR/open:$PATH run seccheck --only path
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "FAIL  PATH          $BATS_TEST_TMPDIR/open is world-writable, anyone can plant a command" ]
}

@test "etc fails on a world-writable file" {
    echo x > "$TB_ROOTFS/etc/motd"
    chmod 666 "$TB_ROOTFS/etc/motd"
    run seccheck --only etc
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "FAIL  /etc files    /etc/motd is world-writable" ]
    [ "${lines[1]}" = "      fix  sudo chmod o-w /etc/motd" ]
}

@test "encryption reads the device under /" {
    tb_stub findmnt 'echo "/dev/mapper/luks-1a2b"'
    tb_stub lsblk 'printf "crypt\npart\ndisk\n"'
    run seccheck --only encryption
    [ "${lines[0]}" = "PASS  encryption    / is on LUKS" ]
}

@test "screen lock reads gsettings on GNOME" {
    export XDG_CURRENT_DESKTOP=GNOME
    tb_stub gsettings 'case $2 in *screensaver) echo true ;; *) echo "uint32 1800" ;; esac'
    run seccheck --only screenlock
    [ "${lines[0]}" = "WARN  screen lock   locks after 30 min idle" ]
    XDG_CURRENT_DESKTOP="" run seccheck --only screenlock
    [ "${lines[0]}" = "SKIP  screen lock   no GNOME, Cinnamon, MATE or KDE session here" ]
}

@test "secure boot is skipped on a BIOS machine" {
    run seccheck --only secureboot
    [ "${lines[0]}" = "SKIP  secure boot   this machine boots with BIOS, not UEFI" ]
}

@test "-q prints only the summary line" {
    echo "PasswordAuthentication no" > "$TB_ROOTFS/etc/ssh/sshd_config.d/10-cloud.conf"
    run seccheck -q --only ssh,sudo
    [ "$status" -eq 0 ]
    [ "$output" = "3 checks: 3 pass, 0 warn, 0 fail" ]
}
