// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class SDe extends S {
  SDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get close => 'Schließen';

  @override
  String get delete => 'Löschen';

  @override
  String get save => 'Speichern';

  @override
  String get connect => 'Verbinden';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get import_ => 'Importieren';

  @override
  String get export_ => 'Exportieren';

  @override
  String get rename => 'Umbenennen';

  @override
  String get create => 'Erstellen';

  @override
  String get back => 'Zurück';

  @override
  String get copy => 'Kopieren';

  @override
  String get paste => 'Einfügen';

  @override
  String get select => 'Auswählen';

  @override
  String get required => 'Erforderlich';

  @override
  String get settings => 'Einstellungen';

  @override
  String get terminal => 'Terminal';

  @override
  String get files => 'Dateien';

  @override
  String get transfer => 'Übertragung';

  @override
  String get open => 'Öffnen';

  @override
  String get search => 'Suchen...';

  @override
  String get filter => 'Filtern...';

  @override
  String get merge => 'Zusammenführen';

  @override
  String get replace => 'Ersetzen';

  @override
  String get reconnect => 'Neu verbinden';

  @override
  String get updateAvailable => 'Update verfügbar';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'Version $version ist verfügbar (aktuell: v$current).';
  }

  @override
  String get releaseNotes => 'Versionshinweise:';

  @override
  String get skipThisVersion => 'Diese Version überspringen';

  @override
  String get unskip => 'Nicht mehr überspringen';

  @override
  String get downloadAndInstall => 'Herunterladen & Installieren';

  @override
  String get openInBrowser => 'Im Browser öffnen';

  @override
  String get couldNotOpenBrowser =>
      'Browser konnte nicht geöffnet werden — URL in Zwischenablage kopiert';

  @override
  String get checkForUpdates => 'Nach Updates suchen';

  @override
  String get checkForUpdatesOnStartup => 'Beim Start nach Updates suchen';

  @override
  String get checking => 'Prüfe...';

  @override
  String get youreUpToDate => 'Alles auf dem neuesten Stand';

  @override
  String get updateCheckFailed => 'Update-Prüfung fehlgeschlagen';

  @override
  String get unknownError => 'Unbekannter Fehler';

  @override
  String downloadingPercent(int percent) {
    return 'Herunterladen... $percent%';
  }

  @override
  String get downloadComplete => 'Download abgeschlossen';

  @override
  String get installNow => 'Jetzt installieren';

  @override
  String get couldNotOpenInstaller =>
      'Installationsprogramm konnte nicht geöffnet werden';

  @override
  String versionAvailable(String version) {
    return 'Version $version verfügbar';
  }

  @override
  String currentVersion(String version) {
    return 'Aktuell: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'SSH-Schlüssel empfangen: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return '$count Sitzung(en) über QR importiert';
  }

  @override
  String importedSessions(int count) {
    return '$count Sitzung(en) importiert';
  }

  @override
  String importFailed(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String get sessions => 'Sitzungen';

  @override
  String get sessionsHeader => 'SITZUNGEN';

  @override
  String get savedSessions => 'Gespeicherte Sitzungen';

  @override
  String get activeConnections => 'Aktive Verbindungen';

  @override
  String get openTabs => 'Offene Tabs';

  @override
  String get noSavedSessions => 'Keine gespeicherten Sitzungen';

  @override
  String get addSession => 'Sitzung hinzufügen';

  @override
  String get noSessions => 'Keine Sitzungen';

  @override
  String get noSessionsToExport => 'Keine Sitzungen zum Exportieren';

  @override
  String nSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get selectAll => 'Alle auswählen';

  @override
  String get deselectAll => 'Alle abwählen';

  @override
  String get moveTo => 'Verschieben nach...';

  @override
  String get moveToFolder => 'In Ordner verschieben';

  @override
  String get rootFolder => '/ (Stammverzeichnis)';

  @override
  String get newFolder => 'Neuer Ordner';

  @override
  String get newConnection => 'Neue Verbindung';

  @override
  String get editConnection => 'Verbindung bearbeiten';

  @override
  String get duplicate => 'Duplizieren';

  @override
  String get deleteSession => 'Sitzung löschen';

  @override
  String get renameFolder => 'Ordner umbenennen';

  @override
  String get deleteFolder => 'Ordner löschen';

  @override
  String get deleteSelected => 'Ausgewählte löschen';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return '$parts löschen?\n\nDies kann nicht rückgängig gemacht werden.';
  }

  @override
  String nSessions(int count) {
    return '$count Sitzung(en)';
  }

  @override
  String nFolders(int count) {
    return '$count Ordner';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'Ordner \"$name\" löschen?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'Dadurch werden auch $count Sitzung(en) darin gelöscht.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return '\"$name\" löschen?';
  }

  @override
  String get connection => 'Verbindung';

  @override
  String get auth => 'Authentifizierung';

  @override
  String get options => 'Optionen';

  @override
  String get sessionName => 'Sitzungsname';

  @override
  String get hintMyServer => 'Mein Server';

  @override
  String get hostRequired => 'Host *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'Port';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'Benutzername *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'Passwort';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'Schlüssel-Passphrase';

  @override
  String get hintOptional => 'Optional';

  @override
  String get hidePemText => 'PEM-Text ausblenden';

  @override
  String get pastePemKeyText => 'PEM-Schlüsseltext einfügen';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'Noch keine zusätzlichen Optionen';

  @override
  String get saveAndConnect => 'Speichern & Verbinden';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst =>
      'Geben Sie zuerst eine Schlüsseldatei oder PEM-Text an';

  @override
  String get keyTextPem => 'Schlüsseltext (PEM)';

  @override
  String get selectKeyFile => 'Schlüsseldatei auswählen';

  @override
  String get clearKeyFile => 'Schlüsseldatei entfernen';

  @override
  String get authOrDivider => 'ODER';

  @override
  String get providePasswordOrKey =>
      'Geben Sie ein Passwort oder einen SSH-Schlüssel an';

  @override
  String get quickConnect => 'Schnellverbindung';

  @override
  String get scanQrCode => 'QR-Code scannen';

  @override
  String get qrGenerationFailed => 'QR-Erzeugung fehlgeschlagen';

  @override
  String get scanWithCameraApp =>
      'Scannen Sie mit einer Kamera-App auf einem Gerät,\nauf dem LetsFLUTssh installiert ist.';

  @override
  String get noPasswordsInQr =>
      'Keine Passwörter oder Schlüssel in diesem QR-Code';

  @override
  String get copyLink => 'Link kopieren';

  @override
  String get linkCopied => 'Link in Zwischenablage kopiert';

  @override
  String get hostKeyChanged => 'Host-Schlüssel geändert!';

  @override
  String get unknownHost => 'Unbekannter Host';

  @override
  String get hostKeyChangedWarning =>
      'WARNUNG: Der Host-Schlüssel für diesen Server hat sich geändert. Dies könnte auf einen Man-in-the-Middle-Angriff hinweisen, oder der Server wurde neu installiert.';

  @override
  String get unknownHostMessage =>
      'Die Authentizität dieses Hosts kann nicht festgestellt werden. Möchten Sie die Verbindung trotzdem fortsetzen?';

  @override
  String get host => 'Host';

  @override
  String get keyType => 'Schlüsseltyp';

  @override
  String get fingerprint => 'Fingerabdruck';

  @override
  String get fingerprintCopied => 'Fingerabdruck kopiert';

  @override
  String get copyFingerprint => 'Fingerabdruck kopieren';

  @override
  String get acceptAnyway => 'Trotzdem akzeptieren';

  @override
  String get accept => 'Akzeptieren';

  @override
  String get importData => 'Daten importieren';

  @override
  String get masterPassword => 'Master-Passwort';

  @override
  String get confirmPassword => 'Passwort bestätigen';

  @override
  String get importModeMergeDescription =>
      'Neue Sitzungen hinzufügen, vorhandene behalten';

  @override
  String get importModeReplaceDescription =>
      'Alle Sitzungen durch importierte ersetzen';

  @override
  String errorPrefix(String error) {
    return 'Fehler: $error';
  }

  @override
  String get folderName => 'Ordnername';

  @override
  String get newName => 'Neuer Name';

  @override
  String deleteItems(String names) {
    return '$names löschen?';
  }

  @override
  String deleteNItems(int count) {
    return '$count Elemente löschen';
  }

  @override
  String deletedItem(String name) {
    return '$name gelöscht';
  }

  @override
  String deletedNItems(int count) {
    return '$count Elemente gelöscht';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'Ordner konnte nicht erstellt werden: $error';
  }

  @override
  String failedToRename(String error) {
    return 'Umbenennung fehlgeschlagen: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return '$name konnte nicht gelöscht werden: $error';
  }

  @override
  String get editPath => 'Pfad bearbeiten';

  @override
  String get root => 'Stammverzeichnis';

  @override
  String get controllersNotInitialized => 'Controller nicht initialisiert';

  @override
  String get initializingSftp => 'SFTP wird initialisiert...';

  @override
  String get clearHistory => 'Verlauf löschen';

  @override
  String get noTransfersYet => 'Noch keine Übertragungen';

  @override
  String get duplicateTab => 'Tab duplizieren';

  @override
  String get duplicateTabShortcut => 'Tab duplizieren (Ctrl+\\)';

  @override
  String get copyDown => 'Nach unten kopieren';

  @override
  String get previous => 'Vorheriges';

  @override
  String get next => 'Nächstes';

  @override
  String get closeEsc => 'Schließen (Esc)';

  @override
  String get closeAll => 'Alle schließen';

  @override
  String get closeOthers => 'Andere schließen';

  @override
  String get closeTabsToTheLeft => 'Tabs links schließen';

  @override
  String get closeTabsToTheRight => 'Tabs rechts schließen';

  @override
  String get sortByName => 'Nach Name sortieren';

  @override
  String get sortByStatus => 'Nach Status sortieren';

  @override
  String get noActiveSession => 'Keine aktive Sitzung';

  @override
  String get createConnectionHint =>
      'Erstellen Sie eine neue Verbindung oder wählen Sie eine aus der Seitenleiste';

  @override
  String get hideSidebar => 'Seitenleiste ausblenden (Ctrl+B)';

  @override
  String get showSidebar => 'Seitenleiste einblenden (Ctrl+B)';

  @override
  String get language => 'Sprache';

  @override
  String get languageSystemDefault => 'Auto';

  @override
  String get theme => 'Thema';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeSystem => 'System';

  @override
  String get appearance => 'Darstellung';

  @override
  String get connectionSection => 'Verbindung';

  @override
  String get transfers => 'Übertragungen';

  @override
  String get data => 'Daten';

  @override
  String get logging => 'Protokollierung';

  @override
  String get updates => 'Updates';

  @override
  String get about => 'Über';

  @override
  String get resetToDefaults => 'Auf Standardwerte zurücksetzen';

  @override
  String get uiScale => 'UI-Skalierung';

  @override
  String get terminalFontSize => 'Terminal-Schriftgröße';

  @override
  String get scrollbackLines => 'Rücklaufzeilen';

  @override
  String get keepAliveInterval => 'Keep-Alive-Intervall (Sek.)';

  @override
  String get sshTimeout => 'SSH-Zeitüberschreitung (Sek.)';

  @override
  String get defaultPort => 'Standard-Port';

  @override
  String get parallelWorkers => 'Parallele Worker';

  @override
  String get maxHistory => 'Maximaler Verlauf';

  @override
  String get calculateFolderSizes => 'Ordnergrößen berechnen';

  @override
  String get exportData => 'Daten exportieren';

  @override
  String get exportDataSubtitle =>
      'Sitzungen, Konfiguration und Schlüssel in verschlüsselter .lfs-Datei speichern';

  @override
  String get importDataSubtitle => 'Daten aus .lfs-Datei laden';

  @override
  String get setMasterPasswordHint =>
      'Legen Sie ein Master-Passwort zum Verschlüsseln des Archivs fest.';

  @override
  String get passwordsDoNotMatch => 'Passwörter stimmen nicht überein';

  @override
  String exportedTo(String path) {
    return 'Exportiert nach: $path';
  }

  @override
  String exportFailed(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get pathToLfsFile => 'Pfad zur .lfs-Datei';

  @override
  String get hintLfsPath => '/pfad/zum/export.lfs';

  @override
  String get browse => 'Durchsuchen';

  @override
  String get shareViaQrCode => 'Per QR-Code teilen';

  @override
  String get shareViaQrSubtitle =>
      'Sitzungen als QR exportieren, um sie mit einem anderen Gerät zu scannen';

  @override
  String get dataLocation => 'Datenspeicherort';

  @override
  String get pathCopied => 'Pfad in Zwischenablage kopiert';

  @override
  String get urlCopied => 'URL in Zwischenablage kopiert';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — SSH/SFTP-Client';
  }

  @override
  String get sourceCode => 'Quellcode';

  @override
  String get enableLogging => 'Protokollierung aktivieren';

  @override
  String get logIsEmpty => 'Protokoll ist leer';

  @override
  String logExportedTo(String path) {
    return 'Protokoll exportiert nach: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Protokollexport fehlgeschlagen: $error';
  }

  @override
  String get logsCleared => 'Protokolle gelöscht';

  @override
  String get copiedToClipboard => 'In Zwischenablage kopiert';

  @override
  String get copyLog => 'Protokoll kopieren';

  @override
  String get exportLog => 'Protokoll exportieren';

  @override
  String get clearLogs => 'Protokolle löschen';

  @override
  String get local => 'Lokal';

  @override
  String get remote => 'Remote';

  @override
  String get pickFolder => 'Ordner auswählen';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get up => 'Nach oben';

  @override
  String get emptyDirectory => 'Leeres Verzeichnis';

  @override
  String get cancelSelection => 'Auswahl abbrechen';

  @override
  String get openSftpBrowser => 'SFTP-Browser öffnen';

  @override
  String get openSshTerminal => 'SSH-Terminal öffnen';

  @override
  String get noActiveFileBrowsers => 'Keine aktiven Dateibrowser';

  @override
  String get useSftpFromSessions => 'Verwenden Sie \"SFTP\" unter Sitzungen';

  @override
  String get anotherInstanceRunning =>
      'Eine weitere Instanz von LetsFLUTssh läuft bereits.';

  @override
  String importFailedShort(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String get saveLogAs => 'Protokoll speichern unter';

  @override
  String get chooseSaveLocation => 'Speicherort wählen';

  @override
  String get forward => 'Vorwärts';

  @override
  String get name => 'Name';

  @override
  String get size => 'Größe';

  @override
  String get modified => 'Geändert';

  @override
  String get mode => 'Modus';

  @override
  String get owner => 'Eigentümer';

  @override
  String get connectionError => 'Verbindungsfehler';

  @override
  String get resizeWindowToViewFiles =>
      'Fenstergröße ändern, um Dateien anzuzeigen';

  @override
  String get completed => 'Abgeschlossen';

  @override
  String get connected => 'Verbunden';

  @override
  String get disconnected => 'Getrennt';

  @override
  String get exit => 'Beenden';

  @override
  String get exitConfirmation => 'Aktive Sitzungen werden getrennt. Beenden?';

  @override
  String get hintFolderExample => 'z. B. Production';

  @override
  String get credentialsNotSet => 'Zugangsdaten nicht festgelegt';

  @override
  String get exportSessionsViaQr => 'Sitzungen per QR exportieren';

  @override
  String get qrNoCredentialsWarning =>
      'Passwörter und SSH-Schlüssel sind NICHT enthalten.\nImportierte Sitzungen müssen die Zugangsdaten nachträglich erhalten.';

  @override
  String get qrTooManyForSingleCode =>
      'Zu viele Sitzungen für einen einzelnen QR-Code. Reduzieren Sie die Auswahl oder nutzen Sie den .lfs-Export.';

  @override
  String get qrTooLarge =>
      'Zu groß — reduzieren Sie die Auswahl oder nutzen Sie den .lfs-Dateiexport.';

  @override
  String get exportAll => 'Alle exportieren';

  @override
  String get showQr => 'QR anzeigen';

  @override
  String get sort => 'Sortieren';

  @override
  String get resizePanelDivider => 'Panelteiler verschieben';

  @override
  String get youreRunningLatest => 'Sie verwenden die neueste Version';

  @override
  String get liveLog => 'Live-Log';

  @override
  String transferNItems(int count) {
    return '$count Elemente übertragen';
  }

  @override
  String get time => 'Zeit';

  @override
  String get failed => 'Fehlgeschlagen';

  @override
  String get errOperationNotPermitted => 'Operation nicht erlaubt';

  @override
  String get errNoSuchFileOrDirectory =>
      'Datei oder Verzeichnis nicht gefunden';

  @override
  String get errNoSuchProcess => 'Kein solcher Prozess';

  @override
  String get errIoError => 'E/A-Fehler';

  @override
  String get errBadFileDescriptor => 'Ungültiger Dateideskriptor';

  @override
  String get errResourceTemporarilyUnavailable =>
      'Ressource vorübergehend nicht verfügbar';

  @override
  String get errOutOfMemory => 'Nicht genügend Speicher';

  @override
  String get errPermissionDenied => 'Zugriff verweigert';

  @override
  String get errFileExists => 'Datei existiert bereits';

  @override
  String get errNotADirectory => 'Kein Verzeichnis';

  @override
  String get errIsADirectory => 'Ist ein Verzeichnis';

  @override
  String get errInvalidArgument => 'Ungültiges Argument';

  @override
  String get errTooManyOpenFiles => 'Zu viele offene Dateien';

  @override
  String get errNoSpaceLeftOnDevice => 'Kein Speicherplatz mehr auf dem Gerät';

  @override
  String get errReadOnlyFileSystem => 'Schreibgeschütztes Dateisystem';

  @override
  String get errBrokenPipe => 'Unterbrochene Pipe';

  @override
  String get errFileNameTooLong => 'Dateiname zu lang';

  @override
  String get errDirectoryNotEmpty => 'Verzeichnis nicht leer';

  @override
  String get errAddressAlreadyInUse => 'Adresse wird bereits verwendet';

  @override
  String get errCannotAssignAddress =>
      'Angeforderte Adresse kann nicht zugewiesen werden';

  @override
  String get errNetworkIsDown => 'Netzwerk ist ausgefallen';

  @override
  String get errNetworkIsUnreachable => 'Netzwerk ist nicht erreichbar';

  @override
  String get errConnectionResetByPeer =>
      'Verbindung von Gegenstelle zurückgesetzt';

  @override
  String get errConnectionTimedOut => 'Zeitüberschreitung der Verbindung';

  @override
  String get errConnectionRefused => 'Verbindung abgelehnt';

  @override
  String get errHostIsDown => 'Host ist nicht erreichbar';

  @override
  String get errNoRouteToHost => 'Keine Route zum Host';

  @override
  String get errConnectionAborted => 'Verbindung abgebrochen';

  @override
  String get errAlreadyConnected => 'Bereits verbunden';

  @override
  String get errNotConnected => 'Nicht verbunden';

  @override
  String errSshConnectFailed(String host, int port) {
    return 'Verbindung zu $host:$port fehlgeschlagen';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return 'Authentifizierung für $user@$host fehlgeschlagen';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return 'Verbindung zu $host:$port fehlgeschlagen';
  }

  @override
  String get errSshAuthAborted => 'Authentifizierung abgebrochen';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return 'Hostschlüssel für $host:$port abgelehnt — akzeptieren Sie den Hostschlüssel oder prüfen Sie known_hosts';
  }

  @override
  String get errSshOpenShellFailed => 'Shell konnte nicht geöffnet werden';

  @override
  String get errSshLoadKeyFileFailed =>
      'SSH-Schlüsseldatei konnte nicht geladen werden';

  @override
  String get errSshParseKeyFailed =>
      'PEM-Schlüsseldaten konnten nicht analysiert werden';

  @override
  String get errSshConnectionDisposed => 'Verbindung beendet';

  @override
  String get errSshNotConnected => 'Nicht verbunden';

  @override
  String get errConnectionFailed => 'Verbindung fehlgeschlagen';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'Zeitüberschreitung der Verbindung nach $seconds Sekunden';
  }

  @override
  String get errSessionClosed => 'Sitzung geschlossen';

  @override
  String errShellError(String error) {
    return 'Shell-Fehler: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'Wiederverbindung fehlgeschlagen: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'SFTP-Initialisierung fehlgeschlagen: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Download fehlgeschlagen: $error';
  }

  @override
  String get errDecryptionFailed =>
      'Zugangsdaten konnten nicht entschlüsselt werden. Die Schlüsseldatei ist möglicherweise beschädigt.';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'Anmeldung';

  @override
  String get protocol => 'Protokoll';

  @override
  String get typeLabel => 'Typ';

  @override
  String get folder => 'Ordner';

  @override
  String nSubitems(int count) {
    return '$count Element(e)';
  }

  @override
  String get subitems => 'Elemente';

  @override
  String get storagePermissionRequired =>
      'Speicherberechtigung erforderlich, um lokale Dateien zu durchsuchen';

  @override
  String get grantPermission => 'Berechtigung erteilen';

  @override
  String get storagePermissionLimited =>
      'Eingeschränkter Zugriff — erteilen Sie die volle Speicherberechtigung für alle Dateien';

  @override
  String progressConnecting(String host, int port) {
    return 'Verbindung zu $host:$port';
  }

  @override
  String get progressVerifyingHostKey => 'Hostschlüssel wird überprüft';

  @override
  String progressAuthenticating(String user) {
    return 'Authentifizierung als $user';
  }

  @override
  String get progressOpeningShell => 'Shell wird geöffnet';

  @override
  String get progressOpeningSftp => 'SFTP-Kanal wird geöffnet';

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
  String get maximize => 'Maximieren';

  @override
  String get restore => 'Wiederherstellen';

  @override
  String get duplicateDownShortcut => 'Nach unten duplizieren (Ctrl+Shift+\\)';

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
}
