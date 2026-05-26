// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class SVi extends S {
  SVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'OK';

  @override
  String get infoDialogProtectsHeader => 'Bảo vệ khỏi';

  @override
  String get infoDialogDoesNotProtectHeader => 'Không bảo vệ khỏi';

  @override
  String get cancel => 'Hủy';

  @override
  String get close => 'Đóng';

  @override
  String get delete => 'Xóa';

  @override
  String get save => 'Lưu';

  @override
  String get connect => 'Kết nối';

  @override
  String get retry => 'Thử lại';

  @override
  String get import_ => 'Nhập';

  @override
  String get export_ => 'Xuất';

  @override
  String get rename => 'Đổi tên';

  @override
  String get create => 'Tạo';

  @override
  String get back => 'Quay lại';

  @override
  String get copy => 'Sao chép';

  @override
  String get cut => 'Cắt';

  @override
  String get paste => 'Dán';

  @override
  String get select => 'Chọn';

  @override
  String get copyModeTapToStart => 'Chạm để đánh dấu điểm bắt đầu';

  @override
  String get copyModeExtending => 'Kéo để mở rộng vùng chọn';

  @override
  String get copyModeSetAnchor => 'Đặt mỏ neo';

  @override
  String get copyModeCopySelection => 'Sao chép vùng chọn';

  @override
  String get required => 'Bắt buộc';

  @override
  String get errFillRequiredFields => 'Điền các trường bắt buộc đánh dấu *';

  @override
  String get settings => 'Cài đặt';

  @override
  String get appSettings => 'Cài đặt ứng dụng';

  @override
  String get yes => 'Có';

  @override
  String get no => 'Không';

  @override
  String get importWhatToImport => 'Những gì cần nhập:';

  @override
  String get exportWhatToExport => 'Những gì cần xuất:';

  @override
  String get enterMasterPasswordPrompt => 'Nhập mật khẩu chính:';

  @override
  String get nextStep => 'Tiếp theo';

  @override
  String get includePasswords => 'Mật khẩu phiên';

  @override
  String get embeddedKeys => 'Khóa nhúng';

  @override
  String get managerKeys => 'Khóa từ trình quản lý';

  @override
  String get managerKeysMayBeLarge =>
      'Khóa trình quản lý có thể vượt quá kích thước QR';

  @override
  String get qrPasswordWarning => 'Khóa SSH bị tắt theo mặc định khi xuất.';

  @override
  String get sshKeysMayBeLarge => 'Khóa có thể vượt quá kích thước QR';

  @override
  String exportTotalSize(String size) {
    return 'Tổng kích thước: $size';
  }

  @override
  String get terminal => 'Terminal';

  @override
  String get files => 'Tệp';

  @override
  String get transfer => 'Truyền tệp';

  @override
  String get open => 'Mở';

  @override
  String get search => 'Tìm kiếm...';

  @override
  String get noResults => 'Không có kết quả';

  @override
  String get filter => 'Lọc...';

  @override
  String get merge => 'Gộp';

  @override
  String get replace => 'Thay thế';

  @override
  String get reconnect => 'Kết nối lại';

  @override
  String get updateAvailable => 'Có bản cập nhật';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'Phiên bản $version đã có sẵn (hiện tại: v$current).';
  }

  @override
  String get releaseNotes => 'Ghi chú phát hành:';

  @override
  String get skipThisVersion => 'Bỏ qua phiên bản này';

  @override
  String get unskip => 'Hủy bỏ qua';

  @override
  String get downloadAndInstall => 'Tải về & Cài đặt';

  @override
  String get openInBrowser => 'Mở trong trình duyệt';

  @override
  String get couldNotOpenBrowser =>
      'Không thể mở trình duyệt — URL đã được sao chép vào bộ nhớ tạm';

  @override
  String get checkForUpdates => 'Kiểm tra cập nhật';

  @override
  String get checkNow => 'Kiểm tra ngay';

  @override
  String get checkForUpdatesOnStartup => 'Kiểm tra cập nhật khi khởi động';

  @override
  String get checking => 'Đang kiểm tra...';

  @override
  String get youreUpToDate => 'Bạn đang dùng phiên bản mới nhất';

  @override
  String get updateCheckFailed => 'Kiểm tra cập nhật thất bại';

  @override
  String get unknownError => 'Lỗi không xác định';

  @override
  String downloadingPercent(int percent) {
    return 'Đang tải... $percent%';
  }

  @override
  String get updateVerifying => 'Đang xác thực…';

  @override
  String get downloadComplete => 'Tải xuống hoàn tất';

  @override
  String get installNow => 'Cài đặt ngay';

  @override
  String get openReleasePage => 'Mở trang phát hành';

  @override
  String get couldNotOpenInstaller => 'Không thể mở trình cài đặt';

  @override
  String get installerFailedOpenedReleasePage =>
      'Không thể khởi chạy trình cài đặt; đã mở trang phát hành trong trình duyệt';

  @override
  String versionAvailable(String version) {
    return 'Phiên bản $version có sẵn';
  }

  @override
  String currentVersion(String version) {
    return 'Hiện tại: v$version';
  }

  @override
  String importedSessions(int count) {
    return 'Đã nhập $count phiên';
  }

  @override
  String importFailed(String error) {
    return 'Nhập thất bại: $error';
  }

  @override
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã bỏ qua $count liên kết (mục tiêu không tồn tại)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã bỏ qua $count phiên bị hỏng',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'Phiên';

  @override
  String get emptyFolders => 'Thư mục trống';

  @override
  String get sessionsHeader => 'PHIÊN';

  @override
  String get savedSessions => 'Phiên đã lưu';

  @override
  String get activeConnections => 'Kết nối đang hoạt động';

  @override
  String get openTabs => 'Tab đang mở';

  @override
  String get noSavedSessions => 'Không có phiên đã lưu';

  @override
  String get addSession => 'Thêm phiên';

  @override
  String get noSessions => 'Không có phiên';

  @override
  String nSelectedCount(int count) {
    return 'Đã chọn $count';
  }

  @override
  String get selectAll => 'Chọn tất cả';

  @override
  String get deselectAll => 'Bỏ chọn tất cả';

  @override
  String get moveTo => 'Di chuyển đến...';

  @override
  String get moveToFolder => 'Di chuyển đến thư mục';

  @override
  String get rootFolder => '/ (gốc)';

  @override
  String get newFolder => 'Thư mục mới';

  @override
  String get newConnection => 'Kết nối mới';

  @override
  String get editConnection => 'Sửa kết nối';

  @override
  String get duplicate => 'Nhân bản';

  @override
  String get deleteSession => 'Xóa phiên';

  @override
  String get renameFolder => 'Đổi tên thư mục';

  @override
  String get deleteFolder => 'Xóa thư mục';

  @override
  String get deleteSelected => 'Xóa mục đã chọn';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return 'Xóa $parts?\n\nThao tác này không thể hoàn tác.';
  }

  @override
  String nSessions(int count) {
    return '$count phiên';
  }

  @override
  String nFolders(int count) {
    return '$count thư mục';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'Xóa thư mục \"$name\"?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'Sẽ xóa luôn $count phiên bên trong.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return 'Xóa \"$name\"?';
  }

  @override
  String get connection => 'Kết nối';

  @override
  String get auth => 'Xác thực';

  @override
  String get sectionAuthentication => 'Xác thực';

  @override
  String get sectionAdvanced => 'Nâng cao';

  @override
  String get moreOptions => 'Tùy chọn khác';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString quy tắc port forwarding',
      zero: 'Không có quy tắc port forwarding',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => 'Quản lý…';

  @override
  String get authMethodAgent => 'Dùng ssh-agent hệ thống';

  @override
  String get options => 'Tùy chọn';

  @override
  String get sessionName => 'Tên phiên';

  @override
  String get sessionNameAutoFromHost => 'Tự động từ host';

  @override
  String get sessionNameAutoFromUrl => 'Tự động từ host của URL';

  @override
  String get sessionNameAutoFromBucket => 'Tự động từ bucket mặc định';

  @override
  String get hintMyServer => 'Máy chủ của tôi';

  @override
  String get hostRequired => 'Máy chủ *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'Cổng';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'Tên đăng nhập *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'Mật khẩu';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'Key passphrase';

  @override
  String get hintOptional => 'Tùy chọn';

  @override
  String get savedTypeToChange => 'Đã lưu — nhập để thay đổi';

  @override
  String get hidePemText => 'Ẩn văn bản PEM';

  @override
  String get pastePemKeyText => 'Dán văn bản khóa PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get saveAndConnect => 'Lưu & Kết nối';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst => 'Cung cấp tệp khóa hoặc văn bản PEM trước';

  @override
  String get keyTextPem => 'Văn bản khóa (PEM)';

  @override
  String get selectKeyFile => 'Chọn tệp khóa';

  @override
  String get clearKeyFile => 'Xóa tệp khóa';

  @override
  String get authOrDivider => 'HOẶC';

  @override
  String get providePasswordOrKey => 'Cung cấp mật khẩu hoặc khóa SSH';

  @override
  String get quickConnect => 'Kết nối nhanh';

  @override
  String get scanQrCode => 'Quét mã QR';

  @override
  String get emptyFolder => 'Thư mục trống';

  @override
  String get qrGenerationFailed => 'Tạo mã QR thất bại';

  @override
  String get scanWithCameraApp =>
      'Quét bằng ứng dụng camera trên thiết bị\ncó cài LetsFLUTssh.';

  @override
  String get noPasswordsInQr => 'Không có mật khẩu hoặc khóa trong mã QR này';

  @override
  String get qrContainsCredentialsWarning =>
      'Mã QR này chứa thông tin xác thực. Giữ màn hình riêng tư.';

  @override
  String get copyLink => 'Sao chép liên kết';

  @override
  String get linkCopied => 'Đã sao chép liên kết vào bộ nhớ tạm';

  @override
  String get hostKeyChanged => 'Host key đã thay đổi!';

  @override
  String get unknownHost => 'Máy chủ không xác định';

  @override
  String get hostKeyChangedWarning =>
      'CẢNH BÁO: Host key của server này đã thay đổi. Có thể là dấu hiệu tấn công man-in-the-middle, hoặc server đã được cài lại.';

  @override
  String get unknownHostMessage =>
      'Không thể xác minh danh tính của máy chủ này. Bạn có chắc muốn tiếp tục kết nối?';

  @override
  String get host => 'Máy chủ';

  @override
  String get keyType => 'Loại khóa';

  @override
  String get fingerprint => 'Fingerprint';

  @override
  String get fingerprintCopied => 'Đã sao chép fingerprint';

  @override
  String get copyFingerprint => 'Sao chép fingerprint';

  @override
  String get acceptAnyway => 'Vẫn chấp nhận';

  @override
  String get accept => 'Chấp nhận';

  @override
  String get importData => 'Nhập dữ liệu';

  @override
  String get masterPassword => 'Mật khẩu chính';

  @override
  String get confirmPassword => 'Xác nhận mật khẩu';

  @override
  String get importModeMergeDescription => 'Thêm phiên mới, giữ phiên hiện có';

  @override
  String get importModeReplaceDescription =>
      'Thay thế tất cả phiên bằng phiên nhập vào';

  @override
  String get folderName => 'Tên thư mục';

  @override
  String get newName => 'Tên mới';

  @override
  String deleteItems(String names) {
    return 'Xóa $names?';
  }

  @override
  String deleteNItems(int count) {
    return 'Xóa $count mục';
  }

  @override
  String deletedItem(String name) {
    return 'Đã xóa $name';
  }

  @override
  String deletedNItems(int count) {
    return 'Đã xóa $count mục';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'Không thể tạo thư mục: $error';
  }

  @override
  String failedToRename(String error) {
    return 'Đổi tên thất bại: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return 'Không thể xóa $name: $error';
  }

  @override
  String get editPath => 'Sửa đường dẫn';

  @override
  String get root => 'Gốc';

  @override
  String get controllersNotInitialized => 'Bộ điều khiển chưa được khởi tạo';

  @override
  String get clearHistory => 'Xóa lịch sử';

  @override
  String get noTransfersYet => 'Chưa có lần truyền tệp nào';

  @override
  String get duplicateTab => 'Nhân bản tab';

  @override
  String get duplicateTabShortcut => 'Nhân bản tab (Ctrl+\\)';

  @override
  String get previous => 'Trước';

  @override
  String get next => 'Tiếp';

  @override
  String get closeEsc => 'Đóng (Esc)';

  @override
  String get closeAll => 'Đóng tất cả';

  @override
  String get closeOthers => 'Đóng các tab khác';

  @override
  String get closeTabsToTheLeft => 'Đóng các tab bên trái';

  @override
  String get closeTabsToTheRight => 'Đóng các tab bên phải';

  @override
  String get noActiveSession => 'Không có phiên đang hoạt động';

  @override
  String get createConnectionHint =>
      'Tạo kết nối mới hoặc chọn một kết nối từ thanh bên';

  @override
  String get hideSidebar => 'Ẩn thanh bên (Ctrl+B)';

  @override
  String get showSidebar => 'Hiện thanh bên (Ctrl+B)';

  @override
  String get language => 'Ngôn ngữ';

  @override
  String get languageSystemDefault => 'Tự động';

  @override
  String get theme => 'Giao diện';

  @override
  String get themeDark => 'Tối';

  @override
  String get themeLight => 'Sáng';

  @override
  String get themeSystem => 'Hệ thống';

  @override
  String get appearance => 'Giao diện';

  @override
  String get connectionSection => 'Kết nối';

  @override
  String get transfers => 'Truyền tệp';

  @override
  String get data => 'Dữ liệu';

  @override
  String get logging => 'Log';

  @override
  String get updates => 'Cập nhật';

  @override
  String get about => 'Giới thiệu';

  @override
  String get resetToDefaults => 'Đặt lại mặc định';

  @override
  String get uiScale => 'Tỷ lệ giao diện';

  @override
  String get terminalFontSize => 'Cỡ chữ Terminal';

  @override
  String get scrollbackLines => 'Số dòng cuộn lại';

  @override
  String get keepAliveInterval => 'Khoảng giữ kết nối (giây)';

  @override
  String get sshTimeout => 'Thời gian chờ SSH (giây)';

  @override
  String get defaultPort => 'Cổng mặc định';

  @override
  String get parallelWorkers => 'Luồng song song';

  @override
  String get maxHistory => 'Lịch sử tối đa';

  @override
  String get calculateFolderSizes => 'Tính kích thước thư mục';

  @override
  String get verboseConnectionLog => 'Nhật ký kết nối chi tiết';

  @override
  String get verboseConnectionLogSubtitle =>
      'Ghi toàn bộ trace handshake SSH và xác thực vào tệp log (để chẩn đoán lỗi kết nối)';

  @override
  String get exportData => 'Xuất dữ liệu';

  @override
  String get exportRecordings => 'Bản ghi phiên';

  @override
  String sshConfigPreviewHostsFound(int count) {
    return 'Đã tìm thấy $count host';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'Không tìm thấy host nào có thể nhập trong tệp này.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'Không thể đọc tệp khóa cho: $hosts. Các host này sẽ được nhập mà không có thông tin xác thực.';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'Xuất kho lưu trữ';

  @override
  String get exportArchiveSubtitle =>
      'Lưu phiên, cấu hình và khóa vào tệp .lfs được mã hóa';

  @override
  String get exportQrCode => 'Xuất mã QR';

  @override
  String get exportQrCodeSubtitle => 'Chia sẻ phiên và khóa đã chọn qua mã QR';

  @override
  String get importArchive => 'Nhập kho lưu trữ';

  @override
  String get importArchiveSubtitle => 'Tải dữ liệu từ tệp .lfs';

  @override
  String get importFromSshDir => 'Nhập từ ~/.ssh';

  @override
  String get importFromSshDirSubtitle =>
      'Chọn các máy chủ từ tệp cấu hình và/hoặc khóa riêng tư từ ~/.ssh';

  @override
  String get sshDirImportHostsSection => 'Máy chủ từ tệp cấu hình';

  @override
  String get sshDirImportKeysSection => 'Khóa trong ~/.ssh';

  @override
  String importSshKeysFound(int count) {
    return 'Đã tìm thấy $count khóa — chọn khóa nào để nhập';
  }

  @override
  String get importSshKeysNoneFound =>
      'Không tìm thấy khóa riêng tư nào trong ~/.ssh.';

  @override
  String get sshKeyAlreadyImported => 'đã có trong kho';

  @override
  String get setMasterPasswordHint =>
      'Đặt mật khẩu chính để mã hóa kho lưu trữ.';

  @override
  String get passwordsDoNotMatch => 'Mật khẩu không khớp';

  @override
  String get passwordStrengthWeak => 'Yếu';

  @override
  String get passwordStrengthModerate => 'Trung bình';

  @override
  String get passwordStrengthStrong => 'Mạnh';

  @override
  String get passwordStrengthVeryStrong => 'Rất mạnh';

  @override
  String get tierPlaintextLabel => 'Plaintext';

  @override
  String get tierPlaintextSubtitle =>
      'Không mã hóa — chỉ dựa vào file permissions';

  @override
  String get tierKeychainLabel => 'Keychain';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'Khóa nằm trong $keychain — tự động mở khóa khi khởi chạy';
  }

  @override
  String get tierKeychainUnavailable =>
      'Keychain của HĐH không khả dụng trên bản cài đặt này.';

  @override
  String get tierHardwareLabel => 'Phần cứng';

  @override
  String get tierParanoidLabel => 'Mật khẩu chính (Paranoid)';

  @override
  String get tierHardwareUnavailable =>
      'Hardware vault không khả dụng trên bản cài này.';

  @override
  String get pinLabel => 'Mật khẩu';

  @override
  String get l2UnlockTitle => 'Cần mật khẩu';

  @override
  String get l2UnlockHint => 'Nhập mật khẩu ngắn để tiếp tục';

  @override
  String get l2WrongPassword => 'Sai mật khẩu';

  @override
  String get l3UnlockTitle => 'Nhập mật khẩu';

  @override
  String get l3UnlockHint => 'Mật khẩu mở khóa kho liên kết phần cứng';

  @override
  String get l3WrongPin => 'Sai mật khẩu';

  @override
  String tierCooldownHint(int seconds) {
    return 'Thử lại sau $seconds giây';
  }

  @override
  String exportedTo(String path) {
    return 'Đã xuất đến: $path';
  }

  @override
  String exportFailed(String error) {
    return 'Xuất thất bại: $error';
  }

  @override
  String get pathToLfsFile => 'Đường dẫn tệp .lfs';

  @override
  String get dataLocation => 'Vị trí dữ liệu';

  @override
  String get dataStorageSection => 'Lưu trữ';

  @override
  String get pathCopied => 'Đã sao chép đường dẫn vào bộ nhớ tạm';

  @override
  String get urlCopied => 'Đã sao chép URL vào bộ nhớ tạm';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — Ứng dụng SSH/SFTP';
  }

  @override
  String get sourceCode => 'Mã nguồn';

  @override
  String get logIsEmpty => 'Log trống';

  @override
  String logExportedTo(String path) {
    return 'Đã xuất nhật ký đến: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Xuất nhật ký thất bại: $error';
  }

  @override
  String get logsCleared => 'Đã xóa log';

  @override
  String get copiedToClipboard => 'Đã sao chép vào bộ nhớ tạm';

  @override
  String get copyLog => 'Copy log';

  @override
  String get exportLog => 'Xuất log';

  @override
  String get clearLogs => 'Xóa log';

  @override
  String get local => 'Nội bộ';

  @override
  String get remote => 'Từ xa';

  @override
  String get pickFolder => 'Chọn thư mục';

  @override
  String get refresh => 'Làm mới';

  @override
  String get up => 'Lên';

  @override
  String get emptyDirectory => 'Thư mục trống';

  @override
  String get cancelSelection => 'Hủy chọn';

  @override
  String get openSftpBrowser => 'Mở trình duyệt SFTP';

  @override
  String get openSshTerminal => 'Mở Terminal SSH';

  @override
  String get noActiveFileBrowsers => 'Không có trình duyệt tệp đang hoạt động';

  @override
  String get useSftpFromSessions => 'Sử dụng \"SFTP\" từ Phiên';

  @override
  String get saveLogAs => 'Lưu nhật ký thành';

  @override
  String get chooseSaveLocation => 'Chọn vị trí lưu';

  @override
  String get forward => 'Tiến';

  @override
  String get name => 'Tên';

  @override
  String get size => 'Kích thước';

  @override
  String get modified => 'Ngày sửa';

  @override
  String get mode => 'Quyền';

  @override
  String get owner => 'Chủ sở hữu';

  @override
  String get connectionError => 'Lỗi kết nối';

  @override
  String get resizeWindowToViewFiles => 'Thay đổi kích thước cửa sổ để xem tệp';

  @override
  String get completed => 'Hoàn thành';

  @override
  String get connected => 'Đã kết nối';

  @override
  String get disconnected => 'Đã ngắt kết nối';

  @override
  String a11yConnectingTo(String host) {
    return 'Đang kết nối đến $host';
  }

  @override
  String a11yConnectedTo(String host) {
    return 'Đã kết nối đến $host';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return 'Đã ngắt kết nối khỏi $host';
  }

  @override
  String a11yConnectionFailed(String host) {
    return 'Kết nối đến $host thất bại';
  }

  @override
  String get exit => 'Thoát';

  @override
  String get exitConfirmation =>
      'Các phiên đang hoạt động sẽ bị ngắt kết nối. Thoát?';

  @override
  String get hintFolderExample => 'ví dụ: Production';

  @override
  String get credentialsNotSet => 'Chưa có credential';

  @override
  String get exportSessionsViaQr => 'Xuất phiên qua QR';

  @override
  String get qrTooManyForSingleCode =>
      'Quá nhiều phiên cho một mã QR. Bỏ chọn một số hoặc sử dụng xuất .lfs.';

  @override
  String get qrTooLarge =>
      'Quá lớn — bỏ chọn một số mục hoặc sử dụng xuất tệp .lfs.';

  @override
  String get showQr => 'Hiện QR';

  @override
  String get sort => 'Sắp xếp';

  @override
  String get resizePanelDivider => 'Thay đổi kích thước thanh phân chia';

  @override
  String get youreRunningLatest => 'Bạn đang sử dụng phiên bản mới nhất';

  @override
  String get liveLog => 'Live log';

  @override
  String get archivedLog => 'Log lưu trữ';

  @override
  String get loggingLevel => 'Mức log';

  @override
  String get loggingLevelSubtitleInfo => 'Mục thường + cảnh báo + lỗi';

  @override
  String get loggingLevelSubtitleWarn => 'Chỉ đường dẫn suy giảm và lỗi';

  @override
  String get loggingLevelSubtitleError => 'Chỉ lỗi';

  @override
  String get loggingLevelSubtitleOff => 'Không ghi log thường';

  @override
  String transferNItems(int count) {
    return 'Truyền $count mục';
  }

  @override
  String get time => 'Thời gian';

  @override
  String get failed => 'Thất bại';

  @override
  String get errOperationNotPermitted => 'Thao tác không được phép';

  @override
  String get errNoSuchFileOrDirectory => 'Không tìm thấy tệp hoặc thư mục';

  @override
  String get errNoSuchProcess => 'Không tìm thấy tiến trình';

  @override
  String get errIoError => 'Lỗi I/O';

  @override
  String get errBadFileDescriptor => 'File descriptor không hợp lệ';

  @override
  String get errResourceTemporarilyUnavailable =>
      'Tài nguyên tạm thời không khả dụng';

  @override
  String get errOutOfMemory => 'Hết bộ nhớ';

  @override
  String get errPermissionDenied => 'Quyền truy cập bị từ chối';

  @override
  String get errFileExists => 'Tệp đã tồn tại';

  @override
  String get errNotADirectory => 'Không phải thư mục';

  @override
  String get errIsADirectory => 'Là một thư mục';

  @override
  String get errInvalidArgument => 'Đối số không hợp lệ';

  @override
  String get errTooManyOpenFiles => 'Quá nhiều tệp đang mở';

  @override
  String get errNoSpaceLeftOnDevice =>
      'Không còn dung lượng trống trên thiết bị';

  @override
  String get errReadOnlyFileSystem => 'Hệ thống tệp chỉ đọc';

  @override
  String get errBrokenPipe => 'Broken pipe';

  @override
  String get errFileNameTooLong => 'Tên tệp quá dài';

  @override
  String get errDirectoryNotEmpty => 'Thư mục không trống';

  @override
  String get errAddressAlreadyInUse => 'Địa chỉ đã được sử dụng';

  @override
  String get errCannotAssignAddress => 'Không thể gán địa chỉ yêu cầu';

  @override
  String get errNetworkIsDown => 'Mạng không hoạt động';

  @override
  String get errNetworkIsUnreachable => 'Không thể truy cập mạng';

  @override
  String get errConnectionResetByPeer => 'Kết nối bị đặt lại bởi máy đối tác';

  @override
  String get errConnectionTimedOut => 'Kết nối đã hết thời gian chờ';

  @override
  String get errConnectionRefused => 'Kết nối bị từ chối';

  @override
  String get errHostIsDown => 'Máy chủ không hoạt động';

  @override
  String get errNoRouteToHost => 'Không tìm thấy đường đến máy chủ';

  @override
  String get errConnectionAborted => 'Kết nối bị hủy';

  @override
  String get errAlreadyConnected => 'Đã kết nối';

  @override
  String get errNotConnected => 'Chưa kết nối';

  @override
  String errSshConnectFailed(String host, int port) {
    return 'Không thể kết nối đến $host:$port';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return 'Xác thực thất bại cho $user@$host';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return 'Kết nối đến $host:$port thất bại';
  }

  @override
  String get errSshAuthAborted => 'Xác thực đã bị hủy';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return 'Khóa máy chủ bị từ chối cho $host:$port — chấp nhận khóa máy chủ hoặc kiểm tra known_hosts';
  }

  @override
  String get errSshOpenShellFailed => 'Không thể mở shell';

  @override
  String get errSshLoadKeyFileFailed => 'Không thể tải tệp khóa SSH';

  @override
  String get errSshParseKeyFailed => 'Không thể phân tích dữ liệu khóa PEM';

  @override
  String get errSshConnectionDisposed => 'Kết nối đã bị hủy';

  @override
  String get errSshNotConnected => 'Chưa kết nối';

  @override
  String get errConnectionFailed => 'Kết nối thất bại';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'Kết nối đã hết thời gian chờ sau $seconds giây';
  }

  @override
  String get errSessionClosed => 'Phiên đã đóng';

  @override
  String errSftpInitFailed(String error) {
    return 'Không thể khởi tạo SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Tải xuống thất bại: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'Bộ chọn thư mục của hệ thống không khả dụng. Hãy thử vị trí khác hoặc kiểm tra quyền lưu trữ của ứng dụng.';

  @override
  String get biometricUnlockPrompt => 'Mở khóa LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'Mở khóa bằng biometric';

  @override
  String get biometricUnlockSubtitle =>
      'Không cần nhập mật khẩu — mở khóa bằng cảm biến biometric của thiết bị.';

  @override
  String get biometricEnableFailed => 'Không thể bật mở khóa sinh trắc học.';

  @override
  String get biometricUnlockFailed =>
      'Mở khóa bằng sinh trắc học thất bại. Nhập mật khẩu chính của bạn.';

  @override
  String get biometricUnlockCancelled => 'Đã hủy mở khóa bằng sinh trắc học.';

  @override
  String get biometricNotEnrolled =>
      'Chưa đăng ký biometric nào trên thiết bị này.';

  @override
  String get biometricSensorNotAvailable =>
      'Thiết bị này không có cảm biến biometric.';

  @override
  String get biometricSystemServiceMissing =>
      'Dịch vụ vân tay (fprintd) chưa được cài đặt. Xem README → Installation.';

  @override
  String get currentPasswordIncorrect => 'Mật khẩu hiện tại không đúng';

  @override
  String get wrongPassword => 'Mật khẩu không đúng';

  @override
  String get lockScreenTitle => 'LetsFLUTssh đã bị khóa';

  @override
  String get lockScreenSubtitle =>
      'Nhập mật khẩu chính hoặc dùng sinh trắc học để tiếp tục.';

  @override
  String get unlock => 'Mở khóa';

  @override
  String get autoLockTitle => 'Tự động khóa khi không hoạt động';

  @override
  String get autoLockSubtitle =>
      'Khóa giao diện sau khoảng thời gian không hoạt động này. Khóa cơ sở dữ liệu sẽ bị xóa và kho lưu trữ mã hóa sẽ đóng lại sau mỗi lần khóa; các phiên đang hoạt động vẫn kết nối nhờ bộ nhớ đệm thông tin đăng nhập theo từng phiên, được xóa khi phiên kết thúc.';

  @override
  String get autoLockOff => 'Tắt';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes phút',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'Bản cập nhật bị từ chối: các tệp đã tải xuống không được ký bởi khóa phát hành được ghim trong ứng dụng. Điều này có thể có nghĩa là quá trình tải xuống đã bị giả mạo trên đường truyền, hoặc bản phát hành hiện tại không dành cho cài đặt này. KHÔNG cài đặt — thay vào đó, hãy cài đặt lại theo cách thủ công từ trang Phát hành chính thức.';

  @override
  String get errReleaseManifestUnavailable =>
      'Không lấy được manifest của release. Có thể do vấn đề mạng, hoặc release đang được publish. Thử lại sau vài phút.';

  @override
  String get updateSecurityWarningTitle => 'Xác minh cập nhật thất bại';

  @override
  String get updateReinstallAction => 'Mở trang phát hành';

  @override
  String get errLfsNotArchive =>
      'Tệp đã chọn không phải là tệp lưu trữ LetsFLUTssh.';

  @override
  String get errLfsDecryptFailed => 'Mật khẩu chính sai hoặc tệp .lfs bị hỏng';

  @override
  String get errLfsArchiveTruncated =>
      'Kho lưu trữ không hoàn chỉnh. Hãy tải lại hoặc xuất lại từ thiết bị gốc.';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'Tệp lưu trữ quá lớn ($sizeMb MB). Giới hạn là $limitMb MB — đã hủy trước khi giải mã để bảo vệ bộ nhớ.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'Mục known_hosts quá lớn ($sizeMb MB). Giới hạn là $limitMb MB — đã hủy để giữ cho thao tác nhập phản hồi nhanh.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'Nhập thất bại — dữ liệu của bạn đã được khôi phục về trạng thái trước khi nhập. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'Tệp lưu trữ sử dụng lược đồ v$found, nhưng bản dựng này chỉ hỗ trợ đến v$supported. Hãy cập nhật ứng dụng để nhập nó.';
  }

  @override
  String get progressReadingArchive => 'Đang đọc kho lưu trữ…';

  @override
  String get progressDecrypting => 'Đang giải mã…';

  @override
  String get progressCollectingData => 'Đang thu thập dữ liệu…';

  @override
  String get progressEncrypting => 'Đang mã hóa…';

  @override
  String get progressWritingArchive => 'Đang ghi kho lưu trữ…';

  @override
  String get progressWorking => 'Đang xử lý…';

  @override
  String get importFromLink => 'Nhập từ liên kết QR';

  @override
  String get importFromLinkSubtitle =>
      'Dán deep-link letsflutssh:// đã sao chép từ thiết bị khác';

  @override
  String get pasteImportLinkTitle => 'Dán liên kết nhập';

  @override
  String get pasteImportLinkDescription =>
      'Dán liên kết letsflutssh://import?d=… (hoặc payload thô) được tạo trên thiết bị khác. Không cần camera.';

  @override
  String get pasteFromClipboard => 'Dán từ bộ nhớ tạm';

  @override
  String get invalidImportLink =>
      'Liên kết không chứa payload LetsFLUTssh hợp lệ';

  @override
  String get importAction => 'Nhập';

  @override
  String get noTagsAvailable =>
      'Chưa có thẻ nào — tạo một thẻ trong Tools → Tags.';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'Đăng nhập';

  @override
  String get protocol => 'Giao thức';

  @override
  String get typeLabel => 'Loại';

  @override
  String get folder => 'Thư mục';

  @override
  String nSubitems(int count) {
    return '$count mục';
  }

  @override
  String get subitems => 'Mục';

  @override
  String get grantPermission => 'Cấp quyền';

  @override
  String get storagePermissionLimited =>
      'Truy cập hạn chế — cấp quyền truy cập bộ nhớ đầy đủ cho tất cả tệp';

  @override
  String progressConnecting(String host, int port) {
    return 'Đang kết nối đến $host:$port';
  }

  @override
  String get progressVerifyingHostKey => 'Đang xác minh khóa máy chủ';

  @override
  String progressAuthenticating(String user) {
    return 'Đang xác thực với tên $user';
  }

  @override
  String get progressOpeningShell => 'Đang mở shell';

  @override
  String get progressOpeningSftp => 'Đang mở kênh SFTP';

  @override
  String get transfersLabel => 'Truyền tải:';

  @override
  String transferCountActive(int count) {
    return '$count đang hoạt động';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count đang chờ';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count trong lịch sử';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'Tạo lúc: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'Bắt đầu: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'Kết thúc: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'Thời lượng: $duration';
  }

  @override
  String get transferStatusQueued => 'Đang chờ';

  @override
  String get fileConflictTitle => 'Tệp đã tồn tại';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" đã tồn tại trong $targetDir. Bạn muốn làm gì?';
  }

  @override
  String get fileConflictSkip => 'Bỏ qua';

  @override
  String get fileConflictKeepBoth => 'Giữ cả hai';

  @override
  String get fileConflictReplace => 'Thay thế';

  @override
  String get fileConflictApplyAll => 'Áp dụng cho tất cả các tệp còn lại';

  @override
  String get folderNameLabel => 'TÊN THƯ MỤC';

  @override
  String folderAlreadyExists(String name) {
    return 'Thư mục \"$name\" đã tồn tại';
  }

  @override
  String get dropKeyFileHere => 'Kéo thả tệp khóa vào đây';

  @override
  String get sessionNoCredentials =>
      'Phiên không có thông tin xác thực — chỉnh sửa để thêm mật khẩu hoặc khóa';

  @override
  String dragItemCount(int count) {
    return '$count mục';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'Chọn tất cả ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'Kích thước: $size KB / tối đa $max KB';
  }

  @override
  String get noActiveTerminals => 'Không có terminal hoạt động';

  @override
  String get connectFromSessionsTab => 'Kết nối từ tab Phiên';

  @override
  String fileNotFound(String path) {
    return 'Không tìm thấy tệp: $path';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count mục, $size';
  }

  @override
  String get maximize => 'Phóng to';

  @override
  String get restore => 'Khôi phục';

  @override
  String get duplicateDownShortcut => 'Nhân bản xuống (Ctrl+Shift+\\)';

  @override
  String get security => 'Bảo mật';

  @override
  String get knownHosts => 'Known hosts';

  @override
  String get knownHostsSubtitle => 'Quản lý fingerprint của host SSH tin cậy';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count known host',
      zero: 'Không có known host',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'Chưa có known host. Kết nối tới một host để thêm.';

  @override
  String get removeHost => 'Xóa host';

  @override
  String removeHostConfirm(String host) {
    return 'Xóa $host khỏi known hosts? Key sẽ được xác minh lại ở lần kết nối sau.';
  }

  @override
  String get clearAllKnownHosts => 'Xóa tất cả máy chủ đã biết';

  @override
  String get clearAllKnownHostsConfirm =>
      'Xóa tất cả máy chủ đã biết? Mỗi khóa máy chủ sẽ cần xác minh lại.';

  @override
  String get clearedAllHosts => 'Đã xóa tất cả máy chủ đã biết';

  @override
  String removedHost(String host) {
    return 'Đã xóa $host';
  }

  @override
  String get tools => 'Công cụ';

  @override
  String get sshKeys => 'Khóa SSH';

  @override
  String get sshKeysSubtitle => 'Quản lý cặp khóa SSH để xác thực';

  @override
  String get noKeys => 'Không có khóa SSH. Nhập hoặc tạo một khóa.';

  @override
  String get generateKey => 'Tạo khóa';

  @override
  String get addKey => 'Thêm khóa';

  @override
  String get addKeyMenuPaste => 'Dán PEM';

  @override
  String get filePickerUnavailable =>
      'Trình chọn tệp không khả dụng trên hệ thống này';

  @override
  String get importKey => 'Nhập khóa';

  @override
  String get keyLabel => 'Tên khóa';

  @override
  String get keyLabelHint => 'VD: Máy chủ công việc, GitHub';

  @override
  String get selectKeyType => 'Loại khóa';

  @override
  String get generating => 'Đang tạo...';

  @override
  String keyGenerated(String label) {
    return 'Đã tạo khóa: $label';
  }

  @override
  String keyImported(String label) {
    return 'Đã nhập khóa: $label';
  }

  @override
  String get deleteKey => 'Xóa khóa';

  @override
  String deleteKeyConfirm(String label) {
    return 'Xóa khóa \"$label\"? Các phiên sử dụng khóa này sẽ mất quyền truy cập.';
  }

  @override
  String keyDeleted(String label) {
    return 'Đã xóa khóa: $label';
  }

  @override
  String get publicKey => 'Khóa công khai';

  @override
  String get publicKeyCopied => 'Đã sao chép khóa công khai vào clipboard';

  @override
  String get sshCertificate => 'Certificate';

  @override
  String get certImport => 'Import certificate';

  @override
  String get certImportTooltip =>
      'Đính kèm OpenSSH certificate đã được CA của bạn ký (file `-cert.pub` từ `ssh-keygen -s …`). Dùng khi server verify bằng CA signature thay vì `authorized_keys`. Bỏ qua nếu server dùng plain key auth.';

  @override
  String get certImportPickerTitle => 'Chọn file certificate OpenSSH';

  @override
  String get certValidFrom => 'Hiệu lực từ';

  @override
  String get certValidTo => 'Hết hạn';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => 'Certificate này sắp hết hạn.';

  @override
  String get certExpired => 'Hết hạn';

  @override
  String get certRemove => 'Xoá certificate';

  @override
  String get certRemoveConfirmTitle => 'Xoá certificate?';

  @override
  String get certRemoveConfirmBody =>
      'Sau khi xoá, lần connect tiếp theo sẽ fallback về public key thường.';

  @override
  String errCertParse(String detail) {
    return 'Không parse được certificate: $detail';
  }

  @override
  String get errCertPairFingerprintMismatch =>
      'Certificate này không được pair với key đang chọn.';

  @override
  String get pastePrivateKey => 'Dán khóa riêng tư (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Dữ liệu khóa PEM không hợp lệ';

  @override
  String get selectFromKeyStore => 'Chọn từ kho khóa';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count khóa',
      zero: 'Không có khóa',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'Đã tạo';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get enterMasterPassword =>
      'Nhập mật khẩu chính để truy cập thông tin đăng nhập đã lưu.';

  @override
  String get wrongMasterPassword => 'Sai mật khẩu. Thử lại.';

  @override
  String get currentPassword => 'Mật khẩu hiện tại';

  @override
  String get forgotPassword => 'Quên mật khẩu?';

  @override
  String get credentialsReset => 'Tất cả thông tin đăng nhập đã lưu đã bị xóa';

  @override
  String get migrationToast => 'Bộ nhớ đã được nâng cấp lên định dạng mới nhất';

  @override
  String get dbCorruptTitle => 'Không thể mở cơ sở dữ liệu';

  @override
  String get dbCorruptBody =>
      'Dữ liệu trên disk không mở được. Hãy thử credential khác, hoặc reset để bắt đầu lại.';

  @override
  String get dbCorruptWarning =>
      'Đặt lại sẽ xóa vĩnh viễn cơ sở dữ liệu đã mã hóa và mọi tệp liên quan đến bảo mật. Không có dữ liệu nào được khôi phục.';

  @override
  String get dbCorruptTryOther => 'Thử thông tin xác thực khác';

  @override
  String get dbCorruptResetContinue => 'Đặt lại & Cài đặt mới';

  @override
  String get dbCorruptExit => 'Thoát LetsFLUTssh';

  @override
  String get tierResetTitle => 'Cần đặt lại bảo mật';

  @override
  String get tierResetBody =>
      'Bản cài đặt này mang theo dữ liệu bảo mật từ phiên bản LetsFLUTssh cũ hơn sử dụng mô hình tầng khác. Mô hình mới là thay đổi không tương thích — không có đường dẫn di chuyển tự động. Để tiếp tục, tất cả phiên đã lưu, thông tin đăng nhập, khóa SSH và máy chủ đã biết trên bản cài đặt này phải bị xóa và chạy lại trình hướng dẫn thiết lập lần đầu từ đầu.';

  @override
  String get tierResetWarning =>
      'Chọn «Đặt lại & Thiết lập mới» sẽ xóa vĩnh viễn cơ sở dữ liệu đã mã hóa và mọi tập tin liên quan đến bảo mật. Nếu bạn cần khôi phục dữ liệu, hãy thoát ứng dụng ngay và cài lại phiên bản trước của LetsFLUTssh để xuất trước.';

  @override
  String get tierResetResetContinue => 'Đặt lại & Thiết lập mới';

  @override
  String get tierResetExit => 'Thoát LetsFLUTssh';

  @override
  String get derivingKey => 'Đang tạo khóa mã hóa...';

  @override
  String get securitySetupTitle => 'Thiết lập bảo mật';

  @override
  String get keychainAvailable => 'Khả dụng';

  @override
  String get changeSecurityTierConfirm =>
      'Đang mã hóa lại cơ sở dữ liệu với mức mới. Không thể dừng — giữ ứng dụng mở đến khi hoàn tất.';

  @override
  String get changeSecurityTierDone => 'Đã đổi mức bảo mật';

  @override
  String get changeSecurityTierFailed => 'Không thể đổi mức bảo mật';

  @override
  String get firstLaunchSecurityTitle => 'Đã bật lưu trữ an toàn';

  @override
  String get firstLaunchSecurityBody =>
      'Dữ liệu của bạn được mã hoá bằng khoá nằm trong keychain hệ điều hành. Việc mở khoá trên thiết bị này diễn ra tự động.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'Thiết bị này có lưu trữ phần cứng sẵn có. Nâng cấp trong Cài đặt → Bảo mật để liên kết TPM / Secure Enclave.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'Lưu trữ phần cứng không khả dụng trên thiết bị này.';

  @override
  String get firstLaunchSecurityOpenSettings => 'Mở Cài đặt';

  @override
  String get wizardReducedBanner =>
      'Keychain hệ điều hành không thể truy cập trong bản cài đặt này. Hãy chọn giữa không mã hoá (T0) và mật khẩu chính (Paranoid). Cài đặt gnome-keyring, kwallet hoặc trình cung cấp libsecret khác để bật tầng Keychain.';

  @override
  String get tierBadgeCurrent => 'Hiện tại';

  @override
  String get securitySetupEnable => 'Kích hoạt';

  @override
  String get securitySetupApply => 'Áp dụng';

  @override
  String get hwProbeLinuxDeviceMissing =>
      'Không phát hiện TPM tại /dev/tpmrm0. Bật fTPM / PTT trong BIOS nếu thiết bị hỗ trợ, nếu không tầng phần cứng không khả dụng trên máy này.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools chưa được cài đặt. Chạy `sudo apt install tpm2-tools` (hoặc tương đương trên phân phối của bạn) để kích hoạt tầng phần cứng.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'Kiểm tra tầng phần cứng thất bại. Kiểm tra quyền trên /dev/tpmrm0 và các quy tắc udev — xem log để biết chi tiết.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'Không phát hiện TPM 2.0. Bật fTPM / PTT trong phần mềm UEFI, hoặc chấp nhận rằng tầng phần cứng không khả dụng trên thiết bị này — ứng dụng chuyển sang kho thông tin xác thực phần mềm.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Cả Microsoft Platform Crypto Provider lẫn Software Key Storage Provider đều không truy cập được — có thể do hệ thống mật mã Windows bị hỏng hoặc Group Policy chặn CNG. Kiểm tra Event Viewer → Applications and Services Logs.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'Mac này không có Secure Enclave (Mac Intel trước 2017 không có chip bảo mật T1 / T2). Tầng phần cứng không khả dụng; hãy dùng mật khẩu chính.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'Chưa đặt mật khẩu đăng nhập trên Mac này. Tạo khóa Secure Enclave cần có — đặt mật khẩu đăng nhập trong System Settings → Touch ID & Password (hoặc Login Password).';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave từ chối danh tính chữ ký của ứng dụng (-34018). Chạy script `macos-resign.sh` đi kèm bản phát hành để gán cho bản cài đặt này một danh tính tự ký ổn định, sau đó khởi động lại ứng dụng.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'Chưa đặt mã khóa thiết bị. Tạo khóa Secure Enclave cần có — đặt mã trong Settings → Face ID & Passcode (hoặc Touch ID & Passcode).';

  @override
  String get hwProbeIosSimulator =>
      'Đang chạy trên iOS Simulator, không có Secure Enclave. Tầng phần cứng chỉ khả dụng trên thiết bị iOS vật lý.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'Cần Android 9 trở lên cho tầng phần cứng (StrongBox và vô hiệu hóa khóa khi thay đổi đăng ký sinh trắc học không đáng tin cậy trên phiên bản cũ hơn).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'Thiết bị này không có phần cứng sinh trắc học (vân tay hoặc khuôn mặt). Hãy dùng mật khẩu chính.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'Chưa đăng ký sinh trắc học. Thêm vân tay hoặc khuôn mặt trong Settings → Bảo mật và quyền riêng tư → Sinh trắc học, sau đó bật lại tầng phần cứng.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'Phần cứng sinh trắc học tạm thời không sử dụng được (khóa sau nhiều lần thất bại hoặc đang chờ cập nhật bảo mật). Thử lại sau vài phút.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'Android Keystore từ chối hỗ trợ khóa phần cứng trên bản dựng thiết bị này (StrongBox không có, ROM tùy chỉnh hoặc lỗi trình điều khiển). Lớp phần cứng không khả dụng.';

  @override
  String get securityRecheck => 'Kiểm tra lại hỗ trợ lớp';

  @override
  String get securityRecheckUpdated =>
      'Hỗ trợ lớp đã cập nhật — xem thẻ ở trên';

  @override
  String get securityRecheckUnchanged => 'Hỗ trợ lớp không thay đổi';

  @override
  String get securityMacosEnableSecureTiers =>
      'Mở khóa các lớp bảo mật trên Mac này';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'Ký lại ứng dụng bằng chứng chỉ cá nhân để Keychain (T1) và Secure Enclave (T2) vẫn hoạt động sau cập nhật';

  @override
  String get securityMacosEnableSecureTiersPrompt =>
      'macOS sẽ hỏi mật khẩu của bạn một lần';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'Các lớp bảo mật đã mở khóa — T1 và T2 hiện khả dụng';

  @override
  String get securityMacosEnableSecureTiersFailed =>
      'Không thể mở khóa các lớp bảo mật';

  @override
  String get securityMacosOfferTitle => 'Kích hoạt Keychain + Secure Enclave?';

  @override
  String get securityMacosOfferBody =>
      'macOS ràng buộc bộ nhớ mã hóa với danh tính ký của ứng dụng. Không có chứng chỉ ổn định, Keychain (T1) và Secure Enclave (T2) từ chối truy cập. Chúng tôi có thể tạo chứng chỉ cá nhân tự ký trên Mac này và ký lại ứng dụng — bản cập nhật tiếp tục hoạt động và bí mật của bạn tồn tại qua các bản phát hành. macOS sẽ hỏi mật khẩu đăng nhập một lần để tin cậy chứng chỉ mới.';

  @override
  String get securityMacosOfferAccept => 'Kích hoạt';

  @override
  String get securityMacosOfferDecline => 'Bỏ qua — chọn T0 hoặc Paranoid';

  @override
  String get securityMacosRemoveIdentity => 'Xóa danh tính ký';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      'Xóa chứng chỉ cá nhân. Dữ liệu T1 / T2 gắn với nó — chuyển sang T0 hoặc Paranoid trước, sau đó xóa.';

  @override
  String get securityMacosRemoveIdentityConfirmTitle => 'Xóa danh tính ký?';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'Xóa chứng chỉ cá nhân khỏi Keychain đăng nhập. Bí mật T1 / T2 đã lưu sẽ không đọc được. Trình hướng dẫn sẽ mở để di chuyển sang T0 (văn bản thuần) hoặc Paranoid (mật khẩu chính) trước khi xóa.';

  @override
  String get securityMacosRemoveIdentitySuccess => 'Đã xóa danh tính ký';

  @override
  String get securityMacosRemoveIdentityFailed => 'Không thể xóa danh tính ký';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus đang chạy nhưng không có secret-service daemon nào đang hoạt động. Cài đặt gnome-keyring (`sudo apt install gnome-keyring`) hoặc KWalletManager và đảm bảo nó khởi động khi đăng nhập.';

  @override
  String get keyringProbeFailed =>
      'Keychain OS không truy cập được trên thiết bị này. Xem log để biết lỗi nền tảng cụ thể; ứng dụng chuyển sang mật khẩu chính.';

  @override
  String get snippets => 'Snippet';

  @override
  String get snippetsSubtitle => 'Quản lý các snippet lệnh có thể tái sử dụng';

  @override
  String get noSnippets => 'Chưa có snippet';

  @override
  String get addSnippet => 'Thêm snippet';

  @override
  String get editSnippet => 'Chỉnh sửa snippet';

  @override
  String get deleteSnippet => 'Xóa snippet';

  @override
  String deleteSnippetConfirm(String title) {
    return 'Xóa snippet \"$title\"?';
  }

  @override
  String get snippetTitle => 'Tiêu đề';

  @override
  String get snippetTitleHint => 'vd. Triển khai, Khởi động lại dịch vụ';

  @override
  String get snippetCommand => 'Lệnh';

  @override
  String get snippetCommandHint => 'vd. sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'Mô tả (tùy chọn)';

  @override
  String get snippetDescriptionHint => 'Lệnh này làm gì?';

  @override
  String get snippetSaved => 'Đã lưu snippet';

  @override
  String snippetDeleted(String title) {
    return 'Đã xóa snippet \"$title\"';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippet',
      one: '1 snippet',
      zero: 'Không có snippet',
    );
    return '$_temp0';
  }

  @override
  String get pinToSession => 'Ghim vào phiên này';

  @override
  String get unpinFromSession => 'Bỏ ghim khỏi phiên này';

  @override
  String get pinnedSnippets => 'Đã ghim';

  @override
  String get allSnippets => 'Tất cả';

  @override
  String get commandCopied => 'Đã sao chép lệnh';

  @override
  String get snippetTokensHint =>
      'Chạm để chèn placeholder. Chúng được thay thế khi chạy bằng giá trị từ phiên hoạt động:';

  @override
  String get snippetCustomTokensHint =>
      'Bất kỳ thứ gì khác với dấu ngoặc nhọn kép sẽ hỏi bạn giá trị khi chạy snippet.';

  @override
  String get snippetFillTitle => 'Điền tham số snippet';

  @override
  String get snippetFillSubmit => 'Chạy';

  @override
  String get broadcastSetDriver => 'Phát từ ngăn này';

  @override
  String get broadcastClearDriver => 'Dừng phát từ ngăn này';

  @override
  String get broadcastAddReceiver => 'Nhận phát ở đây';

  @override
  String get broadcastRemoveReceiver => 'Ngừng nhận phát';

  @override
  String get broadcastClearAll => 'Dừng tất cả phát';

  @override
  String get broadcastPasteTitle => 'Gửi dán đến tất cả các ngăn?';

  @override
  String broadcastPasteBody(int chars, int count) {
    return '$chars ký tự sẽ được gửi đến $count ngăn khác.';
  }

  @override
  String get broadcastPasteSend => 'Gửi';

  @override
  String get portForwarding => 'Chuyển tiếp';

  @override
  String get portForwardingEmpty => 'Chưa có quy tắc nào';

  @override
  String get addForwardRule => 'Thêm quy tắc';

  @override
  String get editForwardRule => 'Sửa quy tắc';

  @override
  String get deleteForwardRule => 'Xoá quy tắc';

  @override
  String get localForward => 'Cục bộ';

  @override
  String get remoteForward => 'Từ xa';

  @override
  String get dynamicForward => 'Động';

  @override
  String get forwardKind => 'Loại';

  @override
  String get bindAddress => 'Địa chỉ bind';

  @override
  String get bindPort => 'Cổng bind';

  @override
  String get targetHost => 'Máy đích';

  @override
  String get targetPort => 'Cổng đích';

  @override
  String get forwardDescription => 'Mô tả (tuỳ chọn)';

  @override
  String get forwardEnabled => 'Bật';

  @override
  String get forwardBindWildcardWarning =>
      'Bind tới 0.0.0.0 phát chuyển tiếp trên mọi giao diện — thường bạn muốn 127.0.0.1.';

  @override
  String get forwardKindLocalHelp =>
      'Cục bộ: mở một cổng trên thiết bị này, tạo đường hầm đến mục tiêu mà máy chủ SSH có thể tới. Hữu ích để truy cập cơ sở dữ liệu hoặc giao diện admin từ xa qua localhost:bindPort.';

  @override
  String get forwardKindRemoteHelp =>
      'Từ xa: yêu cầu máy chủ SSH mở một cổng, tạo đường hầm trở về mục tiêu mà thiết bị này có thể tới. Hữu ích để chia sẻ máy chủ dev cục bộ với host từ xa (máy chủ có thể cần GatewayPorts yes cho bind không phải loopback).';

  @override
  String get forwardKindDynamicHelp =>
      'Động: một proxy SOCKS5 trên thiết bị này định tuyến mọi kết nối qua máy chủ SSH. Trỏ trình duyệt hoặc curl đến localhost:bindPort để gửi mọi lưu lượng qua SSH.';

  @override
  String get proxyJump => 'Kết nối qua';

  @override
  String get proxyJumpNone => 'Kết nối trực tiếp';

  @override
  String get proxyJumpSavedSession => 'Phiên đã lưu';

  @override
  String get proxyJumpCustom => 'Tuỳ chỉnh';

  @override
  String get proxyJumpCustomNote =>
      'Hop tuỳ chỉnh dùng thông tin xác thực của phiên này. Để xác thực bastion khác, hãy lưu bastion như một phiên riêng.';

  @override
  String viaSessionLabel(String label) {
    return 'qua $label';
  }

  @override
  String get recordSession => 'Ghi phiên';

  @override
  String get recordSessionHelp =>
      'Lưu đầu ra terminal vào đĩa cho phiên này. Mã hóa khi nghỉ khi master password hoặc khóa phần cứng bảo vệ cơ sở dữ liệu phiên; nếu không, lưu dưới dạng plaintext bên cạnh cơ sở dữ liệu.';

  @override
  String get recordingsBrowserTitle => 'Bản ghi';

  @override
  String get recordingsBrowserSubtitle =>
      'Duyệt, phát lại và xóa các phiên đã ghi';

  @override
  String get recordingsEmpty => 'Chưa có bản ghi nào';

  @override
  String get playRecording => 'Phát';

  @override
  String get deleteRecording => 'Xóa';

  @override
  String get recordingPlaybackTitle => 'Phát lại bản ghi';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

  @override
  String get tags => 'Thẻ';

  @override
  String get tagsSubtitle => 'Tổ chức phiên và thư mục bằng thẻ màu';

  @override
  String get noTags => 'Chưa có thẻ';

  @override
  String get addTag => 'Thêm thẻ';

  @override
  String get deleteTag => 'Xóa thẻ';

  @override
  String deleteTagConfirm(String name) {
    return 'Xóa thẻ \"$name\"? Nó sẽ bị xóa khỏi mọi phiên và thư mục.';
  }

  @override
  String get tagName => 'Tên thẻ';

  @override
  String get tagNameHint => 'vd. Production, Staging';

  @override
  String get tagColor => 'Màu';

  @override
  String get tagCreated => 'Đã tạo thẻ';

  @override
  String tagDeleted(String name) {
    return 'Đã xóa thẻ \"$name\"';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count thẻ',
      one: '1 thẻ',
      zero: 'Không có thẻ',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'Quản lý thẻ';

  @override
  String get editTags => 'Chỉnh sửa thẻ';

  @override
  String get fullBackup => 'Sao lưu đầy đủ';

  @override
  String get sessionsOnly => 'Phiên';

  @override
  String get presetFullImport => 'Nhập toàn bộ';

  @override
  String get presetSelective => 'Chọn lọc';

  @override
  String get presetCustom => 'Tùy chỉnh';

  @override
  String get sessionSshKeys => 'Khóa phiên (trình quản lý)';

  @override
  String get allManagerKeys => 'Tất cả khóa trong trình quản lý';

  @override
  String get browseFiles => 'Chọn tệp…';

  @override
  String get sshDirSessionAlreadyImported => 'đã có trong các phiên';

  @override
  String get languageSubtitle => 'Ngôn ngữ giao diện';

  @override
  String get themeSubtitle => 'Tối, sáng hoặc theo hệ thống';

  @override
  String get uiScaleSubtitle => 'Tỷ lệ toàn bộ giao diện';

  @override
  String get terminalFontSizeSubtitle => 'Cỡ chữ trong đầu ra terminal';

  @override
  String get scrollbackLinesSubtitle => 'Kích thước bộ đệm lịch sử terminal';

  @override
  String get keepAliveIntervalSubtitle =>
      'Giây giữa các gói SSH keep-alive (0 = tắt)';

  @override
  String get sshTimeoutSubtitle => 'Thời gian chờ kết nối (giây)';

  @override
  String get defaultPortSubtitle => 'Cổng mặc định cho phiên mới';

  @override
  String get parallelWorkersSubtitle => 'Số luồng truyền SFTP song song';

  @override
  String get maxHistorySubtitle => 'Số lệnh tối đa lưu trong lịch sử';

  @override
  String get calculateFolderSizesSubtitle =>
      'Hiển thị tổng dung lượng bên cạnh thư mục ở thanh bên';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Kiểm tra phiên bản mới trên GitHub khi khởi chạy ứng dụng';

  @override
  String get threatColdDiskTheft => 'Trộm ổ đĩa khi máy đã tắt';

  @override
  String get threatColdDiskTheftDescription =>
      'Máy đã tắt bị tháo ổ đĩa ra và đọc trên một máy khác, hoặc ai đó có quyền truy cập thư mục cá nhân của bạn sao chép tệp cơ sở dữ liệu.';

  @override
  String get threatKeyringFileTheft => 'Đánh cắp tệp keyring / keychain';

  @override
  String get threatKeyringFileTheftDescription =>
      'Kẻ tấn công đọc trực tiếp tệp kho thông tin xác thực của hệ điều hành từ ổ đĩa (libsecret keyring, Windows Credential Manager, macOS login keychain) và khôi phục khóa cơ sở dữ liệu được gói bên trong. Tầng phần cứng chặn điều này bất kể mật khẩu vì chip từ chối xuất vật liệu khóa; tầng keychain cần thêm mật khẩu, nếu không tệp bị đánh cắp có thể mở chỉ bằng mật khẩu đăng nhập hệ điều hành.';

  @override
  String get modifierOnlyWithPassword => 'chỉ với mật khẩu';

  @override
  String get threatBystanderUnlockedMachine => 'Người ngoài bên máy đã mở khóa';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'Có người tiến lại chiếc máy đã mở khóa của bạn và mở ứng dụng trong lúc bạn vắng mặt.';

  @override
  String get threatLiveRamForensicsLocked => 'RAM forensics trên máy đã khóa';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'Kẻ tấn công đóng băng RAM (hoặc dump qua DMA) và trích xuất các mảnh key còn sót lại trong snapshot, ngay cả khi ứng dụng đang bị khóa.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'Xâm phạm kernel OS hoặc keychain';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'Lỗ hổng kernel, rò rỉ keychain, hoặc backdoor trong chip bảo mật. OS từ thành phần tin cậy trở thành chính kẻ tấn công.';

  @override
  String get threatOfflineBruteForce => 'Dò mật khẩu yếu ngoại tuyến';

  @override
  String get threatOfflineBruteForceDescription =>
      'Kẻ tấn công có bản sao khóa đã bọc hoặc blob được niêm phong sẽ thử mọi mật khẩu theo nhịp độ của chính mình, không bị giới hạn tốc độ nào.';

  @override
  String get legendProtects => 'Được bảo vệ';

  @override
  String get legendDoesNotProtect => 'Không được bảo vệ';

  @override
  String get colT0 => 'T0 Plaintext';

  @override
  String get colT1 => 'T1 Keychain';

  @override
  String get colT1Password => 'T1 + mật khẩu';

  @override
  String get colT1PasswordBiometric => 'T1 + mật khẩu + biometric';

  @override
  String get colT2Password => 'T2 + mật khẩu';

  @override
  String get colT2PasswordBiometric => 'T2 + mật khẩu + biometric';

  @override
  String get colParanoid => 'Paranoid';

  @override
  String get securityComparisonTableThreatColumn => 'Mối đe dọa';

  @override
  String get compareAllTiers => 'So sánh tất cả các bậc';

  @override
  String get resetAllDataTitle => 'Đặt lại toàn bộ dữ liệu';

  @override
  String get resetAllDataSubtitle =>
      'Xóa tất cả phiên, khóa, cấu hình và tạo tác bảo mật. Đồng thời xóa các mục trong keychain và các khe của kho phần cứng.';

  @override
  String get resetAllDataConfirmTitle => 'Đặt lại toàn bộ dữ liệu?';

  @override
  String get resetAllDataConfirmBody =>
      'Tất cả phiên, khóa SSH, known hosts, đoạn mã, thẻ, tùy chọn và mọi tạo tác bảo mật (mục keychain, dữ liệu kho phần cứng, lớp phủ sinh trắc học) sẽ bị xóa vĩnh viễn. Hành động này không thể hoàn tác.';

  @override
  String get resetAllDataConfirmAction => 'Đặt lại tất cả';

  @override
  String resetAllDataConfirmTypePrompt(String phrase) {
    return 'Nhập $phrase bên dưới để xác nhận:';
  }

  @override
  String get resetAllDataInProgress => 'Đang đặt lại…';

  @override
  String get resetAllDataDone => 'Đã đặt lại toàn bộ dữ liệu';

  @override
  String get resetAllDataFailed => 'Đặt lại thất bại';

  @override
  String get recordingsTitle => 'Recordings';

  @override
  String get recordingsStorageUsedLabel => 'Đã dùng';

  @override
  String get recordingsCapLabel => 'Cap';

  @override
  String get recordingsCapHint =>
      'Hard cap cho thư mục recordings/. Khi vượt, recording cũ nhất bị xoá trước; recording đang chạy không bao giờ bị động đến.';

  @override
  String get recordingsClearAllAction => 'Xoá toàn bộ recordings';

  @override
  String get recordingsClearAllConfirmTitle => 'Xoá toàn bộ recordings?';

  @override
  String get recordingsClearAllConfirmBody =>
      'Mọi session đã ghi dưới <app>/recordings/ sẽ bị xoá. Recording đang chạy (nếu có) vẫn còn. Hành động này không thể hoàn tác.';

  @override
  String recordingsClearAllResult(int count) {
    return 'Đã xoá $count recordings';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return 'Cap đã cập nhật. Giải phóng $bytes.';
  }

  @override
  String get recordingsCapChangedNoChange =>
      'Cap đã cập nhật. Không có gì để xoá.';

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
      'Tự động khóa yêu cầu mật khẩu trên bậc đang hoạt động.';

  @override
  String get recommendedBadge => 'KHUYẾN NGHỊ';

  @override
  String get tierHardwareSubtitleHonest =>
      'Nâng cao: khóa gắn với phần cứng, luôn được bảo vệ bằng password. Dữ liệu không thể khôi phục nếu chip của thiết bị này bị mất hoặc bị thay thế.';

  @override
  String get tierParanoidSubtitleHonest =>
      'Phương án thay thế: mật khẩu chính, không tin cậy OS. Bảo vệ khỏi việc OS bị xâm phạm. Không cải thiện bảo vệ lúc chạy so với T1/T2.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'Các mối đe dọa runtime (malware từ cùng người dùng, dump bộ nhớ tiến trình đang chạy) được hiển thị là ✗ ở mọi cấp. Chúng được xử lý bằng các tính năng giảm thiểu riêng biệt, áp dụng bất kể cấp đã chọn.';

  @override
  String get currentTierBadge => 'HIỆN TẠI';

  @override
  String get paranoidAlternativeHeader => 'THAY THẾ';

  @override
  String get modifierPasswordLabel => 'Mật khẩu';

  @override
  String get modifierPasswordSubtitle =>
      'Mật khẩu cần nhập trước khi mở vault dữ liệu.';

  @override
  String get modifierPasswordRequired =>
      'Bắt buộc — tier Hardware luôn được bảo vệ bằng password.';

  @override
  String get modifierBiometricLabel => 'Shortcut biometric';

  @override
  String get modifierBiometricSubtitle =>
      'Lấy mật khẩu từ một khe hệ điều hành được bảo vệ bằng sinh trắc học, thay vì gõ nó.';

  @override
  String get biometricRequiresPassword =>
      'Hãy bật mật khẩu trước — sinh trắc chỉ là lối tắt để nhập mật khẩu.';

  @override
  String get biometricRequiresActiveTier =>
      'Chọn tầng này trước để bật mở khóa sinh trắc học';

  @override
  String get autoLockRequiresActiveTier =>
      'Chọn tầng này trước để cấu hình khóa tự động';

  @override
  String get biometricForbiddenParanoid =>
      'Mức Paranoid không cho phép sinh trắc theo thiết kế.';

  @override
  String get fprintdNotAvailable =>
      'fprintd chưa được cài đặt hoặc chưa đăng ký vân tay.';

  @override
  String get t2RequiresPasswordTitle => 'Đặt master password cho tier Hardware';

  @override
  String get t2RequiresPasswordBody =>
      'Tier Hardware cần password làm modifier. Biometric là shortcut tùy chọn ở trên.';

  @override
  String get t2MigrationPromptTitle => 'Tier Hardware cần password';

  @override
  String get t2MigrationPromptBody =>
      'Các install Hardware hiện có không có password phải đặt một cái ngay bây giờ để tiếp tục.';

  @override
  String get t2MigrationContinue => 'Tiếp tục';

  @override
  String get t2MigrationSetPasswordTitle => 'Đặt password để giữ tier Hardware';

  @override
  String get t2MigrationSetPasswordBody =>
      'Nhập master password mới. DB key đã sealed trong hardware module sẽ được re-seal dưới password này — session và key của bạn vẫn còn nguyên.';

  @override
  String get t2MigrationWipeAndRestart => 'Wipe và bắt đầu lại';

  @override
  String get t2MigrationResealFailed =>
      'Re-seal tier Hardware thất bại — chọn password khác hoặc wipe để bắt đầu lại.';

  @override
  String get biometricOverlayEnable =>
      'Kích hoạt shortcut biometric trên tier Hardware';

  @override
  String get biometricOverlayEnableSubtitle =>
      'Giải phóng password của bạn từ một OS slot được bảo vệ bằng biometric.';

  @override
  String get biometricOverlayUnavailable =>
      'Overlay biometric chưa khả dụng trên platform này.';

  @override
  String get biometricOverlayRequiresPassword =>
      'Đặt password tier Hardware trước đã.';

  @override
  String get t2UnlockTitle => 'Mở khóa bằng master password';

  @override
  String get t2UnlockSubtitle =>
      'Khóa hardware-bound được bảo vệ bằng password của bạn.';

  @override
  String get t2UnlockUseBiometricButton => 'Dùng biometric';

  @override
  String get t2PasswordChanged => 'Password tier Hardware đã được cập nhật.';

  @override
  String get paranoidMasterPasswordNote =>
      'Rất khuyến nghị dùng cụm mật khẩu dài — Argon2id chỉ làm chậm tấn công vét cạn, không ngăn chặn được.';

  @override
  String get plaintextWarningTitle => 'Plaintext: không mã hóa';

  @override
  String get plaintextWarningBody =>
      'Phiên, key và known hosts sẽ được lưu không mã hóa. Bất kỳ ai truy cập được filesystem của máy này đều có thể đọc.';

  @override
  String get plaintextAcknowledge =>
      'Tôi hiểu rằng dữ liệu của tôi sẽ không được mã hóa';

  @override
  String get plaintextAcknowledgeRequired =>
      'Xác nhận bạn đã hiểu trước khi tiếp tục.';

  @override
  String get passwordLabel => 'Mật khẩu';

  @override
  String get masterPasswordLabel => 'Mật khẩu chính';

  @override
  String get globalErrorTitle => 'Lỗi không mong đợi';

  @override
  String get globalErrorBody =>
      'Đã xảy ra lỗi không mong đợi. Ứng dụng sẽ tiếp tục chạy.';

  @override
  String get globalErrorLogSavedNote =>
      'Toàn bộ chi tiết đã được ghi vào file log.';

  @override
  String get globalErrorLogDisabledNote =>
      'Bật ghi log trong Cài đặt để lưu chi tiết lỗi.';

  @override
  String globalErrorTechnicalLine(String detail) {
    return 'Lỗi: $detail';
  }

  @override
  String get globalErrorEnableLoggingButton => 'Bật ghi log';

  @override
  String get globalErrorLoggingEnabledToast =>
      'Đã bật ghi log — lỗi sẽ được ghi vào file log';

  @override
  String get fatalErrorQuitButton => 'Thoát';

  @override
  String get fatalErrorWipeButton => 'Xóa toàn bộ dữ liệu';

  @override
  String get fatalErrorWipingButton => 'Đang xóa…';

  @override
  String get fatalErrorWipeExplanation =>
      'Xóa sẽ loại bỏ mọi file của ứng dụng (config, database, blob vault, log); lần khởi động sau bắt đầu từ bản cài đặt sạch. Không thể hoàn tác.';

  @override
  String get fatalErrorWipeConfirmTitle => 'Xóa toàn bộ dữ liệu?';

  @override
  String get fatalErrorWipeConfirmBody =>
      'Thao tác này xóa vĩnh viễn mọi file config, database và vault. Ứng dụng sẽ khởi động lại từ bản cài đặt trống. Tiếp tục?';

  @override
  String get fatalErrorWipeConfirmAction => 'Xóa tất cả';

  @override
  String get unencryptedArchiveWarning =>
      'Kho lưu trữ này không được bảo vệ bằng mật khẩu. Bất kỳ ai có file đều đọc được nội dung.';

  @override
  String get clipboardCopyFailed => 'Không sao chép được vào clipboard.';

  @override
  String get nonAsciiHostnameWarning =>
      'Tên host chứa ký tự không phải ASCII — đối chiếu từng ký tự với những gì bạn đã nhập. Các codepoint trông giống nhau (Kirin / Hy Lạp) có thể giả mạo một tên miền Latin.';

  @override
  String get playbackPause => 'Tạm dừng';

  @override
  String get recordingPlayLocked =>
      'Mở khóa ứng dụng để phát bản ghi đã mã hóa này.';

  @override
  String get recordToggleStart => 'Bắt đầu ghi';

  @override
  String get recordToggleStop => 'Dừng ghi';

  @override
  String get foregroundServiceTitle => 'SSH đang hoạt động';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kết nối đang hoạt động',
      one: '1 kết nối đang hoạt động',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => 'Loại session';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => 'Username';

  @override
  String get webDavAuthMethod => 'Phương thức auth';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer token';

  @override
  String get trustedCert => 'Chứng chỉ tin cậy (PEM)';

  @override
  String get trustedCertHint => '-----BEGIN CERTIFICATE-----';

  @override
  String get trustedCertHelp =>
      'Dán chứng chỉ máy chủ (một hoặc nhiều khối PEM). Được thêm như một CA gốc bổ sung chỉ cho phiên này — không ảnh hưởng đến ứng dụng khác. Để trống để dùng trust store hệ thống.';

  @override
  String get acceptAnyCert => 'Chấp nhận mọi chứng chỉ';

  @override
  String get acceptAnyCertHelp =>
      'Bỏ qua mọi kiểm tra chứng chỉ và hostname trong các TLS handshake của phiên này. Lối thoát cuối cùng khi cả trust store hệ thống lẫn chứng chỉ được pin đều không phù hợp.';

  @override
  String get acceptAnyCertWarn =>
      'Dễ bị tấn công MITM — bất kỳ ai trên mạng có thể giả mạo máy chủ. Chỉ dùng trên mạng riêng tin cậy.';

  @override
  String get webDavCopyUrl => 'Sao chép WebDAV URL';

  @override
  String get webDavOpenInBrowser => 'Mở trong trình duyệt';

  @override
  String get errWebDavAuthFailed => 'Auth WebDAV thất bại';

  @override
  String get errWebDavNotFound => 'Không tìm thấy path';

  @override
  String get errWebDavConflict => 'Thao tác xung đột với state hiện tại';

  @override
  String errWebDavGeneric(String detail) {
    return 'Server WebDAV từ chối request: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'Cần base URL của WebDAV';

  @override
  String get errWebDavBaseUrlInvalid =>
      'Base URL phải là http:// hoặc https://';

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
      'Bỏ trống cho AWS, hoặc đặt cho MinIO / R2 / Spaces';

  @override
  String get s3PathStyle => 'Path-style addressing';

  @override
  String get s3PathStyleHint => 'Cần cho MinIO; tắt cho AWS';

  @override
  String get s3DefaultBucket => 'Bucket mặc định';

  @override
  String get s3DefaultPrefix => 'Prefix mặc định';

  @override
  String get s3GeneratePresignedUrl => 'Tạo presigned URL';

  @override
  String get s3PresignedUrlExpiry => 'Hết hạn sau';

  @override
  String get s3CopyUri => 'Copy URI s3://bucket/key';

  @override
  String get s3PresignedUrlExpiry15min => '15 phút';

  @override
  String get s3PresignedUrlExpiry1hour => '1 giờ';

  @override
  String get s3PresignedUrlExpiry4hour => '4 giờ';

  @override
  String get s3PresignedUrlExpiry24hour => '24 giờ';

  @override
  String get s3PresignedUrlExpiry7day => '7 ngày';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (kiểm tra access key + secret)';

  @override
  String get errS3NoSuchBucket =>
      'Bucket không tồn tại hoặc không truy cập được';

  @override
  String get errS3RegionMismatch => 'Bucket ở region khác với cấu hình';

  @override
  String errS3Generic(String detail) {
    return 'S3 server từ chối request: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'Bật WebDAV sync';

  @override
  String get syncPassphrase => 'Sync passphrase';

  @override
  String get syncPassphraseHint =>
      'Mã hóa archive sync. Phải khác master password.';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Sync passphrase không được trùng master password.';

  @override
  String get syncRemotePath => 'Đường dẫn remote';

  @override
  String get syncRemotePathHint =>
      'Path dưới WebDAV base URL — mặc định letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return 'Push gần nhất: $when';
  }

  @override
  String syncLastPulled(String when) {
    return 'Pull gần nhất: $when';
  }

  @override
  String get syncNeverRun => 'Chưa từng';

  @override
  String get syncUpToDate => 'Sync đã cập nhật';

  @override
  String syncPushedBytes(String bytes) {
    return 'Push $bytes';
  }

  @override
  String syncPullApplied(int count) {
    return 'Áp dụng $count thay đổi từ remote';
  }

  @override
  String get errSyncDisabled => 'Sync đã tắt';

  @override
  String get errSyncEtagMismatch => 'Remote đã đổi — pull trước rồi push';

  @override
  String get errSyncUnauthorized => 'Xác thực WebDAV thất bại';

  @override
  String errSyncNetwork(String detail) {
    return 'Lỗi mạng: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion =>
      'Archive sync từ remote cần build mới hơn';

  @override
  String get hardwareKey => 'Hardware key';

  @override
  String get hardwareKeyTapPrompt => 'Chạm vào hardware key';

  @override
  String get hardwareKeyPin => 'PIN của hardware key';

  @override
  String get hardwareKeyTimeout => 'Hardware key không phản hồi';

  @override
  String get hardwareKeyNotFound => 'Không tìm thấy hardware key';

  @override
  String get hardwareKeyUnsupported =>
      'Truy cập trực tiếp hardware key không khả dụng trên platform này';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'Cần Apple Developer Program entitlement; dùng ssh-agent trên macOS';

  @override
  String get skKeyRequiresDevice =>
      'SSH key này cần hardware key — chạm để auth';

  @override
  String get errSkWrongPin => 'PIN không đúng';

  @override
  String get hardwareKeyImport => 'Import hardware key (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => 'Đã hủy prompt hardware key';

  @override
  String get agentEndpointSectionTitle => 'Tích hợp với SSH client bên ngoài';

  @override
  String get agentEndpointToggleTitle =>
      'Cho phép SSH client hệ thống dùng hardware-bound keys';

  @override
  String get agentEndpointToggleSubtitle =>
      'Cho phép git, ssh và IDE plugin trên thiết bị này dùng key FIDO2 / smart-card / TPM của bạn.';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'Sao chép lệnh export';

  @override
  String get agentEndpointCopyPipeName => 'Sao chép tên pipe';

  @override
  String get agentEndpointSignatureRequestTitle => 'Yêu cầu ký';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester muốn ký bằng $keyLabel';
  }

  @override
  String get agentEndpointRequesterUnknown => 'Một SSH client bên ngoài';

  @override
  String get agentEndpointAuthorizeOnce => 'Cho phép một lần';

  @override
  String get agentEndpointAuthorizeAlways => 'Cho phép và ghi nhớ';

  @override
  String get agentEndpointDeny => 'Từ chối';

  @override
  String get agentEndpointStatusRunning => 'Đang chạy';

  @override
  String get agentEndpointStatusStopped => 'Đã dừng';

  @override
  String get agentEndpointStatusUnsupported => 'Không hỗ trợ trên nền tảng này';

  @override
  String get agentEndpointRefusedAddIdentity =>
      'Đã từ chối: client bên ngoài không thể thêm key.';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'Không khởi động được ssh-agent endpoint: $detail';
  }

  @override
  String get pkcs11AddTitle => 'Thêm key smart-card / token';

  @override
  String get pkcs11ModuleLabel => 'Module PKCS#11';

  @override
  String get pkcs11ModuleAutoDetected => 'Tự động phát hiện';

  @override
  String get pkcs11ModuleCustom => 'Module tuỳ chỉnh...';

  @override
  String get pkcs11ModulePickerTitle => 'Chọn library PKCS#11';

  @override
  String get pkcs11NoModuleFound =>
      'Không tìm thấy module PKCS#11. Cài OpenSC hoặc chọn library của vendor.';

  @override
  String get pkcs11InitializeFailed => 'Module PKCS#11 không initialise được.';

  @override
  String get pkcs11NoTokenPresent => 'Không có token nào trong reader.';

  @override
  String pkcs11TokenLabel(String label) {
    return 'Token: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return 'Serial: $serial';
  }

  @override
  String get pkcs11LoginRequired => 'Token yêu cầu login.';

  @override
  String pkcs11PinPrompt(String token) {
    return 'PIN cho $token';
  }

  @override
  String get pkcs11PinPad => 'Xác nhận trên PIN-pad của token.';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'PIN sai. Còn $remaining lần thử.';
  }

  @override
  String get pkcs11PinLocked => 'PIN của token đã khoá. Mở khoá bằng PUK.';

  @override
  String get pkcs11NoSignableKeys =>
      'Token không có key dùng được với SSH (RSA, ECDSA, Ed25519).';

  @override
  String get pkcs11GostUnsupported => 'Key GOST không dùng được với SSH.';

  @override
  String pkcs11TokenUnplugged(String label) {
    return 'Token \"$label\" không được cắm.';
  }

  @override
  String get pkcs11UriRebindFailed =>
      'Không tìm thấy token đã lưu. Cắm lại và thử lại.';

  @override
  String pkcs11SignFailed(String reason) {
    return 'Signing thất bại: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      'Smart-card / token PKCS#11 không khả dụng trên nền tảng này.';

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
  String get pkcs11WizardStepModule => 'Chọn module PKCS#11';

  @override
  String get pkcs11WizardStepToken => 'Chọn token';

  @override
  String get pkcs11WizardStepKey => 'Chọn key';

  @override
  String get pkcs11WizardStepPin => 'Nhập PIN';

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
  String get pkcs11SaveInProgress => 'Đang đọc public key từ token...';

  @override
  String get pkcs11SaveSuccess => 'Đã thêm key smart card.';

  @override
  String get pkcs11ScanInProgress => 'Đang quét module PKCS#11...';

  @override
  String get pkcs11LoadingTokens => 'Đang tải token...';

  @override
  String get pkcs11LoadingKeys => 'Đang tải key...';

  @override
  String get pkcs11ModuleStatusReady => 'Module đã được tải.';

  @override
  String get pkcs11ModuleStatusNoToken => 'Không có token.';

  @override
  String get pkcs11ModuleStatusFailed => 'Không tải được module.';

  @override
  String get pkcs11PinPadHint => '(PIN pad trên thiết bị)';

  @override
  String get pkcs11WizardBack => 'Quay lại';

  @override
  String get pkcs11WizardNext => 'Tiếp';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => 'Thêm hardware key';

  @override
  String get sshKeyHardwareBoundExplainer =>
      'Private key nằm trong secure hardware của thiết bị và không thể export.';

  @override
  String get sshKeyEnclaveDeviceBound => 'Key này chỉ hoạt động trên Mac này.';

  @override
  String get sshKeyEnclaveDeviceBoundIos =>
      'Key này chỉ hoạt động trên iPhone này.';

  @override
  String get sshKeyHelloDeviceBound => 'Key này chỉ hoạt động trên PC này.';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'Yêu cầu Touch ID / Face ID';

  @override
  String get sshKeyEnclavePasscodeFallback =>
      'Cho phép passcode thiết bị làm fallback';

  @override
  String get sshKeyHelloPinRequired =>
      'Yêu cầu Windows Hello (PIN, vân tay hoặc khuôn mặt)';

  @override
  String get sshKeyHardwareUnavailableTitle => 'Hardware key không khả dụng';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'App phải được code-signed mới dùng được Secure Enclave.';

  @override
  String get sshKeyHardwareUnavailableHello =>
      'Windows Hello chưa được cấu hình trên PC này.';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'Không phát hiện TPM — chỉ software-backed.';

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
  String get sshKeyGenerateCta => 'Tạo';

  @override
  String get sshKeyGenerateInProgress =>
      'Đang tạo key trong secure hardware...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Cần code-signing — xem USER_GUIDE.md → Hardware-bound keys.';

  @override
  String get sshKeySignInProgress => 'Đang ký với secure hardware...';

  @override
  String get sshKeyPublicCopy => 'Sao chép public key';

  @override
  String get sshKeyAuthorizedKeysHint =>
      'Thêm dòng này vào ~/.ssh/authorized_keys trên server.';

  @override
  String get sshKeyEnclaveWizardTitle => 'Secure Enclave SSH key';

  @override
  String get sshKeyEnclaveWizardLabelHint => 'Tên key';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'Khóa SSH Windows Hello';

  @override
  String get helloWizardLabelHint => 'Nhãn khóa';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'Xác thực bằng Windows Hello';

  @override
  String get helloPromptDescription =>
      'PIN, vân tay hoặc khuôn mặt — Windows Hello ký challenge SSH này.';

  @override
  String get helloSoftwareGatedWarning =>
      'Thiết bị này không có TPM. Khóa nằm trong user storage; Windows Hello vẫn gate mọi chữ ký.';

  @override
  String get helloP384NotSupported =>
      'Firmware TPM không hỗ trợ P-384. Chọn P-256 hoặc RSA-2048.';

  @override
  String get helloConfigureFirst =>
      'Cấu hình Windows Hello trước tại Settings -> Sign-in options.';

  @override
  String get tpmSshTitle => 'Tạo SSH key gắn TPM';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (khuyến nghị)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported => 'Firmware TPM không hỗ trợ algorithm này.';

  @override
  String get tpmSshPinProtect => 'Bảo vệ bằng PIN';

  @override
  String get tpmSshPinLockoutWarning =>
      'Nhiều lần nhập sai PIN sẽ khiến TPM khóa key.';

  @override
  String get tpmSshPinMismatch => 'PIN không khớp.';

  @override
  String get tpmSshStorageBlob => 'Lưu wrapped key trong app data';

  @override
  String get tpmSshStorageHandle => 'Lưu trong slot memory TPM';

  @override
  String get tpmSshStorageHandleHelp =>
      'Signing nhanh hơn. Dùng một trong các persistent slot của TPM.';

  @override
  String get tpmSshLabel => 'Nhãn key';

  @override
  String get tpmSshImportTitle => 'Nhập SSH key được bảo vệ TPM';

  @override
  String get tpmSshImportFormat => 'File TPM 2.0 (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return 'TPM PIN cho $label';
  }

  @override
  String get tpmSshPinIncorrect => 'PIN không đúng.';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM đang trong lockout cooldown. Chờ $duration rồi thử lại.';
  }

  @override
  String get tpmSshGenerating => 'Đang tạo key trong TPM...';

  @override
  String get tpmSshSigning => 'Signing bằng TPM...';

  @override
  String get tpmSshUnavailable => 'Không phát hiện TPM trên thiết bị này.';

  @override
  String get tpmSshUnavailableFwDisabled => 'TPM bị tắt trong firmware.';

  @override
  String get tpmSshUnavailableNoPermission =>
      'App không thể truy cập TPM. Thêm user vào group `tss`.';

  @override
  String tpmSshHandleInUse(String handle) {
    return 'Persistent slot $handle đã được dùng.';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      'Key này sign mà KHÔNG có prompt Hello / PIN — bất kỳ ai có quyền truy cập desktop khi bạn logged in đều có thể dùng.';

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
  String get keystoreKeyGenerating => 'Đang generate hardware-bound key...';

  @override
  String get keystoreKeyAuthPrompt => 'Authenticate để dùng SSH key';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      'Key đã bị huỷ: enroll biometric mới. Đăng ký lại public key trên server.';

  @override
  String get keystoreKeyStrongBoxUnavailable =>
      'StrongBox HSM không có trên device này';

  @override
  String get keystoreKeyUserAuthRequired =>
      'Yêu cầu biometric / device unlock cho mọi signature';

  @override
  String get keystoreKeyExportDisabled =>
      'Không export được hardware-bound keys';

  @override
  String get keystoreKeyDeleteWarning =>
      'Xoá key này sẽ gỡ khỏi hardware store. Server sẽ reject key cho đến khi bạn register key mới.';

  @override
  String get keystoreKeyBiometricNotEnrolled =>
      'Enroll biometric hoặc device PIN trước';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (StrongBox-eligible)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+, TEE only)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (widest compatibility)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM không khả dụng';

  @override
  String get keystoreStrongBoxFallbackBody =>
      'Device của bạn không expose StrongBox HSM. Tạo key TEE-backed thay thế? Vẫn là hardware-backed, chỉ không có isolation của StrongBox.';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'Dùng TEE';

  @override
  String get keystoreStrongBoxFallbackCancel => 'Huỷ';

  @override
  String get fido2BrokerSectionTitle => 'Hardware security key';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / security key';

  @override
  String get fido2BrokerMacosLabel => 'Dialog security key của hệ thống';

  @override
  String get fido2BrokerIosLabel => 'Security key hệ thống (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel =>
      'Security key hệ thống (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => 'USB HID trực tiếp (CTAP2)';

  @override
  String get fido2BrokerTransportNone => 'Không khả dụng trên platform này';

  @override
  String get fido2BrokerPreferDirectHidTitle =>
      'Ưu tiên USB HID trực tiếp thay vì dialog hệ thống';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return 'Nâng cao: bỏ qua $brokerLabel trên các platform mà cả hai đường đều chạy. HID trực tiếp hỗ trợ nhiều tính năng authenticator hơn nhưng cần permission grant theo từng app.';
  }

  @override
  String get sshIntegrationSection => 'Tích hợp SSH';

  @override
  String get fido2BrokerNoTransportSubtitle =>
      'Hỗ trợ hardware key không khả dụng trên thiết bị này.';

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return 'Thiết bị này chỉ có $transport; toggle bị vô hiệu.';
  }

  @override
  String get hardwareKeyStubBadge => 'Stub đã nhập';

  @override
  String get hardwareKeyStubSubtitle =>
      'Ở thiết bị khác — tạo lại tại đây để dùng';

  @override
  String get hardwareKeyStubRegenerateAction => 'Tạo lại tại đây';

  @override
  String get hardwareKeyStubRemoveAction => 'Xoá stub';

  @override
  String get hardwareKeyStubPickerTooltip =>
      'Tạo lại key này trên thiết bị này trước khi dùng';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return 'Chọn module PKCS#11 cho token \"$token\"';
  }

  @override
  String get arrowLeft => 'Mũi tên trái';

  @override
  String get arrowUp => 'Mũi tên lên';

  @override
  String get arrowDown => 'Mũi tên xuống';

  @override
  String get arrowRight => 'Mũi tên phải';

  @override
  String get copyMode => 'Chế độ sao chép';

  @override
  String get exitCopyMode => 'Thoát chế độ sao chép';

  @override
  String importedGeneric(String items) {
    return 'Đã nhập: $items';
  }
}
