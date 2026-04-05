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
  String get couldNotOpenInstaller => 'تعذر فتح المثبّت';

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
  String get sessions => 'الجلسات';

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
  String get quickConnect => 'اتصال سريع';

  @override
  String get scanQrCode => 'مسح رمز QR';

  @override
  String get qrGenerationFailed => 'فشل إنشاء رمز QR';

  @override
  String get scanWithCameraApp =>
      'امسح باستخدام أي تطبيق كاميرا على جهاز\nمثبّت عليه LetsFLUTssh.';

  @override
  String get noPasswordsInQr => 'لا توجد كلمات مرور أو مفاتيح في رمز QR هذا';

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
  String get copyRight => 'نسخ لليمين';

  @override
  String get copyDown => 'نسخ للأسفل';

  @override
  String get closePane => 'إغلاق اللوحة';

  @override
  String get previous => 'السابق';

  @override
  String get next => 'التالي';

  @override
  String get closeEsc => 'إغلاق (Esc)';

  @override
  String get copyRightShortcut => 'نسخ لليمين (Ctrl+\\)';

  @override
  String get copyDownShortcut => 'نسخ للأسفل (Ctrl+Shift+\\)';

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
  String get setMasterPasswordHint => 'عيّن كلمة مرور رئيسية لتشفير الأرشيف.';

  @override
  String get passwordsDoNotMatch => 'كلمات المرور غير متطابقة';

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
      'كبير جداً — ألغِ تحديد بعض الجلسات أو استخدم تصدير ملف .lfs.';

  @override
  String get exportAll => 'تصدير الكل';

  @override
  String get showQr => 'عرض QR';

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
}
