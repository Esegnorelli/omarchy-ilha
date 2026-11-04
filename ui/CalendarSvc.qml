import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Serviço da tela de Calendário (só ela o instancia, dentro da tela): a lista
// de lembretes, os relógios de outros fusos e as strings que o Omarchy já
// traduz fora do shell.json. Dono: agente do Calendário.
//
// - Lembretes: `omarchy-reminder show --json`, o mesmo que o StatusSvc lê
//   (que só expõe o próximo e a contagem). Lido em refresh() (opened() da
//   tela) e de novo quando a contagem ou o próximo do island.status mudam
//   com a tela aberta (o Omarchy chama omarchy.indicators refresh ao criar e
//   ao disparar um lembrete). Nada roda com a tela fechada.
// - Outros fusos: as cidades do painel "elsewhen" do Omarchy (entrada
//   omarchy.elsewhen no barConfig.layout, `cities` ou o antigo `zones`).
//   Sem Intl no QML: um `date` por fuso dá o deslocamento (como o próprio
//   elsewhen faz), relido a cada refresh(); a hora anda com island.now.
//   A cidade do fuso local (/etc/localtime) fica de fora.
// - Strings: cli.json (reminder.*) e keybindings.json ("Set reminder") do
//   idioma do Omarchy, com o inglês por baixo. Só lidos a partir do primeiro
//   refresh().
// - Relógio do Omarchy: a entrada omarchy.clock do barConfig.layout (em
//   qualquer seção) dá weekStartDay, birthYear e lifeExpectancy; sem ela,
//   os padrões do Model.js (a semana do idioma, sem barra da vida, 90 anos).
//   As contas (grade de 6 semanas em UTC, semana ISO, barra do ano e da
//   vida) são as do Model.js, portadas aqui. Só leitura: a Ilha não grava
//   a configuração do relógio.
// - Harness (ILHA_DEV=1): tudo aqui é leitura. ILHA_DEV_REMINDERS (JSON no
//   formato do `show --json`) troca a lista real por uma de teste.
QtObject {
    id: root

    // ---- Entradas ----
    property var island: null
    // Entre opened() e closed() da tela.
    property bool live: false

    readonly property bool dev: Quickshell.env("ILHA_DEV") === "1"
    readonly property string omarchyPath: root.island && root.island.omarchyPath ? String(root.island.omarchyPath) : (Quickshell.env("OMARCHY_PATH") || "")

    // ---- Lembretes ----
    // [{key, at (época em s), minutes, message, label}], do mais próximo ao mais distante.
    property var reminders: []
    property bool remindersLoaded: false

    // ---- Outros fusos ----
    // [{label, id, offset (min a leste do UTC; null até a sonda responder)}],
    // sem a cidade do fuso local.
    readonly property var cities: {
        const all = root.parseCities(root.layoutEntry("omarchy.elsewhen"));
        const out = [];
        for (let i = 0; i < all.length; i++) {
            if (all[i].id === priv.localZone)
                continue;
            const off = priv.offsets[all[i].id];
            out.push({ label: all[i].label, id: all[i].id, offset: off === undefined ? null : off });
        }
        return out;
    }

    // ---- Configuração do relógio do Omarchy (entrada omarchy.clock) ----
    readonly property var clockEntry: root.layoutEntry("omarchy.clock")

    // Primeiro dia da semana (0 = domingo): weekStartDay da entrada; sem
    // ela (ou com lixo), o do idioma; sem esse, segunda (normalizedWeekStart).
    function weekStart(localeFirst) {
        const set = root.coerceWeekStart(root.clockEntry ? root.clockEntry.weekStartDay : null);
        if (set !== null)
            return set;
        const loc = root.coerceWeekStart(localeFirst);
        return loc === null ? 1 : loc;
    }

    // Ano de nascimento válido (0 = sem, e a barra da vida some) e a
    // expectativa (padrão 90), como o Model.js do relógio.
    function birthYear(currentYear) {
        return root.parseBirthYear(root.clockEntry ? root.clockEntry.birthYear : 0, currentYear);
    }
    function lifeExpectancy() {
        return root.parseLifeExpectancy(root.clockEntry ? root.clockEntry.lifeExpectancy : 0);
    }

    // ---- Contas do calendário (portadas do Model.js do relógio do Omarchy) ----
    readonly property real msPerDay: 86400000
    readonly property int defaultLifeExpectancy: 90

    function pad2(n) {
        return (n < 10 ? "0" : "") + n;
    }
    // "yyyy-MM-dd" de um dia civil (mês de 0 a 11).
    function dateKey(y, m, d) {
        return y + "-" + root.pad2(Number(m) + 1) + "-" + root.pad2(d);
    }
    function keyForDate(date) {
        return root.dateKey(date.getFullYear(), date.getMonth(), date.getDate());
    }
    // Semana ISO 8601: a semana dona da quinta-feira da semana (segunda a domingo) da data.
    function isoWeek(y, m, d) {
        const date = new Date(Date.UTC(y, m, d));
        const weekday = date.getUTCDay() || 7;
        date.setUTCDate(date.getUTCDate() + 4 - weekday);
        const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
        return Math.ceil(((date.getTime() - yearStart.getTime()) / root.msPerDay + 1) / 7);
    }
    function dayOfYear(y, m, d) {
        return Math.round((Date.UTC(y, m, d) - Date.UTC(y, 0, 1)) / root.msPerDay) + 1;
    }
    // Dias inteiros já vividos sobre os dias do ano: 1º de janeiro é 0 %, 31 de dezembro 100 %.
    function yearProgress(y, m, d) {
        const total = root.dayOfYear(y, 11, 31);
        return total > 0 ? Math.max(0, Math.min(1, (root.dayOfYear(y, m, d) - 1) / total)) : 0;
    }
    function parseBirthYear(value, currentYear) {
        const now = Math.round(Number(currentYear));
        if (!isFinite(now))
            return 0;
        const text = String(value === undefined || value === null ? "" : value).trim();
        if (!/^\d{4}$/.test(text))
            return 0;
        const year = parseInt(text, 10);
        return !isFinite(year) || year > now || year < now - 120 ? 0 : year;
    }
    function parseLifeExpectancy(value) {
        const text = String(value === undefined || value === null ? "" : value).trim();
        if (!/^\d+$/.test(text))
            return root.defaultLifeExpectancy;
        const years = parseInt(text, 10);
        return !isFinite(years) || years <= 0 || years > 150 ? root.defaultLifeExpectancy : years;
    }
    // Anos inteiros, como se diz a idade: quem nasceu em 1984 tem 42 o ano todo de 2026.
    function lifeProgress(born, currentYear, expectancy) {
        const b = root.parseBirthYear(born, currentYear);
        if (b <= 0)
            return 0;
        const age = Math.round(Number(currentYear)) - b;
        const span = root.parseLifeExpectancy(expectancy);
        return age > 0 && age <= 120 && span > 0 ? Math.max(0, Math.min(1, age / span)) : 0;
    }

    // Sempre 6 semanas de 7 dias, andando em UTC (todo dia tem 24 h; uma
    // meia-noite que não existe no horário de verão não repete um dia).
    // Cada linha leva a semana ISO da sua quinta-feira.
    function monthGrid(year, month, weekStart, todayKey) {
        const start = ((Number(weekStart) % 7) + 7) % 7;
        const leading = (new Date(Date.UTC(year, month, 1)).getUTCDay() - start + 7) % 7;
        const cursor = new Date(Date.UTC(year, month, 1 - leading));
        const weeks = [];
        for (let w = 0; w < 6; w++) {
            const days = [];
            let thursday = null;
            for (let d = 0; d < 7; d++) {
                const cy = cursor.getUTCFullYear(), cm = cursor.getUTCMonth(), cd = cursor.getUTCDate(), wd = cursor.getUTCDay();
                const key = root.dateKey(cy, cm, cd);
                if (wd === 4)
                    thursday = { year: cy, month: cm, day: cd };
                days.push({ key: key, year: cy, month: cm, day: cd, weekday: wd, inMonth: cm === month && cy === year, weekend: wd === 0 || wd === 6, today: key === todayKey });
                cursor.setUTCDate(cursor.getUTCDate() + 1);
            }
            const anchor = thursday || days[0];
            weeks.push({ week: root.isoWeek(anchor.year, anchor.month, anchor.day), days: days });
        }
        return weeks;
    }

    // Mês somado em UTC (o 1º de um mês sem meia-noite local não cai no mês errado).
    function stepMonth(year, month, delta) {
        const t = new Date(Date.UTC(year, Number(month) + Number(delta), 1));
        return { year: t.getUTCFullYear(), month: t.getUTCMonth() };
    }
    function daysInMonth(year, month) {
        return new Date(Date.UTC(year, Number(month) + 1, 0)).getUTCDate();
    }

    // ---- Strings do Omarchy fora do shell.json ----
    // cli.json: reminder.upcoming, reminder.none, reminder.minuteLabel, reminder.setTooltip…
    function tc(key, fallback) {
        return root.pick(priv.cliLang, priv.cliEn, key, fallback);
    }
    // keybindings.json: a chave é o próprio texto em inglês.
    function tk(key) {
        return root.pick(priv.keysLang, priv.keysEn, key, key);
    }

    // Lê tudo de novo (opened()).
    function refresh() {
        priv.primed = true;
        root.readReminders();
        root.probeZones();
    }

    function readReminders() {
        const fake = root.dev ? (Quickshell.env("ILHA_DEV_REMINDERS") || "") : "";
        if (fake !== "") {
            root.applyReminders(fake);
            return;
        }
        if (reminderProc.running) {
            reminderProc.again = true;
            return;
        }
        reminderProc.running = true;
    }

    function probeZones() {
        const ids = root.parseCities(root.layoutEntry("omarchy.elsewhen")).map(c => c.id);
        if (ids.length === 0)
            return;
        if (zoneProc.running) {
            zoneProc.again = true;
            return;
        }
        // Os fusos vão como argumentos, nunca como texto do script.
        zoneProc.command = ["sh", "-c", "l=$(readlink /etc/localtime 2>/dev/null); printf 'LOCAL|%s\\n' \"${l#*zoneinfo/}\"; for z in \"$@\"; do TZ=\"$z\" date \"+$z|%z\"; done", "sh"].concat(ids);
        zoneProc.running = true;
    }

    // ---- Leitura ----

    function applyReminders(raw) {
        const text = String(raw || "");
        const a = text.indexOf("{"), b = text.lastIndexOf("}");
        let data = null;
        if (a >= 0 && b > a) {
            try {
                data = JSON.parse(text.slice(a, b + 1));
            } catch (e) {
                data = null;
            }
        }
        const list = data && Array.isArray(data.reminders) ? data.reminders : [];
        const out = [];
        for (let i = 0; i < list.length; i++) {
            const r = list[i] || {};
            const at = Number(r.at);
            if (!isFinite(at) || at <= 0)
                continue;
            const minutes = Math.max(0, Math.floor(Number(r.minutes) || 0));
            const message = root.oneLine(r.message, 120);
            out.push({
                key: String(r.unit || r.timer || ("r" + i)),
                at: at,
                minutes: minutes,
                message: message,
                label: message !== "" ? message : root.oneLine(r.label, 120)
            });
        }
        out.sort((x, y) => x.at - y.at);
        root.reminders = out;
        root.remindersLoaded = true;
    }

    function oneLine(s, max) {
        const t = String(s === undefined || s === null ? "" : s).replace(/\s+/g, " ").trim();
        return t.length > max ? t.slice(0, max - 1) + "…" : t;
    }

    // A entrada de um plugin no layout do barConfig (null sem ela).
    function layoutEntry(id) {
        const cfg = root.island ? root.island.barConfig : null;
        const layout = cfg && typeof cfg === "object" ? cfg.layout : null;
        if (!layout || typeof layout !== "object")
            return null;
        for (const section in layout) {
            const list = layout[section];
            if (!Array.isArray(list))
                continue;
            for (let i = 0; i < list.length; i++) {
                const e = list[i];
                if (e && typeof e === "object" && e.id === id)
                    return e;
            }
        }
        return null;
    }

    // `cities` [{name, zone}] ou o antigo "Rótulo|Fuso, Rótulo|Fuso" em `zones`
    // (Model.parseCities do elsewhen) -> [{label, id}].
    function parseCities(entry) {
        if (!entry)
            return [];
        const valid = /^[A-Za-z0-9_+\-\/]+$/;
        const labelFor = id => String(id).split("/").pop().replace(/_/g, " ");
        const out = [];
        if (Array.isArray(entry.cities) && entry.cities.length > 0) {
            for (let i = 0; i < entry.cities.length; i++) {
                const c = entry.cities[i];
                const id = c && typeof c === "object" ? String(c.zone || "").trim() : "";
                if (id === "" || !valid.test(id))
                    continue;
                const name = String(c.name || "").replace(/[,|]/g, " ").replace(/\s+/g, " ").trim();
                out.push({ label: name !== "" ? name : labelFor(id), id: id });
            }
            return out;
        }
        const parts = String(entry.zones || "").split(",");
        for (let i = 0; i < parts.length; i++) {
            const p = parts[i].trim();
            if (p === "")
                continue;
            const f = p.split("|");
            const id = (f.length >= 2 ? f[1] : f[0]).trim();
            if (id === "" || !valid.test(id))
                continue;
            const label = f.length >= 2 ? f[0].trim() : "";
            out.push({ label: label !== "" ? label : labelFor(id), id: id });
        }
        return out;
    }

    // "monday", "mon", 1, "1" -> 1; o resto -> null (Model.coerceWeekStart do relógio).
    function coerceWeekStart(value) {
        if (value === undefined || value === null)
            return null;
        if (typeof value === "number")
            return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null;
        const text = String(value).trim().toLowerCase();
        if (text === "")
            return null;
        const names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
        for (let i = 0; i < names.length; i++) {
            if (names[i] === text || names[i].substr(0, 3) === text)
                return i;
        }
        const n = parseInt(text, 10);
        return isFinite(n) ? ((n % 7) + 7) % 7 : null;
    }

    function parseCatalog(raw) {
        try {
            const p = JSON.parse(raw || "{}");
            return p && typeof p === "object" && !Array.isArray(p) ? p : ({});
        } catch (e) {
            return ({});
        }
    }

    function pick(lang, en, key, fallback) {
        let v = lang[key];
        if (v && typeof v === "object")
            v = v.other;
        if (typeof v === "string" && v.length > 0)
            return v;
        v = en[key];
        if (v && typeof v === "object")
            v = v.other;
        if (typeof v === "string" && v.length > 0)
            return v;
        return fallback !== undefined ? fallback : key;
    }

    // ---- Estado interno ----
    readonly property QtObject _priv: QtObject {
        id: priv
        property bool primed: false
        property string localZone: ""
        // fuso -> minutos a leste do UTC
        property var offsets: ({})

        readonly property string i18nDir: root.omarchyPath !== "" ? root.omarchyPath + "/default/i18n/" : ""
        readonly property var cliEn: root.parseCatalog(cliEnFile.text())
        readonly property var cliLang: root.parseCatalog(cliLangFile.text())
        readonly property var keysEn: root.parseCatalog(keysEnFile.text())
        readonly property var keysLang: root.parseCatalog(keysLangFile.text())
    }

    readonly property FileView _cliEnFile: FileView {
        id: cliEnFile
        path: priv.primed && priv.i18nDir !== "" ? priv.i18nDir + "en/cli.json" : ""
        blockLoading: true
        printErrors: false
    }
    readonly property FileView _cliLangFile: FileView {
        id: cliLangFile
        path: priv.primed && priv.i18nDir !== "" && Commons.I18n.language !== "en" ? priv.i18nDir + Commons.I18n.language + "/cli.json" : ""
        blockLoading: true
        printErrors: false
    }
    readonly property FileView _keysEnFile: FileView {
        id: keysEnFile
        path: priv.primed && priv.i18nDir !== "" ? priv.i18nDir + "en/keybindings.json" : ""
        blockLoading: true
        printErrors: false
    }
    readonly property FileView _keysLangFile: FileView {
        id: keysLangFile
        path: priv.primed && priv.i18nDir !== "" && Commons.I18n.language !== "en" ? priv.i18nDir + Commons.I18n.language + "/keybindings.json" : ""
        blockLoading: true
        printErrors: false
    }

    readonly property Process _reminderProc: Process {
        id: reminderProc
        property bool again: false
        command: ["omarchy-reminder", "show", "--json"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyReminders(text)
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.reminders = [];
                root.remindersLoaded = true;
            }
            if (reminderProc.again) {
                reminderProc.again = false;
                if (root.live)
                    reminderProc.running = true;
            }
        }
    }

    readonly property Process _zoneProc: Process {
        id: zoneProc
        property bool again: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const lines = String(text || "").split("\n");
                const map = {};
                let local = "";
                for (let i = 0; i < lines.length; i++) {
                    const f = lines[i].split("|");
                    if (f.length < 2)
                        continue;
                    const id = f[0].trim();
                    if (id === "LOCAL") {
                        local = f[1].trim();
                        continue;
                    }
                    const m = /^([+-])(\d{2})(\d{2})$/.exec(f[1].trim());
                    if (id === "" || !m)
                        continue;
                    const mins = parseInt(m[2], 10) * 60 + parseInt(m[3], 10);
                    map[id] = m[1] === "-" ? -mins : mins;
                }
                priv.localZone = local;
                priv.offsets = map;
            }
        }
        onExited: (code, status) => {
            if (zoneProc.again) {
                zoneProc.again = false;
                if (root.live)
                    root.probeZones();
            }
        }
    }

    // Com a tela aberta: um lembrete criado ou disparado muda a contagem ou o próximo.
    readonly property Connections _statusWatch: Connections {
        target: root.live && root.island ? root.island.status : null
        ignoreUnknownSignals: true
        function onReminderCountChanged() {
            root.readReminders();
        }
        function onNextReminderAtChanged() {
            root.readReminders();
        }
    }
}
