# disks

Drives, partitions, space and health together.

## Synopsis

```
disks [options] [-- smartctl options]
```

## Description

`disks` shows every drive in the machine as a tree. Each drive has its partitions under it, and each partition
shows its size, its filesystem, where it is mounted, and how much space is used and free. One command replaces
`lsblk`, `df -h` and `findmnt`, and lines up their answers so you do not have to match device names by eye.

With `--health`, it asks each drive about its own condition through SMART, the self-test data every modern drive
keeps. That shows wear on an SSD, power-on hours, temperature, and the error counters that warn of a drive about
to fail.

`disks` only reads. It never mounts, unmounts, formats, partitions or writes to any device. The SMART query in
`--health` reads the drive's counters and starts no self-test.

### How it builds the table

`disks` runs three read-only commands and joins what they say.

1. `lsblk` lists every block device with its size, type, filesystem, model and parent. The parent link makes
   the tree.
2. `findmnt` lists every mount, including the ones `lsblk` shows only once, such as a btrfs partition mounted
   at both `/` and `/home`.
3. `df` gives used and free space for each mount.

A partition mounted in more than one place shows all its mount points, separated by commas, as in `/, /home`.
Used and free space come from the first one, since every mount of one filesystem shares the same space.

A drive with no partitions and no filesystem shows its model name in the mount column, so you can tell two
drives of the same size apart.

### Sizes

Sizes use the same short units as `lsblk`, in powers of 1024. `600M` is 600 mebibytes, `239G` is 239 gibibytes.
A drive sold as 256 GB shows as about 239G, because the maker counts in powers of 1000.

### The low mark

A mount that is more than 85% full gets the word `low` at the end of its row. `--warn` changes that level.
tmpfs mounts never get the mark, because they live in memory and fill and empty on their own.

At 85%, most filesystems still work well. Past about 95%, ext4 and xfs slow down, btrfs can refuse writes even
with free space left, and package updates fail halfway. The mark gives you time to clean up first. `cleanup`
and `bigfiles` help with that.

### What it hides

By default `disks` shows real drives and what is on them. It hides these, which `-a` brings back.

| Hidden | Why |
|---|---|
| loop devices | Each snap package and each mounted disk image is a loop device. A desktop with snaps has dozens. |
| empty optical drives | A DVD drive with no disc has nothing to show. With a disc in it, it shows. |
| RAM disks | `ram0` to `ram15` exist on some kernels whether used or not. |
| tmpfs mounts | `/run`, `/dev/shm`, `/tmp` on some distros. They live in memory, not on a drive. |
| network mounts | NFS, SMB, sshfs and virtiofs shares. They take space on another machine. |

zram swap stays visible, because it takes real memory and shows up in `free` and `mem`.

### Tree drawing

In a UTF-8 terminal the tree uses line drawing characters, `├` and `└`. In a plain C or POSIX locale it uses
`|-` and `` `- `` instead, so the output stays readable over a serial console or in an old terminal.

### SMART health

`--health` runs `smartctl -H -i -A` on each whole drive. The query needs root, because it talks to the drive
directly. When you are not root, `disks` runs smartctl through `sudo`, which asks for your password in a
terminal. With no terminal, it uses `sudo -n`, which fails at once instead of waiting for a password that
cannot come.

For each drive it shows the lines that matter and skips the rest of smartctl's long report.

| Line | What it means |
|---|---|
| `smart` | The drive's own verdict. PASSED means the drive sees no reason to fail. FAILED means replace it now. |
| `wear` | On an SSD, how much of its rated write life is used. 100% used does not mean dead, but it is past its rating. |
| `power on` | Hours the drive has been powered. 8,760 hours is one year of running all day. |
| `written` | Data written over the drive's life. Compare it with the TBW rating on the maker's data sheet. |
| `temperature` | The drive's own temperature now. Most drives are happy under 60 C. |
| `media errors` | NVMe errors the drive could not correct. Anything above 0 is worth a backup today. |
| `reallocated` | Sectors a hard drive has swapped for spares. A number that grows means the surface is failing. |
| `pending` | Sectors a hard drive could not read and wants to swap. Any number above 0 is a warning. |
| `unsafe shutdowns` | Power losses without a clean shutdown. High counts on a laptop are normal. |

Drives behind many USB adapters cannot answer SMART at all. `disks` says `not available over this USB bridge`
for those. Some adapters answer when told the protocol, with `disks --health -- -d sat`.

zram, loop and RAM devices are not real drives and have no SMART data, so `--health` skips them.

## Options

| Option | What it does |
|---|---|
| `-a`, `--all` | Also show loop devices, empty optical drives, RAM disks, tmpfs and network mounts. |
| `-H`, `--health` | Show SMART health for each drive instead of the space table. Needs root, through sudo when you are not root. |
| `--warn PERCENT` | Mark mounts fuller than PERCENT as low, list each one after the table, and exit 1 when there is one. PERCENT is 0 to 100, with or without a `%` sign. |
| `-q`, `--quiet` | Only the table, without the health hint. With `--warn`, only the lines for full mounts, and nothing when all is well. |
| `-v`, `--verbose` | Show every step, and each command before it runs. |
| `-h`, `--help` | Show the help. |

`disks` takes no device names. It always shows every drive, because a problem is often on the drive you did not
think to look at. Use `lsblk /dev/sda` for one device.

## Pass-through

With `--health`, options after `--` go to smartctl, before the device name. The common ones are these.

| Option | Use |
|---|---|
| `-d sat` | A USB adapter that passes ATA commands through, as most recent ones do. |
| `-d sntrealtek`, `-d sntjmicron`, `-d sntasmedia` | An NVMe drive in a USB enclosure with that chip. |
| `-d nvme` | Force NVMe when smartctl guesses wrong. |
| `-T permissive` | Keep going when the drive reports a partial answer. |

The same options go to every drive, so pass-through is most useful with one drive attached. Without
`--health`, `--` is a usage error.

## Per-distro notes

- **Debian and Ubuntu.** smartctl is in the `smartmontools` package. Installing it also starts `smartd`, which
  checks drives in the background and mails root about problems.
- **Fedora and RHEL.** The package is `smartmontools`. Whether `smartd` starts on its own depends on the
  release. Check with `svc smartd`, and turn it on with `sudo systemctl enable --now smartd`.
- **Arch.** The package is `smartmontools`.
- **openSUSE.** The package is `smartmontools`.
- **Alpine.** lsblk and findmnt are in `lsblk` and `findmnt` packages, not in busybox. smartctl is in
  `smartmontools`.
- **Virtual machines.** Virtual drives such as `vda` have no SMART data. `--health` says so for each one. The
  host's drives are the ones to check.
- **btrfs.** One partition often holds several subvolumes mounted in different places. They share one pool of
  space, which `disks` shows once, with every mount point on the row.
- **LVM and LUKS.** A partition that holds LVM or an encrypted volume shows as `lvm` or `luks` in the FS column,
  with the logical or opened volumes under it in the tree.

## Needs

- `lsblk` and `findmnt`, from util-linux. Every distro has them except minimal Alpine.
- `df`, from coreutils.
- `smartctl`, from smartmontools, for `--health` only.
- `sudo`, for `--health` when you are not root.

## Examples

### A laptop with a USB stick in it

```console
$ disks
DEVICE       SIZE  FS       MOUNTED ON    USED   FREE   USE
nvme0n1      239G           SAMSUNG MZVLB256HAHQ-000L7
├ nvme0n1p1  600M  vfat     /boot/efi      19M   581M    4%
├ nvme0n1p2    1G  ext4     /boot         412M   478M   47%
└ nvme0n1p3  237G  btrfs    /, /home      214G    23G   91% low
sda           58G           SanDisk Ultra
└ sda1        58G  exfat    /run/media/khadir/USB
                                           31G    27G   54%
zram0        7.6G  swap     [SWAP]
health  run disks --health, it needs sudo
```

The root filesystem is 91% full, past the low mark. A mount point too long for its column moves the numbers to
the next line.

### A virtual machine

```console
$ disks
DEVICE       SIZE  FS       MOUNTED ON    USED   FREE   USE
vda           50G
└ vda1        50G  ext4     /              44G   2.5G   95% low
health  run disks --health, it needs sudo
```

### Everything, with shares and memory filesystems

```console
$ disks -a
DEVICE       SIZE  FS       MOUNTED ON    USED   FREE   USE
sr0            1G           QEMU DVD-ROM
vda           50G
└ vda1        50G  ext4     /              44G   2.5G   95% low
tmpfs        795M  tmpfs    /run          1.2M   794M    1%
tmpfs        3.9G  tmpfs    /dev/shm      120M   3.8G    4%
tmpfs          5M  tmpfs    /run/lock       8K     5M    1%
tmpfs        3.9G  tmpfs    /tmp          3.2G   703M   83%
host_share   229G  virtiofs /mnt/host     210G    19G   92% low
```

The shared folder from the host is 92% full too. That space belongs to the host's drive.

### Drive health

```console
$ disks --health
[sudo] password for khadir:
nvme0n1   SAMSUNG MZVLB256HAHQ-000L7
  smart             PASSED
  wear              11% used
  power on          9,412 hours
  written           48.2 TB
  temperature       38 C
  media errors      0
  unsafe shutdowns  71
sda       SanDisk Ultra
  smart             not available over this USB bridge
```

This SSD has used 11% of its rated life in a little over a year of running time, and has no media errors.

### A check for a cron job or a script

```console
$ disks -q --warn 90
/ is 95% full, 2.5G free
$ echo $?
1
```

With `-q` and `--warn`, `disks` prints only the full mounts, and nothing at all when every mount is under the
level. The exit status tells the script which case it is.

### A USB drive that needs a protocol hint

```console
$ disks --health -- -d sat
nvme0n1   SAMSUNG MZVLB256HAHQ-000L7
  smart             not available on this drive
sda       SanDisk Ultra
  smart             PASSED
  power on          112 hours
  temperature       30 C
```

`-d sat` made the USB adapter pass SMART through, but it also went to the NVMe drive, which does not speak that
protocol. Run the command once with the stick attached and once without.

## Troubleshooting

**`disks: --health needs root. Run it in a terminal so sudo can ask, or as root`** There was no terminal for
sudo to ask for a password, such as in a cron job. Run `sudo disks --health` instead, or add a sudo rule for
`smartctl` only.

**`disks: needs smartctl.`** Install smartmontools. The message shows the install command for your distro.

**`smart  not available on this drive`** The drive is virtual, or SMART is off in its firmware. Try
`sudo smartctl -s on /dev/sdX` to turn it on for a real drive.

**The numbers do not match `df -h`.** `df -h` rounds differently and counts some reserved blocks. ext4 keeps 5%
of the space for root, so a full ext4 shows 95% in some tools and 100% in others. `disks` uses `df`'s own
percentage.

**A mounted drive is missing.** It is a loop device, a network share or a tmpfs. Run `disks -a`.

**`low` on a mount you cannot clean.** A drive meant to be full, such as a backup disk, can go over the mark on
purpose. Use `--warn 98` in scripts that watch it.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, no mount is over `--warn`, and every drive with SMART data passed. |
| 1 | A mount is fuller than `--warn`, a drive failed its SMART check, or `--health` could not get root. |
| 2 | Bad usage, such as a device name, `--warn` without a number, or `--` without `--health`. |
| 3 | lsblk, findmnt or df is missing, or smartctl for `--health`. |

## See also

`mem`, `bigfiles`, `cleanup`, `temps`, `lsblk(8)`, `findmnt(8)`, `df(1)`, `smartctl(8)`
