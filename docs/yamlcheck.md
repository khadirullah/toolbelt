# yamlcheck

Lint YAML and check Kubernetes manifests.

## Synopsis

```
yamlcheck [-k] [--kube-version V] [--strict] [file | dir ...] [-- yamllint options]
```

## Description

YAML fails in quiet ways. A tab where spaces belong, a key written twice, or a port number in quotes all look
fine in an editor. Some of them only show up when `kubectl apply` rejects the manifest, and a duplicate key never
shows up at all, because the parser keeps the last value and drops the first without a word.

`yamlcheck` checks every YAML file you name, and every `.yaml` and `.yml` file under a folder you name. With no
argument it checks the current folder. It skips `.git` folders. Each file gets a line with `pass`, or its name
followed by one line per finding with the line and column, the level and the message. The last line counts the
files, such as `3 files, 1 pass, 2 fail`.

It runs up to three checks on each file.

1. yamllint, when it is installed, for syntax and style. Its settings come from `.yamllint`, `.yamllint.yaml`
   or `.yamllint.yml` in the current folder, or yamllint's defaults.
2. A check in python3 that always runs. It finds tabs in the indentation, duplicate keys and syntax errors, so
   those fail even when a yamllint config turns its own rules off, and even when yamllint is not installed.
3. With `-k`, kubeconform, which checks each Kubernetes object against the schema for your cluster's version.

A finding that yamllint and python3 both report on the same line shows once. Two yamllint messages get plainer
words. `found character '\t' that cannot start any token` becomes `tab character, YAML allows spaces only`, and
`duplication of key "image" in mapping` becomes `duplicate key "image"`.

`yamlcheck` only reads. It never changes a file and never talks to the cluster, except to ask its version when
`-k` needs one.

## Options

| Option | What it does |
|---|---|
| `-k`, `--kube` | Check Kubernetes manifests against the schema too. Needs kubeconform. |
| `--kube-version V` | The Kubernetes version of the schema, such as `1.31` or `1.31.4`. Works with `-k`. |
| `--strict` | Treat warnings as failures, so a file with only warnings fails. |
| `-q`, `--quiet` | Print only the summary line. |
| `-v`, `--verbose` | Show each step and each real command before it runs. |
| `-h`, `--help` | Show the help. |

## Errors and warnings

yamllint gives each rule a level, `error` or `warning`, and `yamlcheck` shows it as `error` or `warn`. A file
fails when it has an error. Warnings are shown and do not fail the file, unless you pass `--strict`. Tabs,
duplicate keys, syntax errors and schema errors are always errors.

## Kubernetes schemas

With `-k`, files that passed the YAML checks go to kubeconform. A file with a syntax error is left out, since
kubeconform could not read it either.

The schema version comes from `--kube-version` when you give it. Otherwise `yamlcheck` runs
`kubectl version -o json --request-timeout=3s` and uses the server's version, so the manifest is checked against
the cluster you are about to apply it to. When no cluster answers in 3 seconds, or kubectl is missing, kubeconform
uses its newest schema. `-v` says which one it picked.

kubeconform downloads schemas from GitHub the first time and keeps them in `~/.cache/toolbelt/kubeconform`, so
later runs work offline for the same version.

Custom resources, such as a cert-manager `Certificate`, have no schema in the standard set. They get a note,
`schema  skip   no schema for Certificate site`, and do not fail. A YAML file that is not a Kubernetes object at
all, such as a Helm `values.yaml`, gets `not a Kubernetes manifest, schema check skipped`. An object whose
schema kubeconform could not download, as on a machine with no network, gets the same skip note as a custom
resource.

## Pass-through

Options after `--` go to yamllint. Use them to pick a config or turn a rule off for one run.

```console
$ yamlcheck deploy/ -- -c .yamllint.yaml
$ yamlcheck values.yaml -- -d "{extends: default, rules: {line-length: disable}}"
```

Options after `--` need yamllint, so they exit 3 when it is missing.

## Per-distro notes

yamllint
: Debian, Ubuntu, Fedora, Arch, openSUSE and Alpine all package it as `yamllint`.

kubeconform
: Arch and openSUSE Tumbleweed have `kubeconform`. On Debian, Ubuntu, Fedora and Alpine, download the release
  from github.com/yannh/kubeconform/releases and put the binary in `~/.local/bin`.

python3 without PyYAML
: The duplicate key and syntax checks need the `yaml` module, from `python3-yaml` on Debian and Ubuntu,
  `python3-pyyaml` on Fedora and `python-yaml` on Arch. Without it and without yamllint, `yamlcheck` only finds
  tabs and says so.

## Needs

`yamllint`, or `python3` for the tab, duplicate key and syntax checks alone. Both is best. `kubeconform` for
`-k`, and `kubectl` to learn the cluster's version, which is optional.

## Examples

### A folder of manifests, with the schema

```console
$ yamlcheck -k deploy/
deploy/api.yaml
  12:3    error  wrong indentation: expected 4 but found 2 (indentation)
  27:81   warn   line too long (96 > 80 characters) (line-length)
deploy/cm.yaml  pass
deploy/svc.yaml
  schema  error  Service web, spec.ports[0].port: expected integer, but got string
3 files, 1 pass, 2 fail
```

The quotes around `"8080"` make it a string, and a Service port must be a number.

### A key written twice

```console
$ yamlcheck values.yaml
values.yaml
  5:1     error  duplicate key "image"
1 file, 1 fail
```

Helm would have used the second `image` and dropped the first without a word.

### Without yamllint

```console
$ yamlcheck values.yaml chart.yaml
yamlcheck: yamllint is missing, so only syntax, tabs and duplicate keys were checked. Install it with: sudo apt install yamllint
values.yaml
  5:1     error  duplicate key "image"
chart.yaml
  3:1     error  tab character, YAML allows spaces only
2 files, 2 fail
```

### Warnings fail with --strict

```console
$ yamlcheck --strict deploy/cm.yaml
deploy/cm.yaml
  1:1     warn   missing document start "---" (document-start)
1 file, 1 fail
```

Without `--strict` the same file passes and the warning still shows.

### Check against the cluster you deploy to

```console
$ yamlcheck -q -k --kube-version 1.30 deploy/
3 files, 3 pass
```

### No kubeconform

```console
$ yamlcheck -k deploy/
yamlcheck: needs kubeconform for -k. Install it from https://github.com/yannh/kubeconform/releases
$ echo $?
3
```

## Troubleshooting

`yamlcheck: needs yamllint`
: Neither yamllint nor python3 is installed, or you passed options after `--` without yamllint. Install
  yamllint.

`yamlcheck: yamllint: ...`
: yamllint refused its config or an option after `--`. The rest of the line is yamllint's own message.

`yamlcheck: no .yaml or .yml files in DIR`
: The folder and its subfolders hold no files with those endings. Name other files directly, such as
  `yamlcheck Chart.lock`.

`yamlcheck: kubeconform gave no result`
: kubeconform crashed or could not download a schema, often because the machine is offline and the version is not
  in the cache yet. Run the kubeconform line from `-v` by hand to see why.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every file passed. |
| 1 | A file failed, a path does not exist, or a folder has no YAML files. |
| 2 | Bad usage, such as `--kube-version` without `-k`. |
| 3 | No yamllint and no python3, or no kubeconform for `-k`. |

## See also

`tfcheck`, `kyaml`, `yamllint(1)`, `kubectl(1)`
