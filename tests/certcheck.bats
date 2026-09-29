#!/usr/bin/env bats
# Tests for certcheck. Certificates are tiny self-signed ones made here with
# openssl req. openssl s_client is a stub, so no test touches the network.

load helpers

# A self-signed ed25519 certificate that expired on 2020-01-01. It has no
# key anywhere and is only good for testing dates.
OLD_PEM='-----BEGIN CERTIFICATE-----
MIIBSjCB/aADAgECAhQ8Lt+c58LHj/xvUcp5RKPuG75j5DAFBgMrZXAwGzEZMBcG
A1UEAwwQb2xkLnRlc3QuZXhhbXBsZTAeFw0xOTAxMDEwMDAwMDBaFw0yMDAxMDEw
MDAwMDBaMBsxGTAXBgNVBAMMEG9sZC50ZXN0LmV4YW1wbGUwKjAFBgMrZXADIQAX
P6PIVV0LLRCa4U6NnsAkQVPtvKgVki92LRLgq+09UqNTMFEwHQYDVR0OBBYEFFky
2gLi11x36fxxNmpL1dmdlaEAMB8GA1UdIwQYMBaAFFky2gLi11x36fxxNmpL1dmd
laEAMA8GA1UdEwEB/wQFMAMBAf8wBQYDK2VwA0EAhbp4u0FeGou1TQa2JEnTExWS
irv5RBvbXDaXECcx6PYgh0jUhTXw3O7az52Ve/ccQq+kkDcTxS1qa6Pc/i7FBQ==
-----END CERTIFICATE-----'

# make_cert FILE DAYS SUBJECT [SAN]
make_cert() {
    local san=()
    [[ -n ${4:-} ]] && san=(-addext "subjectAltName=$4")
    "$REAL_OPENSSL" req -x509 -newkey ed25519 -keyout "$BATS_TEST_TMPDIR/key.pem" -out "$1" \
        -days "$2" -nodes -subj "$3" "${san[@]}" 2>/dev/null
}

setup() {
    tb_setup
    tb_needs openssl
    REAL_OPENSSL=$(command -v openssl)
    export REAL_OPENSSL
    export CALLS=$BATS_TEST_TMPDIR/calls
    : > "$CALLS"
    make_cert "$BATS_TEST_TMPDIR/good.pem" 90 "/O=Let's Encrypt/CN=E7" \
        "DNS:example.com,DNS:www.example.com"
    make_cert "$BATS_TEST_TMPDIR/soon.pem" 12 "/O=Let's Encrypt/CN=R12" "DNS:api.example.com"
    printf '%s\n' "$OLD_PEM" > "$BATS_TEST_TMPDIR/old.pem"
    export SERVE=$BATS_TEST_TMPDIR/good.pem SCLIENT=ok
    # s_client prints the certificate it is told to serve, or fails the way
    # SCLIENT says. Every other openssl command is the real one.
    cat > "$BATS_TEST_TMPDIR/stubs/openssl" <<'SH'
#!/usr/bin/env bash
if [[ $1 == s_client ]]; then
    echo "openssl $*" >> "$CALLS"
    case $SCLIENT in
        ok)      echo "CONNECTED(00000003)"; cat "$SERVE"; echo "---"; exit 0 ;;
        refused) echo "connect:errno=111" >&2; echo "Connection refused" >&2; exit 1 ;;
        dns)     echo "BIO_lookup_ex:system lib:Name or service not known" >&2; exit 1 ;;
        timeout) exit 124 ;;
        plain)   echo "error:0A00010B:SSL routines::wrong version number" >&2; exit 1 ;;
    esac
fi
exec "$REAL_OPENSSL" "$@"
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/openssl"
}

@test "help prints usage and exits 0" {
    run certcheck --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: certcheck [options] HOST[:PORT] | FILE ... [-- s_client options]" ]
    [ "${lines[2]}" = "Days until a TLS certificate expires." ]
}

@test "bad usage exits 2" {
    run certcheck
    [ "$status" -eq 2 ]
    [[ $output == *"give a host, a file or -f LIST"* ]]
    run certcheck -w soon example.com
    [ "$status" -eq 2 ]
    run certcheck -t 0 example.com
    [ "$status" -eq 2 ]
    run certcheck --nope
    [ "$status" -eq 2 ]
    run certcheck -f
    [ "$status" -eq 2 ]
}

@test "no openssl exits 3" {
    tb_without openssl
    run certcheck example.com
    [ "$status" -eq 3 ]
    [[ $output == "certcheck: needs openssl."* ]]
}

@test "a PEM file with time left" {
    cp "$BATS_TEST_TMPDIR/good.pem" site.pem
    run certcheck ./site.pem
    [ "$status" -eq 0 ]
    [ "$output" = "./site.pem  90 days  Let's Encrypt E7  example.com www.example.com" ]
}

@test "a DER file reads the same" {
    "$REAL_OPENSSL" x509 -in "$BATS_TEST_TMPDIR/good.pem" -outform DER -out site.der
    run certcheck site.der
    [ "$status" -eq 0 ]
    [[ $output == "site.der  90 days  Let's Encrypt E7  "* ]]
}

@test "inside the warning window exits 1" {
    run certcheck "$BATS_TEST_TMPDIR/soon.pem"
    [ "$status" -eq 1 ]
    [[ ${lines[0]} == *"soon.pem  12 days  Let's Encrypt R12  api.example.com" ]]
    [[ ${lines[1]} == "certcheck: "*"soon.pem expires on "*", inside the 30 day warning window" ]]
    run certcheck -w 7 "$BATS_TEST_TMPDIR/soon.pem"
    [ "$status" -eq 0 ]
}

@test "an expired certificate exits 1 with negative days" {
    run certcheck "$BATS_TEST_TMPDIR/old.pem"
    [ "$status" -eq 1 ]
    [[ ${lines[0]} =~ old\.pem\ \ -[0-9]+\ days\ \ old\.test\.example\ \ old\.test\.example$ ]]
    [[ ${lines[1]} == *"old.pem expired "*" days ago, on 2020-01-01" ]]
}

@test "a file that is not a certificate, or is missing" {
    echo "hello" > notes.pem
    run certcheck notes.pem
    [ "$status" -eq 1 ]
    [ "$output" = "certcheck: notes.pem is not a certificate, openssl x509 cannot read it" ]
    run certcheck ./gone.pem
    [ "$status" -eq 1 ]
    [ "$output" = "certcheck: ./gone.pem: no such file" ]
}

@test "a host goes through s_client with SNI on port 443" {
    run certcheck example.com
    [ "$status" -eq 0 ]
    [ "$output" = "example.com  90 days  Let's Encrypt E7  example.com www.example.com" ]
    [ "$(cat "$CALLS")" = "openssl s_client -connect example.com:443 -servername example.com" ]
}

@test "a URL, a port and pass-through options" {
    run certcheck https://example.com/login?x=1
    [ "$status" -eq 0 ]
    [[ $output == "example.com  90 days"* ]]
    : > "$CALLS"
    run certcheck smtp.example.com:587 -- -starttls smtp
    [ "$status" -eq 0 ]
    [[ $output == "smtp.example.com:587  90 days"* ]]
    [ "$(cat "$CALLS")" = "openssl s_client -connect smtp.example.com:587 -servername smtp.example.com -starttls smtp" ]
}

@test "an address gets no SNI, and IPv6 gets brackets" {
    run certcheck 192.0.2.10:8443
    [ "$status" -eq 0 ]
    run certcheck '[2001:db8::1]'
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$CALLS")" = "openssl s_client -connect 192.0.2.10:8443" ]
    [ "$(sed -n 2p "$CALLS")" = "openssl s_client -connect [2001:db8::1]:443" ]
}

@test "connection errors say what went wrong" {
    SCLIENT=refused run certcheck example.com
    [ "$status" -eq 1 ]
    [ "$output" = "certcheck: cannot connect to example.com:443, connection refused" ]
    SCLIENT=dns run certcheck intranet.example.com
    [ "$output" = "certcheck: cannot find intranet.example.com in DNS" ]
    SCLIENT=timeout run certcheck -t 2 intranet.example.com
    [ "$status" -eq 1 ]
    [ "$output" = "certcheck: cannot connect to intranet.example.com:443, timed out after 2s" ]
    SCLIENT=plain run certcheck mail.example.com:25
    [[ $output == *"mail.example.com:25 does not speak TLS here. For a mail port try: certcheck mail.example.com:25 -- -starttls smtp" ]]
}

@test "a list gives a table and a summary" {
    cp "$BATS_TEST_TMPDIR/soon.pem" api.pem
    cp "$BATS_TEST_TMPDIR/old.pem" old.pem
    printf '# my sites\nexample.com\n\n./api.pem   # the api\n./old.pem\n' > hosts.txt
    run certcheck -f hosts.txt
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "HOST         DAYS  ISSUER             EXPIRES" ]
    [[ ${lines[1]} == "example.com    90  Let's Encrypt E7   "* ]]
    [[ ${lines[2]} == "./api.pem      12  Let's Encrypt R12  "*"  warn" ]]
    [[ ${lines[3]} == *"2020-01-01  expired" ]]
    [ "${lines[4]}" = "3 certificates, 1 warn, 1 expired" ]
}

@test "a list from stdin with a failed host" {
    run bash -c 'printf "example.com\nwww.example.com\n" | SCLIENT=ok certcheck -f -'
    [ "$status" -eq 0 ]
    [ "${lines[3]}" = "2 hosts, all good for 30 days or more" ]
    run bash -c 'printf "down.example.com\n" | SCLIENT=refused certcheck -f -'
    [ "$status" -eq 1 ]
    [[ ${lines[1]} == "down.example.com     -  -       -           error, connection refused" ]]
    [ "${lines[2]}" = "1 host, 1 failed" ]
}

@test "-q shows only problems and the summary" {
    run certcheck -q "$BATS_TEST_TMPDIR/good.pem" "$BATS_TEST_TMPDIR/soon.pem"
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -eq 2 ]
    [[ ${lines[0]} == *"soon.pem"*"warn" ]]
    [ "${lines[1]}" = "2 files, 1 warn" ]
}

@test "-v shows the openssl commands" {
    run certcheck -v example.com
    [ "$status" -eq 0 ]
    [[ $output == *"+ openssl s_client -connect example.com:443 -servername example.com"* ]]
    [[ $output == *"+ openssl x509 -in "*" -noout -enddate -issuer -subject -ext subjectAltName -nameopt multiline"* ]]
}
