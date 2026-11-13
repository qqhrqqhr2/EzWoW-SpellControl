#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Spell Control (docs/images/ui_*.png, settings_*.png).

The tactical board, the spells-by-level window, the spellbook panel, a spell tooltip and
the settings window and the recommended-talents button, menu and popup are rebuilt from the sizes,
coordinates, colours and strings in the addon code (UI/MicroBoard.lua, UI/SpellsByLevel.lua,
UI/OptionsWindow.lua, Modules/TalentBuilds.lua, Data/TalentBuilds.lua, Core/Init.lua DEFAULTS, Core/Locales.lua), in game pixels x scale. Icons are simplified drawings;
every name is made up.

usage: python scripts/make_readme_images.py .
Renders with a local headless Chrome (set CHROME=<path> if it is not found).
"""
import base64
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PAGE_W = 1600

# ---------------------------------------------------------------------------
# Small readers for the Lua code
# ---------------------------------------------------------------------------


def read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


def find_file(root, *names):
    """First existing file of names (case-insensitive on every system)."""
    for name in names:
        p = root / name
        if p.exists():
            return p
        parent = p.parent
        if parent.exists():
            for q in parent.iterdir():
                if q.name.lower() == p.name.lower():
                    return q
    raise FileNotFoundError(names)


def rgb_list(body):
    return [float(v) for v in body.split(",") if v.strip()]


def lua_table(src, start_pattern):
    """Text of the Lua table that starts at start_pattern (balanced braces)."""
    m = re.search(start_pattern, src)
    if not m:
        raise ValueError(start_pattern)
    i = src.index("{", m.start())
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[i + 1:j]
    raise ValueError("unbalanced " + start_pattern)


def lua_strings(block):
    """key = "value" pairs of a Lua table body (plain keys and ["keys"])."""
    out = {}
    for k1, k2, v in re.findall(r'(?:^|[\s,{])(?:(\w+)|\["((?:[^"\\]|\\.)*)"\])\s*=\s*"((?:[^"\\]|\\.)*)"', block, re.M):
        out[k1 or k2] = unlua(v)
    return out


def unlua(v):
    return v.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def toc_version(root):
    for p in root.glob("*.toc"):
        m = re.search(r"^## Version:\s*(\S+)", p.read_text(encoding="utf-8"), re.M)
        if m:
            return m.group(1)
    return ""


def css(c, alpha=None, mul=1.0):
    r, g, b = (round(min(1, v * mul) * 255) for v in c[:3])
    a = alpha if alpha is not None else (c[3] if len(c) > 3 else 1)
    return f"rgba({r},{g},{b},{a:.2f})"


def hexc(c):
    return "#%02x%02x%02x" % tuple(round(v * 255) for v in c[:3])


def esc(s):
    return html.escape(str(s), quote=False)


def wow(s):
    """Game text -> HTML: |cffRRGGBB..|r colours, |n / \\n line breaks, icons dropped."""
    s = esc(s)
    s = re.sub(r"\|T[^|]*\|t", "", s)
    s = re.sub(r"\|A[^|]*\|a", "", s)
    out, depth = [], 0
    pos = 0
    for m in re.finditer(r"\|c[0-9a-fA-F]{2}([0-9a-fA-F]{6})|\|r", s):
        out.append(s[pos:m.start()])
        if m.group(0) == "|r":
            if depth:
                out.append("</span>")
                depth -= 1
        else:
            out.append(f'<span style="color:#{m.group(1)}">')
            depth += 1
        pos = m.end()
    out.append(s[pos:])
    out.append("</span>" * depth)
    return "".join(out).replace("|n", "<br>").replace("\n", "<br>")


# ---------------------------------------------------------------------------
# Page parts (game px x S -> page px)
# ---------------------------------------------------------------------------
S = 1.3


def px(v):
    return f"{v * S:.2f}px"


OUTLINE = "text-shadow:-1px 0 #000,1px 0 #000,0 -1px #000,0 1px #000,0 0 2px #000;"
SHADOW = "text-shadow:1px 1px 0 #000,0 0 2px rgba(0,0,0,.8);"

# client colours used by several mock-ups
QUALITY = {0: "#9d9d9d", 1: "#ffffff", 2: "#1eff00", 3: "#0070dd", 4: "#a335ee", 5: "#ff8000"}
CLASS_HEX = {"WARRIOR": "#c69b6d", "PALADIN": "#f48cba", "HUNTER": "#aad372", "ROGUE": "#fff468", "PRIEST": "#ffffff",
             "SHAMAN": "#0070dd", "MAGE": "#3fc7eb", "WARLOCK": "#8788ee", "DRUID": "#ff7c0a"}
GOLD = "#ffd100"

THEME = {
    "bg": (0.071, 0.094, 0.122, 0.97), "bgSub": (0.114, 0.157, 0.192, 0.96), "border": (0.204, 0.298, 0.357, 1),
    "text": (0.929, 0.957, 0.969, 1), "muted": (0.655, 0.725, 0.773, 1), "accent": (0.5, 0.8, 0.9, 1),
}


def page_css(call):
    return f"""
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
html, body {{ width: {PAGE_W}px; overflow: hidden; }}
body {{ background: #0e141a; font-family: 'Noto Sans KR','Malgun Gothic',sans-serif; color: #edf4f7; position: relative; }}
.sky {{ position: absolute; left: 0; top: 0; width: {PAGE_W}px; height: 100%;
  background: radial-gradient(ellipse at 25% 0%, #1d2b38 0%, #151f28 45%, #10171d 75%, #0c1115 100%); }}
.hills {{ position: absolute; left: 0; bottom: 0; width: {PAGE_W}px; height: 260px; }}
.page {{ position: relative; padding: 34px 50px 0; }}
h1 {{ color: {call}; font-size: 40px; font-weight: 700; letter-spacing: .3px; display: flex; align-items: center; gap: 14px; }}
h1 .badge {{ font-size: 15px; background: {call}; color: #10161c; padding: 2px 9px; border-radius: 5px; }}
.lead {{ color: #d5dde2; font-size: 19px; margin-top: 6px; }}
.abs {{ position: absolute; }}
.t {{ position: absolute; white-space: nowrap; line-height: 1.15; }}
.call {{ position: absolute; width: 30px; height: 30px; border-radius: 50%; background: {call}; color: #10161c; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #10161c; box-shadow: 0 0 0 2px {call}55; z-index: 60; }}
.notes {{ position: absolute; }}
.note {{ display: flex; gap: 12px; margin-bottom: 11px; font-size: 16px; line-height: 1.5; color: #dfe6ea; }}
.note .n {{ flex: none; width: 28px; height: 28px; border-radius: 50%; background: {call}; color: #10161c; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; }}
.note b {{ color: #fff; }}
.foot {{ position: absolute; color: #7d8d98; font-size: 13.5px; line-height: 1.5; }}
.fit {{ display: inline-block; white-space: nowrap; }}
.tip {{ position: absolute; z-index: 30; }}
.tip .row {{ display: flex; justify-content: space-between; gap: 18px; white-space: nowrap; }}
"""


HILLS = ('<svg class="hills" viewBox="0 0 1600 260" preserveAspectRatio="none">'
         '<path d="M0 150 C 220 70 420 90 640 140 C 860 190 1060 60 1300 80 C 1440 92 1540 120 1600 130 V260 H0 Z" fill="#141c23" opacity=".9"/>'
         '<path d="M0 210 C 260 160 520 170 800 205 C 1080 240 1340 170 1600 190 V260 H0 Z" fill="#0b1014"/></svg>')

FIT_JS = """
<script>
document.querySelectorAll('[data-fit]').forEach(function (e) {
  var max = parseFloat(e.dataset.fit), min = parseFloat(e.dataset.min || 8);
  var fs = parseFloat(getComputedStyle(e).fontSize);
  while (e.scrollWidth > max && fs > min) { fs -= 0.25; e.style.fontSize = fs + 'px'; }
  if (e.scrollWidth > max) { e.style.maxWidth = max + 'px'; e.style.overflow = 'hidden'; e.style.textOverflow = 'ellipsis'; }
});
// place the footnote under the lowest element, then record the page height
var bottom = 0;
document.querySelectorAll('.page *, body > .abs, body > .notes, body > .call, body > .tip').forEach(function (e) {
  var r = e.getBoundingClientRect(); if (r.height > 0 && r.bottom > bottom) bottom = r.bottom;
});
var foot = document.querySelector('.foot');
if (foot) { foot.style.top = (bottom + 26) + 'px'; bottom = foot.getBoundingClientRect().bottom; }
document.body.setAttribute('data-h', Math.ceil(bottom + 34));
document.body.style.height = Math.ceil(bottom + 34) + 'px';
</script>
"""


def box(x, y, w, h, style="", inner=""):
    return f'<div class="abs" style="left:{px(x)};top:{px(y)};width:{px(w)};height:{px(h)};{style}">{inner}</div>'


def text(x, y, s, size, color="#fff", anchor="left", style="", fit=None, shadow=SHADOW):
    """Font string; y is the vertical centre (game px)."""
    tr = {"left": "translate(0,-50%)", "right": "translate(-100%,-50%)", "center": "translate(-50%,-50%)"}[anchor]
    inner = s if fit is None else f'<span class="fit" data-fit="{fit * S:.1f}" data-min="{size * 0.7 * S:.1f}">{s}</span>'
    return (f'<div class="t" style="left:{px(x)};top:{px(y)};font-size:{px(size)};color:{color};'
            f'transform:{tr};{shadow}{style}">{inner}</div>')


def text_top(x, y, s, size, color="#fff", width=None, style="", shadow=SHADOW):
    """Font string anchored at its top-left (TOPLEFT points)."""
    w = f"width:{px(width)};white-space:normal;" if width else ""
    return (f'<div class="t" style="left:{px(x)};top:{px(y)};font-size:{px(size)};color:{color};line-height:1.3;'
            f'{w}{shadow}{style}">{s}</div>')


class Window:
    """A flat EzWoW style window: header strip, accent line, icon, title, sub title, close box."""

    def __init__(self, th, w, h, title, sub="", icon=None, header=56, close=22, close_off=10, title_color=None):
        self.th, self.w, self.h = th, w, h
        self.p = []
        acc = css(th["accent"], 1)
        if header:
            self.p.append(box(1, 1, w - 2, header, f"background:{css(th['bgSub'], .98)}"))
            self.p.append(box(1, header - 1, w - 2, 2, f"background:{acc}"))
            if icon:
                self.p.append(f'<img class="abs" src="{icon}" style="left:{px(14)};top:{px(14)};width:{px(28)};height:{px(28)}">')
            self.p.append(text_top(48, 10, esc(title), 16, title_color or acc))
            if sub:
                self.p.append(text_top(48, 32, sub, 10, css(th["muted"]), width=w - 120))
            if close:
                self.button(w - 1 - close_off - close, close_off + 1, close, close, "X", size=12)

    def add(self, s):
        self.p.append(s)

    def section(self, x, y, label, width=None, line_dy=18):
        acc = css(self.th["accent"], 1)
        self.p.append(text_top(x, y, label, 13, acc))
        w = width if width else self.w - x - 20
        self.p.append(box(x, y + line_dy, w, 1, f"background:{css(self.th['border'], .85)}"))

    def check(self, x, y, label, on, size=24, label_w=180, font=12, disabled=False, color=None):
        mark = (f'<div class="t" style="left:{px(size * 0.1)};top:{px(-size * 0.12)};font-size:{px(size * 0.9)};color:#ffd200;'
                f'text-shadow:0 0 1px #000,1px 1px 0 #6b4a00">&#10004;</div>') if on else ""
        b = size * 0.72
        o = (size - b) / 2
        alpha = ";opacity:.55" if disabled else ""
        self.p.append(box(x + o, y + o, b, b, f"border:1px solid #6d6a5d;background:#191919;border-radius:2px;overflow:visible{alpha}", mark))
        col = color or css(self.th["muted"] if disabled else self.th["text"])
        self.p.append(text(x + size + 4, y + size / 2, label, font, col, fit=label_w))

    def radio(self, x, y, label, on, size=22, label_w=150, font=12):
        dot = box(size * .32, size * .32, size * .36, size * .36, "border-radius:50%;background:#ffd200;box-shadow:0 0 3px #ffb000") if on else ""
        self.p.append(box(x + 2, y + 2, size - 4, size - 4, "border:1px solid #7a7a7a;border-radius:50%;background:#151515", dot))
        self.p.append(text(x + size + 4, y + size / 2, label, font, css(self.th["text"]), fit=label_w))

    def button(self, x, y, w, h, label, accent=False, size=12, color=None, bg=None, border=None):
        th = self.th
        bgc = bg or css(th["bgSub"])
        bd = border or (css(th["accent"]) if accent else css(th["border"]))
        col = color or (css(th["accent"]) if accent else css(th["text"]))
        self.p.append(box(x, y, w, h, f"background:{bgc};border:1px solid {bd};display:flex;align-items:center;justify-content:center",
                          f'<span class="fit" data-fit="{(w - 10) * S:.1f}" data-min="{size * .7 * S:.1f}" '
                          f'style="font-size:{px(size)};color:{col};{SHADOW}">{label}</span>'))

    def stepper(self, x, y, label, value, minus_dx, plus_dx, bw=25, bh=25, label_dy=6, label_w=84, value_color=None, font=12):
        self.p.append(text_top(x, y + label_dy, f'<span class="fit" data-fit="{label_w * S:.1f}" data-min="{9 * S:.1f}">{label}</span>',
                               font, css(self.th["text"])))
        self.button(x + minus_dx, y, bw, bh, "-", size=14)
        self.button(x + plus_dx, y, bw, bh, "+", size=14)
        cx = x + minus_dx + bw / 2 + (plus_dx - minus_dx) / 2
        self.p.append(text(cx, y + bh / 2, value, font, value_color or css(self.th["text"]), anchor="center"))

    def html(self, ox, oy, extra_style=""):
        th = self.th
        return (f'<div class="abs" style="left:{ox}px;top:{oy}px;width:{px(self.w)};height:{px(self.h)};background:{css(th["bg"])};'
                f'border:1px solid {css(th["border"])};box-shadow:0 10px 40px rgba(0,0,0,.45);{extra_style}">' + "".join(self.p) + "</div>")


def tooltip(x, y, lines, border="#344c5b", width=None, pad=10, bg="rgba(18,24,31,.95)", gloss=True, bar=None, font=12,
            title_size=14, left_pad=0, z=30, extra=""):
    """A tooltip card at page px (x, y). lines: list of str | (left, right) | ("gap",); first line is the title.
    Strings are already HTML. bar: (fraction, colour, label) drawn along the bottom."""
    rows = []
    for i, ln in enumerate(lines):
        fs = title_size if i == 0 else font
        if ln == ("gap",):
            rows.append(f'<div style="height:{px(font * .7)}"></div>')
        elif isinstance(ln, tuple):
            rows.append(f'<div class="row" style="font-size:{px(fs)};line-height:1.42"><span>{ln[0]}</span><span>{ln[1]}</span></div>')
        else:
            rows.append(f'<div style="font-size:{px(fs)};line-height:1.42;white-space:nowrap">{ln}</div>')
    w = f"width:{px(width)};" if width else ""
    glo = (f'<div class="abs" style="left:0;right:0;top:0;height:{px(26)};background:linear-gradient(to bottom,rgba(255,255,255,.07),'
           f'rgba(255,255,255,0))"></div>') if gloss else ""
    bar_h = ""
    bottom_pad = pad
    if bar:
        frac, col, label = bar
        bottom_pad = pad + 10
        bar_h = (f'<div class="abs" style="left:{px(1)};right:{px(1)};bottom:{px(1)};height:{px(8)};background:rgba(0,0,0,.6)">'
                 f'<div class="abs" style="left:0;top:0;bottom:0;width:{frac * 100:.1f}%;background:{col}"></div>'
                 f'<div class="abs" style="inset:0;display:flex;align-items:center;justify-content:center;font-size:{px(7.5)};color:#fff;{OUTLINE}">{label}</div></div>')
    return (f'<div class="tip" style="left:{x:.0f}px;top:{y:.0f}px;{w}background:{bg};border:1px solid {border};'
            f'padding:{px(pad)} {px(pad)} {px(bottom_pad)} {px(pad + left_pad)};{SHADOW}z-index:{z};{extra}">'
            f'{glo}{"".join(rows)}{bar_h}</div>')


def callouts(points):
    return "".join(f'<div class="call" style="left:{x - 15:.0f}px;top:{y - 15:.0f}px">{i}</div>' for i, (x, y) in enumerate(points, 1))


def notes_html(notes, start=1):
    return "".join(f'<div class="note"><span class="n">{start + i}</span><div><b>{esc(a)}</b> — {b}</div></div>'
                   for i, (a, b) in enumerate(notes))


def notes_block(x, y, w, notes, start=1):
    return f'<div class="notes" style="left:{x:.0f}px;top:{y:.0f}px;width:{w:.0f}px">{notes_html(notes, start)}</div>'


def heading(title, lead, badge=None):
    b = f' <span class="badge">{esc(badge)}</span>' if badge else ""
    return f'<div class="page"><h1>{esc(title)}{b}</h1><div class="lead">{lead}</div></div>'


def icon_data(path):
    return "data:image/png;base64," + base64.b64encode(Path(path).read_bytes()).decode()


# simple square icon art (stands in for game icons)
ICON_ART = {
    "potion": ("#3a1418", '<path d="M40 14 H60 V34 C76 40 82 54 82 64 A32 26 0 0 1 18 64 C18 54 24 40 40 34 Z" fill="#d8323c"/><rect x="38" y="10" width="24" height="8" fill="#b08860"/>'),
    "mana": ("#121e3e", '<path d="M40 14 H60 V34 C76 40 82 54 82 64 A32 26 0 0 1 18 64 C18 54 24 40 40 34 Z" fill="#3d7cf0"/><rect x="38" y="10" width="24" height="8" fill="#b08860"/>'),
    "elixir": ("#14301e", '<path d="M44 12 H56 V40 L74 80 H26 L44 40 Z" fill="#5fd05a"/><rect x="40" y="8" width="20" height="8" fill="#b08860"/>'),
    "stone": ("#1c2a1c", '<path d="M50 12 L80 40 L62 86 H38 L20 40 Z" fill="#62e07a"/><path d="M50 12 L62 40 L50 86 L38 40 Z" fill="#a8f5b4"/>'),
    "helm": ("#2a2a30", '<path d="M18 64 C18 30 34 16 50 16 C66 16 82 30 82 64 L72 80 H28 Z" fill="#a8adb8"/><rect x="30" y="50" width="40" height="10" fill="#2a2a30"/>'),
    "glove": ("#2a2420", '<path d="M30 86 V44 L26 22 H36 L40 40 V16 H48 V40 V12 H56 V40 V16 H64 V44 L74 34 L80 40 L66 62 V86 Z" fill="#b58a5a"/>'),
    "ring": ("#2a2418", '<circle cx="50" cy="56" r="24" fill="none" stroke="#e8c050" stroke-width="10"/><path d="M42 26 L50 14 L58 26 L50 34 Z" fill="#6ad0ff"/>'),
    "sword": ("#202830", '<path d="M70 14 L84 16 L86 30 L44 72 L30 58 Z" fill="#cfd8e0"/><path d="M26 54 L46 74 L40 80 L20 60 Z" fill="#b08040"/><path d="M28 72 L18 82" stroke="#806030" stroke-width="8"/>'),
    "food": ("#3a2412", '<ellipse cx="50" cy="58" rx="30" ry="20" fill="#c87838"/><circle cx="64" cy="40" r="12" fill="#f0e0c0"/>'),
    "drink": ("#14283a", '<path d="M30 20 H70 L64 84 H36 Z" fill="#8fd0f0" opacity=".85"/><rect x="30" y="20" width="40" height="10" fill="#e0f4ff"/>'),
    "bandage": ("#2c2c2c", '<rect x="18" y="38" width="64" height="26" rx="12" fill="#e8e0d0" transform="rotate(-35 50 50)"/>'),
    "hearth": ("#1a2a3a", '<circle cx="50" cy="50" r="26" fill="#7fd0ff"/><circle cx="50" cy="50" r="12" fill="#e0f6ff"/>'),
    "pet": ("#2a2018", '<ellipse cx="50" cy="62" rx="26" ry="18" fill="#d8a060"/><circle cx="66" cy="38" r="14" fill="#d8a060"/><path d="M60 26 L62 14 L70 24 Z M72 28 L80 18 L80 32 Z" fill="#a06a30"/><circle cx="70" cy="38" r="3" fill="#201008"/>'),
    "pick": ("#2a2a2a", '<path d="M20 30 C40 14 64 14 82 30 L76 36 C62 26 42 26 26 36 Z" fill="#bcc4cc"/><rect x="46" y="28" width="8" height="58" fill="#8a6030"/>'),
    "herb": ("#1c3018", '<path d="M50 86 V40" stroke="#5a9040" stroke-width="6"/><ellipse cx="36" cy="44" rx="14" ry="8" fill="#70c050" transform="rotate(-30 36 44)"/><ellipse cx="64" cy="40" rx="14" ry="8" fill="#70c050" transform="rotate(30 64 40)"/><circle cx="50" cy="28" r="10" fill="#e070d0"/>'),
    "fire": ("#3a1a0a", '<path d="M50 12 C62 34 80 44 70 70 A22 22 0 0 1 30 70 C22 50 40 40 42 26 C48 36 50 30 50 12 Z" fill="#ff8a2a"/><path d="M50 46 C58 58 62 64 56 76 A10 10 0 0 1 42 74 C40 64 48 58 50 46 Z" fill="#ffe070"/>'),
    "holy": ("#3a3010", '<circle cx="50" cy="50" r="20" fill="#ffe680"/><path d="M50 10 V30 M50 70 V90 M10 50 H30 M70 50 H90 M22 22 L36 36 M64 64 L78 78 M22 78 L36 64 M64 36 L78 22" stroke="#ffe680" stroke-width="6"/>'),
    "shield": ("#1e2836", '<path d="M50 10 L84 22 C84 56 72 78 50 90 C28 78 16 56 16 22 Z" fill="#7aa4d8"/><path d="M50 22 L72 30 C72 54 64 70 50 78 Z" fill="#b8d4f4"/>'),
    "shadow": ("#1e1430", '<circle cx="50" cy="50" r="28" fill="#8a5ad8"/><circle cx="50" cy="50" r="14" fill="#2a1840"/>'),
    "frost": ("#14283a", '<path d="M50 12 V88 M17 31 L83 69 M17 69 L83 31" stroke="#bfe6ff" stroke-width="9" stroke-linecap="round"/>'),
    "nature": ("#203a1c", '<path d="M50 84 C20 70 18 36 50 14 C82 36 80 70 50 84 Z" fill="#7cd060"/><path d="M50 84 V30" stroke="#2a5a1c" stroke-width="5"/>'),
    "arcane": ("#2a1840", '<path d="M50 14 L58 42 L86 50 L58 58 L50 86 L42 58 L14 50 L42 42 Z" fill="#d79cff"/>'),
    "claw": ("#3a1414", '<path d="M25 80 L45 20 M45 82 L62 22 M65 84 L80 28" stroke="#ff6a5a" stroke-width="9" stroke-linecap="round"/>'),
    "bear": ("#2e2014", '<circle cx="50" cy="56" r="26" fill="#8a5a30"/><circle cx="30" cy="30" r="10" fill="#8a5a30"/><circle cx="70" cy="30" r="10" fill="#8a5a30"/><circle cx="42" cy="52" r="4" fill="#1a0a00"/><circle cx="58" cy="52" r="4" fill="#1a0a00"/>'),
    "cat": ("#3a2a1a", '<path d="M24 82 L24 34 L36 18 L44 34 L56 34 L64 18 L76 34 L76 82 Z" fill="#c9965a"/><circle cx="40" cy="50" r="5" fill="#2a1a0a"/><circle cx="60" cy="50" r="5" fill="#2a1a0a"/>'),
    "heal": ("#14301e", '<rect x="40" y="18" width="20" height="64" fill="#8cf08c"/><rect x="18" y="40" width="64" height="20" fill="#8cf08c"/>'),
    "book": ("#2a1e14", '<rect x="20" y="16" width="60" height="70" rx="4" fill="#8a4a2a"/><rect x="28" y="16" width="6" height="70" fill="#5a2a14"/><rect x="40" y="30" width="30" height="6" fill="#e8c890"/>'),
    "scroll": ("#2e2616", '<rect x="24" y="22" width="52" height="56" fill="#e8d8a8"/><rect x="18" y="16" width="64" height="10" rx="5" fill="#b89860"/><rect x="18" y="74" width="64" height="10" rx="5" fill="#b89860"/><path d="M34 40 H66 M34 52 H66 M34 64 H56" stroke="#8a6a3a" stroke-width="4"/>'),
    "flask": ("#2a1a3a", '<circle cx="50" cy="60" r="24" fill="#b070f0"/><rect x="42" y="14" width="16" height="26" fill="#b070f0"/><rect x="38" y="10" width="24" height="8" fill="#b08860"/>'),
    "thread": ("#1a2840", '<rect x="34" y="16" width="32" height="68" rx="6" fill="#d8b070"/><rect x="30" y="30" width="40" height="40" fill="#3a78d8"/>'),
    "hammer": ("#2a2a2a", '<rect x="22" y="18" width="56" height="22" rx="3" fill="#a0a8b0"/><rect x="45" y="40" width="10" height="46" fill="#8a6030"/>'),
    "fish": ("#10304a", '<path d="M14 50 C30 26 62 26 74 50 C62 74 30 74 14 50 Z" fill="#7fb8e0"/><path d="M74 50 L90 34 V66 Z" fill="#7fb8e0"/><circle cx="30" cy="46" r="4" fill="#0a1a2a"/>'),
    "gear": ("#26303a", '<circle cx="50" cy="50" r="22" fill="none" stroke="#c0c8d0" stroke-width="12" stroke-dasharray="9 6"/><circle cx="50" cy="50" r="10" fill="#c0c8d0"/>'),
    "bolt": ("#24204a", '<path d="M56 10 L26 56 H48 L40 90 L76 40 H54 Z" fill="#ffe14a"/>'),
    "chest": ("#2a1e10", '<rect x="18" y="38" width="64" height="42" fill="#9a6a30"/><path d="M18 38 C18 18 82 18 82 38 Z" fill="#b8843c"/><rect x="44" y="44" width="12" height="14" fill="#e8c050"/>'),
    "arrow": ("#2a2418", '<path d="M18 82 L72 28" stroke="#c8a870" stroke-width="7"/><path d="M64 20 L84 16 L80 36 Z" fill="#c0c8d0"/><path d="M18 82 L26 66 M18 82 L34 74" stroke="#e8e0d0" stroke-width="5"/>'),
    "kick": ("#2e1c14", '<path d="M30 20 L48 20 L54 56 L80 64 L78 80 L34 80 Z" fill="#c9965a"/>'),
    "stealth": ("#1a1a24", '<circle cx="50" cy="50" r="30" fill="#4a4a6a"/><path d="M26 50 C38 34 62 34 74 50 C62 66 38 66 26 50 Z" fill="#1a1a24"/><circle cx="50" cy="50" r="8" fill="#9aa0d0"/>'),
}


def icon_svg(kind):
    bg, shape = ICON_ART[kind]
    return (f'<svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none" style="display:block">'
            f'<defs><linearGradient id="sh_{kind}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".18"/>'
            f'<stop offset=".55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".35"/></linearGradient></defs>'
            f'<rect width="100" height="100" fill="{bg}"/>{shape}<rect width="100" height="100" fill="url(#sh_{kind})"/></svg>')


def icon_box(x, y, size, kind, border="#000", style=""):
    return box(x, y, size, size, f"border:1px solid {border};overflow:hidden;{style}", icon_svg(kind))


# ---------------------------------------------------------------------------
# Rendering (local headless Chrome)
# ---------------------------------------------------------------------------
def find_chrome():
    cands = [os.environ.get("CHROME"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
             shutil.which("chrome"), shutil.which("google-chrome"), shutil.which("chromium")]
    for c in cands:
        if c and Path(c).exists():
            return c
    sys.exit("Chrome not found (set CHROME=<path to chrome>)")


def chrome_args(chrome, tmp):
    return [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
            f"--user-data-dir={Path(tmp) / 'chrome_profile'}", "--virtual-time-budget=3000"]


def render(chrome, body, call, out_png, tmp):
    doc = (f'<!doctype html><html><head><meta charset="utf-8"><style>{page_css(call)}</style></head>'
           f'<body><div class="sky"></div>{HILLS}{body}{FIT_JS}</body></html>')
    page = Path(tmp) / (out_png.stem + ".html")
    page.write_text(doc, encoding="utf-8")
    # pass 1: let the page measure itself, pass 2: screenshot at that height
    dom = subprocess.run(chrome_args(chrome, tmp) + ["--window-size=1600,4000", "--dump-dom", page.as_uri()],
                         check=True, capture_output=True, timeout=120).stdout.decode("utf-8", "replace")
    m = re.search(r'data-h="(\d+)"', dom)
    height = int(m.group(1)) if m else 1200
    subprocess.run(chrome_args(chrome, tmp) + [f"--window-size={PAGE_W},{height}", f"--screenshot={out_png}", page.as_uri()],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    return height


def run_pages(root, pages, call):
    """pages: list of (file stem, function returning page body html)."""
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    chrome = find_chrome()
    tmp = tempfile.mkdtemp(prefix="ezwow_readme_")
    try:
        for stem, fn in pages:
            png = out / f"{stem}.png"
            h = render(chrome, fn(), call, png, tmp)
            print("wrote", png, h)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# EzWoW - Spell Control
# ---------------------------------------------------------------------------
TITLE = "EzWoW - Spell Control"


def load(root):
    loc = read(root, "Core/Locales.lua")
    init = read(root, "Core/Init.lua")
    ow = read(root, "UI/OptionsWindow.lua")
    sbl = read(root, "UI/SpellsByLevel.lua")
    mb = read(root, "UI/MicroBoard.lua")
    L = {"en": lua_strings(lua_table(loc, r"local lEnus = \{")), "ko": lua_strings(lua_table(loc, r"local lKokr = \{"))}
    for k, v in L["en"].items():
        L["ko"].setdefault(k, v)
    dflt = {}
    for k, v in re.findall(r"^\s{4}(\w+) = ([^,\n]+),", lua_table(init, r"ns\.DEFAULTS = \{"), re.M):
        dflt[k] = v.strip().strip('"')
    acc = [float(v) for v in re.search(r"ns\.ACCENT_R, ns\.ACCENT_G, ns\.ACCENT_B = ([\d.]+), ([\d.]+), ([\d.]+)", init).groups()] \
        if re.search(r"ns\.ACCENT_R, ns\.ACCENT_G, ns\.ACCENT_B = ", init) else \
        [float(v) for v in re.search(r"ns\.ACCENT_R or ([\d.]+), ns\.ACCENT_G or ([\d.]+), ns\.ACCENT_B or ([\d.]+)", sbl).groups()]
    style = {k: rgb_list(v) for k, v in re.findall(r"(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", lua_table(mb, r"local STYLE = \{"))}
    th = {"bg": style["bgMain"], "bgSub": style["bgSub"], "border": style["border"], "text": style["textMain"],
          "muted": style["textSub"], "accent": acc + [1]}
    win_size = re.search(r'config:SetSize\((\d+), (\d+)\)', ow)
    checks = [(k, -int(y), lab) for k, y, lab in re.findall(r'optionCheck\("(\w+)",\s+(-?\d+),\s+"(\w+)"\)', ow)]
    simple = [(k, int(x), -int(y), int(w)) for _, k, x, y, w in re.findall(r'config\.(\w+) = simpleCheck\("(\w+)", (\d+), (-?\d+), (\d+)', ow)]
    sections = [(-int(y)) for y in re.findall(r"config\.sec\w+ = section\((-?\d+)\)", ow)]
    sec_keys = re.findall(r'fitFontStringToWidth\(themeColor\.sec\w+, self:L\("(\w+)"\)', ow)
    steppers = {n: (int(x), -int(y)) for n, x, y in re.findall(r"config\.(\w+)Label, config\.\w+ = stepper\(\s*(\d+), (-?\d+)", ow)}
    actions = {n: (int(x), -int(y)) for n, x, y in re.findall(r"config\.(\w+) = actionBtn\((\d+), (-?\d+)", ow)}
    sbl_c = {k: int(v) for k, v in re.findall(r"^local (\w+_H) = (\d+)", sbl, re.M)}
    sbl_win = re.search(r"win:SetSize\((\d+), (\d+)\)", sbl)
    dock = re.search(r"panel:SetSize\(280, math\.max\((\d+), math\.min\(bookHeight - 4, (\d+)\)\)\)", sbl)
    tb = [(n, int(o)) for n, o in re.findall(r'buildToolbarControl\("\w+", "(\w+)", (-?\d+)', mb)]
    # recommended talents: button / menu / popup strings and the Priest builds
    tbm = read(root, "Modules/TalentBuilds.lua")
    tbd = read(root, "Data/TalentBuilds.lua")
    tl = {"ko": lua_strings(lua_table(tbm, r"koKR = \{")), "en": lua_strings(lua_table(tbm, r"enUS = \{"))}
    specs = {k: {"ko": ko, "en": en} for k, ko, en in re.findall(r'\["([\w-]+)"\] = \{ ko = "([^"]*)", en = "([^"]*)" \}', tbd)}
    builds = [{"spec": sp, "ko": ko, "en": en, "split": split} for sp, ko, en, split in
              re.findall(r'spec = "([\w-]+)", ko = "([^"]*)", en = "([^"]*)", split = "([^"]*)"', lua_table(tbd, r"PRIEST = \{"))]
    tb_btn = re.search(r'button:SetSize\((\d+), (\d+)\)', tbm)
    return {"tl": tl, "tSpecs": specs, "tBuilds": builds, "tBtn": (int(tb_btn.group(1)), int(tb_btn.group(2))),"L": L, "dflt": dflt, "th": th, "W": int(win_size.group(1)), "H": int(win_size.group(2)), "checks": checks,
            "simple": simple, "sections": list(zip(sections, sec_keys)), "steppers": steppers, "actions": actions,
            "sbl": sbl_c, "sblWin": (int(sbl_win.group(1)), int(sbl_win.group(2))), "dockMinMax": (int(dock.group(1)), int(dock.group(2))),
            "toolbar": tb, "small": int(re.search(r"ns\.SMALL_CELL_SIZE = (\d+)", init).group(1)),
            "icon": icon_data(find_file(root, "Media/Icon.png"))}


T = {
    "ko": {
        "lead": "파티 버프 · 디버프 해제 · 메즈를 클릭 한 번으로, 레벨별로 배울 주문과 추천 특성까지 (사제 예시)",
        "me": "나", "party": ["들꽃노래", "잿빛서리", "검은송곳"], "enemy": "해골 마법사",
        "cls": "사제", "scanned": "2026-11-06 21:14", "level": 20,
        "spells": [
            (16, "정신 분열", 2, 6000, "shadow", "learned"),
            (18, "신의 권능: 보호막", 3, 9000, "shield", "learned"),
            (18, "어둠의 권능: 고통", 3, 9000, "shadow", "learned"),
            (20, "순간 치유", 1, 18000, "holy", "now"),
            (20, "신성한 불꽃", 1, 18000, "fire", "now"),
            (20, "소생", 3, 18000, "heal", "now"),
            (22, "정신 분열", 3, 22000, "shadow", ""),
            (22, "강타", 4, 22000, "holy", ""),
            (24, "신의 권능: 인내", 3, 30000, "holy", ""),
            (24, "마나 연소", 1, 30000, "arcane", ""),
            (26, "어둠의 권능: 고통", 4, 36000, "shadow", ""),
        ],
        "book": "주문책", "chat": "EzWoW - Spell Control:",
        "tipA": ("신의 권능: 인내", "랭크 2", ["마나 105", "30 미터 사거리", "즉시 시전"], "대상의 체력을 30분 동안 8만큼 증가시킵니다."),
        "tipB": ("신성한 불꽃", "랭크 1", ["마나 85", "30 미터 사거리", "시전 시간 3.5초"], "신성한 불꽃으로 대상을 태웁니다."),
        "notes": [
            ("제목 줄", "마우스를 올리면 접기 · 잠금 · 설정(톱니) 단추. Ctrl+제목 드래그로 이동, 오른쪽 아래 모서리로 크기 조절."),
            ("버프 · 해제 · 메즈", "버프가 빠진 파티원, 내가 지울 수 있는 디버프(테두리 색 = 종류), 적 대상에 걸 수 있는 메즈만 칸에 나옵니다. 좌/우클릭으로 바로 시전."),
            ("주문 툴팁 랭크 안내", "배운 주문에는 “다음 랭크: 랭크 N · Lv”, 아직 배우지 않은 랭크에는 “배울 수 있는 레벨”이 붙습니다."),
            ("레벨별 배울 스킬 (/ezsc spells)", "직업 기술 전문가를 열 때 저장한 목록. 지금 배울 수 있는 주문은 강조, 배운 주문은 흐리게 체크, 오른쪽은 비용."),
            ("주문책 옆 패널", "주문책을 열면 같은 목록이 옆에 붙습니다(줄마다 Lv). < 단추로 접기."),
            ("레벨업 알림", "레벨이 오르면 새로 배울 수 있는 주문 수를 채팅창에 알려 줍니다."),
            ("추천 특성 (/추천특성)", "특성 창의 단추. 직업별 빌드를 고르면 남은 포인트를 빌드 순서대로 넣고, 적용할지 한 번 더 묻습니다. 레벨이 오를 때마다 다시 누르면 이어서 찍습니다."),
        ],
        "foot": "애드온 코드의 창 크기 · 좌표 · 색상 · 문구로 재현한 예시 화면입니다. 전술 보드는 칸 크기 40(설정에서 바꿀 수 있음)으로 그렸습니다. 파티원 이름은 지어낸 예시이고, 아이콘과 주문책 · 특성 창 테두리는 단순화했습니다.",
        "sLead": "/ezsc · 버프 · 해제 · 메즈 동작, 클릭 지정, 보유 주문, 창 배치, 레벨별 스킬",
        "sTitle": "설정창",
        "learned": [("보유 버프 (좌/우):", "[좌] 신의 권능: 인내, [우] 내면의 열정"), ("보유 해제 (좌/우):", "[좌] 마법 무효화, [우] 질병 치료"),
                    ("보유 메즈 (좌/우):", "[좌] 언데드 속박 (언데드), [우] 영혼의 절규")],
        "sNotes": [
            ("동작 설정", "빠진 버프 자동 추천, 저레벨 대상 자동 하향, 보조 버프 검사, 파티 전체 버프 우선, 해제 알림음, 솔로 표시, 우호적 대상, 메즈 칸, 위로 펼치기, 새 랭크를 배우면 단축바의 낮은 랭크 교체, 담당 공대 파티(1~8)."),
            ("클릭 지정 · 보유 주문 · 언어", "좌클릭 · 우클릭 버프(자동 추천 / 특정 버프 / 사용 안 함), 배운 버프 · 해제 · 메즈 목록, 언어(목록에서 선택)."),
            ("창 배치", "파티 · 공대 칸 크기, 한 줄 개수, 불투명도, 마우스 올릴 때만 표시, 만료 임박(남은 시간이 짧은 버프도 빠진 것으로)."),
            ("상태 단추", "창 잠금 · 숨기기, 전체 펼치기 · 접기, 새로고침, 위치 초기화."),
            ("레벨별 스킬", "레벨별 배울 스킬 창, 레벨업 때 배울 주문 알림, 주문책 옆에 레벨별 스킬 표시."),
            ("후원", "후원 주소 복사 창."),
        ],
        "sFoot": "애드온 코드의 창 크기 · 좌표 · 색상 · 문구로 재현한 예시 화면입니다. 체크 상태와 숫자는 기본값이며, 보유 주문 목록은 사제 예시입니다.",
    },
    "en": {
        "lead": "One-click party buffs, cleanses and crowd control, plus spells by level and recommended talents (Priest example)",
        "me": "Me", "party": ["Wildsong", "Ashfrost", "Darkfang"], "enemy": "Skeletal Mage",
        "cls": "Priest", "scanned": "2026-11-06 21:14", "level": 20,
        "spells": [
            (16, "Mind Blast", 2, 6000, "shadow", "learned"),
            (18, "Power Word: Shield", 3, 9000, "shield", "learned"),
            (18, "Shadow Word: Pain", 3, 9000, "shadow", "learned"),
            (20, "Flash Heal", 1, 18000, "holy", "now"),
            (20, "Holy Fire", 1, 18000, "fire", "now"),
            (20, "Renew", 3, 18000, "heal", "now"),
            (22, "Mind Blast", 3, 22000, "shadow", ""),
            (22, "Smite", 4, 22000, "holy", ""),
            (24, "Power Word: Fortitude", 3, 30000, "holy", ""),
            (24, "Mana Burn", 1, 30000, "arcane", ""),
            (26, "Shadow Word: Pain", 4, 36000, "shadow", ""),
        ],
        "book": "Spellbook", "chat": "EzWoW - Spell Control:",
        "tipA": ("Power Word: Fortitude", "Rank 2", ["105 Mana", "30 yd range", "Instant"], "Power infuses the target increasing their Stamina by 8 for 30 min."),
        "tipB": ("Holy Fire", "Rank 1", ["85 Mana", "30 yd range", "3.5 sec cast"], "Consumes the enemy in Holy flame."),
        "notes": [
            ("Title bar", "Hover for fold, lock and settings (gear). Ctrl + drag the title to move, drag the bottom-right corner to resize."),
            ("Buffs · cleanse · CC", "Only members missing a buff, debuffs you can remove (border colour = type) and CC you can use on the enemy target get cells. Left/right-click casts at once."),
            ("Rank hints in spell tooltips", "Learned spells show “Next rank: Rank N · Lv”, ranks you have not learned show “Learnable at level”."),
            ("Spells by level (/ezsc spells)", "Saved when you open your class trainer. Spells you can learn now are highlighted, learned ones are faded with a check, the cost is on the right."),
            ("Spellbook panel", "Opening the spellbook docks the same list next to it (with Lv on each row). Fold it with <."),
            ("Level-up notice", "On level-up, chat tells you how many new spells you can learn."),
            ("Recommended talents (/eztalent)", "A button on the talent window. Pick a build for your class: free points are spent in the build's order, then you confirm before they are applied. Click again after each level to continue."),
        ],
        "foot": "Mock-ups rebuilt from the window sizes, coordinates, colours and strings in the addon code. The board is drawn with cell size 40 (adjustable in the settings). Party names are made up; icons and the spellbook and talent window edges are simplified.",
        "sLead": "/ezsc · buff, cleanse & CC behaviour, click assignment, learned spells, layout, spells by level",
        "sTitle": "Settings",
        "learned": [("Buffs (L/R):", "[L] Power Word: Fortitude, [R] Inner Fire"), ("Cleanse (L/R):", "[L] Dispel Magic, [R] Cure Disease"),
                    ("CC (L/R):", "[L] Shackle Undead (Undead), [R] Psychic Scream")],
        "sNotes": [
            ("Behaviour", "Auto-suggest missing buffs, auto-downrank on low-level targets, secondary buffs, prefer group buffs, cleanse sound, show yourself solo, friendly target, CC slot, expand upward, replace lower ranks on action bars after learning a new rank, raid groups you look after (1–8)."),
            ("Click assignment · learned spells · language", "Left/right-click buff (Auto / a specific buff / none), learned buffs, cleanses and CC, language (pick from the list)."),
            ("Layout", "Party and raid cell size, per row, opacity, show only on mouseover, expiring soon (buffs running out count as missing)."),
            ("Board buttons", "Lock and hide the board, expand and collapse all, refresh, reset position."),
            ("Spells by level", "Open the spells-by-level window, level-up spell notice, show spells by level next to the spellbook."),
            ("Support", "Copy the support link."),
        ],
        "sFoot": "Mock-up rebuilt from the window size, coordinates, colours and strings in the addon code. Check boxes and numbers show the defaults; the learned-spell list is a Priest example.",
    },
}

BOARD_CELL = 40
DEBUFF = {"Magic": (0.2, 0.6, 1.0), "Disease": (0.6, 0.4, 0.0), "Poison": (0.0, 0.6, 0.0), "Curse": (0.6, 0.0, 1.0)}


def money(copper, lang):
    g, s = copper // 10000, (copper % 10000) // 100
    out = []
    if g:
        out.append(f'{g}<span style="color:#ffd700">●</span>')
    if s:
        out.append(f'{s}<span style="color:#c7c7cf">●</span>')
    return " ".join(out)


def board(ctx, lang):
    t, L, th = T[lang], ctx["L"][lang], ctx["th"]
    acc = css(th["accent"])
    # cell size 40 (option range 20-64) so the names stay readable in the picture; columns = default
    size, cols = BOARD_CELL, int(ctx["dflt"]["columns"])
    W = max(165, 16 + cols * (size + 4))
    p = []
    y = 32
    sections = [
        (L["GROUP_BUFF"], [(t["me"], "PRIEST", "holy", L["BADGE_BUFF_L"], None, 1), (t["party"][0], "DRUID", "holy", L["BADGE_BUFF_L"], None, 1),
                           (t["party"][1], "MAGE", "holy", L["BADGE_BUFF_R"], None, 1), (t["party"][2], "ROGUE", "holy", L["BADGE_OUT_OF_RANGE"], None, .45)]),
        (L["GROUP_CLEANSE"], [(t["party"][1], "MAGE", "arcane", L["BADGE_DISPEL_L"].replace("%s", L["DEBUFF_Magic"]), "Magic", 1),
                              (t["party"][0], "DRUID", "bandage", L["BADGE_ABOLISHING"], "Disease", 1)]),
        (L["GROUP_CC"], [(t["enemy"], None, "shadow", L["BADGE_CC_L"], None, 1)]),
    ]
    for title, cells in sections:
        p.append(box(8, y, W - 16, 20, f"background:{css(th['bgSub'], .92)}"))
        p.append(box(8, y, 2, 20, f"background:{acc}"))
        p.append(text(20, y + 10, esc(f"v  {title}  |  {len(cells)}"), 10, css(th["text"])))
        p.append(text(W - 16, y + 10, "↕", 10, css(th["accent"], .85), anchor="right"))
        y += 25
        for i, (name, cls, icon, badge, deb, alpha) in enumerate(cells):
            x = 8 + (i % cols) * (size + 4)
            border = css(DEBUFF[deb]) if deb else "#000"
            inner = f'<div class="abs" style="left:{px(2)};top:{px(2)};right:{px(2)};bottom:{px(2)}">{icon_svg(icon)}</div>'
            if cls:
                inner += f'<div class="abs" style="left:{px(2)};top:{px(2)};right:{px(2)};height:{px(3)};background:{CLASS_HEX[cls]}"></div>'
            inner += (f'<div class="t" style="left:0;right:0;top:{px(5)};text-align:center;font-size:{px(10)};color:#fff;{OUTLINE}'
                      f'overflow:hidden">{esc(name)}</div>')
            inner += (f'<div class="t" style="left:0;right:0;bottom:{px(2)};text-align:center;font-size:{px(10)};color:#ffd100;{OUTLINE}">'
                      f'{esc(badge)}</div>')
            bw = 2 if deb else 1
            p.append(box(x, y, size, size, f"background:{css((0.09, 0.125, 0.155), .92)};border:{px(bw)} solid {border};opacity:{alpha}", inner))
        y += (size + 4) + 5
    H = y + 6
    p.insert(0, text(12, 14, esc(L["BOARD_TITLE"]), 10, acc))
    glyph = {"fold": "⌄", "unlock": "🔓", "gear": "⚙"}
    for name, off in ctx["toolbar"]:
        g = {"fold": "v", "unlock": "&#9711;", "gear": "&#9881;"}[name]
        p.insert(1, box(W + off - 23, 3, 23, 23, f"background:{css(th['bgSub'], .92)};border:1px solid {css(th['border'], .95)};display:flex;align-items:center;justify-content:center",
                        f'<span style="color:{css(th["text"])};font-size:{px(12)}">{g}</span>'))
    p.append(f'<div class="abs" style="right:{px(3)};bottom:{px(3)};width:{px(12)};height:{px(12)};'
             f'background:linear-gradient(135deg,transparent 50%,#7c8a96 50%,#7c8a96 58%,transparent 58%,transparent 70%,#7c8a96 70%,#7c8a96 78%,transparent 78%)"></div>')
    return W, H, "".join(p)


def spell_rows(ctx, lang, compact, width):
    """RenderList of UI/SpellsByLevel.lua: every level, a highlighted "your level" line before the
    first row at or above the player's level, rank 1 / rankless unlearned rows marked as new spells
    (gold), and the list scrolled to that line minus 3 rows as on opening.
    Returns html of the rows (game px) and the height."""
    t, L, c = T[lang], ctx["L"][lang], ctx["sbl"]
    acc = css(ctx["th"]["accent"])
    new_col = "#ffd100"   # NEW_R, NEW_G, NEW_B = 1, 0.82, 0
    p, y, last, marker_y = [], 0, None, None

    def header(label, current=False):
        nonlocal y
        if current:
            p.append(box(0, y, width, c["HEADER_H"], f"background:{css(ctx['th']['accent'], .14)}"))
        p.append(text_top(4, y + c["HEADER_H"] - 5 - 13, esc(label), 12, new_col if current else acc))
        p.append(box(0, y + c["HEADER_H"] - 3, width, 1, "background:rgba(52,76,91,.85)"))
        y += c["HEADER_H"]

    for lvl, name, rank, cost, icon, state in t["spells"]:
        if marker_y is None and lvl >= t["level"]:
            marker_y = y
            header(L["SBL_CURRENT_LEVEL"].replace("%d", str(t["level"])), True)
            if lvl == t["level"]:
                last = lvl          # the marker names the level already
        if not compact and lvl != last:
            last = lvl
            header(L["SBL_LEVEL"].replace("%d", str(lvl)))
        h = c["COMPACT_ROW_H"] if compact else c["ROW_H"]
        cost_w = 74 if compact else 96
        is_new = rank in (None, 1) and state != "learned"
        if is_new:
            label = f'{esc(name)} <span style="color:{new_col}">({esc(L["SBL_NEW_SPELL"])})</span>'
        else:
            label = f'{esc(name)} <span style="color:#A7B9C5">({esc(L["SBL_RANK"].replace("%d", str(rank)))})</span>'
        if compact:
            label = f"Lv {lvl} · " + label
        if state == "learned":
            col = "#A7B9C5"
        elif is_new:
            col = new_col
        elif state == "now":
            col = acc
        else:
            col = "#EDF4F7"
        alpha = 0.45 if state == "learned" else 1
        row = []
        if state == "now":
            row.append(box(0, 0, width, h, f"background:{css(ctx['th']['accent'], .14)}"))
        isz = h - 4
        row.append(icon_box(4, 2, isz, icon, style="filter:grayscale(1)" if state == "learned" else ""))
        if state == "learned":
            row.append(f'<div class="t" style="left:{px(4 + isz - 10)};top:{px(isz - 9)};font-size:{px(13)};color:#3ce03c;{OUTLINE}">&#10004;</div>')
        row.append(text(4 + isz + 6, h / 2, label, 10, col, fit=width - (4 + isz + 6) - cost_w - 12))
        row.append(text(width - 6, h / 2, money(cost, lang), 10, "#fff", anchor="right"))
        p.append(f'<div class="abs" style="left:0;top:{px(y)};width:{px(width)};height:{px(h)};opacity:{alpha}">{"".join(row)}</div>')
        y += h
    # opened at the player's level: scroll = markerY - 3 * ROW_H
    off = max(0, (marker_y or 0) - 3 * c["ROW_H"])
    return f'<div class="abs" style="left:0;top:{px(-off)};width:{px(width)};height:{px(y)}">{"".join(p)}</div>', y - off


def scrollbar(x, y, h):
    return (box(x, y, 16, h, "background:rgba(0,0,0,.35);border-radius:2px")
            + box(x + 3, y + 18, 10, h * 0.45, "background:#4a5560;border-radius:3px"))


def summary(ctx, lang):
    t, L = T[lang], ctx["L"][lang]
    now = [s for s in t["spells"] if s[5] == "now"]
    return esc(L["SBL_SUMMARY"].replace("%d", str(len(now)), 1).replace("%s", "")) + money(sum(s[3] for s in now), lang)


def ui_page(lang, ctx):
    global S
    t, L, th = T[lang], ctx["L"][lang], ctx["th"]
    acc = css(th["accent"])
    parts = [heading(TITLE, esc(t["lead"]))]
    # 1-2 board
    S = 1.4
    bx, by = 50, 168
    W, H, inner = board(ctx, lang)
    parts.append(f'<div class="abs" style="left:{bx}px;top:{by}px;width:{px(W)};height:{px(H)};background:{css(th["bg"], .93)};'
                 f'border:1px solid {css(th["border"], .9)}">{inner}</div>')
    board_bottom = by + H * S
    calls = [(bx + W * S + 4, by + 16), (bx - 14, by + 60 * S)]
    # 3 spell tooltips with rank hints
    S = 1.2
    ta = t["tipA"]
    la = [(f'<span style="color:#fff">{esc(ta[0])}</span>', f'<span style="color:#808080">{esc(ta[1])}</span>')] + \
         [esc(s) for s in ta[2]] + [f'<span style="color:#ffd100;white-space:normal">{esc(ta[3])}</span>',
                                    f'<span style="color:{acc}">{esc(L["SBL_TIP_NEXT"].replace("%d", "3", 1).replace("%d", "24", 1))}</span>']
    ty = board_bottom + 26
    parts.append(tooltip(bx, ty, la, width=250))
    tb = t["tipB"]
    lb = [(f'<span style="color:#fff">{esc(tb[0])}</span>', f'<span style="color:#808080">{esc(tb[1])}</span>')] + \
         [esc(s) for s in tb[2]] + [f'<span style="color:#ffd100;white-space:normal">{esc(tb[3])}</span>',
                                    f'<span style="color:{acc}">{esc(L["SBL_TIP_LEARN_AT"].replace("%d", "20"))}</span>']
    parts.append(tooltip(bx, ty + 178, lb, width=250))
    calls.append((bx, ty))
    # 4 spells-by-level window
    S = 1.15
    ww, wh = ctx["sblWin"]
    wx, wy = 420, 168
    win = Window(th, ww, wh, L["SBL_TITLE"], esc(f'{t["cls"]} · ' + L["SBL_SCANNED"].replace("%s", t["scanned"])), ctx["icon"],
                 header=52, close=22, close_off=10)
    win.add(text_top(16, 64, summary(ctx, lang), 12, acc))
    rows, rh = spell_rows(ctx, lang, False, ww - 12 - 32)
    win.add(f'<div class="abs" style="left:{px(12)};top:{px(88)};width:{px(ww - 44)};height:{px(wh - 100)};overflow:hidden">{rows}</div>')
    win.add(scrollbar(ww - 28, 88, wh - 100))
    parts.append(win.html(wx, wy))
    calls.append((wx, wy))
    # 5 spellbook edge + docked panel
    sbx, sby = wx + ww * S + 26, 168
    book_w, book_h = 120, 470
    parts.append(f'<div class="abs" style="left:{sbx}px;top:{sby}px;width:{px(book_w)};height:{px(book_h)};'
                 f'background:linear-gradient(90deg,#2a2218,#3b3022);border:{px(3)} solid #6b5a3a;border-left:none;border-radius:0 6px 6px 0">'
                 f'<div class="t" style="left:{px(14)};top:{px(14)};font-size:{px(13)};color:#ffd100;{OUTLINE}">{esc(t["book"])}</div>'
                 + "".join(icon_box(14 + (i % 2) * 48, 46 + (i // 2) * 48, 36, k) for i, k in enumerate(["holy", "heal", "shield", "fire", "shadow", "stealth", "arcane", "holy"]))
                 + '</div>')
    dmin, dmax = ctx["dockMinMax"]
    dh = max(dmin, min(book_h - 4, dmax))
    dx, dy = sbx + book_w * S + 4 * S, sby + 2 * S
    p = [text(10, 9 + 7, esc(L["SBL_TITLE"]), 12, acc),
         box(280 - 6 - 22, 5, 22, 22, f"background:{css(th['bgSub'])};border:1px solid {css(th['border'])};display:flex;align-items:center;justify-content:center",
             f'<span style="color:{css(th["muted"])};font-size:{px(10)}">&lt;</span>'),
         text(10, 32 + 6, summary(ctx, lang), 10, acc, fit=256)]
    rows, _ = spell_rows(ctx, lang, True, 280 - 6 - 28)
    p.append(f'<div class="abs" style="left:{px(6)};top:{px(50)};width:{px(280 - 34)};height:{px(dh - 58)};overflow:hidden">{rows}</div>')
    p.append(scrollbar(280 - 24, 50, dh - 58))
    parts.append(f'<div class="abs" style="left:{dx:.0f}px;top:{dy:.0f}px;width:{px(280)};height:{px(dh)};background:{css(th["bg"], .96)};'
                 f'border:1px solid {css(th["border"])}">{"".join(p)}</div>')
    calls.append((dx + 280 * S, dy))
    # 6 level-up chat line
    cy = sby + book_h * S + 26
    msg = esc(L["SBL_LEVELUP_MSG"].replace("%d", "3"))
    parts.append(f'<div class="abs" style="left:{sbx}px;top:{cy:.0f}px;width:{PAGE_W - 40 - sbx:.0f}px;padding:10px 14px;background:rgba(0,0,0,.45);'
                 f'border-radius:4px;font-size:15px;line-height:1.5;{SHADOW}"><span style="color:#ffff00">[{esc("레벨 21" if lang == "ko" else "Level 21")}]</span> '
                 f'<span style="color:#5CE0B8">{esc(t["chat"])}</span> <span style="color:#fff">{msg}</span></div>')
    calls.append((sbx, cy))
    # 7 recommended talents: button on the talent window, its menu, the confirm popup
    S = 1.15
    tl = ctx["tl"][lang]
    ky = cy + 84
    strip_w = PAGE_W - 40 - sbx
    bw, bh = ctx["tBtn"]
    sw, sh = 150, 22                       # talent search box (simplified)
    sx = sbx + strip_w - 16 - sw * S
    bxx = sx - 10 * S - bw * S
    red_btn = ("background:linear-gradient(#9a2216,#5e0f09);border:1px solid #2a0704;border-radius:3px;"
               "box-shadow:inset 0 1px 0 rgba(255,255,255,.18);display:flex;align-items:center;justify-content:center")
    parts.append(f'<div class="abs" style="left:{sbx}px;top:{ky:.0f}px;width:{strip_w:.0f}px;height:{px(36)};'
                 f'background:linear-gradient(#23252b,#17181c);border:{px(2)} solid #4b4b4f;border-radius:6px 6px 0 0">'
                 + "".join(f'<div class="abs" style="left:{16 + i * 70}px;top:{px(9)};width:{px(56)};height:{px(14)};'
                           f'background:rgba(255,255,255,.05);border-radius:3px"></div>' for i in range(3))
                 + '</div>')
    parts.append(f'<div class="abs" style="left:{sx:.0f}px;top:{ky + 7 * S:.0f}px;width:{px(sw)};height:{px(sh)};background:#0b0b0d;'
                 f'border:1px solid #5a5a5e;border-radius:3px;font-size:{px(11)};color:#7a7a7a;padding-left:{px(8)};line-height:{px(sh - 2)}">'
                 f'{esc("검색" if lang == "ko" else "Search")}</div>')
    parts.append(f'<div class="abs" style="left:{bxx:.0f}px;top:{ky + 7 * S:.0f}px;width:{px(bw)};height:{px(bh)};{red_btn}">'
                 f'<span style="font-size:{px(11)};color:#ffd100;{SHADOW}">{esc(tl["button"])}</span></div>')
    # menu (MenuUtil context menu) under the button
    cls_name = t["cls"]
    rows = [f'<div style="color:#ffd100;font-size:{px(12)};padding:{px(3)} {px(10)}">{esc(tl["menuTitle"].replace("%s", cls_name))}</div>']
    pick = None
    for b in ctx["tBuilds"]:
        label = f'{ctx["tSpecs"][b["spec"]][lang]} ({b[lang]})'
        hl = "background:rgba(255,255,255,.13);" if b["spec"] == "shadow" else ""
        if b["spec"] == "shadow":
            pick = label
        rows.append(f'<div style="{hl}color:#fff;font-size:{px(12)};padding:{px(3)} {px(10)};white-space:nowrap">{esc(label)}'
                    f'&nbsp;&nbsp;<span style="color:#999999">{esc(b["split"])}</span></div>')
    rows.append(f'<div style="height:1px;background:#4a4a4a;margin:{px(4)} {px(8)}"></div>')
    rows.append(f'<div style="color:#8c8c8c;font-size:{px(12)};padding:{px(3)} {px(10)}">EzWoW - Spell Control</div>')
    my = ky + (7 + bh + 4) * S
    parts.append(f'<div class="abs" style="left:{bxx:.0f}px;top:{my:.0f}px;min-width:{px(180)};padding:{px(5)} 0;background:rgba(12,12,14,.95);'
                 f'border:1px solid #5c5c60;border-radius:4px;box-shadow:0 6px 18px rgba(0,0,0,.5);{SHADOW}z-index:40">{"".join(rows)}</div>')
    menu_bottom = my + (5 * 2 + 4 * 24 + 9 + 24) * S
    # confirm popup (StaticPopup), left of the menu
    pw = min(300, (bxx - sbx - 24) / S)
    popup = wow(tl["confirm"].replace("%s", pick or "", 1).replace("%d", "10", 1)) + "<br><br>" + '<span style="color:#8c8c8c">EzWoW - Spell Control</span>'
    pbtn = lambda s: (f'<div style="width:{px(110)};height:{px(22)};{red_btn}"><span style="font-size:{px(11)};color:#ffd100;{SHADOW}">'  # noqa: E731
                      f'{esc(s)}</span></div>')
    parts.append(f'<div class="abs" style="left:{sbx + 6:.0f}px;top:{my + 4:.0f}px;width:{px(pw)};padding:{px(14)} {px(12)} {px(12)};'
                 f'background:rgba(8,8,10,.94);border:{px(2)} solid #6c6c70;border-radius:6px;text-align:center;font-size:{px(12)};'
                 f'line-height:1.45;color:#fff;{SHADOW}box-shadow:0 8px 24px rgba(0,0,0,.55);z-index:35">{popup}'
                 f'<div style="display:flex;justify-content:center;gap:{px(8)};margin-top:{px(12)}">{pbtn(tl["apply"])}{pbtn(tl["cancel"])}</div></div>')
    calls.append((sbx, ky))
    parts.append(callouts(calls))
    ny = max(ty + 420, menu_bottom + 40, my + 4 + 200 * S)   # under the menu and the popup
    parts.append(notes_block(50, ny, 730, [(a, esc(b_)) for a, b_ in t["notes"][:4]]))
    parts.append(notes_block(820, ny, 730, [(a, esc(b_)) for a, b_ in t["notes"][4:]], start=5))
    parts.append(f'<div class="foot" style="left:50px;width:1500px">{esc(t["foot"])}</div>')
    return "".join(parts)


def settings_page(lang, ctx):
    global S
    S = 1.05
    t, L, th, d = T[lang], ctx["L"][lang], ctx["th"], ctx["dflt"]
    acc = css(th["accent"])
    W, H = ctx["W"], ctx["H"]
    win = Window(th, W, H, L["SETTINGS_TITLE"], esc(L["SETTINGS_SUBTITLE"]), ctx["icon"], header=58, close=24, close_off=10)
    for y, key in ctx["sections"]:
        win.section(20, y, esc(L[key]), line_dy=20)
    for key, y, lab in ctx["checks"]:
        win.check(20, y, esc(L[lab]), d.get(key) == "true", size=26, label_w=340)
    # raid groups 1-8 (all on)
    win.add(text_top(24, 340, f'<span class="fit" data-fit="{118 * S:.1f}">{esc(L["OPT_RAID_GROUPS"])}</span>', 12, css(th["text"])))
    for g in range(1, 9):
        win.button(148 + (g - 1) * 31, 334, 28, 24, str(g), color=acc, bg="rgba(28,51,56,.96)", border=acc)
    slot = lambda k, v: f'{L[k]} {v} ▼'  # noqa: E731
    win.button(20, 400, 187, 28, esc(slot("OPT_PRIMARY_BUFF", L["OPT_AUTO"])))
    win.button(213, 400, 187, 28, esc(slot("OPT_SECOND_BUFF", L["OPT_AUTO"])))
    lines = "<br>".join(f'<span style="color:{c}">{esc(k)}</span> <span style="color:#fff">{esc(v)}</span>'
                        for (k, v), c in zip(t["learned"], ("#F1BD57", "#5CE0B8", "#E77C70")))
    win.add(box(20, 433, 380, 62, f"background:rgba(14,19,25,.9);border:1px solid {css(th['border'], .85)}",
                f'<div class="abs" style="left:{px(8)};top:{px(6)};right:{px(8)};font-size:{px(10)};line-height:{px(14)};color:#A7B9C5;{SHADOW}">{lines}</div>'))
    win.button(20, 503, 380, 28, esc(f'{L["OPT_LANGUAGE"]}: Auto ▼'))
    st = ctx["steppers"]
    vals = {"size": d["cellSize"], "raidSize": d["raidCellSize"], "cols": d["columns"], "alpha": f'{round(float(d["opacity"]) * 100)}%',
            "expire": L["OPT_EXPIRING_VALUE"].replace("%d", d["expiringMinutes"])}
    keys = {"size": "OPT_SIZE", "raidSize": "OPT_RAID_SIZE", "cols": "OPT_COLUMNS", "alpha": "OPT_OPACITY", "expire": "OPT_EXPIRING"}
    for name, (x, y) in st.items():
        win.stepper(x, y, esc(L[keys[name]]), esc(str(vals[name])), 94, 160, bw=27, bh=29, label_dy=8, label_w=88)
    win.check(20, 639, esc(L["OPT_FADE"]), d.get("fade") == "true", size=26, label_w=160)
    btn_keys = {"lockBtn": "BTN_LOCK", "visBtn": "BTN_HIDE_BAR", "expandBtn": "BTN_EXPAND", "collapseBtn": "BTN_COLLAPSE",
                "refreshBtn": "BTN_REFRESH", "resetPosBtn": "BTN_RESET_POS", "spellsByLevelBtn": "BTN_SPELLS_BY_LEVEL"}
    for name, (x, y) in ctx["actions"].items():
        win.button(x, y, 181, 31, esc(L[btn_keys[name]]))
    for key, x, y, w in ctx["simple"]:
        lab = {"levelUpSpellNotice": "OPT_LEVELUP_NOTICE", "spellbookDock": "OPT_SPELLBOOK_DOCK"}[key]
        win.check(x, y, esc(L[lab]), d.get(key) != "false", size=26, label_w=w)
    win.add(f'<div class="t" style="left:{px(20)};top:{px(H - 78 - 12)};font-size:{px(10)};color:#808080;{SHADOW}">{esc(L["HINT_MOVE_RESIZE"])}</div>')
    win.button(20, H - 38 - 32, 380, 32, esc(L["BTN_DONATE"]), accent=True, bg="rgba(28,51,56,.96)")
    win.add(f'<div class="t" style="left:50%;transform:translateX(-50%);bottom:{px(12)};font-size:{px(10)};color:#808080;{SHADOW}">'
            f'EzWoW - Spell Control v{esc(ctx.get("version", ""))}  ·  /ezsc</div>')
    ox, oy = 60, 150
    secs = [y for y, _ in ctx["sections"]]
    spans = [(secs[0], 360), (secs[1], 532), (secs[2], 668), (672, 774), (777, 840), (H - 70, H - 38)]
    calls = [(ox + W * S + 22, oy + (a + b_) / 2 * S) for a, b_ in spans]
    nx = ox + W * S + 70
    return (heading(TITLE, esc(t["sLead"]), t["sTitle"]) + win.html(ox, oy) + callouts(calls)
            + notes_block(nx, oy + 6, PAGE_W - nx - 40, [(a, esc(b_)) for a, b_ in t["sNotes"]])
            + f'<div class="foot" style="left:50px;width:1500px">{esc(t["sFoot"])}</div>')


def main(root: Path):
    ctx = load(root)
    ctx["version"] = toc_version(root)
    call = hexc(ctx["th"]["accent"])
    run_pages(root, [(f"{n}_{lang}", (lambda n=n, lang=lang: (ui_page if n == "ui" else settings_page)(lang, ctx)))
                     for lang in ("ko", "en") for n in ("ui", "settings")], call)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())
