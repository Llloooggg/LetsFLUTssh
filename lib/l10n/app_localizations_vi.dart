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
  String get paste => 'Dán';

  @override
  String get select => 'Chọn';

  @override
  String get required => 'Bắt buộc';

  @override
  String get settings => 'Cài đặt';

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
  String get downloadComplete => 'Tải xuống hoàn tất';

  @override
  String get installNow => 'Cài đặt ngay';

  @override
  String get couldNotOpenInstaller => 'Không thể mở trình cài đặt';

  @override
  String versionAvailable(String version) {
    return 'Phiên bản $version có sẵn';
  }

  @override
  String currentVersion(String version) {
    return 'Hiện tại: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'Đã nhận khóa SSH: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return 'Đã nhập $count phiên qua QR';
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
  String get sessions => 'Phiên';

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
  String get noSessionsToExport => 'Không có phiên để xuất';

  @override
  String nSelectedCount(int count) {
    return 'Đã chọn $count';
  }

  @override
  String get selectAll => 'Chọn tất cả';

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
  String get options => 'Tùy chọn';

  @override
  String get sessionName => 'Tên phiên';

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
  String get keyPassphrase => 'Mật khẩu khóa';

  @override
  String get hintOptional => 'Tùy chọn';

  @override
  String get hidePemText => 'Ẩn văn bản PEM';

  @override
  String get pastePemKeyText => 'Dán văn bản khóa PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'Chưa có tùy chọn bổ sung';

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
  String get quickConnect => 'Kết nối nhanh';

  @override
  String get scanQrCode => 'Quét mã QR';

  @override
  String get qrGenerationFailed => 'Tạo mã QR thất bại';

  @override
  String get scanWithCameraApp =>
      'Quét bằng ứng dụng camera trên thiết bị\ncó cài LetsFLUTssh.';

  @override
  String get noPasswordsInQr => 'Không có mật khẩu hoặc khóa trong mã QR này';

  @override
  String get copyLink => 'Sao chép liên kết';

  @override
  String get linkCopied => 'Đã sao chép liên kết vào bộ nhớ tạm';

  @override
  String get hostKeyChanged => 'Khóa máy chủ đã thay đổi!';

  @override
  String get unknownHost => 'Máy chủ không xác định';

  @override
  String get hostKeyChangedWarning =>
      'CẢNH BÁO: Khóa máy chủ của server này đã thay đổi. Điều này có thể là dấu hiệu của tấn công man-in-the-middle, hoặc server đã được cài đặt lại.';

  @override
  String get unknownHostMessage =>
      'Không thể xác minh danh tính của máy chủ này. Bạn có chắc muốn tiếp tục kết nối?';

  @override
  String get host => 'Máy chủ';

  @override
  String get keyType => 'Loại khóa';

  @override
  String get fingerprint => 'Dấu vân tay';

  @override
  String get fingerprintCopied => 'Đã sao chép dấu vân tay';

  @override
  String get copyFingerprint => 'Sao chép dấu vân tay';

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
  String errorPrefix(String error) {
    return 'Lỗi: $error';
  }

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
  String get initializingSftp => 'Đang khởi tạo SFTP...';

  @override
  String get clearHistory => 'Xóa lịch sử';

  @override
  String get noTransfersYet => 'Chưa có lần truyền tệp nào';

  @override
  String get copyRight => 'Sao chép sang phải';

  @override
  String get copyDown => 'Sao chép xuống dưới';

  @override
  String get closePane => 'Đóng khung';

  @override
  String get previous => 'Trước';

  @override
  String get next => 'Tiếp';

  @override
  String get closeEsc => 'Đóng (Esc)';

  @override
  String get copyRightShortcut => 'Sao chép sang phải (Ctrl+\\)';

  @override
  String get copyDownShortcut => 'Sao chép xuống dưới (Ctrl+Shift+\\)';

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
  String get logging => 'Nhật ký';

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
  String get exportData => 'Xuất dữ liệu';

  @override
  String get exportDataSubtitle =>
      'Lưu phiên, cấu hình và khóa vào tệp .lfs được mã hóa';

  @override
  String get importDataSubtitle => 'Tải dữ liệu từ tệp .lfs';

  @override
  String get setMasterPasswordHint =>
      'Đặt mật khẩu chính để mã hóa kho lưu trữ.';

  @override
  String get passwordsDoNotMatch => 'Mật khẩu không khớp';

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
  String get hintLfsPath => '/path/to/export.lfs';

  @override
  String get shareViaQrCode => 'Chia sẻ qua mã QR';

  @override
  String get shareViaQrSubtitle =>
      'Xuất phiên sang mã QR để quét từ thiết bị khác';

  @override
  String get dataLocation => 'Vị trí dữ liệu';

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
  String get enableLogging => 'Bật nhật ký';

  @override
  String get logIsEmpty => 'Nhật ký trống';

  @override
  String logExportedTo(String path) {
    return 'Đã xuất nhật ký đến: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Xuất nhật ký thất bại: $error';
  }

  @override
  String get logsCleared => 'Đã xóa nhật ký';

  @override
  String get copiedToClipboard => 'Đã sao chép vào bộ nhớ tạm';

  @override
  String get copyLog => 'Sao chép nhật ký';

  @override
  String get exportLog => 'Xuất nhật ký';

  @override
  String get clearLogs => 'Xóa nhật ký';

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
  String get anotherInstanceRunning => 'Một phiên LetsFLUTssh khác đang chạy.';

  @override
  String importFailedShort(String error) {
    return 'Nhập thất bại: $error';
  }

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
  String get exit => 'Thoát';

  @override
  String get exitConfirmation =>
      'Các phiên đang hoạt động sẽ bị ngắt kết nối. Thoát?';

  @override
  String get hintFolderExample => 'ví dụ: Production';

  @override
  String get credentialsNotSet => 'Chưa đặt thông tin xác thực';

  @override
  String get exportSessionsViaQr => 'Xuất phiên qua QR';

  @override
  String get qrNoCredentialsWarning =>
      'Mật khẩu và khóa SSH KHÔNG được bao gồm.\nCác phiên nhập vào sẽ cần điền thông tin xác thực.';

  @override
  String get qrTooManyForSingleCode =>
      'Quá nhiều phiên cho một mã QR. Bỏ chọn một số hoặc sử dụng xuất .lfs.';

  @override
  String get qrTooLarge =>
      'Quá lớn — bỏ chọn một số phiên hoặc sử dụng xuất tệp .lfs.';

  @override
  String get exportAll => 'Xuất tất cả';

  @override
  String get showQr => 'Hiện QR';

  @override
  String get resizePanelDivider => 'Thay đổi kích thước thanh phân chia';

  @override
  String get youreRunningLatest => 'Bạn đang sử dụng phiên bản mới nhất';

  @override
  String get liveLog => 'Nhật ký trực tiếp';

  @override
  String transferNItems(int count) {
    return 'Truyền $count mục';
  }

  @override
  String get time => 'Thời gian';

  @override
  String get failed => 'Thất bại';
}
