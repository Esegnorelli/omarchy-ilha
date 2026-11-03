# Portão de contraste dos tokens do Theme.qml em todos os temas.
#
#   python3 -I dev/contrast.py [pasta de temas …]
#   (padrão: $OMARCHY_PATH/themes e ~/.config/omarchy/themes)
#
# Lê colors.toml como o Commons.Color do Omarchy (foreground, background,
# accent, red/color1 = urgent, com as reservas color0/color7/color4) e refaz
# as contas do Theme.qml: surface = mix(#000, escura, 0.10); ink = clara;
# accent >= 3:1 e accentInk >= 4,5:1 contra surface (subindo para a tinta em
# passos de 0,08); onAccent = #000 ou #fff; danger >= 3:1.
# Falha se onAccent < 4,5 contra accent ou accentInk < 4,5 contra surface.
# Avisa (não falha) accent < 3 e danger < 3.
import glob
import os
import re
import sys


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def lum(c):
    f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])


def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def lift(c, toward, ratio, against):
    for i in range(14):
        m = mix(c, toward, min(1, i * 0.08))
        if contrast(m, against) >= ratio:
            return m
    return toward


def parse(path):
    v = {"foreground": "#cacccc", "background": "#101315", "accent": "#cacccc", "urgent": "#a55555"}
    got = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r'^\s*([A-Za-z0-9_-]+)\s*=\s*["\']?(#[0-9A-Fa-f]{6})', line)
        if not m:
            continue
        k, val = m.group(1), m.group(2)
        if k in ("foreground", "background", "accent"):
            v[k] = val
            got[k] = True
        elif k in ("color0", "color4", "color7"):
            got[k] = val
        elif k in ("red", "color1"):
            v["urgent"] = val
    if "background" not in got and "color0" in got:
        v["background"] = got["color0"]
    if "foreground" not in got and "color7" in got:
        v["foreground"] = got["color7"]
    if "accent" not in got and "color4" in got:
        v["accent"] = got["color4"]
    return v


def tokens(v):
    bg, fg = hexrgb(v["background"]), hexrgb(v["foreground"])
    dark, ink = (bg, fg) if lum(bg) <= lum(fg) else (fg, bg)
    surface = mix((0, 0, 0), dark, 0.10)
    base = hexrgb(v["accent"])
    accent = lift(base, ink, 3.0, surface)
    accent_ink = lift(base, ink, 4.5, surface)
    black, white = (0, 0, 0), (1, 1, 1)
    on_accent = black if contrast(black, accent) >= contrast(white, accent) else white
    danger = lift(hexrgb(v["urgent"]), ink, 3.0, surface)
    return {
        "accent": contrast(accent, surface),
        "accentInk": contrast(accent_ink, surface),
        "onAccent": contrast(on_accent, accent),
        "danger": contrast(danger, surface),
        "ink": contrast(ink, surface),
    }


dirs = sys.argv[1:] or [os.path.join(os.environ.get("OMARCHY_PATH", os.path.expanduser("~/.local/share/omarchy")), "themes"),
                        os.path.expanduser("~/.config/omarchy/themes")]
rows, fail, warn = [], [], []
for d in dirs:
    for f in sorted(glob.glob(os.path.join(d, "*", "colors.toml"))):
        name = os.path.basename(os.path.dirname(f))
        t = tokens(parse(f))
        rows.append((name, t))
        if t["onAccent"] < 4.5:
            fail.append("%s: onAccent %.2f < 4.5" % (name, t["onAccent"]))
        if t["accentInk"] < 4.5:
            fail.append("%s: accentInk %.2f < 4.5" % (name, t["accentInk"]))
        if t["accent"] < 3.0:
            warn.append("%s: accent %.2f < 3" % (name, t["accent"]))
        if t["danger"] < 3.0:
            warn.append("%s: danger %.2f < 3" % (name, t["danger"]))

print("%-20s %7s %9s %8s %7s %6s" % ("tema", "accent", "accentInk", "onAccent", "danger", "ink"))
for name, t in rows:
    print("%-20s %7.2f %9.2f %8.2f %7.2f %6.2f" % (name, t["accent"], t["accentInk"], t["onAccent"], t["danger"], t["ink"]))
print("contrast: %d temas" % len(rows))
for w in warn:
    print("aviso: " + w)
if fail:
    for x in fail:
        print("FALHA: " + x)
    sys.exit(1)
print("contrast: onAccent >= 4.5 e accentInk >= 4.5 em todos")
