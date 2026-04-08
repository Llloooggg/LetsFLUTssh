// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class SZh extends S {
  SZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => '确定';

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get connect => '连接';

  @override
  String get retry => '重试';

  @override
  String get import_ => '导入';

  @override
  String get export_ => '导出';

  @override
  String get rename => '重命名';

  @override
  String get create => '创建';

  @override
  String get back => '返回';

  @override
  String get copy => '复制';

  @override
  String get paste => '粘贴';

  @override
  String get select => '选择';

  @override
  String get required => '必填';

  @override
  String get settings => '设置';

  @override
  String get terminal => '终端';

  @override
  String get files => '文件';

  @override
  String get transfer => '传输';

  @override
  String get open => '打开';

  @override
  String get search => '搜索...';

  @override
  String get filter => '筛选...';

  @override
  String get merge => '合并';

  @override
  String get replace => '替换';

  @override
  String get reconnect => '重新连接';

  @override
  String get updateAvailable => '有可用更新';

  @override
  String updateVersionAvailable(String version, String current) {
    return '版本 $version 可用（当前：v$current）。';
  }

  @override
  String get releaseNotes => '更新说明：';

  @override
  String get skipThisVersion => '跳过此版本';

  @override
  String get unskip => '取消跳过';

  @override
  String get downloadAndInstall => '下载并安装';

  @override
  String get openInBrowser => '在浏览器中打开';

  @override
  String get couldNotOpenBrowser => '无法打开浏览器 — URL 已复制到剪贴板';

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get checkForUpdatesOnStartup => '启动时检查更新';

  @override
  String get checking => '检查中...';

  @override
  String get youreUpToDate => '已是最新版本';

  @override
  String get updateCheckFailed => '检查更新失败';

  @override
  String get unknownError => '未知错误';

  @override
  String downloadingPercent(int percent) {
    return '下载中... $percent%';
  }

  @override
  String get downloadComplete => '下载完成';

  @override
  String get installNow => '立即安装';

  @override
  String get couldNotOpenInstaller => '无法打开安装程序';

  @override
  String versionAvailable(String version) {
    return '版本 $version 可用';
  }

  @override
  String currentVersion(String version) {
    return '当前：v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return '已接收 SSH 密钥：$filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return '通过 QR 导入了 $count 个会话';
  }

  @override
  String importedSessions(int count) {
    return '已导入 $count 个会话';
  }

  @override
  String importFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get sessions => '会话';

  @override
  String get sessionsHeader => '会话';

  @override
  String get savedSessions => '已保存的会话';

  @override
  String get activeConnections => '活动连接';

  @override
  String get openTabs => '打开的标签页';

  @override
  String get noSavedSessions => '没有已保存的会话';

  @override
  String get addSession => '添加会话';

  @override
  String get noSessions => '没有会话';

  @override
  String get noSessionsToExport => '没有可导出的会话';

  @override
  String nSelectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get selectAll => '全选';

  @override
  String get deselectAll => '取消全选';

  @override
  String get moveTo => '移动到...';

  @override
  String get moveToFolder => '移动到文件夹';

  @override
  String get rootFolder => '/（根目录）';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get newConnection => '新建连接';

  @override
  String get editConnection => '编辑连接';

  @override
  String get duplicate => '复制';

  @override
  String get deleteSession => '删除会话';

  @override
  String get renameFolder => '重命名文件夹';

  @override
  String get deleteFolder => '删除文件夹';

  @override
  String get deleteSelected => '删除所选';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return '删除 $parts？\n\n此操作无法撤销。';
  }

  @override
  String nSessions(int count) {
    return '$count 个会话';
  }

  @override
  String nFolders(int count) {
    return '$count 个文件夹';
  }

  @override
  String deleteFolderConfirm(String name) {
    return '删除文件夹 \"$name\"？';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return '这也将删除其中的 $count 个会话。';
  }

  @override
  String deleteSessionConfirm(String name) {
    return '删除 \"$name\"？';
  }

  @override
  String get connection => '连接';

  @override
  String get auth => '认证';

  @override
  String get options => '选项';

  @override
  String get sessionName => '会话名称';

  @override
  String get hintMyServer => '我的服务器';

  @override
  String get hostRequired => '主机 *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => '端口';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => '用户名 *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => '密码';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => '密钥密码';

  @override
  String get hintOptional => '可选';

  @override
  String get hidePemText => '隐藏 PEM 文本';

  @override
  String get pastePemKeyText => '粘贴 PEM 密钥文本';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => '暂无其他选项';

  @override
  String get saveAndConnect => '保存并连接';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst => '请先提供密钥文件或 PEM 文本';

  @override
  String get keyTextPem => '密钥文本 (PEM)';

  @override
  String get selectKeyFile => '选择密钥文件';

  @override
  String get clearKeyFile => '清除密钥文件';

  @override
  String get authOrDivider => '或';

  @override
  String get providePasswordOrKey => '请提供密码或 SSH 密钥';

  @override
  String get quickConnect => '快速连接';

  @override
  String get scanQrCode => '扫描 QR 码';

  @override
  String get qrGenerationFailed => 'QR 码生成失败';

  @override
  String get scanWithCameraApp => '使用已安装 LetsFLUTssh 的设备上的\n相机应用扫描。';

  @override
  String get noPasswordsInQr => '此 QR 码中不包含密码或密钥';

  @override
  String get copyLink => '复制链接';

  @override
  String get linkCopied => '链接已复制到剪贴板';

  @override
  String get hostKeyChanged => '主机密钥已更改！';

  @override
  String get unknownHost => '未知主机';

  @override
  String get hostKeyChangedWarning =>
      '警告：此服务器的主机密钥已更改。这可能表示存在中间人攻击，或服务器已被重新安装。';

  @override
  String get unknownHostMessage => '无法验证此主机的真实性。确定要继续连接吗？';

  @override
  String get host => '主机';

  @override
  String get keyType => '密钥类型';

  @override
  String get fingerprint => '指纹';

  @override
  String get fingerprintCopied => '指纹已复制';

  @override
  String get copyFingerprint => '复制指纹';

  @override
  String get acceptAnyway => '仍然接受';

  @override
  String get accept => '接受';

  @override
  String get importData => '导入数据';

  @override
  String get masterPassword => '主密码';

  @override
  String get confirmPassword => '确认密码';

  @override
  String get importModeMergeDescription => '添加新会话，保留已有会话';

  @override
  String get importModeReplaceDescription => '用导入的会话替换所有会话';

  @override
  String errorPrefix(String error) {
    return '错误：$error';
  }

  @override
  String get folderName => '文件夹名称';

  @override
  String get newName => '新名称';

  @override
  String deleteItems(String names) {
    return '删除 $names？';
  }

  @override
  String deleteNItems(int count) {
    return '删除 $count 项';
  }

  @override
  String deletedItem(String name) {
    return '已删除 $name';
  }

  @override
  String deletedNItems(int count) {
    return '已删除 $count 项';
  }

  @override
  String failedToCreateFolder(String error) {
    return '创建文件夹失败：$error';
  }

  @override
  String failedToRename(String error) {
    return '重命名失败：$error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return '删除 $name 失败：$error';
  }

  @override
  String get editPath => '编辑路径';

  @override
  String get root => '根目录';

  @override
  String get controllersNotInitialized => '控制器未初始化';

  @override
  String get initializingSftp => '正在初始化 SFTP...';

  @override
  String get clearHistory => '清除历史';

  @override
  String get noTransfersYet => '暂无传输记录';

  @override
  String get duplicateTab => '复制标签页';

  @override
  String get duplicateTabShortcut => '复制标签页 (Ctrl+\\)';

  @override
  String get copyDown => '向下复制';

  @override
  String get previous => '上一个';

  @override
  String get next => '下一个';

  @override
  String get closeEsc => '关闭 (Esc)';

  @override
  String get closeAll => '关闭全部';

  @override
  String get closeOthers => '关闭其他';

  @override
  String get closeTabsToTheLeft => '关闭左侧标签页';

  @override
  String get closeTabsToTheRight => '关闭右侧标签页';

  @override
  String get sortByName => '按名称排序';

  @override
  String get sortByStatus => '按状态排序';

  @override
  String get noActiveSession => '没有活动会话';

  @override
  String get createConnectionHint => '创建新连接或从侧边栏选择一个';

  @override
  String get hideSidebar => '隐藏侧边栏 (Ctrl+B)';

  @override
  String get showSidebar => '显示侧边栏 (Ctrl+B)';

  @override
  String get language => '语言';

  @override
  String get languageSystemDefault => '自动';

  @override
  String get theme => '主题';

  @override
  String get themeDark => '深色';

  @override
  String get themeLight => '浅色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get appearance => '外观';

  @override
  String get connectionSection => '连接';

  @override
  String get transfers => '传输';

  @override
  String get data => '数据';

  @override
  String get logging => '日志';

  @override
  String get updates => '更新';

  @override
  String get about => '关于';

  @override
  String get resetToDefaults => '恢复默认设置';

  @override
  String get uiScale => '界面缩放';

  @override
  String get terminalFontSize => '终端字体大小';

  @override
  String get scrollbackLines => '回滚行数';

  @override
  String get keepAliveInterval => '保活间隔（秒）';

  @override
  String get sshTimeout => 'SSH 超时（秒）';

  @override
  String get defaultPort => '默认端口';

  @override
  String get parallelWorkers => '并行工作线程';

  @override
  String get maxHistory => '最大历史记录';

  @override
  String get calculateFolderSizes => '计算文件夹大小';

  @override
  String get exportData => '导出数据';

  @override
  String get exportDataSubtitle => '将会话、配置和密钥保存为加密的 .lfs 文件';

  @override
  String get importDataSubtitle => '从 .lfs 文件加载数据';

  @override
  String get setMasterPasswordHint => '设置主密码以加密存档。';

  @override
  String get passwordsDoNotMatch => '密码不一致';

  @override
  String exportedTo(String path) {
    return '已导出至：$path';
  }

  @override
  String exportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get pathToLfsFile => '.lfs 文件路径';

  @override
  String get hintLfsPath => '/path/to/export.lfs';

  @override
  String get browse => '浏览';

  @override
  String get shareViaQrCode => '通过 QR 码分享';

  @override
  String get shareViaQrSubtitle => '将会话导出为 QR 码，供其他设备扫描';

  @override
  String get dataLocation => '数据位置';

  @override
  String get pathCopied => '路径已复制到剪贴板';

  @override
  String get urlCopied => 'URL 已复制到剪贴板';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — SSH/SFTP 客户端';
  }

  @override
  String get sourceCode => '源代码';

  @override
  String get enableLogging => '启用日志';

  @override
  String get logIsEmpty => '日志为空';

  @override
  String logExportedTo(String path) {
    return '日志已导出至：$path';
  }

  @override
  String logExportFailed(String error) {
    return '日志导出失败：$error';
  }

  @override
  String get logsCleared => '日志已清除';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get copyLog => '复制日志';

  @override
  String get exportLog => '导出日志';

  @override
  String get clearLogs => '清除日志';

  @override
  String get local => '本地';

  @override
  String get remote => '远程';

  @override
  String get pickFolder => '选择文件夹';

  @override
  String get refresh => '刷新';

  @override
  String get up => '上级';

  @override
  String get emptyDirectory => '空目录';

  @override
  String get cancelSelection => '取消选择';

  @override
  String get openSftpBrowser => '打开 SFTP 浏览器';

  @override
  String get openSshTerminal => '打开 SSH 终端';

  @override
  String get noActiveFileBrowsers => '没有活动的文件浏览器';

  @override
  String get useSftpFromSessions => '从会话中使用 \"SFTP\"';

  @override
  String get anotherInstanceRunning => 'LetsFLUTssh 的另一个实例已在运行。';

  @override
  String importFailedShort(String error) {
    return '导入失败：$error';
  }

  @override
  String get saveLogAs => '日志另存为';

  @override
  String get chooseSaveLocation => '选择保存位置';

  @override
  String get forward => '前进';

  @override
  String get name => '名称';

  @override
  String get size => '大小';

  @override
  String get modified => '修改时间';

  @override
  String get mode => '权限';

  @override
  String get owner => '所有者';

  @override
  String get connectionError => '连接错误';

  @override
  String get resizeWindowToViewFiles => '调整窗口大小以查看文件';

  @override
  String get completed => '已完成';

  @override
  String get connected => '已连接';

  @override
  String get disconnected => '已断开';

  @override
  String get exit => '退出';

  @override
  String get exitConfirmation => '活动会话将被断开。确定退出吗？';

  @override
  String get hintFolderExample => '例如 Production';

  @override
  String get credentialsNotSet => '凭据未设置';

  @override
  String get exportSessionsViaQr => '通过 QR 导出会话';

  @override
  String get qrNoCredentialsWarning => '密码和 SSH 密钥不会包含在内。\n导入的会话需要重新填写凭据。';

  @override
  String get qrTooManyForSingleCode => '会话过多，无法生成单个 QR 码。请取消部分选择或使用 .lfs 导出。';

  @override
  String get qrTooLarge => '数据过大——请取消部分选择或使用 .lfs 文件导出。';

  @override
  String get exportAll => '全部导出';

  @override
  String get showQr => '显示 QR';

  @override
  String get sort => '排序';

  @override
  String get resizePanelDivider => '调整面板分隔线';

  @override
  String get youreRunningLatest => '您正在使用最新版本';

  @override
  String get liveLog => '实时日志';

  @override
  String transferNItems(int count) {
    return '传输 $count 个项目';
  }

  @override
  String get time => '时间';

  @override
  String get failed => '失败';

  @override
  String get errOperationNotPermitted => '操作不允许';

  @override
  String get errNoSuchFileOrDirectory => '文件或目录不存在';

  @override
  String get errNoSuchProcess => '进程不存在';

  @override
  String get errIoError => 'I/O 错误';

  @override
  String get errBadFileDescriptor => '无效的文件描述符';

  @override
  String get errResourceTemporarilyUnavailable => '资源暂时不可用';

  @override
  String get errOutOfMemory => '内存不足';

  @override
  String get errPermissionDenied => '权限被拒绝';

  @override
  String get errFileExists => '文件已存在';

  @override
  String get errNotADirectory => '不是目录';

  @override
  String get errIsADirectory => '是一个目录';

  @override
  String get errInvalidArgument => '无效参数';

  @override
  String get errTooManyOpenFiles => '打开的文件过多';

  @override
  String get errNoSpaceLeftOnDevice => '设备上没有剩余空间';

  @override
  String get errReadOnlyFileSystem => '只读文件系统';

  @override
  String get errBrokenPipe => '管道中断';

  @override
  String get errFileNameTooLong => '文件名过长';

  @override
  String get errDirectoryNotEmpty => '目录不为空';

  @override
  String get errAddressAlreadyInUse => '地址已被占用';

  @override
  String get errCannotAssignAddress => '无法分配请求的地址';

  @override
  String get errNetworkIsDown => '网络已断开';

  @override
  String get errNetworkIsUnreachable => '网络不可达';

  @override
  String get errConnectionResetByPeer => '连接被对端重置';

  @override
  String get errConnectionTimedOut => '连接超时';

  @override
  String get errConnectionRefused => '连接被拒绝';

  @override
  String get errHostIsDown => '主机已关闭';

  @override
  String get errNoRouteToHost => '没有到主机的路由';

  @override
  String get errConnectionAborted => '连接已中止';

  @override
  String get errAlreadyConnected => '已连接';

  @override
  String get errNotConnected => '未连接';

  @override
  String errSshConnectFailed(String host, int port) {
    return '无法连接到 $host:$port';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return '$user@$host 认证失败';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return '连接 $host:$port 失败';
  }

  @override
  String get errSshAuthAborted => '认证已中止';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return '$host:$port 的主机密钥被拒绝 — 请接受主机密钥或检查 known_hosts';
  }

  @override
  String get errSshOpenShellFailed => '打开 Shell 失败';

  @override
  String get errSshLoadKeyFileFailed => '加载 SSH 密钥文件失败';

  @override
  String get errSshParseKeyFailed => '解析 PEM 密钥数据失败';

  @override
  String get errSshConnectionDisposed => '连接已释放';

  @override
  String get errSshNotConnected => '未连接';

  @override
  String get errConnectionFailed => '连接失败';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return '连接在 $seconds 秒后超时';
  }

  @override
  String get errSessionClosed => '会话已关闭';

  @override
  String errShellError(String error) {
    return 'Shell 错误：$error';
  }

  @override
  String errReconnectFailed(String error) {
    return '重新连接失败：$error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'SFTP 初始化失败：$error';
  }

  @override
  String errDownloadFailed(String error) {
    return '下载失败：$error';
  }

  @override
  String get errDecryptionFailed => '凭据解密失败。密钥文件可能已损坏。';

  @override
  String errWithPath(String error, String path) {
    return '$error：$path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error（$cause）';
  }

  @override
  String get login => '用户名';

  @override
  String get protocol => '协议';

  @override
  String get typeLabel => '类型';

  @override
  String get folder => '文件夹';

  @override
  String nSubitems(int count) {
    return '$count 个项目';
  }

  @override
  String get subitems => '项目';

  @override
  String get storagePermissionRequired => '需要存储权限才能浏览本地文件';

  @override
  String get grantPermission => '授予权限';

  @override
  String get storagePermissionLimited => '访问受限 — 请授予完整存储权限以访问所有文件';

  @override
  String progressConnecting(String host, int port) {
    return '正在连接 $host:$port';
  }

  @override
  String get progressVerifyingHostKey => '正在验证主机密钥';

  @override
  String progressAuthenticating(String user) {
    return '正在以 $user 身份认证';
  }

  @override
  String get progressOpeningShell => '正在打开终端';

  @override
  String get progressOpeningSftp => '正在打开 SFTP 通道';

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
  String get maximize => '最大化';

  @override
  String get restore => '恢复';

  @override
  String get duplicateDownShortcut => '向下复制 (Ctrl+Shift+\\)';
}
