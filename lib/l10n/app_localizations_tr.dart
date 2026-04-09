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
  String get paste => 'Yapıştır';

  @override
  String get select => 'Seç';

  @override
  String get required => 'Gerekli';

  @override
  String get settings => 'Ayarlar';

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
  String get downloadComplete => 'İndirme tamamlandı';

  @override
  String get installNow => 'Şimdi Kur';

  @override
  String get couldNotOpenInstaller => 'Yükleyici açılamadı';

  @override
  String versionAvailable(String version) {
    return 'Sürüm $version mevcut';
  }

  @override
  String currentVersion(String version) {
    return 'Güncel: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'SSH anahtarı alındı: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return 'QR ile $count oturum içe aktarıldı';
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
  String get sessions => 'Oturumlar';

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
  String get noSessionsToExport => 'Dışa aktarılacak oturum yok';

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
  String get options => 'Seçenekler';

  @override
  String get sessionName => 'Oturum Adı';

  @override
  String get hintMyServer => 'Sunucum';

  @override
  String get hostRequired => 'Ana Bilgisayar *';

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
  String get hidePemText => 'PEM metnini gizle';

  @override
  String get pastePemKeyText => 'PEM anahtar metni yapıştır';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'Henüz ek seçenek yok';

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
  String get qrGenerationFailed => 'QR oluşturma başarısız';

  @override
  String get scanWithCameraApp =>
      'LetsFLUTssh yüklü bir cihazda\nherhangi bir kamera uygulamasıyla tarayın.';

  @override
  String get noPasswordsInQr => 'Bu QR kodunda şifre veya anahtar yok';

  @override
  String get copyLink => 'Bağlantıyı Kopyala';

  @override
  String get linkCopied => 'Bağlantı panoya kopyalandı';

  @override
  String get hostKeyChanged => 'Ana Bilgisayar Anahtarı Değişti!';

  @override
  String get unknownHost => 'Bilinmeyen Ana Bilgisayar';

  @override
  String get hostKeyChangedWarning =>
      'UYARI: Bu sunucunun ana bilgisayar anahtarı değişti. Bu, ortadaki adam saldırısına veya sunucunun yeniden kurulmasına işaret edebilir.';

  @override
  String get unknownHostMessage =>
      'Bu ana bilgisayarın kimliği doğrulanamıyor. Bağlanmaya devam etmek istediğinizden emin misiniz?';

  @override
  String get host => 'Ana Bilgisayar';

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
  String errorPrefix(String error) {
    return 'Hata: $error';
  }

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
  String get controllersNotInitialized => 'Denetleyiciler başlatılmadı';

  @override
  String get initializingSftp => 'SFTP başlatılıyor...';

  @override
  String get clearHistory => 'Geçmişi temizle';

  @override
  String get noTransfersYet => 'Henüz transfer yok';

  @override
  String get duplicateTab => 'Sekmeyi Çoğalt';

  @override
  String get duplicateTabShortcut => 'Sekmeyi Çoğalt (Ctrl+\\)';

  @override
  String get copyDown => 'Aşağı Kopyala';

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
  String get sortByName => 'Ada Göre Sırala';

  @override
  String get sortByStatus => 'Duruma Göre Sırala';

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
  String get scrollbackLines => 'Geri Kaydırma Satırları';

  @override
  String get keepAliveInterval => 'Canlı Tutma Aralığı (sn)';

  @override
  String get sshTimeout => 'SSH Zaman Aşımı (sn)';

  @override
  String get defaultPort => 'Varsayılan Port';

  @override
  String get parallelWorkers => 'Paralel İşçiler';

  @override
  String get maxHistory => 'Maks Geçmiş';

  @override
  String get calculateFolderSizes => 'Klasör Boyutlarını Hesapla';

  @override
  String get exportData => 'Veriyi Dışa Aktar';

  @override
  String get exportDataSubtitle =>
      'Oturumları, yapılandırmayı ve anahtarları şifreli .lfs dosyasına kaydet';

  @override
  String get importDataSubtitle => '.lfs dosyasından veri yükle';

  @override
  String get setMasterPasswordHint =>
      'Arşivi şifrelemek için bir ana şifre belirleyin.';

  @override
  String get passwordsDoNotMatch => 'Şifreler eşleşmiyor';

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
  String get hintLfsPath => '/path/to/export.lfs';

  @override
  String get browse => 'Gözat';

  @override
  String get shareViaQrCode => 'QR Kodu ile Paylaş';

  @override
  String get shareViaQrSubtitle =>
      'Oturumları başka bir cihazdan taranmak üzere QR koduna aktar';

  @override
  String get dataLocation => 'Veri Konumu';

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
  String get enableLogging => 'Günlükleri Etkinleştir';

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
  String get anotherInstanceRunning =>
      'LetsFLUTssh\'ın başka bir örneği zaten çalışıyor.';

  @override
  String importFailedShort(String error) {
    return 'İçe aktarma başarısız: $error';
  }

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
  String get qrNoCredentialsWarning =>
      'Şifreler ve SSH anahtarları DAHİL DEĞİLDİR.\nİçe aktarılan oturumların kimlik bilgilerinin doldurulması gerekecektir.';

  @override
  String get qrTooManyForSingleCode =>
      'Tek bir QR kodu için çok fazla oturum. Bazılarının seçimini kaldırın veya .lfs dışa aktarımını kullanın.';

  @override
  String get qrTooLarge =>
      'Çok büyük — bazı oturumların seçimini kaldırın veya .lfs dosya dışa aktarımını kullanın.';

  @override
  String get exportAll => 'Tümünü Dışa Aktar';

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
  String get errBrokenPipe => 'Boru kırıldı';

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
  String get errHostIsDown => 'Ana bilgisayar çalışmıyor';

  @override
  String get errNoRouteToHost => 'Ana bilgisayara yol bulunamadı';

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
    return '$host:$port için ana bilgisayar anahtarı reddedildi — anahtarı kabul edin veya known_hosts dosyasını kontrol edin';
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
  String errConnectionTimedOutSeconds(int seconds) {
    return '$seconds saniye sonra bağlantı zaman aşımına uğradı';
  }

  @override
  String get errSessionClosed => 'Oturum kapatıldı';

  @override
  String errShellError(String error) {
    return 'Kabuk hatası: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'Yeniden bağlanma başarısız: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'SFTP başlatılamadı: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'İndirme başarısız: $error';
  }

  @override
  String get errDecryptionFailed =>
      'Kimlik bilgileri çözülemedi. Anahtar dosyası bozulmuş olabilir.';

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
  String get storagePermissionRequired =>
      'Yerel dosyalara göz atmak için depolama izni gerekli';

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
  String get maximize => 'Büyüt';

  @override
  String get restore => 'Geri Yükle';

  @override
  String get duplicateDownShortcut => 'Aşağı Çoğalt (Ctrl+Shift+\\)';

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
}
