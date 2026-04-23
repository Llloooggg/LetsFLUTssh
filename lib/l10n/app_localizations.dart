import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fa.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fa'),
    Locale('fr'),
    Locale('hi'),
    Locale('id'),
    Locale('ja'),
    Locale('ko'),
    Locale('pt'),
    Locale('ru'),
    Locale('tr'),
    Locale('vi'),
    Locale('zh'),
  ];

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

  /// No description provided for @infoDialogProtectsHeader.
  ///
  /// In en, this message translates to:
  /// **'Protects against'**
  String get infoDialogProtectsHeader;

  /// No description provided for @infoDialogDoesNotProtectHeader.
  ///
  /// In en, this message translates to:
  /// **'Does not protect against'**
  String get infoDialogDoesNotProtectHeader;

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

  /// No description provided for @cut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cut;

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

  /// No description provided for @copyModeTapToStart.
  ///
  /// In en, this message translates to:
  /// **'Touch to mark selection start'**
  String get copyModeTapToStart;

  /// No description provided for @copyModeExtending.
  ///
  /// In en, this message translates to:
  /// **'Drag to extend selection'**
  String get copyModeExtending;

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

  /// No description provided for @appSettings.
  ///
  /// In en, this message translates to:
  /// **'App Settings'**
  String get appSettings;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @importWhatToImport.
  ///
  /// In en, this message translates to:
  /// **'What to import:'**
  String get importWhatToImport;

  /// No description provided for @exportWhatToExport.
  ///
  /// In en, this message translates to:
  /// **'What to export:'**
  String get exportWhatToExport;

  /// No description provided for @enterMasterPasswordPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter master password:'**
  String get enterMasterPasswordPrompt;

  /// No description provided for @nextStep.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get nextStep;

  /// No description provided for @includeCredentials.
  ///
  /// In en, this message translates to:
  /// **'Include passwords and SSH keys'**
  String get includeCredentials;

  /// No description provided for @includePasswords.
  ///
  /// In en, this message translates to:
  /// **'Session passwords'**
  String get includePasswords;

  /// No description provided for @embeddedKeys.
  ///
  /// In en, this message translates to:
  /// **'Session keys'**
  String get embeddedKeys;

  /// No description provided for @managerKeys.
  ///
  /// In en, this message translates to:
  /// **'Keys from manager'**
  String get managerKeys;

  /// No description provided for @managerKeysMayBeLarge.
  ///
  /// In en, this message translates to:
  /// **'Manager keys may exceed QR size limit'**
  String get managerKeysMayBeLarge;

  /// No description provided for @qrPasswordWarning.
  ///
  /// In en, this message translates to:
  /// **'SSH keys are disabled by default for export.'**
  String get qrPasswordWarning;

  /// No description provided for @sshKeysMayBeLarge.
  ///
  /// In en, this message translates to:
  /// **'Keys may exceed QR size limit'**
  String get sshKeysMayBeLarge;

  /// No description provided for @exportTotalSize.
  ///
  /// In en, this message translates to:
  /// **'Total size: {size}'**
  String exportTotalSize(String size);

  /// No description provided for @qrCredentialsWarning.
  ///
  /// In en, this message translates to:
  /// **'Passwords and SSH keys WILL be visible in the QR code. Only share in trusted environments.'**
  String get qrCredentialsWarning;

  /// No description provided for @qrCredentialsTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Credentials make the QR code too large. Remove some sessions or disable credentials.'**
  String get qrCredentialsTooLarge;

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

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

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

  /// No description provided for @checkNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get checkNow;

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

  /// No description provided for @openReleasePage.
  ///
  /// In en, this message translates to:
  /// **'Open Release Page'**
  String get openReleasePage;

  /// No description provided for @couldNotOpenInstaller.
  ///
  /// In en, this message translates to:
  /// **'Could not open installer'**
  String get couldNotOpenInstaller;

  /// No description provided for @installerFailedOpenedReleasePage.
  ///
  /// In en, this message translates to:
  /// **'Installer launch failed; opened release page in browser'**
  String get installerFailedOpenedReleasePage;

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

  /// Trailing note for the import-success toast when one or more session/folder→tag or session→snippet links were dropped because the referenced tag/snippet was not part of the import (would have failed an FK insert).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} association dropped (target missing)} other{{count} associations dropped (targets missing)}}'**
  String importSkippedLinks(int count);

  /// Trailing note appended to the import-success toast when one or more session entries in the .lfs archive failed to parse and were dropped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} corrupt session skipped} other{{count} corrupt sessions skipped}}'**
  String importSkippedSessions(int count);

  /// No description provided for @sessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessions;

  /// No description provided for @emptyFolders.
  ///
  /// In en, this message translates to:
  /// **'Empty Folders'**
  String get emptyFolders;

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

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get deselectAll;

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

  /// No description provided for @authOrDivider.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get authOrDivider;

  /// No description provided for @providePasswordOrKey.
  ///
  /// In en, this message translates to:
  /// **'Provide a password or SSH key'**
  String get providePasswordOrKey;

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

  /// No description provided for @emptyFolder.
  ///
  /// In en, this message translates to:
  /// **'Empty folder'**
  String get emptyFolder;

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

  /// No description provided for @qrContainsCredentialsWarning.
  ///
  /// In en, this message translates to:
  /// **'This QR code contains session credentials. Keep the screen private.'**
  String get qrContainsCredentialsWarning;

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
  /// **'Key Type'**
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

  /// No description provided for @duplicateTab.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Tab'**
  String get duplicateTab;

  /// No description provided for @duplicateTabShortcut.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Tab (Ctrl+\\)'**
  String get duplicateTabShortcut;

  /// No description provided for @copyDown.
  ///
  /// In en, this message translates to:
  /// **'Copy Down'**
  String get copyDown;

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

  /// No description provided for @closeAll.
  ///
  /// In en, this message translates to:
  /// **'Close All'**
  String get closeAll;

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

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get languageSystemDefault;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

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

  /// No description provided for @sshConfigPreviewHostsFound.
  ///
  /// In en, this message translates to:
  /// **'{count} host(s) found'**
  String sshConfigPreviewHostsFound(int count);

  /// No description provided for @sshConfigPreviewNoHosts.
  ///
  /// In en, this message translates to:
  /// **'No importable hosts found in this file.'**
  String get sshConfigPreviewNoHosts;

  /// No description provided for @sshConfigPreviewMissingKeys.
  ///
  /// In en, this message translates to:
  /// **'Could not read key files for: {hosts}. These hosts will be imported without credentials.'**
  String sshConfigPreviewMissingKeys(String hosts);

  /// No description provided for @sshConfigPreviewFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Imported to folder: {folder}'**
  String sshConfigPreviewFolderLabel(String folder);

  /// No description provided for @sshConfigImportFolderName.
  ///
  /// In en, this message translates to:
  /// **'.ssh {date}'**
  String sshConfigImportFolderName(String date);

  /// No description provided for @exportArchive.
  ///
  /// In en, this message translates to:
  /// **'Export archive'**
  String get exportArchive;

  /// No description provided for @exportArchiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save sessions, config, and keys to encrypted .lfs file'**
  String get exportArchiveSubtitle;

  /// No description provided for @exportQrCode.
  ///
  /// In en, this message translates to:
  /// **'Export QR code'**
  String get exportQrCode;

  /// No description provided for @exportQrCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share selected sessions and keys via QR code'**
  String get exportQrCodeSubtitle;

  /// No description provided for @importArchive.
  ///
  /// In en, this message translates to:
  /// **'Import archive'**
  String get importArchive;

  /// No description provided for @importArchiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Load data from .lfs file'**
  String get importArchiveSubtitle;

  /// No description provided for @importFromSshDir.
  ///
  /// In en, this message translates to:
  /// **'Import from ~/.ssh'**
  String get importFromSshDir;

  /// No description provided for @importFromSshDirSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick hosts from config and/or private keys from ~/.ssh'**
  String get importFromSshDirSubtitle;

  /// No description provided for @sshDirImportHostsSection.
  ///
  /// In en, this message translates to:
  /// **'Hosts from config'**
  String get sshDirImportHostsSection;

  /// No description provided for @sshDirImportKeysSection.
  ///
  /// In en, this message translates to:
  /// **'Keys in ~/.ssh'**
  String get sshDirImportKeysSection;

  /// No description provided for @importSshKeysFound.
  ///
  /// In en, this message translates to:
  /// **'{count} key(s) found — pick which to import'**
  String importSshKeysFound(int count);

  /// No description provided for @importSshKeysNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No private keys found in ~/.ssh.'**
  String get importSshKeysNoneFound;

  /// No description provided for @sshKeyAlreadyImported.
  ///
  /// In en, this message translates to:
  /// **'already in store'**
  String get sshKeyAlreadyImported;

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

  /// No description provided for @passwordStrengthWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get passwordStrengthWeak;

  /// No description provided for @passwordStrengthModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get passwordStrengthModerate;

  /// No description provided for @passwordStrengthStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get passwordStrengthStrong;

  /// No description provided for @passwordStrengthVeryStrong.
  ///
  /// In en, this message translates to:
  /// **'Very strong'**
  String get passwordStrengthVeryStrong;

  /// No description provided for @tierRecommendedBadge.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get tierRecommendedBadge;

  /// No description provided for @tierCurrentBadge.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get tierCurrentBadge;

  /// No description provided for @tierAlternativeBranchLabel.
  ///
  /// In en, this message translates to:
  /// **'Alternative — don\'t trust the OS'**
  String get tierAlternativeBranchLabel;

  /// No description provided for @tierUpcomingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Ships in an upcoming version.'**
  String get tierUpcomingTooltip;

  /// No description provided for @tierUpcomingNotes.
  ///
  /// In en, this message translates to:
  /// **'This tier\'s underlying plumbing is not shipped yet. The row is visible so you know the option exists.'**
  String get tierUpcomingNotes;

  /// No description provided for @tierPlaintextLabel.
  ///
  /// In en, this message translates to:
  /// **'Plaintext'**
  String get tierPlaintextLabel;

  /// No description provided for @tierPlaintextSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No encryption — file permissions only'**
  String get tierPlaintextSubtitle;

  /// No description provided for @tierPlaintextThreat1.
  ///
  /// In en, this message translates to:
  /// **'Anyone with filesystem access reads your data'**
  String get tierPlaintextThreat1;

  /// No description provided for @tierPlaintextThreat2.
  ///
  /// In en, this message translates to:
  /// **'Accidental sync or backup reveals everything'**
  String get tierPlaintextThreat2;

  /// No description provided for @tierPlaintextNotes.
  ///
  /// In en, this message translates to:
  /// **'Use only in trusted, isolated environments.'**
  String get tierPlaintextNotes;

  /// No description provided for @tierKeychainLabel.
  ///
  /// In en, this message translates to:
  /// **'Keychain'**
  String get tierKeychainLabel;

  /// No description provided for @tierKeychainSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Key lives in {keychain} — auto-unlock on launch'**
  String tierKeychainSubtitle(String keychain);

  /// No description provided for @tierKeychainProtect1.
  ///
  /// In en, this message translates to:
  /// **'Other users on the same machine'**
  String get tierKeychainProtect1;

  /// No description provided for @tierKeychainProtect2.
  ///
  /// In en, this message translates to:
  /// **'Stolen disk without the OS login'**
  String get tierKeychainProtect2;

  /// No description provided for @tierKeychainThreat1.
  ///
  /// In en, this message translates to:
  /// **'Malware running under your OS account'**
  String get tierKeychainThreat1;

  /// No description provided for @tierKeychainThreat2.
  ///
  /// In en, this message translates to:
  /// **'An attacker who takes over your OS login'**
  String get tierKeychainThreat2;

  /// No description provided for @tierKeychainUnavailable.
  ///
  /// In en, this message translates to:
  /// **'OS keychain not available on this install.'**
  String get tierKeychainUnavailable;

  /// No description provided for @tierKeychainPassProtect1.
  ///
  /// In en, this message translates to:
  /// **'Coworker sitting at your desk'**
  String get tierKeychainPassProtect1;

  /// No description provided for @tierKeychainPassProtect2.
  ///
  /// In en, this message translates to:
  /// **'A passerby with unlocked access'**
  String get tierKeychainPassProtect2;

  /// No description provided for @tierKeychainPassThreat1.
  ///
  /// In en, this message translates to:
  /// **'Offline attacker with the file on disk'**
  String get tierKeychainPassThreat1;

  /// No description provided for @tierKeychainPassThreat2.
  ///
  /// In en, this message translates to:
  /// **'Same OS-compromise risks as Keychain'**
  String get tierKeychainPassThreat2;

  /// No description provided for @tierHardwareLabel.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get tierHardwareLabel;

  /// No description provided for @tierHardwareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hardware-bound vault + short PIN with lockout'**
  String get tierHardwareSubtitle;

  /// No description provided for @tierHardwareProtect1.
  ///
  /// In en, this message translates to:
  /// **'Offline brute force of the PIN (hardware rate-limit)'**
  String get tierHardwareProtect1;

  /// No description provided for @tierHardwareProtect2.
  ///
  /// In en, this message translates to:
  /// **'Stealing the disk and the keychain blob'**
  String get tierHardwareProtect2;

  /// No description provided for @tierHardwareThreat1.
  ///
  /// In en, this message translates to:
  /// **'OS or firmware CVE on the secure module'**
  String get tierHardwareThreat1;

  /// No description provided for @tierHardwareThreat2.
  ///
  /// In en, this message translates to:
  /// **'Forced biometric unlock (if enabled)'**
  String get tierHardwareThreat2;

  /// No description provided for @tierParanoidLabel.
  ///
  /// In en, this message translates to:
  /// **'Master password (Paranoid)'**
  String get tierParanoidLabel;

  /// No description provided for @tierParanoidSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Long password + Argon2id. Key never enters the OS.'**
  String get tierParanoidSubtitle;

  /// No description provided for @tierParanoidProtect1.
  ///
  /// In en, this message translates to:
  /// **'OS keychain compromise'**
  String get tierParanoidProtect1;

  /// No description provided for @tierParanoidProtect2.
  ///
  /// In en, this message translates to:
  /// **'Stolen disk (as long as your password is strong)'**
  String get tierParanoidProtect2;

  /// No description provided for @tierParanoidThreat1.
  ///
  /// In en, this message translates to:
  /// **'Keylogger capturing your password'**
  String get tierParanoidThreat1;

  /// No description provided for @tierParanoidThreat2.
  ///
  /// In en, this message translates to:
  /// **'Weak password + offline Argon2id cracking'**
  String get tierParanoidThreat2;

  /// No description provided for @tierParanoidNotes.
  ///
  /// In en, this message translates to:
  /// **'Biometric is disabled by design on this tier.'**
  String get tierParanoidNotes;

  /// No description provided for @tierHardwareUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Hardware vault not available on this install.'**
  String get tierHardwareUnavailable;

  /// No description provided for @pinLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get pinLabel;

  /// No description provided for @l2UnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Password required'**
  String get l2UnlockTitle;

  /// No description provided for @l2UnlockHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your short password to continue'**
  String get l2UnlockHint;

  /// No description provided for @l2WrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password'**
  String get l2WrongPassword;

  /// No description provided for @l3UnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get l3UnlockTitle;

  /// No description provided for @l3UnlockHint.
  ///
  /// In en, this message translates to:
  /// **'Password unlocks the hardware-bound vault'**
  String get l3UnlockHint;

  /// No description provided for @l3WrongPin.
  ///
  /// In en, this message translates to:
  /// **'Wrong password'**
  String get l3WrongPin;

  /// No description provided for @tierCooldownHint.
  ///
  /// In en, this message translates to:
  /// **'Try again in {seconds}s'**
  String tierCooldownHint(int seconds);

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

  /// No description provided for @browse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browse;

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

  /// No description provided for @dataStorageSection.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get dataStorageSection;

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

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @modified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get modified;

  /// No description provided for @mode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get mode;

  /// No description provided for @owner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get owner;

  /// No description provided for @connectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get connectionError;

  /// No description provided for @resizeWindowToViewFiles.
  ///
  /// In en, this message translates to:
  /// **'Resize window to view files'**
  String get resizeWindowToViewFiles;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exit;

  /// No description provided for @exitConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Active sessions will be disconnected. Exit?'**
  String get exitConfirmation;

  /// No description provided for @hintFolderExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. Production'**
  String get hintFolderExample;

  /// No description provided for @credentialsNotSet.
  ///
  /// In en, this message translates to:
  /// **'Credentials not set'**
  String get credentialsNotSet;

  /// No description provided for @exportSessionsViaQr.
  ///
  /// In en, this message translates to:
  /// **'Export Sessions via QR'**
  String get exportSessionsViaQr;

  /// No description provided for @qrNoCredentialsWarning.
  ///
  /// In en, this message translates to:
  /// **'Passwords and SSH keys are NOT included.\nImported sessions will need credentials filled in.'**
  String get qrNoCredentialsWarning;

  /// No description provided for @qrTooManyForSingleCode.
  ///
  /// In en, this message translates to:
  /// **'Too many sessions for a single QR code. Deselect some or use .lfs export.'**
  String get qrTooManyForSingleCode;

  /// No description provided for @qrTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Too large — deselect some items or use .lfs file export.'**
  String get qrTooLarge;

  /// No description provided for @exportAll.
  ///
  /// In en, this message translates to:
  /// **'Export All'**
  String get exportAll;

  /// No description provided for @showQr.
  ///
  /// In en, this message translates to:
  /// **'Show QR'**
  String get showQr;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @resizePanelDivider.
  ///
  /// In en, this message translates to:
  /// **'Resize panel divider'**
  String get resizePanelDivider;

  /// No description provided for @youreRunningLatest.
  ///
  /// In en, this message translates to:
  /// **'You\'re running the latest version'**
  String get youreRunningLatest;

  /// No description provided for @liveLog.
  ///
  /// In en, this message translates to:
  /// **'Live Log'**
  String get liveLog;

  /// No description provided for @transferNItems.
  ///
  /// In en, this message translates to:
  /// **'Transfer {count} items'**
  String transferNItems(int count);

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @errOperationNotPermitted.
  ///
  /// In en, this message translates to:
  /// **'Operation not permitted'**
  String get errOperationNotPermitted;

  /// No description provided for @errNoSuchFileOrDirectory.
  ///
  /// In en, this message translates to:
  /// **'No such file or directory'**
  String get errNoSuchFileOrDirectory;

  /// No description provided for @errNoSuchProcess.
  ///
  /// In en, this message translates to:
  /// **'No such process'**
  String get errNoSuchProcess;

  /// No description provided for @errIoError.
  ///
  /// In en, this message translates to:
  /// **'I/O error'**
  String get errIoError;

  /// No description provided for @errBadFileDescriptor.
  ///
  /// In en, this message translates to:
  /// **'Bad file descriptor'**
  String get errBadFileDescriptor;

  /// No description provided for @errResourceTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Resource temporarily unavailable'**
  String get errResourceTemporarilyUnavailable;

  /// No description provided for @errOutOfMemory.
  ///
  /// In en, this message translates to:
  /// **'Out of memory'**
  String get errOutOfMemory;

  /// No description provided for @errPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get errPermissionDenied;

  /// No description provided for @errFileExists.
  ///
  /// In en, this message translates to:
  /// **'File exists'**
  String get errFileExists;

  /// No description provided for @errNotADirectory.
  ///
  /// In en, this message translates to:
  /// **'Not a directory'**
  String get errNotADirectory;

  /// No description provided for @errIsADirectory.
  ///
  /// In en, this message translates to:
  /// **'Is a directory'**
  String get errIsADirectory;

  /// No description provided for @errInvalidArgument.
  ///
  /// In en, this message translates to:
  /// **'Invalid argument'**
  String get errInvalidArgument;

  /// No description provided for @errTooManyOpenFiles.
  ///
  /// In en, this message translates to:
  /// **'Too many open files'**
  String get errTooManyOpenFiles;

  /// No description provided for @errNoSpaceLeftOnDevice.
  ///
  /// In en, this message translates to:
  /// **'No space left on device'**
  String get errNoSpaceLeftOnDevice;

  /// No description provided for @errReadOnlyFileSystem.
  ///
  /// In en, this message translates to:
  /// **'Read-only file system'**
  String get errReadOnlyFileSystem;

  /// No description provided for @errBrokenPipe.
  ///
  /// In en, this message translates to:
  /// **'Broken pipe'**
  String get errBrokenPipe;

  /// No description provided for @errFileNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'File name too long'**
  String get errFileNameTooLong;

  /// No description provided for @errDirectoryNotEmpty.
  ///
  /// In en, this message translates to:
  /// **'Directory not empty'**
  String get errDirectoryNotEmpty;

  /// No description provided for @errAddressAlreadyInUse.
  ///
  /// In en, this message translates to:
  /// **'Address already in use'**
  String get errAddressAlreadyInUse;

  /// No description provided for @errCannotAssignAddress.
  ///
  /// In en, this message translates to:
  /// **'Cannot assign requested address'**
  String get errCannotAssignAddress;

  /// No description provided for @errNetworkIsDown.
  ///
  /// In en, this message translates to:
  /// **'Network is down'**
  String get errNetworkIsDown;

  /// No description provided for @errNetworkIsUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Network is unreachable'**
  String get errNetworkIsUnreachable;

  /// No description provided for @errConnectionResetByPeer.
  ///
  /// In en, this message translates to:
  /// **'Connection reset by peer'**
  String get errConnectionResetByPeer;

  /// No description provided for @errConnectionTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out'**
  String get errConnectionTimedOut;

  /// No description provided for @errConnectionRefused.
  ///
  /// In en, this message translates to:
  /// **'Connection refused'**
  String get errConnectionRefused;

  /// No description provided for @errHostIsDown.
  ///
  /// In en, this message translates to:
  /// **'Host is down'**
  String get errHostIsDown;

  /// No description provided for @errNoRouteToHost.
  ///
  /// In en, this message translates to:
  /// **'No route to host'**
  String get errNoRouteToHost;

  /// No description provided for @errConnectionAborted.
  ///
  /// In en, this message translates to:
  /// **'Connection aborted'**
  String get errConnectionAborted;

  /// No description provided for @errAlreadyConnected.
  ///
  /// In en, this message translates to:
  /// **'Already connected'**
  String get errAlreadyConnected;

  /// No description provided for @errNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get errNotConnected;

  /// No description provided for @errSshConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to connect to {host}:{port}'**
  String errSshConnectFailed(String host, int port);

  /// No description provided for @errSshAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed for {user}@{host}'**
  String errSshAuthFailed(String user, String host);

  /// No description provided for @errSshConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed to {host}:{port}'**
  String errSshConnectionFailed(String host, int port);

  /// No description provided for @errSshAuthAborted.
  ///
  /// In en, this message translates to:
  /// **'Authentication aborted'**
  String get errSshAuthAborted;

  /// No description provided for @errSshHostKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'Host key rejected for {host}:{port} — accept the host key or check known_hosts'**
  String errSshHostKeyRejected(String host, int port);

  /// No description provided for @errSshOpenShellFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open shell'**
  String get errSshOpenShellFailed;

  /// No description provided for @errSshLoadKeyFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load SSH key file'**
  String get errSshLoadKeyFileFailed;

  /// No description provided for @errSshParseKeyFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to parse PEM key data'**
  String get errSshParseKeyFailed;

  /// No description provided for @errSshConnectionDisposed.
  ///
  /// In en, this message translates to:
  /// **'Connection disposed'**
  String get errSshConnectionDisposed;

  /// No description provided for @errSshNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get errSshNotConnected;

  /// No description provided for @errConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get errConnectionFailed;

  /// No description provided for @errConnectionTimedOutSeconds.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out after {seconds} seconds'**
  String errConnectionTimedOutSeconds(int seconds);

  /// No description provided for @errSessionClosed.
  ///
  /// In en, this message translates to:
  /// **'Session closed'**
  String get errSessionClosed;

  /// No description provided for @errShellError.
  ///
  /// In en, this message translates to:
  /// **'Shell error: {error}'**
  String errShellError(String error);

  /// No description provided for @errReconnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Reconnect failed: {error}'**
  String errReconnectFailed(String error);

  /// No description provided for @errSftpInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to initialize SFTP: {error}'**
  String errSftpInitFailed(String error);

  /// No description provided for @errDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String errDownloadFailed(String error);

  /// No description provided for @errDecryptionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to decrypt credentials. Key file may be corrupted.'**
  String get errDecryptionFailed;

  /// No description provided for @errExportPickerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The system folder picker is unavailable. Try another location or check app storage permissions.'**
  String get errExportPickerUnavailable;

  /// No description provided for @biometricUnlockPrompt.
  ///
  /// In en, this message translates to:
  /// **'Unlock LetsFLUTssh'**
  String get biometricUnlockPrompt;

  /// No description provided for @biometricUnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics'**
  String get biometricUnlockTitle;

  /// No description provided for @biometricUnlockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Skip typing the password — unlock with the device biometric sensor.'**
  String get biometricUnlockSubtitle;

  /// No description provided for @biometricNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock is not available on this device.'**
  String get biometricNotAvailable;

  /// No description provided for @biometricEnableFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not enable biometric unlock.'**
  String get biometricEnableFailed;

  /// No description provided for @biometricEnabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock enabled'**
  String get biometricEnabled;

  /// No description provided for @biometricDisabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock disabled'**
  String get biometricDisabled;

  /// No description provided for @biometricUnlockFailed.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock failed. Enter your master password.'**
  String get biometricUnlockFailed;

  /// No description provided for @biometricUnlockCancelled.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock cancelled.'**
  String get biometricUnlockCancelled;

  /// No description provided for @biometricNotEnrolled.
  ///
  /// In en, this message translates to:
  /// **'No biometric credentials enrolled on this device.'**
  String get biometricNotEnrolled;

  /// No description provided for @biometricRequiresMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Set a master password first to enable biometric unlock.'**
  String get biometricRequiresMasterPassword;

  /// No description provided for @biometricSensorNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This device has no biometric sensor.'**
  String get biometricSensorNotAvailable;

  /// No description provided for @biometricSystemServiceMissing.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint service (fprintd) is not installed. See README → Installation.'**
  String get biometricSystemServiceMissing;

  /// No description provided for @biometricBackingHardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware-backed (Secure Enclave / TPM)'**
  String get biometricBackingHardware;

  /// No description provided for @biometricBackingSoftware.
  ///
  /// In en, this message translates to:
  /// **'Software-backed'**
  String get biometricBackingSoftware;

  /// No description provided for @currentPasswordIncorrect.
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect'**
  String get currentPasswordIncorrect;

  /// No description provided for @wrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password'**
  String get wrongPassword;

  /// No description provided for @useKeychain.
  ///
  /// In en, this message translates to:
  /// **'Encrypt with OS keychain'**
  String get useKeychain;

  /// No description provided for @useKeychainSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Store the database key in the system credential store. Off = plaintext database.'**
  String get useKeychainSubtitle;

  /// No description provided for @lockScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'LetsFLUTssh is locked'**
  String get lockScreenTitle;

  /// No description provided for @lockScreenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the master password or use biometrics to continue.'**
  String get lockScreenSubtitle;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @autoLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock after inactivity'**
  String get autoLockTitle;

  /// No description provided for @autoLockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Block the UI when idle for this long. The database key is wiped and the encrypted store is closed on every lock; active sessions stay connected through a per-session credential cache that clears when the session is closed.'**
  String get autoLockSubtitle;

  /// No description provided for @autoLockOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get autoLockOff;

  /// No description provided for @autoLockMinutesValue.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, one{{minutes} minute} other{{minutes} minutes}}'**
  String autoLockMinutesValue(int minutes);

  /// No description provided for @errReleaseSignatureInvalid.
  ///
  /// In en, this message translates to:
  /// **'Update rejected: the downloaded files are not signed by the pinned release key. This can mean the download was tampered with in transit, or the current release genuinely is not for this installation. Do NOT install — reinstall manually from the official Releases page instead.'**
  String get errReleaseSignatureInvalid;

  /// No description provided for @updateSecurityWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Update verification failed'**
  String get updateSecurityWarningTitle;

  /// No description provided for @updateReinstallAction.
  ///
  /// In en, this message translates to:
  /// **'Open Releases page'**
  String get updateReinstallAction;

  /// No description provided for @errLfsNotArchive.
  ///
  /// In en, this message translates to:
  /// **'Selected file is not a LetsFLUTssh archive.'**
  String get errLfsNotArchive;

  /// No description provided for @errLfsDecryptFailed.
  ///
  /// In en, this message translates to:
  /// **'Wrong master password or corrupted .lfs archive'**
  String get errLfsDecryptFailed;

  /// No description provided for @errLfsArchiveTruncated.
  ///
  /// In en, this message translates to:
  /// **'Archive is incomplete. Re-download or re-export from the original device.'**
  String get errLfsArchiveTruncated;

  /// No description provided for @errLfsArchiveTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Archive is too large ({sizeMb} MB). The limit is {limitMb} MB — aborted before decryption to protect memory.'**
  String errLfsArchiveTooLarge(String sizeMb, String limitMb);

  /// Shown when the known_hosts blob inside a successfully decrypted .lfs archive exceeds the per-entry cap.
  ///
  /// In en, this message translates to:
  /// **'known_hosts entry is too large ({sizeMb} MB). The limit is {limitMb} MB — aborted to keep the import responsive.'**
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb);

  /// Shown after a replace-mode import fails and the pre-import snapshot has been replayed. {cause} is the underlying failure (already localized).
  ///
  /// In en, this message translates to:
  /// **'Import failed — your data has been restored to the state before the import. ({cause})'**
  String errLfsImportRolledBack(String cause);

  /// No description provided for @errLfsUnsupportedVersion.
  ///
  /// In en, this message translates to:
  /// **'Archive uses schema v{found}, but this build only understands up to v{supported}. Update the app to import it.'**
  String errLfsUnsupportedVersion(int found, int supported);

  /// No description provided for @progressReadingArchive.
  ///
  /// In en, this message translates to:
  /// **'Reading archive…'**
  String get progressReadingArchive;

  /// No description provided for @progressDecrypting.
  ///
  /// In en, this message translates to:
  /// **'Decrypting…'**
  String get progressDecrypting;

  /// No description provided for @progressParsingArchive.
  ///
  /// In en, this message translates to:
  /// **'Parsing archive…'**
  String get progressParsingArchive;

  /// No description provided for @progressImportingSessions.
  ///
  /// In en, this message translates to:
  /// **'Importing sessions'**
  String get progressImportingSessions;

  /// No description provided for @progressImportingFolders.
  ///
  /// In en, this message translates to:
  /// **'Importing folders'**
  String get progressImportingFolders;

  /// No description provided for @progressImportingManagerKeys.
  ///
  /// In en, this message translates to:
  /// **'Importing SSH keys'**
  String get progressImportingManagerKeys;

  /// No description provided for @progressImportingTags.
  ///
  /// In en, this message translates to:
  /// **'Importing tags'**
  String get progressImportingTags;

  /// No description provided for @progressImportingSnippets.
  ///
  /// In en, this message translates to:
  /// **'Importing snippets'**
  String get progressImportingSnippets;

  /// No description provided for @progressApplyingConfig.
  ///
  /// In en, this message translates to:
  /// **'Applying configuration…'**
  String get progressApplyingConfig;

  /// No description provided for @progressImportingKnownHosts.
  ///
  /// In en, this message translates to:
  /// **'Importing known_hosts…'**
  String get progressImportingKnownHosts;

  /// No description provided for @progressCollectingData.
  ///
  /// In en, this message translates to:
  /// **'Collecting data…'**
  String get progressCollectingData;

  /// No description provided for @progressEncrypting.
  ///
  /// In en, this message translates to:
  /// **'Encrypting…'**
  String get progressEncrypting;

  /// No description provided for @progressWritingArchive.
  ///
  /// In en, this message translates to:
  /// **'Writing archive…'**
  String get progressWritingArchive;

  /// No description provided for @progressReencrypting.
  ///
  /// In en, this message translates to:
  /// **'Re-encrypting stores…'**
  String get progressReencrypting;

  /// No description provided for @progressWorking.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get progressWorking;

  /// No description provided for @importFromLink.
  ///
  /// In en, this message translates to:
  /// **'Import from QR link'**
  String get importFromLink;

  /// No description provided for @importFromLinkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Paste a letsflutssh:// deep link copied from another device'**
  String get importFromLinkSubtitle;

  /// No description provided for @pasteImportLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste import link'**
  String get pasteImportLinkTitle;

  /// No description provided for @pasteImportLinkDescription.
  ///
  /// In en, this message translates to:
  /// **'Paste the letsflutssh://import?d=… link (or raw payload) generated on another device. No camera needed.'**
  String get pasteImportLinkDescription;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @invalidImportLink.
  ///
  /// In en, this message translates to:
  /// **'Link does not contain a valid LetsFLUTssh payload'**
  String get invalidImportLink;

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// No description provided for @saveSessionToAssignTags.
  ///
  /// In en, this message translates to:
  /// **'Save the session first to assign tags'**
  String get saveSessionToAssignTags;

  /// No description provided for @noTagsAssigned.
  ///
  /// In en, this message translates to:
  /// **'No tags assigned'**
  String get noTagsAssigned;

  /// No description provided for @errWithPath.
  ///
  /// In en, this message translates to:
  /// **'{error}: {path}'**
  String errWithPath(String error, String path);

  /// No description provided for @errWithCause.
  ///
  /// In en, this message translates to:
  /// **'{error} ({cause})'**
  String errWithCause(String error, String cause);

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @protocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get protocol;

  /// No description provided for @typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// No description provided for @folder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// No description provided for @nSubitems.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s)'**
  String nSubitems(int count);

  /// No description provided for @subitems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get subitems;

  /// No description provided for @storagePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Storage permission required to browse local files'**
  String get storagePermissionRequired;

  /// No description provided for @grantPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant Permission'**
  String get grantPermission;

  /// No description provided for @storagePermissionLimited.
  ///
  /// In en, this message translates to:
  /// **'Limited access — grant full storage permission for all files'**
  String get storagePermissionLimited;

  /// No description provided for @progressConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {host}:{port}'**
  String progressConnecting(String host, int port);

  /// No description provided for @progressVerifyingHostKey.
  ///
  /// In en, this message translates to:
  /// **'Verifying host key'**
  String get progressVerifyingHostKey;

  /// No description provided for @progressAuthenticating.
  ///
  /// In en, this message translates to:
  /// **'Authenticating as {user}'**
  String progressAuthenticating(String user);

  /// No description provided for @progressOpeningShell.
  ///
  /// In en, this message translates to:
  /// **'Opening shell'**
  String get progressOpeningShell;

  /// No description provided for @progressOpeningSftp.
  ///
  /// In en, this message translates to:
  /// **'Opening SFTP channel'**
  String get progressOpeningSftp;

  /// No description provided for @transfersLabel.
  ///
  /// In en, this message translates to:
  /// **'Transfers:'**
  String get transfersLabel;

  /// No description provided for @transferCountActive.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String transferCountActive(int count);

  /// No description provided for @transferCountQueued.
  ///
  /// In en, this message translates to:
  /// **', {count} queued'**
  String transferCountQueued(int count);

  /// No description provided for @transferCountInHistory.
  ///
  /// In en, this message translates to:
  /// **'{count} in history'**
  String transferCountInHistory(int count);

  /// No description provided for @transferTooltipCreated.
  ///
  /// In en, this message translates to:
  /// **'Created: {time}'**
  String transferTooltipCreated(String time);

  /// No description provided for @transferTooltipStarted.
  ///
  /// In en, this message translates to:
  /// **'Started: {time}'**
  String transferTooltipStarted(String time);

  /// No description provided for @transferTooltipEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended: {time}'**
  String transferTooltipEnded(String time);

  /// No description provided for @transferTooltipDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration: {duration}'**
  String transferTooltipDuration(String duration);

  /// No description provided for @transferStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get transferStatusQueued;

  /// No description provided for @transferStartingUpload.
  ///
  /// In en, this message translates to:
  /// **'Starting upload...'**
  String get transferStartingUpload;

  /// No description provided for @transferStartingDownload.
  ///
  /// In en, this message translates to:
  /// **'Starting download...'**
  String get transferStartingDownload;

  /// No description provided for @transferCopying.
  ///
  /// In en, this message translates to:
  /// **'Copying...'**
  String get transferCopying;

  /// No description provided for @transferDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get transferDone;

  /// No description provided for @transferFilesProgress.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} files'**
  String transferFilesProgress(int done, int total);

  /// No description provided for @fileConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'File already exists'**
  String get fileConflictTitle;

  /// No description provided for @fileConflictMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{fileName}\" already exists in {targetDir}. What would you like to do?'**
  String fileConflictMessage(String fileName, String targetDir);

  /// No description provided for @fileConflictSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get fileConflictSkip;

  /// No description provided for @fileConflictKeepBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get fileConflictKeepBoth;

  /// No description provided for @fileConflictReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get fileConflictReplace;

  /// No description provided for @fileConflictApplyAll.
  ///
  /// In en, this message translates to:
  /// **'Apply to all remaining'**
  String get fileConflictApplyAll;

  /// No description provided for @folderNameLabel.
  ///
  /// In en, this message translates to:
  /// **'FOLDER NAME'**
  String get folderNameLabel;

  /// No description provided for @folderAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Folder \"{name}\" already exists'**
  String folderAlreadyExists(String name);

  /// No description provided for @dropKeyFileHere.
  ///
  /// In en, this message translates to:
  /// **'Drop key file here'**
  String get dropKeyFileHere;

  /// No description provided for @sessionNoCredentials.
  ///
  /// In en, this message translates to:
  /// **'Session has no credentials — edit it first to add a password or key'**
  String get sessionNoCredentials;

  /// No description provided for @dragItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String dragItemCount(int count);

  /// No description provided for @qrSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All ({selected}/{total})'**
  String qrSelectAll(int selected, int total);

  /// No description provided for @qrPayloadSize.
  ///
  /// In en, this message translates to:
  /// **'Payload: {size} KB / {max} KB max'**
  String qrPayloadSize(String size, String max);

  /// No description provided for @noActiveTerminals.
  ///
  /// In en, this message translates to:
  /// **'No active terminals'**
  String get noActiveTerminals;

  /// No description provided for @connectFromSessionsTab.
  ///
  /// In en, this message translates to:
  /// **'Connect from Sessions tab'**
  String get connectFromSessionsTab;

  /// No description provided for @fileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found: {path}'**
  String fileNotFound(String path);

  /// No description provided for @sshConnectionChannel.
  ///
  /// In en, this message translates to:
  /// **'SSH Connection'**
  String get sshConnectionChannel;

  /// No description provided for @sshConnectionChannelDesc.
  ///
  /// In en, this message translates to:
  /// **'Keeps SSH connections alive in the background.'**
  String get sshConnectionChannelDesc;

  /// No description provided for @sshActive.
  ///
  /// In en, this message translates to:
  /// **'SSH active'**
  String get sshActive;

  /// No description provided for @activeConnectionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active connection(s)'**
  String activeConnectionCount(int count);

  /// No description provided for @itemCountWithSize.
  ///
  /// In en, this message translates to:
  /// **'{count} items, {size}'**
  String itemCountWithSize(int count, String size);

  /// No description provided for @maximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get maximize;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @duplicateDownShortcut.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Down (Ctrl+Shift+\\)'**
  String get duplicateDownShortcut;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @knownHosts.
  ///
  /// In en, this message translates to:
  /// **'Known Hosts'**
  String get knownHosts;

  /// No description provided for @knownHostsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage trusted SSH server fingerprints'**
  String get knownHostsSubtitle;

  /// No description provided for @knownHostsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No known hosts} =1{1 known host} other{{count} known hosts}}'**
  String knownHostsCount(int count);

  /// No description provided for @knownHostsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No known hosts yet. Connect to a server to add one.'**
  String get knownHostsEmpty;

  /// No description provided for @removeHost.
  ///
  /// In en, this message translates to:
  /// **'Remove Host'**
  String get removeHost;

  /// No description provided for @removeHostConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {host} from known hosts? You will be prompted to verify its key again on next connection.'**
  String removeHostConfirm(String host);

  /// No description provided for @clearAllKnownHosts.
  ///
  /// In en, this message translates to:
  /// **'Clear All Known Hosts'**
  String get clearAllKnownHosts;

  /// No description provided for @clearAllKnownHostsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove all known hosts? You will be prompted to verify each server key again.'**
  String get clearAllKnownHostsConfirm;

  /// No description provided for @importKnownHostsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import from OpenSSH known_hosts file'**
  String get importKnownHostsSubtitle;

  /// No description provided for @clearedAllHosts.
  ///
  /// In en, this message translates to:
  /// **'Cleared all known hosts'**
  String get clearedAllHosts;

  /// No description provided for @removedHost.
  ///
  /// In en, this message translates to:
  /// **'Removed {host}'**
  String removedHost(String host);

  /// No description provided for @tools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tools;

  /// No description provided for @sshKeys.
  ///
  /// In en, this message translates to:
  /// **'SSH Keys'**
  String get sshKeys;

  /// No description provided for @sshKeysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage SSH key pairs for authentication'**
  String get sshKeysSubtitle;

  /// No description provided for @noKeys.
  ///
  /// In en, this message translates to:
  /// **'No SSH keys. Import or generate one.'**
  String get noKeys;

  /// No description provided for @generateKey.
  ///
  /// In en, this message translates to:
  /// **'Generate Key'**
  String get generateKey;

  /// No description provided for @addKey.
  ///
  /// In en, this message translates to:
  /// **'Add Key'**
  String get addKey;

  /// No description provided for @filePickerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'File picker unavailable on this system'**
  String get filePickerUnavailable;

  /// No description provided for @importKey.
  ///
  /// In en, this message translates to:
  /// **'Import Key'**
  String get importKey;

  /// No description provided for @keyLabel.
  ///
  /// In en, this message translates to:
  /// **'Key Label'**
  String get keyLabel;

  /// No description provided for @keyLabelHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Work Server, GitHub'**
  String get keyLabelHint;

  /// No description provided for @selectKeyType.
  ///
  /// In en, this message translates to:
  /// **'Key Type'**
  String get selectKeyType;

  /// No description provided for @generating.
  ///
  /// In en, this message translates to:
  /// **'Generating...'**
  String get generating;

  /// No description provided for @keyGenerated.
  ///
  /// In en, this message translates to:
  /// **'Key generated: {label}'**
  String keyGenerated(String label);

  /// No description provided for @keyImported.
  ///
  /// In en, this message translates to:
  /// **'Key imported: {label}'**
  String keyImported(String label);

  /// No description provided for @deleteKey.
  ///
  /// In en, this message translates to:
  /// **'Delete Key'**
  String get deleteKey;

  /// No description provided for @deleteKeyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete key \"{label}\"? Sessions using it will lose access.'**
  String deleteKeyConfirm(String label);

  /// No description provided for @keyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Key deleted: {label}'**
  String keyDeleted(String label);

  /// No description provided for @publicKey.
  ///
  /// In en, this message translates to:
  /// **'Public Key'**
  String get publicKey;

  /// No description provided for @publicKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Public key copied to clipboard'**
  String get publicKeyCopied;

  /// No description provided for @pastePrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Paste Private Key (PEM)'**
  String get pastePrivateKey;

  /// No description provided for @pemHint.
  ///
  /// In en, this message translates to:
  /// **'-----BEGIN OPENSSH PRIVATE KEY-----'**
  String get pemHint;

  /// No description provided for @invalidPem.
  ///
  /// In en, this message translates to:
  /// **'Invalid PEM key data'**
  String get invalidPem;

  /// No description provided for @selectFromKeyStore.
  ///
  /// In en, this message translates to:
  /// **'Select from Key Store'**
  String get selectFromKeyStore;

  /// No description provided for @noKeySelected.
  ///
  /// In en, this message translates to:
  /// **'No key selected'**
  String get noKeySelected;

  /// No description provided for @keyCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No keys} =1{1 key} other{{count} keys}}'**
  String keyCount(int count);

  /// No description provided for @generated.
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get generated;

  /// No description provided for @passphraseRequired.
  ///
  /// In en, this message translates to:
  /// **'Passphrase Required'**
  String get passphraseRequired;

  /// No description provided for @passphrasePrompt.
  ///
  /// In en, this message translates to:
  /// **'The SSH key for {host} is encrypted. Enter the passphrase to unlock it.'**
  String passphrasePrompt(String host);

  /// No description provided for @passphraseWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong passphrase. Please try again.'**
  String get passphraseWrong;

  /// No description provided for @passphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphrase;

  /// No description provided for @rememberPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Remember for this session'**
  String get rememberPassphrase;

  /// No description provided for @masterPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Protect saved credentials with a password'**
  String get masterPasswordSubtitle;

  /// No description provided for @setMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Set Master Password'**
  String get setMasterPassword;

  /// No description provided for @changeMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Change Master Password'**
  String get changeMasterPassword;

  /// No description provided for @removeMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Remove Master Password'**
  String get removeMasterPassword;

  /// No description provided for @masterPasswordEnabled.
  ///
  /// In en, this message translates to:
  /// **'Credentials are protected by master password'**
  String get masterPasswordEnabled;

  /// No description provided for @masterPasswordDisabled.
  ///
  /// In en, this message translates to:
  /// **'Credentials use auto-generated key (no password)'**
  String get masterPasswordDisabled;

  /// No description provided for @enterMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter master password to unlock your saved credentials.'**
  String get enterMasterPassword;

  /// No description provided for @wrongMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password. Please try again.'**
  String get wrongMasterPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPassword;

  /// No description provided for @masterPasswordSet.
  ///
  /// In en, this message translates to:
  /// **'Master password enabled'**
  String get masterPasswordSet;

  /// No description provided for @masterPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Master password changed'**
  String get masterPasswordChanged;

  /// No description provided for @masterPasswordRemoved.
  ///
  /// In en, this message translates to:
  /// **'Master password removed'**
  String get masterPasswordRemoved;

  /// No description provided for @masterPasswordWarning.
  ///
  /// In en, this message translates to:
  /// **'If you forget this password, all saved passwords and SSH keys will be lost. There is no recovery.'**
  String get masterPasswordWarning;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @forgotPasswordWarning.
  ///
  /// In en, this message translates to:
  /// **'This will delete ALL saved passwords, SSH keys, and passphrases. Sessions and settings will be kept. This cannot be undone.'**
  String get forgotPasswordWarning;

  /// No description provided for @resetAndDeleteCredentials.
  ///
  /// In en, this message translates to:
  /// **'Reset & Delete Credentials'**
  String get resetAndDeleteCredentials;

  /// No description provided for @credentialsReset.
  ///
  /// In en, this message translates to:
  /// **'All saved credentials have been deleted'**
  String get credentialsReset;

  /// No description provided for @migrationToast.
  ///
  /// In en, this message translates to:
  /// **'Storage upgraded to the latest format'**
  String get migrationToast;

  /// No description provided for @dbCorruptTitle.
  ///
  /// In en, this message translates to:
  /// **'Database cannot be opened'**
  String get dbCorruptTitle;

  /// No description provided for @dbCorruptBody.
  ///
  /// In en, this message translates to:
  /// **'The data on disk cannot be opened. Try a different credential, or reset to start fresh.'**
  String get dbCorruptBody;

  /// No description provided for @dbCorruptWarning.
  ///
  /// In en, this message translates to:
  /// **'Reset will permanently delete the encrypted database and every security-related file. No data will be recovered.'**
  String get dbCorruptWarning;

  /// No description provided for @dbCorruptTryOther.
  ///
  /// In en, this message translates to:
  /// **'Try different credentials'**
  String get dbCorruptTryOther;

  /// No description provided for @dbCorruptResetContinue.
  ///
  /// In en, this message translates to:
  /// **'Reset & Setup Fresh'**
  String get dbCorruptResetContinue;

  /// No description provided for @dbCorruptExit.
  ///
  /// In en, this message translates to:
  /// **'Quit LetsFLUTssh'**
  String get dbCorruptExit;

  /// No description provided for @tierResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Security reset required'**
  String get tierResetTitle;

  /// No description provided for @tierResetBody.
  ///
  /// In en, this message translates to:
  /// **'This install carries security data from an older version of LetsFLUTssh that used a different tier model. The new model is a breaking change — there is no automatic migration path. To continue, every saved session, credential, SSH key, and known-host entry on this install must be wiped and the first-launch setup wizard run fresh.'**
  String get tierResetBody;

  /// No description provided for @tierResetWarning.
  ///
  /// In en, this message translates to:
  /// **'Choosing Reset & Setup Fresh will permanently delete the encrypted database and every security-related file. If you need to recover your data, quit the app now and reinstall the previous version of LetsFLUTssh to export first.'**
  String get tierResetWarning;

  /// No description provided for @tierResetResetContinue.
  ///
  /// In en, this message translates to:
  /// **'Reset & Setup Fresh'**
  String get tierResetResetContinue;

  /// No description provided for @tierResetExit.
  ///
  /// In en, this message translates to:
  /// **'Quit LetsFLUTssh'**
  String get tierResetExit;

  /// No description provided for @derivingKey.
  ///
  /// In en, this message translates to:
  /// **'Deriving encryption key...'**
  String get derivingKey;

  /// No description provided for @reEncrypting.
  ///
  /// In en, this message translates to:
  /// **'Re-encrypting data...'**
  String get reEncrypting;

  /// No description provided for @confirmRemoveMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password to remove master password protection. Credentials will be re-encrypted with an auto-generated key.'**
  String get confirmRemoveMasterPassword;

  /// No description provided for @securitySetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Security Setup'**
  String get securitySetupTitle;

  /// No description provided for @securitySetupKeychainFound.
  ///
  /// In en, this message translates to:
  /// **'OS Keychain detected ({keychainName}). Your data will be automatically encrypted using your system keychain.'**
  String securitySetupKeychainFound(String keychainName);

  /// No description provided for @securitySetupKeychainOptional.
  ///
  /// In en, this message translates to:
  /// **'You can also set a master password for additional protection.'**
  String get securitySetupKeychainOptional;

  /// No description provided for @securitySetupNoKeychain.
  ///
  /// In en, this message translates to:
  /// **'No OS Keychain detected. Without a keychain, your session data (hosts, passwords, keys) will be stored in plaintext.'**
  String get securitySetupNoKeychain;

  /// No description provided for @securitySetupNoKeychainHint.
  ///
  /// In en, this message translates to:
  /// **'This is normal on WSL, headless Linux, or minimal installations. To enable keychain on Linux: install libsecret and a keyring daemon (e.g. gnome-keyring).'**
  String get securitySetupNoKeychainHint;

  /// No description provided for @securitySetupRecommendMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'We recommend setting a master password to protect your data.'**
  String get securitySetupRecommendMasterPassword;

  /// No description provided for @continueWithKeychain.
  ///
  /// In en, this message translates to:
  /// **'Continue with Keychain'**
  String get continueWithKeychain;

  /// No description provided for @continueWithoutEncryption.
  ///
  /// In en, this message translates to:
  /// **'Continue without Encryption'**
  String get continueWithoutEncryption;

  /// No description provided for @securityLevel.
  ///
  /// In en, this message translates to:
  /// **'Security Level'**
  String get securityLevel;

  /// No description provided for @securityLevelPlaintext.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get securityLevelPlaintext;

  /// No description provided for @securityLevelKeychain.
  ///
  /// In en, this message translates to:
  /// **'OS Keychain'**
  String get securityLevelKeychain;

  /// No description provided for @securityLevelMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Master Password'**
  String get securityLevelMasterPassword;

  /// No description provided for @keychainStatus.
  ///
  /// In en, this message translates to:
  /// **'Keychain'**
  String get keychainStatus;

  /// No description provided for @keychainAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get keychainAvailable;

  /// No description provided for @keychainNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get keychainNotAvailable;

  /// No description provided for @enableKeychain.
  ///
  /// In en, this message translates to:
  /// **'Enable Keychain Encryption'**
  String get enableKeychain;

  /// No description provided for @enableKeychainSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Re-encrypt stored data using OS keychain'**
  String get enableKeychainSubtitle;

  /// No description provided for @keychainEnabled.
  ///
  /// In en, this message translates to:
  /// **'Keychain encryption enabled'**
  String get keychainEnabled;

  /// No description provided for @manageMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Manage Master Password'**
  String get manageMasterPassword;

  /// No description provided for @manageMasterPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set, change, or remove master password'**
  String get manageMasterPasswordSubtitle;

  /// No description provided for @changeSecurityTier.
  ///
  /// In en, this message translates to:
  /// **'Change Security Tier'**
  String get changeSecurityTier;

  /// No description provided for @changeSecurityTierSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open the tier ladder and switch to a different security level'**
  String get changeSecurityTierSubtitle;

  /// No description provided for @changeSecurityTierConfirm.
  ///
  /// In en, this message translates to:
  /// **'Re-encrypting the database with the new tier. This cannot be interrupted — keep the app open until it finishes.'**
  String get changeSecurityTierConfirm;

  /// No description provided for @changeSecurityTierDone.
  ///
  /// In en, this message translates to:
  /// **'Security tier changed'**
  String get changeSecurityTierDone;

  /// No description provided for @changeSecurityTierFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change security tier'**
  String get changeSecurityTierFailed;

  /// No description provided for @firstLaunchSecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'Secure storage enabled'**
  String get firstLaunchSecurityTitle;

  /// No description provided for @firstLaunchSecurityBody.
  ///
  /// In en, this message translates to:
  /// **'Your data is encrypted with a key held in the OS keychain. Unlock is automatic on this device.'**
  String get firstLaunchSecurityBody;

  /// No description provided for @firstLaunchSecurityUpgradeAvailable.
  ///
  /// In en, this message translates to:
  /// **'Hardware-backed storage is available on this device. Upgrade in Settings → Security for TPM / Secure Enclave binding.'**
  String get firstLaunchSecurityUpgradeAvailable;

  /// No description provided for @firstLaunchSecurityHardwareUnavailableWindows.
  ///
  /// In en, this message translates to:
  /// **'Hardware-backed storage is unavailable — no TPM 2.0 detected on this device.'**
  String get firstLaunchSecurityHardwareUnavailableWindows;

  /// No description provided for @firstLaunchSecurityHardwareUnavailableApple.
  ///
  /// In en, this message translates to:
  /// **'Hardware-backed storage is unavailable — this device does not report a Secure Enclave.'**
  String get firstLaunchSecurityHardwareUnavailableApple;

  /// No description provided for @firstLaunchSecurityHardwareUnavailableLinux.
  ///
  /// In en, this message translates to:
  /// **'Hardware-backed storage is unavailable — install tpm2-tools and a TPM 2.0 device to enable it.'**
  String get firstLaunchSecurityHardwareUnavailableLinux;

  /// No description provided for @firstLaunchSecurityHardwareUnavailableAndroid.
  ///
  /// In en, this message translates to:
  /// **'Hardware-backed storage is unavailable — this device does not report a StrongBox or TEE.'**
  String get firstLaunchSecurityHardwareUnavailableAndroid;

  /// No description provided for @firstLaunchSecurityHardwareUnavailableGeneric.
  ///
  /// In en, this message translates to:
  /// **'Hardware-backed storage is unavailable on this device.'**
  String get firstLaunchSecurityHardwareUnavailableGeneric;

  /// No description provided for @firstLaunchSecurityOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get firstLaunchSecurityOpenSettings;

  /// No description provided for @firstLaunchSecurityDismiss.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get firstLaunchSecurityDismiss;

  /// No description provided for @securityHardwareUpgradeTitle.
  ///
  /// In en, this message translates to:
  /// **'Hardware-backed storage available'**
  String get securityHardwareUpgradeTitle;

  /// No description provided for @securityHardwareUpgradeBody.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to bind secrets to TPM / Secure Enclave.'**
  String get securityHardwareUpgradeBody;

  /// No description provided for @securityHardwareUpgradeAction.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get securityHardwareUpgradeAction;

  /// No description provided for @securityHardwareUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Hardware-backed storage unavailable'**
  String get securityHardwareUnavailableTitle;

  /// No description provided for @wizardReducedBanner.
  ///
  /// In en, this message translates to:
  /// **'OS keychain is not reachable on this install. Pick between no encryption (T0) and a master password (Paranoid). Install gnome-keyring, kwallet, or another libsecret provider to enable the Keychain tier.'**
  String get wizardReducedBanner;

  /// No description provided for @tierBlockProtectsHeader.
  ///
  /// In en, this message translates to:
  /// **'PROTECTS AGAINST'**
  String get tierBlockProtectsHeader;

  /// No description provided for @tierBlockDoesNotProtectHeader.
  ///
  /// In en, this message translates to:
  /// **'DOES NOT PROTECT'**
  String get tierBlockDoesNotProtectHeader;

  /// No description provided for @tierBlockProtectsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this tier.'**
  String get tierBlockProtectsEmpty;

  /// No description provided for @tierBlockDoesNotProtectEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing left uncovered.'**
  String get tierBlockDoesNotProtectEmpty;

  /// No description provided for @tierBadgeCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get tierBadgeCurrent;

  /// No description provided for @securitySetupEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get securitySetupEnable;

  /// No description provided for @securitySetupApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get securitySetupApply;

  /// No description provided for @passwordDisabledPlaintext.
  ///
  /// In en, this message translates to:
  /// **'Plaintext tier stores no secret to protect with a password.'**
  String get passwordDisabledPlaintext;

  /// No description provided for @passwordDisabledParanoid.
  ///
  /// In en, this message translates to:
  /// **'Paranoid derives the database key from the password — it is always on.'**
  String get passwordDisabledParanoid;

  /// No description provided for @passwordSubtitleOn.
  ///
  /// In en, this message translates to:
  /// **'On — password required on unlock'**
  String get passwordSubtitleOn;

  /// No description provided for @passwordSubtitleOff.
  ///
  /// In en, this message translates to:
  /// **'Off — tap to add a password on this tier'**
  String get passwordSubtitleOff;

  /// No description provided for @passwordSubtitleParanoid.
  ///
  /// In en, this message translates to:
  /// **'Required — the master password is the tier\'s secret'**
  String get passwordSubtitleParanoid;

  /// No description provided for @passwordSubtitlePlaintext.
  ///
  /// In en, this message translates to:
  /// **'Not applicable — no encryption on this tier'**
  String get passwordSubtitlePlaintext;

  /// No description provided for @hwProbeLinuxDeviceMissing.
  ///
  /// In en, this message translates to:
  /// **'No TPM detected at /dev/tpmrm0. Enable fTPM / PTT in BIOS if the machine supports it, otherwise the hardware tier is unavailable on this device.'**
  String get hwProbeLinuxDeviceMissing;

  /// No description provided for @hwProbeLinuxBinaryMissing.
  ///
  /// In en, this message translates to:
  /// **'tpm2-tools is not installed. Run `sudo apt install tpm2-tools` (or your distro equivalent) to enable the hardware tier.'**
  String get hwProbeLinuxBinaryMissing;

  /// No description provided for @hwProbeLinuxProbeFailed.
  ///
  /// In en, this message translates to:
  /// **'Hardware-tier probe failed. Check /dev/tpmrm0 permissions / udev rules — see logs for the tpm2-tools error.'**
  String get hwProbeLinuxProbeFailed;

  /// No description provided for @hwProbeWindowsSoftwareOnly.
  ///
  /// In en, this message translates to:
  /// **'No TPM 2.0 detected. Enable fTPM / PTT in UEFI firmware, or accept that the hardware tier is unavailable on this device — the app falls back to the software-backed credential store.'**
  String get hwProbeWindowsSoftwareOnly;

  /// No description provided for @hwProbeWindowsProvidersMissing.
  ///
  /// In en, this message translates to:
  /// **'Neither the Microsoft Platform Crypto Provider nor the Software Key Storage Provider is reachable — likely a corrupted Windows crypto subsystem or a Group Policy that blocks CNG. Check Event Viewer → Applications and Services Logs.'**
  String get hwProbeWindowsProvidersMissing;

  /// No description provided for @hwProbeMacosNoSecureEnclave.
  ///
  /// In en, this message translates to:
  /// **'This Mac has no Secure Enclave (pre-2017 Intel Mac without a T1 / T2 security chip). The hardware tier is not available; use master password instead.'**
  String get hwProbeMacosNoSecureEnclave;

  /// No description provided for @hwProbeMacosPasscodeNotSet.
  ///
  /// In en, this message translates to:
  /// **'No login password is set on this Mac. Secure Enclave key creation requires one — set a login password in System Settings → Touch ID & Password (or Login Password).'**
  String get hwProbeMacosPasscodeNotSet;

  /// No description provided for @hwProbeMacosSigningIdentityMissing.
  ///
  /// In en, this message translates to:
  /// **'Secure Enclave rejected the app\'s signing identity (-34018). Run the bundled `macos-resign.sh` script (download from the same release) to give this install a stable self-signed identity, then relaunch.'**
  String get hwProbeMacosSigningIdentityMissing;

  /// No description provided for @hwProbeIosPasscodeNotSet.
  ///
  /// In en, this message translates to:
  /// **'No device passcode is set. Secure Enclave key creation requires one — set a passcode in Settings → Face ID & Passcode (or Touch ID & Passcode).'**
  String get hwProbeIosPasscodeNotSet;

  /// No description provided for @hwProbeIosSimulator.
  ///
  /// In en, this message translates to:
  /// **'Running on the iOS Simulator, which has no Secure Enclave. The hardware tier is only available on physical iOS devices.'**
  String get hwProbeIosSimulator;

  /// No description provided for @hwProbeAndroidApiTooLow.
  ///
  /// In en, this message translates to:
  /// **'Android 9 or newer is required for the hardware tier (StrongBox and per-key enrolment invalidation are not reliable on older versions).'**
  String get hwProbeAndroidApiTooLow;

  /// No description provided for @hwProbeAndroidBiometricNone.
  ///
  /// In en, this message translates to:
  /// **'This device has no biometric hardware (fingerprint or face). Use master password instead.'**
  String get hwProbeAndroidBiometricNone;

  /// No description provided for @hwProbeAndroidBiometricNotEnrolled.
  ///
  /// In en, this message translates to:
  /// **'No biometric is enrolled. Add a fingerprint or face in Settings → Security & privacy → Biometrics, then re-enable the hardware tier.'**
  String get hwProbeAndroidBiometricNotEnrolled;

  /// No description provided for @hwProbeAndroidBiometricUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometric hardware is temporarily unusable (lockout after failed attempts, or pending security update). Retry in a few minutes.'**
  String get hwProbeAndroidBiometricUnavailable;

  /// No description provided for @hwProbeAndroidKeystoreRejected.
  ///
  /// In en, this message translates to:
  /// **'The Android Keystore refused to back a hardware key on this device build (StrongBox unavailable, custom ROM stripping, or driver glitch). The hardware tier is not available.'**
  String get hwProbeAndroidKeystoreRejected;

  /// No description provided for @securityRecheck.
  ///
  /// In en, this message translates to:
  /// **'Re-check tier support'**
  String get securityRecheck;

  /// No description provided for @securityRecheckUpdated.
  ///
  /// In en, this message translates to:
  /// **'Tier support updated — see cards above'**
  String get securityRecheckUpdated;

  /// No description provided for @securityRecheckUnchanged.
  ///
  /// In en, this message translates to:
  /// **'Tier support unchanged'**
  String get securityRecheckUnchanged;

  /// No description provided for @securityMacosEnableSecureTiers.
  ///
  /// In en, this message translates to:
  /// **'Unlock secure tiers on this Mac'**
  String get securityMacosEnableSecureTiers;

  /// No description provided for @securityMacosEnableSecureTiersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Re-sign the app with a personal certificate so Keychain (T1) and Secure Enclave (T2) work across updates'**
  String get securityMacosEnableSecureTiersSubtitle;

  /// No description provided for @securityMacosEnableSecureTiersPrompt.
  ///
  /// In en, this message translates to:
  /// **'macOS will ask for your password once'**
  String get securityMacosEnableSecureTiersPrompt;

  /// No description provided for @securityMacosEnableSecureTiersSuccess.
  ///
  /// In en, this message translates to:
  /// **'Secure tiers unlocked — T1 and T2 are now available'**
  String get securityMacosEnableSecureTiersSuccess;

  /// No description provided for @securityMacosEnableSecureTiersFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to unlock secure tiers'**
  String get securityMacosEnableSecureTiersFailed;

  /// No description provided for @securityMacosOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable Keychain + Secure Enclave?'**
  String get securityMacosOfferTitle;

  /// No description provided for @securityMacosOfferBody.
  ///
  /// In en, this message translates to:
  /// **'macOS binds encrypted storage to the app\'s signing identity. Without a stable cert, Keychain (T1) and Secure Enclave (T2) reject access. We can create a personal self-signed certificate on this Mac and re-sign the app with it — updates will keep working, and your secrets survive across releases. macOS will ask for your login password once to trust the new cert.'**
  String get securityMacosOfferBody;

  /// No description provided for @securityMacosOfferAccept.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get securityMacosOfferAccept;

  /// No description provided for @securityMacosOfferDecline.
  ///
  /// In en, this message translates to:
  /// **'Skip — pick T0 or Paranoid'**
  String get securityMacosOfferDecline;

  /// No description provided for @securityMacosRemoveIdentity.
  ///
  /// In en, this message translates to:
  /// **'Remove secure identity'**
  String get securityMacosRemoveIdentity;

  /// No description provided for @securityMacosRemoveIdentitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Deletes the personal signing cert. T1 / T2 data is tied to it — pick T0 or Paranoid first, then remove.'**
  String get securityMacosRemoveIdentitySubtitle;

  /// No description provided for @securityMacosRemoveIdentityConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove signing identity?'**
  String get securityMacosRemoveIdentityConfirmTitle;

  /// No description provided for @securityMacosRemoveIdentityConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes the personal cert from your login keychain. T1 / T2 stored secrets become unreadable afterwards. The wizard will open so you can migrate to T0 (plaintext) or Paranoid (master password) before removal.'**
  String get securityMacosRemoveIdentityConfirmBody;

  /// No description provided for @securityMacosRemoveIdentitySuccess.
  ///
  /// In en, this message translates to:
  /// **'Signing identity removed'**
  String get securityMacosRemoveIdentitySuccess;

  /// No description provided for @securityMacosRemoveIdentityFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove signing identity'**
  String get securityMacosRemoveIdentityFailed;

  /// No description provided for @keyringProbeLinuxNoSecretService.
  ///
  /// In en, this message translates to:
  /// **'D-Bus is up but no secret-service daemon is running. Install gnome-keyring (`sudo apt install gnome-keyring`) or KWalletManager and ensure it starts at login.'**
  String get keyringProbeLinuxNoSecretService;

  /// No description provided for @keyringProbeFailed.
  ///
  /// In en, this message translates to:
  /// **'The OS keychain is unreachable on this device. See logs for the specific platform error; the app falls back to master password.'**
  String get keyringProbeFailed;

  /// No description provided for @snippets.
  ///
  /// In en, this message translates to:
  /// **'Snippets'**
  String get snippets;

  /// No description provided for @snippetsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage reusable command snippets'**
  String get snippetsSubtitle;

  /// No description provided for @noSnippets.
  ///
  /// In en, this message translates to:
  /// **'No snippets yet'**
  String get noSnippets;

  /// No description provided for @addSnippet.
  ///
  /// In en, this message translates to:
  /// **'Add Snippet'**
  String get addSnippet;

  /// No description provided for @editSnippet.
  ///
  /// In en, this message translates to:
  /// **'Edit Snippet'**
  String get editSnippet;

  /// No description provided for @deleteSnippet.
  ///
  /// In en, this message translates to:
  /// **'Delete Snippet'**
  String get deleteSnippet;

  /// No description provided for @deleteSnippetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete snippet \"{title}\"?'**
  String deleteSnippetConfirm(String title);

  /// No description provided for @snippetTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get snippetTitle;

  /// No description provided for @snippetTitleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Deploy, Restart Service'**
  String get snippetTitleHint;

  /// No description provided for @snippetCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get snippetCommand;

  /// No description provided for @snippetCommandHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. sudo systemctl restart nginx'**
  String get snippetCommandHint;

  /// No description provided for @snippetDescription.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get snippetDescription;

  /// No description provided for @snippetDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'What does this command do?'**
  String get snippetDescriptionHint;

  /// No description provided for @snippetSaved.
  ///
  /// In en, this message translates to:
  /// **'Snippet saved'**
  String get snippetSaved;

  /// No description provided for @snippetDeleted.
  ///
  /// In en, this message translates to:
  /// **'Snippet \"{title}\" deleted'**
  String snippetDeleted(String title);

  /// No description provided for @snippetCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No snippets} =1{1 snippet} other{{count} snippets}}'**
  String snippetCount(int count);

  /// No description provided for @runSnippet.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get runSnippet;

  /// No description provided for @pinToSession.
  ///
  /// In en, this message translates to:
  /// **'Pin to this session'**
  String get pinToSession;

  /// No description provided for @unpinFromSession.
  ///
  /// In en, this message translates to:
  /// **'Unpin from this session'**
  String get unpinFromSession;

  /// No description provided for @pinnedSnippets.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinnedSnippets;

  /// No description provided for @allSnippets.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allSnippets;

  /// No description provided for @sendToTerminal.
  ///
  /// In en, this message translates to:
  /// **'Send to terminal'**
  String get sendToTerminal;

  /// No description provided for @commandCopied.
  ///
  /// In en, this message translates to:
  /// **'Command copied to clipboard'**
  String get commandCopied;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @tagsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Organize sessions and folders with color tags'**
  String get tagsSubtitle;

  /// No description provided for @noTags.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get noTags;

  /// No description provided for @addTag.
  ///
  /// In en, this message translates to:
  /// **'Add Tag'**
  String get addTag;

  /// No description provided for @deleteTag.
  ///
  /// In en, this message translates to:
  /// **'Delete Tag'**
  String get deleteTag;

  /// No description provided for @deleteTagConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete tag \"{name}\"? It will be removed from all sessions and folders.'**
  String deleteTagConfirm(String name);

  /// No description provided for @tagName.
  ///
  /// In en, this message translates to:
  /// **'Tag Name'**
  String get tagName;

  /// No description provided for @tagNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Production, Staging'**
  String get tagNameHint;

  /// No description provided for @tagColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get tagColor;

  /// No description provided for @tagCreated.
  ///
  /// In en, this message translates to:
  /// **'Tag created'**
  String get tagCreated;

  /// No description provided for @tagDeleted.
  ///
  /// In en, this message translates to:
  /// **'Tag \"{name}\" deleted'**
  String tagDeleted(String name);

  /// No description provided for @tagCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No tags} =1{1 tag} other{{count} tags}}'**
  String tagCount(int count);

  /// No description provided for @manageTags.
  ///
  /// In en, this message translates to:
  /// **'Manage Tags'**
  String get manageTags;

  /// No description provided for @editTags.
  ///
  /// In en, this message translates to:
  /// **'Edit Tags'**
  String get editTags;

  /// No description provided for @fullBackup.
  ///
  /// In en, this message translates to:
  /// **'Full backup'**
  String get fullBackup;

  /// No description provided for @sessionsOnly.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessionsOnly;

  /// No description provided for @allKeysFromManager.
  ///
  /// In en, this message translates to:
  /// **'All keys from manager'**
  String get allKeysFromManager;

  /// No description provided for @exportTags.
  ///
  /// In en, this message translates to:
  /// **'Tags ({count})'**
  String exportTags(int count);

  /// No description provided for @exportSnippets.
  ///
  /// In en, this message translates to:
  /// **'Snippets ({count})'**
  String exportSnippets(int count);

  /// No description provided for @disableKeychain.
  ///
  /// In en, this message translates to:
  /// **'Disable keychain encryption'**
  String get disableKeychain;

  /// No description provided for @disableKeychainSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to plaintext storage (not recommended)'**
  String get disableKeychainSubtitle;

  /// No description provided for @disableKeychainConfirm.
  ///
  /// In en, this message translates to:
  /// **'The database will be re-encrypted without a key. Sessions and keys will be stored in plaintext on disk. Continue?'**
  String get disableKeychainConfirm;

  /// No description provided for @keychainDisabled.
  ///
  /// In en, this message translates to:
  /// **'Keychain encryption disabled'**
  String get keychainDisabled;

  /// No description provided for @presetFullImport.
  ///
  /// In en, this message translates to:
  /// **'Full import'**
  String get presetFullImport;

  /// No description provided for @presetSelective.
  ///
  /// In en, this message translates to:
  /// **'Selective'**
  String get presetSelective;

  /// No description provided for @presetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get presetCustom;

  /// No description provided for @sessionSshKeys.
  ///
  /// In en, this message translates to:
  /// **'Session keys (manager)'**
  String get sessionSshKeys;

  /// No description provided for @allManagerKeys.
  ///
  /// In en, this message translates to:
  /// **'All manager keys'**
  String get allManagerKeys;

  /// No description provided for @browseFiles.
  ///
  /// In en, this message translates to:
  /// **'Browse files…'**
  String get browseFiles;

  /// No description provided for @sshDirSessionAlreadyImported.
  ///
  /// In en, this message translates to:
  /// **'already in sessions'**
  String get sshDirSessionAlreadyImported;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Interface language'**
  String get languageSubtitle;

  /// No description provided for @themeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Dark, light, or follow the system'**
  String get themeSubtitle;

  /// No description provided for @uiScaleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scale the whole interface'**
  String get uiScaleSubtitle;

  /// No description provided for @terminalFontSizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Font size in terminal output'**
  String get terminalFontSizeSubtitle;

  /// No description provided for @scrollbackLinesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Terminal history buffer size'**
  String get scrollbackLinesSubtitle;

  /// No description provided for @keepAliveIntervalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Seconds between SSH keep-alive packets (0 = off)'**
  String get keepAliveIntervalSubtitle;

  /// No description provided for @sshTimeoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connection timeout in seconds'**
  String get sshTimeoutSubtitle;

  /// No description provided for @defaultPortSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Default port for new sessions'**
  String get defaultPortSubtitle;

  /// No description provided for @parallelWorkersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Concurrent SFTP transfer workers'**
  String get parallelWorkersSubtitle;

  /// No description provided for @maxHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Maximum saved commands in history'**
  String get maxHistorySubtitle;

  /// No description provided for @calculateFolderSizesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show total size next to folders in the sidebar'**
  String get calculateFolderSizesSubtitle;

  /// No description provided for @checkForUpdatesOnStartupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Query GitHub for a new release when the app launches'**
  String get checkForUpdatesOnStartupSubtitle;

  /// No description provided for @enableLoggingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Write app events to a rotating log file'**
  String get enableLoggingSubtitle;

  /// No description provided for @exportWithoutPassword.
  ///
  /// In en, this message translates to:
  /// **'Export Without Password?'**
  String get exportWithoutPassword;

  /// No description provided for @exportWithoutPasswordWarning.
  ///
  /// In en, this message translates to:
  /// **'The archive will not be encrypted. Anyone with access to the file can read your data, including passwords and private keys.'**
  String get exportWithoutPasswordWarning;

  /// No description provided for @continueWithoutPassword.
  ///
  /// In en, this message translates to:
  /// **'Continue Without Password'**
  String get continueWithoutPassword;

  /// No description provided for @threatColdDiskTheft.
  ///
  /// In en, this message translates to:
  /// **'Cold-disk theft'**
  String get threatColdDiskTheft;

  /// No description provided for @threatColdDiskTheftDescription.
  ///
  /// In en, this message translates to:
  /// **'Powered-off machine with the drive removed and read on another computer, or a copy of the database file taken by someone with access to your home directory.'**
  String get threatColdDiskTheftDescription;

  /// No description provided for @threatKeyringFileTheft.
  ///
  /// In en, this message translates to:
  /// **'Keyring / keychain file exfiltration'**
  String get threatKeyringFileTheft;

  /// No description provided for @threatKeyringFileTheftDescription.
  ///
  /// In en, this message translates to:
  /// **'Attacker reads the platform\'s credential-store file directly off the disk (libsecret keyring, Windows Credential Manager, macOS login keychain) and recovers the wrapped database key from it. The hardware tier defeats this regardless of password because the chip refuses to export key material; the keychain tier needs a password on top so the stolen file cannot be unwrapped by the OS login password alone.'**
  String get threatKeyringFileTheftDescription;

  /// No description provided for @modifierOnlyWithPassword.
  ///
  /// In en, this message translates to:
  /// **'only with password'**
  String get modifierOnlyWithPassword;

  /// No description provided for @threatBystanderUnlockedMachine.
  ///
  /// In en, this message translates to:
  /// **'Bystander on an unlocked machine'**
  String get threatBystanderUnlockedMachine;

  /// No description provided for @threatBystanderUnlockedMachineDescription.
  ///
  /// In en, this message translates to:
  /// **'Someone walks up to your already-unlocked computer and opens the app while you are away.'**
  String get threatBystanderUnlockedMachineDescription;

  /// No description provided for @threatLiveRamForensicsLocked.
  ///
  /// In en, this message translates to:
  /// **'RAM forensics on a locked machine'**
  String get threatLiveRamForensicsLocked;

  /// No description provided for @threatLiveRamForensicsLockedDescription.
  ///
  /// In en, this message translates to:
  /// **'An attacker freezes RAM (or captures it via DMA) and pulls still-resident key material out of the snapshot, even while the app is locked.'**
  String get threatLiveRamForensicsLockedDescription;

  /// No description provided for @threatOsKernelOrKeychainBreach.
  ///
  /// In en, this message translates to:
  /// **'OS kernel or keychain compromise'**
  String get threatOsKernelOrKeychainBreach;

  /// No description provided for @threatOsKernelOrKeychainBreachDescription.
  ///
  /// In en, this message translates to:
  /// **'Kernel vulnerability, keychain exfiltration, or a backdoor in the hardware security chip. The operating system becomes the attacker rather than a trusted resource.'**
  String get threatOsKernelOrKeychainBreachDescription;

  /// No description provided for @threatOfflineBruteForce.
  ///
  /// In en, this message translates to:
  /// **'Offline brute force on weak password'**
  String get threatOfflineBruteForce;

  /// No description provided for @threatOfflineBruteForceDescription.
  ///
  /// In en, this message translates to:
  /// **'An attacker who has a copy of the wrapped key or sealed blob tries every password at their own pace without any rate limiter.'**
  String get threatOfflineBruteForceDescription;

  /// No description provided for @legendProtects.
  ///
  /// In en, this message translates to:
  /// **'Protected'**
  String get legendProtects;

  /// No description provided for @legendDoesNotProtect.
  ///
  /// In en, this message translates to:
  /// **'Not protected'**
  String get legendDoesNotProtect;

  /// No description provided for @legendNotApplicable.
  ///
  /// In en, this message translates to:
  /// **'Not applicable — no user secret for this tier'**
  String get legendNotApplicable;

  /// No description provided for @legendWeakPasswordWarning.
  ///
  /// In en, this message translates to:
  /// **'Weak password acceptable — another layer (hardware rate limiter or wrapped-key binding) carries the security'**
  String get legendWeakPasswordWarning;

  /// No description provided for @legendStrongPasswordRecommended.
  ///
  /// In en, this message translates to:
  /// **'A long passphrase is strongly recommended — this tier\'s security depends on it'**
  String get legendStrongPasswordRecommended;

  /// No description provided for @colT0.
  ///
  /// In en, this message translates to:
  /// **'T0 Plaintext'**
  String get colT0;

  /// No description provided for @colT1.
  ///
  /// In en, this message translates to:
  /// **'T1 Keychain'**
  String get colT1;

  /// No description provided for @colT1Password.
  ///
  /// In en, this message translates to:
  /// **'T1 + password'**
  String get colT1Password;

  /// No description provided for @colT1PasswordBiometric.
  ///
  /// In en, this message translates to:
  /// **'T1 + password + biometric'**
  String get colT1PasswordBiometric;

  /// No description provided for @colT2.
  ///
  /// In en, this message translates to:
  /// **'T2 Hardware'**
  String get colT2;

  /// No description provided for @colT2Password.
  ///
  /// In en, this message translates to:
  /// **'T2 + password'**
  String get colT2Password;

  /// No description provided for @colT2PasswordBiometric.
  ///
  /// In en, this message translates to:
  /// **'T2 + password + biometric'**
  String get colT2PasswordBiometric;

  /// No description provided for @colParanoid.
  ///
  /// In en, this message translates to:
  /// **'Paranoid'**
  String get colParanoid;

  /// No description provided for @securityComparisonTableTitle.
  ///
  /// In en, this message translates to:
  /// **'Security tiers — side-by-side comparison'**
  String get securityComparisonTableTitle;

  /// No description provided for @securityComparisonTableThreatColumn.
  ///
  /// In en, this message translates to:
  /// **'Threat'**
  String get securityComparisonTableThreatColumn;

  /// No description provided for @compareAllTiers.
  ///
  /// In en, this message translates to:
  /// **'Compare all tiers'**
  String get compareAllTiers;

  /// No description provided for @resetAllDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset all data'**
  String get resetAllDataTitle;

  /// No description provided for @resetAllDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Delete every session, key, config and security artefact. Clears keychain entries and hardware-vault slots too.'**
  String get resetAllDataSubtitle;

  /// No description provided for @resetAllDataConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset all data?'**
  String get resetAllDataConfirmTitle;

  /// No description provided for @resetAllDataConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All sessions, SSH keys, known hosts, snippets, tags, preferences, and every security artefact (keychain entries, hardware-vault blobs, biometric overlay) will be permanently deleted. This cannot be undone.'**
  String get resetAllDataConfirmBody;

  /// No description provided for @resetAllDataConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Reset everything'**
  String get resetAllDataConfirmAction;

  /// No description provided for @resetAllDataInProgress.
  ///
  /// In en, this message translates to:
  /// **'Resetting…'**
  String get resetAllDataInProgress;

  /// No description provided for @resetAllDataDone.
  ///
  /// In en, this message translates to:
  /// **'All data reset'**
  String get resetAllDataDone;

  /// No description provided for @resetAllDataFailed.
  ///
  /// In en, this message translates to:
  /// **'Reset failed'**
  String get resetAllDataFailed;

  /// No description provided for @compareAllTiersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See what each tier protects against, side-by-side.'**
  String get compareAllTiersSubtitle;

  /// No description provided for @autoLockRequiresPassword.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock requires a password on the active tier.'**
  String get autoLockRequiresPassword;

  /// No description provided for @recommendedBadge.
  ///
  /// In en, this message translates to:
  /// **'RECOMMENDED'**
  String get recommendedBadge;

  /// No description provided for @continueWithRecommended.
  ///
  /// In en, this message translates to:
  /// **'Continue with recommended'**
  String get continueWithRecommended;

  /// No description provided for @customizeSecurity.
  ///
  /// In en, this message translates to:
  /// **'Customize security'**
  String get customizeSecurity;

  /// No description provided for @tierHardwareSubtitleHonest.
  ///
  /// In en, this message translates to:
  /// **'Advanced: hardware-bound key. Data is irrecoverable if this device\'s chip is lost or replaced.'**
  String get tierHardwareSubtitleHonest;

  /// No description provided for @tierParanoidSubtitleHonest.
  ///
  /// In en, this message translates to:
  /// **'Alternative: master password, no OS trust. Protects against OS compromise. Does not improve runtime protection over T1/T2.'**
  String get tierParanoidSubtitleHonest;

  /// No description provided for @mitigationsNoteRuntimeThreats.
  ///
  /// In en, this message translates to:
  /// **'Runtime threats (same-user malware, live process memory dump) are shown as ✗ across every tier. They are addressed by separate mitigation features applied regardless of tier choice.'**
  String get mitigationsNoteRuntimeThreats;

  /// No description provided for @securitySetupContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get securitySetupContinue;

  /// No description provided for @currentTierBadge.
  ///
  /// In en, this message translates to:
  /// **'CURRENT'**
  String get currentTierBadge;

  /// No description provided for @paranoidAlternativeHeader.
  ///
  /// In en, this message translates to:
  /// **'ALTERNATIVE'**
  String get paranoidAlternativeHeader;

  /// No description provided for @modifierPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get modifierPasswordLabel;

  /// No description provided for @modifierPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Typed secret gate before the vault unlocks.'**
  String get modifierPasswordSubtitle;

  /// No description provided for @modifierBiometricLabel.
  ///
  /// In en, this message translates to:
  /// **'Biometric shortcut'**
  String get modifierBiometricLabel;

  /// No description provided for @modifierBiometricSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Release the password from a biometric-gated OS slot instead of typing it.'**
  String get modifierBiometricSubtitle;

  /// No description provided for @biometricRequiresPassword.
  ///
  /// In en, this message translates to:
  /// **'Enable a password first — biometric is a shortcut for entering it.'**
  String get biometricRequiresPassword;

  /// No description provided for @biometricRequiresActiveTier.
  ///
  /// In en, this message translates to:
  /// **'Select this tier first to enable biometric unlock'**
  String get biometricRequiresActiveTier;

  /// No description provided for @autoLockRequiresActiveTier.
  ///
  /// In en, this message translates to:
  /// **'Select this tier first to configure auto-lock'**
  String get autoLockRequiresActiveTier;

  /// No description provided for @biometricForbiddenParanoid.
  ///
  /// In en, this message translates to:
  /// **'Paranoid does not allow biometric by design.'**
  String get biometricForbiddenParanoid;

  /// No description provided for @fprintdNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'fprintd not installed or no enrolled finger.'**
  String get fprintdNotAvailable;

  /// No description provided for @linuxTpmWithoutPasswordNote.
  ///
  /// In en, this message translates to:
  /// **'TPM without a password provides isolation, not authentication. Anyone who can run this app can unlock the data.'**
  String get linuxTpmWithoutPasswordNote;

  /// No description provided for @paranoidMasterPasswordNote.
  ///
  /// In en, this message translates to:
  /// **'A long passphrase is strongly recommended — Argon2id only slows brute force, it does not block it.'**
  String get paranoidMasterPasswordNote;

  /// No description provided for @plaintextWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Plaintext: no encryption'**
  String get plaintextWarningTitle;

  /// No description provided for @plaintextWarningBody.
  ///
  /// In en, this message translates to:
  /// **'Sessions, keys, and known hosts will be stored without encryption. Anyone with access to this computer\'s filesystem can read them.'**
  String get plaintextWarningBody;

  /// No description provided for @plaintextAcknowledge.
  ///
  /// In en, this message translates to:
  /// **'I understand my data will not be encrypted'**
  String get plaintextAcknowledge;

  /// No description provided for @plaintextAcknowledgeRequired.
  ///
  /// In en, this message translates to:
  /// **'Confirm you understand before continuing.'**
  String get plaintextAcknowledgeRequired;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @masterPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Master password'**
  String get masterPasswordLabel;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'de',
    'en',
    'es',
    'fa',
    'fr',
    'hi',
    'id',
    'ja',
    'ko',
    'pt',
    'ru',
    'tr',
    'vi',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return SAr();
    case 'de':
      return SDe();
    case 'en':
      return SEn();
    case 'es':
      return SEs();
    case 'fa':
      return SFa();
    case 'fr':
      return SFr();
    case 'hi':
      return SHi();
    case 'id':
      return SId();
    case 'ja':
      return SJa();
    case 'ko':
      return SKo();
    case 'pt':
      return SPt();
    case 'ru':
      return SRu();
    case 'tr':
      return STr();
    case 'vi':
      return SVi();
    case 'zh':
      return SZh();
  }

  throw FlutterError(
    'S.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
