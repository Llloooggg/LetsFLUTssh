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
  String get paste => 'لصق';

  @override
  String get select => 'تحديد';

  @override
  String get required => 'مطلوب';

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
  String get includeCredentials => 'تضمين كلمات المرور ومفاتيح SSH';

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
  String get qrCredentialsWarning =>
      'ستكون كلمات المرور ومفاتيح SSH مرئية في رمز QR';

  @override
  String get qrCredentialsTooLarge => 'بيانات الاعتماد تجعل رمز QR كبيرًا جدًا';

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
  String importedSessionsViaQr(int count) {
    return 'تم استيراد $count جلسة عبر QR';
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
  String get noSessionsToExport => 'لا توجد جلسات للتصدير';

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
  String get options => 'الخيارات';

  @override
  String get sessionName => 'اسم الجلسة';

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
  String get hidePemText => 'إخفاء نص PEM';

  @override
  String get pastePemKeyText => 'لصق نص مفتاح PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'لا توجد خيارات إضافية بعد';

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
  String errorPrefix(String error) {
    return 'خطأ: $error';
  }

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
  String get initializingSftp => 'جارٍ تهيئة SFTP...';

  @override
  String get clearHistory => 'مسح السجل';

  @override
  String get noTransfersYet => 'لا توجد عمليات نقل بعد';

  @override
  String get duplicateTab => 'تكرار التبويب';

  @override
  String get duplicateTabShortcut => 'تكرار التبويب (Ctrl+\\)';

  @override
  String get copyDown => 'نسخ للأسفل';

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
  String get scrollbackLines => 'عدد أسطر التمرير';

  @override
  String get keepAliveInterval => 'فترة الإبقاء على الاتصال (ثانية)';

  @override
  String get sshTimeout => 'مهلة SSH (ثانية)';

  @override
  String get defaultPort => 'المنفذ الافتراضي';

  @override
  String get parallelWorkers => 'العمال المتوازيون';

  @override
  String get maxHistory => 'الحد الأقصى للسجل';

  @override
  String get calculateFolderSizes => 'حساب أحجام المجلدات';

  @override
  String get exportData => 'تصدير البيانات';

  @override
  String get exportDataSubtitle =>
      'حفظ الجلسات والإعدادات والمفاتيح في ملف .lfs مشفّر';

  @override
  String get importDataSubtitle => 'تحميل البيانات من ملف .lfs';

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
  String sshConfigPreviewFolderLabel(String folder) {
    return 'تم الاستيراد إلى المجلد: $folder';
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
  String get hintLfsPath => '/path/to/export.lfs';

  @override
  String get browse => 'تصفح';

  @override
  String get shareViaQrCode => 'مشاركة عبر رمز QR';

  @override
  String get shareViaQrSubtitle => 'تصدير الجلسات إلى رمز QR لمسحه من جهاز آخر';

  @override
  String get dataLocation => 'موقع البيانات';

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
  String get enableLogging => 'تفعيل السجلات';

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
  String get anotherInstanceRunning =>
      'نسخة أخرى من LetsFLUTssh قيد التشغيل بالفعل.';

  @override
  String importFailedShort(String error) {
    return 'فشل الاستيراد: $error';
  }

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
  String get qrNoCredentialsWarning =>
      'كلمات المرور ومفاتيح SSH غير مضمّنة.\nالجلسات المستوردة ستحتاج إلى إدخال بيانات الاعتماد.';

  @override
  String get qrTooManyForSingleCode =>
      'جلسات كثيرة جداً لرمز QR واحد. ألغِ تحديد بعضها أو استخدم تصدير .lfs.';

  @override
  String get qrTooLarge =>
      'كبير جداً — ألغِ تحديد بعض العناصر أو استخدم تصدير ملف .lfs.';

  @override
  String get exportAll => 'تصدير الكل';

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
  String get errBrokenPipe => 'أنبوب مكسور';

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
  String get errSshOpenShellFailed => 'فشل فتح الصدفة';

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
  String errShellError(String error) {
    return 'خطأ في الصدفة: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'فشلت إعادة الاتصال: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'فشلت تهيئة SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'فشل التنزيل: $error';
  }

  @override
  String get errDecryptionFailed =>
      'فشل فك تشفير بيانات الاعتماد. قد يكون ملف المفتاح تالفاً.';

  @override
  String get errExportPickerUnavailable =>
      'منتقي المجلدات في النظام غير متاح. جرّب موقعاً آخر أو تحقق من أذونات تخزين التطبيق.';

  @override
  String get biometricUnlockPrompt => 'فتح قفل LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'الفتح بالمقاييس الحيوية';

  @override
  String get biometricUnlockSubtitle =>
      'تجنّب كتابة كلمة المرور الرئيسية عند تشغيل التطبيق.';

  @override
  String get biometricNotAvailable =>
      'الفتح بالمقاييس الحيوية غير متاح على هذا الجهاز.';

  @override
  String get biometricEnableFailed => 'تعذّر تفعيل الفتح بالمقاييس الحيوية.';

  @override
  String get biometricEnabled => 'تم تفعيل الفتح بالمقاييس الحيوية';

  @override
  String get biometricDisabled => 'تم تعطيل الفتح بالمقاييس الحيوية';

  @override
  String get biometricUnlockFailed =>
      'فشل فتح القفل بالبيانات الحيوية. أدخل كلمة المرور الرئيسية.';

  @override
  String get biometricUnlockCancelled =>
      'تم إلغاء فتح القفل بالبيانات الحيوية.';

  @override
  String get biometricNotEnrolled =>
      'لا توجد بيانات حيوية مسجلة على هذا الجهاز.';

  @override
  String get biometricRequiresMasterPassword =>
      'يرجى تعيين كلمة مرور رئيسية أولاً لتمكين فتح القفل بالبيانات الحيوية.';

  @override
  String get biometricSensorNotAvailable =>
      'لا يحتوي هذا الجهاز على مستشعر بيومتري.';

  @override
  String get biometricSystemServiceMissing =>
      'خدمة بصمة الإصبع (fprintd) غير مثبتة. راجع README ← التثبيت.';

  @override
  String get biometricBackingHardware => 'مدعوم بالعتاد (Secure Enclave / TPM)';

  @override
  String get biometricBackingSoftware => 'مدعوم بالبرنامج';

  @override
  String get autoLockRequiresMasterPassword =>
      'يرجى تعيين كلمة مرور رئيسية أولاً لتمكين القفل التلقائي.';

  @override
  String get currentPasswordIncorrect => 'كلمة المرور الحالية غير صحيحة';

  @override
  String get wrongPassword => 'كلمة مرور خاطئة';

  @override
  String get useKeychain => 'التشفير باستخدام سلسلة مفاتيح النظام';

  @override
  String get useKeychainSubtitle =>
      'تخزين مفتاح قاعدة البيانات في مخزن بيانات الاعتماد بالنظام. إيقاف = قاعدة بيانات بنص صريح.';

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
      'قفل الواجهة بعد هذه المدة من الخمول. لا يُعاد قفل قاعدة البيانات المشفّرة إلا عند عدم وجود جلسات SSH نشطة، حتى تستمر العمليات الطويلة دون انقطاع.';

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
  String get updateSecurityWarningTitle => 'فشل التحقق من التحديث';

  @override
  String get updateReinstallAction => 'فتح صفحة الإصدارات';

  @override
  String get errLfsNotArchive => 'الملف المحدد ليس أرشيف LetsFLUTssh.';

  @override
  String get errLfsDecryptFailed =>
      'كلمة المرور الرئيسية خاطئة أو أرشيف .lfs تالف';

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
  String get progressParsingArchive => 'تحليل الأرشيف…';

  @override
  String get progressImportingSessions => 'استيراد الجلسات';

  @override
  String get progressImportingFolders => 'استيراد المجلدات';

  @override
  String get progressImportingManagerKeys => 'استيراد مفاتيح SSH';

  @override
  String get progressImportingTags => 'استيراد العلامات';

  @override
  String get progressImportingSnippets => 'استيراد المقتطفات';

  @override
  String get progressApplyingConfig => 'تطبيق الإعدادات…';

  @override
  String get progressImportingKnownHosts => 'استيراد known_hosts…';

  @override
  String get progressCollectingData => 'جمع البيانات…';

  @override
  String get progressEncrypting => 'تشفير…';

  @override
  String get progressWritingArchive => 'كتابة الأرشيف…';

  @override
  String get progressReencrypting => 'إعادة تشفير المخازن…';

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
  String get saveSessionToAssignTags => 'احفظ الجلسة أولاً لتعيين العلامات';

  @override
  String get noTagsAssigned => 'لم يتم تعيين علامات';

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
  String get storagePermissionRequired =>
      'يلزم إذن التخزين لتصفح الملفات المحلية';

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
  String get transferStartingUpload => 'بدء الرفع...';

  @override
  String get transferStartingDownload => 'بدء التنزيل...';

  @override
  String get transferCopying => 'جارٍ النسخ...';

  @override
  String get transferDone => 'تم';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total ملفات';
  }

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
  String get sshConnectionChannel => 'اتصال SSH';

  @override
  String get sshConnectionChannelDesc =>
      'يحافظ على اتصالات SSH نشطة في الخلفية.';

  @override
  String get sshActive => 'SSH نشط';

  @override
  String activeConnectionCount(int count) {
    return '$count اتصال(ات) نشطة';
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
  String get importKnownHostsSubtitle => 'استيراد من ملف OpenSSH known_hosts';

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
  String get pastePrivateKey => 'لصق المفتاح الخاص (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'بيانات مفتاح PEM غير صالحة';

  @override
  String get selectFromKeyStore => 'اختر من مخزن المفاتيح';

  @override
  String get noKeySelected => 'لم يتم اختيار مفتاح';

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
  String get passphraseRequired => 'عبارة المرور مطلوبة';

  @override
  String passphrasePrompt(String host) {
    return 'مفتاح SSH لـ $host مشفر. أدخل عبارة المرور لفتحه.';
  }

  @override
  String get passphraseWrong => 'عبارة المرور غير صحيحة. حاول مرة أخرى.';

  @override
  String get passphrase => 'عبارة المرور';

  @override
  String get rememberPassphrase => 'تذكر لهذه الجلسة';

  @override
  String get masterPasswordSubtitle =>
      'حماية بيانات الاعتماد المحفوظة بكلمة مرور';

  @override
  String get setMasterPassword => 'تعيين كلمة المرور الرئيسية';

  @override
  String get changeMasterPassword => 'تغيير كلمة المرور الرئيسية';

  @override
  String get removeMasterPassword => 'إزالة كلمة المرور الرئيسية';

  @override
  String get masterPasswordEnabled =>
      'بيانات الاعتماد محمية بكلمة المرور الرئيسية';

  @override
  String get masterPasswordDisabled =>
      'بيانات الاعتماد تستخدم مفتاحاً مولداً تلقائياً (بدون كلمة مرور)';

  @override
  String get enterMasterPassword =>
      'أدخل كلمة المرور الرئيسية للوصول إلى بيانات الاعتماد المحفوظة.';

  @override
  String get wrongMasterPassword => 'كلمة مرور خاطئة. حاول مرة أخرى.';

  @override
  String get newPassword => 'كلمة مرور جديدة';

  @override
  String get currentPassword => 'كلمة المرور الحالية';

  @override
  String get masterPasswordSet => 'تم تفعيل كلمة المرور الرئيسية';

  @override
  String get masterPasswordChanged => 'تم تغيير كلمة المرور الرئيسية';

  @override
  String get masterPasswordRemoved => 'تمت إزالة كلمة المرور الرئيسية';

  @override
  String get masterPasswordWarning =>
      'إذا نسيت هذه الكلمة، ستفقد جميع كلمات المرور ومفاتيح SSH المحفوظة. لا يمكن الاسترداد.';

  @override
  String get forgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get forgotPasswordWarning =>
      'سيؤدي هذا إلى حذف جميع كلمات المرور ومفاتيح SSH وعبارات المرور المحفوظة. سيتم الاحتفاظ بالجلسات والإعدادات. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get resetAndDeleteCredentials => 'إعادة تعيين وحذف البيانات';

  @override
  String get credentialsReset => 'تم حذف جميع بيانات الاعتماد المحفوظة';

  @override
  String get legacyKdfTitle => 'يلزم تحديث أمني';

  @override
  String get legacyKdfBody =>
      'يحمي هذا التثبيت كلمة المرور الرئيسية بخوارزمية قديمة لاشتقاق المفاتيح (PBKDF2). وقد تم استبدالها بـ Argon2id لتوفير مقاومة أقوى بكثير ضد الكسر عبر GPU/ASIC. التنسيق الجديد غير متوافق مع التنسيق السابق، لذا لا يمكن ترحيل ملف الملح القديم تلقائيًا.';

  @override
  String get legacyKdfWarning =>
      'سيؤدي اختيار «إعادة التعيين والمتابعة» إلى حذف جميع بيانات الاعتماد المحفوظة بشكل دائم (كلمات المرور، مفاتيح SSH، المضيفون المعروفون). سيتم الاحتفاظ بجلساتك وإعداداتك. إذا كنت بحاجة إلى استرداد بيانات الاعتماد، فأغلق التطبيق وأعد تثبيت الإصدار السابق من LetsFLUTssh لتصدير بياناتك أولًا.';

  @override
  String get legacyKdfResetContinue => 'إعادة التعيين والمتابعة';

  @override
  String get legacyKdfExit => 'إنهاء LetsFLUTssh';

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
  String get reEncrypting => 'جارٍ إعادة التشفير...';

  @override
  String get confirmRemoveMasterPassword =>
      'أدخل كلمة المرور الحالية لإزالة حماية كلمة المرور الرئيسية. سيتم إعادة تشفير البيانات بمفتاح مولد تلقائياً.';

  @override
  String get securitySetupTitle => 'إعداد الأمان';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'تم اكتشاف سلسلة مفاتيح النظام ($keychainName). سيتم تشفير بياناتك تلقائياً باستخدام سلسلة مفاتيح النظام.';
  }

  @override
  String get securitySetupKeychainOptional =>
      'يمكنك أيضاً تعيين كلمة مرور رئيسية لحماية إضافية.';

  @override
  String get securitySetupNoKeychain =>
      'لم يتم اكتشاف سلسلة مفاتيح النظام. بدونها، سيتم تخزين بيانات الجلسة (المضيفون، كلمات المرور، المفاتيح) كنص عادي.';

  @override
  String get securitySetupNoKeychainHint =>
      'هذا طبيعي في WSL أو Linux بدون واجهة رسومية أو التثبيتات المحدودة. لتفعيل سلسلة المفاتيح في Linux: ثبّت libsecret وخفي سلسلة المفاتيح (مثل gnome-keyring).';

  @override
  String get securitySetupRecommendMasterPassword =>
      'نوصي بتعيين كلمة مرور رئيسية لحماية بياناتك.';

  @override
  String get continueWithKeychain => 'المتابعة مع سلسلة المفاتيح';

  @override
  String get continueWithoutEncryption => 'المتابعة بدون تشفير';

  @override
  String get securityLevel => 'مستوى الأمان';

  @override
  String get securityLevelPlaintext => 'بدون';

  @override
  String get securityLevelKeychain => 'سلسلة مفاتيح النظام';

  @override
  String get securityLevelMasterPassword => 'كلمة المرور الرئيسية';

  @override
  String get keychainStatus => 'سلسلة المفاتيح';

  @override
  String get keychainAvailable => 'متاحة';

  @override
  String get keychainNotAvailable => 'غير متاحة';

  @override
  String get enableKeychain => 'تفعيل تشفير سلسلة المفاتيح';

  @override
  String get enableKeychainSubtitle =>
      'إعادة تشفير البيانات المخزنة باستخدام سلسلة مفاتيح النظام';

  @override
  String get keychainEnabled => 'تم تفعيل تشفير سلسلة المفاتيح';

  @override
  String get manageMasterPassword => 'إدارة كلمة المرور الرئيسية';

  @override
  String get manageMasterPasswordSubtitle =>
      'تعيين أو تغيير أو إزالة كلمة المرور الرئيسية';

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
  String get runSnippet => 'تشغيل';

  @override
  String get pinToSession => 'تثبيت في هذه الجلسة';

  @override
  String get unpinFromSession => 'إلغاء التثبيت من هذه الجلسة';

  @override
  String get pinnedSnippets => 'المثبتة';

  @override
  String get allSnippets => 'الكل';

  @override
  String get sendToTerminal => 'إرسال إلى الطرفية';

  @override
  String get commandCopied => 'تم نسخ الأمر';

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
  String get sessionKeysFromManager => 'مفاتيح الجلسات من المدير';

  @override
  String get allKeysFromManager => 'جميع المفاتيح من المدير';

  @override
  String exportTags(int count) {
    return 'الوسوم ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'القصاصات ($count)';
  }

  @override
  String get disableKeychain => 'تعطيل تشفير سلسلة المفاتيح';

  @override
  String get disableKeychainSubtitle =>
      'التبديل إلى التخزين بنص عادي (غير موصى به)';

  @override
  String get disableKeychainConfirm =>
      'ستتم إعادة تشفير قاعدة البيانات بدون مفتاح. سيتم تخزين الجلسات والمفاتيح بنص عادي على القرص. هل تريد المتابعة؟';

  @override
  String get keychainDisabled => 'تم تعطيل تشفير سلسلة المفاتيح';

  @override
  String get presetFullImport => 'استيراد كامل';

  @override
  String get presetSelective => 'انتقائي';

  @override
  String get presetCustom => 'مخصص';

  @override
  String get sessionSshKeys => 'مفاتيح SSH للجلسة';

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
  String get parallelWorkersSubtitle => 'عدد عمال نقل SFTP المتزامنين';

  @override
  String get maxHistorySubtitle => 'الحد الأقصى للأوامر المحفوظة في السجل';

  @override
  String get calculateFolderSizesSubtitle =>
      'إظهار الحجم الإجمالي بجانب المجلدات في الشريط الجانبي';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'الاستعلام عن إصدار جديد على GitHub عند تشغيل التطبيق';

  @override
  String get enableLoggingSubtitle => 'كتابة أحداث التطبيق في ملف سجل دوّار';

  @override
  String get exportWithoutPassword => 'تصدير بدون كلمة مرور؟';

  @override
  String get exportWithoutPasswordWarning =>
      'لن يتم تشفير الأرشيف. يمكن لأي شخص لديه حق الوصول إلى الملف قراءة بياناتك، بما في ذلك كلمات المرور والمفاتيح الخاصة.';

  @override
  String get continueWithoutPassword => 'المتابعة بدون كلمة مرور';
}
