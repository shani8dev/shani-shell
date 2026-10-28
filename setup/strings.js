.pragma library
// First-boot setup's words, in the languages it opens most often in. The
// language picked on the first page switches the rest of the wizard at once;
// anything missing here falls back to English.

var strings = {
    en: {
        welcome: "Welcome to ShaniOS", welcomeSub: "Choose your language. It can be changed later in Settings.",
        keyboard: "Your keyboard", keyboardSub: "Add the layouts you type in. Super+Space switches between them.",
        network: "Get connected", networkSub: "Connect now for the right time and updates — or skip this.",
        time: "Your time zone", timeSub: "Search for a city or region near you.",
        account: "About you", accountSub: "This is the computer's first account, and its administrator.",
        done: "All set", signingIn: "Signing you in…",
        searchLang: "Search — English, मराठी, Deutsch…", addLayout: "Add a layout — marathi, german, dvorak…",
        online: "Connected to the internet.", chooseWifi: "Choose a Wi-Fi network.", noWifi: "No Wi-Fi here — plug in a cable, or skip.",
        connected: "Connected", connecting: "Connecting…", passwordFor: "Password for ",
        searchZone: "Search — Kolkata, Berlin, New York…",
        fullName: "Your full name", userName: "User name", password: "Password", passwordAgain: "Password again", computerName: "Computer name",
        passwordIs: "Password: ", weak: "Weak — 8 or more characters is better", fair: "Fair", strong: "Strong",
        needName: "Your name, please", badUser: "The user name: lower-case letters, digits, '-' and '_'",
        needPassword: "Choose a password", mismatch: "The passwords do not match", badHost: "The computer name: letters, digits and '-'",
        back: "Back", next: "Next", skip: "Skip", start: "Start using ShaniOS", working: "Setting up…",
        larger: "Larger text", contrast: "High contrast", reader: "Screen reader", note: "Note: ", remove: "Remove "
    },
    mr: {
        welcome: "ShaniOS मध्ये आपले स्वागत", welcomeSub: "तुमची भाषा निवडा. ती नंतर सेटिंग्जमध्ये बदलता येईल.",
        keyboard: "तुमचा कीबोर्ड", keyboardSub: "तुम्ही ज्या लेआउटमध्ये टाइप करता ते जोडा. Super+Space ने त्यांच्यात बदला.",
        network: "जोडणी करा", networkSub: "योग्य वेळ आणि अपडेटसाठी आताच जोडा — किंवा हे वगळा.",
        time: "तुमचा वेळ विभाग", timeSub: "जवळचे शहर किंवा प्रदेश शोधा.",
        account: "तुमच्याबद्दल", accountSub: "हे या संगणकाचे पहिले खाते आहे, आणि त्याचे प्रशासक.",
        done: "सर्व तयार", signingIn: "तुम्हाला साइन इन करत आहे…",
        searchLang: "शोधा — English, मराठी, Deutsch…", addLayout: "लेआउट जोडा — marathi, german, dvorak…",
        online: "इंटरनेटशी जोडले आहे.", chooseWifi: "वाय-फाय नेटवर्क निवडा.", noWifi: "येथे वाय-फाय नाही — केबल लावा, किंवा वगळा.",
        connected: "जोडले", connecting: "जोडत आहे…", passwordFor: "पासवर्ड: ",
        searchZone: "शोधा — Kolkata, Berlin, New York…",
        fullName: "तुमचे पूर्ण नाव", userName: "वापरकर्ता नाव", password: "पासवर्ड", passwordAgain: "पासवर्ड पुन्हा", computerName: "संगणकाचे नाव",
        passwordIs: "पासवर्ड: ", weak: "कमकुवत — ८ किंवा जास्त अक्षरे चांगली", fair: "ठीक", strong: "मजबूत",
        needName: "कृपया तुमचे नाव", badUser: "वापरकर्ता नाव: लहान इंग्रजी अक्षरे, अंक, '-' आणि '_'",
        needPassword: "पासवर्ड निवडा", mismatch: "पासवर्ड जुळत नाहीत", badHost: "संगणकाचे नाव: अक्षरे, अंक आणि '-'",
        back: "मागे", next: "पुढे", skip: "वगळा", start: "ShaniOS वापरायला सुरुवात करा", working: "तयारी करत आहे…",
        larger: "मोठा मजकूर", contrast: "उच्च कॉन्ट्रास्ट", reader: "स्क्रीन रीडर", note: "टीप: ", remove: "काढा "
    },
    hi: {
        welcome: "ShaniOS में आपका स्वागत है", welcomeSub: "अपनी भाषा चुनें। इसे बाद में सेटिंग्स में बदला जा सकता है।",
        keyboard: "आपका कीबोर्ड", keyboardSub: "जिन लेआउट में आप टाइप करते हैं उन्हें जोड़ें। Super+Space से उनके बीच बदलें।",
        network: "कनेक्ट करें", networkSub: "सही समय और अपडेट के लिए अभी कनेक्ट करें — या इसे छोड़ दें।",
        time: "आपका समय क्षेत्र", timeSub: "अपने पास का शहर या क्षेत्र खोजें।",
        account: "आपके बारे में", accountSub: "यह इस कंप्यूटर का पहला खाता है, और इसका व्यवस्थापक।",
        done: "सब तैयार", signingIn: "आपको साइन इन किया जा रहा है…",
        searchLang: "खोजें — English, हिन्दी, मराठी…", addLayout: "लेआउट जोड़ें — hindi, marathi, german…",
        online: "इंटरनेट से कनेक्ट है।", chooseWifi: "वाई-फ़ाई नेटवर्क चुनें।", noWifi: "यहाँ वाई-फ़ाई नहीं — केबल लगाएँ, या छोड़ दें।",
        connected: "कनेक्ट है", connecting: "कनेक्ट हो रहा है…", passwordFor: "पासवर्ड: ",
        searchZone: "खोजें — Kolkata, Berlin, New York…",
        fullName: "आपका पूरा नाम", userName: "उपयोगकर्ता नाम", password: "पासवर्ड", passwordAgain: "पासवर्ड दोबारा", computerName: "कंप्यूटर का नाम",
        passwordIs: "पासवर्ड: ", weak: "कमज़ोर — 8 या अधिक अक्षर बेहतर हैं", fair: "ठीक", strong: "मज़बूत",
        needName: "कृपया अपना नाम", badUser: "उपयोगकर्ता नाम: छोटे अंग्रेज़ी अक्षर, अंक, '-' और '_'",
        needPassword: "पासवर्ड चुनें", mismatch: "पासवर्ड मेल नहीं खाते", badHost: "कंप्यूटर का नाम: अक्षर, अंक और '-'",
        back: "पीछे", next: "आगे", skip: "छोड़ें", start: "ShaniOS का उपयोग शुरू करें", working: "तैयार किया जा रहा है…",
        larger: "बड़ा टेक्स्ट", contrast: "उच्च कंट्रास्ट", reader: "स्क्रीन रीडर", note: "नोट: ", remove: "हटाएँ "
    },
    de: {
        welcome: "Willkommen bei ShaniOS", welcomeSub: "Wählen Sie Ihre Sprache. Sie lässt sich später in den Einstellungen ändern.",
        keyboard: "Ihre Tastatur", keyboardSub: "Fügen Sie die Belegungen hinzu, mit denen Sie schreiben. Super+Leertaste wechselt.",
        network: "Verbinden", networkSub: "Jetzt verbinden für die richtige Uhrzeit und Aktualisierungen — oder überspringen.",
        time: "Ihre Zeitzone", timeSub: "Suchen Sie eine Stadt oder Region in Ihrer Nähe.",
        account: "Über Sie", accountSub: "Das ist das erste Konto dieses Computers und sein Administrator.",
        done: "Fertig", signingIn: "Sie werden angemeldet …",
        searchLang: "Suchen — Deutsch, English, मराठी …", addLayout: "Belegung hinzufügen — german, french, dvorak …",
        online: "Mit dem Internet verbunden.", chooseWifi: "Wählen Sie ein WLAN.", noWifi: "Kein WLAN — Kabel anschließen oder überspringen.",
        connected: "Verbunden", connecting: "Verbinde …", passwordFor: "Passwort für ",
        searchZone: "Suchen — Berlin, Wien, Zürich …",
        fullName: "Ihr vollständiger Name", userName: "Benutzername", password: "Passwort", passwordAgain: "Passwort wiederholen", computerName: "Computername",
        passwordIs: "Passwort: ", weak: "Schwach — 8 oder mehr Zeichen sind besser", fair: "Mittel", strong: "Stark",
        needName: "Ihr Name, bitte", badUser: "Benutzername: Kleinbuchstaben, Ziffern, '-' und '_'",
        needPassword: "Wählen Sie ein Passwort", mismatch: "Die Passwörter stimmen nicht überein", badHost: "Computername: Buchstaben, Ziffern und '-'",
        back: "Zurück", next: "Weiter", skip: "Überspringen", start: "ShaniOS verwenden", working: "Wird eingerichtet …",
        larger: "Größere Schrift", contrast: "Hoher Kontrast", reader: "Bildschirmleser", note: "Hinweis: ", remove: "Entfernen: "
    },
    es: {
        welcome: "Te damos la bienvenida a ShaniOS", welcomeSub: "Elige tu idioma. Podrás cambiarlo más tarde en Ajustes.",
        keyboard: "Tu teclado", keyboardSub: "Añade las distribuciones en las que escribes. Super+Espacio cambia entre ellas.",
        network: "Conéctate", networkSub: "Conéctate ahora para tener la hora correcta y actualizaciones, u omite este paso.",
        time: "Tu zona horaria", timeSub: "Busca una ciudad o región cercana.",
        account: "Sobre ti", accountSub: "Es la primera cuenta de este equipo y su administradora.",
        done: "Todo listo", signingIn: "Iniciando tu sesión…",
        searchLang: "Buscar — Español, English, मराठी…", addLayout: "Añadir distribución — spanish, latin american, dvorak…",
        online: "Conectado a internet.", chooseWifi: "Elige una red Wi-Fi.", noWifi: "No hay Wi-Fi: conecta un cable u omite este paso.",
        connected: "Conectado", connecting: "Conectando…", passwordFor: "Contraseña de ",
        searchZone: "Buscar — Madrid, Ciudad de México, Bogotá…",
        fullName: "Tu nombre completo", userName: "Nombre de usuario", password: "Contraseña", passwordAgain: "Repite la contraseña", computerName: "Nombre del equipo",
        passwordIs: "Contraseña: ", weak: "Débil: mejor 8 caracteres o más", fair: "Aceptable", strong: "Fuerte",
        needName: "Tu nombre, por favor", badUser: "Nombre de usuario: minúsculas, dígitos, '-' y '_'",
        needPassword: "Elige una contraseña", mismatch: "Las contraseñas no coinciden", badHost: "Nombre del equipo: letras, dígitos y '-'",
        back: "Atrás", next: "Siguiente", skip: "Omitir", start: "Empezar a usar ShaniOS", working: "Configurando…",
        larger: "Texto más grande", contrast: "Alto contraste", reader: "Lector de pantalla", note: "Nota: ", remove: "Quitar "
    },
    fr: {
        welcome: "Bienvenue dans ShaniOS", welcomeSub: "Choisissez votre langue. Vous pourrez la changer plus tard dans les Paramètres.",
        keyboard: "Votre clavier", keyboardSub: "Ajoutez les dispositions dans lesquelles vous écrivez. Super+Espace passe de l'une à l'autre.",
        network: "Se connecter", networkSub: "Connectez-vous maintenant pour l'heure exacte et les mises à jour — ou passez.",
        time: "Votre fuseau horaire", timeSub: "Cherchez une ville ou une région proche.",
        account: "À propos de vous", accountSub: "C'est le premier compte de cet ordinateur, et son administrateur.",
        done: "Tout est prêt", signingIn: "Connexion à votre session…",
        searchLang: "Rechercher — Français, English, मराठी…", addLayout: "Ajouter une disposition — french, bepo, dvorak…",
        online: "Connecté à Internet.", chooseWifi: "Choisissez un réseau Wi-Fi.", noWifi: "Pas de Wi-Fi ici — branchez un câble, ou passez.",
        connected: "Connecté", connecting: "Connexion…", passwordFor: "Mot de passe pour ",
        searchZone: "Rechercher — Paris, Montréal, Dakar…",
        fullName: "Votre nom complet", userName: "Nom d'utilisateur", password: "Mot de passe", passwordAgain: "Mot de passe, à nouveau", computerName: "Nom de l'ordinateur",
        passwordIs: "Mot de passe : ", weak: "Faible — 8 caractères ou plus, c'est mieux", fair: "Moyen", strong: "Fort",
        needName: "Votre nom, s'il vous plaît", badUser: "Nom d'utilisateur : minuscules, chiffres, '-' et '_'",
        needPassword: "Choisissez un mot de passe", mismatch: "Les mots de passe ne correspondent pas", badHost: "Nom de l'ordinateur : lettres, chiffres et '-'",
        back: "Retour", next: "Suivant", skip: "Passer", start: "Commencer à utiliser ShaniOS", working: "Configuration…",
        larger: "Texte plus grand", contrast: "Contraste élevé", reader: "Lecteur d'écran", note: "Note : ", remove: "Retirer "
    }
};

// "mr_IN.UTF-8" → its language's word for key, English when there is none
function tr(locale, key) {
    var lang = (locale || "en").slice(0, 2);
    var t = strings[lang] || strings.en;
    return t[key] !== undefined ? t[key] : strings.en[key];
}
