# dnscheck

The DNS records email depends on.

## Synopsis

```
dnscheck [-s SELECTOR ...] DOMAIN [-- dig options]
```

## Description

Mail from your domain lands in spam, or bounces, most often because of a DNS record. Gmail, Outlook and Yahoo now
reject bulk mail from domains without SPF, DKIM and DMARC. `dnscheck` looks up the five records that decide
whether mail to and from a domain works, and prints one line for each, with `pass`, `warn`, `fail` or `skip` and
the record it found.

| Line | What it looks up | What it is for |
|---|---|---|
| `A` | The A record of the domain, or AAAA when there is no A | Where the website lives. Mail does not need it. |
| `MX` | The MX records | Which servers take mail for the domain. |
| `SPF` | The TXT record that starts with `v=spf1` | Which servers may send mail as the domain. |
| `DKIM` | The TXT record at `SELECTOR._domainkey.DOMAIN` | The public key that checks the signature on each message. |
| `DMARC` | The TXT record at `_dmarc.DOMAIN` | What a receiver does with mail that fails SPF and DKIM, and where to send reports. |

`dnscheck` only reads DNS. It asks the resolver your system uses, unless you name another server after `--`. It
changes nothing and sends no mail.

## Options

| Option | What it does |
|---|---|
| `-s`, `--selector NAME` | The DKIM selector to look up. Repeat it for each one, as in `-s google -s s1`. |
| `-q`, `--quiet` | Print only the `warn` and `fail` lines. Nothing at all means every check passed. |
| `-v`, `--verbose` | Show each step and each `dig` command before it runs. |
| `-h`, `--help` | Show the help. |

The domain may be written as a URL or a mail address. `https://Example.com/contact` and `postmaster@example.com`
both check `example.com`.

## How each check decides

### A

`pass` with up to 3 addresses. `warn` when the domain has neither A nor AAAA, which is fine for a domain that only
handles mail.

### MX

`pass` with the servers in order of preference, lowest number first. A single `0 .` record is a null MX, a
statement that the domain takes no mail at all, and passes. No MX record at all is a `fail`. Senders then fall
back to the A record, which almost never runs a mail server.

### SPF

| Result | When |
|---|---|
| `fail` | No SPF record. Any server can claim to send as the domain. |
| `fail` | More than one TXT record starts with `v=spf1`. Receivers treat that as an error and SPF fails for every message. |
| `fail` | More than 10 DNS lookups. See below. |
| `fail` | An `include:` names a domain with no SPF record. |
| `fail` | The record ends in `+all` or a bare `all`, which lets every server on the internet pass. |
| `warn` | It ends in `?all`, or has no `all` and no `redirect=`. Mail from other servers is neither passed nor failed. |
| `pass` | Anything else. The line shows the record, cut to 60 characters, and the lookup count. |

The count follows the rules of RFC 7208. Each `include`, `redirect`, `a`, `mx`, `ptr` and `exists` term costs one
lookup, and `dnscheck` follows every `include` and `redirect` and counts the terms in those records too. `ip4`,
`ip6` and `all` cost nothing. Past 10 lookups, receivers stop and treat SPF as broken. Adding one more mail
service to a record with 9 lookups is the usual way to cross the limit.

### DKIM

The selector is a name your mail provider picks, and DNS has no way to list them. Google Workspace uses
`google`, Microsoft 365 uses `selector1` and `selector2`, Mailchimp uses `k1`, and SendGrid uses `s1` and `s2`.
Your provider's admin page shows the one it uses. Without `-s`, the DKIM line says `skip`, which does not count as
a failure.

| Result | When |
|---|---|
| `fail` | No record at `SELECTOR._domainkey.DOMAIN`. |
| `fail` | The record has an empty `p=`, which means the key was revoked. |
| `fail` | An RSA key under 1024 bits. |
| `warn` | An RSA key of 1024 bits. Many receivers now want 2048. |
| `pass` | RSA 2048 or more, or an Ed25519 key. |

The key size is worked out from the length of the base64 key, which is exact enough to tell 1024 from 2048 and
4096. A record split into several quoted strings, as long keys are, is joined first. A CNAME that points the
selector at the provider, as SendGrid and Microsoft 365 use, is followed by the resolver.

### DMARC

| Result | When |
|---|---|
| `fail` | No record at `_dmarc.DOMAIN`, more than one, or no valid `p=` policy. |
| `warn` | `p=none`. Receivers still deliver mail that fails, so the record only collects reports. |
| `warn` | `p=quarantine` or `p=reject` with `pct=` under 100, so only part of the failing mail is caught. |
| `pass` | `p=quarantine` or `p=reject`. The line shows where reports go, from `rua=`. |

A subdomain with no DMARC record of its own is covered by the parent's record in practice, through its `sp=` tag.
`dnscheck` checks only the exact domain you give, so check the parent too.

## Pass-through

Options after `--` go to `dig`, or to `drill` when `dig` is missing. The common use is asking a particular DNS
server, to see what the rest of the world sees rather than a local cache.

```console
$ dnscheck example.com -- @1.1.1.1
$ dnscheck example.com -- @ns1.example-dns.com
```

Asking the domain's own name server shows a change the moment you save it. Public resolvers show it once the old
record's TTL runs out.

## Needs

`dig`, or `drill` when `dig` is missing.

| Distro | dig | drill |
|---|---|---|
| Debian, Ubuntu | `sudo apt install bind9-dnsutils` | `sudo apt install ldnsutils` |
| Fedora, RHEL | `sudo dnf install bind-utils` | `sudo dnf install ldns-utils` |
| Arch | `sudo pacman -S bind` | `sudo pacman -S ldns` |
| openSUSE | `sudo zypper install bind-utils` | `sudo zypper install ldns` |
| Alpine | `sudo apk add bind-tools` | `sudo apk add drill` |

## Examples

### A domain on Google Workspace with everything right

```console
$ dnscheck -s google example.com
A      pass  93.184.215.14
MX     pass  1 smtp.google.com
SPF    pass  v=spf1 include:_spf.google.com ~all, 4 lookups
DKIM   pass  google._domainkey, RSA 2048
DMARC  pass  p=quarantine, reports to dmarc@example.com
```

Google's own SPF record includes three more, so one `include:` costs 4 of the 10 lookups.

### A domain that sends no mail at all

```console
$ dnscheck example.com
A      pass  104.20.23.154, 172.66.147.243
MX     pass  null MX, this domain takes no mail
SPF    pass  v=spf1 -all, 0 lookups
DKIM   skip  give a selector with -s, your mail provider names it
DMARC  pass  p=reject, no reports asked for
```

This is the right setup for a domain that must never appear as a sender. It stops anyone from using it for
phishing.

### Why is our mail in spam?

```console
$ dnscheck -s s1 shop.example.com
A      pass  203.0.113.7
MX     pass  10 mx1.example.com, 20 mx2.example.com
SPF    fail  2 SPF records, a domain may have only one
DKIM   fail  no record at s1._domainkey.shop.example.com
DMARC  warn  p=none, failing mail is still delivered, no reports asked for
$ echo $?
1
```

Someone added SendGrid as a second SPF record instead of adding `include:sendgrid.net` to the first one. Merge
them into `v=spf1 mx include:sendgrid.net -all`, and add the DKIM record from SendGrid's setup page.

### Every step, for a record with too many lookups

```console
$ dnscheck -v news.example.com
dnscheck: looking up the address of news.example.com
+ dig +noall +answer +time=3 +tries=2 A news.example.com
+ dig +noall +answer +time=3 +tries=2 AAAA news.example.com
A      warn  no A or AAAA record, fine for a domain that only does mail
dnscheck: looking up the mail servers of news.example.com
+ dig +noall +answer +time=3 +tries=2 MX news.example.com
MX     pass  10 mx.example.com
dnscheck: looking up the SPF record of news.example.com
+ dig +noall +answer +time=3 +tries=2 TXT news.example.com
+ dig +noall +answer +time=3 +tries=2 TXT a.example.net
+ dig +noall +answer +time=3 +tries=2 TXT ca.example.net
+ dig +noall +answer +time=3 +tries=2 TXT b.example.net
+ dig +noall +answer +time=3 +tries=2 TXT cb.example.net
SPF    fail  14 DNS lookups, the limit is 10
DKIM   skip  give a selector with -s, your mail provider names it
dnscheck: looking up the DMARC policy at _dmarc.news.example.com
+ dig +noall +answer +time=3 +tries=2 TXT _dmarc.news.example.com
DMARC  fail  no record at _dmarc.news.example.com
```

### Only the problems

```console
$ dnscheck -q news.example.com
A      warn  no A or AAAA record, fine for a domain that only does mail
SPF    fail  14 DNS lookups, the limit is 10
DMARC  fail  no record at _dmarc.news.example.com
```

### Several DKIM selectors

```console
$ dnscheck -s selector1 -s selector2 example.com
```

Microsoft 365 publishes two selectors and switches between them when it rotates keys. Check both.

## Troubleshooting

`dnscheck: no answer from the DNS server (...). Check the network, or ask another server with: dnscheck DOMAIN -- @1.1.1.1`
: No DNS server answered within 3 seconds, twice. Check the network with `netcheck`. On a network that blocks
  outside DNS, leave out the `@` server.

`dnscheck: DOMAIN does not exist in DNS, check the spelling`
: The DNS server said the name does not exist (NXDOMAIN). A new domain can take a few hours to appear.

`DKIM fail no record at SELECTOR._domainkey.DOMAIN`, but the provider says DKIM is on
: The selector is wrong, or the record went in with the domain written twice, as in
  `s1._domainkey.example.com.example.com`. Many DNS panels add the domain for you.

You fixed a record and `dnscheck` still shows the old one
: Your resolver caches the old answer until its TTL runs out. Ask the domain's own name server after `--` to see
  the new record now.

`SPF fail N DNS lookups, the limit is 10`
: Remove services you no longer use, replace an `a` or `mx` term with the `ip4:` addresses it stands for, or ask
  your provider for a flattened record.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every check passed, was skipped, or only warned. |
| 1 | At least one check failed, the domain does not exist, or no DNS server answered. |
| 2 | Bad usage, such as no domain or a selector with spaces. |
| 3 | Neither `dig` nor `drill` is installed. |

## See also

`certcheck`, `netcheck`, `myip`, `dig(1)`, `drill(1)`, RFC 7208 (SPF), RFC 6376 (DKIM), RFC 7489 (DMARC)
