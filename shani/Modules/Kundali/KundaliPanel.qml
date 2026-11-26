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

AppWindow {
    id: win
    appName: "Kundali"
    visible: Ui.kundali
    onGone: Ui.kundali = false
    margins: 0
    implicitWidth: Theme.px(980)
    implicitHeight: Theme.px(760)

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
    property string error: ""
    property bool loading: false
    property string varga: "D1"
    property string section: "chart"        // the chart's sections (data, drawn below)
    property string sectionText: ""
    property string group: "chart"          // every other calculation, by group
    property string calc: ""
    property string calcText: ""
    property bool calcBusy: false
    property int horaryHouse: 7
    property bool copied: false

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
        win.error = "";
        win.sectionText = "";
        win.calcText = "";
        win.copied = false;
    }

    // ---- running the bridge --------------------------------------------------
    readonly property string scriptPath: Quickshell.env("SHANI_KUNDALI_TOOL") || "/usr/lib/shani-shell/kundali.py"
    function calculate() {
        win.clearResult();
        win.loading = true;
        main.command = win.mode === "panchang"
            ? ["python3", win.scriptPath, "panchang", win.birthArg(), String(win.place.lat), String(win.place.lon)]
            : ["python3", win.scriptPath, "kundali", win.birthArg(), String(win.place.lat), String(win.place.lon)];
        main.running = true;
    }
    function showSection(id) {
        win.section = id;
        win.sectionText = "";
        if (id === "chart" || !win.chart) return;
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
    onVisibleChanged: if (visible && Ui.kundaliDate) {
        win.mode = "panchang";
        win.dateInput = Ui.kundaliDate;
        win.calculate();
    }

    Process {
        id: main
        stdout: StdioCollector {
            onStreamFinished: {
                win.loading = false;
                try {
                    const d = JSON.parse(text);
                    if (d.error) { win.error = d.error; return; }
                    if (win.mode === "panchang") win.day = d;
                    else { win.chart = d; win.showSection(win.section); if (win.calc) win.runCalc(win.calc); }
                } catch (e) { win.error = Tr.t("The result could not be read"); }
            }
        }
        onExited: code => { if (code !== 0 && win.error === "" && !win.chart && !win.day) { win.loading = false; win.error = Tr.t("The calculation failed — is the Kundali helper installed?"); } }
    }
    Process {
        id: sectionProc
        stdout: StdioCollector { onStreamFinished: {
            try { const d = JSON.parse(text); win.sectionText = d.error ? Tr.t("Could not compute: %1").arg(d.error) : win.renderSection(d); }
            catch (e) { win.sectionText = Tr.t("The result could not be read"); }
        } }
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

    AppPage {
        anchors.fill: parent
        title: win.mode === "panchang" ? Tr.t("Panchang") : Tr.t("Kundali")
        subtitle: win.mode === "panchang" ? Tr.t("The day's tithi, nakshatra, yoga and karana, for a place")
                                          : Tr.t("A birth chart, sidereal with Lahiri ayanamsa, worked out on this computer")
        Keys.onEscapePressed: Ui.kundali = false

        SegmentedTabs {
            options: [Tr.t("Birth chart"), Tr.t("Panchang")]
            currentIndex: win.mode === "panchang" ? 1 : 0
            onActivated: index => { win.mode = index === 1 ? "panchang" : "kundali"; win.clearResult(); }
        }

        // ---- when and where ---------------------------------------------------
        Card {
            Layout.fillWidth: true
            icon: "x-office-calendar"
            title: win.mode === "panchang" ? Tr.t("Which day, and where") : Tr.t("When and where you were born")
            subtitle: Tr.t("Times are read in the place's own time zone, summer time included")

            GridLayout {
                Layout.fillWidth: true
                columns: width > Theme.px(620) && win.mode === "kundali" ? 2 : 1
                columnSpacing: Theme.space(6)
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

        // ---- the day -------------------------------------------------------------
        TileGrid {
            Layout.fillWidth: true
            visible: win.mode === "panchang" && win.day !== null
            minTileWidth: Theme.px(170)
            maxColumns: 5
            StatTile { icon: "weather-clear-night"; label: Tr.t("Tithi"); value: (win.day || {}).tithi || "" }
            StatTile { icon: "x-office-calendar"; label: Tr.t("Vara"); value: (win.day || {}).vara || "" }
            StatTile { icon: "starred"; label: Tr.t("Nakshatra"); value: (win.day || {}).nakshatra || "" }
            StatTile { icon: "emblem-favorite"; label: Tr.t("Yoga"); value: (win.day || {}).yoga || "" }
            StatTile { icon: "view-calendar-day"; label: Tr.t("Karana"); value: (win.day || {}).karana || "" }
        }

        // ---- the birth chart -------------------------------------------------------
        TileGrid {
            Layout.fillWidth: true
            visible: win.mode === "kundali" && win.chart !== null
            minTileWidth: Theme.px(180)
            readonly property var moon: ((win.chart || {}).planets || []).find(p => p.name === "Moon") || {}
            StatTile { icon: "go-up"; label: Tr.t("Rising sign"); value: (win.chart || {}).ascendant_sign || ""; detail: Tr.t("Ascendant, %1°", Math.floor(((win.chart || {}).ascendant || 0) % 30)) }
            StatTile { icon: "weather-clear-night"; label: Tr.t("Moon sign"); value: parent.moon.sign || ""; detail: ((parent.moon.nakshatra || {}).nakshatra || "") }
            StatTile { icon: "starred"; label: Tr.t("Ayanamsa"); value: ((win.chart || {}).ayanamsa || 0).toFixed ? Number((win.chart || {}).ayanamsa).toFixed(3) + "°" : ""; detail: (win.chart || {}).ayanamsa_name || "" }
        }

        Card {
            Layout.fillWidth: true
            visible: win.mode === "kundali" && win.chart !== null
            icon: "view-grid"
            title: win.varga === "D9" ? Tr.t("Navamsa chart (D9)") : Tr.t("Birth chart (D1)")
            subtitle: Tr.t("North Indian style: the houses stay put, the first at the top; numbers are signs, ᴿ is retrograde")
            actions: [ SegmentedTabs { options: [Tr.t("D1"), Tr.t("D9")]; segmentWidth: Theme.px(56); currentIndex: win.varga === "D9" ? 1 : 0; onActivated: index => win.varga = index === 1 ? "D9" : "D1" } ]
            KundaliChart {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(Theme.px(420), parent.width)
                Layout.preferredHeight: Layout.preferredWidth
                ascendantSign: win.varga === "D9" ? ((win.chart || {}).navamsa_ascendant || "") : ((win.chart || {}).ascendant_sign || "")
                planets: {
                    const ps = ((win.chart || {}).planets || []).filter(p => ["Uranus", "Neptune", "Pluto"].indexOf(p.name) < 0);
                    if (win.varga !== "D9") return ps;
                    const nav = (win.chart || {}).navamsa || [];
                    return ps.map(p => ({ name: p.name, retrograde: p.retrograde, sign: (nav.find(n => n.name === p.name) || {}).sign || "" }));
                }
            }
        }

        Card {
            Layout.fillWidth: true
            visible: win.mode === "kundali" && win.chart !== null
            icon: "starred"
            title: Tr.t("Planets")
            spacing: 0
            Repeater {
                model: (win.chart || {}).planets || []
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    interactive: false
                    icon: "starred"
                    title: modelData.name + (modelData.retrograde ? "  ·  " + Tr.t("retrograde") : "")
                    subtitle: Tr.t("%1 %2°%3′", modelData.sign, modelData.degree, String(modelData.minute).padStart(2, "0"))
                              + ((modelData.nakshatra || {}).nakshatra ? " · " + modelData.nakshatra.nakshatra : "")
                    trailing: modelData.dignity || ""
                }
            }
        }

        Card {
            Layout.fillWidth: true
            visible: win.mode === "kundali" && win.chart !== null
            icon: "view-calendar-timeline"
            title: Tr.t("Vimshottari dasha")
            subtitle: Tr.t("The great periods from birth; the one running now is marked")
            spacing: 0
            Repeater {
                model: win.chart ? win.dashaRows() : []
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    interactive: false
                    selected: modelData.current
                    icon: modelData.current ? "media-playback-start" : "x-office-calendar"
                    title: modelData.lord
                    subtitle: Math.floor(modelData.from) + " – " + Math.floor(modelData.to)
                    trailing: modelData.current ? Tr.t("now") : ""
                }
            }
        }

        // ---- the chart's sections --------------------------------------------------
        Card {
            Layout.fillWidth: true
            visible: win.mode === "kundali"
            icon: "view-list-details"
            title: Tr.t("Chart details")
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: secRow.implicitHeight
                contentWidth: secRow.implicitWidth
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Row {
                    id: secRow
                    spacing: Theme.space(2)
                    Repeater {
                        model: win.sections
                        Choice {
                            required property var modelData
                            text: modelData[1]
                            selected: win.section === modelData[0]
                            onClicked: win.showSection(modelData[0])
                        }
                    }
                }
            }
            ResultText { visible: win.section !== "chart" && win.sectionText !== ""; text: win.sectionText }
            Text {
                visible: win.chart === null
                text: Tr.t("Make the chart first: its sections appear here")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("small")
            }
        }

        // ---- every other calculation ----------------------------------------------
        Card {
            Layout.fillWidth: true
            visible: win.mode === "kundali"
            icon: "accessories-calculator"
            title: Tr.t("Every calculation")
            subtitle: Tr.t("Strength, other dashas, special points, yogas, timing and more, for this birth")
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: groupRow.implicitHeight
                contentWidth: groupRow.implicitWidth
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Row {
                    id: groupRow
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
            }
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
            RowLayout {
                visible: win.calc === "horary"
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
            Text {
                visible: win.chart === null
                text: Tr.t("Make the chart first, then pick a calculation")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("small")
            }
        }
    }
}
