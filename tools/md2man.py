#!/usr/bin/env python3
"""Build man/man1/<command>.1 from docs/<command>.md.

It reads the small part of Markdown the docs use: headings, paragraphs, lists,
tables, fenced code, inline code, bold, italics and links. Standard library only.
Run: python3 tools/md2man.py [docs/unpack.md ...]
"""
import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION = (ROOT / "VERSION").read_text().strip()


def esc(text):
    """Escape text for roff, outside code."""
    text = text.replace("\\", "\\e")
    text = text.replace("-", "\\-")
    return text


def inline(text):
    """Markdown inline marks to roff fonts."""
    out = []
    pos = 0
    for m in re.finditer(r"`([^`]+)`|\*\*([^*]+)\*\*|\*([^*]+)\*|\[([^\]]+)\]\(([^)]+)\)", text):
        out.append(esc(text[pos:m.start()]))
        code, bold, ital, ltext, lurl = m.groups()
        if code is not None:
            out.append("\\fB" + esc(code) + "\\fR")
        elif bold is not None:
            out.append("\\fB" + esc(bold) + "\\fR")
        elif ital is not None:
            out.append("\\fI" + esc(ital) + "\\fR")
        else:
            if lurl.startswith("#") or lurl.endswith(".md"):
                out.append(esc(ltext))
            else:
                out.append(esc(ltext) + " (" + esc(lurl) + ")")
        pos = m.end()
    out.append(esc(text[pos:]))
    line = "".join(out)
    # A line starting with . or ' would be read as a roff request.
    if line.startswith((".", "'")):
        line = "\\&" + line
    return line


def split_row(line):
    cells = line.strip().strip("|").split("|")
    return [c.strip() for c in cells]


def convert(md_path):
    lines = md_path.read_text().splitlines()
    name = md_path.stem
    title = lines[0].lstrip("# ").strip() if lines else name
    oneliner = ""
    i = 1
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and not lines[i].startswith("#"):
        oneliner = lines[i].strip().rstrip(".")
        i += 1

    date = datetime.date.today().isoformat()
    out = [
        f'.TH "{title.upper()}" 1 "{date}" "toolbelt {VERSION}" "toolbelt manual"',
        ".SH NAME",
        f"{esc(title)} \\- {inline(oneliner[:1].lower() + oneliner[1:])}",
    ]

    para = []

    def flush():
        if para:
            out.append(".PP")
            out.append(inline(" ".join(para)))
            para.clear()

    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s.startswith("```"):
            flush()
            i += 1
            out.append(".PP")
            out.append(".RS 4")
            out.append(".nf")
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code = lines[i].replace("\\", "\\e")
                if code.startswith((".", "'")):
                    code = "\\&" + code
                out.append(code)
                i += 1
            out.append(".fi")
            out.append(".RE")
        elif s.startswith("## "):
            flush()
            out.append(".SH " + esc(s[3:].upper()))
        elif s.startswith("### ") or s.startswith("#### "):
            flush()
            out.append(".SS " + esc(s.lstrip("# ")))
        elif s.startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            flush()
            header = split_row(s)
            i += 2
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(split_row(lines[i]))
                i += 1
            i -= 1
            if len(header) == 2:
                for row in rows:
                    out.append(".TP")
                    out.append(inline(row[0]))
                    out.append(inline(row[1] if len(row) > 1 else ""))
            else:
                for row in rows:
                    out.append(".TP")
                    out.append(inline(row[0]))
                    rest = [f"{h}: {c}" for h, c in zip(header[1:], row[1:]) if c]
                    out.append(inline(". ".join(rest)))
        elif re.match(r"^([-*]|\d+\.)\s+", s):
            flush()
            text = re.sub(r"^([-*]|\d+\.)\s+", "", s)
            # Continuation lines are indented.
            while i + 1 < len(lines) and lines[i + 1].startswith("  ") and lines[i + 1].strip() \
                    and not re.match(r"^\s*([-*]|\d+\.)\s+", lines[i + 1]):
                i += 1
                text += " " + lines[i].strip()
            out.append(".IP \\(bu 2")
            out.append(inline(text))
        elif not s:
            flush()
        else:
            para.append(s)
        i += 1
    flush()
    return "\n".join(out) + "\n"


def main(args):
    paths = [Path(a) for a in args] or sorted((ROOT / "docs").glob("*.md"))
    outdir = ROOT / "man" / "man1"
    outdir.mkdir(parents=True, exist_ok=True)
    n = 0
    for p in paths:
        if p.stem.isupper() or p.stem.startswith("_"):
            continue
        (outdir / f"{p.stem}.1").write_text(convert(p))
        n += 1
    print(f"wrote {n} man pages to man/man1")


if __name__ == "__main__":
    main(sys.argv[1:])
