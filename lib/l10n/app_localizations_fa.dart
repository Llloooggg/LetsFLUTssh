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
  String get appSettings => 'تنظیمات برنامه';

  @override
  String get yes => 'بله';

  @override
  String get no => 'خیر';

  @override
  String get importWhatToImport => 'چه چیزی وارد شود:';

  @override
  String get exportWhatToExport => 'چه چیزی صادر شود:';

  @override
  String get enterMasterPasswordPrompt => 'رمز عبور اصلی را وارد کنید:';

  @override
  String get nextStep => 'بعدی';

  @override
  String get includeCredentials => 'شامل رمزهای عبور و کلیدهای SSH';

  @override
  String get includePasswords => 'رمزهای عبور نشست‌ها';

  @override
  String get embeddedKeys => 'کلیدهای جاسازی‌شده';

  @override
  String get managerKeys => 'کلیدها از مدیر';

  @override
  String get managerKeysMayBeLarge =>
      'کلیدهای مدیر ممکن است از اندازه QR فراتر رود';

  @override
  String get qrPasswordWarning =>
      'کلیدهای SSH به طور پیش‌فرض برای صدور غیرفعال هستند.';

  @override
  String get sshKeysMayBeLarge => 'کلیدها ممکن است از اندازه QR فراتر رود';

  @override
  String exportTotalSize(String size) {
    return 'حجم کل: $size';
  }

  @override
  String get qrCredentialsWarning =>
      'رمزهای عبور و کلیدهای SSH در کد QR قابل مشاهده خواهند بود';

  @override
  String get qrCredentialsTooLarge =>
      'اعتبارنامه‌ها کد QR را خیلی بزرگ می‌کنند';

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
  String get noResults => 'نتیجه‌ای نیست';

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
  String get openReleasePage => 'باز کردن صفحه انتشار';

  @override
  String get couldNotOpenInstaller => 'نصب‌کننده باز نشد';

  @override
  String get installerFailedOpenedReleasePage =>
      'اجرای نصب‌کننده ناموفق بود؛ صفحه انتشار در مرورگر باز شد';

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
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count پیوند کنار گذاشته شد (هدف وجود ندارد)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نشست خراب نادیده گرفته شد',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'جلسات';

  @override
  String get emptyFolders => 'پوشه‌های خالی';

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
  String get emptyFolder => 'پوشه خالی';

  @override
  String get qrGenerationFailed => 'تولید QR ناموفق بود';

  @override
  String get scanWithCameraApp =>
      'با هر برنامه دوربینی روی دستگاهی که LetsFLUTssh نصب است اسکن کنید.';

  @override
  String get noPasswordsInQr => 'رمز عبور یا کلیدی در این کد QR وجود ندارد';

  @override
  String get qrContainsCredentialsWarning =>
      'این کد QR حاوی اعتبارنامه‌ها است. صفحه را خصوصی نگه دارید.';

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
  String sshConfigPreviewHostsFound(int count) {
    return '$count میزبان یافت شد';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'هیچ میزبان قابل واردسازی در این فایل یافت نشد.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'نمی‌توان فایل‌های کلید را برای این موارد خواند: $hosts. این میزبان‌ها بدون اعتبارنامه وارد می‌شوند.';
  }

  @override
  String sshConfigPreviewFolderLabel(String folder) {
    return 'وارد شد به پوشه: $folder';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'خروجی گرفتن از آرشیو';

  @override
  String get exportArchiveSubtitle =>
      'ذخیره جلسات، تنظیمات و کلیدها در فایل رمزگذاری‌شده .lfs';

  @override
  String get exportQrCode => 'خروجی گرفتن کد QR';

  @override
  String get exportQrCodeSubtitle =>
      'اشتراک‌گذاری جلسات و کلیدهای انتخاب‌شده از طریق کد QR';

  @override
  String get importArchive => 'وارد کردن آرشیو';

  @override
  String get importArchiveSubtitle => 'بارگذاری داده از فایل .lfs';

  @override
  String get importFromSshDir => 'وارد کردن از ~/.ssh';

  @override
  String get importFromSshDirSubtitle =>
      'میزبان‌ها را از فایل پیکربندی و/یا کلیدهای خصوصی را از ~/.ssh انتخاب کنید';

  @override
  String get sshDirImportHostsSection => 'میزبان‌ها از فایل پیکربندی';

  @override
  String get sshDirImportKeysSection => 'کلیدها در ~/.ssh';

  @override
  String importSshKeysFound(int count) {
    return '$count کلید یافت شد — انتخاب کنید کدام‌ها وارد شوند';
  }

  @override
  String get importSshKeysNoneFound => 'هیچ کلید خصوصی در ~/.ssh یافت نشد.';

  @override
  String get sshKeyAlreadyImported => 'از قبل در مخزن موجود است';

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
      'حجم بیش از حد است — برخی موارد را حذف انتخاب کنید یا از خروجی فایل .lfs استفاده کنید.';

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
  String get errExportPickerUnavailable =>
      'انتخابگر پوشهٔ سیستم در دسترس نیست. مکان دیگری را امتحان کنید یا مجوزهای ذخیره‌سازی برنامه را بررسی کنید.';

  @override
  String get biometricUnlockPrompt => 'باز کردن قفل LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'باز کردن قفل با زیست‌سنجی';

  @override
  String get biometricUnlockSubtitle =>
      'هنگام اجرای برنامه نیازی به تایپ گذرواژهٔ اصلی نباشد.';

  @override
  String get biometricNotAvailable =>
      'باز کردن قفل زیست‌سنجی روی این دستگاه در دسترس نیست.';

  @override
  String get biometricEnableFailed =>
      'فعال‌سازی باز کردن قفل زیست‌سنجی ممکن نشد.';

  @override
  String get biometricEnabled => 'باز کردن قفل زیست‌سنجی فعال شد';

  @override
  String get biometricDisabled => 'باز کردن قفل زیست‌سنجی غیرفعال شد';

  @override
  String get biometricUnlockFailed =>
      'باز کردن قفل با زیست‌سنجی ناموفق بود. رمز عبور اصلی خود را وارد کنید.';

  @override
  String get biometricUnlockCancelled => 'باز کردن قفل با زیست‌سنجی لغو شد.';

  @override
  String get biometricNotEnrolled =>
      'هیچ اطلاعات زیست‌سنجی روی این دستگاه ثبت نشده است.';

  @override
  String get biometricRequiresMasterPassword =>
      'ابتدا یک رمز عبور اصلی تنظیم کنید تا باز کردن قفل با زیست‌سنجی فعال شود.';

  @override
  String get biometricSensorNotAvailable => 'این دستگاه سنسور زیست‌سنجی ندارد.';

  @override
  String get autoLockRequiresMasterPassword =>
      'ابتدا یک رمز عبور اصلی تنظیم کنید تا قفل خودکار فعال شود.';

  @override
  String get currentPasswordIncorrect => 'گذرواژهٔ فعلی نادرست است';

  @override
  String get wrongPassword => 'گذرواژهٔ نادرست';

  @override
  String get useKeychain => 'رمزگذاری با کی‌چین سیستم‌عامل';

  @override
  String get useKeychainSubtitle =>
      'کلید پایگاه داده در مخزن اعتبارنامهٔ سیستم ذخیره می‌شود. خاموش = پایگاه داده به‌صورت متن ساده.';

  @override
  String get lockScreenTitle => 'LetsFLUTssh قفل است';

  @override
  String get lockScreenSubtitle =>
      'برای ادامه، گذرواژهٔ اصلی را وارد کنید یا از زیست‌سنجی استفاده کنید.';

  @override
  String get unlock => 'باز کردن قفل';

  @override
  String get autoLockTitle => 'قفل خودکار پس از بی‌کاری';

  @override
  String get autoLockSubtitle =>
      'پس از این مدت بی‌کاری، رابط را قفل می‌کند. پایگاه داده رمزنگاری‌شده تنها زمانی دوباره قفل می‌شود که هیچ نشست فعال SSH وجود نداشته باشد، تا عملیات طولانی قطع نشوند.';

  @override
  String get autoLockOff => 'خاموش';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes دقیقه',
      one: '$minutes دقیقه',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'به‌روزرسانی رد شد: فایل‌های دانلود‌شده با کلید انتشار تثبیت‌شده در برنامه امضا نشده‌اند. این ممکن است به معنای دستکاری دانلود در مسیر باشد، یا انتشار فعلی برای این نصب نیست. نصب نکنید — به صورت دستی از صفحه انتشارهای رسمی دوباره نصب کنید.';

  @override
  String get updateSecurityWarningTitle => 'تأیید به‌روزرسانی ناموفق بود';

  @override
  String get updateReinstallAction => 'باز کردن صفحه انتشارها';

  @override
  String get errLfsNotArchive => 'فایل انتخاب‌شده یک بایگانی LetsFLUTssh نیست.';

  @override
  String get errLfsDecryptFailed => 'رمز اصلی اشتباه یا بایگانی .lfs خراب';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'بایگانی بسیار بزرگ است ($sizeMb مگابایت). محدودیت $limitMb مگابایت است — برای محافظت از حافظه، پیش از رمزگشایی لغو شد.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'ورودی known_hosts بسیار بزرگ است ($sizeMb مگابایت). محدودیت $limitMb مگابایت است — برای پاسخگو ماندن وارد کردن لغو شد.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'وارد کردن ناموفق بود — داده‌های شما به وضعیت پیش از وارد کردن بازگردانده شد. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'بایگانی از طرح v$found استفاده می‌کند، اما این نسخه فقط تا v$supported را پشتیبانی می‌کند. برای وارد کردن آن، برنامه را به‌روزرسانی کنید.';
  }

  @override
  String get progressReadingArchive => 'خواندن بایگانی…';

  @override
  String get progressDecrypting => 'در حال رمزگشایی…';

  @override
  String get progressParsingArchive => 'تحلیل بایگانی…';

  @override
  String get progressImportingSessions => 'در حال وارد کردن نشست‌ها';

  @override
  String get progressImportingFolders => 'در حال وارد کردن پوشه‌ها';

  @override
  String get progressImportingManagerKeys => 'در حال وارد کردن کلیدهای SSH';

  @override
  String get progressImportingTags => 'در حال وارد کردن برچسب‌ها';

  @override
  String get progressImportingSnippets => 'در حال وارد کردن قطعه‌ها';

  @override
  String get progressApplyingConfig => 'در حال اعمال پیکربندی…';

  @override
  String get progressImportingKnownHosts => 'در حال وارد کردن known_hosts…';

  @override
  String get progressCollectingData => 'در حال جمع‌آوری داده‌ها…';

  @override
  String get progressEncrypting => 'در حال رمزگذاری…';

  @override
  String get progressWritingArchive => 'در حال نوشتن بایگانی…';

  @override
  String get progressReencrypting => 'در حال رمزگذاری مجدد مخازن…';

  @override
  String get progressWorking => 'در حال پردازش…';

  @override
  String get importFromLink => 'درون‌ریزی از پیوند QR';

  @override
  String get importFromLinkSubtitle =>
      'پیوند letsflutssh:// کپی‌شده از دستگاه دیگر را بچسبانید';

  @override
  String get pasteImportLinkTitle => 'چسباندن پیوند درون‌ریزی';

  @override
  String get pasteImportLinkDescription =>
      'پیوند letsflutssh://import?d=… (یا بار خام) تولیدشده در دستگاه دیگر را بچسبانید. نیازی به دوربین نیست.';

  @override
  String get pasteFromClipboard => 'چسباندن از کلیپ‌بورد';

  @override
  String get invalidImportLink => 'پیوند بار معتبر LetsFLUTssh را شامل نیست';

  @override
  String get importAction => 'درون‌ریزی';

  @override
  String get saveSessionToAssignTags =>
      'برای اختصاص برچسب، ابتدا نشست را ذخیره کنید';

  @override
  String get noTagsAssigned => 'برچسبی اختصاص داده نشده';

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
  String get transfersLabel => 'انتقال‌ها:';

  @override
  String transferCountActive(int count) {
    return '$count فعال';
  }

  @override
  String transferCountQueued(int count) {
    return '، $count در صف';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count در تاریخچه';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'ایجاد شده: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'شروع شده: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'پایان یافته: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'مدت: $duration';
  }

  @override
  String get transferStatusQueued => 'در صف انتظار';

  @override
  String get transferStartingUpload => 'شروع آپلود...';

  @override
  String get transferStartingDownload => 'شروع دانلود...';

  @override
  String get transferCopying => 'در حال کپی...';

  @override
  String get transferDone => 'انجام شد';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total فایل';
  }

  @override
  String get fileConflictTitle => 'فایل از قبل وجود دارد';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" از قبل در $targetDir وجود دارد. چه کاری می‌خواهید انجام دهید؟';
  }

  @override
  String get fileConflictSkip => 'رد کردن';

  @override
  String get fileConflictKeepBoth => 'نگه داشتن هر دو';

  @override
  String get fileConflictReplace => 'جایگزینی';

  @override
  String get fileConflictApplyAll => 'اعمال برای همه موارد باقی‌مانده';

  @override
  String get folderNameLabel => 'نام پوشه';

  @override
  String folderAlreadyExists(String name) {
    return 'پوشه \"$name\" از قبل وجود دارد';
  }

  @override
  String get dropKeyFileHere => 'فایل کلید را اینجا رها کنید';

  @override
  String get sessionNoCredentials =>
      'جلسه بدون اعتبارنامه است — آن را ویرایش کنید تا رمز عبور یا کلید اضافه کنید';

  @override
  String dragItemCount(int count) {
    return '$count مورد';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'انتخاب همه ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'اندازه: $size کیلوبایت / حداکثر $max کیلوبایت';
  }

  @override
  String get noActiveTerminals => 'ترمینال فعالی وجود ندارد';

  @override
  String get connectFromSessionsTab => 'از تب جلسات متصل شوید';

  @override
  String fileNotFound(String path) {
    return 'فایل یافت نشد: $path';
  }

  @override
  String get sshConnectionChannel => 'اتصال SSH';

  @override
  String get sshConnectionChannelDesc =>
      'اتصالات SSH را در پس‌زمینه فعال نگه می‌دارد.';

  @override
  String get sshActive => 'SSH فعال';

  @override
  String activeConnectionCount(int count) {
    return '$count اتصال فعال';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count مورد، $size';
  }

  @override
  String get maximize => 'بزرگ‌نمایی';

  @override
  String get restore => 'بازگردانی';

  @override
  String get duplicateDownShortcut => 'کپی به پایین (Ctrl+Shift+\\)';

  @override
  String get security => 'امنیت';

  @override
  String get knownHosts => 'میزبان‌های شناخته شده';

  @override
  String get knownHostsSubtitle => 'مدیریت اثر انگشت سرورهای SSH قابل اعتماد';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count میزبان شناخته شده',
      zero: 'بدون میزبان شناخته شده',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'میزبان شناخته شده‌ای وجود ندارد. برای افزودن به سروری متصل شوید.';

  @override
  String get removeHost => 'حذف میزبان';

  @override
  String removeHostConfirm(String host) {
    return 'حذف $host از میزبان‌های شناخته شده؟ در اتصال بعدی کلید دوباره بررسی می‌شود.';
  }

  @override
  String get clearAllKnownHosts => 'پاک کردن همه میزبان‌های شناخته شده';

  @override
  String get clearAllKnownHostsConfirm =>
      'همه میزبان‌های شناخته شده حذف شوند؟ کلید هر سرور باید دوباره تأیید شود.';

  @override
  String get importKnownHosts => 'وارد کردن میزبان‌های شناخته شده';

  @override
  String get importKnownHostsSubtitle =>
      'وارد کردن از فایل OpenSSH known_hosts';

  @override
  String get exportKnownHosts => 'صادر کردن میزبان‌های شناخته شده';

  @override
  String importedHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count میزبان جدید وارد شد',
      zero: 'میزبان جدیدی وارد نشد',
    );
    return '$_temp0';
  }

  @override
  String get clearedAllHosts => 'همه میزبان‌های شناخته شده پاک شدند';

  @override
  String removedHost(String host) {
    return '$host حذف شد';
  }

  @override
  String get noHostsToExport => 'میزبانی برای صادر کردن وجود ندارد';

  @override
  String get tools => 'ابزارها';

  @override
  String get sshKeys => 'کلیدهای SSH';

  @override
  String get sshKeysSubtitle => 'مدیریت جفت کلیدهای SSH برای احراز هویت';

  @override
  String get noKeys => 'کلید SSH وجود ندارد. یکی را وارد کنید یا بسازید.';

  @override
  String get generateKey => 'ساخت کلید';

  @override
  String get importKey => 'وارد کردن کلید';

  @override
  String get keyLabel => 'نام کلید';

  @override
  String get keyLabelHint => 'مثلاً سرور کاری، GitHub';

  @override
  String get selectKeyType => 'نوع کلید';

  @override
  String get generating => 'در حال ساخت...';

  @override
  String keyGenerated(String label) {
    return 'کلید ساخته شد: $label';
  }

  @override
  String keyImported(String label) {
    return 'کلید وارد شد: $label';
  }

  @override
  String get deleteKey => 'حذف کلید';

  @override
  String deleteKeyConfirm(String label) {
    return 'حذف کلید \"$label\"؟ جلساتی که از آن استفاده می‌کنند دسترسی را از دست می‌دهند.';
  }

  @override
  String keyDeleted(String label) {
    return 'کلید حذف شد: $label';
  }

  @override
  String get publicKey => 'کلید عمومی';

  @override
  String get publicKeyCopied => 'کلید عمومی در کلیپ‌بورد کپی شد';

  @override
  String get pastePrivateKey => 'چسباندن کلید خصوصی (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'داده کلید PEM نامعتبر';

  @override
  String get selectFromKeyStore => 'انتخاب از مخزن کلید';

  @override
  String get noKeySelected => 'کلیدی انتخاب نشده';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count کلید',
      zero: 'بدون کلید',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'ساخته شده';

  @override
  String get passphraseRequired => 'عبارت عبور لازم است';

  @override
  String passphrasePrompt(String host) {
    return 'کلید SSH برای $host رمزنگاری شده است. عبارت عبور را برای باز کردن وارد کنید.';
  }

  @override
  String get passphraseWrong => 'عبارت عبور اشتباه است. دوباره تلاش کنید.';

  @override
  String get passphrase => 'عبارت عبور';

  @override
  String get rememberPassphrase => 'در این جلسه به خاطر بسپار';

  @override
  String get masterPasswordSubtitle =>
      'محافظت از اعتبارنامه‌های ذخیره شده با رمز عبور';

  @override
  String get setMasterPassword => 'تنظیم رمز عبور اصلی';

  @override
  String get changeMasterPassword => 'تغییر رمز عبور اصلی';

  @override
  String get removeMasterPassword => 'حذف رمز عبور اصلی';

  @override
  String get masterPasswordEnabled =>
      'اعتبارنامه‌ها با رمز عبور اصلی محافظت می‌شوند';

  @override
  String get masterPasswordDisabled =>
      'اعتبارنامه‌ها از کلید خودکار استفاده می‌کنند (بدون رمز عبور)';

  @override
  String get enterMasterPassword =>
      'رمز عبور اصلی را برای دسترسی به اعتبارنامه‌های ذخیره شده وارد کنید.';

  @override
  String get wrongMasterPassword => 'رمز عبور اشتباه. دوباره تلاش کنید.';

  @override
  String get newPassword => 'رمز عبور جدید';

  @override
  String get currentPassword => 'رمز عبور فعلی';

  @override
  String get masterPasswordSet => 'رمز عبور اصلی فعال شد';

  @override
  String get masterPasswordChanged => 'رمز عبور اصلی تغییر کرد';

  @override
  String get masterPasswordRemoved => 'رمز عبور اصلی حذف شد';

  @override
  String get masterPasswordWarning =>
      'اگر این رمز عبور را فراموش کنید، تمام رمزهای عبور و کلیدهای SSH ذخیره شده از بین می‌روند. بازیابی ممکن نیست.';

  @override
  String get forgotPassword => 'رمز عبور را فراموش کرده‌اید؟';

  @override
  String get forgotPasswordWarning =>
      'این کار تمام رمزهای عبور، کلیدهای SSH و عبارات عبور ذخیره شده را حذف می‌کند. جلسات و تنظیمات حفظ می‌شوند. این عمل قابل بازگشت نیست.';

  @override
  String get resetAndDeleteCredentials => 'بازنشانی و حذف داده‌ها';

  @override
  String get credentialsReset => 'تمام اعتبارنامه‌های ذخیره شده حذف شدند';

  @override
  String get derivingKey => 'در حال ساخت کلید رمزنگاری...';

  @override
  String get reEncrypting => 'در حال رمزنگاری مجدد داده‌ها...';

  @override
  String get confirmRemoveMasterPassword =>
      'رمز عبور فعلی را برای حذف محافظت رمز عبور اصلی وارد کنید. اعتبارنامه‌ها با کلید خودکار مجدداً رمزنگاری می‌شوند.';

  @override
  String get securitySetupTitle => 'تنظیمات امنیتی';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'زنجیره کلید سیستم شناسایی شد ($keychainName). داده‌های شما به طور خودکار با زنجیره کلید سیستم رمزنگاری می‌شوند.';
  }

  @override
  String get securitySetupKeychainOptional =>
      'همچنین می‌توانید رمز عبور اصلی برای محافظت بیشتر تنظیم کنید.';

  @override
  String get securitySetupNoKeychain =>
      'زنجیره کلید سیستم شناسایی نشد. بدون آن، داده‌های جلسه (میزبان‌ها، رمزهای عبور، کلیدها) به صورت متن ساده ذخیره می‌شوند.';

  @override
  String get securitySetupNoKeychainHint =>
      'این در WSL، لینوکس بدون رابط گرافیکی یا نصب‌های حداقلی عادی است. برای فعال‌سازی زنجیره کلید در لینوکس: libsecret و یک دیمن زنجیره کلید (مثلاً gnome-keyring) نصب کنید.';

  @override
  String get securitySetupRecommendMasterPassword =>
      'توصیه می‌کنیم رمز عبور اصلی برای محافظت از داده‌هایتان تنظیم کنید.';

  @override
  String get continueWithKeychain => 'ادامه با زنجیره کلید';

  @override
  String get continueWithoutEncryption => 'ادامه بدون رمزنگاری';

  @override
  String get securityLevel => 'سطح امنیت';

  @override
  String get securityLevelPlaintext => 'بدون';

  @override
  String get securityLevelKeychain => 'زنجیره کلید سیستم';

  @override
  String get securityLevelMasterPassword => 'رمز عبور اصلی';

  @override
  String get keychainStatus => 'زنجیره کلید';

  @override
  String get keychainAvailable => 'در دسترس';

  @override
  String get keychainNotAvailable => 'در دسترس نیست';

  @override
  String get enableKeychain => 'فعال‌سازی رمزنگاری زنجیره کلید';

  @override
  String get enableKeychainSubtitle =>
      'دوباره‌رمزنگاری داده‌های ذخیره‌شده با استفاده از زنجیره کلید سیستم';

  @override
  String get keychainEnabled => 'رمزنگاری زنجیره کلید فعال شد';

  @override
  String get manageMasterPassword => 'مدیریت رمز عبور اصلی';

  @override
  String get manageMasterPasswordSubtitle =>
      'تنظیم، تغییر یا حذف رمز عبور اصلی';

  @override
  String get snippets => 'قطعه‌ها';

  @override
  String get snippetsSubtitle =>
      'قطعه‌های دستوری قابل استفاده مجدد را مدیریت کنید';

  @override
  String get noSnippets => 'هنوز قطعه‌ای وجود ندارد';

  @override
  String get addSnippet => 'افزودن قطعه';

  @override
  String get editSnippet => 'ویرایش قطعه';

  @override
  String get deleteSnippet => 'حذف قطعه';

  @override
  String deleteSnippetConfirm(String title) {
    return 'قطعه «$title» حذف شود؟';
  }

  @override
  String get snippetTitle => 'عنوان';

  @override
  String get snippetTitleHint => 'مثلاً Deploy، راه‌اندازی مجدد سرویس';

  @override
  String get snippetCommand => 'دستور';

  @override
  String get snippetCommandHint => 'مثلاً sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'توضیح (اختیاری)';

  @override
  String get snippetDescriptionHint => 'این دستور چه می‌کند؟';

  @override
  String get snippetSaved => 'قطعه ذخیره شد';

  @override
  String snippetDeleted(String title) {
    return 'قطعه «$title» حذف شد';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count قطعه',
      one: '۱ قطعه',
      zero: 'بدون قطعه',
    );
    return '$_temp0';
  }

  @override
  String get runSnippet => 'اجرا';

  @override
  String get pinToSession => 'سنجاق کردن به این نشست';

  @override
  String get unpinFromSession => 'برداشتن سنجاق از این نشست';

  @override
  String get pinnedSnippets => 'سنجاق‌شده‌ها';

  @override
  String get allSnippets => 'همه';

  @override
  String get sendToTerminal => 'ارسال به پایانه';

  @override
  String get commandCopied => 'دستور کپی شد';

  @override
  String get tags => 'برچسب‌ها';

  @override
  String get tagsSubtitle =>
      'نشست‌ها و پوشه‌ها را با برچسب‌های رنگی سازماندهی کنید';

  @override
  String get noTags => 'هنوز برچسبی وجود ندارد';

  @override
  String get addTag => 'افزودن برچسب';

  @override
  String get deleteTag => 'حذف برچسب';

  @override
  String deleteTagConfirm(String name) {
    return 'برچسب «$name» حذف شود؟ از تمام نشست‌ها و پوشه‌ها حذف خواهد شد.';
  }

  @override
  String get tagName => 'نام برچسب';

  @override
  String get tagNameHint => 'مثلاً Production، Staging';

  @override
  String get tagColor => 'رنگ';

  @override
  String get tagCreated => 'برچسب ایجاد شد';

  @override
  String tagDeleted(String name) {
    return 'برچسب «$name» حذف شد';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count برچسب',
      one: '۱ برچسب',
      zero: 'بدون برچسب',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'مدیریت برچسب‌ها';

  @override
  String get editTags => 'ویرایش برچسب‌ها';

  @override
  String get fullBackup => 'پشتیبان‌گیری کامل';

  @override
  String get sessionsOnly => 'نشست‌ها';

  @override
  String get sessionKeysFromManager => 'کلیدهای نشست از مدیر';

  @override
  String get allKeysFromManager => 'همه کلیدها از مدیر';

  @override
  String exportTags(int count) {
    return 'برچسب‌ها ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'قطعه‌ها ($count)';
  }

  @override
  String get disableKeychain => 'غیرفعال‌سازی رمزنگاری کلیدستان';

  @override
  String get disableKeychainSubtitle =>
      'تغییر به ذخیره‌سازی متن ساده (توصیه نمی‌شود)';

  @override
  String get disableKeychainConfirm =>
      'پایگاه داده بدون کلید دوباره رمزنگاری می‌شود. نشست‌ها و کلیدها به‌صورت متن ساده روی دیسک ذخیره خواهند شد. ادامه می‌دهید؟';

  @override
  String get keychainDisabled => 'رمزنگاری کلیدستان غیرفعال شد';

  @override
  String get presetFullImport => 'واردات کامل';

  @override
  String get presetSelective => 'انتخابی';

  @override
  String get presetCustom => 'سفارشی';

  @override
  String get sessionSshKeys => 'کلیدهای SSH جلسه';

  @override
  String get allManagerKeys => 'همهٔ کلیدهای مدیر';

  @override
  String get browseFiles => 'انتخاب فایل…';

  @override
  String get sshDirSessionAlreadyImported => 'در جلسات موجود است';

  @override
  String get languageSubtitle => 'زبان رابط کاربری';

  @override
  String get themeSubtitle => 'تیره، روشن یا پیروی از سیستم';

  @override
  String get uiScaleSubtitle => 'مقیاس‌بندی کل رابط کاربری';

  @override
  String get terminalFontSizeSubtitle => 'اندازهٔ قلم در خروجی پایانه';

  @override
  String get scrollbackLinesSubtitle => 'اندازهٔ بافر تاریخچهٔ پایانه';

  @override
  String get keepAliveIntervalSubtitle =>
      'ثانیه‌ها بین بسته‌های SSH keep-alive (۰ = خاموش)';

  @override
  String get sshTimeoutSubtitle => 'مهلت اتصال به ثانیه';

  @override
  String get defaultPortSubtitle => 'درگاه پیش‌فرض برای جلسات جدید';

  @override
  String get parallelWorkersSubtitle => 'کارگران انتقال SFTP هم‌زمان';

  @override
  String get maxHistorySubtitle => 'حداکثر فرمان‌های ذخیره‌شده در تاریخچه';

  @override
  String get calculateFolderSizesSubtitle =>
      'نمایش حجم کل در کنار پوشه‌ها در نوار کناری';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'هنگام راه‌اندازی برنامه از گیت‌هاب نسخهٔ جدید را بررسی کن';

  @override
  String get enableLoggingSubtitle =>
      'ثبت رویدادهای برنامه در یک فایل گزارش چرخشی';

  @override
  String get exportWithoutPassword => 'بدون رمز عبور خروجی گرفته شود؟';

  @override
  String get exportWithoutPasswordWarning =>
      'آرشیو رمزگذاری نخواهد شد. هر کسی که به فایل دسترسی داشته باشد می‌تواند داده‌های شما از جمله رمزهای عبور و کلیدهای خصوصی را بخواند.';

  @override
  String get continueWithoutPassword => 'بدون رمز عبور ادامه بده';
}
