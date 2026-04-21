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
  String get infoDialogProtectsHeader => 'Protège contre';

  @override
  String get infoDialogDoesNotProtectHeader => 'Ne protège pas contre';

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
  String get exportWhatToExport => 'Éléments à exporter :';

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
      'Les clés SSH sont désactivées par défaut à l\'export.';

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
  String get noResults => 'Aucun résultat';

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
  String get checkNow => 'Vérifier';

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
  String get openReleasePage => 'Ouvrir la page de release';

  @override
  String get couldNotOpenInstaller => 'Impossible d\'ouvrir l\'installateur';

  @override
  String get installerFailedOpenedReleasePage =>
      'Échec du lancement de l\'installateur; page de release ouverte dans le navigateur';

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
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count associations ignorées (cibles manquantes)',
      one: '$count association ignorée (cible manquante)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions corrompues ignorées',
      one: '$count session corrompue ignorée',
    );
    return '$_temp0';
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
  String get emptyFolder => 'Dossier vide';

  @override
  String get qrGenerationFailed => 'Échec de la génération du QR code';

  @override
  String get scanWithCameraApp =>
      'Scannez avec n\'importe quelle application appareil photo\nsur un appareil où LetsFLUTssh est installé.';

  @override
  String get noPasswordsInQr => 'Aucun mot de passe ni clé dans ce QR code';

  @override
  String get qrContainsCredentialsWarning =>
      'Ce code QR contient des identifiants. Gardez l\'écran privé.';

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
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
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
  String get importFromSshDir => 'Importer depuis ~/.ssh';

  @override
  String get importFromSshDirSubtitle =>
      'Choisissez des hôtes depuis le fichier de configuration et/ou des clés privées depuis ~/.ssh';

  @override
  String get sshDirImportHostsSection =>
      'Hôtes depuis le fichier de configuration';

  @override
  String get sshDirImportKeysSection => 'Clés dans ~/.ssh';

  @override
  String importSshKeysFound(int count) {
    return '$count clé(s) trouvée(s) — choisissez lesquelles importer';
  }

  @override
  String get importSshKeysNoneFound => 'Aucune clé privée trouvée dans ~/.ssh.';

  @override
  String get sshKeyAlreadyImported => 'déjà dans le magasin';

  @override
  String get setMasterPasswordHint =>
      'Définissez un mot de passe principal pour chiffrer l\'archive.';

  @override
  String get passwordsDoNotMatch => 'Les mots de passe ne correspondent pas';

  @override
  String get passwordStrengthWeak => 'Faible';

  @override
  String get passwordStrengthModerate => 'Moyen';

  @override
  String get passwordStrengthStrong => 'Fort';

  @override
  String get passwordStrengthVeryStrong => 'Très fort';

  @override
  String get tierRecommendedBadge => 'Recommandé';

  @override
  String get tierCurrentBadge => 'Actuel';

  @override
  String get tierAlternativeBranchLabel =>
      'Alternative — ne pas faire confiance au SE';

  @override
  String get tierUpcomingTooltip => 'Arrive dans une future version.';

  @override
  String get tierUpcomingNotes =>
      'L\'infrastructure sous-jacente de ce niveau n\'est pas encore livrée. La ligne est visible pour que vous sachiez que l\'option existe.';

  @override
  String get tierPlaintextLabel => 'Texte brut';

  @override
  String get tierPlaintextSubtitle =>
      'Pas de chiffrement — uniquement les permissions de fichier';

  @override
  String get tierPlaintextThreat1 =>
      'Quiconque a accès au système de fichiers lit vos données';

  @override
  String get tierPlaintextThreat2 =>
      'Une synchro ou sauvegarde accidentelle révèle tout';

  @override
  String get tierPlaintextNotes =>
      'À utiliser uniquement dans des environnements de confiance et isolés.';

  @override
  String get tierKeychainLabel => 'Trousseau';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'La clé vit dans $keychain — déverrouillage auto au lancement';
  }

  @override
  String get tierKeychainProtect1 => 'Autres utilisateurs sur la même machine';

  @override
  String get tierKeychainProtect2 => 'Disque volé sans la connexion du SE';

  @override
  String get tierKeychainThreat1 => 'Malware exécuté sous votre compte SE';

  @override
  String get tierKeychainThreat2 =>
      'Un attaquant qui prend le contrôle de votre session SE';

  @override
  String get tierKeychainUnavailable =>
      'Trousseau du SE indisponible sur cette installation.';

  @override
  String get tierKeychainPassProtect1 => 'Collègue assis à votre bureau';

  @override
  String get tierKeychainPassProtect2 => 'Un passant avec accès déverrouillé';

  @override
  String get tierKeychainPassThreat1 =>
      'Attaquant hors-ligne avec le fichier sur disque';

  @override
  String get tierKeychainPassThreat2 =>
      'Mêmes risques de compromission du SE que le trousseau';

  @override
  String get tierHardwareLabel => 'Matériel';

  @override
  String get tierHardwareSubtitle =>
      'Coffre lié au matériel + PIN court avec verrouillage';

  @override
  String get tierHardwareProtect1 =>
      'Force brute hors-ligne du PIN (limitation matérielle)';

  @override
  String get tierHardwareProtect2 => 'Vol du disque et du blob du trousseau';

  @override
  String get tierHardwareThreat1 => 'CVE SE ou firmware sur le module sécurisé';

  @override
  String get tierHardwareThreat2 =>
      'Déverrouillage biométrique forcé (si activé)';

  @override
  String get tierParanoidLabel => 'Mot de passe maître (Paranoid)';

  @override
  String get tierParanoidSubtitle =>
      'Long mot de passe + Argon2id. La clé n\'entre jamais dans le SE.';

  @override
  String get tierParanoidProtect1 => 'Compromission du trousseau SE';

  @override
  String get tierParanoidProtect2 =>
      'Disque volé (tant que votre mot de passe est fort)';

  @override
  String get tierParanoidThreat1 => 'Keylogger capturant votre mot de passe';

  @override
  String get tierParanoidThreat2 =>
      'Mot de passe faible + cassage Argon2id hors-ligne';

  @override
  String get tierParanoidNotes =>
      'La biométrie est désactivée par conception à ce niveau.';

  @override
  String get tierHardwareUnavailable =>
      'Coffre matériel indisponible sur cette installation.';

  @override
  String get pinLabel => 'Mot de passe';

  @override
  String get l2UnlockTitle => 'Mot de passe requis';

  @override
  String get l2UnlockHint =>
      'Saisissez votre mot de passe court pour continuer';

  @override
  String get l2WrongPassword => 'Mot de passe incorrect';

  @override
  String get l3UnlockTitle => 'Saisir le mot de passe';

  @override
  String get l3UnlockHint =>
      'Le mot de passe déverrouille le coffre lié au matériel';

  @override
  String get l3WrongPin => 'Mot de passe incorrect';

  @override
  String tierCooldownHint(int seconds) {
    return 'Réessayer dans $seconds s';
  }

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
  String get dataStorageSection => 'Stockage';

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
  String get errExportPickerUnavailable =>
      'Le sélecteur de dossier système n\'est pas disponible. Essayez un autre emplacement ou vérifiez les autorisations de stockage de l\'application.';

  @override
  String get biometricUnlockPrompt => 'Déverrouiller LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'Déverrouiller par biométrie';

  @override
  String get biometricUnlockSubtitle =>
      'Évitez de saisir le mot de passe — déverrouillez avec le capteur biométrique de l\'appareil.';

  @override
  String get biometricNotAvailable =>
      'Le déverrouillage biométrique n\'est pas disponible sur cet appareil.';

  @override
  String get biometricEnableFailed =>
      'Impossible d\'activer le déverrouillage biométrique.';

  @override
  String get biometricEnabled => 'Déverrouillage biométrique activé';

  @override
  String get biometricDisabled => 'Déverrouillage biométrique désactivé';

  @override
  String get biometricUnlockFailed =>
      'Échec du déverrouillage biométrique. Saisissez votre mot de passe principal.';

  @override
  String get biometricUnlockCancelled => 'Déverrouillage biométrique annulé.';

  @override
  String get biometricNotEnrolled =>
      'Aucune donnée biométrique enregistrée sur cet appareil.';

  @override
  String get biometricRequiresMasterPassword =>
      'Définissez d\'abord un mot de passe principal pour activer le déverrouillage biométrique.';

  @override
  String get biometricSensorNotAvailable =>
      'Cet appareil n\'a pas de capteur biométrique.';

  @override
  String get biometricSystemServiceMissing =>
      'Le service d\'empreintes digitales (fprintd) n\'est pas installé. Voir README → Installation.';

  @override
  String get biometricBackingHardware =>
      'Sauvegardé par le matériel (Secure Enclave / TPM)';

  @override
  String get biometricBackingSoftware => 'Sauvegardé par logiciel';

  @override
  String get currentPasswordIncorrect => 'Mot de passe actuel incorrect';

  @override
  String get wrongPassword => 'Mot de passe incorrect';

  @override
  String get useKeychain => 'Chiffrer avec le trousseau du système';

  @override
  String get useKeychainSubtitle =>
      'Stocker la clé de la base de données dans le coffre d\'identifiants du système. Désactivé = base de données en clair.';

  @override
  String get lockScreenTitle => 'LetsFLUTssh est verrouillé';

  @override
  String get lockScreenSubtitle =>
      'Saisissez le mot de passe maître ou utilisez la biométrie pour continuer.';

  @override
  String get unlock => 'Déverrouiller';

  @override
  String get autoLockTitle => 'Verrouillage automatique après inactivité';

  @override
  String get autoLockSubtitle =>
      'Verrouille l’interface après cette durée d’inactivité. La clé de la base est effacée et le magasin chiffré est fermé à chaque verrouillage ; les sessions actives restent connectées grâce à un cache d’identifiants par session qui se vide à la fermeture de la session.';

  @override
  String get autoLockOff => 'Désactivé';

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
      'Mise à jour rejetée : les fichiers téléchargés ne sont pas signés par la clé de publication ancrée dans l\'application. Cela peut signifier que le téléchargement a été altéré en transit, ou que la version actuelle n\'est pas destinée à cette installation. N\'INSTALLEZ PAS — réinstallez manuellement depuis la page officielle des versions.';

  @override
  String get updateSecurityWarningTitle =>
      'Échec de la vérification de la mise à jour';

  @override
  String get updateReinstallAction => 'Ouvrir la page des versions';

  @override
  String get errLfsNotArchive =>
      'Le fichier sélectionné n\'est pas une archive LetsFLUTssh.';

  @override
  String get errLfsDecryptFailed =>
      'Mot de passe maître incorrect ou archive .lfs corrompue';

  @override
  String get errLfsArchiveTruncated =>
      'L\'archive est incomplète. Retéléchargez-la ou réexportez-la depuis l\'appareil d\'origine.';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'L\'archive est trop volumineuse ($sizeMb Mo). La limite est de $limitMb Mo — interrompu avant le déchiffrement pour protéger la mémoire.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'L\'entrée known_hosts est trop volumineuse ($sizeMb Mo). La limite est de $limitMb Mo — interrompu pour garder l\'import réactif.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'Échec de l\'import — vos données ont été restaurées à l\'état antérieur. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'L\'archive utilise le schéma v$found, mais cette version ne prend en charge que jusqu\'à v$supported. Mettez à jour l\'application pour l\'importer.';
  }

  @override
  String get progressReadingArchive => 'Lecture de l\'archive…';

  @override
  String get progressDecrypting => 'Déchiffrement…';

  @override
  String get progressParsingArchive => 'Analyse de l\'archive…';

  @override
  String get progressImportingSessions => 'Importation des sessions';

  @override
  String get progressImportingFolders => 'Importation des dossiers';

  @override
  String get progressImportingManagerKeys => 'Importation des clés SSH';

  @override
  String get progressImportingTags => 'Importation des étiquettes';

  @override
  String get progressImportingSnippets => 'Importation des snippets';

  @override
  String get progressApplyingConfig => 'Application de la configuration…';

  @override
  String get progressImportingKnownHosts => 'Importation de known_hosts…';

  @override
  String get progressCollectingData => 'Collecte des données…';

  @override
  String get progressEncrypting => 'Chiffrement…';

  @override
  String get progressWritingArchive => 'Écriture de l\'archive…';

  @override
  String get progressReencrypting => 'Rechiffrement des magasins…';

  @override
  String get progressWorking => 'Traitement…';

  @override
  String get importFromLink => 'Importer depuis un lien QR';

  @override
  String get importFromLinkSubtitle =>
      'Collez un deep-link letsflutssh:// copié depuis un autre appareil';

  @override
  String get pasteImportLinkTitle => 'Coller le lien d\'import';

  @override
  String get pasteImportLinkDescription =>
      'Collez le lien letsflutssh://import?d=… (ou le payload brut) généré sur un autre appareil. Pas de caméra requise.';

  @override
  String get pasteFromClipboard => 'Coller depuis le presse-papiers';

  @override
  String get invalidImportLink =>
      'Le lien ne contient pas de payload LetsFLUTssh valide';

  @override
  String get importAction => 'Importer';

  @override
  String get saveSessionToAssignTags =>
      'Enregistrez d\'abord la session pour attribuer des étiquettes';

  @override
  String get noTagsAssigned => 'Aucune étiquette attribuée';

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
  String get fileConflictTitle => 'Le fichier existe déjà';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '« $fileName » existe déjà dans $targetDir. Que voulez-vous faire ?';
  }

  @override
  String get fileConflictSkip => 'Ignorer';

  @override
  String get fileConflictKeepBoth => 'Garder les deux';

  @override
  String get fileConflictReplace => 'Remplacer';

  @override
  String get fileConflictApplyAll => 'Appliquer à tous les suivants';

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
  String get importKnownHostsSubtitle =>
      'Import depuis un fichier OpenSSH known_hosts';

  @override
  String get clearedAllHosts => 'Tous les hôtes connus supprimés';

  @override
  String removedHost(String host) {
    return '$host supprimé';
  }

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
  String get migrationToast => 'Stockage mis à jour au format actuel';

  @override
  String get dbCorruptTitle => 'Impossible d\'ouvrir la base de données';

  @override
  String get dbCorruptBody =>
      'Les données sur le disque ne s\'ouvrent pas. Essayez un autre identifiant ou réinitialisez pour repartir à zéro.';

  @override
  String get dbCorruptWarning =>
      'La réinitialisation supprimera définitivement la base chiffrée et tous les fichiers liés à la sécurité. Aucune donnée ne sera récupérée.';

  @override
  String get dbCorruptTryOther => 'Essayer d\'autres identifiants';

  @override
  String get dbCorruptResetContinue => 'Réinitialiser et configurer';

  @override
  String get dbCorruptExit => 'Quitter LetsFLUTssh';

  @override
  String get tierResetTitle => 'Réinitialisation de sécurité requise';

  @override
  String get tierResetBody =>
      'Cette installation contient des données de sécurité d\'une ancienne version de LetsFLUTssh qui utilisait un modèle de niveaux différent. Le nouveau modèle introduit une rupture — il n\'y a pas de chemin de migration automatique. Pour continuer, toutes les sessions enregistrées, identifiants, clés SSH et hôtes connus de cette installation doivent être effacés et l\'assistant de configuration initiale exécuté à nouveau.';

  @override
  String get tierResetWarning =>
      'Choisir « Réinitialiser et reconfigurer » supprimera définitivement la base de données chiffrée et tous les fichiers liés à la sécurité. Si vous devez récupérer vos données, quittez l\'application maintenant et réinstallez la version précédente de LetsFLUTssh pour d\'abord les exporter.';

  @override
  String get tierResetResetContinue => 'Réinitialiser et reconfigurer';

  @override
  String get tierResetExit => 'Quitter LetsFLUTssh';

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
  String get securityLevelPlaintext => 'Aucun';

  @override
  String get securityLevelKeychain => 'Trousseau du système';

  @override
  String get securityLevelMasterPassword => 'Mot de passe principal';

  @override
  String get keychainStatus => 'Trousseau';

  @override
  String get keychainAvailable => 'Disponible';

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
  String get changeSecurityTier => 'Modifier le niveau de sécurité';

  @override
  String get changeSecurityTierSubtitle =>
      'Ouvrir l\'échelle des niveaux et passer à un autre niveau de sécurité';

  @override
  String get changeSecurityTierConfirm =>
      'Re-chiffrement de la base avec le nouveau niveau. Ne pas interrompre — laissez l\'app ouverte jusqu\'à la fin.';

  @override
  String get changeSecurityTierDone => 'Niveau de sécurité modifié';

  @override
  String get changeSecurityTierFailed =>
      'Impossible de modifier le niveau de sécurité';

  @override
  String get firstLaunchSecurityTitle => 'Stockage sécurisé activé';

  @override
  String get firstLaunchSecurityBody =>
      'Vos données sont chiffrées avec une clé conservée dans le trousseau du système. Le déverrouillage sur cet appareil est automatique.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'Un stockage matériel est disponible sur cet appareil. Passez par Paramètres → Sécurité pour une liaison TPM / Secure Enclave.';

  @override
  String get firstLaunchSecurityHardwareUnavailableWindows =>
      'Stockage matériel indisponible — aucun TPM 2.0 détecté sur cet appareil.';

  @override
  String get firstLaunchSecurityHardwareUnavailableApple =>
      'Stockage matériel indisponible — cet appareil ne signale pas de Secure Enclave.';

  @override
  String get firstLaunchSecurityHardwareUnavailableLinux =>
      'Stockage matériel indisponible — installez tpm2-tools et un périphérique TPM 2.0 pour l\'activer.';

  @override
  String get firstLaunchSecurityHardwareUnavailableAndroid =>
      'Stockage matériel indisponible — cet appareil ne signale ni StrongBox ni TEE.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'Stockage matériel indisponible sur cet appareil.';

  @override
  String get firstLaunchSecurityOpenSettings => 'Ouvrir les paramètres';

  @override
  String get firstLaunchSecurityDismiss => 'Compris';

  @override
  String get securityHardwareUpgradeTitle => 'Stockage matériel disponible';

  @override
  String get securityHardwareUpgradeBody =>
      'Passez au stockage matériel pour lier les secrets au TPM / Secure Enclave.';

  @override
  String get securityHardwareUpgradeAction => 'Mettre à niveau';

  @override
  String get securityHardwareUnavailableTitle =>
      'Stockage matériel indisponible';

  @override
  String get wizardReducedBanner =>
      'Le trousseau du système n\'est pas accessible sur cette installation. Choisissez entre aucun chiffrement (T0) et un mot de passe maître (Paranoid). Installez gnome-keyring, kwallet ou un autre fournisseur libsecret pour activer le niveau Keychain.';

  @override
  String get tierBlockProtectsHeader => 'PROTÈGE CONTRE';

  @override
  String get tierBlockDoesNotProtectHeader => 'NE PROTÈGE PAS';

  @override
  String get tierBlockProtectsEmpty => 'Rien à ce niveau.';

  @override
  String get tierBlockDoesNotProtectEmpty => 'Aucune menace non couverte.';

  @override
  String get tierBadgeCurrent => 'Actuel';

  @override
  String get securitySetupEnable => 'Activer';

  @override
  String get securitySetupApply => 'Appliquer';

  @override
  String get passwordDisabledPlaintext =>
      'Le niveau sans chiffrement ne stocke aucun secret à protéger par un mot de passe.';

  @override
  String get passwordDisabledParanoid =>
      'Paranoid dérive la clé de la base de données du mot de passe — toujours actif.';

  @override
  String get passwordSubtitleOn =>
      'Activé — mot de passe requis au déverrouillage';

  @override
  String get passwordSubtitleOff =>
      'Désactivé — appuyez pour ajouter un mot de passe à ce niveau';

  @override
  String get passwordSubtitleParanoid =>
      'Requis — le mot de passe maître est le secret du niveau';

  @override
  String get passwordSubtitlePlaintext =>
      'Non applicable — aucun chiffrement à ce niveau';

  @override
  String get hwProbeLinuxDeviceMissing =>
      'Aucun TPM détecté sur /dev/tpmrm0. Activez fTPM / PTT dans le BIOS si la machine le prend en charge, sinon le niveau matériel n\'est pas disponible sur cet appareil.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools n\'est pas installé. Exécutez `sudo apt install tpm2-tools` (ou l\'équivalent de votre distribution) pour activer le niveau matériel.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'La vérification du niveau matériel a échoué. Vérifiez les autorisations de /dev/tpmrm0 et les règles udev — détails dans les journaux.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'Aucun TPM 2.0 détecté. Activez fTPM / PTT dans le firmware UEFI, ou acceptez que le niveau matériel n\'est pas disponible sur cet appareil — l\'app bascule vers le magasin d\'identifiants logiciel.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Ni Microsoft Platform Crypto Provider ni Software Key Storage Provider ne sont accessibles — probablement un sous-système cryptographique Windows corrompu ou une stratégie de groupe qui bloque CNG. Vérifiez Observateur d\'événements → Journaux des applications et services.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'Ce Mac n\'a pas de Secure Enclave (Mac Intel avant 2017 sans puce de sécurité T1 / T2). Le niveau matériel n\'est pas disponible ; utilisez le mot de passe maître.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'Aucun mot de passe de session défini sur ce Mac. La création de clé Secure Enclave en requiert un — définissez-le dans Réglages système → Touch ID et mot de passe (ou Mot de passe de connexion).';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave a rejeté l\'identité de signature de l\'application (-34018). Exécutez le script `macos-resign.sh` fourni avec la version pour donner à cette installation une identité auto-signée stable, puis redémarrez l\'application.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'Aucun code défini sur l\'appareil. La création de clé Secure Enclave en requiert un — définissez un code dans Réglages → Face ID et code (ou Touch ID et code).';

  @override
  String get hwProbeIosSimulator =>
      'Exécution dans le Simulateur iOS, qui n\'a pas de Secure Enclave. Le niveau matériel n\'est disponible que sur les appareils iOS physiques.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'Android 9 ou plus récent est requis pour le niveau matériel (StrongBox et l\'invalidation par changement biométrique ne sont pas fiables sur les versions antérieures).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'Cet appareil n\'a pas de matériel biométrique (empreinte ou visage). Utilisez le mot de passe maître.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'Aucune biométrie enregistrée. Ajoutez une empreinte ou un visage dans Paramètres → Sécurité et confidentialité → Biométrie, puis réactivez le niveau matériel.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'Matériel biométrique temporairement inutilisable (verrouillage après échecs ou mise à jour de sécurité en attente). Réessayez dans quelques minutes.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'Le Keystore Android a refusé de créer une clé matérielle sur cette build d\'appareil (StrongBox indisponible, ROM personnalisée ou bogue du pilote). Le niveau matériel n\'est pas disponible.';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus fonctionne mais aucun secret-service daemon n\'est actif. Installez gnome-keyring (`sudo apt install gnome-keyring`) ou KWalletManager et assurez-vous qu\'il démarre à la connexion.';

  @override
  String get keyringProbeFailed =>
      'Le trousseau de l\'OS n\'est pas accessible sur cet appareil. Voir les logs pour l\'erreur plateforme spécifique ; l\'app bascule vers le mot de passe maître.';

  @override
  String get snippets => 'Snippets';

  @override
  String get snippetsSubtitle =>
      'Gérez des snippets de commandes réutilisables';

  @override
  String get noSnippets => 'Aucun snippet pour l\'instant';

  @override
  String get addSnippet => 'Ajouter un snippet';

  @override
  String get editSnippet => 'Modifier le snippet';

  @override
  String get deleteSnippet => 'Supprimer le snippet';

  @override
  String deleteSnippetConfirm(String title) {
    return 'Supprimer le snippet « $title » ?';
  }

  @override
  String get snippetTitle => 'Titre';

  @override
  String get snippetTitleHint => 'ex. Déploiement, Redémarrer le service';

  @override
  String get snippetCommand => 'Commande';

  @override
  String get snippetCommandHint => 'ex. sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'Description (optionnelle)';

  @override
  String get snippetDescriptionHint => 'Que fait cette commande ?';

  @override
  String get snippetSaved => 'Snippet enregistré';

  @override
  String snippetDeleted(String title) {
    return 'Snippet « $title » supprimé';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets',
      one: '1 snippet',
      zero: 'Aucun snippet',
    );
    return '$_temp0';
  }

  @override
  String get runSnippet => 'Exécuter';

  @override
  String get pinToSession => 'Épingler à cette session';

  @override
  String get unpinFromSession => 'Détacher de cette session';

  @override
  String get pinnedSnippets => 'Épinglés';

  @override
  String get allSnippets => 'Tous';

  @override
  String get sendToTerminal => 'Envoyer au terminal';

  @override
  String get commandCopied => 'Commande copiée dans le presse-papiers';

  @override
  String get tags => 'Étiquettes';

  @override
  String get tagsSubtitle =>
      'Organisez sessions et dossiers avec des étiquettes de couleur';

  @override
  String get noTags => 'Aucune étiquette pour l\'instant';

  @override
  String get addTag => 'Ajouter une étiquette';

  @override
  String get deleteTag => 'Supprimer l\'étiquette';

  @override
  String deleteTagConfirm(String name) {
    return 'Supprimer l\'étiquette « $name » ? Elle sera retirée de toutes les sessions et dossiers.';
  }

  @override
  String get tagName => 'Nom de l\'étiquette';

  @override
  String get tagNameHint => 'ex. Production, Staging';

  @override
  String get tagColor => 'Couleur';

  @override
  String get tagCreated => 'Étiquette créée';

  @override
  String tagDeleted(String name) {
    return 'Étiquette « $name » supprimée';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count étiquettes',
      one: '1 étiquette',
      zero: 'Aucune étiquette',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'Gérer les étiquettes';

  @override
  String get editTags => 'Modifier les étiquettes';

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
  String get presetFullImport => 'Import complet';

  @override
  String get presetSelective => 'Sélectif';

  @override
  String get presetCustom => 'Personnalisé';

  @override
  String get sessionSshKeys => 'Clés SSH de la session';

  @override
  String get allManagerKeys => 'Toutes les clés du gestionnaire';

  @override
  String get browseFiles => 'Parcourir les fichiers…';

  @override
  String get sshDirSessionAlreadyImported => 'déjà dans les sessions';

  @override
  String get languageSubtitle => 'Langue de l\'interface';

  @override
  String get themeSubtitle => 'Sombre, clair ou suivre le système';

  @override
  String get uiScaleSubtitle => 'Mettre à l\'échelle toute l\'interface';

  @override
  String get terminalFontSizeSubtitle =>
      'Taille de police dans la sortie du terminal';

  @override
  String get scrollbackLinesSubtitle =>
      'Taille du tampon d\'historique du terminal';

  @override
  String get keepAliveIntervalSubtitle =>
      'Secondes entre les paquets SSH keep-alive (0 = désactivé)';

  @override
  String get sshTimeoutSubtitle => 'Délai de connexion en secondes';

  @override
  String get defaultPortSubtitle =>
      'Port par défaut pour les nouvelles sessions';

  @override
  String get parallelWorkersSubtitle =>
      'Travailleurs SFTP de transfert parallèles';

  @override
  String get maxHistorySubtitle =>
      'Nombre maximum de commandes enregistrées dans l\'historique';

  @override
  String get calculateFolderSizesSubtitle =>
      'Afficher la taille totale à côté des dossiers dans la barre latérale';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Interroger GitHub pour une nouvelle version au lancement de l\'application';

  @override
  String get enableLoggingSubtitle =>
      'Écrire les événements de l\'application dans un fichier journal rotatif';

  @override
  String get exportWithoutPassword => 'Exporter sans mot de passe ?';

  @override
  String get exportWithoutPasswordWarning =>
      'L\'archive ne sera pas chiffrée. Toute personne ayant accès au fichier pourra lire vos données, y compris les mots de passe et les clés privées.';

  @override
  String get continueWithoutPassword => 'Continuer sans mot de passe';

  @override
  String get threatColdDiskTheft => 'Vol de disque éteint';

  @override
  String get threatColdDiskTheftDescription =>
      'Machine éteinte dont le disque est retiré et lu sur un autre ordinateur, ou copie du fichier de base de données prise par quelqu\'un ayant accès à votre dossier personnel.';

  @override
  String get threatKeyringFileTheft => 'Vol du fichier keyring / keychain';

  @override
  String get threatKeyringFileTheftDescription =>
      'Un attaquant lit directement le fichier du magasin d\'identifiants de la plateforme depuis le disque (libsecret keyring, Credential Manager Windows, login keychain macOS) et en extrait la clé de base de données encapsulée. Le niveau matériel bloque cela indépendamment du mot de passe car la puce refuse d\'exporter le matériel de clé ; le niveau keychain nécessite en plus un mot de passe, sinon le fichier volé se déchiffre avec le seul mot de passe de connexion du système.';

  @override
  String get modifierOnlyWithPassword => 'uniquement avec mot de passe';

  @override
  String get threatBystanderUnlockedMachine =>
      'Témoin devant une machine déverrouillée';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'Quelqu\'un s\'approche de votre ordinateur déjà déverrouillé et ouvre l\'application pendant que vous êtes absent.';

  @override
  String get threatLiveRamForensicsLocked =>
      'Forensique de RAM sur machine verrouillée';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'Un attaquant gèle la RAM (ou la capture via DMA) et extrait du matériel de clé encore présent dans l\'instantané, même si l\'application est verrouillée.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'Compromission du noyau ou du trousseau';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'Vulnérabilité du noyau, exfiltration du trousseau ou porte dérobée dans la puce de sécurité matérielle. Le système d\'exploitation devient l\'attaquant au lieu d\'une ressource de confiance.';

  @override
  String get threatOfflineBruteForce =>
      'Force brute hors ligne sur mot de passe faible';

  @override
  String get threatOfflineBruteForceDescription =>
      'Un attaquant possédant une copie de la clé encapsulée ou du blob scellé teste chaque mot de passe à son propre rythme, sans aucun limiteur de débit.';

  @override
  String get legendProtects => 'Protégé';

  @override
  String get legendDoesNotProtect => 'Non protégé';

  @override
  String get legendNotApplicable =>
      'Non applicable — pas de secret utilisateur pour ce niveau';

  @override
  String get legendWeakPasswordWarning =>
      'Mot de passe faible acceptable — une autre couche (limiteur matériel ou liaison de clé encapsulée) assure la sécurité';

  @override
  String get legendStrongPasswordRecommended =>
      'Une longue phrase secrète est fortement recommandée — la sécurité de ce niveau en dépend';

  @override
  String get colT0 => 'T0 Texte brut';

  @override
  String get colT1 => 'T1 Trousseau';

  @override
  String get colT1Password => 'T1 + mot de passe';

  @override
  String get colT1PasswordBiometric => 'T1 + mot de passe + biométrie';

  @override
  String get colT2 => 'T2 Matériel';

  @override
  String get colT2Password => 'T2 + mot de passe';

  @override
  String get colT2PasswordBiometric => 'T2 + mot de passe + biométrie';

  @override
  String get colParanoid => 'Paranoïaque';

  @override
  String get securityComparisonTableTitle =>
      'Niveaux de sécurité — comparaison côte à côte';

  @override
  String get securityComparisonTableThreatColumn => 'Menace';

  @override
  String get compareAllTiers => 'Comparer tous les niveaux';

  @override
  String get resetAllDataTitle => 'Réinitialiser toutes les données';

  @override
  String get resetAllDataSubtitle =>
      'Supprimer toutes les sessions, clés, configurations et artefacts de sécurité. Efface également les entrées du trousseau et les emplacements du coffre matériel.';

  @override
  String get resetAllDataConfirmTitle => 'Réinitialiser toutes les données ?';

  @override
  String get resetAllDataConfirmBody =>
      'Toutes les sessions, clés SSH, known hosts, extraits, étiquettes, préférences et tous les artefacts de sécurité (entrées du trousseau, données du coffre matériel, surcouche biométrique) seront définitivement supprimés. Cette action est irréversible.';

  @override
  String get resetAllDataConfirmAction => 'Tout réinitialiser';

  @override
  String get resetAllDataInProgress => 'Réinitialisation…';

  @override
  String get resetAllDataDone => 'Toutes les données réinitialisées';

  @override
  String get resetAllDataFailed => 'Échec de la réinitialisation';

  @override
  String get compareAllTiersSubtitle =>
      'Comparez côte à côte ce contre quoi chaque niveau protège.';

  @override
  String get autoLockRequiresPassword =>
      'Le verrouillage automatique nécessite un mot de passe sur le niveau actif.';

  @override
  String get recommendedBadge => 'RECOMMANDÉ';

  @override
  String get continueWithRecommended => 'Continuer avec la recommandation';

  @override
  String get customizeSecurity => 'Personnaliser la sécurité';

  @override
  String get tierHardwareSubtitleHonest =>
      'Avancé : clé liée au matériel. Les données sont irrécupérables si la puce de cet appareil est perdue ou remplacée.';

  @override
  String get tierParanoidSubtitleHonest =>
      'Alternative : mot de passe maître, aucune confiance envers l\'OS. Protège contre une compromission de l\'OS. N\'améliore pas la protection à l\'exécution par rapport à T1/T2.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'Les menaces runtime (malware du même utilisateur, vidage mémoire d\'un processus actif) sont affichées avec ✗ à tous les niveaux. Elles sont traitées par des fonctions de mitigation distinctes appliquées indépendamment du niveau choisi.';

  @override
  String get securitySetupContinue => 'Continuer';

  @override
  String get currentTierBadge => 'ACTUEL';

  @override
  String get paranoidAlternativeHeader => 'ALTERNATIVE';

  @override
  String get modifierPasswordLabel => 'Mot de passe';

  @override
  String get modifierPasswordSubtitle =>
      'Barrière de secret saisi avant le déverrouillage du coffre.';

  @override
  String get modifierBiometricLabel => 'Raccourci biométrique';

  @override
  String get modifierBiometricSubtitle =>
      'Récupérer le mot de passe depuis un emplacement du système protégé par biométrie au lieu de le saisir.';

  @override
  String get biometricRequiresPassword =>
      'Activez d\'abord un mot de passe — la biométrie n\'est qu\'un raccourci pour le saisir.';

  @override
  String get biometricRequiresActiveTier =>
      'Sélectionnez d\'abord ce niveau pour activer le déverrouillage biométrique';

  @override
  String get autoLockRequiresActiveTier =>
      'Sélectionnez d\'abord ce niveau pour configurer le verrouillage automatique';

  @override
  String get biometricForbiddenParanoid =>
      'Paranoid n\'autorise pas la biométrie par conception.';

  @override
  String get fprintdNotAvailable =>
      'fprintd non installé ou aucune empreinte enregistrée.';

  @override
  String get linuxTpmWithoutPasswordNote =>
      'Un TPM sans mot de passe fournit de l\'isolation, pas de l\'authentification. Quiconque peut exécuter cette application peut déverrouiller les données.';

  @override
  String get paranoidMasterPasswordNote =>
      'Une phrase de passe longue est fortement recommandée — Argon2id ne fait que ralentir la force brute, il ne la bloque pas.';

  @override
  String get plaintextWarningTitle => 'Texte brut : pas de chiffrement';

  @override
  String get plaintextWarningBody =>
      'Les sessions, clés et known hosts seront stockés sans chiffrement. Toute personne ayant accès au système de fichiers de cet ordinateur pourra les lire.';

  @override
  String get plaintextAcknowledge =>
      'Je comprends que mes données ne seront pas chiffrées';

  @override
  String get plaintextAcknowledgeRequired =>
      'Confirmez votre compréhension avant de continuer.';

  @override
  String get passwordLabel => 'Mot de passe';

  @override
  String get masterPasswordLabel => 'Mot de passe maître';
}
