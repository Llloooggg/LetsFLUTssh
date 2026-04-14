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
  String get appSettings => 'إعدادات التطبيق';

  @override
  String get yes => 'نعم';

  @override
  String get no => 'لا';

  @override
  String get importWhatToImport => 'ماذا تريد أن تستورد:';

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
  String get qrPasswordWarning =>
      'ستكون كلمات المرور غير مشفرة في رمز QR. يمكن لأي شخص مسحه رؤيتها.';

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
  String get sortByName => 'ترتيب حسب الاسم';

  @override
  String get sortByStatus => 'ترتيب حسب الحالة';

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
      'كبير جداً — ألغِ تحديد بعض الجلسات أو استخدم تصدير ملف .lfs.';

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
  String get importKnownHosts => 'استيراد المضيفين المعروفين';

  @override
  String get importKnownHostsSubtitle => 'استيراد من ملف OpenSSH known_hosts';

  @override
  String get exportKnownHosts => 'تصدير المضيفين المعروفين';

  @override
  String importedHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم استيراد $count مضيف جديد',
      one: 'تم استيراد مضيف جديد واحد',
      zero: 'لم يتم استيراد مضيفين جدد',
    );
    return '$_temp0';
  }

  @override
  String get clearedAllHosts => 'تم مسح جميع المضيفين المعروفين';

  @override
  String removedHost(String host) {
    return 'تمت إزالة $host';
  }

  @override
  String get noHostsToExport => 'لا يوجد مضيفون للتصدير';

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
  String get unlock => 'فتح القفل';

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
  String get passwordTooShort => 'يجب أن تكون كلمة المرور 8 أحرف على الأقل';

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
  String get securityLevelPlaintext => 'بدون (نص عادي)';

  @override
  String get securityLevelKeychain => 'سلسلة مفاتيح النظام';

  @override
  String get securityLevelMasterPassword => 'كلمة المرور الرئيسية';

  @override
  String get keychainStatus => 'سلسلة المفاتيح';

  @override
  String keychainAvailable(String name) {
    return 'متاحة ($name)';
  }

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
  String get snippets => 'Snippets';

  @override
  String get snippetsSubtitle => 'Manage reusable command snippets';

  @override
  String get noSnippets => 'No snippets yet';

  @override
  String get addSnippet => 'Add Snippet';

  @override
  String get editSnippet => 'Edit Snippet';

  @override
  String get deleteSnippet => 'Delete Snippet';

  @override
  String deleteSnippetConfirm(String title) {
    return 'Delete snippet \"$title\"?';
  }

  @override
  String get snippetTitle => 'Title';

  @override
  String get snippetTitleHint => 'e.g. Deploy, Restart Service';

  @override
  String get snippetCommand => 'Command';

  @override
  String get snippetCommandHint => 'e.g. sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'Description (optional)';

  @override
  String get snippetDescriptionHint => 'What does this command do?';

  @override
  String get snippetSaved => 'Snippet saved';

  @override
  String snippetDeleted(String title) {
    return 'Snippet \"$title\" deleted';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets',
      one: '1 snippet',
      zero: 'No snippets',
    );
    return '$_temp0';
  }

  @override
  String get runSnippet => 'Run';

  @override
  String get pinToSession => 'Pin to this session';

  @override
  String get unpinFromSession => 'Unpin from this session';

  @override
  String get pinnedSnippets => 'Pinned';

  @override
  String get allSnippets => 'All';

  @override
  String get sendToTerminal => 'Send to terminal';

  @override
  String get commandCopied => 'Command copied to clipboard';
}
