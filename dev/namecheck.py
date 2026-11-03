# Portão de nomes da Ilha 2.0.
#
#   python3 -I dev/namecheck.py [raiz do repo] [pasta qml do Qt, padrão /usr/lib/qt6/qml]
#
# Falha quando:
# 1. o nome de um arquivo de ui/ é igual a um tipo exportado por QtQuick,
#    QtQuick.Controls, QtQuick.Layouts, QtQuick.Effects, Quickshell,
#    Quickshell.Io, Quickshell.Wayland, Quickshell.Hyprland, Quickshell.Widgets
#    ou Quickshell.Services.* (qmltypes "exports" e linhas de tipo dos qmldir);
# 2. um arquivo importa QtQuick.Controls sem qualificador (`as QQC`);
# 3. um arquivo cuja raiz é um Item declara uma propriedade com o nome de uma
#    propriedade do Item (top, left, right, bottom, state, scale, …): no Qt 6.12
#    elas são FINAL e o tipo inteiro deixa de carregar.
import glob
import os
import re
import sys

repo = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
qml = sys.argv[2] if len(sys.argv) > 2 else "/usr/lib/qt6/qml"

MODULE_DIRS = [
    "QtQuick", "QtQuick/Controls", "QtQuick/Layouts", "QtQuick/Effects",
    "Quickshell", "Quickshell/Io", "Quickshell/Wayland", "Quickshell/Hyprland",
    "Quickshell/Widgets", "Quickshell/Services",
]
# Pastas que ficam dentro de QtQuick mas são módulos à parte (não importados pela Ilha).
SKIP_UNDER_QTQUICK = ("QtQuick/Controls", "QtQuick/Layouts", "QtQuick/Effects", "QtQuick/Dialogs",
                      "QtQuick/LocalStorage", "QtQuick/Particles", "QtQuick/Pdf", "QtQuick/Scene2D",
                      "QtQuick/Scene3D", "QtQuick/Shapes", "QtQuick/Templates", "QtQuick/Timeline",
                      "QtQuick/tooling", "QtQuick/VirtualKeyboard", "QtQuick/Window", "QtQuick/NativeStyle",
                      "QtQuick/VectorImage", "QtQuick/Particles")


def types_in(moddir, recursive):
    names = set()
    root = os.path.join(qml, moddir)
    if not os.path.isdir(root):
        return names
    if recursive:
        walk = [d for d, _, _ in os.walk(root)]
    else:
        walk = [root]
    for d in walk:
        rel = os.path.relpath(d, qml)
        if moddir == "QtQuick" and any(rel == s or rel.startswith(s + "/") for s in SKIP_UNDER_QTQUICK):
            continue
        for f in glob.glob(os.path.join(d, "*.qmltypes")):
            txt = open(f, encoding="utf-8", errors="replace").read()
            for m in re.finditer(r'exports:\s*\[([^\]]*)\]', txt):
                for e in re.findall(r'"([^"]+)"', m.group(1)):
                    n = e.split("/")[-1].split(" ")[0]
                    if n:
                        names.add(n)
        q = os.path.join(d, "qmldir")
        if os.path.isfile(q):
            for line in open(q, encoding="utf-8", errors="replace"):
                p = line.split()
                if len(p) >= 3 and re.match(r"^[A-Z]\w*$", p[0]) and p[-1].endswith((".qml", ".js")):
                    names.add(p[0])
                if len(p) >= 4 and p[0] in ("singleton", "internal") and re.match(r"^[A-Z]\w*$", p[1]):
                    names.add(p[1])
    return names


exported = set()
for m in MODULE_DIRS:
    exported |= types_in(m, recursive=(m != "QtQuick"))
# QtQuick: o próprio plugin e as subpastas de estilo que ele inclui
exported |= types_in("QtQuick", recursive=True)

# Propriedades do QQuickItem (qmltypes do QtQuick).
item_props = set()
for f in glob.glob(os.path.join(qml, "QtQuick", "*.qmltypes")):
    txt = open(f, encoding="utf-8", errors="replace").read()
    i = txt.find('name: "QQuickItem"')
    if i >= 0:
        j = txt.find("\n    Component {", i)
        item_props |= set(re.findall(r'Property \{\s*name: "([^"]+)"', txt[i:j]))
        item_props |= set(re.findall(r'Property \{\s*\n\s*name: "([^"]+)"', txt[i:j]))
# Propriedades que a Ilha pode redefinir de propósito (não são FINAL no Qt 6.12).
item_props -= {"implicitWidth", "implicitHeight"}

ITEMISH = {"Item", "Rectangle", "Text", "FocusScope", "MouseArea", "Loader", "Image", "Flickable",
           "ListView", "GridView", "Column", "Row", "Grid", "Flow", "Repeater", "TextInput",
           "TextEdit", "Canvas", "ShaderEffect", "MultiEffect", "RectangularShadow"}

files = sorted(glob.glob(os.path.join(repo, "ui", "*.qml")))
roots = {}
for f in files:
    src = open(f, encoding="utf-8").read()
    m = re.search(r"(?m)^([A-Z][\w.]*)\s*\{", src)
    roots[os.path.splitext(os.path.basename(f))[0]] = m.group(1) if m else ""


def is_item(t, seen=()):
    if t in ITEMISH:
        return True
    if t in roots and t not in seen:
        return is_item(roots[t], seen + (t,))
    return False


bad = []
for f in files + sorted(glob.glob(os.path.join(repo, "ui", "*.js"))):
    base = os.path.splitext(os.path.basename(f))[0]
    rel = os.path.relpath(f, repo)
    if f.endswith(".qml") and base in exported:
        bad.append("%s: o nome '%s' é um tipo exportado por um módulo importado" % (rel, base))
    src = open(f, encoding="utf-8").read()
    for m in re.finditer(r"(?m)^\s*import\s+QtQuick\.Controls(\s+[\d.]+)?\s*$", src):
        bad.append("%s: `import QtQuick.Controls` sem `as QQC`" % rel)
    for m in re.finditer(r"(?m)^\s*import\s+QtQuick\.Controls\b.*\bas\s+(\w+)", src):
        if m.group(1) != "QQC":
            bad.append("%s: QtQuick.Controls importado como %s (use QQC)" % (rel, m.group(1)))
    if f.endswith(".qml") and is_item(roots.get(base, "")):
        # Só as propriedades declaradas na raiz (indentação de 4 espaços).
        for m in re.finditer(r"(?m)^    (?:readonly\s+|required\s+|default\s+)*property\s+[\w<>.]+\s+(\w+)", src):
            if m.group(1) in item_props:
                line = src.count("\n", 0, m.start()) + 1
                bad.append("%s:%d: a propriedade '%s' já existe no Item (FINAL no Qt 6.12)" % (rel, line, m.group(1)))

print("namecheck: %d arquivos em ui/, %d tipos exportados conhecidos, %d propriedades do Item" % (len(files), len(exported), len(item_props)))
if bad:
    print("namecheck: %d colisões:" % len(bad))
    for b in bad:
        print("  " + b)
    sys.exit(1)
print("namecheck: 0 colisões")
