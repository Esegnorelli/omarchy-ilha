# Gera as duas fontes que a Ilha carrega (fonts/), a partir das originais.
#
#   uv run --no-project --with fonttools --with uharfbuzz python -I dev/subset.py \
#       symbols <MaterialSymbolsRounded.ttf completa> dev/icons.txt fonts/MaterialSymbolsRoundedIlha2.ttf
#   uv run --no-project --with fonttools --with uharfbuzz python -I dev/subset.py \
#       inter <InterVariable.ttf> fonts/InterIlha2.ttf
#
# symbols: só os ícones de dev/icons.txt. O GSUB perde todas as outras
#   ligaduras ANTES do subset (senão o fechamento a partir de a–z puxaria os
#   6 mil ícones de volta). Ficam os eixos FILL, wght e opsz; GRAD é fixado
#   em 0. Cada nome é moldado com HarfBuzz na fonte completa e na gerada e
#   precisa dar exatamente o mesmo glifo, um só.
# inter: as faixas do host_contract, eixo wght (opsz fixado em 14) e as
#   features tnum / kern / calt (mais as de base que o HarfBuzz aplica).
#
# O nome da família muda (a fonte do sistema, se houver, não toma o lugar).
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

SYMBOLS_FAMILY = "Material Symbols Rounded Ilha2"
INTER_FAMILY = "Inter Ilha2"

INTER_RANGES = [
    (0x0000, 0x024F), (0x02B0, 0x02FF), (0x0300, 0x036F), (0x0370, 0x03FF),
    (0x0400, 0x04FF), (0x1E00, 0x1EFF), (0x2000, 0x206F), (0x20A0, 0x20CF),
    (0x2190, 0x21FF),
]
INTER_SINGLES = [0x2212, 0x00D7, 0x00B7, 0x2026]
INTER_FEATURES = ["kern", "calt", "tnum", "ccmp", "locl", "mark", "mkmk", "liga", "rlig", "case"]


def shape(path, text):
    import uharfbuzz as hb
    blob = hb.Blob.from_file_path(path)
    face = hb.Face(blob)
    font = hb.Font(face)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {"liga": True})
    return [info.codepoint for info in buf.glyph_infos]


def rename(font, family):
    name = font["name"]
    ps = family.replace(" ", "")
    for rec in list(name.names):
        if rec.nameID in (16, 17, 21, 22, 25):
            name.removeNames(nameID=rec.nameID)
    for plat, enc, lang in ((3, 1, 0x409), (1, 0, 0)):
        name.setName(family, 1, plat, enc, lang)
        name.setName("Regular", 2, plat, enc, lang)
        name.setName(family, 4, plat, enc, lang)
        name.setName(ps, 6, plat, enc, lang)
        name.setName(family + " Regular", 3, plat, enc, lang)


def symbols(src, icons_file, out):
    names = [l.strip() for l in open(icons_file, encoding="utf-8") if l.strip() and not l.startswith("#")]
    if len(set(names)) != len(names):
        sys.exit("icons.txt tem nomes repetidos")
    full = TTFont(src)
    order = full.getGlyphOrder()
    want = {}
    bad = []
    for n in names:
        gids = shape(src, n)
        if len(gids) != 1 or gids[0] == 0:
            bad.append(n)
            continue
        want[n] = order[gids[0]]
    if bad:
        sys.exit("não molda para um glifo só na fonte completa: " + ", ".join(bad))

    # 1. GSUB: só as ligaduras cujo texto é um nome da lista.
    # O cmap leva "A" e "a" ao mesmo glifo: o texto é comparado em minúsculas.
    rev = {}
    for cp, gname in full.getBestCmap().items():
        rev.setdefault(gname, chr(cp).lower())
    keep_glyphs = set(want.values())
    wanted_text = set(names)
    for lookup in full["GSUB"].table.LookupList.Lookup:
        for st in lookup.SubTable:
            st = getattr(st, "ExtSubTable", st)
            if getattr(st, "LookupType", 0) != 4:
                continue
            kept = {}
            for first, ligs in st.ligatures.items():
                ok = []
                for lig in ligs:
                    text = "".join(rev.get(g, "\0") for g in [first] + list(lig.Component))
                    if text in wanted_text and lig.LigGlyph in keep_glyphs:
                        ok.append(lig)
                if ok:
                    kept[first] = ok
            st.ligatures = kept

    # 2. Subset: letras, dígitos, sublinhado, espaço e os glifos dos ícones.
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.hinting = False
    opts.notdef_outline = True
    opts.name_IDs = ["*"]
    opts.glyph_names = True
    opts.drop_tables += ["prep", "gasp"]
    sub = subset.Subsetter(opts)
    sub.populate(text="abcdefghijklmnopqrstuvwxyz0123456789_ ", glyphs=sorted(keep_glyphs))
    sub.subset(full)

    # 3. GRAD fixo em 0; FILL, wght e opsz continuam variáveis.
    full = instancer.instantiateVariableFont(full, {"GRAD": 0})
    rename(full, SYMBOLS_FAMILY)
    full.save(out)

    # 4. Confere a gerada: mesmo glifo, um só, para cada nome.
    got = TTFont(out)
    gorder = got.getGlyphOrder()
    miss = []
    for n in names:
        gids = shape(out, n)
        if len(gids) != 1 or gids[0] == 0 or gorder[gids[0]] != want[n]:
            miss.append(n)
    if miss:
        sys.exit("a fonte gerada não resolve: " + ", ".join(miss))
    axes = [a.axisTag for a in got["fvar"].axes]
    print("symbols: %d ícones, %d glifos, eixos %s -> %s" % (len(names), len(gorder), "/".join(axes), out))


def inter(src, out):
    import io
    font = TTFont(src)
    font = instancer.instantiateVariableFont(font, {"opsz": 14})
    # Ida e volta pelo binário: o gvar do instancer em memória não casa com o subset.
    buf = io.BytesIO()
    font.save(buf)
    buf.seek(0)
    font = TTFont(buf)
    unicodes = set(INTER_SINGLES)
    for a, b in INTER_RANGES:
        unicodes.update(range(a, b + 1))
    opts = subset.Options()
    opts.layout_features = INTER_FEATURES
    opts.hinting = False
    opts.notdef_outline = True
    opts.name_IDs = ["*"]
    opts.glyph_names = False
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=sorted(unicodes))
    sub.subset(font)
    rename(font, INTER_FAMILY)
    font.save(out)
    got = TTFont(out)
    axes = [a.axisTag for a in got["fvar"].axes]
    feats = sorted({fr.FeatureTag for fr in got["GSUB"].table.FeatureList.FeatureRecord}
                   | {fr.FeatureTag for fr in got["GPOS"].table.FeatureList.FeatureRecord})
    print("inter: %d glifos, eixos %s, features %s -> %s" % (len(got.getGlyphOrder()), "/".join(axes), ",".join(feats), out))


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "symbols":
        symbols(sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) == 4 and sys.argv[1] == "inter":
        inter(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__ or "uso: subset.py symbols <src> <icons.txt> <out> | inter <src> <out>")
