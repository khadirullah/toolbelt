# jwtpeek

Decode a JWT and show when it expires.

## Synopsis

```
jwtpeek [--json] [TOKEN]
command | jwtpeek [--json]
```

## Description

A JSON Web Token, or JWT, is the long `eyJ...` string that an API gets in its `Authorization: Bearer` header. It
has three parts joined by dots. The first two are JSON written in base64url, the header and the claims. The third
is the signature. `jwtpeek` decodes the first two and prints them as a table, with every time claim turned into a
local date and how long ago or how long from now that is. The last line says whether the token has expired.

`jwtpeek` reads the token from its argument, or from standard input when there is no argument. It strips spaces,
newlines, quotes, a `Bearer ` prefix and a whole `Authorization: Bearer ` header line, so you can paste what your
browser's network tab or a `curl -v` log shows.

It never checks the signature. That needs the issuer's key, and a tool that decodes without it can only tell you
what the token claims, not whether the claims are true. It also never sends the token anywhere. Decoding is local
work with `base64`, and the table comes from `jq` or `python3`.

## Options

| Option | What it does |
|---|---|
| `--json` | Print the header and claims as one JSON object, `{"header":{...},"claims":{...}}`, for `jq`. |
| `-q`, `--quiet` | Print only the expiry line, such as `expires in 42m` or `expired 20h ago, at ...`. |
| `-v`, `--verbose` | Say how many bytes each part decoded to, before the table. |
| `-h`, `--help` | Show the help. |

## How it reads the claims

Top-level claims print one per line, in the order the token has them. Strings print as they are. A list of strings,
such as `aud` or `groups`, prints joined with spaces. Numbers, `true`, `false` and `null` print as JSON. A nested
object prints as compact JSON on one line, so `realm_access` from Keycloak shows as `{"roles":["admin","dev"]}`.
Use `--json` with `jq` to dig into nested claims.

These claims hold a time in seconds since 1970 and print as a local date: `exp`, `iat`, `nbf`, `auth_time` and
`updated_at`. `iat`, `nbf` and the others also get how long ago or how long ahead that is. `exp` gets its own line
at the end.

| Claim | Meaning | What `jwtpeek` does with it |
|---|---|---|
| `exp` | Expires at | The last line says `expires in 42m`, or `expired 20h ago` and exit 1. |
| `nbf` | Not valid before | When it is in the future, prints `not valid until ...` and exits 1. |
| `iat` | Issued at | Shown with how long ago. |
| `iss` | Issuer | Shown. The URL of the login server that made the token. |
| `sub` | Subject | Shown. The user or service the token is for. |
| `aud` | Audience | Shown. The API the token is meant for. A token for another API is refused there. |

A token with no `exp` claim prints `no exp claim, it never expires`. That is legal, and worth knowing about.

## Safety

- Tokens are passwords while they are valid. Pass one on standard input, as in `clip -o | jwtpeek`, rather than as
  an argument. An argument ends up in your shell history and in `ps` output for other users on the machine.
- `jwtpeek` reads at most 64 KB from standard input, so a wrong pipe cannot fill memory.
- A token with an empty signature and `alg` set to `none` gets the note `no signature, alg none. Never accept a
  token like this`. An API that accepts such a token lets anyone write their own claims.
- An encrypted token, a JWE with 5 parts, cannot be read without the key. `jwtpeek` says so and exits 2.

## Pass-through

None. Decoding needs only `base64`.

## Needs

`base64` from coreutils, installed everywhere. The table needs `jq` or `python3`, and uses the first one it finds.
`--json` needs neither, and checks the JSON when one of them is there. Install `jq` with `sudo apt install jq`,
`sudo dnf install jq`, `sudo pacman -S jq`, `sudo zypper install jq` or `sudo apk add jq`.

## Examples

### What is in this token?

```console
$ clip -o | jwtpeek
header
  alg  RS256
  typ  JWT
  kid  7f3c1a9e
claims
  iss    https://auth.example.com/
  sub    user_8412
  aud    api.example.com
  scope  orders:read orders:write
  iat    2026-09-29 20:15:32 IST, 18m ago
  exp    2026-09-29 21:16:02 IST
expires in 42m
signature not checked
```

`kid` names the key the issuer signed with. The issuer publishes its keys at a URL such as
`https://auth.example.com/.well-known/jwks.json`.

### Why does the API say 401?

```console
$ echo "$TOKEN" | jwtpeek -q
expired 20h ago, at 2026-09-29 00:33:32 IST
$ echo $?
1
```

### Stop a script before it uses an old token

```bash
if ! printf '%s' "$TOKEN" | jwtpeek -q >/dev/null; then
    TOKEN=$(get-new-token)
fi
```

### Nested claims and a token that is not valid yet

```console
$ jwtpeek "$TOKEN"
header
  alg  ES256
  typ  JWT
claims
  sub             42
  realm_access    {"roles":["admin","dev"]}
  groups          ops sre
  email_verified  true
  nbf             2026-09-29 20:44:02 IST, in 10m
  exp             2026-09-29 21:34:02 IST
not valid until 2026-09-29 20:44:02 IST, in 10m
expires in 1h
signature not checked
```

When `nbf` is a few seconds or minutes ahead, the clock of the machine that made the token and the clock of this
machine disagree. Check both with `timedatectl`.

### Raw JSON for jq

```console
$ jwtpeek --json "$TOKEN"
{"header":{"alg":"HS256","typ":"JWT"},"claims":{"sub":"ci-bot","exp":1790622212}}
$ jwtpeek --json "$TOKEN" | jq -r '.claims.realm_access.roles[]'
admin
dev
```

### A token with no signature

```console
$ jwtpeek "$TOKEN"
header
  alg  none
claims
  sub   admin
  role  admin
no exp claim, it never expires
no signature, alg none. Never accept a token like this
```

### Something that is not a JWT

```console
$ jwtpeek hello.world
jwtpeek: not a JWT, expected 3 parts separated by dots, found 2
```

## Troubleshooting

`jwtpeek: not a JWT, expected 3 parts separated by dots, found 1`
: The text has no dots. You may have copied an opaque access token, which is a random string that only the
  issuer can look up, or a refresh token. Only JWTs can be decoded.

`jwtpeek: not a JWT, the header is not base64url`
: The copy picked up extra characters, such as a trailing comma from a JSON file. Copy the token again, from `eyJ`
  to the last character before the closing quote.

`jwtpeek: this is an encrypted token (JWE, 5 parts), its claims cannot be read without the key`
: The claims are encrypted for the API that reads them. Ask the issuer, or decode it where the key lives.

`jwtpeek: needs jq. Install it with: ...`
: Neither `jq` nor `python3` is installed. Install one, or use `--json`, which needs neither.

Times look an hour or more off
: `jwtpeek` prints local time from the `TZ` variable and `/etc/localtime`. Run `TZ=UTC jwtpeek` to compare with a
  log in UTC.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The token decoded and has not expired, or has no `exp` claim. |
| 1 | The token has expired, or its `nbf` time is still ahead. |
| 2 | Bad usage, no token, or the text is not a JWT that can be read. |
| 3 | Neither `jq` nor `python3` is installed, for the table. |

## See also

`clip`, `epoch`, `jq(1)`, `base64(1)`, RFC 7519
