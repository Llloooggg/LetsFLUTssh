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
  String get infoDialogProtectsHeader => 'Schützt vor';

  @override
  String get infoDialogDoesNotProtectHeader => 'Schützt nicht vor';

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
  String get cut => 'Ausschneiden';

  @override
  String get paste => 'Einfügen';

  @override
  String get select => 'Auswählen';

  @override
  String get copyModeTapToStart => 'Tippen, um Auswahlbeginn zu markieren';

  @override
  String get copyModeExtending => 'Ziehen, um Auswahl zu erweitern';

  @override
  String get required => 'Erforderlich';

  @override
  String get settings => 'Einstellungen';

  @override
  String get appSettings => 'App-Einstellungen';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nein';

  @override
  String get importWhatToImport => 'Was importieren:';

  @override
  String get exportWhatToExport => 'Was exportieren:';

  @override
  String get enterMasterPasswordPrompt => 'Master-Passwort eingeben:';

  @override
  String get nextStep => 'Weiter';

  @override
  String get includePasswords => 'Sitzungs-Passwörter';

  @override
  String get embeddedKeys => 'Eingebettete Schlüssel';

  @override
  String get managerKeys => 'Schlüssel aus dem Manager';

  @override
  String get managerKeysMayBeLarge =>
      'Manager-Schlüssel können die QR-Größe überschreiten';

  @override
  String get qrPasswordWarning =>
      'SSH-Schlüssel sind beim Export standardmäßig deaktiviert.';

  @override
  String get sshKeysMayBeLarge => 'Schlüssel können die QR-Größe überschreiten';

  @override
  String exportTotalSize(String size) {
    return 'Gesamtgröße: $size';
  }

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
  String get noResults => 'Keine Ergebnisse';

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
  String get checkNow => 'Jetzt prüfen';

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
  String get updateVerifying => 'Wird überprüft…';

  @override
  String get downloadComplete => 'Download abgeschlossen';

  @override
  String get installNow => 'Jetzt installieren';

  @override
  String get openReleasePage => 'Release-Seite öffnen';

  @override
  String get couldNotOpenInstaller =>
      'Installationsprogramm konnte nicht geöffnet werden';

  @override
  String get installerFailedOpenedReleasePage =>
      'Installationsprogramm konnte nicht gestartet werden; Release-Seite im Browser geöffnet';

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
  String importedSessions(int count) {
    return '$count Sitzung(en) importiert';
  }

  @override
  String importFailed(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Verknüpfungen verworfen (Ziele fehlen)',
      one: '$count Verknüpfung verworfen (Ziel fehlt)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count beschädigte Sitzungen übersprungen',
      one: '$count beschädigte Sitzung übersprungen',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'Sitzungen';

  @override
  String get emptyFolders => 'Leere Ordner';

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
  String get emptyFolder => 'Leerer Ordner';

  @override
  String get qrGenerationFailed => 'QR-Erzeugung fehlgeschlagen';

  @override
  String get scanWithCameraApp =>
      'Scannen Sie mit einer Kamera-App auf einem Gerät,\nauf dem LetsFLUTssh installiert ist.';

  @override
  String get noPasswordsInQr =>
      'Keine Passwörter oder Schlüssel in diesem QR-Code';

  @override
  String get qrContainsCredentialsWarning =>
      'Dieser QR-Code enthält Zugangsdaten. Halten Sie den Bildschirm privat.';

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
  String get clearHistory => 'Verlauf löschen';

  @override
  String get noTransfersYet => 'Noch keine Übertragungen';

  @override
  String get duplicateTab => 'Tab duplizieren';

  @override
  String get duplicateTabShortcut => 'Tab duplizieren (Ctrl+\\)';

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
  String get scrollbackLines => 'Scrollback-Zeilen';

  @override
  String get keepAliveInterval => 'Keep-Alive-Intervall (Sek.)';

  @override
  String get sshTimeout => 'SSH-Timeout (Sek.)';

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
  String sshConfigPreviewHostsFound(int count) {
    return '$count Host(s) gefunden';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'Keine importierbaren Hosts in dieser Datei gefunden.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'Schlüsseldateien konnten nicht gelesen werden für: $hosts. Diese Hosts werden ohne Anmeldedaten importiert.';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'Archiv exportieren';

  @override
  String get exportArchiveSubtitle =>
      'Sitzungen, Konfiguration und Schlüssel in verschlüsselter .lfs-Datei speichern';

  @override
  String get exportQrCode => 'QR-Code exportieren';

  @override
  String get exportQrCodeSubtitle =>
      'Ausgewählte Sitzungen und Schlüssel per QR-Code teilen';

  @override
  String get importArchive => 'Archiv importieren';

  @override
  String get importArchiveSubtitle => 'Daten aus .lfs-Datei laden';

  @override
  String get importFromSshDir => 'Aus ~/.ssh importieren';

  @override
  String get importFromSshDirSubtitle =>
      'Hosts aus der Konfiguration und/oder private Schlüssel aus ~/.ssh auswählen';

  @override
  String get sshDirImportHostsSection => 'Hosts aus der Konfiguration';

  @override
  String get sshDirImportKeysSection => 'Schlüssel in ~/.ssh';

  @override
  String importSshKeysFound(int count) {
    return '$count Schlüssel gefunden — auswählen, welche importiert werden sollen';
  }

  @override
  String get importSshKeysNoneFound =>
      'Keine privaten Schlüssel in ~/.ssh gefunden.';

  @override
  String get sshKeyAlreadyImported => 'bereits im Speicher';

  @override
  String get setMasterPasswordHint =>
      'Legen Sie ein Master-Passwort zum Verschlüsseln des Archivs fest.';

  @override
  String get passwordsDoNotMatch => 'Passwörter stimmen nicht überein';

  @override
  String get passwordStrengthWeak => 'Schwach';

  @override
  String get passwordStrengthModerate => 'Mittel';

  @override
  String get passwordStrengthStrong => 'Stark';

  @override
  String get passwordStrengthVeryStrong => 'Sehr stark';

  @override
  String get tierPlaintextLabel => 'Klartext';

  @override
  String get tierPlaintextSubtitle =>
      'Keine Verschlüsselung — nur Dateiberechtigungen';

  @override
  String get tierKeychainLabel => 'Schlüsselbund';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'Schlüssel liegt in $keychain — Auto-Entsperrung beim Start';
  }

  @override
  String get tierKeychainUnavailable =>
      'OS-Schlüsselbund auf dieser Installation nicht verfügbar.';

  @override
  String get tierHardwareLabel => 'Hardware';

  @override
  String get tierParanoidLabel => 'Master-Passwort (Paranoid)';

  @override
  String get tierHardwareUnavailable =>
      'Hardware-Tresor in dieser Installation nicht verfügbar.';

  @override
  String get pinLabel => 'Passwort';

  @override
  String get l2UnlockTitle => 'Passwort erforderlich';

  @override
  String get l2UnlockHint =>
      'Geben Sie Ihr kurzes Passwort ein, um fortzufahren';

  @override
  String get l2WrongPassword => 'Falsches Passwort';

  @override
  String get l3UnlockTitle => 'Passwort eingeben';

  @override
  String get l3UnlockHint => 'Passwort entsperrt den hardwaregebundenen Tresor';

  @override
  String get l3WrongPin => 'Falsches Passwort';

  @override
  String tierCooldownHint(int seconds) {
    return 'Erneut versuchen in $seconds s';
  }

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
  String get dataLocation => 'Datenspeicherort';

  @override
  String get dataStorageSection => 'Speicher';

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
      'Zu groß — wählen Sie einige Elemente ab oder nutzen Sie den .lfs-Dateiexport.';

  @override
  String get exportAll => 'Alle exportieren';

  @override
  String get showQr => 'QR anzeigen';

  @override
  String get sort => 'Sortieren';

  @override
  String get resizePanelDivider => 'Trennlinie verschieben';

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
  String get errConnectionTimedOut => 'Verbindungs-Timeout';

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
      'PEM-Schlüsseldaten konnten nicht geparst werden';

  @override
  String get errSshConnectionDisposed => 'Verbindung beendet';

  @override
  String get errSshNotConnected => 'Nicht verbunden';

  @override
  String get errConnectionFailed => 'Verbindung fehlgeschlagen';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'Verbindungs-Timeout nach $seconds Sekunden';
  }

  @override
  String get errSessionClosed => 'Sitzung geschlossen';

  @override
  String errSftpInitFailed(String error) {
    return 'SFTP-Initialisierung fehlgeschlagen: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Download fehlgeschlagen: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'Die System-Ordnerauswahl ist nicht verfügbar. Versuchen Sie einen anderen Speicherort oder überprüfen Sie die Speicherberechtigungen der App.';

  @override
  String get biometricUnlockPrompt => 'LetsFLUTssh entsperren';

  @override
  String get biometricUnlockTitle => 'Mit Biometrie entsperren';

  @override
  String get biometricUnlockSubtitle =>
      'Passwort nicht eingeben — mit dem Biometriesensor des Geräts entsperren.';

  @override
  String get biometricEnableFailed =>
      'Biometrische Entsperrung konnte nicht aktiviert werden.';

  @override
  String get biometricUnlockFailed =>
      'Biometrische Entsperrung fehlgeschlagen. Geben Sie Ihr Masterpasswort ein.';

  @override
  String get biometricUnlockCancelled =>
      'Biometrische Entsperrung abgebrochen.';

  @override
  String get biometricNotEnrolled =>
      'Auf diesem Gerät sind keine biometrischen Daten registriert.';

  @override
  String get biometricSensorNotAvailable =>
      'Dieses Gerät verfügt über keinen biometrischen Sensor.';

  @override
  String get biometricSystemServiceMissing =>
      'Fingerabdruckdienst (fprintd) ist nicht installiert. Siehe README → Installation.';

  @override
  String get currentPasswordIncorrect => 'Aktuelles Passwort ist falsch';

  @override
  String get wrongPassword => 'Falsches Passwort';

  @override
  String get lockScreenTitle => 'LetsFLUTssh ist gesperrt';

  @override
  String get lockScreenSubtitle =>
      'Geben Sie das Master-Passwort ein oder verwenden Sie Biometrie, um fortzufahren.';

  @override
  String get unlock => 'Entsperren';

  @override
  String get autoLockTitle => 'Automatisch sperren bei Inaktivität';

  @override
  String get autoLockSubtitle =>
      'Sperrt die Oberfläche nach dieser Inaktivitätsdauer. Der Datenbankschlüssel wird bei jeder Sperre gelöscht und der verschlüsselte Speicher geschlossen; aktive Sitzungen bleiben dank eines Sitzungs-Anmeldedaten-Caches verbunden, der beim Schließen der Sitzung geleert wird.';

  @override
  String get autoLockOff => 'Aus';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes Minuten',
      one: '$minutes Minute',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'Aktualisierung abgelehnt: Die heruntergeladenen Dateien sind nicht mit dem in der App verankerten Release-Schlüssel signiert. Dies kann bedeuten, dass der Download unterwegs manipuliert wurde, oder die aktuelle Version ist nicht für diese Installation bestimmt. NICHT installieren — stattdessen manuell von der offiziellen Releases-Seite neu installieren.';

  @override
  String get errReleaseManifestUnavailable =>
      'Release-Manifest nicht erreichbar. Wahrscheinlich ein Netzwerkproblem, oder der Release wird gerade veröffentlicht. In ein paar Minuten erneut versuchen.';

  @override
  String get updateSecurityWarningTitle => 'Update-Überprüfung fehlgeschlagen';

  @override
  String get updateReinstallAction => 'Releases-Seite öffnen';

  @override
  String get errLfsNotArchive =>
      'Die ausgewählte Datei ist kein LetsFLUTssh-Archiv.';

  @override
  String get errLfsDecryptFailed =>
      'Falsches Master-Passwort oder beschädigtes .lfs-Archiv';

  @override
  String get errLfsArchiveTruncated =>
      'Archiv ist unvollständig. Erneut herunterladen oder vom Originalgerät neu exportieren.';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'Archiv ist zu groß ($sizeMb MB). Das Limit beträgt $limitMb MB – Abbruch vor der Entschlüsselung zum Schutz des Speichers.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'known_hosts-Eintrag ist zu groß ($sizeMb MB). Das Limit beträgt $limitMb MB – abgebrochen, damit der Import reaktionsfähig bleibt.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'Import fehlgeschlagen – Ihre Daten wurden auf den Stand vor dem Import zurückgesetzt. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'Archiv verwendet Schema v$found, aber dieser Build unterstützt nur bis v$supported. Aktualisieren Sie die App, um es zu importieren.';
  }

  @override
  String get progressReadingArchive => 'Archiv wird gelesen…';

  @override
  String get progressDecrypting => 'Entschlüsseln…';

  @override
  String get progressParsingArchive => 'Archiv wird analysiert…';

  @override
  String get progressImportingSessions => 'Sitzungen werden importiert';

  @override
  String get progressImportingFolders => 'Ordner werden importiert';

  @override
  String get progressImportingManagerKeys => 'SSH-Schlüssel werden importiert';

  @override
  String get progressImportingTags => 'Tags werden importiert';

  @override
  String get progressImportingSnippets => 'Snippets werden importiert';

  @override
  String get progressApplyingConfig => 'Konfiguration wird angewendet…';

  @override
  String get progressImportingKnownHosts => 'known_hosts werden importiert…';

  @override
  String get progressCollectingData => 'Daten werden gesammelt…';

  @override
  String get progressEncrypting => 'Verschlüsseln…';

  @override
  String get progressWritingArchive => 'Archiv wird geschrieben…';

  @override
  String get progressWorking => 'Wird bearbeitet…';

  @override
  String get importFromLink => 'Per QR-Link importieren';

  @override
  String get importFromLinkSubtitle =>
      'Einen von einem anderen Gerät kopierten letsflutssh:// Deep-Link einfügen';

  @override
  String get pasteImportLinkTitle => 'Import-Link einfügen';

  @override
  String get pasteImportLinkDescription =>
      'Füge den auf einem anderen Gerät erzeugten letsflutssh://import?d=… Link (oder die rohe Payload) ein. Keine Kamera erforderlich.';

  @override
  String get pasteFromClipboard => 'Aus Zwischenablage einfügen';

  @override
  String get invalidImportLink =>
      'Der Link enthält keine gültige LetsFLUTssh-Payload';

  @override
  String get importAction => 'Importieren';

  @override
  String get saveSessionToAssignTags =>
      'Sitzung zuerst speichern, um Tags zuzuweisen';

  @override
  String get noTagsAssigned => 'Keine Tags zugewiesen';

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
  String get transfersLabel => 'Übertragungen:';

  @override
  String transferCountActive(int count) {
    return '$count aktiv';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count in Warteschlange';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count im Verlauf';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'Erstellt: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'Gestartet: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'Beendet: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'Dauer: $duration';
  }

  @override
  String get transferStatusQueued => 'In Warteschlange';

  @override
  String get transferStartingUpload => 'Upload wird gestartet...';

  @override
  String get transferStartingDownload => 'Download wird gestartet...';

  @override
  String get transferCopying => 'Wird kopiert...';

  @override
  String get transferDone => 'Fertig';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total Dateien';
  }

  @override
  String get fileConflictTitle => 'Datei existiert bereits';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" existiert bereits in $targetDir. Was möchten Sie tun?';
  }

  @override
  String get fileConflictSkip => 'Überspringen';

  @override
  String get fileConflictKeepBoth => 'Beide behalten';

  @override
  String get fileConflictReplace => 'Ersetzen';

  @override
  String get fileConflictApplyAll => 'Auf alle verbleibenden anwenden';

  @override
  String get folderNameLabel => 'ORDNERNAME';

  @override
  String folderAlreadyExists(String name) {
    return 'Ordner \"$name\" existiert bereits';
  }

  @override
  String get dropKeyFileHere => 'Schlüsseldatei hierher ziehen';

  @override
  String get sessionNoCredentials =>
      'Sitzung hat keine Anmeldedaten — bearbeiten Sie sie, um ein Passwort oder einen Schlüssel hinzuzufügen';

  @override
  String dragItemCount(int count) {
    return '$count Elemente';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'Alle auswählen ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'Größe: $size KB / $max KB max.';
  }

  @override
  String get noActiveTerminals => 'Keine aktiven Terminals';

  @override
  String get connectFromSessionsTab => 'Verbindung über Sitzungen herstellen';

  @override
  String fileNotFound(String path) {
    return 'Datei nicht gefunden: $path';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count Elemente, $size';
  }

  @override
  String get maximize => 'Maximieren';

  @override
  String get restore => 'Wiederherstellen';

  @override
  String get duplicateDownShortcut => 'Nach unten duplizieren (Ctrl+Shift+\\)';

  @override
  String get security => 'Sicherheit';

  @override
  String get knownHosts => 'Bekannte Hosts';

  @override
  String get knownHostsSubtitle =>
      'Verwaltung vertrauenswürdiger SSH-Server-Fingerabdrücke';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bekannte Hosts',
      one: '1 bekannter Host',
      zero: 'Keine bekannten Hosts',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'Keine bekannten Hosts. Verbinden Sie sich mit einem Server, um einen hinzuzufügen.';

  @override
  String get removeHost => 'Host entfernen';

  @override
  String removeHostConfirm(String host) {
    return '$host aus bekannten Hosts entfernen? Beim nächsten Verbinden wird der Schlüssel erneut überprüft.';
  }

  @override
  String get clearAllKnownHosts => 'Alle bekannten Hosts löschen';

  @override
  String get clearAllKnownHostsConfirm =>
      'Alle bekannten Hosts entfernen? Jeder Serverschlüssel muss erneut bestätigt werden.';

  @override
  String get clearedAllHosts => 'Alle bekannten Hosts gelöscht';

  @override
  String removedHost(String host) {
    return '$host entfernt';
  }

  @override
  String get tools => 'Werkzeuge';

  @override
  String get sshKeys => 'SSH-Schlüssel';

  @override
  String get sshKeysSubtitle =>
      'Verwaltung von SSH-Schlüsselpaaren zur Authentifizierung';

  @override
  String get noKeys =>
      'Keine SSH-Schlüssel. Importieren oder generieren Sie einen.';

  @override
  String get generateKey => 'Schlüssel generieren';

  @override
  String get addKey => 'Schlüssel hinzufügen';

  @override
  String get filePickerUnavailable =>
      'Dateiauswahl auf diesem System nicht verfügbar';

  @override
  String get importKey => 'Schlüssel importieren';

  @override
  String get keyLabel => 'Schlüsselname';

  @override
  String get keyLabelHint => 'z.B. Arbeitsserver, GitHub';

  @override
  String get selectKeyType => 'Schlüsseltyp';

  @override
  String get generating => 'Wird generiert...';

  @override
  String keyGenerated(String label) {
    return 'Schlüssel generiert: $label';
  }

  @override
  String keyImported(String label) {
    return 'Schlüssel importiert: $label';
  }

  @override
  String get deleteKey => 'Schlüssel löschen';

  @override
  String deleteKeyConfirm(String label) {
    return 'Schlüssel \"$label\" löschen? Sitzungen, die ihn verwenden, verlieren den Zugang.';
  }

  @override
  String keyDeleted(String label) {
    return 'Schlüssel gelöscht: $label';
  }

  @override
  String get publicKey => 'Öffentlicher Schlüssel';

  @override
  String get publicKeyCopied =>
      'Öffentlicher Schlüssel in Zwischenablage kopiert';

  @override
  String get pastePrivateKey => 'Privaten Schlüssel einfügen (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Ungültige PEM-Schlüsseldaten';

  @override
  String get selectFromKeyStore => 'Aus Schlüsselspeicher auswählen';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Schlüssel',
      one: '1 Schlüssel',
      zero: 'Keine Schlüssel',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'Generiert';

  @override
  String get passphraseRequired => 'Passphrase erforderlich';

  @override
  String passphrasePrompt(String host) {
    return 'Der SSH-Schlüssel für $host ist verschlüsselt. Geben Sie die Passphrase zum Entsperren ein.';
  }

  @override
  String get passphraseWrong =>
      'Falsche Passphrase. Bitte versuchen Sie es erneut.';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get rememberPassphrase => 'Für diese Sitzung merken';

  @override
  String get enterMasterPassword =>
      'Geben Sie das Master-Passwort ein, um Ihre gespeicherten Anmeldedaten zu entsperren.';

  @override
  String get wrongMasterPassword =>
      'Falsches Passwort. Bitte versuchen Sie es erneut.';

  @override
  String get newPassword => 'Neues Passwort';

  @override
  String get currentPassword => 'Aktuelles Passwort';

  @override
  String get forgotPassword => 'Passwort vergessen?';

  @override
  String get credentialsReset =>
      'Alle gespeicherten Anmeldedaten wurden gelöscht';

  @override
  String get migrationToast => 'Speicher auf aktuelles Format aktualisiert';

  @override
  String get dbCorruptTitle => 'Datenbank kann nicht geöffnet werden';

  @override
  String get dbCorruptBody =>
      'Die Daten auf der Festplatte lassen sich nicht öffnen. Probiere andere Anmeldedaten oder setze zurück, um neu zu starten.';

  @override
  String get dbCorruptWarning =>
      'Zurücksetzen löscht die verschlüsselte Datenbank und alle sicherheitsrelevanten Dateien dauerhaft. Keine Daten werden wiederhergestellt.';

  @override
  String get dbCorruptTryOther => 'Andere Anmeldedaten versuchen';

  @override
  String get dbCorruptResetContinue => 'Zurücksetzen & neu einrichten';

  @override
  String get dbCorruptExit => 'LetsFLUTssh beenden';

  @override
  String get tierResetTitle => 'Sicherheits-Reset erforderlich';

  @override
  String get tierResetBody =>
      'Diese Installation enthält Sicherheitsdaten aus einer älteren Version von LetsFLUTssh, die ein anderes Stufenmodell verwendete. Das neue Modell ist eine inkompatible Änderung — es gibt keinen automatischen Migrationspfad. Um fortzufahren, müssen alle gespeicherten Sitzungen, Anmeldedaten, SSH-Schlüssel und bekannten Hosts dieser Installation gelöscht und der Ersteinrichtungsassistent neu ausgeführt werden.';

  @override
  String get tierResetWarning =>
      'Mit „Zurücksetzen & Neu einrichten“ werden die verschlüsselte Datenbank und alle sicherheitsrelevanten Dateien dauerhaft gelöscht. Wenn Sie Ihre Daten wiederherstellen müssen, beenden Sie die App jetzt und installieren Sie die vorherige Version von LetsFLUTssh erneut, um zunächst zu exportieren.';

  @override
  String get tierResetResetContinue => 'Zurücksetzen & Neu einrichten';

  @override
  String get tierResetExit => 'LetsFLUTssh beenden';

  @override
  String get derivingKey => 'Verschlüsselungsschlüssel wird abgeleitet...';

  @override
  String get securitySetupTitle => 'Sicherheitseinrichtung';

  @override
  String get keychainAvailable => 'Verfügbar';

  @override
  String get changeSecurityTierConfirm =>
      'Datenbank wird mit der neuen Stufe neu verschlüsselt. Vorgang nicht unterbrechen — App bis zum Abschluss geöffnet halten.';

  @override
  String get changeSecurityTierDone => 'Sicherheitsstufe geändert';

  @override
  String get changeSecurityTierFailed =>
      'Sicherheitsstufe konnte nicht geändert werden';

  @override
  String get firstLaunchSecurityTitle => 'Sicherer Speicher aktiviert';

  @override
  String get firstLaunchSecurityBody =>
      'Deine Daten sind mit einem Schlüssel im Schlüsselbund des Betriebssystems verschlüsselt. Die Entsperrung erfolgt auf diesem Gerät automatisch.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'Auf diesem Gerät ist hardwaregestützter Speicher verfügbar. Wechsle unter Einstellungen → Sicherheit, um TPM / Secure Enclave zu nutzen.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'Hardwaregestützter Speicher auf diesem Gerät nicht verfügbar.';

  @override
  String get firstLaunchSecurityOpenSettings => 'Einstellungen öffnen';

  @override
  String get wizardReducedBanner =>
      'Der Schlüsselbund des Betriebssystems ist bei dieser Installation nicht erreichbar. Wähle zwischen keiner Verschlüsselung (T0) und einem Master-Passwort (Paranoid). Installiere gnome-keyring, kwallet oder einen anderen libsecret-Anbieter, um die Keychain-Stufe zu aktivieren.';

  @override
  String get tierBlockProtectsEmpty => 'Auf dieser Stufe nichts.';

  @override
  String get tierBlockDoesNotProtectEmpty => 'Keine ungedeckten Bedrohungen.';

  @override
  String get tierBadgeCurrent => 'Aktuell';

  @override
  String get securitySetupEnable => 'Aktivieren';

  @override
  String get securitySetupApply => 'Übernehmen';

  @override
  String get hwProbeLinuxDeviceMissing =>
      'Kein TPM unter /dev/tpmrm0 gefunden. Aktiviere fTPM / PTT im BIOS, falls unterstützt; sonst ist die Hardware-Stufe auf diesem Gerät nicht verfügbar.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools ist nicht installiert. Führe `sudo apt install tpm2-tools` (oder das Äquivalent deiner Distribution) aus, um die Hardware-Stufe zu aktivieren.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'Die Hardware-Stufen-Prüfung ist fehlgeschlagen. Prüfe Berechtigungen auf /dev/tpmrm0 und udev-Regeln — Details im Log.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'Kein TPM 2.0 erkannt. Aktiviere fTPM / PTT in der UEFI-Firmware, oder akzeptiere dass die Hardware-Stufe auf diesem Gerät nicht verfügbar ist — die App fällt auf den software-gestützten Anmeldedatenspeicher zurück.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Weder Microsoft Platform Crypto Provider noch Software Key Storage Provider sind erreichbar — wahrscheinlich ein beschädigtes Windows-Krypto-Subsystem oder eine Gruppenrichtlinie, die CNG blockiert. Prüfe Ereignisanzeige → Anwendungs- und Dienstprotokolle.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'Dieser Mac hat keine Secure Enclave (Intel-Mac vor 2017 ohne T1 / T2-Sicherheitschip). Die Hardware-Stufe ist nicht verfügbar; verwende stattdessen das Master-Passwort.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'Auf diesem Mac ist kein Anmeldepasswort festgelegt. Secure-Enclave-Schlüsselerstellung erfordert eines — setze ein Anmeldepasswort in Systemeinstellungen → Touch ID & Passwort (oder Anmeldepasswort).';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave hat die Signaturidentität der App abgelehnt (-34018). Führe das mitgelieferte Skript `macos-resign.sh` aus dem Release aus, um diesem Build eine stabile selbstsignierte Identität zu geben, und starte die App neu.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'Kein Gerätecode festgelegt. Secure-Enclave-Schlüsselerstellung erfordert einen — setze einen Code in Einstellungen → Face ID & Code (oder Touch ID & Code).';

  @override
  String get hwProbeIosSimulator =>
      'Ausführung im iOS-Simulator, der keine Secure Enclave hat. Die Hardware-Stufe ist nur auf physischen iOS-Geräten verfügbar.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'Für die Hardware-Stufe ist Android 9 oder neuer erforderlich (StrongBox und per-Key-Enrolment-Invalidierung sind auf älteren Versionen nicht zuverlässig).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'Dieses Gerät hat keine Biometrie-Hardware (Fingerabdruck oder Gesicht). Verwende stattdessen das Master-Passwort.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'Keine Biometrie registriert. Füge einen Fingerabdruck oder Gesicht in Einstellungen → Sicherheit & Datenschutz → Biometrie hinzu, dann aktiviere die Hardware-Stufe erneut.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'Biometrie-Hardware ist vorübergehend unbrauchbar (Sperre nach fehlgeschlagenen Versuchen oder ausstehendes Sicherheitsupdate). Versuche es in ein paar Minuten erneut.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'Der Android-Keystore hat das Erstellen eines Hardware-Schlüssels für diese Geräteversion abgelehnt (StrongBox nicht verfügbar, Custom-ROM oder Treiberfehler). Die Hardware-Stufe ist nicht verfügbar.';

  @override
  String get securityRecheck => 'Stufen-Unterstützung erneut prüfen';

  @override
  String get securityRecheckUpdated =>
      'Stufen-Unterstützung aktualisiert — siehe Karten oben';

  @override
  String get securityRecheckUnchanged => 'Stufen-Unterstützung unverändert';

  @override
  String get securityMacosEnableSecureTiers =>
      'Sichere Stufen auf diesem Mac freischalten';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'App mit einem persönlichen Zertifikat signieren, damit Schlüsselbund (T1) und Secure Enclave (T2) Updates überstehen';

  @override
  String get securityMacosEnableSecureTiersPrompt =>
      'macOS fragt einmalig nach Ihrem Passwort';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'Sichere Stufen freigeschaltet — T1 und T2 sind verfügbar';

  @override
  String get securityMacosEnableSecureTiersFailed =>
      'Freischalten der sicheren Stufen fehlgeschlagen';

  @override
  String get securityMacosOfferTitle =>
      'Schlüsselbund + Secure Enclave aktivieren?';

  @override
  String get securityMacosOfferBody =>
      'macOS bindet verschlüsselten Speicher an die Signier-Identität der App. Ohne stabiles Zertifikat verweigern Schlüsselbund (T1) und Secure Enclave (T2) den Zugriff. Wir können ein persönliches, selbstsigniertes Zertifikat erstellen und die App damit neu signieren — Updates funktionieren weiter und Ihre Geheimnisse überdauern Versionen. macOS fragt einmal nach Ihrem Anmeldepasswort, um dem neuen Zertifikat zu vertrauen.';

  @override
  String get securityMacosOfferAccept => 'Aktivieren';

  @override
  String get securityMacosOfferDecline =>
      'Überspringen — T0 oder Paranoid wählen';

  @override
  String get securityMacosRemoveIdentity => 'Signier-Identität entfernen';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      'Löscht das persönliche Zertifikat. T1 / T2-Daten sind daran gebunden — zuerst auf T0 oder Paranoid umstellen, dann entfernen.';

  @override
  String get securityMacosRemoveIdentityConfirmTitle =>
      'Signier-Identität entfernen?';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'Löscht das persönliche Zertifikat aus dem Anmelde-Schlüsselbund. T1 / T2 gespeicherte Geheimnisse werden unlesbar. Der Wizard öffnet sich, damit Sie vor dem Entfernen auf T0 (Klartext) oder Paranoid (Master-Passwort) migrieren.';

  @override
  String get securityMacosRemoveIdentitySuccess => 'Signier-Identität entfernt';

  @override
  String get securityMacosRemoveIdentityFailed =>
      'Signier-Identität konnte nicht entfernt werden';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus läuft, aber kein Secret-Service-Daemon ist aktiv. Installiere gnome-keyring (`sudo apt install gnome-keyring`) oder KWalletManager und stelle sicher, dass es beim Anmelden startet.';

  @override
  String get keyringProbeFailed =>
      'Der OS-Schlüsselbund ist auf diesem Gerät nicht erreichbar. Plattformspezifischer Fehler siehe Log; die App fällt auf das Master-Passwort zurück.';

  @override
  String get snippets => 'Snippets';

  @override
  String get snippetsSubtitle => 'Wiederverwendbare Befehls-Snippets verwalten';

  @override
  String get noSnippets => 'Noch keine Snippets';

  @override
  String get addSnippet => 'Snippet hinzufügen';

  @override
  String get editSnippet => 'Snippet bearbeiten';

  @override
  String get deleteSnippet => 'Snippet löschen';

  @override
  String deleteSnippetConfirm(String title) {
    return 'Snippet „$title“ löschen?';
  }

  @override
  String get snippetTitle => 'Titel';

  @override
  String get snippetTitleHint => 'z. B. Deploy, Dienst neu starten';

  @override
  String get snippetCommand => 'Befehl';

  @override
  String get snippetCommandHint => 'z. B. sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'Beschreibung (optional)';

  @override
  String get snippetDescriptionHint => 'Was macht dieser Befehl?';

  @override
  String get snippetSaved => 'Snippet gespeichert';

  @override
  String snippetDeleted(String title) {
    return 'Snippet „$title“ gelöscht';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Snippets',
      one: '1 Snippet',
      zero: 'Keine Snippets',
    );
    return '$_temp0';
  }

  @override
  String get pinToSession => 'An diese Sitzung anheften';

  @override
  String get unpinFromSession => 'Von dieser Sitzung lösen';

  @override
  String get pinnedSnippets => 'Angeheftet';

  @override
  String get allSnippets => 'Alle';

  @override
  String get commandCopied => 'Befehl in die Zwischenablage kopiert';

  @override
  String get snippetFillTitle => 'Fill in snippet parameters';

  @override
  String get snippetFillSubmit => 'Run';

  @override
  String get snippetPreview => 'Preview';

  @override
  String get tags => 'Tags';

  @override
  String get tagsSubtitle =>
      'Sitzungen und Ordner mit farbigen Tags organisieren';

  @override
  String get noTags => 'Noch keine Tags';

  @override
  String get addTag => 'Tag hinzufügen';

  @override
  String get deleteTag => 'Tag löschen';

  @override
  String deleteTagConfirm(String name) {
    return 'Tag „$name“ löschen? Er wird von allen Sitzungen und Ordnern entfernt.';
  }

  @override
  String get tagName => 'Tag-Name';

  @override
  String get tagNameHint => 'z. B. Production, Staging';

  @override
  String get tagColor => 'Farbe';

  @override
  String get tagCreated => 'Tag erstellt';

  @override
  String tagDeleted(String name) {
    return 'Tag „$name“ gelöscht';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tags',
      one: '1 Tag',
      zero: 'Keine Tags',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'Tags verwalten';

  @override
  String get editTags => 'Tags bearbeiten';

  @override
  String get fullBackup => 'Vollständige Sicherung';

  @override
  String get sessionsOnly => 'Sitzungen';

  @override
  String get presetFullImport => 'Vollständiger Import';

  @override
  String get presetSelective => 'Selektiv';

  @override
  String get presetCustom => 'Benutzerdefiniert';

  @override
  String get sessionSshKeys => 'Sitzungsschlüssel (Manager)';

  @override
  String get allManagerKeys => 'Alle Manager-Schlüssel';

  @override
  String get browseFiles => 'Dateien auswählen…';

  @override
  String get sshDirSessionAlreadyImported => 'bereits in Sitzungen';

  @override
  String get languageSubtitle => 'Sprache der Benutzeroberfläche';

  @override
  String get themeSubtitle => 'Dunkel, hell oder dem System folgen';

  @override
  String get uiScaleSubtitle => 'Gesamte Benutzeroberfläche skalieren';

  @override
  String get terminalFontSizeSubtitle => 'Schriftgröße in der Terminalausgabe';

  @override
  String get scrollbackLinesSubtitle => 'Größe des Terminal-Verlaufspuffers';

  @override
  String get keepAliveIntervalSubtitle =>
      'Sekunden zwischen SSH-Keep-Alive-Paketen (0 = aus)';

  @override
  String get sshTimeoutSubtitle => 'Verbindungs-Timeout in Sekunden';

  @override
  String get defaultPortSubtitle => 'Standardport für neue Sitzungen';

  @override
  String get parallelWorkersSubtitle => 'Parallele SFTP-Worker';

  @override
  String get maxHistorySubtitle => 'Maximal gespeicherte Befehle im Verlauf';

  @override
  String get calculateFolderSizesSubtitle =>
      'Gesamtgröße neben Ordnern in der Seitenleiste anzeigen';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Beim Start nach einer neuen Version auf GitHub suchen';

  @override
  String get enableLoggingSubtitle =>
      'App-Ereignisse in eine rotierende Logdatei schreiben';

  @override
  String get exportWithoutPassword => 'Ohne Passwort exportieren?';

  @override
  String get exportWithoutPasswordWarning =>
      'Das Archiv wird nicht verschlüsselt. Jeder, der auf die Datei zugreifen kann, kann Ihre Daten lesen, einschließlich Passwörter und privater Schlüssel.';

  @override
  String get continueWithoutPassword => 'Ohne Passwort fortfahren';

  @override
  String get threatColdDiskTheft => 'Diebstahl bei ausgeschaltetem Gerät';

  @override
  String get threatColdDiskTheftDescription =>
      'Ausgeschalteter Rechner, dessen Laufwerk ausgebaut und an einem anderen Computer gelesen wird, oder eine Kopie der Datenbankdatei, die jemand mit Zugriff auf dein Home-Verzeichnis erstellt hat.';

  @override
  String get threatKeyringFileTheft => 'Diebstahl der Keyring-/Keychain-Datei';

  @override
  String get threatKeyringFileTheftDescription =>
      'Ein Angreifer liest die Credential-Store-Datei der Plattform direkt vom Laufwerk (libsecret-Keyring, Windows Credential Manager, macOS-Login-Keychain) und rekonstruiert daraus den umhüllten (wrapped) Datenbankschlüssel. Die Hardware-Stufe wehrt das unabhängig vom Passwort ab, weil der Chip den Export des Schlüsselmaterials verweigert; die Keychain-Stufe braucht zusätzlich ein Passwort, sonst lässt sich die gestohlene Datei mit dem OS-Anmeldepasswort allein entschlüsseln.';

  @override
  String get modifierOnlyWithPassword => 'nur mit Passwort';

  @override
  String get threatBystanderUnlockedMachine =>
      'Umstehende an einem entsperrten Gerät';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'Jemand tritt an deinen bereits entsperrten Computer und öffnet die App, während du abwesend bist.';

  @override
  String get threatLiveRamForensicsLocked =>
      'RAM-Forensik an gesperrtem Rechner';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'Ein Angreifer friert den RAM ein (oder erfasst ihn per DMA) und zieht noch vorhandenes Schlüsselmaterial aus dem Abbild, auch wenn die App gesperrt ist.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'Kompromittierung des OS-Kernels oder Schlüsselbunds';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'Kernel-Schwachstelle, Exfiltration aus dem Schlüsselbund oder eine Hintertür im Hardware-Sicherheitschip. Das Betriebssystem wird vom vertrauenswürdigen Bestandteil zum Angreifer.';

  @override
  String get threatOfflineBruteForce =>
      'Offline-Brute-Force gegen schwaches Passwort';

  @override
  String get threatOfflineBruteForceDescription =>
      'Ein Angreifer mit einer Kopie des umhüllten Schlüssels oder versiegelten Blobs probiert jedes Passwort in eigenem Tempo, ohne jede Geschwindigkeitsbegrenzung.';

  @override
  String get legendProtects => 'Geschützt';

  @override
  String get legendDoesNotProtect => 'Nicht geschützt';

  @override
  String get colT0 => 'T0 Klartext';

  @override
  String get colT1 => 'T1 Schlüsselbund';

  @override
  String get colT1Password => 'T1 + Passwort';

  @override
  String get colT1PasswordBiometric => 'T1 + Passwort + Biometrie';

  @override
  String get colT2 => 'T2 Hardware';

  @override
  String get colT2Password => 'T2 + Passwort';

  @override
  String get colT2PasswordBiometric => 'T2 + Passwort + Biometrie';

  @override
  String get colParanoid => 'Paranoid';

  @override
  String get securityComparisonTableThreatColumn => 'Bedrohung';

  @override
  String get compareAllTiers => 'Alle Stufen vergleichen';

  @override
  String get resetAllDataTitle => 'Alle Daten zurücksetzen';

  @override
  String get resetAllDataSubtitle =>
      'Alle Sitzungen, Schlüssel, Konfigurationen und Sicherheitsartefakte löschen. Entfernt auch Schlüsselbund-Einträge und Hardware-Vault-Slots.';

  @override
  String get resetAllDataConfirmTitle => 'Alle Daten zurücksetzen?';

  @override
  String get resetAllDataConfirmBody =>
      'Alle Sitzungen, SSH-Schlüssel, Known-Hosts, Snippets, Tags, Einstellungen und alle Sicherheitsartefakte (Schlüsselbund-Einträge, Hardware-Vault-Daten, biometrisches Overlay) werden dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get resetAllDataConfirmAction => 'Alles zurücksetzen';

  @override
  String get resetAllDataInProgress => 'Wird zurückgesetzt…';

  @override
  String get resetAllDataDone => 'Alle Daten zurückgesetzt';

  @override
  String get resetAllDataFailed => 'Zurücksetzen fehlgeschlagen';

  @override
  String get autoLockRequiresPassword =>
      'Auto-Sperre erfordert ein Passwort auf der aktiven Stufe.';

  @override
  String get recommendedBadge => 'EMPFOHLEN';

  @override
  String get tierHardwareSubtitleHonest =>
      'Fortgeschritten: hardware-gebundener Schlüssel. Daten sind unwiederbringlich verloren, wenn der Chip dieses Geräts verloren geht oder ersetzt wird.';

  @override
  String get tierParanoidSubtitleHonest =>
      'Alternative: Master-Passwort, kein Vertrauen in das OS. Schützt vor OS-Kompromittierung. Verbessert den Laufzeitschutz gegenüber T1/T2 nicht.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'Runtime-Bedrohungen (Malware desselben Benutzers, Speicherabbild des laufenden Prozesses) werden in jeder Stufe als ✗ dargestellt. Sie werden durch separate Mitigationsfunktionen behandelt, die unabhängig von der gewählten Stufe gelten.';

  @override
  String get currentTierBadge => 'AKTUELL';

  @override
  String get paranoidAlternativeHeader => 'ALTERNATIVE';

  @override
  String get modifierPasswordLabel => 'Passwort';

  @override
  String get modifierPasswordSubtitle =>
      'Eingegebenes Passwort, das vor dem Entsperren des Tresors abgefragt wird.';

  @override
  String get modifierBiometricLabel => 'Biometrische Verknüpfung';

  @override
  String get modifierBiometricSubtitle =>
      'Das Passwort aus einem biometrisch gesicherten OS-Slot freigeben, statt es einzutippen.';

  @override
  String get biometricRequiresPassword =>
      'Aktivieren Sie zuerst ein Passwort — Biometrie ist nur eine Verknüpfung zur Eingabe.';

  @override
  String get biometricRequiresActiveTier =>
      'Wähle zuerst diese Stufe, um die biometrische Entsperrung zu aktivieren';

  @override
  String get autoLockRequiresActiveTier =>
      'Wähle zuerst diese Stufe, um die automatische Sperre zu konfigurieren';

  @override
  String get biometricForbiddenParanoid =>
      'Paranoid erlaubt Biometrie per Design nicht.';

  @override
  String get fprintdNotAvailable =>
      'fprintd ist nicht installiert oder kein Finger registriert.';

  @override
  String get linuxTpmWithoutPasswordNote =>
      'Ein TPM ohne Passwort bietet Isolation, keine Authentifizierung. Wer diese App ausführen kann, kann die Daten entsperren.';

  @override
  String get paranoidMasterPasswordNote =>
      'Eine lange Passphrase wird dringend empfohlen — Argon2id verlangsamt Brute-Force nur, blockiert es aber nicht.';

  @override
  String get plaintextWarningTitle => 'Klartext: keine Verschlüsselung';

  @override
  String get plaintextWarningBody =>
      'Sitzungen, Schlüssel und known hosts werden ohne Verschlüsselung gespeichert. Jeder mit Zugriff auf das Dateisystem dieses Computers kann sie lesen.';

  @override
  String get plaintextAcknowledge =>
      'Ich verstehe, dass meine Daten nicht verschlüsselt werden';

  @override
  String get plaintextAcknowledgeRequired =>
      'Bestätigen Sie, dass Sie es verstanden haben, bevor Sie fortfahren.';

  @override
  String get passwordLabel => 'Passwort';

  @override
  String get masterPasswordLabel => 'Master-Passwort';
}
