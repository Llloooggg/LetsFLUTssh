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
      'Terlalu besar — batalkan beberapa sesi atau gunakan ekspor file .lfs.';

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
  String get maximize => 'Maksimalkan';

  @override
  String get restore => 'Pulihkan';

  @override
  String get duplicateDownShortcut => 'Duplikat ke Bawah (Ctrl+Shift+\\)';
}
