# tfcheck

Every Terraform check in one pass.

## Synopsis

```
tfcheck [--fix] [--only CHECK] [dir] [-- validate options]
```

## Description

A Terraform change usually has to pass four checks before anyone merges it. `terraform fmt` wants the files laid
out its way, `terraform validate` wants every reference to point at something real, tflint knows the provider's
rules, and trivy knows the security mistakes. Each tool has its own flags and its own output. `tfcheck` runs all
four on one folder and prints one short section per check, with the file and line of every finding.

The folder is one Terraform module, the current folder by default. `tfcheck` looks at the `.tf` files directly
in it, the same set `terraform plan` would read. It does not walk into subfolders such as `modules/`. Run it once
per module, or in a loop.

The checks run in a fixed order, fmt, validate, tflint, trivy. Each one prints `pass`, `fail` or `skip` on its own
line, with the details indented below. The last line counts the result, such as `3 of 4 checks failed`. That line
goes to stdout like the rest, so `tfcheck -q` in a script prints just the count.

`tfcheck` changes no file unless you pass `--fix`. It never runs `terraform init`, never downloads a provider or
a module, and never touches state or a backend.

## The four checks

fmt
: Runs `terraform fmt -check -list=true`. Terraform prints the name of each file whose layout differs from its
  own style, and `tfcheck` lists them. With `--fix` it runs `terraform fmt -list=true` instead, which rewrites
  those files and prints their names after `fixed`.

validate
: Runs `terraform validate -json` and shows each error with its file, line, summary and the detail Terraform
  gives, folded to fit the screen. Validate checks references, types and required arguments. It knows nothing
  about the cloud, so a wrong instance type still passes here.

tflint
: Runs `tflint --chdir=DIR --format=compact` when tflint is installed. Each issue shows the file, line and rule
  name, then tflint's message. Errors, warnings and notices all count as issues. With the AWS, Azure or Google
  plugin, tflint knows the real instance types, regions and machine sizes.

trivy
: Runs `trivy config --format json --severity HIGH,CRITICAL DIR` when trivy is installed. Only high and critical
  findings count, and critical ones are listed first, each with its file, line, check ID and title. Lower
  severities stay out of the way. Run trivy by hand to see them.

tflint and trivy are optional. When one is missing, its line says `skip  not installed, see toolbelt doctor`,
and the summary counts it as skipped rather than failed. When you ask for it by name with `--only`, a missing
tool is an error, exit 3.

## Options

| Option | What it does |
|---|---|
| `--fix` | Let `terraform fmt` rewrite the files that need it. The other checks run as usual. |
| `--only CHECK` | Run only this check, `fmt`, `validate`, `tflint` or `trivy`. Repeat it for more. |
| `-q`, `--quiet` | Print only the summary line. |
| `-v`, `--verbose` | Show each step and each real command before it runs. |
| `-h`, `--help` | Show the help. |

`--fix` needs the fmt check, so `--fix --only tflint` is bad usage.

## Terraform or OpenTofu

`tfcheck` uses `terraform` when it is on your PATH, and `tofu` from OpenTofu when it is not. Both take the same
`fmt` and `validate` commands and give the same JSON, so the output looks the same. The command lines in `-v` and
in the messages name the tool that ran.

When you only ask for tflint or trivy with `--only`, `tfcheck` does not need Terraform at all.

## When validate needs init

`terraform validate` has to load every provider and module the configuration uses. Those live in `.terraform/`,
which `terraform init` fills. A fresh clone has no `.terraform/`, so validate cannot run there.

`tfcheck` does not run init for you. Init downloads providers from the internet, can take hundreds of megabytes,
writes `.terraform/` and may create `.terraform.lock.hcl`, and none of that fits a command that promises to
change nothing. Instead the validate line says

```
validate  skip  needs terraform init first, see man tfcheck
```

and the summary counts it as skipped. To validate without touching a remote backend, run this once in the
folder, then run `tfcheck` again.

```console
$ terraform init -backend=false
```

A module with no providers, such as one that only holds variables and outputs, validates without init.

## tflint plugins

tflint's cloud rules live in plugins named in `.tflint.hcl`. When the file names a plugin that is not installed,
tflint stops with an error and `tfcheck` shows it.

```
tflint    fail  tflint stopped with exit 1
          Failed to initialize plugins; Plugin "aws" not found. Did you run
          "tflint --init"?
          run tflint --init in infra/eks to install its plugins
```

Run `tflint --init` in that folder once. It downloads the plugins into `~/.tflint.d/`.

## Pass-through

Options after `--` go to `terraform validate`, before `-json`. `-no-tests` skips the `.tftest.hcl` files, and
`-test-directory=DIR` points at tests kept elsewhere.

```console
$ tfcheck infra/eks -- -no-tests
```

The other checks take no extra options from the command line. tflint reads `.tflint.hcl` in the folder and trivy
reads `trivy.yaml`, so put their settings there.

## Per-distro notes

Terraform
: HashiCorp ships Terraform from its own package repository for Debian, Ubuntu, Fedora and RHEL, since the
  license change keeps it out of most distro repos. Arch has `terraform` in extra. On openSUSE and Alpine, use
  the HashiCorp zip or OpenTofu.

OpenTofu
: Fedora, Arch, openSUSE Tumbleweed and Alpine have `opentofu`, which installs `tofu`. On Debian and Ubuntu,
  use the OpenTofu apt repository or the standalone installer.

tflint
: Arch has `tflint`. Elsewhere, download the release zip from github.com/terraform-linters/tflint and put the
  binary in `~/.local/bin`.

trivy
: Fedora, Arch and openSUSE Tumbleweed have `trivy`. On Debian and Ubuntu, use Aqua Security's apt repository.
  trivy downloads its check bundle on the first run and caches it in `~/.cache/trivy`.

## Needs

`terraform` or `tofu` for the fmt and validate checks, and `python3` to read their JSON and trivy's. `tflint` and
`trivy` are optional. `toolbelt doctor` lists which of them this machine has.

## Examples

### A module with work to do

```console
$ tfcheck infra/eks
fmt       fail  2 files need formatting
          main.tf
          variables.tf
          tfcheck --fix rewrites them
validate  pass
tflint    fail  2 issues
          main.tf:14  aws_instance_invalid_type
            "t3.mediun" is an invalid value as instance_type
          vpc.tf:3  terraform_unused_declarations
            variable "azs" is declared but not used
trivy     fail  1 high, 1 critical
          eks.tf:8  AVD-AWS-0040 CRITICAL
            EKS cluster has the public access enabled
          eks.tf:21  AVD-AWS-0039 HIGH
            EKS should have the encryption of secrets enabled
3 of 4 checks failed
$ echo $?
1
```

Validate passed, and still the instance type is wrong. Only tflint's AWS plugin knows the list of real types.

### Fix the layout

```console
$ tfcheck --fix infra/eks
fmt       fixed main.tf variables.tf
validate  pass
tflint    pass
trivy     pass  0 high, 0 critical
all 4 checks passed
```

`git diff` shows exactly what fmt changed.

### A typo in a variable name, without tflint

```console
$ tfcheck modules/vpc
fmt       pass
validate  fail  1 error
          main.tf:9  Reference to undeclared input variable
            An input variable with the name "cluster_verison" has not been
            declared. Did you mean "cluster_version"?
tflint    skip  not installed, see toolbelt doctor
trivy     pass  0 high, 0 critical
1 of 3 checks failed, 1 skipped
```

### A fresh clone

```console
$ tfcheck infra/eks
fmt       pass
validate  skip  needs terraform init first, see man tfcheck
tflint    skip  not installed, see toolbelt doctor
trivy     pass  0 high, 0 critical
all 2 checks passed, 2 skipped
```

Run `terraform init -backend=false` in `infra/eks` to let validate run.

### Only the fast checks, with the commands shown

```console
$ tfcheck -v --only fmt --only validate modules/vpc
tfcheck: checking /home/khadir/lab/infra/modules/vpc
tfcheck: running fmt
+ terraform -chdir=modules/vpc fmt -check -list=true -no-color
fmt       pass
tfcheck: running validate
+ terraform -chdir=modules/vpc validate -no-color -json
validate  pass
all 2 checks passed
```

### In a script or a git hook

```console
$ tfcheck -q infra/eks || echo "fix the findings first"
3 of 4 checks failed
fix the findings first
```

A pre-commit hook can run `tfcheck -q` on each changed module and stop the commit when one fails.

### The wrong folder

```console
$ tfcheck ~/Downloads
tfcheck: no .tf files in /home/khadir/Downloads
$ echo $?
2
```

## Troubleshooting

`tfcheck: no .tf files in DIR`
: The folder holds no `.tf` or `.tf.json` files at its top level. `cd` into the module, or name it, such as
  `tfcheck infra/eks`.

`tfcheck: needs terraform. Install the package that provides it`
: Neither `terraform` nor `tofu` is on your PATH. Install one of them, see the per-distro notes above.

`validate  skip  needs terraform init first`
: The module uses providers or modules that are not in `.terraform/` yet. Run `terraform init -backend=false`
  in the folder once.

`fmt  fail  terraform fmt could not parse the files`
: A file has a syntax error, such as a missing brace. The lines below show Terraform's own message with the file
  and line. Validate fails for the same reason.

`tflint  fail  tflint stopped with exit 1`
: tflint could not run, most often because a plugin in `.tflint.hcl` is missing. Run `tflint --init` in the
  folder.

`trivy  fail  trivy stopped with exit 1`
: trivy could not download its check bundle, often because the machine is offline. The lines below show trivy's
  own message. Once the bundle is cached in `~/.cache/trivy`, it works offline.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every check that ran passed. Skipped checks do not count. |
| 1 | A check failed, or a tool it runs stopped with an error. |
| 2 | Bad usage, or no `.tf` files in the folder. |
| 3 | Neither `terraform` nor `tofu` is installed, or a check named with `--only` is missing. |

## See also

`yamlcheck`, `terraform(1)`, `tflint(1)`, `trivy(1)`
