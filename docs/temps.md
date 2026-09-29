# temps

CPU, drive and board temperatures, and fan speed.

## Synopsis

```
temps [options] [-- sensors options]
```

## Description

`temps` shows how hot the parts of the machine are, one row per part. The CPU, each NVMe or SATA drive, the
graphics card, the Wi-Fi card and the mainboard each get a row, with the reading and the high mark the driver
reports for it. Fans show their speed.

It reads the kernel's hardware monitor files in `/sys/class/hwmon` directly, so it needs no extra package, no
root and no setup. The `sensors` command from lm-sensors reads the same files. `temps` groups them by part and
leaves out the noise, such as the dozen identical readings a CPU with many cores reports.

`temps` only reads. It never changes a fan speed, a power limit or any other setting.

### How it names each row

The first column says what the part is. The second column names the sensor.

| Group | Drivers | What it measures |
|---|---|---|
| `cpu` | coretemp, k10temp, zenpower, cpu_thermal | The processor. `package` is the whole chip, `cores` lists each core. |
| `nvme` | nvme | An NVMe SSD, named after its device, such as `nvme0n1`. |
| `drive` | drivetemp | A SATA drive, named after its device, such as `sda`. The drivetemp module must be loaded. |
| `gpu` | amdgpu, radeon, nouveau, i915, xe | The graphics chip. |
| `wifi` | iwlwifi, ath, mt7, rtw | The Wi-Fi card. |
| `board` | acpitz, nct, it87, thinkpad, dell_smm, asus | Mainboard and firmware sensors. |
| `fan` | any driver with a fan input | Fan speed in revolutions per minute. |
| `other` | anything else | Sensors `temps` does not know, shown with their driver name. |

On Intel CPUs, `Package id 0` becomes `package`. On AMD CPUs, `Tctl` becomes `package`. All `Core N` readings go
on one `cores` row, so an 8-core CPU takes one line, not 8.

An NVMe drive often reports two or three sensors. `temps` shows the main one, called Composite, and keeps the
rest for `-a`.

### The high mark and hot

Next to a reading, `high 100 C` is the temperature the driver says the part should stay under. `temps` takes the
driver's max value, or its critical value when there is no max. A driver that reports 0 or more than 200 as its
limit has not set one, so `temps` shows none.

A reading within 5 C of its high mark gets the word `hot`. A CPU that reaches its high mark slows itself down to
cool off, which is why a hot laptop feels slow. A drive at its high mark slows down too, and wears faster.

### No hwmon sensors

Some machines, such as many ARM boards, have no hwmon sensors but do have thermal zones in
`/sys/class/thermal`. `temps` falls back to those, and uses each zone's critical trip point as the high mark.

Virtual machines usually have neither, because the host keeps the hardware to itself. `temps` then says
`no sensors found` and exits 1.

### Watching

`-w` refreshes the table every 2 seconds, or every SEC seconds. It adds MIN and MAX columns, so you can start a
game, a build or a video call and see how hot things got. In a terminal the table redraws in place, with the
reminder `Ctrl+C stops it.` under it. When the output goes to a file, each refresh is appended, with a blank line
between them, and the reminder goes to stderr once at the start.

Ctrl+C stops it and prints one line for each part that got hot, with how often and how hot. When nothing got
hot, it names the hottest reading instead.

## Options

| Option | What it does |
|---|---|
| `-a`, `--all` | Show every raw sensor, with its hwmon file, driver, label, value and high mark. |
| `-w`, `--watch [SEC]` | Refresh every SEC seconds, 2 by default, with MIN and MAX columns. SEC can have a decimal point, such as `0.5`. Ctrl+C stops it. |
| `-q`, `--quiet` | One line, the hottest CPU reading, such as `cpu 71 C`. Without a CPU sensor, the hottest reading of all. |
| `-v`, `--verbose` | Show every step. |
| `-h`, `--help` | Show the help. |

## Pass-through

Options after `--` skip the table and run `sensors` from lm-sensors with those options. Use it for what only
lm-sensors does, such as Fahrenheit or its own config file.

```
temps -- -f
temps -- -u
temps -- -j
```

This needs the lm-sensors package. The table itself does not.

## Per-distro notes

- **All distros.** The table works everywhere the kernel has hwmon drivers, which is every desktop distro.
- **SATA drive temperatures.** These need the `drivetemp` kernel module, which most distros build but do not
  load. Run `sudo modprobe drivetemp` to try it, and add `drivetemp` to a file in `/etc/modules-load.d/` to load
  it at every boot.
- **Mainboard sensors.** Chips such as nct6775 and it87 need their module loaded. `sudo sensors-detect` from
  lm-sensors finds and loads them.
- **lm-sensors packages.** `lm-sensors` on Debian, Ubuntu and Alpine, `lm_sensors` on Fedora and Arch,
  `sensors` on openSUSE.
- **Raspberry Pi.** The CPU reports through a thermal zone called `cpu-thermal`.

## Needs

- Nothing for the table. It reads `/sys/class/hwmon` and `/sys/class/thermal`.
- `sensors`, from lm-sensors, for options after `--`.

## Examples

### A laptop

```console
$ temps
board    acpitz       45 C  high 120 C
nvme     nvme0n1      39 C  high 82 C
cpu      package      71 C  high 100 C
cpu      cores        69 C  68 C  high 100 C
fan      fan1         3,810 rpm
```

The CPU is at 71 C with a limit of 100 C. The fan runs, and nothing is hot.

### A CPU near its limit

```console
$ temps
board    acpitz       45 C  high 120 C
nvme     nvme0n1      39 C  high 82 C
cpu      package      97 C  high 100 C  hot
cpu      cores        69 C  68 C  high 100 C
fan      fan1         3,810 rpm
```

At 97 C the CPU slows itself down. Check that the vents are clear and the fan is not full of dust.

### One number for a status bar

```console
$ temps -q
cpu 71 C
```

### Every raw sensor

```console
$ temps -a
SENSOR                 DRIVER       LABEL                VALUE  HIGH
hwmon0/temp1_input     acpitz       -                     45 C  120 C
hwmon1/temp1_input     nvme         Composite             39 C  82 C
hwmon1/temp2_input     nvme         Sensor 1              39 C
hwmon2/temp1_input     coretemp     Package id 0          71 C  100 C
hwmon2/temp2_input     coretemp     Core 0                69 C  100 C
hwmon2/temp3_input     coretemp     Core 1                68 C  100 C
hwmon3/fan1_input      thinkpad     -                3,810 rpm
```

The SENSOR column is the file under `/sys/class/hwmon`. Read it yourself with
`cat /sys/class/hwmon/hwmon2/temp1_input`, which gives millidegrees, 71000 for 71 C.

### Watch during a heavy job

```console
$ temps -w 1
                       NOW       MIN       MAX
board acpitz          45 C      45 C      45 C
nvme nvme0n1          39 C      39 C      39 C
cpu package           74 C      71 C      96 C
cpu cores             88 C      69 C      88 C
fan fan1         3,810 rpm 3,810 rpm 3,810 rpm
Ctrl+C stops it.
^C
cpu package went within 5 C of its high mark in 1 of 4 readings, the most was 96 C.
```

The CPU touched 96 C once and came back down. One short peak is normal under load. Many readings near the limit
mean the cooling cannot keep up.

### A virtual machine

```console
$ temps
temps: no sensors found. Virtual machines usually have none.
```

## Troubleshooting

**`temps: no sensors found.`** On a virtual machine or in a container this is expected. On real hardware, the
driver for the sensor chip is not loaded. Run `sudo sensors-detect` from lm-sensors and let it load the modules
it finds.

**No row for a SATA drive.** Load the drivetemp module, as in the per-distro notes above. NVMe drives need
nothing extra.

**A reading of 0 C or 127 C that never changes.** The sensor is not wired up on this board. It shows in `-a`
under its driver name. Ignore it, or blacklist the driver if it bothers you.

**`temps: needs sensors.`** Options after `--` need lm-sensors. The message shows the install command. The table
works without it.

**The fan shows 0 rpm.** Many laptops stop the fan when the CPU is cool. Watch with `-w` under load and the
number should rise.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked. With `-w`, stopped with Ctrl+C. |
| 1 | No sensor found. |
| 2 | Bad usage, such as a name, or `-w 0`. |
| 3 | sensors is missing, for options after `--`. |
| 143 | `-w` was stopped by a TERM signal, such as from `kill` or `timeout`. The summary still prints. |

## See also

`disks`, `mem`, `sysinfo`, `sensors(1)`, `sensors-detect(8)`
