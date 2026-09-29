#!/usr/bin/env bats
# Tests for schedules. systemctl, crontab and journalctl are stubs, and the
# system cron files are tiny fixtures in a fake tree through TB_ROOTFS.
# Nothing edits a real crontab or timer.

load helpers

# One list-timers JSON entry: seconds from now to next and last (0 for
# none), the timer and the unit it starts.
jt() {
    local n=0 l=0
    (( $1 != 0 )) && n=$(( (NOW + $1) * 1000000 ))
    (( $2 != 0 )) && l=$(( (NOW + $2) * 1000000 ))
    printf '{"next":%s,"left":0,"last":%s,"passed":0,"unit":"%s","activates":"%s"}' "$n" "$l" "$3" "$4"
}

setup() {
    tb_setup
    export TZ=UTC
    export TB_ROOTFS=$BATS_TEST_TMPDIR/root
    NOW=$(date +%s)
    local f=$BATS_TEST_TMPDIR
    mkdir -p "$TB_ROOTFS/etc/cron.d"
    cat > "$TB_ROOTFS/etc/crontab" <<'EOF'
SHELL=/bin/sh
# m h dom mon dow user command
17 * * * * root cd / && run-parts --report /etc/cron.hourly
@reboot root /usr/local/bin/warm-cache
EOF
    echo "30 2 29 2 * root /usr/local/bin/leap-day" > "$TB_ROOTFS/etc/cron.d/leap"
    echo "0 1 * * * root /bin/false" > "$TB_ROOTFS/etc/cron.d/leap.dpkg-old"
    echo "0 1 * * * root /bin/false" > "$TB_ROOTFS/etc/cron.d/leap~"
    echo "*/15 * * * * $HOME/bin/sync-notes.sh" > "$f/crontab"
    printf '[%s,%s,%s]\n' \
        "$(jt 2310 -1300 logrotate.timer logrotate.service)" \
        "$(jt 90000 -50000 fstrim.timer fstrim.service)" \
        "$(jt 300000 0 plocate-updatedb.timer plocate-updatedb.service)" > "$f/timers-system"
    printf '[%s]\n' "$(jt 600 -3000 backup-notes.timer backup-notes.service)" > "$f/timers-user"
    cat > "$f/show-system" <<'EOF'
Id=logrotate.service
Result=success
ExecMainStatus=0
ExecMainStartTimestampMonotonic=5000000000
ExecMainExitTimestampMonotonic=5004000000
ActiveState=inactive

Id=fstrim.service
Result=success
ExecMainStatus=0
ExecMainStartTimestampMonotonic=0
ExecMainExitTimestampMonotonic=0
ActiveState=inactive

Id=plocate-updatedb.service
Result=success
ExecMainStatus=0
ExecMainStartTimestampMonotonic=0
ExecMainExitTimestampMonotonic=0
ActiveState=inactive
EOF
    cat > "$f/show-user" <<'EOF'
Id=backup-notes.service
Result=exit-code
ExecMainStatus=1
ExecMainStartTimestampMonotonic=7000000000
ExecMainExitTimestampMonotonic=7192000000
ActiveState=failed
EOF
    export CRON_RC=0
    tb_stub systemctl "
echo \"\$*\" >> '$f/args'
s=system; [[ \$1 == --user ]] && s=user
case \"\$*\" in
    *list-timers*) cat '$f/timers-'\$s ;;
    *show*) cat '$f/show-'\$s ;;
    *is-active*) exit \$CRON_RC ;;
esac"
    tb_stub crontab "[ -s '$f/crontab' ] || { echo 'no crontab for test' >&2; exit 1; }; cat '$f/crontab'"
    tb_stub journalctl "echo \"\$(( $NOW - 1500 )) host CRON[4411]: (test) CMD ($HOME/bin/sync-notes.sh)\""
}

@test "help prints usage and exits 0" {
    run schedules --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: schedules "* ]]
}

@test "bad usage exits 2" {
    run schedules --user --system
    [ "$status" -eq 2 ]
    [[ $output == *"--user and --system do not go together"* ]]
    run schedules logrotate
    [ "$status" -eq 2 ]
    run schedules --next
    [ "$status" -eq 2 ]
}

@test "without systemctl it says so and lists cron jobs only" {
    tb_without systemctl
    run schedules
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "schedules: no systemctl here, so only cron jobs" ]
    [[ $output != *logrotate* ]]
    [[ $output == *"/etc/cron.hourly/*"* ]]
}

@test "timers and cron jobs share one table, soonest first" {
    run schedules
    [ "$status" -eq 0 ]
    [[ ${lines[0]} =~ ^NEXT\ +LEFT\ +JOB\ +FROM$ ]]
    local re=" [0-9]+m +~/bin/sync-notes.sh +cron, test"
    [[ $output =~ $re ]]
    [[ $output == *"  38m       logrotate                  timer"* ]]
    [[ $output == *"  1d 1h     fstrim                     timer"* ]]
    [[ $output == *"  3d 11h    plocate-updatedb           timer"* ]]
    [[ $output == *"/etc/cron.hourly/*         cron, crontab"* ]]
    [[ $output =~ \ (9|10)m\ +backup-notes\ +timer,\ user ]]
    [ "${lines[8]}" = "at boot        -         /usr/local/bin/warm-cache  cron, crontab" ]
    [ "${lines[-1]}" = "8 jobs, 1 failed last time. See: schedules --last" ]
}

@test "cron reads day, month and leap years right" {
    run schedules --system
    local re="02:30 Feb 29   [0-9]+d [0-9]+h +/usr/local/bin/leap-day +cron, leap"
    [[ $output =~ $re ]]
}

@test "cron.d skips files with dots or a trailing tilde, as cron does" {
    run schedules --system
    [[ $output != *"/bin/false"* ]]
}

@test "--user shows only your timers and crontab" {
    run schedules --user
    [[ $output == *backup-notes* ]]
    [[ $output == *sync-notes* ]]
    [[ $output != *logrotate* ]]
    [[ $output != *warm-cache* ]]
    [ "${#lines[@]}" -eq 4 ]
}

@test "--system leaves out your timers and crontab" {
    run schedules --system
    [[ $output != *backup-notes* ]]
    [[ $output != *sync-notes* ]]
    [ "${lines[-1]}" = "6 jobs." ]
}

@test "--last shows when each job ran, how long it took and the result" {
    run schedules --last
    [ "$status" -eq 0 ]
    [[ ${lines[0]} =~ ^JOB\ +LAST\ RUN\ +TOOK\ +RESULT$ ]]
    # A last run reads "15:40 today" or "21:30 Sep 28".
    local at='[0-9]{2}:[0-9]{2} [A-Za-z]{3}( [0-9]{2}|[a-z]{2})'
    local re="backup-notes +$at +3m 12s +failed, exit 1"
    [[ $output =~ $re ]]
    re="logrotate +$at +4s +ok"
    [[ $output =~ $re ]]
    re="fstrim +$at +- +earlier boot"
    [[ $output =~ $re ]]
    re="plocate-updatedb +- +- +never ran"
    [[ $output =~ $re ]]
    re="~/bin/sync-notes.sh +$at +- +ran"
    [[ $output =~ $re ]]
    re="/usr/local/bin/warm-cache +- +- +no record"
    [[ $output =~ $re ]]
    [[ $output == *"8 jobs, 1 failed last time."* ]]
    if [ "$EUID" -ne 0 ]; then
        [[ $output == *"cron keeps no exit code"* ]]
    else
        [[ $output != *"cron keeps no exit code"* ]]
    fi
}

@test "a failed job shows in the summary of the plain table" {
    run schedules --user
    [ "${lines[-1]}" = "2 jobs, 1 failed last time. See: schedules --last" ]
}

@test "-a asks systemctl for inactive timers too" {
    run schedules -a --system
    grep -q -- 'list-timers --output=json --no-pager --all' "$BATS_TEST_TMPDIR/args"
}

@test "warns when no cron daemon runs" {
    CRON_RC=3 run schedules --system
    [[ $output == *"schedules: no cron daemon is running, so the cron jobs here do not run"* ]]
}

@test "-q prints only the table" {
    run schedules -q --user
    [ "${#lines[@]}" -eq 3 ]
    [[ ${lines[0]} == NEXT* ]]
}

@test "nothing scheduled says so" {
    rm -rf "$TB_ROOTFS/etc"
    : > "$BATS_TEST_TMPDIR/crontab"
    echo '[]' > "$BATS_TEST_TMPDIR/timers-system"
    echo '[]' > "$BATS_TEST_TMPDIR/timers-user"
    run schedules
    [ "$status" -eq 0 ]
    [ "$output" = "No timers or cron jobs." ]
}
