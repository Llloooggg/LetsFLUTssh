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
  String get infoDialogProtectsHeader => 'محافظت می‌کند در برابر';

  @override
  String get infoDialogDoesNotProtectHeader => 'محافظت نمی‌کند در برابر';

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
  String get credentialPromptPassphraseTitle => 'عبارت عبور کلید لازم است';

  @override
  String get credentialPromptPasswordTitle => 'گذرواژه لازم است';

  @override
  String get credentialPromptHint =>
      'برای تکمیل اتصال آن را وارد کنید. هرگز روی دیسک نوشته نمی‌شود.';

  @override
  String credentialPromptHintForSession(String session) {
    return 'برای تکمیل اتصال به «$session» آن را وارد کنید. هرگز روی دیسک نوشته نمی‌شود.';
  }

  @override
  String get credentialPromptRememberSession => 'برای این نشست به خاطر بسپار';

  @override
  String get passwordBlankPromptHint =>
      'خالی بگذارید تا هنگام اتصال پرسیده شود';

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
  String get cut => 'برش';

  @override
  String get paste => 'جای‌گذاری';

  @override
  String get select => 'انتخاب';

  @override
  String get copyModeTapToStart => 'برای تعیین ابتدای انتخاب لمس کنید';

  @override
  String get copyModeExtending => 'برای گسترش انتخاب بکشید';

  @override
  String get copyModeSetAnchor => 'تنظیم لنگر';

  @override
  String get copyModeCopySelection => 'کپی انتخاب';

  @override
  String get required => 'الزامی';

  @override
  String get errFillRequiredFields =>
      'فیلدهای الزامی نشان‌گذاری‌شده با * را پر کنید';

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
  String get includePasswords => 'رمزهای عبور نشست‌ها';

  @override
  String get embeddedKeys => 'کلیدهای نشست';

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
  String get checkNow => 'اکنون بررسی کنید';

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
  String get updateVerifying => 'در حال بررسی…';

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
  String get sectionAuthentication => 'احراز هویت';

  @override
  String get sectionAdvanced => 'پیشرفته';

  @override
  String get moreOptions => 'گزینه‌های بیشتر';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString قاعده تغییر مسیر پورت',
      zero: 'بدون قاعده تغییر مسیر پورت',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => 'مدیریت…';

  @override
  String get authMethodAgent => 'استفاده از ssh-agent سیستم';

  @override
  String get options => 'گزینه‌ها';

  @override
  String get sessionName => 'نام جلسه';

  @override
  String get sessionNameAutoFromHost => 'خودکار از میزبان';

  @override
  String get sessionNameAutoFromUrl => 'خودکار از میزبان URL';

  @override
  String get sessionNameAutoFromBucket => 'خودکار از سطل پیش‌فرض';

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
  String get savedTypeToChange => 'ذخیره شد — برای تغییر بنویسید';

  @override
  String get hidePemText => 'پنهان کردن متن PEM';

  @override
  String get pastePemKeyText => 'جای‌گذاری متن کلید PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

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
  String get clearHistory => 'پاک کردن تاریخچه';

  @override
  String get noTransfersYet => 'هنوز انتقالی انجام نشده';

  @override
  String get duplicateTab => 'کپی تب';

  @override
  String get duplicateTabShortcut => 'کپی تب (Ctrl+\\)';

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
  String get scrollbackLines => 'خطوط Scrollback';

  @override
  String get keepAliveInterval => 'فاصله ارسال نگه‌داشتن اتصال (ثانیه)';

  @override
  String get sshTimeout => 'وقفه زمانی SSH (ثانیه)';

  @override
  String get defaultPort => 'پورت پیش‌فرض';

  @override
  String get parallelWorkers => 'Workerهای موازی';

  @override
  String get maxHistory => 'حداکثر تاریخچه';

  @override
  String get calculateFolderSizes => 'محاسبه اندازه پوشه‌ها';

  @override
  String get verboseConnectionLog => 'گزارش اتصال مفصل';

  @override
  String get verboseConnectionLogSubtitle =>
      'ثبت کامل ردِ هندشیک SSH و احراز هویت در فایل لاگ (برای عیب‌یابی خطاهای اتصال)';

  @override
  String get exportData => 'خروجی گرفتن از داده';

  @override
  String get exportRecordings => 'ضبط‌های نشست';

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
  String get securityFieldsRequired => 'لطفاً تمام فیلدهای ضروری را پر کنید';

  @override
  String get passwordConfirmationRequired => 'لطفاً رمز عبور خود را تأیید کنید';

  @override
  String get passwordStrengthWeak => 'ضعیف';

  @override
  String get passwordStrengthModerate => 'متوسط';

  @override
  String get passwordStrengthStrong => 'قوی';

  @override
  String get passwordStrengthVeryStrong => 'بسیار قوی';

  @override
  String get tierPlaintextLabel => 'متن ساده';

  @override
  String get tierPlaintextSubtitle => 'بدون رمزنگاری — فقط مجوزهای فایل';

  @override
  String get tierKeychainLabel => 'Keychain';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'کلید در $keychain زندگی می‌کند — باز شدن خودکار هنگام راه‌اندازی';
  }

  @override
  String get tierKeychainUnavailable =>
      'زنجیره کلید سیستم‌عامل در این نصب در دسترس نیست.';

  @override
  String get tierHardwareLabel => 'سخت‌افزار';

  @override
  String get tierParanoidLabel => 'رمز عبور اصلی (Paranoid)';

  @override
  String get tierHardwareUnavailable =>
      'Vault سخت‌افزاری در این نصب در دسترس نیست.';

  @override
  String get pinLabel => 'رمز عبور';

  @override
  String get l2UnlockTitle => 'گذرواژه لازم است';

  @override
  String get l2UnlockHint => 'برای ادامه گذرواژه کوتاه خود را وارد کنید';

  @override
  String get l2WrongPassword => 'گذرواژه اشتباه';

  @override
  String get l3UnlockTitle => 'رمز عبور را وارد کنید';

  @override
  String get l3UnlockHint =>
      'رمز عبور، گاوصندوق وابسته به سخت‌افزار را باز می‌کند';

  @override
  String get l3WrongPin => 'رمز عبور اشتباه';

  @override
  String tierCooldownHint(int seconds) {
    return '$seconds ثانیه دیگر تلاش کنید';
  }

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
  String get dataLocation => 'محل داده';

  @override
  String get dataStorageSection => 'ذخیره‌سازی';

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
  String a11yConnectingTo(String host) {
    return 'در حال اتصال به $host';
  }

  @override
  String a11yConnectedTo(String host) {
    return 'متصل به $host';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return 'اتصال به $host قطع شد';
  }

  @override
  String a11yConnectionFailed(String host) {
    return 'اتصال به $host ناموفق بود';
  }

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
  String get qrTooManyForSingleCode =>
      'تعداد جلسات برای یک کد QR بیش از حد است. برخی را حذف انتخاب کنید یا از خروجی .lfs استفاده کنید.';

  @override
  String get qrTooLarge =>
      'حجم بیش از حد است — برخی موارد را حذف انتخاب کنید یا از خروجی فایل .lfs استفاده کنید.';

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
  String get archivedLog => 'گزارش بایگانی‌شده';

  @override
  String get loggingLevel => 'سطح گزارش';

  @override
  String get loggingLevelSubtitleInfo => 'ورودی‌های معمول + هشدارها + خطاها';

  @override
  String get loggingLevelSubtitleWarn => 'فقط مسیرهای تنزل‌یافته و خطاها';

  @override
  String get loggingLevelSubtitleError => 'فقط خطاها';

  @override
  String get loggingLevelSubtitleOff => 'گزارش‌های معمول نوشته نمی‌شوند';

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
  String get errBrokenPipe => 'Broken pipe';

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
  String get errConnectionLostReconnect =>
      'اتصال قطع شد — نشست قطع شد (خواب یا شبکه). از فهرست نشست‌ها دوباره وصل کنید.';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'وقفه زمانی اتصال پس از $seconds ثانیه';
  }

  @override
  String get errSessionClosed => 'جلسه بسته شد';

  @override
  String errSftpInitFailed(String error) {
    return 'راه‌اندازی SFTP ناموفق بود: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'دانلود ناموفق بود: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'انتخابگر پوشهٔ سیستم در دسترس نیست. مکان دیگری را امتحان کنید یا مجوزهای ذخیره‌سازی برنامه را بررسی کنید.';

  @override
  String get biometricUnlockPrompt => 'باز کردن قفل LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'باز کردن قفل با زیست‌سنجی';

  @override
  String get biometricUnlockSubtitle =>
      'گذرواژه را تایپ نکنید — با سنسور بیومتریک دستگاه قفل را باز کنید.';

  @override
  String get biometricEnableFailed =>
      'فعال‌سازی باز کردن قفل زیست‌سنجی ممکن نشد.';

  @override
  String get biometricUnlockFailed =>
      'باز کردن قفل با زیست‌سنجی ناموفق بود. رمز عبور اصلی خود را وارد کنید.';

  @override
  String get biometricUnlockCancelled => 'باز کردن قفل با زیست‌سنجی لغو شد.';

  @override
  String get biometricNotEnrolled =>
      'هیچ اطلاعات زیست‌سنجی روی این دستگاه ثبت نشده است.';

  @override
  String get biometricSensorNotAvailable => 'این دستگاه سنسور زیست‌سنجی ندارد.';

  @override
  String get biometricSystemServiceMissing =>
      'سرویس اثر انگشت (fprintd) نصب نشده است. README ← نصب را ببینید.';

  @override
  String get currentPasswordIncorrect => 'گذرواژهٔ فعلی نادرست است';

  @override
  String get wrongPassword => 'گذرواژهٔ نادرست';

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
      'پس از این مدت بی‌کاری، رابط را قفل می‌کند. در هر قفل‌شدن، کلید پایگاه‌داده پاک و فضای رمزنگاری‌شده بسته می‌شود؛ نشست‌های فعال به لطف یک حافظهٔ نهان اعتبارنامه به ازای هر نشست متصل می‌مانند که هنگام بستن نشست پاک می‌شود.';

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
  String get errReleaseManifestUnavailable =>
      'دسترسی به manifest انتشار ممکن نشد. احتمالاً مشکل شبکه است، یا انتشار هنوز در حال بارگذاری است. چند دقیقه بعد دوباره امتحان کنید.';

  @override
  String get updateSecurityWarningTitle => 'تأیید به‌روزرسانی ناموفق بود';

  @override
  String get updateReinstallAction => 'باز کردن صفحه انتشارها';

  @override
  String get errLfsNotArchive => 'فایل انتخاب‌شده یک بایگانی LetsFLUTssh نیست.';

  @override
  String get errLfsDecryptFailed => 'رمز اصلی اشتباه یا بایگانی .lfs خراب';

  @override
  String get errLfsArchiveTruncated =>
      'بایگانی ناقص است. دوباره دانلود کنید یا از دستگاه اصلی دوباره صادر کنید.';

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
  String get progressCollectingData => 'در حال جمع‌آوری داده‌ها…';

  @override
  String get progressEncrypting => 'در حال رمزگذاری…';

  @override
  String get progressWritingArchive => 'در حال نوشتن بایگانی…';

  @override
  String get progressWorking => 'در حال پردازش…';

  @override
  String get importFromLink => 'وارد کردن از لینک QR';

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
  String get importAction => 'وارد کردن';

  @override
  String get noTagsAvailable =>
      'هنوز برچسبی نیست — یکی در ابزارها → برچسب‌ها بسازید.';

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
  String get bucket => 'Bucket';

  @override
  String get prefix => 'Prefix';

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
  String get dropKeyFileHere => 'فایل کلید را اینجا بیندازید';

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
  String get clearedAllHosts => 'همه میزبان‌های شناخته شده پاک شدند';

  @override
  String removedHost(String host) {
    return '$host حذف شد';
  }

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
  String get addKey => 'افزودن کلید';

  @override
  String get addKeyMenuPaste => 'جای‌گذاری PEM';

  @override
  String get filePickerUnavailable =>
      'انتخابگر فایل در این سیستم در دسترس نیست';

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
  String get sshCertificate => 'Certificate';

  @override
  String get certImport => 'ایمپورت certificate';

  @override
  String get certImportTooltip =>
      'یک گواهی OpenSSH امضاشده توسط CA خود را پیوست کنید (فایل `-cert.pub` از `ssh-keygen -s …`). زمانی استفاده کنید که سرورها به‌جای `authorized_keys` با امضای CA تأیید می‌کنند. اگر سرورهای شما از plain key auth استفاده می‌کنند، صرف نظر کنید.';

  @override
  String get certImportPickerTitle =>
      'فایل certificate از نوع OpenSSH را انتخاب کنید';

  @override
  String get certValidFrom => 'معتبر از';

  @override
  String get certValidTo => 'معتبر تا';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => 'این certificate به‌زودی منقضی می‌شود.';

  @override
  String get certExpired => 'منقضی';

  @override
  String get certRemove => 'حذف certificate';

  @override
  String get certRemoveConfirmTitle => 'certificate حذف شود؟';

  @override
  String get certRemoveConfirmBody =>
      'بعد از حذف، در اتصال بعدی به مسیر public key معمولی برمی‌گردد.';

  @override
  String errCertParse(String detail) {
    return 'Certificate پارس نشد: $detail';
  }

  @override
  String get errCertPairFingerprintMismatch =>
      'این certificate با کلید انتخاب‌شده جفت نیست.';

  @override
  String get pastePrivateKey => 'چسباندن کلید خصوصی (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'داده کلید PEM نامعتبر';

  @override
  String get selectFromKeyStore => 'انتخاب از مخزن کلید';

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
  String get passphrase => 'عبارت عبور';

  @override
  String get enterMasterPassword =>
      'رمز عبور اصلی را برای دسترسی به اعتبارنامه‌های ذخیره شده وارد کنید.';

  @override
  String get wrongMasterPassword => 'رمز عبور اشتباه. دوباره تلاش کنید.';

  @override
  String get currentPassword => 'رمز عبور فعلی';

  @override
  String get forgotPassword => 'رمز عبور را فراموش کرده‌اید؟';

  @override
  String get credentialsReset => 'تمام اعتبارنامه‌های ذخیره شده حذف شدند';

  @override
  String get migrationToast => 'ذخیره‌سازی به آخرین فرمت ارتقا یافت';

  @override
  String get dbCorruptTitle => 'باز کردن پایگاه داده ممکن نیست';

  @override
  String get dbCorruptBody =>
      'داده‌های روی دیسک باز نمی‌شوند. اعتبارنامه دیگری امتحان کنید یا برای شروع تازه بازنشانی کنید.';

  @override
  String get dbCorruptWarning =>
      'بازنشانی، پایگاه داده رمزگذاری‌شده و تمام فایل‌های مربوط به امنیت را برای همیشه حذف می‌کند. هیچ داده‌ای بازیابی نخواهد شد.';

  @override
  String get dbCorruptTryOther => 'تلاش با اعتبارنامه دیگر';

  @override
  String get dbCorruptResetContinue => 'بازنشانی و راه‌اندازی تازه';

  @override
  String get dbCorruptExit => 'خروج از LetsFLUTssh';

  @override
  String get tierResetTitle => 'بازنشانی امنیتی لازم است';

  @override
  String get tierResetBody =>
      'این نصب شامل داده‌های امنیتی از نسخه‌ای قدیمی از LetsFLUTssh است که از مدل لایه‌های متفاوتی استفاده می‌کرد. مدل جدید یک تغییر ناسازگار است — مسیر مهاجرت خودکار وجود ندارد. برای ادامه، همه جلسات ذخیره‌شده، اعتبارنامه‌ها، کلیدهای SSH و میزبان‌های شناخته‌شده در این نصب باید پاک شوند و راهنمای راه‌اندازی اولیه دوباره اجرا شود.';

  @override
  String get tierResetWarning =>
      'انتخاب «بازنشانی و راه‌اندازی جدید» پایگاه داده رمزگذاری‌شده و تمام فایل‌های مرتبط با امنیت را برای همیشه حذف می‌کند. اگر نیاز به بازیابی داده‌های خود دارید، اکنون از برنامه خارج شوید و نسخه قبلی LetsFLUTssh را دوباره نصب کنید تا ابتدا صادر شوند.';

  @override
  String get tierResetResetContinue => 'بازنشانی و راه‌اندازی جدید';

  @override
  String get tierResetExit => 'خروج از LetsFLUTssh';

  @override
  String get derivingKey => 'در حال ساخت کلید رمزنگاری...';

  @override
  String get securitySetupTitle => 'تنظیمات امنیتی';

  @override
  String get keychainAvailable => 'در دسترس';

  @override
  String get changeSecurityTierConfirm =>
      'در حال رمزگذاری مجدد پایگاه داده با سطح جدید. قابل قطع نیست — تا پایان برنامه را باز نگه دارید.';

  @override
  String get changeSecurityTierDone => 'سطح امنیت تغییر کرد';

  @override
  String get changeSecurityTierFailed => 'تغییر سطح امنیت ممکن نشد';

  @override
  String get firstLaunchSecurityTitle => 'ذخیره‌سازی امن فعال شد';

  @override
  String get firstLaunchSecurityBody =>
      'داده‌های شما با کلیدی که در Keychain سیستم نگهداری می‌شود رمزگذاری می‌شوند. باز کردن قفل روی این دستگاه خودکار است.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'ذخیره‌سازی مبتنی بر سخت‌افزار روی این دستگاه در دسترس است. برای اتصال TPM / Secure Enclave از تنظیمات ← امنیت ارتقا دهید.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'ذخیره‌سازی مبتنی بر سخت‌افزار روی این دستگاه در دسترس نیست.';

  @override
  String get firstLaunchSecurityOpenSettings => 'باز کردن تنظیمات';

  @override
  String get wizardReducedBanner =>
      'Keychain سیستم در این نصب قابل دسترسی نیست. بین «بدون رمزگذاری» (T0) و گذرواژهٔ اصلی (Paranoid) انتخاب کنید. برای فعال‌سازی سطح Keychain، gnome-keyring، kwallet یا ارائه‌دهندهٔ libsecret دیگری را نصب کنید.';

  @override
  String get tierBadgeCurrent => 'فعلی';

  @override
  String get securitySetupEnable => 'فعال‌سازی';

  @override
  String get securitySetupApply => 'اعمال';

  @override
  String get hwProbeLinuxDeviceMissing =>
      'هیچ TPM در /dev/tpmrm0 شناسایی نشد. اگر دستگاه پشتیبانی می‌کند، fTPM / PTT را در BIOS فعال کنید؛ در غیر این صورت سطح سخت‌افزاری روی این دستگاه در دسترس نیست.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools نصب نیست. برای فعال‌سازی سطح سخت‌افزاری `sudo apt install tpm2-tools` (یا معادل در توزیع خود) را اجرا کنید.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'بررسی سطح سخت‌افزاری ناموفق بود. مجوزهای /dev/tpmrm0 و قوانین udev را بررسی کنید — جزئیات در لاگ‌ها.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'TPM 2.0 شناسایی نشد. fTPM / PTT را در سفت‌افزار UEFI فعال کنید، یا بپذیرید که سطح سخت‌افزاری روی این دستگاه در دسترس نیست — برنامه به فروشگاه اعتبارنامه مبتنی بر نرم‌افزار بازمی‌گردد.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'نه Microsoft Platform Crypto Provider و نه Software Key Storage Provider در دسترس هستند — احتمالاً زیرسیستم رمزنگاری Windows آسیب دیده یا Group Policy مانع CNG شده است. Event Viewer → Applications and Services Logs را بررسی کنید.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'این Mac فاقد Secure Enclave است (Intel Mac قبل از ۲۰۱۷ بدون تراشه امنیتی T1 / T2). سطح سخت‌افزاری در دسترس نیست؛ از رمز عبور اصلی استفاده کنید.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'رمز عبور ورود روی این Mac تنظیم نشده است. ایجاد کلید Secure Enclave به آن نیاز دارد — در System Settings ← Touch ID & Password (یا Login Password) تنظیم کنید.';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave هویت امضای برنامه را رد کرد (-34018). اسکریپت `macos-resign.sh` همراه نسخه را اجرا کنید تا به این نصب یک هویت پایدار خودامضا داده شود، سپس برنامه را دوباره راه‌اندازی کنید.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'رمز دستگاه تنظیم نشده است. ایجاد کلید Secure Enclave به آن نیاز دارد — در تنظیمات ← Face ID & Passcode (یا Touch ID & Passcode) تنظیم کنید.';

  @override
  String get hwProbeIosSimulator =>
      'در iOS Simulator اجرا می‌شود که Secure Enclave ندارد. سطح سخت‌افزاری فقط در دستگاه‌های فیزیکی iOS در دسترس است.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'برای سطح سخت‌افزاری به Android 9 یا جدیدتر نیاز است (StrongBox و باطل‌سازی هر کلید هنگام تغییر ثبت در نسخه‌های قدیمی قابل اعتماد نیستند).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'این دستگاه سخت‌افزار بیومتریک ندارد (اثر انگشت یا چهره). از رمز عبور اصلی استفاده کنید.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'هیچ بیومتریکی ثبت نشده است. در تنظیمات ← امنیت و حریم خصوصی ← بیومتریک، اثر انگشت یا چهره اضافه کنید، سپس سطح سخت‌افزاری را دوباره فعال کنید.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'سخت‌افزار بیومتریک به طور موقت غیرقابل استفاده است (قفل پس از تلاش‌های ناموفق یا به‌روزرسانی امنیتی در انتظار). چند دقیقه دیگر امتحان کنید.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'Android Keystore در این نسخهٔ دستگاه از پشتیبانی کلید سخت‌افزاری امتناع کرد (StrongBox در دسترس نیست، ROM سفارشی یا خطای درایور). لایهٔ سخت‌افزاری در دسترس نیست.';

  @override
  String get securityRecheck => 'بررسی مجدد پشتیبانی لایه‌ها';

  @override
  String get securityRecheckUpdated =>
      'پشتیبانی لایه‌ها به‌روزرسانی شد — کارت‌های بالا را ببینید';

  @override
  String get securityRecheckUnchanged => 'پشتیبانی لایه‌ها بدون تغییر';

  @override
  String get securityMacosEnableSecureTiers =>
      'باز کردن لایه‌های امن در این Mac';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'برنامه را با یک گواهی شخصی دوباره امضا کنید تا Keychain (T1) و Secure Enclave (T2) پس از به‌روزرسانی کار کنند';

  @override
  String get securityMacosEnableSecureTiersPrompt =>
      'مک یک بار رمز عبور شما را می‌خواهد';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'لایه‌های امن باز شد — T1 و T2 اکنون در دسترس هستند';

  @override
  String get securityMacosEnableSecureTiersFailed =>
      'باز کردن لایه‌های امن ناموفق بود';

  @override
  String get securityMacosOfferTitle => 'فعال‌سازی Keychain + Secure Enclave؟';

  @override
  String get securityMacosOfferBody =>
      'macOS ذخیره‌سازی رمزگذاری‌شده را به هویت امضای برنامه گره می‌زند. بدون گواهی پایدار، Keychain (T1) و Secure Enclave (T2) دسترسی را رد می‌کنند. می‌توانیم یک گواهی شخصی خودامضا روی این مک ایجاد کنیم و برنامه را با آن دوباره امضا کنیم — به‌روزرسانی‌ها ادامه می‌یابند و اسرار شما در نسخه‌ها باقی می‌مانند. مک یک بار رمز ورود شما را می‌خواهد تا به گواهی جدید اعتماد کند.';

  @override
  String get securityMacosOfferAccept => 'فعال‌سازی';

  @override
  String get securityMacosOfferDecline =>
      'رد کردن — T0 یا Paranoid انتخاب کنید';

  @override
  String get securityMacosRemoveIdentity => 'حذف هویت امضا';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      'گواهی شخصی را حذف می‌کند. داده‌های T1 / T2 به آن وابسته‌اند — ابتدا به T0 یا Paranoid تغییر دهید سپس حذف کنید.';

  @override
  String get securityMacosRemoveIdentityConfirmTitle => 'حذف هویت امضا؟';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'گواهی شخصی را از Keychain ورود حذف می‌کند. اسرار ذخیره‌شده T1 / T2 ناخوانا می‌شوند. جادوگر برای مهاجرت به T0 (متن ساده) یا Paranoid (گذرواژه اصلی) قبل از حذف باز می‌شود.';

  @override
  String get securityMacosRemoveIdentitySuccess => 'هویت امضا حذف شد';

  @override
  String get securityMacosRemoveIdentityFailed => 'حذف هویت امضا ناموفق بود';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus فعال است اما هیچ secret-service daemon در حال اجرا نیست. gnome-keyring (`sudo apt install gnome-keyring`) یا KWalletManager را نصب کنید و مطمئن شوید که هنگام ورود به سیستم اجرا می‌شود.';

  @override
  String get keyringProbeFailed =>
      'OS keychain در این دستگاه قابل دسترسی نیست. برای خطای مخصوص پلتفرم به لاگ‌ها مراجعه کنید؛ برنامه به رمز عبور اصلی بازمی‌گردد.';

  @override
  String get snippets => 'اسنیپت‌ها';

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
  String get pinToSession => 'سنجاق کردن به این نشست';

  @override
  String get unpinFromSession => 'برداشتن سنجاق از این نشست';

  @override
  String get pinnedSnippets => 'سنجاق‌شده‌ها';

  @override
  String get allSnippets => 'همه';

  @override
  String get commandCopied => 'دستور کپی شد';

  @override
  String get snippetTokensHint =>
      'برای درج یک مکان‌نما ضربه بزنید. این‌ها در زمان اجرا با مقادیر نشست فعال جایگزین می‌شوند:';

  @override
  String get snippetCustomTokensHint =>
      'هر چیز دیگری با دو آکولاد هنگام اجرای قطعه از شما مقدار می‌خواهد.';

  @override
  String get snippetFillTitle => 'پارامترهای قطعه را پر کنید';

  @override
  String get snippetFillSubmit => 'اجرا';

  @override
  String get broadcastSetDriver => 'پخش از این پنل';

  @override
  String get broadcastClearDriver => 'توقف پخش از این پنل';

  @override
  String get broadcastAddReceiver => 'دریافت پخش در اینجا';

  @override
  String get broadcastRemoveReceiver => 'توقف دریافت پخش';

  @override
  String get broadcastClearAll => 'توقف تمام پخش‌ها';

  @override
  String get broadcastPasteTitle => 'ارسال چسباندن به همه پنل‌ها؟';

  @override
  String broadcastPasteBody(int chars, int count) {
    return '$chars نویسه به $count پنل دیگر ارسال می‌شود.';
  }

  @override
  String get broadcastPasteSend => 'ارسال';

  @override
  String get portForwarding => 'فوروارد';

  @override
  String get portForwardingEmpty => 'هنوز قاعده‌ای نیست';

  @override
  String get addForwardRule => 'افزودن قاعده';

  @override
  String get editForwardRule => 'ویرایش قاعده';

  @override
  String get deleteForwardRule => 'حذف قاعده';

  @override
  String get localForward => 'محلی';

  @override
  String get remoteForward => 'راه دور';

  @override
  String get dynamicForward => 'پویا';

  @override
  String get forwardKind => 'نوع';

  @override
  String get bindAddress => 'آدرس باند';

  @override
  String get bindPort => 'پورت باند';

  @override
  String get targetHost => 'میزبان هدف';

  @override
  String get targetPort => 'پورت هدف';

  @override
  String get forwardDescription => 'توضیح (اختیاری)';

  @override
  String get forwardEnabled => 'فعال';

  @override
  String get forwardBindWildcardWarning =>
      'باند به 0.0.0.0 فوروارد را روی همه واسط‌ها منتشر می‌کند — معمولاً 127.0.0.1 می‌خواهید.';

  @override
  String get forwardKindLocalHelp =>
      'محلی: یک پورت روی این دستگاه باز می‌کند که به هدف قابل دسترسی از سرور SSH تونل می‌زند. مفید برای دسترسی به پایگاه‌های داده دور یا UI ادمین در localhost:bindPort.';

  @override
  String get forwardKindRemoteHelp =>
      'راه دور: از سرور SSH می‌خواهد پورتی باز کند که به هدف قابل دسترسی از این دستگاه برمی‌گردد. مفید برای اشتراک سرور توسعه محلی با میزبان راه دور (ممکن است سرور به GatewayPorts yes برای bind غیر loopback نیاز داشته باشد).';

  @override
  String get forwardKindDynamicHelp =>
      'پویا: پروکسی SOCKS5 روی این دستگاه که هر اتصال را از طریق سرور SSH هدایت می‌کند. مرورگر یا curl را به localhost:bindPort اشاره دهید تا تمام ترافیک از طریق SSH ارسال شود.';

  @override
  String get proxyJump => 'اتصال از طریق';

  @override
  String get proxyJumpNone => 'اتصال مستقیم';

  @override
  String get proxyJumpSavedSession => 'نشست ذخیره‌شده';

  @override
  String get proxyJumpCustom => 'سفارشی';

  @override
  String get proxyJumpCustomNote =>
      'پرش‌های سفارشی از اعتبارنامه‌های همین نشست استفاده می‌کنند. برای احراز هویت متفاوت بستیون، آن را به‌عنوان نشست جداگانه ذخیره کنید.';

  @override
  String viaSessionLabel(String label) {
    return 'از طریق $label';
  }

  @override
  String get recordSession => 'ضبط نشست';

  @override
  String get recordSessionHelp =>
      'ذخیره خروجی پایانه روی دیسک برای این نشست. در حالت ساکن رمزگذاری می‌شود وقتی گذرواژه اصلی یا کلید سخت‌افزاری از پایگاه‌داده نشست‌ها محافظت می‌کند؛ در غیر این صورت در کنار پایگاه‌داده به‌صورت متن ساده ذخیره می‌شود.';

  @override
  String get recordingsBrowserTitle => 'ضبط‌ها';

  @override
  String get recordingsBrowserSubtitle =>
      'مرور، پخش مجدد و حذف نشست‌های ضبط شده';

  @override
  String get recordingsEmpty => 'هنوز ضبطی وجود ندارد';

  @override
  String get playRecording => 'پخش';

  @override
  String get deleteRecording => 'حذف';

  @override
  String get recordingPlaybackTitle => 'پخش مجدد ضبط';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

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
  String get presetFullImport => 'واردات کامل';

  @override
  String get presetSelective => 'انتخابی';

  @override
  String get presetCustom => 'سفارشی';

  @override
  String get sessionSshKeys => 'کلیدهای جلسه (مدیر)';

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
  String get terminalFontSizeSubtitle => 'اندازهٔ فونت در خروجی ترمینال';

  @override
  String get scrollbackLinesSubtitle => 'اندازهٔ بافر تاریخچهٔ ترمینال';

  @override
  String get keepAliveIntervalSubtitle =>
      'ثانیه‌ها بین بسته‌های SSH keep-alive (۰ = خاموش)';

  @override
  String get sshTimeoutSubtitle => 'مهلت اتصال به ثانیه';

  @override
  String get defaultPortSubtitle => 'درگاه پیش‌فرض برای جلسات جدید';

  @override
  String get parallelWorkersSubtitle => 'Workerهای انتقال SFTP هم‌زمان';

  @override
  String get maxHistorySubtitle => 'حداکثر فرمان‌های ذخیره‌شده در تاریخچه';

  @override
  String get calculateFolderSizesSubtitle =>
      'نمایش حجم کل در کنار پوشه‌ها در نوار کناری';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'هنگام راه‌اندازی برنامه از گیت‌هاب نسخهٔ جدید را بررسی کنید';

  @override
  String get threatColdDiskTheft => 'سرقت دیسک آفلاین';

  @override
  String get threatColdDiskTheftDescription =>
      'دستگاهی که خاموش است، درایو آن بیرون کشیده شده و روی رایانهٔ دیگری خوانده می‌شود، یا رونوشتی از فایل پایگاه داده که کسی با دسترسی به پوشهٔ خانگی شما برداشته است.';

  @override
  String get threatKeyringFileTheft => 'سرقت فایل keyring / keychain';

  @override
  String get threatKeyringFileTheftDescription =>
      'مهاجم فایل مخزن اعتبارنامه پلتفرم را مستقیماً از دیسک می‌خواند (libsecret keyring، Windows Credential Manager، macOS login keychain) و کلید بسته‌بندی‌شدهٔ پایگاه داده را از آن بازیابی می‌کند. سطح سخت‌افزاری این را بدون توجه به رمز عبور مسدود می‌کند زیرا تراشه از خروج‌دهی مواد کلید سر باز می‌زند؛ سطح keychain به رمز عبور اضافی نیاز دارد و در غیر این صورت فایل دزدیده‌شده تنها با رمز ورود سیستم‌عامل باز می‌شود.';

  @override
  String get modifierOnlyWithPassword => 'فقط با رمز عبور';

  @override
  String get threatBystanderUnlockedMachine => 'ناظر کنار دستگاه قفل‌گشوده';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'در غیاب شما، فردی به رایانهٔ از پیش قفل‌گشودهٔ شما نزدیک می‌شود و برنامه را باز می‌کند.';

  @override
  String get threatLiveRamForensicsLocked => 'فارنزیک RAM روی دستگاه قفل';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'مهاجم RAM را فریز می‌کند (یا از طریق DMA آن را می‌گیرد) و key material هنوز باقی‌مانده در snapshot حافظه را حتی هنگام قفل‌بودن برنامه بیرون می‌کشد.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'نفوذ به kernel سیستم‌عامل یا keychain';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'آسیب‌پذیری kernel، خروج داده از keychain، یا backdoor در تراشهٔ امنیتی سخت‌افزاری. سیستم‌عامل به جای منبعی قابل اعتماد، خود تبدیل به مهاجم می‌شود.';

  @override
  String get threatOfflineBruteForce => 'حملهٔ brute-force آفلاین به رمز ضعیف';

  @override
  String get threatOfflineBruteForceDescription =>
      'مهاجمی که کپی کلید wrap‌شده یا blob مهروموم‌شده را دارد، بدون rate limit، با سرعت دلخواه همهٔ رمزها را امتحان می‌کند.';

  @override
  String get legendProtects => 'محافظت می‌شود';

  @override
  String get legendDoesNotProtect => 'محافظت نمی‌شود';

  @override
  String get colT0 => 'T0 متن ساده';

  @override
  String get colT1 => 'T1 Keychain';

  @override
  String get colT1Password => 'T1 + رمز';

  @override
  String get colT1PasswordBiometric => 'T1 + رمز + زیست‌سنجی';

  @override
  String get colT2Password => 'T2 + رمز';

  @override
  String get colT2PasswordBiometric => 'T2 + رمز + زیست‌سنجی';

  @override
  String get colParanoid => 'Paranoid';

  @override
  String get securityComparisonTableThreatColumn => 'تهدید';

  @override
  String get compareAllTiers => 'مقایسهٔ همهٔ سطوح';

  @override
  String get resetAllDataTitle => 'بازنشانی همهٔ داده‌ها';

  @override
  String get resetAllDataSubtitle =>
      'حذف همهٔ نشست‌ها، کلیدها، پیکربندی‌ها و مؤلفه‌های امنیتی. ورودی‌های کی‌چین و اسلات‌های خزانهٔ سخت‌افزاری نیز پاک می‌شوند.';

  @override
  String get resetAllDataConfirmTitle => 'همهٔ داده‌ها بازنشانی شود؟';

  @override
  String get resetAllDataConfirmBody =>
      'همهٔ نشست‌ها، کلیدهای SSH، فهرست known hosts، قطعه‌کدها، برچسب‌ها، تنظیمات و همهٔ مؤلفه‌های امنیتی (ورودی‌های کی‌چین، دادهٔ خزانهٔ سخت‌افزاری، لایهٔ زیست‌سنجی) برای همیشه حذف خواهند شد. این عمل قابل بازگشت نیست.';

  @override
  String get resetAllDataConfirmAction => 'بازنشانی همه';

  @override
  String resetAllDataConfirmTypePrompt(String phrase) {
    return 'برای تأیید، $phrase را در زیر تایپ کنید:';
  }

  @override
  String get resetAllDataInProgress => 'در حال بازنشانی…';

  @override
  String get resetAllDataDone => 'همهٔ داده‌ها بازنشانی شدند';

  @override
  String get resetAllDataFailed => 'بازنشانی ناموفق بود';

  @override
  String get recordingsTitle => 'ضبط‌ها';

  @override
  String get recordingsStorageUsedLabel => 'استفاده‌شده';

  @override
  String get recordingsCapLabel => 'سقف';

  @override
  String get recordingsCapHint =>
      'سقف سخت برای پوشهٔ recordings/. هنگام عبور، قدیمی‌ترین ضبط ابتدا حذف می‌شود؛ ضبط جاری هرگز دست‌کاری نمی‌شود.';

  @override
  String get recordingsClearAllAction => 'پاک کردن همهٔ ضبط‌ها';

  @override
  String get recordingsClearAllConfirmTitle => 'همهٔ ضبط‌ها پاک شود؟';

  @override
  String get recordingsClearAllConfirmBody =>
      'هر سشن ضبط‌شده در <app>/recordings/ حذف خواهد شد. ضبط در حال انجام (در صورت وجود) باقی می‌ماند. این عمل قابل بازگشت نیست.';

  @override
  String recordingsClearAllResult(int count) {
    return '$count ضبط حذف شد';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return 'سقف به‌روزرسانی شد. $bytes آزاد شد.';
  }

  @override
  String get recordingsCapChangedNoChange =>
      'سقف به‌روزرسانی شد. چیزی برای حذف نیست.';

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
      'قفل خودکار نیازمند رمز عبور در سطح فعلی است.';

  @override
  String get recommendedBadge => 'توصیه‌شده';

  @override
  String get tierHardwareSubtitleHonest =>
      'پیشرفته: کلید به سخت‌افزار گره خورده، همیشه با رمز عبور محافظت می‌شود. اگر تراشه این دستگاه گم یا تعویض شود، داده‌ها قابل بازیابی نیستند.';

  @override
  String get tierParanoidSubtitleHonest =>
      'جایگزین: رمز عبور اصلی، بدون اعتماد به سیستم‌عامل. در برابر نفوذ OS محافظت می‌کند. حفاظت زمان اجرا را نسبت به T1/T2 بهبود نمی‌دهد.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'تهدیدهای runtime (malware از همان کاربر، دامپ حافظهٔ فرآیند فعال) در همهٔ سطح‌ها به‌صورت ✗ نمایش داده می‌شوند. این موارد توسط قابلیت‌های کاهش ریسک جداگانه‌ای برطرف می‌شوند که مستقل از انتخاب سطح اعمال می‌گردند.';

  @override
  String get currentTierBadge => 'فعلی';

  @override
  String get paranoidAlternativeHeader => 'جایگزین';

  @override
  String get modifierPasswordLabel => 'رمز عبور';

  @override
  String get modifierPasswordSubtitle =>
      'دروازهٔ مخفیِ تایپ‌شده پیش از باز شدن گاوصندوق.';

  @override
  String get modifierPasswordRequired =>
      'الزامی — لایه Hardware همیشه با رمز محافظت می‌شود.';

  @override
  String get modifierBiometricLabel => 'میان‌برِ بیومتریک';

  @override
  String get modifierBiometricSubtitle =>
      'گرفتن رمز عبور از یک اسلات سیستم‌عامل با حفاظ بیومتریک به جای تایپ آن.';

  @override
  String get biometricRequiresPassword =>
      'ابتدا یک رمز عبور فعال کنید — بیومتریک تنها میان‌بری برای وارد کردن آن است.';

  @override
  String get biometricRequiresActiveTier =>
      'برای فعال‌سازی باز کردن قفل بیومتریک ابتدا این سطح را انتخاب کنید';

  @override
  String get autoLockRequiresActiveTier =>
      'برای پیکربندی قفل خودکار ابتدا این سطح را انتخاب کنید';

  @override
  String get biometricForbiddenParanoid =>
      'سطح Paranoid به‌طور طراحی‌شده اجازهٔ بیومتریک را نمی‌دهد.';

  @override
  String get fprintdNotAvailable =>
      'fprintd نصب نشده یا هیچ اثر انگشتی ثبت نشده است.';

  @override
  String get t2RequiresPasswordTitle =>
      'یک رمز master برای لایه Hardware تعیین کنید';

  @override
  String get t2RequiresPasswordBody =>
      'لایه Hardware به یک رمز به عنوان modifier نیاز دارد. بیومتریک یک shortcut اختیاری روی آن است.';

  @override
  String get t2MigrationPromptTitle => 'لایه Hardware به رمز نیاز دارد';

  @override
  String get t2MigrationPromptBody =>
      'نصب‌های موجود Hardware بدون رمز باید اکنون یکی تعیین کنند تا ادامه دهند.';

  @override
  String get t2MigrationContinue => 'ادامه';

  @override
  String get t2MigrationSetPasswordTitle =>
      'برای حفظ لایه Hardware یک رمز تعیین کنید';

  @override
  String get t2MigrationSetPasswordBody =>
      'یک passphrase اصلی جدید وارد کنید. کلید DB که قبلاً در ماژول hardware مهر شده، تحت این رمز re-seal می‌شود — sessionها و کلیدها دست‌نخورده می‌مانند.';

  @override
  String get t2MigrationWipeAndRestart => 'پاک‌سازی و شروع دوباره';

  @override
  String get t2MigrationResealFailed =>
      're-seal لایه Hardware ناموفق بود — رمز دیگری انتخاب کنید یا پاک‌سازی کنید.';

  @override
  String get biometricOverlayEnable =>
      'فعال‌سازی shortcut بیومتریک روی لایه Hardware';

  @override
  String get biometricOverlayEnableSubtitle =>
      'رمز شما را از یک slot سیستم با گیت بیومتریک آزاد می‌کند.';

  @override
  String get biometricOverlayUnavailable =>
      'overlay بیومتریک هنوز روی این پلتفرم در دسترس نیست.';

  @override
  String get biometricOverlayRequiresPassword =>
      'ابتدا رمز لایه Hardware را تعیین کنید.';

  @override
  String get t2UnlockTitle => 'با رمز master باز کنید';

  @override
  String get t2UnlockSubtitle =>
      'کلید hardware-bound با رمز شما محافظت می‌شود.';

  @override
  String get t2UnlockUseBiometricButton => 'از بیومتریک استفاده کنید';

  @override
  String get t2PasswordChanged => 'رمز لایه Hardware به‌روز شد.';

  @override
  String get paranoidMasterPasswordNote =>
      'یک عبارت عبور طولانی به شدت توصیه می‌شود — Argon2id فقط حملهٔ جستجوی فراگیر را کند می‌کند، جلوی آن را نمی‌گیرد.';

  @override
  String get plaintextWarningTitle => 'متن ساده: بدون رمزگذاری';

  @override
  String get plaintextWarningBody =>
      'جلسه‌ها، کلیدها و known hosts بدون رمزگذاری ذخیره خواهند شد. هر کسی که به سیستم فایل این رایانه دسترسی داشته باشد می‌تواند آنها را بخواند.';

  @override
  String get plaintextAcknowledge =>
      'می‌دانم که داده‌های من رمزگذاری نخواهند شد';

  @override
  String get plaintextAcknowledgeRequired =>
      'پیش از ادامه، درک خود را تأیید کنید.';

  @override
  String get passwordLabel => 'رمز عبور';

  @override
  String get masterPasswordLabel => 'رمز عبور اصلی';

  @override
  String get globalErrorTitle => 'خطای غیرمنتظره';

  @override
  String get globalErrorBody =>
      'یک خطای غیرمنتظره رخ داد. برنامه به کار ادامه می‌دهد.';

  @override
  String get globalErrorLogSavedNote => 'همهٔ جزئیات در فایل log نوشته شد.';

  @override
  String get globalErrorLogDisabledNote =>
      'برای ذخیرهٔ جزئیات خطا، log را در تنظیمات فعال کن.';

  @override
  String globalErrorTechnicalLine(String detail) {
    return 'خطا: $detail';
  }

  @override
  String get globalErrorEnableLoggingButton => 'فعال‌سازی log';

  @override
  String get globalErrorLoggingEnabledToast =>
      'log فعال شد — خطاها در فایل log نوشته می‌شوند';

  @override
  String get fatalErrorQuitButton => 'خروج';

  @override
  String get fatalErrorWipeButton => 'پاک‌کردن همهٔ داده‌ها';

  @override
  String get fatalErrorWipingButton => 'در حال پاک‌کردن…';

  @override
  String get fatalErrorWipeExplanation =>
      'پاک‌کردن همهٔ فایل‌های برنامه (config، دیتابیس، blobهای vault، logها) را حذف می‌کند و اجرای بعدی از نصب تمیز شروع می‌شود. قابل بازگشت نیست.';

  @override
  String get fatalErrorWipeConfirmTitle => 'همهٔ داده‌ها پاک شوند؟';

  @override
  String get fatalErrorWipeConfirmBody =>
      'این کار همهٔ فایل‌های config، دیتابیس و vault را برای همیشه حذف می‌کند. برنامه از نصب خالی دوباره اجرا می‌شود. ادامه می‌دهید؟';

  @override
  String get fatalErrorWipeConfirmAction => 'پاک‌کردن همه‌چیز';

  @override
  String get unencryptedArchiveWarning =>
      'این آرشیو با رمز محافظت نشده است. هر کسی که فایل را داشته باشد می‌تواند محتوای آن را بخواند.';

  @override
  String get clipboardCopyFailed => 'کپی به clipboard ناموفق بود.';

  @override
  String get nonAsciiHostnameWarning =>
      'نام host شامل نویسه‌های غیر ASCII است — هر نویسه را با چیزی که تایپ کردی مقایسه کن. کدپوینت‌های از نظر ظاهری مشابه (سیریلیک / یونانی) می‌توانند یک دامنهٔ لاتین را جعل کنند.';

  @override
  String get playbackPause => 'توقف موقت';

  @override
  String get recordingPlayLocked =>
      'برای پخش این ضبط رمزگذاری‌شده، قفل برنامه را باز کنید.';

  @override
  String get recordToggleStart => 'شروع ضبط';

  @override
  String get recordToggleStop => 'توقف ضبط';

  @override
  String get foregroundServiceTitle => 'SSH فعال';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count اتصال فعال',
      one: '۱ اتصال فعال',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => 'نوع session';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => 'نام کاربری';

  @override
  String get webDavAuthMethod => 'روش auth';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer token';

  @override
  String get trustedCert => 'گواهی مورد اعتماد (PEM)';

  @override
  String get trustedCertHint => '-----BEGIN CERTIFICATE-----';

  @override
  String get trustedCertHelp =>
      'گواهی سرور را الصاق کنید (یک یا چند بلوک PEM). به‌عنوان CA ریشه اضافی فقط برای این نشست افزوده می‌شود — سایر برنامه‌ها تحت تأثیر قرار نمی‌گیرند. خالی بگذارید تا از مخزن اعتماد سیستم استفاده شود.';

  @override
  String get acceptAnyCert => 'پذیرش هر گواهی';

  @override
  String get acceptAnyCertHelp =>
      'همه بررسی‌های گواهی و نام میزبان را برای دست‌دادن‌های TLS این نشست رد کند. درب اضطراری وقتی نه مخزن اعتماد سیستم و نه گواهی پین‌شده کار می‌کند.';

  @override
  String get acceptAnyCertWarn =>
      'آسیب‌پذیر در برابر حملات MITM — هر کسی در شبکه می‌تواند هویت سرور را جعل کند. فقط در شبکه‌های خصوصی مورد اعتماد استفاده کنید.';

  @override
  String get webDavCopyUrl => 'کپی WebDAV URL';

  @override
  String get webDavOpenInBrowser => 'باز کردن در مرورگر';

  @override
  String get errWebDavAuthFailed => 'auth WebDAV ناموفق';

  @override
  String get errWebDavNotFound => 'Path یافت نشد';

  @override
  String get errWebDavConflict => 'عملیات با وضعیت فعلی در تعارض است';

  @override
  String errWebDavGeneric(String detail) {
    return 'سرور WebDAV درخواست را رد کرد: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'Base URL برای WebDAV لازم است';

  @override
  String get errWebDavBaseUrlInvalid =>
      'Base URL باید با http:// یا https:// شروع شود';

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
      'برای AWS خالی بگذار، یا برای MinIO / R2 / Spaces مقدار بده';

  @override
  String get s3PathStyle => 'Path-style addressing';

  @override
  String get s3PathStyleHint => 'برای MinIO لازم است؛ برای AWS off بگذار';

  @override
  String get s3DefaultBucket => 'Bucket پیش‌فرض';

  @override
  String get s3DefaultPrefix => 'Prefix پیش‌فرض';

  @override
  String get s3GeneratePresignedUrl => 'ساختن presigned URL';

  @override
  String get s3PresignedUrlExpiry => 'منقضی می‌شود در';

  @override
  String get s3CopyUri => 'کپی URI s3://bucket/key';

  @override
  String get s3PresignedUrlExpiry15min => '۱۵ دقیقه';

  @override
  String get s3PresignedUrlExpiry1hour => '۱ ساعت';

  @override
  String get s3PresignedUrlExpiry4hour => '۴ ساعت';

  @override
  String get s3PresignedUrlExpiry24hour => '۲۴ ساعت';

  @override
  String get s3PresignedUrlExpiry7day => '۷ روز';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (access key + secret را بررسی کنید)';

  @override
  String get errS3NoSuchBucket => 'Bucket وجود ندارد یا قابل دسترسی نیست';

  @override
  String get errS3RegionMismatch => 'Bucket در region متفاوتی است';

  @override
  String errS3Generic(String detail) {
    return 'سرور S3 درخواست را رد کرد: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'فعال‌سازی WebDAV sync';

  @override
  String get syncPassphrase => 'Sync passphrase';

  @override
  String get syncPassphraseHint =>
      'بایگانی sync را رمزگذاری می‌کند. باید با master password متفاوت باشد.';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Sync passphrase نباید با master password یکسان باشد.';

  @override
  String get syncRemotePath => 'مسیر remote';

  @override
  String get syncRemotePathHint =>
      'مسیر زیر WebDAV base URL — پیش‌فرض letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return 'آخرین push: $when';
  }

  @override
  String syncLastPulled(String when) {
    return 'آخرین pull: $when';
  }

  @override
  String get syncNeverRun => 'هرگز';

  @override
  String get syncUpToDate => 'Sync به‌روز است';

  @override
  String syncPushedBytes(String bytes) {
    return 'Push $bytes';
  }

  @override
  String syncPullApplied(int count) {
    return 'اعمال $count تغییر از remote';
  }

  @override
  String get errSyncDisabled => 'Sync غیرفعال است';

  @override
  String get errSyncEtagMismatch => 'Remote تغییر کرده — اول pull سپس push';

  @override
  String get errSyncUnauthorized => 'احراز هویت WebDAV ناموفق بود';

  @override
  String errSyncNetwork(String detail) {
    return 'خطای شبکه: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion =>
      'بایگانی sync از remote نیاز به build جدیدتر دارد';

  @override
  String get hardwareKey => 'Hardware key';

  @override
  String get hardwareKeyTapPrompt => 'hardware key را لمس کن';

  @override
  String get hardwareKeyPin => 'PIN ـ hardware key';

  @override
  String get hardwareKeyTimeout => 'hardware key پاسخ نداد';

  @override
  String get hardwareKeyNotFound => 'hardware key یافت نشد';

  @override
  String get hardwareKeyUnsupported =>
      'دسترسی مستقیم به hardware key در این پلتفرم در دسترس نیست';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'نیاز به Apple Developer Program entitlement؛ روی macOS از ssh-agent استفاده کن';

  @override
  String get skKeyRequiresDevice =>
      'این کلید SSH به hardware key نیاز دارد — برای auth لمس کن';

  @override
  String get errSkWrongPin => 'PIN اشتباه است';

  @override
  String get hardwareKeyImport => 'import کردن hardware key (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => 'درخواست hardware key لغو شد';

  @override
  String get agentEndpointSectionTitle => 'ادغام با کلاینت‌های SSH خارجی';

  @override
  String get agentEndpointToggleTitle =>
      'ارائه hardware-bound keys به کلاینت‌های SSH سیستم';

  @override
  String get agentEndpointToggleSubtitle =>
      'به git و ssh و افزونه‌های IDE روی این دستگاه اجازه می‌دهد از key های FIDO2 / smart-card / TPM شما استفاده کنند.';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'کپی دستور export';

  @override
  String get agentEndpointCopyPipeName => 'کپی نام pipe';

  @override
  String get agentEndpointSignatureRequestTitle => 'درخواست امضا';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester می‌خواهد با $keyLabel امضا کند';
  }

  @override
  String get agentEndpointRequesterUnknown => 'یک کلاینت SSH خارجی';

  @override
  String get agentEndpointAuthorizeOnce => 'یک‌بار اجازه بده';

  @override
  String get agentEndpointAuthorizeAlways => 'اجازه بده و به خاطر بسپار';

  @override
  String get agentEndpointDeny => 'رد کن';

  @override
  String get agentEndpointStatusRunning => 'در حال اجرا';

  @override
  String get agentEndpointStatusStopped => 'متوقف';

  @override
  String get agentEndpointStatusUnsupported => 'در این پلتفرم پشتیبانی نمی‌شود';

  @override
  String get agentEndpointRefusedAddIdentity =>
      'رد شد: کلاینت‌های خارجی نمی‌توانند key اضافه کنند.';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'راه‌اندازی ssh-agent endpoint ممکن نشد: $detail';
  }

  @override
  String get pkcs11AddTitle => 'افزودن کلید smart-card / token';

  @override
  String get pkcs11ModuleLabel => 'ماژول PKCS#11';

  @override
  String get pkcs11ModuleAutoDetected => 'به‌طور خودکار پیدا شد';

  @override
  String get pkcs11ModuleCustom => 'ماژول دلخواه...';

  @override
  String get pkcs11ModulePickerTitle => 'انتخاب کتابخانه PKCS#11';

  @override
  String get pkcs11NoModuleFound =>
      'ماژول PKCS#11 پیدا نشد. OpenSC را نصب کنید یا کتابخانه vendor را انتخاب کنید.';

  @override
  String get pkcs11InitializeFailed => 'ماژول PKCS#11 initialise نشد.';

  @override
  String get pkcs11NoTokenPresent => 'هیچ token در reader وجود ندارد.';

  @override
  String pkcs11TokenLabel(String label) {
    return 'Token: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return 'Serial: $serial';
  }

  @override
  String get pkcs11LoginRequired => 'Token نیاز به ورود دارد.';

  @override
  String pkcs11PinPrompt(String token) {
    return 'PIN برای $token';
  }

  @override
  String get pkcs11PinPad => 'روی PIN-pad token تأیید کنید.';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'PIN اشتباه. $remaining تلاش باقی‌مانده.';
  }

  @override
  String get pkcs11PinLocked => 'PIN قفل شده. با PUK باز کنید.';

  @override
  String get pkcs11NoSignableKeys =>
      'Token کلید SSH-قابل‌استفاده ندارد (RSA, ECDSA, Ed25519).';

  @override
  String get pkcs11GostUnsupported => 'کلیدهای GOST با SSH کار نمی‌کنند.';

  @override
  String pkcs11TokenUnplugged(String label) {
    return 'Token \"$label\" متصل نیست.';
  }

  @override
  String get pkcs11UriRebindFailed =>
      'Token ذخیره‌شده پیدا نشد. دوباره وصل کنید.';

  @override
  String pkcs11SignFailed(String reason) {
    return 'Sign ناموفق: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      'Smart-card / token PKCS#11 در این پلتفرم در دسترس نیست.';

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
  String get pkcs11WizardStepModule => 'Module PKCS#11 را انتخاب کنید';

  @override
  String get pkcs11WizardStepToken => 'Token را انتخاب کنید';

  @override
  String get pkcs11WizardStepKey => 'کلید را انتخاب کنید';

  @override
  String get pkcs11WizardStepPin => 'PIN را وارد کنید';

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
  String get pkcs11SaveInProgress => 'خواندن کلید عمومی از token...';

  @override
  String get pkcs11SaveSuccess => 'کلید smart card اضافه شد.';

  @override
  String get pkcs11ScanInProgress => 'جستجوی module های PKCS#11...';

  @override
  String get pkcs11LoadingTokens => 'بارگذاری token ها...';

  @override
  String get pkcs11LoadingKeys => 'بارگذاری کلیدها...';

  @override
  String get pkcs11ModuleStatusReady => 'Module بارگذاری شد.';

  @override
  String get pkcs11ModuleStatusNoToken => 'Token موجود نیست.';

  @override
  String get pkcs11ModuleStatusFailed => 'بارگذاری module ناموفق بود.';

  @override
  String get pkcs11PinPadHint => '(PIN pad روی دستگاه)';

  @override
  String get pkcs11WizardBack => 'بازگشت';

  @override
  String get pkcs11WizardNext => 'بعدی';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => 'افزودن hardware key';

  @override
  String get sshKeyHardwareBoundExplainer =>
      'Private key داخل secure hardware دستگاه قرار دارد و export نمی‌شود.';

  @override
  String get sshKeyEnclaveDeviceBound => 'این key فقط روی همین Mac کار می‌کند.';

  @override
  String get sshKeyEnclaveDeviceBoundIos =>
      'این key فقط روی همین iPhone کار می‌کند.';

  @override
  String get sshKeyHelloDeviceBound => 'این key فقط روی همین PC کار می‌کند.';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'الزام Touch ID / Face ID';

  @override
  String get sshKeyEnclavePasscodeFallback =>
      'اجازه استفاده از passcode دستگاه به‌عنوان fallback';

  @override
  String get sshKeyHelloPinRequired =>
      'الزام Windows Hello (PIN، اثر انگشت یا چهره)';

  @override
  String get sshKeyHardwareUnavailableTitle => 'Hardware keys در دسترس نیست';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'برای استفاده از Secure Enclave اپ باید code-signed باشد.';

  @override
  String get sshKeyHardwareUnavailableHello =>
      'Windows Hello روی این PC تنظیم نشده.';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'TPM شناسایی نشد — فقط software-backed.';

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
  String get sshKeyGenerateCta => 'ساختن';

  @override
  String get sshKeyGenerateInProgress =>
      'در حال ساخت key در secure hardware...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Code-signing لازم است — به USER_GUIDE.md → Hardware-bound keys مراجعه کنید.';

  @override
  String get sshKeySignInProgress => 'امضا با secure hardware...';

  @override
  String get sshKeyPublicCopy => 'کپی public key';

  @override
  String get sshKeyAuthorizedKeysHint =>
      'این خط را به ~/.ssh/authorized_keys روی سرور اضافه کنید.';

  @override
  String get sshKeyEnclaveWizardTitle => 'Secure Enclave SSH key';

  @override
  String get sshKeyEnclaveWizardLabelHint => 'نام key';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'کلید SSH از Windows Hello';

  @override
  String get helloWizardLabelHint => 'برچسب کلید';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'احراز هویت با Windows Hello';

  @override
  String get helloPromptDescription =>
      'PIN، اثر انگشت یا چهره — Windows Hello این چالش SSH را امضا می‌کند.';

  @override
  String get helloSoftwareGatedWarning =>
      'این دستگاه TPM ندارد. کلید در فضای کاربر می‌ماند؛ هر امضا را همچنان Windows Hello کنترل می‌کند.';

  @override
  String get helloP384NotSupported =>
      'فریمور TPM از P-384 پشتیبانی نمی‌کند. P-256 یا RSA-2048 را انتخاب کنید.';

  @override
  String get helloConfigureFirst =>
      'ابتدا Windows Hello را در Settings -> Sign-in options تنظیم کن.';

  @override
  String get tpmSshTitle => 'ساخت کلید SSH متصل به TPM';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (پیشنهادی)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported =>
      'این الگوریتم در فریمور TPM پشتیبانی نمی‌شود.';

  @override
  String get tpmSshPinProtect => 'محافظت با PIN';

  @override
  String get tpmSshPinLockoutWarning =>
      'TPM پس از چند PIN اشتباه کلید را قفل می‌کند.';

  @override
  String get tpmSshPinMismatch => 'PINها یکسان نیستند.';

  @override
  String get tpmSshStorageBlob => 'ذخیره کلید بسته‌بندی‌شده در داده‌های برنامه';

  @override
  String get tpmSshStorageHandle => 'نگهداری در اسلات حافظهٔ TPM';

  @override
  String get tpmSshStorageHandleHelp =>
      'امضای سریع‌تر. یکی از اسلات‌های دائمی TPM را اشغال می‌کند.';

  @override
  String get tpmSshLabel => 'برچسب کلید';

  @override
  String get tpmSshImportTitle => 'وارد کردن کلید SSH محافظت‌شده با TPM';

  @override
  String get tpmSshImportFormat => 'فایل TPM 2.0 (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return 'PIN مربوط به TPM برای $label';
  }

  @override
  String get tpmSshPinIncorrect => 'PIN نادرست است.';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM در دورهٔ خنک‌کاری قفل است. $duration صبر کنید و دوباره امتحان کنید.';
  }

  @override
  String get tpmSshGenerating => 'در حال ساخت کلید در TPM...';

  @override
  String get tpmSshSigning => 'در حال امضا با TPM...';

  @override
  String get tpmSshUnavailable => 'TPM روی این دستگاه یافت نشد.';

  @override
  String get tpmSshUnavailableFwDisabled => 'TPM در فریمور غیرفعال است.';

  @override
  String get tpmSshUnavailableNoPermission =>
      'برنامه به TPM دسترسی ندارد. کاربر را به گروه `tss` اضافه کنید.';

  @override
  String tpmSshHandleInUse(String handle) {
    return 'اسلات دائمی $handle قبلاً در حال استفاده است.';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      'این کلید بدون درخواست Hello / PIN امضا می‌کند — هر کسی که در زمان ورود شما به دسکتاپ دسترسی دارد می‌تواند از آن استفاده کند.';

  @override
  String get keystoreWizardTitle => 'Android Hardware Key';

  @override
  String get keystoreBadge => 'Android Keystore';

  @override
  String get keystoreKeyAndroidLabel => 'Android Keystore (سخت‌افزاری)';

  @override
  String get keystoreKeyStrongBoxLabel => 'StrongBox HSM';

  @override
  String get keystoreKeyTeeLabel => 'TEE (پشتیبانی سخت‌افزاری)';

  @override
  String get keystoreKeyGenerating => 'در حال ساخت کلید سخت‌افزاری...';

  @override
  String get keystoreKeyAuthPrompt =>
      'برای استفاده از کلید SSH احراز هویت کنید';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      'کلید نابود شد: بیومتریک جدیدی ثبت شده است. کلید عمومی را روی سرورها دوباره ثبت کنید.';

  @override
  String get keystoreKeyStrongBoxUnavailable =>
      'StrongBox HSM روی این دستگاه در دسترس نیست';

  @override
  String get keystoreKeyUserAuthRequired =>
      'برای هر امضا بیومتریک / باز کردن قفل دستگاه را الزامی کن';

  @override
  String get keystoreKeyExportDisabled =>
      'کلیدهای سخت‌افزاری قابل خروجی گرفتن نیستند';

  @override
  String get keystoreKeyDeleteWarning =>
      'حذف این کلید آن را از مخزن سخت‌افزاری پاک می‌کند. سرورها این کلید را رد می‌کنند تا یک کلید جدید ثبت کنید.';

  @override
  String get keystoreKeyBiometricNotEnrolled =>
      'ابتدا بیومتریک یا PIN دستگاه را تنظیم کنید';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (سازگار با StrongBox)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+، فقط TEE)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (بیشترین سازگاری)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM در دسترس نیست';

  @override
  String get keystoreStrongBoxFallbackBody =>
      'دستگاه شما StrongBox HSM را در دسترس نمی‌گذارد. به‌جای آن یک کلید مبتنی بر TEE ساخته شود؟ همچنان hardware-backed است، فقط بدون ایزولاسیون StrongBox.';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'استفاده از TEE';

  @override
  String get keystoreStrongBoxFallbackCancel => 'لغو';

  @override
  String get fido2BrokerSectionTitle => 'کلیدهای امنیتی سخت‌افزاری';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / security key';

  @override
  String get fido2BrokerMacosLabel => 'دیالوگ سیستمی security key';

  @override
  String get fido2BrokerIosLabel => 'security key سیستم (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel => 'security key سیستم (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => 'USB HID مستقیم (CTAP2)';

  @override
  String get fido2BrokerTransportNone => 'در این پلتفرم در دسترس نیست';

  @override
  String get fido2BrokerPreferDirectHidTitle =>
      'USB HID مستقیم به دیالوگ سیستم ترجیح داده شود';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return 'پیشرفته: عبور از $brokerLabel روی پلتفرم‌هایی که هر دو مسیر کار می‌کنند. HID مستقیم ویژگی‌های بیشتری از authenticator را در دسترس می‌گذارد ولی برای هر اپ نیاز به مجوز دارد.';
  }

  @override
  String get sshIntegrationSection => 'ادغام SSH';

  @override
  String get fido2BrokerNoTransportSubtitle =>
      'پشتیبانی از کلید سخت‌افزاری روی این دستگاه در دسترس نیست.';

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return 'فقط $transport روی این دستگاه در دسترس است؛ کلید غیرفعال است.';
  }

  @override
  String get hardwareKeyStubBadge => 'استاب وارد شده';

  @override
  String get hardwareKeyStubSubtitle =>
      'روی دستگاه دیگری بود — اینجا مجدداً تولید کنید تا قابل استفاده شود';

  @override
  String get hardwareKeyStubRegenerateAction => 'اینجا مجدداً تولید کن';

  @override
  String get hardwareKeyStubRemoveAction => 'حذف استاب';

  @override
  String get hardwareKeyStubPickerTooltip =>
      'این کلید را روی این دستگاه قبل از استفاده مجدداً تولید کنید';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return 'ماژول PKCS#11 برای توکن «$token» را پیدا کنید';
  }

  @override
  String get arrowLeft => 'فلش چپ';

  @override
  String get arrowUp => 'فلش بالا';

  @override
  String get arrowDown => 'فلش پایین';

  @override
  String get arrowRight => 'فلش راست';

  @override
  String get copyMode => 'حالت کپی';

  @override
  String get exitCopyMode => 'خروج از حالت کپی';

  @override
  String importedGeneric(String items) {
    return 'وارد شد: $items';
  }
}
