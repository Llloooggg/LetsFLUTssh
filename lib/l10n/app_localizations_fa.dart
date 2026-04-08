// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class SFa extends S {
  SFa([String locale = 'fa']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'تأیید';

  @override
  String get cancel => 'لغو';

  @override
  String get close => 'بستن';

  @override
  String get delete => 'حذف';

  @override
  String get save => 'ذخیره';

  @override
  String get connect => 'اتصال';

  @override
  String get retry => 'تلاش مجدد';

  @override
  String get import_ => 'وارد کردن';

  @override
  String get export_ => 'خروجی گرفتن';

  @override
  String get rename => 'تغییر نام';

  @override
  String get create => 'ایجاد';

  @override
  String get back => 'بازگشت';

  @override
  String get copy => 'کپی';

  @override
  String get paste => 'جای‌گذاری';

  @override
  String get select => 'انتخاب';

  @override
  String get required => 'الزامی';

  @override
  String get settings => 'تنظیمات';

  @override
  String get terminal => 'ترمینال';

  @override
  String get files => 'فایل‌ها';

  @override
  String get transfer => 'انتقال';

  @override
  String get open => 'باز کردن';

  @override
  String get search => 'جستجو...';

  @override
  String get filter => 'فیلتر...';

  @override
  String get merge => 'ادغام';

  @override
  String get replace => 'جایگزینی';

  @override
  String get reconnect => 'اتصال مجدد';

  @override
  String get updateAvailable => 'به‌روزرسانی موجود است';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'نسخه $version موجود است (فعلی: v$current).';
  }

  @override
  String get releaseNotes => 'یادداشت‌های انتشار:';

  @override
  String get skipThisVersion => 'رد کردن این نسخه';

  @override
  String get unskip => 'لغو رد کردن';

  @override
  String get downloadAndInstall => 'دانلود و نصب';

  @override
  String get openInBrowser => 'باز کردن در مرورگر';

  @override
  String get couldNotOpenBrowser => 'مرورگر باز نشد — آدرس در کلیپ‌بورد کپی شد';

  @override
  String get checkForUpdates => 'بررسی به‌روزرسانی';

  @override
  String get checkForUpdatesOnStartup => 'بررسی به‌روزرسانی هنگام راه‌اندازی';

  @override
  String get checking => 'در حال بررسی...';

  @override
  String get youreUpToDate => 'نسخه شما به‌روز است';

  @override
  String get updateCheckFailed => 'بررسی به‌روزرسانی ناموفق بود';

  @override
  String get unknownError => 'خطای ناشناخته';

  @override
  String downloadingPercent(int percent) {
    return 'در حال دانلود... $percent%';
  }

  @override
  String get downloadComplete => 'دانلود کامل شد';

  @override
  String get installNow => 'نصب اکنون';

  @override
  String get couldNotOpenInstaller => 'نصب‌کننده باز نشد';

  @override
  String versionAvailable(String version) {
    return 'نسخه $version موجود است';
  }

  @override
  String currentVersion(String version) {
    return 'فعلی: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'کلید SSH دریافت شد: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return '$count جلسه از طریق QR وارد شد';
  }

  @override
  String importedSessions(int count) {
    return '$count جلسه وارد شد';
  }

  @override
  String importFailed(String error) {
    return 'وارد کردن ناموفق بود: $error';
  }

  @override
  String get sessions => 'جلسات';

  @override
  String get sessionsHeader => 'جلسات';

  @override
  String get savedSessions => 'جلسات ذخیره‌شده';

  @override
  String get activeConnections => 'اتصالات فعال';

  @override
  String get openTabs => 'تب‌های باز';

  @override
  String get noSavedSessions => 'هیچ جلسه‌ای ذخیره نشده';

  @override
  String get addSession => 'افزودن جلسه';

  @override
  String get noSessions => 'هیچ جلسه‌ای وجود ندارد';

  @override
  String get noSessionsToExport => 'هیچ جلسه‌ای برای خروجی وجود ندارد';

  @override
  String nSelectedCount(int count) {
    return '$count انتخاب شده';
  }

  @override
  String get selectAll => 'انتخاب همه';

  @override
  String get deselectAll => 'لغو انتخاب همه';

  @override
  String get moveTo => 'انتقال به...';

  @override
  String get moveToFolder => 'انتقال به پوشه';

  @override
  String get rootFolder => '/ (ریشه)';

  @override
  String get newFolder => 'پوشه جدید';

  @override
  String get newConnection => 'اتصال جدید';

  @override
  String get editConnection => 'ویرایش اتصال';

  @override
  String get duplicate => 'کپی';

  @override
  String get deleteSession => 'حذف جلسه';

  @override
  String get renameFolder => 'تغییر نام پوشه';

  @override
  String get deleteFolder => 'حذف پوشه';

  @override
  String get deleteSelected => 'حذف موارد انتخاب‌شده';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return 'حذف $parts؟\n\nاین عملیات قابل بازگشت نیست.';
  }

  @override
  String nSessions(int count) {
    return '$count جلسه';
  }

  @override
  String nFolders(int count) {
    return '$count پوشه';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'پوشه \"$name\" حذف شود؟';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'این عملیات همچنین $count جلسه داخل آن را حذف می‌کند.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return '\"$name\" حذف شود؟';
  }

  @override
  String get connection => 'اتصال';

  @override
  String get auth => 'احراز هویت';

  @override
  String get options => 'گزینه‌ها';

  @override
  String get sessionName => 'نام جلسه';

  @override
  String get hintMyServer => 'سرور من';

  @override
  String get hostRequired => 'میزبان *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'پورت';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'نام کاربری *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'رمز عبور';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'رمز عبور کلید';

  @override
  String get hintOptional => 'اختیاری';

  @override
  String get hidePemText => 'پنهان کردن متن PEM';

  @override
  String get pastePemKeyText => 'جای‌گذاری متن کلید PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'هنوز گزینه اضافی‌ای وجود ندارد';

  @override
  String get saveAndConnect => 'ذخیره و اتصال';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst => 'ابتدا یک فایل کلید یا متن PEM وارد کنید';

  @override
  String get keyTextPem => 'متن کلید (PEM)';

  @override
  String get selectKeyFile => 'انتخاب فایل کلید';

  @override
  String get clearKeyFile => 'پاک کردن فایل کلید';

  @override
  String get authOrDivider => 'یا';

  @override
  String get providePasswordOrKey => 'یک رمز عبور یا کلید SSH وارد کنید';

  @override
  String get quickConnect => 'اتصال سریع';

  @override
  String get scanQrCode => 'اسکن کد QR';

  @override
  String get qrGenerationFailed => 'تولید QR ناموفق بود';

  @override
  String get scanWithCameraApp =>
      'با هر برنامه دوربینی روی دستگاهی که LetsFLUTssh نصب است اسکن کنید.';

  @override
  String get noPasswordsInQr => 'رمز عبور یا کلیدی در این کد QR وجود ندارد';

  @override
  String get copyLink => 'کپی لینک';

  @override
  String get linkCopied => 'لینک در کلیپ‌بورد کپی شد';

  @override
  String get hostKeyChanged => 'کلید میزبان تغییر کرده است!';

  @override
  String get unknownHost => 'میزبان ناشناخته';

  @override
  String get hostKeyChangedWarning =>
      'هشدار: کلید میزبان این سرور تغییر کرده است. این ممکن است نشانه حمله مرد میانی باشد، یا سرور مجدداً نصب شده باشد.';

  @override
  String get unknownHostMessage =>
      'اصالت این میزبان قابل تأیید نیست. آیا مطمئنید که می‌خواهید اتصال را ادامه دهید؟';

  @override
  String get host => 'میزبان';

  @override
  String get keyType => 'نوع کلید';

  @override
  String get fingerprint => 'اثر انگشت';

  @override
  String get fingerprintCopied => 'اثر انگشت کپی شد';

  @override
  String get copyFingerprint => 'کپی اثر انگشت';

  @override
  String get acceptAnyway => 'پذیرفتن در هر صورت';

  @override
  String get accept => 'پذیرفتن';

  @override
  String get importData => 'وارد کردن داده';

  @override
  String get masterPassword => 'رمز عبور اصلی';

  @override
  String get confirmPassword => 'تأیید رمز عبور';

  @override
  String get importModeMergeDescription => 'افزودن جلسات جدید، حفظ موجودها';

  @override
  String get importModeReplaceDescription =>
      'جایگزینی همه جلسات با موارد وارد شده';

  @override
  String errorPrefix(String error) {
    return 'خطا: $error';
  }

  @override
  String get folderName => 'نام پوشه';

  @override
  String get newName => 'نام جدید';

  @override
  String deleteItems(String names) {
    return 'حذف $names؟';
  }

  @override
  String deleteNItems(int count) {
    return 'حذف $count مورد';
  }

  @override
  String deletedItem(String name) {
    return '$name حذف شد';
  }

  @override
  String deletedNItems(int count) {
    return '$count مورد حذف شد';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'ایجاد پوشه ناموفق بود: $error';
  }

  @override
  String failedToRename(String error) {
    return 'تغییر نام ناموفق بود: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return 'حذف $name ناموفق بود: $error';
  }

  @override
  String get editPath => 'ویرایش مسیر';

  @override
  String get root => 'ریشه';

  @override
  String get controllersNotInitialized => 'کنترل‌کننده‌ها مقداردهی نشده‌اند';

  @override
  String get initializingSftp => 'در حال راه‌اندازی SFTP...';

  @override
  String get clearHistory => 'پاک کردن تاریخچه';

  @override
  String get noTransfersYet => 'هنوز انتقالی انجام نشده';

  @override
  String get duplicateTab => 'کپی تب';

  @override
  String get duplicateTabShortcut => 'کپی تب (Ctrl+\\)';

  @override
  String get copyDown => 'کپی به پایین';

  @override
  String get previous => 'قبلی';

  @override
  String get next => 'بعدی';

  @override
  String get closeEsc => 'بستن (Esc)';

  @override
  String get closeAll => 'بستن همه';

  @override
  String get closeOthers => 'بستن بقیه';

  @override
  String get closeTabsToTheLeft => 'بستن تب‌های سمت چپ';

  @override
  String get closeTabsToTheRight => 'بستن تب‌های سمت راست';

  @override
  String get sortByName => 'مرتب‌سازی بر اساس نام';

  @override
  String get sortByStatus => 'مرتب‌سازی بر اساس وضعیت';

  @override
  String get noActiveSession => 'جلسه فعالی وجود ندارد';

  @override
  String get createConnectionHint =>
      'یک اتصال جدید ایجاد کنید یا از نوار کناری انتخاب کنید';

  @override
  String get hideSidebar => 'پنهان کردن نوار کناری (Ctrl+B)';

  @override
  String get showSidebar => 'نمایش نوار کناری (Ctrl+B)';

  @override
  String get language => 'زبان';

  @override
  String get languageSystemDefault => 'خودکار';

  @override
  String get theme => 'پوسته';

  @override
  String get themeDark => 'تیره';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeSystem => 'سیستم';

  @override
  String get appearance => 'ظاهر';

  @override
  String get connectionSection => 'اتصال';

  @override
  String get transfers => 'انتقال‌ها';

  @override
  String get data => 'داده';

  @override
  String get logging => 'ثبت رویداد';

  @override
  String get updates => 'به‌روزرسانی‌ها';

  @override
  String get about => 'درباره';

  @override
  String get resetToDefaults => 'بازگشت به پیش‌فرض';

  @override
  String get uiScale => 'مقیاس رابط کاربری';

  @override
  String get terminalFontSize => 'اندازه فونت ترمینال';

  @override
  String get scrollbackLines => 'خطوط اسکرول بازگشتی';

  @override
  String get keepAliveInterval => 'فاصله ارسال نگه‌داشتن اتصال (ثانیه)';

  @override
  String get sshTimeout => 'وقفه زمانی SSH (ثانیه)';

  @override
  String get defaultPort => 'پورت پیش‌فرض';

  @override
  String get parallelWorkers => 'کارگران موازی';

  @override
  String get maxHistory => 'حداکثر تاریخچه';

  @override
  String get calculateFolderSizes => 'محاسبه اندازه پوشه‌ها';

  @override
  String get exportData => 'خروجی گرفتن از داده';

  @override
  String get exportDataSubtitle =>
      'ذخیره جلسات، تنظیمات و کلیدها در فایل رمزگذاری‌شده .lfs';

  @override
  String get importDataSubtitle => 'بارگذاری داده از فایل .lfs';

  @override
  String get setMasterPasswordHint =>
      'یک رمز عبور اصلی برای رمزگذاری آرشیو تعیین کنید.';

  @override
  String get passwordsDoNotMatch => 'رمزهای عبور مطابقت ندارند';

  @override
  String exportedTo(String path) {
    return 'خروجی گرفته شد به: $path';
  }

  @override
  String exportFailed(String error) {
    return 'خروجی گرفتن ناموفق بود: $error';
  }

  @override
  String get pathToLfsFile => 'مسیر فایل .lfs';

  @override
  String get hintLfsPath => '/path/to/export.lfs';

  @override
  String get browse => 'مرور';

  @override
  String get shareViaQrCode => 'اشتراک‌گذاری از طریق کد QR';

  @override
  String get shareViaQrSubtitle =>
      'خروجی گرفتن از جلسات به QR برای اسکن توسط دستگاه دیگر';

  @override
  String get dataLocation => 'محل داده';

  @override
  String get pathCopied => 'مسیر در کلیپ‌بورد کپی شد';

  @override
  String get urlCopied => 'آدرس در کلیپ‌بورد کپی شد';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — کلاینت SSH/SFTP';
  }

  @override
  String get sourceCode => 'کد منبع';

  @override
  String get enableLogging => 'فعال‌سازی ثبت رویداد';

  @override
  String get logIsEmpty => 'گزارش خالی است';

  @override
  String logExportedTo(String path) {
    return 'گزارش خروجی گرفته شد به: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'خروجی گرفتن از گزارش ناموفق بود: $error';
  }

  @override
  String get logsCleared => 'گزارش‌ها پاک شدند';

  @override
  String get copiedToClipboard => 'در کلیپ‌بورد کپی شد';

  @override
  String get copyLog => 'کپی گزارش';

  @override
  String get exportLog => 'خروجی گزارش';

  @override
  String get clearLogs => 'پاک کردن گزارش‌ها';

  @override
  String get local => 'محلی';

  @override
  String get remote => 'راه دور';

  @override
  String get pickFolder => 'انتخاب پوشه';

  @override
  String get refresh => 'بازخوانی';

  @override
  String get up => 'بالا';

  @override
  String get emptyDirectory => 'پوشه خالی';

  @override
  String get cancelSelection => 'لغو انتخاب';

  @override
  String get openSftpBrowser => 'باز کردن مرورگر SFTP';

  @override
  String get openSshTerminal => 'باز کردن ترمینال SSH';

  @override
  String get noActiveFileBrowsers => 'هیچ مرورگر فایل فعالی وجود ندارد';

  @override
  String get useSftpFromSessions => 'از «SFTP» در جلسات استفاده کنید';

  @override
  String get anotherInstanceRunning =>
      'نسخه دیگری از LetsFLUTssh در حال اجرا است.';

  @override
  String importFailedShort(String error) {
    return 'وارد کردن ناموفق بود: $error';
  }

  @override
  String get saveLogAs => 'ذخیره گزارش به عنوان';

  @override
  String get chooseSaveLocation => 'انتخاب محل ذخیره';

  @override
  String get forward => 'جلو';

  @override
  String get name => 'نام';

  @override
  String get size => 'اندازه';

  @override
  String get modified => 'تغییر یافته';

  @override
  String get mode => 'حالت';

  @override
  String get owner => 'مالک';

  @override
  String get connectionError => 'خطای اتصال';

  @override
  String get resizeWindowToViewFiles =>
      'اندازه پنجره را برای مشاهده فایل‌ها تغییر دهید';

  @override
  String get completed => 'تکمیل شد';

  @override
  String get connected => 'متصل شد';

  @override
  String get disconnected => 'قطع شد';

  @override
  String get exit => 'خروج';

  @override
  String get exitConfirmation => 'جلسات فعال قطع خواهند شد. خروج؟';

  @override
  String get hintFolderExample => 'مثلاً Production';

  @override
  String get credentialsNotSet => 'اعتبارنامه تنظیم نشده';

  @override
  String get exportSessionsViaQr => 'خروجی جلسات از طریق QR';

  @override
  String get qrNoCredentialsWarning =>
      'رمزهای عبور و کلیدهای SSH شامل نمی‌شوند.\nجلسات وارد شده نیاز به تکمیل اعتبارنامه دارند.';

  @override
  String get qrTooManyForSingleCode =>
      'تعداد جلسات برای یک کد QR بیش از حد است. برخی را حذف انتخاب کنید یا از خروجی .lfs استفاده کنید.';

  @override
  String get qrTooLarge =>
      'حجم بیش از حد است — برخی جلسات را حذف انتخاب کنید یا از خروجی فایل .lfs استفاده کنید.';

  @override
  String get exportAll => 'خروجی همه';

  @override
  String get showQr => 'نمایش QR';

  @override
  String get sort => 'مرتب‌سازی';

  @override
  String get resizePanelDivider => 'تغییر اندازه جداکننده پنل';

  @override
  String get youreRunningLatest => 'شما آخرین نسخه را اجرا می‌کنید';

  @override
  String get liveLog => 'گزارش زنده';

  @override
  String transferNItems(int count) {
    return 'انتقال $count مورد';
  }

  @override
  String get time => 'زمان';

  @override
  String get failed => 'ناموفق';

  @override
  String get errOperationNotPermitted => 'عملیات مجاز نیست';

  @override
  String get errNoSuchFileOrDirectory => 'فایل یا پوشه‌ای وجود ندارد';

  @override
  String get errNoSuchProcess => 'فرآیندی وجود ندارد';

  @override
  String get errIoError => 'خطای ورودی/خروجی';

  @override
  String get errBadFileDescriptor => 'توصیف‌گر فایل نامعتبر';

  @override
  String get errResourceTemporarilyUnavailable => 'منبع موقتاً در دسترس نیست';

  @override
  String get errOutOfMemory => 'حافظه ناکافی';

  @override
  String get errPermissionDenied => 'دسترسی رد شد';

  @override
  String get errFileExists => 'فایل وجود دارد';

  @override
  String get errNotADirectory => 'یک پوشه نیست';

  @override
  String get errIsADirectory => 'یک پوشه است';

  @override
  String get errInvalidArgument => 'آرگومان نامعتبر';

  @override
  String get errTooManyOpenFiles => 'تعداد فایل‌های باز بیش از حد است';

  @override
  String get errNoSpaceLeftOnDevice => 'فضای خالی روی دستگاه وجود ندارد';

  @override
  String get errReadOnlyFileSystem => 'سیستم فایل فقط خواندنی';

  @override
  String get errBrokenPipe => 'لوله شکسته';

  @override
  String get errFileNameTooLong => 'نام فایل بیش از حد طولانی است';

  @override
  String get errDirectoryNotEmpty => 'پوشه خالی نیست';

  @override
  String get errAddressAlreadyInUse => 'آدرس در حال استفاده است';

  @override
  String get errCannotAssignAddress => 'آدرس درخواستی قابل تخصیص نیست';

  @override
  String get errNetworkIsDown => 'شبکه قطع است';

  @override
  String get errNetworkIsUnreachable => 'شبکه در دسترس نیست';

  @override
  String get errConnectionResetByPeer => 'اتصال توسط طرف مقابل بازنشانی شد';

  @override
  String get errConnectionTimedOut => 'وقفه زمانی اتصال';

  @override
  String get errConnectionRefused => 'اتصال رد شد';

  @override
  String get errHostIsDown => 'میزبان خاموش است';

  @override
  String get errNoRouteToHost => 'مسیری به میزبان وجود ندارد';

  @override
  String get errConnectionAborted => 'اتصال لغو شد';

  @override
  String get errAlreadyConnected => 'از قبل متصل است';

  @override
  String get errNotConnected => 'متصل نیست';

  @override
  String errSshConnectFailed(String host, int port) {
    return 'اتصال به $host:$port ناموفق بود';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return 'احراز هویت برای $user@$host ناموفق بود';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return 'اتصال به $host:$port ناموفق بود';
  }

  @override
  String get errSshAuthAborted => 'احراز هویت لغو شد';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return 'کلید میزبان برای $host:$port رد شد — کلید میزبان را بپذیرید یا known_hosts را بررسی کنید';
  }

  @override
  String get errSshOpenShellFailed => 'باز کردن شل ناموفق بود';

  @override
  String get errSshLoadKeyFileFailed => 'بارگذاری فایل کلید SSH ناموفق بود';

  @override
  String get errSshParseKeyFailed => 'تجزیه داده کلید PEM ناموفق بود';

  @override
  String get errSshConnectionDisposed => 'اتصال از بین رفته است';

  @override
  String get errSshNotConnected => 'متصل نیست';

  @override
  String get errConnectionFailed => 'اتصال ناموفق بود';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'وقفه زمانی اتصال پس از $seconds ثانیه';
  }

  @override
  String get errSessionClosed => 'جلسه بسته شد';

  @override
  String errShellError(String error) {
    return 'خطای شل: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'اتصال مجدد ناموفق بود: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'راه‌اندازی SFTP ناموفق بود: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'دانلود ناموفق بود: $error';
  }

  @override
  String get errDecryptionFailed =>
      'رمزگشایی اعتبارنامه ناموفق بود. فایل کلید ممکن است خراب باشد.';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'نام کاربری';

  @override
  String get protocol => 'پروتکل';

  @override
  String get typeLabel => 'نوع';

  @override
  String get folder => 'پوشه';

  @override
  String nSubitems(int count) {
    return '$count مورد';
  }

  @override
  String get subitems => 'موارد';

  @override
  String get storagePermissionRequired =>
      'برای مرور فایل‌های محلی مجوز ذخیره‌سازی لازم است';

  @override
  String get grantPermission => 'اعطای مجوز';

  @override
  String get storagePermissionLimited =>
      'دسترسی محدود — مجوز ذخیره‌سازی کامل برای همه فایل‌ها را اعطا کنید';

  @override
  String progressConnecting(String host, int port) {
    return 'اتصال به $host:$port';
  }

  @override
  String get progressVerifyingHostKey => 'تأیید کلید میزبان';

  @override
  String progressAuthenticating(String user) {
    return 'احراز هویت به‌عنوان $user';
  }

  @override
  String get progressOpeningShell => 'باز کردن شل';

  @override
  String get progressOpeningSftp => 'باز کردن کانال SFTP';

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
  String get maximize => 'بزرگ‌نمایی';

  @override
  String get restore => 'بازگردانی';

  @override
  String get duplicateDownShortcut => 'کپی به پایین (Ctrl+Shift+\\)';
}
