#!/usr/bin/env python3
"""Build the toolbelt website from the docs.

Reads lib/commands for the groups and their order, docs/<command>.md for each page, and README.md for the intro
when it exists. Writes plain HTML to site/out/ and copies site/src/style.css and site/src/filter.js next to it.
Standard library only. A command with no docs page yet is left out, with one warning line for all of them.

Run: python3 tools/build-site.py, or make site.
"""
import html
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
SRC = ROOT / "site" / "src"
OUT = ROOT / "site" / "out"
REPO = "https://github.com/khadirullah/toolbelt"
POST = "https://khadirullah.com/blog/toolbelt-bash-commands-8-distros/"
INSTALL = "curl -fsSL https://raw.githubusercontent.com/khadirullah/toolbelt/main/install.sh | bash"
INTRO = [
    "toolbelt is a set of {n} small Bash commands for daily Linux work. Each one does one job, such as unpacking "
    "any archive or showing who holds a port.",
    "Every command takes the same common options and shows the real command it runs with `-v`. Nothing gets "
    "deleted without a question, and deletes go to the trash. When a tool is missing, the command prints the "
    "install line for your distro.",
]

# Runs for the home page: the command, the example heading in its docs page (None for the first example), and
# what you would type without toolbelt. The first four whose docs page exists are shown.
SHOWCASE = [
    ("unpack", "Unpack a split backup into another folder",
     ["mkdir -p ~/restore", "cat backup.tar.gz.a* | tar -xzf - -C ~/restore"]),
    ("port", "Who holds a port",
     ["ss -tlnp 'sport = :8000'", "ps -o user=,args= -p 4121"]),
    ("kwhy", None,
     ["kubectl get pods", "kubectl describe pod NAME", "kubectl get events --sort-by=.lastTimestamp"]),
    ("genpass", "A passphrase",
     ["shuf -n 5 /usr/share/dict/words | paste -sd-"]),
    ("certcheck", "One site",
     ["echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \\",
      "    | openssl x509 -noout -enddate -issuer"]),
]

# Home page sections below the command list. Every claim here is backed by CONTRIBUTING.md, lib/common.sh,
# install.sh or .github/workflows/ci.yml. {verbose} is the squash example with -v, taken from its docs page.
RULES_MD = """
## How every command works

Learn this once and it holds for every command.

### Three layers of options

1. **Common options.** `-h`, `-q`, `-v` and `-y` mean the same in every command.
   `squash -l 9` is the smallest level for gzip and for zstd alike, mapped onto each
   tool's own scale.
2. **Pass-through.** Anything after `--` goes to the tool underneath, so its own options stay yours, as in
   `squash photos/ -- --long=27` or `unpack photos.7z -- -mmt=4`.
3. **`-v` shows the real command.** It prints every step, and each real command as a line starting with `+`.
   Copy that line and change any flag you like.

{verbose}

### Common options

| Option | What it does |
|---|---|
| `-h`, `--help` | Show the help and exit 0. |
| `-q`, `--quiet` | Show only the result line and errors. |
| `-v`, `--verbose` | Show every step, and each real command before it runs. |
| `-y`, `--yes` | Go ahead without asking. With no terminal, a command that would ask refuses unless `-y` is given. |
| `--version` | Show the command name and the toolbelt version. |
| `--` | Pass the rest to the tool underneath. |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | It worked. |
| 1 | It failed. The message says why. |
| 2 | Bad usage, such as an unknown option. |
| 3 | A tool is missing. The message has the install line. |
| 4 | A safety check refused. |
| 5 | You answered no, so nothing changed. |

A command may give a code a meaning of its own, such as `certcheck` exiting 1 when a certificate expires soon. Its
page says so under Exit status.

## Six rules

1. **It points you to good tools it does not replace.** `toolbelt doctor` recommends btop, ncdu, fzf, tldr and
   dive when they are missing.
2. **`-h` and `--help` always mean help.** Every help page has the same layout. Usage, one line on what the command
   does, options, pass-through, examples, then what it needs and its exit codes. `toolbelt help unpack` prints the
   same page as `unpack --help`, and `man unpack` has the full manual.
3. **A missing tool comes with the install line for your distro.** It knows apt, dnf, yum, pacman, zypper and apk,
   and one table in `lib/pkgmap` holds the package name for each. 7-Zip is `7zip` on Debian 13, Fedora and Arch,
   and `p7zip-full` on older Ubuntu releases.
4. **Nothing destructive happens without asking.** Deletes go to the trash in `~/.local/share/Trash`, so you can
   restore them. After `unpack` or `squash` checks its result, it asks whether to delete the archive or the source.
   `--rm` deletes without asking and `-k` keeps without asking. In a script there is nobody to ask, so the file
   stays unless you pass `--rm`. No command writes over a file of yours. It picks a free name such as `backup-1`.
5. **Scripts stay clean.** Results go to stdout and everything meant for a person goes to stderr. Colour and
   progress bars appear only in a terminal, and `NO_COLOR` turns colour off. The exit codes are the same in every
   command.
6. **It is small on memory.** Commands stream data through pipes instead of reading whole files, and check free
   memory and disk space before heavy work.

Rule 3 in practice:

```console
$ unpack logs.tar.zst
unpack: needs zstd. Install it with: sudo apt install zstd
```

## Where it runs

On every push to main and every pull request, CI runs the whole test suite on GitHub Actions in a container of each of these images.

| Image | Package manager |
|---|---|
| `debian:13` | apt |
| `ubuntu:24.04` | apt |
| `ubuntu:22.04` | apt |
| `fedora:44` | dnf |
| `rockylinux:9` | dnf |
| `archlinux:latest` | pacman |
| `opensuse/leap:15` | zypper |
| `alpine:3` | apk |

- toolbelt needs Bash 4.4 or newer, and the installer stops on an older one. Alpine does not ship bash, so the
  installer asks you to run `apk add bash` first.
- The shared library has fallbacks for BusyBox, such as whole seconds where `date +%N` is missing.
- CI checks every package name in `lib/pkgmap` against the real repos of each image, except Rocky 9 and
  Ubuntu 22.04.
"""

FENCE = re.compile(r"^(`{3,}|~{3,})\s*([\w-]*)\s*$")
HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
ITEM = re.compile(r"^( {0,3})([-*+]|\d{1,9}[.)])\s+(.*)$")
TABLE_SEP = re.compile(r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$")
CODE_SPAN = re.compile(r"(`+)(.+?)(?<!`)\1(?!`)", re.S)
LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
BOLD = re.compile(r"\*\*(.+?)\*\*", re.S)


def esc(text):
    return html.escape(text, quote=True)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "section"


def page_url(cmd):
    return "getting-started.html" if cmd == "toolbelt" else f"{cmd}.html"


class Markdown:
    """Render the Markdown subset the docs use. One instance per page, so heading ids stay unique."""

    def __init__(self, link_cmds=()):
        self.link_cmds = set(link_cmds)   # command names that `name` links to, in See also sections
        self.ids = set()
        self.toc = []                     # (id, text) of every h2
        self.in_see_also = False

    def unique_id(self, text):
        base = new = slug(text)
        n = 2
        while new in self.ids:
            new, n = f"{base}-{n}", n + 1
        self.ids.add(new)
        return new

    def inline(self, text):
        codes = []

        def stash(m):
            body = m.group(2)
            if len(body) > 2 and body[0] == " " and body[-1] == " " and body.strip():
                body = body[1:-1]
            code = f"<code>{esc(body)}</code>"
            if self.in_see_also and body in self.link_cmds:
                code = f'<a href="{page_url(body)}">{code}</a>'
            codes.append(code)
            return f"\x00{len(codes) - 1}\x00"

        text = esc(CODE_SPAN.sub(stash, text))
        text = LINK.sub(lambda m: f'<a href="{self.href(m.group(2))}">{m.group(1)}</a>', text)
        text = BOLD.sub(r"<strong>\1</strong>", text)
        return re.sub("\x00(\\d+)\x00", lambda m: codes[int(m.group(1))], text)

    @staticmethod
    def href(url):
        if re.match(r"^[a-z]+:|^#", url) or not re.search(r"\.md(#.*)?$", url):
            return url
        path, _, frag = url.partition("#")
        name = Path(path).stem
        if (DOCS / f"{name}.md").exists():
            return page_url(name) + (f"#{frag}" if frag else "")
        return f"{REPO}/blob/main/{path.lstrip('./')}"

    def render(self, lines):
        out, i, n = [], 0, len(lines)
        while i < n:
            line = lines[i]
            if not line.strip():
                i += 1
            elif FENCE.match(line):
                i = self.fence(lines, i, out)
            elif HEADING.match(line):
                self.heading(HEADING.match(line), out)
                i += 1
            elif "|" in line and i + 1 < n and "|" in lines[i + 1] and TABLE_SEP.match(lines[i + 1]):
                i = self.table(lines, i, out)
            elif ITEM.match(line):
                i = self.list(lines, i, out)
            elif self.is_term(lines, i):
                i = self.deflist(lines, i, out)
            else:
                i = self.paragraph(lines, i, out)
        return out

    @staticmethod
    def is_term(lines, i):
        return bool(lines[i].strip()) and i + 1 < len(lines) and lines[i + 1].startswith(": ")

    def starts_block(self, lines, i):
        line = lines[i]
        return (not line.strip() or FENCE.match(line) or HEADING.match(line) or ITEM.match(line)
                or self.is_term(lines, i)
                or ("|" in line and i + 1 < len(lines) and TABLE_SEP.match(lines[i + 1]) and "|" in lines[i + 1]))

    def heading(self, m, out):
        level = max(2, len(m.group(1)))      # the page title is the only h1
        text = m.group(2).rstrip("#").strip()
        hid = self.unique_id(text)
        if level == 2:
            self.toc.append((hid, text))
            self.in_see_also = text.lower() == "see also"
        out.append(f'<h{level} id="{hid}">{self.inline(text)}</h{level}>')

    def fence(self, lines, i, out):
        mark, lang = FENCE.match(lines[i]).groups()
        body, i = [], i + 1
        while i < len(lines) and not (lines[i].startswith(mark[0] * len(mark)) and not lines[i].strip(mark[0] + " ")):
            body.append(lines[i])
            i += 1
        out.append(code_block(lang, body))
        return i + 1

    def table(self, lines, i, out):
        head = split_row(lines[i])
        rows, i = [], i + 2
        while i < len(lines) and "|" in lines[i] and lines[i].strip():
            rows.append(split_row(lines[i]))
            i += 1
        parts = ['<div class="tw"><table>', "<thead><tr>"]
        parts += [f"<th>{self.inline(c)}</th>" for c in head]
        parts.append("</tr></thead><tbody>")
        for row in rows:
            row = (row + [""] * len(head))[:len(head)]
            parts.append("<tr>" + "".join(f"<td>{self.inline(c)}</td>" for c in row) + "</tr>")
        parts.append("</tbody></table></div>")
        out.append("".join(parts))
        return i

    def list(self, lines, i, out):
        first = ITEM.match(lines[i])
        base = len(first.group(1))
        ordered = first.group(2)[0].isdigit()
        items, n = [], len(lines)
        while i < n:
            m = ITEM.match(lines[i])
            if not m or len(m.group(1)) != base or m.group(2)[0].isdigit() != ordered:
                break
            col = base + len(m.group(2)) + 1
            buf, i = [m.group(3)], i + 1
            while i < n:
                line = lines[i]
                indent = len(line) - len(line.lstrip(" "))
                if not line.strip():
                    j = i
                    while j < n and not lines[j].strip():
                        j += 1
                    if j < n and len(lines[j]) - len(lines[j].lstrip(" ")) >= col:
                        buf += [""] * (j - i)
                        i = j
                        continue
                    break
                if indent > base and indent >= 2:
                    buf.append(line[min(indent, col):])
                elif self.starts_block(lines, i):
                    break
                else:
                    buf.append(line)          # a lazy continuation line
                i += 1
            items.append(buf)
            j = i
            while j < n and not lines[j].strip():
                j += 1
            nxt = ITEM.match(lines[j]) if j < n else None
            if nxt and len(nxt.group(1)) == base and nxt.group(2)[0].isdigit() == ordered:
                i = j
            else:
                break
        tag = "ol" if ordered else "ul"
        start = int(first.group(2)[:-1]) if ordered else 1
        attr = f' start="{start}"' if start != 1 else ""
        parts = [f"<{tag}{attr}>"]
        for buf in items:
            blocks = self.render(buf)
            if blocks and blocks[0].startswith("<p>"):
                blocks[0] = blocks[0][3:-4]      # tight items, no <p> around the first paragraph
            parts.append("<li>" + "\n".join(blocks) + "</li>")
        parts.append(f"</{tag}>")
        out.append("\n".join(parts))
        return i

    def deflist(self, lines, i, out):
        """Troubleshooting entries: a term line, then `: ` and the answer, with indented lines that go on."""
        parts, n = ["<dl>"], len(lines)
        while i < n and self.is_term(lines, i):
            parts.append(f"<dt>{self.inline(lines[i].strip())}</dt>")
            i += 1
            while i < n and lines[i].startswith(": "):
                buf, i = [lines[i][2:]], i + 1
                while i < n and lines[i].startswith("  ") and lines[i].strip():
                    buf.append(lines[i][2:])
                    i += 1
                blocks = self.render(buf)
                if len(blocks) == 1 and blocks[0].startswith("<p>"):
                    blocks[0] = blocks[0][3:-4]
                parts.append("<dd>" + "\n".join(blocks) + "</dd>")
            j = i
            while j < n and not lines[j].strip():
                j += 1
            if j < n and self.is_term(lines, j):
                i = j
            else:
                break
        parts.append("</dl>")
        out.append("\n".join(parts))
        return i

    def paragraph(self, lines, i, out):
        buf = [lines[i].strip()]
        i += 1
        while i < len(lines) and not self.starts_block(lines, i):
            buf.append(lines[i].strip())
            i += 1
        out.append(f"<p>{self.inline(chr(10).join(buf))}</p>")
        return i


def split_row(line):
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", s)]


def code_block(lang, lines, extra=""):
    """A fenced block. In console blocks the lines that start with `$ ` are what you type, the rest is output."""
    if lang != "console":
        return f'<pre class="code{extra}"><code>{esc(chr(10).join(lines))}</code></pre>'
    shown = []
    for line in lines:
        if line == "$" or line.startswith("$ "):
            shown.append(f'<span class="in"><span class="ps" aria-hidden="true">$ </span>{esc(line[2:])}</span>')
        else:
            shown.append(esc(line))
    return f'<pre class="console{extra}"><code>{chr(10).join(shown)}</code></pre>'


def read_groups():
    groups = []
    for line in (ROOT / "lib/commands").read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            name, *cmds = line.split()
            groups.append((name, cmds))
    return groups


def read_doc(cmd):
    """Return (one-liner, body lines) of docs/<cmd>.md, or None when it is missing or has no title yet."""
    path = DOCS / f"{cmd}.md"
    if not path.is_file():
        return None
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or not lines[0].startswith("# "):
        return None
    i = 1
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i >= len(lines) or lines[i].startswith("#"):
        return "", lines[i:]
    return lines[i].strip(), lines[i + 1:]


def example(body, heading):
    """The first console block under ### heading in the Examples section, or under the first example."""
    in_examples, found = False, heading is None
    for i, line in enumerate(body):
        if line.startswith("## "):
            in_examples = line[3:].strip() == "Examples"
        elif in_examples and line.startswith("### "):
            title = line[4:].strip()
            if heading is None or title == heading:
                found, heading = True, title
        elif in_examples and found and FENCE.match(line) and FENCE.match(line).group(2) == "console":
            end = i + 1
            while end < len(body) and not body[end].startswith("```"):
                end += 1
            return heading, body[i + 1:end]
    return None


def page(title, desc, running, body, script=""):
    upper = f"{running.upper()}(1)"
    version = (ROOT / "VERSION").read_text().strip() if (ROOT / "VERSION").exists() else ""
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>{esc(title)}</title>
<meta name="description" content="{esc(desc)}">
<link rel="stylesheet" href="style.css">
</head>
<body>
<a class="skip" href="#main">Skip to the content</a>
<header class="run"><span>{esc(upper)}</span><a href="index.html">toolbelt manual</a><span class="end">{esc(upper)}</span></header>
{body}
<footer class="run"><span>toolbelt {esc(version)}</span><a href="{REPO}">Source on GitHub</a><span class="end">MIT licence</span></footer>
{script}</body>
</html>
"""


def side_nav(group, cmds, current, docs):
    items = []
    for c in cmds:
        if c not in docs:
            continue
        cur = ' aria-current="page"' if c == current else ""
        items.append(f'<li><a href="{page_url(c)}"{cur}>{esc(c)}</a></li>')
    group_link = f'<a href="index.html#g-{slug(group)}">{esc(group)}</a>' if group else "Other"
    return (f'<nav class="side" aria-label="{esc(group or "Other")} commands">\n'
            f'<p><a href="index.html#commands">All commands</a></p>\n'
            f'<p class="grp">{group_link}</p>\n<ul>\n' + "\n".join(items) + "\n</ul>\n"
            f'<p><a href="getting-started.html">Getting started</a></p>\n</nav>')


def toc(md):
    if len(md.toc) < 5:
        return ""
    links = "".join(f'<li><a href="#{hid}">{esc(text)}</a></li>' for hid, text in md.toc)
    return f'<nav class="toc" aria-label="On this page"><ul>{links}</ul></nav>\n'


def command_page(cmd, group, cmds, docs):
    oneliner, body = docs[cmd]
    md = Markdown(link_cmds=set(docs) - {cmd})
    content = "\n".join(md.render(body))
    main = (f'<main id="main">\n<h1 class="name">{esc(cmd)}</h1>\n<p class="lede">{md.inline(oneliner)}</p>\n'
            f"{toc(md)}{content}\n</main>")
    body_html = f'<div class="wrap">\n{side_nav(group, cmds, cmd, docs)}\n{main}\n</div>'
    return page(f"{cmd} | toolbelt manual", oneliner, cmd, body_html)


def install_blocks(bold):
    first = code_block("console", [f"$ {INSTALL}"], " install" if bold else "")
    clone = code_block("console", [f"$ git clone {REPO}.git", "$ cd toolbelt", "$ ./install.sh"])
    return (f"<p>One line. It installs into <code>~/.local</code> and needs no sudo.</p>\n{first}\n"
            f"<p>To read the code before it runs, clone the repo and run the installer from the clone.</p>\n{clone}\n")


def getting_started(group, cmds, docs):
    oneliner, body = docs["toolbelt"]
    md = Markdown(link_cmds=set(docs) - {"toolbelt"})
    for text in ("Install", "First steps"):
        md.toc.append((md.unique_id(text), text))
    steps = md.render([
        "1. Run `toolbelt doctor`. It lists the optional tools your machine lacks and the line that installs them.",
        "2. Run `toolbelt setup` to install them. It shows the list and the exact command, then asks.",
        "3. Run `toolbelt shell enable functions` if you want `mkcd` and `up`, then open a new terminal.",
        "4. Try any command with `--help`, or read its page with `man`, such as `man unpack`.",
    ])
    content = "\n".join(md.render(body))
    main = (f'<main id="main">\n<h1 class="title">Getting started</h1>\n'
            f'<p class="lede">Install toolbelt, check your machine, and meet <code>toolbelt</code>, the command '
            f"that looks after the others.</p>\n{toc(md)}"
            f'<h2 id="install">Install</h2>\n{install_blocks(False)}'
            f'<p>To remove it, run <code>toolbelt uninstall</code>, or <code>./install.sh --uninstall</code> '
            f"from the clone.</p>\n"
            f'<h2 id="first-steps">First steps</h2>\n' + "\n".join(steps) + "\n"
            f"<p>The rest of this page is the manual for the <code>toolbelt</code> command. It lists the others, "
            f"checks your machine, and installs, updates or removes toolbelt.</p>\n{content}\n</main>")
    body_html = f'<div class="wrap">\n{side_nav(group, cmds, "toolbelt", docs)}\n{main}\n</div>'
    return page("Getting started | toolbelt manual", oneliner, "toolbelt", body_html)


def readme_intro():
    """The first paragraph after the title of README.md, when there is one."""
    path = ROOT / "README.md"
    if not path.is_file():
        return None
    paras, buf = [], []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or line.startswith("!") or line.startswith("[!"):
            continue
        if line.strip():
            buf.append(line.strip())
        elif buf:
            paras.append(" ".join(buf))
            buf = []
        if paras:
            break
    return paras or None


def test_count():
    """The number of bats tests under tests/, for the line under the title."""
    return sum(len(re.findall(r"^@test ", p.read_text(encoding="utf-8"), re.M)) for p in (ROOT / "tests").rglob("*.bats"))


def ci_distros():
    """The number of images in CI's test matrix."""
    text = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    m = re.search(r"^\s*image:\n((?:\s+- .+\n)+)", text, re.M)
    return len(m.group(1).splitlines()) if m else 0


def index_page(groups, docs, total):
    md = Markdown()
    md.ids.update({"install", "commands", "commands-h", "examples", "main", "filter", "filter-box", "nomatch"})
    md.ids.update(f"g-{slug(g)}" for g, _ in groups)
    found = example(docs["squash"][1], "Every step, with the real commands") if "squash" in docs else None
    verbose = "```console\n" + "\n".join(found[1]) + "\n```" if found else ""
    rules = "\n".join(md.render(RULES_MD.replace("{verbose}", verbose).splitlines()))
    intro = readme_intro() or [p.format(n=total) for p in INTRO]
    lists = []
    for group, cmds in groups:
        items = [f'<li><a href="{page_url(c)}">{esc(c)}</a><span>{md.inline(docs[c][0])}</span></li>'
                 for c in cmds if c in docs]
        if items:
            lists.append(f'<div class="group" id="g-{slug(group)}">\n<h3>{esc(group)}</h3>\n'
                         f'<ul class="cmds">\n' + "\n".join(items) + "\n</ul>\n</div>")
    shows = []
    for cmd, heading, before in SHOWCASE:
        found = example(docs[cmd][1], heading) if cmd in docs else None
        if not found or len(shows) == 4:
            continue
        title, after = found
        shows.append(
            f'<div class="pair">\n<h3>{md.inline(title)}</h3>\n'
            f'<p class="label">Without toolbelt</p>\n{code_block("console", [b if b[0] == " " else "$ " + b for b in before], " before")}\n'
            f'<p class="label">With <a href="{page_url(cmd)}"><code>{esc(cmd)}</code></a></p>\n'
            f'{code_block("console", after)}\n</div>')
    proof = (f'<p class="proof">{total} commands · <a href="{REPO}/tree/main/tests">{test_count():,} tests</a> · '
             f'<a href="{REPO}/actions/workflows/ci.yml">CI on {ci_distros()} distros</a> · '
             f'<a href="{POST}">How it was tested</a></p>')
    main = f"""<main id="main" class="home">
<h1>toolbelt</h1>
{"".join(f"<p>{md.inline(p)}</p>" for p in intro)}
{proof}
<p>New here? <a href="getting-started.html">Getting started</a> walks through install, the health check and the
shell settings.</p>
<section aria-labelledby="examples">
<h2 id="examples">What it looks like</h2>
<p>Real runs, copied from the manual pages, next to what you would type without toolbelt.</p>
{chr(10).join(shows)}
</section>
<section aria-labelledby="install">
<h2 id="install">Install</h2>
{install_blocks(True)}</section>
<section id="commands" aria-labelledby="commands-h">
<h2 id="commands-h">Commands</h2>
<p>Each name opens its full manual page. The same text is in <code>man</code> and <code>--help</code>.</p>
<div class="filter" id="filter-box" hidden>
<label for="filter">Filter the list</label>
<input id="filter" type="search" autocomplete="off" spellcheck="false" placeholder="such as port, or archive">
</div>
<p id="nomatch" role="status" hidden>No command matches. Try a shorter word.</p>
{chr(10).join(lists)}
</section>
{rules}
</main>"""
    return page("toolbelt, small Bash commands for daily Linux work", intro[0].replace("`", ""), "toolbelt", main,
                '<script src="filter.js"></script>\n')


def main():
    groups = read_groups()
    listed = [c for _, cmds in groups for c in cmds]
    docs, missing = {}, []
    for cmd in listed:
        doc = read_doc(cmd)
        if doc is None:
            missing.append(cmd)
        else:
            docs[cmd] = doc
    extra = sorted(p.stem for p in DOCS.glob("*.md") if p.stem not in listed and read_doc(p.stem))
    for cmd in extra:
        docs[cmd] = read_doc(cmd)
    if extra:
        groups.append(("Other", extra))

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    for name in ("style.css", "filter.js"):
        shutil.copy(SRC / name, OUT / name)

    built = 0
    for group, cmds in groups:
        for cmd in cmds:
            if cmd not in docs:
                continue
            html_text = getting_started(group, cmds, docs) if cmd == "toolbelt" else command_page(cmd, group, cmds, docs)
            (OUT / page_url(cmd)).write_text(html_text, encoding="utf-8")
            built += 1
    (OUT / "index.html").write_text(index_page(groups, docs, len(listed)), encoding="utf-8")

    if missing:
        print(f"build-site: warning: no docs page yet, skipped {len(missing)}: {' '.join(missing)}", file=sys.stderr)
    if extra:
        print(f"build-site: warning: not in lib/commands, listed under Other: {' '.join(extra)}", file=sys.stderr)
    print(f"build-site: {built + 1} pages in {OUT.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
