# Portão dos catálogos da Ilha 2.0.
#
#   uv run --no-project --with fonttools python -I dev/i18ncheck.py [raiz do repo] [locales.json]
#   (locales.json padrão: $OMARCHY_PATH/default/i18n/locales.json)
#
# Confere:
# 1. Um catálogo por código do locales.json do Omarchy (50), JSON válido, plano.
# 2. Paridade de chaves com en.json: 0 faltando, 0 sobrando.
# 3. Paridade de %N (o mesmo conjunto de %1, %2… que o inglês).
# 4. Plurais: objeto com as categorias CLDR do idioma (porte do Plural.js do
#    Omarchy), cada forma com os mesmos %N; texto simples só onde o inglês é simples.
# 5. Regras da casa: ilha.title é "Ilha"; "·" aparece quando aparece no inglês.
# 6. Cobertura de glifos: todo caractere de um catálogo de escrita não
#    complexa existe em fonts/InterIlha2.ttf (as escritas complexas caem no
#    fontconfig). Sem fontTools, este passo é pulado com aviso.
# Sai com 1 se algo falha. `--seeded-only` não exige tradução (placeholders
# iguais ao inglês são permitidos sempre; isto só lista quantos faltam traduzir).
import json
import os
import re
import sys

repo = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
locales_path = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else os.path.join(
    os.environ.get("OMARCHY_PATH", os.path.expanduser("~/.local/share/omarchy")), "default", "i18n", "locales.json")

COMPLEX = {"ar", "fa", "ur", "he", "hi", "bn", "si", "ta", "th", "ja", "ko", "zh-CN", "zh-TW"}
ORDER = ["zero", "one", "two", "few", "many", "other"]


def within(v, lo, hi):
    return lo <= v <= hi


def category(code, count):
    n = abs(int(count))
    n10, n100 = n % 10, n % 100
    millions = n != 0 and n % 1000000 == 0
    if code in ("ja", "ko", "zh-CN", "zh-TW", "th", "vi", "id", "ms"):
        return "other"
    if code in ("hi", "bn", "fa", "si"):
        return "one" if n <= 1 else "other"
    if code in ("fr", "pt-BR"):
        return "one" if n <= 1 else ("many" if millions else "other")
    if code in ("ca", "es-MX", "it", "pt"):
        return "one" if n == 1 else ("many" if millions else "other")
    if code == "fil":
        return "other" if n10 in (4, 6, 9) else "one"
    if code == "is":
        return "one" if n10 == 1 and n100 != 11 else "other"
    if code in ("cs", "sk"):
        return "one" if n == 1 else ("few" if within(n, 2, 4) else "other")
    if code == "pl":
        if n == 1:
            return "one"
        return "few" if within(n10, 2, 4) and not within(n100, 12, 14) else "many"
    if code in ("ru", "uk"):
        if n10 == 1 and n100 != 11:
            return "one"
        return "few" if within(n10, 2, 4) and not within(n100, 12, 14) else "many"
    if code in ("hr", "sr"):
        if n10 == 1 and n100 != 11:
            return "one"
        return "few" if within(n10, 2, 4) and not within(n100, 12, 14) else "other"
    if code == "sl":
        if n100 == 1:
            return "one"
        if n100 == 2:
            return "two"
        return "few" if within(n100, 3, 4) else "other"
    if code == "lt":
        if within(n100, 11, 19):
            return "other"
        return "one" if n10 == 1 else ("few" if n10 >= 2 else "other")
    if code == "lv":
        if n10 == 0 or within(n100, 11, 19):
            return "zero"
        return "one" if n10 == 1 else "other"
    if code == "ro":
        if n == 1:
            return "one"
        return "few" if n == 0 or within(n100, 1, 19) else "other"
    if code == "ar":
        if n <= 2:
            return ["zero", "one", "two"][n]
        return "few" if within(n100, 3, 10) else ("many" if within(n100, 11, 99) else "other")
    if code == "he":
        return "one" if n == 1 else ("two" if n == 2 else "other")
    if code == "ga":
        if n <= 2:
            return "other" if n == 0 else ("one" if n == 1 else "two")
        return "few" if within(n, 3, 6) else ("many" if within(n, 7, 10) else "other")
    return "one" if n == 1 else "other"


def categories(code):
    seen = {"other"}
    for n in range(0, 1001):
        seen.add(category(code, n))
    seen.add(category(code, 1000000))
    return [c for c in ORDER if c in seen]


def holes(s):
    return sorted(set(re.findall(r"%\d", s)))


def main():
    i18n = os.path.join(repo, "i18n")
    codes = sorted(json.load(open(locales_path, encoding="utf-8")).keys())
    bad = []
    cats = {}
    try:
        en = json.load(open(os.path.join(i18n, "en.json"), encoding="utf-8"))
    except Exception as e:
        sys.exit("en.json: %s" % e)
    present = sorted(f[:-5] for f in os.listdir(i18n) if f.endswith(".json"))
    for c in codes:
        if c not in present:
            bad.append("%s.json: faltando" % c)
    for p in present:
        if p not in codes:
            bad.append("%s.json: código fora do locales.json" % p)

    chars = {}
    untranslated = {}
    for code in codes:
        path = os.path.join(i18n, code + ".json")
        if not os.path.isfile(path):
            continue
        try:
            cat = json.load(open(path, encoding="utf-8"))
        except Exception as e:
            bad.append("%s.json: JSON inválido: %s" % (code, e))
            continue
        if not isinstance(cat, dict):
            bad.append("%s.json: não é um objeto" % code)
            continue
        cats[code] = cat
        miss = [k for k in en if k not in cat]
        extra = [k for k in cat if k not in en]
        if miss:
            bad.append("%s.json: %d faltando: %s" % (code, len(miss), ", ".join(miss[:8])))
        if extra:
            bad.append("%s.json: %d sobrando: %s" % (code, len(extra), ", ".join(extra[:8])))
        need = categories(code)
        same = 0
        text = []
        for k, ev in en.items():
            if k not in cat:
                continue
            v = cat[k]
            if code != "en" and v == ev:
                same += 1
            if isinstance(ev, dict):
                if not isinstance(v, dict):
                    bad.append("%s.json: %s precisa ser plural (objeto)" % (code, k))
                    continue
                lacking = [c for c in need if c not in v]
                if lacking:
                    bad.append("%s.json: %s sem as formas %s" % (code, k, ",".join(lacking)))
                for form, s in v.items():
                    if form not in ORDER:
                        bad.append("%s.json: %s forma desconhecida '%s'" % (code, k, form))
                    elif not isinstance(s, str) or s == "":
                        bad.append("%s.json: %s.%s vazio" % (code, k, form))
                    elif holes(s) != holes(ev.get("other", "")):
                        bad.append("%s.json: %s.%s %%N %s ≠ %s" % (code, k, form, holes(s), holes(ev.get("other", ""))))
                    else:
                        text.append(s)
            else:
                if not isinstance(v, str) or v == "":
                    bad.append("%s.json: %s precisa ser texto não vazio" % (code, k))
                    continue
                if holes(v) != holes(ev):
                    bad.append("%s.json: %s %%N %s ≠ %s" % (code, k, holes(v), holes(ev)))
                if "·" in ev and "·" not in v:
                    bad.append("%s.json: %s perdeu o separador ·" % (code, k))
                text.append(v)
        if cat.get("ilha.title") != "Ilha":
            bad.append("%s.json: ilha.title precisa ser \"Ilha\"" % code)
        untranslated[code] = same
        if code not in COMPLEX:
            chars[code] = set("".join(text))

    # Cobertura da Inter Ilha2.
    font = os.path.join(repo, "fonts", "InterIlha2.ttf")
    try:
        from fontTools.ttLib import TTFont
        cmap = set(TTFont(font, lazy=True).getBestCmap().keys())
        for code, cs in sorted(chars.items()):
            missing = sorted(ch for ch in cs if ord(ch) > 0x20 and ord(ch) not in cmap)
            if missing:
                bad.append("%s.json: a Inter Ilha2 não cobre %s" % (code, " ".join("U+%04X(%s)" % (ord(c), c) for c in missing[:12])))
        cover = "cobertura da Inter conferida em %d catálogos" % len(chars)
    except ImportError:
        cover = "AVISO: sem fontTools, cobertura de glifos não conferida"

    print("i18ncheck: %d catálogos, %d chaves em en.json; %s" % (len(cats), len(en), cover))
    todo = {c: n for c, n in untranslated.items() if c != "en" and n > 0}
    if todo:
        print("i18ncheck: iguais ao inglês (a traduzir): " + ", ".join("%s %d" % (c, n) for c, n in sorted(todo.items())))
    if bad:
        print("i18ncheck: %d problemas:" % len(bad))
        for b in bad[:200]:
            print("  " + b)
        sys.exit(1)
    print("i18ncheck: 0 faltando, 0 sobrando, 0 placeholders divergentes")


if __name__ == "__main__":
    main()
