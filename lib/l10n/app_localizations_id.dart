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
  String get paste => 'Tempel';

  @override
  String get select => 'Pilih';

  @override
  String get required => 'Wajib';

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
  String get enterMasterPasswordPrompt => 'Masukkan kata sandi utama:';

  @override
  String get nextStep => 'Berikutnya';

  @override
  String get includeCredentials => 'Sertakan kata sandi dan kunci SSH';

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
      'Kata sandi akan tidak terenkripsi dalam kode QR. Siapa pun yang memindai dapat melihatnya.';

  @override
  String get sshKeysMayBeLarge => 'Kunci dapat melebihi ukuran QR';

  @override
  String exportTotalSize(String size) {
    return 'Ukuran total: $size';
  }

  @override
  String get qrCredentialsWarning =>
      'Kata sandi dan kunci SSH AKAN terlihat di kode QR';

  @override
  String get qrCredentialsTooLarge =>
      'Kredensial membuat kode QR terlalu besar';

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
  String get downloadComplete => 'Unduhan selesai';

  @override
  String get installNow => 'Pasang Sekarang';

  @override
  String get couldNotOpenInstaller => 'Tidak dapat membuka penginstal';

  @override
  String versionAvailable(String version) {
    return 'Versi $version tersedia';
  }

  @override
  String currentVersion(String version) {
    return 'Saat ini: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'Kunci SSH diterima: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return '$count sesi diimpor via QR';
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
  String get noSessionsToExport => 'Tidak ada sesi untuk diekspor';

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
  String get options => 'Opsi';

  @override
  String get sessionName => 'Nama Sesi';

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
  String get hidePemText => 'Sembunyikan teks PEM';

  @override
  String get pastePemKeyText => 'Tempel teks kunci PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'Belum ada opsi tambahan';

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
  String get qrGenerationFailed => 'Pembuatan QR gagal';

  @override
  String get scanWithCameraApp =>
      'Pindai dengan aplikasi kamera di perangkat\nyang telah memasang LetsFLUTssh.';

  @override
  String get noPasswordsInQr =>
      'Tidak ada kata sandi atau kunci dalam kode QR ini';

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
  String get acceptAnyway => 'Terima Saja';

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
  String errorPrefix(String error) {
    return 'Kesalahan: $error';
  }

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
  String get controllersNotInitialized => 'Kontroler belum diinisialisasi';

  @override
  String get initializingSftp => 'Menginisialisasi SFTP...';

  @override
  String get clearHistory => 'Hapus riwayat';

  @override
  String get noTransfersYet => 'Belum ada transfer';

  @override
  String get duplicateTab => 'Duplikat Tab';

  @override
  String get duplicateTabShortcut => 'Duplikat Tab (Ctrl+\\)';

  @override
  String get copyDown => 'Salin ke Bawah';

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
  String get sortByName => 'Urutkan berdasarkan Nama';

  @override
  String get sortByStatus => 'Urutkan berdasarkan Status';

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
  String get parallelWorkers => 'Pekerja Paralel';

  @override
  String get maxHistory => 'Riwayat Maksimal';

  @override
  String get calculateFolderSizes => 'Hitung Ukuran Folder';

  @override
  String get exportData => 'Ekspor Data';

  @override
  String get exportDataSubtitle =>
      'Simpan sesi, konfigurasi, dan kunci ke file .lfs terenkripsi';

  @override
  String get importDataSubtitle => 'Muat data dari file .lfs';

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
  String sshConfigPreviewFolderLabel(String folder) {
    return 'Diimpor ke folder: $folder';
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
  String get hintLfsPath => '/path/to/export.lfs';

  @override
  String get browse => 'Telusuri';

  @override
  String get shareViaQrCode => 'Bagikan via Kode QR';

  @override
  String get shareViaQrSubtitle =>
      'Ekspor sesi ke kode QR untuk dipindai perangkat lain';

  @override
  String get dataLocation => 'Lokasi Data';

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
  String get enableLogging => 'Aktifkan Log';

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
  String get remote => 'Jarak Jauh';

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
  String get anotherInstanceRunning =>
      'Instance LetsFLUTssh lain sudah berjalan.';

  @override
  String importFailedShort(String error) {
    return 'Impor gagal: $error';
  }

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
  String get qrNoCredentialsWarning =>
      'Kata sandi dan kunci SSH TIDAK disertakan.\nSesi yang diimpor perlu diisi kredensialnya.';

  @override
  String get qrTooManyForSingleCode =>
      'Terlalu banyak sesi untuk satu kode QR. Batalkan beberapa pilihan atau gunakan ekspor .lfs.';

  @override
  String get qrTooLarge =>
      'Terlalu besar — batalkan beberapa item atau gunakan ekspor file .lfs.';

  @override
  String get exportAll => 'Ekspor Semua';

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
  String get errBadFileDescriptor => 'Deskriptor file buruk';

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
  String get errNotADirectory => 'Bukan sebuah direktori';

  @override
  String get errIsADirectory => 'Adalah sebuah direktori';

  @override
  String get errInvalidArgument => 'Argumen tidak valid';

  @override
  String get errTooManyOpenFiles => 'Terlalu banyak file terbuka';

  @override
  String get errNoSpaceLeftOnDevice => 'Tidak ada ruang tersisa di perangkat';

  @override
  String get errReadOnlyFileSystem => 'Sistem file hanya-baca';

  @override
  String get errBrokenPipe => 'Pipa rusak';

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
  String get errConnectionResetByPeer => 'Koneksi direset oleh rekan';

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
  String errShellError(String error) {
    return 'Kesalahan shell: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'Gagal menghubungkan ulang: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'Gagal menginisialisasi SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Unduhan gagal: $error';
  }

  @override
  String get errDecryptionFailed =>
      'Gagal mendekripsi kredensial. File kunci mungkin rusak.';

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
  String get storagePermissionRequired =>
      'Izin penyimpanan diperlukan untuk menjelajahi file lokal';

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
  String get transferStartingUpload => 'Memulai unggah...';

  @override
  String get transferStartingDownload => 'Memulai unduh...';

  @override
  String get transferCopying => 'Menyalin...';

  @override
  String get transferDone => 'Selesai';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total file';
  }

  @override
  String get folderNameLabel => 'NAMA FOLDER';

  @override
  String folderAlreadyExists(String name) {
    return 'Folder \"$name\" sudah ada';
  }

  @override
  String get dropKeyFileHere => 'Seret file kunci ke sini';

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
  String get sshConnectionChannel => 'Koneksi SSH';

  @override
  String get sshConnectionChannelDesc =>
      'Menjaga koneksi SSH tetap aktif di latar belakang.';

  @override
  String get sshActive => 'SSH aktif';

  @override
  String activeConnectionCount(int count) {
    return '$count koneksi aktif';
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
  String get importKnownHosts => 'Impor host dikenal';

  @override
  String get importKnownHostsSubtitle => 'Impor dari file OpenSSH known_hosts';

  @override
  String get exportKnownHosts => 'Ekspor host dikenal';

  @override
  String importedHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count host baru diimpor',
      zero: 'Tidak ada host baru diimpor',
    );
    return '$_temp0';
  }

  @override
  String get clearedAllHosts => 'Semua host dikenal telah dihapus';

  @override
  String removedHost(String host) {
    return '$host dihapus';
  }

  @override
  String get noHostsToExport => 'Tidak ada host untuk diekspor';

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
  String get pastePrivateKey => 'Tempel kunci privat (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Data kunci PEM tidak valid';

  @override
  String get selectFromKeyStore => 'Pilih dari penyimpanan kunci';

  @override
  String get noKeySelected => 'Tidak ada kunci dipilih';

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
  String get passphraseRequired => 'Frasa sandi diperlukan';

  @override
  String passphrasePrompt(String host) {
    return 'Kunci SSH untuk $host terenkripsi. Masukkan frasa sandi untuk membukanya.';
  }

  @override
  String get passphraseWrong => 'Frasa sandi salah. Silakan coba lagi.';

  @override
  String get passphrase => 'Frasa sandi';

  @override
  String get rememberPassphrase => 'Ingat untuk sesi ini';

  @override
  String get unlock => 'Buka kunci';

  @override
  String get masterPasswordSubtitle =>
      'Lindungi kredensial tersimpan dengan kata sandi';

  @override
  String get setMasterPassword => 'Atur kata sandi utama';

  @override
  String get changeMasterPassword => 'Ubah kata sandi utama';

  @override
  String get removeMasterPassword => 'Hapus kata sandi utama';

  @override
  String get masterPasswordEnabled => 'Kredensial dilindungi kata sandi utama';

  @override
  String get masterPasswordDisabled =>
      'Kredensial menggunakan kunci otomatis (tanpa kata sandi)';

  @override
  String get enterMasterPassword =>
      'Masukkan kata sandi utama untuk mengakses kredensial tersimpan.';

  @override
  String get wrongMasterPassword => 'Kata sandi salah. Silakan coba lagi.';

  @override
  String get newPassword => 'Kata sandi baru';

  @override
  String get currentPassword => 'Kata sandi saat ini';

  @override
  String get passwordTooShort => 'Kata sandi minimal 8 karakter';

  @override
  String get masterPasswordSet => 'Kata sandi utama diaktifkan';

  @override
  String get masterPasswordChanged => 'Kata sandi utama diubah';

  @override
  String get masterPasswordRemoved => 'Kata sandi utama dihapus';

  @override
  String get masterPasswordWarning =>
      'Jika Anda lupa kata sandi ini, semua kata sandi dan kunci SSH tersimpan akan hilang. Tidak ada pemulihan.';

  @override
  String get forgotPassword => 'Lupa kata sandi?';

  @override
  String get forgotPasswordWarning =>
      'Ini akan menghapus SEMUA kata sandi, kunci SSH, dan frasa sandi tersimpan. Sesi dan pengaturan akan dipertahankan. Tindakan ini tidak dapat dibatalkan.';

  @override
  String get resetAndDeleteCredentials => 'Reset dan hapus data';

  @override
  String get credentialsReset => 'Semua kredensial tersimpan telah dihapus';

  @override
  String get derivingKey => 'Membuat kunci enkripsi...';

  @override
  String get reEncrypting => 'Mengenkripsi ulang data...';

  @override
  String get confirmRemoveMasterPassword =>
      'Masukkan kata sandi saat ini untuk menghapus perlindungan kata sandi utama. Kredensial akan dienkripsi ulang dengan kunci otomatis.';

  @override
  String get securitySetupTitle => 'Pengaturan keamanan';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'Rantai kunci sistem terdeteksi ($keychainName). Data Anda akan dienkripsi secara otomatis menggunakan rantai kunci sistem.';
  }

  @override
  String get securitySetupKeychainOptional =>
      'Anda juga bisa mengatur kata sandi utama untuk perlindungan tambahan.';

  @override
  String get securitySetupNoKeychain =>
      'Rantai kunci sistem tidak terdeteksi. Tanpa rantai kunci, data sesi (host, kata sandi, kunci) akan disimpan dalam teks biasa.';

  @override
  String get securitySetupNoKeychainHint =>
      'Ini normal di WSL, Linux tanpa GUI, atau instalasi minimal. Untuk mengaktifkan rantai kunci di Linux: instal libsecret dan daemon rantai kunci (cth. gnome-keyring).';

  @override
  String get securitySetupRecommendMasterPassword =>
      'Kami sarankan mengatur kata sandi utama untuk melindungi data Anda.';

  @override
  String get continueWithKeychain => 'Lanjutkan dengan rantai kunci';

  @override
  String get continueWithoutEncryption => 'Lanjutkan tanpa enkripsi';

  @override
  String get securityLevel => 'Tingkat keamanan';

  @override
  String get securityLevelPlaintext => 'Tidak ada (teks biasa)';

  @override
  String get securityLevelKeychain => 'Rantai kunci sistem';

  @override
  String get securityLevelMasterPassword => 'Kata sandi utama';

  @override
  String get keychainStatus => 'Rantai kunci';

  @override
  String keychainAvailable(String name) {
    return 'Tersedia ($name)';
  }

  @override
  String get keychainNotAvailable => 'Tidak tersedia';

  @override
  String get enableKeychain => 'Aktifkan enkripsi rantai kunci';

  @override
  String get enableKeychainSubtitle =>
      'Enkripsi ulang data tersimpan menggunakan rantai kunci sistem';

  @override
  String get keychainEnabled => 'Enkripsi rantai kunci diaktifkan';

  @override
  String get manageMasterPassword => 'Kelola kata sandi utama';

  @override
  String get manageMasterPasswordSubtitle =>
      'Atur, ubah, atau hapus kata sandi utama';

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
  String get fullBackup => 'Cadangan lengkap';

  @override
  String get sessionsOnly => 'Sesi';

  @override
  String get sessionKeysFromManager => 'Kunci sesi dari manajer';

  @override
  String get allKeysFromManager => 'Semua kunci dari manajer';

  @override
  String exportTags(int count) {
    return 'Tag ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'Cuplikan ($count)';
  }

  @override
  String get disableKeychain => 'Nonaktifkan enkripsi keychain';

  @override
  String get disableKeychainSubtitle =>
      'Beralih ke penyimpanan teks biasa (tidak disarankan)';

  @override
  String get disableKeychainConfirm =>
      'Basis data akan dienkripsi ulang tanpa kunci. Sesi dan kunci akan disimpan dalam teks biasa di disk. Lanjutkan?';

  @override
  String get keychainDisabled => 'Enkripsi keychain dinonaktifkan';

  @override
  String get presetFullImport => 'Impor lengkap';

  @override
  String get presetSelective => 'Selektif';

  @override
  String get presetCustom => 'Kustom';

  @override
  String get sessionSshKeys => 'Kunci SSH sesi';

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
  String get parallelWorkersSubtitle => 'Pekerja transfer SFTP paralel';

  @override
  String get maxHistorySubtitle => 'Maksimum perintah tersimpan di riwayat';

  @override
  String get calculateFolderSizesSubtitle =>
      'Tampilkan ukuran total di samping folder di bilah sisi';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Cek rilis baru di GitHub saat aplikasi dijalankan';

  @override
  String get enableLoggingSubtitle =>
      'Tulis peristiwa aplikasi ke berkas log berotasi';
}
