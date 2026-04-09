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
  String get couldNotOpenInstaller => 'No se pudo abrir el instalador';

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
  String get sessions => 'Sesiones';

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
  String get qrGenerationFailed => 'Error al generar QR';

  @override
  String get scanWithCameraApp =>
      'Escanee con cualquier aplicación de cámara en un dispositivo\nque tenga LetsFLUTssh instalado.';

  @override
  String get noPasswordsInQr =>
      'Este código QR no contiene contraseñas ni claves';

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
  String get sortByName => 'Ordenar por nombre';

  @override
  String get sortByStatus => 'Ordenar por estado';

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
  String get setMasterPasswordHint =>
      'Establezca una contraseña maestra para cifrar el archivo.';

  @override
  String get passwordsDoNotMatch => 'Las contraseñas no coinciden';

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
      'Demasiado grande — deseleccione algunas sesiones o use la exportación en archivo .lfs.';

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
  String get maximize => 'Maximizar';

  @override
  String get restore => 'Restaurar';

  @override
  String get duplicateDownShortcut => 'Duplicar abajo (Ctrl+Shift+\\)';

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
