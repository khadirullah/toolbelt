# certcheck

Days until a TLS certificate expires.

## Synopsis

```
certcheck [options] HOST[:PORT] | FILE ... [-- s_client options]
certcheck [options] -f LIST
```

## Description

Every HTTPS site, mail server and API has a TLS certificate with an end date. After that date browsers show a
full-page warning, `curl` refuses to connect, and mail servers stop delivering. Let's Encrypt certificates last 90
days and renew themselves, until the renewal job breaks quietly. `certcheck` tells you how many days a
certificate has left, who issued it and which names it covers, so you find a broken renewal weeks before your
users do.

Give it a host, and it connects with `openssl s_client`, reads the certificate the server sends, and hands it to
`openssl x509`. Give it a file, and it reads the file with `openssl x509` alone, with no network. A `.pem`, `.crt`
or `.cer` file in PEM form works, and so does DER, the binary form. For a file with a whole chain, such as
`fullchain.pem`, it reads the first certificate, which is the one for your site.

One target prints one line. Several targets, or `-f LIST`, print a table and a summary line. Either way it exits
1 when any certificate has fewer days left than the warning window, has expired, or cannot be read, so a cron job
or a CI step can act on it.

`certcheck` checks dates. It does not check that the chain leads to a trusted root, that the name matches, or that
the server's TLS settings are sound. Pass `-- -verify_return_error` to make s_client fail on an untrusted chain.

## Options

| Option | What it does |
|---|---|
| `-w`, `--warn DAYS` | The warning window. Exit 1 when fewer days are left. 30 by default. `-w 0` flags only expired ones. |
| `-f`, `--file LIST` | Read targets from a file, one per line. `-` reads standard input. Blank lines and text after `#` are ignored. Targets on the command line are checked too. |
| `-t`, `--timeout SECS` | Give up on a host after this many seconds. 5 by default. |
| `-q`, `--quiet` | In a table, show only the rows with a problem, then the summary line. |
| `-v`, `--verbose` | Show each step and each `openssl` command before it runs. |
| `-h`, `--help` | Show the help. |

## Targets

A target is a host, a host and port, a URL or a file.

| You type | certcheck connects to |
|---|---|
| `example.com` | `example.com:443` |
| `example.com:8443` | `example.com:8443` |
| `https://example.com/login` | `example.com:443`. The scheme and path are dropped. |
| `192.0.2.10` | `192.0.2.10:443`, with no server name sent |
| `[2001:db8::1]:8443` | that IPv6 address on port 8443 |
| `./site.pem`, `site.crt`, `/etc/ssl/x.pem` | no connection, it reads the file |

A target counts as a file when the file exists, when it has a `/` in it, or when it ends in `.pem`, `.crt`, `.cer`
or `.der`. A missing file gives `no such file` rather than a DNS lookup of `site.pem`.

For a name, `certcheck` sends it as the server name (SNI). One server often hosts many sites and picks the
certificate by that name. An IP address gets no server name, so you see the server's default certificate.

## How it decides

- Days left are rounded to the nearest day. A certificate that ends in 11 days and 20 hours shows 12.
- `warn` means fewer days left than `--warn`. `expired` means the end date has passed. Days show as a negative
  number then.
- `error` means no certificate could be read. The row or the message says why. An error counts as a failure.
- The issuer column joins the issuer's organisation and name, as in `Let's Encrypt E7`. When the name already has
  the organisation in it, as in `Amazon RSA 2048 M02`, it shows the name alone. Long ones are cut to 28
  characters in the table.
- The names come from the certificate's subject alternative names. A single line shows the first 4 and a count of
  the rest.

## Pass-through

Options after `--` go to `openssl s_client`, for hosts only. The common use is a mail or database port that
starts in plain text and switches to TLS.

```console
$ certcheck smtp.example.com:587 -- -starttls smtp
$ certcheck imap.example.com:143 -- -starttls imap
$ certcheck db.example.com:5432 -- -starttls postgres
```

Port 465 for SMTP and 993 for IMAP speak TLS from the start and need no pass-through.

## Needs

`openssl`, from the `openssl` package on every distro. `timeout` from coreutils is used for `--timeout` when it is
there. Without it, a host that never answers can make `certcheck` wait for the system's TCP timeout, which is
often two minutes.

## Examples

### One site

```console
$ certcheck example.com
example.com  87 days  SSL Corporation Cloudflare TLS Issuing ECC CA 3  example.com *.example.com
```

### Every site in one run

```console
$ cat hosts.txt
# production sites
./shop.pem
./api.pem
./many.pem
intranet.example.com
$ certcheck -f hosts.txt
HOST                  DAYS  ISSUER               EXPIRES
./shop.pem              61  Let's Encrypt E7     2026-11-29
./api.pem               12  Let's Encrypt R12    2026-10-11  warn
./many.pem             200  Amazon RSA 2048 M02  2027-04-17
intranet.example.com     -  -                    -           error, not found in DNS
4 certificates, 1 warn, 1 failed
$ echo $?
1
```

### Only the problems, for cron

```console
$ certcheck -q -f hosts.txt
./api.pem               12  Let's Encrypt R12    2026-10-11  warn
intranet.example.com     -  -                    -           error, not found in DNS
4 certificates, 1 warn, 1 failed
```

A crontab line that mails you only when something is wrong:

```
0 8 * * * certcheck -q -w 21 -f ~/hosts.txt >/tmp/certs.txt || mail -s "certificates" you@example.com </tmp/certs.txt
```

### A file on disk, with the commands shown

```console
$ certcheck -v ./api.pem
certcheck: reading ./api.pem
+ openssl x509 -in ./api.pem -noout -enddate -issuer -subject -ext subjectAltName -nameopt multiline
./api.pem  12 days  Let's Encrypt R12  api.example.com
certcheck: ./api.pem expires on 2026-10-11, inside the 30 day warning window
```

### A certificate with many names

```console
$ certcheck many.pem
many.pem  200 days  Amazon RSA 2048 M02  a.example.com b.example.com c.example.com d.example.com +2 more
```

### Did the renewal work?

Run it against the file certbot wrote and against the live site. When the file has the new date and the site has
the old one, the web server has not reloaded the new certificate yet.

```console
$ sudo certcheck /etc/letsencrypt/live/shop.example.com/cert.pem shop.example.com
```

### A host that does not answer

```console
$ certcheck intranet.example.com
certcheck: cannot find intranet.example.com in DNS
$ certcheck -t 2 10.0.0.99
certcheck: cannot connect to 10.0.0.99:443, timed out after 2s
```

## Troubleshooting

`certcheck: cannot connect to HOST:443, connection refused`
: Nothing listens on that port. Check the port, and check it from the server with `port 443`.

`certcheck: cannot connect to HOST:443, timed out after 5s`
: A firewall drops the packets, or the host is down. Raise the limit with `-t 15` for a slow network.

`certcheck: HOST:25 does not speak TLS here. For a mail port try: certcheck HOST:25 -- -starttls smtp`
: The port speaks plain text first. Pass the right `-starttls` protocol after `--`.

`certcheck: FILE is not a certificate, openssl x509 cannot read it`
: The file holds something else, often the private key. Certbot keeps the certificate in `cert.pem` and the key
  in `privkey.pem`.

The days differ from what the browser shows
: The site may serve a different certificate for another name. Give the exact name the browser uses, since
  `certcheck` sends it as the server name.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every certificate has at least the warning window left. |
| 1 | A certificate expires inside the warning window, has expired, or could not be read. |
| 2 | Bad usage, such as no target or a `--warn` that is not a number. |
| 3 | `openssl` is not installed. |

## See also

`dnscheck`, `httptime`, `openssl-s_client(1)`, `openssl-x509(1)`
