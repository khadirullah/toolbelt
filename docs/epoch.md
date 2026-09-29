# epoch

Convert Unix timestamps and dates both ways.

## Synopsis

```
epoch [options] [timestamp | date]
```

## Description

A Unix timestamp counts the seconds since 1970-01-01 00:00:00 UTC. Logs, databases, JWTs, Kubernetes objects and
most APIs store times this way, and none of us can read `1790000000` at a glance.

Give `epoch` a number and it prints that moment in your local time, in UTC, and how long ago it was:

```
local  Mon 2026-09-21 19:43:20 IST
utc    Mon 2026-09-21 14:13:20 UTC
ago    8 days
```

Give it a date and it prints the timestamp:

```console
$ epoch "2026-09-29 14:30"
1790672400
```

Give it nothing and it prints the timestamp of this moment.

### How it tells a number from a date

Input that is only digits, with an optional minus sign and an optional fraction, is a timestamp. `@1790000000`, the
form `date -d` uses, is a timestamp too. Anything else is a date.

Many systems count in milliseconds or smaller units, and the number of digits gives it away. A timestamp for a date
between 2001 and 2286 has 10 digits in seconds, 13 in milliseconds, 16 in microseconds and 19 in nanoseconds.
`epoch` reads the number by its length:

| Digits | Read as | Seen in |
|---|---|---|
| up to 11 | seconds | Unix tools, JWT `exp` and `iat`, most APIs |
| 12 to 14 | milliseconds | JavaScript `Date.now()`, Java, Elasticsearch, Kafka |
| 15 to 17 | microseconds | PostgreSQL, Python `time.time_ns() // 1000` |
| 18 and 19 | nanoseconds | Go, Prometheus, Loki, containerd logs |

When it reads the number as anything but seconds, it says so on stderr, `epoch: read as milliseconds`, and shows
the first three digits of the fraction.

A fraction, as in `1790000000.5`, is seconds with a decimal part, which Python's `time.time()` and many JSON logs
print.

### The "ago" line

The last line counts from now to the timestamp in the two largest units that apply: years, days, hours, minutes
and seconds. A time in the future says `in` instead of `ago`. A year counts as 365 days, so over many years the
count drifts by a day for each leap year.

### Dates it reads

`epoch` hands a date to `date -d`, so it reads everything GNU `date` reads:

- `2026-09-29`, midnight at the start of the day
- `2026-09-29 14:30` and `2026-09-29 14:30:05`
- `2026-09-29T09:00:00Z` and `2026-09-29T14:30:00+05:30`, ISO 8601 with a zone
- `Tue, 29 Sep 2026 09:00:00 GMT`, the form in HTTP headers and emails
- `yesterday 18:00`, `next friday`, `2 hours ago`

A date without a zone is local time. `-u` reads it as UTC. A date with a zone, such as `Z` or `+05:30`, ignores
`-u`, because it already says which zone it is in.

Words after `epoch` join with spaces, so `epoch 2026-09-29 14:30` works without quotes.

## Options

| Option | What it does |
|---|---|
| `-u`, `--utc` | Read a date without a zone as UTC, not local time. |
| `--ms` | Print the timestamp in milliseconds, for a date or for now. |
| `-q`, `--quiet` | Hide the "read as" line. |
| `-v`, `--verbose` | Print how it read the input and the `date` command it runs. For a date, also print the date back in full, so you can check it read what you meant. |
| `-h`, `--help` | Show the help. |

## Time zones

The local line uses your time zone, from `TZ` or the system setting. Set `TZ` for one command to see a timestamp
in another place:

```console
$ TZ=America/New_York epoch 1790000000
local  Mon 2026-09-21 10:13:20 EDT
utc    Mon 2026-09-21 14:13:20 UTC
ago    8 days
```

`timedatectl list-timezones` lists the names.

## Pass-through

None. It calls `date` with fixed options.

## Needs

`date` from coreutils. BusyBox `date`, on Alpine, reads timestamps fine but knows far fewer date forms. Stick to
`2026-09-29 14:30` there. `--ms` for a date uses `%N`, and on BusyBox it prints whole seconds times 1000.

## Examples

### A timestamp from a log

```console
$ epoch 1790000000
local  Mon 2026-09-21 19:43:20 IST
utc    Mon 2026-09-21 14:13:20 UTC
ago    8 days
```

### Milliseconds

```console
$ epoch 1790000000123
epoch: read as milliseconds
local  Mon 2026-09-21 19:43:20.123 IST
utc    Mon 2026-09-21 14:13:20.123 UTC
ago    8 days
```

### When a token expires

```console
$ epoch 1800000000
local  Fri 2027-01-15 13:30:00 IST
utc    Fri 2027-01-15 08:00:00 UTC
in     107 days, 16 hours
```

### A date to a timestamp

```console
$ epoch "2026-09-29 14:30"
1790672400
```

### The same moment, typed in UTC

```console
$ epoch -u 2026-09-29 09:00
1790672400
```

### Checking what it read

```console
$ epoch -v 2026-09-29T09:00:00Z
+ date -d 2026-09-29T09:00:00Z +%s
epoch: Tue 2026-09-29 14:30:00 IST
1790672400
```

### Milliseconds for an API

```console
$ epoch --ms "2026-09-29 14:30:00.250"
1790672400250
```

### Something it cannot read

```console
$ epoch next-ish
epoch: cannot read next-ish as a timestamp or a date
Try 'epoch --help' for the options.
```

## Troubleshooting

`epoch: cannot read next-ish as a timestamp or a date`
: `date -d` did not understand the text. Write the date as `2026-09-29 14:30`, or check it with `date -d 'text'`.

The date is off by hours
: A date without a zone is local time. For a UTC time from a log, add `-u`, or write the zone, as in
  `2026-09-29T09:00:00Z`.

A timestamp shows a date in 1970 or far in the future
: The number is in a different unit than its length suggests, such as a 13-digit value in seconds, or a value
  someone cut short. Divide or multiply by 1000 and try again.

A year in the thousands, such as 5138
: An 11-digit number reads as seconds, and 99999999999 seconds is more than 3000 years. The number is probably
  milliseconds with its last digits cut off.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked. |
| 1 | It failed, such as a timestamp too large for `date` to show. |
| 2 | The input is neither a timestamp nor a date. |
| 3 | `date` is missing. |

## See also

`jwtpeek`, `date(1)`
