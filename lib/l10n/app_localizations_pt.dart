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
  String get appSettings => 'Configurações do Aplicativo';

  @override
  String get yes => 'Sim';

  @override
  String get no => 'Não';

  @override
  String get importWhatToImport => 'O que importar:';

  @override
  String get exportWhatToExport => 'O que exportar:';

  @override
  String get enterMasterPasswordPrompt => 'Digite a senha mestra:';

  @override
  String get nextStep => 'Próximo';

  @override
  String get includeCredentials => 'Incluir senhas e chaves SSH';

  @override
  String get includePasswords => 'Senhas de sessões';

  @override
  String get embeddedKeys => 'Chaves integradas';

  @override
  String get managerKeys => 'Chaves do gerenciador';

  @override
  String get managerKeysMayBeLarge =>
      'Chaves do gerenciador podem exceder o tamanho do QR';

  @override
  String get qrPasswordWarning =>
      'As chaves SSH estão desativadas por padrão na exportação.';

  @override
  String get sshKeysMayBeLarge => 'As chaves podem exceder o tamanho do QR';

  @override
  String exportTotalSize(String size) {
    return 'Tamanho total: $size';
  }

  @override
  String get qrCredentialsWarning =>
      'Senhas e chaves SSH FICARÃO visíveis no código QR';

  @override
  String get qrCredentialsTooLarge =>
      'As credenciais tornam o código QR muito grande';

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
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count associações descartadas (alvos ausentes)',
      one: '$count associação descartada (alvo ausente)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessões corrompidas ignoradas',
      one: '$count sessão corrompida ignorada',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'Sessões';

  @override
  String get emptyFolders => 'Pastas vazias';

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
  String get emptyFolder => 'Pasta vazia';

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
  String get masterPassword => 'Senha mestra';

  @override
  String get confirmPassword => 'Confirmar senha';

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
  String sshConfigPreviewHostsFound(int count) {
    return '$count host(s) encontrado(s)';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'Nenhum host importável encontrado neste arquivo.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'Não foi possível ler os arquivos de chave para: $hosts. Esses hosts serão importados sem credenciais.';
  }

  @override
  String sshConfigPreviewFolderLabel(String folder) {
    return 'Importado para a pasta: $folder';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'Exportar arquivo';

  @override
  String get exportArchiveSubtitle =>
      'Salvar sessões, configurações e chaves em arquivo .lfs criptografado';

  @override
  String get exportQrCode => 'Exportar código QR';

  @override
  String get exportQrCodeSubtitle =>
      'Compartilhar sessões e chaves selecionadas via código QR';

  @override
  String get importArchive => 'Importar arquivo';

  @override
  String get importArchiveSubtitle => 'Carregar dados de arquivo .lfs';

  @override
  String get importFromSshDir => 'Importar de ~/.ssh';

  @override
  String get importFromSshDirSubtitle =>
      'Escolha hosts do arquivo de configuração e/ou chaves privadas de ~/.ssh';

  @override
  String get sshDirImportHostsSection => 'Hosts do arquivo de configuração';

  @override
  String get sshDirImportKeysSection => 'Chaves em ~/.ssh';

  @override
  String importSshKeysFound(int count) {
    return '$count chave(s) encontrada(s) — escolha quais importar';
  }

  @override
  String get importSshKeysNoneFound =>
      'Nenhuma chave privada encontrada em ~/.ssh.';

  @override
  String get sshKeyAlreadyImported => 'já no armazenamento';

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
      'Muito grande — desmarque alguns itens ou use a exportação em arquivo .lfs.';

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
  String get errExportPickerUnavailable =>
      'O seletor de pastas do sistema não está disponível. Tente outro local ou verifique as permissões de armazenamento do aplicativo.';

  @override
  String get biometricUnlockPrompt => 'Desbloquear LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'Desbloquear com biometria';

  @override
  String get biometricUnlockSubtitle =>
      'Evite digitar a senha mestra ao iniciar o aplicativo.';

  @override
  String get biometricNotAvailable =>
      'O desbloqueio biométrico não está disponível neste dispositivo.';

  @override
  String get biometricEnableFailed =>
      'Não foi possível ativar o desbloqueio biométrico.';

  @override
  String get biometricEnabled => 'Desbloqueio biométrico ativado';

  @override
  String get biometricDisabled => 'Desbloqueio biométrico desativado';

  @override
  String get currentPasswordIncorrect => 'A senha atual está incorreta';

  @override
  String get wrongPassword => 'Senha incorreta';

  @override
  String get useKeychain => 'Criptografar com chaveiro do sistema';

  @override
  String get useKeychainSubtitle =>
      'Armazenar a chave do banco de dados no cofre de credenciais do sistema. Desligado = banco de dados em texto simples.';

  @override
  String get lockScreenTitle => 'LetsFLUTssh está bloqueado';

  @override
  String get lockScreenSubtitle =>
      'Digite a senha mestra ou use a biometria para continuar.';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get autoLockTitle => 'Bloquear automaticamente após inatividade';

  @override
  String get autoLockSubtitle =>
      'Bloqueia a interface após este período de inatividade. O banco de dados criptografado só é re-bloqueado quando não há sessões SSH ativas, para não interromper operações longas.';

  @override
  String get autoLockOff => 'Desativado';

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
  String get errLfsDecryptFailed =>
      'Senha mestra incorreta ou arquivo .lfs corrompido';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'Arquivo muito grande ($sizeMb MB). O limite é de $limitMb MB — interrompido antes da descriptografia para proteger a memória.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'Entrada known_hosts muito grande ($sizeMb MB). O limite é de $limitMb MB — interrompido para manter a importação responsiva.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'Falha na importação — seus dados foram restaurados ao estado anterior. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'O arquivo usa o esquema v$found, mas esta versão do app só entende até v$supported. Atualize o aplicativo para importá-lo.';
  }

  @override
  String get progressReadingArchive => 'Lendo arquivo…';

  @override
  String get progressDecrypting => 'Descriptografando…';

  @override
  String get progressParsingArchive => 'Analisando arquivo…';

  @override
  String get progressImportingSessions => 'Importando sessões';

  @override
  String get progressImportingFolders => 'Importando pastas';

  @override
  String get progressImportingManagerKeys => 'Importando chaves SSH';

  @override
  String get progressImportingTags => 'Importando tags';

  @override
  String get progressImportingSnippets => 'Importando snippets';

  @override
  String get progressApplyingConfig => 'Aplicando configuração…';

  @override
  String get progressImportingKnownHosts => 'Importando known_hosts…';

  @override
  String get progressCollectingData => 'Coletando dados…';

  @override
  String get progressEncrypting => 'Criptografando…';

  @override
  String get progressWritingArchive => 'Gravando arquivo…';

  @override
  String get progressReencrypting => 'Recriptografando armazenamentos…';

  @override
  String get progressWorking => 'Processando…';

  @override
  String get importFromLink => 'Importar de link QR';

  @override
  String get importFromLinkSubtitle =>
      'Cole um deep-link letsflutssh:// copiado de outro dispositivo';

  @override
  String get pasteImportLinkTitle => 'Colar link de importação';

  @override
  String get pasteImportLinkDescription =>
      'Cole o link letsflutssh://import?d=… (ou o payload bruto) gerado em outro dispositivo. Sem necessidade de câmera.';

  @override
  String get pasteFromClipboard => 'Colar da área de transferência';

  @override
  String get invalidImportLink =>
      'O link não contém um payload válido do LetsFLUTssh';

  @override
  String get importAction => 'Importar';

  @override
  String get saveSessionToAssignTags =>
      'Salve a sessão primeiro para atribuir tags';

  @override
  String get noTagsAssigned => 'Nenhuma tag atribuída';

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
  String get transfersLabel => 'Transferências:';

  @override
  String transferCountActive(int count) {
    return '$count ativas';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count na fila';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count no histórico';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'Criado: $time';
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
    return 'Duração: $duration';
  }

  @override
  String get transferStatusQueued => 'Na fila';

  @override
  String get transferStartingUpload => 'Iniciando envio...';

  @override
  String get transferStartingDownload => 'Iniciando download...';

  @override
  String get transferCopying => 'Copiando...';

  @override
  String get transferDone => 'Concluído';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total arquivos';
  }

  @override
  String get folderNameLabel => 'NOME DA PASTA';

  @override
  String folderAlreadyExists(String name) {
    return 'A pasta \"$name\" já existe';
  }

  @override
  String get dropKeyFileHere => 'Arraste o arquivo de chave aqui';

  @override
  String get sessionNoCredentials =>
      'A sessão não tem credenciais — edite-a para adicionar uma senha ou chave';

  @override
  String dragItemCount(int count) {
    return '$count itens';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'Selecionar tudo ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'Tamanho: $size KB / $max KB máx.';
  }

  @override
  String get noActiveTerminals => 'Nenhum terminal ativo';

  @override
  String get connectFromSessionsTab => 'Conecte-se pela aba Sessões';

  @override
  String fileNotFound(String path) {
    return 'Arquivo não encontrado: $path';
  }

  @override
  String get sshConnectionChannel => 'Conexão SSH';

  @override
  String get sshConnectionChannelDesc =>
      'Mantém as conexões SSH ativas em segundo plano.';

  @override
  String get sshActive => 'SSH ativo';

  @override
  String activeConnectionCount(int count) {
    return '$count conexão(ões) ativa(s)';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count itens, $size';
  }

  @override
  String get maximize => 'Maximizar';

  @override
  String get restore => 'Restaurar';

  @override
  String get duplicateDownShortcut => 'Duplicar abaixo (Ctrl+Shift+\\)';

  @override
  String get security => 'Segurança';

  @override
  String get knownHosts => 'Hosts conhecidos';

  @override
  String get knownHostsSubtitle =>
      'Gerenciar impressões digitais de servidores SSH confiáveis';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts conhecidos',
      one: '1 host conhecido',
      zero: 'Nenhum host conhecido',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'Nenhum host conhecido. Conecte-se a um servidor para adicionar um.';

  @override
  String get removeHost => 'Remover host';

  @override
  String removeHostConfirm(String host) {
    return 'Remover $host dos hosts conhecidos? A chave será verificada novamente na próxima conexão.';
  }

  @override
  String get clearAllKnownHosts => 'Limpar todos os hosts conhecidos';

  @override
  String get clearAllKnownHostsConfirm =>
      'Remover todos os hosts conhecidos? Cada chave de servidor precisará ser verificada novamente.';

  @override
  String get importKnownHosts => 'Importar hosts conhecidos';

  @override
  String get importKnownHostsSubtitle =>
      'Importar de arquivo OpenSSH known_hosts';

  @override
  String get exportKnownHosts => 'Exportar hosts conhecidos';

  @override
  String importedHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts novos importados',
      one: '1 host novo importado',
      zero: 'Nenhum host novo importado',
    );
    return '$_temp0';
  }

  @override
  String get clearedAllHosts => 'Todos os hosts conhecidos foram limpos';

  @override
  String removedHost(String host) {
    return '$host removido';
  }

  @override
  String get noHostsToExport => 'Nenhum host para exportar';

  @override
  String get tools => 'Ferramentas';

  @override
  String get sshKeys => 'Chaves SSH';

  @override
  String get sshKeysSubtitle =>
      'Gerenciar pares de chaves SSH para autenticação';

  @override
  String get noKeys => 'Sem chaves SSH. Importe ou gere uma.';

  @override
  String get generateKey => 'Gerar chave';

  @override
  String get importKey => 'Importar chave';

  @override
  String get keyLabel => 'Nome da chave';

  @override
  String get keyLabelHint => 'ex. Servidor de trabalho, GitHub';

  @override
  String get selectKeyType => 'Tipo de chave';

  @override
  String get generating => 'Gerando...';

  @override
  String keyGenerated(String label) {
    return 'Chave gerada: $label';
  }

  @override
  String keyImported(String label) {
    return 'Chave importada: $label';
  }

  @override
  String get deleteKey => 'Excluir chave';

  @override
  String deleteKeyConfirm(String label) {
    return 'Excluir chave \"$label\"? Sessões que a usam perderão o acesso.';
  }

  @override
  String keyDeleted(String label) {
    return 'Chave excluída: $label';
  }

  @override
  String get publicKey => 'Chave pública';

  @override
  String get publicKeyCopied =>
      'Chave pública copiada para a área de transferência';

  @override
  String get pastePrivateKey => 'Colar chave privada (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Dados de chave PEM inválidos';

  @override
  String get selectFromKeyStore => 'Selecionar do armazenamento de chaves';

  @override
  String get noKeySelected => 'Nenhuma chave selecionada';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chaves',
      one: '1 chave',
      zero: 'Sem chaves',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'Gerada';

  @override
  String get passphraseRequired => 'Frase secreta necessária';

  @override
  String passphrasePrompt(String host) {
    return 'A chave SSH para $host está criptografada. Digite a frase secreta para desbloqueá-la.';
  }

  @override
  String get passphraseWrong =>
      'Frase secreta incorreta. Por favor, tente novamente.';

  @override
  String get passphrase => 'Frase secreta';

  @override
  String get rememberPassphrase => 'Lembrar para esta sessão';

  @override
  String get masterPasswordSubtitle => 'Proteger credenciais salvas com senha';

  @override
  String get setMasterPassword => 'Definir senha mestra';

  @override
  String get changeMasterPassword => 'Alterar senha mestra';

  @override
  String get removeMasterPassword => 'Remover senha mestra';

  @override
  String get masterPasswordEnabled => 'Credenciais protegidas por senha mestra';

  @override
  String get masterPasswordDisabled =>
      'Credenciais usam chave auto-gerada (sem senha)';

  @override
  String get enterMasterPassword =>
      'Digite a senha mestra para acessar suas credenciais salvas.';

  @override
  String get wrongMasterPassword =>
      'Senha incorreta. Por favor, tente novamente.';

  @override
  String get newPassword => 'Nova senha';

  @override
  String get currentPassword => 'Senha atual';

  @override
  String get passwordTooShort => 'A senha deve ter pelo menos 8 caracteres';

  @override
  String get masterPasswordSet => 'Senha mestra ativada';

  @override
  String get masterPasswordChanged => 'Senha mestra alterada';

  @override
  String get masterPasswordRemoved => 'Senha mestra removida';

  @override
  String get masterPasswordWarning =>
      'Se você esquecer esta senha, todas as senhas e chaves SSH salvas serão perdidas. Não há recuperação.';

  @override
  String get forgotPassword => 'Esqueceu a senha?';

  @override
  String get forgotPasswordWarning =>
      'Isso excluirá TODAS as senhas, chaves SSH e frases secretas salvas. Sessões e configurações serão mantidas. Esta ação é irreversível.';

  @override
  String get resetAndDeleteCredentials => 'Redefinir e excluir dados';

  @override
  String get credentialsReset => 'Todas as credenciais salvas foram excluídas';

  @override
  String get derivingKey => 'Derivando chave de criptografia...';

  @override
  String get reEncrypting => 'Re-criptografando dados...';

  @override
  String get confirmRemoveMasterPassword =>
      'Digite sua senha atual para remover a proteção de senha mestra. As credenciais serão re-criptografadas com uma chave auto-gerada.';

  @override
  String get securitySetupTitle => 'Configuração de segurança';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'Chaveiro do sistema detectado ($keychainName). Seus dados serão criptografados automaticamente usando o chaveiro do sistema.';
  }

  @override
  String get securitySetupKeychainOptional =>
      'Você também pode definir uma senha mestra para proteção adicional.';

  @override
  String get securitySetupNoKeychain =>
      'Nenhum chaveiro do sistema detectado. Sem chaveiro, os dados de sessão (hosts, senhas, chaves) serão armazenados em texto simples.';

  @override
  String get securitySetupNoKeychainHint =>
      'Isso é normal no WSL, Linux sem interface gráfica ou instalações mínimas. Para habilitar o chaveiro no Linux: instale libsecret e um daemon de chaveiro (ex. gnome-keyring).';

  @override
  String get securitySetupRecommendMasterPassword =>
      'Recomendamos definir uma senha mestra para proteger seus dados.';

  @override
  String get continueWithKeychain => 'Continuar com chaveiro';

  @override
  String get continueWithoutEncryption => 'Continuar sem criptografia';

  @override
  String get securityLevel => 'Nível de segurança';

  @override
  String get securityLevelPlaintext => 'Nenhum (texto simples)';

  @override
  String get securityLevelKeychain => 'Chaveiro do sistema';

  @override
  String get securityLevelMasterPassword => 'Senha mestra';

  @override
  String get keychainStatus => 'Chaveiro';

  @override
  String keychainAvailable(String name) {
    return 'Disponível ($name)';
  }

  @override
  String get keychainNotAvailable => 'Não disponível';

  @override
  String get enableKeychain => 'Ativar criptografia do chaveiro';

  @override
  String get enableKeychainSubtitle =>
      'Recriptografar dados armazenados usando chaveiro do sistema';

  @override
  String get keychainEnabled => 'Criptografia do chaveiro ativada';

  @override
  String get manageMasterPassword => 'Gerenciar senha mestra';

  @override
  String get manageMasterPasswordSubtitle =>
      'Definir, alterar ou remover senha mestra';

  @override
  String get snippets => 'Snippets';

  @override
  String get snippetsSubtitle => 'Gerencie snippets de comandos reutilizáveis';

  @override
  String get noSnippets => 'Ainda não há snippets';

  @override
  String get addSnippet => 'Adicionar snippet';

  @override
  String get editSnippet => 'Editar snippet';

  @override
  String get deleteSnippet => 'Excluir snippet';

  @override
  String deleteSnippetConfirm(String title) {
    return 'Excluir o snippet \"$title\"?';
  }

  @override
  String get snippetTitle => 'Título';

  @override
  String get snippetTitleHint => 'ex.: Deploy, Reiniciar serviço';

  @override
  String get snippetCommand => 'Comando';

  @override
  String get snippetCommandHint => 'ex.: sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'Descrição (opcional)';

  @override
  String get snippetDescriptionHint => 'O que este comando faz?';

  @override
  String get snippetSaved => 'Snippet salvo';

  @override
  String snippetDeleted(String title) {
    return 'Snippet \"$title\" excluído';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets',
      one: '1 snippet',
      zero: 'Sem snippets',
    );
    return '$_temp0';
  }

  @override
  String get runSnippet => 'Executar';

  @override
  String get pinToSession => 'Fixar nesta sessão';

  @override
  String get unpinFromSession => 'Desafixar desta sessão';

  @override
  String get pinnedSnippets => 'Fixados';

  @override
  String get allSnippets => 'Todos';

  @override
  String get sendToTerminal => 'Enviar ao terminal';

  @override
  String get commandCopied => 'Comando copiado';

  @override
  String get tags => 'Tags';

  @override
  String get tagsSubtitle => 'Organize sessões e pastas com tags coloridas';

  @override
  String get noTags => 'Ainda não há tags';

  @override
  String get addTag => 'Adicionar tag';

  @override
  String get deleteTag => 'Excluir tag';

  @override
  String deleteTagConfirm(String name) {
    return 'Excluir a tag \"$name\"? Ela será removida de todas as sessões e pastas.';
  }

  @override
  String get tagName => 'Nome da tag';

  @override
  String get tagNameHint => 'ex.: Produção, Staging';

  @override
  String get tagColor => 'Cor';

  @override
  String get tagCreated => 'Tag criada';

  @override
  String tagDeleted(String name) {
    return 'Tag \"$name\" excluída';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags',
      one: '1 tag',
      zero: 'Sem tags',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'Gerenciar tags';

  @override
  String get editTags => 'Editar tags';

  @override
  String get fullBackup => 'Backup completo';

  @override
  String get sessionsOnly => 'Sessões';

  @override
  String get sessionKeysFromManager => 'Chaves de sessão do gerenciador';

  @override
  String get allKeysFromManager => 'Todas as chaves do gerenciador';

  @override
  String exportTags(int count) {
    return 'Etiquetas ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'Trechos ($count)';
  }

  @override
  String get disableKeychain => 'Desativar criptografia do chaveiro';

  @override
  String get disableKeychainSubtitle =>
      'Mudar para armazenamento em texto simples (não recomendado)';

  @override
  String get disableKeychainConfirm =>
      'O banco de dados será recriptografado sem chave. Sessões e chaves serão armazenadas em texto simples no disco. Continuar?';

  @override
  String get keychainDisabled => 'Criptografia do chaveiro desativada';

  @override
  String get presetFullImport => 'Importação completa';

  @override
  String get presetSelective => 'Seletivo';

  @override
  String get presetCustom => 'Personalizado';

  @override
  String get sessionSshKeys => 'Chaves SSH da sessão';

  @override
  String get allManagerKeys => 'Todas as chaves do gerenciador';

  @override
  String get browseFiles => 'Procurar arquivos…';

  @override
  String get sshDirSessionAlreadyImported => 'já está nas sessões';

  @override
  String get languageSubtitle => 'Idioma da interface';

  @override
  String get themeSubtitle => 'Escuro, claro ou seguir o sistema';

  @override
  String get uiScaleSubtitle => 'Escalar toda a interface';

  @override
  String get terminalFontSizeSubtitle =>
      'Tamanho da fonte na saída do terminal';

  @override
  String get scrollbackLinesSubtitle =>
      'Tamanho do buffer de histórico do terminal';

  @override
  String get keepAliveIntervalSubtitle =>
      'Segundos entre pacotes SSH keep-alive (0 = desligado)';

  @override
  String get sshTimeoutSubtitle => 'Tempo limite de conexão em segundos';

  @override
  String get defaultPortSubtitle => 'Porta padrão para novas sessões';

  @override
  String get parallelWorkersSubtitle =>
      'Trabalhadores de transferência SFTP paralelos';

  @override
  String get maxHistorySubtitle => 'Máximo de comandos salvos no histórico';

  @override
  String get calculateFolderSizesSubtitle =>
      'Mostrar tamanho total ao lado das pastas na barra lateral';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Consultar o GitHub por uma nova versão ao iniciar o app';

  @override
  String get enableLoggingSubtitle =>
      'Gravar eventos do app em arquivo de log rotativo';

  @override
  String get exportWithoutPassword => 'Exportar sem senha?';

  @override
  String get exportWithoutPasswordWarning =>
      'O arquivo não será criptografado. Qualquer pessoa com acesso ao arquivo poderá ler seus dados, incluindo senhas e chaves privadas.';

  @override
  String get continueWithoutPassword => 'Continuar sem senha';
}
