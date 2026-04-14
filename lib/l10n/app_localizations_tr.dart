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
  String get appSettings => 'Uygulama Ayarları';

  @override
  String get yes => 'Evet';

  @override
  String get no => 'Hayır';

  @override
  String get importWhatToImport => 'Ne içe aktarılacak:';

  @override
  String get enterMasterPasswordPrompt => 'Ana şifreyi girin:';

  @override
  String get nextStep => 'İleri';

  @override
  String get includeCredentials => 'Şifreleri ve SSH anahtarlarını dahil et';

  @override
  String get includePasswords => 'Oturum parolaları';

  @override
  String get embeddedKeys => 'Gömülü anahtarlar';

  @override
  String get managerKeys => 'Yöneticideki anahtarlar';

  @override
  String get managerKeysMayBeLarge =>
      'Yönetici anahtarları QR boyutunu aşabilir';

  @override
  String get qrPasswordWarning =>
      'Parolalar QR kodunda şifresiz olacaktır. Taranan herkes görebilir.';

  @override
  String get sshKeysMayBeLarge => 'Anahtarlar QR boyutunu aşabilir';

  @override
  String exportTotalSize(String size) {
    return 'Toplam boyut: $size';
  }

  @override
  String get qrCredentialsWarning =>
      'Şifreler ve SSH anahtarları QR kodunda GÖRÜNECEK';

  @override
  String get qrCredentialsTooLarge =>
      'Kimlik bilgileri QR kodunu çok büyük yapıyor';

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
      'Çok büyük — bazı öğelerin seçimini kaldırın veya .lfs dosya dışa aktarımını kullanın.';

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
  String get transferStartingUpload => 'Yükleme başlıyor...';

  @override
  String get transferStartingDownload => 'İndirme başlıyor...';

  @override
  String get transferCopying => 'Kopyalanıyor...';

  @override
  String get transferDone => 'Tamamlandı';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total dosya';
  }

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
  String get sshConnectionChannel => 'SSH Bağlantısı';

  @override
  String get sshConnectionChannelDesc =>
      'SSH bağlantılarını arka planda canlı tutar.';

  @override
  String get sshActive => 'SSH aktif';

  @override
  String activeConnectionCount(int count) {
    return '$count aktif bağlantı';
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
  String get knownHosts => 'Bilinen Sunucular';

  @override
  String get knownHostsSubtitle =>
      'Güvenilir SSH sunucu parmak izlerini yönetin';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bilinen sunucu',
      one: '1 bilinen sunucu',
      zero: 'Bilinen sunucu yok',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'Bilinen sunucu yok. Eklemek için bir sunucuya bağlanın.';

  @override
  String get removeHost => 'Sunucuyu kaldır';

  @override
  String removeHostConfirm(String host) {
    return '$host bilinen sunuculardan kaldırılsın mı? Sonraki bağlantıda anahtar yeniden doğrulanacak.';
  }

  @override
  String get clearAllKnownHosts => 'Tüm bilinen sunucuları temizle';

  @override
  String get clearAllKnownHostsConfirm =>
      'Tüm bilinen sunucular kaldırılsın mı? Her sunucu anahtarı yeniden doğrulanmalı.';

  @override
  String get importKnownHosts => 'Bilinen sunucuları içe aktar';

  @override
  String get importKnownHostsSubtitle =>
      'OpenSSH known_hosts dosyasından içe aktar';

  @override
  String get exportKnownHosts => 'Bilinen sunucuları dışa aktar';

  @override
  String importedHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count yeni sunucu içe aktarıldı',
      one: '1 yeni sunucu içe aktarıldı',
      zero: 'Yeni sunucu içe aktarılmadı',
    );
    return '$_temp0';
  }

  @override
  String get clearedAllHosts => 'Tüm bilinen sunucular temizlendi';

  @override
  String removedHost(String host) {
    return '$host kaldırıldı';
  }

  @override
  String get noHostsToExport => 'Dışa aktarılacak sunucu yok';

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
  String get publicKey => 'Genel anahtar';

  @override
  String get publicKeyCopied => 'Genel anahtar panoya kopyalandı';

  @override
  String get pastePrivateKey => 'Özel anahtarı yapıştır (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Geçersiz PEM anahtar verisi';

  @override
  String get selectFromKeyStore => 'Anahtar deposundan seç';

  @override
  String get noKeySelected => 'Anahtar seçilmedi';

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
  String get passphraseRequired => 'Parola gerekli';

  @override
  String passphrasePrompt(String host) {
    return '$host için SSH anahtarı şifrelenmiş. Kilidini açmak için parolayı girin.';
  }

  @override
  String get passphraseWrong => 'Yanlış parola. Lütfen tekrar deneyin.';

  @override
  String get passphrase => 'Parola';

  @override
  String get rememberPassphrase => 'Bu oturum için hatırla';

  @override
  String get unlock => 'Kilidi aç';

  @override
  String get masterPasswordSubtitle =>
      'Kayıtlı kimlik bilgilerini şifreyle koruyun';

  @override
  String get setMasterPassword => 'Ana şifre belirle';

  @override
  String get changeMasterPassword => 'Ana şifreyi değiştir';

  @override
  String get removeMasterPassword => 'Ana şifreyi kaldır';

  @override
  String get masterPasswordEnabled => 'Kimlik bilgileri ana şifreyle korunuyor';

  @override
  String get masterPasswordDisabled =>
      'Kimlik bilgileri otomatik oluşturulan anahtar kullanıyor (şifresiz)';

  @override
  String get enterMasterPassword =>
      'Kayıtlı kimlik bilgilerinize erişmek için ana şifreyi girin.';

  @override
  String get wrongMasterPassword => 'Yanlış şifre. Lütfen tekrar deneyin.';

  @override
  String get newPassword => 'Yeni şifre';

  @override
  String get currentPassword => 'Mevcut şifre';

  @override
  String get passwordTooShort => 'Şifre en az 8 karakter olmalı';

  @override
  String get masterPasswordSet => 'Ana şifre etkinleştirildi';

  @override
  String get masterPasswordChanged => 'Ana şifre değiştirildi';

  @override
  String get masterPasswordRemoved => 'Ana şifre kaldırıldı';

  @override
  String get masterPasswordWarning =>
      'Bu şifreyi unutursanız, tüm kayıtlı şifreler ve SSH anahtarları kaybolacak. Kurtarma mümkün değil.';

  @override
  String get forgotPassword => 'Şifrenizi mi unuttunuz?';

  @override
  String get forgotPasswordWarning =>
      'Bu işlem TÜM kayıtlı şifreleri, SSH anahtarlarını ve parolaları silecek. Oturumlar ve ayarlar korunacak. Bu işlem geri alınamaz.';

  @override
  String get resetAndDeleteCredentials => 'Sıfırla ve verileri sil';

  @override
  String get credentialsReset => 'Tüm kayıtlı kimlik bilgileri silindi';

  @override
  String get derivingKey => 'Şifreleme anahtarı türetiliyor...';

  @override
  String get reEncrypting => 'Veriler yeniden şifreleniyor...';

  @override
  String get confirmRemoveMasterPassword =>
      'Ana şifre korumasını kaldırmak için mevcut şifrenizi girin. Kimlik bilgileri otomatik anahtarla yeniden şifrelenecek.';

  @override
  String get securitySetupTitle => 'Güvenlik ayarları';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'Sistem anahtar zinciri algılandı ($keychainName). Verileriniz sistem anahtar zinciri kullanılarak otomatik şifrelenecek.';
  }

  @override
  String get securitySetupKeychainOptional =>
      'Ek koruma için ana şifre de belirleyebilirsiniz.';

  @override
  String get securitySetupNoKeychain =>
      'Sistem anahtar zinciri algılanmadı. Anahtar zinciri olmadan oturum verileriniz (sunucular, şifreler, anahtarlar) düz metin olarak saklanacak.';

  @override
  String get securitySetupNoKeychainHint =>
      'WSL, grafik arayüzsüz Linux veya minimal kurulumlar için normaldir. Linux\'ta anahtar zincirini etkinleştirmek için: libsecret ve bir anahtar zinciri arka plan hizmeti (örn. gnome-keyring) yükleyin.';

  @override
  String get securitySetupRecommendMasterPassword =>
      'Verilerinizi korumak için ana şifre belirlemenizi öneriyoruz.';

  @override
  String get continueWithKeychain => 'Anahtar zinciriyle devam et';

  @override
  String get continueWithoutEncryption => 'Şifreleme olmadan devam et';

  @override
  String get securityLevel => 'Güvenlik düzeyi';

  @override
  String get securityLevelPlaintext => 'Yok (düz metin)';

  @override
  String get securityLevelKeychain => 'Sistem anahtar zinciri';

  @override
  String get securityLevelMasterPassword => 'Ana şifre';

  @override
  String get keychainStatus => 'Anahtar zinciri';

  @override
  String keychainAvailable(String name) {
    return 'Kullanılabilir ($name)';
  }

  @override
  String get keychainNotAvailable => 'Kullanılamaz';

  @override
  String get enableKeychain => 'Anahtar zinciri şifrelemesini etkinleştir';

  @override
  String get enableKeychainSubtitle =>
      'Sistem anahtar zincirini kullanarak saklanan verileri yeniden şifrele';

  @override
  String get keychainEnabled => 'Anahtar zinciri şifrelemesi etkinleştirildi';

  @override
  String get manageMasterPassword => 'Ana şifreyi yönet';

  @override
  String get manageMasterPasswordSubtitle =>
      'Ana şifreyi belirle, değiştir veya kaldır';

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

  @override
  String get tags => 'Tags';

  @override
  String get tagsSubtitle => 'Organize sessions and folders with color tags';

  @override
  String get noTags => 'No tags yet';

  @override
  String get addTag => 'Add Tag';

  @override
  String get deleteTag => 'Delete Tag';

  @override
  String deleteTagConfirm(String name) {
    return 'Delete tag \"$name\"? It will be removed from all sessions and folders.';
  }

  @override
  String get tagName => 'Tag Name';

  @override
  String get tagNameHint => 'e.g. Production, Staging';

  @override
  String get tagColor => 'Color';

  @override
  String get tagCreated => 'Tag created';

  @override
  String tagDeleted(String name) {
    return 'Tag \"$name\" deleted';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags',
      one: '1 tag',
      zero: 'No tags',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'Manage Tags';

  @override
  String get editTags => 'Edit Tags';

  @override
  String get fullBackup => 'Tam yedekleme';

  @override
  String get sessionsOnly => 'Oturumlar';

  @override
  String get sessionKeysFromManager => 'Yöneticiden oturum anahtarları';

  @override
  String get allKeysFromManager => 'Yöneticiden tüm anahtarlar';

  @override
  String exportTags(int count) {
    return 'Etiketler ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'Kod parçacıkları ($count)';
  }

  @override
  String get disableKeychain =>
      'Anahtar zinciri şifrelemesini devre dışı bırak';

  @override
  String get disableKeychainSubtitle => 'Düz metin depolamaya geç (önerilmez)';

  @override
  String get disableKeychainConfirm =>
      'Veritabanı anahtarsız olarak yeniden şifrelenecek. Oturumlar ve anahtarlar diskte düz metin olarak saklanacak. Devam edilsin mi?';

  @override
  String get keychainDisabled =>
      'Anahtar zinciri şifrelemesi devre dışı bırakıldı';
}
