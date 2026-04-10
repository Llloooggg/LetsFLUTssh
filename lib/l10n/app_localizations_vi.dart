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
  String get authOrDivider => 'HOẶC';

  @override
  String get providePasswordOrKey => 'Cung cấp mật khẩu hoặc khóa SSH';

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
  String get duplicateTab => 'Nhân bản tab';

  @override
  String get duplicateTabShortcut => 'Nhân bản tab (Ctrl+\\)';

  @override
  String get copyDown => 'Sao chép xuống dưới';

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
  String get sortByName => 'Sắp xếp theo tên';

  @override
  String get sortByStatus => 'Sắp xếp theo trạng thái';

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
  String get browse => 'Duyệt';

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
  String get sort => 'Sắp xếp';

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

  @override
  String get errOperationNotPermitted => 'Thao tác không được phép';

  @override
  String get errNoSuchFileOrDirectory => 'Không tìm thấy tệp hoặc thư mục';

  @override
  String get errNoSuchProcess => 'Không tìm thấy tiến trình';

  @override
  String get errIoError => 'Lỗi I/O';

  @override
  String get errBadFileDescriptor => 'Mô tả tệp không hợp lệ';

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
  String get errBrokenPipe => 'Ống dẫn bị hỏng';

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
  String errShellError(String error) {
    return 'Lỗi shell: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'Kết nối lại thất bại: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'Không thể khởi tạo SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Tải xuống thất bại: $error';
  }

  @override
  String get errDecryptionFailed =>
      'Không thể giải mã thông tin xác thực. Tệp khóa có thể bị hỏng.';

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
  String get storagePermissionRequired =>
      'Cần quyền truy cập bộ nhớ để duyệt tệp cục bộ';

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
  String get maximize => 'Phóng to';

  @override
  String get restore => 'Khôi phục';

  @override
  String get duplicateDownShortcut => 'Nhân bản xuống (Ctrl+Shift+\\)';

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

  @override
  String get passphraseRequired => 'Passphrase Required';

  @override
  String passphrasePrompt(String host) {
    return 'The SSH key for $host is encrypted. Enter the passphrase to unlock it.';
  }

  @override
  String get passphraseWrong => 'Wrong passphrase. Please try again.';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get rememberPassphrase => 'Remember for this session';

  @override
  String get unlock => 'Unlock';

  @override
  String get masterPasswordSubtitle =>
      'Protect saved credentials with a password';

  @override
  String get setMasterPassword => 'Set Master Password';

  @override
  String get changeMasterPassword => 'Change Master Password';

  @override
  String get removeMasterPassword => 'Remove Master Password';

  @override
  String get masterPasswordEnabled =>
      'Credentials are protected by master password';

  @override
  String get masterPasswordDisabled =>
      'Credentials use auto-generated key (no password)';

  @override
  String get enterMasterPassword =>
      'Enter master password to unlock your saved credentials.';

  @override
  String get wrongMasterPassword => 'Wrong password. Please try again.';

  @override
  String get newPassword => 'New Password';

  @override
  String get currentPassword => 'Current Password';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String get masterPasswordSet => 'Master password enabled';

  @override
  String get masterPasswordChanged => 'Master password changed';

  @override
  String get masterPasswordRemoved => 'Master password removed';

  @override
  String get masterPasswordWarning =>
      'If you forget this password, all saved passwords and SSH keys will be lost. There is no recovery.';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get forgotPasswordWarning =>
      'This will delete ALL saved passwords, SSH keys, and passphrases. Sessions and settings will be kept. This cannot be undone.';

  @override
  String get resetAndDeleteCredentials => 'Reset & Delete Credentials';

  @override
  String get credentialsReset => 'All saved credentials have been deleted';

  @override
  String get derivingKey => 'Deriving encryption key...';

  @override
  String get reEncrypting => 'Re-encrypting data...';

  @override
  String get confirmRemoveMasterPassword =>
      'Enter your current password to remove master password protection. Credentials will be re-encrypted with an auto-generated key.';

  @override
  String get securitySetupTitle => 'Security Setup';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'OS Keychain detected ($keychainName). Your data will be automatically encrypted using your system keychain.';
  }

  @override
  String get securitySetupKeychainOptional =>
      'You can also set a master password for additional protection.';

  @override
  String get securitySetupNoKeychain =>
      'No OS Keychain detected. Without a keychain, your session data (hosts, passwords, keys) will be stored in plaintext.';

  @override
  String get securitySetupNoKeychainHint =>
      'This is normal on WSL, headless Linux, or minimal installations. To enable keychain on Linux: install libsecret and a keyring daemon (e.g. gnome-keyring).';

  @override
  String get securitySetupRecommendMasterPassword =>
      'We recommend setting a master password to protect your data.';

  @override
  String get continueWithKeychain => 'Continue with Keychain';

  @override
  String get continueWithoutEncryption => 'Continue without Encryption';

  @override
  String get securityLevel => 'Security Level';

  @override
  String get securityLevelPlaintext => 'None (plaintext)';

  @override
  String get securityLevelKeychain => 'OS Keychain';

  @override
  String get securityLevelMasterPassword => 'Master Password';

  @override
  String get keychainStatus => 'Keychain';

  @override
  String keychainAvailable(String name) {
    return 'Available ($name)';
  }

  @override
  String get keychainNotAvailable => 'Not available';

  @override
  String get manageMasterPassword => 'Manage Master Password';

  @override
  String get manageMasterPasswordSubtitle =>
      'Set, change, or remove master password';
}
