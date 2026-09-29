# imgpeek

Look inside a container image.

## Synopsis

```
imgpeek [-o dir] image [-- save options]
imgpeek -l image
imgpeek --find PATTERN image
```

## Description

A container image is a stack of tar files called layers, plus a small JSON config. To see what is inside, you
would normally start a container and look around in a shell. That runs the image's code, needs a shell inside the
image, and fails for distroless images that have none. `imgpeek` does it without running anything. It saves the
image to an archive, applies its layers one by one into a plain folder, and prints what it found. You can then
browse the files with `ls`, read them with `less`, or search them with `grep -r`.

The image is a name such as `nginx:1.27` or `ghcr.io/org/app:2.3`, or a file you made earlier with
`docker save` or `podman save`. For a name, `imgpeek` uses the first of these that is installed.

1. podman, which runs without a daemon and without root.
2. docker.
3. skopeo, which copies the image straight from the registry with no container engine at all.

With podman or docker, it asks the engine whether the image is already local. If not, it pulls it first. Then it
runs `save` into a temp folder and reads the archive from there. The temp folder goes away when `imgpeek` exits,
also on Ctrl+C.

`imgpeek` understands both archive layouts in use. The classic `docker save` layout has a `manifest.json` at the
top. The OCI layout, from `podman save --format oci-archive` and from newer Docker, has an `index.json` and a
`blobs/sha256/` folder. Layers may be plain tar, gzip, bzip2, xz or zstd.

## Options

| Option | What it does |
|---|---|
| `-o`, `--out DIR` | Put the files in DIR. By default a new folder in the current folder, named after the image. |
| `-l`, `--layers` | List the layers with their size and the build step that made each, then stop. |
| `--find PATTERN` | Show which layer added, changed or deleted the files that match, then stop. |
| `-q`, `--quiet` | Print only the `wrote` line. |
| `-v`, `--verbose` | Show each step and each real command before it runs. |
| `-h`, `--help` | Show the help. |

`-l` and `--find` do not write the image's files anywhere, so they cannot take `-o`, and they cannot be used
together.

## The folder it writes

The folder name comes from the last part of the image name, with `:` and `@` turned into `-`. So
`docker.io/library/nginx:1.27` becomes `nginx-1.27`, and an image pinned by digest, such as
`alpine@sha256:4bcff6...`, becomes `alpine-4bcff6` with the first 12 characters of the digest. A saved archive
such as `app.tar` becomes `app`.

When that folder already exists, `imgpeek` picks the next free name, `nginx-1.27-1`, then `nginx-1.27-2`. It
never writes into a folder that is already there. With `-o`, the folder may exist only when it is empty. A folder
with files in it is refused with exit 4.

## How the layers are applied

Each layer holds the files its build step added or changed. A layer can also delete a file from the layers below
it. It does that with a marker file, called a whiteout, named `.wh.` plus the file's name. A marker named
`.wh..wh..opq` inside a folder hides everything the lower layers put in that folder.

`imgpeek` applies the layers in order, bottom first, the same way a container engine does.

- A file in a higher layer replaces the same file from a lower one.
- A `.wh.NAME` marker deletes NAME, and a folder marked with `.wh..wh..opq` loses what the lower layers put in it.
  The markers themselves never show up in the folder.
- The `layers` line counts the files the markers removed, such as `2 deleted files left out`.

The result is the filesystem a container would start with. A file that one layer added and a later layer deleted
does not appear, even though its bytes are still in the image. `--find` shows those.

## Safety checks

An image is data from somewhere else, so `imgpeek` treats it with care.

- It never runs anything from the image. It only reads the archive.
- Every path stays inside the output folder. A name such as `../../escape.txt` lands at the top of the folder.
- Symlinks inside the image resolve against the output folder, never against this machine. When a layer has
  `var/run -> /run` and a later layer writes `var/run/app.pid`, the file goes to `nginx-1.27/run/app.pid`, not
  to the real `/run`. The symlink itself stays as the image has it, so `ls -l` shows `var/run -> /run`.
- Set-user-ID and set-group-ID bits are dropped, so no file in the folder can run as another user.
- Device files such as `/dev/null` cannot be made without root. They are skipped, and the `layers` line counts
  them.
- Each file gets read and write access for you, so you can open everything and delete the folder later.
- Before it saves, it checks the image size against the free space where the archive goes. Before it unpacks, it
  checks the archive size against the free space where the folder goes. When space is short it stops with exit 4
  and names both sizes.
- It never overwrites a folder, see above.

## Where the temp files go

The saved archive can be as big as the image. `/tmp` on many systems lives in RAM, so a 1 GB image there would
take 1 GB of memory. `imgpeek` keeps it out of `/tmp`, unless `-o` points there. When it unpacks, the archive
goes into a hidden `.imgpeek-XXXXXX` folder next to the output folder, on the same disk. With `-l` or `--find`,
it goes into `~/.cache/toolbelt`. Either way it is deleted when `imgpeek` exits.

## The summary

```
image    nginx:1.27, 3 layers, 20 KB
layers   applied in order, 2 deleted files left out, 1 device file skipped
wrote    ./nginx-1.27/, 7 files, 70 B
config   user root, entrypoint /docker-entrypoint.sh
         cmd nginx -g "daemon off;", port 80/tcp
```

image
: The name the archive gives the image, how many layers it has, and their total size as stored.

layers
: How many files the whiteout markers removed, and how many device files were skipped.

wrote
: The output folder, the number of files and symlinks in it, and the size of the files. This is the line `-q`
  keeps.

config
: The user the container runs as, its entrypoint and command, and the ports it declares. An image with no
  user set runs as root, and `imgpeek` says so.

## Listing layers

`-l` prints one line per layer, bottom first. SIZE is the layer as stored in the archive, compressed or not.
MADE BY is the build step from the image's history. `imgpeek` cleans up the forms Docker leaves there, so
`/bin/sh -c #(nop) COPY ...` shows as `COPY ...`, a plain `/bin/sh -c ...` shows as `RUN ...`, and the trailing
`# buildkit` goes. Long steps are cut to fit the screen. Steps that made no layer, such as `ENV` or `CMD`, are
left out, since they have no files.

When [dive](https://github.com/wagoodman/dive) is installed, `-l` ends with a hint that `dive IMAGE` shows the
files of each layer in a browser in the terminal.

## Finding a file

`--find PATTERN` reads every layer and prints one line for each time a matching file appears.

- `added` means the file first appears in this layer.
- `changed` means a lower layer had it and this layer replaced it.
- `deleted` means this layer removed it with a whiteout.

A pattern with no `*`, `?` or `[` matches anywhere in the path, so `nginx.conf` finds `etc/nginx/nginx.conf`. A
pattern with those characters is a shell glob. It matches the whole path, the file name, or the end of the path,
so `*.pem` and `conf.d/*.conf` both work. Folders do not count, only files and links. No match at all exits 1.

## Pass-through

Options after `--` go to the tool that fetches the image. That is `podman save`, `docker save`, or `skopeo copy`
when neither engine is installed.

```console
$ imgpeek nginx:1.27 -- --format oci-archive
$ imgpeek ghcr.io/org/app:2.3 -- --src-creds me:TOKEN
```

The first asks podman for the OCI layout. The second, on a machine with only skopeo, gives skopeo registry
credentials. With a saved archive
there is nothing to fetch, so `--` is bad usage there.

## Per-distro notes

Debian and Ubuntu
: `sudo apt install podman` gives rootless podman. For docker, `docker.io` is the distro package. Add yourself
  to the `docker` group, or every docker command needs sudo.

Fedora, RHEL and CentOS Stream
: podman is installed on most setups already. Docker CE comes from Docker's own repository, and `moby-engine`
  is Fedora's build of it.

Arch
: `pacman -S podman` or `pacman -S docker`. dive is in extra.

openSUSE
: `zypper install podman`. Tumbleweed also has dive and skopeo.

Alpine
: `apk add podman` or `apk add docker`. Rootless podman needs `/etc/subuid` and `/etc/subgid` entries for your
  user.

## Needs

One of `podman`, `docker` or `skopeo` to fetch an image by name. `python3` to read the archive and apply the
layers, from its standard library only. `zstd` only for images whose layers are compressed with zstd. `dive` is
optional.

A saved archive needs only `python3`.

## Examples

### Unpack an image and look around

```console
$ imgpeek nginx:1.27
image    nginx:1.27, 3 layers, 20 KB
layers   applied in order, 2 deleted files left out, 1 device file skipped
wrote    ./nginx-1.27/, 7 files, 70 B
config   user root, entrypoint /docker-entrypoint.sh
         cmd nginx -g "daemon off;", port 80/tcp
$ cat nginx-1.27/etc/nginx/nginx.conf
worker_processes auto;
```

### See the layers

```console
$ imgpeek -l nginx:1.27
LAYER  SIZE    MADE BY
1      10 KB   ADD file:5d1b2d in /
2      10 KB   RUN set -x && groupadd --system nginx
3      168 B   COPY conf.d /etc/nginx/conf.d
```

### Which layer changed a file

```console
$ imgpeek --find nginx.conf nginx:1.27
layer 1   added    etc/nginx/nginx.conf
layer 2   changed  etc/nginx/nginx.conf
```

The base layer shipped a `nginx.conf`, and layer 2 replaced it.

### A file that a later layer deleted

```console
$ imgpeek --find 'conf.d/*.conf' nginx:1.27
layer 2   added    etc/nginx/conf.d/default.conf
layer 3   deleted  etc/nginx/conf.d/default.conf
layer 3   added    etc/nginx/conf.d/site.conf
```

`default.conf` is not in the unpacked folder, and it still takes space in the image. A secret removed this way
stays readable in layer 2.

### Into a folder of your choice, with each step shown

```console
$ imgpeek -v -o /srv/peek/nginx nginx:1.27
+ podman image inspect --format '{{.Size}}' nginx:1.27
imgpeek: saving nginx:1.27 with podman
+ podman save -o /srv/peek/.imgpeek-caYCjT/image.tar nginx:1.27
imgpeek: applying 3 layers into /srv/peek/nginx
+ python3 -c '<apply the layers in order>' /srv/peek/.imgpeek-caYCjT/image.tar /srv/peek/nginx
image    nginx:1.27, 3 layers, 20 KB
layers   applied in order, 2 deleted files left out, 1 device file skipped
wrote    /srv/peek/nginx/, 7 files, 70 B
config   user root, entrypoint /docker-entrypoint.sh
         cmd nginx -g "daemon off;", port 80/tcp
```

### A second run keeps the first

```console
$ imgpeek -q nginx:1.27
wrote    ./nginx-1.27-1/, 7 files, 70 B
```

### An archive from docker save, on a machine with no engine

```console
$ imgpeek app.tar
image    nginx:1.27, 3 layers, 20 KB
layers   applied in order, 2 deleted files left out, 1 device file skipped
wrote    ./app/, 7 files, 70 B
config   user root, entrypoint /docker-entrypoint.sh
         cmd nginx -g "daemon off;", port 80/tcp
```

### An image that does not exist

```console
$ imgpeek nosuch:1.0
pulling nosuch:1.0
Trying to pull docker.io/library/nosuch:1.0...
Error: initializing source docker://docker.io/library/nosuch:1.0: reading manifest 1.0 in docker.io/library/nosuch: requested access to the resource is denied
imgpeek: cannot pull nosuch:1.0. Check the name, and podman login for a private registry
$ echo $?
1
```

## Troubleshooting

`imgpeek: needs podman or docker. Install it with: sudo apt install podman`
: No container tool is installed. Install podman, or save the image on another machine with
  `docker save -o app.tar IMAGE` and run `imgpeek app.tar` here.

`imgpeek: cannot pull NAME. Check the name, and podman login for a private registry`
: The registry has no such image, or it needs a login. Run `podman login REGISTRY` or `docker login REGISTRY`
  and try again. Docker Hub names need no registry, others need it in full, such as `ghcr.io/org/app:2.3`.

`permission denied while trying to connect to the Docker daemon socket`
: Your user is not in the `docker` group. Run `sudo usermod -aG docker $USER` and log in again, or install
  podman, which needs no daemon.

`imgpeek: not enough space to save IMAGE`
: The disk that holds the output folder, or `~/.cache` for `-l` and `--find`, is too full. Free some space, or
  point `-o` at a bigger disk.

`imgpeek: NAME already exists and is not empty, pick another folder with -o`
: `-o` named a folder with files in it. Pick a new name, or leave out `-o` for a free one.

`imgpeek: a layer is compressed with zstd. Install zstd and run it again`
: Some registries store layers with zstd, and python3 cannot read those alone. Install `zstd`.

`imgpeek: N entries could not be written`
: A layer had an entry the folder could not hold, such as a hard link to a file that is not there. The rest of
  the image is in place. The message names the first entry.

`imgpeek: no file in IMAGE matches PATTERN`
: `--find` found nothing. Try a shorter pattern, such as the file name alone.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked. |
| 1 | The image could not be pulled or saved, the archive is not an image, or `--find` matched nothing. |
| 2 | Bad usage, such as no image, two images, or `-l` with `--find`. |
| 3 | None of podman, docker and skopeo is installed, or no python3. |
| 4 | Refused. The `-o` folder has files in it, or there is not enough free space. |

## See also

`unpack`, `bigfiles`, `podman-save(1)`, `docker-save(1)`, `skopeo-copy(1)`, `dive(1)`
