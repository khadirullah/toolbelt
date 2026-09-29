#!/usr/bin/env bats
# Tests for imgpeek. docker, podman, skopeo and dive are stubs. The image
# is a docker save archive of a few KB, built here with python3, so the
# layer, whiteout, -l and --find code runs for real.

load helpers

# Build the image archive. Layer 1 has the base files, layer 2 deletes one
# and changes another, layer 3 is gzip and hides a folder with an opaque
# whiteout. Args: output file, and "oci" for the OCI layout.
make_image() {
    python3 - "$1" "${2:-docker}" <<'PY'
import gzip, hashlib, io, json, sys, tarfile, time

def layer(entries, gz=False):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as t:
        for name, kind, data in entries:
            i = tarfile.TarInfo(name)
            i.mtime = 1758000000
            if kind == "dir":
                i.type, i.mode = tarfile.DIRTYPE, 0o755
                t.addfile(i)
            elif kind == "sym":
                i.type, i.linkname = tarfile.SYMTYPE, data
                t.addfile(i)
            elif kind == "hard":
                i.type, i.linkname = tarfile.LNKTYPE, data
                t.addfile(i)
            elif kind == "chr":
                i.type, i.devmajor, i.devminor = tarfile.CHRTYPE, 1, 3
                t.addfile(i)
            else:
                b = data.encode()
                i.size, i.mode = len(b), 0o4755 if kind == "suid" else 0o644
                t.addfile(i, io.BytesIO(b))
    raw = buf.getvalue()
    return gzip.compress(raw, mtime=0) if gz else raw

l1 = layer([
    ("etc", "dir", None), ("etc/nginx", "dir", None),
    ("etc/nginx/nginx.conf", "file", "worker_processes 1;\n"),
    ("usr/share/doc/readme", "file", "read me\n"),
    ("usr/bin/tool", "suid", "#!/bin/sh\n"),
    ("usr/bin/tool2", "hard", "usr/bin/tool"),
    ("var/run", "sym", "/run"),
    ("run", "dir", None),
])
l2 = layer([
    ("usr/share/doc/.wh.readme", "file", ""),
    ("etc/nginx/nginx.conf", "file", "worker_processes auto;\n"),
    ("etc/nginx/conf.d/default.conf", "file", "server {}\n"),
    ("var/run/app.pid", "file", "1\n"),
    ("dev/null", "chr", None),
    ("../../escape.txt", "file", "no\n"),
])
l3 = layer([
    ("etc/nginx/conf.d/.wh..wh..opq", "file", ""),
    ("etc/nginx/conf.d/site.conf", "file", "server { listen 80; }\n"),
], gz=True)

config = json.dumps({
    "architecture": "amd64", "os": "linux",
    "config": {"User": "", "Entrypoint": ["/docker-entrypoint.sh"],
               "Cmd": ["nginx", "-g", "daemon off;"], "ExposedPorts": {"80/tcp": {}}},
    "history": [
        {"created_by": "/bin/sh -c #(nop) ADD file:5d1b2d in / "},
        {"created_by": "/bin/sh -c #(nop)  CMD [\"bash\"]", "empty_layer": True},
        {"created_by": "RUN /bin/sh -c set -x && groupadd --system nginx # buildkit"},
        {"created_by": "COPY conf.d /etc/nginx/conf.d # buildkit"},
    ],
}).encode()

def sha(b):
    return hashlib.sha256(b).hexdigest()

files = {}
if sys.argv[2] == "oci":
    blobs = [config, l1, l2, l3]
    for b in blobs:
        files["blobs/sha256/" + sha(b)] = b
    man = json.dumps({"schemaVersion": 2,
        "config": {"digest": "sha256:" + sha(config)},
        "layers": [{"digest": "sha256:" + sha(b)} for b in (l1, l2, l3)]}).encode()
    files["blobs/sha256/" + sha(man)] = man
    files["index.json"] = json.dumps({"schemaVersion": 2, "manifests": [
        {"digest": "sha256:" + sha(man),
         "annotations": {"io.containerd.image.name": "docker.io/library/nginx:1.27"}}]}).encode()
    files["oci-layout"] = b'{"imageLayoutVersion":"1.0.0"}'
else:
    names = []
    for n, b in enumerate((l1, l2, l3), 1):
        files["l%d/layer.tar" % n] = b
        names.append("l%d/layer.tar" % n)
    files[sha(config) + ".json"] = config
    files["manifest.json"] = json.dumps([{"Config": sha(config) + ".json",
        "RepoTags": ["nginx:1.27"], "Layers": names}]).encode()

with tarfile.open(sys.argv[1], "w") as t:
    for name, b in files.items():
        i = tarfile.TarInfo(name)
        i.size = len(b)
        t.addfile(i, io.BytesIO(b))
PY
}

setup() {
    tb_setup
    export CALLS=$BATS_TEST_TMPDIR/calls
    : > "$CALLS"
    export FIXTURE=$BATS_TEST_TMPDIR/nginx.tar
    make_image "$FIXTURE"
    # docker and podman: inspect answers when the image is local, pull
    # makes it local, save copies the fixture.
    for tool in docker podman; do
        cat > "$BATS_TEST_TMPDIR/stubs/$tool" <<'SH'
#!/usr/bin/env bash
echo "${0##*/} $*" >> "$CALLS"
case $1 in
    image) [[ -e $BATS_TEST_TMPDIR/pulled || -n ${LOCAL:-} ]] || exit 1; echo 6144 ;;
    pull)  [[ -n ${NO_PULL:-} ]] && { echo "Error: manifest unknown" >&2; exit 1; }
           touch "$BATS_TEST_TMPDIR/pulled"; echo "pulled" ;;
    save)  cp "$FIXTURE" "$3" ;;
esac
SH
        chmod +x "$BATS_TEST_TMPDIR/stubs/$tool"
    done
}

@test "help prints usage and exits 0" {
    run imgpeek --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: imgpeek "* ]]
    [ "${lines[3]}" = "Look inside a container image." ]
}

@test "bad usage exits 2" {
    run imgpeek
    [ "$status" -eq 2 ]
    [[ $output == *"name an image"* ]]
    run imgpeek a:1 b:2
    [ "$status" -eq 2 ]
    run imgpeek -l --find x nginx:1.27
    [ "$status" -eq 2 ]
    run imgpeek -l -o out nginx:1.27
    [ "$status" -eq 2 ]
    run imgpeek --find
    [ "$status" -eq 2 ]
    run imgpeek --nope x
    [ "$status" -eq 2 ]
}

@test "with no podman, docker or skopeo it exits 3" {
    rm "$BATS_TEST_TMPDIR/stubs/docker" "$BATS_TEST_TMPDIR/stubs/podman"
    tb_without podman docker skopeo
    run imgpeek alpine:3.22
    [ "$status" -eq 3 ]
    [[ $output == "imgpeek: needs podman or docker. Install it with: "* ]]
}

@test "an image is pulled, saved and unpacked in layer order" {
    export LOCAL=1
    run imgpeek nginx:1.27
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "image    nginx:1.27, 3 layers, "*" KB" ]]
    [ "${lines[1]}" = "layers   applied in order, 2 deleted files left out, 1 device file skipped" ]
    [[ ${lines[2]} == "wrote    ./nginx-1.27/, 7 files, "* ]]
    [ "${lines[3]}" = "config   user root, entrypoint /docker-entrypoint.sh" ]
    [ "${lines[4]}" = "         cmd nginx -g \"daemon off;\", port 80/tcp" ]
    # layer 2 changed nginx.conf and deleted readme
    [ "$(cat nginx-1.27/etc/nginx/nginx.conf)" = "worker_processes auto;" ]
    [ ! -e nginx-1.27/usr/share/doc/readme ]
    # layer 3 hid conf.d from the layers below, and kept its own file
    [ ! -e nginx-1.27/etc/nginx/conf.d/default.conf ]
    [ -f nginx-1.27/etc/nginx/conf.d/site.conf ]
    # the absolute symlink resolves inside the folder, never on this machine
    [ -f nginx-1.27/run/app.pid ]
    [ "$(readlink nginx-1.27/var/run)" = /run ]
    # no setuid bit, and nothing written outside
    [ ! -u nginx-1.27/usr/bin/tool ]
    [ -f nginx-1.27/usr/bin/tool2 ]
    [ ! -e "$BATS_TEST_TMPDIR/escape.txt" ] && [ ! -e escape.txt ]
    [ -f nginx-1.27/escape.txt ]
    grep -q '^podman save -o .*/image.tar nginx:1.27$' "$CALLS"
    # the temp folder is gone
    [ -z "$(ls -A | grep '^\.imgpeek-')" ]
}

@test "podman is used before docker, and a missing image is pulled" {
    run imgpeek nginx:1.27
    [ "$status" -eq 0 ]
    grep -q '^podman pull nginx:1.27$' "$CALLS"
    grep -q '^podman save ' "$CALLS"
    ! grep -q '^docker' "$CALLS"
}

@test "docker is used when podman is missing" {
    rm "$BATS_TEST_TMPDIR/stubs/podman"
    tb_without podman
    export LOCAL=1
    run imgpeek -q nginx:1.27
    [ "$status" -eq 0 ]
    [[ $output == "wrote    ./nginx-1.27/, 7 files, "* ]]
    grep -q '^docker save ' "$CALLS"
}

@test "an image that cannot be pulled exits 1" {
    export NO_PULL=1
    run imgpeek nosuch:1
    [ "$status" -eq 1 ]
    [[ $output == *"imgpeek: cannot pull nosuch:1. Check the name, and podman login for a private registry"* ]]
    [ ! -e nosuch-1 ]
}

@test "skopeo copies the image when there is no podman or docker" {
    rm "$BATS_TEST_TMPDIR/stubs/docker" "$BATS_TEST_TMPDIR/stubs/podman"
    tb_stub skopeo 'echo "skopeo $*" >> "$CALLS"; dest=${3#docker-archive:}; cp "$FIXTURE" "${dest%%:*}"'
    tb_without podman docker
    run imgpeek nginx:1.27
    [ "$status" -eq 0 ]
    grep -q '^skopeo copy docker://nginx:1.27 docker-archive:.*/image.tar:nginx:1.27$' "$CALLS"
    [ -f nginx-1.27/etc/nginx/conf.d/site.conf ]
}

@test "a second run never overwrites the first folder" {
    export LOCAL=1
    run imgpeek nginx:1.27
    run imgpeek nginx:1.27
    [ "$status" -eq 0 ]
    [[ ${lines[2]} == "wrote    ./nginx-1.27-1/, "* ]]
}

@test "-o into a folder that has files is refused" {
    export LOCAL=1
    mkdir -p full && echo keep > full/mine.txt
    run imgpeek -o full nginx:1.27
    [ "$status" -eq 4 ]
    [ "$output" = "imgpeek: full already exists and is not empty, pick another folder with -o" ]
    [ "$(cat full/mine.txt)" = keep ]
    mkdir empty
    run imgpeek -o empty/ nginx:1.27
    [ "$status" -eq 0 ]
    [[ ${lines[2]} == "wrote    ./empty/, 7 files, "* ]]
}

@test "a saved archive works without podman or docker" {
    rm "$BATS_TEST_TMPDIR/stubs/docker" "$BATS_TEST_TMPDIR/stubs/podman"
    tb_without podman docker skopeo
    cp "$FIXTURE" app.tar
    run imgpeek app.tar
    [ "$status" -eq 0 ]
    [[ ${lines[2]} == "wrote    ./app/, 7 files, "* ]]
}

@test "the OCI layout works too" {
    make_image oci.tar oci
    run imgpeek -o oci-out oci.tar
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "image    docker.io/library/nginx:1.27, 3 layers, "* ]]
    [ -f oci-out/etc/nginx/conf.d/site.conf ]
    [ ! -e oci-out/usr/share/doc/readme ]
}

@test "-l lists the layers with the step that made each" {
    export LOCAL=1
    run imgpeek -l nginx:1.27
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "LAYER  SIZE    MADE BY" ]
    [[ ${lines[1]} =~ ^1\ +[0-9.]+\ KB\ +ADD\ file:5d1b2d\ in\ /$ ]]
    [[ ${lines[2]} =~ ^2\ +[0-9.]+\ KB\ +RUN\ set\ -x\ \&\&\ groupadd\ --system\ nginx$ ]]
    [[ ${lines[3]} =~ ^3\ +[0-9]+\ B\ +COPY\ conf.d\ /etc/nginx/conf.d$ ]]
    [ ! -e nginx-1.27 ]
}

@test "-l mentions dive when it is installed" {
    export LOCAL=1
    tb_stub dive 'echo "dive $*" >> "$CALLS"'
    run imgpeek -l nginx:1.27
    [[ $output == *"dive nginx:1.27 browses the files of each layer"* ]]
    ! grep -q '^dive' "$CALLS"
}

@test "--find shows which layer added, changed or deleted a file" {
    export LOCAL=1
    run imgpeek --find conf nginx:1.27
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "layer 1   added    etc/nginx/nginx.conf" ]
    [ "${lines[1]}" = "layer 2   changed  etc/nginx/nginx.conf" ]
    [ "${lines[2]}" = "layer 2   added    etc/nginx/conf.d/default.conf" ]
    [ "${lines[3]}" = "layer 3   deleted  etc/nginx/conf.d/default.conf" ]
    [ "${lines[4]}" = "layer 3   added    etc/nginx/conf.d/site.conf" ]
    run imgpeek --find 'read*' nginx:1.27
    [ "${lines[1]}" = "layer 2   deleted  usr/share/doc/readme" ]
    run imgpeek --find 'conf.d/*.conf' nginx:1.27
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[2]}" = "layer 3   added    etc/nginx/conf.d/site.conf" ]
    run imgpeek --find nothing-here nginx:1.27
    [ "$status" -eq 1 ]
    [ "$output" = "imgpeek: no file in nginx:1.27 matches nothing-here" ]
}

@test "options after -- go to save" {
    export LOCAL=1
    run imgpeek nginx:1.27 -- --format docker-archive
    [ "$status" -eq 0 ]
    grep -q '^podman save -o .*/image.tar --format docker-archive nginx:1.27$' "$CALLS"
    cp "$FIXTURE" app.tar
    run imgpeek app.tar -- --x
    [ "$status" -eq 2 ]
    [[ $output == *"options after -- go to save, and app.tar is already a file"* ]]
}

@test "a file that is not an image archive exits 1" {
    head -c 2K /dev/urandom > junk.tar
    run imgpeek junk.tar
    [ "$status" -eq 1 ]
    [[ $output == "imgpeek: cannot read junk.tar as an image archive"* ]]
    [ ! -e junk ]
}

@test "-v shows the real commands" {
    export LOCAL=1
    run imgpeek -v nginx:1.27
    [[ $output == *"+ podman image inspect --format '{{.Size}}' nginx:1.27"* ]]
    [[ $output == *"+ podman save -o "*"/image.tar nginx:1.27"* ]]
}
