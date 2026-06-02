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
  String get copyModeSetAnchor => 'Anker setzen';

  @override
  String get copyModeCopySelection => 'Auswahl kopieren';

  @override
  String get required => 'Erforderlich';

  @override
  String get errFillRequiredFields =>
      'Fülle die mit * markierten Pflichtfelder aus';

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
  String importedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sitzungen importiert',
      one: '1 Sitzung importiert',
      zero: 'Keine Sitzungen importiert',
    );
    return '$_temp0';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sitzungen',
      one: '1 Sitzung',
      zero: '0 Sitzungen',
    );
    return '$_temp0';
  }

  @override
  String nFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ordner',
      one: '1 Ordner',
    );
    return '$_temp0';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'Ordner \"$name\" löschen?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dadurch werden auch $count Sitzungen darin gelöscht.',
      one: 'Dadurch wird auch 1 Sitzung darin gelöscht.',
    );
    return '$_temp0';
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
  String get sectionAuthentication => 'Authentifizierung';

  @override
  String get sectionAdvanced => 'Erweitert';

  @override
  String get moreOptions => 'Weitere Optionen';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Portweiterleitungsregeln',
      one: '1 Portweiterleitungsregel',
      zero: 'Keine Portweiterleitungsregeln',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => 'Verwalten…';

  @override
  String get authMethodAgent => 'System-ssh-agent verwenden';

  @override
  String get options => 'Optionen';

  @override
  String get sessionName => 'Sitzungsname';

  @override
  String get sessionNameAutoFromHost => 'Auto vom Host';

  @override
  String get sessionNameAutoFromUrl => 'Auto vom URL-Host';

  @override
  String get sessionNameAutoFromBucket => 'Auto vom Default-Bucket';

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
  String get savedTypeToChange => 'Gespeichert — zum Ändern eingeben';

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
  String get verboseConnectionLog => 'Ausführliches Verbindungsprotokoll';

  @override
  String get verboseConnectionLogSubtitle =>
      'Den vollständigen SSH-Handshake- und Authentifizierungs-Trace in die Logdatei schreiben (zur Diagnose von Verbindungsfehlern)';

  @override
  String get exportData => 'Daten exportieren';

  @override
  String get exportRecordings => 'Sitzungsaufzeichnungen';

  @override
  String sshConfigPreviewHostsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Hosts gefunden',
      one: '1 Host gefunden',
      zero: 'Keine Hosts gefunden',
    );
    return '$_temp0';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Schlüssel gefunden — auswählen, welche importiert werden sollen',
      one: '1 Schlüssel gefunden — auswählen, ob importiert wird',
    );
    return '$_temp0';
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
  String a11yConnectingTo(String host) {
    return 'Verbinde mit $host';
  }

  @override
  String a11yConnectedTo(String host) {
    return 'Verbunden mit $host';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return 'Verbindung zu $host getrennt';
  }

  @override
  String a11yConnectionFailed(String host) {
    return 'Verbindung zu $host fehlgeschlagen';
  }

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
  String get qrTooManyForSingleCode =>
      'Zu viele Sitzungen für einen einzelnen QR-Code. Reduzieren Sie die Auswahl oder nutzen Sie den .lfs-Export.';

  @override
  String get qrTooLarge =>
      'Zu groß — wählen Sie einige Elemente ab oder nutzen Sie den .lfs-Dateiexport.';

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
  String get archivedLog => 'Archiviertes Log';

  @override
  String get loggingLevel => 'Log-Level';

  @override
  String get loggingLevelSubtitleInfo =>
      'Routine-Einträge + Warnungen + Fehler';

  @override
  String get loggingLevelSubtitleWarn => 'Nur degradierte Pfade und Fehler';

  @override
  String get loggingLevelSubtitleError => 'Nur Fehler';

  @override
  String get loggingLevelSubtitleOff => 'Keine Routine-Logs werden geschrieben';

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
  String get errConnectionLostReconnect =>
      'Verbindung verloren — die Sitzung wurde getrennt (Ruhezustand oder Netzwerk). Verbinde sie über die Sitzungsliste neu.';

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
  String get noTagsAvailable =>
      'Noch keine Tags — leg in Tools → Tags einen an.';

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
  String get bucket => 'Bucket';

  @override
  String get prefix => 'Prefix';

  @override
  String get typeLabel => 'Typ';

  @override
  String get folder => 'Ordner';

  @override
  String nSubitems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente',
      one: '1 Element',
      zero: '0 Elemente',
    );
    return '$_temp0';
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
  String get addKeyMenuPaste => 'PEM einfügen';

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
  String get sshCertificate => 'Zertifikat';

  @override
  String get certImport => 'Zertifikat importieren';

  @override
  String get certImportTooltip =>
      'OpenSSH-Zertifikat anhängen, das von deiner CA signiert wurde (`-cert.pub` aus `ssh-keygen -s …`). Verwenden, wenn der Server über CA-Signatur statt `authorized_keys` verifiziert. Überspringen, wenn deine Server plain key auth nutzen.';

  @override
  String get certImportPickerTitle => 'OpenSSH-Zertifikatsdatei auswählen';

  @override
  String get certValidFrom => 'Gültig ab';

  @override
  String get certValidTo => 'Gültig bis';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => 'Dieses Zertifikat läuft bald ab.';

  @override
  String get certExpired => 'Abgelaufen';

  @override
  String get certRemove => 'Zertifikat entfernen';

  @override
  String get certRemoveConfirmTitle => 'Zertifikat entfernen?';

  @override
  String get certRemoveConfirmBody =>
      'Nach dem Entfernen verbindet sich die Sitzung wieder über den reinen Public-Key-Pfad.';

  @override
  String errCertParse(String detail) {
    return 'Zertifikat konnte nicht geparst werden: $detail';
  }

  @override
  String get errCertPairFingerprintMismatch =>
      'Dieses Zertifikat gehört nicht zum ausgewählten Schlüssel.';

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
  String get passphrase => 'Passphrase';

  @override
  String get enterMasterPassword =>
      'Geben Sie das Master-Passwort ein, um Ihre gespeicherten Anmeldedaten zu entsperren.';

  @override
  String get wrongMasterPassword => 'Falsches Passwort. Erneut versuchen.';

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
  String get snippetTokensHint =>
      'Tippen, um einen Platzhalter einzufügen. Diese werden zur Laufzeit mit Werten aus der aktiven Sitzung ersetzt:';

  @override
  String get snippetCustomTokensHint =>
      'Alles andere mit doppelten geschweiften Klammern fragt dich beim Ausführen nach einem Wert.';

  @override
  String get snippetFillTitle => 'Snippet-Parameter ausfüllen';

  @override
  String get snippetFillSubmit => 'Ausführen';

  @override
  String get broadcastSetDriver => 'Aus diesem Bereich senden';

  @override
  String get broadcastClearDriver => 'Senden aus diesem Bereich beenden';

  @override
  String get broadcastAddReceiver => 'Übertragung hier empfangen';

  @override
  String get broadcastRemoveReceiver => 'Empfang beenden';

  @override
  String get broadcastClearAll => 'Alles Senden beenden';

  @override
  String get broadcastPasteTitle => 'Einfügen an alle Bereiche senden?';

  @override
  String broadcastPasteBody(int chars, int count) {
    return '$chars Zeichen werden an $count weitere Bereiche gesendet.';
  }

  @override
  String get broadcastPasteSend => 'Senden';

  @override
  String get portForwarding => 'Weiterleitung';

  @override
  String get portForwardingEmpty => 'Noch keine Regeln';

  @override
  String get addForwardRule => 'Regel hinzufügen';

  @override
  String get editForwardRule => 'Regel bearbeiten';

  @override
  String get deleteForwardRule => 'Regel löschen';

  @override
  String get localForward => 'Lokal';

  @override
  String get remoteForward => 'Entfernt';

  @override
  String get dynamicForward => 'Dynamisch';

  @override
  String get forwardKind => 'Art';

  @override
  String get bindAddress => 'Bindadresse';

  @override
  String get bindPort => 'Bindport';

  @override
  String get targetHost => 'Zielhost';

  @override
  String get targetPort => 'Zielport';

  @override
  String get forwardDescription => 'Beschreibung (optional)';

  @override
  String get forwardEnabled => 'Aktiviert';

  @override
  String get forwardBindWildcardWarning =>
      'Bindung an 0.0.0.0 macht die Weiterleitung auf jeder Schnittstelle sichtbar — meist willst du 127.0.0.1.';

  @override
  String get forwardKindLocalHelp =>
      'Lokal: öffnet einen Port auf diesem Gerät, der zu einem vom SSH-Server erreichbaren Ziel tunnelt. Nützlich für entfernte Datenbanken oder Admin-UIs über localhost:bindPort.';

  @override
  String get forwardKindRemoteHelp =>
      'Entfernt: bittet den SSH-Server, einen Port zu öffnen, der zu einem von diesem Gerät erreichbaren Ziel zurücktunnelt. Nützlich um einen lokalen Dev-Server mit einem Remote-Host zu teilen (Server braucht ggf. GatewayPorts yes für Non-Loopback-Binds).';

  @override
  String get forwardKindDynamicHelp =>
      'Dynamisch: ein SOCKS5-Proxy auf diesem Gerät, der jede Verbindung durch den SSH-Server leitet. Browser oder curl auf localhost:bindPort zeigen lassen — der gesamte Traffic geht über SSH.';

  @override
  String get proxyJump => 'Verbinden über';

  @override
  String get proxyJumpNone => 'Direkte Verbindung';

  @override
  String get proxyJumpSavedSession => 'Gespeicherte Sitzung';

  @override
  String get proxyJumpCustom => 'Benutzerdefiniert';

  @override
  String get proxyJumpCustomNote =>
      'Override-Hops verwenden die Anmeldedaten dieser Sitzung. Für andere Bastion-Auth speichere den Bastion als eigene Sitzung.';

  @override
  String viaSessionLabel(String label) {
    return 'über $label';
  }

  @override
  String get recordSession => 'Sitzung aufzeichnen';

  @override
  String get recordSessionHelp =>
      'Terminal-Ausgabe für diese Sitzung auf der Festplatte speichern. Im Ruhezustand verschlüsselt, wenn ein Master-Passwort oder Hardware-Key die Sitzungs-DB schützt; sonst als Klartext neben der DB abgelegt.';

  @override
  String get recordingsBrowserTitle => 'Aufzeichnungen';

  @override
  String get recordingsBrowserSubtitle =>
      'Aufgezeichnete Sitzungen durchsuchen, abspielen und löschen';

  @override
  String get recordingsEmpty => 'Noch keine Aufzeichnungen';

  @override
  String get playRecording => 'Abspielen';

  @override
  String get deleteRecording => 'Löschen';

  @override
  String get recordingPlaybackTitle => 'Aufzeichnung wiedergeben';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

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
  String resetAllDataConfirmTypePrompt(String phrase) {
    return 'Geben Sie $phrase unten ein, um zu bestätigen:';
  }

  @override
  String get resetAllDataInProgress => 'Wird zurückgesetzt…';

  @override
  String get resetAllDataDone => 'Alle Daten zurückgesetzt';

  @override
  String get resetAllDataFailed => 'Zurücksetzen fehlgeschlagen';

  @override
  String get recordingsTitle => 'Aufnahmen';

  @override
  String get recordingsStorageUsedLabel => 'Belegt';

  @override
  String get recordingsCapLabel => 'Limit';

  @override
  String get recordingsCapHint =>
      'Hartes Limit für den Ordner recordings/. Beim Überschreiten wird die älteste Aufnahme zuerst gelöscht; die laufende Aufnahme bleibt unangetastet.';

  @override
  String get recordingsClearAllAction => 'Alle Aufnahmen löschen';

  @override
  String get recordingsClearAllConfirmTitle => 'Alle Aufnahmen löschen?';

  @override
  String get recordingsClearAllConfirmBody =>
      'Jede aufgenommene Session unter <app>/recordings/ wird gelöscht. Die gerade laufende Aufnahme (falls vorhanden) bleibt erhalten. Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String recordingsClearAllResult(int count) {
    return '$count Aufnahmen entfernt';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return 'Limit aktualisiert. $bytes freigegeben.';
  }

  @override
  String get recordingsCapChangedNoChange =>
      'Limit aktualisiert. Nichts zu entfernen.';

  @override
  String get recordingsCapPreset100Mb => '100 MiB';

  @override
  String get recordingsCapPreset250Mb => '250 MiB';

  @override
  String get recordingsCapPreset500Mb => '500 MiB';

  @override
  String get recordingsCapPreset1Gb => '1 GiB';

  @override
  String get recordingsCapPreset2Gb => '2 GiB';

  @override
  String get recordingsCapPreset5Gb => '5 GiB';

  @override
  String get autoLockRequiresPassword =>
      'Auto-Sperre erfordert ein Passwort auf der aktiven Stufe.';

  @override
  String get recommendedBadge => 'EMPFOHLEN';

  @override
  String get tierHardwareSubtitleHonest =>
      'Fortgeschritten: hardware-gebundener Schlüssel, immer Passwort-geschützt. Daten sind unwiederbringlich verloren, wenn der Chip dieses Geräts verloren geht oder ersetzt wird.';

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
  String get modifierPasswordRequired =>
      'Erforderlich — Hardware-Stufe ist immer Passwort-geschützt.';

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
  String get t2RequiresPasswordTitle =>
      'Master-Passwort für Hardware-Stufe festlegen';

  @override
  String get t2RequiresPasswordBody =>
      'Hardware-Stufe braucht ein Passwort als Modifier. Biometrie ist ein optionaler Shortcut darüber.';

  @override
  String get t2MigrationPromptTitle => 'Hardware-Stufe braucht ein Passwort';

  @override
  String get t2MigrationPromptBody =>
      'Bestehende Hardware-Installationen ohne Passwort müssen jetzt eines setzen, um fortzufahren.';

  @override
  String get t2MigrationContinue => 'Weiter';

  @override
  String get t2MigrationSetPasswordTitle =>
      'Passwort setzen, um die Hardware-Stufe zu behalten';

  @override
  String get t2MigrationSetPasswordBody =>
      'Gib ein neues Master-Passwort ein. Der bereits im Hardware-Modul versiegelte DB-Key wird unter diesem Passwort neu versiegelt — deine Sessions und Keys bleiben unangetastet.';

  @override
  String get t2MigrationWipeAndRestart => 'Wipen und neu starten';

  @override
  String get t2MigrationResealFailed =>
      'Hardware-Stufe konnte nicht neu versiegelt werden — anderes Passwort wählen oder wipen.';

  @override
  String get biometricOverlayEnable =>
      'Biometrie-Shortcut auf Hardware-Stufe aktivieren';

  @override
  String get biometricOverlayEnableSubtitle =>
      'Gibt dein Passwort aus einem biometrisch geschützten OS-Slot frei.';

  @override
  String get biometricOverlayUnavailable =>
      'Biometrie-Overlay auf dieser Plattform noch nicht verfügbar.';

  @override
  String get biometricOverlayRequiresPassword =>
      'Setze zuerst das Hardware-Passwort.';

  @override
  String get t2UnlockTitle => 'Mit Master-Passwort entsperren';

  @override
  String get t2UnlockSubtitle =>
      'Der hardware-gebundene Schlüssel ist durch dein Passwort geschützt.';

  @override
  String get t2UnlockUseBiometricButton => 'Biometrie verwenden';

  @override
  String get t2PasswordChanged => 'Hardware-Passwort aktualisiert.';

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

  @override
  String get globalErrorTitle => 'Unerwarteter Fehler';

  @override
  String get globalErrorBody =>
      'Ein unerwarteter Fehler ist aufgetreten. Die App läuft weiter.';

  @override
  String get globalErrorLogSavedNote =>
      'Alle Details wurden in die Logdatei geschrieben.';

  @override
  String get globalErrorLogDisabledNote =>
      'Logging in den Einstellungen aktivieren, um Fehlerdetails zu speichern.';

  @override
  String globalErrorTechnicalLine(String detail) {
    return 'Fehler: $detail';
  }

  @override
  String get globalErrorEnableLoggingButton => 'Logging aktivieren';

  @override
  String get globalErrorLoggingEnabledToast =>
      'Logging aktiviert — Fehler werden in die Logdatei geschrieben';

  @override
  String get fatalErrorQuitButton => 'Beenden';

  @override
  String get fatalErrorWipeButton => 'Alle Daten löschen';

  @override
  String get fatalErrorWipingButton => 'Wird gelöscht…';

  @override
  String get fatalErrorWipeExplanation =>
      'Das Löschen entfernt jede App-Datei (Config, Datenbank, Vault-Blobs, Logs) — der nächste Start beginnt mit einer sauberen Installation. Nicht umkehrbar.';

  @override
  String get fatalErrorWipeConfirmTitle => 'Alle Daten löschen?';

  @override
  String get fatalErrorWipeConfirmBody =>
      'Dies löscht dauerhaft jede Config-, Datenbank- und Vault-Datei. Die App startet mit einer leeren Installation neu. Fortfahren?';

  @override
  String get fatalErrorWipeConfirmAction => 'Alles löschen';

  @override
  String get unencryptedArchiveWarning =>
      'Dieses Archiv ist nicht passwortgeschützt. Jeder mit der Datei kann den Inhalt lesen.';

  @override
  String get clipboardCopyFailed =>
      'Kopieren in die Zwischenablage fehlgeschlagen.';

  @override
  String get nonAsciiHostnameWarning =>
      'Der Hostname enthält Nicht-ASCII-Zeichen — jedes Zeichen gegen die getippte Eingabe prüfen. Visuell ähnliche Codepoints (Kyrillisch / Griechisch) können eine Latin-Domain fälschen.';

  @override
  String get playbackPause => 'Pause';

  @override
  String get recordingPlayLocked =>
      'App entsperren, um diese verschlüsselte Aufnahme abzuspielen.';

  @override
  String get recordToggleStart => 'Aufzeichnung starten';

  @override
  String get recordToggleStop => 'Aufzeichnung stoppen';

  @override
  String get foregroundServiceTitle => 'SSH aktiv';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count aktive Verbindungen',
      one: '1 aktive Verbindung',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => 'Sitzungstyp';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => 'Benutzername';

  @override
  String get webDavAuthMethod => 'Auth-Methode';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer-Token';

  @override
  String get trustedCert => 'Vertrauenswürdiges Zertifikat (PEM)';

  @override
  String get trustedCertHint => '-----BEGIN CERTIFICATE-----';

  @override
  String get trustedCertHelp =>
      'Server-Zertifikat einfügen (ein oder mehrere PEM-Blöcke). Wird nur für diese Sitzung als zusätzliche Root-CA hinzugefügt — andere Apps bleiben unberührt. Leer lassen, um den System-Trust-Store zu nutzen.';

  @override
  String get acceptAnyCert => 'Jedes Zertifikat akzeptieren';

  @override
  String get acceptAnyCertHelp =>
      'Überspringt alle Zertifikat- und Hostnamen-Prüfungen für die TLS-Handshakes dieser Sitzung. Notausgang, wenn weder System-Trust-Store noch ein gepinntes Zertifikat passen.';

  @override
  String get acceptAnyCertWarn =>
      'Anfällig für MITM-Angriffe — jeder im Netz kann den Server imitieren. Nur in vertrauenswürdigen privaten Netzen verwenden.';

  @override
  String get webDavCopyUrl => 'WebDAV-URL kopieren';

  @override
  String get webDavOpenInBrowser => 'Im Browser öffnen';

  @override
  String get errWebDavAuthFailed => 'WebDAV-Authentifizierung fehlgeschlagen';

  @override
  String get errWebDavNotFound => 'Pfad nicht gefunden';

  @override
  String get errWebDavConflict =>
      'Operation steht im Konflikt mit aktuellem Zustand';

  @override
  String errWebDavGeneric(String detail) {
    return 'WebDAV-Server hat Anfrage abgelehnt: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'WebDAV-Base-URL ist erforderlich';

  @override
  String get errWebDavBaseUrlInvalid =>
      'Base URL muss http:// oder https:// sein';

  @override
  String get sessionKindS3 => 'S3';

  @override
  String get s3AccessKeyId => 'Access Key ID';

  @override
  String get s3SecretKey => 'Secret Access Key';

  @override
  String get s3Region => 'Region';

  @override
  String get s3RegionHint => 'us-east-1, eu-west-2, auto';

  @override
  String get s3Endpoint => 'Endpoint';

  @override
  String get s3EndpointHint =>
      'Leer lassen für AWS, oder setzen für MinIO / R2 / Spaces';

  @override
  String get s3PathStyle => 'Path-Style-Adressierung';

  @override
  String get s3PathStyleHint => 'Pflicht für MinIO; bei AWS aus lassen';

  @override
  String get s3DefaultBucket => 'Standard-Bucket';

  @override
  String get s3DefaultPrefix => 'Standard-Prefix';

  @override
  String get s3GeneratePresignedUrl => 'Presigned URL erzeugen';

  @override
  String get s3PresignedUrlExpiry => 'Läuft ab in';

  @override
  String get s3CopyUri => 's3://bucket/key URI kopieren';

  @override
  String get s3PresignedUrlExpiry15min => '15 Minuten';

  @override
  String get s3PresignedUrlExpiry1hour => '1 Stunde';

  @override
  String get s3PresignedUrlExpiry4hour => '4 Stunden';

  @override
  String get s3PresignedUrlExpiry24hour => '24 Stunden';

  @override
  String get s3PresignedUrlExpiry7day => '7 Tage';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (Access Key + Secret prüfen)';

  @override
  String get errS3NoSuchBucket =>
      'Bucket existiert nicht oder ist nicht erreichbar';

  @override
  String get errS3RegionMismatch =>
      'Bucket liegt in einer anderen Region als konfiguriert';

  @override
  String errS3Generic(String detail) {
    return 'S3-Server hat die Anfrage abgelehnt: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'WebDAV-Sync aktivieren';

  @override
  String get syncPassphrase => 'Sync-Passphrase';

  @override
  String get syncPassphraseHint =>
      'Verschlüsselt das Sync-Archiv. Muss sich vom Master-Passwort unterscheiden.';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Sync-Passphrase darf nicht mit dem Master-Passwort übereinstimmen.';

  @override
  String get syncRemotePath => 'Remote-Pfad';

  @override
  String get syncRemotePathHint =>
      'Pfad unter der WebDAV-Base-URL — Standard letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return 'Letzter Push: $when';
  }

  @override
  String syncLastPulled(String when) {
    return 'Letzter Pull: $when';
  }

  @override
  String get syncNeverRun => 'Nie';

  @override
  String get syncUpToDate => 'Sync ist aktuell';

  @override
  String syncPushedBytes(String bytes) {
    return '$bytes gepusht';
  }

  @override
  String syncPullApplied(int count) {
    return '$count Änderungen vom Remote übernommen';
  }

  @override
  String get errSyncDisabled => 'Sync ist deaktiviert';

  @override
  String get errSyncEtagMismatch =>
      'Remote hat sich geändert — erst pullen, dann pushen';

  @override
  String get errSyncUnauthorized => 'WebDAV-Authentifizierung fehlgeschlagen';

  @override
  String errSyncNetwork(String detail) {
    return 'Netzwerkfehler: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion =>
      'Sync-Archiv vom Remote benötigt einen neueren Build';

  @override
  String get hardwareKey => 'Hardware Key';

  @override
  String get hardwareKeyTapPrompt => 'Hardware Key berühren';

  @override
  String get hardwareKeyPin => 'Hardware-Key-PIN';

  @override
  String get hardwareKeyTimeout => 'Hardware Key hat nicht reagiert';

  @override
  String get hardwareKeyNotFound => 'Kein Hardware Key gefunden';

  @override
  String get hardwareKeyUnsupported =>
      'Direkter Hardware-Key-Zugriff ist auf dieser Plattform nicht verfügbar';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'Erfordert Apple-Developer-Program-Entitlement; nutze ssh-agent auf macOS';

  @override
  String get skKeyRequiresDevice =>
      'Dieser SSH-Schlüssel benötigt einen Hardware Key — zum Authentifizieren berühren';

  @override
  String get errSkWrongPin => 'Falscher PIN';

  @override
  String get hardwareKeyImport => 'Hardware Key importieren (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => 'Hardware Key Abfrage abgebrochen';

  @override
  String get agentEndpointSectionTitle => 'Externe SSH-Client-Integration';

  @override
  String get agentEndpointToggleTitle =>
      'Hardware-bound Keys für SSH-Clients freigeben';

  @override
  String get agentEndpointToggleSubtitle =>
      'Erlaubt git, ssh, IDE-Plugins auf diesem Gerät, deine FIDO2 / Smart-Card / TPM Keys zu nutzen.';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'Export-Befehl kopieren';

  @override
  String get agentEndpointCopyPipeName => 'Pipe-Name kopieren';

  @override
  String get agentEndpointSignatureRequestTitle => 'Signaturanfrage';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester möchte mit $keyLabel signieren';
  }

  @override
  String get agentEndpointRequesterUnknown => 'Ein externer SSH-Client';

  @override
  String get agentEndpointAuthorizeOnce => 'Einmal erlauben';

  @override
  String get agentEndpointAuthorizeAlways => 'Erlauben und merken';

  @override
  String get agentEndpointDeny => 'Ablehnen';

  @override
  String get agentEndpointStatusRunning => 'Aktiv';

  @override
  String get agentEndpointStatusStopped => 'Gestoppt';

  @override
  String get agentEndpointStatusUnsupported =>
      'Auf dieser Plattform nicht verfügbar';

  @override
  String get agentEndpointRefusedAddIdentity =>
      'Abgelehnt: externe Clients dürfen keine Keys hinzufügen.';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'SSH-Agent-Endpoint konnte nicht gestartet werden: $detail';
  }

  @override
  String get pkcs11AddTitle => 'Smartcard- / Token-Schlüssel hinzufügen';

  @override
  String get pkcs11ModuleLabel => 'PKCS#11-Modul';

  @override
  String get pkcs11ModuleAutoDetected => 'Automatisch erkannt';

  @override
  String get pkcs11ModuleCustom => 'Benutzerdefiniertes Modul...';

  @override
  String get pkcs11ModulePickerTitle => 'PKCS#11-Bibliothek auswählen';

  @override
  String get pkcs11NoModuleFound =>
      'Kein PKCS#11-Modul gefunden. OpenSC installieren oder Vendor-Library wählen.';

  @override
  String get pkcs11InitializeFailed =>
      'PKCS#11-Modul wurde nicht initialisiert.';

  @override
  String get pkcs11NoTokenPresent => 'Kein Token im Lesegerät.';

  @override
  String pkcs11TokenLabel(String label) {
    return 'Token: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return 'Seriennummer: $serial';
  }

  @override
  String get pkcs11LoginRequired => 'Token benötigt Login.';

  @override
  String pkcs11PinPrompt(String token) {
    return 'PIN für $token';
  }

  @override
  String get pkcs11PinPad => 'Auf dem PIN-Pad des Tokens bestätigen.';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'PIN falsch. $remaining Versuche übrig.';
  }

  @override
  String get pkcs11PinLocked => 'Token-PIN ist gesperrt. Mit PUK entsperren.';

  @override
  String get pkcs11NoSignableKeys =>
      'Token hat keine SSH-tauglichen Schlüssel (RSA, ECDSA, Ed25519).';

  @override
  String get pkcs11GostUnsupported =>
      'GOST-Schlüssel funktionieren nicht über SSH.';

  @override
  String pkcs11TokenUnplugged(String label) {
    return 'Token \"$label\" ist nicht eingesteckt.';
  }

  @override
  String get pkcs11UriRebindFailed =>
      'Gespeicherter Token nicht gefunden. Erneut einstecken und wiederholen.';

  @override
  String pkcs11SignFailed(String reason) {
    return 'Signieren fehlgeschlagen: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      'Smartcards / PKCS#11-Tokens sind auf dieser Plattform nicht verfügbar.';

  @override
  String get pkcs11Badge => 'Smartcard / Token';

  @override
  String pkcs11InfoModulePath(String path) {
    return 'Modul: $path';
  }

  @override
  String pkcs11InfoTokenSerial(String serial) {
    return 'Token-Seriennummer: $serial';
  }

  @override
  String pkcs11InfoObjectLabel(String label) {
    return 'Objekt: $label';
  }

  @override
  String get pkcs11WizardStepModule => 'PKCS#11-Modul wählen';

  @override
  String get pkcs11WizardStepToken => 'Token wählen';

  @override
  String get pkcs11WizardStepKey => 'Schlüssel wählen';

  @override
  String get pkcs11WizardStepPin => 'PIN eingeben';

  @override
  String get pkcs11AlgoRsa => 'RSA';

  @override
  String get pkcs11AlgoEcdsa => 'ECDSA';

  @override
  String get pkcs11AlgoEd25519 => 'Ed25519';

  @override
  String get pkcs11AlgoGost => 'GOST';

  @override
  String pkcs11KeyMetaFormat(String algo, String detail) {
    return '$algo $detail';
  }

  @override
  String get pkcs11SaveCta => 'Schlüssel importieren';

  @override
  String get pkcs11SaveInProgress =>
      'Öffentlichen Schlüssel vom Token lesen...';

  @override
  String get pkcs11SaveSuccess => 'Smartcard-Schlüssel hinzugefügt.';

  @override
  String get pkcs11ScanInProgress => 'Suche nach PKCS#11-Modulen...';

  @override
  String get pkcs11LoadingTokens => 'Tokens werden geladen...';

  @override
  String get pkcs11LoadingKeys => 'Schlüssel werden geladen...';

  @override
  String get pkcs11ModuleStatusReady => 'Modul geladen.';

  @override
  String get pkcs11ModuleStatusNoToken => 'Kein Token vorhanden.';

  @override
  String get pkcs11ModuleStatusFailed => 'Modul konnte nicht geladen werden.';

  @override
  String get pkcs11PinPadHint => '(PIN-Pad am Gerät)';

  @override
  String get pkcs11WizardBack => 'Zurück';

  @override
  String get pkcs11WizardNext => 'Weiter';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => 'Hardware-Schlüssel hinzufügen';

  @override
  String get sshKeyHardwareBoundExplainer =>
      'Der private Schlüssel liegt im Secure Hardware des Geräts und kann nicht exportiert werden.';

  @override
  String get sshKeyEnclaveDeviceBound =>
      'Dieser Schlüssel funktioniert nur auf diesem Mac.';

  @override
  String get sshKeyEnclaveDeviceBoundIos =>
      'Dieser Schlüssel funktioniert nur auf diesem iPhone.';

  @override
  String get sshKeyHelloDeviceBound =>
      'Dieser Schlüssel funktioniert nur auf diesem PC.';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'Touch ID / Face ID erforderlich';

  @override
  String get sshKeyEnclavePasscodeFallback =>
      'Gerätepasscode als Fallback erlauben';

  @override
  String get sshKeyHelloPinRequired =>
      'Windows Hello erforderlich (PIN, Fingerabdruck oder Gesicht)';

  @override
  String get sshKeyHardwareUnavailableTitle =>
      'Hardware-Schlüssel nicht verfügbar';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'App muss signiert sein, um die Secure Enclave zu nutzen.';

  @override
  String get sshKeyHardwareUnavailableHello =>
      'Windows Hello ist auf diesem PC nicht eingerichtet.';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'Kein TPM erkannt — nur software-backed.';

  @override
  String get sshKeyHardwareUnavailableTier => 'Software-gated';

  @override
  String get sshKeyEnclaveAlgorithm => 'ecdsa-sha2-nistp256';

  @override
  String get sshKeyHelloAlgorithmEcdsa256 => 'ecdsa-sha2-nistp256 (TPM)';

  @override
  String get sshKeyHelloAlgorithmEcdsa384 => 'ecdsa-sha2-nistp384 (TPM)';

  @override
  String get sshKeyHelloAlgorithmRsa => 'rsa-sha2-256 (TPM)';

  @override
  String get sshKeyGenerateCta => 'Generieren';

  @override
  String get sshKeyGenerateInProgress =>
      'Schlüssel im Secure Hardware wird erzeugt...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Code-Signing erforderlich — siehe USER_GUIDE.md → Hardware-bound keys.';

  @override
  String get sshKeySignInProgress => 'Signiere mit Secure Hardware...';

  @override
  String get sshKeyPublicCopy => 'Öffentlichen Schlüssel kopieren';

  @override
  String get sshKeyAuthorizedKeysHint =>
      'Diese Zeile in ~/.ssh/authorized_keys auf dem Server eintragen.';

  @override
  String get sshKeyEnclaveWizardTitle => 'Secure-Enclave-SSH-Schlüssel';

  @override
  String get sshKeyEnclaveWizardLabelHint => 'Schlüsselname';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'Windows-Hello-SSH-Schlüssel';

  @override
  String get helloWizardLabelHint => 'Schlüsselbezeichnung';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'Mit Windows Hello bestätigen';

  @override
  String get helloPromptDescription =>
      'PIN, Fingerabdruck oder Gesicht — Windows Hello signiert die SSH-Challenge.';

  @override
  String get helloSoftwareGatedWarning =>
      'Kein TPM auf diesem Gerät. Der Schlüssel landet im User-Storage; Windows Hello bleibt das Gate für jede Signatur.';

  @override
  String get helloP384NotSupported =>
      'Die TPM-Firmware unterstützt kein P-384. Wähle P-256 oder RSA-2048.';

  @override
  String get helloConfigureFirst =>
      'Richte zuerst Windows Hello ein: Einstellungen -> Anmeldeoptionen.';

  @override
  String get tpmSshTitle => 'TPM-gestützten SSH-Schlüssel erzeugen';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (empfohlen)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported =>
      'Algorithmus von dieser TPM-Firmware nicht unterstützt.';

  @override
  String get tpmSshPinProtect => 'Mit PIN schützen';

  @override
  String get tpmSshPinLockoutWarning =>
      'Nach mehreren falschen PIN-Eingaben sperrt das TPM den Schlüssel.';

  @override
  String get tpmSshPinMismatch => 'PINs stimmen nicht überein.';

  @override
  String get tpmSshStorageBlob => 'Verpackten Schlüssel in App-Daten speichern';

  @override
  String get tpmSshStorageHandle => 'Im TPM-Speicherslot ablegen';

  @override
  String get tpmSshStorageHandleHelp =>
      'Schnelleres Signieren. Belegt einen der permanenten TPM-Slots.';

  @override
  String get tpmSshLabel => 'Schlüssel-Label';

  @override
  String get tpmSshImportTitle => 'TPM-geschützten SSH-Schlüssel importieren';

  @override
  String get tpmSshImportFormat => 'TPM 2.0 Key File (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return 'TPM-PIN für $label';
  }

  @override
  String get tpmSshPinIncorrect => 'PIN falsch.';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM ist in der Lockout-Cooldown. $duration warten und erneut versuchen.';
  }

  @override
  String get tpmSshGenerating => 'Schlüssel wird im TPM erzeugt...';

  @override
  String get tpmSshSigning => 'Signiere mit TPM...';

  @override
  String get tpmSshUnavailable => 'Kein TPM auf diesem Gerät gefunden.';

  @override
  String get tpmSshUnavailableFwDisabled =>
      'TPM ist in der Firmware deaktiviert.';

  @override
  String get tpmSshUnavailableNoPermission =>
      'App hat keinen Zugriff auf das TPM. Benutzer zur Gruppe `tss` hinzufügen.';

  @override
  String tpmSshHandleInUse(String handle) {
    return 'Permanenter Slot $handle ist bereits belegt.';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      'Dieser Schlüssel signiert OHNE Hello-/PIN-Prompt — jeder mit Desktop-Zugriff während du angemeldet bist kann ihn nutzen.';

  @override
  String get keystoreWizardTitle => 'Android Hardware Key';

  @override
  String get keystoreBadge => 'Android Keystore';

  @override
  String get keystoreKeyAndroidLabel => 'Android Keystore (hardware-gebunden)';

  @override
  String get keystoreKeyStrongBoxLabel => 'StrongBox HSM';

  @override
  String get keystoreKeyTeeLabel => 'TEE (hardware-backed)';

  @override
  String get keystoreKeyGenerating =>
      'Hardware-gebundener Schlüssel wird erzeugt...';

  @override
  String get keystoreKeyAuthPrompt =>
      'Authentifiziere dich, um den SSH-Schlüssel zu nutzen';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      'Schlüssel zerstört: neue Biometrie wurde registriert. Registriere den öffentlichen Schlüssel erneut auf deinen Servern.';

  @override
  String get keystoreKeyStrongBoxUnavailable =>
      'StrongBox HSM auf diesem Gerät nicht verfügbar';

  @override
  String get keystoreKeyUserAuthRequired =>
      'Biometrie / Geräte-Entsperrung für jede Signatur verlangen';

  @override
  String get keystoreKeyExportDisabled =>
      'Hardware-gebundene Schlüssel können nicht exportiert werden';

  @override
  String get keystoreKeyDeleteWarning =>
      'Das Löschen entfernt den Schlüssel aus dem Hardware-Speicher. Server lehnen ihn ab, bis du einen neuen registrierst.';

  @override
  String get keystoreKeyBiometricNotEnrolled =>
      'Biometrie oder Geräte-PIN zuerst einrichten';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (StrongBox-eligible)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+, nur TEE)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (breiteste Kompatibilität)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM nicht verfügbar';

  @override
  String get keystoreStrongBoxFallbackBody =>
      'Dein Gerät stellt das StrongBox HSM nicht bereit. Stattdessen einen TEE-gestützten Schlüssel anlegen? Bleibt hardware-backed, nur ohne StrongBox-Isolation.';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'TEE verwenden';

  @override
  String get keystoreStrongBoxFallbackCancel => 'Abbrechen';

  @override
  String get fido2BrokerSectionTitle => 'Hardware-Security-Keys';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / Security Key';

  @override
  String get fido2BrokerMacosLabel => 'System-Security-Key-Dialog';

  @override
  String get fido2BrokerIosLabel => 'System-Security-Key (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel => 'System-Security-Key (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => 'Direktes USB HID (CTAP2)';

  @override
  String get fido2BrokerTransportNone => 'Auf dieser Plattform nicht verfügbar';

  @override
  String get fido2BrokerPreferDirectHidTitle =>
      'Direktes USB HID dem System-Dialog vorziehen';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return 'Fortgeschritten: $brokerLabel auf Plattformen umgehen, wo beide Pfade funktionieren. Direktes HID unterstützt mehr Authenticator-Features, benötigt aber je App eine Berechtigung.';
  }

  @override
  String get sshIntegrationSection => 'SSH-Integration';

  @override
  String get fido2BrokerNoTransportSubtitle =>
      'Hardware-Key-Unterstützung ist auf diesem Gerät nicht verfügbar.';

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return 'Auf diesem Gerät ist nur $transport verfügbar; der Schalter ist deaktiviert.';
  }

  @override
  String get hardwareKeyStubBadge => 'Importierter Stub';

  @override
  String get hardwareKeyStubSubtitle =>
      'War auf einem anderen Gerät — hier neu generieren, um ihn zu nutzen';

  @override
  String get hardwareKeyStubRegenerateAction => 'Hier neu generieren';

  @override
  String get hardwareKeyStubRemoveAction => 'Stub entfernen';

  @override
  String get hardwareKeyStubPickerTooltip =>
      'Diesen Schlüssel auf diesem Gerät vor der Nutzung neu generieren';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return 'PKCS#11-Modul für Token \"$token\" auswählen';
  }

  @override
  String get arrowLeft => 'Pfeil links';

  @override
  String get arrowUp => 'Pfeil oben';

  @override
  String get arrowDown => 'Pfeil unten';

  @override
  String get arrowRight => 'Pfeil rechts';

  @override
  String get copyMode => 'Kopiermodus';

  @override
  String get exitCopyMode => 'Kopiermodus beenden';

  @override
  String importedGeneric(String items) {
    return 'Importiert: $items';
  }
}
