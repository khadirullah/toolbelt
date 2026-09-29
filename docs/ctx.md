# ctx

Where your commands will land, on one screen.

## Synopsis

```
ctx [-s] [--prod REGEX]
ctx [-n NAMESPACE] [CONTEXT | -]
ctx -l
```

## Description

`kubectl delete`, `terraform apply` and `aws s3 rm` act on whatever cluster, account or workspace the current
settings point at. Those settings live in five different places, and each tool has its own command to show them.
The classic mistake is a delete meant for a test cluster that runs against production, because a context switched
an hour ago in another terminal.

`ctx` reads all of them and prints one screen:

| Line | Where it comes from |
|---|---|
| `kube` | The current context and its namespace, from `kubectl config`. `KUBECONFIG` is honoured. |
| `aws` | The profile from `AWS_PROFILE`, and the region from `AWS_REGION` or the profile in `~/.aws/config`. |
| `gcloud` | The project of the active gcloud configuration, from `~/.config/gcloud`. |
| `terraform` | The workspace of the Terraform folder you are in, from `TF_WORKSPACE` or `.terraform/environment`. |
| `git` | The `user.name` and `user.email` that a commit here would get. |
| `signing` | The key git signs commits with, and whether it signs them. |

Any line whose name looks like production is printed in red in a terminal, and a last line starting with `!` names
them. Then `ctx` exits 1, so a script can stop before it touches production.

With a context name, `ctx` switches kubectl to that context. With `-n`, it sets the namespace.

`ctx` only reads files and runs `kubectl config` and `git config`. It never talks to a cluster or a cloud API, so
it is fast enough for a shell prompt and works offline. It never prints secrets. With keys in
`AWS_ACCESS_KEY_ID`, it says the keys come from there, and never shows them.

## Options

| Option | What it does |
|---|---|
| `-s`, `--short` | One line for a shell prompt, such as `kind-kind/shop aws:default tf:default`. It starts with `!` when something looks like production. |
| `--prod REGEX` | What counts as production. See below. |
| `-l`, `--list` | List the kube contexts with their namespace. `*` marks the current one, and production ones are flagged. |
| `-n`, `--namespace NS` | Set the namespace of the current context, or of the one you switch to. |
| `-q`, `--quiet` | Print only the production line. Nothing at all means nothing looks like production. |
| `-v`, `--verbose` | Show each `kubectl` and `git` command and each file it reads. |
| `-h`, `--help` | Show the help. |

## What counts as production

By default, a name counts as production when `prod`, `prd` or `live` starts a word in it. A word starts at the
beginning of the name or after any character that is not a letter or digit. These match:

- `prod`, `production`, `prod-eks`, `shop-prod-4821`, `eu_prd`, `live`
- `arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks`, because of the `/` before `prod`

These do not, because the letters sit inside a word:

- `delivery`, `reproduce`, `olive-dev`

`ctx` checks the kube context name and namespace, the AWS profile, the gcloud project and the Terraform
workspace. It does not check git.

To use your own rule, set `CTX_PROD` in your shell profile or pass `--prod`. The value is an extended regular
expression, matched anywhere in the name, with case ignored.

```bash
export CTX_PROD='prod|pci|^customer-'
```

## Switching contexts

`ctx NAME` runs `kubectl config use-context NAME`. The name can be the full context name or any part of it that
only one context has. `ctx prod` works for `arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks` when no other
context has `prod` in it. When two or more match, `ctx` lists them and changes nothing. When the name you gave
is not the full name, the line ends with `matched from` and what you typed, so a match you did not mean shows at
once.

`ctx -` switches back to the context you had before the last switch, like `cd -`. `ctx` keeps that name in
`~/.local/state/toolbelt/ctx-previous`.

`ctx -n NAMESPACE` runs `kubectl config set-context --current --namespace=NAMESPACE`. Combine the two with
`ctx NAME -n NAMESPACE`.

Switching to a context that looks like production prints a warning, and still switches. It exits 0, since you
asked for it.

The switch writes to your kubeconfig, the same way `kubectl config use-context` does. With several files in
`KUBECONFIG`, kubectl writes the current context to the first one.

## In a shell prompt

Add the short form to your prompt, so every line shows where commands go. For bash, in `~/.bashrc`:

```bash
PS1='$(ctx -s 2>/dev/null) \w \$ '
```

For zsh, in `~/.zshrc`:

```zsh
setopt prompt_subst
PROMPT='$(ctx -s 2>/dev/null) %~ %# '
```

`ctx -s` runs `kubectl config` twice, which takes about 50 ms. On a slow machine, show it only in folders that
matter, or only when `KUBECONFIG` is set.

## Pass-through

None. `ctx` only reads the config of each tool.

## Needs

Nothing is required. Each line needs its tool or its files.

- `kubectl` for the `kube` line and for switching. Without it the line says `kubectl not installed`, and a switch
  exits 3 with the install line.
- The `aws` line reads `~/.aws/config` and the `AWS_` variables. It does not need the `aws` command.
- The `gcloud` line reads `~/.config/gcloud`, or `CLOUDSDK_CONFIG`, and `CLOUDSDK_CORE_PROJECT`. It does not need
  the `gcloud` command.
- The `terraform` line reads `.terraform/environment`, or `TF_DATA_DIR`, and `TF_WORKSPACE`. It only shows a
  workspace in a folder with `.tf` files, since a workspace belongs to a folder.
- `git` for the `git` and `signing` lines.

A line reads `not installed` when neither the tool nor its settings are on the machine, and `not set up` when
the tool is there with no settings.

## Examples

### Before an apply

```console
$ ctx
kube       kind-kind, namespace shop
aws        profile default, region ap-south-1
gcloud     not installed
terraform  workspace default, in ~/lab/infra/eks
git        Khadirullah, khadirullah@example.com
signing    none, commits are not signed
```

### Production everywhere

```console
$ AWS_PROFILE=prod-admin ctx
kube       arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks
           namespace payments
aws        profile prod-admin, region ap-south-1
gcloud     project shop-prod-4821
terraform  workspace prod, in ~/work/infra
git        Khadirullah, khadirullah@example.com
signing    ssh key ~/.ssh/id_ed25519.pub, commits signed
! context looks like production: kube, aws, gcloud, terraform
$ echo $?
1
```

A long context name, such as an EKS ARN, gets the namespace on its own line.

### Stop a script before production

```bash
ctx -q || { echo "refusing to run against production"; exit 1; }
kubectl delete pod -l app=test
```

### The prompt line

```console
$ ctx -s
kind-kind/shop aws:default tf:default
```

### List and switch

```console
$ ctx -l
* arn:aws:eks:ap-south-1:123456789012:cluster/prod-eks  payments  ! production
  kind-kind                                             shop
  minikube                                              default
$ ctx -
switched to kind-kind, namespace shop
$ ctx mini -n kube-system
switched to minikube, namespace kube-system, matched from mini
```

### What it reads

```console
$ ctx -v -q
+ kubectl config current-context
+ kubectl config view --minify -o 'jsonpath={..namespace}'
ctx: reading /home/khadirullah/.aws/config
ctx: reading /home/khadirullah/.config/gcloud/configurations/config_default
+ git config user.name
! context looks like production: gcloud, terraform
```

## Troubleshooting

`kube       no current context`
: Your kubeconfig has contexts but none is selected, or it has none. Run `ctx -l`, then `ctx NAME`. A new kind
  or minikube cluster adds its own context.

`ctx: NAME matches 2 contexts: a, b. Give more of the name`
: Type more of the name, or the whole name from `ctx -l`.

`ctx: no previous context yet`
: `ctx -` only works after one switch made with `ctx`. A switch made with `kubectl config use-context` is not
  recorded.

The `aws` line shows a region you did not expect
: `AWS_REGION` and `AWS_DEFAULT_REGION` win over the config file, in that order. Run `env | grep ^AWS_` to see
  what your shell has set.

`terraform  no .tf files here`
: Change into the Terraform folder first. The workspace belongs to the folder, not to your shell.

A namespace called `delivery` or `live-stream` is flagged, or a real production one is not
: Set `CTX_PROD` to a pattern that fits your names, such as `CTX_PROD='^prod-|-prod$'`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Nothing looks like production, or a switch worked. |
| 1 | Something looks like production, or a switch failed, such as an unknown or unclear name. |
| 2 | Bad usage, such as two context names, `-s` with a switch, or a `--prod` pattern that is not valid. |
| 3 | `kubectl` is not installed, for `-l`, a switch or `-n`. |

## See also

`kwhy`, `kres`, `git-whoami`, `tfcheck`, `kubectl-config(1)`
