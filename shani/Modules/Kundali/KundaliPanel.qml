// Kundali: a birth chart and the day's panchang, offline (bridge/kundali.py
// over bridge/astronomy.py and bridge/kundali_engine.py). The page follows
// docs/DESIGN.md: when and where in one card, picked by click (a place's own
// time zone, summer time and all); then the drawn chart (D1 / D9), the
// planets, the Vimshottari periods, the chart's sections, and every other
// calculation the engine has, by group.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services as Services
import qs.Modules.Kundali

AppWindow {
    id: win
    appName: "Kundali"
    visible: Ui.kundali
    onGone: Ui.kundali = false
    margins: 0
    implicitWidth: Theme.px(980)
    implicitHeight: Theme.px(940)

    // ---- what the person chose ---------------------------------------------
    property string mode: "kundali"         // kundali (a birth) or panchang (a day)
    property string dateInput: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property string timeInput: "12:00"
    // the place: a searched place carries its own zone; "" is this computer's
    property var place: ({ name: "", region: "", country: "", lat: Services.Location.lat || 0,
                           lon: Services.Location.lon || 0, timezone: "" })
    property bool placeOpen: false
    property bool exactOpen: false

    // ---- what came back ------------------------------------------------------
    property var chart: null                // the birth chart (planets, houses, dasha, navamsa)
    property var day: null                  // the panchang
    property var times: null                // the day's rise/set, ends, muhurtas and hours
    property string error: ""
    property bool loading: false
    property string varga: "D1"
    property string section: "chart"        // the chart's sections (data, drawn below)
    property string sectionText: ""
    property var sectionData: null
    property bool editing: true            // the birth form; folds into one line once a chart is made
    property string chartStyle: "north"     // north | south
    readonly property var vargaNames: ({
        D1: Tr.t("Rashi: the birth chart"), D2: Tr.t("Hora: wealth"), D3: Tr.t("Drekkana: siblings"),
        D4: Tr.t("Chaturthamsha: home and fortune"), D7: Tr.t("Saptamsha: children"), D9: Tr.t("Navamsha: marriage and dharma"),
        D10: Tr.t("Dashamsha: career"), D12: Tr.t("Dwadashamsha: parents"), D16: Tr.t("Shodashamsha: vehicles and comforts"),
        D20: Tr.t("Vimshamsha: spiritual life"), D24: Tr.t("Chaturvimshamsha: learning"), D27: Tr.t("Saptavimshamsha: strength"),
        D30: Tr.t("Trimshamsha: misfortune"), D40: Tr.t("Khavedamsha: maternal line"), D45: Tr.t("Akshavedamsha: paternal line"),
        D60: Tr.t("Shashtiamsha: past karma")
    })
    function vargaAscendant() {
        const v = ((win.chart || {}).vargas_all || {})[win.varga];
        return v ? v.ascendant : ((win.chart || {}).ascendant_sign || "");
    }
    function vargaPlanets() {
        const ps = ((win.chart || {}).planets || []).filter(p => ["Uranus", "Neptune", "Pluto"].indexOf(p.name) < 0);
        const v = ((win.chart || {}).vargas_all || {})[win.varga];
        if (!v || win.varga === "D1") return ps;
        return ps.map(p => ({ name: p.name, retrograde: p.retrograde, sign: v.planets[p.name] || "" }));
    }
    property string group: "chart"          // every other calculation, by group
    property string calc: ""
    property string calcText: ""
    property bool calcBusy: false
    property int horaryHouse: 7
    property bool copied: false
    property bool chartCopied: false
    property bool saveOpen: false
    readonly property var birth: ({ date: win.dateInput, time: win.timeInput, lat: Number(win.place.lat), lon: Number(win.place.lon),
                                    zone: win.place.timezone || "", place: win.placeTitle })
    readonly property var savedProfile: Services.KundaliProfiles.profiles.length >= 0 ? Services.KundaliProfiles.find(win.birth) : null
    readonly property bool saved: win.savedProfile !== null
    function openProfile(p) {
        win.mode = "kundali";
        win.dateInput = p.date;
        win.timeInput = p.time || "12:00";
        win.place = { name: p.place || p.name, region: "", country: "", lat: p.lat, lon: p.lon, timezone: p.zone || "" };
        win.calculate();
    }

    readonly property var sections: [
        ["chart", Tr.t("Chart")],
        ["dasha", Tr.t("Dasha periods")],
        ["ashtakavarga", Tr.t("Ashtakavarga")],
        ["dignity", Tr.t("Planetary dignity")],
        ["aspects", Tr.t("Aspects")],
        ["nakshatra", Tr.t("Nakshatra details")],
        ["eclipse", Tr.t("Eclipses")]
    ]
    // bridge/kundali_engine.py ACTION_GROUPS: the keys are the engine's
    readonly property var groups: [
        { id: "chart", label: Tr.t("Chart"), calcs: ["fullchart", "bhava", "drishti", "aspects", "nakshatra", "lunarmansion", "nodes"] },
        { id: "dashas", label: Tr.t("Dashas"), calcs: ["yoginidasha", "ashtottaridasha", "charadasha", "timelords"] },
        { id: "strength", label: Tr.t("Strength"), calcs: ["shadbala", "shadbala_full", "vimshopaka", "ashtakavarga", "cheshta", "dignity", "combustion", "grahayuddha"] },
        { id: "points", label: Tr.t("Special points"), calcs: ["arudha", "upagrahas", "upagrahas_full", "charakarakas", "karakas_full", "arabicparts", "arabicparts_full", "fixedstars"] },
        { id: "yogas", label: Tr.t("Yogas"), calcs: ["yogas", "vishesha", "vishesha_yogas"] },
        { id: "timing", label: Tr.t("Timing"), calcs: ["gochara", "muhurta", "horary", "fullpanchang", "kalamana"] },
        { id: "sky", label: Tr.t("Sky"), calcs: ["grahana", "eclipse", "meanmotion"] },
        { id: "traditions", label: Tr.t("Other traditions"), calcs: ["bazi", "ziwei", "chinese", "temperament"] }
    ]
    readonly property var calcNames: ({
        fullchart: Tr.t("Full chart"), bhava: Tr.t("Houses (bhava)"), drishti: Tr.t("Vedic aspects (drishti)"),
        aspects: Tr.t("Aspects"), nakshatra: Tr.t("Moon's nakshatra"), lunarmansion: Tr.t("Lunar mansion"),
        nodes: Tr.t("Lunar nodes"), yoginidasha: Tr.t("Yogini dasha"), ashtottaridasha: Tr.t("Ashtottari dasha"),
        charadasha: Tr.t("Chara dasha"), timelords: Tr.t("Time lords"), shadbala: Tr.t("Shadbala"),
        shadbala_full: Tr.t("Shadbala, in full"), vimshopaka: Tr.t("Vimshopaka bala"), ashtakavarga: Tr.t("Ashtakavarga"),
        cheshta: Tr.t("Motion (cheshta)"), dignity: Tr.t("Dignity"), combustion: Tr.t("Combustion"),
        grahayuddha: Tr.t("Planetary war"), arudha: Tr.t("Arudha padas"), upagrahas: Tr.t("Upagrahas"),
        upagrahas_full: Tr.t("Upagrahas, in full"), charakarakas: Tr.t("Chara karakas"), karakas_full: Tr.t("Karakas, in full"),
        arabicparts: Tr.t("Arabic parts"), arabicparts_full: Tr.t("Arabic parts, in full"), fixedstars: Tr.t("Fixed stars"),
        yogas: Tr.t("Yogas"), vishesha: Tr.t("Special yogas"), vishesha_yogas: Tr.t("Special yogas, in full"),
        gochara: Tr.t("Transits (gochara)"), muhurta: Tr.t("Muhurta"), horary: Tr.t("Horary (prashna)"),
        fullpanchang: Tr.t("Full panchang"), kalamana: Tr.t("Kala mana"), grahana: Tr.t("Eclipses (grahana)"),
        eclipse: Tr.t("Eclipse check"), meanmotion: Tr.t("Mean motion"), bazi: Tr.t("Four pillars (BaZi)"),
        ziwei: Tr.t("Zi Wei"), chinese: Tr.t("Chinese calendar"), temperament: Tr.t("Temperament")
    })

    // ---- the birth time as the bridge takes it -----------------------------
    // A searched place: its clock time there, converted with that zone's rules
    // that day ("…@Asia/Kolkata"). This computer's place: its local time.
    function birthArg() {
        const time = win.mode === "panchang" ? "12:00" : (win.timeInput || "12:00");
        if (win.place.timezone)
            return win.dateInput + "T" + time + "@" + win.place.timezone;
        const d = new Date(win.dateInput + "T" + time + ":00");
        return isNaN(d.getTime()) ? win.dateInput + "T" + time + ":00Z" : d.toISOString();
    }
    readonly property string zoneLabel: {
        if (win.place.timezone) return win.place.timezone.replace(/_/g, " ");
        const m = -new Date(win.dateInput + "T" + (win.timeInput || "12:00") + ":00").getTimezoneOffset();
        if (isNaN(m)) return "";
        const h = Math.floor(Math.abs(m) / 60), mi = Math.abs(m) % 60;
        return Tr.t("Local time, %1", "UTC" + (m < 0 ? "−" : "+") + String(h).padStart(2, "0") + ":" + String(mi).padStart(2, "0"));
    }
    readonly property string placeTitle: win.place.name !== "" ? win.place.name
        : (Services.Location.city !== "" ? Services.Location.city : Tr.t("This computer's place"))
    readonly property string placeLine: [win.place.region, win.place.country].filter(s => s).join(", ")
        + (win.place.region || win.place.country ? " · " : "")
        + Number(win.place.lat).toFixed(4) + ", " + Number(win.place.lon).toFixed(4) + " · " + win.zoneLabel

    function clearResult() {
        win.chart = null;
        win.day = null;
        win.times = null;
        win.error = "";
        win.sectionText = "";
        win.calcText = "";
        win.copied = false;
        win.chartCopied = false;
        win.extra = win.nothing;
        win.matchData = null;
    }

    // ---- running the bridge --------------------------------------------------
    readonly property string scriptPath: Quickshell.env("SHANI_KUNDALI_TOOL") || "/usr/lib/shani-shell/kundali.py"
    readonly property string timesTool: Quickshell.env("SHANI_KUNDALI_PANCHANG_TOOL") || "/usr/lib/shani-shell/panchang_times.py"
    function loadTimes() {
        timesProc.command = ["python3", win.timesTool, win.dateInput, String(win.place.lat),
                             String(win.place.lon), win.place.timezone || ""];
        timesProc.running = true;
    }
    function calculate() {
        win.clearResult();
        win.loading = true;
        if (win.mode === "panchang") win.loadTimes();
        main.command = win.mode === "panchang"
            ? ["python3", win.scriptPath, "panchang", win.birthArg(), String(win.place.lat), String(win.place.lon)]
            : ["python3", win.scriptPath, "kundali", win.birthArg(), String(win.place.lat), String(win.place.lon)];
        main.running = true;
    }
    function showSection(id) {
        win.section = id;
        win.sectionText = "";
        win.sectionData = null;
        if (id === "chart" || id === "all" || !win.chart) return;
        if (id === "ahead") { win.loadAhead(); return; }
        if (id === "doshas") { win.loadData(["mangaldosha", "kalasarpa", "sadesati"]); return; }
        if (id === "kp") { win.loadData(["kplords"]); return; }
        if (id === "annual") { win.loadData(["varshaphal"]); return; }
        if (id === "lalkitab") { win.loadData(["lalkitab"]); return; }
        if (id === "match") { win.matchData = null; if (win.partner) win.runMatch(); return; }
        sectionProc.command = ["python3", win.scriptPath, "details", id, win.birthArg(), String(win.place.lat), String(win.place.lon)];
        sectionProc.running = true;
    }
    function runCalc(id) {
        win.calc = id;
        win.calcText = "";
        win.copied = false;
        if (!win.chart) return;
        win.calcBusy = true;
        const args = ["python3", win.scriptPath, "run", id, win.birthArg(), String(win.place.lat), String(win.place.lon)];
        if (id === "horary") args.push(String(win.horaryHouse));
        calcProc.command = args;
        calcProc.running = true;
    }
    readonly property var signsList: ["Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra",
                                      "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"]
    // ---- the engine's data for a tab: doshas, KP, the annual chart, Lal Kitab ----
    property var extra: ({})
    readonly property var nothing: ({})        // an empty answer set (copied on write, never changed in place)
    property var dataQueue: []
    property int annualYear: new Date().getFullYear()
    function loadData(actions) {
        win.dataQueue = actions.slice();
        dataNext();
    }
    function dataNext() {
        if (dataProc.running || win.dataQueue.length === 0) return;
        const a = win.dataQueue[0];
        win.dataQueue = win.dataQueue.slice(1);
        dataProc.action = a;
        dataProc.command = ["python3", win.scriptPath, "data", a, win.birthArg(), String(win.place.lat), String(win.place.lon)]
            .concat(a === "varshaphal" ? [String(win.annualYear)] : []);
        dataProc.running = true;
    }
    // ---- matching: this chart and a saved one --------------------------------
    property var partner: null
    property bool thisIsGroom: true
    property var matchData: null
    function runMatch() {
        if (!win.partner) return;
        win.matchData = null;
        const me = [win.birthArg(), String(win.place.lat), String(win.place.lon)];
        const other = [Services.KundaliProfiles.birthArg(win.partner), String(win.partner.lat), String(win.partner.lon)];
        const pair = win.thisIsGroom ? me.concat(other) : other.concat(me);
        matchProc.command = ["python3", win.scriptPath, "match"].concat(pair);
        matchProc.running = true;
    }
    readonly property var kootaNames: ({ varna: Tr.t("Varna: temperament"), vashya: Tr.t("Vashya: attraction"), tara: Tr.t("Tara: health and fortune"),
        yoni: Tr.t("Yoni: intimacy"), graha_maitri: Tr.t("Graha maitri: friendship of minds"), gana: Tr.t("Gana: nature"),
        bhakoot: Tr.t("Bhakoot: family and finances"), nadi: Tr.t("Nadi: health and children") })

    // the days ahead for the chart on screen (the same forecast the notices use)
    property var ahead: null
    readonly property string forecastTool: Quickshell.env("SHANI_KUNDALI_FORECAST_TOOL") || "/usr/lib/shani-shell/kundali_forecast.py"
    function loadAhead() {
        win.ahead = null;
        aheadProc.command = ["python3", win.forecastTool, win.birthArg(), String(win.place.lat), String(win.place.lon),
                             Qt.formatDate(new Date(), "yyyy-MM-dd"), "14"];
        aheadProc.running = true;
    }
    function choghadiyaRows() {
        const c = (win.times || {}).choghadiya || {};
        return (c.day || []).map(p => Object.assign({ part: Tr.t("Day") }, p))
            .concat((c.night || []).map(p => Object.assign({ part: Tr.t("Night") }, p)));
    }
    function rawMinutes(text) {
        const s = String(text || "0");
        const shift = s.endsWith("+1") ? 1440 : (s.endsWith("-1") ? -1440 : 0);
        const parts = (shift ? s.slice(0, -2) : s).split(":");
        return shift + Number(parts[0]) * 60 + Number(parts[1]);
    }
    function timelineRows() {
        const rows = ((win.times || {}).muhurtas || []).map(p =>
            ({ start: p.start, end: p.end, name: p.name, tone: p.auspicious ? "ok" : "warn" }));
        choghadiyaRows().forEach(p => rows.push({ start: p.start, end: p.end, name: p.name,
            tone: p.nature === "good" ? "ok" : (p.nature === "bad" ? "error" : "neutral") }));
        ((win.times || {}).horas || []).forEach(p => rows.push({ start: p.start, end: p.end,
            name: p.lord, tone: "accent" }));
        return rows;
    }
    readonly property var daySpan: {
        const rows = win.timelineRows();
        if (rows.length === 0) return [0, 1440];
        let lo = Infinity, hi = 0;
        rows.forEach(p => { lo = Math.min(lo, win.rawMinutes(p.start)); hi = Math.max(hi, win.rawMinutes(p.end)); });
        return [Math.max(0, lo - 15), hi + 15];
    }
    // a time after midnight carries +1 in the bridge; say it in plain words
    function clock(text) {
        const s = String(text || "–");
        return s.endsWith("+1") ? s.slice(0, -2) + " · " + Tr.t("next day") : s;
    }
    function stepDay(n) {
        const d = new Date(win.dateInput + "T12:00:00");
        d.setDate(d.getDate() + n);
        win.dateInput = Qt.formatDate(d, "yyyy-MM-dd");
        win.calculate();
    }
    function pickPlace(r) {
        win.place = { name: r.name || "", region: r.region || "", country: r.country || "",
                      lat: Number(r.lat), lon: Number(r.lon), timezone: r.timezone || "" };
        win.placeOpen = false;
        win.clearResult();
    }
    function useThisComputer() {
        win.place = { name: "", region: "", country: "", lat: Services.Location.lat || 0,
                      lon: Services.Location.lon || 0, timezone: "" };
        win.placeOpen = false;
        win.clearResult();
    }
    // the Vimshottari periods as calendar years from the birth
    function dashaRows() {
        const md = ((win.chart || {}).dasha || {}).mahadashas || [];
        const born = new Date(win.dateInput + "T" + (win.timeInput || "12:00") + ":00");
        const year = born.getFullYear() + (born.getMonth() + born.getDate() / 31) / 12;
        const now = new Date().getFullYear() + new Date().getMonth() / 12;
        return md.map(d => ({ lord: d.lord, from: year + d.start_offset, to: year + d.start_offset + d.years,
                              current: now >= year + d.start_offset && now < year + d.start_offset + d.years }));
    }

    // The calendar opens this with a day in mind: the panchang of that day.
    // A script, Chronoa or the tests open it with a birth: that chart.
    onVisibleChanged: {
        if (!visible) return;
        if (Ui.kundaliBirth) {
            const b = Ui.kundaliBirth;
            Ui.kundaliBirth = null;
            win.mode = b.mode === "panchang" ? "panchang" : "kundali";
            win.dateInput = b.date;
            win.timeInput = b.time || "12:00";
            win.place = { name: b.name || "", region: "", country: "", lat: b.lat, lon: b.lon, timezone: b.zone || "" };
            win.calculate();
        } else if (Ui.kundaliDate) {
            win.mode = "panchang";
            win.dateInput = Ui.kundaliDate;
            win.calculate();
        }
    }

    Process {
        id: main
        stdout: StdioCollector {
            onStreamFinished: {
                win.loading = false;
                try {
                    const d = JSON.parse(text);
                    if (d.error) { win.error = d.error; return; }
                    if (win.mode === "panchang") { win.day = d; win.editing = false; }
                    else { win.chart = d; win.editing = false; win.showSection(win.section); if (win.calc) win.runCalc(win.calc); }
                } catch (e) { win.error = Tr.t("The result could not be read"); }
            }
        }
        onExited: code => { if (code !== 0 && win.error === "" && !win.chart && !win.day) { win.loading = false; win.error = Tr.t("The calculation failed — is the Kundali helper installed?"); } }
    }
    Process {
        id: timesProc
        stdout: StdioCollector { onStreamFinished: {
            try { const d = JSON.parse(text); win.times = d.error ? null : d; }
            catch (e) { win.times = null; }
        } }
    }
    Process {
        id: sectionProc
        stdout: StdioCollector { onStreamFinished: {
            try { const d = JSON.parse(text); win.sectionData = d.error ? null : d; win.sectionText = d.error ? Tr.t("Could not compute: %1").arg(d.error) : win.renderSection(d); }
            catch (e) { win.sectionText = Tr.t("The result could not be read"); }
        } }
    }
    Process {
        id: dataProc
        property string action: ""
        stdout: StdioCollector { onStreamFinished: {
            const o = Object.assign({}, win.extra);
            try { o[dataProc.action] = JSON.parse(text); } catch (e) { o[dataProc.action] = { error: Tr.t("The result could not be read") }; }
            win.extra = o;
        } }
        onExited: Qt.callLater(win.dataNext)
    }
    Process {
        id: matchProc
        stdout: StdioCollector { onStreamFinished: { try { win.matchData = JSON.parse(text); } catch (e) { win.matchData = { error: Tr.t("The result could not be read") }; } } }
    }
    Process {
        id: aheadProc
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); win.ahead = d.error ? null : d; } catch (e) { win.ahead = null; } } }
    }
    Process {
        id: calcProc
        stdout: StdioCollector { onStreamFinished: {
            win.calcBusy = false;
            try { const d = JSON.parse(text); win.calcText = d.error ? Tr.t("Could not compute: %1").arg(d.error) : (d.text || ""); }
            catch (e) { win.calcText = Tr.t("The result could not be read"); }
        } }
        onExited: code => { win.calcBusy = false; }
    }

    // A section is data with stable keys; every word here belongs to the UI.
    function renderSection(data) {
        if (win.section === "dasha")
            return (data.periods || []).map(d => d.lord + ": " + Tr.t("%1 years", d.years) + " · " + Tr.t("from year %1", d.start_offset)).join("\n");
        if (win.section === "ashtakavarga")
            return (data.rows || []).map(r => r.sign + ": " + Tr.t("%1 points", r.points)).join("\n");
        if (win.section === "dignity")
            return (data.planets || []).map(p => Tr.t("%1 in %2: %3", p.name, p.sign, p.dignity)).join("\n");
        if (win.section === "aspects")
            return (data.aspects || []).map(a => Tr.t("%1 %2 %3 (orb %4°)", a.planet1, a.aspect, a.planet2, a.orb)).join("\n");
        if (win.section === "nakshatra") {
            const m = data.moon || {};
            return Tr.t("%1, pada %2, lord %3", data.nakshatra, data.pada, data.lord) + "\n"
                 + Tr.t("Moon in %1 %2°%3'", m.sign, m.degree, String(m.minute).padStart(2, "0"));
        }
        let r = Tr.t("Solar eclipse: %1", data.solar_eclipse ? Tr.t("Yes") : Tr.t("No")) + "\n"
              + Tr.t("Lunar eclipse: %1", data.lunar_eclipse ? Tr.t("Yes") : Tr.t("No")) + "\n"
              + Tr.t("Separation: %1°", data.angular_separation);
        if (data.type) r += "\n" + Tr.t("Type: %1", data.type) + " · " + Tr.t("Magnitude: %1", data.magnitude);
        return r;
    }

    // one row of a day's timeline: the width of each span comes from the bar,
    // never from the labels inside it (that would feed back into the layout)
    component PeriodBar: ColumnLayout {
        id: bar
        property string label: ""
        property var periods: []
        Layout.fillWidth: true
        spacing: Theme.space(1)
        Text {
            Layout.fillWidth: true
            text: bar.label
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.type("small")
        }
        Item {
            id: strip
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.px(20)
            Row {
                anchors.fill: parent
                Repeater {
                    model: bar.periods
                    Rectangle {
                        required property var modelData
                        readonly property real length: win.rawMinutes(modelData.end) - win.rawMinutes(modelData.start)
                        width: Math.max(1, strip.width * length / Math.max(1, win.daySpan[1] - win.daySpan[0]))
                        height: strip.height
                        color: Theme.alpha(Theme.toneColor(modelData.tone), 0.55)
                        border.color: Theme.toneColor(modelData.tone)
                        border.width: 1
                        Accessible.role: Accessible.StaticText
                        Accessible.name: (modelData.name || "") + " " + win.clock(modelData.start) + "–" + win.clock(modelData.end)
                        Text {
                            anchors.centerIn: parent
                            visible: parent.width > Theme.px(70)
                            text: modelData.name || ""
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.type("small")
                            elide: Text.ElideRight
                            Accessible.ignored: true
                        }
                    }
                }
            }
        }
    }

    // a block of the engine's text: readable, selectable, copyable
    component ResultText: Rectangle {
        id: rt
        property string text: ""
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + Theme.space(6)
        radius: Theme.radiusSmall
        color: Theme.surface1
        border.width: 1
        border.color: Theme.stroke
        TextEdit {
            id: body
            x: Theme.space(3); y: Theme.space(3)
            width: rt.width - Theme.space(6)
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            text: rt.text
            color: Theme.text
            selectionColor: Theme.accent
            font.family: Theme.mono
            font.pixelSize: Theme.type("small")
            Accessible.role: Accessible.StaticText
            Accessible.name: rt.text
        }
    }

    // the planets' colours in the drawings: one hue each, calm, the same everywhere
    readonly property var planetTint: ({
        Sun: Theme.amber, Moon: Theme.blue, Mars: Theme.danger, Mercury: Theme.success, Jupiter: Theme.amber,
        Venus: Theme.accent, Saturn: Theme.dim, Rahu: Theme.faint, Ketu: Theme.faint
    })
    readonly property var moon: ((win.chart || {}).planets || []).find(p => p.name === "Moon") || {}
    readonly property var dashaNow: (win.chart ? win.dashaRows() : []).find(d => d.current) || null

    AppPage {
        anchors.fill: parent
        title: win.mode === "panchang" ? Tr.t("Panchang") : (win.place.name !== "" && !win.editing && win.chart ? Tr.t("Kundali for %1", win.place.name) : Tr.t("Kundali"))
        subtitle: win.mode === "panchang" ? Tr.t("The day's tithi, nakshatra, yoga and karana, for a place")
                                          : Tr.t("A birth chart, sidereal with Lahiri ayanamsa, worked out on this computer")
        Keys.onEscapePressed: Ui.kundali = false
        actions: [
            SegmentedTabs {
                options: [Tr.t("Birth chart"), Tr.t("Panchang")]
                segmentWidth: Theme.px(110)
                currentIndex: win.mode === "panchang" ? 1 : 0
                onActivated: index => { win.mode = index === 1 ? "panchang" : "kundali"; win.clearResult(); win.editing = true; }
            }
        ]

        // ---- the people saved here --------------------------------------------------
        Card {
            Layout.fillWidth: true
            visible: win.mode === "kundali" && Services.KundaliProfiles.profiles.length > 0 && (win.editing || win.chart === null)
            icon: "system-users"
            title: Tr.t("Saved")
            subtitle: Tr.t("Open one, or turn its notices about the days ahead on or off")
            spacing: 0
            Repeater {
                model: Services.KundaliProfiles.profiles
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "avatar-default"
                    title: modelData.name
                    subtitle: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "d MMM yyyy") + " · " + modelData.time + " · " + modelData.place
                    onClicked: win.openProfile(modelData)
                    IconButton {
                        icon: modelData.alerts ? "notifications" : "notifications-disabled"
                        on: modelData.alerts
                        tip: modelData.alerts ? Tr.t("Notices about the days ahead: on") : Tr.t("Notices about the days ahead: off")
                        onClicked: Services.KundaliProfiles.setAlerts(modelData.id, !modelData.alerts)
                    }
                    ConfirmButton {
                        icon: "user-trash"
                        tip: Tr.t("Remove %1", modelData.name)
                        armedText: Tr.t("Click again to remove %1 from this computer", modelData.name)
                        onConfirmed: Services.KundaliProfiles.remove(modelData.id)
                    }
                }
            }
        }

        // ---- save the chart under a name -------------------------------------------
        Card {
            Layout.fillWidth: true
            visible: win.saveOpen && win.chart !== null
            icon: "document-save"
            title: Tr.t("Save this chart")
            subtitle: Tr.t("Saved charts stay on this computer. You get a notice before a hard day and when a period begins")
            TextField {
                id: saveName
                Layout.fillWidth: true
                label: Tr.t("Whose chart")
                placeholder: Tr.t("Whose chart, e.g. Asha")
                onAccepted: saveBtn.clicked()
            }
            SwitchRow {
                id: saveAlerts
                Layout.fillWidth: true
                text: Tr.t("Notices about the days ahead")
                hint: Tr.t("Hard days (chandrashtama, an unfavourable tara) and periods that begin")
                checked: true
                onToggled: on => checked = on
            }
            RowLayout {
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: win.saveOpen = false }
                Button {
                    id: saveBtn
                    kind: "primary"
                    text: Tr.t("Save")
                    onClicked: {
                        Services.KundaliProfiles.save(Object.assign({}, win.birth, { name: saveName.text.trim() || win.placeTitle, alerts: saveAlerts.checked }));
                        win.saveOpen = false;
                    }
                }
            }
        }

        // ---- the birth, folded into one line once there is a chart --------------
        Card {
            Layout.fillWidth: true
            visible: !win.editing
            icon: "x-office-calendar"
            title: win.mode === "panchang" ? Qt.formatDate(new Date(win.dateInput + "T12:00:00"), "dddd, d MMMM yyyy")
                                           : Qt.formatDate(new Date(win.dateInput + "T12:00:00"), "d MMMM yyyy") + " · " + win.timeInput
            subtitle: win.placeTitle + " · " + win.zoneLabel
            actions: [
                // a day back, a day on: the panchang is read day by day
                IconButton { visible: win.mode === "panchang"; icon: "go-previous"; tip: Tr.t("The day before"); onClicked: win.stepDay(-1) },
                IconButton { visible: win.mode === "panchang"; icon: "go-next"; tip: Tr.t("The day after"); onClicked: win.stepDay(1) },
                // the whole chart as text, for a message or a note (no mouse selection needed)
                Button {
                    visible: win.mode === "kundali" && win.chart !== null && win.error === ""
                    text: win.chartCopied ? Tr.t("Copied") : Tr.t("Copy chart")
                    Accessible.name: win.chartCopied ? Tr.t("Copied") : Tr.t("Copy chart")
                    onClicked: { Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", (win.chart || {}).text || ""]); win.chartCopied = true; }
                },
                Button {
                    visible: win.mode === "kundali" && win.chart !== null
                    kind: win.saved ? "plain" : "primary"
                    text: win.saved ? Tr.t("Saved") : Tr.t("Save")
                    enabled: !win.saved
                    onClicked: win.saveOpen = true
                },
                Button { text: win.mode === "panchang" ? Tr.t("Change day or place") : Tr.t("Edit birth details"); onClicked: win.editing = true }
            ]
        }

        // ---- when and where (the form) ------------------------------------------
        Card {
            Layout.fillWidth: true
            visible: win.editing
            icon: "x-office-calendar"
            title: win.mode === "panchang" ? Tr.t("Which day, and where") : Tr.t("When and where you were born")
            subtitle: Tr.t("Times are read in the place's own time zone, summer time included")

            GridLayout {
                Layout.fillWidth: true
                columns: width > Theme.px(640) && win.mode === "kundali" ? 2 : 1
                columnSpacing: Theme.space(8)
                rowSpacing: Theme.space(4)
                DatePicker {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    label: Tr.t("Date")
                    value: win.dateInput
                    onPicked: date => { win.dateInput = date; win.clearResult(); }
                }
                TimePicker {
                    visible: win.mode === "kundali"
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    label: Tr.t("Time of birth")
                    value: win.timeInput
                    onPicked: time => { win.timeInput = time; win.clearResult(); }
                }
            }

            ListRow {
                Layout.fillWidth: true
                icon: "mark-location"
                title: win.placeTitle
                subtitle: win.placeLine
                onClicked: win.placeOpen = !win.placeOpen
                Button { text: win.placeOpen ? Tr.t("Done") : Tr.t("Change place"); flat: true; onClicked: win.placeOpen = !win.placeOpen }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: win.placeOpen
                spacing: Theme.space(2)
                SearchField {
                    id: placeSearch
                    Layout.fillWidth: true
                    placeholder: Tr.t("Search a town or city")
                    label: Tr.t("Search a town or city")
                    onTextChanged: searchTimer.restart()
                    Timer { id: searchTimer; interval: 450; onTriggered: if (placeSearch.text.trim().length >= 2) Services.Weather.searchCity(placeSearch.text) }
                }
                Text {
                    visible: Services.Weather.searchError !== "" && placeSearch.text !== ""
                    text: Services.Weather.searchError
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                Repeater {
                    model: placeSearch.text.trim().length >= 2 ? Services.Weather.searchResults : []
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        icon: "mark-location"
                        title: modelData.name
                        subtitle: [modelData.region, modelData.country].filter(s => s).join(", ") + (modelData.timezone ? " · " + modelData.timezone.replace(/_/g, " ") : "")
                        onClicked: win.pickPlace(modelData)
                    }
                }
                ListRow {
                    Layout.fillWidth: true
                    icon: "computer"
                    title: Tr.t("This computer's place and time zone")
                    subtitle: Services.Location.city !== "" ? Services.Location.city : Number(Services.Location.lat).toFixed(2) + ", " + Number(Services.Location.lon).toFixed(2)
                    onClicked: win.useThisComputer()
                }
                ListRow {
                    Layout.fillWidth: true
                    icon: "preferences-system"
                    title: Tr.t("Exact coordinates")
                    subtitle: Tr.t("For a village the search does not know")
                    onClicked: win.exactOpen = !win.exactOpen
                }
                RowLayout {
                    visible: win.exactOpen
                    Layout.fillWidth: true
                    spacing: Theme.space(2)
                    TextField {
                        Layout.fillWidth: true
                        label: Tr.t("Latitude")
                        placeholder: Tr.t("Latitude, e.g. 18.5204")
                        text: String(win.place.lat)
                        onAccepted: { const v = parseFloat(text); if (isFinite(v)) { win.place = Object.assign({}, win.place, { lat: v }); win.clearResult(); } }
                    }
                    TextField {
                        Layout.fillWidth: true
                        label: Tr.t("Longitude")
                        placeholder: Tr.t("Longitude, e.g. 73.8567")
                        text: String(win.place.lon)
                        onAccepted: { const v = parseFloat(text); if (isFinite(v)) { win.place = Object.assign({}, win.place, { lon: v }); win.clearResult(); } }
                    }
                }
            }

            Button {
                Layout.fillWidth: true
                kind: "primary"
                busy: win.loading
                text: win.mode === "panchang" ? Tr.t("Show the day") : Tr.t("Make the chart")
                enabled: !win.loading && win.dateInput !== ""
                onClicked: win.calculate()
            }
        }

        InfoBanner {
            Layout.fillWidth: true
            visible: win.error !== ""
            tone: "error"
            title: Tr.t("Could not compute")
            text: win.error
        }

        // ---- the day ------------------------------------------------------------------
        // the Vedic date first, the way a printed panchang heads its page
        Card {
            Layout.fillWidth: true
            visible: win.mode === "panchang" && win.day !== null
            icon: "weather-clear-night"
            tint: Theme.blue
            title: [(win.day || {}).masa, (win.day || {}).paksha, String((win.day || {}).tithi || "").split(" (")[0]].filter(s => s).join(" ")
            subtitle: [(win.day || {}).vikram_year ? Tr.t("Vikram %1", win.day.vikram_year) : "",
                       (win.day || {}).shaka_year ? Tr.t("Shaka %1", win.day.shaka_year) : "",
                       (win.day || {}).ritu ? Tr.t("%1 ritu", win.day.ritu) : "",
                       (win.day || {}).ayana || ""].filter(s => s).join(" · ")
            ListRow {
                Layout.fillWidth: true
                visible: win.times !== null
                interactive: false
                icon: "x-office-calendar"
                title: Tr.t("Amanta %1 · Purnimanta %2", ((win.times || {}).month || {}).amanta || "",
                            ((win.times || {}).month || {}).purnimanta || "")
                subtitle: Tr.t("%1 paksha", ((win.times || {}).month || {}).paksha || "")
            }
            ListRow {
                Layout.fillWidth: true
                visible: win.times !== null
                interactive: false
                icon: "weather-clear-night"
                title: Tr.t("Moon %1% lit · %2", Math.round(((win.times || {}).illumination || {}).percent || 0),
                            ((win.times || {}).illumination || {}).phase || "")
                subtitle: ((win.times || {}).illumination || {}).waxing ? Tr.t("Waxing") : Tr.t("Waning")
            }
        }
        Card {
            Layout.fillWidth: true
            visible: win.mode === "panchang" && win.day !== null
            icon: "view-list-details"
            title: Tr.t("The five limbs")
            subtitle: Qt.formatDate(new Date(win.dateInput + "T12:00:00"), "dddd, d MMMM yyyy") + " · " + win.placeTitle
            spacing: 0
            Repeater {
                model: [
                    { k: Tr.t("Tithi"), v: (win.day || {}).tithi, d: (win.day || {}).paksha ? Tr.t("%1 paksha", win.day.paksha) : "" },
                    { k: Tr.t("Nakshatra"), v: (win.day || {}).nakshatra, d: (win.day || {}).nakshatra_lord ? Tr.t("Lord: %1", win.day.nakshatra_lord) : "" },
                    { k: Tr.t("Yoga"), v: (win.day || {}).yoga, d: "" },
                    { k: Tr.t("Karana"), v: (win.day || {}).karana, d: "" },
                    { k: Tr.t("Vara"), v: (win.day || {}).vara, d: "" }
                ]
                GridLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space(1)
                    Layout.bottomMargin: Theme.space(1)
                    // narrow, the name of the limb sits above its value
                    columns: width < Theme.px(480) ? 1 : 2
                    columnSpacing: Theme.space(4)
                    rowSpacing: 0
                    Text {
                        Layout.preferredWidth: Theme.px(120)
                        text: modelData.k
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("body")
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData.v || "–"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("heading"); font.weight: Font.DemiBold }
                        Text { visible: modelData.d !== ""; text: modelData.d; color: Theme.blue; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                    }
                }
            }
        }

        // ---- the day's times: the same day, read hour by hour --------------------------------
        Card {
            Layout.fillWidth: true
            visible: win.mode === "panchang" && win.times !== null
            icon: "weather-sunset"
            tint: Theme.amber
            title: Tr.t("Sun and Moon")
            subtitle: Tr.t("Rise and set at %1", win.placeTitle)
            TileGrid {
                Layout.fillWidth: true
                minTileWidth: Theme.px(145)
                StatTile { icon: "weather-sun"; label: Tr.t("Sunrise"); tint: Theme.amber
                           value: win.clock(((win.times || {}).sun || {}).sunrise); detail: "" }
                StatTile { icon: "weather-sunset"; label: Tr.t("Sunset"); tint: Theme.amber
                           value: win.clock(((win.times || {}).sun || {}).sunset); detail: Tr.t("Day: %1", ((win.times || {}).sun || {}).day_length || "–") }
                StatTile { icon: "weather-clear-night"; label: Tr.t("Moonrise"); tint: Theme.blue
                           value: win.clock(((win.times || {}).moon || {}).moonrise); detail: "" }
                StatTile { icon: "weather-clear-night"; label: Tr.t("Moonset"); tint: Theme.blue
                           value: win.clock(((win.times || {}).moon || {}).moonset); detail: Tr.t("Night: %1", ((win.times || {}).sun || {}).night_length || "–") }
            }
        }

        Card {
            Layout.fillWidth: true
            visible: win.mode === "panchang" && win.times !== null
            icon: "view-list-details"
            title: Tr.t("When each limb ends")
            subtitle: Tr.t("Tithi, nakshatra, yoga and karana, with what follows")
            spacing: 0
            Repeater {
                model: [
                    { k: Tr.t("Tithi"), v: ((win.times || {}).limbs || {}).tithi },
                    { k: Tr.t("Nakshatra"), v: ((win.times || {}).limbs || {}).nakshatra },
                    { k: Tr.t("Yoga"), v: ((win.times || {}).limbs || {}).yoga },
                    { k: Tr.t("Karana"), v: ((win.times || {}).limbs || {}).karana }
                ]
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    visible: !!modelData.v
                    interactive: false
                    icon: "go-next"
                    title: modelData.k + " · " + ((modelData.v || {}).name || "")
                    subtitle: modelData.v ? Tr.t("Ends %1 · next %2", win.clock(modelData.v.ends_at), modelData.v.next || "–") : ""
                }
            }
        }

        Card {
            Layout.fillWidth: true
            visible: win.mode === "panchang" && win.times !== null
            icon: "chronometer"
            title: Tr.t("Times of the day")
            subtitle: Tr.t("What to avoid, what is good, and the planetary hours")
            spacing: Theme.space(3)
            PeriodBar {
                label: Tr.t("Muhurtas")
                periods: (win.times || {}).muhurtas || []
            }
            PeriodBar {
                label: Tr.t("Choghadiya")
                periods: win.choghadiyaRows()
            }
            PeriodBar {
                label: Tr.t("Planetary hours")
                periods: (win.times || {}).horas || []
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Muhurtas")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("small")
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.space(2)
                Repeater {
                    model: (win.times || {}).muhurtas || []
                    StatusPill {
                        required property var modelData
                        tone: modelData.auspicious ? "ok" : "warn"
                        text: modelData.name + " " + win.clock(modelData.start) + "–" + win.clock(modelData.end)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Choghadiya")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("small")
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.space(2)
                Repeater {
                    model: win.choghadiyaRows()
                    StatusPill {
                        required property var modelData
                        tone: modelData.nature === "good" ? "ok" : (modelData.nature === "bad" ? "error" : "neutral")
                        text: modelData.part + " · " + modelData.name + " " + win.clock(modelData.start) + "–" + win.clock(modelData.end)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Planetary hours")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("small")
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.space(2)
                Repeater {
                    model: (win.times || {}).horas || []
                    StatusPill {
                        required property var modelData
                        tone: "accent"
                        text: modelData.lord + " " + win.clock(modelData.start) + "–" + win.clock(modelData.end)
                    }
                }
            }
        }

        // ---- what to look at: the chart, its sections, every calculation ---------------
        // a row that wraps: every tab stays on screen, a phone's too
        Flow {
            Layout.fillWidth: true
            visible: win.mode === "kundali"
            spacing: Theme.space(2)
            Repeater {
                model: [win.sections[0], ["ahead", Tr.t("Days ahead")], ["doshas", Tr.t("Doshas")], ["match", Tr.t("Match")]]
                       .concat(win.sections.slice(1))
                       .concat([["kp", Tr.t("KP")], ["annual", Tr.t("Annual chart")], ["lalkitab", Tr.t("Lal Kitab")], ["all", Tr.t("Every calculation")]])
                Choice {
                    required property var modelData
                    text: modelData[1]
                    selected: win.section === modelData[0]
                    onClicked: win.showSection(modelData[0])
                }
            }
        }

        // ---- the chart at a glance -----------------------------------------------------
        TileGrid {
            Layout.fillWidth: true
            visible: win.mode === "kundali" && win.chart !== null
            minTileWidth: Theme.px(width < Theme.px(600) ? 140 : 190)
            StatTile {
                icon: "go-up"; label: Tr.t("Rising sign"); tint: Theme.accent
                value: (win.chart || {}).ascendant_sign || ""
                detail: Tr.t("Ascendant at %1°", Math.floor(((win.chart || {}).ascendant || 0) % 30))
            }
            StatTile {
                icon: "weather-clear-night"; label: Tr.t("Moon sign"); tint: Theme.blue
                value: win.moon.sign || ""
                detail: ((win.moon.nakshatra || {}).nakshatra || "") + ((win.moon.nakshatra || {}).pada ? " · " + Tr.t("pada %1", win.moon.nakshatra.pada) : "")
            }
            StatTile {
                icon: "media-playback-start"; label: Tr.t("Period now"); tint: Theme.success
                value: win.dashaNow ? Tr.t("%1 dasha", win.dashaNow.lord) : "–"
                detail: win.dashaNow ? Tr.t("until %1", Math.floor(win.dashaNow.to)) : ""
                progress: win.dashaNow ? (new Date().getFullYear() - win.dashaNow.from) / (win.dashaNow.to - win.dashaNow.from) : -1
            }
            StatTile {
                icon: "starred"; label: Tr.t("Retrograde"); tint: Theme.amber
                value: String(((win.chart || {}).planets || []).filter(p => p.retrograde && p.name !== "Rahu" && p.name !== "Ketu").length)
                detail: ((win.chart || {}).planets || []).filter(p => p.retrograde && p.name !== "Rahu" && p.name !== "Ketu").map(p => p.name).join(", ")
            }
        }

        // ---- doshas: Mangal, Kaal Sarp, Sade Sati -----------------------------------
        GridLayout {
            id: doshaGrid
            Layout.fillWidth: true
            visible: win.section === "doshas" && win.chart !== null
            columns: width > Theme.px(860) ? 3 : 1
            columnSpacing: Theme.space(4)
            rowSpacing: Theme.space(4)
            readonly property var mangal: win.extra.mangaldosha || null
            readonly property var sarpa: win.extra.kalasarpa || null
            readonly property var sati: win.extra.sadesati || null

            Card {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                icon: doshaGrid.mangal && doshaGrid.mangal.effective ? "dialog-warning" : "emblem-ok"
                tint: Theme.toneColor(doshaGrid.mangal && doshaGrid.mangal.effective ? "warn" : "ok")
                title: Tr.t("Mangal dosha")
                subtitle: !doshaGrid.mangal ? Tr.t("Working it out…")
                        : doshaGrid.mangal.effective ? Tr.t("Present: Mars in the %1th from the ascendant", doshaGrid.mangal.mars_house_from_ascendant)
                        : doshaGrid.mangal.present ? Tr.t("Present, but cancelled") : Tr.t("Not present")
                spacing: 0
                Repeater {
                    model: doshaGrid.mangal ? [["ascendant", Tr.t("From the ascendant")], ["moon", Tr.t("From the Moon")], ["venus", Tr.t("From Venus")]] : []
                    ListRow {
                        required property var modelData
                        readonly property var h: ((doshaGrid.mangal || {}).houses || {})[modelData[0]] || {}
                        Layout.fillWidth: true
                        interactive: false
                        icon: h.afflicted ? "dialog-warning" : "emblem-ok"
                        title: modelData[1]
                        subtitle: Tr.t("Mars in the %1th", h.house)
                        trailing: h.afflicted ? Tr.t("afflicted") : ""
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    visible: ((doshaGrid.mangal || {}).cancellations || []).length > 0
                    spacing: Theme.space(1)
                    Repeater {
                        model: (doshaGrid.mangal || {}).cancellations || []
                        StatusPill { required property var modelData; tone: "ok"; text: String(modelData).replace(/_/g, " ") }
                    }
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                icon: doshaGrid.sarpa && doshaGrid.sarpa.present ? "dialog-warning" : "emblem-ok"
                tint: Theme.toneColor(doshaGrid.sarpa && doshaGrid.sarpa.present ? "warn" : "ok")
                title: Tr.t("Kaal Sarp dosha")
                subtitle: !doshaGrid.sarpa ? Tr.t("Working it out…")
                        : doshaGrid.sarpa.present ? Tr.t("Present: %1 Kaal Sarp", doshaGrid.sarpa.type) : Tr.t("Not present: not every planet lies between Rahu and Ketu")
                spacing: 0
                ListRow {
                    Layout.fillWidth: true
                    interactive: false
                    visible: !!doshaGrid.sarpa
                    icon: "starred"
                    title: Tr.t("Rahu in the %1th, Ketu in the %2th", (doshaGrid.sarpa || {}).rahu_house, (doshaGrid.sarpa || {}).ketu_house)
                    subtitle: ((doshaGrid.sarpa || {}).planets_outside || []).length
                              ? Tr.t("Outside the axis: %1", doshaGrid.sarpa.planets_outside.join(", ")) : Tr.t("Every planet between the nodes")
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                icon: doshaGrid.sati && doshaGrid.sati.running ? "dialog-warning" : "x-office-calendar"
                tint: Theme.toneColor(doshaGrid.sati && doshaGrid.sati.running ? "warn" : "info")
                title: Tr.t("Sade Sati")
                subtitle: !doshaGrid.sati ? Tr.t("Working it out…")
                        : doshaGrid.sati.running ? Tr.t("Running: the %1 phase", ({ rising: Tr.t("rising"), peak: Tr.t("peak"), setting: Tr.t("setting") })[doshaGrid.sati.phase_name] || "")
                        : doshaGrid.sati.start ? Tr.t("Next from %1", String(doshaGrid.sati.start).slice(0, 10)) : Tr.t("Not in the coming years")
                spacing: 0
                Repeater {
                    model: (doshaGrid.sati || {}).phases || []
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        interactive: false
                        icon: "x-office-calendar"
                        title: ({ rising: Tr.t("Rising phase"), peak: Tr.t("Peak phase"), setting: Tr.t("Setting phase") })[modelData.name] || modelData.phase
                        subtitle: Qt.formatDate(new Date(modelData.start), "d MMM yyyy") + " – " + Qt.formatDate(new Date(modelData.end), "d MMM yyyy")
                    }
                }
            }
        }

        // ---- matching ------------------------------------------------------------------
        Card {
            Layout.fillWidth: true
            visible: win.section === "match" && win.chart !== null
            icon: "emblem-favorite"
            title: Tr.t("Match with")
            subtitle: Services.KundaliProfiles.profiles.filter(p => !Services.KundaliProfiles.same(p, win.birth)).length
                      ? Tr.t("Pick a saved chart; Ashtakoota guna milan, 36 points")
                      : Tr.t("Save the other person's chart first (make it, then Save); it appears here")
            Flow {
                Layout.fillWidth: true
                spacing: Theme.space(2)
                Repeater {
                    model: Services.KundaliProfiles.profiles.filter(p => !Services.KundaliProfiles.same(p, win.birth))
                    Choice {
                        required property var modelData
                        text: modelData.name
                        selected: !!win.partner && win.partner.id === modelData.id
                        onClicked: { win.partner = modelData; win.runMatch(); }
                    }
                }
            }
            RowLayout {
                visible: win.partner !== null
                spacing: Theme.space(2)
                Text { text: Tr.t("This chart is the"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                Choice { text: Tr.t("groom"); selected: win.thisIsGroom; onClicked: { win.thisIsGroom = true; win.runMatch(); } }
                Choice { text: Tr.t("bride"); selected: !win.thisIsGroom; onClicked: { win.thisIsGroom = false; win.runMatch(); } }
            }
        }
        StatusHero {
            Layout.fillWidth: true
            visible: win.section === "match" && win.matchData !== null && !win.matchData.error
            readonly property real total: Number((win.matchData || {}).total || 0)
            tone: total >= 25 ? "ok" : total >= 18 ? "warn" : "error"
            overline: Tr.t("Ashtakoota guna milan")
            headline: Tr.t("%1 of 36 points", total)
            detail: total >= 33 ? Tr.t("An excellent match") : total >= 25 ? Tr.t("A good match")
                  : total >= 18 ? Tr.t("An acceptable match") : Tr.t("Not recommended by the traditional count")
            chips: [((win.matchData || {}).nadi_dosha || {}).present ? Tr.t("Nadi dosha") : Tr.t("No nadi dosha"),
                    ((win.matchData || {}).bhakoot_dosha || {}).present ? Tr.t("Bhakoot dosha") : Tr.t("No bhakoot dosha")]
        }
        Card {
            Layout.fillWidth: true
            visible: win.section === "match" && win.matchData !== null && !win.matchData.error
            icon: "view-statistics"
            title: Tr.t("The eight kootas")
            spacing: Theme.space(2)
            Repeater {
                model: (win.matchData || {}).kootas || []
                ColumnLayout {
                    id: koota
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(3)
                    RowLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: win.kootaNames[koota.modelData.name] || koota.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body") }
                        Text { text: koota.modelData.score + " / " + koota.modelData.max; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body"); font.weight: Font.DemiBold }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.px(8)
                        radius: height / 2
                        color: Theme.pressed
                        Rectangle {
                            width: parent.width * (koota.modelData.max ? koota.modelData.score / koota.modelData.max : 0)
                            height: parent.height
                            radius: parent.radius
                            readonly property real f: koota.modelData.max ? koota.modelData.score / koota.modelData.max : 0
                            color: f >= 0.75 ? Theme.success : f >= 0.4 ? Theme.amber : Theme.danger
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: [koota.modelData.groom, koota.modelData.bride].filter(x => x).join("  ·  ")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                    }
                }
            }
        }

        // ---- KP: each cusp's and planet's lords ------------------------------------------
        Card {
            Layout.fillWidth: true
            visible: win.section === "kp" && win.chart !== null
            icon: "view-list-details"
            title: Tr.t("KP: sign, star, sub and sub-sub lords")
            subtitle: (win.extra.kplords || {}).kp_ayanamsa ? Tr.t("Placidus cusps, KP ayanamsa %1°", Number(win.extra.kplords.kp_ayanamsa).toFixed(3)) : Tr.t("Working it out…")
            spacing: 0
            Repeater {
                model: ((win.extra.kplords || {}).points || []).concat((win.extra.kplords || {}).cusps || [])
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    interactive: false
                    icon: String(modelData.name).indexOf("house") === 0 ? "go-home" : "starred"
                    title: String(modelData.name).indexOf("house") === 0 ? Tr.t("Cusp %1", String(modelData.name).replace("house ", "")) : modelData.name
                    subtitle: Tr.t("%1 · sign %2 · star %3", modelData.sign, modelData.sign_lord, modelData.star_lord)
                    trailing: Tr.t("sub %1 · %2", modelData.sub_lord, modelData.sub_sub_lord)
                }
            }
        }

        // ---- the annual chart (Varshaphal) --------------------------------------------------
        Card {
            id: annualCard
            Layout.fillWidth: true
            visible: win.section === "annual" && win.chart !== null
            readonly property var v: win.extra.varshaphal || null
            icon: "x-office-calendar"
            title: Tr.t("Annual chart %1", win.annualYear)
            subtitle: v && !v.error ? Tr.t("The Sun returns on %1", Qt.formatDateTime(new Date(v.solar_return), "d MMMM yyyy, HH:mm")) : Tr.t("Working it out…")
            actions: [
                IconButton { icon: "go-previous"; tip: Tr.t("The year before"); onClicked: { win.annualYear -= 1; win.loadData(["varshaphal"]); } },
                IconButton { icon: "go-next"; tip: Tr.t("The year after"); onClicked: { win.annualYear += 1; win.loadData(["varshaphal"]); } }
            ]
            Flow {
                Layout.fillWidth: true
                spacing: Theme.space(2)
                visible: !!annualCard.v && !annualCard.v.error
                StatusPill { tone: "info"; text: Tr.t("Muntha in %1 (lord %2)", ((annualCard.v || {}).muntha || {}).sign, ((annualCard.v || {}).muntha || {}).lord) }
                StatusPill { tone: "ok"; text: Tr.t("Year lord: %1", (annualCard.v || {}).year_lord || "") }
            }
            KundaliChart {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.maximumWidth: Theme.px(400)
                Layout.preferredHeight: width   // square: its height follows the width it was given
                visible: !!annualCard.v && !annualCard.v.error
                style: win.chartStyle
                tints: win.planetTint
                ascendantSign: annualCard.v && annualCard.v.ascendant !== undefined ? win.signsList[Math.floor(annualCard.v.ascendant / 30) % 12] : ""
                planets: ((annualCard.v || {}).planets || []).filter(p => ["Uranus", "Neptune", "Pluto"].indexOf(p.name) < 0)
            }
        }

        // ---- Lal Kitab -----------------------------------------------------------------
        GridLayout {
            id: lkGrid
            Layout.fillWidth: true
            visible: win.section === "lalkitab" && win.chart !== null
            columns: width > Theme.px(860) ? 2 : 1
            columnSpacing: Theme.space(5)
            rowSpacing: Theme.space(5)
            readonly property var lk: win.extra.lalkitab || null
            Card {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                icon: "view-grid"
                title: Tr.t("Lal Kitab chart")
                subtitle: Tr.t("Aries is always the first house; the planets keep their houses")
                KundaliChart {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.maximumWidth: Theme.px(400)
                    Layout.preferredHeight: width   // square: its height follows the width it was given
                    style: "north"
                    tints: win.planetTint
                    ascendantSign: "Aries"
                    planets: ((lkGrid.lk || {}).planets || []).filter(p => ["Uranus", "Neptune", "Pluto"].indexOf(p.name) < 0)
                             .map(p => ({ name: p.name, sign: win.signsList[(p.house - 1) % 12], retrograde: false }))
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                icon: "starred"
                title: Tr.t("Planets in their houses")
                subtitle: Tr.t("Pakka ghar is each planet's own house in Lal Kitab")
                spacing: 0
                Repeater {
                    model: ((lkGrid.lk || {}).planets || []).filter(p => ["Uranus", "Neptune", "Pluto"].indexOf(p.name) < 0)
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        interactive: false
                        icon: modelData.in_pakka_ghar ? "emblem-ok" : "starred"
                        title: Tr.t("%1 in house %2", modelData.name, modelData.house)
                        subtitle: Tr.t("Pakka ghar %1", modelData.pakka_ghar) + (modelData.in_pakka_ghar ? " · " + Tr.t("at home") : "")
                        trailing: modelData.dignity && modelData.dignity !== "Neutral" ? modelData.dignity : ""
                    }
                }
            }
        }

        // ---- the days ahead -------------------------------------------------------------
        Card {
            Layout.fillWidth: true
            visible: win.section === "ahead" && win.chart !== null
            icon: "view-calendar-week"
            title: Tr.t("The days ahead")
            subtitle: Tr.t("Traditional indications from this chart, not certainties: the Moon's place from the birth Moon, the day's star, and the periods")
            BusyNote { visible: win.ahead === null; note: Tr.t("Working it out…"); iconSize: Theme.px(16) }
            // now: the periods running, Saturn and Jupiter from the birth Moon
            Flow {
                Layout.fillWidth: true
                visible: win.ahead !== null
                spacing: Theme.space(2)
                readonly property var now: (win.ahead || {}).now || {}
                StatusPill { visible: !!parent.now.mahadasha; tone: "info"; text: parent.now.mahadasha ? Tr.t("%1 mahadasha, until %2", parent.now.mahadasha.lord, parent.now.mahadasha.until) : "" }
                StatusPill { visible: !!parent.now.antardasha; tone: "info"; text: parent.now.antardasha ? Tr.t("%1 antardasha, until %2", parent.now.antardasha.lord, parent.now.antardasha.until) : "" }
                StatusPill {
                    visible: !!parent.now.saturn
                    tone: "warn"
                    text: ({ sade_sati_rising: Tr.t("Sade Sati: rising phase"), sade_sati_peak: Tr.t("Sade Sati: peak phase"),
                             sade_sati_setting: Tr.t("Sade Sati: setting phase"), kantaka: Tr.t("Kantaka Shani: Saturn 4th from the Moon"),
                             ashtama: Tr.t("Ashtama Shani: Saturn 8th from the Moon") })[parent.now.saturn] || ""
                }
                StatusPill {
                    visible: !!(parent.now.sade_sati || {}).running
                    tone: "warn"
                    readonly property var cur: ((parent.now.sade_sati || {}).phases || [])[0] || {}
                    text: cur.end ? Tr.t("This Sade Sati phase ends %1", Qt.formatDate(new Date(cur.end + "T12:00:00"), "d MMM yyyy")) : ""
                }
                StatusPill { visible: parent.now.jupiter === "hard"; tone: "warn"; text: Tr.t("Jupiter %1th from the Moon", parent.now.jupiter_from_moon) }
                StatusPill { visible: parent.now.jupiter === "good"; tone: "ok"; text: Tr.t("Jupiter %1th from the Moon: supportive", parent.now.jupiter_from_moon) }
            }
            // the days, as a strip: one tile each, coloured by how the day looks
            GridLayout {
                Layout.fillWidth: true
                visible: win.ahead !== null
                columns: width < Theme.px(560) ? 4 : 7
                columnSpacing: Theme.space(2)
                rowSpacing: Theme.space(2)
                Repeater {
                    model: (win.ahead || {}).days || []
                    Rectangle {
                        id: dayTile
                        required property var modelData
                        readonly property color tone: modelData.tone === "difficult" ? Theme.danger : modelData.tone === "caution" ? Theme.amber
                                                    : modelData.tone === "good" ? Theme.success : Theme.dim
                        Layout.fillWidth: true
                        implicitHeight: dcol.implicitHeight + Theme.space(4)
                        radius: Theme.radius
                        color: Theme.alpha(tone, 0.14)
                        border.width: 1
                        border.color: Theme.alpha(tone, 0.45)
                        Accessible.role: Accessible.StaticText
                        Accessible.name: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "dddd d MMMM") + ": "
                                         + ((modelData.reasons || []).map(r => Services.KundaliProfiles.reasonText(r)).join(", ") || Tr.t("nothing in the way"))
                        ColumnLayout {
                            id: dcol
                            anchors.centerIn: parent
                            width: parent.width - Theme.space(2)
                            spacing: 0
                            Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(new Date(dayTile.modelData.date + "T12:00:00"), "ddd"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("caption") }
                            Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(new Date(dayTile.modelData.date + "T12:00:00"), "d"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("subtitle"); font.weight: Font.DemiBold }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: dayTile.modelData.tone === "difficult" ? Tr.t("hard") : dayTile.modelData.tone === "caution" ? Tr.t("care")
                                    : dayTile.modelData.tone === "good" ? Tr.t("good") : Tr.t("even")
                                color: dayTile.tone
                                font.family: Theme.font
                                font.pixelSize: Theme.type("caption")
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }
            // why: each day that is not plain sailing, in words
            Repeater {
                model: ((win.ahead || {}).days || []).filter(d => (d.reasons || []).length > 0)
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    interactive: false
                    icon: modelData.tone === "difficult" ? "dialog-warning" : "dialog-information"
                    title: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "dddd, d MMMM")
                    subtitle: (modelData.reasons || []).map(r => Services.KundaliProfiles.reasonText(r)).join(" · ")
                }
            }
            Repeater {
                model: (win.ahead || {}).changes || []
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    interactive: false
                    icon: "x-office-calendar"
                    title: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "dddd, d MMMM")
                    subtitle: Services.KundaliProfiles.changeText(modelData)
                }
            }
        }

        // the chart: drawn, beside its planets
        GridLayout {
            Layout.fillWidth: true
            visible: win.mode === "kundali" && win.chart !== null && win.section === "chart"
            columns: width > Theme.px(860) ? 2 : 1
            columnSpacing: Theme.space(5)
            rowSpacing: Theme.space(5)

            Card {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                icon: "view-grid"
                title: Tr.t("Chart %1", win.varga)
                subtitle: win.vargaNames[win.varga] || ""
                // the three ways India draws a chart
            actions: [
                Choice { text: Tr.t("North"); selected: win.chartStyle === "north"; Accessible.name: Tr.t("North Indian chart"); onClicked: win.chartStyle = "north" },
                Choice { text: Tr.t("South"); selected: win.chartStyle === "south"; Accessible.name: Tr.t("South Indian chart"); onClicked: win.chartStyle = "south" },
                Choice { text: Tr.t("East"); selected: win.chartStyle === "east"; Accessible.name: Tr.t("East Indian chart"); onClicked: win.chartStyle = "east" }
            ]
                KundaliChart {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.maximumWidth: Theme.px(440)
                    Layout.preferredHeight: width   // square: its height follows the width it was given
                    style: win.chartStyle
                    tints: win.planetTint
                    ascendantSign: win.vargaAscendant()
                    planets: win.vargaPlanets()
                }
                // every divisional chart: D1 to D60
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.space(1)
                    Repeater {
                        model: ["D1", "D2", "D3", "D4", "D7", "D9", "D10", "D12", "D16", "D20", "D24", "D27", "D30", "D40", "D45", "D60"]
                        Choice {
                            required property string modelData
                            text: modelData
                            selected: win.varga === modelData
                            Accessible.name: win.vargaNames[modelData] || modelData
                            onClicked: win.varga = modelData
                        }
                    }
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                icon: "starred"
                title: Tr.t("Planets")
                subtitle: Tr.t("Sign and degree, nakshatra, and how well placed")
                spacing: 0
                Repeater {
                    model: ((win.chart || {}).planets || []).filter(p => ["Uranus", "Neptune", "Pluto"].indexOf(p.name) < 0)
                    RowLayout {
                        id: prow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(Theme.px(44), Theme.touchTarget)
                        spacing: Theme.space(3)
                        Rectangle {
                            implicitWidth: Theme.px(10); implicitHeight: implicitWidth; radius: width / 2
                            color: win.planetTint[prow.modelData.name] || Theme.dim
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: prow.modelData.name
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.type("body")
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Tr.t("%1 %2°%3′", prow.modelData.sign, prow.modelData.degree, String(prow.modelData.minute).padStart(2, "0"))
                                      + ((prow.modelData.nakshatra || {}).nakshatra ? " · " + prow.modelData.nakshatra.nakshatra : "")
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.type("small")
                            }
                        }
                        StatusPill { visible: !!prow.modelData.retrograde && ["Rahu", "Ketu"].indexOf(prow.modelData.name) < 0; tone: "warn"; text: Tr.t("retrograde") }
                        StatusPill {
                            visible: !!prow.modelData.dignity && prow.modelData.dignity !== "Neutral"
                            readonly property string d: String(prow.modelData.dignity || "").toLowerCase()
                            tone: d.indexOf("exalt") >= 0 || d.indexOf("own") >= 0 || d.indexOf("moola") >= 0 ? "ok"
                                : d.indexOf("debil") >= 0 || d.indexOf("enemy") >= 0 ? "error" : "neutral"
                            text: prow.modelData.dignity || ""
                        }
                    }
                }
            }
        }

        // the Vimshottari periods, as a line through the years
        Card {
            Layout.fillWidth: true
            visible: win.mode === "kundali" && win.chart !== null && (win.section === "chart" || win.section === "dasha")
            icon: "view-calendar-timeline"
            title: Tr.t("Vimshottari dasha")
            subtitle: win.dashaNow ? Tr.t("Now in %1, until %2", win.dashaNow.lord, Math.floor(win.dashaNow.to)) : Tr.t("The great periods of life, from birth")
            Item {
                Layout.fillWidth: true
                implicitHeight: Theme.px(64)
                readonly property var rows: win.chart ? win.dashaRows() : []
                readonly property real span: rows.length ? rows[rows.length - 1].to - rows[0].from : 1
                Repeater {
                    model: parent.rows
                    Item {
                        required property var modelData
                        required property int index
                        readonly property var line: parent
                        x: (modelData.from - parent.rows[0].from) / parent.span * parent.width
                        width: Math.max(2, (modelData.to - modelData.from) / parent.span * parent.width - 2)
                        height: parent.height
                        Rectangle {
                            width: parent.width
                            height: Theme.px(22)
                            radius: Theme.radiusSmall
                            color: modelData.current ? Theme.accent : Theme.alpha(win.planetTint[modelData.lord] || Theme.dim, 0.35)
                            border.width: modelData.current ? 0 : 1
                            border.color: Theme.cardBorder
                            Accessible.role: Accessible.StaticText
                            Accessible.name: Tr.t("%1 dasha, %2 to %3", modelData.lord, Math.floor(modelData.from), Math.floor(modelData.to))
                        }
                        Text {
                            y: Theme.px(26)
                            width: parent.width
                            visible: parent.width > Theme.px(34)
                            elide: Text.ElideRight
                            text: modelData.lord
                            color: modelData.current ? Theme.accent : Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.type("caption")
                            font.weight: modelData.current ? Font.DemiBold : Font.Normal
                        }
                        Text {
                            y: Theme.px(42)
                            width: parent.width
                            visible: parent.width > Theme.px(34)
                            text: String(Math.floor(modelData.from))
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.type("caption")
                        }
                    }
                }
            }
        }

        // ashtakavarga: the points in each sign, as bars
        Card {
            Layout.fillWidth: true
            visible: win.section === "ashtakavarga" && win.sectionData !== null && win.chart !== null
            icon: "view-statistics"
            title: Tr.t("Ashtakavarga")
            subtitle: Tr.t("Points in each sign: 28 and more is strong, under 25 weak")
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(200)
                spacing: Theme.space(2)
                Repeater {
                    model: (win.sectionData || {}).rows || []
                    ColumnLayout {
                        id: bar
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Theme.space(1)
                        readonly property real pts: Number(modelData.points) || 0
                        Item { Layout.fillHeight: true }
                        Text { Layout.alignment: Qt.AlignHCenter; text: String(bar.pts); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("caption"); font.weight: Font.DemiBold }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(4, bar.pts / 45 * Theme.px(150))
                            radius: Theme.radiusSmall
                            color: bar.pts >= 28 ? Theme.success : bar.pts < 25 ? Theme.danger : Theme.amber
                            Accessible.role: Accessible.StaticText
                            Accessible.name: Tr.t("%1: %2 points", bar.modelData.sign, bar.pts)
                        }
                        Text { Layout.alignment: Qt.AlignHCenter; text: String(bar.modelData.sign).slice(0, 3); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("caption") }
                    }
                }
            }
        }

        // the other sections: their rows
        Card {
            Layout.fillWidth: true
            visible: win.chart !== null && ["dignity", "aspects", "nakshatra", "eclipse"].indexOf(win.section) >= 0
            icon: "view-list-details"
            title: (win.sections.find(s => s[0] === win.section) || ["", ""])[1]
            spacing: 0
            Repeater {
                model: win.section === "dignity" ? ((win.sectionData || {}).planets || [])
                     : win.section === "aspects" ? ((win.sectionData || {}).aspects || []) : []
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    interactive: false
                    icon: "starred"
                    title: win.section === "dignity" ? modelData.name : modelData.planet1 + " – " + modelData.planet2
                    subtitle: win.section === "dignity" ? modelData.sign : modelData.aspect
                    trailing: win.section === "dignity" ? modelData.dignity : Tr.t("orb %1°", modelData.orb)
                }
            }
            ResultText { visible: (win.section === "nakshatra" || win.section === "eclipse") && win.sectionText !== ""; text: win.sectionText }
        }

        // ---- every other calculation ------------------------------------------------
        Card {
            Layout.fillWidth: true
            visible: win.mode === "kundali" && win.section === "all"
            icon: "accessories-calculator"
            title: Tr.t("Every calculation")
            subtitle: Tr.t("Strength, other dashas, special points, yogas, timing and more, for this birth")
            Flow {
                Layout.fillWidth: true
                spacing: Theme.space(2)
                Repeater {
                    model: win.groups
                    Choice {
                        required property var modelData
                        text: modelData.label
                        selected: win.group === modelData.id
                        onClicked: { win.group = modelData.id; win.calc = ""; win.calcText = ""; }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.stroke }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.space(2)
                Repeater {
                    model: (win.groups.find(g => g.id === win.group) || { calcs: [] }).calcs
                    Choice {
                        required property var modelData
                        text: win.calcNames[modelData] || modelData
                        selected: win.calc === modelData
                        enabled: win.chart !== null
                        onClicked: win.runCalc(modelData)
                    }
                }
            }
            // a horary question is about one house
            Flow {
                visible: win.calc === "horary"
                Layout.fillWidth: true
                spacing: Theme.space(2)
                Text { text: Tr.t("The question is about house"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                Repeater {
                    model: 12
                    Choice {
                        required property int index
                        text: String(index + 1)
                        selected: win.horaryHouse === index + 1
                        onClicked: { win.horaryHouse = index + 1; win.runCalc("horary"); }
                    }
                }
            }
            BusyNote { visible: win.calcBusy; note: Tr.t("Working it out…") }
            ResultText { visible: win.calcText !== "" && !win.calcBusy; text: win.calcText }
            RowLayout {
                visible: win.calcText !== "" && !win.calcBusy
                Item { Layout.fillWidth: true }
                Button {
                    text: win.copied ? Tr.t("Copied") : Tr.t("Copy result")
                    onClicked: { Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", win.calcText]); win.copied = true; }
                }
            }
            EmptyState {
                Layout.fillWidth: true
                visible: win.chart === null
                icon: "accessories-calculator"
                title: Tr.t("Make the chart first")
                subtitle: Tr.t("Then pick a calculation")
            }
        }

        // nothing yet: say what happens
        EmptyState {
            Layout.fillWidth: true
            visible: win.mode === "kundali" && win.chart === null && !win.loading && win.error === "" && win.section !== "all"
            icon: "starred"
            title: Tr.t("Your chart appears here")
            subtitle: Tr.t("Pick the date, time and place of birth, then Make the chart")
        }
    }
}
