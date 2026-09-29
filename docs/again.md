# again

Run a command again until it works.

## Synopsis

```
again [options] [--] command [args]
```

## Description

`again` runs a command. If the command fails, `again` waits and runs it again. It stops at the first try that
exits 0, or after the last try. Use it for a download that drops, a service that is still starting, or an API that
rate limits you.

The first wait is 1 second. Each wait after that doubles, so the waits go 1, 2, 4, 8 and 16 seconds. No single
wait is longer than 60 seconds. With the defaults, `again` makes 5 tries and waits 15 seconds in all.

After each failed try, `again` prints one line on stderr with the try number, the exit code and the next wait:

```
again: try 2 of 5 failed, exit 7, next in 2s
```

When a try works after one or more failures, it says how long the whole run took. When the first try works,
`again` prints nothing of its own, so you can put it in front of a command in a script and the output stays the
same.

After the last try, `again` exits with the command's own exit code. A script that checks for `curl` exit 22 still
sees 22.

The command's output passes through untouched. `again` never reads it, never hides it and never changes it.

### Where the command starts

The command starts at the first word that is not an option of `again`, or right after `--`. Everything from there
on belongs to the command, so its own options never mix with those of `again`:

```console
$ again -n 3 curl -fsS -d @body.json https://example.com/api
```

Here `-n 3` goes to `again`, and `-fsS` and `-d` go to `curl`. Use `--` when the command name itself starts with a
dash, or when you want the line to read clearly in a script.

### What it can run

`again` runs programs and scripts found on your `PATH`, and the builtins of bash. It cannot run your shell's
aliases or functions, because it runs in its own process. For a pipeline or a shell loop, hand the whole thing to
`sh -c`:

```console
$ again -- sh -c 'kubectl get pod api-0 | grep -q Running'
```

## Options

| Option | What it does |
|---|---|
| `-n`, `--times N` | Tries in total, counting the first. 5 by default. 1 means a single try, with no retry. |
| `-d`, `--delay SECS` | The first wait, in whole seconds. 1 by default. 0 retries at once. |
| `--max-delay SECS` | The longest single wait. 60 by default. A doubling wait stops growing here. |
| `--fixed` | Wait the same time between every try, the value of `--delay`, with no doubling. |
| `--on CODE` | Try again only when the command exits with this code. Repeat it for more codes. Any other failing code stops `again` at once. |
| `-q`, `--quiet` | Print none of the try lines. The command's own output and the final "gave up" line still show. |
| `-v`, `--verbose` | Print the command line before each try, as `+ curl -fsS https://example.com/health`. |
| `-h`, `--help` | Show the help. |

## How the waits grow

With `-d 10 --max-delay 30` the waits go 10, 20, 30, 30, 30. With `--fixed -d 5` every wait is 5 seconds.

| Tries (`-n`) | First wait (`-d`) | Waits | Longest total wait |
|---|---|---|---|
| 5 | 1 | 1 2 4 8 | 15s |
| 10 | 1 | 1 2 4 8 16 32 60 60 60 | 243s |
| 10 | 5, with `--fixed` | 5 each, 9 times | 45s |
| 3 | 0 | 0 0 | 0s |

The waits are whole seconds. The total time also counts how long each try itself took.

## Picking which failures to retry

Some failures are worth a retry and some are not. A timeout may pass on the next try. A wrong password will not.
`--on` tells `again` which exit codes mean "try again". Any other exit code ends the run at once, with that code:

```console
$ again --on 6 --on 7 --on 28 -- curl -fsS https://example.com/health
```

For `curl`, 6 means the name did not resolve, 7 that the connection failed and 28 a timeout. A 404, exit 22 with
`-f`, stops at once, because asking again will not fix it.

`rsync` uses 23 and 24 for partial transfers and 30 and 35 for timeouts. `ssh` uses 255 for a connection error.

## Stopping it

Ctrl+C stops `again` and the command it is running. It exits 130, the usual code for Ctrl+C.

## Pass-through

None. Everything after `--`, or from the first word that is not an option, is the command that `again` runs.

## Needs

Bash only. `sleep` from coreutils does the waiting. It is on every Linux system, BusyBox included.

## Examples

### A health check while a service starts

```console
$ again -- curl -fsS https://example.com/health
curl: (7) Failed to connect to example.com port 443
again: try 1 of 5 failed, exit 7, next in 1s
curl: (7) Failed to connect to example.com port 443
again: try 2 of 5 failed, exit 7, next in 2s
{"status":"ok"}
again: try 3 of 5 worked, 3.1s in total
```

### Giving up

```console
$ again -n 3 -- ping -c1 -W1 10.0.0.9
PING 10.0.0.9 (10.0.0.9) 56(84) bytes of data.

--- 10.0.0.9 ping statistics ---
1 packets transmitted, 0 received, 100% packet loss, time 0ms

again: try 1 of 3 failed, exit 1, next in 1s
...
again: try 2 of 3 failed, exit 1, next in 2s
...
again: gave up after 3 tries, last exit 1
$ echo $?
1
```

### A rollout, checked every 5 seconds

```console
$ again -n 10 -d 5 --fixed -- kubectl rollout status deploy/api --timeout=30s
error: deployment "api" exceeded its progress deadline
again: try 1 of 10 failed, exit 1, next in 5s
deployment "api" successfully rolled out
again: try 2 of 10 worked, 36s in total
```

### Long waits with a cap

```console
$ again -n 6 -d 10 --max-delay 30 -- false
again: try 1 of 6 failed, exit 1, next in 10s
again: try 2 of 6 failed, exit 1, next in 20s
again: try 3 of 6 failed, exit 1, next in 30s
again: try 4 of 6 failed, exit 1, next in 30s
again: try 5 of 6 failed, exit 1, next in 30s
again: gave up after 6 tries, last exit 1
```

### Only for the codes that can pass

```console
$ again --on 75 -n 3 -- sh -c 'exit 1'
again: try 1 of 3 failed, exit 1, which is not in --on, so no more tries
```

### Seeing each command

```console
$ again -v -n 2 -d 5 --fixed -- sh -c 'exit 1'
+ sh -c 'exit 1'
again: try 1 of 2 failed, exit 1, next in 5s
+ sh -c 'exit 1'
again: gave up after 2 tries, last exit 1
```

## Troubleshooting

`again: myfunc: command not found`
: The name is not a program on your `PATH` or a bash builtin. Shell functions and aliases live only in your shell.
  Put the work in a script, or run `again -- bash -c 'source ~/.bashrc; myfunc'`.

`again: --times needs a whole number of 1 or more, not 0`
: `-n` counts every try, the first one too. `-n 1` runs the command once.

It retries a command that can never work
: Some commands exit 1 for every kind of error. Use `--on` with the codes that mean a passing problem, or lower
  `-n`.

The waits are longer than I asked for
: `--max-delay` is 60 by default, but `-d` above it is cut down to it. `-d 90` waits 60 seconds unless you also give
  `--max-delay 90`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | A try worked. |
| 2 | Bad usage, such as `-n 0` or no command. |
| 127 | The command does not exist. |
| 130 | Stopped with Ctrl+C. |
| other | The exit code of the command's last try. |

## See also

`waitfor`, `notify-done`, `timeout(1)`
