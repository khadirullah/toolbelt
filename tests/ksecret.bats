#!/usr/bin/env bats
# Tests for ksecret. kubectl is a stub that prints Secrets shaped like
# `kubectl get secret -o json`. Every value is made up in the test.

load helpers
bats_require_minimum_version 1.5.0

setup_file() {
    local d=$BATS_FILE_TMPDIR
    # Only the certificate and key tests need these, and they skip without openssl.
    command -v openssl >/dev/null || return 0
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$d/k.pem" -out "$d/c.pem" -days 80 \
        -subj /CN=shop.example.com 2>/dev/null
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$d/ec.pem" 2>/dev/null
}

setup() {
    tb_setup
    export FX=$BATS_TEST_TMPDIR/fx CALLS=$BATS_TEST_TMPDIR/calls
    mkdir -p "$FX"
    : > "$CALLS"
    local d=$BATS_FILE_TMPDIR
    jq -n --arg c "$(base64 -w0 "$d/c.pem")" --arg k "$(base64 -w0 "$d/k.pem")" \
        '{apiVersion: "v1", kind: "Secret", metadata: {name: "shop-tls", namespace: "shop"},
          type: "kubernetes.io/tls", data: {"tls.crt": $c, "tls.key": $k}}' > "$FX/shop-tls.json"
    jq -n --arg k "$(base64 -w0 "$d/ec.pem")" \
        '{apiVersion: "v1", kind: "Secret", metadata: {name: "ec", namespace: "shop"},
          type: "Opaque", data: {"key.pem": $k}}' > "$FX/ec.json"
    jq -n --arg h "$(printf postgres.shop.svc.cluster.local | base64 -w0)" \
        --arg u "$(printf shop | base64 -w0)" --arg p "$(printf fake-pass-123 | base64 -w0)" \
        --arg b "$(printf 'a\0b\1' | base64 -w0)" --arg m "$(printf 'line one\nline two\n' | base64 -w0)" \
        '{apiVersion: "v1", kind: "Secret", metadata: {name: "db-creds", namespace: "shop"}, type: "Opaque",
          data: {DB_HOST: $h, DB_USER: $u, DB_PASSWORD: $p, blob: $b, "app.conf": $m, empty: ""}}' > "$FX/db-creds.json"
    cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'SH'
#!/usr/bin/env bash
echo "kubectl $*" >> "$CALLS"
if [[ -n ${KUBE_ERR:-} && $* != config* ]]; then echo "$KUBE_ERR" >&2; exit 1; fi
case " $* " in
    *" config view "*) printf 'kind-kind\tshop' ;;
    *" get secrets "*) printf 'secret/db-creds\nsecret/shop-tls\n' ;;
    *" get secret "*)
        name=$3
        if [[ -f $FX/$name.json ]]; then cat "$FX/$name.json"; exit 0; fi
        echo "Error from server (NotFound): secrets \"$name\" not found" >&2; exit 1 ;;
esac
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/kubectl"
    tb_stub clip 'cat > "$BATS_TEST_TMPDIR/clipboard"; echo "clip $*" >> "$CALLS"'
}

@test "help prints usage and exits 0" {
    run ksecret -h
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: ksecret "* ]]
}

@test "bad usage exits 2" {
    run ksecret
    [ "$status" -eq 2 ]
    run ksecret -c db-creds
    [ "$status" -eq 2 ]
    [[ $output == *"-c copies one value"* ]]
    run ksecret a b c
    [ "$status" -eq 2 ]
    run ksecret --nope x
    [ "$status" -eq 2 ]
}

@test "missing kubectl exits 3" {
    tb_without kubectl
    run ksecret db-creds
    [ "$status" -eq 3 ]
    [[ $output == "ksecret: needs kubectl."* ]]
}

@test "prints every key decoded" {
    run ksecret -n shop db-creds
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "secret shop/db-creds, type Opaque, 6 keys" ]
    [[ $output == *"DB_HOST      postgres.shop.svc.cluster.local"* ]]
    [[ $output == *"DB_PASSWORD  fake-pass-123"* ]]
    [[ $output == *"blob         binary, 4 bytes"* ]]
    [[ $output == *"app.conf     line one"* ]]
    [[ $output == *"             line two"* ]]
    [[ $output == *"empty        (empty)"* ]]
    grep -q -- "get secret db-creds -n shop -o json" "$CALLS"
}

@test "-q drops the header" {
    run ksecret -q db-creds
    [ "${lines[0]}" = "DB_HOST      postgres.shop.svc.cluster.local" ]
}

@test "one key prints the exact value" {
    run ksecret db-creds DB_PASSWORD
    [ "$status" -eq 0 ]
    [ "$output" = "fake-pass-123" ]
    ksecret db-creds app.conf > out
    [ "$(printf 'line one\nline two\n' | sha256sum)" = "$(sha256sum < out)" ]
}

@test "a missing key exits 1 and lists the keys" {
    run ksecret db-creds nope
    [ "$status" -eq 1 ]
    [[ $output == *"no key nope in secret shop/db-creds. Keys are DB_HOST, DB_USER"*"and empty" ]]
}

@test "a missing Secret suggests the closest name" {
    run ksecret db-cred
    [ "$status" -eq 1 ]
    [ "$output" = "ksecret: no Secret db-cred in shop. Did you mean db-creds?" ]
    run ksecret zzzzzzzz
    [ "$status" -eq 1 ]
    [[ $output == *"List them with: kubectl get secrets -n shop" ]]
}

@test "certificates show name and expiry, private keys stay hidden" {
    tb_needs openssl
    run ksecret shop-tls
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "secret shop/shop-tls, type kubernetes.io/tls, 2 keys" ]
    [[ ${lines[1]} == "tls.crt  CN=shop.example.com, expires "*", 79 days left" || ${lines[1]} == *", 80 days left" ]]
    [ "${lines[2]}" = "tls.key  RSA 2048 private key, hidden, use --show-keys" ]
    [[ $output != *"BEGIN PRIVATE KEY"* ]]
    run ksecret ec
    [ "${lines[1]}" = "key.pem  EC 256 private key, hidden, use --show-keys" ]
}

@test "--show-keys prints private keys" {
    tb_needs openssl
    run ksecret --show-keys shop-tls
    [ "$status" -eq 0 ]
    [[ $output == *"tls.key  -----BEGIN PRIVATE KEY-----"* ]]
}

@test "-c copies with clip and prints nothing on stdout" {
    run --separate-stderr ksecret -c db-creds DB_PASSWORD
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$stderr" = "ksecret: copied DB_PASSWORD (13 bytes) to the clipboard" ]
    [ "$(cat "$BATS_TEST_TMPDIR/clipboard")" = "fake-pass-123" ]
}

@test "pass-through options reach kubectl" {
    run ksecret db-creds -- --context kind-kind
    grep -q -- "get secret db-creds -n shop -o json --context kind-kind" "$CALLS"
}

@test "an unreachable cluster exits 1" {
    KUBE_ERR='Unable to connect to the server: dial tcp 10.0.0.1:6443: i/o timeout' run ksecret db-creds
    [ "$status" -eq 1 ]
    [[ $output == *"cannot reach the cluster for context kind-kind"* ]]
}
