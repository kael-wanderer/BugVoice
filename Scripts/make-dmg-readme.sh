#!/usr/bin/env bash
#
# Regenerate "App/DMG/Read Me First.pdf" from "App/DMG/Read Me First.md".
# Needs python3 (built-in, no packages) and Google Chrome (headless print),
# like Scripts/make-app-icon.sh. Screenshots named in the Markdown are
# included when the files exist and omitted when they do not.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 -I - "$PWD/App/DMG" "$WORK/readme.html" <<'PY'
import html, os, re, sys

dmg, out = sys.argv[1], sys.argv[2]
lines = open(os.path.join(dmg, "Read Me First.md"), encoding="utf-8").read().splitlines()

def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)

def image(line):
    m = re.fullmatch(r"\s*!\[([^\]]*)\]\(([^)]+)\)\s*", line)
    if not m:
        return None
    path = os.path.realpath(os.path.join(dmg, m.group(2)))
    if not path.startswith(os.path.realpath(dmg) + os.sep) or not os.path.isfile(path):
        return ""  # missing screenshot: leave it out
    return '<img src="file://%s" alt="%s">' % (html.escape(path), html.escape(m.group(1)))

body, in_list = [], False
for line in lines:
    img = image(line)
    if img is not None:
        body.append(img)
        continue
    m = re.match(r"(#+) (.*)", line)
    n = re.match(r"\d+\. (.*)", line)
    if m:
        if in_list: body.append("</ol>"); in_list = False
        level = len(m.group(1))
        body.append("<h%d>%s</h%d>" % (level, inline(m.group(2)), level))
    elif n:
        if not in_list: body.append("<ol>"); in_list = True
        body.append("<li>%s</li>" % inline(n.group(1)))
    elif line.strip():
        if in_list and not line.startswith(" "): body.append("</ol>"); in_list = False
        body.append("<p>%s</p>" % inline(line.strip()))

if in_list: body.append("</ol>")
page = """<!doctype html><html><head><meta charset="utf-8"><style>
@page { size: Letter; margin: 18mm; }
body { font: 13px/1.5 -apple-system, Helvetica, Arial, sans-serif; color: #1d1d1f; }
h1 { font-size: 24px; } h2 { font-size: 18px; margin-top: 22px; } h3 { font-size: 15px; }
code { font: 12px Menlo, monospace; background: #eee; padding: 1px 5px; border-radius: 4px; }
img { display: block; max-width: 70%; margin: 8px 0 8px 22px; border: 1px solid #ccc; border-radius: 6px; }
</style></head><body>""" + "\n".join(body) + "</body></html>"
open(out, "w", encoding="utf-8").write(page)
PY

"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$PWD/App/DMG/Read Me First.pdf" "file://$WORK/readme.html" >/dev/null 2>&1
echo "Wrote App/DMG/Read Me First.pdf"
