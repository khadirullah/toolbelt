#!/usr/bin/env bats
# Tests for ctx. kubectl and git are the real ones, pointed at a kubeconfig
# and a git config made in the test folder, so the real ~/.kube/config and
# ~/.gitconfig are never read or changed. aws and gcloud are only read from
# files made here.

load helpers

setup() {
    tb_setup
    unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_REGION AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID
    unset AWS_CONFIG_FILE AWS_SHARED_CREDENTIALS_FILE CLOUDSDK_CONFIG CLOUDSDK_CORE_PROJECT
    unset CLOUDSDK_ACTIVE_CONFIG_NAME TF_WORKSPACE TF_DATA_DIR CTX_PROD
    export KUBECONFIG=$BATS_TEST_TMPDIR/kubeconfig
    cat > "$KUBECONFIG" <<'EOF'
apiVersion: v1
kind: Config
clusters:
- name: kind-kind
  cluster: {server: "https://127.0.0.1:6443"}
users:
- name: dev
  user: {token: not-a-real-token}
contexts:
- name: kind-kind
  context: {cluster: kind-kind, user: dev, namespace: shop}
- name: kind-delivery
  context: {cluster: kind-kind, user: dev, namespace: delivery}
- name: arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks
  context: {cluster: kind-kind, user: dev, namespace: payments}
current-context: kind-kind
EOF
    export GIT_CONFIG_GLOBAL=$BATS_TEST_TMPDIR/gitconfig GIT_CONFIG_NOSYSTEM=1
    export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR
    printf '[user]\n\tname = Khadirullah\n\temail = khadirullah@example.com\n' > "$GIT_CONFIG_GLOBAL"
    mkdir -p "$HOME/.aws" "$HOME/.config/gcloud/configurations"
    printf '[default]\nregion = ap-south-1\n\n[profile prod-admin]\nregion = eu-west-1\n' > "$HOME/.aws/config"
    echo default > "$HOME/.config/gcloud/active_config"
    printf '[core]\nproject = shop-dev-1234\n' > "$HOME/.config/gcloud/configurations/config_default"
    printf '[core]\nproject = shop-prod-4821\n' > "$HOME/.config/gcloud/configurations/config_work"
    mkdir -p "$HOME/infra/eks"
    touch "$HOME/infra/eks/main.tf"
    cd "$HOME/infra/eks" || return 1
}

@test "help prints usage and exits 0" {
    run ctx --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: ctx [-s] [--prod REGEX]" ]
    [ "${lines[3]}" = "Where your commands will land, on one screen." ]
}

@test "bad usage exits 2" {
    run ctx a b
    [ "$status" -eq 2 ]
    run ctx -l kind-kind
    [ "$status" -eq 2 ]
    run ctx -s kind-kind
    [ "$status" -eq 2 ]
    run ctx --prod '('
    [ "$status" -eq 2 ]
    [[ $output == *"--prod is not a valid pattern"* ]]
    run ctx -n Bad_NS
    [ "$status" -eq 2 ]
    run ctx --nope
    [ "$status" -eq 2 ]
}

@test "switching without kubectl exits 3" {
    tb_without kubectl
    run ctx kind-kind
    [ "$status" -eq 3 ]
    [[ $output == "ctx: needs kubectl."* ]]
}

@test "the full view with nothing in production" {
    run ctx
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "kube       kind-kind, namespace shop" ]
    [ "${lines[1]}" = "aws        profile default, region ap-south-1" ]
    [ "${lines[2]}" = "gcloud     project shop-dev-1234" ]
    [ "${lines[3]}" = "terraform  workspace default, in ~/infra/eks" ]
    [ "${lines[4]}" = "git        Khadirullah, khadirullah@example.com" ]
    [ "${lines[5]}" = "signing    none, commits are not signed" ]
    [ "${#lines[@]}" -eq 6 ]
}

@test "production anywhere exits 1 and says where" {
    echo work > "$HOME/.config/gcloud/active_config"
    mkdir .terraform
    echo prod > .terraform/environment
    kubectl config use-context arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks >/dev/null
    AWS_PROFILE=prod-admin run ctx
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "kube       arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks" ]
    [ "${lines[1]}" = "           namespace payments" ]
    [ "${lines[2]}" = "aws        profile prod-admin, region eu-west-1" ]
    [ "${lines[3]}" = "gcloud     project shop-prod-4821, config work" ]
    [ "${lines[4]}" = "terraform  workspace prod, in ~/infra/eks" ]
    [ "${lines[7]}" = "! context looks like production: kube, aws, gcloud, terraform" ]
}

@test "the default pattern ignores prod inside a word, --prod and CTX_PROD replace it" {
    kubectl config use-context kind-delivery >/dev/null
    run ctx -q
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run ctx -q --prod 'deliv'
    [ "$status" -eq 1 ]
    [ "$output" = "! context looks like production: kube" ]
    CTX_PROD='^kind-' run ctx -q
    [ "$status" -eq 1 ]
}

@test "-s prints one line for a prompt" {
    run ctx -s
    [ "$status" -eq 0 ]
    [ "$output" = "kind-kind/shop aws:default gcp:shop-dev-1234 tf:default" ]
    kubectl config use-context arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks >/dev/null
    cd "$HOME"
    run ctx -s
    [ "$status" -eq 1 ]
    [ "$output" = "! prod-eks/payments aws:default gcp:shop-dev-1234" ]
}

@test "env variables win over the config files" {
    AWS_REGION=us-east-1 AWS_ACCESS_KEY_ID=AKIAEXAMPLE CLOUDSDK_CORE_PROJECT=other-dev TF_WORKSPACE=blue run ctx
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "aws        keys from AWS_ACCESS_KEY_ID, region us-east-1" ]
    [ "${lines[2]}" = "gcloud     project other-dev" ]
    [ "${lines[3]}" = "terraform  workspace blue, in ~/infra/eks" ]
    [[ $output != *AKIAEXAMPLE* ]]
}

@test "tools that are not there, or not set up" {
    rm -r "$HOME/.aws" "$HOME/.config/gcloud"
    cd "$HOME"
    tb_without kubectl aws gcloud terraform tofu
    run ctx
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "kube       kubectl not installed" ]
    [ "${lines[1]}" = "aws        not installed" ]
    [ "${lines[2]}" = "gcloud     not installed" ]
    [ "${lines[3]}" = "terraform  not installed" ]
    tb_stub aws 'exit 0'
    tb_stub gcloud 'exit 0'
    export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
    run ctx
    [ "${lines[1]}" = "aws        no profile or keys set up" ]
    [ "${lines[2]}" = "gcloud     not set up" ]
}

@test "git signing with an ssh key" {
    git config --global gpg.format ssh
    git config --global user.signingkey "$HOME/.ssh/id_ed25519.pub"
    git config --global commit.gpgsign true
    run ctx
    [ "${lines[5]}" = "signing    ssh key ~/.ssh/id_ed25519.pub, commits signed" ]
}

@test "switch by name or part of a name, and back with -" {
    run ctx prod-eks
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "switched to arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks, namespace payments" ]
    [[ ${lines[1]} == "ctx: ! arn:aws:eks:"*" looks like production" ]]
    [ "$(kubectl config current-context)" = "arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks" ]
    run ctx -
    [ "$status" -eq 0 ]
    [ "$output" = "switched to kind-kind, namespace shop" ]
    [ "$(kubectl config current-context)" = kind-kind ]
}

@test "switch refuses an unknown or unclear name" {
    run ctx nope
    [ "$status" -eq 1 ]
    [ "$output" = "ctx: no context named nope. List them with: ctx -l" ]
    run ctx kind
    [ "$status" -eq 1 ]
    [ "$output" = "ctx: kind matches 2 contexts: kind-delivery, kind-kind. Give more of the name" ]
    run ctx -
    [ "$status" -eq 1 ]
    [ "$output" = "ctx: no previous context yet" ]
    [ "$(kubectl config current-context)" = kind-kind ]
}

@test "-n sets the namespace, -v shows the kubectl command" {
    run ctx -v -n billing
    [ "$status" -eq 0 ]
    [[ $output == *"+ kubectl config set-context --current --namespace=billing"* ]]
    [[ $output == *"switched to kind-kind, namespace billing" ]]
    [ "$(kubectl config view --minify -o 'jsonpath={..namespace}')" = billing ]
    run ctx kind-delivery -n shop
    [ "$output" = "switched to kind-delivery, namespace shop" ]
}

@test "-l lists contexts with the current and production ones marked" {
    run ctx -l
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "  arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks  payments  ! production" ]
    [ "${lines[1]}" = "  kind-delivery                                         delivery" ]
    [ "${lines[2]}" = "* kind-kind                                             shop" ]
}
