// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class SAr extends S {
  SAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'موافق';

  @override
  String get infoDialogProtectsHeader => 'يحمي من';

  @override
  String get infoDialogDoesNotProtectHeader => 'لا يحمي من';

  @override
  String get cancel => 'إلغاء';

  @override
  String get close => 'إغلاق';

  @override
  String get delete => 'حذف';

  @override
  String get save => 'حفظ';

  @override
  String get connect => 'اتصال';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get import_ => 'استيراد';

  @override
  String get export_ => 'تصدير';

  @override
  String get rename => 'إعادة تسمية';

  @override
  String get create => 'إنشاء';

  @override
  String get back => 'رجوع';

  @override
  String get copy => 'نسخ';

  @override
  String get cut => 'قص';

  @override
  String get paste => 'لصق';

  @override
  String get select => 'تحديد';

  @override
  String get copyModeTapToStart => 'المس لتحديد بداية التحديد';

  @override
  String get copyModeExtending => 'اسحب لتمديد التحديد';

  @override
  String get copyModeSetAnchor => 'تعيين نقطة الإرساء';

  @override
  String get copyModeCopySelection => 'نسخ التحديد';

  @override
  String get required => 'مطلوب';

  @override
  String get errFillRequiredFields => 'املأ الحقول المطلوبة المعلَّمة بـ *';

  @override
  String get settings => 'الإعدادات';

  @override
  String get appSettings => 'إعدادات التطبيق';

  @override
  String get yes => 'نعم';

  @override
  String get no => 'لا';

  @override
  String get importWhatToImport => 'ماذا تريد أن تستورد:';

  @override
  String get exportWhatToExport => 'ماذا تريد أن تصدّر:';

  @override
  String get enterMasterPasswordPrompt => 'أدخل كلمة المرور الرئيسية:';

  @override
  String get nextStep => 'التالي';

  @override
  String get includePasswords => 'كلمات مرور الجلسات';

  @override
  String get embeddedKeys => 'المفاتيح المضمنة';

  @override
  String get managerKeys => 'المفاتيح من المدير';

  @override
  String get managerKeysMayBeLarge => 'قد تتجاوز مفاتيح المدير حجم رمز QR';

  @override
  String get qrPasswordWarning => 'مفاتيح SSH معطلة افتراضيًا للتصدير.';

  @override
  String get sshKeysMayBeLarge => 'قد تتجاوز المفاتيح حجم رمز QR';

  @override
  String exportTotalSize(String size) {
    return 'الحجم الإجمالي: $size';
  }

  @override
  String get terminal => 'الطرفية';

  @override
  String get files => 'الملفات';

  @override
  String get transfer => 'النقل';

  @override
  String get open => 'فتح';

  @override
  String get search => 'بحث...';

  @override
  String get noResults => 'لا توجد نتائج';

  @override
  String get filter => 'تصفية...';

  @override
  String get merge => 'دمج';

  @override
  String get replace => 'استبدال';

  @override
  String get reconnect => 'إعادة الاتصال';

  @override
  String get updateAvailable => 'تحديث متاح';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'الإصدار $version متاح (الحالي: v$current).';
  }

  @override
  String get releaseNotes => 'ملاحظات الإصدار:';

  @override
  String get skipThisVersion => 'تخطي هذا الإصدار';

  @override
  String get unskip => 'إلغاء التخطي';

  @override
  String get downloadAndInstall => 'تنزيل وتثبيت';

  @override
  String get openInBrowser => 'فتح في المتصفح';

  @override
  String get couldNotOpenBrowser =>
      'تعذر فتح المتصفح — تم نسخ الرابط إلى الحافظة';

  @override
  String get checkForUpdates => 'التحقق من التحديثات';

  @override
  String get checkNow => 'تحقق الآن';

  @override
  String get checkForUpdatesOnStartup => 'التحقق من التحديثات عند بدء التشغيل';

  @override
  String get checking => 'جارٍ التحقق...';

  @override
  String get youreUpToDate => 'أنت تستخدم أحدث إصدار';

  @override
  String get updateCheckFailed => 'فشل التحقق من التحديثات';

  @override
  String get unknownError => 'خطأ غير معروف';

  @override
  String downloadingPercent(int percent) {
    return 'جارٍ التنزيل... $percent%';
  }

  @override
  String get updateVerifying => 'جاري التحقق...';

  @override
  String get downloadComplete => 'اكتمل التنزيل';

  @override
  String get installNow => 'تثبيت الآن';

  @override
  String get openReleasePage => 'فتح صفحة الإصدار';

  @override
  String get couldNotOpenInstaller => 'تعذر فتح المثبّت';

  @override
  String get installerFailedOpenedReleasePage =>
      'تعذر تشغيل المثبّت؛ تم فتح صفحة الإصدار في المتصفح';

  @override
  String versionAvailable(String version) {
    return 'الإصدار $version متاح';
  }

  @override
  String currentVersion(String version) {
    return 'الحالي: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'تم استلام مفتاح SSH: $filename';
  }

  @override
  String importedSessions(int count) {
    return 'تم استيراد $count جلسة';
  }

  @override
  String importFailed(String error) {
    return 'فشل الاستيراد: $error';
  }

  @override
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم إسقاط $count ارتباط (الأهداف مفقودة)',
      many: 'تم إسقاط $count ارتباطًا (الأهداف مفقودة)',
      few: 'تم إسقاط $count ارتباطات (الأهداف مفقودة)',
      two: 'تم إسقاط ارتباطين (الأهداف مفقودة)',
      one: 'تم إسقاط ارتباط واحد (الهدف مفقود)',
      zero: 'لا توجد ارتباطات مفقودة',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تخطي $count جلسة تالفة',
      many: 'تم تخطي $count جلسة تالفة',
      few: 'تم تخطي $count جلسات تالفة',
      two: 'تم تخطي جلستين تالفتين',
      one: 'تم تخطي جلسة تالفة واحدة',
      zero: 'لا توجد جلسات تالفة',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'الجلسات';

  @override
  String get emptyFolders => 'مجلدات فارغة';

  @override
  String get sessionsHeader => 'الجلسات';

  @override
  String get savedSessions => 'الجلسات المحفوظة';

  @override
  String get activeConnections => 'الاتصالات النشطة';

  @override
  String get openTabs => 'علامات التبويب المفتوحة';

  @override
  String get noSavedSessions => 'لا توجد جلسات محفوظة';

  @override
  String get addSession => 'إضافة جلسة';

  @override
  String get noSessions => 'لا توجد جلسات';

  @override
  String nSelectedCount(int count) {
    return '$count محدد';
  }

  @override
  String get selectAll => 'تحديد الكل';

  @override
  String get deselectAll => 'إلغاء تحديد الكل';

  @override
  String get moveTo => 'نقل إلى...';

  @override
  String get moveToFolder => 'نقل إلى مجلد';

  @override
  String get rootFolder => '/ (الجذر)';

  @override
  String get newFolder => 'مجلد جديد';

  @override
  String get newConnection => 'اتصال جديد';

  @override
  String get editConnection => 'تعديل الاتصال';

  @override
  String get duplicate => 'تكرار';

  @override
  String get deleteSession => 'حذف الجلسة';

  @override
  String get renameFolder => 'إعادة تسمية المجلد';

  @override
  String get deleteFolder => 'حذف المجلد';

  @override
  String get deleteSelected => 'حذف المحدد';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return 'حذف $parts؟\n\nلا يمكن التراجع عن هذا الإجراء.';
  }

  @override
  String nSessions(int count) {
    return '$count جلسة';
  }

  @override
  String nFolders(int count) {
    return '$count مجلد';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'حذف المجلد \"$name\"؟';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'سيتم أيضاً حذف $count جلسة بداخله.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return 'حذف \"$name\"؟';
  }

  @override
  String get connection => 'الاتصال';

  @override
  String get auth => 'المصادقة';

  @override
  String get sectionAuthentication => 'المصادقة';

  @override
  String get sectionAdvanced => 'متقدم';

  @override
  String get moreOptions => 'المزيد من الخيارات';

  @override
  String get connectTo => 'الاتصال بـ';

  @override
  String get connectHint => 'root@example.com:22';

  @override
  String get connectStringInvalid => 'تنسيق غير صالح — متوقع user@host:port';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString قاعدة توجيه منافذ',
      many: '$countString قاعدة توجيه منافذ',
      few: '$countString قواعد توجيه منافذ',
      two: 'قاعدتا توجيه منفذ',
      one: 'قاعدة توجيه منفذ واحدة',
      zero: 'لا توجد قواعد توجيه منافذ',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => 'إدارة…';

  @override
  String get authMethodAgent => 'استخدم ssh-agent النظام';

  @override
  String get authMethodAgentSubtitle =>
      'المصادقة عبر \$SSH_AUTH_SOCK (Linux/macOS) أو OpenSSH named pipe (Windows). مفيد إذا كانت مفاتيحك في gpg-agent أو Pageant أو ssh-agent نظامي.';

  @override
  String get authMethodAgentMobileUnsupported =>
      'غير متاح على الموبايل — endpoint الخاص بـ ssh-agent النظام للأجهزة المكتبية فقط.';

  @override
  String get options => 'الخيارات';

  @override
  String get sessionName => 'اسم الجلسة';

  @override
  String get sessionNameAutoFromHost => 'تلقائي من المضيف';

  @override
  String get sessionNameAutoFromUrl => 'تلقائي من مضيف URL';

  @override
  String get sessionNameAutoFromBucket => 'تلقائي من السلة الافتراضية';

  @override
  String get hintMyServer => 'خادمي';

  @override
  String get hostRequired => 'المضيف *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'المنفذ';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'اسم المستخدم *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'كلمة المرور';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'عبارة مرور المفتاح';

  @override
  String get hintOptional => 'اختياري';

  @override
  String get savedTypeToChange => 'محفوظ — اكتب للتغيير';

  @override
  String get hidePemText => 'إخفاء نص PEM';

  @override
  String get pastePemKeyText => 'لصق نص مفتاح PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get saveAndConnect => 'حفظ واتصال';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst => 'قم بتوفير ملف مفتاح أو نص PEM أولاً';

  @override
  String get keyTextPem => 'نص المفتاح (PEM)';

  @override
  String get selectKeyFile => 'اختيار ملف المفتاح';

  @override
  String get clearKeyFile => 'مسح ملف المفتاح';

  @override
  String get authOrDivider => 'أو';

  @override
  String get providePasswordOrKey => 'قدم كلمة مرور أو مفتاح SSH';

  @override
  String get quickConnect => 'اتصال سريع';

  @override
  String get scanQrCode => 'مسح رمز QR';

  @override
  String get emptyFolder => 'مجلد فارغ';

  @override
  String get qrGenerationFailed => 'فشل إنشاء رمز QR';

  @override
  String get scanWithCameraApp =>
      'امسح باستخدام أي تطبيق كاميرا على جهاز\nمثبّت عليه LetsFLUTssh.';

  @override
  String get noPasswordsInQr => 'لا توجد كلمات مرور أو مفاتيح في رمز QR هذا';

  @override
  String get qrContainsCredentialsWarning =>
      'يحتوي رمز QR هذا على بيانات اعتماد. احتفظ بخصوصية الشاشة.';

  @override
  String get copyLink => 'نسخ الرابط';

  @override
  String get linkCopied => 'تم نسخ الرابط إلى الحافظة';

  @override
  String get hostKeyChanged => 'تغيّر مفتاح المضيف!';

  @override
  String get unknownHost => 'مضيف غير معروف';

  @override
  String get hostKeyChangedWarning =>
      'تحذير: تغيّر مفتاح المضيف لهذا الخادم. قد يشير ذلك إلى هجوم رجل في المنتصف، أو ربما تمت إعادة تثبيت الخادم.';

  @override
  String get unknownHostMessage =>
      'لا يمكن التحقق من هوية هذا المضيف. هل أنت متأكد أنك تريد متابعة الاتصال؟';

  @override
  String get host => 'المضيف';

  @override
  String get keyType => 'نوع المفتاح';

  @override
  String get fingerprint => 'البصمة';

  @override
  String get fingerprintCopied => 'تم نسخ البصمة';

  @override
  String get copyFingerprint => 'نسخ البصمة';

  @override
  String get acceptAnyway => 'قبول على أي حال';

  @override
  String get accept => 'قبول';

  @override
  String get importData => 'استيراد البيانات';

  @override
  String get masterPassword => 'كلمة المرور الرئيسية';

  @override
  String get confirmPassword => 'تأكيد كلمة المرور';

  @override
  String get importModeMergeDescription =>
      'إضافة جلسات جديدة والاحتفاظ بالحالية';

  @override
  String get importModeReplaceDescription => 'استبدال جميع الجلسات بالمستوردة';

  @override
  String get folderName => 'اسم المجلد';

  @override
  String get newName => 'الاسم الجديد';

  @override
  String deleteItems(String names) {
    return 'حذف $names؟';
  }

  @override
  String deleteNItems(int count) {
    return 'حذف $count عنصر';
  }

  @override
  String deletedItem(String name) {
    return 'تم حذف $name';
  }

  @override
  String deletedNItems(int count) {
    return 'تم حذف $count عنصر';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'فشل إنشاء المجلد: $error';
  }

  @override
  String failedToRename(String error) {
    return 'فشلت إعادة التسمية: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return 'فشل حذف $name: $error';
  }

  @override
  String get editPath => 'تعديل المسار';

  @override
  String get root => 'الجذر';

  @override
  String get controllersNotInitialized => 'لم تتم تهيئة المتحكمات';

  @override
  String get clearHistory => 'مسح السجل';

  @override
  String get noTransfersYet => 'لا توجد عمليات نقل بعد';

  @override
  String get duplicateTab => 'تكرار التبويب';

  @override
  String get duplicateTabShortcut => 'تكرار التبويب (Ctrl+\\)';

  @override
  String get previous => 'السابق';

  @override
  String get next => 'التالي';

  @override
  String get closeEsc => 'إغلاق (Esc)';

  @override
  String get closeAll => 'إغلاق الكل';

  @override
  String get closeOthers => 'إغلاق الأخرى';

  @override
  String get closeTabsToTheLeft => 'إغلاق علامات التبويب على اليسار';

  @override
  String get closeTabsToTheRight => 'إغلاق علامات التبويب على اليمين';

  @override
  String get noActiveSession => 'لا توجد جلسة نشطة';

  @override
  String get createConnectionHint =>
      'أنشئ اتصالاً جديداً أو اختر واحداً من الشريط الجانبي';

  @override
  String get hideSidebar => 'إخفاء الشريط الجانبي (Ctrl+B)';

  @override
  String get showSidebar => 'إظهار الشريط الجانبي (Ctrl+B)';

  @override
  String get language => 'اللغة';

  @override
  String get languageSystemDefault => 'تلقائي';

  @override
  String get theme => 'المظهر';

  @override
  String get themeDark => 'داكن';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeSystem => 'النظام';

  @override
  String get appearance => 'المظهر';

  @override
  String get connectionSection => 'الاتصال';

  @override
  String get transfers => 'عمليات النقل';

  @override
  String get data => 'البيانات';

  @override
  String get logging => 'السجلات';

  @override
  String get updates => 'التحديثات';

  @override
  String get about => 'حول';

  @override
  String get resetToDefaults => 'إعادة التعيين إلى الافتراضي';

  @override
  String get uiScale => 'حجم الواجهة';

  @override
  String get terminalFontSize => 'حجم خط الطرفية';

  @override
  String get scrollbackLines => 'عدد أسطر scrollback';

  @override
  String get keepAliveInterval => 'فترة الإبقاء على الاتصال (ثانية)';

  @override
  String get sshTimeout => 'مهلة SSH (ثانية)';

  @override
  String get defaultPort => 'المنفذ الافتراضي';

  @override
  String get parallelWorkers => 'Workers المتوازية';

  @override
  String get maxHistory => 'الحد الأقصى للسجل';

  @override
  String get calculateFolderSizes => 'حساب أحجام المجلدات';

  @override
  String get exportData => 'تصدير البيانات';

  @override
  String get exportRecordings => 'تسجيلات الجلسات';

  @override
  String sshConfigPreviewHostsFound(int count) {
    return 'تم العثور على $count مضيف';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'لم يتم العثور على مضيفين قابلين للاستيراد في هذا الملف.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'تعذر قراءة ملفات المفاتيح لـ: $hosts. سيتم استيراد هؤلاء المضيفين بدون بيانات اعتماد.';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'تصدير الأرشيف';

  @override
  String get exportArchiveSubtitle =>
      'حفظ الجلسات والإعدادات والمفاتيح في ملف .lfs مشفّر';

  @override
  String get exportQrCode => 'تصدير رمز QR';

  @override
  String get exportQrCodeSubtitle =>
      'مشاركة الجلسات والمفاتيح المحددة عبر رمز QR';

  @override
  String get importArchive => 'استيراد الأرشيف';

  @override
  String get importArchiveSubtitle => 'تحميل البيانات من ملف .lfs';

  @override
  String get importFromSshDir => 'الاستيراد من ~/.ssh';

  @override
  String get importFromSshDirSubtitle =>
      'اختر المضيفين من ملف الإعدادات و/أو المفاتيح الخاصة من ~/.ssh';

  @override
  String get sshDirImportHostsSection => 'المضيفون من ملف الإعدادات';

  @override
  String get sshDirImportKeysSection => 'المفاتيح في ~/.ssh';

  @override
  String importSshKeysFound(int count) {
    return 'تم العثور على $count مفتاح — اختر أيها تريد استيراده';
  }

  @override
  String get importSshKeysNoneFound =>
      'لم يتم العثور على مفاتيح خاصة في ~/.ssh.';

  @override
  String get sshKeyAlreadyImported => 'موجود بالفعل في المخزن';

  @override
  String get setMasterPasswordHint => 'عيّن كلمة مرور رئيسية لتشفير الأرشيف.';

  @override
  String get passwordsDoNotMatch => 'كلمات المرور غير متطابقة';

  @override
  String get passwordStrengthWeak => 'ضعيفة';

  @override
  String get passwordStrengthModerate => 'متوسطة';

  @override
  String get passwordStrengthStrong => 'قوية';

  @override
  String get passwordStrengthVeryStrong => 'قوية جدًا';

  @override
  String get tierPlaintextLabel => 'نص عادي';

  @override
  String get tierPlaintextSubtitle => 'بدون تشفير — أذونات الملفات فقط';

  @override
  String get tierKeychainLabel => 'سلسلة مفاتيح';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'يوجد المفتاح في $keychain — فتح تلقائي عند الإطلاق';
  }

  @override
  String get tierKeychainUnavailable =>
      'سلسلة مفاتيح النظام غير متوفرة في هذه النسخة.';

  @override
  String get tierHardwareLabel => 'جهاز';

  @override
  String get tierParanoidLabel => 'كلمة المرور الرئيسية (Paranoid)';

  @override
  String get tierHardwareUnavailable =>
      'خزينة الأجهزة غير متاحة في هذا التثبيت.';

  @override
  String get pinLabel => 'كلمة المرور';

  @override
  String get l2UnlockTitle => 'كلمة المرور مطلوبة';

  @override
  String get l2UnlockHint => 'أدخل كلمة المرور القصيرة للمتابعة';

  @override
  String get l2WrongPassword => 'كلمة مرور خاطئة';

  @override
  String get l3UnlockTitle => 'أدخل كلمة المرور';

  @override
  String get l3UnlockHint => 'كلمة المرور تفتح الخزينة المرتبطة بالأجهزة';

  @override
  String get l3WrongPin => 'كلمة مرور خاطئة';

  @override
  String tierCooldownHint(int seconds) {
    return 'أعد المحاولة بعد $seconds ث';
  }

  @override
  String exportedTo(String path) {
    return 'تم التصدير إلى: $path';
  }

  @override
  String exportFailed(String error) {
    return 'فشل التصدير: $error';
  }

  @override
  String get pathToLfsFile => 'مسار ملف .lfs';

  @override
  String get dataLocation => 'موقع البيانات';

  @override
  String get dataStorageSection => 'التخزين';

  @override
  String get pathCopied => 'تم نسخ المسار إلى الحافظة';

  @override
  String get urlCopied => 'تم نسخ الرابط إلى الحافظة';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — عميل SSH/SFTP';
  }

  @override
  String get sourceCode => 'الشيفرة المصدرية';

  @override
  String get logIsEmpty => 'السجل فارغ';

  @override
  String logExportedTo(String path) {
    return 'تم تصدير السجل إلى: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'فشل تصدير السجل: $error';
  }

  @override
  String get logsCleared => 'تم مسح السجلات';

  @override
  String get copiedToClipboard => 'تم النسخ إلى الحافظة';

  @override
  String get copyLog => 'نسخ السجل';

  @override
  String get exportLog => 'تصدير السجل';

  @override
  String get clearLogs => 'مسح السجلات';

  @override
  String get local => 'محلي';

  @override
  String get remote => 'بعيد';

  @override
  String get pickFolder => 'اختيار مجلد';

  @override
  String get refresh => 'تحديث';

  @override
  String get up => 'أعلى';

  @override
  String get emptyDirectory => 'مجلد فارغ';

  @override
  String get cancelSelection => 'إلغاء التحديد';

  @override
  String get openSftpBrowser => 'فتح متصفح SFTP';

  @override
  String get openSshTerminal => 'فتح طرفية SSH';

  @override
  String get noActiveFileBrowsers => 'لا توجد متصفحات ملفات نشطة';

  @override
  String get useSftpFromSessions => 'استخدم \"SFTP\" من الجلسات';

  @override
  String get saveLogAs => 'حفظ السجل باسم';

  @override
  String get chooseSaveLocation => 'اختر موقع الحفظ';

  @override
  String get forward => 'للأمام';

  @override
  String get name => 'الاسم';

  @override
  String get size => 'الحجم';

  @override
  String get modified => 'تاريخ التعديل';

  @override
  String get mode => 'الصلاحيات';

  @override
  String get owner => 'المالك';

  @override
  String get connectionError => 'خطأ في الاتصال';

  @override
  String get resizeWindowToViewFiles => 'غيّر حجم النافذة لعرض الملفات';

  @override
  String get completed => 'مكتمل';

  @override
  String get connected => 'متصل';

  @override
  String get disconnected => 'غير متصل';

  @override
  String a11yConnectingTo(String host) {
    return 'جارٍ الاتصال بـ $host';
  }

  @override
  String a11yConnectedTo(String host) {
    return 'تم الاتصال بـ $host';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return 'تم قطع الاتصال بـ $host';
  }

  @override
  String a11yConnectionFailed(String host) {
    return 'فشل الاتصال بـ $host';
  }

  @override
  String get exit => 'خروج';

  @override
  String get exitConfirmation => 'سيتم قطع الجلسات النشطة. هل تريد الخروج؟';

  @override
  String get hintFolderExample => 'مثال: Production';

  @override
  String get credentialsNotSet => 'لم يتم تعيين بيانات الاعتماد';

  @override
  String get exportSessionsViaQr => 'تصدير الجلسات عبر QR';

  @override
  String get qrTooManyForSingleCode =>
      'جلسات كثيرة جداً لرمز QR واحد. ألغِ تحديد بعضها أو استخدم تصدير .lfs.';

  @override
  String get qrTooLarge =>
      'كبير جداً — ألغِ تحديد بعض العناصر أو استخدم تصدير ملف .lfs.';

  @override
  String get showQr => 'عرض QR';

  @override
  String get sort => 'ترتيب';

  @override
  String get resizePanelDivider => 'تغيير حجم فاصل اللوحات';

  @override
  String get youreRunningLatest => 'أنت تستخدم أحدث إصدار';

  @override
  String get liveLog => 'سجل مباشر';

  @override
  String get archivedLog => 'سجل مؤرشف';

  @override
  String get loggingLevel => 'مستوى السجل';

  @override
  String get loggingLevelSubtitleInfo => 'إدخالات روتينية + تحذيرات + أخطاء';

  @override
  String get loggingLevelSubtitleWarn => 'المسارات المتدهورة والأخطاء فقط';

  @override
  String get loggingLevelSubtitleError => 'الأخطاء فقط';

  @override
  String get loggingLevelSubtitleOff => 'لا تُكتب سجلات روتينية';

  @override
  String transferNItems(int count) {
    return 'نقل $count عنصر';
  }

  @override
  String get time => 'الوقت';

  @override
  String get failed => 'فشل';

  @override
  String get errOperationNotPermitted => 'العملية غير مسموح بها';

  @override
  String get errNoSuchFileOrDirectory => 'لا يوجد ملف أو مجلد بهذا الاسم';

  @override
  String get errNoSuchProcess => 'لا توجد عملية بهذا المعرّف';

  @override
  String get errIoError => 'خطأ في الإدخال/الإخراج';

  @override
  String get errBadFileDescriptor => 'واصف ملف غير صالح';

  @override
  String get errResourceTemporarilyUnavailable => 'المورد غير متاح مؤقتاً';

  @override
  String get errOutOfMemory => 'نفدت الذاكرة';

  @override
  String get errPermissionDenied => 'تم رفض الإذن';

  @override
  String get errFileExists => 'الملف موجود بالفعل';

  @override
  String get errNotADirectory => 'ليس مجلداً';

  @override
  String get errIsADirectory => 'هو مجلد';

  @override
  String get errInvalidArgument => 'وسيطة غير صالحة';

  @override
  String get errTooManyOpenFiles => 'عدد الملفات المفتوحة كبير جداً';

  @override
  String get errNoSpaceLeftOnDevice => 'لا توجد مساحة متبقية على الجهاز';

  @override
  String get errReadOnlyFileSystem => 'نظام ملفات للقراءة فقط';

  @override
  String get errBrokenPipe => 'Broken pipe';

  @override
  String get errFileNameTooLong => 'اسم الملف طويل جداً';

  @override
  String get errDirectoryNotEmpty => 'المجلد ليس فارغاً';

  @override
  String get errAddressAlreadyInUse => 'العنوان مستخدم بالفعل';

  @override
  String get errCannotAssignAddress => 'لا يمكن تعيين العنوان المطلوب';

  @override
  String get errNetworkIsDown => 'الشبكة معطّلة';

  @override
  String get errNetworkIsUnreachable => 'الشبكة غير قابلة للوصول';

  @override
  String get errConnectionResetByPeer =>
      'أُعيد تعيين الاتصال من قبل الطرف الآخر';

  @override
  String get errConnectionTimedOut => 'انتهت مهلة الاتصال';

  @override
  String get errConnectionRefused => 'تم رفض الاتصال';

  @override
  String get errHostIsDown => 'المضيف معطّل';

  @override
  String get errNoRouteToHost => 'لا يوجد مسار إلى المضيف';

  @override
  String get errConnectionAborted => 'تم إجهاض الاتصال';

  @override
  String get errAlreadyConnected => 'متصل بالفعل';

  @override
  String get errNotConnected => 'غير متصل';

  @override
  String errSshConnectFailed(String host, int port) {
    return 'فشل الاتصال بـ $host:$port';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return 'فشلت المصادقة لـ $user@$host';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return 'فشل الاتصال بـ $host:$port';
  }

  @override
  String get errSshAuthAborted => 'تم إلغاء المصادقة';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return 'تم رفض مفتاح المضيف لـ $host:$port — اقبل مفتاح المضيف أو تحقق من known_hosts';
  }

  @override
  String get errSshOpenShellFailed => 'فشل فتح جلسة shell';

  @override
  String get errSshLoadKeyFileFailed => 'فشل تحميل ملف مفتاح SSH';

  @override
  String get errSshParseKeyFailed => 'فشل تحليل بيانات مفتاح PEM';

  @override
  String get errSshConnectionDisposed => 'تم التخلص من الاتصال';

  @override
  String get errSshNotConnected => 'غير متصل';

  @override
  String get errConnectionFailed => 'فشل الاتصال';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'انتهت مهلة الاتصال بعد $seconds ثانية';
  }

  @override
  String get errSessionClosed => 'تم إغلاق الجلسة';

  @override
  String errSftpInitFailed(String error) {
    return 'فشلت تهيئة SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'فشل التنزيل: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'منتقي المجلدات في النظام غير متاح. جرّب موقعاً آخر أو تحقق من أذونات تخزين التطبيق.';

  @override
  String get biometricUnlockPrompt => 'فتح قفل LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'الفتح بالبصمة';

  @override
  String get biometricUnlockSubtitle =>
      'لا تحتاج إلى كتابة كلمة المرور — افتح القفل باستخدام مستشعر البصمة في الجهاز.';

  @override
  String get biometricEnableFailed => 'تعذّر تفعيل الفتح بالبصمة.';

  @override
  String get biometricUnlockFailed =>
      'فشل الفتح بالبصمة. أدخل كلمة المرور الرئيسية.';

  @override
  String get biometricUnlockCancelled => 'تم إلغاء الفتح بالبصمة.';

  @override
  String get biometricNotEnrolled => 'لا توجد بصمة مسجلة على هذا الجهاز.';

  @override
  String get biometricSensorNotAvailable =>
      'لا يحتوي هذا الجهاز على مستشعر بصمة.';

  @override
  String get biometricSystemServiceMissing =>
      'خدمة بصمة الإصبع (fprintd) غير مثبتة. راجع README ← التثبيت.';

  @override
  String get currentPasswordIncorrect => 'كلمة المرور الحالية غير صحيحة';

  @override
  String get wrongPassword => 'كلمة مرور خاطئة';

  @override
  String get lockScreenTitle => 'LetsFLUTssh مُقفل';

  @override
  String get lockScreenSubtitle =>
      'أدخل كلمة المرور الرئيسية أو استخدم المقاييس الحيوية للمتابعة.';

  @override
  String get unlock => 'فتح القفل';

  @override
  String get autoLockTitle => 'القفل التلقائي بعد الخمول';

  @override
  String get autoLockSubtitle =>
      'قفل الواجهة بعد هذه المدة من الخمول. يُمحى مفتاح قاعدة البيانات ويُغلق المخزن المشفّر عند كل قفل؛ وتبقى الجلسات النشطة متصلة عبر ذاكرة تخزين مؤقت للبيانات لكل جلسة، تُفرَّغ عند إغلاق الجلسة.';

  @override
  String get autoLockOff => 'معطّل';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes دقيقة',
      many: '$minutes دقيقة',
      few: '$minutes دقائق',
      two: 'دقيقتان',
      one: 'دقيقة واحدة',
      zero: '$minutes دقيقة',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'تم رفض التحديث: الملفات التي تم تنزيلها ليست موقّعة بمفتاح الإصدار المثبّت في التطبيق. قد يعني هذا أنه تم العبث بالتنزيل أثناء النقل، أو أن الإصدار الحالي ليس مخصصًا لهذا التثبيت. لا تقم بالتثبيت — أعد التثبيت يدويًا من صفحة الإصدارات الرسمية.';

  @override
  String get errReleaseManifestUnavailable =>
      'تعذر الوصول إلى manifest الإصدار. على الأرجح مشكلة في الشبكة، أو أن الإصدار لا يزال قيد النشر. جرّب مرة أخرى بعد دقائق.';

  @override
  String get updateSecurityWarningTitle => 'فشل التحقق من التحديث';

  @override
  String get updateReinstallAction => 'فتح صفحة الإصدارات';

  @override
  String get errLfsNotArchive => 'الملف المحدد ليس أرشيف LetsFLUTssh.';

  @override
  String get errLfsDecryptFailed =>
      'كلمة المرور الرئيسية خاطئة أو أرشيف .lfs تالف';

  @override
  String get errLfsArchiveTruncated =>
      'الأرشيف غير مكتمل. أعد التنزيل أو إعادة التصدير من الجهاز الأصلي.';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'الأرشيف كبير جدًا ($sizeMb ميجابايت). الحد الأقصى هو $limitMb ميجابايت — تم الإلغاء قبل فك التشفير لحماية الذاكرة.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'إدخال known_hosts كبير جدًا ($sizeMb ميجابايت). الحد الأقصى هو $limitMb ميجابايت — تم الإلغاء للحفاظ على استجابة الاستيراد.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'فشل الاستيراد — تمت استعادة بياناتك إلى الحالة السابقة. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'يستخدم الأرشيف المخطط v$found، لكن هذا الإصدار يدعم فقط حتى v$supported. قم بتحديث التطبيق لاستيراده.';
  }

  @override
  String get progressReadingArchive => 'قراءة الأرشيف…';

  @override
  String get progressDecrypting => 'فك التشفير…';

  @override
  String get progressCollectingData => 'جمع البيانات…';

  @override
  String get progressEncrypting => 'تشفير…';

  @override
  String get progressWritingArchive => 'كتابة الأرشيف…';

  @override
  String get progressWorking => 'قيد المعالجة…';

  @override
  String get importFromLink => 'استيراد من رابط QR';

  @override
  String get importFromLinkSubtitle =>
      'الصق رابط letsflutssh:// المنسوخ من جهاز آخر';

  @override
  String get pasteImportLinkTitle => 'لصق رابط الاستيراد';

  @override
  String get pasteImportLinkDescription =>
      'الصق رابط letsflutssh://import?d=… (أو الحمولة الخام) الذي تم إنشاؤه على جهاز آخر. لا حاجة للكاميرا.';

  @override
  String get pasteFromClipboard => 'لصق من الحافظة';

  @override
  String get invalidImportLink => 'الرابط لا يحتوي على حمولة LetsFLUTssh صالحة';

  @override
  String get importAction => 'استيراد';

  @override
  String get noTagsAvailable =>
      'لا توجد علامات بعد — أنشئ واحدة في الأدوات → العلامات.';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get protocol => 'البروتوكول';

  @override
  String get typeLabel => 'النوع';

  @override
  String get folder => 'المجلد';

  @override
  String nSubitems(int count) {
    return '$count عنصر';
  }

  @override
  String get subitems => 'العناصر';

  @override
  String get grantPermission => 'منح الإذن';

  @override
  String get storagePermissionLimited =>
      'وصول محدود — امنح إذن التخزين الكامل لجميع الملفات';

  @override
  String progressConnecting(String host, int port) {
    return 'الاتصال بـ $host:$port';
  }

  @override
  String get progressVerifyingHostKey => 'التحقق من مفتاح المضيف';

  @override
  String progressAuthenticating(String user) {
    return 'المصادقة كـ $user';
  }

  @override
  String get progressOpeningShell => 'فتح الطرفية';

  @override
  String get progressOpeningSftp => 'فتح قناة SFTP';

  @override
  String get transfersLabel => 'عمليات النقل:';

  @override
  String transferCountActive(int count) {
    return '$count نشطة';
  }

  @override
  String transferCountQueued(int count) {
    return '، $count في الانتظار';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count في السجل';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'تم الإنشاء: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'بدأ: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'انتهى: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'المدة: $duration';
  }

  @override
  String get transferStatusQueued => 'في الانتظار';

  @override
  String get fileConflictTitle => 'الملف موجود بالفعل';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" موجود بالفعل في $targetDir. ماذا تريد أن تفعل؟';
  }

  @override
  String get fileConflictSkip => 'تخطي';

  @override
  String get fileConflictKeepBoth => 'الاحتفاظ بكلاهما';

  @override
  String get fileConflictReplace => 'استبدال';

  @override
  String get fileConflictApplyAll => 'تطبيق على جميع الملفات المتبقية';

  @override
  String get folderNameLabel => 'اسم المجلد';

  @override
  String folderAlreadyExists(String name) {
    return 'المجلد \"$name\" موجود بالفعل';
  }

  @override
  String get dropKeyFileHere => 'اسحب ملف المفتاح هنا';

  @override
  String get sessionNoCredentials =>
      'الجلسة لا تحتوي على بيانات اعتماد — قم بتعديلها لإضافة كلمة مرور أو مفتاح';

  @override
  String dragItemCount(int count) {
    return '$count عناصر';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'تحديد الكل ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'الحجم: $size كيلوبايت / $max كيلوبايت كحد أقصى';
  }

  @override
  String get noActiveTerminals => 'لا توجد أجهزة طرفية نشطة';

  @override
  String get connectFromSessionsTab => 'اتصل من علامة تبويب الجلسات';

  @override
  String fileNotFound(String path) {
    return 'الملف غير موجود: $path';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count عناصر، $size';
  }

  @override
  String get maximize => 'تكبير';

  @override
  String get restore => 'استعادة';

  @override
  String get duplicateDownShortcut => 'تكرار للأسفل (Ctrl+Shift+\\)';

  @override
  String get security => 'الأمان';

  @override
  String get knownHosts => 'المضيفون المعروفون';

  @override
  String get knownHostsSubtitle => 'إدارة بصمات خوادم SSH الموثوقة';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مضيف معروف',
      one: 'مضيف معروف واحد',
      zero: 'لا يوجد مضيفون معروفون',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'لا يوجد مضيفون معروفون. اتصل بخادم لإضافة واحد.';

  @override
  String get removeHost => 'إزالة المضيف';

  @override
  String removeHostConfirm(String host) {
    return 'إزالة $host من المضيفين المعروفين؟ سيتم التحقق من المفتاح مرة أخرى عند الاتصال التالي.';
  }

  @override
  String get clearAllKnownHosts => 'مسح جميع المضيفين المعروفين';

  @override
  String get clearAllKnownHostsConfirm =>
      'إزالة جميع المضيفين المعروفين؟ سيحتاج كل مفتاح خادم إلى إعادة التحقق.';

  @override
  String get clearedAllHosts => 'تم مسح جميع المضيفين المعروفين';

  @override
  String removedHost(String host) {
    return 'تمت إزالة $host';
  }

  @override
  String get tools => 'أدوات';

  @override
  String get sshKeys => 'مفاتيح SSH';

  @override
  String get sshKeysSubtitle => 'إدارة أزواج مفاتيح SSH للمصادقة';

  @override
  String get noKeys => 'لا توجد مفاتيح SSH. قم بالاستيراد أو التوليد.';

  @override
  String get generateKey => 'توليد مفتاح';

  @override
  String get addKey => 'إضافة مفتاح';

  @override
  String get addKeyMenuPaste => 'لصق PEM';

  @override
  String get filePickerUnavailable => 'منتقي الملفات غير متاح في هذا النظام';

  @override
  String get importKey => 'استيراد مفتاح';

  @override
  String get keyLabel => 'اسم المفتاح';

  @override
  String get keyLabelHint => 'مثال: خادم العمل، GitHub';

  @override
  String get selectKeyType => 'نوع المفتاح';

  @override
  String get generating => 'جارٍ التوليد...';

  @override
  String keyGenerated(String label) {
    return 'تم توليد المفتاح: $label';
  }

  @override
  String keyImported(String label) {
    return 'تم استيراد المفتاح: $label';
  }

  @override
  String get deleteKey => 'حذف المفتاح';

  @override
  String deleteKeyConfirm(String label) {
    return 'حذف المفتاح \"$label\"؟ ستفقد الجلسات التي تستخدمه الوصول.';
  }

  @override
  String keyDeleted(String label) {
    return 'تم حذف المفتاح: $label';
  }

  @override
  String get publicKey => 'المفتاح العام';

  @override
  String get publicKeyCopied => 'تم نسخ المفتاح العام إلى الحافظة';

  @override
  String get sshCertificate => 'Certificate';

  @override
  String get certImport => 'استيراد certificate';

  @override
  String get certImportTooltip =>
      'اربط شهادة OpenSSH موقّعة من CA الخاص بك (ملف `-cert.pub` من `ssh-keygen -s …`). استخدم هذا عندما تتحقق الخوادم عبر توقيع CA بدلاً من `authorized_keys`. تجاوز إذا كانت خوادمك تستخدم plain key auth.';

  @override
  String get certImportPickerTitle => 'اختر ملف certificate من نوع OpenSSH';

  @override
  String get certValidFrom => 'ساري من';

  @override
  String get certValidTo => 'ساري حتى';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => 'صلاحية هذا الـ certificate ستنتهي قريبًا.';

  @override
  String get certExpired => 'منتهي الصلاحية';

  @override
  String get certRemove => 'إزالة الـ certificate';

  @override
  String get certRemoveConfirmTitle => 'إزالة الـ certificate؟';

  @override
  String get certRemoveConfirmBody =>
      'بعد الإزالة ستعود الجلسة إلى مصادقة public key العادية عند الاتصال.';

  @override
  String errCertParse(String detail) {
    return 'تعذر تحليل الـ certificate: $detail';
  }

  @override
  String get errCertPairFingerprintMismatch =>
      'هذا الـ certificate غير مرتبط بالمفتاح المختار.';

  @override
  String get pastePrivateKey => 'لصق المفتاح الخاص (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'بيانات مفتاح PEM غير صالحة';

  @override
  String get selectFromKeyStore => 'اختر من مخزن المفاتيح';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مفاتيح',
      one: 'مفتاح واحد',
      zero: 'لا توجد مفاتيح',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'تم التوليد';

  @override
  String get passphrase => 'عبارة المرور';

  @override
  String get enterMasterPassword =>
      'أدخل كلمة المرور الرئيسية للوصول إلى بيانات الاعتماد المحفوظة.';

  @override
  String get wrongMasterPassword => 'كلمة مرور خاطئة. حاول مرة أخرى.';

  @override
  String get currentPassword => 'كلمة المرور الحالية';

  @override
  String get forgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get credentialsReset => 'تم حذف جميع بيانات الاعتماد المحفوظة';

  @override
  String get migrationToast => 'تمت ترقية التخزين إلى أحدث تنسيق';

  @override
  String get dbCorruptTitle => 'تعذر فتح قاعدة البيانات';

  @override
  String get dbCorruptBody =>
      'تعذّر فتح البيانات الموجودة على القرص. جرّب بيانات اعتماد أخرى أو أعد التعيين للبدء من جديد.';

  @override
  String get dbCorruptWarning =>
      'سيؤدي الإعادة إلى حذف قاعدة البيانات المشفرة وجميع الملفات المتعلقة بالأمان نهائيًا. لن تتم استعادة أي بيانات.';

  @override
  String get dbCorruptTryOther => 'تجربة بيانات اعتماد أخرى';

  @override
  String get dbCorruptResetContinue => 'إعادة تعيين وإعداد جديد';

  @override
  String get dbCorruptExit => 'الخروج من LetsFLUTssh';

  @override
  String get tierResetTitle => 'مطلوب إعادة تعيين أمني';

  @override
  String get tierResetBody =>
      'يحتوي هذا التثبيت على بيانات أمنية من إصدار سابق من LetsFLUTssh كان يستخدم نموذج طبقات مختلفًا. النموذج الجديد يعتبر تغييرًا غير متوافق مع السابق — لا يوجد مسار ترحيل تلقائي. للمتابعة، يجب حذف كل الجلسات المحفوظة وبيانات الاعتماد ومفاتيح SSH والمضيفين المعروفين، وتشغيل معالج الإعداد الأولي من جديد.';

  @override
  String get tierResetWarning =>
      'سيؤدي اختيار «إعادة تعيين وإعداد جديد» إلى حذف قاعدة البيانات المشفرة وجميع الملفات الأمنية بشكل دائم. إذا كنت بحاجة إلى استرداد بياناتك، فأغلق التطبيق الآن وأعد تثبيت الإصدار السابق من LetsFLUTssh لتصدير بياناتك أولًا.';

  @override
  String get tierResetResetContinue => 'إعادة تعيين وإعداد جديد';

  @override
  String get tierResetExit => 'إنهاء LetsFLUTssh';

  @override
  String get derivingKey => 'جارٍ اشتقاق مفتاح التشفير...';

  @override
  String get securitySetupTitle => 'إعداد الأمان';

  @override
  String get keychainAvailable => 'متاحة';

  @override
  String get changeSecurityTierConfirm =>
      'يتم إعادة تشفير قاعدة البيانات بالمستوى الجديد. لا يمكن المقاطعة — اترك التطبيق مفتوحًا حتى الانتهاء.';

  @override
  String get changeSecurityTierDone => 'تم تغيير مستوى الأمان';

  @override
  String get changeSecurityTierFailed => 'تعذر تغيير مستوى الأمان';

  @override
  String get firstLaunchSecurityTitle => 'تم تفعيل التخزين الآمن';

  @override
  String get firstLaunchSecurityBody =>
      'يتم تشفير بياناتك بمفتاح محفوظ في سلسلة مفاتيح النظام. فتح القفل على هذا الجهاز تلقائي.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'يتوفر على هذا الجهاز تخزين مدعوم بالعتاد. قم بالترقية من الإعدادات ← الأمان لربط TPM / Secure Enclave.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'التخزين المدعوم بالعتاد غير متاح على هذا الجهاز.';

  @override
  String get firstLaunchSecurityOpenSettings => 'فتح الإعدادات';

  @override
  String get wizardReducedBanner =>
      'سلسلة مفاتيح النظام غير متاحة في هذا التثبيت. اختر بين «بدون تشفير» (T0) وكلمة مرور رئيسية (Paranoid). ثبّت gnome-keyring أو kwallet أو أي مزوّد libsecret آخر لتفعيل مستوى Keychain.';

  @override
  String get tierBadgeCurrent => 'الحالي';

  @override
  String get securitySetupEnable => 'تفعيل';

  @override
  String get securitySetupApply => 'تطبيق';

  @override
  String get hwProbeLinuxDeviceMissing =>
      'لم يتم اكتشاف TPM على /dev/tpmrm0. فعّل fTPM / PTT في BIOS إن كان الجهاز يدعم ذلك، وإلا فإن المستوى العتادي غير متاح على هذا الجهاز.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'لم يتم تثبيت tpm2-tools. نفّذ `sudo apt install tpm2-tools` (أو ما يقابله في توزيعتك) لتفعيل المستوى العتادي.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'فحص المستوى العتادي فشل. تحقق من صلاحيات /dev/tpmrm0 وقواعد udev — التفاصيل في السجلات.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'لم يتم اكتشاف TPM 2.0. فعّل fTPM / PTT في برنامج UEFI الثابت، أو اقبل أن المستوى العتادي غير متاح على هذا الجهاز — يعود التطبيق إلى مخزن بيانات الاعتماد المستند إلى البرامج.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'لا يمكن الوصول إلى Microsoft Platform Crypto Provider ولا إلى Software Key Storage Provider — من المحتمل أن يكون نظام تشفير Windows الفرعي تالفًا أو أن سياسة المجموعة تحظر CNG. تحقق من عارض الأحداث → سجلات التطبيقات والخدمات.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'هذا الـ Mac لا يحتوي على Secure Enclave (Intel Mac قبل 2017 بدون شريحة أمان T1 / T2). المستوى العتادي غير متاح؛ استخدم كلمة المرور الرئيسية بدلاً من ذلك.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'لم يتم تعيين كلمة مرور تسجيل الدخول على هذا الـ Mac. يتطلب إنشاء مفتاح Secure Enclave ذلك — اضبطها في إعدادات النظام ← Touch ID وكلمة المرور (أو كلمة مرور تسجيل الدخول).';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'رفض Secure Enclave هوية توقيع التطبيق (-34018). شغّل سكربت `macos-resign.sh` المرفق بالإصدار لمنح هذه النسخة هوية موقَّعة ذاتيًا وثابتة، ثم أعد تشغيل التطبيق.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'لم يتم تعيين رمز الجهاز. يتطلب إنشاء مفتاح Secure Enclave ذلك — اضبط الرمز في الإعدادات ← Face ID والرمز (أو Touch ID والرمز).';

  @override
  String get hwProbeIosSimulator =>
      'يعمل على iOS Simulator الذي لا يحتوي على Secure Enclave. المستوى العتادي متاح فقط على أجهزة iOS الفعلية.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'يتطلب المستوى العتادي Android 9 أو أحدث (StrongBox وإلغاء صلاحية المفتاح عند تغيير التسجيل غير موثوقين في الإصدارات الأقدم).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'لا يحتوي هذا الجهاز على أجهزة بيومترية (بصمة أو وجه). استخدم كلمة المرور الرئيسية.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'لا توجد بصمة مسجلة. أضف بصمة أو وجهًا في الإعدادات ← الأمان والخصوصية ← المقاييس الحيوية، ثم أعد تمكين المستوى العتادي.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'الأجهزة البيومترية غير قابلة للاستخدام مؤقتًا (قفل بعد محاولات فاشلة أو تحديث أمني معلق). أعد المحاولة بعد بضع دقائق.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'رفض Android Keystore دعم مفتاح أجهزة في نسخة هذا الجهاز (StrongBox غير متوفر، أو ROM مخصص، أو خلل في برنامج التشغيل). مستوى الأجهزة غير متاح.';

  @override
  String get securityRecheck => 'إعادة فحص دعم المستويات';

  @override
  String get securityRecheckUpdated =>
      'تم تحديث دعم المستويات — انظر البطاقات أعلاه';

  @override
  String get securityRecheckUnchanged => 'دعم المستويات دون تغيير';

  @override
  String get securityMacosEnableSecureTiers =>
      'فتح المستويات الآمنة على هذا الـ Mac';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'إعادة توقيع التطبيق بشهادة شخصية حتى تعمل سلسلة المفاتيح (T1) و Secure Enclave (T2) بعد التحديثات';

  @override
  String get securityMacosEnableSecureTiersPrompt =>
      'سيطلب macOS كلمة مرورك مرة واحدة';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'تم فتح المستويات الآمنة — T1 و T2 متاحان الآن';

  @override
  String get securityMacosEnableSecureTiersFailed => 'فشل فتح المستويات الآمنة';

  @override
  String get securityMacosOfferTitle =>
      'تفعيل سلسلة المفاتيح + Secure Enclave؟';

  @override
  String get securityMacosOfferBody =>
      'يربط macOS التخزين المشفر بهوية توقيع التطبيق. بدون شهادة مستقرة، ترفض سلسلة المفاتيح (T1) و Secure Enclave (T2) الوصول. يمكننا إنشاء شهادة شخصية موقعة ذاتيًا على هذا الـ Mac وإعادة توقيع التطبيق بها — ستستمر التحديثات في العمل، وستبقى أسرارك عبر الإصدارات. سيطلب macOS كلمة مرور تسجيل الدخول مرة واحدة للوثوق بالشهادة الجديدة.';

  @override
  String get securityMacosOfferAccept => 'تفعيل';

  @override
  String get securityMacosOfferDecline => 'تخطي — اختر T0 أو Paranoid';

  @override
  String get securityMacosRemoveIdentity => 'إزالة هوية التوقيع';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      'يحذف الشهادة الشخصية. بيانات T1 / T2 مرتبطة بها — تحول إلى T0 أو Paranoid أولاً ثم احذف.';

  @override
  String get securityMacosRemoveIdentityConfirmTitle => 'إزالة هوية التوقيع؟';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'يحذف الشهادة الشخصية من سلسلة مفاتيح تسجيل الدخول. ستصبح أسرار T1 / T2 المخزنة غير قابلة للقراءة. سيفتح المعالج للترحيل إلى T0 (نص عادي) أو Paranoid (كلمة مرور رئيسية) قبل الإزالة.';

  @override
  String get securityMacosRemoveIdentitySuccess => 'تمت إزالة هوية التوقيع';

  @override
  String get securityMacosRemoveIdentityFailed => 'فشلت إزالة هوية التوقيع';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus يعمل ولكن لا يوجد secret-service daemon قيد التشغيل. ثبّت gnome-keyring (`sudo apt install gnome-keyring`) أو KWalletManager وتأكد من بدء تشغيله عند تسجيل الدخول.';

  @override
  String get keyringProbeFailed =>
      'لا يمكن الوصول إلى سلسلة مفاتيح نظام التشغيل على هذا الجهاز. راجع السجلات للاطلاع على خطأ المنصة المحدد؛ يعود التطبيق إلى كلمة المرور الرئيسية.';

  @override
  String get snippets => 'المقتطفات';

  @override
  String get snippetsSubtitle => 'إدارة مقتطفات أوامر قابلة لإعادة الاستخدام';

  @override
  String get noSnippets => 'لا توجد مقتطفات بعد';

  @override
  String get addSnippet => 'إضافة مقتطف';

  @override
  String get editSnippet => 'تحرير المقتطف';

  @override
  String get deleteSnippet => 'حذف المقتطف';

  @override
  String deleteSnippetConfirm(String title) {
    return 'حذف المقتطف \"$title\"؟';
  }

  @override
  String get snippetTitle => 'العنوان';

  @override
  String get snippetTitleHint => 'مثال: نشر، إعادة تشغيل الخدمة';

  @override
  String get snippetCommand => 'الأمر';

  @override
  String get snippetCommandHint => 'مثال: sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'الوصف (اختياري)';

  @override
  String get snippetDescriptionHint => 'ما الذي يفعله هذا الأمر؟';

  @override
  String get snippetSaved => 'تم حفظ المقتطف';

  @override
  String snippetDeleted(String title) {
    return 'تم حذف المقتطف \"$title\"';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مقتطف',
      many: '$count مقتطفاً',
      few: '$count مقتطفات',
      two: 'مقتطفان',
      one: 'مقتطف واحد',
      zero: 'لا توجد مقتطفات',
    );
    return '$_temp0';
  }

  @override
  String get pinToSession => 'تثبيت في هذه الجلسة';

  @override
  String get unpinFromSession => 'إلغاء التثبيت من هذه الجلسة';

  @override
  String get pinnedSnippets => 'المثبتة';

  @override
  String get allSnippets => 'الكل';

  @override
  String get commandCopied => 'تم نسخ الأمر';

  @override
  String get snippetTokensHint =>
      'انقر لإدراج عنصر نائب. تُستبدل هذه القيم وقت التشغيل بقيم من الجلسة النشطة:';

  @override
  String get snippetCustomTokensHint =>
      'أي شيء آخر بأقواس مزدوجة يطلب منك قيمة عند تشغيل المقتطف.';

  @override
  String get snippetFillTitle => 'املأ معلمات المقتطف';

  @override
  String get snippetFillSubmit => 'تشغيل';

  @override
  String get broadcastSetDriver => 'بث من هذا الجزء';

  @override
  String get broadcastClearDriver => 'إيقاف البث من هذا الجزء';

  @override
  String get broadcastAddReceiver => 'استقبال البث هنا';

  @override
  String get broadcastRemoveReceiver => 'إيقاف استقبال البث';

  @override
  String get broadcastClearAll => 'إيقاف كل البث';

  @override
  String get broadcastPasteTitle => 'إرسال اللصق إلى كل الأجزاء؟';

  @override
  String broadcastPasteBody(int chars, int count) {
    return 'سيتم إرسال $chars حرفًا إلى $count أجزاء أخرى.';
  }

  @override
  String get broadcastPasteSend => 'إرسال';

  @override
  String get portForwarding => 'إعادة التوجيه';

  @override
  String get portForwardingEmpty => 'لا توجد قواعد بعد';

  @override
  String get addForwardRule => 'إضافة قاعدة';

  @override
  String get editForwardRule => 'تعديل القاعدة';

  @override
  String get deleteForwardRule => 'حذف القاعدة';

  @override
  String get localForward => 'محلي';

  @override
  String get remoteForward => 'بعيد';

  @override
  String get dynamicForward => 'ديناميكي';

  @override
  String get forwardKind => 'النوع';

  @override
  String get bindAddress => 'عنوان الربط';

  @override
  String get bindPort => 'منفذ الربط';

  @override
  String get targetHost => 'الخادم الهدف';

  @override
  String get targetPort => 'المنفذ الهدف';

  @override
  String get forwardDescription => 'الوصف (اختياري)';

  @override
  String get forwardEnabled => 'مفعّل';

  @override
  String get forwardBindWildcardWarning =>
      'الربط بـ 0.0.0.0 ينشر التحويل على جميع الواجهات — غالبًا تريد 127.0.0.1.';

  @override
  String get forwardKindLocalHelp =>
      'محلي: فتح منفذ على هذا الجهاز يمر عبر النفق إلى هدف يمكن الوصول إليه من خادم SSH. مفيد للوصول إلى قواعد بيانات بعيدة أو واجهات إدارة عبر localhost:bindPort.';

  @override
  String get forwardKindRemoteHelp =>
      'بعيد: اطلب من خادم SSH فتح منفذ يمر إلى هدف يمكن الوصول إليه من هذا الجهاز. مفيد لمشاركة خادم تطوير محلي مع مضيف بعيد (قد يحتاج الخادم إلى GatewayPorts yes لربط غير loopback).';

  @override
  String get forwardKindDynamicHelp =>
      'ديناميكي: وكيل SOCKS5 على هذا الجهاز يوجه كل اتصال عبر خادم SSH. وجّه المتصفح أو curl إلى localhost:bindPort لإرسال كل الحركة عبر SSH.';

  @override
  String get proxyJump => 'الاتصال عبر';

  @override
  String get proxyJumpNone => 'اتصال مباشر';

  @override
  String get proxyJumpSavedSession => 'جلسة محفوظة';

  @override
  String get proxyJumpCustom => 'مخصص';

  @override
  String get proxyJumpCustomNote =>
      'القفزات المخصصة تستخدم بيانات اعتماد هذه الجلسة. لمصادقة بستيون مختلفة، احفظ البستيون كجلسة خاصة.';

  @override
  String viaSessionLabel(String label) {
    return 'عبر $label';
  }

  @override
  String get recordSession => 'تسجيل الجلسة';

  @override
  String get recordSessionHelp =>
      'حفظ مخرجات الطرفية على القرص لهذه الجلسة. مشفّر في حالة السكون عندما تحمي كلمة مرور رئيسية أو مفتاح أجهزة قاعدة بيانات الجلسات؛ وإلا يُخزَّن كنص عادي بجانب القاعدة.';

  @override
  String get recordingsBrowserTitle => 'التسجيلات';

  @override
  String get recordingsBrowserSubtitle =>
      'تصفح وإعادة تشغيل وحذف الجلسات المسجلة';

  @override
  String get recordingsEmpty => 'لا توجد تسجيلات بعد';

  @override
  String get playRecording => 'تشغيل';

  @override
  String get deleteRecording => 'حذف';

  @override
  String get recordingPlaybackTitle => 'إعادة تشغيل التسجيل';

  @override
  String get recordingSpeed => 'السرعة';

  @override
  String get recordingSpeedInstant => 'فوري';

  @override
  String get recordingScrubTooltipUnavailable =>
      'Scrub bar يحتاج إلى sidecar index، والتسجيلات القديمة (قبل هذا الإصدار) لا تحتوي عليه. التسجيلات الجديدة ستدعم التمرير.';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

  @override
  String get tags => 'العلامات';

  @override
  String get tagsSubtitle => 'نظّم الجلسات والمجلدات بعلامات ملوّنة';

  @override
  String get noTags => 'لا توجد علامات بعد';

  @override
  String get addTag => 'إضافة علامة';

  @override
  String get deleteTag => 'حذف العلامة';

  @override
  String deleteTagConfirm(String name) {
    return 'حذف العلامة \"$name\"؟ ستُزال من جميع الجلسات والمجلدات.';
  }

  @override
  String get tagName => 'اسم العلامة';

  @override
  String get tagNameHint => 'مثال: Production، Staging';

  @override
  String get tagColor => 'اللون';

  @override
  String get tagCreated => 'تم إنشاء العلامة';

  @override
  String tagDeleted(String name) {
    return 'تم حذف العلامة \"$name\"';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count علامة',
      many: '$count علامة',
      few: '$count علامات',
      two: 'علامتان',
      one: 'علامة واحدة',
      zero: 'لا توجد علامات',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'إدارة العلامات';

  @override
  String get editTags => 'تحرير العلامات';

  @override
  String get fullBackup => 'نسخة احتياطية كاملة';

  @override
  String get sessionsOnly => 'الجلسات';

  @override
  String get presetFullImport => 'استيراد كامل';

  @override
  String get presetSelective => 'انتقائي';

  @override
  String get presetCustom => 'مخصص';

  @override
  String get sessionSshKeys => 'مفاتيح الجلسة (المدير)';

  @override
  String get allManagerKeys => 'جميع المفاتيح في المدير';

  @override
  String get browseFiles => 'تصفح الملفات…';

  @override
  String get sshDirSessionAlreadyImported => 'موجودة في الجلسات بالفعل';

  @override
  String get languageSubtitle => 'لغة الواجهة';

  @override
  String get themeSubtitle => 'داكن أو فاتح أو اتباع النظام';

  @override
  String get uiScaleSubtitle => 'تغيير حجم الواجهة بالكامل';

  @override
  String get terminalFontSizeSubtitle => 'حجم الخط في خرج الطرفية';

  @override
  String get scrollbackLinesSubtitle => 'حجم ذاكرة السجل في الطرفية';

  @override
  String get keepAliveIntervalSubtitle =>
      'الثواني بين حزم SSH keep-alive (0 = متوقف)';

  @override
  String get sshTimeoutSubtitle => 'مهلة الاتصال بالثواني';

  @override
  String get defaultPortSubtitle => 'المنفذ الافتراضي للجلسات الجديدة';

  @override
  String get parallelWorkersSubtitle => 'عدد workers نقل SFTP المتزامنة';

  @override
  String get maxHistorySubtitle => 'الحد الأقصى للأوامر المحفوظة في السجل';

  @override
  String get calculateFolderSizesSubtitle =>
      'إظهار الحجم الإجمالي بجانب المجلدات في الشريط الجانبي';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'الاستعلام عن إصدار جديد على GitHub عند تشغيل التطبيق';

  @override
  String get threatColdDiskTheft => 'سرقة القرص أثناء إيقاف التشغيل';

  @override
  String get threatColdDiskTheftDescription =>
      'جهاز متوقف عن التشغيل يُنزع قرصه ويُقرأ على حاسوب آخر، أو نسخة من ملف قاعدة البيانات أخذها شخص لديه وصول إلى مجلدك الشخصي.';

  @override
  String get threatKeyringFileTheft => 'سرقة ملف keyring / keychain';

  @override
  String get threatKeyringFileTheftDescription =>
      'يقرأ المهاجم ملف مخزن بيانات الاعتماد الخاص بالمنصة مباشرة من القرص (libsecret keyring، Windows Credential Manager، macOS login keychain) ويستخرج منه wrapped key الخاص بقاعدة البيانات. يمنع المستوى العتادي ذلك بصرف النظر عن كلمة المرور لأن الشريحة ترفض تصدير مادة المفاتيح؛ أما مستوى keychain فيحتاج كلمة مرور إضافية وإلا أمكن فتح الملف المسروق بكلمة مرور تسجيل دخول النظام وحدها.';

  @override
  String get modifierOnlyWithPassword => 'مع كلمة مرور فقط';

  @override
  String get threatBystanderUnlockedMachine => 'متطفّل على جهاز غير مقفول';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'يقترب شخص ما من حاسوبك غير المقفول ويفتح التطبيق أثناء غيابك.';

  @override
  String get threatLiveRamForensicsLocked => 'تفريغ RAM على جهاز مقفول';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'يُجمِّد المهاجم RAM (أو يلتقطها عبر DMA) ويستخرج مادة المفاتيح التي ما زالت حاضرة في اللقطة، حتى والتطبيق مقفول.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'اختراق نواة النظام أو سلسلة المفاتيح';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'ثغرة في النواة، أو تسريب من سلسلة المفاتيح، أو باب خلفي في شريحة الأمان العتادية. يصبح نظام التشغيل مهاجماً بدلاً من أن يكون مورداً موثوقاً.';

  @override
  String get threatOfflineBruteForce =>
      'هجوم brute-force بلا اتصال على كلمة مرور ضعيفة';

  @override
  String get threatOfflineBruteForceDescription =>
      'مهاجم يملك نسخة من wrapped key أو sealed blob يجرّب كل كلمات المرور بوتيرته الخاصة دون أي rate limit.';

  @override
  String get legendProtects => 'محمي';

  @override
  String get legendDoesNotProtect => 'غير محمي';

  @override
  String get colT0 => 'T0 نص صريح';

  @override
  String get colT1 => 'T1 سلسلة المفاتيح';

  @override
  String get colT1Password => 'T1 + كلمة مرور';

  @override
  String get colT1PasswordBiometric => 'T1 + كلمة مرور + بصمة حيوية';

  @override
  String get colT2Password => 'T2 + كلمة مرور';

  @override
  String get colT2PasswordBiometric => 'T2 + كلمة مرور + بصمة حيوية';

  @override
  String get colParanoid => 'Paranoid';

  @override
  String get securityComparisonTableThreatColumn => 'التهديد';

  @override
  String get compareAllTiers => 'مقارنة جميع المستويات';

  @override
  String get resetAllDataTitle => 'إعادة تعيين جميع البيانات';

  @override
  String get resetAllDataSubtitle =>
      'حذف جميع الجلسات والمفاتيح والإعدادات ومكونات الأمان. يُمسح أيضاً مدخلات سلسلة المفاتيح وفتحات hardware vault.';

  @override
  String get resetAllDataConfirmTitle => 'إعادة تعيين جميع البيانات؟';

  @override
  String get resetAllDataConfirmBody =>
      'سيتم حذف جميع الجلسات ومفاتيح SSH وقائمة known_hosts والمقتطفات والوسوم والتفضيلات وجميع مكونات الأمان (مدخلات سلسلة المفاتيح، بيانات hardware vault، الطبقة البيومترية) بشكل دائم. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get resetAllDataConfirmAction => 'إعادة تعيين كل شيء';

  @override
  String resetAllDataConfirmTypePrompt(String phrase) {
    return 'اكتب $phrase أدناه للتأكيد:';
  }

  @override
  String get resetAllDataInProgress => 'جارٍ إعادة التعيين…';

  @override
  String get resetAllDataDone => 'تمت إعادة تعيين جميع البيانات';

  @override
  String get resetAllDataFailed => 'فشلت إعادة التعيين';

  @override
  String get recordingsTitle => 'التسجيلات';

  @override
  String get recordingsStorageUsedLabel => 'المستخدم';

  @override
  String get recordingsCapLabel => 'الحد الأقصى';

  @override
  String get recordingsCapHint =>
      'حد صارم على مجلد recordings/. عند التجاوز يُحذف أقدم تسجيل أولاً؛ التسجيل الجاري لا يُمَس أبداً.';

  @override
  String get recordingsClearAllAction => 'حذف كل التسجيلات';

  @override
  String get recordingsClearAllConfirmTitle => 'حذف كل التسجيلات؟';

  @override
  String get recordingsClearAllConfirmBody =>
      'سيتم حذف كل جلسة مسجلة تحت <app>/recordings/. التسجيل الجاري حالياً (إن وُجد) يبقى. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String recordingsClearAllResult(int count) {
    return 'تم حذف $count تسجيلاً';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return 'تم تحديث الحد الأقصى. تم تحرير $bytes.';
  }

  @override
  String get recordingsCapChangedNoChange =>
      'تم تحديث الحد الأقصى. لا شيء لحذفه.';

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
      'يتطلب القفل التلقائي كلمة مرور على المستوى الحالي.';

  @override
  String get recommendedBadge => 'موصى به';

  @override
  String get tierHardwareSubtitleHonest =>
      'متقدم: مفتاح مرتبط بالعتاد، محمي دائماً بكلمة مرور. البيانات غير قابلة للاسترداد إذا فُقدت شريحة هذا الجهاز أو استُبدلت.';

  @override
  String get tierParanoidSubtitleHonest =>
      'بديل: كلمة مرور رئيسية، دون الوثوق بنظام التشغيل. يحمي من اختراق نظام التشغيل. لا يُحسّن الحماية أثناء التشغيل مقارنة بـ T1/T2.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'تهديدات runtime (malware من المستخدم نفسه، تفريغ ذاكرة عملية نشطة) تظهر على شكل ✗ في جميع المستويات. تتم معالجتها عبر ميزات تخفيف منفصلة تُطبَّق بصرف النظر عن المستوى المختار.';

  @override
  String get currentTierBadge => 'الحالي';

  @override
  String get paranoidAlternativeHeader => 'بديل';

  @override
  String get modifierPasswordLabel => 'كلمة المرور';

  @override
  String get modifierPasswordSubtitle => 'حاجز سري يُكتب قبل فتح القبو.';

  @override
  String get modifierPasswordRequired =>
      'مطلوبة — مستوى Hardware محمي دائماً بكلمة مرور.';

  @override
  String get modifierBiometricLabel => 'اختصار بصمة';

  @override
  String get modifierBiometricSubtitle =>
      'إخراج كلمة المرور من فتحة نظام محمية ببصمة بدلاً من كتابتها يدويًا.';

  @override
  String get biometricRequiresPassword =>
      'فعّل كلمة مرور أولاً — البصمة مجرد اختصار لإدخالها.';

  @override
  String get biometricRequiresActiveTier =>
      'اختر هذا المستوى أولاً لتمكين فتح القفل البيومتري';

  @override
  String get autoLockRequiresActiveTier =>
      'اختر هذا المستوى أولاً لتكوين القفل التلقائي';

  @override
  String get biometricForbiddenParanoid =>
      'مستوى Paranoid لا يسمح بالبصمة بحكم التصميم.';

  @override
  String get fprintdNotAvailable =>
      'لم يتم تثبيت fprintd أو لا توجد بصمة مسجلة.';

  @override
  String get t2RequiresPasswordTitle => 'اضبط كلمة مرور رئيسية لمستوى Hardware';

  @override
  String get t2RequiresPasswordBody =>
      'يحتاج مستوى Hardware إلى كلمة مرور كمعدّل. القياس الحيوي هو اختصار اختياري فوقها.';

  @override
  String get t2MigrationPromptTitle => 'مستوى Hardware يحتاج كلمة مرور';

  @override
  String get t2MigrationPromptBody =>
      'تثبيتات Hardware الحالية بدون كلمة مرور يجب تعيين واحدة الآن للمتابعة.';

  @override
  String get t2MigrationContinue => 'متابعة';

  @override
  String get t2MigrationSetPasswordTitle =>
      'عيّن كلمة مرور للحفاظ على مستوى Hardware';

  @override
  String get t2MigrationSetPasswordBody =>
      'أدخل كلمة مرور رئيسية جديدة. يُعاد ختم مفتاح DB المختوم بالفعل داخل وحدة hardware تحت هذه الكلمة — جلساتك ومفاتيحك تبقى سليمة.';

  @override
  String get t2MigrationWipeAndRestart => 'محو والبدء من جديد';

  @override
  String get t2MigrationResealFailed =>
      'فشل إعادة ختم مستوى Hardware — اختر كلمة مرور أخرى أو امحُ للبدء من جديد.';

  @override
  String get biometricOverlayEnable =>
      'تفعيل اختصار القياس الحيوي على مستوى Hardware';

  @override
  String get biometricOverlayEnableSubtitle =>
      'يحرّر كلمة المرور من فتحة نظام محمية بالقياس الحيوي.';

  @override
  String get biometricOverlayUnavailable =>
      'طبقة القياس الحيوي غير متاحة على هذا النظام بعد.';

  @override
  String get biometricOverlayRequiresPassword =>
      'اضبط كلمة مرور مستوى Hardware أولاً.';

  @override
  String get t2UnlockTitle => 'افتح بكلمة المرور الرئيسية';

  @override
  String get t2UnlockSubtitle =>
      'المفتاح المرتبط بالعتاد محمي بكلمة المرور الخاصة بك.';

  @override
  String get t2UnlockUseBiometricButton => 'استخدم القياس الحيوي';

  @override
  String get t2PasswordChanged => 'تم تحديث كلمة مرور مستوى Hardware.';

  @override
  String get paranoidMasterPasswordNote =>
      'يُنصح بشدة بعبارة مرور طويلة — Argon2id يبطئ القوة الغاشمة فقط ولا يمنعها.';

  @override
  String get plaintextWarningTitle => 'نص صريح: بدون تشفير';

  @override
  String get plaintextWarningBody =>
      'ستُخزَّن الجلسات والمفاتيح و known hosts بدون تشفير. أي شخص لديه وصول إلى نظام ملفات هذا الحاسوب يمكنه قراءتها.';

  @override
  String get plaintextAcknowledge => 'أفهم أن بياناتي لن تكون مشفّرة';

  @override
  String get plaintextAcknowledgeRequired => 'أكّد فهمك قبل المتابعة.';

  @override
  String get passwordLabel => 'كلمة المرور';

  @override
  String get masterPasswordLabel => 'كلمة المرور الرئيسية';

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
  String get playbackPause => 'إيقاف مؤقت';

  @override
  String get recordingPlayLocked =>
      'Unlock the app to play this encrypted recording';

  @override
  String get recordToggleStart => 'بدء التسجيل';

  @override
  String get recordToggleStop => 'إيقاف التسجيل';

  @override
  String get foregroundServiceTitle => 'SSH نشط';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count اتصالات نشطة',
      one: 'اتصال نشط واحد',
      zero: 'لا توجد اتصالات نشطة',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => 'نوع الجلسة';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => 'اسم المستخدم';

  @override
  String get webDavAuthMethod => 'طريقة Auth';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer token';

  @override
  String get trustedCert => 'شهادة موثوقة (PEM)';

  @override
  String get trustedCertHint => '-----BEGIN CERTIFICATE-----';

  @override
  String get trustedCertHelp =>
      'ألصق شهادة الخادم (كتلة PEM واحدة أو أكثر). تُضاف كجذر CA إضافي لهذه الجلسة فقط — لا تؤثر على التطبيقات الأخرى. اتركها فارغة لاستخدام مخزن الثقة في النظام.';

  @override
  String get acceptAnyCert => 'قبول أي شهادة';

  @override
  String get acceptAnyCertHelp =>
      'تخطّي كل فحوصات الشهادة واسم المضيف لمصافحات TLS هذه الجلسة. مخرج طوارئ عندما لا يناسب مخزن ثقة النظام أو شهادة مثبتة.';

  @override
  String get acceptAnyCertWarn =>
      'عرضة لهجمات MITM — يمكن لأي شخص على الشبكة انتحال هوية الخادم. استخدمها فقط على شبكات خاصة موثوقة.';

  @override
  String get webDavCopyUrl => 'نسخ WebDAV URL';

  @override
  String get webDavOpenInBrowser => 'فتح في المتصفح';

  @override
  String get errWebDavAuthFailed => 'فشل auth WebDAV';

  @override
  String get errWebDavNotFound => 'Path غير موجود';

  @override
  String get errWebDavConflict => 'العملية تتعارض مع الحالة الحالية';

  @override
  String errWebDavGeneric(String detail) {
    return 'خادم WebDAV رفض الطلب: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'Base URL لـ WebDAV مطلوب';

  @override
  String get errWebDavBaseUrlInvalid =>
      'Base URL يجب أن يبدأ بـ http:// أو https://';

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
      'اتركه فارغًا لـ AWS، أو ضع endpoint لـ MinIO / R2 / Spaces';

  @override
  String get s3PathStyle => 'Path-style addressing';

  @override
  String get s3PathStyleHint => 'مطلوب لـ MinIO؛ اتركه off مع AWS';

  @override
  String get s3DefaultBucket => 'Bucket الافتراضي';

  @override
  String get s3DefaultPrefix => 'Prefix الافتراضي';

  @override
  String get s3GeneratePresignedUrl => 'إنشاء presigned URL';

  @override
  String get s3PresignedUrlExpiry => 'تنتهي خلال';

  @override
  String get s3CopyUri => 'نسخ URI s3://bucket/key';

  @override
  String get s3PresignedUrlExpiry15min => '15 دقيقة';

  @override
  String get s3PresignedUrlExpiry1hour => 'ساعة';

  @override
  String get s3PresignedUrlExpiry4hour => '4 ساعات';

  @override
  String get s3PresignedUrlExpiry24hour => '24 ساعة';

  @override
  String get s3PresignedUrlExpiry7day => '7 أيام';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (تحقق من access key + secret)';

  @override
  String get errS3NoSuchBucket => 'Bucket غير موجود أو غير قابل للوصول';

  @override
  String get errS3RegionMismatch => 'Bucket في region مختلف عن المُعدّ';

  @override
  String errS3Generic(String detail) {
    return 'خادم S3 رفض الطلب: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'تفعيل WebDAV sync';

  @override
  String get syncPassphrase => 'Sync passphrase';

  @override
  String get syncPassphraseHint =>
      'يشفّر أرشيف sync. يجب أن يختلف عن كلمة المرور الرئيسية.';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Sync passphrase لا يمكن أن يطابق كلمة المرور الرئيسية.';

  @override
  String get syncRemotePath => 'المسار البعيد';

  @override
  String get syncRemotePathHint =>
      'المسار تحت WebDAV base URL — الافتراضي letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return 'آخر push: $when';
  }

  @override
  String syncLastPulled(String when) {
    return 'آخر pull: $when';
  }

  @override
  String get syncNeverRun => 'لم يتم';

  @override
  String get syncUpToDate => 'Sync محدّث';

  @override
  String syncPushedBytes(String bytes) {
    return 'Push $bytes';
  }

  @override
  String syncPullApplied(int count) {
    return 'تم تطبيق $count تغييرات من remote';
  }

  @override
  String get errSyncDisabled => 'Sync معطّل';

  @override
  String get errSyncEtagMismatch => 'تغيّر remote — pull أولاً، ثم push';

  @override
  String get errSyncUnauthorized => 'فشل مصادقة WebDAV';

  @override
  String errSyncNetwork(String detail) {
    return 'خطأ شبكة: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion =>
      'أرشيف sync البعيد يحتاج إصدارًا أحدث';

  @override
  String get hardwareKey => 'Hardware key';

  @override
  String get hardwareKeyTapPrompt => 'المس hardware key';

  @override
  String get hardwareKeyPin => 'PIN الـ hardware key';

  @override
  String get hardwareKeyTimeout => 'Hardware key لم يستجب';

  @override
  String get hardwareKeyNotFound => 'لم يتم العثور على hardware key';

  @override
  String get hardwareKeyUnsupported =>
      'الوصول المباشر إلى hardware key غير متاح على هذه المنصة';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'يتطلب Apple Developer Program entitlement؛ استخدم ssh-agent على macOS';

  @override
  String get skKeyRequiresDevice =>
      'هذا المفتاح SSH يحتاج hardware key — المسه للمصادقة';

  @override
  String get errSkWrongPin => 'PIN غير صحيح';

  @override
  String get hardwareKeyImport => 'استيراد hardware key (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => 'تم إلغاء طلب hardware key';

  @override
  String get agentEndpointSectionTitle => 'تكامل مع عملاء SSH الخارجيين';

  @override
  String get agentEndpointToggleTitle =>
      'كشف hardware-bound keys لعملاء SSH على النظام';

  @override
  String get agentEndpointToggleSubtitle =>
      'يسمح لـ git و ssh وإضافات IDE على هذا الجهاز باستخدام مفاتيح FIDO2 / smart-card / TPM.';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'نسخ أمر export';

  @override
  String get agentEndpointCopyPipeName => 'نسخ اسم pipe';

  @override
  String get agentEndpointSignatureRequestTitle => 'طلب توقيع';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester يريد التوقيع باستخدام $keyLabel';
  }

  @override
  String get agentEndpointRequesterUnknown => 'عميل SSH خارجي';

  @override
  String get agentEndpointAuthorizeOnce => 'اسمح مرة واحدة';

  @override
  String get agentEndpointAuthorizeAlways => 'اسمح وتذكّر';

  @override
  String get agentEndpointDeny => 'رفض';

  @override
  String get agentEndpointStatusRunning => 'قيد التشغيل';

  @override
  String get agentEndpointStatusStopped => 'متوقف';

  @override
  String get agentEndpointStatusUnsupported => 'غير مدعوم على هذه المنصة';

  @override
  String get agentEndpointRefusedAddIdentity =>
      'مرفوض: لا يمكن للعملاء الخارجيين إضافة keys.';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'تعذّر تشغيل ssh-agent endpoint: $detail';
  }

  @override
  String get pkcs11AddTitle => 'إضافة مفتاح smart-card / token';

  @override
  String get pkcs11ModuleLabel => 'وحدة PKCS#11';

  @override
  String get pkcs11ModuleAutoDetected => 'تم اكتشافه تلقائيًا';

  @override
  String get pkcs11ModuleCustom => 'وحدة مخصصة...';

  @override
  String get pkcs11ModulePickerTitle => 'اختر مكتبة PKCS#11';

  @override
  String get pkcs11NoModuleFound =>
      'لم يتم العثور على وحدة PKCS#11. ثبّت OpenSC أو اختر مكتبة المُورد.';

  @override
  String get pkcs11InitializeFailed => 'فشل تهيئة وحدة PKCS#11.';

  @override
  String get pkcs11NoTokenPresent => 'لا يوجد token في القارئ.';

  @override
  String pkcs11TokenLabel(String label) {
    return 'Token: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return 'الرقم التسلسلي: $serial';
  }

  @override
  String get pkcs11LoginRequired => 'يتطلب الـ token تسجيل دخول.';

  @override
  String pkcs11PinPrompt(String token) {
    return 'PIN لـ $token';
  }

  @override
  String get pkcs11PinPad => 'أكّد على PIN-pad الـ token.';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'PIN خاطئ. $remaining محاولات متبقية.';
  }

  @override
  String get pkcs11PinLocked => 'PIN الـ token مقفل. افتحه باستخدام PUK.';

  @override
  String get pkcs11NoSignableKeys =>
      'الـ token لا يحتوي على مفاتيح SSH (RSA، ECDSA، Ed25519).';

  @override
  String get pkcs11GostUnsupported => 'مفاتيح GOST لا تعمل مع SSH.';

  @override
  String pkcs11TokenUnplugged(String label) {
    return 'الـ token \"$label\" غير موصول.';
  }

  @override
  String get pkcs11UriRebindFailed =>
      'Token المحفوظ غير موجود. أعد التوصيل وحاول مجددًا.';

  @override
  String pkcs11SignFailed(String reason) {
    return 'فشل التوقيع: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      'Smart-cards / tokens PKCS#11 غير متاحة على هذه المنصة.';

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
  String get pkcs11WizardStepModule => 'اختر module PKCS#11';

  @override
  String get pkcs11WizardStepToken => 'اختر token';

  @override
  String get pkcs11WizardStepKey => 'اختر مفتاحًا';

  @override
  String get pkcs11WizardStepPin => 'أدخل PIN';

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
  String get pkcs11SaveCta => 'Import key';

  @override
  String get pkcs11SaveInProgress => 'قراءة المفتاح العام من token...';

  @override
  String get pkcs11SaveSuccess => 'تم إضافة مفتاح smart card.';

  @override
  String get pkcs11ScanInProgress => 'البحث عن modules PKCS#11...';

  @override
  String get pkcs11LoadingTokens => 'تحميل tokens...';

  @override
  String get pkcs11LoadingKeys => 'تحميل المفاتيح...';

  @override
  String get pkcs11ModuleStatusReady => 'تم تحميل module.';

  @override
  String get pkcs11ModuleStatusNoToken => 'لا يوجد token.';

  @override
  String get pkcs11ModuleStatusFailed => 'فشل تحميل module.';

  @override
  String get pkcs11PinPadHint => '(PIN pad على الجهاز)';

  @override
  String get pkcs11WizardBack => 'رجوع';

  @override
  String get pkcs11WizardNext => 'التالي';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => 'إضافة hardware key';

  @override
  String get sshKeyHardwareBoundExplainer =>
      'الـ private key يعيش في الـ secure hardware للجهاز ولا يمكن تصديره.';

  @override
  String get sshKeyEnclaveDeviceBound =>
      'هذا الـ key يعمل فقط على هذا الـ Mac.';

  @override
  String get sshKeyEnclaveDeviceBoundIos =>
      'هذا الـ key يعمل فقط على هذا الـ iPhone.';

  @override
  String get sshKeyHelloDeviceBound => 'هذا الـ key يعمل فقط على هذا الـ PC.';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'اشترط Touch ID / Face ID';

  @override
  String get sshKeyEnclavePasscodeFallback =>
      'اسمح بـ passcode الجهاز كـ fallback';

  @override
  String get sshKeyHelloPinRequired =>
      'اشترط Windows Hello (PIN، بصمة، أو وجه)';

  @override
  String get sshKeyHardwareUnavailableTitle => 'الـ hardware keys غير متاحة';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'يجب أن يكون التطبيق code-signed لاستخدام Secure Enclave.';

  @override
  String get sshKeyHardwareUnavailableHello =>
      'Windows Hello غير مُعدّ على هذا الـ PC.';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'لم يتم اكتشاف TPM — software-backed فقط.';

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
  String get sshKeyGenerateCta => 'إنشاء';

  @override
  String get sshKeyGenerateInProgress => 'إنشاء key في الـ secure hardware...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Code-signing مطلوب — راجع USER_GUIDE.md → Hardware-bound keys.';

  @override
  String get sshKeySignInProgress => 'توقيع عبر الـ secure hardware...';

  @override
  String get sshKeyPublicCopy => 'نسخ الـ public key';

  @override
  String get sshKeyAuthorizedKeysHint =>
      'أضف هذا السطر إلى ~/.ssh/authorized_keys على الخادم.';

  @override
  String get sshKeyEnclaveWizardTitle => 'Secure Enclave SSH key';

  @override
  String get sshKeyEnclaveWizardLabelHint => 'اسم الـ key';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'مفتاح SSH عبر Windows Hello';

  @override
  String get helloWizardLabelHint => 'تسمية المفتاح';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'المصادقة عبر Windows Hello';

  @override
  String get helloPromptDescription =>
      'PIN أو بصمة أو وجه — يوقّع Windows Hello تحدّي SSH.';

  @override
  String get helloSoftwareGatedWarning =>
      'لا يوجد TPM في هذا الجهاز. يبقى المفتاح في تخزين المستخدم؛ Windows Hello لا يزال يطالب بالتوقيع في كل مرة.';

  @override
  String get helloP384NotSupported =>
      'برنامج TPM الثابت لا يدعم P-384. اختر P-256 أو RSA-2048.';

  @override
  String get helloConfigureFirst =>
      'اضبط Windows Hello أولًا من الإعدادات -> خيارات تسجيل الدخول.';

  @override
  String get tpmSshTitle => 'إنشاء مفتاح SSH عبر TPM';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (موصى به)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported =>
      'خوارزمية غير مدعومة من البرنامج الثابت لـ TPM.';

  @override
  String get tpmSshPinProtect => 'حماية برمز PIN';

  @override
  String get tpmSshPinLockoutWarning =>
      'يقفل TPM المفتاح بعد محاولات PIN خاطئة متكررة.';

  @override
  String get tpmSshPinMismatch => 'رمزا PIN غير متطابقين.';

  @override
  String get tpmSshStorageBlob => 'حفظ المفتاح المغلف في بيانات التطبيق';

  @override
  String get tpmSshStorageHandle => 'حفظ في فتحة ذاكرة TPM';

  @override
  String get tpmSshStorageHandleHelp =>
      'توقيع أسرع. يستهلك إحدى الفتحات الدائمة في TPM.';

  @override
  String get tpmSshLabel => 'اسم المفتاح';

  @override
  String get tpmSshImportTitle => 'استيراد مفتاح SSH محمي بـ TPM';

  @override
  String get tpmSshImportFormat => 'ملف مفتاح TPM 2.0 (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return 'رمز TPM PIN لـ $label';
  }

  @override
  String get tpmSshPinIncorrect => 'رمز PIN غير صحيح.';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM في فترة انتظار القفل. انتظر $duration وأعد المحاولة.';
  }

  @override
  String get tpmSshGenerating => 'جارٍ إنشاء المفتاح في TPM...';

  @override
  String get tpmSshSigning => 'جارٍ التوقيع باستخدام TPM...';

  @override
  String get tpmSshUnavailable => 'لم يتم اكتشاف TPM على هذا الجهاز.';

  @override
  String get tpmSshUnavailableFwDisabled => 'TPM معطل في البرنامج الثابت.';

  @override
  String get tpmSshUnavailableNoPermission =>
      'لا يمكن للتطبيق الوصول إلى TPM. أضف المستخدم إلى مجموعة `tss`.';

  @override
  String tpmSshHandleInUse(String handle) {
    return 'الفتحة الدائمة $handle مستخدمة بالفعل.';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      'يوقع هذا المفتاح دون مطالبة Hello / PIN — أي شخص لديه وصول إلى سطح المكتب أثناء تسجيل دخولك يمكنه استخدامه.';

  @override
  String get keystoreWizardTitle => 'Android Hardware Key';

  @override
  String get keystoreBadge => 'Android Keystore';

  @override
  String get keystoreKeyAndroidLabel => 'Android Keystore (مرتبط بالعتاد)';

  @override
  String get keystoreKeyStrongBoxLabel => 'StrongBox HSM';

  @override
  String get keystoreKeyTeeLabel => 'TEE (مدعوم بالعتاد)';

  @override
  String get keystoreKeyGenerating => 'جاري إنشاء مفتاح مرتبط بالعتاد...';

  @override
  String get keystoreKeyAuthPrompt => 'أكد هويتك لاستخدام مفتاح SSH';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      'تم إتلاف المفتاح: تم تسجيل قياس حيوي جديد. أعد تسجيل المفتاح العام على خوادمك.';

  @override
  String get keystoreKeyStrongBoxUnavailable =>
      'StrongBox HSM غير متاح على هذا الجهاز';

  @override
  String get keystoreKeyUserAuthRequired =>
      'اطلب القياس الحيوي / فتح الجهاز لكل توقيع';

  @override
  String get keystoreKeyExportDisabled =>
      'لا يمكن تصدير المفاتيح المرتبطة بالعتاد';

  @override
  String get keystoreKeyDeleteWarning =>
      'حذف هذا المفتاح يزيله من مخزن العتاد. سترفض الخوادم هذا المفتاح حتى تسجل واحدا جديدا.';

  @override
  String get keystoreKeyBiometricNotEnrolled =>
      'سجل القياس الحيوي أو PIN الجهاز أولا';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (مؤهل لـ StrongBox)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+، TEE فقط)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (أوسع توافق)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM غير متاح';

  @override
  String get keystoreStrongBoxFallbackBody =>
      'جهازك لا يعرض StrongBox HSM. هل تريد إنشاء مفتاح مدعوم بـ TEE بدلاً منه؟ سيظل مرتبطًا بالعتاد، فقط بدون عزل StrongBox.';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'استخدم TEE';

  @override
  String get keystoreStrongBoxFallbackCancel => 'إلغاء';

  @override
  String get fido2BrokerSectionTitle => 'مفاتيح الأمان العتادية';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / security key';

  @override
  String get fido2BrokerMacosLabel => 'حوار النظام لـ security key';

  @override
  String get fido2BrokerIosLabel => 'security key النظام (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel => 'security key النظام (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => 'USB HID مباشر (CTAP2)';

  @override
  String get fido2BrokerTransportNone => 'غير متاح على هذه المنصة';

  @override
  String get fido2BrokerPreferDirectHidTitle =>
      'تفضيل USB HID المباشر على حوار النظام';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return 'متقدم: تجاوز $brokerLabel على المنصات التي يعمل فيها المساران. الـ HID المباشر يدعم ميزات authenticator أكثر لكن يحتاج صلاحيات لكل تطبيق.';
  }

  @override
  String get sshIntegrationSection => 'تكامل SSH';

  @override
  String get fido2BrokerNoTransportSubtitle =>
      'دعم مفاتيح الأجهزة غير متاح على هذا الجهاز.';

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return 'فقط $transport متاح على هذا الجهاز؛ التبديل معطّل.';
  }

  @override
  String get hardwareKeyStubBadge => 'بدل مستورد';

  @override
  String get hardwareKeyStubSubtitle =>
      'كان على جهاز آخر — أعد التوليد هنا لاستخدامه';

  @override
  String get hardwareKeyStubRegenerateAction => 'أعد التوليد هنا';

  @override
  String get hardwareKeyStubRemoveAction => 'إزالة البدل';

  @override
  String get hardwareKeyStubPickerTooltip =>
      'أعد توليد هذا المفتاح على هذا الجهاز قبل الاستخدام';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return 'حدد مسار وحدة PKCS#11 للرمز \"$token\"';
  }
}
