pragma Singleton
// Internet radio (Shortwave parity), in the Media Player: stations from the
// community directory radio-browser.info (the one Shortwave uses) - searched,
// the most played, the ones near you (your country), by genre - and your
// favourites, kept in Settings. A station plays in the Media Player like a file.
// Asked only while the Radio page is open; a play is counted with the directory,
// as it asks of the apps that use it. SHANI_RADIO_API (tests): another server.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string api: Quickshell.env("SHANI_RADIO_API") || "https://de1.api.radio-browser.info"
    readonly property string userAgent: "shani-shell-radio/1.0 (+https://github.com/shani8dev/shani-shell)"
    property var stations: []               // [{ uuid, name, url, favicon, tags, country, codec, bitrate }]
    property string showing: ""             // favourites | popular | near | genre:<tag> | search:<words>
    property string sourceChoice: "internet"   // internet | fm: the source picked on Media Player > Radio
    property bool loading: false
    property string error: ""
    readonly property var favourites: Settings.data.radioFavourites || []
    // Free, public stations to start with (listener-supported SomaFM and Radio
    // Paradise, plus Indian stations from radio-browser.info). No secret keys.
    readonly property var featured: [
        { uuid: "", name: "SomaFM Groove Salad", url: "https://ice1.somafm.com/groovesalad-128-mp3", favicon: "", tags: "ambient, chill", country: "US", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "SomaFM Indie Pop Rocks", url: "https://ice1.somafm.com/indiepop-128-mp3", favicon: "", tags: "indie, pop", country: "US", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Radio Paradise", url: "https://stream.radioparadise.com/mp3-320", favicon: "", tags: "eclectic, ad-free", country: "US", codec: "MP3", bitrate: 320 },
        { uuid: "", name: "BIG 92.7 FM", url: "https://stream.zeno.fm/dbstwo3dvhhtv", favicon: "", tags: "bollywood, hindi", country: "IN", codec: "MP3", bitrate: 0 },
        { uuid: "", name: "Hindi Gold Radio", url: "https://azuracast.vibesounds.in:8010/radio.mp3", favicon: "https://onlineradiohub.com/wp-content/uploads/2023/07/hindi-gold-radio.jpg", tags: "", country: "IN", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Diverse FM", url: "https://carol.epichosts.co.uk:8570/;", favicon: "https://onlineradiohub.com/wp-content/uploads/2023/05/diverse-fm-hindi.jpg", tags: "", country: "IN", codec: "AAC+", bitrate: 48 },
        { uuid: "", name: "Nostalgic Bollywood 90s", url: "https://www.desizoneradio.com/relay3", favicon: "", tags: "90s", country: "IN", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "All India Radio News 24X7", url: "https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio002/hlspbaudio002_Auto.m3u8", favicon: "https://onlineradiohub.com/wp-content/uploads/2023/06/air-radio-news-24-7.jpg", tags: "infotainment", country: "IN", codec: "AAC+", bitrate: 32 },
        { uuid: "", name: "Aaj Tak News Radio Live", url: "https://feeds.intoday.in/aajtak/api/master.m3u8", favicon: "https://onlineradiohub.com/wp-content/uploads/2023/06/aaj-tak-radio.jpg", tags: "", country: "IN", codec: "AAC", bitrate: 255 },
        { uuid: "", name: "Radio Udaan", url: "https://stream.radioudaan.com/listen/radio_udaan/radio.mp3", favicon: "https://radioudaan.com/sites/default/files/Radioudaan%20small%202_0.png", tags: "bollywood", country: "IN", codec: "MP3", bitrate: 256 },
        { uuid: "", name: "Radio Hotstar", url: "https://leo.streamerr.co/8004/stream", favicon: "https://radiohotstar.com/logo.png", tags: "90s", country: "IN", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Desi Hits 2000s", url: "https://www.desizoneradio.com/relay2", favicon: "", tags: "2000s", country: "IN", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Radio Digital Malayali", url: "https://radio.digitalmalayali.in/listen/stream/radio.mp3", favicon: "https://radio.digitalmalayali.in/static/uploads/album_art.1688135987.jpg", tags: "bollywood", country: "IN", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Radio Gaana", url: "https://sp14.instainternet.com/8044/stream", favicon: "https://radiohotstar.com/logo2.png", tags: "90s", country: "IN", codec: "AAC+", bitrate: 96 },
        { uuid: "", name: "Gazal Radio London", url: "https://streaming.webhostnepal.com/8018/stream", favicon: "https://onlineradiohub.com/wp-content/uploads/2023/10/gazal-radio-london-uk.png", tags: "", country: "IN", codec: "AAC+", bitrate: 64 },
        { uuid: "", name: "AIR Fm Gold Delhi", url: "https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio005/hlspbaudio00564kbps.m3u8", favicon: "https://liveradios.in/wp-content/uploads/output-onlinepngtools-1-150x150.png", tags: "", country: "IN", codec: "UNKNOWN", bitrate: 0 },
        { uuid: "", name: "Vividh Bharti Mumbai", url: "https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio011/hlspbaudio011_Auto.m3u8", favicon: "https://onlineradiohub.com/wp-content/uploads/2023/07/vividh-bharathi-mumbai.jpg", tags: "", country: "IN", codec: "AAC+", bitrate: 32 },
        { uuid: "", name: "FM Gold Mumbai", url: "https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio007/hlspbaudio007_Auto.m3u8", favicon: "https://onlineradiohub.com/wp-content/uploads/2023/07/fmgold-mumbai.jpg", tags: "", country: "IN", codec: "AAC+", bitrate: 32 },
        { uuid: "", name: "Bhajans Radio Guyana", url: "https://s5.citrus3.com:8148/stream", favicon: "https://onlineradiohub.com/wp-content/uploads/2023/07/bhajan-radio-guyana.jpg", tags: "", country: "IN", codec: "AAC", bitrate: 128 },
        { uuid: "", name: "Shahimsha Online radio", url: "https://radio.shahimsha.com/listen/shahimsha/radio.mp3", favicon: "", tags: "classical", country: "IN", codec: "MP3", bitrate: 192 },
        { uuid: "", name: "Tune India Radio", url: "https://s2.radio.co/se5e166e2f/listen#.mp3", favicon: "https://onlineradiohub.com/wp-content/uploads/2023/09/tune-india-radio.jpg", tags: "", country: "IN", codec: "AAC", bitrate: 96 },
        { uuid: "", name: "AIR DELHI FM GOLD", url: "https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio005/hlspbaudio00532kbps.m3u8", favicon: "", tags: "drama", country: "IN", codec: "UNKNOWN", bitrate: 0 },
        { uuid: "", name: "DesiZone Radio", url: "https://www.desizoneradio.com/relay1", favicon: "", tags: "bollywood", country: "IN", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Fm Rainbow Delhi 32 kbps", url: "https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio004/hlspbaudio00432kbps.m3u8", favicon: "", tags: "added by shivam", country: "IN", codec: "UNKNOWN", bitrate: 0 },
        { uuid: "", name: "Pew Hits Desi", url: "https://pewhits.duckdns.org/stream/pewhitsdesi", favicon: "", tags: "bollywood", country: "IN", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Christmas FM Non-stop!", url: "https://xmas-node1.zip.wf/live.aac", favicon: "https://zip.wf/chfm.jpg", tags: "advent", country: "FI", codec: "AAC", bitrate: 128 },
        { uuid: "", name: "Radio Armisa", url: "https://onair.armisa.it/listen/armisa/radio.mp3", favicon: "https://armisa.it/assets/favicon/android-chrome-512x512.png", tags: "anni 80", country: "IT", codec: "MP3", bitrate: 0 },
        { uuid: "", name: "RTL", url: "https://live.m6radio.quortex.io/webM89Hc99XApzgfhXNX8ASN5/grouprtl/national/short/audio-64000/index.m3u8", favicon: "https://duckduckgo.com/i/035a5e15d396c67a.png", tags: "généraliste", country: "FR", codec: "AAC", bitrate: 64 },
        { uuid: "", name: "MANGORADIO", url: "https://mangoradio.stream.laut.fm/mangoradio", favicon: "https://mangoradio.de/wp-content/uploads/cropped-Logo-192x192.webp", tags: "music", country: "DE", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Europe 1", url: "https://europe1.lmn.fm/europe1.mp3", favicon: "https://db.radioline.fr/pictures/radio_fa64fea9b6ccd92e058ced3fa41f58f5/logo200.jpg", tags: "génaraliste", country: "FR", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "RMC Info Talk Sport", url: "https://audio.bfmtv.com/rmcradio_128.mp3?aw_0_1st.playerId=RMC_audio_web&aggregator=RMC_audio_web", favicon: "https://rmc.bfmtv.com/android-icon-192x192.png", tags: "sports news", country: "FR", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "SWR3", url: "https://liveradio.swr.de/sw282p3/swr3/play.mp3", favicon: "https://swr3.de/assets/swr3/icons/apple-touch-icon.png", tags: "news", country: "DE", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Nostalgie HQ", url: "https://streaming.nrjaudio.fm/oua8a3w2dqao?origine=playernostalgie&aw_0_req.userConsentV2=&aw_0_1st.station=", favicon: "https://img.nrj.fr/J6jlakQsQ2siRzCzCI_2IDCQj1E=/80x80/https%3A%2F%2Fplayers.nrjaudio.fm%2Flive-metadata%2Fplayer%2Fimg%2Fplayer-files%2Fnosta%2Flogos%2F640x640%2FP_Nostalgie_Premium_Logo_2023.png", tags: "", country: "FR", codec: "AAC", bitrate: 320 },
        { uuid: "", name: "Deutschlandfunk | DLF | MP3 128k", url: "https://st01.sslstream.dlf.de/dlf/01/128/mp3/stream.mp3?aggregator=web", favicon: "https://www.deutschlandfunk.de/static/img/deutschlandfunk/icons/apple-touch-icon-128x128.png", tags: "culture", country: "DE", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Power POP", url: "https://listen.powerapp.com.tr/powerpop/128/chunks.m3u8", favicon: "https://www.powerapp.com.tr/i/favicov2/apple-icon-120x120.png?v=817", tags: "00s", country: "TR", codec: "UNKNOWN", bitrate: 0 },
        { uuid: "", name: "Nrj Hits", url: "https://streaming.nrjaudio.fm/ou7xugf3s5gi?origine=playernrj&aw_0_req.userConsentV2=&aw_0_1st.station=NRJ-Hits", favicon: "https://img.nrj.fr/8loJFyDgG_Gm_fgnk1fhkYIewhI=/medias%2F2021%2F06%2Flogo-nrj_60db2627d4729.svg", tags: "hits", country: "FR", codec: "AAC+", bitrate: 128 },
        { uuid: "", name: "DamarTurk FM", url: "https://live.radyositesihazir.com:10997/stream?type=http&nocache=99881", favicon: "https://www.damarturkfm.com/favicon.ico", tags: "", country: "TR", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "1LIVE", url: "https://wdr-1live-live.icecastssl.wdr.de/wdr/1live/live/mp3/128/stream.mp3", favicon: "https://www1.wdr.de/radio/1live/resources/img/favicon/apple-touch-icon.png", tags: "ard", country: "DE", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "JOY TÜRK TURKEY", url: "https://playerservices.streamtheworld.com/api/livestream-redirect/JOY_TURK_SC?/", favicon: "", tags: "", country: "TR", codec: "MP3", bitrate: 64 },
        { uuid: "", name: "Bayern 3", url: "https://dispatcher.rndfnk.com/br/br3/live/mp3/mid", favicon: "https://api.ardmediathek.de/image-service/images/urn:ard:image:52fd25fc45de7c6a?w=512", tags: "pop", country: "DE", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "SomaFM Groove Salad (128k MP3)", url: "https://ice5.somafm.com/groovesalad-128-mp3", favicon: "https://somafm.com/img3/groovesalad-400.jpg", tags: "ambient", country: "US", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "Radio Italia Solo Musica Italiana", url: "https://radioitaliasmi.akamaized.net/hls/live/2093120/RISMI/stream01/streamPlaylist.m3u8", favicon: "https://www.radioitalia.it/images/logo-radioitalia.png", tags: "italian pop", country: "IT", codec: "UNKNOWN", bitrate: 0 },
        { uuid: "", name: "Retro-Ko Radio", url: "https://radio.retroko.com/listen/retroko/radio.mp3", favicon: "https://radio.retroko.com/static/uploads/browser_icon/original.1794115059.png", tags: "electronic", country: "JP", codec: "MP3", bitrate: 192 },
        { uuid: "", name: "# RdMix Classic Rock 70s 80s 90s", url: "https://cast1.torontocast.com:4610/stream", favicon: "https://static.wixstatic.com/media/f361b3_1bad7e5fb9a54196b2ac2c2fe71d6e4f~mv2.jpg", tags: "60s", country: "CA", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "EuroDance 90 radio", url: "https://stream-eurodance90.fr/radio/8000/128.mp3?1627933323", favicon: "https://eurodance90.fr/favicon.ico", tags: "dancefloor", country: "FR", codec: "MP3", bitrate: 128 },
        { uuid: "", name: "РАДИО ВАНЯ", url: "https://icecast-radiovanya.cdnvideo.ru/radiovanya", favicon: "", tags: "pop", country: "RU", codec: "AAC+", bitrate: 64 },
        { uuid: "", name: "Intense Radio - We love Dance 256K", url: "https://secure.live-streams.nl/main", favicon: "https://www.intenseradio.net/wp-content/uploads/2023/09/intense-radio-vierkant-4d-2026.jpg", tags: "clubhouse", country: "NL", codec: "MP3", bitrate: 256 },
        { uuid: "", name: "ORF Hitradio Ö3 | HQ", url: "https://orf-live.ors-shoutcast.at/oe3-q2a", favicon: "https://tubestatic.orf.at/mojo/1_3/storyserver//tube/common/images/apple-icons/oe3.png", tags: "orf", country: "AT", codec: "MP3", bitrate: 192 },
        { uuid: "", name: "Radio Mirchi Bay Area", url: "https://playerservices.streamtheworld.com/api/livestream-redirect/SFO_HIN_PSTAAC.aac", favicon: "https://static-media.streema.com/media/cache/6c/23/6c23aa893f7a781a098f50d1a56a39a4.png", tags: "bollywood", country: "US", codec: "AAC+", bitrate: 64 },
        { uuid: "", name: "Sangeet Radio FM 95.1 AM 1460 Houston, TX, US", url: "https://ice8.securenetsystems.net/SGTRADIO", favicon: "https://i0.wp.com/sangeetradio.com/wp-content/uploads/2020/05/cropped-512x512-1.png?fit=180%2c180&#038;ssl=1", tags: "hindi", country: "US", codec: "AAC+", bitrate: 32 },
        { uuid: "", name: "Translation of the Quran in Hindi", url: "https://serverkw.quran-uni.com:8126/;", favicon: "", tags: "hindi", country: "KW", codec: "MP3", bitrate: 128 }
    ]
    readonly property string countryCode: (Qt.locale().name.split("_")[1] || "").toUpperCase()

    function station(s) {
        return { uuid: s.stationuuid || s.uuid || "", name: (s.name || "").trim(), url: s.url_resolved || s.url || "",
                 favicon: s.favicon || "", tags: (s.tags || "").split(",").slice(0, 3).join(", "),
                 country: s.countrycode || s.country || "", codec: s.codec || "", bitrate: s.bitrate || 0 };
    }
    function show(what) {
        root.showing = what;
        root.error = "";
        if (what === "favourites") { root.stations = root.favourites; return; }
        if (what === "featured") { root.stations = root.featured; return; }
        let path;
        if (what === "popular") path = "/json/stations/topclick/60";
        else if (what === "near") path = "/json/stations/bycountrycodeexact/" + encodeURIComponent(root.countryCode || "IN") + "?order=clickcount&reverse=true&limit=60";
        else if (what.startsWith("genre:")) path = "/json/stations/bytagexact/" + encodeURIComponent(what.slice(6)) + "?order=clickcount&reverse=true&limit=60";
        else if (what.startsWith("search:")) path = "/json/stations/search?name=" + encodeURIComponent(what.slice(7)) + "&order=clickcount&reverse=true&limit=60&hidebroken=true";
        else return;
        fetch.command = ["curl", "-sf", "--max-time", "15", "-A", root.userAgent, root.api + path];
        root.loading = true;
        fetch.running = true;
    }
    Process {
        id: fetch
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                let r = [];
                try { r = JSON.parse(text); } catch (e) { root.error = Tr.t("The station list could not be reached"); r = []; }
                root.stations = (Array.isArray(r) ? r : []).map(root.station).filter(s => s.url && s.name);
            }
        }
    }

    function isFavourite(s) { return !!s && root.favourites.some(f => f.url === s.url); }
    function toggleFavourite(s) {
        if (!s) return;
        Settings.data.radioFavourites = isFavourite(s) ? root.favourites.filter(f => f.url !== s.url) : root.favourites.concat([s]);
        if (root.showing === "favourites") root.stations = root.favourites;
    }
    function play(s) {
        if (!s || !s.url) return;
        PlayQueue.playStream(s.url, s.name, s.favicon);
        // radio-browser counts plays from the apps that use it (its own request)
        if (s.uuid && !Quickshell.env("SHANI_RADIO_NO_COUNT"))
            Quickshell.execDetached(["curl", "-sf", "--max-time", "10", "-A", root.userAgent, "-o", "/dev/null", root.api + "/json/url/" + s.uuid]);
    }
}
