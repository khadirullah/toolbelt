#!/usr/bin/env bats
# Tests for dnscheck. dig and drill are stubs that answer from a small zone
# file written in each test, so nothing goes to a real DNS server.

load helpers

# A zone line: name, type, then the record as dig prints it.
zone() { printf '%s\n' "$@" >> "$ZONE"; }

# base64 of N bytes, the length of a DKIM key of that size.
key() { head -c "$1" /dev/zero | base64 | tr -d '\n'; }

setup() {
    tb_setup
    export ZONE=$BATS_TEST_TMPDIR/zone CALLS=$BATS_TEST_TMPDIR/calls
    : > "$ZONE"
    : > "$CALLS"
    cat > "$BATS_TEST_TMPDIR/stubs/dig" <<'SH'
#!/usr/bin/env bash
echo "dig $*" >> "$CALLS"
if [[ -n ${DNS_DOWN:-} ]]; then
    echo ";; communications error to 127.0.0.53#53: timed out"
    echo ";; no servers could be reached"
    exit 9
fi
args=("$@")
n=${#args[@]}
type=${args[n-2]} name=${args[n-1]}
if [[ " $* " == *" +comments "* ]]; then
    if awk -v n="$name" '$1 == n { f = 1 } END { exit !f }' "$ZONE"; then s=NOERROR; else s=NXDOMAIN; fi
    echo ";; ->>HEADER<<- opcode: QUERY, status: $s, id: 4242"
    exit 0
fi
awk -v n="$name" -v t="$type" '$1 == n && $2 == t {
    r = $0; sub(/^[^ ]+ [^ ]+ /, "", r); printf "%s.\t300\tIN\t%s\t%s\n", n, t, r }' "$ZONE"
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/dig"
    cat > "$BATS_TEST_TMPDIR/stubs/drill" <<'SH'
#!/usr/bin/env bash
echo "drill $*" >> "$CALLS"
args=("$@")
n=${#args[@]}
name=${args[n-2]} type=${args[n-1]}
echo ";; ->>HEADER<<- opcode: QUERY, rcode: NOERROR, id: 4242"
echo ";; ANSWER SECTION:"
awk -v n="$name" -v t="$type" '$1 == n && $2 == t {
    r = $0; sub(/^[^ ]+ [^ ]+ /, "", r); printf "%s.\t300\tIN\t%s\t%s\n", n, t, r }' "$ZONE"
echo
echo ";; AUTHORITY SECTION:"
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/drill"
}

# A domain with every record right, like one on Google Workspace.
good_domain() {
    zone "example.com A 93.184.215.14" \
         "example.com MX 1 smtp.google.com." \
         'example.com TXT "v=spf1 include:_spf.google.com ~all"' \
         'example.com TXT "google-site-verification=abc123"' \
         '_spf.google.com TXT "v=spf1 include:_netblocks.google.com include:_netblocks2.google.com include:_netblocks3.google.com ~all"' \
         '_netblocks.google.com TXT "v=spf1 ip4:35.190.247.0/24 ~all"' \
         '_netblocks2.google.com TXT "v=spf1 ip6:2001:4860:4000::/36 ~all"' \
         '_netblocks3.google.com TXT "v=spf1 ip4:172.217.0.0/19 ~all"' \
         "google._domainkey.example.com TXT \"v=DKIM1; k=rsa; \" \"p=$(key 294)\"" \
         '_dmarc.example.com TXT "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"'
}

@test "help prints usage and exits 0" {
    run dnscheck --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: dnscheck [-s SELECTOR ...] DOMAIN [-- dig options]" ]
    [ "${lines[1]}" = "The DNS records email depends on." ]
}

@test "bad usage exits 2" {
    run dnscheck
    [ "$status" -eq 2 ]
    [[ $output == *"give a domain"* ]]
    run dnscheck example.com example.org
    [ "$status" -eq 2 ]
    run dnscheck -s 'bad sel' example.com
    [ "$status" -eq 2 ]
    run dnscheck 'exa mple.com'
    [ "$status" -eq 2 ]
    [[ $output == *"not a domain name"* ]]
    run dnscheck --nope example.com
    [ "$status" -eq 2 ]
}

@test "no dig and no drill exits 3" {
    tb_without dig drill
    run dnscheck example.com
    [ "$status" -eq 3 ]
    [[ $output == "dnscheck: needs dig."* ]]
}

@test "a domain with every record right passes" {
    good_domain
    run dnscheck -s google example.com
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "A      pass  93.184.215.14" ]
    [ "${lines[1]}" = "MX     pass  1 smtp.google.com" ]
    [ "${lines[2]}" = "SPF    pass  v=spf1 include:_spf.google.com ~all, 4 lookups" ]
    [ "${lines[3]}" = "DKIM   pass  google._domainkey, RSA 2048" ]
    [ "${lines[4]}" = "DMARC  pass  p=quarantine, reports to dmarc@example.com" ]
}

@test "no selector skips DKIM without failing" {
    good_domain
    run dnscheck example.com
    [ "$status" -eq 0 ]
    [ "${lines[3]}" = "DKIM   skip  give a selector with -s, your mail provider names it" ]
}

@test "two SPF records, a missing DKIM key and p=none" {
    zone "example.com A 93.184.215.14" \
         "example.com MX 20 mx2.example.com." "example.com MX 10 mx1.example.com." \
         'example.com TXT "v=spf1 mx -all"' 'example.com TXT "v=spf1 include:sendgrid.net ~all"' \
         '_dmarc.example.com TXT "v=DMARC1; p=none"'
    run dnscheck -s s1 example.com
    [ "$status" -eq 1 ]
    [ "${lines[1]}" = "MX     pass  10 mx1.example.com, 20 mx2.example.com" ]
    [ "${lines[2]}" = "SPF    fail  2 SPF records, a domain may have only one" ]
    [ "${lines[3]}" = "DKIM   fail  no record at s1._domainkey.example.com" ]
    [ "${lines[4]}" = "DMARC  warn  p=none, failing mail is still delivered, no reports asked for" ]
}

@test "a warn alone still exits 0" {
    good_domain
    sed -i 's/p=quarantine; rua=mailto:dmarc@example.com/p=none/' "$ZONE"
    run dnscheck example.com
    [ "$status" -eq 0 ]
    [[ ${lines[4]} == "DMARC  warn  p=none"* ]]
}

@test "SPF over 10 lookups fails" {
    zone "example.com MX 10 mx.example.com." \
         'example.com TXT "v=spf1 a mx include:a.example.net include:b.example.net ~all"' \
         '_dmarc.example.com TXT "v=DMARC1; p=reject"'
    for x in a b; do
        zone "$x.example.net TXT \"v=spf1 a mx ptr exists:x.example.net a:y mx:z include:c$x.example.net -all\""
        zone "c$x.example.net TXT \"v=spf1 ip4:192.0.2.0/24 -all\""
    done
    run dnscheck example.com
    [ "$status" -eq 1 ]
    [ "${lines[2]}" = "SPF    fail  18 DNS lookups, the limit is 10" ]
}

@test "SPF +all fails, ?all warns, a broken include fails" {
    zone "example.com MX 10 mx.example.com." 'example.com TXT "v=spf1 mx +all"' \
         '_dmarc.example.com TXT "v=DMARC1; p=reject"'
    run dnscheck example.com
    [ "${lines[2]}" = "SPF    fail  +all lets any server send mail as example.com" ]
    sed -i 's/+all/?all/' "$ZONE"
    run dnscheck example.com
    [ "$status" -eq 0 ]
    [ "${lines[2]}" = "SPF    warn  ?all, mail from other servers is neither passed nor failed" ]
    sed -i 's/mx ?all/include:gone.example.net -all/' "$ZONE"
    run dnscheck example.com
    [ "$status" -eq 1 ]
    [ "${lines[2]}" = "SPF    fail  include:gone.example.net has no SPF record, so SPF fails for every message" ]
}

@test "null MX, -all and reject, a domain that sends no mail" {
    zone "example.com A 104.20.23.154" "example.com A 172.66.147.243" "example.com MX 0 ." \
         'example.com TXT "v=spf1 -all"' '_dmarc.example.com TXT "v=DMARC1;p=reject;sp=reject;adkim=s;aspf=s"'
    run dnscheck example.com
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "A      pass  104.20.23.154, 172.66.147.243" ]
    [ "${lines[1]}" = "MX     pass  null MX, this domain takes no mail" ]
    [ "${lines[2]}" = "SPF    pass  v=spf1 -all, 0 lookups" ]
    [ "${lines[4]}" = "DMARC  pass  p=reject, no reports asked for" ]
}

@test "no MX fails and no address warns" {
    zone 'example.com TXT "v=spf1 -all"' '_dmarc.example.com TXT "v=DMARC1; p=reject"'
    run dnscheck example.com
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "A      warn  no A or AAAA record, fine for a domain that only does mail" ]
    [ "${lines[1]}" = "MX     fail  no MX record, mail for example.com has nowhere to go" ]
}

@test "DKIM key sizes, types and a revoked key" {
    good_domain
    zone "old._domainkey.example.com TXT \"v=DKIM1; k=rsa; p=$(key 162)\"" \
         'ed._domainkey.example.com TXT "v=DKIM1; k=ed25519; p=11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="' \
         'gone._domainkey.example.com TXT "v=DKIM1; p="'
    run dnscheck -s old -s ed -s gone example.com
    [ "$status" -eq 1 ]
    [ "${lines[3]}" = "DKIM   warn  old._domainkey, RSA 1024, use 2048 or more" ]
    [ "${lines[4]}" = "DKIM   pass  ed._domainkey, Ed25519" ]
    [ "${lines[5]}" = "DKIM   fail  gone._domainkey, the key is revoked, p= is empty" ]
}

@test "DMARC for part of the mail, and several report addresses" {
    good_domain
    sed -i 's/p=quarantine; rua=mailto:dmarc@example.com/p=reject; pct=25; rua=mailto:a@example.com,mailto:b@example.net/' "$ZONE"
    run dnscheck example.com
    [ "$status" -eq 0 ]
    [ "${lines[4]}" = "DMARC  warn  p=reject for only 25% of failing mail, reports to a@example.com, b@example.net" ]
}

@test "-q shows only warn and fail lines" {
    zone "example.com A 93.184.215.14" "example.com MX 10 mx.example.com." \
         'example.com TXT "v=spf1 mx -all"' '_dmarc.example.com TXT "v=DMARC1; p=none"'
    run dnscheck -q example.com
    [ "$status" -eq 0 ]
    [ "$output" = "DMARC  warn  p=none, failing mail is still delivered, no reports asked for" ]
}

@test "-v shows each dig command, and -- passes options to dig" {
    good_domain
    run dnscheck -v example.com -- @1.1.1.1
    [ "$status" -eq 0 ]
    [[ $output == *"dnscheck: looking up the address of example.com"* ]]
    [[ $output == *"+ dig +noall +answer +time=3 +tries=2 @1.1.1.1 A example.com"* ]]
    [[ $output == *"+ dig +noall +answer +time=3 +tries=2 @1.1.1.1 TXT _dmarc.example.com"* ]]
    grep -q "^dig +noall +answer +time=3 +tries=2 @1.1.1.1 MX example.com$" "$CALLS"
}

@test "a DNS server that does not answer exits 1" {
    DNS_DOWN=1 run dnscheck example.com
    [ "$status" -eq 1 ]
    [[ $output == "dnscheck: no answer from the DNS server (communications error to 127.0.0.53#53: timed out). Check the network"* ]]
}

@test "a domain that does not exist exits 1" {
    run dnscheck nosuch.example
    [ "$status" -eq 1 ]
    [[ $output == *"dnscheck: nosuch.example does not exist in DNS, check the spelling" ]]
}

@test "drill works when dig is missing" {
    good_domain
    tb_without dig
    run dnscheck -s google example.com
    [ "$status" -eq 0 ]
    [ "${lines[2]}" = "SPF    pass  v=spf1 include:_spf.google.com ~all, 4 lookups" ]
    grep -q "^drill example.com A$" "$CALLS"
}

@test "a URL or a mail address becomes the domain" {
    good_domain
    run dnscheck https://Example.COM/contact
    [ "$status" -eq 0 ]
    run dnscheck postmaster@example.com.
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "A      pass  93.184.215.14" ]
}
