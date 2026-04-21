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
  String get infoDialogProtectsHeader => '防护范围';

  @override
  String get infoDialogDoesNotProtectHeader => '不在防护范围';

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
  String get appSettings => '应用设置';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get importWhatToImport => '导入内容：';

  @override
  String get exportWhatToExport => '导出内容：';

  @override
  String get enterMasterPasswordPrompt => '输入主密码:';

  @override
  String get nextStep => '下一步';

  @override
  String get includeCredentials => '包含密码和 SSH 密钥';

  @override
  String get includePasswords => '会话密码';

  @override
  String get embeddedKeys => '内置密钥';

  @override
  String get managerKeys => '管理器中的密钥';

  @override
  String get managerKeysMayBeLarge => '管理器密钥可能超出 QR 大小限制';

  @override
  String get qrPasswordWarning => '导出时 SSH 密钥默认已禁用。';

  @override
  String get sshKeysMayBeLarge => '密钥可能超出 QR 大小';

  @override
  String exportTotalSize(String size) {
    return '总大小: $size';
  }

  @override
  String get qrCredentialsWarning => '密码和 SSH 密钥将在 QR 码中可见';

  @override
  String get qrCredentialsTooLarge => '凭证使 QR 码过大';

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
  String get noResults => '无结果';

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
  String get checkNow => '立即检查';

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
  String get openReleasePage => '打开发布页面';

  @override
  String get couldNotOpenInstaller => '无法打开安装程序';

  @override
  String get installerFailedOpenedReleasePage => '启动安装程序失败；已在浏览器中打开发布页面';

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
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已丢弃 $count 个关联（目标缺失）',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已跳过 $count 个损坏的会话',
    );
    return '$_temp0';
  }

  @override
  String get sessions => '会话';

  @override
  String get emptyFolders => '空文件夹';

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
  String get emptyFolder => '空文件夹';

  @override
  String get qrGenerationFailed => 'QR 码生成失败';

  @override
  String get scanWithCameraApp => '使用已安装 LetsFLUTssh 的设备上的\n相机应用扫描。';

  @override
  String get noPasswordsInQr => '此 QR 码中不包含密码或密钥';

  @override
  String get qrContainsCredentialsWarning => '此二维码包含凭据。请保持屏幕隐私。';

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
  String sshConfigPreviewHostsFound(int count) {
    return '找到 $count 个主机';
  }

  @override
  String get sshConfigPreviewNoHosts => '此文件中未找到可导入的主机。';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return '无法读取以下主机的密钥文件：$hosts。这些主机将在没有凭据的情况下被导入。';
  }

  @override
  String sshConfigPreviewFolderLabel(String folder) {
    return '已导入到文件夹：$folder';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => '导出存档';

  @override
  String get exportArchiveSubtitle => '将会话、配置和密钥保存为加密的 .lfs 文件';

  @override
  String get exportQrCode => '导出二维码';

  @override
  String get exportQrCodeSubtitle => '通过二维码分享所选会话和密钥';

  @override
  String get importArchive => '导入存档';

  @override
  String get importArchiveSubtitle => '从 .lfs 文件加载数据';

  @override
  String get importFromSshDir => '从 ~/.ssh 导入';

  @override
  String get importFromSshDirSubtitle => '从配置文件选择主机，和/或从 ~/.ssh 选择私钥';

  @override
  String get sshDirImportHostsSection => '来自配置文件的主机';

  @override
  String get sshDirImportKeysSection => '~/.ssh 中的密钥';

  @override
  String importSshKeysFound(int count) {
    return '找到 $count 个密钥 — 请选择要导入的密钥';
  }

  @override
  String get importSshKeysNoneFound => '在 ~/.ssh 中未找到私钥。';

  @override
  String get sshKeyAlreadyImported => '已在存储中';

  @override
  String get setMasterPasswordHint => '设置主密码以加密存档。';

  @override
  String get passwordsDoNotMatch => '密码不匹配';

  @override
  String get passwordStrengthWeak => '弱';

  @override
  String get passwordStrengthModerate => '中等';

  @override
  String get passwordStrengthStrong => '强';

  @override
  String get passwordStrengthVeryStrong => '很强';

  @override
  String get tierRecommendedBadge => '推荐';

  @override
  String get tierCurrentBadge => '当前';

  @override
  String get tierAlternativeBranchLabel => '替代方案 — 不信任操作系统';

  @override
  String get tierUpcomingTooltip => '将在后续版本中提供。';

  @override
  String get tierUpcomingNotes => '此层级的底层机制尚未发布。该行可见是为了让您知道此选项存在。';

  @override
  String get tierPlaintextLabel => '明文';

  @override
  String get tierPlaintextSubtitle => '无加密 — 仅文件权限';

  @override
  String get tierPlaintextThreat1 => '任何拥有文件系统访问权限的人都能读取您的数据';

  @override
  String get tierPlaintextThreat2 => '意外同步或备份会暴露一切';

  @override
  String get tierPlaintextNotes => '仅在受信任的隔离环境中使用。';

  @override
  String get tierKeychainLabel => '钥匙串';

  @override
  String tierKeychainSubtitle(String keychain) {
    return '密钥存放于 $keychain — 启动时自动解锁';
  }

  @override
  String get tierKeychainProtect1 => '同一机器上的其他用户';

  @override
  String get tierKeychainProtect2 => '没有操作系统登录的被盗磁盘';

  @override
  String get tierKeychainThreat1 => '在您的操作系统账户下运行的恶意软件';

  @override
  String get tierKeychainThreat2 => '接管您的操作系统登录的攻击者';

  @override
  String get tierKeychainUnavailable => '此安装无法使用操作系统钥匙串。';

  @override
  String get tierKeychainPassProtect1 => '坐在您桌前的同事';

  @override
  String get tierKeychainPassProtect2 => '具有解锁访问权限的路人';

  @override
  String get tierKeychainPassThreat1 => '拥有磁盘上文件的离线攻击者';

  @override
  String get tierKeychainPassThreat2 => '与钥匙串相同的操作系统入侵风险';

  @override
  String get tierHardwareLabel => '硬件';

  @override
  String get tierHardwareSubtitle => '绑定硬件的保险库 + 带锁定的短 PIN';

  @override
  String get tierHardwareProtect1 => 'PIN 的离线暴力破解（硬件速率限制）';

  @override
  String get tierHardwareProtect2 => '偷窃磁盘和钥匙串 blob';

  @override
  String get tierHardwareThreat1 => '安全模块上的操作系统或固件 CVE';

  @override
  String get tierHardwareThreat2 => '强制生物识别解锁（如果启用）';

  @override
  String get tierParanoidLabel => '主密码 (Paranoid)';

  @override
  String get tierParanoidSubtitle => '长密码 + Argon2id。密钥从不进入操作系统。';

  @override
  String get tierParanoidProtect1 => '操作系统钥匙串入侵';

  @override
  String get tierParanoidProtect2 => '被盗磁盘（只要您的密码足够强）';

  @override
  String get tierParanoidThreat1 => '捕获您密码的键盘记录器';

  @override
  String get tierParanoidThreat2 => '弱密码 + 离线 Argon2id 破解';

  @override
  String get tierParanoidNotes => '此层级上的生物识别按设计禁用。';

  @override
  String get tierHardwareUnavailable => '此安装不支持硬件保险库。';

  @override
  String get pinLabel => 'PIN';

  @override
  String get l2UnlockTitle => '需要密码';

  @override
  String get l2UnlockHint => '输入您的短密码以继续';

  @override
  String get l2WrongPassword => '密码错误';

  @override
  String get l3UnlockTitle => '输入 PIN';

  @override
  String get l3UnlockHint => '短 PIN 解锁硬件绑定的保险库';

  @override
  String get l3WrongPin => 'PIN 错误';

  @override
  String tierCooldownHint(int seconds) {
    return '$seconds 秒后重试';
  }

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
  String get dataStorageSection => '存储';

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
  String get errExportPickerUnavailable => '系统文件夹选择器不可用。请尝试其他位置或检查应用的存储权限。';

  @override
  String get biometricUnlockPrompt => '解锁 LetsFLUTssh';

  @override
  String get biometricUnlockTitle => '使用生物识别解锁';

  @override
  String get biometricUnlockSubtitle => '无需输入密码——使用设备生物识别传感器解锁。';

  @override
  String get biometricNotAvailable => '此设备不支持生物识别解锁。';

  @override
  String get biometricEnableFailed => '无法启用生物识别解锁。';

  @override
  String get biometricEnabled => '已启用生物识别解锁';

  @override
  String get biometricDisabled => '已停用生物识别解锁';

  @override
  String get biometricUnlockFailed => '生物识别解锁失败。请输入主密码。';

  @override
  String get biometricUnlockCancelled => '生物识别解锁已取消。';

  @override
  String get biometricNotEnrolled => '此设备未注册任何生物识别凭据。';

  @override
  String get biometricRequiresMasterPassword => '请先设置主密码以启用生物识别解锁。';

  @override
  String get biometricSensorNotAvailable => '此设备没有生物识别传感器。';

  @override
  String get biometricSystemServiceMissing =>
      '指纹服务 (fprintd) 未安装。请参阅 README → Installation。';

  @override
  String get biometricBackingHardware => '硬件支持 (Secure Enclave / TPM)';

  @override
  String get biometricBackingSoftware => '软件支持';

  @override
  String get currentPasswordIncorrect => '当前密码不正确';

  @override
  String get wrongPassword => '密码错误';

  @override
  String get useKeychain => '使用操作系统钥匙串加密';

  @override
  String get useKeychainSubtitle => '将数据库密钥保存在系统凭据存储中。关闭 = 明文数据库。';

  @override
  String get lockScreenTitle => 'LetsFLUTssh 已锁定';

  @override
  String get lockScreenSubtitle => '输入主密码或使用生物识别以继续。';

  @override
  String get unlock => '解锁';

  @override
  String get autoLockTitle => '闲置后自动锁定';

  @override
  String get autoLockSubtitle =>
      '在闲置达到此时长后锁定界面。每次锁定都会清除数据库密钥并关闭加密存储；活动会话通过按会话缓存的凭据保持连接，该缓存会在会话关闭时清空。';

  @override
  String get autoLockOff => '关闭';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes 分钟',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      '更新已拒绝：下载的文件未使用应用中固定的发布密钥签名。这可能意味着下载过程中被篡改，或者当前版本并非适用于此安装。请勿安装 — 请从官方发布页面手动重新安装。';

  @override
  String get updateSecurityWarningTitle => '更新验证失败';

  @override
  String get updateReinstallAction => '打开发布页';

  @override
  String get errLfsNotArchive => '所选文件不是 LetsFLUTssh 归档。';

  @override
  String get errLfsDecryptFailed => '主密码错误或 .lfs 归档已损坏';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return '归档过大（$sizeMb MB）。上限为 $limitMb MB — 已在解密前中止以保护内存。';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'known_hosts 条目过大（$sizeMb MB）。上限为 $limitMb MB — 为保持导入响应性已中止。';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return '导入失败 — 您的数据已恢复到导入前的状态。($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return '归档使用架构 v$found，但此版本仅支持到 v$supported。请更新应用以导入它。';
  }

  @override
  String get progressReadingArchive => '正在读取归档…';

  @override
  String get progressDecrypting => '正在解密…';

  @override
  String get progressParsingArchive => '正在解析归档…';

  @override
  String get progressImportingSessions => '正在导入会话';

  @override
  String get progressImportingFolders => '正在导入文件夹';

  @override
  String get progressImportingManagerKeys => '正在导入 SSH 密钥';

  @override
  String get progressImportingTags => '正在导入标签';

  @override
  String get progressImportingSnippets => '正在导入代码片段';

  @override
  String get progressApplyingConfig => '正在应用配置…';

  @override
  String get progressImportingKnownHosts => '正在导入 known_hosts…';

  @override
  String get progressCollectingData => '正在收集数据…';

  @override
  String get progressEncrypting => '正在加密…';

  @override
  String get progressWritingArchive => '正在写入归档…';

  @override
  String get progressReencrypting => '正在重新加密存储…';

  @override
  String get progressWorking => '处理中…';

  @override
  String get importFromLink => '从 QR 链接导入';

  @override
  String get importFromLinkSubtitle => '粘贴从其他设备复制的 letsflutssh:// 深层链接';

  @override
  String get pasteImportLinkTitle => '粘贴导入链接';

  @override
  String get pasteImportLinkDescription =>
      '粘贴在其他设备生成的 letsflutssh://import?d=… 链接（或原始负载）。无需摄像头。';

  @override
  String get pasteFromClipboard => '从剪贴板粘贴';

  @override
  String get invalidImportLink => '链接不包含有效的 LetsFLUTssh 数据';

  @override
  String get importAction => '导入';

  @override
  String get saveSessionToAssignTags => '先保存会话才能分配标签';

  @override
  String get noTagsAssigned => '未分配标签';

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
  String get transfersLabel => '传输：';

  @override
  String transferCountActive(int count) {
    return '$count 个活跃';
  }

  @override
  String transferCountQueued(int count) {
    return '，$count 个排队';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count 个历史记录';
  }

  @override
  String transferTooltipCreated(String time) {
    return '创建时间：$time';
  }

  @override
  String transferTooltipStarted(String time) {
    return '开始时间：$time';
  }

  @override
  String transferTooltipEnded(String time) {
    return '结束时间：$time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return '持续时间：$duration';
  }

  @override
  String get transferStatusQueued => '排队中';

  @override
  String get transferStartingUpload => '正在开始上传...';

  @override
  String get transferStartingDownload => '正在开始下载...';

  @override
  String get transferCopying => '正在复制...';

  @override
  String get transferDone => '完成';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total 个文件';
  }

  @override
  String get fileConflictTitle => '文件已存在';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" 已存在于 $targetDir 中。您想怎么做？';
  }

  @override
  String get fileConflictSkip => '跳过';

  @override
  String get fileConflictKeepBoth => '保留两者';

  @override
  String get fileConflictReplace => '替换';

  @override
  String get fileConflictApplyAll => '应用于所有剩余项';

  @override
  String get folderNameLabel => '文件夹名称';

  @override
  String folderAlreadyExists(String name) {
    return '文件夹“$name”已存在';
  }

  @override
  String get dropKeyFileHere => '将密钥文件拖放到此处';

  @override
  String get sessionNoCredentials => '会话没有凭据——请先编辑添加密码或密钥';

  @override
  String dragItemCount(int count) {
    return '$count 个项目';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return '全选 ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return '大小：$size KB / 最大 $max KB';
  }

  @override
  String get noActiveTerminals => '没有活跃的终端';

  @override
  String get connectFromSessionsTab => '从会话标签页连接';

  @override
  String fileNotFound(String path) {
    return '文件未找到：$path';
  }

  @override
  String get sshConnectionChannel => 'SSH 连接';

  @override
  String get sshConnectionChannelDesc => '在后台保持 SSH 连接活跃。';

  @override
  String get sshActive => 'SSH 活跃';

  @override
  String activeConnectionCount(int count) {
    return '$count 个活跃连接';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count 个项目，$size';
  }

  @override
  String get maximize => '最大化';

  @override
  String get restore => '恢复';

  @override
  String get duplicateDownShortcut => '向下复制 (Ctrl+Shift+\\)';

  @override
  String get security => '安全';

  @override
  String get knownHosts => '已知主机';

  @override
  String get knownHostsSubtitle => '管理受信任的 SSH 服务器指纹';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个已知主机',
      zero: '没有已知主机',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty => '没有已知主机。连接到服务器以添加。';

  @override
  String get removeHost => '移除主机';

  @override
  String removeHostConfirm(String host) {
    return '从已知主机中移除 $host？下次连接时需要重新验证密钥。';
  }

  @override
  String get clearAllKnownHosts => '清除所有已知主机';

  @override
  String get clearAllKnownHostsConfirm => '移除所有已知主机？每个服务器密钥都需要重新验证。';

  @override
  String get importKnownHostsSubtitle => '从 OpenSSH known_hosts 文件导入';

  @override
  String get clearedAllHosts => '已清除所有已知主机';

  @override
  String removedHost(String host) {
    return '已移除 $host';
  }

  @override
  String get tools => '工具';

  @override
  String get sshKeys => 'SSH 密钥';

  @override
  String get sshKeysSubtitle => '管理用于身份验证的 SSH 密钥对';

  @override
  String get noKeys => '没有 SSH 密钥。请导入或生成一个。';

  @override
  String get generateKey => '生成密钥';

  @override
  String get importKey => '导入密钥';

  @override
  String get keyLabel => '密钥名称';

  @override
  String get keyLabelHint => '如：工作服务器、GitHub';

  @override
  String get selectKeyType => '密钥类型';

  @override
  String get generating => '正在生成...';

  @override
  String keyGenerated(String label) {
    return '密钥已生成：$label';
  }

  @override
  String keyImported(String label) {
    return '密钥已导入：$label';
  }

  @override
  String get deleteKey => '删除密钥';

  @override
  String deleteKeyConfirm(String label) {
    return '删除密钥“$label”？使用该密钥的会话将失去访问权限。';
  }

  @override
  String keyDeleted(String label) {
    return '密钥已删除：$label';
  }

  @override
  String get publicKey => '公钥';

  @override
  String get publicKeyCopied => '公钥已复制到剪贴板';

  @override
  String get pastePrivateKey => '粘贴私钥 (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => '无效的 PEM 密钥数据';

  @override
  String get selectFromKeyStore => '从密钥库选择';

  @override
  String get noKeySelected => '未选择密钥';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个密钥',
      zero: '没有密钥',
    );
    return '$_temp0';
  }

  @override
  String get generated => '已生成';

  @override
  String get passphraseRequired => '需要密码短语';

  @override
  String passphrasePrompt(String host) {
    return '$host 的 SSH 密钥已加密。请输入密码短语以解锁。';
  }

  @override
  String get passphraseWrong => '密码短语错误。请重试。';

  @override
  String get passphrase => '密码短语';

  @override
  String get rememberPassphrase => '在此会话中记住';

  @override
  String get masterPasswordSubtitle => '使用密码保护已保存的凭据';

  @override
  String get setMasterPassword => '设置主密码';

  @override
  String get changeMasterPassword => '更改主密码';

  @override
  String get removeMasterPassword => '移除主密码';

  @override
  String get masterPasswordEnabled => '凭据受主密码保护';

  @override
  String get masterPasswordDisabled => '凭据使用自动生成的密钥（无密码）';

  @override
  String get enterMasterPassword => '输入主密码以访问已保存的凭据。';

  @override
  String get wrongMasterPassword => '密码错误。请重试。';

  @override
  String get newPassword => '新密码';

  @override
  String get currentPassword => '当前密码';

  @override
  String get masterPasswordSet => '主密码已启用';

  @override
  String get masterPasswordChanged => '主密码已更改';

  @override
  String get masterPasswordRemoved => '主密码已移除';

  @override
  String get masterPasswordWarning => '如果您忘记此密码，所有保存的密码和 SSH 密钥将丢失。无法恢复。';

  @override
  String get forgotPassword => '忘记密码？';

  @override
  String get forgotPasswordWarning =>
      '这将删除所有已保存的密码、SSH 密钥和密码短语。会话和设置将保留。此操作不可撤销。';

  @override
  String get resetAndDeleteCredentials => '重置并删除凭据';

  @override
  String get credentialsReset => '所有已保存的凭据已删除';

  @override
  String get dbCorruptTitle => '无法打开数据库';

  @override
  String get dbCorruptBody => '无法打开磁盘上的数据。请尝试其他凭据，或重置以重新开始。';

  @override
  String get dbCorruptWarning => '重置将永久删除加密数据库和所有安全相关文件。不会恢复任何数据。';

  @override
  String get dbCorruptTryOther => '尝试其他凭据';

  @override
  String get dbCorruptResetContinue => '重置并重新设置';

  @override
  String get dbCorruptExit => '退出 LetsFLUTssh';

  @override
  String get tierResetTitle => '需要重置安全设置';

  @override
  String get tierResetBody =>
      '此安装携带使用不同层级模型的早期版本 LetsFLUTssh 的安全数据。新模型是不兼容的变更 — 没有自动迁移路径。要继续，必须清除此安装中的所有已保存会话、凭据、SSH 密钥和已知主机，并从头运行首次启动设置向导。';

  @override
  String get tierResetWarning =>
      '选择「重置并重新设置」将永久删除加密数据库和所有与安全相关的文件。如果您需要恢复数据，请立即退出应用并重新安装旧版本的 LetsFLUTssh 以先导出数据。';

  @override
  String get tierResetResetContinue => '重置并重新设置';

  @override
  String get tierResetExit => '退出 LetsFLUTssh';

  @override
  String get derivingKey => '正在生成加密密钥...';

  @override
  String get reEncrypting => '正在重新加密数据...';

  @override
  String get confirmRemoveMasterPassword => '输入当前密码以移除主密码保护。凭据将使用自动生成的密钥重新加密。';

  @override
  String get securitySetupTitle => '安全设置';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return '检测到系统钥匙串 ($keychainName)。您的数据将使用系统钥匙串自动加密。';
  }

  @override
  String get securitySetupKeychainOptional => '您还可以设置主密码以获得额外保护。';

  @override
  String get securitySetupNoKeychain =>
      '未检测到系统钥匙串。没有钥匙串，您的会话数据（主机、密码、密钥）将以明文存储。';

  @override
  String get securitySetupNoKeychainHint =>
      '这在 WSL、无头 Linux 或最小安装中是正常的。要在 Linux 上启用钥匙串：安装 libsecret 和钥匙环守护进程（如 gnome-keyring）。';

  @override
  String get securitySetupRecommendMasterPassword => '建议设置主密码以保护您的数据。';

  @override
  String get continueWithKeychain => '使用钥匙串继续';

  @override
  String get continueWithoutEncryption => '不加密继续';

  @override
  String get securityLevel => '安全级别';

  @override
  String get securityLevelPlaintext => '无';

  @override
  String get securityLevelKeychain => '系统钥匙串';

  @override
  String get securityLevelMasterPassword => '主密码';

  @override
  String get keychainStatus => '钥匙串';

  @override
  String get keychainAvailable => '可用';

  @override
  String get keychainNotAvailable => '不可用';

  @override
  String get enableKeychain => '启用钥匙串加密';

  @override
  String get enableKeychainSubtitle => '使用系统钥匙串重新加密存储的数据';

  @override
  String get keychainEnabled => '钥匙串加密已启用';

  @override
  String get manageMasterPassword => '管理主密码';

  @override
  String get manageMasterPasswordSubtitle => '设置、更改或移除主密码';

  @override
  String get changeSecurityTier => '更改安全等级';

  @override
  String get changeSecurityTierSubtitle => '打开等级梯并切换到其他安全等级';

  @override
  String get changeSecurityTierConfirm => '正在用新等级重新加密数据库。此过程不可中断——请保持应用打开直到完成。';

  @override
  String get changeSecurityTierDone => '安全等级已更改';

  @override
  String get changeSecurityTierFailed => '无法更改安全等级';

  @override
  String get firstLaunchSecurityTitle => '已启用安全存储';

  @override
  String get firstLaunchSecurityBody => '你的数据由系统钥匙串中的密钥加密。本设备会自动解锁。';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      '此设备支持硬件存储。请在“设置 → 安全”中升级以使用 TPM / Secure Enclave 绑定。';

  @override
  String get firstLaunchSecurityHardwareUnavailableWindows =>
      '硬件存储不可用——未在此设备上检测到 TPM 2.0。';

  @override
  String get firstLaunchSecurityHardwareUnavailableApple =>
      '硬件存储不可用——此设备未报告 Secure Enclave。';

  @override
  String get firstLaunchSecurityHardwareUnavailableLinux =>
      '硬件存储不可用——请安装 tpm2-tools 并接入 TPM 2.0 设备以启用。';

  @override
  String get firstLaunchSecurityHardwareUnavailableAndroid =>
      '硬件存储不可用——此设备未报告 StrongBox 或 TEE。';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric => '此设备不支持硬件存储。';

  @override
  String get firstLaunchSecurityOpenSettings => '打开设置';

  @override
  String get firstLaunchSecurityDismiss => '知道了';

  @override
  String get securityHardwareUpgradeTitle => '可使用硬件存储';

  @override
  String get securityHardwareUpgradeBody => '升级以将机密绑定到 TPM / Secure Enclave。';

  @override
  String get securityHardwareUpgradeAction => '升级';

  @override
  String get securityHardwareUnavailableTitle => '硬件存储不可用';

  @override
  String get wizardReducedBanner =>
      '本次安装中无法访问系统钥匙串。请在“无加密”（T0）和“主密码”（Paranoid）之间选择。安装 gnome-keyring、kwallet 或其他 libsecret 提供程序以启用钥匙串等级。';

  @override
  String get tierBlockProtectsHeader => '可抵御';

  @override
  String get tierBlockDoesNotProtectHeader => '无法抵御';

  @override
  String get tierBlockProtectsEmpty => '该等级无可抵御项。';

  @override
  String get tierBlockDoesNotProtectEmpty => '无未覆盖威胁。';

  @override
  String get tierBadgeCurrent => '当前';

  @override
  String get securitySetupEnable => '启用';

  @override
  String get securitySetupApply => '应用';

  @override
  String get passwordDisabledPlaintext => '无加密等级不存储可用密码保护的机密。';

  @override
  String get passwordDisabledParanoid => 'Paranoid 从密码派生数据库密钥——始终开启。';

  @override
  String get passwordSubtitleOn => '已开启——解锁时需要密码';

  @override
  String get passwordSubtitleOff => '已关闭——点击为当前等级添加密码';

  @override
  String get passwordSubtitleParanoid => '必需——主密码就是该等级的机密';

  @override
  String get passwordSubtitlePlaintext => '不适用——此等级未加密';

  @override
  String get hwProbeLinuxDeviceMissing =>
      '在 /dev/tpmrm0 上未检测到 TPM。如机器支持，请在 BIOS 中启用 fTPM / PTT；否则该设备无法使用硬件等级。';

  @override
  String get hwProbeLinuxBinaryMissing =>
      '未安装 tpm2-tools。执行 `sudo apt install tpm2-tools`（或您发行版的等效命令）以启用硬件等级。';

  @override
  String get hwProbeLinuxProbeFailed =>
      '硬件等级探测失败。请检查 /dev/tpmrm0 权限与 udev 规则 —— 详情见日志。';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      '未检测到 TPM 2.0。请在 UEFI 固件中启用 fTPM / PTT，或接受此设备上无法使用硬件等级 —— 应用将回退到软件支持的凭据存储。';

  @override
  String get hwProbeWindowsProvidersMissing =>
      '无法访问 Microsoft Platform Crypto Provider 或 Software Key Storage Provider —— 可能是 Windows 加密子系统损坏或组策略阻止了 CNG。请查看 事件查看器 → 应用程序和服务日志。';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      '此 Mac 没有 Secure Enclave（2017 年之前没有 T1 / T2 安全芯片的 Intel Mac）。硬件等级不可用；请使用主密码。';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      '此 Mac 未设置登录密码。Secure Enclave 密钥创建需要登录密码 —— 请在 系统设置 → 触控 ID 与密码（或登录密码）中设置。';

  @override
  String get hwProbeIosPasscodeNotSet =>
      '未设置设备密码。Secure Enclave 密钥创建需要密码 —— 请在 设置 → 面容 ID 与密码（或触控 ID 与密码）中设置。';

  @override
  String get hwProbeIosSimulator =>
      '在 iOS 模拟器上运行，不具备 Secure Enclave。硬件等级仅在实体 iOS 设备上可用。';

  @override
  String get hwProbeAndroidApiTooLow =>
      '硬件等级需要 Android 9 或更高版本（StrongBox 与密钥注册失效在较旧版本上不可靠）。';

  @override
  String get hwProbeAndroidBiometricNone => '此设备没有生物识别硬件（指纹或人脸）。请改用主密码。';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      '未注册生物识别。请在 设置 → 安全和隐私 → 生物识别 中添加指纹或人脸，然后重新启用硬件等级。';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      '生物识别硬件暂时不可用（失败尝试后锁定或待处理的安全更新）。请几分钟后重试。';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus 正在运行但没有 secret-service daemon 在运行。请安装 gnome-keyring（`sudo apt install gnome-keyring`）或 KWalletManager 并确保它在登录时启动。';

  @override
  String get keyringProbeFailed => '此设备上无法访问操作系统密钥链。请查看日志以获取特定平台错误；应用将回退到主密码。';

  @override
  String get snippets => '代码片段';

  @override
  String get snippetsSubtitle => '管理可重用的命令片段';

  @override
  String get noSnippets => '暂无代码片段';

  @override
  String get addSnippet => '添加代码片段';

  @override
  String get editSnippet => '编辑代码片段';

  @override
  String get deleteSnippet => '删除代码片段';

  @override
  String deleteSnippetConfirm(String title) {
    return '删除代码片段「$title」？';
  }

  @override
  String get snippetTitle => '标题';

  @override
  String get snippetTitleHint => '例如：部署、重启服务';

  @override
  String get snippetCommand => '命令';

  @override
  String get snippetCommandHint => '例如：sudo systemctl restart nginx';

  @override
  String get snippetDescription => '描述（可选）';

  @override
  String get snippetDescriptionHint => '此命令的作用是什么？';

  @override
  String get snippetSaved => '代码片段已保存';

  @override
  String snippetDeleted(String title) {
    return '代码片段「$title」已删除';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个代码片段',
      zero: '无代码片段',
    );
    return '$_temp0';
  }

  @override
  String get runSnippet => '运行';

  @override
  String get pinToSession => '固定到此会话';

  @override
  String get unpinFromSession => '从此会话取消固定';

  @override
  String get pinnedSnippets => '已固定';

  @override
  String get allSnippets => '全部';

  @override
  String get sendToTerminal => '发送到终端';

  @override
  String get commandCopied => '命令已复制到剪贴板';

  @override
  String get tags => '标签';

  @override
  String get tagsSubtitle => '使用彩色标签整理会话和文件夹';

  @override
  String get noTags => '暂无标签';

  @override
  String get addTag => '添加标签';

  @override
  String get deleteTag => '删除标签';

  @override
  String deleteTagConfirm(String name) {
    return '删除标签「$name」？将从所有会话和文件夹中移除。';
  }

  @override
  String get tagName => '标签名称';

  @override
  String get tagNameHint => '例如：Production、Staging';

  @override
  String get tagColor => '颜色';

  @override
  String get tagCreated => '标签已创建';

  @override
  String tagDeleted(String name) {
    return '标签「$name」已删除';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个标签',
      zero: '无标签',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => '管理标签';

  @override
  String get editTags => '编辑标签';

  @override
  String get fullBackup => '完整备份';

  @override
  String get sessionsOnly => '会话';

  @override
  String get sessionKeysFromManager => '管理器中的会话密钥';

  @override
  String get allKeysFromManager => '管理器中的所有密钥';

  @override
  String exportTags(int count) {
    return '标签 ($count)';
  }

  @override
  String exportSnippets(int count) {
    return '代码片段 ($count)';
  }

  @override
  String get disableKeychain => '禁用钥匙串加密';

  @override
  String get disableKeychainSubtitle => '切换到明文存储（不推荐）';

  @override
  String get disableKeychainConfirm =>
      '数据库将在无密钥的情况下重新加密。会话和密钥将以明文形式存储在磁盘上。是否继续？';

  @override
  String get keychainDisabled => '钥匙串加密已禁用';

  @override
  String get presetFullImport => '完整导入';

  @override
  String get presetSelective => '选择性';

  @override
  String get presetCustom => '自定义';

  @override
  String get sessionSshKeys => '会话 SSH 密钥';

  @override
  String get allManagerKeys => '管理器中的所有密钥';

  @override
  String get browseFiles => '浏览文件…';

  @override
  String get sshDirSessionAlreadyImported => '已在会话中';

  @override
  String get languageSubtitle => '界面语言';

  @override
  String get themeSubtitle => '深色、浅色或跟随系统';

  @override
  String get uiScaleSubtitle => '缩放整个界面';

  @override
  String get terminalFontSizeSubtitle => '终端输出的字体大小';

  @override
  String get scrollbackLinesSubtitle => '终端历史缓冲区大小';

  @override
  String get keepAliveIntervalSubtitle => 'SSH keep-alive 数据包间隔秒数 (0 = 关闭)';

  @override
  String get sshTimeoutSubtitle => '连接超时 (秒)';

  @override
  String get defaultPortSubtitle => '新会话的默认端口';

  @override
  String get parallelWorkersSubtitle => '并行 SFTP 传输工作线程数';

  @override
  String get maxHistorySubtitle => '历史中保留的最大命令数';

  @override
  String get calculateFolderSizesSubtitle => '在侧边栏文件夹旁显示总大小';

  @override
  String get checkForUpdatesOnStartupSubtitle => '应用启动时从 GitHub 检查新版本';

  @override
  String get enableLoggingSubtitle => '将应用事件写入循环日志文件';

  @override
  String get exportWithoutPassword => '不设密码导出？';

  @override
  String get exportWithoutPasswordWarning =>
      '归档将不会被加密。任何能访问该文件的人都可以读取您的数据，包括密码和私钥。';

  @override
  String get continueWithoutPassword => '不设密码继续';

  @override
  String get threatColdDiskTheft => '冷盘窃取';

  @override
  String get threatColdDiskTheftDescription =>
      '关机后拆下硬盘并在另一台计算机上读取，或者有权访问你主目录的人复制了数据库文件。';

  @override
  String get threatKeyringFileTheft => 'keyring / keychain 文件外泄';

  @override
  String get threatKeyringFileTheftDescription =>
      '攻击者直接从磁盘读取平台的凭据存储文件（libsecret keyring、Windows Credential Manager、macOS login keychain），并从中恢复被包装的数据库密钥。硬件等级无论是否有密码都能阻止此攻击，因为芯片拒绝导出密钥材料；keychain 等级还需要密码，否则仅凭 OS 登录密码即可解包被盗文件。';

  @override
  String get modifierOnlyWithPassword => '仅在设置密码时';

  @override
  String get threatBystanderUnlockedMachine => '已解锁设备旁的旁观者';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      '你离开时，有人走向你已经解锁的计算机并打开本应用。';

  @override
  String get threatLiveRamForensicsLocked => '锁定设备上的内存取证';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      '攻击者冻结内存（或通过 DMA 捕获），即便应用处于锁定状态，也能从快照中提取仍然残留的密钥材料。';

  @override
  String get threatOsKernelOrKeychainBreach => '操作系统内核或钥匙串被攻破';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      '内核漏洞、钥匙串外泄，或硬件安全芯片中的后门。操作系统本身从可信资源变成了攻击者。';

  @override
  String get threatOfflineBruteForce => '针对弱密码的离线暴力破解';

  @override
  String get threatOfflineBruteForceDescription =>
      '持有已封装密钥或密封数据副本的攻击者，可以不受任何频率限制，按自己的节奏尝试每一个密码。';

  @override
  String get legendProtects => '已保护';

  @override
  String get legendDoesNotProtect => '未保护';

  @override
  String get legendNotApplicable => '不适用——此等级没有用户密钥';

  @override
  String get legendWeakPasswordWarning => '可接受弱密码——由另一层（硬件频率限制器或密钥封装绑定）承担安全性';

  @override
  String get legendStrongPasswordRecommended => '强烈建议使用长口令——此等级的安全性依赖于它';

  @override
  String get colT0 => 'T0 明文';

  @override
  String get colT1 => 'T1 钥匙串';

  @override
  String get colT1Password => 'T1 + 密码';

  @override
  String get colT1PasswordBiometric => 'T1 + 密码 + 生物识别';

  @override
  String get colT2 => 'T2 硬件';

  @override
  String get colT2Password => 'T2 + 密码';

  @override
  String get colT2PasswordBiometric => 'T2 + 密码 + 生物识别';

  @override
  String get colParanoid => '偏执模式';

  @override
  String get securityComparisonTableTitle => '安全等级——并排对比';

  @override
  String get securityComparisonTableThreatColumn => '威胁';

  @override
  String get compareAllTiers => '比较所有等级';

  @override
  String get resetAllDataTitle => '重置所有数据';

  @override
  String get resetAllDataSubtitle => '删除所有会话、密钥、配置和安全构件。同时清除钥匙串条目和硬件保险库插槽。';

  @override
  String get resetAllDataConfirmTitle => '重置所有数据？';

  @override
  String get resetAllDataConfirmBody =>
      '所有会话、SSH 密钥、known hosts、代码片段、标签、偏好设置以及所有安全构件（钥匙串条目、硬件保险库数据、生物识别覆盖层）都将被永久删除。此操作无法撤销。';

  @override
  String get resetAllDataConfirmAction => '全部重置';

  @override
  String get resetAllDataInProgress => '正在重置…';

  @override
  String get resetAllDataDone => '所有数据已重置';

  @override
  String get resetAllDataFailed => '重置失败';

  @override
  String get compareAllTiersSubtitle => '并排查看每个等级可抵御的威胁。';

  @override
  String get autoLockRequiresPassword => '自动锁定需要在当前等级上设置密码。';

  @override
  String get recommendedBadge => '推荐';

  @override
  String get continueWithRecommended => '使用推荐设置继续';

  @override
  String get customizeSecurity => '自定义安全设置';

  @override
  String get tierHardwareSubtitleHonest => '进阶：密钥与硬件绑定。若此设备的芯片丢失或更换，数据将无法恢复。';

  @override
  String get tierParanoidSubtitleHonest =>
      '备选：使用主密码，不信任操作系统。可防御 OS 被攻破，但运行时防护不优于 T1/T2。';

  @override
  String get mitigationsNoteRuntimeThreats =>
      '运行时 (runtime) 威胁（同用户 malware、活动进程内存转储）在所有层级均显示为 ✗。它们由独立的缓解功能处理，不受层级选择影响。';

  @override
  String get securitySetupContinue => '继续';

  @override
  String get currentTierBadge => '当前';

  @override
  String get paranoidAlternativeHeader => '备选';

  @override
  String get modifierPasswordLabel => '密码';

  @override
  String get modifierPasswordSubtitle => '解锁保险库前需要输入的密钥门槛。';

  @override
  String get modifierBiometricLabel => '生物识别快捷方式';

  @override
  String get modifierBiometricSubtitle => '从受生物识别保护的系统槽位中获取密码，无需手动输入。';

  @override
  String get biometricRequiresPassword => '请先启用密码——生物识别只是输入密码的快捷方式。';

  @override
  String get biometricRequiresActiveTier => '请先选择此等级以启用生物识别解锁';

  @override
  String get autoLockRequiresActiveTier => '请先选择此等级以配置自动锁定';

  @override
  String get biometricForbiddenParanoid => 'Paranoid 级别按设计不允许使用生物识别。';

  @override
  String get fprintdNotAvailable => '未安装 fprintd 或未登记指纹。';

  @override
  String get linuxTpmWithoutPasswordNote =>
      '没有密码的 TPM 仅提供隔离，而非身份验证。任何能运行此应用的人都可以解锁数据。';

  @override
  String get paranoidMasterPasswordNote =>
      '强烈建议使用较长的口令——Argon2id 只能减慢暴力破解，无法阻止它。';

  @override
  String get plaintextWarningTitle => '明文：无加密';

  @override
  String get plaintextWarningBody =>
      '会话、密钥和 known hosts 将以未加密方式保存。任何能访问本机文件系统的人都可以读取它们。';

  @override
  String get plaintextAcknowledge => '我了解我的数据不会被加密';

  @override
  String get plaintextAcknowledgeRequired => '在继续之前请确认您已了解。';

  @override
  String get passwordLabel => '密码';

  @override
  String get masterPasswordLabel => '主密码';
}
