# schedules

Cron jobs and systemd timers in one table.

## Synopsis

```
schedules [--user | --system] [-a] [--last]
```

## Description

`schedules` lists everything that runs on its own on this machine, sorted by when it runs next. A Linux machine
has two places for such jobs. Cron is the old one, a table of times and commands. systemd timers are the newer
one, a `.timer` unit that starts a `.service` unit. Most distros use both, so a job you are looking for can hide
in either. `schedules` puts them in one table, soonest first.

With `--last` it shows the other side, when each job last ran, how long it took and whether it worked. A backup
timer that has failed every night for a month shows up here.

`schedules` only reads. It never edits a crontab, never starts, stops or enables a timer, and never needs root.

### The table

| Column | What it shows |
|---|---|
| `NEXT` | When the job runs next, in local time. `16:40 today` for today, `00:00 Wed` within the next 6 days, `09:00 Oct 12` after that. `at boot` for a cron `@reboot` line. |
| `LEFT` | How long until then, such as `38m`, `5h 28m` or `4d 9h`. |
| `JOB` | The timer name without `.timer`, or the cron command. |
| `FROM` | `timer` for a system timer, `timer, user` for one of yours, or `cron` and the file the line came from. |

The last line counts the jobs. When a timer's service failed the last time it ran, the count says so and points
at `schedules --last`.

### Where the jobs come from

- **System timers.** `systemctl list-timers`, which lists the active timers of the whole machine.
- **Your timers.** `systemctl --user list-timers`, the timers of your own user session.
- **`/etc/crontab`.** The main system cron table. Each line has a user field after the five time fields, which
  `schedules` skips.
- **`/etc/cron.d/`.** Cron tables that packages drop in, in the same format as `/etc/crontab`. FROM names the
  file, such as `cron, e2scrub_all`.
- **Your crontab.** `crontab -l`, the table you edit with `crontab -e`. FROM names you, such as `cron, test`.

`schedules` does not read the crontabs of other users, or `/etc/anacrontab`. See the troubleshooting section.

### Job names

A timer shows its own name, such as `logrotate` for `logrotate.timer`. A cron line shows its command, cut to 40
characters with `...` when it is longer. Your home folder shows as `~`, so `/home/test/bin/sync-notes.sh` reads
`~/bin/sync-notes.sh`.

A cron line that runs a whole folder with `run-parts`, such as
`17 * * * * root cd / && run-parts --report /etc/cron.hourly`, shows as `/etc/cron.hourly/*`. The scripts in
that folder are the real jobs, and `ls /etc/cron.hourly` lists them.

### How the next cron run is worked out

cron itself does not say when a line runs next, so `schedules` works it out from the five time fields, the same
way cron reads them.

| Field | Values |
|---|---|
| minute | 0 to 59 |
| hour | 0 to 23 |
| day of month | 1 to 31 |
| month | 1 to 12, or `jan` to `dec` |
| day of week | 0 to 7, where 0 and 7 are both Sunday, or `sun` to `sat` |

Each field can be `*`, a number, a list such as `1,15`, a range such as `mon-fri`, and a step such as `*/15` or
`0-30/10`. The short forms work too. `@hourly`, `@daily`, `@midnight`, `@weekly`, `@monthly`, `@yearly` and
`@annually` become their five-field lines, and `@reboot` shows as `at boot`.

The day fields follow one old cron rule that surprises people. When both the day of month and the day of week
are set, the line runs when either one matches, not when both do. `0 9 1 * mon` runs at 9:00 on the 1st of each
month and also on every Monday. When one of the two starts with `*`, only the other one counts.

`schedules` looks up to 5 years ahead and knows leap years, so `30 2 29 2 *` shows the next February 29. A line
that can never run, such as one for February 31, shows `-` in NEXT and LEFT and sorts last.

Times are local time, the same clock cron uses. A `CRON_TZ` line in a crontab is not read.

### Files cron skips in /etc/cron.d

cron ignores any file in `/etc/cron.d` whose name has a dot or ends with `~`. Package managers leave files such
as `anacron.dpkg-old`, `sysstat.rpmsave` and `backup~` behind, and cron never runs them. `schedules` skips the
same files, so the table shows what cron runs, not every file in the folder.

A file in `/etc/cron.d` that only root can read is left out, with a line on stderr that names it.

### Is cron running

A cron line does nothing when no cron daemon runs. When the table has system cron jobs, `schedules` asks
systemd whether `cron.service`, `crond.service` or `cronie.service` is active. When none is, it warns first.

```
schedules: no cron daemon is running, so the cron jobs here do not run
```

The jobs still show, so you can see what would run once the daemon is back.

### Last runs

`--last` swaps NEXT and LEFT for LAST RUN, TOOK and RESULT.

For a timer, systemd keeps the facts. LAST RUN is when the timer last fired. TOOK is how long the service ran.
RESULT is one of these.

| Result | Meaning |
|---|---|
| `ok` | The service ran and exited 0. |
| `failed, exit 1` | The service exited with that code. |
| `failed, timeout` | The service failed for another reason, which systemd names, such as `timeout`, `signal` or `core-dump`. |
| `running` | The service is running now. |
| `earlier boot` | The timer fired in an earlier boot. systemd counts run times from the start of each boot, so it has no result or time for it. |
| `never ran` | The timer has never fired. |

For cron, there is much less to know. cron keeps no exit code and no run time, only a journal line each time it
starts a command. `schedules` reads the cron lines of the last 31 days from the journal. A job it finds says
`ran`, with the time, and one it does not find says `no record`. After the table, a line on stderr says so.

```
cron keeps no exit code, so cron jobs only say that they ran. System cron lines in the journal need the systemd-journal group.
```

As a normal user outside the `systemd-journal` group, the journal shows only your own cron lines, so every
system cron job says `no record`. Run it with `sudo` or join the group to see them.

## Options

| Option | What it does |
|---|---|
| `--user` | Only your timers and your crontab. |
| `--system` | Only the system timers, `/etc/crontab` and `/etc/cron.d`. |
| `-a`, `--all` | Include timers that are loaded but not active. These have no next run, so they sort last. It changes nothing for cron. |
| `--last` | Show when each job last ran, how long it took and the result, instead of the next run. |
| `-q`, `--quiet` | Only the table, without the count line or the cron note. |
| `-v`, `--verbose` | Show every step, and each command before it runs. |
| `-h`, `--help` | Show the help. |

`--user` and `--system` do not go together. Without either, `schedules` shows both.

## Per-distro notes

- **Debian and Ubuntu.** The `cron` package runs as `cron.service`. `/etc/crontab` runs the `cron.hourly`,
  `cron.daily`, `cron.weekly` and `cron.monthly` folders through `run-parts`, so they show as
  `/etc/cron.daily/*` and so on. The daily, weekly and monthly lines first run `test -x /usr/sbin/anacron`, and
  step aside when anacron is installed, because then anacron runs those folders. Most daily work, such as
  `apt-daily` and `logrotate`, has moved to timers.
- **Fedora, RHEL and CentOS Stream.** The `cronie` package runs as `crond.service`. `/etc/crontab` is empty, and
  `/etc/cron.d/0hourly` runs `/etc/cron.hourly`, which shows as `/etc/cron.hourly/*`. The daily, weekly and
  monthly folders run from `/etc/anacrontab`, which `schedules` does not read.
- **Arch.** No cron comes with the base system, so there are only timers. Install `cronie` and enable
  `cronie.service` if you want cron.
- **openSUSE.** `cronie` runs as `cron.service`. Many packages ship timers instead of cron files.
- **Alpine.** There is no systemd, so `schedules` says `no systemctl here, so only cron jobs` and lists your
  crontab. Run it as root to see root's crontab, which runs the `/etc/periodic` folders. It cannot check whether
  crond runs, so it gives no warning about it.
- **Older systemd.** The timer list is read as JSON. The systemd in RHEL 8 and other older releases cannot print
  it that way, so the timers may be missing from the table there. `systemctl list-timers` still lists them.

## Needs

- `systemctl`, part of systemd, for timers. Without it, `schedules` lists the cron jobs only.
- `crontab`, from cron or cronie, for your own crontab. Optional.
- `journalctl`, part of systemd, for the cron lines in `--last`. Optional.

## Examples

### A Debian virtual machine

```console
$ schedules
NEXT           LEFT      JOB                                       FROM
18:17 today    22m       /etc/cron.hourly/*                        cron, crontab
18:26 today    31m       fwupd-refresh                             timer
18:30 today    35m       if [ -x /etc/init.d/anacron ] && ! [ ...  cron, anacron
18:31 today    37m       anacron                                   timer
20:16 today    2h 22m    apt-daily                                 timer
00:00 Wed      6h 5m     dpkg-db-backup                            timer
00:31 Wed      6h 37m    systemd-tmpfiles-clean                    timer
00:48 Wed      6h 54m    logrotate                                 timer
03:10 Wed      9h 15m    test -e /run/systemd/system || SERVIC...  cron, e2scrub_all
03:11 Wed      9h 17m    man-db                                    timer
06:03 Wed      12h 8m    apt-daily-upgrade                         timer
06:25 Wed      12h 30m   /etc/cron.daily/*                         cron, crontab
06:52 Thu      1d 12h    /etc/cron.monthly/*                       cron, crontab
03:10 Sun      4d 9h     e2scrub_all                               timer
03:30 Sun      4d 9h     test -e /run/systemd/system || SERVIC...  cron, e2scrub_all
06:47 Sun      4d 12h    /etc/cron.weekly/*                        cron, crontab
00:36 Mon      5d 6h     fstrim                                    timer
17 jobs.
```

Two of the cron lines only run when systemd is not PID 1. They start with `test -e /run/systemd/system ||`, so on
this machine they exit at once and the `e2scrub_all` timer does the work. anacron is installed, so the daily,
weekly and monthly cron lines step aside too, and the `anacron` timer runs those folders. The monthly line would
run on October 1, a Thursday.

### What ran, on the same machine

```console
$ schedules --last
JOB                                       LAST RUN       TOOK     RESULT
/etc/cron.hourly/*                        -              -        no record
fwupd-refresh                             17:13 today    0s       ok
if [ -x /etc/init.d/anacron ] && ! [ ...  -              -        no record
anacron                                   17:31 today    0s       ok
apt-daily                                 09:10 today    0s       ok
dpkg-db-backup                            00:17 today    0s       ok
systemd-tmpfiles-clean                    00:31 today    0s       ok
logrotate                                 00:42 today    0s       ok
test -e /run/systemd/system || SERVIC...  -              -        no record
man-db                                    07:53 today    0s       ok
apt-daily-upgrade                         06:00 today    0s       ok
/etc/cron.daily/*                         -              -        no record
/etc/cron.monthly/*                       -              -        no record
e2scrub_all                               03:11 Sep 27   -        earlier boot
test -e /run/systemd/system || SERVIC...  -              -        no record
/etc/cron.weekly/*                        -              -        no record
fstrim                                    01:36 Sep 28   -        earlier boot
17 jobs.
cron keeps no exit code, so cron jobs only say that they ran. System cron lines in the journal need the systemd-journal group.
```

Every timer that ran in this boot worked. `e2scrub_all` and `fstrim` last ran before the last reboot, so there
is no result for them. The user is not in the `systemd-journal` group, so the system cron jobs say `no record`.

### A laptop with a failing backup

```console
$ schedules
NEXT           LEFT      JOB                        FROM
12:30 today    5m        ~/bin/sync-notes.sh        cron, test
12:34 today    10m       backup-notes               timer, user
13:03 today    38m       logrotate                  timer
13:17 today    52m       /etc/cron.hourly/*         cron, crontab
13:24 Wed      1d 1h     fstrim                     timer
23:44 Fri      3d 11h    plocate-updatedb           timer
02:30 Feb 29   517d 14h  /usr/local/bin/leap-day    cron, leap
at boot        -         /usr/local/bin/warm-cache  cron, crontab
8 jobs, 1 failed last time. See: schedules --last
```

The leap day job waits for February 29, 2028. The `@reboot` line sorts after every job with a time.

```console
$ schedules --last
JOB                        LAST RUN       TOOK     RESULT
~/bin/sync-notes.sh        11:59 today    -        ran
backup-notes               11:34 today    3m 12s   failed, exit 1
logrotate                  12:03 today    4s       ok
/etc/cron.hourly/*         -              -        no record
fstrim                     22:31 Sep 28   -        earlier boot
plocate-updatedb           -              -        never ran
/usr/local/bin/leap-day    -              -        no record
/usr/local/bin/warm-cache  -              -        no record
8 jobs, 1 failed last time.
cron keeps no exit code, so cron jobs only say that they ran. System cron lines in the journal need the systemd-journal group.
```

`backup-notes` ran for 3 minutes and exited 1. It is a user unit, so `journalctl --user -u backup-notes` shows
its output.

### Only your own jobs

```console
$ schedules --user
NEXT           LEFT      JOB                  FROM
12:30 today    5m        ~/bin/sync-notes.sh  cron, test
12:34 today    10m       backup-notes         timer, user
2 jobs, 1 failed last time. See: schedules --last
```

On the Debian machine above, which has no user timers and no crontab, the same command prints one line.

```console
$ schedules --user
No timers or cron jobs.
```

### A stopped cron daemon

```console
$ schedules --system
schedules: no cron daemon is running, so the cron jobs here do not run
NEXT           LEFT      JOB                        FROM
13:03 today    38m       logrotate                  timer
13:17 today    52m       /etc/cron.hourly/*         cron, crontab
13:24 Wed      1d 0h     fstrim                     timer
23:44 Fri      3d 11h    plocate-updatedb           timer
02:30 Feb 29   517d 14h  /usr/local/bin/leap-day    cron, leap
at boot        -         /usr/local/bin/warm-cache  cron, crontab
6 jobs.
```

The timers still run. The three cron lines do not, until `svc start cron` or `svc start crond`.

### The table only, for a script

```console
$ schedules -q --user
NEXT           LEFT      JOB                  FROM
12:30 today    5m        ~/bin/sync-notes.sh  cron, test
12:34 today    9m        backup-notes         timer, user
```

### Every command it runs

```console
$ schedules -v --user
+ systemctl --user list-timers --output=json --no-pager
+ systemctl --user show -p Id,Result,ExecMainStatus,ExecMainStartTimestampMonotonic,ExecMainExitTimestampMonotonic,ActiveState backup-notes.service
+ crontab -l
NEXT           LEFT      JOB                  FROM
12:30 today    5m        ~/bin/sync-notes.sh  cron, test
12:34 today    9m        backup-notes         timer, user
2 jobs, 1 failed last time. See: schedules --last
```

## Troubleshooting

**A job I know about is missing.** Check where it lives. Jobs in `/etc/anacrontab`, in another user's crontab
under `/var/spool/cron`, or in a script's own loop are not listed. `sudo crontab -l -u NAME` shows another
user's crontab. A timer that is loaded but not active shows only with `-a`.

**A file in /etc/cron.d is missing.** Its name has a dot or ends with `~`, so cron skips it too. Rename it, for
example from `backup.sh` to `backup`. Or only root can read it, and `schedules` said so on stderr.

**Every cron job says `no record` in `--last`.** You cannot read the system journal. Run
`sudo usermod -aG systemd-journal $USER` and log in again, or run `sudo schedules --last`. On a machine where
cron logs to a file and not to the journal, such as with rsyslog and no journal, there is nothing to read.

**A cron job says `ran`, but did it work?** cron cannot tell. Make the job log its own result, or turn it into
a systemd timer, which keeps the exit code.

**A timer says `earlier boot`.** It last ran before the machine restarted. The result shows again after the
next run.

**A timer says `failed`.** `journalctl -u NAME` shows the output of the last run, and `svc NAME` shows its state.
For a user timer, use `journalctl --user -u NAME`.

**The NEXT time for a cron line looks wrong.** Check the day fields. A line with both a day of month and a day of
week runs when either matches. A `CRON_TZ` line moves cron to another time zone, which `schedules` does not
follow.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, even when a job failed last time or nothing is scheduled. |
| 1 | It could not make a temp folder. |
| 2 | Bad usage, such as a name, or `--user` with `--system`. |

## See also

`svc`, `logs`, `crontab(1)`, `crontab(5)`, `systemd.timer(5)`, `systemctl(1)`
