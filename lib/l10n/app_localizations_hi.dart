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
  String get couldNotOpenInstaller => 'इंस्टॉलर नहीं खुल सका';

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
  String get sessions => 'सत्र';

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
  String get qrGenerationFailed => 'QR बनाना विफल';

  @override
  String get scanWithCameraApp =>
      'LetsFLUTssh इंस्टॉल किए गए डिवाइस पर\nकिसी भी कैमरा ऐप से स्कैन करें।';

  @override
  String get noPasswordsInQr => 'इस QR कोड में कोई पासवर्ड या कुंजी नहीं है';

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
  String get sortByName => 'नाम से क्रमबद्ध करें';

  @override
  String get sortByStatus => 'स्थिति से क्रमबद्ध करें';

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
  String get setMasterPasswordHint =>
      'आर्काइव को एन्क्रिप्ट करने के लिए मास्टर पासवर्ड सेट करें।';

  @override
  String get passwordsDoNotMatch => 'पासवर्ड मेल नहीं खाते';

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
      'बहुत बड़ा — कुछ सत्र अचयनित करें या .lfs फ़ाइल निर्यात का उपयोग करें।';

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
  String get transfersLabel => 'Transfers:';

  @override
  String transferCountActive(int count) {
    return '$count active';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count queued';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count in history';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'Created: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'Started: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'Ended: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'Duration: $duration';
  }

  @override
  String get transferStatusQueued => 'Queued';

  @override
  String get transferStartingUpload => 'Starting upload...';

  @override
  String get transferStartingDownload => 'Starting download...';

  @override
  String get transferCopying => 'Copying...';

  @override
  String get transferDone => 'Done';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total files';
  }

  @override
  String get folderNameLabel => 'FOLDER NAME';

  @override
  String folderAlreadyExists(String name) {
    return 'Folder \"$name\" already exists';
  }

  @override
  String get dropKeyFileHere => 'Drop key file here';

  @override
  String get sessionNoCredentials =>
      'Session has no credentials — edit it first to add a password or key';

  @override
  String dragItemCount(int count) {
    return '$count items';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'Select All ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'Payload: $size KB / $max KB max';
  }

  @override
  String get noActiveTerminals => 'No active terminals';

  @override
  String get connectFromSessionsTab => 'Connect from Sessions tab';

  @override
  String fileNotFound(String path) {
    return 'File not found: $path';
  }

  @override
  String get sshConnectionChannel => 'SSH Connection';

  @override
  String get sshConnectionChannelDesc =>
      'Keeps SSH connections alive in the background.';

  @override
  String get sshActive => 'SSH active';

  @override
  String activeConnectionCount(int count) {
    return '$count active connection(s)';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count items, $size';
  }

  @override
  String get maximize => 'अधिकतम करें';

  @override
  String get restore => 'पुनर्स्थापित करें';

  @override
  String get duplicateDownShortcut => 'नीचे डुप्लिकेट करें (Ctrl+Shift+\\)';

  @override
  String get security => 'Security';

  @override
  String get knownHosts => 'Known Hosts';

  @override
  String get knownHostsSubtitle => 'Manage trusted SSH server fingerprints';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count known hosts',
      one: '1 known host',
      zero: 'No known hosts',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'No known hosts yet. Connect to a server to add one.';

  @override
  String get removeHost => 'Remove Host';

  @override
  String removeHostConfirm(String host) {
    return 'Remove $host from known hosts? You will be prompted to verify its key again on next connection.';
  }

  @override
  String get clearAllKnownHosts => 'Clear All Known Hosts';

  @override
  String get clearAllKnownHostsConfirm =>
      'Remove all known hosts? You will be prompted to verify each server key again.';

  @override
  String get importKnownHosts => 'Import Known Hosts';

  @override
  String get importKnownHostsSubtitle => 'Import from OpenSSH known_hosts file';

  @override
  String get exportKnownHosts => 'Export Known Hosts';

  @override
  String importedHosts(int count) {
    return 'Imported $count new hosts';
  }

  @override
  String get clearedAllHosts => 'Cleared all known hosts';

  @override
  String removedHost(String host) {
    return 'Removed $host';
  }

  @override
  String get noHostsToExport => 'No known hosts to export';

  @override
  String get sshKeys => 'SSH Keys';

  @override
  String get sshKeysSubtitle => 'Manage SSH key pairs for authentication';

  @override
  String get noKeys => 'No SSH keys. Import or generate one.';

  @override
  String get generateKey => 'Generate Key';

  @override
  String get importKey => 'Import Key';

  @override
  String get keyLabel => 'Key Label';

  @override
  String get keyLabelHint => 'e.g. Work Server, GitHub';

  @override
  String get selectKeyType => 'Key Type';

  @override
  String get generating => 'Generating...';

  @override
  String keyGenerated(String label) {
    return 'Key generated: $label';
  }

  @override
  String keyImported(String label) {
    return 'Key imported: $label';
  }

  @override
  String get deleteKey => 'Delete Key';

  @override
  String deleteKeyConfirm(String label) {
    return 'Delete key \"$label\"? Sessions using it will lose access.';
  }

  @override
  String keyDeleted(String label) {
    return 'Key deleted: $label';
  }

  @override
  String get publicKey => 'Public Key';

  @override
  String get publicKeyCopied => 'Public key copied to clipboard';

  @override
  String get pastePrivateKey => 'Paste Private Key (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Invalid PEM key data';

  @override
  String get selectFromKeyStore => 'Select from Key Store';

  @override
  String get noKeySelected => 'No key selected';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keys',
      one: '1 key',
      zero: 'No keys',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'Generated';

  @override
  String get passphraseRequired => 'Passphrase Required';

  @override
  String passphrasePrompt(String host) {
    return 'The SSH key for $host is encrypted. Enter the passphrase to unlock it.';
  }

  @override
  String get passphraseWrong => 'Wrong passphrase. Please try again.';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get rememberPassphrase => 'Remember for this session';

  @override
  String get unlock => 'Unlock';

  @override
  String get masterPasswordSubtitle =>
      'Protect saved credentials with a password';

  @override
  String get setMasterPassword => 'Set Master Password';

  @override
  String get changeMasterPassword => 'Change Master Password';

  @override
  String get removeMasterPassword => 'Remove Master Password';

  @override
  String get masterPasswordEnabled =>
      'Credentials are protected by master password';

  @override
  String get masterPasswordDisabled =>
      'Credentials use auto-generated key (no password)';

  @override
  String get enterMasterPassword =>
      'Enter master password to unlock your saved credentials.';

  @override
  String get wrongMasterPassword => 'Wrong password. Please try again.';

  @override
  String get newPassword => 'New Password';

  @override
  String get currentPassword => 'Current Password';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String get masterPasswordSet => 'Master password enabled';

  @override
  String get masterPasswordChanged => 'Master password changed';

  @override
  String get masterPasswordRemoved => 'Master password removed';

  @override
  String get masterPasswordWarning =>
      'If you forget this password, all saved passwords and SSH keys will be lost. There is no recovery.';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get forgotPasswordWarning =>
      'This will delete ALL saved passwords, SSH keys, and passphrases. Sessions and settings will be kept. This cannot be undone.';

  @override
  String get resetAndDeleteCredentials => 'Reset & Delete Credentials';

  @override
  String get credentialsReset => 'All saved credentials have been deleted';

  @override
  String get derivingKey => 'Deriving encryption key...';

  @override
  String get reEncrypting => 'Re-encrypting data...';

  @override
  String get confirmRemoveMasterPassword =>
      'Enter your current password to remove master password protection. Credentials will be re-encrypted with an auto-generated key.';
}
