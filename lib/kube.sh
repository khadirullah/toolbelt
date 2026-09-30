# shellcheck shell=bash
# Helpers for the kubectl wrappers: kwhy, ksecret, kyaml, kclean, kfwd,
# kres, knodes and kevents. Sourced after lib/common.sh. They read TB_PASS
# for the options after -- and write kubectl errors to $TMP/kerr.

# The --context and --kubeconfig options from after --, in KCFG, for the
# kubectl config calls that reject other options.
kube_cfg_args() {
    KCFG=()
    local i a
    for ((i = 0; i < ${#TB_PASS[@]}; i++)); do
        a=${TB_PASS[i]}
        case $a in
            --context=*|--kubeconfig=*) KCFG+=("$a") ;;
            --context|--kubeconfig) KCFG+=("$a" "${TB_PASS[i + 1]:-}"); ((i++)) ;;
        esac
    done
}

# The context in KCTX and its default namespace in KNS. Reads only the
# kubeconfig, so it works when the cluster is down.
kube_where() {
    local out
    kube_cfg_args
    out=$(kubectl config view --minify ${KCFG[@]+"${KCFG[@]}"} \
        -o 'jsonpath={.current-context}{"\t"}{.contexts[0].context.namespace}' 2>/dev/null) || out=""
    KCTX=${out%%$'\t'*}
    KNS=""
    [[ $out == *$'\t'* ]] && KNS=${out#*$'\t'}
    [[ -n $KNS ]] || KNS=default
    return 0
}

# Run kubectl with the options from after -- added at the end. Stdout goes
# to the file given first, stderr to $TMP/kerr. Usage: kube_to file get pods -o json
kube_to() {
    local out=$1
    shift
    tb_show kubectl "$@" ${TB_PASS[@]+"${TB_PASS[@]}"}
    kubectl "$@" ${TB_PASS[@]+"${TB_PASS[@]}"} >"$out" 2>"$TMP/kerr"
}

# True when the last kubectl call failed because the object does not exist.
kube_notfound() { grep -q '(NotFound)\| not found' "$TMP/kerr" 2>/dev/null; }

# Turn the last kubectl error into one clear message and exit 1.
kube_fail() {
    local err first
    err=$(head -c 2000 "$TMP/kerr" 2>/dev/null)
    first=$(grep -m1 -v '^[[:space:]]*$' <<<"$err" | sed -E 's/^(error: |Error from server( \([A-Za-z]+\))?: )//')
    case $err in
        *"localhost:8080"*|*"current-context is not set"*|*"current-context must exist"*)
            tb_die 1 "kubectl has no cluster set up. Pick one with: kubectl config use-context NAME" ;;
        *"Unable to connect to the server"*|*"connection refused"*|*"no such host"*|*"i/o timeout"*|\
        *"couldn't get current server API group list"*|*"was refused"*)
            tb_err "cannot reach the cluster for context ${KCTX:-unknown}"
            [[ ${KCTX:-} == kind-* ]] && tb_die 1 "is the kind container running? Try: kind get clusters"
            tb_die 1 "check it with: kubectl cluster-info" ;;
        *"(Unauthorized)"*|*"must be logged in"*|*"provide credentials"*)
            tb_die 1 "the cluster did not accept your login for context ${KCTX:-unknown}, log in again" ;;
        *"(Forbidden)"*)
            tb_die 1 "the cluster refused: $first" ;;
    esac
    tb_die 1 "kubectl failed: ${first:-no message}"
}

# "a", "a and b", "a, b and c".
join_and() {
    local n=$# out="" i=0 a
    for a in "$@"; do
        ((i++))
        if (( i == 1 )); then out=$a
        elif (( i == n )); then out+=" and $a"
        else out+=", $a"; fi
    done
    echo "$out"
}

# The closest name to a typo, from a list on stdin.
closest() {
    awk -v w="$1" '
        function dist(a, b,    i, j, la, lb, d, c, x, y, z) {
            la = length(a); lb = length(b)
            for (i = 0; i <= la; i++) d[i, 0] = i
            for (j = 0; j <= lb; j++) d[0, j] = j
            for (i = 1; i <= la; i++)
                for (j = 1; j <= lb; j++) {
                    c = (substr(a, i, 1) == substr(b, j, 1)) ? 0 : 1
                    x = d[i - 1, j] + 1; y = d[i, j - 1] + 1; z = d[i - 1, j - 1] + c
                    d[i, j] = (x < y ? (x < z ? x : z) : (y < z ? y : z))
                }
            return d[la, lb]
        }
        NF { k = dist(w, $1); if (best == "" || k < best) { best = k; pick = $1 } }
        END { if (best != "" && best <= 2 + int(length(w) / 6)) print pick }'
}
