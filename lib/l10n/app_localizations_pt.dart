// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class SPt extends S {
  SPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Fechar';

  @override
  String get delete => 'Excluir';

  @override
  String get save => 'Salvar';

  @override
  String get connect => 'Conectar';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get import_ => 'Importar';

  @override
  String get export_ => 'Exportar';

  @override
  String get rename => 'Renomear';

  @override
  String get create => 'Criar';

  @override
  String get back => 'Voltar';

  @override
  String get copy => 'Copiar';

  @override
  String get paste => 'Colar';

  @override
  String get select => 'Selecionar';

  @override
  String get required => 'Obrigatório';

  @override
  String get settings => 'Configurações';

  @override
  String get terminal => 'Terminal';

  @override
  String get files => 'Arquivos';

  @override
  String get transfer => 'Transferência';

  @override
  String get open => 'Abrir';

  @override
  String get search => 'Buscar...';

  @override
  String get filter => 'Filtrar...';

  @override
  String get merge => 'Mesclar';

  @override
  String get replace => 'Substituir';

  @override
  String get reconnect => 'Reconectar';

  @override
  String get updateAvailable => 'Atualização Disponível';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'A versão $version está disponível (atual: v$current).';
  }

  @override
  String get releaseNotes => 'Notas da versão:';

  @override
  String get skipThisVersion => 'Pular Esta Versão';

  @override
  String get unskip => 'Desfazer pular';

  @override
  String get downloadAndInstall => 'Baixar e Instalar';

  @override
  String get openInBrowser => 'Abrir no Navegador';

  @override
  String get couldNotOpenBrowser =>
      'Não foi possível abrir o navegador — URL copiada para a área de transferência';

  @override
  String get checkForUpdates => 'Verificar Atualizações';

  @override
  String get checkForUpdatesOnStartup => 'Verificar Atualizações ao Iniciar';

  @override
  String get checking => 'Verificando...';

  @override
  String get youreUpToDate => 'Você está atualizado';

  @override
  String get updateCheckFailed => 'Falha ao verificar atualizações';

  @override
  String get unknownError => 'Erro desconhecido';

  @override
  String downloadingPercent(int percent) {
    return 'Baixando... $percent%';
  }

  @override
  String get downloadComplete => 'Download concluído';

  @override
  String get installNow => 'Instalar Agora';

  @override
  String get couldNotOpenInstaller => 'Não foi possível abrir o instalador';

  @override
  String versionAvailable(String version) {
    return 'Versão $version disponível';
  }

  @override
  String currentVersion(String version) {
    return 'Atual: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'Chave SSH recebida: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return '$count sessão(ões) importada(s) via QR';
  }

  @override
  String importedSessions(int count) {
    return '$count sessão(ões) importada(s)';
  }

  @override
  String importFailed(String error) {
    return 'Falha na importação: $error';
  }

  @override
  String get sessions => 'Sessões';

  @override
  String get sessionsHeader => 'SESSÕES';

  @override
  String get savedSessions => 'Sessões salvas';

  @override
  String get activeConnections => 'Conexões ativas';

  @override
  String get openTabs => 'Abas abertas';

  @override
  String get noSavedSessions => 'Nenhuma sessão salva';

  @override
  String get addSession => 'Adicionar Sessão';

  @override
  String get noSessions => 'Nenhuma sessão';

  @override
  String get noSessionsToExport => 'Nenhuma sessão para exportar';

  @override
  String nSelectedCount(int count) {
    return '$count selecionado(s)';
  }

  @override
  String get selectAll => 'Selecionar Tudo';

  @override
  String get deselectAll => 'Desmarcar Tudo';

  @override
  String get moveTo => 'Mover para...';

  @override
  String get moveToFolder => 'Mover para Pasta';

  @override
  String get rootFolder => '/ (raiz)';

  @override
  String get newFolder => 'Nova Pasta';

  @override
  String get newConnection => 'Nova Conexão';

  @override
  String get editConnection => 'Editar Conexão';

  @override
  String get duplicate => 'Duplicar';

  @override
  String get deleteSession => 'Excluir Sessão';

  @override
  String get renameFolder => 'Renomear Pasta';

  @override
  String get deleteFolder => 'Excluir Pasta';

  @override
  String get deleteSelected => 'Excluir Selecionados';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return 'Excluir $parts?\n\nEsta ação não pode ser desfeita.';
  }

  @override
  String nSessions(int count) {
    return '$count sessão(ões)';
  }

  @override
  String nFolders(int count) {
    return '$count pasta(s)';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'Excluir pasta \"$name\"?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'Isso também excluirá $count sessão(ões) dentro dela.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return 'Excluir \"$name\"?';
  }

  @override
  String get connection => 'Conexão';

  @override
  String get auth => 'Autenticação';

  @override
  String get options => 'Opções';

  @override
  String get sessionName => 'Nome da Sessão';

  @override
  String get hintMyServer => 'Meu Servidor';

  @override
  String get hostRequired => 'Host *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'Porta';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'Usuário *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'Senha';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'Senha da Chave';

  @override
  String get hintOptional => 'Opcional';

  @override
  String get hidePemText => 'Ocultar texto PEM';

  @override
  String get pastePemKeyText => 'Colar texto da chave PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'Nenhuma opção adicional ainda';

  @override
  String get saveAndConnect => 'Salvar e Conectar';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst =>
      'Forneça um arquivo de chave ou texto PEM primeiro';

  @override
  String get keyTextPem => 'Texto da Chave (PEM)';

  @override
  String get selectKeyFile => 'Selecionar Arquivo de Chave';

  @override
  String get clearKeyFile => 'Limpar arquivo de chave';

  @override
  String get authOrDivider => 'OU';

  @override
  String get providePasswordOrKey => 'Forneça uma senha ou chave SSH';

  @override
  String get quickConnect => 'Conexão Rápida';

  @override
  String get scanQrCode => 'Escanear Código QR';

  @override
  String get qrGenerationFailed => 'Falha ao gerar QR';

  @override
  String get scanWithCameraApp =>
      'Escaneie com qualquer aplicativo de câmera em um dispositivo\nque tenha o LetsFLUTssh instalado.';

  @override
  String get noPasswordsInQr => 'Nenhuma senha ou chave está neste código QR';

  @override
  String get copyLink => 'Copiar Link';

  @override
  String get linkCopied => 'Link copiado para a área de transferência';

  @override
  String get hostKeyChanged => 'Chave do Host Alterada!';

  @override
  String get unknownHost => 'Host Desconhecido';

  @override
  String get hostKeyChangedWarning =>
      'AVISO: A chave do host deste servidor foi alterada. Isso pode indicar um ataque man-in-the-middle, ou o servidor pode ter sido reinstalado.';

  @override
  String get unknownHostMessage =>
      'A autenticidade deste host não pode ser verificada. Tem certeza de que deseja continuar a conexão?';

  @override
  String get host => 'Host';

  @override
  String get keyType => 'Tipo de chave';

  @override
  String get fingerprint => 'Impressão digital';

  @override
  String get fingerprintCopied => 'Impressão digital copiada';

  @override
  String get copyFingerprint => 'Copiar impressão digital';

  @override
  String get acceptAnyway => 'Aceitar Mesmo Assim';

  @override
  String get accept => 'Aceitar';

  @override
  String get importData => 'Importar Dados';

  @override
  String get masterPassword => 'Senha Mestra';

  @override
  String get confirmPassword => 'Confirmar Senha';

  @override
  String get importModeMergeDescription =>
      'Adicionar novas sessões, manter existentes';

  @override
  String get importModeReplaceDescription =>
      'Substituir todas as sessões pelas importadas';

  @override
  String errorPrefix(String error) {
    return 'Erro: $error';
  }

  @override
  String get folderName => 'Nome da pasta';

  @override
  String get newName => 'Novo nome';

  @override
  String deleteItems(String names) {
    return 'Excluir $names?';
  }

  @override
  String deleteNItems(int count) {
    return 'Excluir $count itens';
  }

  @override
  String deletedItem(String name) {
    return '$name excluído';
  }

  @override
  String deletedNItems(int count) {
    return '$count itens excluídos';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'Falha ao criar pasta: $error';
  }

  @override
  String failedToRename(String error) {
    return 'Falha ao renomear: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return 'Falha ao excluir $name: $error';
  }

  @override
  String get editPath => 'Editar Caminho';

  @override
  String get root => 'Raiz';

  @override
  String get controllersNotInitialized => 'Controladores não inicializados';

  @override
  String get initializingSftp => 'Inicializando SFTP...';

  @override
  String get clearHistory => 'Limpar histórico';

  @override
  String get noTransfersYet => 'Nenhuma transferência ainda';

  @override
  String get duplicateTab => 'Duplicar Aba';

  @override
  String get duplicateTabShortcut => 'Duplicar Aba (Ctrl+\\)';

  @override
  String get copyDown => 'Copiar Abaixo';

  @override
  String get copyDownShortcut => 'Copiar Abaixo (Ctrl+Shift+\\)';

  @override
  String get previous => 'Anterior';

  @override
  String get next => 'Próximo';

  @override
  String get closeEsc => 'Fechar (Esc)';

  @override
  String get closeAll => 'Fechar Todas';

  @override
  String get closeOthers => 'Fechar Outras';

  @override
  String get closeTabsToTheLeft => 'Fechar Abas à Esquerda';

  @override
  String get closeTabsToTheRight => 'Fechar Abas à Direita';

  @override
  String get sortByName => 'Ordenar por Nome';

  @override
  String get sortByStatus => 'Ordenar por Status';

  @override
  String get noActiveSession => 'Nenhuma sessão ativa';

  @override
  String get createConnectionHint =>
      'Crie uma nova conexão ou selecione uma na barra lateral';

  @override
  String get hideSidebar => 'Ocultar Barra Lateral (Ctrl+B)';

  @override
  String get showSidebar => 'Mostrar Barra Lateral (Ctrl+B)';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystemDefault => 'Auto';

  @override
  String get theme => 'Tema';

  @override
  String get themeDark => 'Escuro';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get appearance => 'Aparência';

  @override
  String get connectionSection => 'Conexão';

  @override
  String get transfers => 'Transferências';

  @override
  String get data => 'Dados';

  @override
  String get logging => 'Registro';

  @override
  String get updates => 'Atualizações';

  @override
  String get about => 'Sobre';

  @override
  String get resetToDefaults => 'Restaurar Padrões';

  @override
  String get uiScale => 'Escala da Interface';

  @override
  String get terminalFontSize => 'Tamanho da Fonte do Terminal';

  @override
  String get scrollbackLines => 'Linhas de Histórico';

  @override
  String get keepAliveInterval => 'Intervalo de Keep-Alive (seg)';

  @override
  String get sshTimeout => 'Tempo Limite SSH (seg)';

  @override
  String get defaultPort => 'Porta Padrão';

  @override
  String get parallelWorkers => 'Trabalhadores Paralelos';

  @override
  String get maxHistory => 'Histórico Máximo';

  @override
  String get calculateFolderSizes => 'Calcular Tamanho das Pastas';

  @override
  String get exportData => 'Exportar Dados';

  @override
  String get exportDataSubtitle =>
      'Salvar sessões, configurações e chaves em arquivo .lfs criptografado';

  @override
  String get importDataSubtitle => 'Carregar dados de arquivo .lfs';

  @override
  String get setMasterPasswordHint =>
      'Defina uma senha mestra para criptografar o arquivo.';

  @override
  String get passwordsDoNotMatch => 'As senhas não coincidem';

  @override
  String exportedTo(String path) {
    return 'Exportado para: $path';
  }

  @override
  String exportFailed(String error) {
    return 'Falha na exportação: $error';
  }

  @override
  String get pathToLfsFile => 'Caminho do arquivo .lfs';

  @override
  String get hintLfsPath => '/caminho/para/exportacao.lfs';

  @override
  String get browse => 'Procurar';

  @override
  String get shareViaQrCode => 'Compartilhar via Código QR';

  @override
  String get shareViaQrSubtitle =>
      'Exportar sessões para QR para escaneamento por outro dispositivo';

  @override
  String get dataLocation => 'Local dos Dados';

  @override
  String get pathCopied => 'Caminho copiado para a área de transferência';

  @override
  String get urlCopied => 'URL copiada para a área de transferência';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — Cliente SSH/SFTP';
  }

  @override
  String get sourceCode => 'Código Fonte';

  @override
  String get enableLogging => 'Ativar Registro';

  @override
  String get logIsEmpty => 'O registro está vazio';

  @override
  String logExportedTo(String path) {
    return 'Registro exportado para: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Falha ao exportar registro: $error';
  }

  @override
  String get logsCleared => 'Registros limpos';

  @override
  String get copiedToClipboard => 'Copiado para a área de transferência';

  @override
  String get copyLog => 'Copiar registro';

  @override
  String get exportLog => 'Exportar registro';

  @override
  String get clearLogs => 'Limpar registros';

  @override
  String get local => 'Local';

  @override
  String get remote => 'Remoto';

  @override
  String get pickFolder => 'Escolher Pasta';

  @override
  String get refresh => 'Atualizar';

  @override
  String get up => 'Acima';

  @override
  String get emptyDirectory => 'Diretório vazio';

  @override
  String get cancelSelection => 'Cancelar seleção';

  @override
  String get openSftpBrowser => 'Abrir Navegador SFTP';

  @override
  String get openSshTerminal => 'Abrir Terminal SSH';

  @override
  String get noActiveFileBrowsers => 'Nenhum navegador de arquivos ativo';

  @override
  String get useSftpFromSessions => 'Use \"SFTP\" nas Sessões';

  @override
  String get anotherInstanceRunning =>
      'Outra instância do LetsFLUTssh já está em execução.';

  @override
  String importFailedShort(String error) {
    return 'Falha na importação: $error';
  }

  @override
  String get saveLogAs => 'Salvar registro como';

  @override
  String get chooseSaveLocation => 'Escolher local para salvar';

  @override
  String get forward => 'Avançar';

  @override
  String get name => 'Nome';

  @override
  String get size => 'Tamanho';

  @override
  String get modified => 'Modificado';

  @override
  String get mode => 'Modo';

  @override
  String get owner => 'Proprietário';

  @override
  String get connectionError => 'Erro de conexão';

  @override
  String get resizeWindowToViewFiles =>
      'Redimensione a janela para visualizar os arquivos';

  @override
  String get completed => 'Concluído';

  @override
  String get connected => 'Conectado';

  @override
  String get disconnected => 'Desconectado';

  @override
  String get exit => 'Sair';

  @override
  String get exitConfirmation => 'As sessões ativas serão desconectadas. Sair?';

  @override
  String get hintFolderExample => 'ex.: Production';

  @override
  String get credentialsNotSet => 'Credenciais não definidas';

  @override
  String get exportSessionsViaQr => 'Exportar Sessões via QR';

  @override
  String get qrNoCredentialsWarning =>
      'Senhas e chaves SSH NÃO estão incluídas.\nAs sessões importadas precisarão ter as credenciais preenchidas.';

  @override
  String get qrTooManyForSingleCode =>
      'Sessões demais para um único código QR. Desmarque algumas ou use a exportação .lfs.';

  @override
  String get qrTooLarge =>
      'Muito grande — desmarque algumas sessões ou use a exportação em arquivo .lfs.';

  @override
  String get exportAll => 'Exportar Tudo';

  @override
  String get showQr => 'Mostrar QR';

  @override
  String get sort => 'Ordenar';

  @override
  String get resizePanelDivider => 'Redimensionar divisor de painel';

  @override
  String get youreRunningLatest => 'Você está usando a versão mais recente';

  @override
  String get liveLog => 'Log ao vivo';

  @override
  String transferNItems(int count) {
    return 'Transferir $count itens';
  }

  @override
  String get time => 'Tempo';

  @override
  String get failed => 'Falhou';

  @override
  String get errOperationNotPermitted => 'Operação não permitida';

  @override
  String get errNoSuchFileOrDirectory => 'Arquivo ou diretório não encontrado';

  @override
  String get errNoSuchProcess => 'Processo não encontrado';

  @override
  String get errIoError => 'Erro de E/S';

  @override
  String get errBadFileDescriptor => 'Descritor de arquivo inválido';

  @override
  String get errResourceTemporarilyUnavailable =>
      'Recurso temporariamente indisponível';

  @override
  String get errOutOfMemory => 'Memória esgotada';

  @override
  String get errPermissionDenied => 'Permissão negada';

  @override
  String get errFileExists => 'O arquivo já existe';

  @override
  String get errNotADirectory => 'Não é um diretório';

  @override
  String get errIsADirectory => 'É um diretório';

  @override
  String get errInvalidArgument => 'Argumento inválido';

  @override
  String get errTooManyOpenFiles => 'Muitos arquivos abertos';

  @override
  String get errNoSpaceLeftOnDevice => 'Sem espaço no dispositivo';

  @override
  String get errReadOnlyFileSystem => 'Sistema de arquivos somente leitura';

  @override
  String get errBrokenPipe => 'Pipe quebrado';

  @override
  String get errFileNameTooLong => 'Nome de arquivo muito longo';

  @override
  String get errDirectoryNotEmpty => 'Diretório não vazio';

  @override
  String get errAddressAlreadyInUse => 'Endereço já em uso';

  @override
  String get errCannotAssignAddress =>
      'Não é possível atribuir o endereço solicitado';

  @override
  String get errNetworkIsDown => 'Rede inativa';

  @override
  String get errNetworkIsUnreachable => 'Rede inacessível';

  @override
  String get errConnectionResetByPeer => 'Conexão redefinida pelo par';

  @override
  String get errConnectionTimedOut => 'Conexão expirou';

  @override
  String get errConnectionRefused => 'Conexão recusada';

  @override
  String get errHostIsDown => 'Host inativo';

  @override
  String get errNoRouteToHost => 'Sem rota para o host';

  @override
  String get errConnectionAborted => 'Conexão abortada';

  @override
  String get errAlreadyConnected => 'Já conectado';

  @override
  String get errNotConnected => 'Não conectado';

  @override
  String errSshConnectFailed(String host, int port) {
    return 'Falha ao conectar a $host:$port';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return 'Autenticação falhou para $user@$host';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return 'Conexão falhou para $host:$port';
  }

  @override
  String get errSshAuthAborted => 'Autenticação abortada';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return 'Chave do host rejeitada para $host:$port — aceite a chave do host ou verifique known_hosts';
  }

  @override
  String get errSshOpenShellFailed => 'Falha ao abrir o shell';

  @override
  String get errSshLoadKeyFileFailed =>
      'Falha ao carregar o arquivo de chave SSH';

  @override
  String get errSshParseKeyFailed => 'Falha ao analisar os dados da chave PEM';

  @override
  String get errSshConnectionDisposed => 'Conexão descartada';

  @override
  String get errSshNotConnected => 'Não conectado';

  @override
  String get errConnectionFailed => 'Conexão falhou';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'Conexão expirou após $seconds segundos';
  }

  @override
  String get errSessionClosed => 'Sessão encerrada';

  @override
  String errShellError(String error) {
    return 'Erro do shell: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'Reconexão falhou: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'Falha ao inicializar SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Download falhou: $error';
  }

  @override
  String get errDecryptionFailed =>
      'Falha ao descriptografar as credenciais. O arquivo de chave pode estar corrompido.';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'Login';

  @override
  String get protocol => 'Protocolo';

  @override
  String get typeLabel => 'Tipo';

  @override
  String get folder => 'Pasta';

  @override
  String nSubitems(int count) {
    return '$count item(ns)';
  }

  @override
  String get subitems => 'Itens';

  @override
  String get storagePermissionRequired =>
      'Permissão de armazenamento necessária para navegar arquivos locais';

  @override
  String get grantPermission => 'Conceder permissão';

  @override
  String get storagePermissionLimited =>
      'Acesso limitado — conceda permissão total de armazenamento para todos os arquivos';

  @override
  String progressConnecting(String host, int port) {
    return 'Conectando a $host:$port';
  }

  @override
  String get progressVerifyingHostKey => 'Verificando chave do host';

  @override
  String progressAuthenticating(String user) {
    return 'Autenticando como $user';
  }

  @override
  String get progressOpeningShell => 'Abrindo shell';

  @override
  String get progressOpeningSftp => 'Abrindo canal SFTP';

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
}
