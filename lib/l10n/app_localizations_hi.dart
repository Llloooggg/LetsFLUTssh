// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class SHi extends S {
  SHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'ठीक है';

  @override
  String get infoDialogProtectsHeader => 'सुरक्षा करता है';

  @override
  String get infoDialogDoesNotProtectHeader => 'सुरक्षा नहीं करता';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get close => 'बंद करें';

  @override
  String get delete => 'हटाएं';

  @override
  String get save => 'सहेजें';

  @override
  String get connect => 'कनेक्ट करें';

  @override
  String get retry => 'पुनः प्रयास करें';

  @override
  String get import_ => 'आयात करें';

  @override
  String get export_ => 'निर्यात करें';

  @override
  String get rename => 'नाम बदलें';

  @override
  String get create => 'बनाएं';

  @override
  String get back => 'वापस';

  @override
  String get copy => 'कॉपी करें';

  @override
  String get paste => 'पेस्ट करें';

  @override
  String get select => 'चुनें';

  @override
  String get required => 'आवश्यक';

  @override
  String get settings => 'सेटिंग्स';

  @override
  String get appSettings => 'ऐप सेटिंग्स';

  @override
  String get yes => 'हाँ';

  @override
  String get no => 'नहीं';

  @override
  String get importWhatToImport => 'क्या आयात करें:';

  @override
  String get exportWhatToExport => 'क्या निर्यात करें:';

  @override
  String get enterMasterPasswordPrompt => 'मास्टर पासवर्ड दर्ज करें:';

  @override
  String get nextStep => 'अगला';

  @override
  String get includeCredentials => 'पासवर्ड और SSH कुंजियां शामिल करें';

  @override
  String get includePasswords => 'सेशन पासवर्ड';

  @override
  String get embeddedKeys => 'एम्बेडेड कुंजियाँ';

  @override
  String get managerKeys => 'मैनेजर से कुंजियाँ';

  @override
  String get managerKeysMayBeLarge =>
      'मैनेजर कुंजियाँ QR आकार सीमा से अधिक हो सकती हैं';

  @override
  String get qrPasswordWarning =>
      'निर्यात के लिए SSH कुंजियाँ डिफ़ॉल्ट रूप से अक्षम हैं।';

  @override
  String get sshKeysMayBeLarge => 'कुंजियां QR आकार से अधिक हो सकती हैं';

  @override
  String exportTotalSize(String size) {
    return 'कुल आकार: $size';
  }

  @override
  String get qrCredentialsWarning =>
      'पासवर्ड और SSH कुंजियां QR कोड में दिखेंगी';

  @override
  String get qrCredentialsTooLarge =>
      'क्रेडेंशियल QR कोड को बहुत बड़ा बनाते हैं';

  @override
  String get terminal => 'टर्मिनल';

  @override
  String get files => 'फ़ाइलें';

  @override
  String get transfer => 'ट्रांसफ़र';

  @override
  String get open => 'खोलें';

  @override
  String get search => 'खोजें...';

  @override
  String get noResults => 'कोई परिणाम नहीं';

  @override
  String get filter => 'फ़िल्टर...';

  @override
  String get merge => 'मर्ज करें';

  @override
  String get replace => 'बदलें';

  @override
  String get reconnect => 'पुनः कनेक्ट करें';

  @override
  String get updateAvailable => 'अपडेट उपलब्ध';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'संस्करण $version उपलब्ध है (वर्तमान: v$current)।';
  }

  @override
  String get releaseNotes => 'रिलीज़ नोट्स:';

  @override
  String get skipThisVersion => 'यह संस्करण छोड़ें';

  @override
  String get unskip => 'छोड़ना रद्द करें';

  @override
  String get downloadAndInstall => 'डाउनलोड और इंस्टॉल करें';

  @override
  String get openInBrowser => 'ब्राउज़र में खोलें';

  @override
  String get couldNotOpenBrowser =>
      'ब्राउज़र नहीं खुल सका — URL क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get checkForUpdates => 'अपडेट जांचें';

  @override
  String get checkNow => 'अभी जांचें';

  @override
  String get checkForUpdatesOnStartup => 'शुरू होने पर अपडेट जांचें';

  @override
  String get checking => 'जांच रहे हैं...';

  @override
  String get youreUpToDate => 'आप अप टू डेट हैं';

  @override
  String get updateCheckFailed => 'अपडेट जांच विफल';

  @override
  String get unknownError => 'अज्ञात त्रुटि';

  @override
  String downloadingPercent(int percent) {
    return 'डाउनलोड हो रहा है... $percent%';
  }

  @override
  String get downloadComplete => 'डाउनलोड पूर्ण';

  @override
  String get installNow => 'अभी इंस्टॉल करें';

  @override
  String get openReleasePage => 'रिलीज़ पेज खोलें';

  @override
  String get couldNotOpenInstaller => 'इंस्टॉलर नहीं खुल सका';

  @override
  String get installerFailedOpenedReleasePage =>
      'इंस्टॉलर लॉन्च विफल; ब्राउज़र में रिलीज़ पेज खोला गया';

  @override
  String versionAvailable(String version) {
    return 'संस्करण $version उपलब्ध';
  }

  @override
  String currentVersion(String version) {
    return 'वर्तमान: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'SSH कुंजी प्राप्त: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return 'QR से $count सत्र आयात किए गए';
  }

  @override
  String importedSessions(int count) {
    return '$count सत्र आयात किए गए';
  }

  @override
  String importFailed(String error) {
    return 'आयात विफल: $error';
  }

  @override
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count संबद्धताएँ छोड़ी गईं (लक्ष्य अनुपस्थित)',
      one: '$count संबद्धता छोड़ी गई (लक्ष्य अनुपस्थित)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count खराब सत्र छोड़े गए',
      one: '$count खराब सत्र छोड़ा गया',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'सत्र';

  @override
  String get emptyFolders => 'खाली फ़ोल्डर';

  @override
  String get sessionsHeader => 'सत्र';

  @override
  String get savedSessions => 'सहेजे गए सत्र';

  @override
  String get activeConnections => 'सक्रिय कनेक्शन';

  @override
  String get openTabs => 'खुले टैब';

  @override
  String get noSavedSessions => 'कोई सहेजा गया सत्र नहीं';

  @override
  String get addSession => 'सत्र जोड़ें';

  @override
  String get noSessions => 'कोई सत्र नहीं';

  @override
  String get noSessionsToExport => 'निर्यात के लिए कोई सत्र नहीं';

  @override
  String nSelectedCount(int count) {
    return '$count चयनित';
  }

  @override
  String get selectAll => 'सभी चुनें';

  @override
  String get deselectAll => 'सभी हटाएं';

  @override
  String get moveTo => 'यहां ले जाएं...';

  @override
  String get moveToFolder => 'फ़ोल्डर में ले जाएं';

  @override
  String get rootFolder => '/ (मूल)';

  @override
  String get newFolder => 'नया फ़ोल्डर';

  @override
  String get newConnection => 'नया कनेक्शन';

  @override
  String get editConnection => 'कनेक्शन संपादित करें';

  @override
  String get duplicate => 'डुप्लिकेट';

  @override
  String get deleteSession => 'सत्र हटाएं';

  @override
  String get renameFolder => 'फ़ोल्डर का नाम बदलें';

  @override
  String get deleteFolder => 'फ़ोल्डर हटाएं';

  @override
  String get deleteSelected => 'चयनित हटाएं';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return '$parts हटाएं?\n\nयह क्रिया पूर्ववत नहीं की जा सकती।';
  }

  @override
  String nSessions(int count) {
    return '$count सत्र';
  }

  @override
  String nFolders(int count) {
    return '$count फ़ोल्डर';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'फ़ोल्डर \"$name\" हटाएं?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'अंदर के $count सत्र भी हटा दिए जाएंगे।';
  }

  @override
  String deleteSessionConfirm(String name) {
    return '\"$name\" हटाएं?';
  }

  @override
  String get connection => 'कनेक्शन';

  @override
  String get auth => 'प्रमाणीकरण';

  @override
  String get options => 'विकल्प';

  @override
  String get sessionName => 'सत्र का नाम';

  @override
  String get hintMyServer => 'मेरा सर्वर';

  @override
  String get hostRequired => 'होस्ट *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'पोर्ट';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'उपयोगकर्ता नाम *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'पासवर्ड';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'कुंजी पासफ़्रेज़';

  @override
  String get hintOptional => 'वैकल्पिक';

  @override
  String get hidePemText => 'PEM टेक्स्ट छिपाएं';

  @override
  String get pastePemKeyText => 'PEM कुंजी टेक्स्ट पेस्ट करें';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'अभी कोई अतिरिक्त विकल्प नहीं';

  @override
  String get saveAndConnect => 'सहेजें और कनेक्ट करें';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst =>
      'पहले एक कुंजी फ़ाइल या PEM टेक्स्ट प्रदान करें';

  @override
  String get keyTextPem => 'कुंजी टेक्स्ट (PEM)';

  @override
  String get selectKeyFile => 'कुंजी फ़ाइल चुनें';

  @override
  String get clearKeyFile => 'कुंजी फ़ाइल हटाएं';

  @override
  String get authOrDivider => 'या';

  @override
  String get providePasswordOrKey => 'पासवर्ड या SSH कुंजी प्रदान करें';

  @override
  String get quickConnect => 'त्वरित कनेक्ट';

  @override
  String get scanQrCode => 'QR कोड स्कैन करें';

  @override
  String get emptyFolder => 'खाली फ़ोल्डर';

  @override
  String get qrGenerationFailed => 'QR बनाना विफल';

  @override
  String get scanWithCameraApp =>
      'LetsFLUTssh इंस्टॉल किए गए डिवाइस पर\nकिसी भी कैमरा ऐप से स्कैन करें।';

  @override
  String get noPasswordsInQr => 'इस QR कोड में कोई पासवर्ड या कुंजी नहीं है';

  @override
  String get qrContainsCredentialsWarning =>
      'इस QR कोड में क्रेडेंशियल हैं। स्क्रीन को निजी रखें।';

  @override
  String get copyLink => 'लिंक कॉपी करें';

  @override
  String get linkCopied => 'लिंक क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get hostKeyChanged => 'होस्ट कुंजी बदल गई!';

  @override
  String get unknownHost => 'अज्ञात होस्ट';

  @override
  String get hostKeyChangedWarning =>
      'चेतावनी: इस सर्वर की होस्ट कुंजी बदल गई है। यह मैन-इन-द-मिडल हमले का संकेत हो सकता है, या सर्वर पुनः इंस्टॉल किया गया हो सकता है।';

  @override
  String get unknownHostMessage =>
      'इस होस्ट की प्रामाणिकता सत्यापित नहीं की जा सकती। क्या आप कनेक्ट करना जारी रखना चाहते हैं?';

  @override
  String get host => 'होस्ट';

  @override
  String get keyType => 'कुंजी प्रकार';

  @override
  String get fingerprint => 'फ़िंगरप्रिंट';

  @override
  String get fingerprintCopied => 'फ़िंगरप्रिंट कॉपी किया गया';

  @override
  String get copyFingerprint => 'फ़िंगरप्रिंट कॉपी करें';

  @override
  String get acceptAnyway => 'फिर भी स्वीकार करें';

  @override
  String get accept => 'स्वीकार करें';

  @override
  String get importData => 'डेटा आयात करें';

  @override
  String get masterPassword => 'मास्टर पासवर्ड';

  @override
  String get confirmPassword => 'पासवर्ड की पुष्टि करें';

  @override
  String get importModeMergeDescription => 'नए सत्र जोड़ें, मौजूदा रखें';

  @override
  String get importModeReplaceDescription => 'सभी सत्रों को आयातित से बदलें';

  @override
  String errorPrefix(String error) {
    return 'त्रुटि: $error';
  }

  @override
  String get folderName => 'फ़ोल्डर का नाम';

  @override
  String get newName => 'नया नाम';

  @override
  String deleteItems(String names) {
    return '$names हटाएं?';
  }

  @override
  String deleteNItems(int count) {
    return '$count आइटम हटाएं';
  }

  @override
  String deletedItem(String name) {
    return '$name हटाया गया';
  }

  @override
  String deletedNItems(int count) {
    return '$count आइटम हटाए गए';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'फ़ोल्डर बनाने में विफल: $error';
  }

  @override
  String failedToRename(String error) {
    return 'नाम बदलने में विफल: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return '$name हटाने में विफल: $error';
  }

  @override
  String get editPath => 'पथ संपादित करें';

  @override
  String get root => 'मूल';

  @override
  String get controllersNotInitialized => 'कंट्रोलर आरंभ नहीं हुए';

  @override
  String get initializingSftp => 'SFTP आरंभ हो रहा है...';

  @override
  String get clearHistory => 'इतिहास साफ़ करें';

  @override
  String get noTransfersYet => 'अभी कोई ट्रांसफ़र नहीं';

  @override
  String get duplicateTab => 'टैब डुप्लिकेट करें';

  @override
  String get duplicateTabShortcut => 'टैब डुप्लिकेट करें (Ctrl+\\)';

  @override
  String get copyDown => 'नीचे कॉपी करें';

  @override
  String get previous => 'पिछला';

  @override
  String get next => 'अगला';

  @override
  String get closeEsc => 'बंद करें (Esc)';

  @override
  String get closeAll => 'सभी बंद करें';

  @override
  String get closeOthers => 'अन्य बंद करें';

  @override
  String get closeTabsToTheLeft => 'बाईं ओर के टैब बंद करें';

  @override
  String get closeTabsToTheRight => 'दाईं ओर के टैब बंद करें';

  @override
  String get noActiveSession => 'कोई सक्रिय सत्र नहीं';

  @override
  String get createConnectionHint => 'नया कनेक्शन बनाएं या साइडबार से एक चुनें';

  @override
  String get hideSidebar => 'साइडबार छिपाएं (Ctrl+B)';

  @override
  String get showSidebar => 'साइडबार दिखाएं (Ctrl+B)';

  @override
  String get language => 'भाषा';

  @override
  String get languageSystemDefault => 'स्वचालित';

  @override
  String get theme => 'थीम';

  @override
  String get themeDark => 'डार्क';

  @override
  String get themeLight => 'लाइट';

  @override
  String get themeSystem => 'सिस्टम';

  @override
  String get appearance => 'दिखावट';

  @override
  String get connectionSection => 'कनेक्शन';

  @override
  String get transfers => 'ट्रांसफ़र';

  @override
  String get data => 'डेटा';

  @override
  String get logging => 'लॉगिंग';

  @override
  String get updates => 'अपडेट';

  @override
  String get about => 'परिचय';

  @override
  String get resetToDefaults => 'डिफ़ॉल्ट पर रीसेट करें';

  @override
  String get uiScale => 'UI स्केल';

  @override
  String get terminalFontSize => 'टर्मिनल फ़ॉन्ट आकार';

  @override
  String get scrollbackLines => 'स्क्रॉलबैक लाइनें';

  @override
  String get keepAliveInterval => 'कीप-अलाइव अंतराल (सेकंड)';

  @override
  String get sshTimeout => 'SSH टाइमआउट (सेकंड)';

  @override
  String get defaultPort => 'डिफ़ॉल्ट पोर्ट';

  @override
  String get parallelWorkers => 'समानांतर वर्कर';

  @override
  String get maxHistory => 'अधिकतम इतिहास';

  @override
  String get calculateFolderSizes => 'फ़ोल्डर आकार गणना करें';

  @override
  String get exportData => 'डेटा निर्यात करें';

  @override
  String get exportDataSubtitle =>
      'सत्र, कॉन्फ़िग और कुंजियों को एन्क्रिप्टेड .lfs फ़ाइल में सहेजें';

  @override
  String get importDataSubtitle => '.lfs फ़ाइल से डेटा लोड करें';

  @override
  String sshConfigPreviewHostsFound(int count) {
    return '$count होस्ट मिले';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'इस फ़ाइल में कोई आयात योग्य होस्ट नहीं मिला।';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'इनके लिए कुंजी फ़ाइलें नहीं पढ़ी जा सकीं: $hosts. ये होस्ट बिना क्रेडेंशियल के आयात होंगे।';
  }

  @override
  String sshConfigPreviewFolderLabel(String folder) {
    return 'फ़ोल्डर में आयात किया गया: $folder';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'आर्काइव निर्यात करें';

  @override
  String get exportArchiveSubtitle =>
      'सत्र, कॉन्फ़िग और कुंजियों को एन्क्रिप्टेड .lfs फ़ाइल में सहेजें';

  @override
  String get exportQrCode => 'QR कोड निर्यात करें';

  @override
  String get exportQrCodeSubtitle =>
      'चयनित सत्र और कुंजियाँ QR कोड के माध्यम से साझा करें';

  @override
  String get importArchive => 'आर्काइव आयात करें';

  @override
  String get importArchiveSubtitle => '.lfs फ़ाइल से डेटा लोड करें';

  @override
  String get importFromSshDir => '~/.ssh से आयात करें';

  @override
  String get importFromSshDirSubtitle =>
      'कॉन्फ़िग फ़ाइल से होस्ट और/या ~/.ssh से निजी कुंजियाँ चुनें';

  @override
  String get sshDirImportHostsSection => 'कॉन्फ़िग फ़ाइल के होस्ट';

  @override
  String get sshDirImportKeysSection => '~/.ssh की कुंजियाँ';

  @override
  String importSshKeysFound(int count) {
    return '$count कुंजी मिली — चुनें कौन-सी आयात करनी हैं';
  }

  @override
  String get importSshKeysNoneFound => '~/.ssh में कोई निजी कुंजी नहीं मिली।';

  @override
  String get sshKeyAlreadyImported => 'पहले से संग्रह में है';

  @override
  String get setMasterPasswordHint =>
      'आर्काइव को एन्क्रिप्ट करने के लिए मास्टर पासवर्ड सेट करें।';

  @override
  String get passwordsDoNotMatch => 'पासवर्ड मेल नहीं खाते';

  @override
  String get passwordStrengthWeak => 'कमज़ोर';

  @override
  String get passwordStrengthModerate => 'मध्यम';

  @override
  String get passwordStrengthStrong => 'मज़बूत';

  @override
  String get passwordStrengthVeryStrong => 'बहुत मज़बूत';

  @override
  String get tierRecommendedBadge => 'अनुशंसित';

  @override
  String get tierCurrentBadge => 'वर्तमान';

  @override
  String get tierAlternativeBranchLabel => 'विकल्प — OS पर भरोसा न करें';

  @override
  String get tierUpcomingTooltip => 'आगामी संस्करण में आएगा।';

  @override
  String get tierUpcomingNotes =>
      'इस स्तर का अंतर्निहित ढाँचा अभी उपलब्ध नहीं है। पंक्ति दिखाई दे रही है ताकि आपको पता चले कि विकल्प मौजूद है।';

  @override
  String get tierPlaintextLabel => 'सादा टेक्स्ट';

  @override
  String get tierPlaintextSubtitle =>
      'कोई एन्क्रिप्शन नहीं — केवल फ़ाइल अनुमतियाँ';

  @override
  String get tierPlaintextThreat1 =>
      'फ़ाइल सिस्टम एक्सेस वाला कोई भी आपका डेटा पढ़ लेता है';

  @override
  String get tierPlaintextThreat2 =>
      'गलती से सिंक या बैकअप सब कुछ उजागर कर देता है';

  @override
  String get tierPlaintextNotes =>
      'केवल विश्वसनीय, पृथक वातावरण में उपयोग करें।';

  @override
  String get tierKeychainLabel => 'कीचेन';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'कुंजी $keychain में रहती है — लॉन्च पर ऑटो-अनलॉक';
  }

  @override
  String get tierKeychainProtect1 => 'उसी मशीन पर अन्य उपयोगकर्ता';

  @override
  String get tierKeychainProtect2 => 'OS लॉगिन के बिना चुराई गई डिस्क';

  @override
  String get tierKeychainThreat1 => 'आपके OS खाते में चल रहा मैलवेयर';

  @override
  String get tierKeychainThreat2 =>
      'एक हमलावर जो आपके OS लॉगिन पर कब्ज़ा कर लेता है';

  @override
  String get tierKeychainUnavailable =>
      'इस इंस्टॉल पर OS कीचेन उपलब्ध नहीं है।';

  @override
  String get tierKeychainPassProtect1 => 'आपके डेस्क पर बैठा सहकर्मी';

  @override
  String get tierKeychainPassProtect2 => 'अनलॉक एक्सेस वाला एक राहगीर';

  @override
  String get tierKeychainPassThreat1 => 'डिस्क पर फ़ाइल वाला ऑफ़लाइन हमलावर';

  @override
  String get tierKeychainPassThreat2 => 'कीचेन के समान OS-समझौते के जोखिम';

  @override
  String get tierHardwareLabel => 'हार्डवेयर + PIN';

  @override
  String get tierHardwareSubtitle =>
      'हार्डवेयर-बाध्य वॉल्ट + लॉकआउट के साथ छोटा PIN';

  @override
  String get tierHardwareProtect1 =>
      'PIN का ऑफ़लाइन ब्रूट फ़ोर्स (हार्डवेयर रेट-लिमिट)';

  @override
  String get tierHardwareProtect2 => 'डिस्क और कीचेन ब्लॉब चुराना';

  @override
  String get tierHardwareThreat1 => 'सुरक्षित मॉड्यूल पर OS या फ़र्मवेयर CVE';

  @override
  String get tierHardwareThreat2 => 'जबरन बायोमेट्रिक अनलॉक (यदि सक्षम हो)';

  @override
  String get tierParanoidLabel => 'मास्टर पासवर्ड (Paranoid)';

  @override
  String get tierParanoidSubtitle =>
      'लंबा पासवर्ड + Argon2id। कुंजी कभी OS में प्रवेश नहीं करती।';

  @override
  String get tierParanoidProtect1 => 'OS कीचेन समझौता';

  @override
  String get tierParanoidProtect2 =>
      'चुराई गई डिस्क (जब तक आपका पासवर्ड मज़बूत है)';

  @override
  String get tierParanoidThreat1 => 'आपका पासवर्ड पकड़ने वाला कीलॉगर';

  @override
  String get tierParanoidThreat2 =>
      'कमज़ोर पासवर्ड + ऑफ़लाइन Argon2id क्रैकिंग';

  @override
  String get tierParanoidNotes =>
      'इस स्तर पर बायोमेट्रिक डिज़ाइन द्वारा अक्षम है।';

  @override
  String get tierHardwareUnavailable =>
      'इस इंस्टॉल पर हार्डवेयर वॉल्ट उपलब्ध नहीं है।';

  @override
  String get pinLabel => 'पिन';

  @override
  String get l2UnlockTitle => 'पासवर्ड आवश्यक';

  @override
  String get l2UnlockHint => 'जारी रखने के लिए अपना छोटा पासवर्ड दर्ज करें';

  @override
  String get l2WrongPassword => 'गलत पासवर्ड';

  @override
  String get l3UnlockTitle => 'पिन दर्ज करें';

  @override
  String get l3UnlockHint => 'छोटा पिन हार्डवेयर-बाउंड वॉल्ट खोलता है';

  @override
  String get l3WrongPin => 'गलत पिन';

  @override
  String tierCooldownHint(int seconds) {
    return '$seconds सेकंड में फिर कोशिश करें';
  }

  @override
  String exportedTo(String path) {
    return 'निर्यात किया गया: $path';
  }

  @override
  String exportFailed(String error) {
    return 'निर्यात विफल: $error';
  }

  @override
  String get pathToLfsFile => '.lfs फ़ाइल का पथ';

  @override
  String get hintLfsPath => '/path/to/export.lfs';

  @override
  String get browse => 'ब्राउज़ करें';

  @override
  String get shareViaQrCode => 'QR कोड से साझा करें';

  @override
  String get shareViaQrSubtitle =>
      'दूसरे डिवाइस से स्कैन करने के लिए सत्रों को QR कोड में निर्यात करें';

  @override
  String get dataLocation => 'डेटा स्थान';

  @override
  String get pathCopied => 'पथ क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get urlCopied => 'URL क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — SSH/SFTP क्लाइंट';
  }

  @override
  String get sourceCode => 'सोर्स कोड';

  @override
  String get enableLogging => 'लॉगिंग सक्षम करें';

  @override
  String get logIsEmpty => 'लॉग खाली है';

  @override
  String logExportedTo(String path) {
    return 'लॉग निर्यात किया गया: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'लॉग निर्यात विफल: $error';
  }

  @override
  String get logsCleared => 'लॉग साफ़ किए गए';

  @override
  String get copiedToClipboard => 'क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get copyLog => 'लॉग कॉपी करें';

  @override
  String get exportLog => 'लॉग निर्यात करें';

  @override
  String get clearLogs => 'लॉग साफ़ करें';

  @override
  String get local => 'स्थानीय';

  @override
  String get remote => 'रिमोट';

  @override
  String get pickFolder => 'फ़ोल्डर चुनें';

  @override
  String get refresh => 'रिफ़्रेश करें';

  @override
  String get up => 'ऊपर';

  @override
  String get emptyDirectory => 'खाली डायरेक्टरी';

  @override
  String get cancelSelection => 'चयन रद्द करें';

  @override
  String get openSftpBrowser => 'SFTP ब्राउज़र खोलें';

  @override
  String get openSshTerminal => 'SSH टर्मिनल खोलें';

  @override
  String get noActiveFileBrowsers => 'कोई सक्रिय फ़ाइल ब्राउज़र नहीं';

  @override
  String get useSftpFromSessions => 'सत्रों से \"SFTP\" का उपयोग करें';

  @override
  String get anotherInstanceRunning =>
      'LetsFLUTssh का एक अन्य इंस्टेंस पहले से चल रहा है।';

  @override
  String importFailedShort(String error) {
    return 'आयात विफल: $error';
  }

  @override
  String get saveLogAs => 'लॉग इस रूप में सहेजें';

  @override
  String get chooseSaveLocation => 'सहेजने का स्थान चुनें';

  @override
  String get forward => 'आगे';

  @override
  String get name => 'नाम';

  @override
  String get size => 'आकार';

  @override
  String get modified => 'संशोधित';

  @override
  String get mode => 'मोड';

  @override
  String get owner => 'स्वामी';

  @override
  String get connectionError => 'कनेक्शन त्रुटि';

  @override
  String get resizeWindowToViewFiles =>
      'फ़ाइलें देखने के लिए विंडो का आकार बदलें';

  @override
  String get completed => 'पूर्ण';

  @override
  String get connected => 'कनेक्टेड';

  @override
  String get disconnected => 'डिस्कनेक्टेड';

  @override
  String get exit => 'बाहर निकलें';

  @override
  String get exitConfirmation =>
      'सक्रिय सत्र डिस्कनेक्ट हो जाएंगे। बाहर निकलें?';

  @override
  String get hintFolderExample => 'उदा. Production';

  @override
  String get credentialsNotSet => 'क्रेडेंशियल सेट नहीं हैं';

  @override
  String get exportSessionsViaQr => 'QR से सत्र निर्यात करें';

  @override
  String get qrNoCredentialsWarning =>
      'पासवर्ड और SSH कुंजियां शामिल नहीं हैं।\nआयातित सत्रों में क्रेडेंशियल भरने की आवश्यकता होगी।';

  @override
  String get qrTooManyForSingleCode =>
      'एक QR कोड के लिए बहुत अधिक सत्र। कुछ अचयनित करें या .lfs निर्यात का उपयोग करें।';

  @override
  String get qrTooLarge =>
      'बहुत बड़ा — कुछ आइटम अचयनित करें या .lfs फ़ाइल निर्यात का उपयोग करें।';

  @override
  String get exportAll => 'सभी निर्यात करें';

  @override
  String get showQr => 'QR दिखाएं';

  @override
  String get sort => 'क्रमबद्ध करें';

  @override
  String get resizePanelDivider => 'पैनल डिवाइडर का आकार बदलें';

  @override
  String get youreRunningLatest => 'आप नवीनतम संस्करण चला रहे हैं';

  @override
  String get liveLog => 'लाइव लॉग';

  @override
  String transferNItems(int count) {
    return '$count आइटम ट्रांसफ़र करें';
  }

  @override
  String get time => 'समय';

  @override
  String get failed => 'विफल';

  @override
  String get errOperationNotPermitted => 'ऑपरेशन की अनुमति नहीं है';

  @override
  String get errNoSuchFileOrDirectory => 'ऐसी कोई फ़ाइल या डायरेक्टरी नहीं';

  @override
  String get errNoSuchProcess => 'ऐसी कोई प्रक्रिया नहीं';

  @override
  String get errIoError => 'I/O त्रुटि';

  @override
  String get errBadFileDescriptor => 'खराब फ़ाइल डिस्क्रिप्टर';

  @override
  String get errResourceTemporarilyUnavailable =>
      'संसाधन अस्थायी रूप से अनुपलब्ध';

  @override
  String get errOutOfMemory => 'मेमोरी समाप्त';

  @override
  String get errPermissionDenied => 'अनुमति अस्वीकृत';

  @override
  String get errFileExists => 'फ़ाइल पहले से मौजूद है';

  @override
  String get errNotADirectory => 'डायरेक्टरी नहीं है';

  @override
  String get errIsADirectory => 'डायरेक्टरी है';

  @override
  String get errInvalidArgument => 'अमान्य आर्गुमेंट';

  @override
  String get errTooManyOpenFiles => 'बहुत अधिक खुली फ़ाइलें';

  @override
  String get errNoSpaceLeftOnDevice => 'डिवाइस पर कोई स्थान शेष नहीं';

  @override
  String get errReadOnlyFileSystem => 'केवल-पठन फ़ाइल सिस्टम';

  @override
  String get errBrokenPipe => 'टूटा हुआ पाइप';

  @override
  String get errFileNameTooLong => 'फ़ाइल का नाम बहुत लंबा';

  @override
  String get errDirectoryNotEmpty => 'डायरेक्टरी खाली नहीं है';

  @override
  String get errAddressAlreadyInUse => 'पता पहले से उपयोग में है';

  @override
  String get errCannotAssignAddress =>
      'अनुरोधित पता निर्दिष्ट नहीं किया जा सकता';

  @override
  String get errNetworkIsDown => 'नेटवर्क बंद है';

  @override
  String get errNetworkIsUnreachable => 'नेटवर्क पहुंच योग्य नहीं है';

  @override
  String get errConnectionResetByPeer => 'पीयर द्वारा कनेक्शन रीसेट किया गया';

  @override
  String get errConnectionTimedOut => 'कनेक्शन का समय समाप्त';

  @override
  String get errConnectionRefused => 'कनेक्शन अस्वीकृत';

  @override
  String get errHostIsDown => 'होस्ट बंद है';

  @override
  String get errNoRouteToHost => 'होस्ट तक कोई मार्ग नहीं';

  @override
  String get errConnectionAborted => 'कनेक्शन निरस्त';

  @override
  String get errAlreadyConnected => 'पहले से कनेक्टेड';

  @override
  String get errNotConnected => 'कनेक्टेड नहीं';

  @override
  String errSshConnectFailed(String host, int port) {
    return '$host:$port से कनेक्ट करने में विफल';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return '$user@$host के लिए प्रमाणीकरण विफल';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return '$host:$port से कनेक्शन विफल';
  }

  @override
  String get errSshAuthAborted => 'प्रमाणीकरण निरस्त';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return '$host:$port के लिए होस्ट कुंजी अस्वीकृत — होस्ट कुंजी स्वीकार करें या known_hosts जांचें';
  }

  @override
  String get errSshOpenShellFailed => 'शेल खोलने में विफल';

  @override
  String get errSshLoadKeyFileFailed => 'SSH कुंजी फ़ाइल लोड करने में विफल';

  @override
  String get errSshParseKeyFailed => 'PEM कुंजी डेटा पार्स करने में विफल';

  @override
  String get errSshConnectionDisposed => 'कनेक्शन निपटाया गया';

  @override
  String get errSshNotConnected => 'कनेक्टेड नहीं';

  @override
  String get errConnectionFailed => 'कनेक्शन विफल';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return '$seconds सेकंड के बाद कनेक्शन का समय समाप्त';
  }

  @override
  String get errSessionClosed => 'सत्र बंद';

  @override
  String errShellError(String error) {
    return 'शेल त्रुटि: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'पुनः कनेक्ट विफल: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'SFTP आरंभ करने में विफल: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'डाउनलोड विफल: $error';
  }

  @override
  String get errDecryptionFailed =>
      'क्रेडेंशियल डिक्रिप्ट करने में विफल। कुंजी फ़ाइल दूषित हो सकती है।';

  @override
  String get errExportPickerUnavailable =>
      'सिस्टम फ़ोल्डर पिकर उपलब्ध नहीं है। कोई अन्य स्थान आज़माएँ या ऐप संग्रहण अनुमतियाँ जाँचें।';

  @override
  String get biometricUnlockPrompt => 'LetsFLUTssh अनलॉक करें';

  @override
  String get biometricUnlockTitle => 'बायोमेट्रिक से अनलॉक करें';

  @override
  String get biometricUnlockSubtitle =>
      'ऐप शुरू करते समय मास्टर पासवर्ड टाइप करने से बचें।';

  @override
  String get biometricNotAvailable =>
      'इस डिवाइस पर बायोमेट्रिक अनलॉक उपलब्ध नहीं है।';

  @override
  String get biometricEnableFailed =>
      'बायोमेट्रिक अनलॉक चालू नहीं किया जा सका।';

  @override
  String get biometricEnabled => 'बायोमेट्रिक अनलॉक सक्षम';

  @override
  String get biometricDisabled => 'बायोमेट्रिक अनलॉक अक्षम';

  @override
  String get biometricUnlockFailed =>
      'बायोमेट्रिक अनलॉक विफल रहा। अपना मास्टर पासवर्ड दर्ज करें।';

  @override
  String get biometricUnlockCancelled => 'बायोमेट्रिक अनलॉक रद्द कर दिया गया।';

  @override
  String get biometricNotEnrolled =>
      'इस डिवाइस पर कोई बायोमेट्रिक क्रेडेंशियल पंजीकृत नहीं है।';

  @override
  String get biometricRequiresMasterPassword =>
      'बायोमेट्रिक अनलॉक सक्षम करने के लिए पहले एक मास्टर पासवर्ड सेट करें।';

  @override
  String get biometricSensorNotAvailable =>
      'इस डिवाइस पर कोई बायोमेट्रिक सेंसर नहीं है।';

  @override
  String get biometricSystemServiceMissing =>
      'फ़िंगरप्रिंट सेवा (fprintd) स्थापित नहीं है। README → Installation देखें।';

  @override
  String get biometricBackingHardware =>
      'हार्डवेयर-समर्थित (Secure Enclave / TPM)';

  @override
  String get biometricBackingSoftware => 'सॉफ़्टवेयर-समर्थित';

  @override
  String get currentPasswordIncorrect => 'वर्तमान पासवर्ड गलत है';

  @override
  String get wrongPassword => 'गलत पासवर्ड';

  @override
  String get useKeychain => 'OS कीचेन से एन्क्रिप्ट करें';

  @override
  String get useKeychainSubtitle =>
      'डेटाबेस कुंजी को सिस्टम क्रेडेंशियल स्टोर में रखें। बंद = सादा-पाठ डेटाबेस।';

  @override
  String get lockScreenTitle => 'LetsFLUTssh लॉक है';

  @override
  String get lockScreenSubtitle =>
      'जारी रखने के लिए मास्टर पासवर्ड दर्ज करें या बायोमेट्रिक्स का उपयोग करें।';

  @override
  String get unlock => 'अनलॉक करें';

  @override
  String get autoLockTitle => 'निष्क्रियता के बाद ऑटो-लॉक';

  @override
  String get autoLockSubtitle =>
      'इतनी देर निष्क्रिय रहने पर UI लॉक होता है। एन्क्रिप्टेड डेटाबेस तभी पुनः लॉक होता है जब कोई सक्रिय SSH सत्र न हो, ताकि लंबी प्रक्रियाएँ बाधित न हों।';

  @override
  String get autoLockOff => 'बंद';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes मिनट',
      one: '$minutes मिनट',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'अपडेट अस्वीकृत: डाउनलोड की गई फ़ाइलें ऐप में पिन की गई रिलीज़ कुंजी से हस्ताक्षरित नहीं हैं। इसका मतलब यह हो सकता है कि डाउनलोड के दौरान छेड़छाड़ हुई थी, या वर्तमान रिलीज़ इस इंस्टॉलेशन के लिए नहीं है। इंस्टॉल न करें — इसके बजाय आधिकारिक रिलीज़ पेज से मैन्युअल रूप से पुनः इंस्टॉल करें।';

  @override
  String get updateSecurityWarningTitle => 'अपडेट सत्यापन विफल';

  @override
  String get updateReinstallAction => 'रिलीज़ पेज खोलें';

  @override
  String get errLfsNotArchive => 'चयनित फ़ाइल LetsFLUTssh संग्रह नहीं है।';

  @override
  String get errLfsDecryptFailed => 'गलत मास्टर पासवर्ड या दूषित .lfs संग्रह';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'संग्रह बहुत बड़ा है ($sizeMb MB). सीमा $limitMb MB है — मेमोरी की सुरक्षा के लिए डिक्रिप्शन से पहले रोका गया.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'known_hosts प्रविष्टि बहुत बड़ी है ($sizeMb MB). सीमा $limitMb MB है — आयात को उत्तरदायी बनाए रखने के लिए रोका गया.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'आयात विफल — आपका डेटा आयात से पहले की स्थिति में पुनर्स्थापित कर दिया गया है। ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'संग्रह स्कीमा v$found का उपयोग करता है, लेकिन यह बिल्ड केवल v$supported तक समझता है. इसे आयात करने के लिए ऐप अपडेट करें.';
  }

  @override
  String get progressReadingArchive => 'संग्रह पढ़ा जा रहा है…';

  @override
  String get progressDecrypting => 'डिक्रिप्ट किया जा रहा है…';

  @override
  String get progressParsingArchive => 'संग्रह पार्स किया जा रहा है…';

  @override
  String get progressImportingSessions => 'सत्र आयात किए जा रहे हैं';

  @override
  String get progressImportingFolders => 'फ़ोल्डर आयात किए जा रहे हैं';

  @override
  String get progressImportingManagerKeys => 'SSH कुंजियाँ आयात की जा रही हैं';

  @override
  String get progressImportingTags => 'टैग आयात किए जा रहे हैं';

  @override
  String get progressImportingSnippets => 'स्निपेट्स आयात किए जा रहे हैं';

  @override
  String get progressApplyingConfig => 'कॉन्फ़िगरेशन लागू किया जा रहा है…';

  @override
  String get progressImportingKnownHosts => 'known_hosts आयात किया जा रहा है…';

  @override
  String get progressCollectingData => 'डेटा एकत्र किया जा रहा है…';

  @override
  String get progressEncrypting => 'एन्क्रिप्ट किया जा रहा है…';

  @override
  String get progressWritingArchive => 'संग्रह लिखा जा रहा है…';

  @override
  String get progressReencrypting => 'स्टोर फिर से एन्क्रिप्ट किए जा रहे हैं…';

  @override
  String get progressWorking => 'प्रसंस्करण…';

  @override
  String get importFromLink => 'QR लिंक से आयात करें';

  @override
  String get importFromLinkSubtitle =>
      'किसी अन्य डिवाइस से कॉपी किया गया letsflutssh:// डीप-लिंक पेस्ट करें';

  @override
  String get pasteImportLinkTitle => 'आयात लिंक पेस्ट करें';

  @override
  String get pasteImportLinkDescription =>
      'किसी अन्य डिवाइस पर जनरेट किया गया letsflutssh://import?d=… लिंक (या रॉ पेलोड) पेस्ट करें। कैमरे की आवश्यकता नहीं।';

  @override
  String get pasteFromClipboard => 'क्लिपबोर्ड से पेस्ट करें';

  @override
  String get invalidImportLink => 'लिंक में मान्य LetsFLUTssh पेलोड नहीं है';

  @override
  String get importAction => 'आयात करें';

  @override
  String get saveSessionToAssignTags =>
      'टैग असाइन करने के लिए पहले सत्र सहेजें';

  @override
  String get noTagsAssigned => 'कोई टैग असाइन नहीं';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'लॉगिन';

  @override
  String get protocol => 'प्रोटोकॉल';

  @override
  String get typeLabel => 'प्रकार';

  @override
  String get folder => 'फ़ोल्डर';

  @override
  String nSubitems(int count) {
    return '$count आइटम';
  }

  @override
  String get subitems => 'आइटम';

  @override
  String get storagePermissionRequired =>
      'स्थानीय फ़ाइलें ब्राउज़ करने के लिए स्टोरेज अनुमति आवश्यक है';

  @override
  String get grantPermission => 'अनुमति दें';

  @override
  String get storagePermissionLimited =>
      'सीमित पहुँच — सभी फ़ाइलों के लिए पूर्ण स्टोरेज अनुमति दें';

  @override
  String progressConnecting(String host, int port) {
    return '$host:$port से कनेक्ट हो रहा है';
  }

  @override
  String get progressVerifyingHostKey => 'होस्ट कुंजी सत्यापित हो रही है';

  @override
  String progressAuthenticating(String user) {
    return '$user के रूप में प्रमाणीकरण';
  }

  @override
  String get progressOpeningShell => 'शेल खोला जा रहा है';

  @override
  String get progressOpeningSftp => 'SFTP चैनल खोला जा रहा है';

  @override
  String get transfersLabel => 'स्थानांतरण:';

  @override
  String transferCountActive(int count) {
    return '$count सक्रिय';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count कतार में';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count इतिहास में';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'बनाया गया: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'शुरू: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'समाप्त: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'अवधि: $duration';
  }

  @override
  String get transferStatusQueued => 'कतार में';

  @override
  String get transferStartingUpload => 'अपलोड शुरू हो रहा है...';

  @override
  String get transferStartingDownload => 'डाउनलोड शुरू हो रहा है...';

  @override
  String get transferCopying => 'कॉपी हो रहा है...';

  @override
  String get transferDone => 'पूर्ण';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total फ़ाइलें';
  }

  @override
  String get fileConflictTitle => 'फ़ाइल पहले से मौजूद है';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" पहले से $targetDir में मौजूद है। आप क्या करना चाहते हैं?';
  }

  @override
  String get fileConflictSkip => 'छोड़ें';

  @override
  String get fileConflictKeepBoth => 'दोनों रखें';

  @override
  String get fileConflictReplace => 'बदलें';

  @override
  String get fileConflictApplyAll => 'सभी शेष पर लागू करें';

  @override
  String get folderNameLabel => 'फ़ोल्डर का नाम';

  @override
  String folderAlreadyExists(String name) {
    return 'फ़ोल्डर \"$name\" पहले से मौजूद है';
  }

  @override
  String get dropKeyFileHere => 'कुंजी फ़ाइल यहाँ छोड़ें';

  @override
  String get sessionNoCredentials =>
      'सत्र में क्रेडेंशियल नहीं हैं — पासवर्ड या कुंजी जोड़ने के लिए इसे संपादित करें';

  @override
  String dragItemCount(int count) {
    return '$count आइटम';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'सभी चुनें ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'आकार: $size KB / अधिकतम $max KB';
  }

  @override
  String get noActiveTerminals => 'कोई सक्रिय टर्मिनल नहीं';

  @override
  String get connectFromSessionsTab => 'सत्र टैब से कनेक्ट करें';

  @override
  String fileNotFound(String path) {
    return 'फ़ाइल नहीं मिली: $path';
  }

  @override
  String get sshConnectionChannel => 'SSH कनेक्शन';

  @override
  String get sshConnectionChannelDesc =>
      'SSH कनेक्शन को पृष्ठभूमि में सक्रिय रखता है।';

  @override
  String get sshActive => 'SSH सक्रिय';

  @override
  String activeConnectionCount(int count) {
    return '$count सक्रिय कनेक्शन';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count आइटम, $size';
  }

  @override
  String get maximize => 'अधिकतम करें';

  @override
  String get restore => 'पुनर्स्थापित करें';

  @override
  String get duplicateDownShortcut => 'नीचे डुप्लिकेट करें (Ctrl+Shift+\\)';

  @override
  String get security => 'सुरक्षा';

  @override
  String get knownHosts => 'ज्ञात होस्ट';

  @override
  String get knownHostsSubtitle =>
      'विश्वसनीय SSH सर्वर फ़िंगरप्रिंट प्रबंधित करें';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ज्ञात होस्ट',
      one: '1 ज्ञात होस्ट',
      zero: 'कोई ज्ञात होस्ट नहीं',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'कोई ज्ञात होस्ट नहीं। एक जोड़ने के लिए सर्वर से कनेक्ट करें।';

  @override
  String get removeHost => 'होस्ट हटाएं';

  @override
  String removeHostConfirm(String host) {
    return 'ज्ञात होस्ट से $host हटाएं? अगले कनेक्शन पर कुंजी की पुनः पुष्टि की जाएगी।';
  }

  @override
  String get clearAllKnownHosts => 'सभी ज्ञात होस्ट साफ़ करें';

  @override
  String get clearAllKnownHostsConfirm =>
      'सभी ज्ञात होस्ट हटाएं? प्रत्येक सर्वर कुंजी की पुनः पुष्टि करनी होगी।';

  @override
  String get importKnownHostsSubtitle =>
      'OpenSSH known_hosts फ़ाइल से आयात करें';

  @override
  String get clearedAllHosts => 'सभी ज्ञात होस्ट साफ़ किए गए';

  @override
  String removedHost(String host) {
    return '$host हटाया गया';
  }

  @override
  String get tools => 'उपकरण';

  @override
  String get sshKeys => 'SSH कुंजियाँ';

  @override
  String get sshKeysSubtitle =>
      'प्रमाणीकरण के लिए SSH कुंजी जोड़ी प्रबंधित करें';

  @override
  String get noKeys => 'कोई SSH कुंजी नहीं। आयात करें या जनरेट करें।';

  @override
  String get generateKey => 'कुंजी जनरेट करें';

  @override
  String get importKey => 'कुंजी आयात करें';

  @override
  String get keyLabel => 'कुंजी का नाम';

  @override
  String get keyLabelHint => 'जैसे कार्य सर्वर, GitHub';

  @override
  String get selectKeyType => 'कुंजी प्रकार';

  @override
  String get generating => 'जनरेट हो रहा है...';

  @override
  String keyGenerated(String label) {
    return 'कुंजी जनरेट हुई: $label';
  }

  @override
  String keyImported(String label) {
    return 'कुंजी आयात हुई: $label';
  }

  @override
  String get deleteKey => 'कुंजी हटाएं';

  @override
  String deleteKeyConfirm(String label) {
    return 'कुंजी \"$label\" हटाएं? इसका उपयोग करने वाले सत्र पहुँच खो देंगे।';
  }

  @override
  String keyDeleted(String label) {
    return 'कुंजी हटाई गई: $label';
  }

  @override
  String get publicKey => 'सार्वजनिक कुंजी';

  @override
  String get publicKeyCopied => 'सार्वजनिक कुंजी क्लिपबोर्ड पर कॉपी की गई';

  @override
  String get pastePrivateKey => 'निजी कुंजी चिपकाएं (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'अमान्य PEM कुंजी डेटा';

  @override
  String get selectFromKeyStore => 'कुंजी भंडार से चुनें';

  @override
  String get noKeySelected => 'कोई कुंजी नहीं चुनी गई';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count कुंजियाँ',
      one: '1 कुंजी',
      zero: 'कोई कुंजी नहीं',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'जनरेट की गई';

  @override
  String get passphraseRequired => 'पासफ़्रेज़ आवश्यक';

  @override
  String passphrasePrompt(String host) {
    return '$host की SSH कुंजी एन्क्रिप्टेड है। अनलॉक करने के लिए पासफ़्रेज़ दर्ज करें।';
  }

  @override
  String get passphraseWrong => 'गलत पासफ़्रेज़। कृपया पुनः प्रयास करें।';

  @override
  String get passphrase => 'पासफ़्रेज़';

  @override
  String get rememberPassphrase => 'इस सत्र के लिए याद रखें';

  @override
  String get masterPasswordSubtitle =>
      'सहेजे गए क्रेडेंशियल को पासवर्ड से सुरक्षित करें';

  @override
  String get setMasterPassword => 'मास्टर पासवर्ड सेट करें';

  @override
  String get changeMasterPassword => 'मास्टर पासवर्ड बदलें';

  @override
  String get removeMasterPassword => 'मास्टर पासवर्ड हटाएं';

  @override
  String get masterPasswordEnabled =>
      'क्रेडेंशियल मास्टर पासवर्ड से सुरक्षित हैं';

  @override
  String get masterPasswordDisabled =>
      'क्रेडेंशियल स्वचालित रूप से जनरेट की गई कुंजी का उपयोग करते हैं (पासवर्ड नहीं)';

  @override
  String get enterMasterPassword =>
      'सहेजे गए क्रेडेंशियल तक पहुँचने के लिए मास्टर पासवर्ड दर्ज करें।';

  @override
  String get wrongMasterPassword => 'गलत पासवर्ड। कृपया पुनः प्रयास करें।';

  @override
  String get newPassword => 'नया पासवर्ड';

  @override
  String get currentPassword => 'वर्तमान पासवर्ड';

  @override
  String get masterPasswordSet => 'मास्टर पासवर्ड सक्रिय किया गया';

  @override
  String get masterPasswordChanged => 'मास्टर पासवर्ड बदला गया';

  @override
  String get masterPasswordRemoved => 'मास्टर पासवर्ड हटाया गया';

  @override
  String get masterPasswordWarning =>
      'यदि आप यह पासवर्ड भूल जाते हैं, तो सभी सहेजे गए पासवर्ड और SSH कुंजियाँ खो जाएंगी। पुनर्प्राप्ति संभव नहीं है।';

  @override
  String get forgotPassword => 'पासवर्ड भूल गए?';

  @override
  String get forgotPasswordWarning =>
      'यह सभी सहेजे गए पासवर्ड, SSH कुंजियाँ और पासफ़्रेज़ हटा देगा। सत्र और सेटिंग्स बनी रहेंगी। यह क्रिया पूर्ववत नहीं की जा सकती।';

  @override
  String get resetAndDeleteCredentials => 'रीसेट करें और डेटा हटाएं';

  @override
  String get credentialsReset => 'सभी सहेजे गए क्रेडेंशियल हटा दिए गए';

  @override
  String get legacyKdfTitle => 'सुरक्षा अपग्रेड आवश्यक';

  @override
  String get legacyKdfBody =>
      'यह इंस्टॉल आपके मास्टर पासवर्ड को एक पुराने की-डेरिवेशन एल्गोरिदम (PBKDF2) से सुरक्षित रखता है। इसे Argon2id से बदल दिया गया है, जो GPU/ASIC से क्रैकिंग के विरुद्ध बहुत अधिक मजबूत प्रतिरोध प्रदान करता है। नया प्रारूप पुराने के साथ संगत नहीं है, इसलिए पुरानी सॉल्ट फ़ाइल को स्वचालित रूप से स्थानांतरित नहीं किया जा सकता।';

  @override
  String get legacyKdfWarning =>
      '«रीसेट करें और जारी रखें» चुनने से सभी सहेजे गए क्रेडेंशियल (पासवर्ड, SSH कुंजियाँ, ज्ञात होस्ट) स्थायी रूप से हटा दिए जाएँगे। आपके सत्र और सेटिंग्स सुरक्षित रहेंगी। यदि आपको अपने क्रेडेंशियल पुनर्प्राप्त करने की आवश्यकता है, तो ऐप बंद करें और अपना डेटा पहले निर्यात करने के लिए LetsFLUTssh का पिछला संस्करण पुनः इंस्टॉल करें।';

  @override
  String get legacyKdfResetContinue => 'रीसेट करें और जारी रखें';

  @override
  String get legacyKdfExit => 'LetsFLUTssh बंद करें';

  @override
  String get dbCorruptTitle => 'डेटाबेस नहीं खोला जा सकता';

  @override
  String get dbCorruptBody =>
      'डिस्क पर एन्क्रिप्टेड डेटाबेस इस इंस्टॉल के दर्ज सुरक्षा स्तर से मेल नहीं खाता। आमतौर पर इसका मतलब है कि पिछला सेटअप बाधित हुआ था या डेटा किसी भिन्न सिफर वाले बिल्ड से है।\n\nLetsFLUTssh तब तक जारी नहीं रह सकता जब तक डेटाबेस मेल खाते बिल्ड की सही प्रमाणिकाओं से नहीं खोला जाता या मिटाकर नए सिरे से सेट नहीं किया जाता।';

  @override
  String get dbCorruptWarning =>
      'रीसेट एन्क्रिप्टेड डेटाबेस और सुरक्षा संबंधी सभी फ़ाइलें स्थायी रूप से हटा देगा। कोई डेटा पुनर्प्राप्त नहीं होगा।';

  @override
  String get dbCorruptTryOther => 'दूसरी प्रमाणिकाएँ आज़माएँ';

  @override
  String get dbCorruptResetContinue => 'रीसेट और नया सेटअप';

  @override
  String get dbCorruptExit => 'LetsFLUTssh से बाहर निकलें';

  @override
  String get tierResetTitle => 'सुरक्षा रीसेट आवश्यक';

  @override
  String get tierResetBody =>
      'इस इंस्टॉल में LetsFLUTssh के पुराने संस्करण से सुरक्षा डेटा मौजूद है जो अलग टियर मॉडल का उपयोग करता था। नया मॉडल एक असंगत परिवर्तन है — कोई स्वचालित माइग्रेशन पथ नहीं है। जारी रखने के लिए, इस इंस्टॉल के सभी सहेजे गए सत्र, क्रेडेंशियल, SSH कुंजियाँ और ज्ञात होस्ट मिटाने होंगे और पहले-लॉन्च सेटअप विज़ार्ड नए सिरे से चलाना होगा।';

  @override
  String get tierResetWarning =>
      '«रीसेट करें और नए सिरे से सेटअप करें» चुनने से एन्क्रिप्टेड डेटाबेस और हर सुरक्षा-संबंधित फ़ाइल स्थायी रूप से हट जाएगी। यदि आपको अपना डेटा पुनर्प्राप्त करने की आवश्यकता है, तो अभी ऐप बंद करें और पहले निर्यात करने के लिए LetsFLUTssh का पिछला संस्करण पुनः इंस्टॉल करें।';

  @override
  String get tierResetResetContinue => 'रीसेट करें और नए सिरे से सेटअप करें';

  @override
  String get tierResetExit => 'LetsFLUTssh बंद करें';

  @override
  String get derivingKey => 'एन्क्रिप्शन कुंजी बनाई जा रही है...';

  @override
  String get reEncrypting => 'डेटा पुनः एन्क्रिप्ट हो रहा है...';

  @override
  String get confirmRemoveMasterPassword =>
      'मास्टर पासवर्ड सुरक्षा हटाने के लिए वर्तमान पासवर्ड दर्ज करें। क्रेडेंशियल स्वचालित कुंजी से पुनः एन्क्रिप्ट होंगे।';

  @override
  String get securitySetupTitle => 'सुरक्षा सेटअप';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'OS कीचेन पाया गया ($keychainName)। आपका डेटा सिस्टम कीचेन का उपयोग करके स्वचालित रूप से एन्क्रिप्ट किया जाएगा।';
  }

  @override
  String get securitySetupKeychainOptional =>
      'अतिरिक्त सुरक्षा के लिए मास्टर पासवर्ड भी सेट कर सकते हैं।';

  @override
  String get securitySetupNoKeychain =>
      'OS कीचेन नहीं पाया गया। कीचेन के बिना, सत्र डेटा (होस्ट, पासवर्ड, कुंजियाँ) सादे पाठ में संग्रहीत होगा।';

  @override
  String get securitySetupNoKeychainHint =>
      'WSL, हेडलेस Linux या न्यूनतम इंस्टॉलेशन में यह सामान्य है। Linux पर कीचेन सक्षम करने के लिए: libsecret और कीरिंग डेमन (जैसे gnome-keyring) इंस्टॉल करें।';

  @override
  String get securitySetupRecommendMasterPassword =>
      'अपने डेटा की सुरक्षा के लिए मास्टर पासवर्ड सेट करने की सिफारिश की जाती है।';

  @override
  String get continueWithKeychain => 'कीचेन के साथ जारी रखें';

  @override
  String get continueWithoutEncryption => 'एन्क्रिप्शन के बिना जारी रखें';

  @override
  String get securityLevel => 'सुरक्षा स्तर';

  @override
  String get securityLevelPlaintext => 'कोई नहीं';

  @override
  String get securityLevelKeychain => 'OS कीचेन';

  @override
  String get securityLevelMasterPassword => 'मास्टर पासवर्ड';

  @override
  String get keychainStatus => 'कीचेन';

  @override
  String get keychainAvailable => 'उपलब्ध';

  @override
  String get keychainNotAvailable => 'अनुपलब्ध';

  @override
  String get enableKeychain => 'कीचेन एन्क्रिप्शन सक्षम करें';

  @override
  String get enableKeychainSubtitle =>
      'OS कीचेन का उपयोग करके संग्रहीत डेटा को पुनः एन्क्रिप्ट करें';

  @override
  String get keychainEnabled => 'कीचेन एन्क्रिप्शन सक्षम';

  @override
  String get manageMasterPassword => 'मास्टर पासवर्ड प्रबंधित करें';

  @override
  String get manageMasterPasswordSubtitle =>
      'मास्टर पासवर्ड सेट, बदलें या हटाएं';

  @override
  String get changeSecurityTier => 'सुरक्षा स्तर बदलें';

  @override
  String get changeSecurityTierSubtitle =>
      'स्तर सीढ़ी खोलें और अलग सुरक्षा स्तर पर जाएँ';

  @override
  String get changeSecurityTierConfirm =>
      'नए स्तर से डेटाबेस फिर से एन्क्रिप्ट हो रहा है। बीच में नहीं रोका जा सकता — समाप्त होने तक ऐप खुला रखें।';

  @override
  String get changeSecurityTierDone => 'सुरक्षा स्तर बदला गया';

  @override
  String get changeSecurityTierFailed => 'सुरक्षा स्तर नहीं बदला जा सका';

  @override
  String get firstLaunchSecurityTitle => 'सुरक्षित स्टोरेज सक्षम है';

  @override
  String get firstLaunchSecurityBody =>
      'आपका डेटा OS कीचेन में रखी गई कुंजी से एन्क्रिप्ट किया गया है। इस डिवाइस पर अनलॉक स्वचालित है।';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'इस डिवाइस पर हार्डवेयर-आधारित स्टोरेज उपलब्ध है। TPM / Secure Enclave बाइंडिंग के लिए सेटिंग्स → सुरक्षा से अपग्रेड करें।';

  @override
  String get firstLaunchSecurityHardwareUnavailableWindows =>
      'हार्डवेयर-आधारित स्टोरेज उपलब्ध नहीं है — इस डिवाइस पर TPM 2.0 नहीं मिला।';

  @override
  String get firstLaunchSecurityHardwareUnavailableApple =>
      'हार्डवेयर-आधारित स्टोरेज उपलब्ध नहीं है — यह डिवाइस Secure Enclave की रिपोर्ट नहीं करता।';

  @override
  String get firstLaunchSecurityHardwareUnavailableLinux =>
      'हार्डवेयर-आधारित स्टोरेज उपलब्ध नहीं है — इसे सक्षम करने के लिए tpm2-tools और TPM 2.0 डिवाइस स्थापित करें।';

  @override
  String get firstLaunchSecurityHardwareUnavailableAndroid =>
      'हार्डवेयर-आधारित स्टोरेज उपलब्ध नहीं है — यह डिवाइस StrongBox या TEE की रिपोर्ट नहीं करता।';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'इस डिवाइस पर हार्डवेयर-आधारित स्टोरेज उपलब्ध नहीं है।';

  @override
  String get firstLaunchSecurityOpenSettings => 'सेटिंग्स खोलें';

  @override
  String get firstLaunchSecurityDismiss => 'समझ गया';

  @override
  String get securityHardwareUpgradeTitle => 'हार्डवेयर-आधारित स्टोरेज उपलब्ध';

  @override
  String get securityHardwareUpgradeBody =>
      'रहस्यों को TPM / Secure Enclave से बाँधने के लिए अपग्रेड करें।';

  @override
  String get securityHardwareUpgradeAction => 'अपग्रेड करें';

  @override
  String get securityHardwareUnavailableTitle =>
      'हार्डवेयर-आधारित स्टोरेज उपलब्ध नहीं';

  @override
  String get wizardReducedBanner =>
      'इस इंस्टॉलेशन में OS कीचेन उपलब्ध नहीं है। कोई एन्क्रिप्शन नहीं (T0) और मास्टर पासवर्ड (Paranoid) में से चुनें। Keychain स्तर सक्षम करने के लिए gnome-keyring, kwallet या कोई अन्य libsecret प्रदाता स्थापित करें।';

  @override
  String get tierBlockProtectsHeader => 'इनसे बचाता है';

  @override
  String get tierBlockDoesNotProtectHeader => 'इनसे नहीं बचाता';

  @override
  String get tierBlockProtectsEmpty => 'इस स्तर पर कुछ नहीं।';

  @override
  String get tierBlockDoesNotProtectEmpty => 'कोई खुला खतरा नहीं।';

  @override
  String get tierBadgeCurrent => 'वर्तमान';

  @override
  String get securitySetupEnable => 'सक्षम करें';

  @override
  String get securitySetupApply => 'लागू करें';

  @override
  String get passwordDisabledPlaintext =>
      'सादा स्तर कोई रहस्य नहीं रखता जिसे पासवर्ड से बचाया जा सके।';

  @override
  String get passwordDisabledParanoid =>
      'Paranoid पासवर्ड से डीबी कुंजी निकालता है — हमेशा चालू।';

  @override
  String get passwordSubtitleOn => 'चालू — अनलॉक पर पासवर्ड आवश्यक';

  @override
  String get passwordSubtitleOff =>
      'बंद — इस स्तर पर पासवर्ड जोड़ने के लिए टैप करें';

  @override
  String get passwordSubtitleParanoid =>
      'आवश्यक — मास्टर पासवर्ड ही स्तर का रहस्य है';

  @override
  String get passwordSubtitlePlaintext =>
      'लागू नहीं — इस स्तर में कोई एन्क्रिप्शन नहीं';

  @override
  String get snippets => 'स्निपेट्स';

  @override
  String get snippetsSubtitle => 'पुन: प्रयोज्य कमांड स्निपेट प्रबंधित करें';

  @override
  String get noSnippets => 'अभी तक कोई स्निपेट नहीं';

  @override
  String get addSnippet => 'स्निपेट जोड़ें';

  @override
  String get editSnippet => 'स्निपेट संपादित करें';

  @override
  String get deleteSnippet => 'स्निपेट हटाएँ';

  @override
  String deleteSnippetConfirm(String title) {
    return 'स्निपेट \"$title\" हटाएँ?';
  }

  @override
  String get snippetTitle => 'शीर्षक';

  @override
  String get snippetTitleHint => 'उदा. डिप्लॉय, सेवा पुनरारंभ';

  @override
  String get snippetCommand => 'कमांड';

  @override
  String get snippetCommandHint => 'उदा. sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'विवरण (वैकल्पिक)';

  @override
  String get snippetDescriptionHint => 'यह कमांड क्या करती है?';

  @override
  String get snippetSaved => 'स्निपेट सहेजा गया';

  @override
  String snippetDeleted(String title) {
    return 'स्निपेट \"$title\" हटाया गया';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count स्निपेट',
      one: '1 स्निपेट',
      zero: 'कोई स्निपेट नहीं',
    );
    return '$_temp0';
  }

  @override
  String get runSnippet => 'चलाएँ';

  @override
  String get pinToSession => 'इस सत्र पर पिन करें';

  @override
  String get unpinFromSession => 'इस सत्र से अनपिन करें';

  @override
  String get pinnedSnippets => 'पिन किए गए';

  @override
  String get allSnippets => 'सभी';

  @override
  String get sendToTerminal => 'टर्मिनल पर भेजें';

  @override
  String get commandCopied => 'कमांड कॉपी की गई';

  @override
  String get tags => 'टैग';

  @override
  String get tagsSubtitle => 'रंगीन टैग के साथ सत्र और फ़ोल्डर व्यवस्थित करें';

  @override
  String get noTags => 'अभी तक कोई टैग नहीं';

  @override
  String get addTag => 'टैग जोड़ें';

  @override
  String get deleteTag => 'टैग हटाएँ';

  @override
  String deleteTagConfirm(String name) {
    return 'टैग \"$name\" हटाएँ? यह सभी सत्रों और फ़ोल्डरों से हटा दिया जाएगा।';
  }

  @override
  String get tagName => 'टैग का नाम';

  @override
  String get tagNameHint => 'उदा. Production, Staging';

  @override
  String get tagColor => 'रंग';

  @override
  String get tagCreated => 'टैग बनाया गया';

  @override
  String tagDeleted(String name) {
    return 'टैग \"$name\" हटाया गया';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count टैग',
      one: '1 टैग',
      zero: 'कोई टैग नहीं',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'टैग प्रबंधित करें';

  @override
  String get editTags => 'टैग संपादित करें';

  @override
  String get fullBackup => 'पूर्ण बैकअप';

  @override
  String get sessionsOnly => 'सत्र';

  @override
  String get sessionKeysFromManager => 'प्रबंधक से सत्र कुंजियाँ';

  @override
  String get allKeysFromManager => 'प्रबंधक से सभी कुंजियाँ';

  @override
  String exportTags(int count) {
    return 'टैग ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'स्निपेट ($count)';
  }

  @override
  String get disableKeychain => 'कीचेन एन्क्रिप्शन अक्षम करें';

  @override
  String get disableKeychainSubtitle =>
      'सादा पाठ संग्रहण पर स्विच करें (अनुशंसित नहीं)';

  @override
  String get disableKeychainConfirm =>
      'डेटाबेस को बिना कुंजी के फिर से एन्क्रिप्ट किया जाएगा। सत्र और कुंजियाँ डिस्क पर सादे पाठ में संग्रहीत की जाएँगी। जारी रखें?';

  @override
  String get keychainDisabled => 'कीचेन एन्क्रिप्शन अक्षम किया गया';

  @override
  String get presetFullImport => 'पूर्ण आयात';

  @override
  String get presetSelective => 'चयनात्मक';

  @override
  String get presetCustom => 'कस्टम';

  @override
  String get sessionSshKeys => 'सत्र की SSH कुंजियाँ';

  @override
  String get allManagerKeys => 'प्रबंधक की सभी कुंजियाँ';

  @override
  String get browseFiles => 'फ़ाइल चुनें…';

  @override
  String get sshDirSessionAlreadyImported => 'सत्रों में पहले से है';

  @override
  String get languageSubtitle => 'इंटरफ़ेस की भाषा';

  @override
  String get themeSubtitle => 'डार्क, लाइट या सिस्टम के अनुसार';

  @override
  String get uiScaleSubtitle => 'पूरे इंटरफ़ेस को स्केल करें';

  @override
  String get terminalFontSizeSubtitle => 'टर्मिनल आउटपुट में फ़ॉन्ट आकार';

  @override
  String get scrollbackLinesSubtitle => 'टर्मिनल इतिहास बफ़र का आकार';

  @override
  String get keepAliveIntervalSubtitle =>
      'SSH keep-alive पैकेट के बीच सेकंड (0 = बंद)';

  @override
  String get sshTimeoutSubtitle => 'कनेक्शन टाइमआउट सेकंडों में';

  @override
  String get defaultPortSubtitle => 'नए सत्रों के लिए डिफ़ॉल्ट पोर्ट';

  @override
  String get parallelWorkersSubtitle => 'समानांतर SFTP ट्रांसफ़र वर्कर्स';

  @override
  String get maxHistorySubtitle => 'इतिहास में अधिकतम सहेजी गई कमांड्स';

  @override
  String get calculateFolderSizesSubtitle =>
      'साइडबार में फ़ोल्डर के बगल में कुल आकार दिखाएँ';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'ऐप शुरू होने पर GitHub से नया संस्करण जाँचें';

  @override
  String get enableLoggingSubtitle =>
      'ऐप की घटनाओं को एक रोटेटिंग लॉग फ़ाइल में लिखें';

  @override
  String get exportWithoutPassword => 'पासवर्ड के बिना निर्यात करें?';

  @override
  String get exportWithoutPasswordWarning =>
      'संग्रह एन्क्रिप्ट नहीं किया जाएगा। फ़ाइल तक पहुंच रखने वाला कोई भी व्यक्ति आपके डेटा को पढ़ सकता है, जिसमें पासवर्ड और निजी कुंजियां शामिल हैं।';

  @override
  String get continueWithoutPassword => 'बिना पासवर्ड के जारी रखें';

  @override
  String get threatColdDiskTheft => 'बंद डिस्क की चोरी';

  @override
  String get threatColdDiskTheftDescription =>
      'बंद मशीन से ड्राइव निकालकर किसी दूसरे कंप्यूटर पर पढ़ी जाए, या आपके होम डायरेक्टरी तक पहुँच रखने वाले किसी व्यक्ति द्वारा डेटाबेस फ़ाइल की नकल ले ली जाए।';

  @override
  String get threatBystanderUnlockedMachine => 'अनलॉक मशीन पर मौजूद अजनबी';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'जब आप दूर होते हैं, कोई आपकी पहले से अनलॉक मशीन के पास आकर ऐप खोल लेता है।';

  @override
  String get threatSameUserMalware => 'उसी उपयोगकर्ता खाते का मैलवेयर';

  @override
  String get threatSameUserMalwareDescription =>
      'आपके अपने उपयोगकर्ता खाते के अंतर्गत चलती एक हानिकारक प्रक्रिया। इसकी फ़ाइलों, कीचेन और मेमोरी तक वही पहुँच होती है जो इस ऐप की है — किसी भी समझौता किए गए होस्ट पर कोई भी टीयर इससे बचाव नहीं करता।';

  @override
  String get threatLiveProcessMemoryDump => 'चालू प्रक्रिया का मेमोरी डंप';

  @override
  String get threatLiveProcessMemoryDumpDescription =>
      'डिबगर या ptrace पहुँच वाला हमलावर अनलॉक किए गए डेटाबेस कुंजी को सीधे चालू ऐप की मेमोरी से पढ़ लेता है।';

  @override
  String get threatLiveRamForensicsLocked => 'लॉक मशीन पर RAM फ़ोरेंसिक';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'हमलावर RAM को फ़्रीज़ करता है (या DMA के ज़रिए कैप्चर करता है) और ऐप लॉक होने पर भी स्नैपशॉट से अब भी मौजूद कुंजी सामग्री निकाल लेता है।';

  @override
  String get threatOsKernelOrKeychainBreach => 'OS कर्नल या कीचेन की सेंधमारी';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'कर्नल की कमज़ोरी, कीचेन से डेटा बाहर निकालना, या हार्डवेयर सुरक्षा चिप में बैकडोर। ऑपरेटिंग सिस्टम विश्वसनीय संसाधन के बजाय स्वयं हमलावर बन जाता है।';

  @override
  String get threatOfflineBruteForce =>
      'कमज़ोर पासवर्ड पर ऑफ़लाइन ब्रूट फ़ोर्स';

  @override
  String get threatOfflineBruteForceDescription =>
      'रैप की गई कुंजी या सील्ड ब्लॉब की प्रति रखने वाला हमलावर किसी दर-सीमक के बिना, अपनी गति से हर पासवर्ड आज़माता है।';

  @override
  String get legendProtects => 'सुरक्षित';

  @override
  String get legendDoesNotProtect => 'सुरक्षित नहीं';

  @override
  String get legendNotApplicable =>
      'लागू नहीं — इस टीयर के लिए कोई उपयोगकर्ता गुप्त नहीं है';

  @override
  String get legendWeakPasswordWarning =>
      'कमज़ोर पासवर्ड स्वीकार्य — सुरक्षा का भार कोई और परत (हार्डवेयर दर-सीमक या रैप की गई कुंजी की बाइंडिंग) उठाती है';

  @override
  String get legendStrongPasswordRecommended =>
      'एक लंबा पासफ़्रेज़ अत्यधिक अनुशंसित है — इस टीयर की सुरक्षा इस पर निर्भर है';

  @override
  String get colT0 => 'T0 सादा पाठ';

  @override
  String get colT1 => 'T1 कीचेन';

  @override
  String get colT1Password => 'T1 + पासवर्ड';

  @override
  String get colT1PasswordBiometric => 'T1 + पासवर्ड + बायोमेट्रिक';

  @override
  String get colT2 => 'T2 हार्डवेयर';

  @override
  String get colT2Password => 'T2 + पासवर्ड';

  @override
  String get colT2PasswordBiometric => 'T2 + पासवर्ड + बायोमेट्रिक';

  @override
  String get colParanoid => 'पैरानॉइड';

  @override
  String get securityComparisonTableTitle => 'सुरक्षा टीयर — आमने-सामने तुलना';

  @override
  String get securityComparisonTableThreatColumn => 'ख़तरा';

  @override
  String get compareAllTiers => 'सभी टीयर की तुलना करें';

  @override
  String get resetAllDataTitle => 'सभी डेटा रीसेट करें';

  @override
  String get resetAllDataSubtitle =>
      'सभी सत्र, कुंजियाँ, कॉन्फ़िगरेशन और सुरक्षा आर्टिफ़ैक्ट हटाएँ। कीचेन प्रविष्टियाँ और हार्डवेयर-वॉल्ट स्लॉट भी साफ़ करता है।';

  @override
  String get resetAllDataConfirmTitle => 'सभी डेटा रीसेट करें?';

  @override
  String get resetAllDataConfirmBody =>
      'सभी सत्र, SSH कुंजियाँ, known hosts, स्निपेट, टैग, वरीयताएँ और सभी सुरक्षा आर्टिफ़ैक्ट (कीचेन प्रविष्टियाँ, हार्डवेयर-वॉल्ट डेटा, बायोमेट्रिक ओवरले) स्थायी रूप से हटा दिए जाएँगे। इसे पूर्ववत नहीं किया जा सकता।';

  @override
  String get resetAllDataConfirmAction => 'सब कुछ रीसेट करें';

  @override
  String get resetAllDataInProgress => 'रीसेट हो रहा है…';

  @override
  String get resetAllDataDone => 'सभी डेटा रीसेट हो गया';

  @override
  String get resetAllDataFailed => 'रीसेट विफल';

  @override
  String get compareAllTiersSubtitle =>
      'देखें कि प्रत्येक टीयर किससे रक्षा करता है, आमने-सामने तुलना में।';

  @override
  String get autoLockRequiresPassword =>
      'ऑटो-लॉक के लिए सक्रिय टीयर पर पासवर्ड आवश्यक है।';

  @override
  String get recommendedBadge => 'अनुशंसित';

  @override
  String get continueWithRecommended => 'अनुशंसित के साथ जारी रखें';

  @override
  String get customizeSecurity => 'सुरक्षा अनुकूलित करें';

  @override
  String get tierHardwareSubtitleHonest =>
      'उन्नत: हार्डवेयर-बाध्य कुंजी। यदि इस डिवाइस की चिप खो जाती है या बदल दी जाती है, तो डेटा पुनर्प्राप्त नहीं किया जा सकता।';

  @override
  String get tierParanoidSubtitleHonest =>
      'विकल्प: मास्टर पासवर्ड, OS पर भरोसा नहीं। OS से समझौता होने पर सुरक्षा करता है। T1/T2 की तुलना में रनटाइम सुरक्षा में सुधार नहीं करता।';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'runtime के खतरे (समान उपयोगकर्ता का malware, चलती प्रक्रिया का मेमोरी डंप) हर tier में ✗ के रूप में दिखाए जाते हैं। इन्हें अलग mitigation सुविधाओं द्वारा संबोधित किया जाता है जो चुने गए tier से स्वतंत्र रूप से लागू होती हैं।';

  @override
  String get securitySetupContinue => 'जारी रखें';

  @override
  String get currentTierBadge => 'वर्तमान';

  @override
  String get paranoidAlternativeHeader => 'विकल्प';

  @override
  String get modifierPasswordLabel => 'पासवर्ड';

  @override
  String get modifierPasswordSubtitle =>
      'वॉल्ट खुलने से पहले टाइप किया गया गुप्त द्वार।';

  @override
  String get modifierBiometricLabel => 'बायोमेट्रिक शॉर्टकट';

  @override
  String get modifierBiometricSubtitle =>
      'पासवर्ड टाइप करने के बजाय बायोमेट्रिक-संरक्षित OS स्लॉट से उसे प्राप्त करें।';

  @override
  String get biometricRequiresPassword =>
      'पहले पासवर्ड सक्षम करें — बायोमेट्रिक उसे दर्ज करने का केवल एक शॉर्टकट है।';

  @override
  String get biometricForbiddenParanoid =>
      'Paranoid डिज़ाइन के अनुसार बायोमेट्रिक की अनुमति नहीं देता।';

  @override
  String get fprintdNotAvailable =>
      'fprintd संस्थापित नहीं है या कोई फिंगरप्रिंट पंजीकृत नहीं है।';

  @override
  String get linuxTpmWithoutPasswordNote =>
      'पासवर्ड के बिना TPM पृथक्करण प्रदान करता है, प्रमाणीकरण नहीं। जो कोई भी इस ऐप को चला सकता है, वह डेटा को अनलॉक कर सकता है।';

  @override
  String get paranoidMasterPasswordNote =>
      'एक लंबे पासफ़्रेज़ की दृढ़ता से अनुशंसा की जाती है — Argon2id केवल ब्रूट फ़ोर्स को धीमा करता है, रोकता नहीं।';

  @override
  String get plaintextWarningTitle => 'सादा पाठ: कोई एन्क्रिप्शन नहीं';

  @override
  String get plaintextWarningBody =>
      'सत्र, कुंजियाँ और known hosts एन्क्रिप्शन के बिना संग्रहीत किए जाएँगे। इस कंप्यूटर के फ़ाइल सिस्टम तक पहुँच रखने वाला कोई भी व्यक्ति उन्हें पढ़ सकता है।';

  @override
  String get plaintextAcknowledge =>
      'मुझे समझ है कि मेरा डेटा एन्क्रिप्ट नहीं किया जाएगा';

  @override
  String get plaintextAcknowledgeRequired =>
      'जारी रखने से पहले पुष्टि करें कि आप समझ गए हैं।';

  @override
  String get passwordLabel => 'पासवर्ड';

  @override
  String get masterPasswordLabel => 'मास्टर पासवर्ड';
}
