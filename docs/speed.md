# speed

Download and upload speed test.

## Synopsis

```
speed [options] [-- tool options]
```

## Description

`speed` measures how fast this machine can download and upload, and how long a round trip to a nearby server takes.
It prints one line per result, with a bar so download and upload compare at a glance, and says how much data the test
used.

```console
$ speed
server    Cloudflare MAA, ping 18 ms, jitter 3 ms
download   94.3 Mbit/s  ████████████████████
upload     41.8 Mbit/s  █████████
used      100 MB down, 100 MB up in 29s
wifi      Home-5G, 5 GHz, signal -61 dBm
```

On Wi-Fi it adds the network, the band and the signal strength, since a weak signal is the most common reason for a
low number. Compare with a cable before you blame the provider.

## What the numbers mean

| Line | Meaning |
|---|---|
| `server` | Where the test ran. With curl, `MAA` is the Cloudflare data centre, named after the nearest airport code. |
| `ping` | The fastest of five round trips to the server, in milliseconds. Games and video calls feel it most. |
| `jitter` | How much the round trip changes from one try to the next. Above about 30 ms, calls start to stutter. |
| `download`, `upload` | Megabits per second, the unit providers sell. Divide by 8 for megabytes per second. |
| `used` | The data the test moved, and how long the whole run took. |
| `wifi` | The network, the band, and the signal in dBm. |

Signal strength in dBm is negative, and closer to zero is better. -50 is excellent, -60 good, -70 fair, and below -75
the link slows down and drops. The 5 GHz and 6 GHz bands are faster than 2.4 GHz but reach less far through walls.

## How it tests

`speed` uses the first of these that is installed:

| Tool | Server | Notes |
|---|---|---|
| `librespeed-cli` | The nearest LibreSpeed server. | Open source. `-- --server ID` picks another, and `librespeed-cli --list` shows them. |
| `speedtest` | The nearest Ookla server. | Ookla's own CLI. The older Python `speedtest-cli`, which is also called `speedtest`, is skipped because its output differs. |
| `curl` | The nearest Cloudflare edge, `speed.cloudflare.com`. | Always there, and the only one that honours `-d`, `-u` and `-s`. |

`-d`, `-u` and `-s` always use curl, since the other tools do not let you choose the direction or the size.

### The curl test

With curl, `speed` does three things:

1. It asks `https://speed.cloudflare.com/cdn-cgi/trace` five times. Each time, the time curl takes to open the TCP
   connection is one round trip. The fastest of the five is the ping, and the average change between tries is the
   jitter. The answer also names the data centre.
2. It downloads `-s` megabytes, 100 by default, as four streams of a quarter each from
   `https://speed.cloudflare.com/__down?bytes=N`, all at once.
3. It uploads the same amount as four streams of zeros to `https://speed.cloudflare.com/__up`.

Four streams side by side fill a fast line better than one. A single TCP stream often stops short of the real speed,
because it takes time to ramp up and a lost packet slows it down again.

The speed is the bytes moved times 8, divided by the time of the slowest stream. Nothing is saved to disk, since
the downloads go to `/dev/null` and the uploads are read from `/dev/zero`.

## Data use

A full default test moves about 200 MB with curl, 100 MB each way. LibreSpeed and Ookla run for a fixed time rather
than a fixed size, so on a fast line they use more, often several hundred MB.

That matters on a phone hotspot or a capped plan. `speed` asks NetworkManager whether the connection is metered, and
asks before it starts:

```
speed: Pixel-8 hotspot is a metered connection, and the test
       uses about 200 MB. Run it anyway? [y/N]
```

NetworkManager marks a connection as metered when you set it so, and guesses it for phone hotspots. Answering no
exits 5 and moves no data. With no terminal to ask in, `speed` refuses with exit 4. `-y` goes ahead without asking.

`-s 10` keeps a test small. It is less exact on fast lines, since the test ends before the streams reach full speed,
but fine for telling 5 Mbit/s from 50.

## Options

| Option | What it does |
|---|---|
| `-d`, `--down` | Download only. |
| `-u`, `--up` | Upload only. |
| `-s`, `--size MB` | Megabytes per direction, 1 to 1000. 100 by default, split into 4 streams. |
| `-y`, `--yes` | Do not ask on a metered connection. |
| `-q`, `--quiet` | Print only the numbers in Mbit/s, download first, such as `94.3 41.8`. With `-d` or `-u`, one number. |
| `-v`, `--verbose` | Print the commands before they run. |
| `-h`, `--help` | Show the help. |

## Pass-through

Options after `--` go to whichever tool runs:

```console
$ speed -- --server 52
$ speed -- --server-id 12345
$ speed -d -- --interface wlp3s0
```

The first picks a LibreSpeed server, the second an Ookla server. The third is for curl, and makes the download go
through the Wi-Fi card even when a cable is plugged in too.

## Needs

`curl`, from the `curl` package on every distro.

`librespeed-cli` and `speedtest` are optional. Neither is in the main repos of most distros. LibreSpeed publishes
`librespeed-cli` builds on its GitHub releases page, and Ookla ships `speedtest` from its own repository at
`speedtest.net/apps/cli`.

`nmcli` from NetworkManager is optional. It gives the metered flag. Without it, `speed` never asks. `iw` gives the
Wi-Fi band and signal, with `/proc/net/wireless` and `nmcli` as the fallback. `ip` finds the interface of the default
route.

## Examples

### A full test

```console
$ speed
server    Cloudflare MAA, ping 18 ms, jitter 3 ms
download   94.3 Mbit/s  ████████████████████
upload     41.8 Mbit/s  █████████
used      100 MB down, 100 MB up in 29s
wifi      Home-5G, 5 GHz, signal -61 dBm
```

### Only the numbers, for a log

```console
$ speed -q
94.3 41.8
$ echo "$(date -I) $(speed -q -y)" >> ~/speed.log
```

### A small download test, with the command shown

```console
$ speed -v -d -s 25
speed: testing with curl on wlp3s0
+ curl -s --max-time 5 https://speed.cloudflare.com/cdn-cgi/trace
+ curl -s -o /dev/null -w '%{size_download} %{time_total}' 'https://speed.cloudflare.com/__down?bytes=6250000'
server    Cloudflare MAA, ping 18 ms, jitter 3 ms
download  91.8 Mbit/s, 25 MB in 2.2s
wifi      Home-5G, 5 GHz, signal -61 dBm
```

The command shown is one of the four streams.

### With LibreSpeed installed

```console
$ speed
server    Chennai, India (Example), ping 18 ms, jitter 3 ms
download   94.3 Mbit/s  ████████████████████
upload     41.8 Mbit/s  █████████
used      118 MB down, 52 MB up in 21s
```

### On a phone hotspot

```console
$ speed
speed: Pixel-8 hotspot is a metered connection, and the test
       uses about 200 MB. Run it anyway? [y/N] n
Nothing changed.
```

### No internet

```console
$ speed
speed: no answer from speed.cloudflare.com. Check the link with: netcheck
```

## Troubleshooting

The number is far below what the plan promises
: Test over a cable to rule out Wi-Fi. If the cable number is good, move closer to the router or switch to 5 GHz. If
  the cable number is also low, test at another time of day. Evening slowdowns point at the provider's network.

Download is fine but upload is very low
: Most home plans sell far less upload than download, so check the plan first. A VPN also slows upload more.

The result changes a lot between runs
: Other devices on the network share the line. Pause big downloads and streams, and run it twice.

`speedtest` is installed but `speed` uses curl
: The installed `speedtest` is the older Python one. Remove it, or install Ookla's CLI.

The test is slow to start
: LibreSpeed and Ookla first ping a list of servers to find the nearest one. Pass a server with `-- --server ID`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The test finished. |
| 1 | The test failed, such as no answer from the server or a stream that broke. |
| 2 | Bad usage, such as `-d` with `-u`, or a size outside 1 to 1000. |
| 3 | `curl` is missing. |
| 4 | A metered connection with no terminal to ask in. |
| 5 | You answered no on a metered connection. |

## See also

`netcheck`, `httptime`, `myip`, `curl(1)`, `nmcli(1)`
