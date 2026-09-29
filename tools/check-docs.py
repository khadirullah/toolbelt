#!/usr/bin/env python3
"""Check every command against the rules in CONTRIBUTING.md.

For each command in lib/commands it checks:
- the script, the docs page and the test file exist
- the docs page has the required sections, in order
- the docs one-liner matches the one-liner in --help
- no em or en dashes, curly quotes or status words in help and docs
- every tool the script needs has a row in lib/pkgmap
Exit 1 when anything fails. Run: python3 tools/check-docs.py
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = ["Synopsis", "Description", "Options", "Needs", "Examples", "Exit status"]
BANNED_CHARS = {"—": "em dash", "–": "en dash", "“": "curly quote", "”": "curly quote",
                "‘": "curly quote", "’": "curly quote"}
BANNED_WORDS = ["roadmap", "phase", "coming soon", "draft", "mockup", "wacky", "todo", "tbd"]
SHELL_FUNCS = {"mkcd", "up"}


def commands():
    for line in (ROOT / "lib/commands").read_text().splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            yield from line.split()[1:]


def pkgmap_names():
    names = set()
    for line in (ROOT / "lib/pkgmap").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            names.add(line.split()[0])
    return names


def help_text(cmd):
    if cmd in SHELL_FUNCS:
        src = f'source "{ROOT}/shell/functions.sh"; {cmd} --help'
        res = subprocess.run(["bash", "-c", src], capture_output=True, text=True)
    else:
        res = subprocess.run([str(ROOT / "bin" / cmd), "--help"], capture_output=True, text=True,
                             env={"PATH": "/usr/bin:/bin", "HOME": "/tmp", "NO_COLOR": "1"})
    return res.returncode, res.stdout


def text_problems(where, text):
    found = []
    for ch, what in BANNED_CHARS.items():
        if ch in text:
            found.append(f"{where}: has an {what}")
    low = text.lower()
    for w in BANNED_WORDS:
        if re.search(r"\b" + re.escape(w) + r"\b", low):
            found.append(f"{where}: uses the word '{w}'")
    return found


def main():
    problems = []
    known = pkgmap_names()
    for cmd in commands():
        script = ROOT / ("shell/functions.sh" if cmd in SHELL_FUNCS else f"bin/{cmd}")
        doc = ROOT / "docs" / f"{cmd}.md"
        test = ROOT / "tests" / f"{cmd}.bats"
        if not script.exists():
            problems.append(f"{cmd}: no {script.relative_to(ROOT)}")
            continue
        if cmd not in SHELL_FUNCS and not os.access(script, os.X_OK):
            problems.append(f"{cmd}: bin/{cmd} is not executable")
            continue
        if not test.exists() and cmd not in SHELL_FUNCS:
            problems.append(f"{cmd}: no tests/{cmd}.bats")
        rc, help_out = help_text(cmd)
        if rc != 0:
            problems.append(f"{cmd}: --help exits {rc}")
        help_lines = help_out.splitlines()
        if not help_lines or not help_lines[0].startswith("usage: "):
            problems.append(f"{cmd}: help does not start with 'usage: '")
        # The one-liner is the first line after the first blank line, below the usage lines.
        oneliner = ""
        if "" in help_lines:
            after = help_lines[help_lines.index("") + 1:]
            oneliner = after[0].strip() if after else ""
        if len(oneliner) > 60:
            problems.append(f"{cmd}: help one-liner is {len(oneliner)} characters, keep it under 60")
        for n, line in enumerate(help_lines, 1):
            if len(line) > 80:
                problems.append(f"{cmd}: help line {n} is {len(line)} columns, keep it to 80")
        problems += text_problems(f"{cmd} --help", help_out)

        if not doc.exists():
            problems.append(f"{cmd}: no docs/{cmd}.md")
        else:
            md = doc.read_text()
            lines = md.splitlines()
            if not lines or lines[0].strip() != f"# {cmd}":
                problems.append(f"{cmd}: docs title must be '# {cmd}'")
            first = next((l.strip() for l in lines[1:] if l.strip()), "")
            if oneliner and first != oneliner:
                problems.append(f"{cmd}: docs one-liner '{first}' differs from help '{oneliner}'")
            heads = [l[3:].strip() for l in lines if l.startswith("## ")]
            pos = -1
            for req in REQUIRED:
                if req not in heads:
                    problems.append(f"{cmd}: docs lack a '## {req}' section")
                    continue
                if heads.index(req) < pos:
                    problems.append(f"{cmd}: docs section '{req}' is out of order")
                pos = heads.index(req)
            prose = re.sub(r"```.*?```", "", md, flags=re.S)
            problems += text_problems(f"docs/{cmd}.md", prose)

        if cmd not in SHELL_FUNCS:
            src = script.read_text()
            for m in re.finditer(r"tb_(need|hint|need_any)\s+([^\n;|&]+)", src):
                words = m.group(2).split()
                if m.group(1) == "need_any":
                    words = words[1:]
                elif m.group(1) == "hint":
                    words = words[:1]
                for w in words:
                    w = w.strip("\"'")
                    if re.fullmatch(r"[a-z0-9][a-z0-9.+_-]*", w) and w not in known:
                        problems.append(f"{cmd}: needs {w}, which has no row in lib/pkgmap")

    for p in sorted(set(problems)):
        print(p)
    count = len(set(problems))
    print(f"{count} problem{'s' if count != 1 else ''}" if count else "docs check passed")
    return 1 if count else 0


if __name__ == "__main__":
    sys.exit(main())
