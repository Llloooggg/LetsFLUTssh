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
  String get infoDialogProtectsHeader => 'Protects against';

  @override
  String get infoDialogDoesNotProtectHeader => 'Does not protect against';

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
  String get cut => 'Cut';

  @override
  String get paste => 'Paste';

  @override
  String get select => 'Select';

  @override
  String get copyModeTapToStart => 'Touch to mark selection start';

  @override
  String get copyModeExtending => 'Drag to extend selection';

  @override
  String get required => 'Required';

  @override
  String get settings => 'Settings';

  @override
  String get appSettings => 'App Settings';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get importWhatToImport => 'What to import:';

  @override
  String get exportWhatToExport => 'What to export:';

  @override
  String get enterMasterPasswordPrompt => 'Enter master password:';

  @override
  String get nextStep => 'Next';

  @override
  String get includePasswords => 'Session passwords';

  @override
  String get embeddedKeys => 'Session keys';

  @override
  String get managerKeys => 'Keys from manager';

  @override
  String get managerKeysMayBeLarge => 'Manager keys may exceed QR size limit';

  @override
  String get qrPasswordWarning =>
      'SSH keys are disabled by default for export.';

  @override
  String get sshKeysMayBeLarge => 'Keys may exceed QR size limit';

  @override
  String exportTotalSize(String size) {
    return 'Total size: $size';
  }

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
  String get noResults => 'No results';

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
  String get checkNow => 'Check now';

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
  String get updateVerifying => 'Verifying…';

  @override
  String get downloadComplete => 'Download complete';

  @override
  String get installNow => 'Install Now';

  @override
  String get openReleasePage => 'Open Release Page';

  @override
  String get couldNotOpenInstaller => 'Could not open installer';

  @override
  String get installerFailedOpenedReleasePage =>
      'Installer launch failed; opened release page in browser';

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
  String importedSessions(int count) {
    return 'Imported $count session(s)';
  }

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count associations dropped (targets missing)',
      one: '$count association dropped (target missing)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corrupt sessions skipped',
      one: '$count corrupt session skipped',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'Sessions';

  @override
  String get emptyFolders => 'Empty Folders';

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
  String nSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get selectAll => 'Select All';

  @override
  String get deselectAll => 'Deselect All';

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
  String get authOrDivider => 'OR';

  @override
  String get providePasswordOrKey => 'Provide a password or SSH key';

  @override
  String get quickConnect => 'Quick Connect';

  @override
  String get scanQrCode => 'Scan QR Code';

  @override
  String get emptyFolder => 'Empty folder';

  @override
  String get qrGenerationFailed => 'QR generation failed';

  @override
  String get scanWithCameraApp =>
      'Scan with any camera app on a device\nthat has LetsFLUTssh installed.';

  @override
  String get noPasswordsInQr => 'No passwords or keys are in this QR code';

  @override
  String get qrContainsCredentialsWarning =>
      'This QR code contains session credentials. Keep the screen private.';

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
  String get keyType => 'Key Type';

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
  String get clearHistory => 'Clear history';

  @override
  String get noTransfersYet => 'No transfers yet';

  @override
  String get duplicateTab => 'Duplicate Tab';

  @override
  String get duplicateTabShortcut => 'Duplicate Tab (Ctrl+\\)';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get closeEsc => 'Close (Esc)';

  @override
  String get closeAll => 'Close All';

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
  String sshConfigPreviewHostsFound(int count) {
    return '$count host(s) found';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'No importable hosts found in this file.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'Could not read key files for: $hosts. These hosts will be imported without credentials.';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'Export archive';

  @override
  String get exportArchiveSubtitle =>
      'Save sessions, config, and keys to encrypted .lfs file';

  @override
  String get exportQrCode => 'Export QR code';

  @override
  String get exportQrCodeSubtitle =>
      'Share selected sessions and keys via QR code';

  @override
  String get importArchive => 'Import archive';

  @override
  String get importArchiveSubtitle => 'Load data from .lfs file';

  @override
  String get importFromSshDir => 'Import from ~/.ssh';

  @override
  String get importFromSshDirSubtitle =>
      'Pick hosts from config and/or private keys from ~/.ssh';

  @override
  String get sshDirImportHostsSection => 'Hosts from config';

  @override
  String get sshDirImportKeysSection => 'Keys in ~/.ssh';

  @override
  String importSshKeysFound(int count) {
    return '$count key(s) found — pick which to import';
  }

  @override
  String get importSshKeysNoneFound => 'No private keys found in ~/.ssh.';

  @override
  String get sshKeyAlreadyImported => 'already in store';

  @override
  String get setMasterPasswordHint =>
      'Set a master password to encrypt the archive.';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get passwordStrengthWeak => 'Weak';

  @override
  String get passwordStrengthModerate => 'Moderate';

  @override
  String get passwordStrengthStrong => 'Strong';

  @override
  String get passwordStrengthVeryStrong => 'Very strong';

  @override
  String get tierPlaintextLabel => 'Plaintext';

  @override
  String get tierPlaintextSubtitle => 'No encryption — file permissions only';

  @override
  String get tierKeychainLabel => 'Keychain';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'Key lives in $keychain — auto-unlock on launch';
  }

  @override
  String get tierKeychainUnavailable =>
      'OS keychain not available on this install.';

  @override
  String get tierHardwareLabel => 'Hardware';

  @override
  String get tierParanoidLabel => 'Master password (Paranoid)';

  @override
  String get tierHardwareUnavailable =>
      'Hardware vault not available on this install.';

  @override
  String get pinLabel => 'Password';

  @override
  String get l2UnlockTitle => 'Password required';

  @override
  String get l2UnlockHint => 'Enter your short password to continue';

  @override
  String get l2WrongPassword => 'Wrong password';

  @override
  String get l3UnlockTitle => 'Enter password';

  @override
  String get l3UnlockHint => 'Password unlocks the hardware-bound vault';

  @override
  String get l3WrongPin => 'Wrong password';

  @override
  String tierCooldownHint(int seconds) {
    return 'Try again in ${seconds}s';
  }

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
  String get dataLocation => 'Data Location';

  @override
  String get dataStorageSection => 'Storage';

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
      'Too large — deselect some items or use .lfs file export.';

  @override
  String get exportAll => 'Export All';

  @override
  String get showQr => 'Show QR';

  @override
  String get sort => 'Sort';

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
  String errSftpInitFailed(String error) {
    return 'Failed to initialize SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'The system folder picker is unavailable. Try another location or check app storage permissions.';

  @override
  String get biometricUnlockPrompt => 'Unlock LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'Unlock with biometrics';

  @override
  String get biometricUnlockSubtitle =>
      'Skip typing the password — unlock with the device biometric sensor.';

  @override
  String get biometricEnableFailed => 'Could not enable biometric unlock.';

  @override
  String get biometricUnlockFailed =>
      'Biometric unlock failed. Enter your master password.';

  @override
  String get biometricUnlockCancelled => 'Biometric unlock cancelled.';

  @override
  String get biometricNotEnrolled =>
      'No biometric credentials enrolled on this device.';

  @override
  String get biometricSensorNotAvailable =>
      'This device has no biometric sensor.';

  @override
  String get biometricSystemServiceMissing =>
      'Fingerprint service (fprintd) is not installed. See README → Installation.';

  @override
  String get currentPasswordIncorrect => 'Current password is incorrect';

  @override
  String get wrongPassword => 'Wrong password';

  @override
  String get lockScreenTitle => 'LetsFLUTssh is locked';

  @override
  String get lockScreenSubtitle =>
      'Enter the master password or use biometrics to continue.';

  @override
  String get unlock => 'Unlock';

  @override
  String get autoLockTitle => 'Auto-lock after inactivity';

  @override
  String get autoLockSubtitle =>
      'Block the UI when idle for this long. The database key is wiped and the encrypted store is closed on every lock; active sessions stay connected through a per-session credential cache that clears when the session is closed.';

  @override
  String get autoLockOff => 'Off';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '$minutes minute',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'Update rejected: the downloaded files are not signed by the pinned release key. This can mean the download was tampered with in transit, or the current release genuinely is not for this installation. Do NOT install — reinstall manually from the official Releases page instead.';

  @override
  String get errReleaseManifestUnavailable =>
      'Could not reach the release manifest. Likely a network issue, or the release is still being published. Try again in a few minutes.';

  @override
  String get updateSecurityWarningTitle => 'Update verification failed';

  @override
  String get updateReinstallAction => 'Open Releases page';

  @override
  String get errLfsNotArchive => 'Selected file is not a LetsFLUTssh archive.';

  @override
  String get errLfsDecryptFailed =>
      'Wrong master password or corrupted .lfs archive';

  @override
  String get errLfsArchiveTruncated =>
      'Archive is incomplete. Re-download or re-export from the original device.';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'Archive is too large ($sizeMb MB). The limit is $limitMb MB — aborted before decryption to protect memory.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'known_hosts entry is too large ($sizeMb MB). The limit is $limitMb MB — aborted to keep the import responsive.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'Import failed — your data has been restored to the state before the import. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'Archive uses schema v$found, but this build only understands up to v$supported. Update the app to import it.';
  }

  @override
  String get progressReadingArchive => 'Reading archive…';

  @override
  String get progressDecrypting => 'Decrypting…';

  @override
  String get progressParsingArchive => 'Parsing archive…';

  @override
  String get progressImportingSessions => 'Importing sessions';

  @override
  String get progressImportingFolders => 'Importing folders';

  @override
  String get progressImportingManagerKeys => 'Importing SSH keys';

  @override
  String get progressImportingTags => 'Importing tags';

  @override
  String get progressImportingSnippets => 'Importing snippets';

  @override
  String get progressApplyingConfig => 'Applying configuration…';

  @override
  String get progressImportingKnownHosts => 'Importing known_hosts…';

  @override
  String get progressCollectingData => 'Collecting data…';

  @override
  String get progressEncrypting => 'Encrypting…';

  @override
  String get progressWritingArchive => 'Writing archive…';

  @override
  String get progressWorking => 'Working…';

  @override
  String get importFromLink => 'Import from QR link';

  @override
  String get importFromLinkSubtitle =>
      'Paste a letsflutssh:// deep link copied from another device';

  @override
  String get pasteImportLinkTitle => 'Paste import link';

  @override
  String get pasteImportLinkDescription =>
      'Paste the letsflutssh://import?d=… link (or raw payload) generated on another device. No camera needed.';

  @override
  String get pasteFromClipboard => 'Paste from clipboard';

  @override
  String get invalidImportLink =>
      'Link does not contain a valid LetsFLUTssh payload';

  @override
  String get importAction => 'Import';

  @override
  String get saveSessionToAssignTags => 'Save the session first to assign tags';

  @override
  String get noTagsAssigned => 'No tags assigned';

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
  String get protocol => 'Protocol';

  @override
  String get typeLabel => 'Type';

  @override
  String get folder => 'Folder';

  @override
  String nSubitems(int count) {
    return '$count item(s)';
  }

  @override
  String get subitems => 'Items';

  @override
  String get grantPermission => 'Grant Permission';

  @override
  String get storagePermissionLimited =>
      'Limited access — grant full storage permission for all files';

  @override
  String progressConnecting(String host, int port) {
    return 'Connecting to $host:$port';
  }

  @override
  String get progressVerifyingHostKey => 'Verifying host key';

  @override
  String progressAuthenticating(String user) {
    return 'Authenticating as $user';
  }

  @override
  String get progressOpeningShell => 'Opening shell';

  @override
  String get progressOpeningSftp => 'Opening SFTP channel';

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
  String get fileConflictTitle => 'File already exists';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" already exists in $targetDir. What would you like to do?';
  }

  @override
  String get fileConflictSkip => 'Skip';

  @override
  String get fileConflictKeepBoth => 'Keep both';

  @override
  String get fileConflictReplace => 'Replace';

  @override
  String get fileConflictApplyAll => 'Apply to all remaining';

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
  String itemCountWithSize(int count, String size) {
    return '$count items, $size';
  }

  @override
  String get maximize => 'Maximize';

  @override
  String get restore => 'Restore';

  @override
  String get duplicateDownShortcut => 'Duplicate Down (Ctrl+Shift+\\)';

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
  String get clearedAllHosts => 'Cleared all known hosts';

  @override
  String removedHost(String host) {
    return 'Removed $host';
  }

  @override
  String get tools => 'Tools';

  @override
  String get sshKeys => 'SSH Keys';

  @override
  String get sshKeysSubtitle => 'Manage SSH key pairs for authentication';

  @override
  String get noKeys => 'No SSH keys. Import or generate one.';

  @override
  String get generateKey => 'Generate Key';

  @override
  String get addKey => 'Add Key';

  @override
  String get filePickerUnavailable => 'File picker unavailable on this system';

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
  String get enterMasterPassword =>
      'Enter master password to unlock your saved credentials.';

  @override
  String get wrongMasterPassword => 'Wrong password. Please try again.';

  @override
  String get newPassword => 'New Password';

  @override
  String get currentPassword => 'Current Password';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get credentialsReset => 'All saved credentials have been deleted';

  @override
  String get migrationToast => 'Storage upgraded to the latest format';

  @override
  String get dbCorruptTitle => 'Database cannot be opened';

  @override
  String get dbCorruptBody =>
      'The data on disk cannot be opened. Try a different credential, or reset to start fresh.';

  @override
  String get dbCorruptWarning =>
      'Reset will permanently delete the encrypted database and every security-related file. No data will be recovered.';

  @override
  String get dbCorruptTryOther => 'Try different credentials';

  @override
  String get dbCorruptResetContinue => 'Reset & Setup Fresh';

  @override
  String get dbCorruptExit => 'Quit LetsFLUTssh';

  @override
  String get tierResetTitle => 'Security reset required';

  @override
  String get tierResetBody =>
      'This install carries security data from an older version of LetsFLUTssh that used a different tier model. The new model is a breaking change — there is no automatic migration path. To continue, every saved session, credential, SSH key, and known-host entry on this install must be wiped and the first-launch setup wizard run fresh.';

  @override
  String get tierResetWarning =>
      'Choosing Reset & Setup Fresh will permanently delete the encrypted database and every security-related file. If you need to recover your data, quit the app now and reinstall the previous version of LetsFLUTssh to export first.';

  @override
  String get tierResetResetContinue => 'Reset & Setup Fresh';

  @override
  String get tierResetExit => 'Quit LetsFLUTssh';

  @override
  String get derivingKey => 'Deriving encryption key...';

  @override
  String get securitySetupTitle => 'Security Setup';

  @override
  String get keychainAvailable => 'Available';

  @override
  String get changeSecurityTierConfirm =>
      'Re-encrypting the database with the new tier. This cannot be interrupted — keep the app open until it finishes.';

  @override
  String get changeSecurityTierDone => 'Security tier changed';

  @override
  String get changeSecurityTierFailed => 'Could not change security tier';

  @override
  String get firstLaunchSecurityTitle => 'Secure storage enabled';

  @override
  String get firstLaunchSecurityBody =>
      'Your data is encrypted with a key held in the OS keychain. Unlock is automatic on this device.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'Hardware-backed storage is available on this device. Upgrade in Settings → Security for TPM / Secure Enclave binding.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'Hardware-backed storage is unavailable on this device.';

  @override
  String get firstLaunchSecurityOpenSettings => 'Open Settings';

  @override
  String get wizardReducedBanner =>
      'OS keychain is not reachable on this install. Pick between no encryption (T0) and a master password (Paranoid). Install gnome-keyring, kwallet, or another libsecret provider to enable the Keychain tier.';

  @override
  String get tierBlockProtectsEmpty => 'Nothing on this tier.';

  @override
  String get tierBlockDoesNotProtectEmpty => 'Nothing left uncovered.';

  @override
  String get tierBadgeCurrent => 'Current';

  @override
  String get securitySetupEnable => 'Enable';

  @override
  String get securitySetupApply => 'Apply';

  @override
  String get hwProbeLinuxDeviceMissing =>
      'No TPM detected at /dev/tpmrm0. Enable fTPM / PTT in BIOS if the machine supports it, otherwise the hardware tier is unavailable on this device.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools is not installed. Run `sudo apt install tpm2-tools` (or your distro equivalent) to enable the hardware tier.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'Hardware-tier probe failed. Check /dev/tpmrm0 permissions / udev rules — see logs for the tpm2-tools error.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'No TPM 2.0 detected. Enable fTPM / PTT in UEFI firmware, or accept that the hardware tier is unavailable on this device — the app falls back to the software-backed credential store.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Neither the Microsoft Platform Crypto Provider nor the Software Key Storage Provider is reachable — likely a corrupted Windows crypto subsystem or a Group Policy that blocks CNG. Check Event Viewer → Applications and Services Logs.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'This Mac has no Secure Enclave (pre-2017 Intel Mac without a T1 / T2 security chip). The hardware tier is not available; use master password instead.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'No login password is set on this Mac. Secure Enclave key creation requires one — set a login password in System Settings → Touch ID & Password (or Login Password).';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave rejected the app\'s signing identity (-34018). Run the bundled `macos-resign.sh` script (download from the same release) to give this install a stable self-signed identity, then relaunch.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'No device passcode is set. Secure Enclave key creation requires one — set a passcode in Settings → Face ID & Passcode (or Touch ID & Passcode).';

  @override
  String get hwProbeIosSimulator =>
      'Running on the iOS Simulator, which has no Secure Enclave. The hardware tier is only available on physical iOS devices.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'Android 9 or newer is required for the hardware tier (StrongBox and per-key enrolment invalidation are not reliable on older versions).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'This device has no biometric hardware (fingerprint or face). Use master password instead.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'No biometric is enrolled. Add a fingerprint or face in Settings → Security & privacy → Biometrics, then re-enable the hardware tier.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'Biometric hardware is temporarily unusable (lockout after failed attempts, or pending security update). Retry in a few minutes.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'The Android Keystore refused to back a hardware key on this device build (StrongBox unavailable, custom ROM stripping, or driver glitch). The hardware tier is not available.';

  @override
  String get securityRecheck => 'Re-check tier support';

  @override
  String get securityRecheckUpdated => 'Tier support updated — see cards above';

  @override
  String get securityRecheckUnchanged => 'Tier support unchanged';

  @override
  String get securityMacosEnableSecureTiers =>
      'Unlock secure tiers on this Mac';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'Re-sign the app with a personal certificate so Keychain (T1) and Secure Enclave (T2) work across updates';

  @override
  String get securityMacosEnableSecureTiersPrompt =>
      'macOS will ask for your password once';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'Secure tiers unlocked — T1 and T2 are now available';

  @override
  String get securityMacosEnableSecureTiersFailed =>
      'Failed to unlock secure tiers';

  @override
  String get securityMacosOfferTitle => 'Enable Keychain + Secure Enclave?';

  @override
  String get securityMacosOfferBody =>
      'macOS binds encrypted storage to the app\'s signing identity. Without a stable cert, Keychain (T1) and Secure Enclave (T2) reject access. We can create a personal self-signed certificate on this Mac and re-sign the app with it — updates will keep working, and your secrets survive across releases. macOS will ask for your login password once to trust the new cert.';

  @override
  String get securityMacosOfferAccept => 'Enable';

  @override
  String get securityMacosOfferDecline => 'Skip — pick T0 or Paranoid';

  @override
  String get securityMacosRemoveIdentity => 'Remove secure identity';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      'Deletes the personal signing cert. T1 / T2 data is tied to it — pick T0 or Paranoid first, then remove.';

  @override
  String get securityMacosRemoveIdentityConfirmTitle =>
      'Remove signing identity?';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'This deletes the personal cert from your login keychain. T1 / T2 stored secrets become unreadable afterwards. The wizard will open so you can migrate to T0 (plaintext) or Paranoid (master password) before removal.';

  @override
  String get securityMacosRemoveIdentitySuccess => 'Signing identity removed';

  @override
  String get securityMacosRemoveIdentityFailed =>
      'Failed to remove signing identity';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus is up but no secret-service daemon is running. Install gnome-keyring (`sudo apt install gnome-keyring`) or KWalletManager and ensure it starts at login.';

  @override
  String get keyringProbeFailed =>
      'The OS keychain is unreachable on this device. See logs for the specific platform error; the app falls back to master password.';

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
  String get pinToSession => 'Pin to this session';

  @override
  String get unpinFromSession => 'Unpin from this session';

  @override
  String get pinnedSnippets => 'Pinned';

  @override
  String get allSnippets => 'All';

  @override
  String get commandCopied => 'Command copied to clipboard';

  @override
  String get snippetFillTitle => 'Fill in snippet parameters';

  @override
  String get snippetFillSubmit => 'Run';

  @override
  String get snippetPreview => 'Preview';

  @override
  String get broadcastSetDriver => 'Broadcast from this pane';

  @override
  String get broadcastClearDriver => 'Stop broadcasting from this pane';

  @override
  String get broadcastAddReceiver => 'Receive broadcast here';

  @override
  String get broadcastRemoveReceiver => 'Stop receiving broadcast';

  @override
  String get broadcastClearAll => 'Stop all broadcasting';

  @override
  String get broadcastPasteTitle => 'Send paste to all panes?';

  @override
  String broadcastPasteBody(int chars, int count) {
    return '$chars characters will be sent to $count other panes.';
  }

  @override
  String get broadcastPasteSend => 'Send';

  @override
  String get portForwarding => 'Forwarding';

  @override
  String get portForwardingEmpty => 'No forward rules yet';

  @override
  String get addForwardRule => 'Add rule';

  @override
  String get editForwardRule => 'Edit rule';

  @override
  String get deleteForwardRule => 'Delete rule';

  @override
  String get localForward => 'Local (-L)';

  @override
  String get remoteForward => 'Remote (-R)';

  @override
  String get dynamicForward => 'Dynamic (-D)';

  @override
  String get forwardKind => 'Kind';

  @override
  String get bindAddress => 'Bind address';

  @override
  String get bindPort => 'Bind port';

  @override
  String get targetHost => 'Target host';

  @override
  String get targetPort => 'Target port';

  @override
  String get forwardDescription => 'Description (optional)';

  @override
  String get forwardEnabled => 'Enabled';

  @override
  String get forwardBindWildcardWarning =>
      'Binding to 0.0.0.0 publishes the forward to every interface — usually you want 127.0.0.1.';

  @override
  String get forwardOnlyLocalSupported =>
      'Local (-L), remote (-R), and dynamic SOCKS5 (-D) forwards are all active.';

  @override
  String get proxyJump => 'Connect via';

  @override
  String get proxyJumpNone => 'Direct connection';

  @override
  String get proxyJumpSavedSession => 'Saved session';

  @override
  String get proxyJumpCustom => 'Custom (user@host:port)';

  @override
  String get proxyJumpCustomNote =>
      'Override hops use this session\'s credentials. For different bastion auth, save the bastion as its own session.';

  @override
  String get errProxyJumpCycle => 'Proxy chain loops back on itself.';

  @override
  String errProxyJumpDepth(int max) {
    return 'Proxy chain is too deep (max $max hops).';
  }

  @override
  String errProxyJumpBastionFailed(String label) {
    return 'Bastion $label failed to connect.';
  }

  @override
  String get recordSession => 'Record session';

  @override
  String get recordSessionHelp =>
      'Save terminal output to disk for this session. Encrypted at rest when a master password / hardware key is enabled.';

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
  String get fullBackup => 'Full backup';

  @override
  String get sessionsOnly => 'Sessions';

  @override
  String get presetFullImport => 'Full import';

  @override
  String get presetSelective => 'Selective';

  @override
  String get presetCustom => 'Custom';

  @override
  String get sessionSshKeys => 'Session keys (manager)';

  @override
  String get allManagerKeys => 'All manager keys';

  @override
  String get browseFiles => 'Browse files…';

  @override
  String get sshDirSessionAlreadyImported => 'already in sessions';

  @override
  String get languageSubtitle => 'Interface language';

  @override
  String get themeSubtitle => 'Dark, light, or follow the system';

  @override
  String get uiScaleSubtitle => 'Scale the whole interface';

  @override
  String get terminalFontSizeSubtitle => 'Font size in terminal output';

  @override
  String get scrollbackLinesSubtitle => 'Terminal history buffer size';

  @override
  String get keepAliveIntervalSubtitle =>
      'Seconds between SSH keep-alive packets (0 = off)';

  @override
  String get sshTimeoutSubtitle => 'Connection timeout in seconds';

  @override
  String get defaultPortSubtitle => 'Default port for new sessions';

  @override
  String get parallelWorkersSubtitle => 'Concurrent SFTP transfer workers';

  @override
  String get maxHistorySubtitle => 'Maximum saved commands in history';

  @override
  String get calculateFolderSizesSubtitle =>
      'Show total size next to folders in the sidebar';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Query GitHub for a new release when the app launches';

  @override
  String get enableLoggingSubtitle => 'Write app events to a rotating log file';

  @override
  String get exportWithoutPassword => 'Export Without Password?';

  @override
  String get exportWithoutPasswordWarning =>
      'The archive will not be encrypted. Anyone with access to the file can read your data, including passwords and private keys.';

  @override
  String get continueWithoutPassword => 'Continue Without Password';

  @override
  String get threatColdDiskTheft => 'Cold-disk theft';

  @override
  String get threatColdDiskTheftDescription =>
      'Powered-off machine with the drive removed and read on another computer, or a copy of the database file taken by someone with access to your home directory.';

  @override
  String get threatKeyringFileTheft => 'Keyring / keychain file exfiltration';

  @override
  String get threatKeyringFileTheftDescription =>
      'Attacker reads the platform\'s credential-store file directly off the disk (libsecret keyring, Windows Credential Manager, macOS login keychain) and recovers the wrapped database key from it. The hardware tier defeats this regardless of password because the chip refuses to export key material; the keychain tier needs a password on top so the stolen file cannot be unwrapped by the OS login password alone.';

  @override
  String get modifierOnlyWithPassword => 'only with password';

  @override
  String get threatBystanderUnlockedMachine =>
      'Bystander on an unlocked machine';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'Someone walks up to your already-unlocked computer and opens the app while you are away.';

  @override
  String get threatLiveRamForensicsLocked =>
      'RAM forensics on a locked machine';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'An attacker freezes RAM (or captures it via DMA) and pulls still-resident key material out of the snapshot, even while the app is locked.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'OS kernel or keychain compromise';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'Kernel vulnerability, keychain exfiltration, or a backdoor in the hardware security chip. The operating system becomes the attacker rather than a trusted resource.';

  @override
  String get threatOfflineBruteForce => 'Offline brute force on weak password';

  @override
  String get threatOfflineBruteForceDescription =>
      'An attacker who has a copy of the wrapped key or sealed blob tries every password at their own pace without any rate limiter.';

  @override
  String get legendProtects => 'Protected';

  @override
  String get legendDoesNotProtect => 'Not protected';

  @override
  String get colT0 => 'T0 Plaintext';

  @override
  String get colT1 => 'T1 Keychain';

  @override
  String get colT1Password => 'T1 + password';

  @override
  String get colT1PasswordBiometric => 'T1 + password + biometric';

  @override
  String get colT2 => 'T2 Hardware';

  @override
  String get colT2Password => 'T2 + password';

  @override
  String get colT2PasswordBiometric => 'T2 + password + biometric';

  @override
  String get colParanoid => 'Paranoid';

  @override
  String get securityComparisonTableThreatColumn => 'Threat';

  @override
  String get compareAllTiers => 'Compare all tiers';

  @override
  String get resetAllDataTitle => 'Reset all data';

  @override
  String get resetAllDataSubtitle =>
      'Delete every session, key, config and security artefact. Clears keychain entries and hardware-vault slots too.';

  @override
  String get resetAllDataConfirmTitle => 'Reset all data?';

  @override
  String get resetAllDataConfirmBody =>
      'All sessions, SSH keys, known hosts, snippets, tags, preferences, and every security artefact (keychain entries, hardware-vault blobs, biometric overlay) will be permanently deleted. This cannot be undone.';

  @override
  String get resetAllDataConfirmAction => 'Reset everything';

  @override
  String get resetAllDataInProgress => 'Resetting…';

  @override
  String get resetAllDataDone => 'All data reset';

  @override
  String get resetAllDataFailed => 'Reset failed';

  @override
  String get autoLockRequiresPassword =>
      'Auto-lock requires a password on the active tier.';

  @override
  String get recommendedBadge => 'RECOMMENDED';

  @override
  String get tierHardwareSubtitleHonest =>
      'Advanced: hardware-bound key. Data is irrecoverable if this device\'s chip is lost or replaced.';

  @override
  String get tierParanoidSubtitleHonest =>
      'Alternative: master password, no OS trust. Protects against OS compromise. Does not improve runtime protection over T1/T2.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'Runtime threats (same-user malware, live process memory dump) are shown as ✗ across every tier. They are addressed by separate mitigation features applied regardless of tier choice.';

  @override
  String get currentTierBadge => 'CURRENT';

  @override
  String get paranoidAlternativeHeader => 'ALTERNATIVE';

  @override
  String get modifierPasswordLabel => 'Password';

  @override
  String get modifierPasswordSubtitle =>
      'Typed secret gate before the vault unlocks.';

  @override
  String get modifierBiometricLabel => 'Biometric shortcut';

  @override
  String get modifierBiometricSubtitle =>
      'Release the password from a biometric-gated OS slot instead of typing it.';

  @override
  String get biometricRequiresPassword =>
      'Enable a password first — biometric is a shortcut for entering it.';

  @override
  String get biometricRequiresActiveTier =>
      'Select this tier first to enable biometric unlock';

  @override
  String get autoLockRequiresActiveTier =>
      'Select this tier first to configure auto-lock';

  @override
  String get biometricForbiddenParanoid =>
      'Paranoid does not allow biometric by design.';

  @override
  String get fprintdNotAvailable =>
      'fprintd not installed or no enrolled finger.';

  @override
  String get linuxTpmWithoutPasswordNote =>
      'TPM without a password provides isolation, not authentication. Anyone who can run this app can unlock the data.';

  @override
  String get paranoidMasterPasswordNote =>
      'A long passphrase is strongly recommended — Argon2id only slows brute force, it does not block it.';

  @override
  String get plaintextWarningTitle => 'Plaintext: no encryption';

  @override
  String get plaintextWarningBody =>
      'Sessions, keys, and known hosts will be stored without encryption. Anyone with access to this computer\'s filesystem can read them.';

  @override
  String get plaintextAcknowledge =>
      'I understand my data will not be encrypted';

  @override
  String get plaintextAcknowledgeRequired =>
      'Confirm you understand before continuing.';

  @override
  String get passwordLabel => 'Password';

  @override
  String get masterPasswordLabel => 'Master password';
}
