import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S of(BuildContext context) {
    return Localizations.of<S>(context, S)!;
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'LetsFLUTssh'**
  String get appTitle;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @import_.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import_;

  /// No description provided for @export_.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export_;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @terminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get terminal;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transfer;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter...'**
  String get filter;

  /// No description provided for @merge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get merge;

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get updateAvailable;

  /// No description provided for @updateVersionAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available (current: v{current}).'**
  String updateVersionAvailable(String version, String current);

  /// No description provided for @releaseNotes.
  ///
  /// In en, this message translates to:
  /// **'Release notes:'**
  String get releaseNotes;

  /// No description provided for @skipThisVersion.
  ///
  /// In en, this message translates to:
  /// **'Skip This Version'**
  String get skipThisVersion;

  /// No description provided for @unskip.
  ///
  /// In en, this message translates to:
  /// **'Unskip'**
  String get unskip;

  /// No description provided for @downloadAndInstall.
  ///
  /// In en, this message translates to:
  /// **'Download & Install'**
  String get downloadAndInstall;

  /// No description provided for @openInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in Browser'**
  String get openInBrowser;

  /// No description provided for @couldNotOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Could not open browser — URL copied to clipboard'**
  String get couldNotOpenBrowser;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get checkForUpdates;

  /// No description provided for @checkForUpdatesOnStartup.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates on Startup'**
  String get checkForUpdatesOnStartup;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get checking;

  /// No description provided for @youreUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You\'re up to date'**
  String get youreUpToDate;

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Update check failed'**
  String get updateCheckFailed;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @downloadingPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading... {percent}%'**
  String downloadingPercent(int percent);

  /// No description provided for @downloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Download complete'**
  String get downloadComplete;

  /// No description provided for @installNow.
  ///
  /// In en, this message translates to:
  /// **'Install Now'**
  String get installNow;

  /// No description provided for @couldNotOpenInstaller.
  ///
  /// In en, this message translates to:
  /// **'Could not open installer'**
  String get couldNotOpenInstaller;

  /// No description provided for @versionAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} available'**
  String versionAvailable(String version);

  /// No description provided for @currentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current: v{version}'**
  String currentVersion(String version);

  /// No description provided for @sshKeyReceived.
  ///
  /// In en, this message translates to:
  /// **'SSH key received: {filename}'**
  String sshKeyReceived(String filename);

  /// No description provided for @importedSessionsViaQr.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} session(s) via QR'**
  String importedSessionsViaQr(int count);

  /// No description provided for @importedSessions.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} session(s)'**
  String importedSessions(int count);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @sessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessions;

  /// No description provided for @sessionsHeader.
  ///
  /// In en, this message translates to:
  /// **'SESSIONS'**
  String get sessionsHeader;

  /// No description provided for @savedSessions.
  ///
  /// In en, this message translates to:
  /// **'Saved sessions'**
  String get savedSessions;

  /// No description provided for @activeConnections.
  ///
  /// In en, this message translates to:
  /// **'Active connections'**
  String get activeConnections;

  /// No description provided for @openTabs.
  ///
  /// In en, this message translates to:
  /// **'Open tabs'**
  String get openTabs;

  /// No description provided for @noSavedSessions.
  ///
  /// In en, this message translates to:
  /// **'No saved sessions'**
  String get noSavedSessions;

  /// No description provided for @addSession.
  ///
  /// In en, this message translates to:
  /// **'Add Session'**
  String get addSession;

  /// No description provided for @noSessions.
  ///
  /// In en, this message translates to:
  /// **'No sessions'**
  String get noSessions;

  /// No description provided for @noSessionsToExport.
  ///
  /// In en, this message translates to:
  /// **'No sessions to export'**
  String get noSessionsToExport;

  /// No description provided for @nSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String nSelectedCount(int count);

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @moveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to...'**
  String get moveTo;

  /// No description provided for @moveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to Folder'**
  String get moveToFolder;

  /// No description provided for @rootFolder.
  ///
  /// In en, this message translates to:
  /// **'/ (root)'**
  String get rootFolder;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @newConnection.
  ///
  /// In en, this message translates to:
  /// **'New Connection'**
  String get newConnection;

  /// No description provided for @editConnection.
  ///
  /// In en, this message translates to:
  /// **'Edit Connection'**
  String get editConnection;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @deleteSession.
  ///
  /// In en, this message translates to:
  /// **'Delete Session'**
  String get deleteSession;

  /// No description provided for @renameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename Folder'**
  String get renameFolder;

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete Folder'**
  String get deleteFolder;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete Selected'**
  String get deleteSelected;

  /// No description provided for @deleteNSessionsAndFolders.
  ///
  /// In en, this message translates to:
  /// **'Delete {parts}?\n\nThis cannot be undone.'**
  String deleteNSessionsAndFolders(String parts);

  /// No description provided for @nSessions.
  ///
  /// In en, this message translates to:
  /// **'{count} session(s)'**
  String nSessions(int count);

  /// No description provided for @nFolders.
  ///
  /// In en, this message translates to:
  /// **'{count} folder(s)'**
  String nFolders(int count);

  /// No description provided for @deleteFolderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete folder \"{name}\"?'**
  String deleteFolderConfirm(String name);

  /// No description provided for @willDeleteSessionsInside.
  ///
  /// In en, this message translates to:
  /// **'This will also delete {count} session(s) inside.'**
  String willDeleteSessionsInside(int count);

  /// No description provided for @deleteSessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteSessionConfirm(String name);

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @auth.
  ///
  /// In en, this message translates to:
  /// **'Auth'**
  String get auth;

  /// No description provided for @options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// No description provided for @sessionName.
  ///
  /// In en, this message translates to:
  /// **'Session Name'**
  String get sessionName;

  /// No description provided for @hintMyServer.
  ///
  /// In en, this message translates to:
  /// **'My Server'**
  String get hintMyServer;

  /// No description provided for @hostRequired.
  ///
  /// In en, this message translates to:
  /// **'Host *'**
  String get hostRequired;

  /// No description provided for @hintHost.
  ///
  /// In en, this message translates to:
  /// **'192.168.1.1'**
  String get hintHost;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @hintPort.
  ///
  /// In en, this message translates to:
  /// **'22'**
  String get hintPort;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Username *'**
  String get usernameRequired;

  /// No description provided for @hintUsername.
  ///
  /// In en, this message translates to:
  /// **'root'**
  String get hintUsername;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @hintPassword.
  ///
  /// In en, this message translates to:
  /// **'••••••••'**
  String get hintPassword;

  /// No description provided for @keyPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Key Passphrase'**
  String get keyPassphrase;

  /// No description provided for @hintOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get hintOptional;

  /// No description provided for @hidePemText.
  ///
  /// In en, this message translates to:
  /// **'Hide PEM text'**
  String get hidePemText;

  /// No description provided for @pastePemKeyText.
  ///
  /// In en, this message translates to:
  /// **'Paste PEM key text'**
  String get pastePemKeyText;

  /// No description provided for @hintPemKey.
  ///
  /// In en, this message translates to:
  /// **'-----BEGIN OPENSSH PRIVATE KEY-----'**
  String get hintPemKey;

  /// No description provided for @noAdditionalOptionsYet.
  ///
  /// In en, this message translates to:
  /// **'No additional options yet'**
  String get noAdditionalOptionsYet;

  /// No description provided for @saveAndConnect.
  ///
  /// In en, this message translates to:
  /// **'Save & Connect'**
  String get saveAndConnect;

  /// No description provided for @portRange.
  ///
  /// In en, this message translates to:
  /// **'1-65535'**
  String get portRange;

  /// No description provided for @provideKeyFirst.
  ///
  /// In en, this message translates to:
  /// **'Provide a key file or PEM text first'**
  String get provideKeyFirst;

  /// No description provided for @keyTextPem.
  ///
  /// In en, this message translates to:
  /// **'Key Text (PEM)'**
  String get keyTextPem;

  /// No description provided for @selectKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Select Key File'**
  String get selectKeyFile;

  /// No description provided for @clearKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Clear key file'**
  String get clearKeyFile;

  /// No description provided for @quickConnect.
  ///
  /// In en, this message translates to:
  /// **'Quick Connect'**
  String get quickConnect;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// No description provided for @qrGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'QR generation failed'**
  String get qrGenerationFailed;

  /// No description provided for @scanWithCameraApp.
  ///
  /// In en, this message translates to:
  /// **'Scan with any camera app on a device\nthat has LetsFLUTssh installed.'**
  String get scanWithCameraApp;

  /// No description provided for @noPasswordsInQr.
  ///
  /// In en, this message translates to:
  /// **'No passwords or keys are in this QR code'**
  String get noPasswordsInQr;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get copyLink;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopied;

  /// No description provided for @hostKeyChanged.
  ///
  /// In en, this message translates to:
  /// **'Host Key Changed!'**
  String get hostKeyChanged;

  /// No description provided for @unknownHost.
  ///
  /// In en, this message translates to:
  /// **'Unknown Host'**
  String get unknownHost;

  /// No description provided for @hostKeyChangedWarning.
  ///
  /// In en, this message translates to:
  /// **'WARNING: The host key for this server has changed. This could indicate a man-in-the-middle attack, or the server may have been reinstalled.'**
  String get hostKeyChangedWarning;

  /// No description provided for @unknownHostMessage.
  ///
  /// In en, this message translates to:
  /// **'The authenticity of this host cannot be established. Are you sure you want to continue connecting?'**
  String get unknownHostMessage;

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @keyType.
  ///
  /// In en, this message translates to:
  /// **'Key type'**
  String get keyType;

  /// No description provided for @fingerprint.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get fingerprint;

  /// No description provided for @fingerprintCopied.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint copied'**
  String get fingerprintCopied;

  /// No description provided for @copyFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Copy fingerprint'**
  String get copyFingerprint;

  /// No description provided for @acceptAnyway.
  ///
  /// In en, this message translates to:
  /// **'Accept Anyway'**
  String get acceptAnyway;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @importData.
  ///
  /// In en, this message translates to:
  /// **'Import Data'**
  String get importData;

  /// No description provided for @masterPassword.
  ///
  /// In en, this message translates to:
  /// **'Master Password'**
  String get masterPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @importModeMergeDescription.
  ///
  /// In en, this message translates to:
  /// **'Add new sessions, keep existing'**
  String get importModeMergeDescription;

  /// No description provided for @importModeReplaceDescription.
  ///
  /// In en, this message translates to:
  /// **'Replace all sessions with imported'**
  String get importModeReplaceDescription;

  /// No description provided for @errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorPrefix(String error);

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @newName.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get newName;

  /// No description provided for @deleteItems.
  ///
  /// In en, this message translates to:
  /// **'Delete {names}?'**
  String deleteItems(String names);

  /// No description provided for @deleteNItems.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} items'**
  String deleteNItems(int count);

  /// No description provided for @deletedItem.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String deletedItem(String name);

  /// No description provided for @deletedNItems.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} items'**
  String deletedNItems(int count);

  /// No description provided for @failedToCreateFolder.
  ///
  /// In en, this message translates to:
  /// **'Failed to create folder: {error}'**
  String failedToCreateFolder(String error);

  /// No description provided for @failedToRename.
  ///
  /// In en, this message translates to:
  /// **'Failed to rename: {error}'**
  String failedToRename(String error);

  /// No description provided for @failedToDeleteItem.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete {name}: {error}'**
  String failedToDeleteItem(String name, String error);

  /// No description provided for @editPath.
  ///
  /// In en, this message translates to:
  /// **'Edit Path'**
  String get editPath;

  /// No description provided for @root.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get root;

  /// No description provided for @controllersNotInitialized.
  ///
  /// In en, this message translates to:
  /// **'Controllers not initialized'**
  String get controllersNotInitialized;

  /// No description provided for @initializingSftp.
  ///
  /// In en, this message translates to:
  /// **'Initializing SFTP...'**
  String get initializingSftp;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// No description provided for @noTransfersYet.
  ///
  /// In en, this message translates to:
  /// **'No transfers yet'**
  String get noTransfersYet;

  /// No description provided for @copyRight.
  ///
  /// In en, this message translates to:
  /// **'Copy Right'**
  String get copyRight;

  /// No description provided for @copyDown.
  ///
  /// In en, this message translates to:
  /// **'Copy Down'**
  String get copyDown;

  /// No description provided for @closePane.
  ///
  /// In en, this message translates to:
  /// **'Close Pane'**
  String get closePane;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @closeEsc.
  ///
  /// In en, this message translates to:
  /// **'Close (Esc)'**
  String get closeEsc;

  /// No description provided for @copyRightShortcut.
  ///
  /// In en, this message translates to:
  /// **'Copy Right (Ctrl+\\)'**
  String get copyRightShortcut;

  /// No description provided for @copyDownShortcut.
  ///
  /// In en, this message translates to:
  /// **'Copy Down (Ctrl+Shift+\\)'**
  String get copyDownShortcut;

  /// No description provided for @closeOthers.
  ///
  /// In en, this message translates to:
  /// **'Close Others'**
  String get closeOthers;

  /// No description provided for @closeTabsToTheLeft.
  ///
  /// In en, this message translates to:
  /// **'Close Tabs to the Left'**
  String get closeTabsToTheLeft;

  /// No description provided for @closeTabsToTheRight.
  ///
  /// In en, this message translates to:
  /// **'Close Tabs to the Right'**
  String get closeTabsToTheRight;

  /// No description provided for @noActiveSession.
  ///
  /// In en, this message translates to:
  /// **'No active session'**
  String get noActiveSession;

  /// No description provided for @createConnectionHint.
  ///
  /// In en, this message translates to:
  /// **'Create a new connection or select one from the sidebar'**
  String get createConnectionHint;

  /// No description provided for @hideSidebar.
  ///
  /// In en, this message translates to:
  /// **'Hide Sidebar (Ctrl+B)'**
  String get hideSidebar;

  /// No description provided for @showSidebar.
  ///
  /// In en, this message translates to:
  /// **'Show Sidebar (Ctrl+B)'**
  String get showSidebar;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @connectionSection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connectionSection;

  /// No description provided for @transfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get transfers;

  /// No description provided for @data.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// No description provided for @logging.
  ///
  /// In en, this message translates to:
  /// **'Logging'**
  String get logging;

  /// No description provided for @updates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updates;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to Defaults'**
  String get resetToDefaults;

  /// No description provided for @uiScale.
  ///
  /// In en, this message translates to:
  /// **'UI Scale'**
  String get uiScale;

  /// No description provided for @terminalFontSize.
  ///
  /// In en, this message translates to:
  /// **'Terminal Font Size'**
  String get terminalFontSize;

  /// No description provided for @scrollbackLines.
  ///
  /// In en, this message translates to:
  /// **'Scrollback Lines'**
  String get scrollbackLines;

  /// No description provided for @keepAliveInterval.
  ///
  /// In en, this message translates to:
  /// **'Keep-Alive Interval (sec)'**
  String get keepAliveInterval;

  /// No description provided for @sshTimeout.
  ///
  /// In en, this message translates to:
  /// **'SSH Timeout (sec)'**
  String get sshTimeout;

  /// No description provided for @defaultPort.
  ///
  /// In en, this message translates to:
  /// **'Default Port'**
  String get defaultPort;

  /// No description provided for @parallelWorkers.
  ///
  /// In en, this message translates to:
  /// **'Parallel Workers'**
  String get parallelWorkers;

  /// No description provided for @maxHistory.
  ///
  /// In en, this message translates to:
  /// **'Max History'**
  String get maxHistory;

  /// No description provided for @calculateFolderSizes.
  ///
  /// In en, this message translates to:
  /// **'Calculate Folder Sizes'**
  String get calculateFolderSizes;

  /// No description provided for @exportData.
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get exportData;

  /// No description provided for @exportDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save sessions, config, and keys to encrypted .lfs file'**
  String get exportDataSubtitle;

  /// No description provided for @importDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Load data from .lfs file'**
  String get importDataSubtitle;

  /// No description provided for @setMasterPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Set a master password to encrypt the archive.'**
  String get setMasterPasswordHint;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported to: {path}'**
  String exportedTo(String path);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @pathToLfsFile.
  ///
  /// In en, this message translates to:
  /// **'Path to .lfs file'**
  String get pathToLfsFile;

  /// No description provided for @hintLfsPath.
  ///
  /// In en, this message translates to:
  /// **'/path/to/export.lfs'**
  String get hintLfsPath;

  /// No description provided for @shareViaQrCode.
  ///
  /// In en, this message translates to:
  /// **'Share via QR Code'**
  String get shareViaQrCode;

  /// No description provided for @shareViaQrSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export sessions to QR for scanning by another device'**
  String get shareViaQrSubtitle;

  /// No description provided for @dataLocation.
  ///
  /// In en, this message translates to:
  /// **'Data Location'**
  String get dataLocation;

  /// No description provided for @pathCopied.
  ///
  /// In en, this message translates to:
  /// **'Path copied to clipboard'**
  String get pathCopied;

  /// No description provided for @urlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied to clipboard'**
  String get urlCopied;

  /// No description provided for @aboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'v{version} — SSH/SFTP client'**
  String aboutSubtitle(String version);

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source Code'**
  String get sourceCode;

  /// No description provided for @enableLogging.
  ///
  /// In en, this message translates to:
  /// **'Enable Logging'**
  String get enableLogging;

  /// No description provided for @logIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Log is empty'**
  String get logIsEmpty;

  /// No description provided for @logExportedTo.
  ///
  /// In en, this message translates to:
  /// **'Log exported to: {path}'**
  String logExportedTo(String path);

  /// No description provided for @logExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Log export failed: {error}'**
  String logExportFailed(String error);

  /// No description provided for @logsCleared.
  ///
  /// In en, this message translates to:
  /// **'Logs cleared'**
  String get logsCleared;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @copyLog.
  ///
  /// In en, this message translates to:
  /// **'Copy log'**
  String get copyLog;

  /// No description provided for @exportLog.
  ///
  /// In en, this message translates to:
  /// **'Export log'**
  String get exportLog;

  /// No description provided for @clearLogs.
  ///
  /// In en, this message translates to:
  /// **'Clear logs'**
  String get clearLogs;

  /// No description provided for @local.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get local;

  /// No description provided for @remote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get remote;

  /// No description provided for @pickFolder.
  ///
  /// In en, this message translates to:
  /// **'Pick Folder'**
  String get pickFolder;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @up.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get up;

  /// No description provided for @emptyDirectory.
  ///
  /// In en, this message translates to:
  /// **'Empty directory'**
  String get emptyDirectory;

  /// No description provided for @cancelSelection.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get cancelSelection;

  /// No description provided for @openSftpBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open SFTP Browser'**
  String get openSftpBrowser;

  /// No description provided for @openSshTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open SSH Terminal'**
  String get openSshTerminal;

  /// No description provided for @noActiveFileBrowsers.
  ///
  /// In en, this message translates to:
  /// **'No active file browsers'**
  String get noActiveFileBrowsers;

  /// No description provided for @useSftpFromSessions.
  ///
  /// In en, this message translates to:
  /// **'Use \"SFTP\" from Sessions'**
  String get useSftpFromSessions;

  /// No description provided for @anotherInstanceRunning.
  ///
  /// In en, this message translates to:
  /// **'Another instance of LetsFLUTssh is already running.'**
  String get anotherInstanceRunning;

  /// No description provided for @importFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailedShort(String error);

  /// No description provided for @saveLogAs.
  ///
  /// In en, this message translates to:
  /// **'Save log as'**
  String get saveLogAs;

  /// No description provided for @chooseSaveLocation.
  ///
  /// In en, this message translates to:
  /// **'Choose save location'**
  String get chooseSaveLocation;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SEn();
  }

  throw FlutterError(
    'S.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
