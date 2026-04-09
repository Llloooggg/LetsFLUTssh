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
  String get couldNotOpenBrowser => 'Impossible d\'ouvrir le navigateur — URL copiée dans le presse-papiers';

  @override
  String get checkForUpdates => 'Vérifier les mises à jour';

  @override
  String get checkForUpdatesOnStartup => 'Vérifier les mises à jour au démarrage';

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
  String get noAdditionalOptionsYet => 'Aucune option supplémentaire pour l\'instant';

  @override
  String get saveAndConnect => 'Enregistrer et connecter';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst => 'Fournissez d\'abord un fichier de clé ou un texte PEM';

  @override
  String get keyTextPem => 'Texte de la clé (PEM)';

  @override
  String get selectKeyFile => 'Sélectionner un fichier de clé';

  @override
  String get clearKeyFile => 'Effacer le fichier de clé';

  @override
  String get authOrDivider => 'OU';

  @override
  String get providePasswordOrKey => 'Fournissez un mot de passe ou une clé SSH';

  @override
  String get quickConnect => 'Connexion rapide';

  @override
  String get scanQrCode => 'Scanner le QR code';

  @override
  String get qrGenerationFailed => 'Échec de la génération du QR code';

  @override
  String get scanWithCameraApp => 'Scannez avec n\'importe quelle application appareil photo\nsur un appareil où LetsFLUTssh est installé.';

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
  String get hostKeyChangedWarning => 'ATTENTION : La clé de l\'hôte de ce serveur a changé. Cela pourrait indiquer une attaque de type « man-in-the-middle », ou le serveur a peut-être été réinstallé.';

  @override
  String get unknownHostMessage => 'L\'authenticité de cet hôte ne peut pas être vérifiée. Êtes-vous sûr de vouloir continuer la connexion ?';

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
  String get importModeMergeDescription => 'Ajouter les nouvelles sessions, conserver les existantes';

  @override
  String get importModeReplaceDescription => 'Remplacer toutes les sessions par celles importées';

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
  String get createConnectionHint => 'Créez une nouvelle connexion ou sélectionnez-en une dans la barre latérale';

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
  String get exportDataSubtitle => 'Enregistrer les sessions, la configuration et les clés dans un fichier .lfs chiffré';

  @override
  String get importDataSubtitle => 'Charger les données depuis un fichier .lfs';

  @override
  String get setMasterPasswordHint => 'Définissez un mot de passe principal pour chiffrer l\'archive.';

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
  String get shareViaQrSubtitle => 'Exporter les sessions en QR code pour les scanner depuis un autre appareil';

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
  String get anotherInstanceRunning => 'Une autre instance de LetsFLUTssh est déjà en cours d\'exécution.';

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
  String get resizeWindowToViewFiles => 'Redimensionnez la fenêtre pour afficher les fichiers';

  @override
  String get completed => 'Terminé';

  @override
  String get connected => 'Connecté';

  @override
  String get disconnected => 'Déconnecté';

  @override
  String get exit => 'Quitter';

  @override
  String get exitConfirmation => 'Les sessions actives seront déconnectées. Quitter ?';

  @override
  String get hintFolderExample => 'ex. Production';

  @override
  String get credentialsNotSet => 'Identifiants non définis';

  @override
  String get exportSessionsViaQr => 'Exporter les sessions via QR';

  @override
  String get qrNoCredentialsWarning => 'Les mots de passe et clés SSH ne sont PAS inclus.\nLes sessions importées devront être complétées avec les identifiants.';

  @override
  String get qrTooManyForSingleCode => 'Trop de sessions pour un seul QR code. Désélectionnez-en ou utilisez l\'export .lfs.';

  @override
  String get qrTooLarge => 'Trop volumineux — désélectionnez des sessions ou utilisez l\'export en fichier .lfs.';

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
  String get errResourceTemporarilyUnavailable => 'Ressource temporairement indisponible';

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
  String get errNoSpaceLeftOnDevice => 'Plus d\'espace disponible sur l\'appareil';

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
  String get errCannotAssignAddress => 'Impossible d\'attribuer l\'adresse demandée';

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
  String get errSshLoadKeyFileFailed => 'Impossible de charger le fichier de clé SSH';

  @override
  String get errSshParseKeyFailed => 'Impossible d\'analyser les données de clé PEM';

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
  String get errDecryptionFailed => 'Impossible de déchiffrer les identifiants. Le fichier de clé est peut-être corrompu.';

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
  String get storagePermissionRequired => 'Autorisation de stockage requise pour parcourir les fichiers locaux';

  @override
  String get grantPermission => 'Accorder l\'autorisation';

  @override
  String get storagePermissionLimited => 'Accès limité — accordez l\'autorisation de stockage complète pour tous les fichiers';

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
  String get sessionNoCredentials => 'Session has no credentials — edit it first to add a password or key';

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
  String get sshConnectionChannelDesc => 'Keeps SSH connections alive in the background.';

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
  String get maximize => 'Maximiser';

  @override
  String get restore => 'Restaurer';

  @override
  String get duplicateDownShortcut => 'Dupliquer en bas (Ctrl+Shift+\\)';

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
  String get knownHostsEmpty => 'No known hosts yet. Connect to a server to add one.';

  @override
  String get removeHost => 'Remove Host';

  @override
  String removeHostConfirm(String host) {
    return 'Remove $host from known hosts? You will be prompted to verify its key again on next connection.';
  }

  @override
  String get clearAllKnownHosts => 'Clear All Known Hosts';

  @override
  String get clearAllKnownHostsConfirm => 'Remove all known hosts? You will be prompted to verify each server key again.';

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
}
