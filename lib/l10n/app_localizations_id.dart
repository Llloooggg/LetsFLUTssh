// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class SId extends S {
  SId([String locale = 'id']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'OK';

  @override
  String get infoDialogProtectsHeader => 'Melindungi dari';

  @override
  String get infoDialogDoesNotProtectHeader => 'Tidak melindungi dari';

  @override
  String get cancel => 'Batal';

  @override
  String get close => 'Tutup';

  @override
  String get delete => 'Hapus';

  @override
  String get save => 'Simpan';

  @override
  String get connect => 'Hubungkan';

  @override
  String get retry => 'Coba Lagi';

  @override
  String get import_ => 'Impor';

  @override
  String get export_ => 'Ekspor';

  @override
  String get rename => 'Ganti Nama';

  @override
  String get create => 'Buat';

  @override
  String get back => 'Kembali';

  @override
  String get copy => 'Salin';

  @override
  String get cut => 'Potong';

  @override
  String get paste => 'Tempel';

  @override
  String get select => 'Pilih';

  @override
  String get copyModeTapToStart => 'Sentuh untuk menandai awal pilihan';

  @override
  String get copyModeExtending => 'Seret untuk memperluas pilihan';

  @override
  String get copyModeSetAnchor => 'Tetapkan jangkar';

  @override
  String get copyModeCopySelection => 'Salin pilihan';

  @override
  String get required => 'Wajib';

  @override
  String get errFillRequiredFields => 'Isi field wajib yang ditandai *';

  @override
  String get settings => 'Pengaturan';

  @override
  String get appSettings => 'Pengaturan Aplikasi';

  @override
  String get yes => 'Ya';

  @override
  String get no => 'Tidak';

  @override
  String get importWhatToImport => 'Apa yang akan diimpor:';

  @override
  String get exportWhatToExport => 'Apa yang akan diekspor:';

  @override
  String get enterMasterPasswordPrompt => 'Masukkan kata sandi utama:';

  @override
  String get nextStep => 'Berikutnya';

  @override
  String get includePasswords => 'Kata sandi sesi';

  @override
  String get embeddedKeys => 'Kunci tertanam';

  @override
  String get managerKeys => 'Kunci dari pengelola';

  @override
  String get managerKeysMayBeLarge =>
      'Kunci pengelola dapat melebihi ukuran QR';

  @override
  String get qrPasswordWarning =>
      'Kunci SSH dinonaktifkan secara default saat ekspor.';

  @override
  String get sshKeysMayBeLarge => 'Kunci dapat melebihi ukuran QR';

  @override
  String exportTotalSize(String size) {
    return 'Ukuran total: $size';
  }

  @override
  String get terminal => 'Terminal';

  @override
  String get files => 'File';

  @override
  String get transfer => 'Transfer';

  @override
  String get open => 'Buka';

  @override
  String get search => 'Cari...';

  @override
  String get noResults => 'Tidak ada hasil';

  @override
  String get filter => 'Filter...';

  @override
  String get merge => 'Gabungkan';

  @override
  String get replace => 'Ganti';

  @override
  String get reconnect => 'Hubungkan Ulang';

  @override
  String get updateAvailable => 'Pembaruan Tersedia';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'Versi $version tersedia (saat ini: v$current).';
  }

  @override
  String get releaseNotes => 'Catatan rilis:';

  @override
  String get skipThisVersion => 'Lewati Versi Ini';

  @override
  String get unskip => 'Batalkan Lewati';

  @override
  String get downloadAndInstall => 'Unduh & Pasang';

  @override
  String get openInBrowser => 'Buka di Browser';

  @override
  String get couldNotOpenBrowser =>
      'Tidak dapat membuka browser — URL disalin ke clipboard';

  @override
  String get checkForUpdates => 'Periksa Pembaruan';

  @override
  String get checkNow => 'Periksa sekarang';

  @override
  String get checkForUpdatesOnStartup => 'Periksa Pembaruan Saat Memulai';

  @override
  String get checking => 'Memeriksa...';

  @override
  String get youreUpToDate => 'Anda sudah menggunakan versi terbaru';

  @override
  String get updateCheckFailed => 'Pemeriksaan pembaruan gagal';

  @override
  String get unknownError => 'Kesalahan tidak diketahui';

  @override
  String downloadingPercent(int percent) {
    return 'Mengunduh... $percent%';
  }

  @override
  String get updateVerifying => 'Memverifikasi…';

  @override
  String get downloadComplete => 'Unduhan selesai';

  @override
  String get installNow => 'Pasang Sekarang';

  @override
  String get openReleasePage => 'Buka Halaman Rilis';

  @override
  String get couldNotOpenInstaller => 'Tidak dapat membuka penginstal';

  @override
  String get installerFailedOpenedReleasePage =>
      'Peluncuran penginstal gagal; halaman rilis dibuka di browser';

  @override
  String versionAvailable(String version) {
    return 'Versi $version tersedia';
  }

  @override
  String currentVersion(String version) {
    return 'Saat ini: v$version';
  }

  @override
  String importedSessions(int count) {
    return '$count sesi diimpor';
  }

  @override
  String importFailed(String error) {
    return 'Impor gagal: $error';
  }

  @override
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count asosiasi dilewati (target hilang)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesi rusak dilewati',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'Sesi';

  @override
  String get emptyFolders => 'Folder kosong';

  @override
  String get sessionsHeader => 'SESI';

  @override
  String get savedSessions => 'Sesi tersimpan';

  @override
  String get activeConnections => 'Koneksi aktif';

  @override
  String get openTabs => 'Tab terbuka';

  @override
  String get noSavedSessions => 'Tidak ada sesi tersimpan';

  @override
  String get addSession => 'Tambah Sesi';

  @override
  String get noSessions => 'Tidak ada sesi';

  @override
  String nSelectedCount(int count) {
    return '$count dipilih';
  }

  @override
  String get selectAll => 'Pilih Semua';

  @override
  String get deselectAll => 'Batal Pilih Semua';

  @override
  String get moveTo => 'Pindahkan ke...';

  @override
  String get moveToFolder => 'Pindahkan ke Folder';

  @override
  String get rootFolder => '/ (root)';

  @override
  String get newFolder => 'Folder Baru';

  @override
  String get newConnection => 'Koneksi Baru';

  @override
  String get editConnection => 'Edit Koneksi';

  @override
  String get duplicate => 'Duplikat';

  @override
  String get deleteSession => 'Hapus Sesi';

  @override
  String get renameFolder => 'Ganti Nama Folder';

  @override
  String get deleteFolder => 'Hapus Folder';

  @override
  String get deleteSelected => 'Hapus yang Dipilih';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return 'Hapus $parts?\n\nTindakan ini tidak dapat dibatalkan.';
  }

  @override
  String nSessions(int count) {
    return '$count sesi';
  }

  @override
  String nFolders(int count) {
    return '$count folder';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'Hapus folder \"$name\"?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return '$count sesi di dalamnya juga akan dihapus.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return 'Hapus \"$name\"?';
  }

  @override
  String get connection => 'Koneksi';

  @override
  String get auth => 'Autentikasi';

  @override
  String get sectionAuthentication => 'Autentikasi';

  @override
  String get sectionAdvanced => 'Lanjutan';

  @override
  String get moreOptions => 'Opsi lainnya';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString aturan port forwarding',
      zero: 'Tidak ada aturan port forwarding',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => 'Kelola…';

  @override
  String get authMethodAgent => 'Pakai ssh-agent sistem';

  @override
  String get options => 'Opsi';

  @override
  String get sessionName => 'Nama Sesi';

  @override
  String get sessionNameAutoFromHost => 'Auto dari host';

  @override
  String get sessionNameAutoFromUrl => 'Auto dari host URL';

  @override
  String get sessionNameAutoFromBucket => 'Auto dari bucket default';

  @override
  String get hintMyServer => 'Server Saya';

  @override
  String get hostRequired => 'Host *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'Port';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'Nama Pengguna *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'Kata Sandi';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'Frasa Sandi Kunci';

  @override
  String get hintOptional => 'Opsional';

  @override
  String get savedTypeToChange => 'Tersimpan — ketik untuk mengubah';

  @override
  String get hidePemText => 'Sembunyikan teks PEM';

  @override
  String get pastePemKeyText => 'Tempel teks kunci PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get saveAndConnect => 'Simpan & Hubungkan';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst =>
      'Sediakan file kunci atau teks PEM terlebih dahulu';

  @override
  String get keyTextPem => 'Teks Kunci (PEM)';

  @override
  String get selectKeyFile => 'Pilih File Kunci';

  @override
  String get clearKeyFile => 'Hapus file kunci';

  @override
  String get authOrDivider => 'ATAU';

  @override
  String get providePasswordOrKey => 'Sediakan kata sandi atau kunci SSH';

  @override
  String get quickConnect => 'Hubungkan Cepat';

  @override
  String get scanQrCode => 'Pindai Kode QR';

  @override
  String get emptyFolder => 'Folder kosong';

  @override
  String get qrGenerationFailed => 'Pembuatan QR gagal';

  @override
  String get scanWithCameraApp =>
      'Pindai dengan aplikasi kamera di perangkat\nyang telah memasang LetsFLUTssh.';

  @override
  String get noPasswordsInQr =>
      'Tidak ada kata sandi atau kunci dalam kode QR ini';

  @override
  String get qrContainsCredentialsWarning =>
      'Kode QR ini berisi kredensial. Jaga privasi layar.';

  @override
  String get copyLink => 'Salin Tautan';

  @override
  String get linkCopied => 'Tautan disalin ke clipboard';

  @override
  String get hostKeyChanged => 'Kunci Host Berubah!';

  @override
  String get unknownHost => 'Host Tidak Dikenal';

  @override
  String get hostKeyChangedWarning =>
      'PERINGATAN: Kunci host untuk server ini telah berubah. Ini bisa menandakan serangan man-in-the-middle, atau server mungkin telah diinstal ulang.';

  @override
  String get unknownHostMessage =>
      'Keaslian host ini tidak dapat diverifikasi. Apakah Anda yakin ingin melanjutkan koneksi?';

  @override
  String get host => 'Host';

  @override
  String get keyType => 'Tipe kunci';

  @override
  String get fingerprint => 'Sidik jari';

  @override
  String get fingerprintCopied => 'Sidik jari disalin';

  @override
  String get copyFingerprint => 'Salin sidik jari';

  @override
  String get acceptAnyway => 'Tetap Terima';

  @override
  String get accept => 'Terima';

  @override
  String get importData => 'Impor Data';

  @override
  String get masterPassword => 'Kata Sandi Utama';

  @override
  String get confirmPassword => 'Konfirmasi Kata Sandi';

  @override
  String get importModeMergeDescription =>
      'Tambahkan sesi baru, pertahankan yang ada';

  @override
  String get importModeReplaceDescription =>
      'Ganti semua sesi dengan yang diimpor';

  @override
  String get folderName => 'Nama folder';

  @override
  String get newName => 'Nama baru';

  @override
  String deleteItems(String names) {
    return 'Hapus $names?';
  }

  @override
  String deleteNItems(int count) {
    return 'Hapus $count item';
  }

  @override
  String deletedItem(String name) {
    return '$name dihapus';
  }

  @override
  String deletedNItems(int count) {
    return '$count item dihapus';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'Gagal membuat folder: $error';
  }

  @override
  String failedToRename(String error) {
    return 'Gagal mengganti nama: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return 'Gagal menghapus $name: $error';
  }

  @override
  String get editPath => 'Edit Jalur';

  @override
  String get root => 'Root';

  @override
  String get controllersNotInitialized => 'Controller belum diinisialisasi';

  @override
  String get clearHistory => 'Hapus riwayat';

  @override
  String get noTransfersYet => 'Belum ada transfer';

  @override
  String get duplicateTab => 'Duplikat Tab';

  @override
  String get duplicateTabShortcut => 'Duplikat Tab (Ctrl+\\)';

  @override
  String get previous => 'Sebelumnya';

  @override
  String get next => 'Berikutnya';

  @override
  String get closeEsc => 'Tutup (Esc)';

  @override
  String get closeAll => 'Tutup Semua';

  @override
  String get closeOthers => 'Tutup Lainnya';

  @override
  String get closeTabsToTheLeft => 'Tutup Tab di Kiri';

  @override
  String get closeTabsToTheRight => 'Tutup Tab di Kanan';

  @override
  String get noActiveSession => 'Tidak ada sesi aktif';

  @override
  String get createConnectionHint =>
      'Buat koneksi baru atau pilih dari sidebar';

  @override
  String get hideSidebar => 'Sembunyikan Sidebar (Ctrl+B)';

  @override
  String get showSidebar => 'Tampilkan Sidebar (Ctrl+B)';

  @override
  String get language => 'Bahasa';

  @override
  String get languageSystemDefault => 'Otomatis';

  @override
  String get theme => 'Tema';

  @override
  String get themeDark => 'Gelap';

  @override
  String get themeLight => 'Terang';

  @override
  String get themeSystem => 'Sistem';

  @override
  String get appearance => 'Tampilan';

  @override
  String get connectionSection => 'Koneksi';

  @override
  String get transfers => 'Transfer';

  @override
  String get data => 'Data';

  @override
  String get logging => 'Log';

  @override
  String get updates => 'Pembaruan';

  @override
  String get about => 'Tentang';

  @override
  String get resetToDefaults => 'Atur Ulang ke Default';

  @override
  String get uiScale => 'Skala Antarmuka';

  @override
  String get terminalFontSize => 'Ukuran Font Terminal';

  @override
  String get scrollbackLines => 'Baris Gulir Balik';

  @override
  String get keepAliveInterval => 'Interval Keep-Alive (detik)';

  @override
  String get sshTimeout => 'Batas Waktu SSH (detik)';

  @override
  String get defaultPort => 'Port Default';

  @override
  String get parallelWorkers => 'Worker Paralel';

  @override
  String get maxHistory => 'Riwayat Maksimal';

  @override
  String get calculateFolderSizes => 'Hitung Ukuran Folder';

  @override
  String get verboseConnectionLog => 'Log koneksi verbose';

  @override
  String get verboseConnectionLogSubtitle =>
      'Catat seluruh trace handshake SSH dan autentikasi ke file log (untuk mendiagnosis kegagalan koneksi)';

  @override
  String get exportData => 'Ekspor Data';

  @override
  String get exportRecordings => 'Rekaman Sesi';

  @override
  String sshConfigPreviewHostsFound(int count) {
    return '$count host ditemukan';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'Tidak ada host yang dapat diimpor di file ini.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'Tidak dapat membaca file kunci untuk: $hosts. Host ini akan diimpor tanpa kredensial.';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'Ekspor arsip';

  @override
  String get exportArchiveSubtitle =>
      'Simpan sesi, konfigurasi, dan kunci ke file .lfs terenkripsi';

  @override
  String get exportQrCode => 'Ekspor kode QR';

  @override
  String get exportQrCodeSubtitle =>
      'Bagikan sesi dan kunci terpilih melalui kode QR';

  @override
  String get importArchive => 'Impor arsip';

  @override
  String get importArchiveSubtitle => 'Muat data dari file .lfs';

  @override
  String get importFromSshDir => 'Impor dari ~/.ssh';

  @override
  String get importFromSshDirSubtitle =>
      'Pilih host dari berkas konfigurasi dan/atau kunci privat dari ~/.ssh';

  @override
  String get sshDirImportHostsSection => 'Host dari berkas konfigurasi';

  @override
  String get sshDirImportKeysSection => 'Kunci di ~/.ssh';

  @override
  String importSshKeysFound(int count) {
    return '$count kunci ditemukan — pilih mana yang akan diimpor';
  }

  @override
  String get importSshKeysNoneFound =>
      'Tidak ada kunci privat yang ditemukan di ~/.ssh.';

  @override
  String get sshKeyAlreadyImported => 'sudah ada di penyimpanan';

  @override
  String get setMasterPasswordHint =>
      'Atur kata sandi utama untuk mengenkripsi arsip.';

  @override
  String get passwordsDoNotMatch => 'Kata sandi tidak cocok';

  @override
  String get passwordStrengthWeak => 'Lemah';

  @override
  String get passwordStrengthModerate => 'Sedang';

  @override
  String get passwordStrengthStrong => 'Kuat';

  @override
  String get passwordStrengthVeryStrong => 'Sangat kuat';

  @override
  String get tierPlaintextLabel => 'Teks biasa';

  @override
  String get tierPlaintextSubtitle => 'Tanpa enkripsi — hanya izin file';

  @override
  String get tierKeychainLabel => 'Keychain';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'Kunci ada di $keychain — buka otomatis saat peluncuran';
  }

  @override
  String get tierKeychainUnavailable =>
      'Keychain OS tidak tersedia pada instalasi ini.';

  @override
  String get tierHardwareLabel => 'Hardware';

  @override
  String get tierParanoidLabel => 'Kata sandi utama (Paranoid)';

  @override
  String get tierHardwareUnavailable =>
      'Hardware vault tidak tersedia pada instalasi ini.';

  @override
  String get pinLabel => 'Kata sandi';

  @override
  String get l2UnlockTitle => 'Kata sandi diperlukan';

  @override
  String get l2UnlockHint =>
      'Masukkan kata sandi pendek Anda untuk melanjutkan';

  @override
  String get l2WrongPassword => 'Kata sandi salah';

  @override
  String get l3UnlockTitle => 'Masukkan kata sandi';

  @override
  String get l3UnlockHint => 'Kata sandi membuka hardware vault';

  @override
  String get l3WrongPin => 'Kata sandi salah';

  @override
  String tierCooldownHint(int seconds) {
    return 'Coba lagi dalam $seconds dtk';
  }

  @override
  String exportedTo(String path) {
    return 'Diekspor ke: $path';
  }

  @override
  String exportFailed(String error) {
    return 'Ekspor gagal: $error';
  }

  @override
  String get pathToLfsFile => 'Jalur file .lfs';

  @override
  String get dataLocation => 'Lokasi Data';

  @override
  String get dataStorageSection => 'Penyimpanan';

  @override
  String get pathCopied => 'Jalur disalin ke clipboard';

  @override
  String get urlCopied => 'URL disalin ke clipboard';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — Klien SSH/SFTP';
  }

  @override
  String get sourceCode => 'Kode Sumber';

  @override
  String get logIsEmpty => 'Log kosong';

  @override
  String logExportedTo(String path) {
    return 'Log diekspor ke: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Ekspor log gagal: $error';
  }

  @override
  String get logsCleared => 'Log dihapus';

  @override
  String get copiedToClipboard => 'Disalin ke clipboard';

  @override
  String get copyLog => 'Salin log';

  @override
  String get exportLog => 'Ekspor log';

  @override
  String get clearLogs => 'Hapus log';

  @override
  String get local => 'Lokal';

  @override
  String get remote => 'Remote';

  @override
  String get pickFolder => 'Pilih Folder';

  @override
  String get refresh => 'Segarkan';

  @override
  String get up => 'Atas';

  @override
  String get emptyDirectory => 'Direktori kosong';

  @override
  String get cancelSelection => 'Batalkan pilihan';

  @override
  String get openSftpBrowser => 'Buka Browser SFTP';

  @override
  String get openSshTerminal => 'Buka Terminal SSH';

  @override
  String get noActiveFileBrowsers => 'Tidak ada browser file aktif';

  @override
  String get useSftpFromSessions => 'Gunakan \"SFTP\" dari Sesi';

  @override
  String get saveLogAs => 'Simpan log sebagai';

  @override
  String get chooseSaveLocation => 'Pilih lokasi penyimpanan';

  @override
  String get forward => 'Maju';

  @override
  String get name => 'Nama';

  @override
  String get size => 'Ukuran';

  @override
  String get modified => 'Diubah';

  @override
  String get mode => 'Mode';

  @override
  String get owner => 'Pemilik';

  @override
  String get connectionError => 'Kesalahan koneksi';

  @override
  String get resizeWindowToViewFiles =>
      'Ubah ukuran jendela untuk melihat file';

  @override
  String get completed => 'Selesai';

  @override
  String get connected => 'Terhubung';

  @override
  String get disconnected => 'Terputus';

  @override
  String a11yConnectingTo(String host) {
    return 'Menghubungkan ke $host';
  }

  @override
  String a11yConnectedTo(String host) {
    return 'Terhubung ke $host';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return 'Terputus dari $host';
  }

  @override
  String a11yConnectionFailed(String host) {
    return 'Gagal terhubung ke $host';
  }

  @override
  String get exit => 'Keluar';

  @override
  String get exitConfirmation => 'Sesi aktif akan terputus. Keluar?';

  @override
  String get hintFolderExample => 'contoh: Production';

  @override
  String get credentialsNotSet => 'Kredensial belum diatur';

  @override
  String get exportSessionsViaQr => 'Ekspor Sesi via QR';

  @override
  String get qrTooManyForSingleCode =>
      'Terlalu banyak sesi untuk satu kode QR. Batalkan beberapa pilihan atau gunakan ekspor .lfs.';

  @override
  String get qrTooLarge =>
      'Terlalu besar — batalkan beberapa item atau gunakan ekspor file .lfs.';

  @override
  String get showQr => 'Tampilkan QR';

  @override
  String get sort => 'Urutkan';

  @override
  String get resizePanelDivider => 'Ubah ukuran pembagi panel';

  @override
  String get youreRunningLatest => 'Anda menggunakan versi terbaru';

  @override
  String get liveLog => 'Log Langsung';

  @override
  String get archivedLog => 'Log terarsip';

  @override
  String get loggingLevel => 'Level log';

  @override
  String get loggingLevelSubtitleInfo => 'Entri rutin + warning + error';

  @override
  String get loggingLevelSubtitleWarn => 'Hanya path degraded dan error';

  @override
  String get loggingLevelSubtitleError => 'Hanya error';

  @override
  String get loggingLevelSubtitleOff => 'Log rutin tidak ditulis';

  @override
  String transferNItems(int count) {
    return 'Transfer $count item';
  }

  @override
  String get time => 'Waktu';

  @override
  String get failed => 'Gagal';

  @override
  String get errOperationNotPermitted => 'Operasi tidak diizinkan';

  @override
  String get errNoSuchFileOrDirectory => 'File atau direktori tidak ditemukan';

  @override
  String get errNoSuchProcess => 'Proses tidak ditemukan';

  @override
  String get errIoError => 'Kesalahan I/O';

  @override
  String get errBadFileDescriptor => 'File descriptor tidak valid';

  @override
  String get errResourceTemporarilyUnavailable =>
      'Sumber daya sementara tidak tersedia';

  @override
  String get errOutOfMemory => 'Kehabisan memori';

  @override
  String get errPermissionDenied => 'Izin ditolak';

  @override
  String get errFileExists => 'File sudah ada';

  @override
  String get errNotADirectory => 'Bukan direktori';

  @override
  String get errIsADirectory => 'Target adalah direktori';

  @override
  String get errInvalidArgument => 'Argumen tidak valid';

  @override
  String get errTooManyOpenFiles => 'Terlalu banyak file terbuka';

  @override
  String get errNoSpaceLeftOnDevice => 'Tidak ada ruang tersisa di perangkat';

  @override
  String get errReadOnlyFileSystem => 'Sistem file hanya-baca';

  @override
  String get errBrokenPipe => 'Broken pipe';

  @override
  String get errFileNameTooLong => 'Nama file terlalu panjang';

  @override
  String get errDirectoryNotEmpty => 'Direktori tidak kosong';

  @override
  String get errAddressAlreadyInUse => 'Alamat sudah digunakan';

  @override
  String get errCannotAssignAddress =>
      'Tidak dapat menetapkan alamat yang diminta';

  @override
  String get errNetworkIsDown => 'Jaringan tidak aktif';

  @override
  String get errNetworkIsUnreachable => 'Jaringan tidak dapat dijangkau';

  @override
  String get errConnectionResetByPeer => 'Koneksi direset oleh peer';

  @override
  String get errConnectionTimedOut => 'Koneksi habis waktu';

  @override
  String get errConnectionRefused => 'Koneksi ditolak';

  @override
  String get errHostIsDown => 'Host tidak aktif';

  @override
  String get errNoRouteToHost => 'Tidak ada rute ke host';

  @override
  String get errConnectionAborted => 'Koneksi dibatalkan';

  @override
  String get errAlreadyConnected => 'Sudah terhubung';

  @override
  String get errNotConnected => 'Tidak terhubung';

  @override
  String errSshConnectFailed(String host, int port) {
    return 'Gagal menghubungkan ke $host:$port';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return 'Autentikasi gagal untuk $user@$host';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return 'Koneksi gagal ke $host:$port';
  }

  @override
  String get errSshAuthAborted => 'Autentikasi dibatalkan';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return 'Kunci host ditolak untuk $host:$port — terima kunci host atau periksa known_hosts';
  }

  @override
  String get errSshOpenShellFailed => 'Gagal membuka shell';

  @override
  String get errSshLoadKeyFileFailed => 'Gagal memuat file kunci SSH';

  @override
  String get errSshParseKeyFailed => 'Gagal mengurai data kunci PEM';

  @override
  String get errSshConnectionDisposed => 'Koneksi telah dibuang';

  @override
  String get errSshNotConnected => 'Tidak terhubung';

  @override
  String get errConnectionFailed => 'Koneksi gagal';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'Koneksi habis waktu setelah $seconds detik';
  }

  @override
  String get errSessionClosed => 'Sesi ditutup';

  @override
  String errSftpInitFailed(String error) {
    return 'Gagal menginisialisasi SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Unduhan gagal: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'Pemilih folder sistem tidak tersedia. Coba lokasi lain atau periksa izin penyimpanan aplikasi.';

  @override
  String get biometricUnlockPrompt => 'Buka kunci LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'Buka kunci dengan biometrik';

  @override
  String get biometricUnlockSubtitle =>
      'Tidak perlu mengetik kata sandi — buka kunci dengan sensor biometrik perangkat.';

  @override
  String get biometricEnableFailed =>
      'Tidak dapat mengaktifkan buka kunci biometrik.';

  @override
  String get biometricUnlockFailed =>
      'Buka kunci biometrik gagal. Masukkan kata sandi utama Anda.';

  @override
  String get biometricUnlockCancelled => 'Buka kunci biometrik dibatalkan.';

  @override
  String get biometricNotEnrolled =>
      'Tidak ada kredensial biometrik yang terdaftar di perangkat ini.';

  @override
  String get biometricSensorNotAvailable =>
      'Perangkat ini tidak memiliki sensor biometrik.';

  @override
  String get biometricSystemServiceMissing =>
      'Layanan sidik jari (fprintd) belum terpasang. Lihat README → Installation.';

  @override
  String get currentPasswordIncorrect => 'Kata sandi saat ini salah';

  @override
  String get wrongPassword => 'Kata sandi salah';

  @override
  String get lockScreenTitle => 'LetsFLUTssh terkunci';

  @override
  String get lockScreenSubtitle =>
      'Masukkan kata sandi utama atau gunakan biometrik untuk melanjutkan.';

  @override
  String get unlock => 'Buka kunci';

  @override
  String get autoLockTitle => 'Kunci otomatis setelah tidak aktif';

  @override
  String get autoLockSubtitle =>
      'Mengunci UI setelah tidak aktif selama durasi ini. Kunci basis data dihapus dan penyimpanan terenkripsi ditutup pada setiap penguncian; sesi aktif tetap tersambung melalui cache kredensial per sesi yang dibersihkan saat sesi ditutup.';

  @override
  String get autoLockOff => 'Mati';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes menit',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'Pembaruan ditolak: file yang diunduh tidak ditandatangani dengan kunci rilis yang disematkan di aplikasi. Ini dapat berarti unduhan telah diubah saat transit, atau rilis saat ini memang bukan untuk instalasi ini. JANGAN instal — instal ulang secara manual dari halaman Rilis resmi.';

  @override
  String get errReleaseManifestUnavailable =>
      'Manifest release tidak bisa diambil. Kemungkinan masalah jaringan, atau release masih sedang di-publish. Coba lagi dalam beberapa menit.';

  @override
  String get updateSecurityWarningTitle => 'Verifikasi pembaruan gagal';

  @override
  String get updateReinstallAction => 'Buka halaman Rilis';

  @override
  String get errLfsNotArchive => 'Berkas yang dipilih bukan arsip LetsFLUTssh.';

  @override
  String get errLfsDecryptFailed =>
      'Kata sandi utama salah atau arsip .lfs rusak';

  @override
  String get errLfsArchiveTruncated =>
      'Arsip tidak lengkap. Unduh ulang atau ekspor ulang dari perangkat asal.';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'Arsip terlalu besar ($sizeMb MB). Batasnya adalah $limitMb MB — dibatalkan sebelum dekripsi untuk melindungi memori.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'Entri known_hosts terlalu besar ($sizeMb MB). Batasnya adalah $limitMb MB — dibatalkan agar impor tetap responsif.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'Impor gagal — data Anda telah dipulihkan ke kondisi sebelum impor. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'Arsip menggunakan skema v$found, tetapi build ini hanya mendukung hingga v$supported. Perbarui aplikasi untuk mengimpornya.';
  }

  @override
  String get progressReadingArchive => 'Membaca arsip…';

  @override
  String get progressDecrypting => 'Mendekripsi…';

  @override
  String get progressCollectingData => 'Mengumpulkan data…';

  @override
  String get progressEncrypting => 'Mengenkripsi…';

  @override
  String get progressWritingArchive => 'Menulis arsip…';

  @override
  String get progressWorking => 'Memproses…';

  @override
  String get importFromLink => 'Impor dari tautan QR';

  @override
  String get importFromLinkSubtitle =>
      'Tempel deep-link letsflutssh:// yang disalin dari perangkat lain';

  @override
  String get pasteImportLinkTitle => 'Tempel tautan impor';

  @override
  String get pasteImportLinkDescription =>
      'Tempel tautan letsflutssh://import?d=… (atau payload mentah) yang dihasilkan pada perangkat lain. Tidak perlu kamera.';

  @override
  String get pasteFromClipboard => 'Tempel dari clipboard';

  @override
  String get invalidImportLink =>
      'Tautan tidak berisi payload LetsFLUTssh yang valid';

  @override
  String get importAction => 'Impor';

  @override
  String get noTagsAvailable => 'Belum ada tag — buat satu di Tools → Tags.';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'Login';

  @override
  String get protocol => 'Protokol';

  @override
  String get typeLabel => 'Tipe';

  @override
  String get folder => 'Folder';

  @override
  String nSubitems(int count) {
    return '$count item';
  }

  @override
  String get subitems => 'Item';

  @override
  String get grantPermission => 'Berikan izin';

  @override
  String get storagePermissionLimited =>
      'Akses terbatas — berikan izin penyimpanan penuh untuk semua file';

  @override
  String progressConnecting(String host, int port) {
    return 'Menghubungkan ke $host:$port';
  }

  @override
  String get progressVerifyingHostKey => 'Memverifikasi kunci host';

  @override
  String progressAuthenticating(String user) {
    return 'Mengautentikasi sebagai $user';
  }

  @override
  String get progressOpeningShell => 'Membuka shell';

  @override
  String get progressOpeningSftp => 'Membuka saluran SFTP';

  @override
  String get transfersLabel => 'Transfer:';

  @override
  String transferCountActive(int count) {
    return '$count aktif';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count dalam antrean';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count dalam riwayat';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'Dibuat: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'Dimulai: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'Selesai: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'Durasi: $duration';
  }

  @override
  String get transferStatusQueued => 'Dalam antrean';

  @override
  String get fileConflictTitle => 'File sudah ada';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" sudah ada di $targetDir. Apa yang ingin Anda lakukan?';
  }

  @override
  String get fileConflictSkip => 'Lewati';

  @override
  String get fileConflictKeepBoth => 'Simpan keduanya';

  @override
  String get fileConflictReplace => 'Ganti';

  @override
  String get fileConflictApplyAll => 'Terapkan ke semua yang tersisa';

  @override
  String get folderNameLabel => 'NAMA FOLDER';

  @override
  String folderAlreadyExists(String name) {
    return 'Folder \"$name\" sudah ada';
  }

  @override
  String get dropKeyFileHere => 'Letakkan file kunci di sini';

  @override
  String get sessionNoCredentials =>
      'Sesi tidak memiliki kredensial — edit untuk menambahkan kata sandi atau kunci';

  @override
  String dragItemCount(int count) {
    return '$count item';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'Pilih semua ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'Ukuran: $size KB / maks. $max KB';
  }

  @override
  String get noActiveTerminals => 'Tidak ada terminal aktif';

  @override
  String get connectFromSessionsTab => 'Hubungkan dari tab Sesi';

  @override
  String fileNotFound(String path) {
    return 'File tidak ditemukan: $path';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count item, $size';
  }

  @override
  String get maximize => 'Maksimalkan';

  @override
  String get restore => 'Pulihkan';

  @override
  String get duplicateDownShortcut => 'Duplikat ke Bawah (Ctrl+Shift+\\)';

  @override
  String get security => 'Keamanan';

  @override
  String get knownHosts => 'Host Dikenal';

  @override
  String get knownHostsSubtitle => 'Kelola sidik jari server SSH terpercaya';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count host dikenal',
      zero: 'Tidak ada host dikenal',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'Tidak ada host dikenal. Hubungkan ke server untuk menambahkan.';

  @override
  String get removeHost => 'Hapus host';

  @override
  String removeHostConfirm(String host) {
    return 'Hapus $host dari host dikenal? Kunci akan diverifikasi ulang pada koneksi berikutnya.';
  }

  @override
  String get clearAllKnownHosts => 'Hapus semua host dikenal';

  @override
  String get clearAllKnownHostsConfirm =>
      'Hapus semua host dikenal? Setiap kunci server perlu diverifikasi ulang.';

  @override
  String get clearedAllHosts => 'Semua host dikenal telah dihapus';

  @override
  String removedHost(String host) {
    return '$host dihapus';
  }

  @override
  String get tools => 'Alat';

  @override
  String get sshKeys => 'Kunci SSH';

  @override
  String get sshKeysSubtitle => 'Kelola pasangan kunci SSH untuk autentikasi';

  @override
  String get noKeys => 'Tidak ada kunci SSH. Impor atau buat satu.';

  @override
  String get generateKey => 'Buat kunci';

  @override
  String get addKey => 'Tambah kunci';

  @override
  String get addKeyMenuPaste => 'Tempel PEM';

  @override
  String get filePickerUnavailable =>
      'Pemilih berkas tidak tersedia pada sistem ini';

  @override
  String get importKey => 'Impor kunci';

  @override
  String get keyLabel => 'Nama kunci';

  @override
  String get keyLabelHint => 'cth. Server Kerja, GitHub';

  @override
  String get selectKeyType => 'Tipe kunci';

  @override
  String get generating => 'Membuat...';

  @override
  String keyGenerated(String label) {
    return 'Kunci dibuat: $label';
  }

  @override
  String keyImported(String label) {
    return 'Kunci diimpor: $label';
  }

  @override
  String get deleteKey => 'Hapus kunci';

  @override
  String deleteKeyConfirm(String label) {
    return 'Hapus kunci \"$label\"? Sesi yang menggunakannya akan kehilangan akses.';
  }

  @override
  String keyDeleted(String label) {
    return 'Kunci dihapus: $label';
  }

  @override
  String get publicKey => 'Kunci publik';

  @override
  String get publicKeyCopied => 'Kunci publik disalin ke clipboard';

  @override
  String get sshCertificate => 'Certificate';

  @override
  String get certImport => 'Import certificate';

  @override
  String get certImportTooltip =>
      'Attach OpenSSH certificate yang di-sign oleh CA Anda (file `-cert.pub` dari `ssh-keygen -s …`). Pakai saat server verifikasi lewat CA signature, bukan `authorized_keys`. Skip kalau server Anda pakai plain key auth.';

  @override
  String get certImportPickerTitle => 'Pilih file certificate OpenSSH';

  @override
  String get certValidFrom => 'Berlaku sejak';

  @override
  String get certValidTo => 'Berlaku sampai';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => 'Certificate ini akan segera expired.';

  @override
  String get certExpired => 'Expired';

  @override
  String get certRemove => 'Hapus certificate';

  @override
  String get certRemoveConfirmTitle => 'Hapus certificate?';

  @override
  String get certRemoveConfirmBody =>
      'Setelah dihapus, sesi akan kembali memakai jalur public key biasa saat connect.';

  @override
  String errCertParse(String detail) {
    return 'Tidak bisa parse certificate: $detail';
  }

  @override
  String get errCertPairFingerprintMismatch =>
      'Certificate ini tidak dipasangkan dengan key yang dipilih.';

  @override
  String get pastePrivateKey => 'Tempel kunci privat (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Data kunci PEM tidak valid';

  @override
  String get selectFromKeyStore => 'Pilih dari penyimpanan kunci';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kunci',
      zero: 'Tidak ada kunci',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'Dibuat';

  @override
  String get passphrase => 'Frasa sandi';

  @override
  String get enterMasterPassword =>
      'Masukkan kata sandi utama untuk mengakses kredensial tersimpan.';

  @override
  String get wrongMasterPassword => 'Kata sandi salah. Coba lagi.';

  @override
  String get currentPassword => 'Kata sandi saat ini';

  @override
  String get forgotPassword => 'Lupa kata sandi?';

  @override
  String get credentialsReset => 'Semua kredensial tersimpan telah dihapus';

  @override
  String get migrationToast => 'Penyimpanan ditingkatkan ke format terbaru';

  @override
  String get dbCorruptTitle => 'Basis data tidak dapat dibuka';

  @override
  String get dbCorruptBody =>
      'Data di disk tidak dapat dibuka. Coba kredensial lain atau setel ulang untuk mulai dari awal.';

  @override
  String get dbCorruptWarning =>
      'Reset akan menghapus basis data terenkripsi dan semua file terkait keamanan secara permanen. Tidak ada data yang dipulihkan.';

  @override
  String get dbCorruptTryOther => 'Coba kredensial lain';

  @override
  String get dbCorruptResetContinue => 'Reset & Siapkan Ulang';

  @override
  String get dbCorruptExit => 'Keluar dari LetsFLUTssh';

  @override
  String get tierResetTitle => 'Perlu atur ulang keamanan';

  @override
  String get tierResetBody =>
      'Instalasi ini membawa data keamanan dari versi LetsFLUTssh lama yang memakai model tier berbeda. Model baru adalah breaking change — tidak ada jalur migrasi otomatis. Untuk melanjutkan, semua sesi tersimpan, kredensial, kunci SSH, dan known-host di instalasi ini harus dihapus dan wizard setup pertama dijalankan ulang.';

  @override
  String get tierResetWarning =>
      'Memilih «Atur Ulang & Siapkan Baru» akan menghapus permanen basis data terenkripsi dan setiap berkas terkait keamanan. Jika Anda perlu memulihkan data, keluar dari aplikasi sekarang dan instal ulang versi sebelumnya dari LetsFLUTssh untuk mengekspor terlebih dahulu.';

  @override
  String get tierResetResetContinue => 'Atur Ulang & Siapkan Baru';

  @override
  String get tierResetExit => 'Keluar dari LetsFLUTssh';

  @override
  String get derivingKey => 'Membuat kunci enkripsi...';

  @override
  String get securitySetupTitle => 'Pengaturan keamanan';

  @override
  String get keychainAvailable => 'Tersedia';

  @override
  String get changeSecurityTierConfirm =>
      'Mengenkripsi ulang basis data dengan tingkat baru. Tidak dapat diganggu — biarkan aplikasi terbuka hingga selesai.';

  @override
  String get changeSecurityTierDone => 'Tingkat keamanan diubah';

  @override
  String get changeSecurityTierFailed =>
      'Tidak dapat mengubah tingkat keamanan';

  @override
  String get firstLaunchSecurityTitle => 'Penyimpanan aman aktif';

  @override
  String get firstLaunchSecurityBody =>
      'Data Anda dienkripsi dengan kunci yang tersimpan di keychain OS. Pembukaan kunci di perangkat ini berjalan otomatis.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'Penyimpanan berbasis perangkat keras tersedia di perangkat ini. Tingkatkan di Pengaturan → Keamanan untuk pengikatan TPM / Secure Enclave.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'Penyimpanan berbasis perangkat keras tidak tersedia di perangkat ini.';

  @override
  String get firstLaunchSecurityOpenSettings => 'Buka Pengaturan';

  @override
  String get wizardReducedBanner =>
      'Keychain OS tidak terjangkau pada pemasangan ini. Pilih antara tanpa enkripsi (T0) dan kata sandi utama (Paranoid). Pasang gnome-keyring, kwallet, atau penyedia libsecret lainnya untuk mengaktifkan tingkat Keychain.';

  @override
  String get tierBadgeCurrent => 'Saat ini';

  @override
  String get securitySetupEnable => 'Aktifkan';

  @override
  String get securitySetupApply => 'Terapkan';

  @override
  String get hwProbeLinuxDeviceMissing =>
      'TPM tidak terdeteksi pada /dev/tpmrm0. Aktifkan fTPM / PTT di BIOS jika perangkat mendukung; jika tidak, tingkat perangkat keras tidak tersedia di perangkat ini.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools belum terpasang. Jalankan `sudo apt install tpm2-tools` (atau padanannya di distro Anda) untuk mengaktifkan tingkat perangkat keras.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'Pemeriksaan tingkat perangkat keras gagal. Periksa izin /dev/tpmrm0 dan aturan udev — lihat log untuk detail.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'TPM 2.0 tidak terdeteksi. Aktifkan fTPM / PTT di firmware UEFI, atau terima bahwa tingkat perangkat keras tidak tersedia di perangkat ini — aplikasi beralih ke penyimpanan kredensial berbasis perangkat lunak.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Baik Microsoft Platform Crypto Provider maupun Software Key Storage Provider tidak dapat dijangkau — kemungkinan subsistem kripto Windows rusak atau Kebijakan Grup yang memblokir CNG. Periksa Event Viewer → Applications and Services Logs.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'Mac ini tidak memiliki Secure Enclave (Mac Intel sebelum 2017 tanpa chip keamanan T1 / T2). Tingkat perangkat keras tidak tersedia; gunakan kata sandi utama.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'Tidak ada kata sandi login di Mac ini. Pembuatan kunci Secure Enclave memerlukannya — atur kata sandi login di Pengaturan Sistem → Touch ID & Kata Sandi (atau Kata Sandi Login).';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave menolak identitas penandatanganan aplikasi (-34018). Jalankan skrip `macos-resign.sh` yang disertakan di rilis untuk memberikan instalasi ini identitas swatandatangan yang stabil, lalu mulai ulang aplikasi.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'Tidak ada kode sandi perangkat yang diatur. Pembuatan kunci Secure Enclave memerlukannya — atur kode sandi di Pengaturan → Face ID & Kode Sandi (atau Touch ID & Kode Sandi).';

  @override
  String get hwProbeIosSimulator =>
      'Berjalan di Simulator iOS, yang tidak memiliki Secure Enclave. Tingkat perangkat keras hanya tersedia di perangkat iOS fisik.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'Android 9 atau lebih baru diperlukan untuk tingkat perangkat keras (StrongBox dan invalidasi per-kunci saat pendaftaran tidak dapat diandalkan pada versi lebih lama).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'Perangkat ini tidak memiliki perangkat keras biometrik (sidik jari atau wajah). Gunakan kata sandi utama.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'Tidak ada biometrik yang terdaftar. Tambahkan sidik jari atau wajah di Pengaturan → Keamanan & privasi → Biometrik, lalu aktifkan kembali tingkat perangkat keras.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'Perangkat keras biometrik tidak dapat digunakan sementara (terkunci setelah percobaan gagal atau pembaruan keamanan tertunda). Coba lagi beberapa menit lagi.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'Android Keystore menolak menyimpan kunci perangkat keras pada build perangkat ini (StrongBox tidak tersedia, ROM kustom, atau gangguan driver). Tingkat perangkat keras tidak tersedia.';

  @override
  String get securityRecheck => 'Periksa ulang dukungan tingkat';

  @override
  String get securityRecheckUpdated =>
      'Dukungan tingkat diperbarui — lihat kartu di atas';

  @override
  String get securityRecheckUnchanged => 'Dukungan tingkat tidak berubah';

  @override
  String get securityMacosEnableSecureTiers =>
      'Buka kunci tingkat aman di Mac ini';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'Tanda tangani ulang aplikasi dengan sertifikat pribadi agar Keychain (T1) dan Secure Enclave (T2) tetap bekerja setelah pembaruan';

  @override
  String get securityMacosEnableSecureTiersPrompt =>
      'macOS akan meminta kata sandi Anda sekali';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'Tingkat aman terbuka — T1 dan T2 sekarang tersedia';

  @override
  String get securityMacosEnableSecureTiersFailed =>
      'Gagal membuka tingkat aman';

  @override
  String get securityMacosOfferTitle => 'Aktifkan Keychain + Secure Enclave?';

  @override
  String get securityMacosOfferBody =>
      'macOS mengikat penyimpanan terenkripsi ke identitas penandatanganan aplikasi. Tanpa sertifikat stabil, Keychain (T1) dan Secure Enclave (T2) menolak akses. Kami dapat membuat sertifikat pribadi bertanda-tangan-sendiri di Mac ini dan menandatangani ulang aplikasi — pembaruan akan terus bekerja, dan rahasia Anda bertahan antar versi. macOS akan meminta kata sandi login Anda sekali untuk memercayai sertifikat baru.';

  @override
  String get securityMacosOfferAccept => 'Aktifkan';

  @override
  String get securityMacosOfferDecline => 'Lewati — pilih T0 atau Paranoid';

  @override
  String get securityMacosRemoveIdentity => 'Hapus identitas penandatanganan';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      'Menghapus sertifikat pribadi. Data T1 / T2 terikat padanya — beralih ke T0 atau Paranoid dulu, lalu hapus.';

  @override
  String get securityMacosRemoveIdentityConfirmTitle =>
      'Hapus identitas penandatanganan?';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'Menghapus sertifikat pribadi dari Keychain login. Rahasia T1 / T2 yang disimpan akan tidak terbaca. Wizard akan terbuka untuk migrasi ke T0 (teks biasa) atau Paranoid (kata sandi utama) sebelum penghapusan.';

  @override
  String get securityMacosRemoveIdentitySuccess =>
      'Identitas penandatanganan dihapus';

  @override
  String get securityMacosRemoveIdentityFailed =>
      'Gagal menghapus identitas penandatanganan';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus aktif tetapi tidak ada secret-service daemon yang berjalan. Pasang gnome-keyring (`sudo apt install gnome-keyring`) atau KWalletManager dan pastikan berjalan saat login.';

  @override
  String get keyringProbeFailed =>
      'Keychain OS tidak dapat dijangkau di perangkat ini. Lihat log untuk error spesifik platform; aplikasi beralih ke kata sandi utama.';

  @override
  String get snippets => 'Snippet';

  @override
  String get snippetsSubtitle =>
      'Kelola snippet perintah yang dapat digunakan kembali';

  @override
  String get noSnippets => 'Belum ada snippet';

  @override
  String get addSnippet => 'Tambah Snippet';

  @override
  String get editSnippet => 'Edit Snippet';

  @override
  String get deleteSnippet => 'Hapus Snippet';

  @override
  String deleteSnippetConfirm(String title) {
    return 'Hapus snippet \"$title\"?';
  }

  @override
  String get snippetTitle => 'Judul';

  @override
  String get snippetTitleHint => 'mis. Deploy, Restart Service';

  @override
  String get snippetCommand => 'Perintah';

  @override
  String get snippetCommandHint => 'mis. sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'Deskripsi (opsional)';

  @override
  String get snippetDescriptionHint => 'Apa fungsi perintah ini?';

  @override
  String get snippetSaved => 'Snippet disimpan';

  @override
  String snippetDeleted(String title) {
    return 'Snippet \"$title\" dihapus';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippet',
      one: '1 snippet',
      zero: 'Tidak ada snippet',
    );
    return '$_temp0';
  }

  @override
  String get pinToSession => 'Sematkan ke sesi ini';

  @override
  String get unpinFromSession => 'Lepaskan dari sesi ini';

  @override
  String get pinnedSnippets => 'Disematkan';

  @override
  String get allSnippets => 'Semua';

  @override
  String get commandCopied => 'Perintah disalin';

  @override
  String get snippetTokensHint =>
      'Ketuk untuk menyisipkan placeholder. Ini diganti saat dijalankan dengan nilai dari sesi aktif:';

  @override
  String get snippetCustomTokensHint =>
      'Apa pun lainnya dengan tanda kurung kurawal ganda akan meminta nilai saat snippet dijalankan.';

  @override
  String get snippetFillTitle => 'Isi parameter snippet';

  @override
  String get snippetFillSubmit => 'Jalankan';

  @override
  String get broadcastSetDriver => 'Siarkan dari panel ini';

  @override
  String get broadcastClearDriver => 'Hentikan siaran dari panel ini';

  @override
  String get broadcastAddReceiver => 'Terima siaran di sini';

  @override
  String get broadcastRemoveReceiver => 'Berhenti menerima siaran';

  @override
  String get broadcastClearAll => 'Hentikan semua siaran';

  @override
  String get broadcastPasteTitle => 'Kirim tempel ke semua panel?';

  @override
  String broadcastPasteBody(int chars, int count) {
    return '$chars karakter akan dikirim ke $count panel lain.';
  }

  @override
  String get broadcastPasteSend => 'Kirim';

  @override
  String get portForwarding => 'Penerusan';

  @override
  String get portForwardingEmpty => 'Belum ada aturan';

  @override
  String get addForwardRule => 'Tambah aturan';

  @override
  String get editForwardRule => 'Edit aturan';

  @override
  String get deleteForwardRule => 'Hapus aturan';

  @override
  String get localForward => 'Lokal';

  @override
  String get remoteForward => 'Jarak jauh';

  @override
  String get dynamicForward => 'Dinamis';

  @override
  String get forwardKind => 'Jenis';

  @override
  String get bindAddress => 'Alamat bind';

  @override
  String get bindPort => 'Port bind';

  @override
  String get targetHost => 'Host target';

  @override
  String get targetPort => 'Port target';

  @override
  String get forwardDescription => 'Deskripsi (opsional)';

  @override
  String get forwardEnabled => 'Aktif';

  @override
  String get forwardBindWildcardWarning =>
      'Bind ke 0.0.0.0 mempublikasikan penerusan ke semua antarmuka — biasanya 127.0.0.1 yang Anda inginkan.';

  @override
  String get forwardKindLocalHelp =>
      'Lokal: membuka port di perangkat ini yang menerowong ke target yang dapat dijangkau dari server SSH. Berguna untuk mengakses database jarak jauh atau UI admin di localhost:bindPort.';

  @override
  String get forwardKindRemoteHelp =>
      'Jarak jauh: meminta server SSH membuka port yang menerowong kembali ke target yang dapat dijangkau dari perangkat ini. Berguna untuk berbagi dev server lokal dengan host jarak jauh (server mungkin perlu GatewayPorts yes untuk bind non-loopback).';

  @override
  String get forwardKindDynamicHelp =>
      'Dinamis: proxy SOCKS5 di perangkat ini yang merutekan setiap koneksi melalui server SSH. Arahkan browser atau curl ke localhost:bindPort untuk mengirim semua lalu lintas melalui SSH.';

  @override
  String get proxyJump => 'Hubungkan melalui';

  @override
  String get proxyJumpNone => 'Koneksi langsung';

  @override
  String get proxyJumpSavedSession => 'Sesi tersimpan';

  @override
  String get proxyJumpCustom => 'Kustom';

  @override
  String get proxyJumpCustomNote =>
      'Hop kustom memakai kredensial sesi ini. Untuk auth bastion berbeda, simpan bastion sebagai sesi tersendiri.';

  @override
  String viaSessionLabel(String label) {
    return 'via $label';
  }

  @override
  String get recordSession => 'Rekam sesi';

  @override
  String get recordSessionHelp =>
      'Simpan output terminal ke disk untuk sesi ini. Terenkripsi saat istirahat jika master password atau hardware key melindungi database sesi; selain itu disimpan sebagai plaintext di samping database.';

  @override
  String get recordingsBrowserTitle => 'Rekaman';

  @override
  String get recordingsBrowserSubtitle =>
      'Telusuri, putar ulang, dan hapus sesi yang direkam';

  @override
  String get recordingsEmpty => 'Belum ada rekaman';

  @override
  String get playRecording => 'Putar';

  @override
  String get deleteRecording => 'Hapus';

  @override
  String get recordingPlaybackTitle => 'Putar ulang rekaman';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

  @override
  String get tags => 'Tag';

  @override
  String get tagsSubtitle => 'Atur sesi dan folder dengan tag berwarna';

  @override
  String get noTags => 'Belum ada tag';

  @override
  String get addTag => 'Tambah Tag';

  @override
  String get deleteTag => 'Hapus Tag';

  @override
  String deleteTagConfirm(String name) {
    return 'Hapus tag \"$name\"? Tag akan dihapus dari semua sesi dan folder.';
  }

  @override
  String get tagName => 'Nama Tag';

  @override
  String get tagNameHint => 'mis. Production, Staging';

  @override
  String get tagColor => 'Warna';

  @override
  String get tagCreated => 'Tag dibuat';

  @override
  String tagDeleted(String name) {
    return 'Tag \"$name\" dihapus';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tag',
      one: '1 tag',
      zero: 'Tidak ada tag',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'Kelola tag';

  @override
  String get editTags => 'Edit Tag';

  @override
  String get fullBackup => 'Cadangan lengkap';

  @override
  String get sessionsOnly => 'Sesi';

  @override
  String get presetFullImport => 'Impor lengkap';

  @override
  String get presetSelective => 'Selektif';

  @override
  String get presetCustom => 'Kustom';

  @override
  String get sessionSshKeys => 'Kunci sesi (pengelola)';

  @override
  String get allManagerKeys => 'Semua kunci di pengelola';

  @override
  String get browseFiles => 'Jelajahi berkas…';

  @override
  String get sshDirSessionAlreadyImported => 'sudah ada di sesi';

  @override
  String get languageSubtitle => 'Bahasa antarmuka';

  @override
  String get themeSubtitle => 'Gelap, terang, atau mengikuti sistem';

  @override
  String get uiScaleSubtitle => 'Skala seluruh antarmuka';

  @override
  String get terminalFontSizeSubtitle => 'Ukuran font pada keluaran terminal';

  @override
  String get scrollbackLinesSubtitle => 'Ukuran buffer riwayat terminal';

  @override
  String get keepAliveIntervalSubtitle =>
      'Detik antara paket SSH keep-alive (0 = mati)';

  @override
  String get sshTimeoutSubtitle => 'Batas waktu koneksi dalam detik';

  @override
  String get defaultPortSubtitle => 'Port default untuk sesi baru';

  @override
  String get parallelWorkersSubtitle => 'Worker transfer SFTP paralel';

  @override
  String get maxHistorySubtitle => 'Maksimum perintah tersimpan di riwayat';

  @override
  String get calculateFolderSizesSubtitle =>
      'Tampilkan ukuran total di samping folder di bilah sisi';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Cek rilis baru di GitHub saat aplikasi dijalankan';

  @override
  String get threatColdDiskTheft => 'Pencurian disk saat mati';

  @override
  String get threatColdDiskTheftDescription =>
      'Komputer dalam keadaan mati yang drive-nya dilepas lalu dibaca di komputer lain, atau salinan berkas basis data yang diambil oleh seseorang dengan akses ke direktori home Anda.';

  @override
  String get threatKeyringFileTheft => 'Pencurian berkas keyring / keychain';

  @override
  String get threatKeyringFileTheftDescription =>
      'Penyerang membaca berkas penyimpanan kredensial platform langsung dari disk (libsecret keyring, Windows Credential Manager, macOS login keychain) dan memulihkan kunci basis data yang dibungkus dari dalamnya. Tingkat perangkat keras memblokirnya terlepas dari kata sandi karena chip menolak mengekspor material kunci; tingkat keychain memerlukan kata sandi tambahan, jika tidak berkas yang dicuri dapat dibuka hanya dengan kata sandi login OS.';

  @override
  String get modifierOnlyWithPassword => 'hanya dengan kata sandi';

  @override
  String get threatBystanderUnlockedMachine =>
      'Orang lain di dekat mesin yang sudah terbuka';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'Seseorang menghampiri komputer Anda yang sudah terbuka kuncinya dan membuka aplikasi saat Anda tidak di tempat.';

  @override
  String get threatLiveRamForensicsLocked =>
      'Dump RAM pada mesin yang terkunci';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'Penyerang membekukan RAM (atau menangkapnya lewat DMA) dan menarik materi kunci yang masih tersimpan dari snapshot, bahkan ketika aplikasi sedang terkunci.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'Kompromi kernel OS atau keychain';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'Kerentanan kernel, eksfiltrasi keychain, atau backdoor pada chip keamanan hardware. OS berubah dari sumber daya tepercaya menjadi penyerang.';

  @override
  String get threatOfflineBruteForce =>
      'Brute force offline pada kata sandi lemah';

  @override
  String get threatOfflineBruteForceDescription =>
      'Penyerang yang memegang salinan kunci yang dibungkus atau blob tersegel mencoba setiap kata sandi dengan kecepatannya sendiri, tanpa pembatas laju apa pun.';

  @override
  String get legendProtects => 'Terlindungi';

  @override
  String get legendDoesNotProtect => 'Tidak terlindungi';

  @override
  String get colT0 => 'T0 Teks polos';

  @override
  String get colT1 => 'T1 Keychain';

  @override
  String get colT1Password => 'T1 + kata sandi';

  @override
  String get colT1PasswordBiometric => 'T1 + kata sandi + biometrik';

  @override
  String get colT2Password => 'T2 + kata sandi';

  @override
  String get colT2PasswordBiometric => 'T2 + kata sandi + biometrik';

  @override
  String get colParanoid => 'Paranoid';

  @override
  String get securityComparisonTableThreatColumn => 'Ancaman';

  @override
  String get compareAllTiers => 'Bandingkan semua tier';

  @override
  String get resetAllDataTitle => 'Reset semua data';

  @override
  String get resetAllDataSubtitle =>
      'Hapus semua sesi, kunci, konfigurasi, dan artefak keamanan. Juga membersihkan entri keychain dan slot brankas perangkat keras.';

  @override
  String get resetAllDataConfirmTitle => 'Reset semua data?';

  @override
  String get resetAllDataConfirmBody =>
      'Semua sesi, kunci SSH, known hosts, snippet, tag, preferensi, dan semua artefak keamanan (entri keychain, data brankas perangkat keras, lapisan biometrik) akan dihapus secara permanen. Tindakan ini tidak dapat dibatalkan.';

  @override
  String get resetAllDataConfirmAction => 'Reset semuanya';

  @override
  String resetAllDataConfirmTypePrompt(String phrase) {
    return 'Ketik $phrase di bawah untuk mengonfirmasi:';
  }

  @override
  String get resetAllDataInProgress => 'Mereset…';

  @override
  String get resetAllDataDone => 'Semua data telah direset';

  @override
  String get resetAllDataFailed => 'Reset gagal';

  @override
  String get recordingsTitle => 'Recordings';

  @override
  String get recordingsStorageUsedLabel => 'Terpakai';

  @override
  String get recordingsCapLabel => 'Cap';

  @override
  String get recordingsCapHint =>
      'Hard cap untuk folder recordings/. Saat terlampaui, recording terlama dihapus dulu; recording yang sedang berjalan tidak pernah disentuh.';

  @override
  String get recordingsClearAllAction => 'Hapus semua recordings';

  @override
  String get recordingsClearAllConfirmTitle => 'Hapus semua recordings?';

  @override
  String get recordingsClearAllConfirmBody =>
      'Setiap session yang direkam di bawah <app>/recordings/ akan dihapus. Recording yang sedang berjalan (jika ada) tetap. Aksi ini tidak bisa dibatalkan.';

  @override
  String recordingsClearAllResult(int count) {
    return '$count recordings dihapus';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return 'Cap diperbarui. $bytes dibebaskan.';
  }

  @override
  String get recordingsCapChangedNoChange =>
      'Cap diperbarui. Tidak ada yang dihapus.';

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
      'Kunci otomatis memerlukan kata sandi pada tier aktif.';

  @override
  String get recommendedBadge => 'DIREKOMENDASIKAN';

  @override
  String get tierHardwareSubtitleHonest =>
      'Lanjutan: kunci terikat pada perangkat keras, selalu dilindungi password. Data tidak dapat dipulihkan jika chip perangkat ini hilang atau diganti.';

  @override
  String get tierParanoidSubtitleHonest =>
      'Alternatif: kata sandi utama, tanpa memercayai OS. Melindungi dari OS yang disusupi. Tidak meningkatkan proteksi runtime dibandingkan T1/T2.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'Ancaman runtime (malware dari pengguna yang sama, dump memori proses yang sedang berjalan) ditampilkan sebagai ✗ di setiap tingkat. Ancaman tersebut ditangani oleh fitur mitigasi terpisah yang berlaku tanpa memandang tingkat yang dipilih.';

  @override
  String get currentTierBadge => 'SAAT INI';

  @override
  String get paranoidAlternativeHeader => 'ALTERNATIF';

  @override
  String get modifierPasswordLabel => 'Kata sandi';

  @override
  String get modifierPasswordSubtitle =>
      'Gerbang rahasia yang diketik sebelum brankas dibuka.';

  @override
  String get modifierPasswordRequired =>
      'Wajib — tier Hardware selalu dilindungi password.';

  @override
  String get modifierBiometricLabel => 'Pintasan biometrik';

  @override
  String get modifierBiometricSubtitle =>
      'Mengambil kata sandi dari slot OS yang dijaga biometrik, alih-alih mengetiknya.';

  @override
  String get biometricRequiresPassword =>
      'Aktifkan kata sandi terlebih dahulu — biometrik hanya pintasan untuk memasukkannya.';

  @override
  String get biometricRequiresActiveTier =>
      'Pilih tingkat ini terlebih dahulu untuk mengaktifkan buka kunci biometrik';

  @override
  String get autoLockRequiresActiveTier =>
      'Pilih tingkat ini terlebih dahulu untuk mengonfigurasi kunci otomatis';

  @override
  String get biometricForbiddenParanoid =>
      'Paranoid tidak mengizinkan biometrik secara desain.';

  @override
  String get fprintdNotAvailable =>
      'fprintd belum diinstal atau tidak ada sidik jari terdaftar.';

  @override
  String get t2RequiresPasswordTitle =>
      'Atur master password untuk tier Hardware';

  @override
  String get t2RequiresPasswordBody =>
      'Tier Hardware butuh password sebagai modifier. Biometric adalah shortcut opsional di atasnya.';

  @override
  String get t2MigrationPromptTitle => 'Tier Hardware butuh password';

  @override
  String get t2MigrationPromptBody =>
      'Install Hardware yang sudah ada tanpa password harus menetapkan satu sekarang untuk melanjutkan.';

  @override
  String get t2MigrationContinue => 'Lanjutkan';

  @override
  String get t2MigrationSetPasswordTitle =>
      'Set password untuk menyimpan tier Hardware';

  @override
  String get t2MigrationSetPasswordBody =>
      'Ketik master password baru. DB key yang sudah di-seal di hardware module akan di-re-seal di bawah password ini — session dan key kamu tetap utuh.';

  @override
  String get t2MigrationWipeAndRestart => 'Wipe dan mulai ulang';

  @override
  String get t2MigrationResealFailed =>
      'Re-seal tier Hardware gagal — pilih password lain atau wipe untuk mulai dari nol.';

  @override
  String get biometricOverlayEnable =>
      'Aktifkan shortcut biometric pada tier Hardware';

  @override
  String get biometricOverlayEnableSubtitle =>
      'Membebaskan password kamu dari slot OS yang dilindungi biometric.';

  @override
  String get biometricOverlayUnavailable =>
      'Overlay biometric belum tersedia di platform ini.';

  @override
  String get biometricOverlayRequiresPassword =>
      'Atur password tier Hardware terlebih dahulu.';

  @override
  String get t2UnlockTitle => 'Buka dengan master password kamu';

  @override
  String get t2UnlockSubtitle =>
      'Kunci hardware-bound dilindungi password kamu.';

  @override
  String get t2UnlockUseBiometricButton => 'Gunakan biometric';

  @override
  String get t2PasswordChanged => 'Password tier Hardware diperbarui.';

  @override
  String get paranoidMasterPasswordNote =>
      'Sangat disarankan menggunakan frasa sandi yang panjang — Argon2id hanya memperlambat serangan brute force, bukan memblokirnya.';

  @override
  String get plaintextWarningTitle => 'Teks polos: tanpa enkripsi';

  @override
  String get plaintextWarningBody =>
      'Sesi, kunci, dan known hosts akan disimpan tanpa enkripsi. Siapa pun yang memiliki akses ke sistem file komputer ini dapat membacanya.';

  @override
  String get plaintextAcknowledge =>
      'Saya memahami bahwa data saya tidak akan dienkripsi';

  @override
  String get plaintextAcknowledgeRequired =>
      'Konfirmasikan pemahaman Anda sebelum melanjutkan.';

  @override
  String get passwordLabel => 'Kata sandi';

  @override
  String get masterPasswordLabel => 'Kata sandi utama';

  @override
  String get globalErrorTitle => 'Kesalahan tak terduga';

  @override
  String get globalErrorBody =>
      'Terjadi kesalahan tak terduga. Aplikasi akan tetap berjalan.';

  @override
  String get globalErrorLogSavedNote =>
      'Semua detail telah ditulis ke file log.';

  @override
  String get globalErrorLogDisabledNote =>
      'Aktifkan logging di Pengaturan untuk menyimpan detail kesalahan.';

  @override
  String globalErrorTechnicalLine(String detail) {
    return 'Kesalahan: $detail';
  }

  @override
  String get globalErrorEnableLoggingButton => 'Aktifkan logging';

  @override
  String get globalErrorLoggingEnabledToast =>
      'Logging aktif — kesalahan akan ditulis ke file log';

  @override
  String get fatalErrorQuitButton => 'Keluar';

  @override
  String get fatalErrorWipeButton => 'Hapus semua data';

  @override
  String get fatalErrorWipingButton => 'Menghapus…';

  @override
  String get fatalErrorWipeExplanation =>
      'Menghapus akan membuang semua file aplikasi (config, database, blob vault, log); peluncuran berikutnya mulai dari instalasi bersih. Tidak bisa dibatalkan.';

  @override
  String get fatalErrorWipeConfirmTitle => 'Hapus semua data?';

  @override
  String get fatalErrorWipeConfirmBody =>
      'Ini menghapus permanen semua file config, database, dan vault. Aplikasi akan mulai ulang dari instalasi kosong. Lanjutkan?';

  @override
  String get fatalErrorWipeConfirmAction => 'Hapus semuanya';

  @override
  String get unencryptedArchiveWarning =>
      'Arsip ini tidak dilindungi kata sandi. Siapa pun yang punya file ini bisa membaca isinya.';

  @override
  String get clipboardCopyFailed => 'Gagal menyalin ke clipboard.';

  @override
  String get nonAsciiHostnameWarning =>
      'Nama host mengandung karakter non-ASCII — periksa tiap karakter terhadap yang kamu ketik. Codepoint yang mirip secara visual (Sirilik / Yunani) bisa memalsukan domain Latin.';

  @override
  String get playbackPause => 'Jeda';

  @override
  String get recordingPlayLocked =>
      'Buka kunci aplikasi untuk memutar rekaman terenkripsi ini.';

  @override
  String get recordToggleStart => 'Mulai recording';

  @override
  String get recordToggleStop => 'Hentikan recording';

  @override
  String get foregroundServiceTitle => 'SSH aktif';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count koneksi aktif',
      one: '1 koneksi aktif',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => 'Tipe session';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => 'Username';

  @override
  String get webDavAuthMethod => 'Metode auth';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer token';

  @override
  String get trustedCert => 'Sertifikat tepercaya (PEM)';

  @override
  String get trustedCertHint => '-----BEGIN CERTIFICATE-----';

  @override
  String get trustedCertHelp =>
      'Tempel sertifikat server (satu atau lebih blok PEM). Ditambahkan sebagai CA root tambahan hanya untuk sesi ini — tidak memengaruhi aplikasi lain. Kosongkan untuk menggunakan trust store sistem.';

  @override
  String get acceptAnyCert => 'Terima sertifikat apa pun';

  @override
  String get acceptAnyCertHelp =>
      'Lewati semua pemeriksaan sertifikat dan hostname untuk handshake TLS sesi ini. Pintu darurat ketika baik trust store sistem maupun sertifikat yang di-pin tidak cocok.';

  @override
  String get acceptAnyCertWarn =>
      'Rentan terhadap serangan MITM — siapa pun di jaringan dapat menyamar sebagai server. Gunakan hanya di jaringan privat tepercaya.';

  @override
  String get webDavCopyUrl => 'Salin URL WebDAV';

  @override
  String get webDavOpenInBrowser => 'Buka di browser';

  @override
  String get errWebDavAuthFailed => 'Auth WebDAV gagal';

  @override
  String get errWebDavNotFound => 'Path tidak ditemukan';

  @override
  String get errWebDavConflict => 'Operasi bentrok dengan state saat ini';

  @override
  String errWebDavGeneric(String detail) {
    return 'Server WebDAV menolak request: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'Base URL WebDAV diperlukan';

  @override
  String get errWebDavBaseUrlInvalid => 'Base URL harus http:// atau https://';

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
      'Kosongkan untuk AWS, atau isi untuk MinIO / R2 / Spaces';

  @override
  String get s3PathStyle => 'Path-style addressing';

  @override
  String get s3PathStyleHint => 'Wajib untuk MinIO; off-kan untuk AWS';

  @override
  String get s3DefaultBucket => 'Default bucket';

  @override
  String get s3DefaultPrefix => 'Default prefix';

  @override
  String get s3GeneratePresignedUrl => 'Generate presigned URL';

  @override
  String get s3PresignedUrlExpiry => 'Kedaluwarsa dalam';

  @override
  String get s3CopyUri => 'Copy URI s3://bucket/key';

  @override
  String get s3PresignedUrlExpiry15min => '15 menit';

  @override
  String get s3PresignedUrlExpiry1hour => '1 jam';

  @override
  String get s3PresignedUrlExpiry4hour => '4 jam';

  @override
  String get s3PresignedUrlExpiry24hour => '24 jam';

  @override
  String get s3PresignedUrlExpiry7day => '7 hari';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (cek access key + secret)';

  @override
  String get errS3NoSuchBucket => 'Bucket tidak ada atau tidak dapat diakses';

  @override
  String get errS3RegionMismatch =>
      'Bucket berada di region berbeda dari konfigurasi';

  @override
  String errS3Generic(String detail) {
    return 'S3 server menolak request: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'Aktifkan WebDAV sync';

  @override
  String get syncPassphrase => 'Sync passphrase';

  @override
  String get syncPassphraseHint =>
      'Mengenkripsi arsip sync. Harus berbeda dari master password.';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Sync passphrase tidak boleh sama dengan master password.';

  @override
  String get syncRemotePath => 'Remote path';

  @override
  String get syncRemotePathHint =>
      'Path di bawah WebDAV base URL — default letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return 'Push terakhir: $when';
  }

  @override
  String syncLastPulled(String when) {
    return 'Pull terakhir: $when';
  }

  @override
  String get syncNeverRun => 'Belum pernah';

  @override
  String get syncUpToDate => 'Sync up to date';

  @override
  String syncPushedBytes(String bytes) {
    return 'Push $bytes';
  }

  @override
  String syncPullApplied(int count) {
    return '$count perubahan diterapkan dari remote';
  }

  @override
  String get errSyncDisabled => 'Sync nonaktif';

  @override
  String get errSyncEtagMismatch => 'Remote berubah — pull dulu, baru push';

  @override
  String get errSyncUnauthorized => 'Autentikasi WebDAV gagal';

  @override
  String errSyncNetwork(String detail) {
    return 'Network error: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion =>
      'Arsip sync remote butuh build yang lebih baru';

  @override
  String get hardwareKey => 'Hardware key';

  @override
  String get hardwareKeyTapPrompt => 'Sentuh hardware key kamu';

  @override
  String get hardwareKeyPin => 'PIN hardware key';

  @override
  String get hardwareKeyTimeout => 'Hardware key tidak merespons';

  @override
  String get hardwareKeyNotFound => 'Hardware key tidak ditemukan';

  @override
  String get hardwareKeyUnsupported =>
      'Akses langsung ke hardware key tidak tersedia di platform ini';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'Butuh Apple Developer Program entitlement; pakai ssh-agent di macOS';

  @override
  String get skKeyRequiresDevice =>
      'SSH key ini butuh hardware key — sentuh untuk auth';

  @override
  String get errSkWrongPin => 'PIN salah';

  @override
  String get hardwareKeyImport => 'Import hardware key (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => 'Prompt hardware key dibatalkan';

  @override
  String get agentEndpointSectionTitle => 'Integrasi SSH client eksternal';

  @override
  String get agentEndpointToggleTitle =>
      'Expose hardware-bound keys ke SSH client sistem';

  @override
  String get agentEndpointToggleSubtitle =>
      'Mengizinkan git, ssh, dan IDE plugin di perangkat ini menggunakan FIDO2 / smart-card / TPM keys Anda.';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'Salin perintah export';

  @override
  String get agentEndpointCopyPipeName => 'Salin nama pipe';

  @override
  String get agentEndpointSignatureRequestTitle => 'Permintaan tanda tangan';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester ingin menandatangani dengan $keyLabel';
  }

  @override
  String get agentEndpointRequesterUnknown => 'SSH client eksternal';

  @override
  String get agentEndpointAuthorizeOnce => 'Izinkan sekali';

  @override
  String get agentEndpointAuthorizeAlways => 'Izinkan dan ingat';

  @override
  String get agentEndpointDeny => 'Tolak';

  @override
  String get agentEndpointStatusRunning => 'Berjalan';

  @override
  String get agentEndpointStatusStopped => 'Berhenti';

  @override
  String get agentEndpointStatusUnsupported => 'Tidak didukung di platform ini';

  @override
  String get agentEndpointRefusedAddIdentity =>
      'Ditolak: client eksternal tidak boleh menambahkan keys.';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'Tidak dapat memulai ssh-agent endpoint: $detail';
  }

  @override
  String get pkcs11AddTitle => 'Tambah key smart-card / token';

  @override
  String get pkcs11ModuleLabel => 'Modul PKCS#11';

  @override
  String get pkcs11ModuleAutoDetected => 'Terdeteksi otomatis';

  @override
  String get pkcs11ModuleCustom => 'Modul kustom...';

  @override
  String get pkcs11ModulePickerTitle => 'Pilih library PKCS#11';

  @override
  String get pkcs11NoModuleFound =>
      'Modul PKCS#11 tidak ditemukan. Install OpenSC atau pilih library vendor.';

  @override
  String get pkcs11InitializeFailed => 'Modul PKCS#11 gagal initialise.';

  @override
  String get pkcs11NoTokenPresent => 'Tidak ada token di reader manapun.';

  @override
  String pkcs11TokenLabel(String label) {
    return 'Token: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return 'Serial: $serial';
  }

  @override
  String get pkcs11LoginRequired => 'Token butuh login.';

  @override
  String pkcs11PinPrompt(String token) {
    return 'PIN untuk $token';
  }

  @override
  String get pkcs11PinPad => 'Konfirmasi di PIN-pad token.';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'PIN salah. Sisa $remaining percobaan.';
  }

  @override
  String get pkcs11PinLocked => 'PIN token terkunci. Unblock dengan PUK.';

  @override
  String get pkcs11NoSignableKeys =>
      'Token tidak punya key SSH (RSA, ECDSA, Ed25519).';

  @override
  String get pkcs11GostUnsupported => 'Key GOST tidak bisa dipakai dengan SSH.';

  @override
  String pkcs11TokenUnplugged(String label) {
    return 'Token \"$label\" tidak terpasang.';
  }

  @override
  String get pkcs11UriRebindFailed =>
      'Token tersimpan tidak ditemukan. Sambungkan ulang dan coba lagi.';

  @override
  String pkcs11SignFailed(String reason) {
    return 'Signing gagal: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      'Smart-card / token PKCS#11 tidak tersedia di platform ini.';

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
  String get pkcs11WizardStepModule => 'Pilih module PKCS#11';

  @override
  String get pkcs11WizardStepToken => 'Pilih token';

  @override
  String get pkcs11WizardStepKey => 'Pilih key';

  @override
  String get pkcs11WizardStepPin => 'Masukkan PIN';

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
  String get pkcs11SaveInProgress => 'Membaca public key dari token...';

  @override
  String get pkcs11SaveSuccess => 'Key smart card ditambahkan.';

  @override
  String get pkcs11ScanInProgress => 'Memindai module PKCS#11...';

  @override
  String get pkcs11LoadingTokens => 'Memuat token...';

  @override
  String get pkcs11LoadingKeys => 'Memuat key...';

  @override
  String get pkcs11ModuleStatusReady => 'Module dimuat.';

  @override
  String get pkcs11ModuleStatusNoToken => 'Token tidak ada.';

  @override
  String get pkcs11ModuleStatusFailed => 'Gagal memuat module.';

  @override
  String get pkcs11PinPadHint => '(PIN pad di perangkat)';

  @override
  String get pkcs11WizardBack => 'Kembali';

  @override
  String get pkcs11WizardNext => 'Lanjut';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => 'Tambah hardware key';

  @override
  String get sshKeyHardwareBoundExplainer =>
      'Private key tersimpan di secure hardware perangkat dan tidak bisa diexport.';

  @override
  String get sshKeyEnclaveDeviceBound => 'Key ini hanya berfungsi di Mac ini.';

  @override
  String get sshKeyEnclaveDeviceBoundIos =>
      'Key ini hanya berfungsi di iPhone ini.';

  @override
  String get sshKeyHelloDeviceBound => 'Key ini hanya berfungsi di PC ini.';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'Wajibkan Touch ID / Face ID';

  @override
  String get sshKeyEnclavePasscodeFallback =>
      'Izinkan passcode perangkat sebagai fallback';

  @override
  String get sshKeyHelloPinRequired =>
      'Wajibkan Windows Hello (PIN, sidik jari, atau wajah)';

  @override
  String get sshKeyHardwareUnavailableTitle => 'Hardware key tidak tersedia';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'Aplikasi harus code-signed untuk pakai Secure Enclave.';

  @override
  String get sshKeyHardwareUnavailableHello =>
      'Windows Hello belum disetup di PC ini.';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'TPM tidak terdeteksi — hanya software-backed.';

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
  String get sshKeyGenerateCta => 'Generate';

  @override
  String get sshKeyGenerateInProgress => 'Membuat key di secure hardware...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Code-signing diperlukan — lihat USER_GUIDE.md → Hardware-bound keys.';

  @override
  String get sshKeySignInProgress => 'Menandatangani via secure hardware...';

  @override
  String get sshKeyPublicCopy => 'Copy public key';

  @override
  String get sshKeyAuthorizedKeysHint =>
      'Tambahkan baris ini ke ~/.ssh/authorized_keys di server.';

  @override
  String get sshKeyEnclaveWizardTitle => 'Secure Enclave SSH key';

  @override
  String get sshKeyEnclaveWizardLabelHint => 'Nama key';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'Kunci SSH Windows Hello';

  @override
  String get helloWizardLabelHint => 'Label kunci';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'Autentikasi via Windows Hello';

  @override
  String get helloPromptDescription =>
      'PIN, sidik jari, atau wajah — Windows Hello menandatangani SSH challenge ini.';

  @override
  String get helloSoftwareGatedWarning =>
      'Device ini tidak punya TPM. Kunci masuk ke user storage; Windows Hello tetap gate setiap tanda tangan.';

  @override
  String get helloP384NotSupported =>
      'Firmware TPM tidak mendukung P-384. Pilih P-256 atau RSA-2048.';

  @override
  String get helloConfigureFirst =>
      'Setup Windows Hello dulu di Settings -> Sign-in options.';

  @override
  String get tpmSshTitle => 'Buat kunci SSH berbasis TPM';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (direkomendasikan)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported =>
      'Algorithm tidak didukung firmware TPM ini.';

  @override
  String get tpmSshPinProtect => 'Lindungi dengan PIN';

  @override
  String get tpmSshPinLockoutWarning =>
      'TPM mengunci key setelah beberapa kali PIN salah.';

  @override
  String get tpmSshPinMismatch => 'PIN tidak cocok.';

  @override
  String get tpmSshStorageBlob => 'Simpan wrapped key di data aplikasi';

  @override
  String get tpmSshStorageHandle => 'Simpan di slot memori TPM';

  @override
  String get tpmSshStorageHandleHelp =>
      'Signing lebih cepat. Memakai salah satu slot persistent TPM.';

  @override
  String get tpmSshLabel => 'Label key';

  @override
  String get tpmSshImportTitle => 'Import SSH key terlindung TPM';

  @override
  String get tpmSshImportFormat => 'File TPM 2.0 (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return 'TPM PIN untuk $label';
  }

  @override
  String get tpmSshPinIncorrect => 'PIN salah.';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM dalam lockout cooldown. Tunggu $duration dan coba lagi.';
  }

  @override
  String get tpmSshGenerating => 'Membuat key di TPM...';

  @override
  String get tpmSshSigning => 'Signing dengan TPM...';

  @override
  String get tpmSshUnavailable => 'TPM tidak terdeteksi di perangkat ini.';

  @override
  String get tpmSshUnavailableFwDisabled => 'TPM dinonaktifkan di firmware.';

  @override
  String get tpmSshUnavailableNoPermission =>
      'Aplikasi tidak bisa mengakses TPM. Tambahkan user ke grup `tss`.';

  @override
  String tpmSshHandleInUse(String handle) {
    return 'Slot persistent $handle sudah dipakai.';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      'Key ini sign TANPA prompt Hello / PIN — siapa saja yang mengakses desktop saat kamu logged in bisa memakainya.';

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
  String get keystoreKeyGenerating => 'Generating hardware-bound key...';

  @override
  String get keystoreKeyAuthPrompt => 'Authenticate untuk pakai SSH key';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      'Key dihancurkan: biometric baru ter-enroll. Register ulang public key di server kamu.';

  @override
  String get keystoreKeyStrongBoxUnavailable =>
      'StrongBox HSM tidak tersedia di device ini';

  @override
  String get keystoreKeyUserAuthRequired =>
      'Wajib biometric / device unlock setiap signature';

  @override
  String get keystoreKeyExportDisabled =>
      'Hardware-bound keys tidak bisa di-export';

  @override
  String get keystoreKeyDeleteWarning =>
      'Menghapus key ini akan mengeluarkannya dari hardware store. Server akan menolak key ini sampai kamu register yang baru.';

  @override
  String get keystoreKeyBiometricNotEnrolled =>
      'Enroll biometric atau device PIN dulu';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (StrongBox-eligible)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+, TEE only)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (widest compatibility)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM tidak tersedia';

  @override
  String get keystoreStrongBoxFallbackBody =>
      'Device kamu tidak meng-expose StrongBox HSM. Buat key TEE-backed saja? Tetap hardware-backed, hanya tanpa isolation StrongBox.';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'Pakai TEE';

  @override
  String get keystoreStrongBoxFallbackCancel => 'Batal';

  @override
  String get fido2BrokerSectionTitle => 'Hardware security keys';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / security key';

  @override
  String get fido2BrokerMacosLabel => 'Dialog security key sistem';

  @override
  String get fido2BrokerIosLabel => 'Security key sistem (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel => 'Security key sistem (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => 'USB HID langsung (CTAP2)';

  @override
  String get fido2BrokerTransportNone => 'Tidak tersedia di platform ini';

  @override
  String get fido2BrokerPreferDirectHidTitle =>
      'Pilih USB HID langsung daripada dialog sistem';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return 'Lanjutan: lewati $brokerLabel di platform yang mendukung kedua jalur. HID langsung mendukung lebih banyak fitur authenticator tapi butuh izin per-app.';
  }

  @override
  String get sshIntegrationSection => 'Integrasi SSH';

  @override
  String get fido2BrokerNoTransportSubtitle =>
      'Dukungan hardware key tidak tersedia di device ini.';

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return 'Hanya $transport yang tersedia di device ini; toggle dinonaktifkan.';
  }

  @override
  String get hardwareKeyStubBadge => 'Stub impor';

  @override
  String get hardwareKeyStubSubtitle =>
      'Ada di perangkat lain — regenerasi di sini untuk dipakai';

  @override
  String get hardwareKeyStubRegenerateAction => 'Regenerasi di sini';

  @override
  String get hardwareKeyStubRemoveAction => 'Hapus stub';

  @override
  String get hardwareKeyStubPickerTooltip =>
      'Regenerasi key ini di perangkat ini sebelum dipakai';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return 'Temukan modul PKCS#11 untuk token \"$token\"';
  }
}
