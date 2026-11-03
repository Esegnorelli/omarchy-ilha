# Portão dos ícones da Ilha 2.0 (HarfBuzz).
#
#   uv run --no-project --with fonttools --with uharfbuzz python -I dev/icons.py \
#       <MaterialSymbolsRounded.ttf completa> [raiz do repo]
#
# 1. Cada nome de dev/icons.txt molda para exatamente UM glifo na fonte
#    completa e para o MESMO glifo em fonts/MaterialSymbolsRoundedIlha2.ttf.
# 2. Coleta os literais de ícone em ui/*.qml e ui/*.js e exige que cada um
#    esteja em dev/icons.txt. Contextos de ícone:
#    a) `name:` dentro de um bloco `Icon { … }`;
#    b) uma propriedade ou chave de objeto cujo nome é icon / glyph ou termina
#       em Icon / Glyph (icon:, glyph:, markIcon:, leadGlyph:, …); a expressão
#       vai até o fim da linha, ou do bloco { … } se começar com {;
#    c) `return "…"` dentro de uma função cujo nome tem icon / glyph (iconFor…);
#    d) os valores (lado direito) de um objeto atribuído a uma propriedade
#       terminada em Icons / Glyphs ({"chave-do-host": "glifo", …});
#    e) qualquer linha com o comentário `ilha-icons`.
#    Só contam literais no formato de nome de ícone ([a-z][a-z0-9_]*).
# 3. Avisa (não falha) os nomes de icons.txt que nenhum arquivo usa.
# Sai com 1 se algo não resolve.
import glob
import os
import re
import sys

import uharfbuzz as hb
from fontTools.ttLib import TTFont

NAME = re.compile(r"^[a-z][a-z0-9_]*$")
LIT = re.compile(r'"([^"\\]*)"')
KEY = re.compile(r'(?:^|[\s{,(])"?((?:icon|glyph)|[A-Za-z_]*(?:Icon|Glyph))"?\s*:\s*')


def shaper(path):
    face = hb.Face(hb.Blob.from_file_path(path))
    font = hb.Font(face)

    def shape(text):
        buf = hb.Buffer()
        buf.add_str(text)
        buf.guess_segment_properties()
        hb.shape(font, buf, {"liga": True})
        return [i.codepoint for i in buf.glyph_infos]
    return shape


def block_from(text, start):
    """Devolve o trecho de text[start] (um '{') até o '}' que fecha."""
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return text[start:]


def expr_from(text, start):
    """A expressão de uma propriedade / chave: até a primeira `,` `;` `}` `)`
    `]` ou quebra de linha no nível 0 (ternários inteiros contam)."""
    if text.startswith("{", start):
        return block_from(text, start)
    depth, in_str, i = 0, False, start
    while i < len(text):
        c = text[i]
        if c == '"' and text[i - 1] != "\\":
            in_str = not in_str
        elif not in_str:
            if c in "([{":
                depth += 1
            elif c in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif depth == 0 and c in ",;\n":
                break
        i += 1
    return text[start:i]


def strip_comments(src):
    out = []
    for line in src.splitlines():
        if "ilha-icons" in line:
            out.append(line)
            continue
        # tira // comentário fora de string (aproximação suficiente para a Ilha)
        res, in_str = [], False
        i = 0
        while i < len(line):
            c = line[i]
            if c == '"' and (i == 0 or line[i - 1] != "\\"):
                in_str = not in_str
            if not in_str and line.startswith("//", i):
                break
            res.append(c)
            i += 1
        out.append("".join(res))
    return "\n".join(out)


def collect(path):
    raw = open(path, encoding="utf-8").read()
    src = strip_comments(raw)
    found = []  # (literal, linha)

    def add_from(expr, offset):
        line = src.count("\n", 0, offset) + 1
        for m in LIT.finditer(expr):
            v = m.group(1)
            if NAME.match(v):
                found.append((v, line))

    # a) Icon { … name: … }
    for m in re.finditer(r"\bIcon\s*\{", src):
        blk = block_from(src, m.end() - 1)
        for n in re.finditer(r"(?m)^\s*name\s*:\s*(.+)$", blk):
            add_from(n.group(1), m.start() + n.start())
    # b) icon: / glyph: / *Icon: / *Glyph:
    for m in KEY.finditer(src):
        add_from(expr_from(src, m.end()), m.start())
    # c) return "…" em funções de ícone
    for m in re.finditer(r"function\s+([A-Za-z_]*(?:icon|Icon|glyph|Glyph)[A-Za-z_]*)\s*\([^)]*\)\s*\{", src):
        body = block_from(src, m.end() - 1)
        for r in re.finditer(r'return\s+([^;\n]+)', body):
            add_from(r.group(1), m.start())
    # d) propriedades *Icons / *Glyphs: só os valores
    for m in re.finditer(r"property\s+var\s+[A-Za-z_]*(?:Icons|Glyphs)\s*:\s*\(?\{", src):
        blk = block_from(src, m.end() - 1)
        for kv in re.finditer(r'"[^"]*"\s*:\s*"([^"]*)"', blk):
            if NAME.match(kv.group(1)):
                found.append((kv.group(1), src.count("\n", 0, m.start()) + 1))
    # e) linhas marcadas
    for i, line in enumerate(raw.splitlines(), 1):
        if "ilha-icons" in line:
            for lm in LIT.finditer(line):
                if NAME.match(lm.group(1)):
                    found.append((lm.group(1), i))
    return found


def main():
    if len(sys.argv) < 2:
        sys.exit("uso: icons.py <fonte completa> [repo]")
    full = sys.argv[1]
    repo = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    names = [l.strip() for l in open(os.path.join(repo, "dev", "icons.txt"), encoding="utf-8") if l.strip() and not l.startswith("#")]
    sub = os.path.join(repo, "fonts", "MaterialSymbolsRoundedIlha2.ttf")
    bad = []

    fs, ss = shaper(full), shaper(sub)
    forder, sorder = TTFont(full, lazy=True).getGlyphOrder(), TTFont(sub, lazy=True).getGlyphOrder()
    for n in names:
        a, b = fs(n), ss(n)
        if len(a) != 1 or a[0] == 0:
            bad.append("%s: %d glifos na fonte completa" % (n, len(a)))
        elif len(b) != 1 or b[0] == 0 or sorder[b[0]] != forder[a[0]]:
            bad.append("%s: o subset não dá o mesmo glifo (%s)" % (n, ",".join(sorder[g] for g in b)))

    wanted = set(names)
    used = set()
    files = sorted(glob.glob(os.path.join(repo, "ui", "*.qml")) + glob.glob(os.path.join(repo, "ui", "*.js")))
    for f in files:
        for lit, line in collect(f):
            used.add(lit)
            if lit not in wanted:
                bad.append("%s:%d: \"%s\" não está em dev/icons.txt" % (os.path.relpath(f, repo), line, lit))
            elif len(fs(lit)) != 1:
                bad.append("%s:%d: \"%s\" não molda para um glifo" % (os.path.relpath(f, repo), line, lit))

    unused = sorted(wanted - used)
    print("icons: %d nomes em icons.txt, %d usados em %d arquivos" % (len(names), len(used & wanted), len(files)))
    if unused:
        print("icons: sem uso (aviso): " + ", ".join(unused))
    if bad:
        print("icons: %d sem resolver:" % len(bad))
        for b in bad:
            print("  " + b)
        sys.exit(1)
    print("icons: 0 sem resolver")


if __name__ == "__main__":
    main()
