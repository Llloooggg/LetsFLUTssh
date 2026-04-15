// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class SFr extends S {
  SFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Annuler';

  @override
  String get close => 'Fermer';

  @override
  String get delete => 'Supprimer';

  @override
  String get save => 'Enregistrer';

  @override
  String get connect => 'Connexion';

  @override
  String get retry => 'Réessayer';

  @override
  String get import_ => 'Importer';

  @override
  String get export_ => 'Exporter';

  @override
  String get rename => 'Renommer';

  @override
  String get create => 'Créer';

  @override
  String get back => 'Retour';

  @override
  String get copy => 'Copier';

  @override
  String get paste => 'Coller';

  @override
  String get select => 'Sélectionner';

  @override
  String get required => 'Requis';

  @override
  String get settings => 'Paramètres';

  @override
  String get appSettings => 'Paramètres de l\'application';

  @override
  String get yes => 'Oui';

  @override
  String get no => 'Non';

  @override
  String get importWhatToImport => 'Éléments à importer :';

  @override
  String get enterMasterPasswordPrompt => 'Entrez le mot de passe principal:';

  @override
  String get nextStep => 'Suivant';

  @override
  String get includeCredentials => 'Inclure mots de passe et clés SSH';

  @override
  String get includePasswords => 'Mots de passe des sessions';

  @override
  String get embeddedKeys => 'Clés intégrées';

  @override
  String get managerKeys => 'Clés du gestionnaire';

  @override
  String get managerKeysMayBeLarge =>
      'Les clés du gestionnaire peuvent dépasser la taille QR';

  @override
  String get qrPasswordWarning =>
      'Les mots de passe seront non chiffrés dans le code QR. Quiconque le scanne peut les voir.';

  @override
  String get sshKeysMayBeLarge => 'Les clés peuvent dépasser la taille QR';

  @override
  String exportTotalSize(String size) {
    return 'Taille totale: $size';
  }

  @override
  String get qrCredentialsWarning =>
      'Les mots de passe et clés SSH SERONT visibles dans le QR code';

  @override
  String get qrCredentialsTooLarge =>
      'Les identifiants rendent le code QR trop grand';

  @override
  String get terminal => 'Terminal';

  @override
  String get files => 'Fichiers';

  @override
  String get transfer => 'Transfert';

  @override
  String get open => 'Ouvrir';

  @override
  String get search => 'Rechercher...';

  @override
  String get filter => 'Filtrer...';

  @override
  String get merge => 'Fusionner';

  @override
  String get replace => 'Remplacer';

  @override
  String get reconnect => 'Reconnecter';

  @override
  String get updateAvailable => 'Mise à jour disponible';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'La version $version est disponible (actuelle : v$current).';
  }

  @override
  String get releaseNotes => 'Notes de version :';

  @override
  String get skipThisVersion => 'Ignorer cette version';

  @override
  String get unskip => 'Ne plus ignorer';

  @override
  String get downloadAndInstall => 'Télécharger et installer';

  @override
  String get openInBrowser => 'Ouvrir dans le navigateur';

  @override
  String get couldNotOpenBrowser =>
      'Impossible d\'ouvrir le navigateur — URL copiée dans le presse-papiers';

  @override
  String get checkForUpdates => 'Vérifier les mises à jour';

  @override
  String get checkForUpdatesOnStartup =>
      'Vérifier les mises à jour au démarrage';

  @override
  String get checking => 'Vérification...';

  @override
  String get youreUpToDate => 'Vous êtes à jour';

  @override
  String get updateCheckFailed => 'La vérification a échoué';

  @override
  String get unknownError => 'Erreur inconnue';

  @override
  String downloadingPercent(int percent) {
    return 'Téléchargement... $percent%';
  }

  @override
  String get downloadComplete => 'Téléchargement terminé';

  @override
  String get installNow => 'Installer maintenant';

  @override
  String get couldNotOpenInstaller => 'Impossible d\'ouvrir l\'installateur';

  @override
  String versionAvailable(String version) {
    return 'Version $version disponible';
  }

  @override
  String currentVersion(String version) {
    return 'Actuelle : v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'Clé SSH reçue : $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return '$count session(s) importée(s) via QR';
  }

  @override
  String importedSessions(int count) {
    return '$count session(s) importée(s)';
  }

  @override
  String importFailed(String error) {
    return 'Échec de l\'import : $error';
  }

  @override
  String get sessions => 'Sessions';

  @override
  String get emptyFolders => 'Dossiers vides';

  @override
  String get sessionsHeader => 'SESSIONS';

  @override
  String get savedSessions => 'Sessions enregistrées';

  @override
  String get activeConnections => 'Connexions actives';

  @override
  String get openTabs => 'Onglets ouverts';

  @override
  String get noSavedSessions => 'Aucune session enregistrée';

  @override
  String get addSession => 'Ajouter une session';

  @override
  String get noSessions => 'Aucune session';

  @override
  String get noSessionsToExport => 'Aucune session à exporter';

  @override
  String nSelectedCount(int count) {
    return '$count sélectionné(s)';
  }

  @override
  String get selectAll => 'Tout sélectionner';

  @override
  String get deselectAll => 'Tout désélectionner';

  @override
  String get moveTo => 'Déplacer vers...';

  @override
  String get moveToFolder => 'Déplacer vers le dossier';

  @override
  String get rootFolder => '/ (racine)';

  @override
  String get newFolder => 'Nouveau dossier';

  @override
  String get newConnection => 'Nouvelle connexion';

  @override
  String get editConnection => 'Modifier la connexion';

  @override
  String get duplicate => 'Dupliquer';

  @override
  String get deleteSession => 'Supprimer la session';

  @override
  String get renameFolder => 'Renommer le dossier';

  @override
  String get deleteFolder => 'Supprimer le dossier';

  @override
  String get deleteSelected => 'Supprimer la sélection';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return 'Supprimer $parts ?\n\nCette action est irréversible.';
  }

  @override
  String nSessions(int count) {
    return '$count session(s)';
  }

  @override
  String nFolders(int count) {
    return '$count dossier(s)';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'Supprimer le dossier « $name » ?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'Cela supprimera également $count session(s) à l\'intérieur.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return 'Supprimer « $name » ?';
  }

  @override
  String get connection => 'Connexion';

  @override
  String get auth => 'Authentification';

  @override
  String get options => 'Options';

  @override
  String get sessionName => 'Nom de la session';

  @override
  String get hintMyServer => 'Mon serveur';

  @override
  String get hostRequired => 'Hôte *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'Port';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'Nom d\'utilisateur *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'Mot de passe';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'Phrase secrète de la clé';

  @override
  String get hintOptional => 'Facultatif';

  @override
  String get hidePemText => 'Masquer le texte PEM';

  @override
  String get pastePemKeyText => 'Coller le texte de la clé PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet =>
      'Aucune option supplémentaire pour l\'instant';

  @override
  String get saveAndConnect => 'Enregistrer et connecter';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst =>
      'Fournissez d\'abord un fichier de clé ou un texte PEM';

  @override
  String get keyTextPem => 'Texte de la clé (PEM)';

  @override
  String get selectKeyFile => 'Sélectionner un fichier de clé';

  @override
  String get clearKeyFile => 'Effacer le fichier de clé';

  @override
  String get authOrDivider => 'OU';

  @override
  String get providePasswordOrKey =>
      'Fournissez un mot de passe ou une clé SSH';

  @override
  String get quickConnect => 'Connexion rapide';

  @override
  String get scanQrCode => 'Scanner le QR code';

  @override
  String get qrGenerationFailed => 'Échec de la génération du QR code';

  @override
  String get scanWithCameraApp =>
      'Scannez avec n\'importe quelle application appareil photo\nsur un appareil où LetsFLUTssh est installé.';

  @override
  String get noPasswordsInQr => 'Aucun mot de passe ni clé dans ce QR code';

  @override
  String get copyLink => 'Copier le lien';

  @override
  String get linkCopied => 'Lien copié dans le presse-papiers';

  @override
  String get hostKeyChanged => 'Clé de l\'hôte modifiée !';

  @override
  String get unknownHost => 'Hôte inconnu';

  @override
  String get hostKeyChangedWarning =>
      'ATTENTION : La clé de l\'hôte de ce serveur a changé. Cela pourrait indiquer une attaque de type « man-in-the-middle », ou le serveur a peut-être été réinstallé.';

  @override
  String get unknownHostMessage =>
      'L\'authenticité de cet hôte ne peut pas être vérifiée. Êtes-vous sûr de vouloir continuer la connexion ?';

  @override
  String get host => 'Hôte';

  @override
  String get keyType => 'Type de clé';

  @override
  String get fingerprint => 'Empreinte';

  @override
  String get fingerprintCopied => 'Empreinte copiée';

  @override
  String get copyFingerprint => 'Copier l\'empreinte';

  @override
  String get acceptAnyway => 'Accepter quand même';

  @override
  String get accept => 'Accepter';

  @override
  String get importData => 'Importer des données';

  @override
  String get masterPassword => 'Mot de passe principal';

  @override
  String get confirmPassword => 'Confirmer le mot de passe';

  @override
  String get importModeMergeDescription =>
      'Ajouter les nouvelles sessions, conserver les existantes';

  @override
  String get importModeReplaceDescription =>
      'Remplacer toutes les sessions par celles importées';

  @override
  String errorPrefix(String error) {
    return 'Erreur : $error';
  }

  @override
  String get folderName => 'Nom du dossier';

  @override
  String get newName => 'Nouveau nom';

  @override
  String deleteItems(String names) {
    return 'Supprimer $names ?';
  }

  @override
  String deleteNItems(int count) {
    return 'Supprimer $count éléments';
  }

  @override
  String deletedItem(String name) {
    return '$name supprimé';
  }

  @override
  String deletedNItems(int count) {
    return '$count éléments supprimés';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'Échec de la création du dossier : $error';
  }

  @override
  String failedToRename(String error) {
    return 'Échec du renommage : $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return 'Échec de la suppression de $name : $error';
  }

  @override
  String get editPath => 'Modifier le chemin';

  @override
  String get root => 'Racine';

  @override
  String get controllersNotInitialized => 'Contrôleurs non initialisés';

  @override
  String get initializingSftp => 'Initialisation SFTP...';

  @override
  String get clearHistory => 'Effacer l\'historique';

  @override
  String get noTransfersYet => 'Aucun transfert pour l\'instant';

  @override
  String get duplicateTab => 'Dupliquer l\'onglet';

  @override
  String get duplicateTabShortcut => 'Dupliquer l\'onglet (Ctrl+\\)';

  @override
  String get copyDown => 'Copier en bas';

  @override
  String get previous => 'Précédent';

  @override
  String get next => 'Suivant';

  @override
  String get closeEsc => 'Fermer (Esc)';

  @override
  String get closeAll => 'Tout fermer';

  @override
  String get closeOthers => 'Fermer les autres';

  @override
  String get closeTabsToTheLeft => 'Fermer les onglets à gauche';

  @override
  String get closeTabsToTheRight => 'Fermer les onglets à droite';

  @override
  String get sortByName => 'Trier par nom';

  @override
  String get sortByStatus => 'Trier par statut';

  @override
  String get noActiveSession => 'Aucune session active';

  @override
  String get createConnectionHint =>
      'Créez une nouvelle connexion ou sélectionnez-en une dans la barre latérale';

  @override
  String get hideSidebar => 'Masquer la barre latérale (Ctrl+B)';

  @override
  String get showSidebar => 'Afficher la barre latérale (Ctrl+B)';

  @override
  String get language => 'Langue';

  @override
  String get languageSystemDefault => 'Auto';

  @override
  String get theme => 'Thème';

  @override
  String get themeDark => 'Sombre';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeSystem => 'Système';

  @override
  String get appearance => 'Apparence';

  @override
  String get connectionSection => 'Connexion';

  @override
  String get transfers => 'Transferts';

  @override
  String get data => 'Données';

  @override
  String get logging => 'Journalisation';

  @override
  String get updates => 'Mises à jour';

  @override
  String get about => 'À propos';

  @override
  String get resetToDefaults => 'Réinitialiser par défaut';

  @override
  String get uiScale => 'Échelle de l\'interface';

  @override
  String get terminalFontSize => 'Taille de police du terminal';

  @override
  String get scrollbackLines => 'Lignes de défilement';

  @override
  String get keepAliveInterval => 'Intervalle Keep-Alive (sec)';

  @override
  String get sshTimeout => 'Délai SSH (sec)';

  @override
  String get defaultPort => 'Port par défaut';

  @override
  String get parallelWorkers => 'Workers parallèles';

  @override
  String get maxHistory => 'Historique max';

  @override
  String get calculateFolderSizes => 'Calculer la taille des dossiers';

  @override
  String get exportData => 'Exporter les données';

  @override
  String get exportDataSubtitle =>
      'Enregistrer les sessions, la configuration et les clés dans un fichier .lfs chiffré';

  @override
  String get importDataSubtitle => 'Charger les données depuis un fichier .lfs';

  @override
  String get importFromSshConfig => 'Importer depuis la configuration OpenSSH';

  @override
  String get importFromSshConfigSubtitle =>
      'Import ponctuel des hôtes depuis ~/.ssh/config';

  @override
  String get sshConfigPickerTitle =>
      'Sélectionner un fichier de configuration OpenSSH';

  @override
  String get sshConfigPreviewTitle => 'Import de configuration SSH';

  @override
  String sshConfigPreviewHostsFound(int count) {
    return '$count hôte(s) trouvé(s)';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'Aucun hôte importable trouvé dans ce fichier.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'Impossible de lire les fichiers de clés pour : $hosts. Ces hôtes seront importés sans identifiants.';
  }

  @override
  String sshConfigPreviewFolderLabel(String folder) {
    return 'Importé dans le dossier : $folder';
  }

  @override
  String sshConfigImportedHosts(int count) {
    return '$count hôte(s) importé(s) depuis la configuration SSH';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '~/.ssh $date';
  }

  @override
  String get exportArchive => 'Exporter l\'archive';

  @override
  String get exportArchiveSubtitle =>
      'Enregistrer les sessions, la configuration et les clés dans un fichier .lfs chiffré';

  @override
  String get exportQrCode => 'Exporter le code QR';

  @override
  String get exportQrCodeSubtitle =>
      'Partager les sessions et clés sélectionnées via un code QR';

  @override
  String get importArchive => 'Importer une archive';

  @override
  String get importArchiveSubtitle =>
      'Charger les données depuis un fichier .lfs';

  @override
  String get importOpensshConfig => 'Importer la configuration OpenSSH';

  @override
  String get importOpensshConfigSubtitle =>
      'Import ponctuel des hôtes depuis ~/.ssh/config';

  @override
  String get importSshKeys => 'Importer les clés SSH depuis ~/.ssh';

  @override
  String get importSshKeysSubtitle =>
      'Analyser ~/.ssh à la recherche de clés privées et ajouter celles sélectionnées au gestionnaire de clés';

  @override
  String get importSshKeysTitle => 'Importer les clés SSH';

  @override
  String importSshKeysFound(int count) {
    return '$count clé(s) trouvée(s) — choisissez lesquelles importer';
  }

  @override
  String get importSshKeysNoneFound => 'Aucune clé privée trouvée dans ~/.ssh.';

  @override
  String importedSshKeys(int count) {
    return '$count clé(s) importée(s)';
  }

  @override
  String importedSshKeysWithSkipped(int imported, int skipped) {
    return '$imported nouvelle(s) clé(s) importée(s), $skipped déjà dans le magasin';
  }

  @override
  String get sshKeyAlreadyImported => 'déjà dans le magasin';

  @override
  String get setMasterPasswordHint =>
      'Définissez un mot de passe principal pour chiffrer l\'archive.';

  @override
  String get passwordsDoNotMatch => 'Les mots de passe ne correspondent pas';

  @override
  String exportedTo(String path) {
    return 'Exporté vers : $path';
  }

  @override
  String exportFailed(String error) {
    return 'Échec de l\'export : $error';
  }

  @override
  String get pathToLfsFile => 'Chemin du fichier .lfs';

  @override
  String get hintLfsPath => '/chemin/vers/export.lfs';

  @override
  String get browse => 'Parcourir';

  @override
  String get shareViaQrCode => 'Partager via QR code';

  @override
  String get shareViaQrSubtitle =>
      'Exporter les sessions en QR code pour les scanner depuis un autre appareil';

  @override
  String get dataLocation => 'Emplacement des données';

  @override
  String get pathCopied => 'Chemin copié dans le presse-papiers';

  @override
  String get urlCopied => 'URL copiée dans le presse-papiers';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — Client SSH/SFTP';
  }

  @override
  String get sourceCode => 'Code source';

  @override
  String get enableLogging => 'Activer la journalisation';

  @override
  String get logIsEmpty => 'Le journal est vide';

  @override
  String logExportedTo(String path) {
    return 'Journal exporté vers : $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Échec de l\'export du journal : $error';
  }

  @override
  String get logsCleared => 'Journaux effacés';

  @override
  String get copiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get copyLog => 'Copier le journal';

  @override
  String get exportLog => 'Exporter le journal';

  @override
  String get clearLogs => 'Effacer les journaux';

  @override
  String get local => 'Local';

  @override
  String get remote => 'Distant';

  @override
  String get pickFolder => 'Choisir un dossier';

  @override
  String get refresh => 'Actualiser';

  @override
  String get up => 'Remonter';

  @override
  String get emptyDirectory => 'Répertoire vide';

  @override
  String get cancelSelection => 'Annuler la sélection';

  @override
  String get openSftpBrowser => 'Ouvrir le navigateur SFTP';

  @override
  String get openSshTerminal => 'Ouvrir le terminal SSH';

  @override
  String get noActiveFileBrowsers => 'Aucun navigateur de fichiers actif';

  @override
  String get useSftpFromSessions => 'Utilisez « SFTP » depuis Sessions';

  @override
  String get anotherInstanceRunning =>
      'Une autre instance de LetsFLUTssh est déjà en cours d\'exécution.';

  @override
  String importFailedShort(String error) {
    return 'Échec de l\'import : $error';
  }

  @override
  String get saveLogAs => 'Enregistrer le journal sous';

  @override
  String get chooseSaveLocation => 'Choisir l\'emplacement de sauvegarde';

  @override
  String get forward => 'Suivant';

  @override
  String get name => 'Nom';

  @override
  String get size => 'Taille';

  @override
  String get modified => 'Modifié';

  @override
  String get mode => 'Mode';

  @override
  String get owner => 'Propriétaire';

  @override
  String get connectionError => 'Erreur de connexion';

  @override
  String get resizeWindowToViewFiles =>
      'Redimensionnez la fenêtre pour afficher les fichiers';

  @override
  String get completed => 'Terminé';

  @override
  String get connected => 'Connecté';

  @override
  String get disconnected => 'Déconnecté';

  @override
  String get exit => 'Quitter';

  @override
  String get exitConfirmation =>
      'Les sessions actives seront déconnectées. Quitter ?';

  @override
  String get hintFolderExample => 'ex. Production';

  @override
  String get credentialsNotSet => 'Identifiants non définis';

  @override
  String get exportSessionsViaQr => 'Exporter les sessions via QR';

  @override
  String get qrNoCredentialsWarning =>
      'Les mots de passe et clés SSH ne sont PAS inclus.\nLes sessions importées devront être complétées avec les identifiants.';

  @override
  String get qrTooManyForSingleCode =>
      'Trop de sessions pour un seul QR code. Désélectionnez-en ou utilisez l\'export .lfs.';

  @override
  String get qrTooLarge =>
      'Trop volumineux — désélectionnez des éléments ou utilisez l\'export en fichier .lfs.';

  @override
  String get exportAll => 'Tout exporter';

  @override
  String get showQr => 'Afficher le QR';

  @override
  String get sort => 'Trier';

  @override
  String get resizePanelDivider => 'Redimensionner le séparateur de panneaux';

  @override
  String get youreRunningLatest => 'Vous utilisez la dernière version';

  @override
  String get liveLog => 'Log en direct';

  @override
  String transferNItems(int count) {
    return 'Transférer $count éléments';
  }

  @override
  String get time => 'Temps';

  @override
  String get failed => 'Échoué';

  @override
  String get errOperationNotPermitted => 'Opération non autorisée';

  @override
  String get errNoSuchFileOrDirectory => 'Fichier ou répertoire introuvable';

  @override
  String get errNoSuchProcess => 'Aucun processus correspondant';

  @override
  String get errIoError => 'Erreur d\'E/S';

  @override
  String get errBadFileDescriptor => 'Descripteur de fichier invalide';

  @override
  String get errResourceTemporarilyUnavailable =>
      'Ressource temporairement indisponible';

  @override
  String get errOutOfMemory => 'Mémoire insuffisante';

  @override
  String get errPermissionDenied => 'Autorisation refusée';

  @override
  String get errFileExists => 'Le fichier existe déjà';

  @override
  String get errNotADirectory => 'N\'est pas un répertoire';

  @override
  String get errIsADirectory => 'Est un répertoire';

  @override
  String get errInvalidArgument => 'Argument invalide';

  @override
  String get errTooManyOpenFiles => 'Trop de fichiers ouverts';

  @override
  String get errNoSpaceLeftOnDevice =>
      'Plus d\'espace disponible sur l\'appareil';

  @override
  String get errReadOnlyFileSystem => 'Système de fichiers en lecture seule';

  @override
  String get errBrokenPipe => 'Tube cassé';

  @override
  String get errFileNameTooLong => 'Nom de fichier trop long';

  @override
  String get errDirectoryNotEmpty => 'Le répertoire n\'est pas vide';

  @override
  String get errAddressAlreadyInUse => 'Adresse déjà utilisée';

  @override
  String get errCannotAssignAddress =>
      'Impossible d\'attribuer l\'adresse demandée';

  @override
  String get errNetworkIsDown => 'Réseau hors service';

  @override
  String get errNetworkIsUnreachable => 'Réseau injoignable';

  @override
  String get errConnectionResetByPeer => 'Connexion réinitialisée par le pair';

  @override
  String get errConnectionTimedOut => 'Délai de connexion dépassé';

  @override
  String get errConnectionRefused => 'Connexion refusée';

  @override
  String get errHostIsDown => 'L\'hôte est hors service';

  @override
  String get errNoRouteToHost => 'Aucune route vers l\'hôte';

  @override
  String get errConnectionAborted => 'Connexion interrompue';

  @override
  String get errAlreadyConnected => 'Déjà connecté';

  @override
  String get errNotConnected => 'Non connecté';

  @override
  String errSshConnectFailed(String host, int port) {
    return 'Échec de la connexion à $host:$port';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return 'Échec de l\'authentification pour $user@$host';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return 'Échec de la connexion à $host:$port';
  }

  @override
  String get errSshAuthAborted => 'Authentification annulée';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return 'Clé de l\'hôte rejetée pour $host:$port — acceptez la clé de l\'hôte ou vérifiez known_hosts';
  }

  @override
  String get errSshOpenShellFailed => 'Impossible d\'ouvrir le shell';

  @override
  String get errSshLoadKeyFileFailed =>
      'Impossible de charger le fichier de clé SSH';

  @override
  String get errSshParseKeyFailed =>
      'Impossible d\'analyser les données de clé PEM';

  @override
  String get errSshConnectionDisposed => 'Connexion terminée';

  @override
  String get errSshNotConnected => 'Non connecté';

  @override
  String get errConnectionFailed => 'Échec de la connexion';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'Délai de connexion dépassé après $seconds secondes';
  }

  @override
  String get errSessionClosed => 'Session fermée';

  @override
  String errShellError(String error) {
    return 'Erreur du shell : $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'Échec de la reconnexion : $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'Échec de l\'initialisation SFTP : $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Échec du téléchargement : $error';
  }

  @override
  String get errDecryptionFailed =>
      'Impossible de déchiffrer les identifiants. Le fichier de clé est peut-être corrompu.';

  @override
  String errWithPath(String error, String path) {
    return '$error : $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'Identifiant';

  @override
  String get protocol => 'Protocole';

  @override
  String get typeLabel => 'Type';

  @override
  String get folder => 'Dossier';

  @override
  String nSubitems(int count) {
    return '$count élément(s)';
  }

  @override
  String get subitems => 'Éléments';

  @override
  String get storagePermissionRequired =>
      'Autorisation de stockage requise pour parcourir les fichiers locaux';

  @override
  String get grantPermission => 'Accorder l\'autorisation';

  @override
  String get storagePermissionLimited =>
      'Accès limité — accordez l\'autorisation de stockage complète pour tous les fichiers';

  @override
  String progressConnecting(String host, int port) {
    return 'Connexion à $host:$port';
  }

  @override
  String get progressVerifyingHostKey => 'Vérification de la clé hôte';

  @override
  String progressAuthenticating(String user) {
    return 'Authentification en tant que $user';
  }

  @override
  String get progressOpeningShell => 'Ouverture du shell';

  @override
  String get progressOpeningSftp => 'Ouverture du canal SFTP';

  @override
  String get transfersLabel => 'Transferts :';

  @override
  String transferCountActive(int count) {
    return '$count actifs';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count en file d\'attente';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count dans l\'historique';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'Créé : $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'Démarré : $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'Terminé : $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'Durée : $duration';
  }

  @override
  String get transferStatusQueued => 'En file d\'attente';

  @override
  String get transferStartingUpload => 'Démarrage de l\'envoi...';

  @override
  String get transferStartingDownload => 'Démarrage du téléchargement...';

  @override
  String get transferCopying => 'Copie en cours...';

  @override
  String get transferDone => 'Terminé';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total fichiers';
  }

  @override
  String get folderNameLabel => 'NOM DU DOSSIER';

  @override
  String folderAlreadyExists(String name) {
    return 'Le dossier \"$name\" existe déjà';
  }

  @override
  String get dropKeyFileHere => 'Déposez le fichier de clé ici';

  @override
  String get sessionNoCredentials =>
      'La session n\'a pas d\'identifiants — modifiez-la pour ajouter un mot de passe ou une clé';

  @override
  String dragItemCount(int count) {
    return '$count éléments';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'Tout sélectionner ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'Taille : $size Ko / $max Ko max.';
  }

  @override
  String get noActiveTerminals => 'Aucun terminal actif';

  @override
  String get connectFromSessionsTab =>
      'Connectez-vous depuis l\'onglet Sessions';

  @override
  String fileNotFound(String path) {
    return 'Fichier introuvable : $path';
  }

  @override
  String get sshConnectionChannel => 'Connexion SSH';

  @override
  String get sshConnectionChannelDesc =>
      'Maintient les connexions SSH en arrière-plan.';

  @override
  String get sshActive => 'SSH actif';

  @override
  String activeConnectionCount(int count) {
    return '$count connexion(s) active(s)';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count éléments, $size';
  }

  @override
  String get maximize => 'Maximiser';

  @override
  String get restore => 'Restaurer';

  @override
  String get duplicateDownShortcut => 'Dupliquer en bas (Ctrl+Shift+\\)';

  @override
  String get security => 'Sécurité';

  @override
  String get knownHosts => 'Hôtes connus';

  @override
  String get knownHostsSubtitle =>
      'Gestion des empreintes de serveurs SSH de confiance';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hôtes connus',
      one: '1 hôte connu',
      zero: 'Aucun hôte connu',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'Aucun hôte connu. Connectez-vous à un serveur pour en ajouter un.';

  @override
  String get removeHost => 'Supprimer l\'hôte';

  @override
  String removeHostConfirm(String host) {
    return 'Supprimer $host des hôtes connus ? La clé sera à nouveau vérifiée lors de la prochaine connexion.';
  }

  @override
  String get clearAllKnownHosts => 'Supprimer tous les hôtes connus';

  @override
  String get clearAllKnownHostsConfirm =>
      'Supprimer tous les hôtes connus ? Chaque clé de serveur devra être re-vérifiée.';

  @override
  String get importKnownHosts => 'Importer les hôtes connus';

  @override
  String get importKnownHostsSubtitle =>
      'Import depuis un fichier OpenSSH known_hosts';

  @override
  String get exportKnownHosts => 'Exporter les hôtes connus';

  @override
  String importedHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouveaux hôtes importés',
      one: '1 nouvel hôte importé',
      zero: 'Aucun nouvel hôte importé',
    );
    return '$_temp0';
  }

  @override
  String get clearedAllHosts => 'Tous les hôtes connus supprimés';

  @override
  String removedHost(String host) {
    return '$host supprimé';
  }

  @override
  String get noHostsToExport => 'Aucun hôte à exporter';

  @override
  String get tools => 'Outils';

  @override
  String get sshKeys => 'Clés SSH';

  @override
  String get sshKeysSubtitle =>
      'Gestion des paires de clés SSH pour l\'authentification';

  @override
  String get noKeys => 'Aucune clé SSH. Importez ou générez-en une.';

  @override
  String get generateKey => 'Générer une clé';

  @override
  String get importKey => 'Importer une clé';

  @override
  String get keyLabel => 'Nom de la clé';

  @override
  String get keyLabelHint => 'ex. Serveur de travail, GitHub';

  @override
  String get selectKeyType => 'Type de clé';

  @override
  String get generating => 'Génération...';

  @override
  String keyGenerated(String label) {
    return 'Clé générée : $label';
  }

  @override
  String keyImported(String label) {
    return 'Clé importée : $label';
  }

  @override
  String get deleteKey => 'Supprimer la clé';

  @override
  String deleteKeyConfirm(String label) {
    return 'Supprimer la clé \"$label\" ? Les sessions l\'utilisant perdront l\'accès.';
  }

  @override
  String keyDeleted(String label) {
    return 'Clé supprimée : $label';
  }

  @override
  String get publicKey => 'Clé publique';

  @override
  String get publicKeyCopied => 'Clé publique copiée dans le presse-papiers';

  @override
  String get pastePrivateKey => 'Coller la clé privée (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Données de clé PEM invalides';

  @override
  String get selectFromKeyStore => 'Sélectionner depuis le trousseau';

  @override
  String get noKeySelected => 'Aucune clé sélectionnée';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clés',
      one: '1 clé',
      zero: 'Aucune clé',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'Générée';

  @override
  String get passphraseRequired => 'Phrase secrète requise';

  @override
  String passphrasePrompt(String host) {
    return 'La clé SSH pour $host est chiffrée. Entrez la phrase secrète pour la déverrouiller.';
  }

  @override
  String get passphraseWrong =>
      'Phrase secrète incorrecte. Veuillez réessayer.';

  @override
  String get passphrase => 'Phrase secrète';

  @override
  String get rememberPassphrase => 'Retenir pour cette session';

  @override
  String get unlock => 'Déverrouiller';

  @override
  String get masterPasswordSubtitle =>
      'Protéger les identifiants enregistrés par mot de passe';

  @override
  String get setMasterPassword => 'Définir le mot de passe principal';

  @override
  String get changeMasterPassword => 'Modifier le mot de passe principal';

  @override
  String get removeMasterPassword => 'Supprimer le mot de passe principal';

  @override
  String get masterPasswordEnabled =>
      'Les identifiants sont protégés par le mot de passe principal';

  @override
  String get masterPasswordDisabled =>
      'Les identifiants utilisent une clé auto-générée (sans mot de passe)';

  @override
  String get enterMasterPassword =>
      'Entrez le mot de passe principal pour accéder à vos identifiants.';

  @override
  String get wrongMasterPassword =>
      'Mot de passe incorrect. Veuillez réessayer.';

  @override
  String get newPassword => 'Nouveau mot de passe';

  @override
  String get currentPassword => 'Mot de passe actuel';

  @override
  String get passwordTooShort =>
      'Le mot de passe doit contenir au moins 8 caractères';

  @override
  String get masterPasswordSet => 'Mot de passe principal activé';

  @override
  String get masterPasswordChanged => 'Mot de passe principal modifié';

  @override
  String get masterPasswordRemoved => 'Mot de passe principal supprimé';

  @override
  String get masterPasswordWarning =>
      'Si vous oubliez ce mot de passe, tous les mots de passe et clés SSH enregistrés seront perdus. La récupération est impossible.';

  @override
  String get forgotPassword => 'Mot de passe oublié ?';

  @override
  String get forgotPasswordWarning =>
      'Ceci supprimera TOUS les mots de passe, clés SSH et phrases secrètes enregistrés. Les sessions et paramètres seront conservés. Cette action est irréversible.';

  @override
  String get resetAndDeleteCredentials =>
      'Réinitialiser et supprimer les données';

  @override
  String get credentialsReset =>
      'Tous les identifiants enregistrés ont été supprimés';

  @override
  String get derivingKey => 'Dérivation de la clé de chiffrement...';

  @override
  String get reEncrypting => 'Re-chiffrement des données...';

  @override
  String get confirmRemoveMasterPassword =>
      'Entrez votre mot de passe actuel pour supprimer la protection par mot de passe principal. Les identifiants seront re-chiffrés avec une clé auto-générée.';

  @override
  String get securitySetupTitle => 'Configuration de la sécurité';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'Trousseau du système détecté ($keychainName). Vos données seront automatiquement chiffrées avec votre trousseau système.';
  }

  @override
  String get securitySetupKeychainOptional =>
      'Vous pouvez aussi définir un mot de passe principal pour une protection supplémentaire.';

  @override
  String get securitySetupNoKeychain =>
      'Aucun trousseau système détecté. Sans trousseau, vos données de session (hôtes, mots de passe, clés) seront stockées en clair.';

  @override
  String get securitySetupNoKeychainHint =>
      'C\'est normal sous WSL, Linux sans interface graphique ou installations minimales. Pour activer le trousseau sous Linux : installez libsecret et un démon de trousseau (ex. gnome-keyring).';

  @override
  String get securitySetupRecommendMasterPassword =>
      'Nous recommandons de définir un mot de passe principal pour protéger vos données.';

  @override
  String get continueWithKeychain => 'Continuer avec le trousseau';

  @override
  String get continueWithoutEncryption => 'Continuer sans chiffrement';

  @override
  String get securityLevel => 'Niveau de sécurité';

  @override
  String get securityLevelPlaintext => 'Aucun (texte clair)';

  @override
  String get securityLevelKeychain => 'Trousseau du système';

  @override
  String get securityLevelMasterPassword => 'Mot de passe principal';

  @override
  String get keychainStatus => 'Trousseau';

  @override
  String keychainAvailable(String name) {
    return 'Disponible ($name)';
  }

  @override
  String get keychainNotAvailable => 'Non disponible';

  @override
  String get enableKeychain => 'Activer le chiffrement par trousseau';

  @override
  String get enableKeychainSubtitle =>
      'Rechiffrer les données stockées avec le trousseau système';

  @override
  String get keychainEnabled => 'Chiffrement par trousseau activé';

  @override
  String get manageMasterPassword => 'Gérer le mot de passe principal';

  @override
  String get manageMasterPasswordSubtitle =>
      'Définir, modifier ou supprimer le mot de passe principal';

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
  String get fullBackup => 'Sauvegarde complète';

  @override
  String get sessionsOnly => 'Sessions uniquement';

  @override
  String get sessionKeysFromManager => 'Clés de session du gestionnaire';

  @override
  String get allKeysFromManager => 'Toutes les clés du gestionnaire';

  @override
  String exportTags(int count) {
    return 'Étiquettes ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'Extraits ($count)';
  }

  @override
  String get disableKeychain => 'Désactiver le chiffrement du trousseau';

  @override
  String get disableKeychainSubtitle =>
      'Passer au stockage en texte clair (non recommandé)';

  @override
  String get disableKeychainConfirm =>
      'La base de données sera rechiffrée sans clé. Les sessions et les clés seront stockées en texte clair sur le disque. Continuer ?';

  @override
  String get keychainDisabled => 'Chiffrement du trousseau désactivé';

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
