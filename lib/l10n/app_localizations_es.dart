// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class SEs extends S {
  SEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'OK';

  @override
  String get infoDialogProtectsHeader => 'Protege contra';

  @override
  String get infoDialogDoesNotProtectHeader => 'No protege contra';

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Cerrar';

  @override
  String get delete => 'Eliminar';

  @override
  String get save => 'Guardar';

  @override
  String get connect => 'Conectar';

  @override
  String get retry => 'Reintentar';

  @override
  String get import_ => 'Importar';

  @override
  String get export_ => 'Exportar';

  @override
  String get rename => 'Renombrar';

  @override
  String get create => 'Crear';

  @override
  String get back => 'Atrás';

  @override
  String get copy => 'Copiar';

  @override
  String get paste => 'Pegar';

  @override
  String get select => 'Seleccionar';

  @override
  String get required => 'Obligatorio';

  @override
  String get settings => 'Ajustes';

  @override
  String get appSettings => 'Ajustes de la aplicación';

  @override
  String get yes => 'Sí';

  @override
  String get no => 'No';

  @override
  String get importWhatToImport => 'Qué importar:';

  @override
  String get exportWhatToExport => 'Qué exportar:';

  @override
  String get enterMasterPasswordPrompt => 'Ingrese contraseña maestra:';

  @override
  String get nextStep => 'Siguiente';

  @override
  String get includeCredentials => 'Incluir contraseñas y claves SSH';

  @override
  String get includePasswords => 'Contraseñas de sesiones';

  @override
  String get embeddedKeys => 'Claves integradas';

  @override
  String get managerKeys => 'Claves del gestor';

  @override
  String get managerKeysMayBeLarge =>
      'Las claves del gestor pueden exceder el tamaño QR';

  @override
  String get qrPasswordWarning =>
      'Las claves SSH están deshabilitadas por defecto al exportar.';

  @override
  String get sshKeysMayBeLarge => 'Las claves pueden exceder el tamaño QR';

  @override
  String exportTotalSize(String size) {
    return 'Tamaño total: $size';
  }

  @override
  String get qrCredentialsWarning =>
      'Las contraseñas y claves SSH SERÁN visibles en el código QR';

  @override
  String get qrCredentialsTooLarge =>
      'Las credenciales hacen el código QR demasiado grande';

  @override
  String get terminal => 'Terminal';

  @override
  String get files => 'Archivos';

  @override
  String get transfer => 'Transferencia';

  @override
  String get open => 'Abrir';

  @override
  String get search => 'Buscar...';

  @override
  String get noResults => 'Sin resultados';

  @override
  String get filter => 'Filtrar...';

  @override
  String get merge => 'Fusionar';

  @override
  String get replace => 'Reemplazar';

  @override
  String get reconnect => 'Reconectar';

  @override
  String get updateAvailable => 'Actualización disponible';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'La versión $version está disponible (actual: v$current).';
  }

  @override
  String get releaseNotes => 'Notas de la versión:';

  @override
  String get skipThisVersion => 'Omitir esta versión';

  @override
  String get unskip => 'Dejar de omitir';

  @override
  String get downloadAndInstall => 'Descargar e instalar';

  @override
  String get openInBrowser => 'Abrir en el navegador';

  @override
  String get couldNotOpenBrowser =>
      'No se pudo abrir el navegador — URL copiada al portapapeles';

  @override
  String get checkForUpdates => 'Buscar actualizaciones';

  @override
  String get checkNow => 'Comprobar ahora';

  @override
  String get checkForUpdatesOnStartup => 'Buscar actualizaciones al iniciar';

  @override
  String get checking => 'Comprobando...';

  @override
  String get youreUpToDate => 'Estás al día';

  @override
  String get updateCheckFailed => 'Error al buscar actualizaciones';

  @override
  String get unknownError => 'Error desconocido';

  @override
  String downloadingPercent(int percent) {
    return 'Descargando... $percent%';
  }

  @override
  String get downloadComplete => 'Descarga completada';

  @override
  String get installNow => 'Instalar ahora';

  @override
  String get openReleasePage => 'Abrir página de lanzamiento';

  @override
  String get couldNotOpenInstaller => 'No se pudo abrir el instalador';

  @override
  String get installerFailedOpenedReleasePage =>
      'No se pudo iniciar el instalador; se abrió la página de lanzamiento en el navegador';

  @override
  String versionAvailable(String version) {
    return 'Versión $version disponible';
  }

  @override
  String currentVersion(String version) {
    return 'Actual: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'Clave SSH recibida: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return '$count sesión/sesiones importadas vía QR';
  }

  @override
  String importedSessions(int count) {
    return '$count sesión/sesiones importadas';
  }

  @override
  String importFailed(String error) {
    return 'Error al importar: $error';
  }

  @override
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count asociaciones descartadas (destinos faltantes)',
      one: '$count asociación descartada (destino faltante)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones corruptas omitidas',
      one: '$count sesión corrupta omitida',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'Sesiones';

  @override
  String get emptyFolders => 'Carpetas vacías';

  @override
  String get sessionsHeader => 'SESIONES';

  @override
  String get savedSessions => 'Sesiones guardadas';

  @override
  String get activeConnections => 'Conexiones activas';

  @override
  String get openTabs => 'Pestañas abiertas';

  @override
  String get noSavedSessions => 'No hay sesiones guardadas';

  @override
  String get addSession => 'Añadir sesión';

  @override
  String get noSessions => 'Sin sesiones';

  @override
  String get noSessionsToExport => 'No hay sesiones para exportar';

  @override
  String nSelectedCount(int count) {
    return '$count seleccionados';
  }

  @override
  String get selectAll => 'Seleccionar todo';

  @override
  String get deselectAll => 'Deseleccionar todo';

  @override
  String get moveTo => 'Mover a...';

  @override
  String get moveToFolder => 'Mover a carpeta';

  @override
  String get rootFolder => '/ (raíz)';

  @override
  String get newFolder => 'Nueva carpeta';

  @override
  String get newConnection => 'Nueva conexión';

  @override
  String get editConnection => 'Editar conexión';

  @override
  String get duplicate => 'Duplicar';

  @override
  String get deleteSession => 'Eliminar sesión';

  @override
  String get renameFolder => 'Renombrar carpeta';

  @override
  String get deleteFolder => 'Eliminar carpeta';

  @override
  String get deleteSelected => 'Eliminar seleccionados';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return '¿Eliminar $parts?\n\nEsta acción no se puede deshacer.';
  }

  @override
  String nSessions(int count) {
    return '$count sesión/sesiones';
  }

  @override
  String nFolders(int count) {
    return '$count carpeta(s)';
  }

  @override
  String deleteFolderConfirm(String name) {
    return '¿Eliminar la carpeta \"$name\"?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'También se eliminarán $count sesión/sesiones dentro.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String get connection => 'Conexión';

  @override
  String get auth => 'Autenticación';

  @override
  String get options => 'Opciones';

  @override
  String get sessionName => 'Nombre de la sesión';

  @override
  String get hintMyServer => 'Mi servidor';

  @override
  String get hostRequired => 'Host *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'Puerto';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'Usuario *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'Contraseña';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'Frase de paso de la clave';

  @override
  String get hintOptional => 'Opcional';

  @override
  String get hidePemText => 'Ocultar texto PEM';

  @override
  String get pastePemKeyText => 'Pegar texto de clave PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'Aún no hay opciones adicionales';

  @override
  String get saveAndConnect => 'Guardar y conectar';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst =>
      'Primero proporcione un archivo de clave o texto PEM';

  @override
  String get keyTextPem => 'Texto de clave (PEM)';

  @override
  String get selectKeyFile => 'Seleccionar archivo de clave';

  @override
  String get clearKeyFile => 'Borrar archivo de clave';

  @override
  String get authOrDivider => 'O';

  @override
  String get providePasswordOrKey => 'Proporcione una contraseña o clave SSH';

  @override
  String get quickConnect => 'Conexión rápida';

  @override
  String get scanQrCode => 'Escanear código QR';

  @override
  String get emptyFolder => 'Carpeta vacía';

  @override
  String get qrGenerationFailed => 'Error al generar QR';

  @override
  String get scanWithCameraApp =>
      'Escanee con cualquier aplicación de cámara en un dispositivo\nque tenga LetsFLUTssh instalado.';

  @override
  String get noPasswordsInQr =>
      'Este código QR no contiene contraseñas ni claves';

  @override
  String get qrContainsCredentialsWarning =>
      'Este código QR contiene credenciales. Mantén la pantalla privada.';

  @override
  String get copyLink => 'Copiar enlace';

  @override
  String get linkCopied => 'Enlace copiado al portapapeles';

  @override
  String get hostKeyChanged => '¡La clave del host ha cambiado!';

  @override
  String get unknownHost => 'Host desconocido';

  @override
  String get hostKeyChangedWarning =>
      'ADVERTENCIA: La clave del host de este servidor ha cambiado. Esto podría indicar un ataque de intermediario, o el servidor puede haber sido reinstalado.';

  @override
  String get unknownHostMessage =>
      'No se puede establecer la autenticidad de este host. ¿Está seguro de que desea continuar conectando?';

  @override
  String get host => 'Host';

  @override
  String get keyType => 'Tipo de clave';

  @override
  String get fingerprint => 'Huella digital';

  @override
  String get fingerprintCopied => 'Huella digital copiada';

  @override
  String get copyFingerprint => 'Copiar huella digital';

  @override
  String get acceptAnyway => 'Aceptar de todos modos';

  @override
  String get accept => 'Aceptar';

  @override
  String get importData => 'Importar datos';

  @override
  String get masterPassword => 'Contraseña maestra';

  @override
  String get confirmPassword => 'Confirmar contraseña';

  @override
  String get importModeMergeDescription =>
      'Añadir sesiones nuevas, conservar las existentes';

  @override
  String get importModeReplaceDescription =>
      'Reemplazar todas las sesiones con las importadas';

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get folderName => 'Nombre de la carpeta';

  @override
  String get newName => 'Nuevo nombre';

  @override
  String deleteItems(String names) {
    return '¿Eliminar $names?';
  }

  @override
  String deleteNItems(int count) {
    return 'Eliminar $count elementos';
  }

  @override
  String deletedItem(String name) {
    return '$name eliminado';
  }

  @override
  String deletedNItems(int count) {
    return '$count elementos eliminados';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'Error al crear la carpeta: $error';
  }

  @override
  String failedToRename(String error) {
    return 'Error al renombrar: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return 'Error al eliminar $name: $error';
  }

  @override
  String get editPath => 'Editar ruta';

  @override
  String get root => 'Raíz';

  @override
  String get controllersNotInitialized => 'Controladores no inicializados';

  @override
  String get initializingSftp => 'Inicializando SFTP...';

  @override
  String get clearHistory => 'Borrar historial';

  @override
  String get noTransfersYet => 'Aún no hay transferencias';

  @override
  String get duplicateTab => 'Duplicar pestaña';

  @override
  String get duplicateTabShortcut => 'Duplicar pestaña (Ctrl+\\)';

  @override
  String get copyDown => 'Copiar abajo';

  @override
  String get previous => 'Anterior';

  @override
  String get next => 'Siguiente';

  @override
  String get closeEsc => 'Cerrar (Esc)';

  @override
  String get closeAll => 'Cerrar todas';

  @override
  String get closeOthers => 'Cerrar otras';

  @override
  String get closeTabsToTheLeft => 'Cerrar pestañas a la izquierda';

  @override
  String get closeTabsToTheRight => 'Cerrar pestañas a la derecha';

  @override
  String get noActiveSession => 'Sin sesión activa';

  @override
  String get createConnectionHint =>
      'Cree una nueva conexión o seleccione una de la barra lateral';

  @override
  String get hideSidebar => 'Ocultar barra lateral (Ctrl+B)';

  @override
  String get showSidebar => 'Mostrar barra lateral (Ctrl+B)';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystemDefault => 'Auto';

  @override
  String get theme => 'Tema';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get appearance => 'Apariencia';

  @override
  String get connectionSection => 'Conexión';

  @override
  String get transfers => 'Transferencias';

  @override
  String get data => 'Datos';

  @override
  String get logging => 'Registro';

  @override
  String get updates => 'Actualizaciones';

  @override
  String get about => 'Acerca de';

  @override
  String get resetToDefaults => 'Restablecer valores predeterminados';

  @override
  String get uiScale => 'Escala de la interfaz';

  @override
  String get terminalFontSize => 'Tamaño de fuente del terminal';

  @override
  String get scrollbackLines => 'Líneas de desplazamiento';

  @override
  String get keepAliveInterval => 'Intervalo de Keep-Alive (seg)';

  @override
  String get sshTimeout => 'Tiempo de espera SSH (seg)';

  @override
  String get defaultPort => 'Puerto predeterminado';

  @override
  String get parallelWorkers => 'Trabajadores en paralelo';

  @override
  String get maxHistory => 'Historial máximo';

  @override
  String get calculateFolderSizes => 'Calcular tamaños de carpetas';

  @override
  String get exportData => 'Exportar datos';

  @override
  String get exportDataSubtitle =>
      'Guardar sesiones, configuración y claves en un archivo .lfs cifrado';

  @override
  String get importDataSubtitle => 'Cargar datos desde un archivo .lfs';

  @override
  String sshConfigPreviewHostsFound(int count) {
    return '$count host(s) encontrado(s)';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'No se encontraron hosts importables en este archivo.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'No se pudieron leer los archivos de clave para: $hosts. Estos hosts se importarán sin credenciales.';
  }

  @override
  String sshConfigPreviewFolderLabel(String folder) {
    return 'Importado en la carpeta: $folder';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'Exportar archivo';

  @override
  String get exportArchiveSubtitle =>
      'Guardar sesiones, configuración y claves en archivo .lfs cifrado';

  @override
  String get exportQrCode => 'Exportar código QR';

  @override
  String get exportQrCodeSubtitle =>
      'Compartir sesiones y claves seleccionadas mediante código QR';

  @override
  String get importArchive => 'Importar archivo';

  @override
  String get importArchiveSubtitle => 'Cargar datos desde archivo .lfs';

  @override
  String get importFromSshDir => 'Importar desde ~/.ssh';

  @override
  String get importFromSshDirSubtitle =>
      'Elige hosts del archivo de configuración y/o claves privadas de ~/.ssh';

  @override
  String get sshDirImportHostsSection => 'Hosts del archivo de configuración';

  @override
  String get sshDirImportKeysSection => 'Claves en ~/.ssh';

  @override
  String importSshKeysFound(int count) {
    return '$count clave(s) encontrada(s) — elige cuáles importar';
  }

  @override
  String get importSshKeysNoneFound =>
      'No se encontraron claves privadas en ~/.ssh.';

  @override
  String get sshKeyAlreadyImported => 'ya en el almacén';

  @override
  String get setMasterPasswordHint =>
      'Establezca una contraseña maestra para cifrar el archivo.';

  @override
  String get passwordsDoNotMatch => 'Las contraseñas no coinciden';

  @override
  String get passwordStrengthWeak => 'Débil';

  @override
  String get passwordStrengthModerate => 'Media';

  @override
  String get passwordStrengthStrong => 'Fuerte';

  @override
  String get passwordStrengthVeryStrong => 'Muy fuerte';

  @override
  String get tierRecommendedBadge => 'Recomendado';

  @override
  String get tierCurrentBadge => 'Actual';

  @override
  String get tierAlternativeBranchLabel => 'Alternativa — no confíes en el SO';

  @override
  String get tierUpcomingTooltip => 'Llega en una versión futura.';

  @override
  String get tierUpcomingNotes =>
      'La infraestructura subyacente de este nivel aún no se ha lanzado. La fila es visible para que sepas que la opción existe.';

  @override
  String get tierPlaintextLabel => 'Texto plano';

  @override
  String get tierPlaintextSubtitle => 'Sin cifrado — solo permisos de archivo';

  @override
  String get tierPlaintextThreat1 =>
      'Cualquiera con acceso al sistema de archivos lee tus datos';

  @override
  String get tierPlaintextThreat2 =>
      'Sincronización o respaldo accidental lo revela todo';

  @override
  String get tierPlaintextNotes =>
      'Usar solo en entornos confiables y aislados.';

  @override
  String get tierKeychainLabel => 'Llavero';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'La clave vive en $keychain — desbloqueo automático al iniciar';
  }

  @override
  String get tierKeychainProtect1 => 'Otros usuarios en la misma máquina';

  @override
  String get tierKeychainProtect2 =>
      'Disco robado sin el inicio de sesión del SO';

  @override
  String get tierKeychainThreat1 =>
      'Malware que se ejecuta bajo tu cuenta del SO';

  @override
  String get tierKeychainThreat2 =>
      'Atacante que toma control de tu inicio de sesión del SO';

  @override
  String get tierKeychainUnavailable =>
      'El llavero del SO no está disponible en esta instalación.';

  @override
  String get tierKeychainPassProtect1 => 'Compañero sentado en tu escritorio';

  @override
  String get tierKeychainPassProtect2 =>
      'Un transeúnte con acceso desbloqueado';

  @override
  String get tierKeychainPassThreat1 =>
      'Atacante sin conexión con el archivo en disco';

  @override
  String get tierKeychainPassThreat2 =>
      'Mismos riesgos de compromiso del SO que el llavero';

  @override
  String get tierHardwareLabel => 'Hardware';

  @override
  String get tierHardwareSubtitle =>
      'Bóveda vinculada al hardware + PIN corto con bloqueo';

  @override
  String get tierHardwareProtect1 =>
      'Fuerza bruta offline del PIN (límite de tasa por hardware)';

  @override
  String get tierHardwareProtect2 => 'Robo del disco y del blob del llavero';

  @override
  String get tierHardwareThreat1 => 'CVE de SO o firmware en el módulo seguro';

  @override
  String get tierHardwareThreat2 =>
      'Desbloqueo biométrico forzado (si está habilitado)';

  @override
  String get tierParanoidLabel => 'Contraseña maestra (Paranoid)';

  @override
  String get tierParanoidSubtitle =>
      'Contraseña larga + Argon2id. La clave nunca entra en el SO.';

  @override
  String get tierParanoidProtect1 => 'Compromiso del llavero del SO';

  @override
  String get tierParanoidProtect2 =>
      'Disco robado (siempre que tu contraseña sea fuerte)';

  @override
  String get tierParanoidThreat1 => 'Keylogger capturando tu contraseña';

  @override
  String get tierParanoidThreat2 =>
      'Contraseña débil + craqueo Argon2id offline';

  @override
  String get tierParanoidNotes =>
      'La biometría está deshabilitada por diseño en este nivel.';

  @override
  String get tierHardwareUnavailable =>
      'Bóveda de hardware no disponible en esta instalación.';

  @override
  String get pinLabel => 'PIN';

  @override
  String get l2UnlockTitle => 'Contraseña requerida';

  @override
  String get l2UnlockHint => 'Introduce tu contraseña corta para continuar';

  @override
  String get l2WrongPassword => 'Contraseña incorrecta';

  @override
  String get l3UnlockTitle => 'Introducir PIN';

  @override
  String get l3UnlockHint =>
      'El PIN corto desbloquea la bóveda vinculada al hardware';

  @override
  String get l3WrongPin => 'PIN incorrecto';

  @override
  String tierCooldownHint(int seconds) {
    return 'Reintentar en $seconds s';
  }

  @override
  String exportedTo(String path) {
    return 'Exportado a: $path';
  }

  @override
  String exportFailed(String error) {
    return 'Error al exportar: $error';
  }

  @override
  String get pathToLfsFile => 'Ruta al archivo .lfs';

  @override
  String get hintLfsPath => '/ruta/al/archivo.lfs';

  @override
  String get browse => 'Examinar';

  @override
  String get shareViaQrCode => 'Compartir vía código QR';

  @override
  String get shareViaQrSubtitle =>
      'Exportar sesiones a QR para escanear desde otro dispositivo';

  @override
  String get dataLocation => 'Ubicación de los datos';

  @override
  String get pathCopied => 'Ruta copiada al portapapeles';

  @override
  String get urlCopied => 'URL copiada al portapapeles';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — Cliente SSH/SFTP';
  }

  @override
  String get sourceCode => 'Código fuente';

  @override
  String get enableLogging => 'Activar registro';

  @override
  String get logIsEmpty => 'El registro está vacío';

  @override
  String logExportedTo(String path) {
    return 'Registro exportado a: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Error al exportar el registro: $error';
  }

  @override
  String get logsCleared => 'Registros borrados';

  @override
  String get copiedToClipboard => 'Copiado al portapapeles';

  @override
  String get copyLog => 'Copiar registro';

  @override
  String get exportLog => 'Exportar registro';

  @override
  String get clearLogs => 'Borrar registros';

  @override
  String get local => 'Local';

  @override
  String get remote => 'Remoto';

  @override
  String get pickFolder => 'Elegir carpeta';

  @override
  String get refresh => 'Actualizar';

  @override
  String get up => 'Subir';

  @override
  String get emptyDirectory => 'Directorio vacío';

  @override
  String get cancelSelection => 'Cancelar selección';

  @override
  String get openSftpBrowser => 'Abrir explorador SFTP';

  @override
  String get openSshTerminal => 'Abrir terminal SSH';

  @override
  String get noActiveFileBrowsers => 'No hay exploradores de archivos activos';

  @override
  String get useSftpFromSessions => 'Use \"SFTP\" desde Sesiones';

  @override
  String get anotherInstanceRunning =>
      'Otra instancia de LetsFLUTssh ya está en ejecución.';

  @override
  String importFailedShort(String error) {
    return 'Error al importar: $error';
  }

  @override
  String get saveLogAs => 'Guardar registro como';

  @override
  String get chooseSaveLocation => 'Elegir ubicación de guardado';

  @override
  String get forward => 'Adelante';

  @override
  String get name => 'Nombre';

  @override
  String get size => 'Tamaño';

  @override
  String get modified => 'Modificado';

  @override
  String get mode => 'Modo';

  @override
  String get owner => 'Propietario';

  @override
  String get connectionError => 'Error de conexión';

  @override
  String get resizeWindowToViewFiles =>
      'Cambie el tamaño de la ventana para ver los archivos';

  @override
  String get completed => 'Completado';

  @override
  String get connected => 'Conectado';

  @override
  String get disconnected => 'Desconectado';

  @override
  String get exit => 'Salir';

  @override
  String get exitConfirmation =>
      'Las sesiones activas serán desconectadas. ¿Salir?';

  @override
  String get hintFolderExample => 'ej. Production';

  @override
  String get credentialsNotSet => 'Credenciales no configuradas';

  @override
  String get exportSessionsViaQr => 'Exportar sesiones vía QR';

  @override
  String get qrNoCredentialsWarning =>
      'Las contraseñas y claves SSH NO están incluidas.\nLas sesiones importadas necesitarán que se completen las credenciales.';

  @override
  String get qrTooManyForSingleCode =>
      'Demasiadas sesiones para un solo código QR. Deseleccione algunas o use la exportación .lfs.';

  @override
  String get qrTooLarge =>
      'Demasiado grande — deseleccione algunos elementos o use la exportación en archivo .lfs.';

  @override
  String get exportAll => 'Exportar todo';

  @override
  String get showQr => 'Mostrar QR';

  @override
  String get sort => 'Ordenar';

  @override
  String get resizePanelDivider => 'Redimensionar divisor de panel';

  @override
  String get youreRunningLatest => 'Está usando la versión más reciente';

  @override
  String get liveLog => 'Log en vivo';

  @override
  String transferNItems(int count) {
    return 'Transferir $count elementos';
  }

  @override
  String get time => 'Tiempo';

  @override
  String get failed => 'Fallido';

  @override
  String get errOperationNotPermitted => 'Operación no permitida';

  @override
  String get errNoSuchFileOrDirectory => 'No existe el archivo o directorio';

  @override
  String get errNoSuchProcess => 'No existe el proceso';

  @override
  String get errIoError => 'Error de E/S';

  @override
  String get errBadFileDescriptor => 'Descriptor de archivo incorrecto';

  @override
  String get errResourceTemporarilyUnavailable =>
      'Recurso temporalmente no disponible';

  @override
  String get errOutOfMemory => 'Memoria agotada';

  @override
  String get errPermissionDenied => 'Permiso denegado';

  @override
  String get errFileExists => 'El archivo ya existe';

  @override
  String get errNotADirectory => 'No es un directorio';

  @override
  String get errIsADirectory => 'Es un directorio';

  @override
  String get errInvalidArgument => 'Argumento no válido';

  @override
  String get errTooManyOpenFiles => 'Demasiados archivos abiertos';

  @override
  String get errNoSpaceLeftOnDevice => 'No queda espacio en el dispositivo';

  @override
  String get errReadOnlyFileSystem => 'Sistema de archivos de solo lectura';

  @override
  String get errBrokenPipe => 'Tubería rota';

  @override
  String get errFileNameTooLong => 'Nombre de archivo demasiado largo';

  @override
  String get errDirectoryNotEmpty => 'El directorio no está vacío';

  @override
  String get errAddressAlreadyInUse => 'La dirección ya está en uso';

  @override
  String get errCannotAssignAddress =>
      'No se puede asignar la dirección solicitada';

  @override
  String get errNetworkIsDown => 'La red está caída';

  @override
  String get errNetworkIsUnreachable => 'La red es inaccesible';

  @override
  String get errConnectionResetByPeer => 'Conexión restablecida por el par';

  @override
  String get errConnectionTimedOut => 'Conexión agotada por tiempo';

  @override
  String get errConnectionRefused => 'Conexión rechazada';

  @override
  String get errHostIsDown => 'El host está caído';

  @override
  String get errNoRouteToHost => 'Sin ruta al host';

  @override
  String get errConnectionAborted => 'Conexión abortada';

  @override
  String get errAlreadyConnected => 'Ya conectado';

  @override
  String get errNotConnected => 'No conectado';

  @override
  String errSshConnectFailed(String host, int port) {
    return 'Error al conectar a $host:$port';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return 'Autenticación fallida para $user@$host';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return 'Conexión fallida a $host:$port';
  }

  @override
  String get errSshAuthAborted => 'Autenticación abortada';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return 'Clave de host rechazada para $host:$port — acepte la clave de host o verifique known_hosts';
  }

  @override
  String get errSshOpenShellFailed => 'Error al abrir el shell';

  @override
  String get errSshLoadKeyFileFailed =>
      'Error al cargar el archivo de clave SSH';

  @override
  String get errSshParseKeyFailed => 'Error al analizar los datos de clave PEM';

  @override
  String get errSshConnectionDisposed => 'Conexión eliminada';

  @override
  String get errSshNotConnected => 'No conectado';

  @override
  String get errConnectionFailed => 'Conexión fallida';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'Conexión agotada tras $seconds segundos';
  }

  @override
  String get errSessionClosed => 'Sesión cerrada';

  @override
  String errShellError(String error) {
    return 'Error del shell: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'Reconexión fallida: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'Error al inicializar SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Descarga fallida: $error';
  }

  @override
  String get errDecryptionFailed =>
      'Error al descifrar las credenciales. El archivo de clave puede estar dañado.';

  @override
  String get errExportPickerUnavailable =>
      'El selector de carpetas del sistema no está disponible. Pruebe otra ubicación o verifique los permisos de almacenamiento de la aplicación.';

  @override
  String get biometricUnlockPrompt => 'Desbloquear LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'Desbloquear con biometría';

  @override
  String get biometricUnlockSubtitle =>
      'Evita escribir la contraseña maestra al iniciar la aplicación.';

  @override
  String get biometricNotAvailable =>
      'El desbloqueo biométrico no está disponible en este dispositivo.';

  @override
  String get biometricEnableFailed =>
      'No se pudo activar el desbloqueo biométrico.';

  @override
  String get biometricEnabled => 'Desbloqueo biométrico activado';

  @override
  String get biometricDisabled => 'Desbloqueo biométrico desactivado';

  @override
  String get biometricUnlockFailed =>
      'Falló el desbloqueo biométrico. Introduzca su contraseña maestra.';

  @override
  String get biometricUnlockCancelled => 'Desbloqueo biométrico cancelado.';

  @override
  String get biometricNotEnrolled =>
      'No hay credenciales biométricas registradas en este dispositivo.';

  @override
  String get biometricRequiresMasterPassword =>
      'Primero establezca una contraseña maestra para habilitar el desbloqueo biométrico.';

  @override
  String get biometricSensorNotAvailable =>
      'Este dispositivo no tiene sensor biométrico.';

  @override
  String get biometricSystemServiceMissing =>
      'El servicio de huella dactilar (fprintd) no está instalado. Ver README → Instalación.';

  @override
  String get biometricBackingHardware =>
      'Respaldado por hardware (Secure Enclave / TPM)';

  @override
  String get biometricBackingSoftware => 'Respaldado por software';

  @override
  String get currentPasswordIncorrect => 'La contraseña actual es incorrecta';

  @override
  String get wrongPassword => 'Contraseña incorrecta';

  @override
  String get useKeychain => 'Cifrar con el llavero del sistema';

  @override
  String get useKeychainSubtitle =>
      'Guardar la clave de la base de datos en el almacén de credenciales del sistema. Desactivado = base de datos sin cifrar.';

  @override
  String get lockScreenTitle => 'LetsFLUTssh está bloqueado';

  @override
  String get lockScreenSubtitle =>
      'Introduce la contraseña maestra o usa la biometría para continuar.';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get autoLockTitle => 'Bloqueo automático por inactividad';

  @override
  String get autoLockSubtitle =>
      'Bloquea la interfaz tras este periodo de inactividad. La base de datos cifrada solo se vuelve a bloquear cuando no hay sesiones SSH activas, para no interrumpir operaciones largas.';

  @override
  String get autoLockOff => 'Desactivado';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutos',
      one: '$minutes minuto',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'Actualización rechazada: los archivos descargados no están firmados por la clave de lanzamiento fijada en la aplicación. Esto puede significar que la descarga fue manipulada en tránsito, o que el lanzamiento actual no es para esta instalación. NO instale — reinstale manualmente desde la página oficial de lanzamientos.';

  @override
  String get updateSecurityWarningTitle =>
      'Falló la verificación de la actualización';

  @override
  String get updateReinstallAction => 'Abrir página de lanzamientos';

  @override
  String get errLfsNotArchive =>
      'El archivo seleccionado no es un archivo de LetsFLUTssh.';

  @override
  String get errLfsDecryptFailed =>
      'Contraseña maestra incorrecta o archivo .lfs dañado';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'El archivo es demasiado grande ($sizeMb MB). El límite es de $limitMb MB: cancelado antes del descifrado para proteger la memoria.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'La entrada known_hosts es demasiado grande ($sizeMb MB). El límite es de $limitMb MB: cancelado para mantener la importación responsiva.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'Error al importar — sus datos se han restaurado al estado anterior a la importación. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'El archivo usa el esquema v$found, pero esta versión solo admite hasta v$supported. Actualiza la aplicación para importarlo.';
  }

  @override
  String get progressReadingArchive => 'Leyendo archivo…';

  @override
  String get progressDecrypting => 'Descifrando…';

  @override
  String get progressParsingArchive => 'Analizando archivo…';

  @override
  String get progressImportingSessions => 'Importando sesiones';

  @override
  String get progressImportingFolders => 'Importando carpetas';

  @override
  String get progressImportingManagerKeys => 'Importando claves SSH';

  @override
  String get progressImportingTags => 'Importando etiquetas';

  @override
  String get progressImportingSnippets => 'Importando snippets';

  @override
  String get progressApplyingConfig => 'Aplicando configuración…';

  @override
  String get progressImportingKnownHosts => 'Importando known_hosts…';

  @override
  String get progressCollectingData => 'Recopilando datos…';

  @override
  String get progressEncrypting => 'Cifrando…';

  @override
  String get progressWritingArchive => 'Escribiendo archivo…';

  @override
  String get progressReencrypting => 'Volviendo a cifrar almacenes…';

  @override
  String get progressWorking => 'Procesando…';

  @override
  String get importFromLink => 'Importar desde enlace QR';

  @override
  String get importFromLinkSubtitle =>
      'Pega un deep-link letsflutssh:// copiado desde otro dispositivo';

  @override
  String get pasteImportLinkTitle => 'Pegar enlace de importación';

  @override
  String get pasteImportLinkDescription =>
      'Pega el enlace letsflutssh://import?d=… (o el payload en bruto) generado en otro dispositivo. No se necesita cámara.';

  @override
  String get pasteFromClipboard => 'Pegar del portapapeles';

  @override
  String get invalidImportLink =>
      'El enlace no contiene un payload LetsFLUTssh válido';

  @override
  String get importAction => 'Importar';

  @override
  String get saveSessionToAssignTags =>
      'Guarda la sesión primero para asignar etiquetas';

  @override
  String get noTagsAssigned => 'Sin etiquetas asignadas';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'Usuario';

  @override
  String get protocol => 'Protocolo';

  @override
  String get typeLabel => 'Tipo';

  @override
  String get folder => 'Carpeta';

  @override
  String nSubitems(int count) {
    return '$count elemento(s)';
  }

  @override
  String get subitems => 'Elementos';

  @override
  String get storagePermissionRequired =>
      'Se requiere permiso de almacenamiento para explorar archivos locales';

  @override
  String get grantPermission => 'Conceder permiso';

  @override
  String get storagePermissionLimited =>
      'Acceso limitado — conceda permiso de almacenamiento completo para todos los archivos';

  @override
  String progressConnecting(String host, int port) {
    return 'Conectando a $host:$port';
  }

  @override
  String get progressVerifyingHostKey => 'Verificando clave del host';

  @override
  String progressAuthenticating(String user) {
    return 'Autenticando como $user';
  }

  @override
  String get progressOpeningShell => 'Abriendo shell';

  @override
  String get progressOpeningSftp => 'Abriendo canal SFTP';

  @override
  String get transfersLabel => 'Transferencias:';

  @override
  String transferCountActive(int count) {
    return '$count activas';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count en cola';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count en historial';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'Creado: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'Iniciado: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'Finalizado: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'Duración: $duration';
  }

  @override
  String get transferStatusQueued => 'En cola';

  @override
  String get transferStartingUpload => 'Iniciando carga...';

  @override
  String get transferStartingDownload => 'Iniciando descarga...';

  @override
  String get transferCopying => 'Copiando...';

  @override
  String get transferDone => 'Listo';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total archivos';
  }

  @override
  String get fileConflictTitle => 'El archivo ya existe';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '«$fileName» ya existe en $targetDir. ¿Qué desea hacer?';
  }

  @override
  String get fileConflictSkip => 'Omitir';

  @override
  String get fileConflictKeepBoth => 'Conservar ambos';

  @override
  String get fileConflictReplace => 'Reemplazar';

  @override
  String get fileConflictApplyAll => 'Aplicar a todos los restantes';

  @override
  String get folderNameLabel => 'NOMBRE DE CARPETA';

  @override
  String folderAlreadyExists(String name) {
    return 'La carpeta \"$name\" ya existe';
  }

  @override
  String get dropKeyFileHere => 'Arrastre el archivo de clave aquí';

  @override
  String get sessionNoCredentials =>
      'La sesión no tiene credenciales — edítela para agregar una contraseña o clave';

  @override
  String dragItemCount(int count) {
    return '$count elementos';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'Seleccionar todo ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'Tamaño: $size KB / $max KB máx.';
  }

  @override
  String get noActiveTerminals => 'No hay terminales activos';

  @override
  String get connectFromSessionsTab => 'Conéctese desde la pestaña Sesiones';

  @override
  String fileNotFound(String path) {
    return 'Archivo no encontrado: $path';
  }

  @override
  String get sshConnectionChannel => 'Conexión SSH';

  @override
  String get sshConnectionChannelDesc =>
      'Mantiene las conexiones SSH activas en segundo plano.';

  @override
  String get sshActive => 'SSH activo';

  @override
  String activeConnectionCount(int count) {
    return '$count conexión(es) activa(s)';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count elementos, $size';
  }

  @override
  String get maximize => 'Maximizar';

  @override
  String get restore => 'Restaurar';

  @override
  String get duplicateDownShortcut => 'Duplicar abajo (Ctrl+Shift+\\)';

  @override
  String get security => 'Seguridad';

  @override
  String get knownHosts => 'Hosts conocidos';

  @override
  String get knownHostsSubtitle =>
      'Gestión de huellas digitales de servidores SSH de confianza';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts conocidos',
      one: '1 host conocido',
      zero: 'Sin hosts conocidos',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'Sin hosts conocidos. Conéctese a un servidor para agregar uno.';

  @override
  String get removeHost => 'Eliminar host';

  @override
  String removeHostConfirm(String host) {
    return '¿Eliminar $host de hosts conocidos? La clave se verificará de nuevo en la próxima conexión.';
  }

  @override
  String get clearAllKnownHosts => 'Eliminar todos los hosts conocidos';

  @override
  String get clearAllKnownHostsConfirm =>
      '¿Eliminar todos los hosts conocidos? Cada clave de servidor deberá ser verificada de nuevo.';

  @override
  String get importKnownHostsSubtitle =>
      'Importar desde archivo OpenSSH known_hosts';

  @override
  String get clearedAllHosts => 'Todos los hosts conocidos eliminados';

  @override
  String removedHost(String host) {
    return '$host eliminado';
  }

  @override
  String get tools => 'Herramientas';

  @override
  String get sshKeys => 'Claves SSH';

  @override
  String get sshKeysSubtitle =>
      'Gestión de pares de claves SSH para autenticación';

  @override
  String get noKeys => 'Sin claves SSH. Importe o genere una.';

  @override
  String get generateKey => 'Generar clave';

  @override
  String get importKey => 'Importar clave';

  @override
  String get keyLabel => 'Nombre de la clave';

  @override
  String get keyLabelHint => 'ej. Servidor de trabajo, GitHub';

  @override
  String get selectKeyType => 'Tipo de clave';

  @override
  String get generating => 'Generando...';

  @override
  String keyGenerated(String label) {
    return 'Clave generada: $label';
  }

  @override
  String keyImported(String label) {
    return 'Clave importada: $label';
  }

  @override
  String get deleteKey => 'Eliminar clave';

  @override
  String deleteKeyConfirm(String label) {
    return '¿Eliminar clave \"$label\"? Las sesiones que la usen perderán el acceso.';
  }

  @override
  String keyDeleted(String label) {
    return 'Clave eliminada: $label';
  }

  @override
  String get publicKey => 'Clave pública';

  @override
  String get publicKeyCopied => 'Clave pública copiada al portapapeles';

  @override
  String get pastePrivateKey => 'Pegar clave privada (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Datos de clave PEM inválidos';

  @override
  String get selectFromKeyStore => 'Seleccionar del almacén de claves';

  @override
  String get noKeySelected => 'Ninguna clave seleccionada';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count claves',
      one: '1 clave',
      zero: 'Sin claves',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'Generada';

  @override
  String get passphraseRequired => 'Frase de contraseña requerida';

  @override
  String passphrasePrompt(String host) {
    return 'La clave SSH para $host está cifrada. Ingrese la frase de contraseña para desbloquearla.';
  }

  @override
  String get passphraseWrong =>
      'Frase de contraseña incorrecta. Por favor, inténtelo de nuevo.';

  @override
  String get passphrase => 'Frase de contraseña';

  @override
  String get rememberPassphrase => 'Recordar para esta sesión';

  @override
  String get masterPasswordSubtitle =>
      'Proteger credenciales guardadas con contraseña';

  @override
  String get setMasterPassword => 'Establecer contraseña maestra';

  @override
  String get changeMasterPassword => 'Cambiar contraseña maestra';

  @override
  String get removeMasterPassword => 'Eliminar contraseña maestra';

  @override
  String get masterPasswordEnabled =>
      'Las credenciales están protegidas por contraseña maestra';

  @override
  String get masterPasswordDisabled =>
      'Las credenciales usan clave auto-generada (sin contraseña)';

  @override
  String get enterMasterPassword =>
      'Ingrese la contraseña maestra para acceder a sus credenciales guardadas.';

  @override
  String get wrongMasterPassword =>
      'Contraseña incorrecta. Por favor, inténtelo de nuevo.';

  @override
  String get newPassword => 'Nueva contraseña';

  @override
  String get currentPassword => 'Contraseña actual';

  @override
  String get masterPasswordSet => 'Contraseña maestra activada';

  @override
  String get masterPasswordChanged => 'Contraseña maestra cambiada';

  @override
  String get masterPasswordRemoved => 'Contraseña maestra eliminada';

  @override
  String get masterPasswordWarning =>
      'Si olvida esta contraseña, todas las contraseñas y claves SSH guardadas se perderán. No hay recuperación posible.';

  @override
  String get forgotPassword => '¿Olvidó su contraseña?';

  @override
  String get forgotPasswordWarning =>
      'Esto eliminará TODAS las contraseñas, claves SSH y frases de contraseña guardadas. Las sesiones y configuraciones se conservarán. Esta acción es irreversible.';

  @override
  String get resetAndDeleteCredentials => 'Restablecer y eliminar datos';

  @override
  String get credentialsReset =>
      'Todas las credenciales guardadas han sido eliminadas';

  @override
  String get legacyKdfTitle => 'Se requiere actualización de seguridad';

  @override
  String get legacyKdfBody =>
      'Esta instalación protege su contraseña maestra con un algoritmo de derivación de clave antiguo (PBKDF2). Ha sido reemplazado por Argon2id, que ofrece una resistencia mucho mayor frente a ataques con GPU/ASIC. El nuevo formato no es compatible con el anterior, por lo que el archivo de sal antiguo no puede migrarse automáticamente.';

  @override
  String get legacyKdfWarning =>
      'Elegir «Restablecer y continuar» eliminará permanentemente todas las credenciales guardadas (contraseñas, claves SSH, hosts conocidos). Sus sesiones y configuración se conservarán. Si necesita recuperar sus credenciales, cierre la aplicación y reinstale la versión anterior de LetsFLUTssh para exportar sus datos primero.';

  @override
  String get legacyKdfResetContinue => 'Restablecer y continuar';

  @override
  String get legacyKdfExit => 'Salir de LetsFLUTssh';

  @override
  String get dbCorruptTitle => 'No se puede abrir la base de datos';

  @override
  String get dbCorruptBody =>
      'La base de datos cifrada en el disco no coincide con el nivel de seguridad registrado para esta instalación. Normalmente significa que una configuración anterior se interrumpió o los datos son de una compilación con otro cifrado.\n\nLetsFLUTssh no puede continuar hasta que la base se abra con las credenciales correctas de una compilación compatible o se borre y configure de nuevo.';

  @override
  String get dbCorruptWarning =>
      'Restablecer eliminará permanentemente la base de datos cifrada y todos los archivos relacionados con la seguridad. No se recuperará ningún dato.';

  @override
  String get dbCorruptTryOther => 'Probar otras credenciales';

  @override
  String get dbCorruptResetContinue => 'Restablecer y configurar';

  @override
  String get dbCorruptExit => 'Salir de LetsFLUTssh';

  @override
  String get tierResetTitle => 'Se requiere restablecer la seguridad';

  @override
  String get tierResetBody =>
      'Esta instalación contiene datos de seguridad de una versión anterior de LetsFLUTssh que usaba un modelo de niveles diferente. El nuevo modelo es un cambio incompatible — no existe ruta de migración automática. Para continuar, todas las sesiones guardadas, credenciales, claves SSH y hosts conocidos de esta instalación deben borrarse y el asistente de configuración inicial debe ejecutarse de nuevo.';

  @override
  String get tierResetWarning =>
      'Elegir «Restablecer y configurar de nuevo» eliminará permanentemente la base de datos cifrada y todos los archivos de seguridad. Si necesita recuperar sus datos, cierre la aplicación ahora y reinstale la versión anterior de LetsFLUTssh para exportarlos primero.';

  @override
  String get tierResetResetContinue => 'Restablecer y configurar de nuevo';

  @override
  String get tierResetExit => 'Salir de LetsFLUTssh';

  @override
  String get derivingKey => 'Derivando clave de cifrado...';

  @override
  String get reEncrypting => 'Re-cifrando datos...';

  @override
  String get confirmRemoveMasterPassword =>
      'Ingrese su contraseña actual para eliminar la protección de contraseña maestra. Las credenciales serán re-cifradas con una clave auto-generada.';

  @override
  String get securitySetupTitle => 'Configuración de seguridad';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'Llavero del sistema detectado ($keychainName). Sus datos serán cifrados automáticamente usando el llavero del sistema.';
  }

  @override
  String get securitySetupKeychainOptional =>
      'También puede establecer una contraseña maestra para protección adicional.';

  @override
  String get securitySetupNoKeychain =>
      'No se detectó llavero del sistema. Sin llavero, los datos de sesión (hosts, contraseñas, claves) se almacenarán en texto plano.';

  @override
  String get securitySetupNoKeychainHint =>
      'Esto es normal en WSL, Linux sin interfaz gráfica o instalaciones mínimas. Para habilitar el llavero en Linux: instale libsecret y un demonio de llavero (ej. gnome-keyring).';

  @override
  String get securitySetupRecommendMasterPassword =>
      'Recomendamos establecer una contraseña maestra para proteger sus datos.';

  @override
  String get continueWithKeychain => 'Continuar con llavero';

  @override
  String get continueWithoutEncryption => 'Continuar sin cifrado';

  @override
  String get securityLevel => 'Nivel de seguridad';

  @override
  String get securityLevelPlaintext => 'Ninguno';

  @override
  String get securityLevelKeychain => 'Llavero del sistema';

  @override
  String get securityLevelMasterPassword => 'Contraseña maestra';

  @override
  String get keychainStatus => 'Llavero';

  @override
  String get keychainAvailable => 'Disponible';

  @override
  String get keychainNotAvailable => 'No disponible';

  @override
  String get enableKeychain => 'Activar cifrado de llavero';

  @override
  String get enableKeychainSubtitle =>
      'Volver a cifrar datos almacenados usando llavero del sistema';

  @override
  String get keychainEnabled => 'Cifrado de llavero activado';

  @override
  String get manageMasterPassword => 'Gestionar contraseña maestra';

  @override
  String get manageMasterPasswordSubtitle =>
      'Establecer, cambiar o eliminar contraseña maestra';

  @override
  String get changeSecurityTier => 'Cambiar nivel de seguridad';

  @override
  String get changeSecurityTierSubtitle =>
      'Abrir la escalera de niveles y pasar a un nivel de seguridad diferente';

  @override
  String get changeSecurityTierConfirm =>
      'Recifrando la base de datos con el nuevo nivel. No se puede interrumpir — mantén la app abierta hasta que termine.';

  @override
  String get changeSecurityTierDone => 'Nivel de seguridad cambiado';

  @override
  String get changeSecurityTierFailed =>
      'No se pudo cambiar el nivel de seguridad';

  @override
  String get firstLaunchSecurityTitle => 'Almacenamiento seguro activado';

  @override
  String get firstLaunchSecurityBody =>
      'Tus datos están cifrados con una clave guardada en el llavero del sistema. El desbloqueo en este dispositivo es automático.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'Hay almacenamiento respaldado por hardware disponible en este dispositivo. Actualiza en Ajustes → Seguridad para vincular con TPM / Secure Enclave.';

  @override
  String get firstLaunchSecurityHardwareUnavailableWindows =>
      'Almacenamiento por hardware no disponible: no se ha detectado TPM 2.0 en este dispositivo.';

  @override
  String get firstLaunchSecurityHardwareUnavailableApple =>
      'Almacenamiento por hardware no disponible: este dispositivo no reporta un Secure Enclave.';

  @override
  String get firstLaunchSecurityHardwareUnavailableLinux =>
      'Almacenamiento por hardware no disponible: instala tpm2-tools y un dispositivo TPM 2.0 para habilitarlo.';

  @override
  String get firstLaunchSecurityHardwareUnavailableAndroid =>
      'Almacenamiento por hardware no disponible: este dispositivo no reporta StrongBox ni TEE.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'Almacenamiento por hardware no disponible en este dispositivo.';

  @override
  String get firstLaunchSecurityOpenSettings => 'Abrir ajustes';

  @override
  String get firstLaunchSecurityDismiss => 'Entendido';

  @override
  String get securityHardwareUpgradeTitle =>
      'Almacenamiento por hardware disponible';

  @override
  String get securityHardwareUpgradeBody =>
      'Actualiza para vincular los secretos a TPM / Secure Enclave.';

  @override
  String get securityHardwareUpgradeAction => 'Actualizar';

  @override
  String get securityHardwareUnavailableTitle =>
      'Almacenamiento por hardware no disponible';

  @override
  String get wizardReducedBanner =>
      'El llavero del sistema no es accesible en esta instalación. Elige entre sin cifrado (T0) y una contraseña maestra (Paranoid). Instala gnome-keyring, kwallet u otro proveedor de libsecret para habilitar el nivel Keychain.';

  @override
  String get tierBlockProtectsHeader => 'PROTEGE CONTRA';

  @override
  String get tierBlockDoesNotProtectHeader => 'NO PROTEGE';

  @override
  String get tierBlockProtectsEmpty => 'Nada en este nivel.';

  @override
  String get tierBlockDoesNotProtectEmpty => 'Sin amenazas sin cubrir.';

  @override
  String get tierBadgeCurrent => 'Actual';

  @override
  String get securitySetupEnable => 'Activar';

  @override
  String get securitySetupApply => 'Aplicar';

  @override
  String get passwordDisabledPlaintext =>
      'El nivel sin cifrado no almacena secretos que proteger con una contraseña.';

  @override
  String get passwordDisabledParanoid =>
      'Paranoid deriva la clave de la base de datos de la contraseña — siempre está activada.';

  @override
  String get passwordSubtitleOn =>
      'Activada — se pide contraseña al desbloquear';

  @override
  String get passwordSubtitleOff =>
      'Desactivada — toca para añadir una contraseña en este nivel';

  @override
  String get passwordSubtitleParanoid =>
      'Obligatoria — la contraseña maestra es el secreto del nivel';

  @override
  String get passwordSubtitlePlaintext =>
      'No aplicable — este nivel no tiene cifrado';

  @override
  String get hwProbeLinuxDeviceMissing =>
      'No se detectó TPM en /dev/tpmrm0. Activa fTPM / PTT en la BIOS si la máquina lo admite; de lo contrario el nivel de hardware no está disponible en este dispositivo.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools no está instalado. Ejecuta `sudo apt install tpm2-tools` (o el equivalente de tu distribución) para habilitar el nivel de hardware.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'La prueba del nivel de hardware falló. Revisa los permisos de /dev/tpmrm0 y las reglas de udev — detalles en los registros.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'No se detectó TPM 2.0. Activa fTPM / PTT en el firmware UEFI, o acepta que el nivel de hardware no está disponible en este dispositivo — la app recurre al almacén de credenciales por software.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Ni el Microsoft Platform Crypto Provider ni el Software Key Storage Provider están accesibles — probablemente un subsistema criptográfico de Windows dañado o una directiva de grupo que bloquea CNG. Revisa Visor de eventos → Registros de aplicaciones y servicios.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'Este Mac no tiene Secure Enclave (Intel Mac anterior a 2017 sin chip de seguridad T1 / T2). El nivel de hardware no está disponible; usa la contraseña maestra.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'No hay contraseña de inicio de sesión en este Mac. Secure Enclave requiere una — establece una en Ajustes del sistema → Touch ID y contraseña (o Contraseña de inicio).';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'No hay código del dispositivo establecido. Secure Enclave requiere uno — establece un código en Ajustes → Face ID y código (o Touch ID y código).';

  @override
  String get hwProbeIosSimulator =>
      'Ejecutándose en el Simulador de iOS, que no tiene Secure Enclave. El nivel de hardware solo está disponible en dispositivos iOS físicos.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'Se requiere Android 9 o superior para el nivel de hardware (StrongBox y la invalidación por cambio de biometría no son fiables en versiones anteriores).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'Este dispositivo no tiene hardware biométrico (huella o rostro). Usa la contraseña maestra.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'No hay biometría registrada. Agrega una huella o rostro en Ajustes → Seguridad y privacidad → Biometría, luego vuelve a habilitar el nivel de hardware.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'Hardware biométrico temporalmente inutilizable (bloqueo por intentos fallidos o actualización de seguridad pendiente). Reintenta en unos minutos.';

  @override
  String get keyringProbeLinuxNoDbusSession =>
      'Sin D-Bus session bus — la app está en una sesión headless o solo por SSH. Inicia una sesión gráfica, o exporta DBUS_SESSION_BUS_ADDRESS antes de iniciar.';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus está activo pero ningún secret-service daemon está ejecutándose. Instala gnome-keyring (`sudo apt install gnome-keyring`) o KWalletManager y asegúrate de que se inicie al iniciar sesión.';

  @override
  String get keyringProbeFailed =>
      'El keychain del sistema no está accesible en este dispositivo. Consulta los registros para el error específico; la app recurre a la contraseña maestra.';

  @override
  String get snippets => 'Snippets';

  @override
  String get snippetsSubtitle =>
      'Administra fragmentos de comandos reutilizables';

  @override
  String get noSnippets => 'Aún no hay snippets';

  @override
  String get addSnippet => 'Añadir snippet';

  @override
  String get editSnippet => 'Editar snippet';

  @override
  String get deleteSnippet => 'Eliminar snippet';

  @override
  String deleteSnippetConfirm(String title) {
    return '¿Eliminar el snippet «$title»?';
  }

  @override
  String get snippetTitle => 'Título';

  @override
  String get snippetTitleHint => 'p. ej., Desplegar, Reiniciar servicio';

  @override
  String get snippetCommand => 'Comando';

  @override
  String get snippetCommandHint => 'p. ej., sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'Descripción (opcional)';

  @override
  String get snippetDescriptionHint => '¿Qué hace este comando?';

  @override
  String get snippetSaved => 'Snippet guardado';

  @override
  String snippetDeleted(String title) {
    return 'Snippet «$title» eliminado';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets',
      one: '1 snippet',
      zero: 'Sin snippets',
    );
    return '$_temp0';
  }

  @override
  String get runSnippet => 'Ejecutar';

  @override
  String get pinToSession => 'Fijar a esta sesión';

  @override
  String get unpinFromSession => 'Desfijar de esta sesión';

  @override
  String get pinnedSnippets => 'Fijados';

  @override
  String get allSnippets => 'Todos';

  @override
  String get sendToTerminal => 'Enviar al terminal';

  @override
  String get commandCopied => 'Comando copiado al portapapeles';

  @override
  String get tags => 'Etiquetas';

  @override
  String get tagsSubtitle =>
      'Organiza sesiones y carpetas con etiquetas de color';

  @override
  String get noTags => 'Aún no hay etiquetas';

  @override
  String get addTag => 'Añadir etiqueta';

  @override
  String get deleteTag => 'Eliminar etiqueta';

  @override
  String deleteTagConfirm(String name) {
    return '¿Eliminar la etiqueta «$name»? Se quitará de todas las sesiones y carpetas.';
  }

  @override
  String get tagName => 'Nombre de la etiqueta';

  @override
  String get tagNameHint => 'p. ej., Producción, Staging';

  @override
  String get tagColor => 'Color';

  @override
  String get tagCreated => 'Etiqueta creada';

  @override
  String tagDeleted(String name) {
    return 'Etiqueta «$name» eliminada';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etiquetas',
      one: '1 etiqueta',
      zero: 'Sin etiquetas',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'Administrar etiquetas';

  @override
  String get editTags => 'Editar etiquetas';

  @override
  String get fullBackup => 'Copia de seguridad completa';

  @override
  String get sessionsOnly => 'Sesiones';

  @override
  String get sessionKeysFromManager => 'Claves de sesión del gestor';

  @override
  String get allKeysFromManager => 'Todas las claves del gestor';

  @override
  String exportTags(int count) {
    return 'Etiquetas ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'Fragmentos ($count)';
  }

  @override
  String get disableKeychain => 'Desactivar cifrado del llavero';

  @override
  String get disableKeychainSubtitle =>
      'Cambiar a almacenamiento en texto plano (no recomendado)';

  @override
  String get disableKeychainConfirm =>
      'La base de datos se volverá a cifrar sin clave. Las sesiones y claves se almacenarán en texto plano en el disco. ¿Continuar?';

  @override
  String get keychainDisabled => 'Cifrado del llavero desactivado';

  @override
  String get presetFullImport => 'Importación completa';

  @override
  String get presetSelective => 'Selectivo';

  @override
  String get presetCustom => 'Personalizado';

  @override
  String get sessionSshKeys => 'Claves SSH de la sesión';

  @override
  String get allManagerKeys => 'Todas las claves del gestor';

  @override
  String get browseFiles => 'Explorar archivos…';

  @override
  String get sshDirSessionAlreadyImported => 'ya está en las sesiones';

  @override
  String get languageSubtitle => 'Idioma de la interfaz';

  @override
  String get themeSubtitle => 'Oscuro, claro o seguir al sistema';

  @override
  String get uiScaleSubtitle => 'Escalar toda la interfaz';

  @override
  String get terminalFontSizeSubtitle =>
      'Tamaño de fuente en la salida de la terminal';

  @override
  String get scrollbackLinesSubtitle =>
      'Tamaño del búfer de historial de la terminal';

  @override
  String get keepAliveIntervalSubtitle =>
      'Segundos entre paquetes SSH keep-alive (0 = desactivado)';

  @override
  String get sshTimeoutSubtitle => 'Tiempo de espera de conexión en segundos';

  @override
  String get defaultPortSubtitle =>
      'Puerto predeterminado para nuevas sesiones';

  @override
  String get parallelWorkersSubtitle =>
      'Trabajadores SFTP de transferencia en paralelo';

  @override
  String get maxHistorySubtitle => 'Comandos máximos guardados en el historial';

  @override
  String get calculateFolderSizesSubtitle =>
      'Mostrar tamaño total junto a las carpetas en la barra lateral';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Consultar GitHub por una nueva versión al iniciar la app';

  @override
  String get enableLoggingSubtitle =>
      'Escribir los eventos de la app en un archivo de registro rotativo';

  @override
  String get exportWithoutPassword => '¿Exportar sin contraseña?';

  @override
  String get exportWithoutPasswordWarning =>
      'El archivo no se cifrará. Cualquiera con acceso al archivo podrá leer tus datos, incluidas contraseñas y claves privadas.';

  @override
  String get continueWithoutPassword => 'Continuar sin contraseña';

  @override
  String get threatColdDiskTheft => 'Robo de disco apagado';

  @override
  String get threatColdDiskTheftDescription =>
      'Equipo apagado con la unidad extraída y leída en otro ordenador, o una copia del archivo de la base de datos hecha por alguien con acceso a tu carpeta personal.';

  @override
  String get threatKeyringFileTheft => 'Robo del archivo keyring / keychain';

  @override
  String get threatKeyringFileTheftDescription =>
      'Un atacante lee el archivo del almacén de credenciales del sistema directamente del disco (libsecret keyring, Credential Manager de Windows, login keychain de macOS) y recupera de él la clave de la base de datos envuelta. El nivel de hardware lo bloquea con independencia de la contraseña porque el chip se niega a exportar el material de clave; el nivel de keychain necesita además una contraseña, de lo contrario el archivo robado se desenvuelve con la sola contraseña de inicio de sesión del SO.';

  @override
  String get modifierOnlyWithPassword => 'solo con contraseña';

  @override
  String get threatBystanderUnlockedMachine =>
      'Curioso frente a un equipo desbloqueado';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'Alguien se acerca a tu ordenador ya desbloqueado y abre la aplicación mientras estás ausente.';

  @override
  String get threatSameUserMalware => 'Malware con el mismo usuario';

  @override
  String get threatSameUserMalwareDescription =>
      'Un proceso hostil ejecutándose bajo tu propia cuenta de usuario. Tiene el mismo acceso a archivos, llavero y memoria que esta aplicación — ningún nivel defiende contra esto en un equipo comprometido.';

  @override
  String get threatLiveProcessMemoryDump =>
      'Volcado de memoria del proceso activo';

  @override
  String get threatLiveProcessMemoryDumpDescription =>
      'Un atacante con acceso a depurador o ptrace lee la clave de la base de datos desbloqueada directamente de la memoria de la aplicación en ejecución.';

  @override
  String get threatLiveRamForensicsLocked =>
      'Análisis forense de RAM en equipo bloqueado';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'Un atacante congela la RAM (o la captura por DMA) y extrae material de clave aún residente desde la instantánea, incluso con la aplicación bloqueada.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'Compromiso del kernel del SO o del llavero';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'Vulnerabilidad del kernel, exfiltración del llavero o una puerta trasera en el chip de seguridad de hardware. El sistema operativo pasa de recurso de confianza a atacante.';

  @override
  String get threatOfflineBruteForce =>
      'Fuerza bruta sin conexión sobre contraseña débil';

  @override
  String get threatOfflineBruteForceDescription =>
      'Un atacante con una copia de la clave envuelta o del blob sellado prueba cada contraseña a su propio ritmo, sin ningún limitador de velocidad.';

  @override
  String get legendProtects => 'Protegido';

  @override
  String get legendDoesNotProtect => 'No protegido';

  @override
  String get legendNotApplicable =>
      'No aplicable — este nivel no tiene un secreto de usuario';

  @override
  String get legendWeakPasswordWarning =>
      'Contraseña débil aceptable — otra capa (limitador de hardware o vínculo de clave envuelta) asume la seguridad';

  @override
  String get legendStrongPasswordRecommended =>
      'Se recomienda encarecidamente una frase de contraseña larga — la seguridad de este nivel depende de ella';

  @override
  String get colT0 => 'T0 Texto plano';

  @override
  String get colT1 => 'T1 Llavero';

  @override
  String get colT1Password => 'T1 + contraseña';

  @override
  String get colT1PasswordBiometric => 'T1 + contraseña + biometría';

  @override
  String get colT2 => 'T2 Hardware';

  @override
  String get colT2Password => 'T2 + contraseña';

  @override
  String get colT2PasswordBiometric => 'T2 + contraseña + biometría';

  @override
  String get colParanoid => 'Paranoico';

  @override
  String get securityComparisonTableTitle =>
      'Niveles de seguridad — comparación lado a lado';

  @override
  String get securityComparisonTableThreatColumn => 'Amenaza';

  @override
  String get compareAllTiers => 'Comparar todos los niveles';

  @override
  String get resetAllDataTitle => 'Restablecer todos los datos';

  @override
  String get resetAllDataSubtitle =>
      'Eliminar todas las sesiones, claves, configuraciones y artefactos de seguridad. También borra las entradas del llavero y las ranuras del almacén de hardware.';

  @override
  String get resetAllDataConfirmTitle => '¿Restablecer todos los datos?';

  @override
  String get resetAllDataConfirmBody =>
      'Todas las sesiones, claves SSH, known hosts, fragmentos, etiquetas, preferencias y todos los artefactos de seguridad (entradas del llavero, datos del almacén de hardware, superposición biométrica) se eliminarán de forma permanente. Esto no se puede deshacer.';

  @override
  String get resetAllDataConfirmAction => 'Restablecer todo';

  @override
  String get resetAllDataInProgress => 'Restableciendo…';

  @override
  String get resetAllDataDone => 'Todos los datos restablecidos';

  @override
  String get resetAllDataFailed => 'Error al restablecer';

  @override
  String get compareAllTiersSubtitle =>
      'Vea, lado a lado, contra qué protege cada nivel.';

  @override
  String get autoLockRequiresPassword =>
      'El bloqueo automático requiere una contraseña en el nivel activo.';

  @override
  String get recommendedBadge => 'RECOMENDADO';

  @override
  String get continueWithRecommended => 'Continuar con el recomendado';

  @override
  String get customizeSecurity => 'Personalizar seguridad';

  @override
  String get tierHardwareSubtitleHonest =>
      'Avanzado: clave vinculada al hardware. Los datos son irrecuperables si el chip de este dispositivo se pierde o se reemplaza.';

  @override
  String get tierParanoidSubtitleHonest =>
      'Alternativa: contraseña maestra, sin confianza en el OS. Protege contra el compromiso del OS. No mejora la protección en tiempo de ejecución respecto a T1/T2.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'Las amenazas en runtime (malware del mismo usuario, volcado de memoria del proceso en ejecución) se muestran como ✗ en todos los niveles. Se abordan mediante funciones de mitigación independientes que se aplican sin importar el nivel elegido.';

  @override
  String get securitySetupContinue => 'Continuar';

  @override
  String get currentTierBadge => 'ACTUAL';

  @override
  String get paranoidAlternativeHeader => 'ALTERNATIVA';

  @override
  String get modifierPasswordLabel => 'Contraseña';

  @override
  String get modifierPasswordSubtitle =>
      'Barrera de secreto escrito antes de desbloquear la bóveda.';

  @override
  String get modifierBiometricLabel => 'Atajo biométrico';

  @override
  String get modifierBiometricSubtitle =>
      'Liberar la contraseña de una ranura del sistema protegida por biometría, en lugar de escribirla.';

  @override
  String get biometricRequiresPassword =>
      'Active primero una contraseña — la biometría es un atajo para introducirla.';

  @override
  String get biometricForbiddenParanoid =>
      'Paranoid no permite biometría por diseño.';

  @override
  String get fprintdNotAvailable =>
      'fprintd no instalado o sin huellas registradas.';

  @override
  String get linuxTpmWithoutPasswordNote =>
      'El TPM sin contraseña proporciona aislamiento, no autenticación. Cualquier persona que pueda ejecutar esta aplicación puede desbloquear los datos.';

  @override
  String get paranoidMasterPasswordNote =>
      'Se recomienda encarecidamente una frase de contraseña larga — Argon2id solo ralentiza la fuerza bruta, no la impide.';

  @override
  String get plaintextWarningTitle => 'Texto plano: sin cifrado';

  @override
  String get plaintextWarningBody =>
      'Las sesiones, claves y known hosts se almacenarán sin cifrar. Cualquier persona con acceso al sistema de archivos de este equipo podrá leerlos.';

  @override
  String get plaintextAcknowledge =>
      'Entiendo que mis datos no estarán cifrados';

  @override
  String get plaintextAcknowledgeRequired =>
      'Confirme que lo entiende antes de continuar.';

  @override
  String get passwordLabel => 'Contraseña';

  @override
  String get masterPasswordLabel => 'Contraseña maestra';
}
