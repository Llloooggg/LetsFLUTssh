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
  String get appSettings => 'Cài đặt ứng dụng';

  @override
  String get yes => 'Có';

  @override
  String get no => 'Không';

  @override
  String get importWhatToImport => 'Những gì cần nhập:';

  @override
  String get enterMasterPasswordPrompt => 'Nhập mật khẩu chính:';

  @override
  String get nextStep => 'Tiếp theo';

  @override
  String get includeCredentials => 'Bao gồm mật khẩu và khóa SSH';

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
  String get qrPasswordWarning =>
      'Mật khẩu sẽ không được mã hóa trong mã QR. Bất kỳ ai quét đều có thể nhìn thấy.';

  @override
  String get sshKeysMayBeLarge => 'Khóa có thể vượt quá kích thước QR';

  @override
  String exportTotalSize(String size) {
    return 'Tổng kích thước: $size';
  }

  @override
  String get qrCredentialsWarning =>
      'Mật khẩu và khóa SSH SẼ hiển thị trong mã QR';

  @override
  String get qrCredentialsTooLarge => 'Thông tin xác thực làm mã QR quá lớn';

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
  String get importFromSshConfig => 'Nhập từ cấu hình OpenSSH';

  @override
  String get importFromSshConfigSubtitle =>
      'Nhập một lần các host từ ~/.ssh/config';

  @override
  String get sshConfigPreviewTitle => 'Nhập cấu hình SSH';

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
  String sshConfigPreviewFolderLabel(String folder) {
    return 'Đã nhập vào thư mục: $folder';
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
  String get importOpensshConfig => 'Nhập cấu hình OpenSSH';

  @override
  String get importOpensshConfigSubtitle =>
      'Nhập một lần các host từ ~/.ssh/config';

  @override
  String get importSshKeys => 'Nhập khóa SSH từ ~/.ssh';

  @override
  String get importSshKeysSubtitle =>
      'Quét ~/.ssh để tìm khóa riêng tư và thêm những khóa đã chọn vào trình quản lý khóa';

  @override
  String get importSshKeysTitle => 'Nhập khóa SSH';

  @override
  String importSshKeysFound(int count) {
    return 'Đã tìm thấy $count khóa — chọn khóa nào để nhập';
  }

  @override
  String get importSshKeysNoneFound =>
      'Không tìm thấy khóa riêng tư nào trong ~/.ssh.';

  @override
  String importedSshKeys(int count) {
    return 'Đã nhập $count khóa';
  }

  @override
  String importedSshKeysWithSkipped(int imported, int skipped) {
    return 'Đã nhập $imported khóa mới, $skipped đã có trong kho';
  }

  @override
  String get sshKeyAlreadyImported => 'đã có trong kho';

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
      'Quá lớn — bỏ chọn một số mục hoặc sử dụng xuất tệp .lfs.';

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
  String get transferStartingUpload => 'Bắt đầu tải lên...';

  @override
  String get transferStartingDownload => 'Bắt đầu tải xuống...';

  @override
  String get transferCopying => 'Đang sao chép...';

  @override
  String get transferDone => 'Hoàn tất';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total tệp';
  }

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
  String get sshConnectionChannel => 'Kết nối SSH';

  @override
  String get sshConnectionChannelDesc => 'Duy trì kết nối SSH trong nền.';

  @override
  String get sshActive => 'SSH hoạt động';

  @override
  String activeConnectionCount(int count) {
    return '$count kết nối hoạt động';
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
  String get knownHosts => 'Máy chủ đã biết';

  @override
  String get knownHostsSubtitle => 'Quản lý dấu vân tay máy chủ SSH tin cậy';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count máy chủ đã biết',
      zero: 'Không có máy chủ đã biết',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'Không có máy chủ đã biết. Kết nối tới máy chủ để thêm.';

  @override
  String get removeHost => 'Xóa máy chủ';

  @override
  String removeHostConfirm(String host) {
    return 'Xóa $host khỏi máy chủ đã biết? Khóa sẽ được xác minh lại khi kết nối tiếp theo.';
  }

  @override
  String get clearAllKnownHosts => 'Xóa tất cả máy chủ đã biết';

  @override
  String get clearAllKnownHostsConfirm =>
      'Xóa tất cả máy chủ đã biết? Mỗi khóa máy chủ sẽ cần xác minh lại.';

  @override
  String get importKnownHosts => 'Nhập máy chủ đã biết';

  @override
  String get importKnownHostsSubtitle => 'Nhập từ tệp OpenSSH known_hosts';

  @override
  String get exportKnownHosts => 'Xuất máy chủ đã biết';

  @override
  String importedHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã nhập $count máy chủ mới',
      zero: 'Không nhập máy chủ mới',
    );
    return '$_temp0';
  }

  @override
  String get clearedAllHosts => 'Đã xóa tất cả máy chủ đã biết';

  @override
  String removedHost(String host) {
    return 'Đã xóa $host';
  }

  @override
  String get noHostsToExport => 'Không có máy chủ để xuất';

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
  String get pastePrivateKey => 'Dán khóa riêng tư (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Dữ liệu khóa PEM không hợp lệ';

  @override
  String get selectFromKeyStore => 'Chọn từ kho khóa';

  @override
  String get noKeySelected => 'Chưa chọn khóa';

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
  String get passphraseRequired => 'Cần cụm mật khẩu';

  @override
  String passphrasePrompt(String host) {
    return 'Khóa SSH cho $host được mã hóa. Nhập cụm mật khẩu để mở khóa.';
  }

  @override
  String get passphraseWrong => 'Cụm mật khẩu sai. Vui lòng thử lại.';

  @override
  String get passphrase => 'Cụm mật khẩu';

  @override
  String get rememberPassphrase => 'Ghi nhớ cho phiên này';

  @override
  String get unlock => 'Mở khóa';

  @override
  String get masterPasswordSubtitle =>
      'Bảo vệ thông tin đăng nhập đã lưu bằng mật khẩu';

  @override
  String get setMasterPassword => 'Đặt mật khẩu chính';

  @override
  String get changeMasterPassword => 'Đổi mật khẩu chính';

  @override
  String get removeMasterPassword => 'Xóa mật khẩu chính';

  @override
  String get masterPasswordEnabled =>
      'Thông tin đăng nhập được bảo vệ bởi mật khẩu chính';

  @override
  String get masterPasswordDisabled =>
      'Thông tin đăng nhập sử dụng khóa tự tạo (không có mật khẩu)';

  @override
  String get enterMasterPassword =>
      'Nhập mật khẩu chính để truy cập thông tin đăng nhập đã lưu.';

  @override
  String get wrongMasterPassword => 'Sai mật khẩu. Vui lòng thử lại.';

  @override
  String get newPassword => 'Mật khẩu mới';

  @override
  String get currentPassword => 'Mật khẩu hiện tại';

  @override
  String get passwordTooShort => 'Mật khẩu phải có ít nhất 8 ký tự';

  @override
  String get masterPasswordSet => 'Đã bật mật khẩu chính';

  @override
  String get masterPasswordChanged => 'Đã đổi mật khẩu chính';

  @override
  String get masterPasswordRemoved => 'Đã xóa mật khẩu chính';

  @override
  String get masterPasswordWarning =>
      'Nếu bạn quên mật khẩu này, tất cả mật khẩu và khóa SSH đã lưu sẽ bị mất. Không thể khôi phục.';

  @override
  String get forgotPassword => 'Quên mật khẩu?';

  @override
  String get forgotPasswordWarning =>
      'Thao tác này sẽ xóa TẤT CẢ mật khẩu, khóa SSH và cụm mật khẩu đã lưu. Các phiên và cài đặt sẽ được giữ lại. Không thể hoàn tác.';

  @override
  String get resetAndDeleteCredentials => 'Đặt lại và xóa dữ liệu';

  @override
  String get credentialsReset => 'Tất cả thông tin đăng nhập đã lưu đã bị xóa';

  @override
  String get derivingKey => 'Đang tạo khóa mã hóa...';

  @override
  String get reEncrypting => 'Đang mã hóa lại dữ liệu...';

  @override
  String get confirmRemoveMasterPassword =>
      'Nhập mật khẩu hiện tại để xóa bảo vệ mật khẩu chính. Thông tin đăng nhập sẽ được mã hóa lại bằng khóa tự tạo.';

  @override
  String get securitySetupTitle => 'Thiết lập bảo mật';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'Đã phát hiện chuỗi khóa hệ thống ($keychainName). Dữ liệu của bạn sẽ được tự động mã hóa bằng chuỗi khóa hệ thống.';
  }

  @override
  String get securitySetupKeychainOptional =>
      'Bạn cũng có thể đặt mật khẩu chính để bảo vệ thêm.';

  @override
  String get securitySetupNoKeychain =>
      'Không phát hiện chuỗi khóa hệ thống. Không có chuỗi khóa, dữ liệu phiên (máy chủ, mật khẩu, khóa) sẽ được lưu dạng văn bản thuần.';

  @override
  String get securitySetupNoKeychainHint =>
      'Điều này bình thường trên WSL, Linux không giao diện hoặc cài đặt tối thiểu. Để bật chuỗi khóa trên Linux: cài libsecret và daemon chuỗi khóa (VD: gnome-keyring).';

  @override
  String get securitySetupRecommendMasterPassword =>
      'Chúng tôi khuyên bạn nên đặt mật khẩu chính để bảo vệ dữ liệu.';

  @override
  String get continueWithKeychain => 'Tiếp tục với chuỗi khóa';

  @override
  String get continueWithoutEncryption => 'Tiếp tục không mã hóa';

  @override
  String get securityLevel => 'Mức bảo mật';

  @override
  String get securityLevelPlaintext => 'Không (văn bản thuần)';

  @override
  String get securityLevelKeychain => 'Chuỗi khóa hệ thống';

  @override
  String get securityLevelMasterPassword => 'Mật khẩu chính';

  @override
  String get keychainStatus => 'Chuỗi khóa';

  @override
  String keychainAvailable(String name) {
    return 'Khả dụng ($name)';
  }

  @override
  String get keychainNotAvailable => 'Không khả dụng';

  @override
  String get enableKeychain => 'Bật mã hóa chuỗi khóa';

  @override
  String get enableKeychainSubtitle =>
      'Mã hóa lại dữ liệu được lưu bằng chuỗi khóa hệ thống';

  @override
  String get keychainEnabled => 'Mã hóa chuỗi khóa đã được bật';

  @override
  String get manageMasterPassword => 'Quản lý mật khẩu chính';

  @override
  String get manageMasterPasswordSubtitle => 'Đặt, đổi hoặc xóa mật khẩu chính';

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
  String get fullBackup => 'Sao lưu đầy đủ';

  @override
  String get sessionsOnly => 'Phiên';

  @override
  String get sessionKeysFromManager => 'Khóa phiên từ trình quản lý';

  @override
  String get allKeysFromManager => 'Tất cả khóa từ trình quản lý';

  @override
  String exportTags(int count) {
    return 'Thẻ ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'Đoạn mã ($count)';
  }

  @override
  String get disableKeychain => 'Tắt mã hóa keychain';

  @override
  String get disableKeychainSubtitle =>
      'Chuyển sang lưu trữ văn bản thuần (không khuyến nghị)';

  @override
  String get disableKeychainConfirm =>
      'Cơ sở dữ liệu sẽ được mã hóa lại mà không có khóa. Các phiên và khóa sẽ được lưu trữ dưới dạng văn bản thuần trên đĩa. Tiếp tục?';

  @override
  String get keychainDisabled => 'Đã tắt mã hóa keychain';

  @override
  String get presetFullImport => 'Full import';

  @override
  String get presetSelective => 'Selective';

  @override
  String get presetCustom => 'Custom';

  @override
  String get sessionSshKeys => 'Session SSH keys';

  @override
  String get allManagerKeys => 'All manager keys';
}
