#!/usr/bin/env bats
# Tests for yamlcheck. yamllint, kubeconform and kubectl are stubs. The
# python3 check runs for real on files of a few bytes.

load helpers

setup() {
    tb_setup
    export CALLS=$BATS_TEST_TMPDIR/calls
    : > "$CALLS"
    mkdir -p deploy
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: web\n' > deploy/cm.yaml
    printf 'apiVersion: v1\nkind: Service\nmetadata:\n  name: web\nspec:\n  ports:\n    - port: "8080"\n' > deploy/svc.yaml
    printf 'image: nginx\nreplicas: 2\nimage: httpd\n' > values.yaml
    printf 'a: 1\nb:\n\tc: 2\n' > tabs.yaml
}

# A yamllint that reports what LINT says, in its parsable format.
lint_stub() {
    tb_stub yamllint 'echo "yamllint $*" >> "$CALLS"
printf "%b" "${LINT:-}"
[[ ${LINT:-} == *"[error]"* ]] && exit 1
[[ ${LINT:-} == *"[warning]"* ]] && exit 2
exit 0'
}

# A kubeconform that answers with the JSON in KC.
kube_stub() {
    tb_stub kubeconform 'echo "kubeconform $*" >> "$CALLS"
none="{\"resources\":[]}"
printf "%s\n" "${KC:-$none}"'
}

@test "help prints usage and exits 0" {
    run yamlcheck --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: yamlcheck "* ]]
    [ "${lines[2]}" = "Lint YAML and check Kubernetes manifests." ]
}

@test "bad usage exits 2" {
    run yamlcheck --kube-version 1.31 deploy
    [ "$status" -eq 2 ]
    [[ $output == *"--kube-version works with -k"* ]]
    kube_stub
    run yamlcheck -k --kube-version latest deploy
    [ "$status" -eq 2 ]
    run yamlcheck --kube-version
    [ "$status" -eq 2 ]
    run yamlcheck --nope
    [ "$status" -eq 2 ]
}

@test "with neither yamllint nor python3 it exits 3" {
    tb_without yamllint python3
    run yamlcheck values.yaml
    [ "$status" -eq 3 ]
    [[ $output == "yamlcheck: needs yamllint."* ]]
}

@test "-k without kubeconform exits 3 with a way to install it" {
    tb_without yamllint kubeconform
    run yamlcheck -k deploy
    [ "$status" -eq 3 ]
    [[ $output == "yamlcheck: needs kubeconform for -k. Install it"* ]]
}

@test "options after -- need yamllint" {
    tb_without yamllint
    run yamlcheck deploy -- -c x.yaml
    [ "$status" -eq 3 ]
    [[ $output == "yamlcheck: needs yamllint."* ]]
}

@test "missing paths and empty folders exit 1" {
    tb_without yamllint
    run yamlcheck nowhere.yaml
    [ "$status" -eq 1 ]
    [ "$output" = "yamlcheck: nowhere.yaml: no such file or folder" ]
    mkdir empty
    run yamlcheck empty/
    [ "$status" -eq 1 ]
    [ "$output" = "yamlcheck: no .yaml or .yml files in empty" ]
}

@test "without yamllint python3 finds duplicate keys and tabs" {
    python3 -c "import yaml" 2>/dev/null || skip "python3 has no yaml module"
    tb_without yamllint
    run yamlcheck values.yaml tabs.yaml deploy
    [ "$status" -eq 1 ]
    [[ $output == *"yamllint is missing, so only syntax, tabs and duplicate keys were checked"* ]]
    [[ $output == *$'values.yaml\n  3:1     error  duplicate key "image"'* ]]
    [[ $output == *$'tabs.yaml\n  3:1     error  tab character, YAML allows spaces only'* ]]
    [[ $output == *"deploy/cm.yaml  pass"* ]]
    [ "${lines[-1]}" = "4 files, 2 pass, 2 fail" ]
}

@test "a syntax error shows its line" {
    python3 -c "import yaml" 2>/dev/null || skip "python3 has no yaml module"
    tb_without yamllint
    printf 'ports: [80, 443\nname: x\n' > broken.yml
    run yamlcheck broken.yml
    [ "$status" -eq 1 ]
    [[ ${lines[-2]} == "  2:5     error  syntax error, "* ]]
    [ "${lines[-1]}" = "1 file, 1 fail" ]
}

@test "a clean file passes and exits 0" {
    python3 -c "import yaml" 2>/dev/null || skip "python3 has no yaml module"
    tb_without yamllint
    run yamlcheck -q deploy/cm.yaml
    [ "$status" -eq 0 ]
    [ "$output" = "1 file, 1 pass" ]
}

@test "python3 without a yaml module still checks tabs, with a warning" {
    tb_without yamllint
    mkdir -p "$BATS_TEST_TMPDIR/py"
    echo 'raise ImportError("no yaml here")' > "$BATS_TEST_TMPDIR/py/yaml.py"
    PYTHONPATH=$BATS_TEST_TMPDIR/py run yamlcheck values.yaml tabs.yaml
    [ "$status" -eq 1 ]
    [[ $output == *"python3 has no yaml module and yamllint is missing, so only tabs were checked"* ]]
    [[ $output == *"values.yaml  pass"* ]]
    [[ $output == *"tab character"* ]]
}

@test "yamllint findings are grouped by file with friendlier words" {
    lint_stub
    export LINT='deploy/svc.yaml:7:81: [warning] line too long (96 > 80 characters) (line-length)\nvalues.yaml:3:1: [error] duplication of key "image" in mapping (key-duplicates)\ntabs.yaml:3:1: [error] syntax error: found character '"'\\\\t'"' that cannot start any token (syntax)\n'
    run yamlcheck values.yaml tabs.yaml deploy -- -c .yamllint.yaml
    [ "$status" -eq 1 ]
    [[ $output == *$'values.yaml\n  3:1     error  duplicate key "image"\n'* ]]
    [[ $output == *$'tabs.yaml\n  3:1     error  tab character, YAML allows spaces only\n'* ]]
    [[ $output == *$'deploy/svc.yaml\n  7:81    warn   line too long (96 > 80 characters) (line-length)'* ]]
    # python3 found the same duplicate and tab, and they show once.
    [ "$(grep -c 'duplicate key' <<<"$output")" -eq 1 ]
    [ "$(grep -c 'tab character' <<<"$output")" -eq 1 ]
    [ "${lines[-1]}" = "4 files, 2 pass, 2 fail" ]
    grep -q '^yamllint -f parsable -c .yamllint.yaml values.yaml tabs.yaml deploy/cm.yaml deploy/svc.yaml$' "$CALLS"
}

@test "warnings pass unless --strict" {
    lint_stub
    export LINT='deploy/cm.yaml:1:1: [warning] missing document start "---" (document-start)\n'
    run yamlcheck deploy/cm.yaml
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "1 file, 1 pass" ]
    run yamlcheck --strict deploy/cm.yaml
    [ "$status" -eq 1 ]
    [ "${lines[-1]}" = "1 file, 1 fail" ]
}

@test "-k shows schema errors and notes from kubeconform" {
    lint_stub
    kube_stub
    tb_stub kubectl 'exit 1'
    export KC='{"resources":[
 {"filename":"deploy/svc.yaml","kind":"Service","name":"web","version":"v1","status":"statusInvalid","msg":"x","validationErrors":[{"path":"/spec/ports/0/port","msg":"expected integer, but got string"}]},
 {"filename":"deploy/cm.yaml","kind":"ConfigMap","name":"web","status":"statusValid"},
 {"filename":"deploy/crd.yaml","kind":"Certificate","name":"site","status":"statusSkipped"}]}'
    printf 'apiVersion: cert-manager.io/v1\nkind: Certificate\nmetadata:\n  name: site\n' > deploy/crd.yaml
    run yamlcheck -k deploy
    [ "$status" -eq 1 ]
    [[ $output == *$'deploy/svc.yaml\n  schema  error  Service web, spec.ports[0].port: expected integer, but got string'* ]]
    [[ $output == *$'deploy/crd.yaml  pass\n  schema  skip   no schema for Certificate site'* ]]
    [[ $output == *"deploy/cm.yaml  pass"* ]]
    [ "${lines[-1]}" = "3 files, 2 pass, 1 fail" ]
    grep -q '^kubeconform -output json -verbose -ignore-missing-schemas -cache .*/toolbelt/kubeconform deploy/cm.yaml' "$CALLS"
    ! grep -q 'kubernetes-version' "$CALLS"
}

@test "-k leaves out files that are not valid YAML" {
    python3 -c "import yaml" 2>/dev/null || skip "python3 has no yaml module"
    kube_stub
    tb_stub kubectl 'exit 1'
    tb_without yamllint
    run yamlcheck -k values.yaml deploy/cm.yaml
    [ "$status" -eq 1 ]
    grep -q ' deploy/cm.yaml$' "$CALLS"
    ! grep -q 'values.yaml' "$CALLS"
}

@test "--kube-version picks the schema, and the cluster's version is the default" {
    lint_stub
    kube_stub
    run yamlcheck -k --kube-version 1.31 deploy/cm.yaml
    [ "$status" -eq 0 ]
    grep -q -- '-kubernetes-version 1.31.0 deploy/cm.yaml' "$CALLS"
    : > "$CALLS"
    tb_stub kubectl 'echo "kubectl $*" >> "$CALLS"; echo "{\"clientVersion\":{\"gitVersion\":\"v1.33.1\"},\"serverVersion\":{\"gitVersion\":\"v1.30.4-eks-1234\"}}"'
    run yamlcheck -k deploy/cm.yaml
    [ "$status" -eq 0 ]
    grep -q '^kubectl version -o json --request-timeout=3s$' "$CALLS"
    grep -q -- '-kubernetes-version 1.30.4 deploy/cm.yaml' "$CALLS"
}

@test "files that are not manifests get a note under -k, not a failure" {
    lint_stub
    kube_stub
    tb_stub kubectl 'exit 1'
    printf 'replicas: 2\n' > plain.yaml
    export KC='{"resources":[{"filename":"plain.yaml","status":"statusError","msg":"error while parsing: missing '"'"'kind'"'"' key"}]}'
    run yamlcheck -k plain.yaml
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "  schema  skip   not a Kubernetes manifest, schema check skipped" ]
}

@test "-v shows the commands" {
    lint_stub
    run yamlcheck -v deploy/cm.yaml
    [[ $output == *"+ yamllint -f parsable deploy/cm.yaml"* ]]
    [[ $output == *"yamlcheck: checking 1 file"* ]]
}

@test "no argument checks the current folder" {
    tb_without yamllint
    cd deploy
    run yamlcheck
    [ "$status" -eq 0 ]
    [[ $output == *"cm.yaml  pass"* ]]
    [[ $output != *"./cm.yaml"* ]]
}
