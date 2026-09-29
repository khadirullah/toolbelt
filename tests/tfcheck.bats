#!/usr/bin/env bats
# Tests for tfcheck. terraform, tofu, tflint and trivy are stubs, so no
# provider is ever downloaded and terraform init never runs.

load helpers

setup() {
    tb_setup
    export CALLS=$BATS_TEST_TMPDIR/calls
    : > "$CALLS"
    mkdir -p infra
    printf 'variable "region" {\n  type = string\n}\n' > infra/main.tf
    printf 'output "r" {\n  value = var.region\n}\n' > infra/outputs.tf
    # terraform: FMT_LIST is what fmt lists, VALIDATE is the -json answer.
    cat > "$BATS_TEST_TMPDIR/stubs/terraform" <<'SH'
#!/usr/bin/env bash
echo "terraform $*" >> "$CALLS"
case " $* " in
    *" init "*) echo "init must never run" >&2; exit 99 ;;
    *" fmt -check "*)
        [[ -n ${FMT_LIST:-} ]] || exit 0
        printf '%b' "$FMT_LIST"; exit 3 ;;
    *" fmt "*) printf '%b' "${FMT_LIST:-}"; exit 0 ;;
    *" validate "*"-json"*)
        ok='{"valid":true,"error_count":0,"diagnostics":[]}'
        printf '%s\n' "${VALIDATE:-$ok}"
        [[ ${VALIDATE:-} == *'"valid":false'* ]] && exit 1
        exit 0 ;;
esac
exit 0
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/terraform"
}

no_linters() { tb_without tflint trivy tofu; }

@test "help prints usage and exits 0" {
    run tfcheck --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: tfcheck "* ]]
    [ "${lines[1]}" = "Every Terraform check in one pass." ]
}

@test "bad usage exits 2" {
    run tfcheck --only lint infra
    [ "$status" -eq 2 ]
    [[ $output == *"--only takes fmt, validate, tflint or trivy, not lint"* ]]
    run tfcheck infra other
    [ "$status" -eq 2 ]
    run tfcheck --only
    [ "$status" -eq 2 ]
    run tfcheck --fix --only tflint infra
    [ "$status" -eq 2 ]
    run tfcheck --nope
    [ "$status" -eq 2 ]
}

@test "a folder with no .tf files exits 2" {
    mkdir empty
    run tfcheck empty
    [ "$status" -eq 2 ]
    [ "$output" = "tfcheck: no .tf files in $BATS_TEST_TMPDIR/work/empty" ]
}

@test "a missing folder exits 1" {
    run tfcheck nowhere
    [ "$status" -eq 1 ]
    [ "$output" = "tfcheck: nowhere: no such folder" ]
}

@test "no terraform and no tofu exits 3" {
    rm "$BATS_TEST_TMPDIR/stubs/terraform"
    tb_without terraform tofu
    run tfcheck infra
    [ "$status" -eq 3 ]
    [[ $output == "tfcheck: needs terraform."* ]]
}

@test "tofu works when terraform is missing" {
    rm "$BATS_TEST_TMPDIR/stubs/terraform"
    tb_stub tofu 'echo "tofu $*" >> "$CALLS"; [[ $* == *validate* ]] && echo "{\"valid\":true,\"diagnostics\":[]}"; exit 0'
    tb_without terraform tflint trivy
    run tfcheck infra
    [ "$status" -eq 0 ]
    grep -q '^tofu -chdir=infra fmt -check' "$CALLS"
}

@test "a clean module passes and missing linters are skipped" {
    no_linters
    run tfcheck infra
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "fmt       pass" ]
    [ "${lines[1]}" = "validate  pass" ]
    [ "${lines[2]}" = "tflint    skip  not installed, see toolbelt doctor" ]
    [ "${lines[3]}" = "trivy     skip  not installed, see toolbelt doctor" ]
    [ "${lines[4]}" = "all 2 checks passed, 2 skipped" ]
    ! grep -q ' init' "$CALLS"
}

@test "fmt lists the files that need formatting and exits 1" {
    no_linters
    export FMT_LIST='main.tf\noutputs.tf\n'
    run tfcheck infra
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "fmt       fail  2 files need formatting" ]
    [ "${lines[1]}" = "          main.tf" ]
    [ "${lines[3]}" = "          tfcheck --fix rewrites them" ]
    [ "${lines[-1]}" = "1 of 2 checks failed, 2 skipped" ]
    ! grep -q 'fmt -list=true -no-color$' "$CALLS"
}

@test "--fix lets fmt rewrite the files" {
    no_linters
    export FMT_LIST='main.tf\n'
    run tfcheck --fix infra
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "fmt       fixed main.tf" ]
    grep -q '^terraform -chdir=infra fmt -list=true -no-color$' "$CALLS"
}

@test "validate errors show file, line and the detail" {
    no_linters
    export VALIDATE='{"valid":false,"error_count":1,"diagnostics":[{"severity":"error","summary":"Reference to undeclared input variable","detail":"An input variable with the name \"cluster_verison\" has not been declared. Did you mean \"cluster_version\"?","range":{"filename":"main.tf","start":{"line":9}}}]}'
    run tfcheck infra
    [ "$status" -eq 1 ]
    [ "${lines[1]}" = "validate  fail  1 error" ]
    [ "${lines[2]}" = "          main.tf:9  Reference to undeclared input variable" ]
    [[ ${lines[3]} == "            An input variable with the name \"cluster_verison\" has"* ]]
}

@test "validate is skipped when the folder needs init" {
    no_linters
    export VALIDATE='{"valid":false,"error_count":1,"diagnostics":[{"severity":"error","summary":"Missing required provider","detail":"This configuration requires provider registry.terraform.io/hashicorp/aws, but that provider is not available. You may be able to install it automatically by running:\n  terraform init"}]}'
    run tfcheck infra
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "validate  skip  needs terraform init first, see man tfcheck" ]
    ! grep -q ' init' "$CALLS"
}

@test "options after -- go to terraform validate" {
    no_linters
    run tfcheck infra -- -no-tests
    [ "$status" -eq 0 ]
    grep -q '^terraform -chdir=infra validate -no-color -no-tests -json$' "$CALLS"
}

@test "tflint issues are listed from its compact format" {
    tb_stub tflint 'echo "tflint $*" >> "$CALLS"
echo "main.tf:14:21: Error - \"t3.mediun\" is an invalid value as instance_type (aws_instance_invalid_type)"
echo "vpc.tf:3:1: Warning - variable \"azs\" is declared but not used (terraform_unused_declarations)"
exit 2'
    tb_without trivy tofu
    run tfcheck infra
    [ "$status" -eq 1 ]
    [ "${lines[2]}" = "tflint    fail  2 issues" ]
    [ "${lines[3]}" = "          main.tf:14  aws_instance_invalid_type" ]
    [ "${lines[4]}" = "            \"t3.mediun\" is an invalid value as instance_type" ]
    [ "${lines[5]}" = "          vpc.tf:3  terraform_unused_declarations" ]
    grep -q '^tflint --chdir=infra --format=compact --no-color$' "$CALLS"
}

@test "a tflint that cannot run fails with its own message" {
    tb_stub tflint 'echo "Failed to initialize plugins; Plugin \"aws\" not found. Did you run \"tflint --init\"?" >&2; exit 1'
    tb_without trivy tofu
    run tfcheck --only tflint infra
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "tflint    fail  tflint stopped with exit 1" ]
    [[ $output == *"run tflint --init in infra to install its plugins"* ]]
}

@test "trivy counts high and critical findings" {
    tb_stub trivy 'echo "trivy $*" >> "$CALLS"
cat <<JSON
{"Results":[{"Target":"eks.tf","Misconfigurations":[
 {"AVDID":"AVD-AWS-0039","Title":"EKS secrets are not encrypted with a KMS key","Severity":"HIGH","Status":"FAIL","CauseMetadata":{"StartLine":21}},
 {"AVDID":"AVD-AWS-0040","Title":"EKS cluster endpoint is open to the public","Severity":"CRITICAL","Status":"FAIL","CauseMetadata":{"StartLine":8}},
 {"AVDID":"AVD-AWS-0038","Title":"passed","Severity":"HIGH","Status":"PASS"}]}]}
JSON'
    tb_without tflint tofu
    run tfcheck --only trivy infra
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "trivy     fail  1 high, 1 critical" ]
    [ "${lines[1]}" = "          eks.tf:8  AVD-AWS-0040 CRITICAL" ]
    [ "${lines[2]}" = "            EKS cluster endpoint is open to the public" ]
    [ "${lines[3]}" = "          eks.tf:21  AVD-AWS-0039 HIGH" ]
    [ "${lines[-1]}" = "1 of 1 checks failed" ]
    grep -q '^trivy config --quiet --format json --severity HIGH,CRITICAL infra$' "$CALLS"
}

@test "trivy with nothing found passes" {
    tb_stub trivy 'echo "{\"Results\":[]}"'
    tb_without tflint tofu
    run tfcheck --only trivy infra
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "trivy     pass  0 high, 0 critical" ]
    [ "${lines[1]}" = "1 check passed" ]
}

@test "--only a linter that is missing exits 3" {
    tb_without tflint tofu trivy
    run tfcheck --only tflint infra
    [ "$status" -eq 3 ]
    [[ $output == "tfcheck: needs tflint."* ]]
}

@test "--only skips terraform when no terraform check was asked for" {
    rm "$BATS_TEST_TMPDIR/stubs/terraform"
    tb_stub trivy 'echo "{\"Results\":[]}"'
    tb_without terraform tofu tflint
    run tfcheck --only trivy infra
    [ "$status" -eq 0 ]
}

@test "-q prints only the summary and -v shows the commands" {
    no_linters
    export FMT_LIST='main.tf\n'
    run tfcheck -q infra
    [ "$status" -eq 1 ]
    [ "$output" = "1 of 2 checks failed, 2 skipped" ]
    run tfcheck -v infra
    [[ $output == *"+ terraform -chdir=infra fmt -check -list=true -no-color"* ]]
    [[ $output == *"+ terraform -chdir=infra validate -no-color -json"* ]]
}

@test "the files are never changed without --fix" {
    no_linters
    export FMT_LIST='main.tf\n'
    before=$(cat infra/main.tf)
    run tfcheck infra
    [ "$(cat infra/main.tf)" = "$before" ]
    ! grep -q 'fmt -list=true -no-color$' "$CALLS"
}
