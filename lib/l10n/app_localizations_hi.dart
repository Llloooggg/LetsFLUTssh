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
  String get cut => 'कट करें';

  @override
  String get paste => 'पेस्ट करें';

  @override
  String get select => 'चुनें';

  @override
  String get copyModeTapToStart => 'चयन आरंभ चिह्नित करने के लिए स्पर्श करें';

  @override
  String get copyModeExtending => 'चयन बढ़ाने के लिए खींचें';

  @override
  String get copyModeSetAnchor => 'एंकर सेट करें';

  @override
  String get copyModeCopySelection => 'चयन कॉपी करें';

  @override
  String get required => 'आवश्यक';

  @override
  String get errFillRequiredFields => '* से चिह्नित आवश्यक फ़ील्ड भरें';

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
  String get updateVerifying => 'सत्यापित किया जा रहा है…';

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
  String get sectionAuthentication => 'प्रमाणीकरण';

  @override
  String get sectionAdvanced => 'उन्नत';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString पोर्ट-फॉरवर्ड नियम',
      one: '1 पोर्ट-फॉरवर्ड नियम',
      zero: 'कोई पोर्ट-फॉरवर्ड नियम नहीं',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => 'प्रबंधित करें…';

  @override
  String get authMethodAgent => 'सिस्टम ssh-agent इस्तेमाल करें';

  @override
  String get authMethodAgentSubtitle =>
      '\$SSH_AUTH_SOCK (Linux/macOS) या OpenSSH named pipe (Windows) के through authenticate करें। काम का है अगर keys gpg-agent, Pageant या system ssh-agent में हैं।';

  @override
  String get authMethodAgentMobileUnsupported =>
      'मोबाइल पर उपलब्ध नहीं — system ssh-agent endpoint सिर्फ desktop के लिए है।';

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
  String get savedTypeToChange => 'सहेजा गया — बदलने के लिए टाइप करें';

  @override
  String get hidePemText => 'PEM टेक्स्ट छिपाएं';

  @override
  String get pastePemKeyText => 'PEM कुंजी टेक्स्ट पेस्ट करें';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

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
  String get clearHistory => 'इतिहास साफ़ करें';

  @override
  String get noTransfersYet => 'अभी कोई ट्रांसफ़र नहीं';

  @override
  String get duplicateTab => 'टैब डुप्लिकेट करें';

  @override
  String get duplicateTabShortcut => 'टैब डुप्लिकेट करें (Ctrl+\\)';

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
  String get parallelWorkers => 'Parallel workers';

  @override
  String get maxHistory => 'अधिकतम इतिहास';

  @override
  String get calculateFolderSizes => 'फ़ोल्डर आकार गणना करें';

  @override
  String get exportData => 'डेटा निर्यात करें';

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
  String get tierPlaintextLabel => 'सादा टेक्स्ट';

  @override
  String get tierPlaintextSubtitle =>
      'कोई एन्क्रिप्शन नहीं — केवल फ़ाइल अनुमतियाँ';

  @override
  String get tierKeychainLabel => 'कीचेन';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'कुंजी $keychain में रहती है — लॉन्च पर ऑटो-अनलॉक';
  }

  @override
  String get tierKeychainUnavailable =>
      'इस इंस्टॉल पर OS कीचेन उपलब्ध नहीं है।';

  @override
  String get tierHardwareLabel => 'हार्डवेयर';

  @override
  String get tierParanoidLabel => 'मास्टर पासवर्ड (Paranoid)';

  @override
  String get tierHardwareUnavailable =>
      'इस इंस्टॉल पर हार्डवेयर वॉल्ट उपलब्ध नहीं है।';

  @override
  String get pinLabel => 'पासवर्ड';

  @override
  String get l2UnlockTitle => 'पासवर्ड आवश्यक';

  @override
  String get l2UnlockHint => 'जारी रखने के लिए अपना छोटा पासवर्ड दर्ज करें';

  @override
  String get l2WrongPassword => 'गलत पासवर्ड';

  @override
  String get l3UnlockTitle => 'पासवर्ड दर्ज करें';

  @override
  String get l3UnlockHint => 'पासवर्ड हार्डवेयर-बाउंड वॉल्ट खोलता है';

  @override
  String get l3WrongPin => 'गलत पासवर्ड';

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
  String get dataLocation => 'डेटा स्थान';

  @override
  String get dataStorageSection => 'संग्रहण';

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
  String a11yConnectingTo(String host) {
    return '$host से कनेक्ट हो रहा है';
  }

  @override
  String a11yConnectedTo(String host) {
    return '$host से कनेक्ट हो गया';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return '$host से डिस्कनेक्ट हो गया';
  }

  @override
  String a11yConnectionFailed(String host) {
    return '$host से कनेक्ट नहीं हो सका';
  }

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
  String get qrTooManyForSingleCode =>
      'एक QR कोड के लिए बहुत अधिक सत्र। कुछ अचयनित करें या .lfs निर्यात का उपयोग करें।';

  @override
  String get qrTooLarge =>
      'बहुत बड़ा — कुछ आइटम अचयनित करें या .lfs फ़ाइल निर्यात का उपयोग करें।';

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
  String get errBadFileDescriptor => 'अमान्य फ़ाइल डिस्क्रिप्टर';

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
  String get errBrokenPipe => 'Broken pipe';

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
  String errSftpInitFailed(String error) {
    return 'SFTP आरंभ करने में विफल: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'डाउनलोड विफल: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'सिस्टम फ़ोल्डर पिकर उपलब्ध नहीं है। कोई अन्य स्थान आज़माएँ या ऐप संग्रहण अनुमतियाँ जाँचें।';

  @override
  String get biometricUnlockPrompt => 'LetsFLUTssh अनलॉक करें';

  @override
  String get biometricUnlockTitle => 'बायोमेट्रिक से अनलॉक करें';

  @override
  String get biometricUnlockSubtitle =>
      'पासवर्ड टाइप न करें — डिवाइस के बायोमेट्रिक सेंसर से अनलॉक करें।';

  @override
  String get biometricEnableFailed =>
      'बायोमेट्रिक अनलॉक चालू नहीं किया जा सका।';

  @override
  String get biometricUnlockFailed =>
      'बायोमेट्रिक अनलॉक विफल रहा। अपना मास्टर पासवर्ड दर्ज करें।';

  @override
  String get biometricUnlockCancelled => 'बायोमेट्रिक अनलॉक रद्द कर दिया गया।';

  @override
  String get biometricNotEnrolled =>
      'इस डिवाइस पर कोई बायोमेट्रिक क्रेडेंशियल पंजीकृत नहीं है।';

  @override
  String get biometricSensorNotAvailable =>
      'इस डिवाइस पर कोई बायोमेट्रिक सेंसर नहीं है।';

  @override
  String get biometricSystemServiceMissing =>
      'फ़िंगरप्रिंट सेवा (fprintd) स्थापित नहीं है। README → Installation देखें।';

  @override
  String get currentPasswordIncorrect => 'वर्तमान पासवर्ड गलत है';

  @override
  String get wrongPassword => 'गलत पासवर्ड';

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
      'इतनी देर निष्क्रिय रहने पर UI लॉक होता है। हर लॉक पर डेटाबेस कुंजी मिटा दी जाती है और एन्क्रिप्टेड स्टोर बंद कर दिया जाता है; सक्रिय सत्र प्रति-सत्र क्रेडेंशियल कैश के ज़रिए जुड़े रहते हैं, जो सत्र बंद होने पर साफ़ हो जाता है।';

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
  String get errReleaseManifestUnavailable =>
      'Release का manifest नहीं मिल सका। संभवतः नेटवर्क समस्या, या release अभी प्रकाशित हो रहा है। कुछ मिनट बाद पुनः प्रयास करें।';

  @override
  String get updateSecurityWarningTitle => 'अपडेट सत्यापन विफल';

  @override
  String get updateReinstallAction => 'रिलीज़ पेज खोलें';

  @override
  String get errLfsNotArchive => 'चयनित फ़ाइल LetsFLUTssh संग्रह नहीं है।';

  @override
  String get errLfsDecryptFailed =>
      'गलत master password या corrupt .lfs archive';

  @override
  String get errLfsArchiveTruncated =>
      'संग्रह अधूरा है। मूल डिवाइस से पुनः डाउनलोड या पुनः निर्यात करें।';

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
  String get progressCollectingData => 'डेटा एकत्र किया जा रहा है…';

  @override
  String get progressEncrypting => 'एन्क्रिप्ट किया जा रहा है…';

  @override
  String get progressWritingArchive => 'संग्रह लिखा जा रहा है…';

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
  String get addKey => 'कुंजी जोड़ें';

  @override
  String get filePickerUnavailable =>
      'इस सिस्टम पर फ़ाइल चयनकर्ता उपलब्ध नहीं है';

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
  String get sshCertificate => 'Certificate';

  @override
  String get certImport => 'Certificate इम्पोर्ट करें';

  @override
  String get certImportPickerTitle => 'OpenSSH certificate फ़ाइल चुनें';

  @override
  String get certValidFrom => 'वैध from';

  @override
  String get certValidTo => 'वैध until';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => 'यह certificate जल्द ही expire हो जाएगा।';

  @override
  String get certExpired => 'Expired';

  @override
  String get certRemove => 'Certificate हटाएं';

  @override
  String get certRemoveConfirmTitle => 'Certificate हटाएं?';

  @override
  String get certRemoveConfirmBody =>
      'हटाने के बाद session फिर से सामान्य public-key auth path से connect होगा।';

  @override
  String errCertParse(String detail) {
    return 'Certificate parse नहीं हुआ: $detail';
  }

  @override
  String get errCertPairFingerprintMismatch =>
      'यह certificate चुनी हुई key के साथ pair नहीं है।';

  @override
  String get pastePrivateKey => 'निजी कुंजी चिपकाएं (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'अमान्य PEM कुंजी डेटा';

  @override
  String get selectFromKeyStore => 'कुंजी भंडार से चुनें';

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
  String get passphrase => 'पासफ़्रेज़';

  @override
  String get enterMasterPassword =>
      'सहेजे गए क्रेडेंशियल तक पहुँचने के लिए मास्टर पासवर्ड दर्ज करें।';

  @override
  String get wrongMasterPassword => 'गलत पासवर्ड। कृपया पुनः प्रयास करें।';

  @override
  String get currentPassword => 'वर्तमान पासवर्ड';

  @override
  String get forgotPassword => 'पासवर्ड भूल गए?';

  @override
  String get credentialsReset => 'सभी सहेजे गए क्रेडेंशियल हटा दिए गए';

  @override
  String get migrationToast => 'स्टोरेज को नवीनतम प्रारूप में अपग्रेड किया गया';

  @override
  String get dbCorruptTitle => 'डेटाबेस नहीं खोला जा सकता';

  @override
  String get dbCorruptBody =>
      'डिस्क पर data नहीं खुल पा रहा। दूसरे credentials से try करें या reset करके नए सिरे से शुरू करें।';

  @override
  String get dbCorruptWarning =>
      'रीसेट एन्क्रिप्टेड डेटाबेस और सुरक्षा संबंधी सभी फ़ाइलें स्थायी रूप से हटा देगा। कोई डेटा पुनर्प्राप्त नहीं होगा।';

  @override
  String get dbCorruptTryOther => 'दूसरे credentials आज़माएँ';

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
  String get securitySetupTitle => 'सुरक्षा सेटअप';

  @override
  String get keychainAvailable => 'उपलब्ध';

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
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'इस डिवाइस पर हार्डवेयर-आधारित स्टोरेज उपलब्ध नहीं है।';

  @override
  String get firstLaunchSecurityOpenSettings => 'सेटिंग्स खोलें';

  @override
  String get wizardReducedBanner =>
      'इस इंस्टॉलेशन में OS कीचेन उपलब्ध नहीं है। कोई एन्क्रिप्शन नहीं (T0) और मास्टर पासवर्ड (Paranoid) में से चुनें। Keychain स्तर सक्षम करने के लिए gnome-keyring, kwallet या कोई अन्य libsecret प्रदाता स्थापित करें।';

  @override
  String get tierBadgeCurrent => 'वर्तमान';

  @override
  String get securitySetupEnable => 'सक्षम करें';

  @override
  String get securitySetupApply => 'लागू करें';

  @override
  String get hwProbeLinuxDeviceMissing =>
      '/dev/tpmrm0 पर कोई TPM नहीं मिला। मशीन समर्थन करती है तो BIOS में fTPM / PTT सक्षम करें; अन्यथा इस डिवाइस पर हार्डवेयर स्तर उपलब्ध नहीं है।';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools स्थापित नहीं है। हार्डवेयर स्तर सक्षम करने के लिए `sudo apt install tpm2-tools` (या आपके वितरण का समतुल्य) चलाएँ।';

  @override
  String get hwProbeLinuxProbeFailed =>
      'हार्डवेयर स्तर जाँच विफल। /dev/tpmrm0 अनुमतियाँ और udev नियम जाँचें — विवरण लॉग में हैं।';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'TPM 2.0 नहीं मिला। UEFI फ़र्मवेयर में fTPM / PTT सक्षम करें, या स्वीकारें कि इस डिवाइस पर हार्डवेयर स्तर उपलब्ध नहीं है — ऐप सॉफ़्टवेयर-आधारित क्रेडेंशियल स्टोर पर वापस लौटता है।';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Microsoft Platform Crypto Provider और Software Key Storage Provider दोनों तक पहुँच नहीं है — संभवतः दूषित Windows क्रिप्टो उपप्रणाली या CNG को ब्लॉक करने वाली Group Policy। Event Viewer → Applications and Services Logs जाँचें।';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'इस Mac में Secure Enclave नहीं है (T1 / T2 सुरक्षा चिप के बिना 2017 से पहले का Intel Mac)। हार्डवेयर स्तर उपलब्ध नहीं; मास्टर पासवर्ड का उपयोग करें।';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'इस Mac पर लॉगिन पासवर्ड सेट नहीं है। Secure Enclave कुंजी निर्माण के लिए यह आवश्यक है — System Settings → Touch ID & Password (या Login Password) में सेट करें।';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave ने ऐप की साइनिंग आइडेंटिटी अस्वीकार की (-34018)। रिलीज़ के साथ शामिल `macos-resign.sh` स्क्रिप्ट चलाएँ ताकि इस इंस्टॉल को एक स्थिर सेल्फ़-साइन आइडेंटिटी मिले, फिर ऐप पुनः आरंभ करें।';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'डिवाइस पासकोड सेट नहीं है। Secure Enclave कुंजी निर्माण के लिए यह आवश्यक है — Settings → Face ID & Passcode (या Touch ID & Passcode) में सेट करें।';

  @override
  String get hwProbeIosSimulator =>
      'iOS Simulator पर चल रहा है, जिसमें Secure Enclave नहीं है। हार्डवेयर स्तर केवल भौतिक iOS डिवाइसों पर उपलब्ध है।';

  @override
  String get hwProbeAndroidApiTooLow =>
      'हार्डवेयर स्तर के लिए Android 9 या नया आवश्यक है (StrongBox और प्रति-कुंजी एनरोलमेंट अमान्यकरण पुराने संस्करणों पर विश्वसनीय नहीं हैं)।';

  @override
  String get hwProbeAndroidBiometricNone =>
      'इस डिवाइस में बायोमेट्रिक हार्डवेयर नहीं है (उँगली या चेहरा)। मास्टर पासवर्ड का उपयोग करें।';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'कोई बायोमेट्रिक नामांकित नहीं। Settings → Security & privacy → Biometrics में उँगली या चेहरा जोड़ें, फिर हार्डवेयर स्तर पुनः सक्षम करें।';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'बायोमेट्रिक हार्डवेयर अस्थायी रूप से अनुपयोगी (असफल प्रयासों के बाद लॉकआउट या लंबित सुरक्षा अपडेट)। कुछ मिनटों में पुनः प्रयास करें।';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'Android Keystore ने इस डिवाइस बिल्ड पर हार्डवेयर कुंजी समर्थन देने से इनकार किया (StrongBox अनुपलब्ध, कस्टम ROM, या ड्राइवर समस्या)। हार्डवेयर टियर उपलब्ध नहीं है।';

  @override
  String get securityRecheck => 'टियर समर्थन पुनः जाँचें';

  @override
  String get securityRecheckUpdated =>
      'टियर समर्थन अपडेट हुआ — ऊपर के कार्ड देखें';

  @override
  String get securityRecheckUnchanged => 'टियर समर्थन अपरिवर्तित';

  @override
  String get securityMacosEnableSecureTiers =>
      'इस Mac पर सुरक्षित टियर अनलॉक करें';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'एप्लिकेशन को व्यक्तिगत प्रमाणपत्र से पुनः साइन करें ताकि कीचेन (T1) और Secure Enclave (T2) अपडेट के बाद भी काम करें';

  @override
  String get securityMacosEnableSecureTiersPrompt =>
      'macOS एक बार आपका पासवर्ड पूछेगा';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'सुरक्षित टियर अनलॉक — T1 और T2 अब उपलब्ध हैं';

  @override
  String get securityMacosEnableSecureTiersFailed =>
      'सुरक्षित टियर अनलॉक करने में विफल';

  @override
  String get securityMacosOfferTitle => 'कीचेन + Secure Enclave सक्षम करें?';

  @override
  String get securityMacosOfferBody =>
      'macOS एन्क्रिप्टेड स्टोरेज को ऐप की सिग्निंग आईडेंटिटी से जोड़ता है। स्थिर प्रमाणपत्र के बिना, कीचेन (T1) और Secure Enclave (T2) एक्सेस अस्वीकार करते हैं। हम इस Mac पर एक व्यक्तिगत स्व-हस्ताक्षरित प्रमाणपत्र बना सकते हैं और ऐप को फिर से साइन कर सकते हैं — अपडेट काम करते रहेंगे, और आपके रहस्य रिलीज़ के बीच बचे रहेंगे। macOS नए प्रमाणपत्र पर भरोसा करने के लिए एक बार आपका लॉगिन पासवर्ड पूछेगा।';

  @override
  String get securityMacosOfferAccept => 'सक्षम करें';

  @override
  String get securityMacosOfferDecline => 'छोड़ें — T0 या Paranoid चुनें';

  @override
  String get securityMacosRemoveIdentity => 'साइनिंग आईडेंटिटी हटाएं';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      'व्यक्तिगत प्रमाणपत्र हटाता है। T1 / T2 डेटा इससे जुड़ा है — पहले T0 या Paranoid पर स्विच करें, फिर हटाएं।';

  @override
  String get securityMacosRemoveIdentityConfirmTitle =>
      'साइनिंग आईडेंटिटी हटाएं?';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'लॉगिन कीचेन से व्यक्तिगत प्रमाणपत्र हटाता है। T1 / T2 संग्रहीत रहस्य अपठनीय हो जाएंगे। हटाने से पहले T0 (सादा) या Paranoid (मास्टर पासवर्ड) में माइग्रेट करने के लिए विज़ार्ड खुलेगा।';

  @override
  String get securityMacosRemoveIdentitySuccess => 'साइनिंग आईडेंटिटी हटाई गई';

  @override
  String get securityMacosRemoveIdentityFailed =>
      'साइनिंग आईडेंटिटी हटाने में विफल';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus चल रहा है लेकिन कोई secret-service daemon नहीं चल रहा। gnome-keyring (`sudo apt install gnome-keyring`) या KWalletManager स्थापित करें और लॉगिन पर शुरू होना सुनिश्चित करें।';

  @override
  String get keyringProbeFailed =>
      'इस डिवाइस पर OS कीचेन पहुँच योग्य नहीं। प्लेटफ़ॉर्म-विशिष्ट त्रुटि के लिए लॉग देखें; ऐप मास्टर पासवर्ड पर वापस लौटता है।';

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
  String get pinToSession => 'इस सत्र पर पिन करें';

  @override
  String get unpinFromSession => 'इस सत्र से अनपिन करें';

  @override
  String get pinnedSnippets => 'पिन किए गए';

  @override
  String get allSnippets => 'सभी';

  @override
  String get commandCopied => 'कमांड कॉपी की गई';

  @override
  String get snippetTokensHint =>
      'प्लेसहोल्डर डालने के लिए टैप करें। ये रनटाइम पर सक्रिय सत्र के मानों से बदले जाते हैं:';

  @override
  String get snippetCustomTokensHint =>
      'डबल ब्रेसेस वाला कुछ भी और स्निपेट चलाने पर मान मांगता है।';

  @override
  String get snippetFillTitle => 'स्निपेट पैरामीटर भरें';

  @override
  String get snippetFillSubmit => 'चलाएँ';

  @override
  String get broadcastSetDriver => 'इस पैन से प्रसारण';

  @override
  String get broadcastClearDriver => 'इस पैन से प्रसारण बंद करें';

  @override
  String get broadcastAddReceiver => 'यहाँ प्रसारण प्राप्त करें';

  @override
  String get broadcastRemoveReceiver => 'प्रसारण प्राप्त करना बंद करें';

  @override
  String get broadcastClearAll => 'सभी प्रसारण बंद करें';

  @override
  String get broadcastPasteTitle => 'पेस्ट सभी पैनों पर भेजें?';

  @override
  String broadcastPasteBody(int chars, int count) {
    return '$chars वर्ण $count अन्य पैनों पर भेजे जाएँगे।';
  }

  @override
  String get broadcastPasteSend => 'भेजें';

  @override
  String get portForwarding => 'फ़ॉरवर्डिंग';

  @override
  String get portForwardingEmpty => 'अभी कोई नियम नहीं';

  @override
  String get addForwardRule => 'नियम जोड़ें';

  @override
  String get editForwardRule => 'नियम संपादित करें';

  @override
  String get deleteForwardRule => 'नियम हटाएँ';

  @override
  String get localForward => 'स्थानीय';

  @override
  String get remoteForward => 'दूरस्थ';

  @override
  String get dynamicForward => 'गतिशील';

  @override
  String get forwardKind => 'प्रकार';

  @override
  String get bindAddress => 'बाइंड पता';

  @override
  String get bindPort => 'बाइंड पोर्ट';

  @override
  String get targetHost => 'लक्ष्य होस्ट';

  @override
  String get targetPort => 'लक्ष्य पोर्ट';

  @override
  String get forwardDescription => 'विवरण (वैकल्पिक)';

  @override
  String get forwardEnabled => 'सक्षम';

  @override
  String get forwardBindWildcardWarning =>
      '0.0.0.0 से बाइंड करने पर फ़ॉरवर्ड हर इंटरफ़ेस पर प्रकाशित होता है — आमतौर पर 127.0.0.1 चाहिए।';

  @override
  String get forwardKindLocalHelp =>
      'स्थानीय: इस डिवाइस पर एक पोर्ट खोलता है जो SSH सर्वर से पहुँच योग्य लक्ष्य तक टनल करता है। localhost:bindPort के माध्यम से दूरस्थ डेटाबेस या एडमिन UI तक पहुँच के लिए उपयोगी।';

  @override
  String get forwardKindRemoteHelp =>
      'दूरस्थ: SSH सर्वर से एक पोर्ट खोलने को कहता है जो इस डिवाइस से पहुँच योग्य लक्ष्य तक वापस टनल करता है। दूरस्थ होस्ट के साथ स्थानीय dev server साझा करने के लिए उपयोगी (सर्वर को non-loopback binds के लिए GatewayPorts yes चाहिए हो सकता है)।';

  @override
  String get forwardKindDynamicHelp =>
      'गतिशील: इस डिवाइस पर एक SOCKS5 प्रॉक्सी जो हर कनेक्शन को SSH सर्वर के माध्यम से रूट करता है। सभी ट्रैफ़िक SSH के माध्यम से भेजने के लिए ब्राउज़र या curl को localhost:bindPort पर पॉइंट करें।';

  @override
  String get proxyJump => 'इसके माध्यम से जुड़ें';

  @override
  String get proxyJumpNone => 'सीधा कनेक्शन';

  @override
  String get proxyJumpSavedSession => 'सहेजा गया सत्र';

  @override
  String get proxyJumpCustom => 'कस्टम';

  @override
  String get proxyJumpCustomNote =>
      'कस्टम हॉप्स इसी सत्र के क्रेडेंशियल उपयोग करते हैं। अलग बेस्टियन ऑथ के लिए बेस्टियन को अलग सत्र के रूप में सहेजें।';

  @override
  String viaSessionLabel(String label) {
    return '$label के माध्यम से';
  }

  @override
  String get recordSession => 'सत्र रिकॉर्ड करें';

  @override
  String get recordSessionHelp =>
      'इस सत्र के लिए टर्मिनल आउटपुट को डिस्क पर सहेजें। मास्टर पासवर्ड या हार्डवेयर कुंजी सक्षम होने पर रेस्ट में एन्क्रिप्टेड।';

  @override
  String get recordingsBrowserTitle => 'रिकॉर्डिंग';

  @override
  String get recordingsBrowserSubtitle =>
      'रिकॉर्ड किए गए सत्र ब्राउज़, चलाएँ और हटाएँ';

  @override
  String get recordingsEmpty => 'अभी कोई रिकॉर्डिंग नहीं';

  @override
  String get playRecording => 'चलाएँ';

  @override
  String get deleteRecording => 'हटाएँ';

  @override
  String get recordingPlaybackTitle => 'रिकॉर्डिंग रीप्ले करें';

  @override
  String get recordingSpeed => 'गति';

  @override
  String get recordingSpeedInstant => 'तुरंत';

  @override
  String get recordingScrubTooltipUnavailable =>
      'Scrub bar के लिए sidecar index चाहिए — पुरानी रिकॉर्डिंग (इस build से पहले की) में यह नहीं है। नई रिकॉर्डिंग scrub हो सकेंगी।';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

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
  String get presetFullImport => 'पूर्ण आयात';

  @override
  String get presetSelective => 'चयनात्मक';

  @override
  String get presetCustom => 'कस्टम';

  @override
  String get sessionSshKeys => 'सत्र कुंजियाँ (मैनेजर)';

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
  String get threatColdDiskTheft => 'बंद डिस्क की चोरी';

  @override
  String get threatColdDiskTheftDescription =>
      'बंद मशीन से ड्राइव निकालकर किसी दूसरे कंप्यूटर पर पढ़ी जाए, या आपके होम डायरेक्टरी तक पहुँच रखने वाले किसी व्यक्ति द्वारा डेटाबेस फ़ाइल की नकल ले ली जाए।';

  @override
  String get threatKeyringFileTheft => 'keyring / keychain फ़ाइल चोरी';

  @override
  String get threatKeyringFileTheftDescription =>
      'हमलावर प्लेटफ़ॉर्म की क्रेडेंशियल स्टोर फ़ाइल को सीधे डिस्क से पढ़ लेता है (libsecret keyring, Windows Credential Manager, macOS login keychain) और उसमें लिपटी डेटाबेस कुंजी को पुनः प्राप्त कर लेता है। हार्डवेयर स्तर पासवर्ड से स्वतंत्र रूप से इसे रोकता है क्योंकि चिप कुंजी सामग्री निर्यात करने से इनकार करता है; keychain स्तर के लिए अतिरिक्त पासवर्ड आवश्यक है, अन्यथा चोरी की गई फ़ाइल केवल OS लॉगिन पासवर्ड से खोली जा सकती है।';

  @override
  String get modifierOnlyWithPassword => 'केवल पासवर्ड के साथ';

  @override
  String get threatBystanderUnlockedMachine => 'अनलॉक मशीन पर मौजूद अजनबी';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'जब आप दूर होते हैं, कोई आपकी पहले से अनलॉक मशीन के पास आकर ऐप खोल लेता है।';

  @override
  String get threatLiveRamForensicsLocked => 'लॉक मशीन पर RAM फ़ोरेंसिक';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'हमलावर RAM को फ़्रीज़ करता है (या DMA के ज़रिए कैप्चर करता है) और ऐप लॉक होने पर भी स्नैपशॉट से अब भी मौजूद कुंजी सामग्री निकाल लेता है।';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'OS kernel या keychain का compromise';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'Kernel vulnerability, keychain से डेटा exfiltrate करना, या hardware security chip में backdoor। OS खुद attacker बन जाता है, trusted resource नहीं।';

  @override
  String get threatOfflineBruteForce =>
      'कमज़ोर पासवर्ड पर ऑफ़लाइन ब्रूट फ़ोर्स';

  @override
  String get threatOfflineBruteForceDescription =>
      'Wrapped key या sealed blob की कॉपी रखने वाला attacker बिना किसी rate limiter के, अपनी गति से हर पासवर्ड try करता है।';

  @override
  String get legendProtects => 'सुरक्षित';

  @override
  String get legendDoesNotProtect => 'सुरक्षित नहीं';

  @override
  String get colT0 => 'T0 सादा पाठ';

  @override
  String get colT1 => 'T1 कीचेन';

  @override
  String get colT1Password => 'T1 + पासवर्ड';

  @override
  String get colT1PasswordBiometric => 'T1 + पासवर्ड + बायोमेट्रिक';

  @override
  String get colT2Password => 'T2 + पासवर्ड';

  @override
  String get colT2PasswordBiometric => 'T2 + पासवर्ड + बायोमेट्रिक';

  @override
  String get colParanoid => 'पैरानॉइड';

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
  String resetAllDataConfirmTypePrompt(String phrase) {
    return 'पुष्टि के लिए नीचे $phrase टाइप करें:';
  }

  @override
  String get resetAllDataInProgress => 'रीसेट हो रहा है…';

  @override
  String get resetAllDataDone => 'सभी डेटा रीसेट हो गया';

  @override
  String get resetAllDataFailed => 'रीसेट विफल';

  @override
  String get recordingsTitle => 'Recordings';

  @override
  String get recordingsStorageUsedLabel => 'उपयोग में';

  @override
  String get recordingsCapLabel => 'Cap';

  @override
  String get recordingsCapHint =>
      'recordings/ फ़ोल्डर पर hard cap। पार होने पर सबसे पुरानी recording पहले हटाई जाती है; चालू recording को कभी नहीं छुआ जाता।';

  @override
  String get recordingsClearAllAction => 'सभी recordings हटाएँ';

  @override
  String get recordingsClearAllConfirmTitle => 'सभी recordings हटाएँ?';

  @override
  String get recordingsClearAllConfirmBody =>
      '<app>/recordings/ के अंदर हर रिकॉर्ड की गई session हटा दी जाएगी। चालू recording (यदि कोई हो) बनी रहेगी। यह क्रिया वापस नहीं ली जा सकती।';

  @override
  String recordingsClearAllResult(int count) {
    return '$count recordings हटाई गईं';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return 'Cap अपडेट हो गया। $bytes खाली हुआ।';
  }

  @override
  String get recordingsCapChangedNoChange =>
      'Cap अपडेट हो गया। हटाने के लिए कुछ नहीं।';

  @override
  String get recordingsCapPreset100Mb => '100 MiB';

  @override
  String get recordingsCapPreset250Mb => '250 MiB';

  @override
  String get recordingsCapPreset500Mb => '500 MiB';

  @override
  String get recordingsCapPreset1Gb => '1 GiB';

  @override
  String get recordingsCapPreset2Gb => '2 GiB';

  @override
  String get recordingsCapPreset5Gb => '5 GiB';

  @override
  String get autoLockRequiresPassword =>
      'ऑटो-लॉक के लिए सक्रिय टीयर पर पासवर्ड आवश्यक है।';

  @override
  String get recommendedBadge => 'अनुशंसित';

  @override
  String get tierHardwareSubtitleHonest =>
      'उन्नत: हार्डवेयर-बाध्य कुंजी, हमेशा पासवर्ड से सुरक्षित। यदि इस डिवाइस की चिप खो जाती है या बदल दी जाती है, तो डेटा पुनर्प्राप्त नहीं किया जा सकता।';

  @override
  String get tierParanoidSubtitleHonest =>
      'विकल्प: master password, OS पर भरोसा नहीं। OS compromise होने पर बचाता है। T1/T2 की तुलना में runtime security बेहतर नहीं करता।';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'runtime के खतरे (समान उपयोगकर्ता का malware, चलती प्रक्रिया का मेमोरी डंप) हर tier में ✗ के रूप में दिखाए जाते हैं। इन्हें अलग mitigation सुविधाओं द्वारा संबोधित किया जाता है जो चुने गए tier से स्वतंत्र रूप से लागू होती हैं।';

  @override
  String get currentTierBadge => 'वर्तमान';

  @override
  String get paranoidAlternativeHeader => 'विकल्प';

  @override
  String get modifierPasswordLabel => 'पासवर्ड';

  @override
  String get modifierPasswordSubtitle =>
      'Vault खुलने से पहले टाइप किया जाने वाला secret।';

  @override
  String get modifierPasswordRequired =>
      'आवश्यक — Hardware tier हमेशा पासवर्ड से सुरक्षित होता है।';

  @override
  String get modifierBiometricLabel => 'बायोमेट्रिक शॉर्टकट';

  @override
  String get modifierBiometricSubtitle =>
      'पासवर्ड टाइप करने के बजाय बायोमेट्रिक-संरक्षित OS स्लॉट से उसे प्राप्त करें।';

  @override
  String get biometricRequiresPassword =>
      'पहले पासवर्ड सक्षम करें — बायोमेट्रिक उसे दर्ज करने का केवल एक शॉर्टकट है।';

  @override
  String get biometricRequiresActiveTier =>
      'बायोमेट्रिक अनलॉक सक्षम करने के लिए पहले इस स्तर को चुनें';

  @override
  String get autoLockRequiresActiveTier =>
      'ऑटो-लॉक कॉन्फ़िगर करने के लिए पहले इस स्तर को चुनें';

  @override
  String get biometricForbiddenParanoid =>
      'Paranoid डिज़ाइन के अनुसार बायोमेट्रिक की अनुमति नहीं देता।';

  @override
  String get fprintdNotAvailable =>
      'fprintd संस्थापित नहीं है या कोई फिंगरप्रिंट पंजीकृत नहीं है।';

  @override
  String get t2RequiresPasswordTitle =>
      'Hardware tier के लिए master password सेट करें';

  @override
  String get t2RequiresPasswordBody =>
      'Hardware tier को modifier के रूप में पासवर्ड की आवश्यकता है। बायोमेट्रिक उसके ऊपर एक वैकल्पिक shortcut है।';

  @override
  String get t2MigrationPromptTitle => 'Hardware tier को पासवर्ड चाहिए';

  @override
  String get t2MigrationPromptBody =>
      'बिना पासवर्ड वाले मौजूदा Hardware installs को आगे बढ़ने के लिए अब एक सेट करना होगा।';

  @override
  String get t2MigrationContinue => 'जारी रखें';

  @override
  String get t2MigrationSetPasswordTitle =>
      'Hardware tier रखने के लिए पासवर्ड सेट करें';

  @override
  String get t2MigrationSetPasswordBody =>
      'एक नया master password टाइप करें। hardware module में पहले से sealed DB key इस password के तहत re-seal हो जाएगी — sessions और keys बरकरार रहेंगे।';

  @override
  String get t2MigrationWipeAndRestart => 'Wipe करके नए सिरे से शुरू करें';

  @override
  String get t2MigrationResealFailed =>
      'Hardware tier का re-seal विफल — दूसरा password चुनें या wipe करें।';

  @override
  String get biometricOverlayEnable =>
      'Hardware tier पर बायोमेट्रिक shortcut सक्षम करें';

  @override
  String get biometricOverlayEnableSubtitle =>
      'आपके पासवर्ड को बायोमेट्रिक-गेटेड OS slot से रिलीज़ करता है।';

  @override
  String get biometricOverlayUnavailable =>
      'इस प्लेटफ़ॉर्म पर बायोमेट्रिक overlay अभी उपलब्ध नहीं है।';

  @override
  String get biometricOverlayRequiresPassword =>
      'पहले Hardware tier का पासवर्ड सेट करें।';

  @override
  String get t2UnlockTitle => 'अपने master password से अनलॉक करें';

  @override
  String get t2UnlockSubtitle =>
      'Hardware-bound कुंजी आपके पासवर्ड से सुरक्षित है।';

  @override
  String get t2UnlockUseBiometricButton => 'बायोमेट्रिक का उपयोग करें';

  @override
  String get t2PasswordChanged => 'Hardware tier का पासवर्ड अपडेट किया गया।';

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

  @override
  String get globalErrorTitle => 'Unexpected Error';

  @override
  String get globalErrorBody =>
      'An unexpected error occurred. The app will continue running.';

  @override
  String get globalErrorLogSavedNote =>
      'Full details have been saved to the log file.';

  @override
  String get globalErrorLogDisabledNote =>
      'Enable logging in Settings to save error details.';

  @override
  String globalErrorTechnicalLine(String detail) {
    return 'Error: $detail';
  }

  @override
  String get globalErrorEnableLoggingButton => 'Enable Logging';

  @override
  String get globalErrorLoggingEnabledToast =>
      'Logging enabled — errors will be saved to log file';

  @override
  String get fatalErrorQuitButton => 'Quit';

  @override
  String get fatalErrorWipeButton => 'Wipe all data';

  @override
  String get fatalErrorWipingButton => 'Wiping…';

  @override
  String get fatalErrorWipeExplanation =>
      'Wipe deletes every app-support file (config, database, vault blobs, logs) so the next launch starts from a clean install. Cannot be undone.';

  @override
  String get fatalErrorWipeConfirmTitle => 'Wipe all data?';

  @override
  String get fatalErrorWipeConfirmBody =>
      'This permanently deletes every config, database, and vault file. The app will restart from a blank install. Continue?';

  @override
  String get fatalErrorWipeConfirmAction => 'Wipe everything';

  @override
  String get unencryptedArchiveWarning =>
      'This archive is not password-protected. Anyone with the file can read its contents.';

  @override
  String get clipboardCopyFailed => 'Copy to clipboard failed.';

  @override
  String get nonAsciiHostnameWarning =>
      'Hostname contains non-ASCII characters — verify each character against the literal you typed. Visually similar codepoints (Cyrillic / Greek) can spoof a Latin domain.';

  @override
  String get recordingPlayLocked =>
      'Unlock the app to play this encrypted recording';

  @override
  String get foregroundServiceTitle => 'SSH सक्रिय';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count सक्रिय कनेक्शन',
      one: '1 सक्रिय कनेक्शन',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => 'Session प्रकार';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => 'Username';

  @override
  String get webDavAuthMethod => 'Auth विधि';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer token';

  @override
  String get webDavSelfSignedFingerprint =>
      'Self-signed प्रमाणपत्र का fingerprint (वैकल्पिक)';

  @override
  String get webDavSelfSignedFingerprintHint =>
      'SHA-256, सिस्टम trust के लिए खाली छोड़ें';

  @override
  String get webDavCopyUrl => 'WebDAV URL कॉपी करें';

  @override
  String get webDavOpenInBrowser => 'Browser में खोलें';

  @override
  String get errWebDavAuthFailed => 'WebDAV auth असफल';

  @override
  String get errWebDavNotFound => 'Path नहीं मिला';

  @override
  String get errWebDavConflict => 'Operation मौजूदा state से टकराता है';

  @override
  String errWebDavGeneric(String detail) {
    return 'WebDAV server ने request अस्वीकार किया: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'WebDAV base URL ज़रूरी है';

  @override
  String get errWebDavBaseUrlInvalid =>
      'Base URL http:// या https:// होना चाहिए';

  @override
  String get sessionKindS3 => 'S3';

  @override
  String get s3AccessKeyId => 'Access key ID';

  @override
  String get s3SecretKey => 'Secret access key';

  @override
  String get s3Region => 'Region';

  @override
  String get s3RegionHint => 'us-east-1, eu-west-2, auto';

  @override
  String get s3Endpoint => 'Endpoint';

  @override
  String get s3EndpointHint =>
      'AWS के लिए खाली छोड़ें, या MinIO / R2 / Spaces के लिए set करें';

  @override
  String get s3PathStyle => 'Path-style addressing';

  @override
  String get s3PathStyleHint => 'MinIO के लिए ज़रूरी; AWS के लिए off रखें';

  @override
  String get s3DefaultBucket => 'Default bucket';

  @override
  String get s3DefaultPrefix => 'Default prefix';

  @override
  String get s3GeneratePresignedUrl => 'Presigned URL बनाएं';

  @override
  String get s3PresignedUrlExpiry => 'खत्म होगा';

  @override
  String get s3CopyUri => 's3://bucket/key URI कॉपी करें';

  @override
  String get s3PresignedUrlExpiry15min => '15 मिनट';

  @override
  String get s3PresignedUrlExpiry1hour => '1 घंटा';

  @override
  String get s3PresignedUrlExpiry4hour => '4 घंटे';

  @override
  String get s3PresignedUrlExpiry24hour => '24 घंटे';

  @override
  String get s3PresignedUrlExpiry7day => '7 दिन';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (access key + secret जाँचें)';

  @override
  String get errS3NoSuchBucket => 'Bucket मौजूद नहीं या पहुँच नहीं है';

  @override
  String get errS3RegionMismatch =>
      'Bucket configured region से अलग region में है';

  @override
  String errS3Generic(String detail) {
    return 'S3 server ने request reject किया: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'WebDAV sync चालू करें';

  @override
  String get syncPassphrase => 'Sync passphrase';

  @override
  String get syncPassphraseHint =>
      'Sync archive एन्क्रिप्ट करता है। Master password से अलग होना चाहिए।';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Sync passphrase master password जैसा नहीं हो सकता।';

  @override
  String get syncRemotePath => 'Remote path';

  @override
  String get syncRemotePathHint =>
      'WebDAV base URL के नीचे path — default letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return 'पिछला push: $when';
  }

  @override
  String syncLastPulled(String when) {
    return 'पिछला pull: $when';
  }

  @override
  String get syncNeverRun => 'कभी नहीं';

  @override
  String get syncUpToDate => 'Sync up to date है';

  @override
  String syncPushedBytes(String bytes) {
    return '$bytes push किया';
  }

  @override
  String syncPullApplied(int count) {
    return 'Remote से $count updates apply हुए';
  }

  @override
  String get errSyncDisabled => 'Sync disabled है';

  @override
  String get errSyncEtagMismatch => 'Remote बदल गया — पहले pull, फिर push';

  @override
  String get errSyncUnauthorized => 'WebDAV authentication fail हुआ';

  @override
  String errSyncNetwork(String detail) {
    return 'Network error: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion =>
      'Remote sync archive के लिए नया build चाहिए';

  @override
  String get hardwareKey => 'Hardware key';

  @override
  String get hardwareKeyTapPrompt => 'अपने hardware key को टैप करें';

  @override
  String get hardwareKeyPin => 'Hardware key PIN';

  @override
  String get hardwareKeyTimeout => 'Hardware key ने जवाब नहीं दिया';

  @override
  String get hardwareKeyNotFound => 'कोई hardware key नहीं मिला';

  @override
  String get hardwareKeyUnsupported =>
      'इस platform पर direct hardware key access उपलब्ध नहीं है';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'Apple Developer Program entitlement चाहिए; macOS पर ssh-agent इस्तेमाल करें';

  @override
  String get skKeyRequiresDevice =>
      'इस SSH key के लिए hardware key चाहिए — auth के लिए टैप करें';

  @override
  String get errSkWrongPin => 'PIN गलत है';

  @override
  String get hardwareKeyImport => 'Hardware key import करें (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => 'Hardware key prompt cancel कर दिया';

  @override
  String get agentEndpointSectionTitle => 'External SSH client integration';

  @override
  String get agentEndpointToggleTitle =>
      'Hardware-bound keys को system SSH clients के लिए expose करें';

  @override
  String get agentEndpointToggleSubtitle =>
      'इस device पर git, ssh और IDE plugins को आपकी FIDO2 / smart-card / TPM keys use करने देता है.';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'export command copy करें';

  @override
  String get agentEndpointCopyPipeName => 'pipe name copy करें';

  @override
  String get agentEndpointSignatureRequestTitle => 'Signature request';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester $keyLabel से sign करना चाहता है';
  }

  @override
  String get agentEndpointRequesterUnknown => 'एक external SSH client';

  @override
  String get agentEndpointAuthorizeOnce => 'एक बार authorize करें';

  @override
  String get agentEndpointAuthorizeAlways => 'Authorize करें और याद रखें';

  @override
  String get agentEndpointDeny => 'Deny';

  @override
  String get agentEndpointStatusRunning => 'Running';

  @override
  String get agentEndpointStatusStopped => 'Stopped';

  @override
  String get agentEndpointStatusUnsupported =>
      'इस platform पर supported नहीं है';

  @override
  String get agentEndpointRefusedAddIdentity =>
      'Refused: external clients keys add नहीं कर सकते.';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'ssh-agent endpoint start नहीं हुआ: $detail';
  }

  @override
  String get pkcs11AddTitle => 'Smart-card / token key add करें';

  @override
  String get pkcs11ModuleLabel => 'PKCS#11 module';

  @override
  String get pkcs11ModuleAutoDetected => 'Auto-detect हुआ';

  @override
  String get pkcs11ModuleCustom => 'Custom module...';

  @override
  String get pkcs11ModulePickerTitle => 'PKCS#11 library चुनें';

  @override
  String get pkcs11NoModuleFound =>
      'PKCS#11 module नहीं मिला। OpenSC install करें या vendor library चुनें।';

  @override
  String get pkcs11InitializeFailed => 'PKCS#11 module initialise नहीं हुआ।';

  @override
  String get pkcs11NoTokenPresent => 'किसी reader में token नहीं है।';

  @override
  String pkcs11TokenLabel(String label) {
    return 'Token: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return 'Serial: $serial';
  }

  @override
  String get pkcs11LoginRequired => 'Token को login की ज़रूरत है।';

  @override
  String pkcs11PinPrompt(String token) {
    return '$token का PIN';
  }

  @override
  String get pkcs11PinPad => 'Token के PIN-pad पर confirm करें।';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'PIN गलत है। $remaining attempts बाकी।';
  }

  @override
  String get pkcs11PinLocked => 'Token का PIN locked है। PUK से unblock करें।';

  @override
  String get pkcs11NoSignableKeys =>
      'Token पर SSH-usable keys नहीं हैं (RSA, ECDSA, Ed25519)।';

  @override
  String get pkcs11GostUnsupported => 'GOST keys SSH में नहीं चलतीं।';

  @override
  String pkcs11TokenUnplugged(String label) {
    return 'Token \"$label\" connect नहीं है।';
  }

  @override
  String get pkcs11UriRebindFailed =>
      'Saved token नहीं मिला। फिर से plug करें।';

  @override
  String pkcs11SignFailed(String reason) {
    return 'Signing fail हो गयी: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      'Smart-card / PKCS#11 tokens इस platform पर available नहीं हैं।';

  @override
  String get pkcs11Badge => 'Smart card / token';

  @override
  String pkcs11InfoModulePath(String path) {
    return 'Module: $path';
  }

  @override
  String pkcs11InfoTokenSerial(String serial) {
    return 'Token serial: $serial';
  }

  @override
  String pkcs11InfoObjectLabel(String label) {
    return 'Object: $label';
  }

  @override
  String get pkcs11WizardStepModule => 'PKCS#11 module चुनें';

  @override
  String get pkcs11WizardStepToken => 'Token चुनें';

  @override
  String get pkcs11WizardStepKey => 'Key चुनें';

  @override
  String get pkcs11WizardStepPin => 'PIN दर्ज करें';

  @override
  String get pkcs11AlgoRsa => 'RSA';

  @override
  String get pkcs11AlgoEcdsa => 'ECDSA';

  @override
  String get pkcs11AlgoEd25519 => 'Ed25519';

  @override
  String get pkcs11AlgoGost => 'GOST';

  @override
  String pkcs11KeyMetaFormat(String algo, String detail) {
    return '$algo $detail';
  }

  @override
  String get pkcs11SaveCta => 'Key import करें';

  @override
  String get pkcs11SaveInProgress => 'Token से public key पढ़ रहा है...';

  @override
  String get pkcs11SaveSuccess => 'Smart-card key जोड़ी गई।';

  @override
  String get pkcs11ScanInProgress => 'PKCS#11 modules scan कर रहा है...';

  @override
  String get pkcs11LoadingTokens => 'Tokens load हो रहे हैं...';

  @override
  String get pkcs11LoadingKeys => 'Keys load हो रही हैं...';

  @override
  String get pkcs11ModuleStatusReady => 'Module load हो गया।';

  @override
  String get pkcs11ModuleStatusNoToken => 'Token नहीं है।';

  @override
  String get pkcs11ModuleStatusFailed => 'Module load fail हुआ।';

  @override
  String get pkcs11PinPadHint => '(Device पर PIN pad)';

  @override
  String get pkcs11WizardBack => 'वापस';

  @override
  String get pkcs11WizardNext => 'आगे';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => 'Hardware key जोड़ें';

  @override
  String get sshKeyHardwareBoundExplainer =>
      'Private key device के secure hardware में रहती है और export नहीं हो सकती।';

  @override
  String get sshKeyEnclaveDeviceBound => 'यह key केवल इस Mac पर काम करती है।';

  @override
  String get sshKeyEnclaveDeviceBoundIos =>
      'यह key केवल इस iPhone पर काम करती है।';

  @override
  String get sshKeyHelloDeviceBound => 'यह key केवल इस PC पर काम करती है।';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'Touch ID / Face ID अनिवार्य करें';

  @override
  String get sshKeyEnclavePasscodeFallback =>
      'Device passcode को fallback के रूप में अनुमति दें';

  @override
  String get sshKeyHelloPinRequired =>
      'Windows Hello अनिवार्य करें (PIN, fingerprint या face)';

  @override
  String get sshKeyHardwareUnavailableTitle => 'Hardware keys उपलब्ध नहीं हैं';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'Secure Enclave के लिए app code-signed होना चाहिए।';

  @override
  String get sshKeyHardwareUnavailableHello =>
      'इस PC पर Windows Hello configured नहीं है।';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'TPM detect नहीं हुआ — केवल software-backed।';

  @override
  String get sshKeyHardwareUnavailableTier => 'Software-gated';

  @override
  String get sshKeyEnclaveAlgorithm => 'ecdsa-sha2-nistp256';

  @override
  String get sshKeyHelloAlgorithmEcdsa256 => 'ecdsa-sha2-nistp256 (TPM)';

  @override
  String get sshKeyHelloAlgorithmEcdsa384 => 'ecdsa-sha2-nistp384 (TPM)';

  @override
  String get sshKeyHelloAlgorithmRsa => 'rsa-sha2-256 (TPM)';

  @override
  String get sshKeyGenerateCta => 'Generate करें';

  @override
  String get sshKeyGenerateInProgress =>
      'Secure hardware में key generate हो रही है...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Code-signing आवश्यक — USER_GUIDE.md → Hardware-bound keys देखें।';

  @override
  String get sshKeySignInProgress => 'Secure hardware से sign हो रहा है...';

  @override
  String get sshKeyPublicCopy => 'Public key copy करें';

  @override
  String get sshKeyAuthorizedKeysHint =>
      'इस लाइन को सर्वर पर ~/.ssh/authorized_keys में जोड़ें।';

  @override
  String get sshKeyEnclaveWizardTitle => 'Secure Enclave SSH key';

  @override
  String get sshKeyEnclaveWizardLabelHint => 'Key का नाम';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'Windows Hello SSH key';

  @override
  String get helloWizardLabelHint => 'Key label';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'Windows Hello से authenticate करें';

  @override
  String get helloPromptDescription =>
      'PIN, फिंगरप्रिंट या face — Windows Hello इस SSH challenge को sign करेगा.';

  @override
  String get helloSoftwareGatedWarning =>
      'इस device में TPM नहीं है. Key user storage में रहेगी; Windows Hello हर signature पर gate रहेगा.';

  @override
  String get helloP384NotSupported =>
      'TPM firmware P-384 support नहीं करता. P-256 या RSA-2048 चुनें.';

  @override
  String get helloConfigureFirst =>
      'पहले Windows Hello को Settings -> Sign-in options में सेट करें.';

  @override
  String get tpmSshTitle => 'TPM-समर्थित SSH key बनाएं';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (अनुशंसित)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported =>
      'इस TPM फ़र्मवेयर पर यह algorithm समर्थित नहीं है।';

  @override
  String get tpmSshPinProtect => 'PIN से सुरक्षित करें';

  @override
  String get tpmSshPinLockoutWarning =>
      'गलत PIN बार-बार डालने पर TPM key को लॉक कर देता है।';

  @override
  String get tpmSshPinMismatch => 'PIN मेल नहीं खा रहे।';

  @override
  String get tpmSshStorageBlob => 'wrapped key को app data में स्टोर करें';

  @override
  String get tpmSshStorageHandle => 'TPM memory slot में रखें';

  @override
  String get tpmSshStorageHandleHelp =>
      'तेज़ signing. TPM के persistent slots में से एक का उपयोग करता है।';

  @override
  String get tpmSshLabel => 'Key label';

  @override
  String get tpmSshImportTitle => 'TPM-protected SSH key import करें';

  @override
  String get tpmSshImportFormat => 'TPM 2.0 Key File (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return '$label के लिए TPM PIN';
  }

  @override
  String get tpmSshPinIncorrect => 'PIN गलत है।';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM lockout cooldown में है। $duration रुकें और दोबारा प्रयास करें।';
  }

  @override
  String get tpmSshGenerating => 'TPM में key बना रहे हैं...';

  @override
  String get tpmSshSigning => 'TPM से sign कर रहे हैं...';

  @override
  String get tpmSshUnavailable => 'इस device पर TPM नहीं मिला।';

  @override
  String get tpmSshUnavailableFwDisabled => 'TPM firmware में disabled है।';

  @override
  String get tpmSshUnavailableNoPermission =>
      'App TPM तक नहीं पहुंच सकता। user को `tss` group में जोड़ें।';

  @override
  String tpmSshHandleInUse(String handle) {
    return 'Persistent slot $handle पहले से उपयोग में है।';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      'यह key Hello / PIN prompt के बिना sign करती है — जब तक आप logged in हैं, desktop access वाला कोई भी इसका उपयोग कर सकता है।';

  @override
  String get keystoreWizardTitle => 'Android Hardware Key';

  @override
  String get keystoreBadge => 'Android Keystore';

  @override
  String get keystoreKeyAndroidLabel => 'Android Keystore (hardware-bound)';

  @override
  String get keystoreKeyStrongBoxLabel => 'StrongBox HSM';

  @override
  String get keystoreKeyTeeLabel => 'TEE (hardware-backed)';

  @override
  String get keystoreKeyGenerating =>
      'Hardware-bound key generate हो रही है...';

  @override
  String get keystoreKeyAuthPrompt =>
      'SSH key use करने के लिए authenticate करें';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      'Key destroy हो गई: नई biometric register हुई है। Server पर public key फिर से register करें।';

  @override
  String get keystoreKeyStrongBoxUnavailable =>
      'इस device पर StrongBox HSM उपलब्ध नहीं';

  @override
  String get keystoreKeyUserAuthRequired =>
      'हर signature के लिए biometric / device unlock require करें';

  @override
  String get keystoreKeyExportDisabled =>
      'Hardware-bound keys export नहीं की जा सकतीं';

  @override
  String get keystoreKeyDeleteWarning =>
      'इस key को delete करने पर यह hardware store से हट जाएगी। जब तक आप नई register नहीं करते, server इसे reject करेंगे।';

  @override
  String get keystoreKeyBiometricNotEnrolled =>
      'पहले biometric या device PIN enroll करें';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (StrongBox-eligible)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+, सिर्फ TEE)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (widest compatibility)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM उपलब्ध नहीं';

  @override
  String get keystoreStrongBoxFallbackBody =>
      'आपका डिवाइस StrongBox HSM expose नहीं करता। इसके बजाय TEE-backed key बनाएँ? यह अभी भी hardware-backed है, बस StrongBox isolation के बिना।';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'TEE use करें';

  @override
  String get keystoreStrongBoxFallbackCancel => 'रद्द करें';

  @override
  String get fido2BrokerSectionTitle => 'हार्डवेयर सिक्योरिटी keys';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / security key';

  @override
  String get fido2BrokerMacosLabel => 'सिस्टम security key डायलॉग';

  @override
  String get fido2BrokerIosLabel => 'सिस्टम security key (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel => 'सिस्टम security key (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => 'डायरेक्ट USB HID (CTAP2)';

  @override
  String get fido2BrokerTransportNone => 'इस प्लेटफ़ॉर्म पर उपलब्ध नहीं';

  @override
  String get fido2BrokerCurrentTransportLabel => 'मौजूदा transport';

  @override
  String get fido2BrokerPreferDirectHidTitle =>
      'सिस्टम डायलॉग की जगह डायरेक्ट USB HID को प्राथमिकता दें';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return 'एडवांस्ड: जिन प्लेटफ़ॉर्म पर दोनों paths काम करते हैं वहाँ $brokerLabel को बायपास करें। डायरेक्ट HID authenticator के ज़्यादा फ़ीचर देता है पर हर app के लिए permission grant ज़रूरी होती है।';
  }

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return 'इस डिवाइस पर सिर्फ़ $transport उपलब्ध है; toggle disabled है।';
  }

  @override
  String get hardwareKeyStubBadge => 'इम्पोर्टेड स्टब';

  @override
  String get hardwareKeyStubSubtitle =>
      'दूसरे डिवाइस पर था — उपयोग के लिए यहाँ रीजेनरेट करें';

  @override
  String get hardwareKeyStubRegenerateAction => 'यहाँ रीजेनरेट करें';

  @override
  String get hardwareKeyStubRemoveAction => 'स्टब हटाएँ';

  @override
  String get hardwareKeyStubPickerTooltip =>
      'उपयोग से पहले इस डिवाइस पर इस कुंजी को रीजेनरेट करें';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return 'टोकन \"$token\" के लिए PKCS#11 मॉड्यूल खोजें';
  }
}
