// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SEn extends S {
  SEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get connect => 'Connect';

  @override
  String get retry => 'Retry';

  @override
  String get import_ => 'Import';

  @override
  String get export_ => 'Export';

  @override
  String get rename => 'Rename';

  @override
  String get create => 'Create';

  @override
  String get back => 'Back';

  @override
  String get copy => 'Copy';

  @override
  String get paste => 'Paste';

  @override
  String get select => 'Select';

  @override
  String get required => 'Required';

  @override
  String get settings => 'Settings';

  @override
  String get terminal => 'Terminal';

  @override
  String get files => 'Files';

  @override
  String get transfer => 'Transfer';

  @override
  String get open => 'Open';

  @override
  String get search => 'Search...';

  @override
  String get filter => 'Filter...';

  @override
  String get merge => 'Merge';

  @override
  String get replace => 'Replace';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get updateAvailable => 'Update Available';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'Version $version is available (current: v$current).';
  }

  @override
  String get releaseNotes => 'Release notes:';

  @override
  String get skipThisVersion => 'Skip This Version';

  @override
  String get unskip => 'Unskip';

  @override
  String get downloadAndInstall => 'Download & Install';

  @override
  String get openInBrowser => 'Open in Browser';

  @override
  String get couldNotOpenBrowser =>
      'Could not open browser — URL copied to clipboard';

  @override
  String get checkForUpdates => 'Check for Updates';

  @override
  String get checkForUpdatesOnStartup => 'Check for Updates on Startup';

  @override
  String get checking => 'Checking...';

  @override
  String get youreUpToDate => 'You\'re up to date';

  @override
  String get updateCheckFailed => 'Update check failed';

  @override
  String get unknownError => 'Unknown error';

  @override
  String downloadingPercent(int percent) {
    return 'Downloading... $percent%';
  }

  @override
  String get downloadComplete => 'Download complete';

  @override
  String get installNow => 'Install Now';

  @override
  String get couldNotOpenInstaller => 'Could not open installer';

  @override
  String versionAvailable(String version) {
    return 'Version $version available';
  }

  @override
  String currentVersion(String version) {
    return 'Current: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'SSH key received: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return 'Imported $count session(s) via QR';
  }

  @override
  String importedSessions(int count) {
    return 'Imported $count session(s)';
  }

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get sessions => 'Sessions';

  @override
  String get sessionsHeader => 'SESSIONS';

  @override
  String get savedSessions => 'Saved sessions';

  @override
  String get activeConnections => 'Active connections';

  @override
  String get openTabs => 'Open tabs';

  @override
  String get noSavedSessions => 'No saved sessions';

  @override
  String get addSession => 'Add Session';

  @override
  String get noSessions => 'No sessions';

  @override
  String get noSessionsToExport => 'No sessions to export';

  @override
  String nSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get selectAll => 'Select All';

  @override
  String get moveTo => 'Move to...';

  @override
  String get moveToFolder => 'Move to Folder';

  @override
  String get rootFolder => '/ (root)';

  @override
  String get newFolder => 'New Folder';

  @override
  String get newConnection => 'New Connection';

  @override
  String get editConnection => 'Edit Connection';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get deleteSession => 'Delete Session';

  @override
  String get renameFolder => 'Rename Folder';

  @override
  String get deleteFolder => 'Delete Folder';

  @override
  String get deleteSelected => 'Delete Selected';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return 'Delete $parts?\n\nThis cannot be undone.';
  }

  @override
  String nSessions(int count) {
    return '$count session(s)';
  }

  @override
  String nFolders(int count) {
    return '$count folder(s)';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'Delete folder \"$name\"?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'This will also delete $count session(s) inside.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get connection => 'Connection';

  @override
  String get auth => 'Auth';

  @override
  String get options => 'Options';

  @override
  String get sessionName => 'Session Name';

  @override
  String get hintMyServer => 'My Server';

  @override
  String get hostRequired => 'Host *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'Port';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'Username *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'Password';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'Key Passphrase';

  @override
  String get hintOptional => 'Optional';

  @override
  String get hidePemText => 'Hide PEM text';

  @override
  String get pastePemKeyText => 'Paste PEM key text';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'No additional options yet';

  @override
  String get saveAndConnect => 'Save & Connect';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst => 'Provide a key file or PEM text first';

  @override
  String get keyTextPem => 'Key Text (PEM)';

  @override
  String get selectKeyFile => 'Select Key File';

  @override
  String get clearKeyFile => 'Clear key file';

  @override
  String get quickConnect => 'Quick Connect';

  @override
  String get scanQrCode => 'Scan QR Code';

  @override
  String get qrGenerationFailed => 'QR generation failed';

  @override
  String get scanWithCameraApp =>
      'Scan with any camera app on a device\nthat has LetsFLUTssh installed.';

  @override
  String get noPasswordsInQr => 'No passwords or keys are in this QR code';

  @override
  String get copyLink => 'Copy Link';

  @override
  String get linkCopied => 'Link copied to clipboard';

  @override
  String get hostKeyChanged => 'Host Key Changed!';

  @override
  String get unknownHost => 'Unknown Host';

  @override
  String get hostKeyChangedWarning =>
      'WARNING: The host key for this server has changed. This could indicate a man-in-the-middle attack, or the server may have been reinstalled.';

  @override
  String get unknownHostMessage =>
      'The authenticity of this host cannot be established. Are you sure you want to continue connecting?';

  @override
  String get host => 'Host';

  @override
  String get keyType => 'Key type';

  @override
  String get fingerprint => 'Fingerprint';

  @override
  String get fingerprintCopied => 'Fingerprint copied';

  @override
  String get copyFingerprint => 'Copy fingerprint';

  @override
  String get acceptAnyway => 'Accept Anyway';

  @override
  String get accept => 'Accept';

  @override
  String get importData => 'Import Data';

  @override
  String get masterPassword => 'Master Password';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get importModeMergeDescription => 'Add new sessions, keep existing';

  @override
  String get importModeReplaceDescription =>
      'Replace all sessions with imported';

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get folderName => 'Folder name';

  @override
  String get newName => 'New name';

  @override
  String deleteItems(String names) {
    return 'Delete $names?';
  }

  @override
  String deleteNItems(int count) {
    return 'Delete $count items';
  }

  @override
  String deletedItem(String name) {
    return 'Deleted $name';
  }

  @override
  String deletedNItems(int count) {
    return 'Deleted $count items';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'Failed to create folder: $error';
  }

  @override
  String failedToRename(String error) {
    return 'Failed to rename: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return 'Failed to delete $name: $error';
  }

  @override
  String get editPath => 'Edit Path';

  @override
  String get root => 'Root';

  @override
  String get controllersNotInitialized => 'Controllers not initialized';

  @override
  String get initializingSftp => 'Initializing SFTP...';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get noTransfersYet => 'No transfers yet';

  @override
  String get copyRight => 'Copy Right';

  @override
  String get copyDown => 'Copy Down';

  @override
  String get closePane => 'Close Pane';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get closeEsc => 'Close (Esc)';

  @override
  String get copyRightShortcut => 'Copy Right (Ctrl+\\)';

  @override
  String get copyDownShortcut => 'Copy Down (Ctrl+Shift+\\)';

  @override
  String get closeOthers => 'Close Others';

  @override
  String get closeTabsToTheLeft => 'Close Tabs to the Left';

  @override
  String get closeTabsToTheRight => 'Close Tabs to the Right';

  @override
  String get noActiveSession => 'No active session';

  @override
  String get createConnectionHint =>
      'Create a new connection or select one from the sidebar';

  @override
  String get hideSidebar => 'Hide Sidebar (Ctrl+B)';

  @override
  String get showSidebar => 'Show Sidebar (Ctrl+B)';

  @override
  String get language => 'Language';

  @override
  String get languageSystemDefault => 'Auto';

  @override
  String get theme => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'System';

  @override
  String get appearance => 'Appearance';

  @override
  String get connectionSection => 'Connection';

  @override
  String get transfers => 'Transfers';

  @override
  String get data => 'Data';

  @override
  String get logging => 'Logging';

  @override
  String get updates => 'Updates';

  @override
  String get about => 'About';

  @override
  String get resetToDefaults => 'Reset to Defaults';

  @override
  String get uiScale => 'UI Scale';

  @override
  String get terminalFontSize => 'Terminal Font Size';

  @override
  String get scrollbackLines => 'Scrollback Lines';

  @override
  String get keepAliveInterval => 'Keep-Alive Interval (sec)';

  @override
  String get sshTimeout => 'SSH Timeout (sec)';

  @override
  String get defaultPort => 'Default Port';

  @override
  String get parallelWorkers => 'Parallel Workers';

  @override
  String get maxHistory => 'Max History';

  @override
  String get calculateFolderSizes => 'Calculate Folder Sizes';

  @override
  String get exportData => 'Export Data';

  @override
  String get exportDataSubtitle =>
      'Save sessions, config, and keys to encrypted .lfs file';

  @override
  String get importDataSubtitle => 'Load data from .lfs file';

  @override
  String get setMasterPasswordHint =>
      'Set a master password to encrypt the archive.';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String exportedTo(String path) {
    return 'Exported to: $path';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get pathToLfsFile => 'Path to .lfs file';

  @override
  String get hintLfsPath => '/path/to/export.lfs';

  @override
  String get shareViaQrCode => 'Share via QR Code';

  @override
  String get shareViaQrSubtitle =>
      'Export sessions to QR for scanning by another device';

  @override
  String get dataLocation => 'Data Location';

  @override
  String get pathCopied => 'Path copied to clipboard';

  @override
  String get urlCopied => 'URL copied to clipboard';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — SSH/SFTP client';
  }

  @override
  String get sourceCode => 'Source Code';

  @override
  String get enableLogging => 'Enable Logging';

  @override
  String get logIsEmpty => 'Log is empty';

  @override
  String logExportedTo(String path) {
    return 'Log exported to: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Log export failed: $error';
  }

  @override
  String get logsCleared => 'Logs cleared';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get copyLog => 'Copy log';

  @override
  String get exportLog => 'Export log';

  @override
  String get clearLogs => 'Clear logs';

  @override
  String get local => 'Local';

  @override
  String get remote => 'Remote';

  @override
  String get pickFolder => 'Pick Folder';

  @override
  String get refresh => 'Refresh';

  @override
  String get up => 'Up';

  @override
  String get emptyDirectory => 'Empty directory';

  @override
  String get cancelSelection => 'Cancel selection';

  @override
  String get openSftpBrowser => 'Open SFTP Browser';

  @override
  String get openSshTerminal => 'Open SSH Terminal';

  @override
  String get noActiveFileBrowsers => 'No active file browsers';

  @override
  String get useSftpFromSessions => 'Use \"SFTP\" from Sessions';

  @override
  String get anotherInstanceRunning =>
      'Another instance of LetsFLUTssh is already running.';

  @override
  String importFailedShort(String error) {
    return 'Import failed: $error';
  }

  @override
  String get saveLogAs => 'Save log as';

  @override
  String get chooseSaveLocation => 'Choose save location';

  @override
  String get forward => 'Forward';

  @override
  String get name => 'Name';

  @override
  String get size => 'Size';

  @override
  String get modified => 'Modified';

  @override
  String get mode => 'Mode';

  @override
  String get owner => 'Owner';

  @override
  String get connectionError => 'Connection error';

  @override
  String get resizeWindowToViewFiles => 'Resize window to view files';

  @override
  String get completed => 'Completed';

  @override
  String get connected => 'Connected';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get exit => 'Exit';

  @override
  String get exitConfirmation => 'Active sessions will be disconnected. Exit?';

  @override
  String get hintFolderExample => 'e.g. Production';

  @override
  String get credentialsNotSet => 'Credentials not set';

  @override
  String get exportSessionsViaQr => 'Export Sessions via QR';

  @override
  String get qrNoCredentialsWarning =>
      'Passwords and SSH keys are NOT included.\nImported sessions will need credentials filled in.';

  @override
  String get qrTooManyForSingleCode =>
      'Too many sessions for a single QR code. Deselect some or use .lfs export.';

  @override
  String get qrTooLarge =>
      'Too large — deselect some sessions or use .lfs file export.';

  @override
  String get exportAll => 'Export All';

  @override
  String get showQr => 'Show QR';

  @override
  String get resizePanelDivider => 'Resize panel divider';

  @override
  String get youreRunningLatest => 'You\'re running the latest version';

  @override
  String get liveLog => 'Live Log';

  @override
  String transferNItems(int count) {
    return 'Transfer $count items';
  }

  @override
  String get time => 'Time';

  @override
  String get failed => 'Failed';

  @override
  String get errOperationNotPermitted => 'Operation not permitted';

  @override
  String get errNoSuchFileOrDirectory => 'No such file or directory';

  @override
  String get errNoSuchProcess => 'No such process';

  @override
  String get errIoError => 'I/O error';

  @override
  String get errBadFileDescriptor => 'Bad file descriptor';

  @override
  String get errResourceTemporarilyUnavailable =>
      'Resource temporarily unavailable';

  @override
  String get errOutOfMemory => 'Out of memory';

  @override
  String get errPermissionDenied => 'Permission denied';

  @override
  String get errFileExists => 'File exists';

  @override
  String get errNotADirectory => 'Not a directory';

  @override
  String get errIsADirectory => 'Is a directory';

  @override
  String get errInvalidArgument => 'Invalid argument';

  @override
  String get errTooManyOpenFiles => 'Too many open files';

  @override
  String get errNoSpaceLeftOnDevice => 'No space left on device';

  @override
  String get errReadOnlyFileSystem => 'Read-only file system';

  @override
  String get errBrokenPipe => 'Broken pipe';

  @override
  String get errFileNameTooLong => 'File name too long';

  @override
  String get errDirectoryNotEmpty => 'Directory not empty';

  @override
  String get errAddressAlreadyInUse => 'Address already in use';

  @override
  String get errCannotAssignAddress => 'Cannot assign requested address';

  @override
  String get errNetworkIsDown => 'Network is down';

  @override
  String get errNetworkIsUnreachable => 'Network is unreachable';

  @override
  String get errConnectionResetByPeer => 'Connection reset by peer';

  @override
  String get errConnectionTimedOut => 'Connection timed out';

  @override
  String get errConnectionRefused => 'Connection refused';

  @override
  String get errHostIsDown => 'Host is down';

  @override
  String get errNoRouteToHost => 'No route to host';

  @override
  String get errConnectionAborted => 'Connection aborted';

  @override
  String get errAlreadyConnected => 'Already connected';

  @override
  String get errNotConnected => 'Not connected';

  @override
  String errSshConnectFailed(String host, int port) {
    return 'Failed to connect to $host:$port';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return 'Authentication failed for $user@$host';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return 'Connection failed to $host:$port';
  }

  @override
  String get errSshAuthAborted => 'Authentication aborted';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return 'Host key rejected for $host:$port — accept the host key or check known_hosts';
  }

  @override
  String get errSshOpenShellFailed => 'Failed to open shell';

  @override
  String get errSshLoadKeyFileFailed => 'Failed to load SSH key file';

  @override
  String get errSshParseKeyFailed => 'Failed to parse PEM key data';

  @override
  String get errSshConnectionDisposed => 'Connection disposed';

  @override
  String get errSshNotConnected => 'Not connected';

  @override
  String get errConnectionFailed => 'Connection failed';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'Connection timed out after $seconds seconds';
  }

  @override
  String get errSessionClosed => 'Session closed';

  @override
  String errShellError(String error) {
    return 'Shell error: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'Reconnect failed: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'Failed to initialize SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get errDecryptionFailed =>
      'Failed to decrypt credentials. Key file may be corrupted.';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get storagePermissionRequired =>
      'Storage permission required to browse local files';

  @override
  String get grantPermission => 'Grant Permission';

  @override
  String get storagePermissionLimited =>
      'Limited access — grant full storage permission for all files';
}
