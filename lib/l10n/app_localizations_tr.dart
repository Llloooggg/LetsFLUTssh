// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class STr extends S {
  STr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'Tamam';

  @override
  String get infoDialogProtectsHeader => 'Şunlara karşı korur';

  @override
  String get infoDialogDoesNotProtectHeader => 'Şunlara karşı korumaz';

  @override
  String get cancel => 'İptal';

  @override
  String get close => 'Kapat';

  @override
  String get delete => 'Sil';

  @override
  String get save => 'Kaydet';

  @override
  String get connect => 'Bağlan';

  @override
  String get credentialPromptPassphraseTitle => 'Anahtar passphrase\'i gerekli';

  @override
  String get credentialPromptPasswordTitle => 'Parola gerekli';

  @override
  String get credentialPromptHint =>
      'Bağlantıyı tamamlamak için girin. Diske asla yazılmaz.';

  @override
  String credentialPromptHintForSession(String session) {
    return '“$session” bağlantısını tamamlamak için girin. Diske asla yazılmaz.';
  }

  @override
  String get credentialPromptRememberSession => 'Bu oturum için hatırla';

  @override
  String get passwordBlankPromptHint =>
      'Bağlanırken sorulması için boş bırakın';

  @override
  String get retry => 'Yeniden Dene';

  @override
  String get import_ => 'İçe Aktar';

  @override
  String get export_ => 'Dışa Aktar';

  @override
  String get rename => 'Yeniden Adlandır';

  @override
  String get create => 'Oluştur';

  @override
  String get back => 'Geri';

  @override
  String get copy => 'Kopyala';

  @override
  String get cut => 'Kes';

  @override
  String get paste => 'Yapıştır';

  @override
  String get select => 'Seç';

  @override
  String get copyModeTapToStart => 'Seçim başlangıcını işaretlemek için dokun';

  @override
  String get copyModeExtending => 'Seçimi genişletmek için sürükle';

  @override
  String get copyModeSetAnchor => 'Bağlantı noktası ayarla';

  @override
  String get copyModeCopySelection => 'Seçimi kopyala';

  @override
  String get required => 'Gerekli';

  @override
  String get errFillRequiredFields => '* ile işaretli zorunlu alanları doldur';

  @override
  String get settings => 'Ayarlar';

  @override
  String get appSettings => 'Uygulama Ayarları';

  @override
  String get yes => 'Evet';

  @override
  String get no => 'Hayır';

  @override
  String get importWhatToImport => 'Ne içe aktarılacak:';

  @override
  String get exportWhatToExport => 'Ne dışa aktarılacak:';

  @override
  String get enterMasterPasswordPrompt => 'Ana şifreyi girin:';

  @override
  String get nextStep => 'İleri';

  @override
  String get includePasswords => 'Oturum parolaları';

  @override
  String get embeddedKeys => 'Oturum anahtarları';

  @override
  String get managerKeys => 'Yöneticideki anahtarlar';

  @override
  String get managerKeysMayBeLarge =>
      'Yönetici anahtarları QR boyutunu aşabilir';

  @override
  String get qrPasswordWarning =>
      'SSH anahtarları dışa aktarmada varsayılan olarak devre dışıdır.';

  @override
  String get sshKeysMayBeLarge => 'Anahtarlar QR boyutunu aşabilir';

  @override
  String exportTotalSize(String size) {
    return 'Toplam boyut: $size';
  }

  @override
  String get terminal => 'Terminal';

  @override
  String get files => 'Dosyalar';

  @override
  String get transfer => 'Transfer';

  @override
  String get open => 'Aç';

  @override
  String get search => 'Ara...';

  @override
  String get noResults => 'Sonuç yok';

  @override
  String get filter => 'Filtrele...';

  @override
  String get merge => 'Birleştir';

  @override
  String get replace => 'Değiştir';

  @override
  String get reconnect => 'Yeniden Bağlan';

  @override
  String get updateAvailable => 'Güncelleme Mevcut';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'Sürüm $version mevcut (güncel: v$current).';
  }

  @override
  String get releaseNotes => 'Sürüm notları:';

  @override
  String get skipThisVersion => 'Bu Sürümü Atla';

  @override
  String get unskip => 'Atlamayı Geri Al';

  @override
  String get downloadAndInstall => 'İndir ve Kur';

  @override
  String get openInBrowser => 'Tarayıcıda Aç';

  @override
  String get couldNotOpenBrowser =>
      'Tarayıcı açılamadı — URL panoya kopyalandı';

  @override
  String get checkForUpdates => 'Güncellemeleri Kontrol Et';

  @override
  String get checkNow => 'Şimdi kontrol et';

  @override
  String get checkForUpdatesOnStartup =>
      'Başlangıçta Güncellemeleri Kontrol Et';

  @override
  String get checking => 'Kontrol ediliyor...';

  @override
  String get youreUpToDate => 'Güncelsiniz';

  @override
  String get updateCheckFailed => 'Güncelleme kontrolü başarısız';

  @override
  String get unknownError => 'Bilinmeyen hata';

  @override
  String downloadingPercent(int percent) {
    return 'İndiriliyor... $percent%';
  }

  @override
  String get updateVerifying => 'Doğrulanıyor…';

  @override
  String get downloadComplete => 'İndirme tamamlandı';

  @override
  String get installNow => 'Şimdi Kur';

  @override
  String get openReleasePage => 'Yayın Sayfasını Aç';

  @override
  String get couldNotOpenInstaller => 'Yükleyici açılamadı';

  @override
  String get installerFailedOpenedReleasePage =>
      'Yükleyici başlatılamadı; tarayıcıda yayın sayfası açıldı';

  @override
  String versionAvailable(String version) {
    return 'Sürüm $version mevcut';
  }

  @override
  String currentVersion(String version) {
    return 'Güncel: v$version';
  }

  @override
  String importedSessions(int count) {
    return '$count oturum içe aktarıldı';
  }

  @override
  String importFailed(String error) {
    return 'İçe aktarma başarısız: $error';
  }

  @override
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ilişki düşürüldü (hedef eksik)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bozuk oturum atlandı',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'Oturumlar';

  @override
  String get emptyFolders => 'Boş klasörler';

  @override
  String get sessionsHeader => 'OTURUMLAR';

  @override
  String get savedSessions => 'Kayıtlı oturumlar';

  @override
  String get activeConnections => 'Aktif bağlantılar';

  @override
  String get openTabs => 'Açık sekmeler';

  @override
  String get noSavedSessions => 'Kayıtlı oturum yok';

  @override
  String get addSession => 'Oturum Ekle';

  @override
  String get noSessions => 'Oturum yok';

  @override
  String nSelectedCount(int count) {
    return '$count seçili';
  }

  @override
  String get selectAll => 'Tümünü Seç';

  @override
  String get deselectAll => 'Tümünü Kaldır';

  @override
  String get moveTo => 'Taşı...';

  @override
  String get moveToFolder => 'Klasöre Taşı';

  @override
  String get rootFolder => '/ (kök)';

  @override
  String get newFolder => 'Yeni Klasör';

  @override
  String get newConnection => 'Yeni Bağlantı';

  @override
  String get editConnection => 'Bağlantıyı Düzenle';

  @override
  String get duplicate => 'Çoğalt';

  @override
  String get deleteSession => 'Oturumu Sil';

  @override
  String get renameFolder => 'Klasörü Yeniden Adlandır';

  @override
  String get deleteFolder => 'Klasörü Sil';

  @override
  String get deleteSelected => 'Seçilenleri Sil';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return '$parts silinsin mi?\n\nBu işlem geri alınamaz.';
  }

  @override
  String nSessions(int count) {
    return '$count oturum';
  }

  @override
  String nFolders(int count) {
    return '$count klasör';
  }

  @override
  String deleteFolderConfirm(String name) {
    return '\"$name\" klasörü silinsin mi?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'İçindeki $count oturum da silinecek.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return '\"$name\" silinsin mi?';
  }

  @override
  String get connection => 'Bağlantı';

  @override
  String get auth => 'Kimlik Doğrulama';

  @override
  String get sectionAuthentication => 'Kimlik doğrulama';

  @override
  String get sectionAdvanced => 'Gelişmiş';

  @override
  String get moreOptions => 'Diğer seçenekler';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString port yönlendirme kuralı',
      zero: 'Port yönlendirme kuralı yok',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => 'Yönet…';

  @override
  String get authMethodAgent => 'Sistem ssh-agent kullan';

  @override
  String get options => 'Seçenekler';

  @override
  String get sessionName => 'Oturum Adı';

  @override
  String get sessionNameAutoFromHost => 'Host\'tan otomatik';

  @override
  String get sessionNameAutoFromUrl => 'URL host\'undan otomatik';

  @override
  String get sessionNameAutoFromBucket => 'Varsayılan bucket\'tan otomatik';

  @override
  String get hintMyServer => 'Sunucum';

  @override
  String get hostRequired => 'Host *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'Port';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'Kullanıcı Adı *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'Şifre';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'Anahtar Parolası';

  @override
  String get hintOptional => 'İsteğe bağlı';

  @override
  String get savedTypeToChange => 'Kaydedildi — değiştirmek için yazın';

  @override
  String get hidePemText => 'PEM metnini gizle';

  @override
  String get pastePemKeyText => 'PEM anahtar metni yapıştır';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get saveAndConnect => 'Kaydet ve Bağlan';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst =>
      'Önce bir anahtar dosyası veya PEM metni sağlayın';

  @override
  String get keyTextPem => 'Anahtar Metni (PEM)';

  @override
  String get selectKeyFile => 'Anahtar Dosyası Seç';

  @override
  String get clearKeyFile => 'Anahtar dosyasını temizle';

  @override
  String get authOrDivider => 'VEYA';

  @override
  String get providePasswordOrKey => 'Bir parola veya SSH anahtarı sağlayın';

  @override
  String get quickConnect => 'Hızlı Bağlantı';

  @override
  String get scanQrCode => 'QR Kodu Tara';

  @override
  String get emptyFolder => 'Boş klasör';

  @override
  String get qrGenerationFailed => 'QR oluşturma başarısız';

  @override
  String get scanWithCameraApp =>
      'LetsFLUTssh yüklü bir cihazda\nherhangi bir kamera uygulamasıyla tarayın.';

  @override
  String get noPasswordsInQr => 'Bu QR kodunda şifre veya anahtar yok';

  @override
  String get qrContainsCredentialsWarning =>
      'Bu QR kodu kimlik bilgilerini içerir. Ekranı gizli tutun.';

  @override
  String get copyLink => 'Bağlantıyı Kopyala';

  @override
  String get linkCopied => 'Bağlantı panoya kopyalandı';

  @override
  String get hostKeyChanged => 'Host anahtarı değişti!';

  @override
  String get unknownHost => 'Bilinmeyen host';

  @override
  String get hostKeyChangedWarning =>
      'UYARI: Bu sunucunun host anahtarı değişti. Bu bir MITM saldırısına ya da sunucunun yeniden kurulduğuna işaret edebilir.';

  @override
  String get unknownHostMessage =>
      'Bu host\'un kimliği doğrulanamıyor. Bağlanmaya devam etmek istediğinizden emin misiniz?';

  @override
  String get host => 'Host';

  @override
  String get keyType => 'Anahtar türü';

  @override
  String get fingerprint => 'Parmak izi';

  @override
  String get fingerprintCopied => 'Parmak izi kopyalandı';

  @override
  String get copyFingerprint => 'Parmak izini kopyala';

  @override
  String get acceptAnyway => 'Yine de Kabul Et';

  @override
  String get accept => 'Kabul Et';

  @override
  String get importData => 'Veri İçe Aktar';

  @override
  String get masterPassword => 'Ana Şifre';

  @override
  String get confirmPassword => 'Şifreyi Onayla';

  @override
  String get importModeMergeDescription =>
      'Yeni oturumları ekle, mevcut olanları koru';

  @override
  String get importModeReplaceDescription =>
      'Tüm oturumları içe aktarılanlarla değiştir';

  @override
  String get folderName => 'Klasör adı';

  @override
  String get newName => 'Yeni ad';

  @override
  String deleteItems(String names) {
    return '$names silinsin mi?';
  }

  @override
  String deleteNItems(int count) {
    return '$count öğeyi sil';
  }

  @override
  String deletedItem(String name) {
    return '$name silindi';
  }

  @override
  String deletedNItems(int count) {
    return '$count öğe silindi';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'Klasör oluşturulamadı: $error';
  }

  @override
  String failedToRename(String error) {
    return 'Yeniden adlandırma başarısız: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return '$name silinemedi: $error';
  }

  @override
  String get editPath => 'Yolu Düzenle';

  @override
  String get root => 'Kök';

  @override
  String get controllersNotInitialized => 'Controller\'lar başlatılmadı';

  @override
  String get clearHistory => 'Geçmişi temizle';

  @override
  String get noTransfersYet => 'Henüz transfer yok';

  @override
  String get duplicateTab => 'Sekmeyi Çoğalt';

  @override
  String get duplicateTabShortcut => 'Sekmeyi Çoğalt (Ctrl+\\)';

  @override
  String get previous => 'Önceki';

  @override
  String get next => 'Sonraki';

  @override
  String get closeEsc => 'Kapat (Esc)';

  @override
  String get closeAll => 'Tümünü Kapat';

  @override
  String get closeOthers => 'Diğerlerini Kapat';

  @override
  String get closeTabsToTheLeft => 'Soldaki Sekmeleri Kapat';

  @override
  String get closeTabsToTheRight => 'Sağdaki Sekmeleri Kapat';

  @override
  String get noActiveSession => 'Aktif oturum yok';

  @override
  String get createConnectionHint =>
      'Yeni bir bağlantı oluşturun veya kenar çubuğundan birini seçin';

  @override
  String get hideSidebar => 'Kenar Çubuğunu Gizle (Ctrl+B)';

  @override
  String get showSidebar => 'Kenar Çubuğunu Göster (Ctrl+B)';

  @override
  String get language => 'Dil';

  @override
  String get languageSystemDefault => 'Otomatik';

  @override
  String get theme => 'Tema';

  @override
  String get themeDark => 'Koyu';

  @override
  String get themeLight => 'Açık';

  @override
  String get themeSystem => 'Sistem';

  @override
  String get appearance => 'Görünüm';

  @override
  String get connectionSection => 'Bağlantı';

  @override
  String get transfers => 'Transferler';

  @override
  String get data => 'Veri';

  @override
  String get logging => 'Günlükler';

  @override
  String get updates => 'Güncellemeler';

  @override
  String get about => 'Hakkında';

  @override
  String get resetToDefaults => 'Varsayılanlara Sıfırla';

  @override
  String get uiScale => 'Arayüz Ölçeği';

  @override
  String get terminalFontSize => 'Terminal Yazı Boyutu';

  @override
  String get scrollbackLines => 'Scrollback satır sayısı';

  @override
  String get keepAliveInterval => 'Keep-alive aralığı (sn)';

  @override
  String get sshTimeout => 'SSH Zaman Aşımı (sn)';

  @override
  String get defaultPort => 'Varsayılan Port';

  @override
  String get parallelWorkers => 'Paralel Worker Sayısı';

  @override
  String get maxHistory => 'Maks Geçmiş';

  @override
  String get calculateFolderSizes => 'Klasör Boyutlarını Hesapla';

  @override
  String get verboseConnectionLog => 'Ayrıntılı bağlantı günlüğü';

  @override
  String get verboseConnectionLogSubtitle =>
      'SSH handshake ve kimlik doğrulama izinin tamamını log dosyasına kaydet (bağlantı hatalarını teşhis etmek için)';

  @override
  String get exportData => 'Veriyi Dışa Aktar';

  @override
  String get exportRecordings => 'Oturum Kayıtları';

  @override
  String sshConfigPreviewHostsFound(int count) {
    return '$count host bulundu';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'Bu dosyada içe aktarılabilir host bulunamadı.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'Şu hostlar için anahtar dosyaları okunamadı: $hosts. Bu hostlar kimlik bilgileri olmadan içe aktarılacak.';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'Arşivi dışa aktar';

  @override
  String get exportArchiveSubtitle =>
      'Oturumları, yapılandırmayı ve anahtarları şifreli .lfs dosyasına kaydet';

  @override
  String get exportQrCode => 'QR kodu dışa aktar';

  @override
  String get exportQrCodeSubtitle =>
      'Seçilen oturumları ve anahtarları QR kodu ile paylaş';

  @override
  String get importArchive => 'Arşivi içe aktar';

  @override
  String get importArchiveSubtitle => '.lfs dosyasından veri yükle';

  @override
  String get importFromSshDir => '~/.ssh dizininden içe aktar';

  @override
  String get importFromSshDirSubtitle =>
      'Yapılandırma dosyasından sunucuları ve/veya ~/.ssh dizinindeki özel anahtarları seçin';

  @override
  String get sshDirImportHostsSection => 'Yapılandırma dosyasındaki sunucular';

  @override
  String get sshDirImportKeysSection => '~/.ssh\'daki anahtarlar';

  @override
  String importSshKeysFound(int count) {
    return '$count anahtar bulundu — hangilerini içe aktaracağınızı seçin';
  }

  @override
  String get importSshKeysNoneFound =>
      '~/.ssh dizininde özel anahtar bulunamadı.';

  @override
  String get sshKeyAlreadyImported => 'zaten depoda';

  @override
  String get setMasterPasswordHint =>
      'Arşivi şifrelemek için bir ana şifre belirleyin.';

  @override
  String get passwordsDoNotMatch => 'Şifreler eşleşmiyor';

  @override
  String get securityFieldsRequired => 'Lütfen tüm gerekli alanları doldurun';

  @override
  String get passwordConfirmationRequired => 'Потвърдете паролата си';

  @override
  String get passwordStrengthWeak => 'Zayıf';

  @override
  String get passwordStrengthModerate => 'Orta';

  @override
  String get passwordStrengthStrong => 'Güçlü';

  @override
  String get passwordStrengthVeryStrong => 'Çok güçlü';

  @override
  String get tierPlaintextLabel => 'Düz metin';

  @override
  String get tierPlaintextSubtitle => 'Şifreleme yok — yalnızca dosya izinleri';

  @override
  String get tierKeychainLabel => 'Keychain';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'Anahtar $keychain içinde — başlatıldığında otomatik kilit açma';
  }

  @override
  String get tierKeychainUnavailable =>
      'Bu kurulumda işletim sistemi anahtarlığı kullanılamıyor.';

  @override
  String get tierHardwareLabel => 'Donanım';

  @override
  String get tierParanoidLabel => 'Ana parola (Paranoid)';

  @override
  String get tierHardwareUnavailable =>
      'Bu kurulumda donanım kasası kullanılamıyor.';

  @override
  String get pinLabel => 'Parola';

  @override
  String get l2UnlockTitle => 'Şifre gerekli';

  @override
  String get l2UnlockHint => 'Devam etmek için kısa şifrenizi girin';

  @override
  String get l2WrongPassword => 'Yanlış şifre';

  @override
  String get l3UnlockTitle => 'Parolayı girin';

  @override
  String get l3UnlockHint => 'Parola donanıma bağlı kasanın kilidini açar';

  @override
  String get l3WrongPin => 'Yanlış parola';

  @override
  String tierCooldownHint(int seconds) {
    return '$seconds sn sonra tekrar deneyin';
  }

  @override
  String exportedTo(String path) {
    return 'Dışa aktarıldı: $path';
  }

  @override
  String exportFailed(String error) {
    return 'Dışa aktarma başarısız: $error';
  }

  @override
  String get pathToLfsFile => '.lfs dosya yolu';

  @override
  String get dataLocation => 'Veri Konumu';

  @override
  String get dataStorageSection => 'Depolama';

  @override
  String get pathCopied => 'Yol panoya kopyalandı';

  @override
  String get urlCopied => 'URL panoya kopyalandı';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — SSH/SFTP istemcisi';
  }

  @override
  String get sourceCode => 'Kaynak Kod';

  @override
  String get logIsEmpty => 'Günlük boş';

  @override
  String logExportedTo(String path) {
    return 'Günlük dışa aktarıldı: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Günlük dışa aktarma başarısız: $error';
  }

  @override
  String get logsCleared => 'Günlükler temizlendi';

  @override
  String get copiedToClipboard => 'Panoya kopyalandı';

  @override
  String get copyLog => 'Günlüğü kopyala';

  @override
  String get exportLog => 'Günlüğü dışa aktar';

  @override
  String get clearLogs => 'Günlükleri temizle';

  @override
  String get local => 'Yerel';

  @override
  String get remote => 'Uzak';

  @override
  String get pickFolder => 'Klasör Seç';

  @override
  String get refresh => 'Yenile';

  @override
  String get up => 'Yukarı';

  @override
  String get emptyDirectory => 'Boş dizin';

  @override
  String get cancelSelection => 'Seçimi iptal et';

  @override
  String get openSftpBrowser => 'SFTP Tarayıcısını Aç';

  @override
  String get openSshTerminal => 'SSH Terminali Aç';

  @override
  String get noActiveFileBrowsers => 'Aktif dosya tarayıcısı yok';

  @override
  String get useSftpFromSessions => 'Oturumlardan \"SFTP\" kullanın';

  @override
  String get saveLogAs => 'Günlüğü farklı kaydet';

  @override
  String get chooseSaveLocation => 'Kayıt konumunu seçin';

  @override
  String get forward => 'İleri';

  @override
  String get name => 'Ad';

  @override
  String get size => 'Boyut';

  @override
  String get modified => 'Değiştirilme';

  @override
  String get mode => 'Mod';

  @override
  String get owner => 'Sahip';

  @override
  String get connectionError => 'Bağlantı hatası';

  @override
  String get resizeWindowToViewFiles =>
      'Dosyaları görüntülemek için pencereyi yeniden boyutlandırın';

  @override
  String get completed => 'Tamamlandı';

  @override
  String get connected => 'Bağlandı';

  @override
  String get disconnected => 'Bağlantı kesildi';

  @override
  String a11yConnectingTo(String host) {
    return '$host bağlanılıyor';
  }

  @override
  String a11yConnectedTo(String host) {
    return '$host bağlanıldı';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return '$host bağlantısı kesildi';
  }

  @override
  String a11yConnectionFailed(String host) {
    return '$host bağlantısı başarısız oldu';
  }

  @override
  String get exit => 'Çıkış';

  @override
  String get exitConfirmation =>
      'Aktif oturumların bağlantısı kesilecek. Çıkılsın mı?';

  @override
  String get hintFolderExample => 'örn. Production';

  @override
  String get credentialsNotSet => 'Kimlik bilgileri ayarlanmadı';

  @override
  String get exportSessionsViaQr => 'Oturumları QR ile Dışa Aktar';

  @override
  String get qrTooManyForSingleCode =>
      'Tek bir QR kodu için çok fazla oturum. Bazılarının seçimini kaldırın veya .lfs dışa aktarımını kullanın.';

  @override
  String get qrTooLarge =>
      'Çok büyük — bazı öğelerin seçimini kaldırın veya .lfs dosya dışa aktarımını kullanın.';

  @override
  String get showQr => 'QR Göster';

  @override
  String get sort => 'Sırala';

  @override
  String get resizePanelDivider => 'Panel ayırıcısını yeniden boyutlandır';

  @override
  String get youreRunningLatest => 'En son sürümü kullanıyorsunuz';

  @override
  String get liveLog => 'Canlı Günlük';

  @override
  String get archivedLog => 'Arşivlenmiş günlük';

  @override
  String get loggingLevel => 'Log seviyesi';

  @override
  String get loggingLevelSubtitleInfo => 'Rutin kayıtlar + uyarılar + hatalar';

  @override
  String get loggingLevelSubtitleWarn => 'Sadece sorunlu yollar ve hatalar';

  @override
  String get loggingLevelSubtitleError => 'Sadece hatalar';

  @override
  String get loggingLevelSubtitleOff => 'Rutin log yazılmıyor';

  @override
  String transferNItems(int count) {
    return '$count öğeyi transfer et';
  }

  @override
  String get time => 'Zaman';

  @override
  String get failed => 'Başarısız';

  @override
  String get errOperationNotPermitted => 'İşleme izin verilmiyor';

  @override
  String get errNoSuchFileOrDirectory => 'Dosya veya dizin bulunamadı';

  @override
  String get errNoSuchProcess => 'İşlem bulunamadı';

  @override
  String get errIoError => 'G/Ç hatası';

  @override
  String get errBadFileDescriptor => 'Geçersiz dosya tanımlayıcı';

  @override
  String get errResourceTemporarilyUnavailable =>
      'Kaynak geçici olarak kullanılamıyor';

  @override
  String get errOutOfMemory => 'Bellek yetersiz';

  @override
  String get errPermissionDenied => 'Erişim reddedildi';

  @override
  String get errFileExists => 'Dosya zaten mevcut';

  @override
  String get errNotADirectory => 'Bir dizin değil';

  @override
  String get errIsADirectory => 'Bir dizin';

  @override
  String get errInvalidArgument => 'Geçersiz argüman';

  @override
  String get errTooManyOpenFiles => 'Çok fazla açık dosya';

  @override
  String get errNoSpaceLeftOnDevice => 'Cihazda boş alan kalmadı';

  @override
  String get errReadOnlyFileSystem => 'Salt okunur dosya sistemi';

  @override
  String get errBrokenPipe => 'Broken pipe';

  @override
  String get errFileNameTooLong => 'Dosya adı çok uzun';

  @override
  String get errDirectoryNotEmpty => 'Dizin boş değil';

  @override
  String get errAddressAlreadyInUse => 'Adres zaten kullanımda';

  @override
  String get errCannotAssignAddress => 'İstenen adres atanamıyor';

  @override
  String get errNetworkIsDown => 'Ağ çalışmıyor';

  @override
  String get errNetworkIsUnreachable => 'Ağa erişilemiyor';

  @override
  String get errConnectionResetByPeer => 'Bağlantı karşı tarafça sıfırlandı';

  @override
  String get errConnectionTimedOut => 'Bağlantı zaman aşımına uğradı';

  @override
  String get errConnectionRefused => 'Bağlantı reddedildi';

  @override
  String get errHostIsDown => 'Host kapalı';

  @override
  String get errNoRouteToHost => 'Host\'a rota yok';

  @override
  String get errConnectionAborted => 'Bağlantı iptal edildi';

  @override
  String get errAlreadyConnected => 'Zaten bağlı';

  @override
  String get errNotConnected => 'Bağlı değil';

  @override
  String errSshConnectFailed(String host, int port) {
    return '$host:$port adresine bağlanılamadı';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return '$user@$host için kimlik doğrulama başarısız';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return '$host:$port adresine bağlantı başarısız';
  }

  @override
  String get errSshAuthAborted => 'Kimlik doğrulama iptal edildi';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return '$host:$port için host anahtarı reddedildi — anahtarı kabul edin veya known_hosts dosyasını kontrol edin';
  }

  @override
  String get errSshOpenShellFailed => 'Kabuk açılamadı';

  @override
  String get errSshLoadKeyFileFailed => 'SSH anahtar dosyası yüklenemedi';

  @override
  String get errSshParseKeyFailed => 'PEM anahtar verisi ayrıştırılamadı';

  @override
  String get errSshConnectionDisposed => 'Bağlantı sonlandırıldı';

  @override
  String get errSshNotConnected => 'Bağlı değil';

  @override
  String get errConnectionFailed => 'Bağlantı başarısız';

  @override
  String get errConnectionLostReconnect =>
      'Bağlantı koptu — oturum kesildi (uyku veya ağ). Oturum listesinden yeniden bağlan.';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return '$seconds saniye sonra bağlantı zaman aşımına uğradı';
  }

  @override
  String get errSessionClosed => 'Oturum kapatıldı';

  @override
  String errSftpInitFailed(String error) {
    return 'SFTP başlatılamadı: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'İndirme başarısız: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'Sistem klasör seçici kullanılamıyor. Başka bir konum deneyin veya uygulamanın depolama izinlerini kontrol edin.';

  @override
  String get biometricUnlockPrompt => 'LetsFLUTssh kilidini aç';

  @override
  String get biometricUnlockTitle => 'Biyometri ile kilidi aç';

  @override
  String get biometricUnlockSubtitle =>
      'Parolayı yazmayın — cihazın biyometrik sensörüyle kilidi açın.';

  @override
  String get biometricEnableFailed =>
      'Biyometrik kilit açma etkinleştirilemedi.';

  @override
  String get biometricUnlockFailed =>
      'Biyometrik kilit açma başarısız. Ana parolanızı girin.';

  @override
  String get biometricUnlockCancelled => 'Biyometrik kilit açma iptal edildi.';

  @override
  String get biometricNotEnrolled =>
      'Bu cihazda kayıtlı biyometrik kimlik bilgisi yok.';

  @override
  String get biometricSensorNotAvailable =>
      'Bu cihazın biyometrik sensörü yok.';

  @override
  String get biometricSystemServiceMissing =>
      'Parmak izi hizmeti (fprintd) yüklü değil. README → Installation bölümüne bakın.';

  @override
  String get currentPasswordIncorrect => 'Mevcut parola yanlış';

  @override
  String get wrongPassword => 'Yanlış parola';

  @override
  String get changePassword => 'Şifre değiştir';

  @override
  String get changePasswordTitle => 'Şifre değiştir';

  @override
  String get currentPassword => 'Mevcut şifre';

  @override
  String get enterCurrentPassword => 'Mevcut şifreyi girin';

  @override
  String get newPassword => 'Yeni şifre';

  @override
  String get enterNewPassword => 'Yeni şifreyi girin';

  @override
  String get confirmNewPassword => 'Yeni şifreyi onayla';

  @override
  String get passwordChanged => 'Şifre değiştirildi.';

  @override
  String get passwordChangeFailed =>
      'Şifre değiştirilemedi. Günlükleri kontrol edin.';

  @override
  String get passwordRequired => 'Şifre gerekli.';

  @override
  String get lockScreenTitle => 'LetsFLUTssh kilitli';

  @override
  String get lockScreenSubtitle =>
      'Devam etmek için ana parolayı girin veya biyometriyi kullanın.';

  @override
  String get unlock => 'Kilidi aç';

  @override
  String get autoLockTitle => 'Hareketsizlik sonrası otomatik kilit';

  @override
  String get autoLockSubtitle =>
      'Bu süre boyunca boşta kalındığında arayüzü kilitler. Her kilitlenmede veritabanı anahtarı silinir ve şifrelenmiş depo kapatılır; etkin oturumlar, oturum kapandığında temizlenen oturum bazlı bir kimlik bilgisi önbelleği sayesinde bağlı kalır.';

  @override
  String get autoLockOff => 'Kapalı';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes dakika',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'Güncelleme reddedildi: İndirilen dosyalar uygulamada sabitlenmiş sürüm anahtarıyla imzalanmamış. Bu, indirmenin aktarım sırasında değiştirildiği veya mevcut sürümün bu kurulum için olmadığı anlamına gelebilir. YÜKLEMEYİN — bunun yerine resmi Sürümler sayfasından manuel olarak yeniden yükleyin.';

  @override
  String get errReleaseManifestUnavailable =>
      'Release manifesti alınamadı. Muhtemelen ağ sorunu, ya da release hâlâ yayınlanıyor. Birkaç dakika sonra tekrar deneyin.';

  @override
  String get updateSecurityWarningTitle => 'Güncelleme doğrulaması başarısız';

  @override
  String get updateReinstallAction => 'Sürümler sayfasını aç';

  @override
  String get errLfsNotArchive => 'Seçilen dosya bir LetsFLUTssh arşivi değil.';

  @override
  String get errLfsDecryptFailed =>
      'Yanlış ana parola veya bozulmuş .lfs arşivi';

  @override
  String get errLfsArchiveTruncated =>
      'Arşiv eksik. Yeniden indirin veya orijinal cihazdan yeniden dışa aktarın.';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'Arşiv çok büyük ($sizeMb MB). Sınır $limitMb MB — belleği korumak için şifre çözme öncesi iptal edildi.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'known_hosts girdisi çok büyük ($sizeMb MB). Sınır $limitMb MB — içe aktarma yanıt verir kalsın diye iptal edildi.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'İçe aktarma başarısız — verileriniz içe aktarma öncesi duruma geri yüklendi. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'Arşiv v$found şemasını kullanıyor, ancak bu sürüm yalnızca v$supported sürümüne kadar destekliyor. İçe aktarmak için uygulamayı güncelleyin.';
  }

  @override
  String get progressReadingArchive => 'Arşiv okunuyor…';

  @override
  String get progressDecrypting => 'Şifre çözülüyor…';

  @override
  String get progressCollectingData => 'Veriler toplanıyor…';

  @override
  String get progressEncrypting => 'Şifreleniyor…';

  @override
  String get progressWritingArchive => 'Arşiv yazılıyor…';

  @override
  String get progressWorking => 'İşleniyor…';

  @override
  String get importFromLink => 'QR bağlantısından içe aktar';

  @override
  String get importFromLinkSubtitle =>
      'Başka bir cihazdan kopyalanan letsflutssh:// derin bağlantısını yapıştırın';

  @override
  String get pasteImportLinkTitle => 'İçe aktarma bağlantısını yapıştır';

  @override
  String get pasteImportLinkDescription =>
      'Başka bir cihazda üretilen letsflutssh://import?d=… bağlantısını (veya ham yükü) yapıştırın. Kamera gerekmez.';

  @override
  String get pasteFromClipboard => 'Panodan yapıştır';

  @override
  String get invalidImportLink =>
      'Bağlantı geçerli bir LetsFLUTssh yükü içermiyor';

  @override
  String get importAction => 'İçe aktar';

  @override
  String get noTagsAvailable =>
      'Henüz etiket yok — Tools → Tags üzerinden oluşturun.';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'Kullanıcı adı';

  @override
  String get protocol => 'Protokol';

  @override
  String get bucket => 'Bucket';

  @override
  String get prefix => 'Prefix';

  @override
  String get typeLabel => 'Tür';

  @override
  String get folder => 'Klasör';

  @override
  String nSubitems(int count) {
    return '$count öğe';
  }

  @override
  String get subitems => 'Öğeler';

  @override
  String get grantPermission => 'İzin ver';

  @override
  String get storagePermissionLimited =>
      'Sınırlı erişim — tüm dosyalar için tam depolama izni verin';

  @override
  String progressConnecting(String host, int port) {
    return '$host:$port adresine bağlanılıyor';
  }

  @override
  String get progressVerifyingHostKey => 'Ana bilgisayar anahtarı doğrulanıyor';

  @override
  String progressAuthenticating(String user) {
    return '$user olarak kimlik doğrulanıyor';
  }

  @override
  String get progressOpeningShell => 'Kabuk açılıyor';

  @override
  String get progressOpeningSftp => 'SFTP kanalı açılıyor';

  @override
  String get transfersLabel => 'Aktarımlar:';

  @override
  String transferCountActive(int count) {
    return '$count aktif';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count sırada';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count geçmişte';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'Oluşturulma: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'Başlangıç: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'Bitiş: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'Süre: $duration';
  }

  @override
  String get transferStatusQueued => 'Sırada';

  @override
  String get fileConflictTitle => 'Dosya zaten mevcut';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" zaten $targetDir içinde var. Ne yapmak istersiniz?';
  }

  @override
  String get fileConflictSkip => 'Atla';

  @override
  String get fileConflictKeepBoth => 'İkisini de sakla';

  @override
  String get fileConflictReplace => 'Değiştir';

  @override
  String get fileConflictApplyAll => 'Kalan tümüne uygula';

  @override
  String get folderNameLabel => 'KLASÖR ADI';

  @override
  String folderAlreadyExists(String name) {
    return '\"$name\" klasörü zaten mevcut';
  }

  @override
  String get dropKeyFileHere => 'Anahtar dosyasını buraya sürükleyin';

  @override
  String get sessionNoCredentials =>
      'Oturumda kimlik bilgisi yok — şifre veya anahtar eklemek için düzenleyin';

  @override
  String dragItemCount(int count) {
    return '$count öğe';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'Tümünü seç ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'Boyut: $size KB / maks. $max KB';
  }

  @override
  String get noActiveTerminals => 'Aktif terminal yok';

  @override
  String get connectFromSessionsTab => 'Oturumlar sekmesinden bağlanın';

  @override
  String fileNotFound(String path) {
    return 'Dosya bulunamadı: $path';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count öğe, $size';
  }

  @override
  String get maximize => 'Büyüt';

  @override
  String get restore => 'Geri Yükle';

  @override
  String get duplicateDownShortcut => 'Aşağı Çoğalt (Ctrl+Shift+\\)';

  @override
  String get security => 'Güvenlik';

  @override
  String get knownHosts => 'Bilinen Host\'lar';

  @override
  String get knownHostsSubtitle => 'Güvenilen SSH host parmak izlerini yönetin';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bilinen host',
      one: '1 bilinen host',
      zero: 'Bilinen host yok',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'Bilinen host yok. Eklemek için bir host\'a bağlanın.';

  @override
  String get removeHost => 'Host\'u kaldır';

  @override
  String removeHostConfirm(String host) {
    return '$host bilinen host\'lardan kaldırılsın mı? Sonraki bağlantıda anahtar yeniden doğrulanacak.';
  }

  @override
  String get clearAllKnownHosts => 'Tüm bilinen sunucuları temizle';

  @override
  String get clearAllKnownHostsConfirm =>
      'Tüm bilinen sunucular kaldırılsın mı? Her sunucu anahtarı yeniden doğrulanmalı.';

  @override
  String get clearedAllHosts => 'Tüm bilinen sunucular temizlendi';

  @override
  String removedHost(String host) {
    return '$host kaldırıldı';
  }

  @override
  String get tools => 'Araçlar';

  @override
  String get sshKeys => 'SSH Anahtarları';

  @override
  String get sshKeysSubtitle =>
      'Kimlik doğrulama için SSH anahtar çiftlerini yönetin';

  @override
  String get noKeys => 'SSH anahtarı yok. İçe aktarın veya oluşturun.';

  @override
  String get generateKey => 'Anahtar oluştur';

  @override
  String get addKey => 'Anahtar ekle';

  @override
  String get addKeyMenuPaste => 'PEM yapıştır';

  @override
  String get filePickerUnavailable => 'Dosya seçici bu sistemde kullanılamıyor';

  @override
  String get importKey => 'Anahtar içe aktar';

  @override
  String get keyLabel => 'Anahtar adı';

  @override
  String get keyLabelHint => 'örn. İş Sunucusu, GitHub';

  @override
  String get selectKeyType => 'Anahtar türü';

  @override
  String get generating => 'Oluşturuluyor...';

  @override
  String keyGenerated(String label) {
    return 'Anahtar oluşturuldu: $label';
  }

  @override
  String keyImported(String label) {
    return 'Anahtar içe aktarıldı: $label';
  }

  @override
  String get deleteKey => 'Anahtarı sil';

  @override
  String deleteKeyConfirm(String label) {
    return '\"$label\" anahtarı silinsin mi? Bu anahtarı kullanan oturumlar erişimi kaybedecek.';
  }

  @override
  String keyDeleted(String label) {
    return 'Anahtar silindi: $label';
  }

  @override
  String get publicKey => 'Public key';

  @override
  String get publicKeyCopied => 'Public key panoya kopyalandı';

  @override
  String get sshCertificate => 'Sertifika';

  @override
  String get certImport => 'Sertifika içe aktar';

  @override
  String get certImportTooltip =>
      'CA\'nızın imzaladığı bir OpenSSH sertifikası ekleyin (`ssh-keygen -s …` ile üretilen `-cert.pub` dosyası). Sunucular `authorized_keys` yerine CA imzasıyla doğruluyorsa kullanın. Sunucularınız plain key auth kullanıyorsa atlayın.';

  @override
  String get certImportPickerTitle => 'OpenSSH sertifika dosyasını seç';

  @override
  String get certValidFrom => 'Geçerlilik başlangıcı';

  @override
  String get certValidTo => 'Geçerlilik bitişi';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => 'Bu sertifikanın süresi yakında dolacak.';

  @override
  String get certExpired => 'Süresi doldu';

  @override
  String get certRemove => 'Sertifikayı kaldır';

  @override
  String get certRemoveConfirmTitle => 'Sertifika kaldırılsın mı?';

  @override
  String get certRemoveConfirmBody =>
      'Sertifika kaldırıldığında oturum düz public key kimlik doğrulamasına geri döner.';

  @override
  String errCertParse(String detail) {
    return 'Sertifika parse edilemedi: $detail';
  }

  @override
  String get errCertPairFingerprintMismatch =>
      'Bu sertifika seçili anahtarla eşleşmiyor.';

  @override
  String get pastePrivateKey => 'Özel anahtarı yapıştır (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Geçersiz PEM anahtar verisi';

  @override
  String get selectFromKeyStore => 'Anahtar deposundan seç';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anahtar',
      one: '1 anahtar',
      zero: 'Anahtar yok',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'Oluşturuldu';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get enterMasterPassword =>
      'Kayıtlı kimlik bilgilerinize erişmek için ana şifreyi girin.';

  @override
  String get wrongMasterPassword => 'Yanlış şifre. Tekrar deneyin.';

  @override
  String get forgotPassword => 'Şifrenizi mi unuttunuz?';

  @override
  String get credentialsReset => 'Tüm kayıtlı kimlik bilgileri silindi';

  @override
  String get migrationToast => 'Depolama en son biçime yükseltildi';

  @override
  String get dbCorruptTitle => 'Veritabanı açılamıyor';

  @override
  String get dbCorruptBody =>
      'Diskteki veriler açılamıyor. Farklı bir kimlik bilgisi deneyin veya sıfırlayıp baştan başlayın.';

  @override
  String get dbCorruptWarning =>
      'Sıfırlama şifrelenmiş veritabanını ve güvenlikle ilgili tüm dosyaları kalıcı olarak siler. Hiçbir veri geri getirilmez.';

  @override
  String get dbCorruptTryOther => 'Farklı kimlik bilgilerini dene';

  @override
  String get dbCorruptResetContinue => 'Sıfırla ve yeniden kur';

  @override
  String get dbCorruptExit => 'LetsFLUTssh\'den çık';

  @override
  String get tierResetTitle => 'Güvenlik sıfırlaması gerekli';

  @override
  String get tierResetBody =>
      'Bu kurulum, farklı bir katman modeli kullanan LetsFLUTssh\'un önceki sürümünden güvenlik verileri taşıyor. Yeni model geriye dönük uyumsuz bir değişikliktir — otomatik geçiş yolu yoktur. Devam etmek için bu kurulumda kayıtlı tüm oturumlar, kimlik bilgileri, SSH anahtarları ve bilinen sunucular silinmeli ve ilk kurulum sihirbazı baştan çalıştırılmalıdır.';

  @override
  String get tierResetWarning =>
      '«Sıfırla ve Yeniden Kur» seçeneği şifreli veritabanını ve güvenlikle ilgili tüm dosyaları kalıcı olarak siler. Verilerinizi kurtarmanız gerekiyorsa, uygulamadan şimdi çıkın ve önce dışa aktarmak için LetsFLUTssh\'un önceki sürümünü yeniden yükleyin.';

  @override
  String get tierResetResetContinue => 'Sıfırla ve Yeniden Kur';

  @override
  String get tierResetExit => 'LetsFLUTssh\'tan Çık';

  @override
  String get derivingKey => 'Şifreleme anahtarı türetiliyor...';

  @override
  String get securitySetupTitle => 'Güvenlik ayarları';

  @override
  String get keychainAvailable => 'Kullanılabilir';

  @override
  String get changeSecurityTierConfirm =>
      'Veritabanı yeni düzeyle yeniden şifreleniyor. Kesilmez — uygulamayı bitene kadar açık tutun.';

  @override
  String get changeSecurityTierDone => 'Güvenlik düzeyi değiştirildi';

  @override
  String get changeSecurityTierFailed => 'Güvenlik düzeyi değiştirilemedi';

  @override
  String get firstLaunchSecurityTitle => 'Güvenli depolama etkinleştirildi';

  @override
  String get firstLaunchSecurityBody =>
      'Verileriniz işletim sisteminin anahtarlığında tutulan bir anahtarla şifrelenir. Bu cihazda kilit açma otomatiktir.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'Bu cihazda donanım destekli depolama mevcut. TPM / Secure Enclave bağlaması için Ayarlar → Güvenlik\'ten yükseltin.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'Bu cihazda donanım destekli depolama kullanılamıyor.';

  @override
  String get firstLaunchSecurityOpenSettings => 'Ayarları Aç';

  @override
  String get wizardReducedBanner =>
      'İşletim sistemi anahtarlığına bu kurulumda erişilemiyor. Şifreleme yok (T0) ile ana parola (Paranoid) arasında seçim yapın. Keychain katmanını etkinleştirmek için gnome-keyring, kwallet veya başka bir libsecret sağlayıcısı kurun.';

  @override
  String get tierBadgeCurrent => 'Geçerli';

  @override
  String get securitySetupEnable => 'Etkinleştir';

  @override
  String get securitySetupApply => 'Uygula';

  @override
  String get hwProbeLinuxDeviceMissing =>
      '/dev/tpmrm0 üzerinde TPM algılanmadı. Makine destekliyorsa BIOS\'tan fTPM / PTT etkinleştirin; aksi halde donanım katmanı bu cihazda kullanılamaz.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools kurulu değil. Donanım katmanını etkinleştirmek için `sudo apt install tpm2-tools` (veya dağıtımınızdaki eşdeğerini) çalıştırın.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'Donanım katmanı denemesi başarısız oldu. /dev/tpmrm0 izinlerini ve udev kurallarını kontrol edin — ayrıntılar günlüklerde.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'TPM 2.0 algılanmadı. UEFI ürün yazılımından fTPM / PTT etkinleştirin veya donanım katmanının bu cihazda kullanılamayacağını kabul edin — uygulama yazılım tabanlı kimlik bilgisi deposuna geri döner.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Ne Microsoft Platform Crypto Provider ne de Software Key Storage Provider erişilebilir — muhtemelen bozuk bir Windows kripto alt sistemi veya CNG\'yi engelleyen bir Grup İlkesi. Olay Görüntüleyici → Uygulama ve Hizmet Günlükleri\'ni kontrol edin.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'Bu Mac\'te Secure Enclave yok (T1 / T2 güvenlik çipi olmayan 2017 öncesi Intel Mac). Donanım katmanı kullanılamaz; bunun yerine ana parolayı kullanın.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'Bu Mac\'te oturum açma parolası ayarlanmamış. Secure Enclave anahtar oluşturma bunu gerektirir — Sistem Ayarları → Touch ID ve Parola (veya Oturum Açma Parolası) bölümünden belirleyin.';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave uygulamanın imza kimliğini reddetti (-34018). Bu yüklemeye sabit bir kendi imzalı kimlik vermek için sürümle birlikte gelen `macos-resign.sh` betiğini çalıştırın ve ardından uygulamayı yeniden başlatın.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'Cihaz kodu ayarlanmamış. Secure Enclave anahtar oluşturma bunu gerektirir — Ayarlar → Face ID ve Kod (veya Touch ID ve Kod) bölümünden belirleyin.';

  @override
  String get hwProbeIosSimulator =>
      'iOS Simülatöründe çalışıyor, Secure Enclave yok. Donanım katmanı yalnızca fiziksel iOS cihazlarda kullanılabilir.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'Donanım katmanı için Android 9 veya üzeri gerekir (StrongBox ve anahtar başına kayıt geçersizliği eski sürümlerde güvenilir değildir).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'Bu cihazda biyometrik donanım yok (parmak izi veya yüz). Bunun yerine ana parolayı kullanın.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'Biyometri kaydedilmemiş. Ayarlar → Güvenlik ve gizlilik → Biyometri\'den parmak izi veya yüz ekleyin, ardından donanım katmanını yeniden etkinleştirin.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'Biyometrik donanım geçici olarak kullanılamıyor (başarısız denemelerden sonra kilit veya bekleyen güvenlik güncellemesi). Birkaç dakika sonra tekrar deneyin.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'Android Keystore bu cihaz sürümünde donanım anahtarını oluşturmayı reddetti (StrongBox yok, özel ROM veya sürücü hatası). Donanım katmanı kullanılamıyor.';

  @override
  String get securityRecheck => 'Katman desteğini yeniden denetle';

  @override
  String get securityRecheckUpdated =>
      'Katman desteği güncellendi — yukarıdaki kartlara bakın';

  @override
  String get securityRecheckUnchanged => 'Katman desteği değişmedi';

  @override
  String get securityMacosEnableSecureTiers =>
      'Bu Mac\'te güvenli katmanların kilidini aç';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'Uygulamayı kişisel bir sertifika ile yeniden imzala, böylece Anahtar Zinciri (T1) ve Secure Enclave (T2) güncellemelerden sonra da çalışır';

  @override
  String get securityMacosEnableSecureTiersPrompt =>
      'macOS bir kez parolanızı isteyecek';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'Güvenli katmanlar açıldı — T1 ve T2 kullanılabilir';

  @override
  String get securityMacosEnableSecureTiersFailed =>
      'Güvenli katmanlar açılamadı';

  @override
  String get securityMacosOfferTitle =>
      'Anahtar Zinciri + Secure Enclave etkinleştirilsin mi?';

  @override
  String get securityMacosOfferBody =>
      'macOS, şifrelenmiş depolamayı uygulamanın imza kimliğine bağlar. Kararlı sertifika olmadan Anahtar Zinciri (T1) ve Secure Enclave (T2) erişimi reddeder. Bu Mac üzerinde kişisel kendinden imzalı bir sertifika oluşturup uygulamayı yeniden imzalayabiliriz — güncellemeler çalışmaya devam eder ve sırlarınız sürümler arasında korunur. macOS yeni sertifikaya güvenmek için bir kez oturum parolanızı isteyecek.';

  @override
  String get securityMacosOfferAccept => 'Etkinleştir';

  @override
  String get securityMacosOfferDecline => 'Atla — T0 veya Paranoid seç';

  @override
  String get securityMacosRemoveIdentity => 'İmza kimliğini kaldır';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      'Kişisel sertifikayı siler. T1 / T2 verileri buna bağlı — önce T0 veya Paranoid\'e geçin, sonra kaldırın.';

  @override
  String get securityMacosRemoveIdentityConfirmTitle =>
      'İmza kimliği kaldırılsın mı?';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'Oturum Anahtar Zincirindeki kişisel sertifikayı siler. T1 / T2 saklanan sırlar okunamaz hale gelir. Sihirbaz kaldırmadan önce T0 (düz metin) veya Paranoid (ana parola)\'ya geçiş için açılır.';

  @override
  String get securityMacosRemoveIdentitySuccess => 'İmza kimliği kaldırıldı';

  @override
  String get securityMacosRemoveIdentityFailed => 'İmza kimliği kaldırılamadı';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus çalışıyor ancak secret-service daemon çalışmıyor. gnome-keyring (`sudo apt install gnome-keyring`) veya KWalletManager kurun ve oturum açıldığında başladığından emin olun.';

  @override
  String get keyringProbeFailed =>
      'İşletim sistemi anahtar zinciri bu cihazda erişilemez. Platforma özgü hata için günlüklere bakın; uygulama ana parolaya geri döner.';

  @override
  String get snippets => 'Snippet\'ler';

  @override
  String get snippetsSubtitle =>
      'Yeniden kullanılabilir komut snippet\'lerini yönetin';

  @override
  String get noSnippets => 'Henüz snippet yok';

  @override
  String get addSnippet => 'Snippet Ekle';

  @override
  String get editSnippet => 'Snippet\'i Düzenle';

  @override
  String get deleteSnippet => 'Snippet\'i Sil';

  @override
  String deleteSnippetConfirm(String title) {
    return '\"$title\" snippet\'i silinsin mi?';
  }

  @override
  String get snippetTitle => 'Başlık';

  @override
  String get snippetTitleHint => 'örn. Dağıt, Servisi Yeniden Başlat';

  @override
  String get snippetCommand => 'Komut';

  @override
  String get snippetCommandHint => 'örn. sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'Açıklama (isteğe bağlı)';

  @override
  String get snippetDescriptionHint => 'Bu komut ne yapar?';

  @override
  String get snippetSaved => 'Snippet kaydedildi';

  @override
  String snippetDeleted(String title) {
    return '\"$title\" snippet\'i silindi';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippet',
      one: '1 snippet',
      zero: 'Snippet yok',
    );
    return '$_temp0';
  }

  @override
  String get pinToSession => 'Bu oturuma sabitle';

  @override
  String get unpinFromSession => 'Bu oturumdan kaldır';

  @override
  String get pinnedSnippets => 'Sabitlenmiş';

  @override
  String get allSnippets => 'Tümü';

  @override
  String get commandCopied => 'Komut panoya kopyalandı';

  @override
  String get snippetTokensHint =>
      'Yer tutucu eklemek için dokunun. Çalışma zamanında aktif oturumun değerleriyle değiştirilir:';

  @override
  String get snippetCustomTokensHint =>
      'Çift süslü parantezli başka herhangi bir şey snippet çalıştırıldığında size bir değer sorar.';

  @override
  String get snippetFillTitle => 'Snippet parametrelerini doldur';

  @override
  String get snippetFillSubmit => 'Çalıştır';

  @override
  String get broadcastSetDriver => 'Bu panelden yayınla';

  @override
  String get broadcastClearDriver => 'Bu panelden yayını durdur';

  @override
  String get broadcastAddReceiver => 'Yayını burada al';

  @override
  String get broadcastRemoveReceiver => 'Yayını almayı durdur';

  @override
  String get broadcastClearAll => 'Tüm yayınları durdur';

  @override
  String get broadcastPasteTitle => 'Yapıştırmayı tüm panellere gönder?';

  @override
  String broadcastPasteBody(int chars, int count) {
    return '$chars karakter diğer $count panele gönderilecek.';
  }

  @override
  String get broadcastPasteSend => 'Gönder';

  @override
  String get portForwarding => 'Yönlendirme';

  @override
  String get portForwardingEmpty => 'Henüz kural yok';

  @override
  String get addForwardRule => 'Kural ekle';

  @override
  String get editForwardRule => 'Kuralı düzenle';

  @override
  String get deleteForwardRule => 'Kuralı sil';

  @override
  String get localForward => 'Yerel';

  @override
  String get remoteForward => 'Uzak';

  @override
  String get dynamicForward => 'Dinamik';

  @override
  String get forwardKind => 'Tür';

  @override
  String get bindAddress => 'Bağlama adresi';

  @override
  String get bindPort => 'Bağlama portu';

  @override
  String get targetHost => 'Hedef sunucu';

  @override
  String get targetPort => 'Hedef port';

  @override
  String get forwardDescription => 'Açıklama (isteğe bağlı)';

  @override
  String get forwardEnabled => 'Etkin';

  @override
  String get forwardBindWildcardWarning =>
      '0.0.0.0 bağlaması yönlendirmeyi tüm arabirimlerde açar — genelde 127.0.0.1 istersin.';

  @override
  String get forwardKindLocalHelp =>
      'Yerel: bu cihazda bir port açar ve SSH sunucusundan erişilebilir hedefe tünel kurar. localhost:bindPort üzerinden uzak veritabanlarına veya yönetim arayüzlerine erişmek için kullanışlı.';

  @override
  String get forwardKindRemoteHelp =>
      'Uzak: SSH sunucusundan bir port açmasını ister; port bu cihazdan erişilebilir hedefe tünel kurar. Yerel dev sunucuyu uzak bir host ile paylaşmak için kullanışlı (sunucu non-loopback bağlamalar için GatewayPorts yes gerektirebilir).';

  @override
  String get forwardKindDynamicHelp =>
      'Dinamik: bu cihazda her bağlantıyı SSH sunucusu üzerinden yönlendiren bir SOCKS5 proxy. Tüm trafiği SSH üzerinden göndermek için tarayıcıyı veya curl\'u localhost:bindPort\'a yönlendirin.';

  @override
  String get proxyJump => 'Üzerinden bağlan';

  @override
  String get proxyJumpNone => 'Doğrudan bağlantı';

  @override
  String get proxyJumpSavedSession => 'Kaydedilmiş oturum';

  @override
  String get proxyJumpCustom => 'Özel';

  @override
  String get proxyJumpCustomNote =>
      'Özel hoplar bu oturumun kimlik bilgilerini kullanır. Farklı bastion auth için bastion\'u ayrı bir oturum olarak kaydet.';

  @override
  String viaSessionLabel(String label) {
    return '$label üzerinden';
  }

  @override
  String get recordSession => 'Oturumu kaydet';

  @override
  String get recordSessionHelp =>
      'Bu oturumun terminal çıktısını diske kaydet. Master parola veya donanım anahtarı oturum veritabanını koruyorsa diskte şifrelidir; aksi takdirde veritabanının yanına plaintext olarak yazılır.';

  @override
  String get recordingsBrowserTitle => 'Kayıtlar';

  @override
  String get recordingsBrowserSubtitle =>
      'Kaydedilmiş oturumlara göz atın, oynatın ve silin';

  @override
  String get recordingsEmpty => 'Henüz kayıt yok';

  @override
  String get playRecording => 'Oynat';

  @override
  String get deleteRecording => 'Sil';

  @override
  String get recordingPlaybackTitle => 'Kaydı oynat';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

  @override
  String get tags => 'Etiketler';

  @override
  String get tagsSubtitle =>
      'Oturumları ve klasörleri renkli etiketlerle düzenleyin';

  @override
  String get noTags => 'Henüz etiket yok';

  @override
  String get addTag => 'Etiket Ekle';

  @override
  String get deleteTag => 'Etiketi Sil';

  @override
  String deleteTagConfirm(String name) {
    return '\"$name\" etiketi silinsin mi? Tüm oturum ve klasörlerden kaldırılacak.';
  }

  @override
  String get tagName => 'Etiket Adı';

  @override
  String get tagNameHint => 'örn. Üretim, Staging';

  @override
  String get tagColor => 'Renk';

  @override
  String get tagCreated => 'Etiket oluşturuldu';

  @override
  String tagDeleted(String name) {
    return '\"$name\" etiketi silindi';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etiket',
      one: '1 etiket',
      zero: 'Etiket yok',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'Etiketleri yönet';

  @override
  String get editTags => 'Etiketleri Düzenle';

  @override
  String get fullBackup => 'Tam yedekleme';

  @override
  String get sessionsOnly => 'Oturumlar';

  @override
  String get presetFullImport => 'Tam içe aktarma';

  @override
  String get presetSelective => 'Seçici';

  @override
  String get presetCustom => 'Özel';

  @override
  String get sessionSshKeys => 'Oturum anahtarları (yönetici)';

  @override
  String get allManagerKeys => 'Tüm yönetici anahtarları';

  @override
  String get browseFiles => 'Dosyalara gözat…';

  @override
  String get sshDirSessionAlreadyImported => 'zaten oturumlarda mevcut';

  @override
  String get languageSubtitle => 'Arayüz dili';

  @override
  String get themeSubtitle => 'Koyu, açık veya sistemle uyumlu';

  @override
  String get uiScaleSubtitle => 'Tüm arayüzü ölçekle';

  @override
  String get terminalFontSizeSubtitle =>
      'Terminal çıktısındaki yazı tipi boyutu';

  @override
  String get scrollbackLinesSubtitle => 'Terminal scrollback buffer boyutu';

  @override
  String get keepAliveIntervalSubtitle =>
      'SSH keep-alive paketleri arasındaki saniye (0 = kapalı)';

  @override
  String get sshTimeoutSubtitle => 'Bağlantı zaman aşımı (saniye)';

  @override
  String get defaultPortSubtitle =>
      'Yeni oturumlar için varsayılan bağlantı noktası';

  @override
  String get parallelWorkersSubtitle =>
      'Eş zamanlı SFTP transfer worker sayısı';

  @override
  String get maxHistorySubtitle => 'Geçmişte saklanan maksimum komut sayısı';

  @override
  String get calculateFolderSizesSubtitle =>
      'Kenar çubuğunda klasörlerin yanında toplam boyutu göster';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Uygulama başlatıldığında GitHub\'da yeni sürümü denetle';

  @override
  String get threatColdDiskTheft => 'Kapalı makineden disk hırsızlığı';

  @override
  String get threatColdDiskTheftDescription =>
      'Kapalı bir bilgisayardan sürücünün çıkarılıp başka bir bilgisayarda okunması ya da ev dizininize erişimi olan biri tarafından veritabanı dosyasının kopyalanması.';

  @override
  String get threatKeyringFileTheft =>
      'Keyring / keychain dosyasının çalınması';

  @override
  String get threatKeyringFileTheftDescription =>
      'Saldırgan, platformun kimlik bilgisi deposu dosyasını doğrudan diskten okur (libsecret keyring, Windows Credential Manager, macOS login keychain) ve sarılmış veritabanı anahtarını bundan çıkarır. Donanım katmanı bunu paroladan bağımsız engeller çünkü çip anahtar malzemesini dışa aktarmayı reddeder; keychain katmanı için ek olarak parola gerekir, aksi halde çalınan dosya yalnızca OS oturum açma parolası ile açılır.';

  @override
  String get modifierOnlyWithPassword => 'yalnızca parola ile';

  @override
  String get threatBystanderUnlockedMachine =>
      'Kilidi açık makinenin yanındaki yabancı';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'Siz yokken biri, kilidi zaten açık olan bilgisayarınıza yaklaşıp uygulamayı açar.';

  @override
  String get threatLiveRamForensicsLocked =>
      'Kilitli makinede RAM dump / bellek forensics';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'Saldırgan RAM\'i dondurur (ya da DMA ile yakalar) ve uygulama kilitliyken bile anlık görüntüden hâlâ kalıcı olan anahtar malzemesini çeker.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'OS kernel veya keychain ele geçirilmesi';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'Kernel güvenlik açığı, keychain sızdırılması ya da donanımsal güvenlik çipindeki arka kapı. OS, güvenilir bir kaynak olmaktan çıkıp saldırganın kendisi haline gelir.';

  @override
  String get threatOfflineBruteForce =>
      'Zayıf parolaya karşı offline brute-force';

  @override
  String get threatOfflineBruteForceDescription =>
      'Wrapped key veya sealed blob kopyasına sahip bir saldırgan, hiçbir rate limit olmadan kendi temposunda her parolayı dener.';

  @override
  String get legendProtects => 'Korunuyor';

  @override
  String get legendDoesNotProtect => 'Korunmuyor';

  @override
  String get colT0 => 'T0 Düz metin';

  @override
  String get colT1 => 'T1 Anahtar zinciri';

  @override
  String get colT1Password => 'T1 + parola';

  @override
  String get colT1PasswordBiometric => 'T1 + parola + biyometrik';

  @override
  String get colT2Password => 'T2 + parola';

  @override
  String get colT2PasswordBiometric => 'T2 + parola + biyometrik';

  @override
  String get colParanoid => 'Paranoyak';

  @override
  String get securityComparisonTableThreatColumn => 'Tehdit';

  @override
  String get compareAllTiers => 'Tüm katmanları karşılaştır';

  @override
  String get resetAllDataTitle => 'Tüm verileri sıfırla';

  @override
  String get resetAllDataSubtitle =>
      'Tüm oturumları, anahtarları, yapılandırmaları ve güvenlik bileşenlerini siler. Anahtar zinciri kayıtlarını ve donanım kasası yuvalarını da temizler.';

  @override
  String get resetAllDataConfirmTitle => 'Tüm veriler sıfırlansın mı?';

  @override
  String get resetAllDataConfirmBody =>
      'Tüm oturumlar, SSH anahtarları, known hosts, parçacıklar, etiketler, tercihler ve tüm güvenlik bileşenleri (anahtar zinciri kayıtları, donanım kasası verileri, biyometrik katman) kalıcı olarak silinecektir. Bu işlem geri alınamaz.';

  @override
  String get resetAllDataConfirmAction => 'Her şeyi sıfırla';

  @override
  String resetAllDataConfirmTypePrompt(String phrase) {
    return 'Onaylamak için aşağıya $phrase yazın:';
  }

  @override
  String get resetAllDataInProgress => 'Sıfırlanıyor…';

  @override
  String get resetAllDataDone => 'Tüm veriler sıfırlandı';

  @override
  String get resetAllDataFailed => 'Sıfırlama başarısız';

  @override
  String get recordingsTitle => 'Recordings';

  @override
  String get recordingsStorageUsedLabel => 'Kullanılan';

  @override
  String get recordingsCapLabel => 'Cap';

  @override
  String get recordingsCapHint =>
      'recordings/ klasörüne uygulanan sert cap. Aşıldığında en eski recording önce silinir; sürmekte olan recording asla dokunulmaz.';

  @override
  String get recordingsClearAllAction => 'Tüm recordings\'i sil';

  @override
  String get recordingsClearAllConfirmTitle => 'Tüm recordings silinsin mi?';

  @override
  String get recordingsClearAllConfirmBody =>
      '<app>/recordings/ altındaki her kayıtlı oturum silinecek. Sürmekte olan recording (varsa) kalır. Bu işlem geri alınamaz.';

  @override
  String recordingsClearAllResult(int count) {
    return '$count recording silindi';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return 'Cap güncellendi. $bytes geri kazanıldı.';
  }

  @override
  String get recordingsCapChangedNoChange =>
      'Cap güncellendi. Silinecek bir şey yok.';

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
      'Otomatik kilit, aktif katmanda bir parola gerektirir.';

  @override
  String get recommendedBadge => 'ÖNERİLEN';

  @override
  String get tierHardwareSubtitleHonest =>
      'Gelişmiş: donanıma bağlı anahtar, her zaman parola ile korunur. Bu cihazın çipi kaybolursa veya değiştirilirse veriler geri getirilemez.';

  @override
  String get tierParanoidSubtitleHonest =>
      'Alternatif: ana parola, OS\'e güven yok. OS\'in ele geçirilmesine karşı korur. Çalışma zamanı korumasını T1/T2\'ye göre iyileştirmez.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'Runtime tehditleri (aynı kullanıcıdan malware, çalışan süreç bellek dökümü) her kademede ✗ olarak gösterilir. Bunlar, kademe seçiminden bağımsız olarak uygulanan ayrı azaltma özellikleriyle ele alınır.';

  @override
  String get currentTierBadge => 'GEÇERLİ';

  @override
  String get paranoidAlternativeHeader => 'ALTERNATİF';

  @override
  String get modifierPasswordLabel => 'Parola';

  @override
  String get modifierPasswordSubtitle =>
      'Kasa açılmadan önce yazılan gizli geçiş kapısı.';

  @override
  String get modifierPasswordRequired =>
      'Zorunlu — Hardware tier her zaman parola ile korunur.';

  @override
  String get modifierBiometricLabel => 'Biyometrik kısayol';

  @override
  String get modifierBiometricSubtitle =>
      'Parolayı yazmak yerine biyometrik korumalı bir OS yuvasından alır.';

  @override
  String get biometricRequiresPassword =>
      'Önce bir parola etkinleştirin — biyometri yalnızca onu girmek için bir kısayoldur.';

  @override
  String get biometricRequiresActiveTier =>
      'Biyometrik kilit açmayı etkinleştirmek için önce bu katmanı seçin';

  @override
  String get autoLockRequiresActiveTier =>
      'Otomatik kilidi yapılandırmak için önce bu katmanı seçin';

  @override
  String get biometricForbiddenParanoid =>
      'Paranoid seviyesi tasarım gereği biyometriye izin vermez.';

  @override
  String get fprintdNotAvailable =>
      'fprintd kurulu değil veya kayıtlı parmak izi yok.';

  @override
  String get t2RequiresPasswordTitle =>
      'Hardware tier için master password belirle';

  @override
  String get t2RequiresPasswordBody =>
      'Hardware tier modifier olarak password gerektirir. Biometric bunun üzerinde opsiyonel bir shortcut\'tır.';

  @override
  String get t2MigrationPromptTitle => 'Hardware tier password gerektiriyor';

  @override
  String get t2MigrationPromptBody =>
      'Password\'siz mevcut Hardware install\'lar devam etmek için şimdi bir tane belirlemeli.';

  @override
  String get t2MigrationContinue => 'Devam';

  @override
  String get t2MigrationSetPasswordTitle =>
      'Hardware tier\'ı korumak için bir password belirle';

  @override
  String get t2MigrationSetPasswordBody =>
      'Yeni bir master password gir. Hardware module içinde zaten sealed olan DB key bu password altında re-seal edilir — session\'ların ve key\'lerin sağlam kalır.';

  @override
  String get t2MigrationWipeAndRestart => 'Wipe edip sıfırdan başla';

  @override
  String get t2MigrationResealFailed =>
      'Hardware tier re-seal başarısız — farklı bir password seç ya da wipe et.';

  @override
  String get biometricOverlayEnable =>
      'Hardware tier üzerinde biometric shortcut\'ı etkinleştir';

  @override
  String get biometricOverlayEnableSubtitle =>
      'Password\'ünü biometric-gated bir OS slot\'undan serbest bırakır.';

  @override
  String get biometricOverlayUnavailable =>
      'Biometric overlay bu platformda henüz mevcut değil.';

  @override
  String get biometricOverlayRequiresPassword =>
      'Önce Hardware tier password\'ünü belirle.';

  @override
  String get t2UnlockTitle => 'Master password ile aç';

  @override
  String get t2UnlockSubtitle =>
      'Hardware-bound anahtar password\'ün ile korunur.';

  @override
  String get t2UnlockUseBiometricButton => 'Biometric kullan';

  @override
  String get t2PasswordChanged => 'Hardware tier password\'ü güncellendi.';

  @override
  String get paranoidMasterPasswordNote =>
      'Uzun bir passphrase kesinlikle önerilir — Argon2id brute-force\'u yalnızca yavaşlatır, engellemez.';

  @override
  String get plaintextWarningTitle => 'Düz metin: şifreleme yok';

  @override
  String get plaintextWarningBody =>
      'Oturumlar, anahtarlar ve known hosts şifrelenmeden saklanacak. Bu bilgisayarın dosya sistemine erişebilen herkes bunları okuyabilir.';

  @override
  String get plaintextAcknowledge => 'Verilerimin şifrelenmeyeceğini anlıyorum';

  @override
  String get plaintextAcknowledgeRequired =>
      'Devam etmeden önce anladığınızı onaylayın.';

  @override
  String get passwordLabel => 'Parola';

  @override
  String get masterPasswordLabel => 'Ana parola';

  @override
  String get globalErrorTitle => 'Beklenmeyen hata';

  @override
  String get globalErrorBody =>
      'Beklenmeyen bir hata oluştu. Uygulama çalışmaya devam edecek.';

  @override
  String get globalErrorLogSavedNote => 'Tüm ayrıntılar log dosyasına yazıldı.';

  @override
  String get globalErrorLogDisabledNote =>
      'Hata ayrıntılarını kaydetmek için Ayarlar\'dan log\'u etkinleştir.';

  @override
  String globalErrorTechnicalLine(String detail) {
    return 'Hata: $detail';
  }

  @override
  String get globalErrorEnableLoggingButton => 'Log\'u etkinleştir';

  @override
  String get globalErrorLoggingEnabledToast =>
      'Log etkin — hatalar log dosyasına yazılacak';

  @override
  String get fatalErrorQuitButton => 'Çık';

  @override
  String get fatalErrorWipeButton => 'Tüm verileri sil';

  @override
  String get fatalErrorWipingButton => 'Siliniyor…';

  @override
  String get fatalErrorWipeExplanation =>
      'Silme, tüm uygulama dosyalarını (config, veritabanı, vault blob\'ları, log\'lar) kaldırır; sonraki açılış temiz bir kurulumdan başlar. Geri alınamaz.';

  @override
  String get fatalErrorWipeConfirmTitle => 'Tüm veriler silinsin mi?';

  @override
  String get fatalErrorWipeConfirmBody =>
      'Bu, tüm config, veritabanı ve vault dosyalarını kalıcı olarak siler. Uygulama boş bir kurulumdan yeniden başlar. Devam edilsin mi?';

  @override
  String get fatalErrorWipeConfirmAction => 'Her şeyi sil';

  @override
  String get unencryptedArchiveWarning =>
      'Bu arşiv parola korumalı değil. Dosyaya sahip olan herkes içeriğini okuyabilir.';

  @override
  String get clipboardCopyFailed => 'Panoya kopyalanamadı.';

  @override
  String get nonAsciiHostnameWarning =>
      'Host adı ASCII olmayan karakterler içeriyor — her karakteri yazdığınla karşılaştır. Görsel olarak benzer kod noktaları (Kiril / Yunan) bir Latin alan adını taklit edebilir.';

  @override
  String get playbackPause => 'Duraklat';

  @override
  String get recordingPlayLocked =>
      'Bu şifreli kaydı oynatmak için uygulamanın kilidini aç.';

  @override
  String get recordToggleStart => 'Kaydı başlat';

  @override
  String get recordToggleStop => 'Kaydı durdur';

  @override
  String get foregroundServiceTitle => 'SSH aktif';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etkin bağlantı',
      one: '1 etkin bağlantı',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => 'Session türü';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => 'Kullanıcı adı';

  @override
  String get webDavAuthMethod => 'Auth yöntemi';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer token';

  @override
  String get trustedCert => 'Güvenilen sertifika (PEM)';

  @override
  String get trustedCertHint => '-----BEGIN CERTIFICATE-----';

  @override
  String get trustedCertHelp =>
      'Sunucu sertifikasını yapıştırın (bir veya birden çok PEM bloğu). Sadece bu oturum için ek bir root CA olarak eklenir — diğer uygulamaları etkilemez. Sistem trust store\'unu kullanmak için boş bırakın.';

  @override
  String get acceptAnyCert => 'Her sertifikayı kabul et';

  @override
  String get acceptAnyCertHelp =>
      'Bu oturumun TLS handshake\'lerinde tüm sertifika ve hostname kontrollerini atla. Sistem trust store da pinned cert de uygun değilse son çare.';

  @override
  String get acceptAnyCertWarn =>
      'MITM saldırılarına karşı savunmasız — ağdaki herkes sunucu kimliğine bürünebilir. Yalnızca güvenilir özel ağlarda kullanın.';

  @override
  String get webDavCopyUrl => 'WebDAV URL kopyala';

  @override
  String get webDavOpenInBrowser => 'Tarayıcıda aç';

  @override
  String get errWebDavAuthFailed => 'WebDAV auth başarısız';

  @override
  String get errWebDavNotFound => 'Path bulunamadı';

  @override
  String get errWebDavConflict => 'Operasyon mevcut state ile çakışıyor';

  @override
  String errWebDavGeneric(String detail) {
    return 'WebDAV server isteği reddetti: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'WebDAV base URL gerekli';

  @override
  String get errWebDavBaseUrlInvalid => 'Base URL http:// veya https:// olmalı';

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
      'AWS için boş bırak, MinIO / R2 / Spaces için endpoint gir';

  @override
  String get s3PathStyle => 'Path-style addressing';

  @override
  String get s3PathStyleHint => 'MinIO için gerekli; AWS için off bırak';

  @override
  String get s3DefaultBucket => 'Default bucket';

  @override
  String get s3DefaultPrefix => 'Default prefix';

  @override
  String get s3GeneratePresignedUrl => 'Presigned URL üret';

  @override
  String get s3PresignedUrlExpiry => 'Süre sonu';

  @override
  String get s3CopyUri => 's3://bucket/key URI kopyala';

  @override
  String get s3PresignedUrlExpiry15min => '15 dakika';

  @override
  String get s3PresignedUrlExpiry1hour => '1 saat';

  @override
  String get s3PresignedUrlExpiry4hour => '4 saat';

  @override
  String get s3PresignedUrlExpiry24hour => '24 saat';

  @override
  String get s3PresignedUrlExpiry7day => '7 gün';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (access key + secret kontrol et)';

  @override
  String get errS3NoSuchBucket => 'Bucket yok veya erişilemiyor';

  @override
  String get errS3RegionMismatch => 'Bucket başka bir region\'da';

  @override
  String errS3Generic(String detail) {
    return 'S3 sunucusu request\'i reddetti: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'WebDAV sync etkinleştir';

  @override
  String get syncPassphrase => 'Sync passphrase';

  @override
  String get syncPassphraseHint =>
      'Sync arşivini şifreler. Master password\'dan farklı olmalı.';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Sync passphrase, master password ile aynı olamaz.';

  @override
  String get syncRemotePath => 'Remote path';

  @override
  String get syncRemotePathHint =>
      'WebDAV base URL altındaki path — varsayılan letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return 'Son push: $when';
  }

  @override
  String syncLastPulled(String when) {
    return 'Son pull: $when';
  }

  @override
  String get syncNeverRun => 'Hiç';

  @override
  String get syncUpToDate => 'Sync güncel';

  @override
  String syncPushedBytes(String bytes) {
    return '$bytes push edildi';
  }

  @override
  String syncPullApplied(int count) {
    return 'Remote\'dan $count değişiklik uygulandı';
  }

  @override
  String get errSyncDisabled => 'Sync devre dışı';

  @override
  String get errSyncEtagMismatch => 'Remote değişti — önce pull, sonra push';

  @override
  String get errSyncUnauthorized => 'WebDAV kimlik doğrulama başarısız';

  @override
  String errSyncNetwork(String detail) {
    return 'Ağ hatası: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion =>
      'Remote sync arşivi daha yeni bir build gerektiriyor';

  @override
  String get hardwareKey => 'Hardware key';

  @override
  String get hardwareKeyTapPrompt => 'Hardware key\'e dokun';

  @override
  String get hardwareKeyPin => 'Hardware key PIN';

  @override
  String get hardwareKeyTimeout => 'Hardware key yanıt vermedi';

  @override
  String get hardwareKeyNotFound => 'Hardware key bulunamadı';

  @override
  String get hardwareKeyUnsupported =>
      'Bu platformda doğrudan hardware key erişimi yok';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'Apple Developer Program entitlement gerekli; macOS\'ta ssh-agent kullan';

  @override
  String get skKeyRequiresDevice =>
      'Bu SSH key bir hardware key gerektiriyor — auth için dokun';

  @override
  String get errSkWrongPin => 'PIN hatalı';

  @override
  String get hardwareKeyImport => 'Hardware key import et (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => 'Hardware key prompt iptal edildi';

  @override
  String get agentEndpointSectionTitle => 'Harici SSH client entegrasyonu';

  @override
  String get agentEndpointToggleTitle =>
      'Hardware-bound keys\'i sistem SSH client\'larına aç';

  @override
  String get agentEndpointToggleSubtitle =>
      'Bu cihazdaki git, ssh ve IDE plugin\'lerinin FIDO2 / smart-card / TPM keys\'lerinizi kullanmasına izin verir.';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'export komutunu kopyala';

  @override
  String get agentEndpointCopyPipeName => 'pipe adını kopyala';

  @override
  String get agentEndpointSignatureRequestTitle => 'İmza isteği';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester, $keyLabel ile imzalamak istiyor';
  }

  @override
  String get agentEndpointRequesterUnknown => 'Harici bir SSH client';

  @override
  String get agentEndpointAuthorizeOnce => 'Bir kez yetkilendir';

  @override
  String get agentEndpointAuthorizeAlways => 'Yetkilendir ve hatırla';

  @override
  String get agentEndpointDeny => 'Reddet';

  @override
  String get agentEndpointStatusRunning => 'Çalışıyor';

  @override
  String get agentEndpointStatusStopped => 'Durdu';

  @override
  String get agentEndpointStatusUnsupported => 'Bu platformda desteklenmiyor';

  @override
  String get agentEndpointRefusedAddIdentity =>
      'Reddedildi: harici client\'lar key ekleyemez.';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'ssh-agent endpoint başlatılamadı: $detail';
  }

  @override
  String get pkcs11AddTitle => 'Smart card / token anahtarı ekle';

  @override
  String get pkcs11ModuleLabel => 'PKCS#11 modülü';

  @override
  String get pkcs11ModuleAutoDetected => 'Otomatik algılandı';

  @override
  String get pkcs11ModuleCustom => 'Özel modül...';

  @override
  String get pkcs11ModulePickerTitle => 'PKCS#11 kütüphanesi seç';

  @override
  String get pkcs11NoModuleFound =>
      'PKCS#11 modülü bulunamadı. OpenSC yükle veya vendor kütüphanesi seç.';

  @override
  String get pkcs11InitializeFailed => 'PKCS#11 modülü initialise olmadı.';

  @override
  String get pkcs11NoTokenPresent => 'Hiçbir okuyucuda token yok.';

  @override
  String pkcs11TokenLabel(String label) {
    return 'Token: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return 'Seri: $serial';
  }

  @override
  String get pkcs11LoginRequired => 'Token login gerektiriyor.';

  @override
  String pkcs11PinPrompt(String token) {
    return '$token için PIN';
  }

  @override
  String get pkcs11PinPad => 'Token\'ın PIN-pad\'inde onayla.';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'PIN yanlış. $remaining deneme kaldı.';
  }

  @override
  String get pkcs11PinLocked => 'Token PIN kilitli. PUK ile aç.';

  @override
  String get pkcs11NoSignableKeys =>
      'Token\'da SSH için kullanılabilir key yok (RSA, ECDSA, Ed25519).';

  @override
  String get pkcs11GostUnsupported => 'GOST key\'leri SSH ile kullanılamaz.';

  @override
  String pkcs11TokenUnplugged(String label) {
    return 'Token \"$label\" takılı değil.';
  }

  @override
  String get pkcs11UriRebindFailed =>
      'Kaydedilmiş token bulunamadı. Yeniden tak ve dene.';

  @override
  String pkcs11SignFailed(String reason) {
    return 'Signing başarısız: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      'Smart card / PKCS#11 token\'lar bu platformda yok.';

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
  String get pkcs11WizardStepModule => 'PKCS#11 module seç';

  @override
  String get pkcs11WizardStepToken => 'Token seç';

  @override
  String get pkcs11WizardStepKey => 'Key seç';

  @override
  String get pkcs11WizardStepPin => 'PIN gir';

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
  String get pkcs11SaveCta => 'Key\'i import et';

  @override
  String get pkcs11SaveInProgress => 'Token\'dan public key okunuyor...';

  @override
  String get pkcs11SaveSuccess => 'Smart card key eklendi.';

  @override
  String get pkcs11ScanInProgress => 'PKCS#11 module\'leri taranıyor...';

  @override
  String get pkcs11LoadingTokens => 'Token\'lar yükleniyor...';

  @override
  String get pkcs11LoadingKeys => 'Key\'ler yükleniyor...';

  @override
  String get pkcs11ModuleStatusReady => 'Module yüklendi.';

  @override
  String get pkcs11ModuleStatusNoToken => 'Token yok.';

  @override
  String get pkcs11ModuleStatusFailed => 'Module yüklenemedi.';

  @override
  String get pkcs11PinPadHint => '(Cihaz üzerinde PIN pad)';

  @override
  String get pkcs11WizardBack => 'Geri';

  @override
  String get pkcs11WizardNext => 'İleri';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => 'Hardware anahtarı ekle';

  @override
  String get sshKeyHardwareBoundExplainer =>
      'Private key cihazın secure hardware bileşeninde yaşıyor ve dışa aktarılamaz.';

  @override
  String get sshKeyEnclaveDeviceBound =>
      'Bu key yalnızca bu Mac üzerinde çalışır.';

  @override
  String get sshKeyEnclaveDeviceBoundIos =>
      'Bu key yalnızca bu iPhone üzerinde çalışır.';

  @override
  String get sshKeyHelloDeviceBound =>
      'Bu key yalnızca bu PC üzerinde çalışır.';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'Touch ID / Face ID zorunlu olsun';

  @override
  String get sshKeyEnclavePasscodeFallback =>
      'Cihaz passcode\'unu fallback olarak kabul et';

  @override
  String get sshKeyHelloPinRequired =>
      'Windows Hello zorunlu olsun (PIN, parmak izi veya yüz)';

  @override
  String get sshKeyHardwareUnavailableTitle => 'Hardware key kullanılamıyor';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'Secure Enclave için uygulamanın code-signed olması gerekir.';

  @override
  String get sshKeyHardwareUnavailableHello =>
      'Bu PC\'de Windows Hello yapılandırılmamış.';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'TPM algılanmadı — yalnızca software-backed.';

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
  String get sshKeyGenerateCta => 'Oluştur';

  @override
  String get sshKeyGenerateInProgress =>
      'Key secure hardware içinde oluşturuluyor...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Code-signing gerekli — USER_GUIDE.md → Hardware-bound keys bölümüne bakın.';

  @override
  String get sshKeySignInProgress => 'Secure hardware ile imzalanıyor...';

  @override
  String get sshKeyPublicCopy => 'Public key\'i kopyala';

  @override
  String get sshKeyAuthorizedKeysHint =>
      'Bu satırı sunucudaki ~/.ssh/authorized_keys dosyasına ekleyin.';

  @override
  String get sshKeyEnclaveWizardTitle => 'Secure Enclave SSH key';

  @override
  String get sshKeyEnclaveWizardLabelHint => 'Key adı';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'Windows Hello SSH anahtarı';

  @override
  String get helloWizardLabelHint => 'Anahtar etiketi';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'Windows Hello ile doğrula';

  @override
  String get helloPromptDescription =>
      'PIN, parmak izi veya yüz — Windows Hello bu SSH challenge\'ını imzalar.';

  @override
  String get helloSoftwareGatedWarning =>
      'Bu cihazda TPM yok. Anahtar kullanıcı alanına düşer; Windows Hello yine her imzayı gate eder.';

  @override
  String get helloP384NotSupported =>
      'TPM firmware P-384 desteklemiyor. P-256 veya RSA-2048 seç.';

  @override
  String get helloConfigureFirst =>
      'Önce Windows Hello\'yu Ayarlar -> Oturum açma seçeneklerinde kur.';

  @override
  String get tpmSshTitle => 'TPM-backed SSH key oluştur';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (önerilen)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported =>
      'Bu TPM firmware bu algorithm\'i desteklemiyor.';

  @override
  String get tpmSshPinProtect => 'PIN ile koru';

  @override
  String get tpmSshPinLockoutWarning =>
      'Yanlış PIN denemeleri sonrası TPM key\'i kilitler.';

  @override
  String get tpmSshPinMismatch => 'PIN\'ler eşleşmiyor.';

  @override
  String get tpmSshStorageBlob => 'Wrapped key\'i app data\'da sakla';

  @override
  String get tpmSshStorageHandle => 'TPM memory slot\'unda tut';

  @override
  String get tpmSshStorageHandleHelp =>
      'Daha hızlı signing. TPM\'in persistent slot\'larından birini tüketir.';

  @override
  String get tpmSshLabel => 'Key etiketi';

  @override
  String get tpmSshImportTitle => 'TPM korumalı SSH key import et';

  @override
  String get tpmSshImportFormat => 'TPM 2.0 Key File (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return '$label için TPM PIN';
  }

  @override
  String get tpmSshPinIncorrect => 'PIN hatalı.';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM lockout cooldown\'da. $duration bekle ve tekrar dene.';
  }

  @override
  String get tpmSshGenerating => 'Key TPM\'de oluşturuluyor...';

  @override
  String get tpmSshSigning => 'TPM ile signing...';

  @override
  String get tpmSshUnavailable => 'Bu cihazda TPM bulunamadı.';

  @override
  String get tpmSshUnavailableFwDisabled => 'TPM firmware\'de devre dışı.';

  @override
  String get tpmSshUnavailableNoPermission =>
      'Uygulama TPM\'e erişemiyor. Kullanıcıyı `tss` grubuna ekle.';

  @override
  String tpmSshHandleInUse(String handle) {
    return 'Persistent slot $handle zaten kullanımda.';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      'Bu key Hello / PIN prompt\'u OLMADAN imzalar — sen logged in iken desktop\'a erişen herkes kullanabilir.';

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
  String get keystoreKeyGenerating => 'Hardware-bound key generate ediliyor...';

  @override
  String get keystoreKeyAuthPrompt => 'SSH key kullanmak için authenticate ol';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      'Key destroy edildi: yeni biometric enroll edildi. Public key\'i sunucularda yeniden register et.';

  @override
  String get keystoreKeyStrongBoxUnavailable => 'Bu cihazda StrongBox HSM yok';

  @override
  String get keystoreKeyUserAuthRequired =>
      'Her signature için biometric / device unlock iste';

  @override
  String get keystoreKeyExportDisabled => 'Hardware-bound keys export edilemez';

  @override
  String get keystoreKeyDeleteWarning =>
      'Bu key\'i silmek hardware store\'dan da çıkarır. Yeni bir tane register edene kadar sunucular reject eder.';

  @override
  String get keystoreKeyBiometricNotEnrolled =>
      'Önce biometric ya da device PIN enroll et';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (StrongBox-eligible)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+, TEE only)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (widest compatibility)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM kullanılamıyor';

  @override
  String get keystoreStrongBoxFallbackBody =>
      'Cihazın StrongBox HSM \'i expose etmiyor. Onun yerine TEE destekli bir key oluşturulsun mu? Hâlâ hardware-backed, sadece StrongBox isolation yok.';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'TEE kullan';

  @override
  String get keystoreStrongBoxFallbackCancel => 'İptal';

  @override
  String get fido2BrokerSectionTitle => 'Donanım security key';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / security key';

  @override
  String get fido2BrokerMacosLabel => 'Sistem security key diyaloğu';

  @override
  String get fido2BrokerIosLabel => 'Sistem security key (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel => 'Sistem security key (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => 'Doğrudan USB HID (CTAP2)';

  @override
  String get fido2BrokerTransportNone => 'Bu platformda kullanılamıyor';

  @override
  String get fido2BrokerPreferDirectHidTitle =>
      'Sistem diyaloğu yerine doğrudan USB HID tercih edilsin';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return 'İleri seviye: her iki yolun da çalıştığı platformlarda $brokerLabel bypass edilir. Doğrudan HID daha fazla authenticator özelliği sunar ama app bazında permission grant gerektirir.';
  }

  @override
  String get sshIntegrationSection => 'SSH entegrasyonu';

  @override
  String get fido2BrokerNoTransportSubtitle =>
      'Bu cihazda donanım anahtarı desteği mevcut değil.';

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return 'Bu cihazda yalnızca $transport mevcut; toggle devre dışı.';
  }

  @override
  String get hardwareKeyStubBadge => 'İçe aktarılmış stub';

  @override
  String get hardwareKeyStubSubtitle =>
      'Başka bir cihazdaydı — kullanmak için burada yeniden üret';

  @override
  String get hardwareKeyStubRegenerateAction => 'Burada yeniden üret';

  @override
  String get hardwareKeyStubRemoveAction => 'Stub\'ı kaldır';

  @override
  String get hardwareKeyStubPickerTooltip =>
      'Kullanmadan önce bu key\'i bu cihazda yeniden üret';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return '\"$token\" token\'ı için PKCS#11 modülünü bul';
  }

  @override
  String get arrowLeft => 'Sol ok';

  @override
  String get arrowUp => 'Yukarı ok';

  @override
  String get arrowDown => 'Aşağı ok';

  @override
  String get arrowRight => 'Sağ ok';

  @override
  String get copyMode => 'Kopyalama modu';

  @override
  String get exitCopyMode => 'Kopyalama modundan çık';

  @override
  String importedGeneric(String items) {
    return 'İçe aktarıldı: $items';
  }
}
