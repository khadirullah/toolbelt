#!/usr/bin/env bats
# Tests for jwtpeek. Every token is made up here, from JSON typed in the test.

load helpers

setup() {
    tb_setup
    export TZ=UTC
    NOW=$(date +%s)
}

# base64url without padding, the way a JWT encodes each part.
b64u() { printf '%s' "$1" | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '='; }

# A token from a header and a claims object.
token() { printf '%s.%s.%s' "$(b64u "$1")" "$(b64u "$2")" "${3-c2lnbmF0dXJl}"; }

@test "help prints usage and exits 0" {
    run jwtpeek --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: jwtpeek [--json] [TOKEN]" ]
    [ "${lines[2]}" = "Decode a JWT and show when it expires." ]
}

@test "bad usage exits 2" {
    run jwtpeek --nope
    [ "$status" -eq 2 ]
    [[ $output == *"unknown option --nope"* ]]
    run jwtpeek a.b.c d.e.f
    [ "$status" -eq 2 ]
    [[ $output == *"one token at a time"* ]]
    run jwtpeek </dev/null
    [ "$status" -eq 2 ]
    [[ $output == *"no token given"* ]]
}

@test "a missing parser exits 3" {
    t=$(token '{"alg":"HS256"}' "{\"exp\":$((NOW + 60))}")
    tb_without jq python3
    run jwtpeek "$t"
    [ "$status" -eq 3 ]
    [[ $output == "jwtpeek: needs jq."* ]]
}

@test "--json works without jq or python3" {
    t=$(token '{"alg":"HS256"}' '{"sub":"u1"}')
    tb_without jq python3
    run jwtpeek --json "$t"
    [ "$status" -eq 0 ]
    [ "$output" = '{"header":{"alg":"HS256"},"claims":{"sub":"u1"}}' ]
}

@test "decodes header and claims with times and time left" {
    t=$(token '{"alg":"RS256","typ":"JWT","kid":"7f3c1a9e"}' \
        "{\"iss\":\"https://auth.example.com/\",\"sub\":\"user_8412\",\"aud\":[\"api.example.com\",\"web\"],\"iat\":$((NOW - 1080)),\"exp\":$((NOW + 2550)),\"org\":{\"id\":7}}")
    run jwtpeek "$t"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "header" ]
    [ "${lines[1]}" = "  alg  RS256" ]
    [ "${lines[4]}" = "claims" ]
    [ "${lines[5]}" = "  iss  https://auth.example.com/" ]
    [ "${lines[7]}" = "  aud  api.example.com web" ]
    [[ ${lines[8]} == "  iat  "*" UTC, 18m ago" ]]
    [[ ${lines[9]} == "  exp  "*" UTC" ]]
    [ "${lines[10]}" = '  org  {"id":7}' ]
    [ "${lines[11]}" = "expires in 42m" ]
    [ "${lines[12]}" = "signature not checked" ]
}

@test "python3 gives the same table as jq" {
    t=$(token '{"alg":"RS256"}' "{\"sub\":\"u1\",\"aud\":[\"a\",\"b\"],\"n\":3,\"ok\":true,\"exp\":$((NOW + 630))}")
    run jwtpeek "$t"
    with_jq=$output
    tb_without jq
    run jwtpeek "$t"
    [ "$status" -eq 0 ]
    [ "$output" = "$with_jq" ]
}

@test "reads stdin and strips a Bearer prefix" {
    t=$(token '{"alg":"HS256"}' "{\"exp\":$((NOW + 7230))}")
    run bash -c "printf 'Authorization: Bearer %s\n' '$t' | jwtpeek -q"
    [ "$status" -eq 0 ]
    [ "$output" = "expires in 2h" ]
    run bash -c "echo 'Bearer $t' | jwtpeek -q"
    [ "$output" = "expires in 2h" ]
}

@test "an expired token exits 1" {
    t=$(token '{"alg":"HS256"}' "{\"exp\":$((NOW - 72000))}")
    run jwtpeek -q "$t"
    [ "$status" -eq 1 ]
    [[ $output == "expired 20h ago, at "*" UTC" ]]
}

@test "a token that is not valid yet exits 1" {
    t=$(token '{"alg":"HS256"}' "{\"nbf\":$((NOW + 630)),\"exp\":$((NOW + 3600))}")
    run jwtpeek -q "$t"
    [ "$status" -eq 1 ]
    [[ $output == "not valid until "*", in 10m" ]]
}

@test "no exp claim says it never expires" {
    t=$(token '{"alg":"HS256"}' '{"sub":"svc"}')
    run jwtpeek -q "$t"
    [ "$status" -eq 0 ]
    [ "$output" = "no exp claim, it never expires" ]
}

@test "alg none gets a warning" {
    t=$(token '{"alg":"none"}' '{"sub":"x"}' "")
    run jwtpeek "$t"
    [ "$status" -eq 0 ]
    [[ $output == *"no signature, alg none. Never accept a token like this"* ]]
}

@test "--json prints header and claims as one object" {
    t=$(token '{"alg":"HS256"}' '{"sub":"u1","n":2}')
    run jwtpeek --json "$t"
    [ "$status" -eq 0 ]
    [ "$output" = '{"header":{"alg":"HS256"},"claims":{"sub":"u1","n":2}}' ]
    run bash -c "jwtpeek --json '$t' | jq -r .claims.sub"
    [ "$output" = u1 ]
}

@test "not a JWT exits 2" {
    run jwtpeek hello.world
    [ "$status" -eq 2 ]
    [ "$output" = "jwtpeek: not a JWT, expected 3 parts separated by dots, found 2" ]
    run jwtpeek 'a!b.c.d'
    [ "$status" -eq 2 ]
    [[ $output == *"the header is not base64url"* ]]
    run jwtpeek "$(b64u 'plain text').$(b64u '{}').x"
    [ "$status" -eq 2 ]
    [[ $output == *"the header is not JSON"* ]]
    run jwtpeek "$(b64u '{"alg":1').$(b64u '{}').x"
    [ "$status" -eq 2 ]
    [[ $output == *"the header is not a JSON object"* ]]
}

@test "an encrypted token says why it cannot be read" {
    run jwtpeek "$(b64u '{"alg":"RSA-OAEP","enc":"A256GCM"}').a.b.c.d"
    [ "$status" -eq 2 ]
    [[ $output == *"encrypted token (JWE, 5 parts)"* ]]
}

@test "-v shows the size of each part" {
    t=$(token '{"alg":"HS256"}' '{"sub":"u1"}')
    run jwtpeek -v "$t"
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "jwtpeek: header 15 bytes, claims 12 bytes, signature 12 characters" ]]
}
