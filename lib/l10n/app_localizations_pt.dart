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
  String get infoDialogProtectsHeader => 'Protege contra';

  @override
  String get infoDialogDoesNotProtectHeader => 'Não protege contra';

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
  String get credentialPromptPassphraseTitle =>
      'Passphrase da chave necessária';

  @override
  String get credentialPromptPasswordTitle => 'Senha necessária';

  @override
  String get credentialPromptHint =>
      'Digite-a para concluir a conexão. Nunca é gravada no disco.';

  @override
  String credentialPromptHintForSession(String session) {
    return 'Digite-a para concluir a conexão com “$session”. Nunca é gravada no disco.';
  }

  @override
  String get credentialPromptRememberSession => 'Lembrar nesta sessão';

  @override
  String get passwordBlankPromptHint =>
      'Deixe em branco para perguntar ao conectar';

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
  String get cut => 'Recortar';

  @override
  String get paste => 'Colar';

  @override
  String get select => 'Selecionar';

  @override
  String get copyModeTapToStart => 'Toque para marcar o início da seleção';

  @override
  String get copyModeExtending => 'Arraste para estender a seleção';

  @override
  String get copyModeSetAnchor => 'Definir âncora';

  @override
  String get copyModeCopySelection => 'Copiar seleção';

  @override
  String get required => 'Obrigatório';

  @override
  String get errFillRequiredFields =>
      'Preencha os campos obrigatórios marcados com *';

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
  String get noResults => 'Sem resultados';

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
  String get checkNow => 'Verificar agora';

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
  String get updateVerifying => 'A verificar…';

  @override
  String get downloadComplete => 'Download concluído';

  @override
  String get installNow => 'Instalar Agora';

  @override
  String get openReleasePage => 'Abrir página de lançamento';

  @override
  String get couldNotOpenInstaller => 'Não foi possível abrir o instalador';

  @override
  String get installerFailedOpenedReleasePage =>
      'Falha ao iniciar o instalador; página de lançamento aberta no navegador';

  @override
  String versionAvailable(String version) {
    return 'Versão $version disponível';
  }

  @override
  String currentVersion(String version) {
    return 'Atual: v$version';
  }

  @override
  String importedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessões importadas',
      one: '1 sessão importada',
      zero: 'Nenhuma sessão importada',
    );
    return '$_temp0';
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
  String nSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selecionados',
      one: '1 selecionado',
    );
    return '$_temp0';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessões',
      one: '1 sessão',
      zero: '0 sessões',
    );
    return '$_temp0';
  }

  @override
  String nFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pastas',
      one: '1 pasta',
      zero: '0 pastas',
    );
    return '$_temp0';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'Excluir pasta \"$name\"?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Isso também excluirá $count sessões dentro dela.',
      one: 'Isso também excluirá 1 sessão dentro dela.',
    );
    return '$_temp0';
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
  String get sectionAuthentication => 'Autenticação';

  @override
  String get sectionAdvanced => 'Avançado';

  @override
  String get moreOptions => 'Mais opções';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString regras de encaminhamento',
      one: '1 regra de encaminhamento',
      zero: 'Sem regras de encaminhamento de porta',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => 'Gerenciar…';

  @override
  String get authMethodAgent => 'Usar o ssh-agent do sistema';

  @override
  String get options => 'Opções';

  @override
  String get sessionName => 'Nome da Sessão';

  @override
  String get sessionNameAutoFromHost => 'Auto a partir do host';

  @override
  String get sessionNameAutoFromUrl => 'Auto a partir do host da URL';

  @override
  String get sessionNameAutoFromBucket => 'Auto a partir do bucket padrão';

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
  String get keyPassphrase => 'Passphrase da chave';

  @override
  String get hintOptional => 'Opcional';

  @override
  String get savedTypeToChange => 'Salvo — digite para alterar';

  @override
  String get hidePemText => 'Ocultar texto PEM';

  @override
  String get pastePemKeyText => 'Colar texto da chave PEM';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

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
  String get qrContainsCredentialsWarning =>
      'Este código QR contém credenciais. Mantenha a tela privada.';

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
  String get fingerprint => 'Fingerprint';

  @override
  String get fingerprintCopied => 'Fingerprint copiado';

  @override
  String get copyFingerprint => 'Copiar fingerprint';

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
  String get clearHistory => 'Limpar histórico';

  @override
  String get noTransfersYet => 'Nenhuma transferência ainda';

  @override
  String get duplicateTab => 'Duplicar Aba';

  @override
  String get duplicateTabShortcut => 'Duplicar Aba (Ctrl+\\)';

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
  String get logging => 'Logs';

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
  String get scrollbackLines => 'Linhas de scrollback';

  @override
  String get keepAliveInterval => 'Intervalo de Keep-Alive (seg)';

  @override
  String get sshTimeout => 'Tempo Limite SSH (seg)';

  @override
  String get defaultPort => 'Porta Padrão';

  @override
  String get parallelWorkers => 'Workers paralelos';

  @override
  String get maxHistory => 'Histórico Máximo';

  @override
  String get calculateFolderSizes => 'Calcular Tamanho das Pastas';

  @override
  String get verboseConnectionLog => 'Log de conexão detalhado';

  @override
  String get verboseConnectionLogSubtitle =>
      'Registrar o trace completo do handshake SSH e da autenticação no arquivo de log (para diagnosticar falhas de conexão)';

  @override
  String get exportData => 'Exportar Dados';

  @override
  String get exportRecordings => 'Gravações de sessão';

  @override
  String sshConfigPreviewHostsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts encontrados',
      one: '1 host encontrado',
      zero: '0 hosts encontrados',
    );
    return '$_temp0';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'Nenhum host importável encontrado neste arquivo.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'Não foi possível ler os arquivos de chave para: $hosts. Esses hosts serão importados sem credenciais.';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chaves encontradas — escolha quais importar',
      one: '1 chave encontrada — escolha se quer importar',
    );
    return '$_temp0';
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
  String get passwordStrengthWeak => 'Fraca';

  @override
  String get passwordStrengthModerate => 'Média';

  @override
  String get passwordStrengthStrong => 'Forte';

  @override
  String get passwordStrengthVeryStrong => 'Muito forte';

  @override
  String get tierPlaintextLabel => 'Plaintext';

  @override
  String get tierPlaintextSubtitle =>
      'Sem criptografia — apenas permissões de arquivo';

  @override
  String get tierKeychainLabel => 'Keychain';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'A chave vive em $keychain — desbloqueio automático ao iniciar';
  }

  @override
  String get tierKeychainUnavailable =>
      'Keychain do SO indisponível nesta instalação.';

  @override
  String get tierHardwareLabel => 'Hardware';

  @override
  String get tierParanoidLabel => 'Senha mestra (Paranoid)';

  @override
  String get tierHardwareUnavailable =>
      'Cofre de hardware indisponível nesta instalação.';

  @override
  String get pinLabel => 'Senha';

  @override
  String get l2UnlockTitle => 'Senha necessária';

  @override
  String get l2UnlockHint => 'Digite sua senha curta para continuar';

  @override
  String get l2WrongPassword => 'Senha incorreta';

  @override
  String get l3UnlockTitle => 'Digite a senha';

  @override
  String get l3UnlockHint =>
      'A senha desbloqueia o cofre vinculado ao hardware';

  @override
  String get l3WrongPin => 'Senha incorreta';

  @override
  String tierCooldownHint(int seconds) {
    return 'Tentar novamente em $seconds s';
  }

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
  String get dataLocation => 'Local dos Dados';

  @override
  String get dataStorageSection => 'Armazenamento';

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
  String get logIsEmpty => 'O log está vazio';

  @override
  String logExportedTo(String path) {
    return 'Log exportado para: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Falha ao exportar log: $error';
  }

  @override
  String get logsCleared => 'Logs limpos';

  @override
  String get copiedToClipboard => 'Copiado para a área de transferência';

  @override
  String get copyLog => 'Copiar log';

  @override
  String get exportLog => 'Exportar log';

  @override
  String get clearLogs => 'Limpar logs';

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
  String get saveLogAs => 'Salvar log como';

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
  String a11yConnectingTo(String host) {
    return 'Conectando a $host';
  }

  @override
  String a11yConnectedTo(String host) {
    return 'Conectado a $host';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return 'Desconectado de $host';
  }

  @override
  String a11yConnectionFailed(String host) {
    return 'Falha ao conectar a $host';
  }

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
  String get qrTooManyForSingleCode =>
      'Sessões demais para um único código QR. Desmarque algumas ou use a exportação .lfs.';

  @override
  String get qrTooLarge =>
      'Muito grande — desmarque alguns itens ou use a exportação em arquivo .lfs.';

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
  String get archivedLog => 'Log arquivado';

  @override
  String get loggingLevel => 'Nível de log';

  @override
  String get loggingLevelSubtitleInfo => 'Entradas rotineiras + avisos + erros';

  @override
  String get loggingLevelSubtitleWarn => 'Apenas caminhos degradados e erros';

  @override
  String get loggingLevelSubtitleError => 'Apenas erros';

  @override
  String get loggingLevelSubtitleOff => 'Logs rotineiros não são gravados';

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
  String get errBrokenPipe => 'Broken pipe';

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
  String get errConnectionResetByPeer => 'Conexão encerrada pelo peer';

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
  String get errConnectionLostReconnect =>
      'Conexão perdida — a sessão foi desconectada (suspensão ou rede). Reconecte-a pela lista de sessões.';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'Conexão expirou após $seconds segundos';
  }

  @override
  String get errSessionClosed => 'Sessão encerrada';

  @override
  String errSftpInitFailed(String error) {
    return 'Falha ao inicializar SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Download falhou: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'O seletor de pastas do sistema não está disponível. Tente outro local ou verifique as permissões de armazenamento do aplicativo.';

  @override
  String get biometricUnlockPrompt => 'Desbloquear LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'Desbloquear com biometria';

  @override
  String get biometricUnlockSubtitle =>
      'Evite digitar a senha — desbloqueie com o sensor biométrico do dispositivo.';

  @override
  String get biometricEnableFailed =>
      'Não foi possível ativar o desbloqueio biométrico.';

  @override
  String get biometricUnlockFailed =>
      'Falha no desbloqueio biométrico. Digite sua senha mestra.';

  @override
  String get biometricUnlockCancelled => 'Desbloqueio biométrico cancelado.';

  @override
  String get biometricNotEnrolled =>
      'Nenhuma credencial biométrica registrada neste dispositivo.';

  @override
  String get biometricSensorNotAvailable =>
      'Este dispositivo não tem sensor biométrico.';

  @override
  String get biometricSystemServiceMissing =>
      'O serviço de impressão digital (fprintd) não está instalado. Ver README → Installation.';

  @override
  String get currentPasswordIncorrect => 'A senha atual está incorreta';

  @override
  String get wrongPassword => 'Senha incorreta';

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
      'Bloqueia a interface após este período de inatividade. A chave do banco é apagada e o armazenamento criptografado é fechado a cada bloqueio; as sessões ativas permanecem conectadas por meio de um cache de credenciais por sessão, que é limpo ao encerrar a sessão.';

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
  String get errReleaseSignatureInvalid =>
      'Atualização rejeitada: os arquivos baixados não estão assinados pela chave de release fixada no app. Pode significar que o download foi adulterado no caminho, ou que este release não é para esta instalação. NÃO instale — reinstale manualmente pela página oficial de releases.';

  @override
  String get errReleaseManifestUnavailable =>
      'Não foi possível obter o manifest do release. Provavelmente um problema de rede, ou o release ainda está sendo publicado. Tente novamente em alguns minutos.';

  @override
  String get updateSecurityWarningTitle =>
      'Falha na verificação da atualização';

  @override
  String get updateReinstallAction => 'Abrir página de lançamentos';

  @override
  String get errLfsNotArchive =>
      'O arquivo selecionado não é um arquivo do LetsFLUTssh.';

  @override
  String get errLfsDecryptFailed =>
      'Senha mestra incorreta ou arquivo .lfs corrompido';

  @override
  String get errLfsArchiveTruncated =>
      'O arquivo está incompleto. Baixe novamente ou reexporte do dispositivo original.';

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
  String get progressCollectingData => 'Coletando dados…';

  @override
  String get progressEncrypting => 'Criptografando…';

  @override
  String get progressWritingArchive => 'Gravando arquivo…';

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
  String get noTagsAvailable =>
      'Ainda sem tags — crie uma em Ferramentas → Tags.';

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
  String get bucket => 'Bucket';

  @override
  String get prefix => 'Prefix';

  @override
  String get typeLabel => 'Tipo';

  @override
  String get folder => 'Pasta';

  @override
  String nSubitems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '1 item',
      zero: '0 itens',
    );
    return '$_temp0';
  }

  @override
  String get subitems => 'Itens';

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
  String get fileConflictTitle => 'O arquivo já existe';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" já existe em $targetDir. O que você deseja fazer?';
  }

  @override
  String get fileConflictSkip => 'Pular';

  @override
  String get fileConflictKeepBoth => 'Manter ambos';

  @override
  String get fileConflictReplace => 'Substituir';

  @override
  String get fileConflictApplyAll => 'Aplicar a todos os restantes';

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
  String get clearedAllHosts => 'Todos os hosts conhecidos foram limpos';

  @override
  String removedHost(String host) {
    return '$host removido';
  }

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
  String get addKey => 'Adicionar chave';

  @override
  String get addKeyMenuPaste => 'Colar PEM';

  @override
  String get filePickerUnavailable =>
      'Seletor de arquivos indisponível neste sistema';

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
  String get sshCertificate => 'Certificado';

  @override
  String get certImport => 'Importar certificado';

  @override
  String get certImportTooltip =>
      'Anexar um certificado OpenSSH assinado pela sua CA (o arquivo `-cert.pub` de `ssh-keygen -s …`). Use quando os servidores verificam por assinatura CA em vez de `authorized_keys`. Pule se seus servidores usam plain key auth.';

  @override
  String get certImportPickerTitle =>
      'Selecione o arquivo de certificado OpenSSH';

  @override
  String get certValidFrom => 'Válido a partir de';

  @override
  String get certValidTo => 'Válido até';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => 'Este certificado expira em breve.';

  @override
  String get certExpired => 'Expirado';

  @override
  String get certRemove => 'Remover certificado';

  @override
  String get certRemoveConfirmTitle => 'Remover certificado?';

  @override
  String get certRemoveConfirmBody =>
      'Após remover, a sessão volta a usar apenas a chave pública na conexão.';

  @override
  String errCertParse(String detail) {
    return 'Não foi possível parsear o certificado: $detail';
  }

  @override
  String get errCertPairFingerprintMismatch =>
      'Este certificado não está pareado com a chave selecionada.';

  @override
  String get pastePrivateKey => 'Colar chave privada (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Dados de chave PEM inválidos';

  @override
  String get selectFromKeyStore => 'Selecionar do armazenamento de chaves';

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
  String get passphrase => 'Passphrase';

  @override
  String get enterMasterPassword =>
      'Digite a senha mestra para acessar suas credenciais salvas.';

  @override
  String get wrongMasterPassword => 'Senha incorreta. Tente novamente.';

  @override
  String get currentPassword => 'Senha atual';

  @override
  String get forgotPassword => 'Esqueceu a senha?';

  @override
  String get credentialsReset => 'Todas as credenciais salvas foram excluídas';

  @override
  String get migrationToast => 'Armazenamento atualizado para o formato atual';

  @override
  String get dbCorruptTitle => 'Não é possível abrir o banco de dados';

  @override
  String get dbCorruptBody =>
      'Os dados no disco não podem ser abertos. Tente credenciais diferentes ou redefina para começar do zero.';

  @override
  String get dbCorruptWarning =>
      'A redefinição apagará permanentemente o banco criptografado e todos os arquivos relacionados à segurança. Nenhum dado será recuperado.';

  @override
  String get dbCorruptTryOther => 'Tentar outras credenciais';

  @override
  String get dbCorruptResetContinue => 'Redefinir e configurar';

  @override
  String get dbCorruptExit => 'Sair do LetsFLUTssh';

  @override
  String get tierResetTitle => 'Redefinição de segurança necessária';

  @override
  String get tierResetBody =>
      'Esta instalação contém dados de segurança de uma versão anterior do LetsFLUTssh que usava um modelo de níveis diferente. O novo modelo é uma mudança incompatível — não há caminho de migração automática. Para continuar, todas as sessões salvas, credenciais, chaves SSH e hosts conhecidos nesta instalação precisam ser apagados e o assistente de configuração inicial executado do zero.';

  @override
  String get tierResetWarning =>
      'Escolher «Redefinir e configurar novamente» excluirá permanentemente o banco de dados criptografado e todos os arquivos relacionados à segurança. Se precisar recuperar seus dados, saia do aplicativo agora e reinstale a versão anterior do LetsFLUTssh para exportá-los primeiro.';

  @override
  String get tierResetResetContinue => 'Redefinir e configurar novamente';

  @override
  String get tierResetExit => 'Sair do LetsFLUTssh';

  @override
  String get derivingKey => 'Derivando chave de criptografia...';

  @override
  String get securitySetupTitle => 'Configuração de segurança';

  @override
  String get keychainAvailable => 'Disponível';

  @override
  String get changeSecurityTierConfirm =>
      'Recriptografando o banco com o novo nível. Não pode ser interrompido — mantenha o app aberto até terminar.';

  @override
  String get changeSecurityTierDone => 'Nível de segurança alterado';

  @override
  String get changeSecurityTierFailed =>
      'Não foi possível alterar o nível de segurança';

  @override
  String get firstLaunchSecurityTitle => 'Armazenamento seguro ativado';

  @override
  String get firstLaunchSecurityBody =>
      'Seus dados são criptografados com uma chave guardada no keychain do sistema. O desbloqueio neste dispositivo é automático.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'Armazenamento baseado em hardware está disponível neste dispositivo. Atualize em Configurações → Segurança para vincular ao TPM / Secure Enclave.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'Armazenamento em hardware indisponível neste dispositivo.';

  @override
  String get firstLaunchSecurityOpenSettings => 'Abrir configurações';

  @override
  String get wizardReducedBanner =>
      'O keychain do sistema não está acessível nesta instalação. Escolha entre sem criptografia (T0) e uma senha mestra (Paranoid). Instale gnome-keyring, kwallet ou outro provedor libsecret para habilitar o nível Keychain.';

  @override
  String get tierBadgeCurrent => 'Atual';

  @override
  String get securitySetupEnable => 'Ativar';

  @override
  String get securitySetupApply => 'Aplicar';

  @override
  String get hwProbeLinuxDeviceMissing =>
      'Nenhum TPM detectado em /dev/tpmrm0. Ative fTPM / PTT na BIOS se o hardware suportar; caso contrário o nível de hardware não está disponível neste dispositivo.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools não está instalado. Execute `sudo apt install tpm2-tools` (ou o equivalente na sua distribuição) para ativar o nível de hardware.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'A verificação do nível de hardware falhou. Revise permissões de /dev/tpmrm0 e regras udev — detalhes nos logs.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'TPM 2.0 não detectado. Ative fTPM / PTT no firmware UEFI, ou aceite que o nível de hardware não está disponível neste dispositivo — o app recorre ao armazenamento de credenciais por software.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Nem o Microsoft Platform Crypto Provider nem o Software Key Storage Provider estão acessíveis — provavelmente um subsistema criptográfico do Windows corrompido ou uma Política de Grupo que bloqueia CNG. Verifique Visualizador de Eventos → Logs de Aplicações e Serviços.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'Este Mac não tem Secure Enclave (Mac Intel anterior a 2017 sem chip de segurança T1 / T2). O nível de hardware não está disponível; use a senha mestra.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'Nenhuma senha de login definida neste Mac. A criação de chave Secure Enclave requer uma — defina uma em Ajustes do Sistema → Touch ID e Senha (ou Senha de Login).';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'O Secure Enclave rejeitou a identidade de assinatura do aplicativo (-34018). Execute o script `macos-resign.sh` incluído no lançamento para dar a esta instalação uma identidade autoassinada estável e reinicie o aplicativo.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'Nenhum código do dispositivo definido. A criação de chave Secure Enclave requer um — defina em Ajustes → Face ID e Código (ou Touch ID e Código).';

  @override
  String get hwProbeIosSimulator =>
      'Executando no Simulador iOS, que não tem Secure Enclave. O nível de hardware só está disponível em dispositivos iOS físicos.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'Android 9 ou superior é necessário para o nível de hardware (StrongBox e invalidação por mudança de biometria não são confiáveis em versões anteriores).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'Este dispositivo não tem hardware biométrico (impressão digital ou rosto). Use a senha mestra.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'Nenhuma biometria registrada. Adicione uma impressão digital ou rosto em Ajustes → Segurança e privacidade → Biometria, e reative o nível de hardware.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'Hardware biométrico temporariamente inutilizável (bloqueio após falhas ou atualização de segurança pendente). Tente novamente em alguns minutos.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'O Keystore do Android recusou-se a respaldar uma chave de hardware nesta build do dispositivo (StrongBox indisponível, ROM personalizada ou falha no driver). O nível de hardware não está disponível.';

  @override
  String get securityRecheck => 'Verificar suporte aos níveis';

  @override
  String get securityRecheckUpdated =>
      'Suporte aos níveis atualizado — ver cartões acima';

  @override
  String get securityRecheckUnchanged => 'Suporte aos níveis inalterado';

  @override
  String get securityMacosEnableSecureTiers =>
      'Desbloquear níveis seguros neste Mac';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'Reassinar o app com um certificado pessoal para que o Keychain (T1) e o Secure Enclave (T2) sobrevivam às atualizações';

  @override
  String get securityMacosEnableSecureTiersPrompt =>
      'O macOS pedirá sua senha uma vez';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'Níveis seguros desbloqueados — T1 e T2 disponíveis';

  @override
  String get securityMacosEnableSecureTiersFailed =>
      'Falha ao desbloquear os níveis seguros';

  @override
  String get securityMacosOfferTitle => 'Ativar Keychain + Secure Enclave?';

  @override
  String get securityMacosOfferBody =>
      'O macOS vincula o armazenamento cifrado à identidade de assinatura do app. Sem certificado estável, o Keychain (T1) e o Secure Enclave (T2) negam acesso. Podemos criar um certificado pessoal autoassinado e reassinar o app — as atualizações continuarão funcionando e seus segredos sobreviverão entre versões. O macOS pedirá sua senha de login uma vez para confiar no novo certificado.';

  @override
  String get securityMacosOfferAccept => 'Ativar';

  @override
  String get securityMacosOfferDecline => 'Pular — escolher T0 ou Paranoid';

  @override
  String get securityMacosRemoveIdentity => 'Remover identidade de assinatura';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      'Exclui o certificado pessoal. Os dados T1 / T2 estão vinculados — mude para T0 ou Paranoid primeiro, depois remova.';

  @override
  String get securityMacosRemoveIdentityConfirmTitle =>
      'Remover identidade de assinatura?';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'Exclui o certificado pessoal do Keychain de login. Os segredos T1 / T2 armazenados ficarão ilegíveis. O assistente abrirá para migrar para T0 (texto simples) ou Paranoid (senha mestra) antes da remoção.';

  @override
  String get securityMacosRemoveIdentitySuccess =>
      'Identidade de assinatura removida';

  @override
  String get securityMacosRemoveIdentityFailed =>
      'Falha ao remover identidade de assinatura';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus está ativo mas nenhum secret-service daemon está rodando. Instale gnome-keyring (`sudo apt install gnome-keyring`) ou KWalletManager e certifique-se de que inicia no login.';

  @override
  String get keyringProbeFailed =>
      'O keychain do SO não está acessível neste dispositivo. Consulte os logs para o erro específico da plataforma; o app recorre à senha mestra.';

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
  String get pinToSession => 'Fixar nesta sessão';

  @override
  String get unpinFromSession => 'Desafixar desta sessão';

  @override
  String get pinnedSnippets => 'Fixados';

  @override
  String get allSnippets => 'Todos';

  @override
  String get commandCopied => 'Comando copiado';

  @override
  String get snippetTokensHint =>
      'Toca para inserir um marcador. Estes são substituídos em tempo de execução por valores da sessão ativa:';

  @override
  String get snippetCustomTokensHint =>
      'Qualquer outro com chaves duplas pede um valor quando o snippet executa.';

  @override
  String get snippetFillTitle => 'Preencher os parâmetros do snippet';

  @override
  String get snippetFillSubmit => 'Executar';

  @override
  String get broadcastSetDriver => 'Transmitir deste painel';

  @override
  String get broadcastClearDriver => 'Parar de transmitir deste painel';

  @override
  String get broadcastAddReceiver => 'Receber transmissão aqui';

  @override
  String get broadcastRemoveReceiver => 'Parar de receber transmissão';

  @override
  String get broadcastClearAll => 'Parar todas as transmissões';

  @override
  String get broadcastPasteTitle => 'Enviar colagem a todos os painéis?';

  @override
  String broadcastPasteBody(int chars, int count) {
    return 'Serão enviados $chars carateres a $count painéis adicionais.';
  }

  @override
  String get broadcastPasteSend => 'Enviar';

  @override
  String get portForwarding => 'Encaminhamento';

  @override
  String get portForwardingEmpty => 'Sem regras ainda';

  @override
  String get addForwardRule => 'Adicionar regra';

  @override
  String get editForwardRule => 'Editar regra';

  @override
  String get deleteForwardRule => 'Remover regra';

  @override
  String get localForward => 'Local';

  @override
  String get remoteForward => 'Remoto';

  @override
  String get dynamicForward => 'Dinâmico';

  @override
  String get forwardKind => 'Tipo';

  @override
  String get bindAddress => 'Endereço de bind';

  @override
  String get bindPort => 'Porta de bind';

  @override
  String get targetHost => 'Host destino';

  @override
  String get targetPort => 'Porta destino';

  @override
  String get forwardDescription => 'Descrição (opcional)';

  @override
  String get forwardEnabled => 'Ativada';

  @override
  String get forwardBindWildcardWarning =>
      'Bind em 0.0.0.0 publica o encaminhamento em todas as interfaces — normalmente queres 127.0.0.1.';

  @override
  String get forwardKindLocalHelp =>
      'Local: abre uma porta neste dispositivo que faz tunnel até um destino alcançável do servidor SSH. Útil para acessar bancos remotos ou UIs admin via localhost:bindPort.';

  @override
  String get forwardKindRemoteHelp =>
      'Remoto: pede ao servidor SSH para abrir uma porta que faz tunnel de volta a um destino alcançável deste dispositivo. Útil para partilhar um dev server local com um host remoto (servidor pode precisar GatewayPorts yes para binds não-loopback).';

  @override
  String get forwardKindDynamicHelp =>
      'Dinâmico: um proxy SOCKS5 neste dispositivo que encaminha cada conexão pelo servidor SSH. Aponte o seu navegador ou curl para localhost:bindPort para enviar todo o tráfego por SSH.';

  @override
  String get proxyJump => 'Ligar através de';

  @override
  String get proxyJumpNone => 'Ligação direta';

  @override
  String get proxyJumpSavedSession => 'Sessão guardada';

  @override
  String get proxyJumpCustom => 'Personalizado';

  @override
  String get proxyJumpCustomNote =>
      'Hops personalizados usam as credenciais desta sessão. Para auth de bastião diferente, guarda o bastião como sessão própria.';

  @override
  String viaSessionLabel(String label) {
    return 'via $label';
  }

  @override
  String get recordSession => 'Gravar sessão';

  @override
  String get recordSessionHelp =>
      'Guardar saída do terminal em disco para esta sessão. Cifrada em repouso quando uma password mestra ou chave de hardware protege a base de sessões; caso contrário, gravada em texto plano junto da base.';

  @override
  String get recordingsBrowserTitle => 'Gravações';

  @override
  String get recordingsBrowserSubtitle =>
      'Navegar, reproduzir e eliminar sessões gravadas';

  @override
  String get recordingsEmpty => 'Sem gravações ainda';

  @override
  String get playRecording => 'Reproduzir';

  @override
  String get deleteRecording => 'Eliminar';

  @override
  String get recordingPlaybackTitle => 'Reproduzir gravação';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

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
  String get presetFullImport => 'Importação completa';

  @override
  String get presetSelective => 'Seletivo';

  @override
  String get presetCustom => 'Personalizado';

  @override
  String get sessionSshKeys => 'Chaves de sessão (gerenciador)';

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
      'Tamanho do buffer de scrollback do terminal';

  @override
  String get keepAliveIntervalSubtitle =>
      'Segundos entre pacotes SSH keep-alive (0 = desligado)';

  @override
  String get sshTimeoutSubtitle => 'Tempo limite de conexão em segundos';

  @override
  String get defaultPortSubtitle => 'Porta padrão para novas sessões';

  @override
  String get parallelWorkersSubtitle =>
      'Workers paralelos para transferências SFTP';

  @override
  String get maxHistorySubtitle => 'Máximo de comandos salvos no histórico';

  @override
  String get calculateFolderSizesSubtitle =>
      'Mostrar tamanho total ao lado das pastas na barra lateral';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Consultar o GitHub por uma nova versão ao iniciar o app';

  @override
  String get threatColdDiskTheft => 'Furto de disco desligado';

  @override
  String get threatColdDiskTheftDescription =>
      'Máquina desligada com a unidade removida e lida em outro computador, ou uma cópia do arquivo do banco de dados tirada por alguém com acesso ao seu diretório pessoal.';

  @override
  String get threatKeyringFileTheft => 'Roubo do arquivo keyring / keychain';

  @override
  String get threatKeyringFileTheftDescription =>
      'Um invasor lê o arquivo do armazenamento de credenciais do sistema diretamente do disco (libsecret keyring, Credential Manager do Windows, login keychain do macOS) e recupera dele a chave do banco de dados empacotada. O nível de hardware bloqueia isso independentemente da senha porque o chip recusa exportar o material da chave; o nível de keychain precisa adicionalmente de uma senha, caso contrário o arquivo roubado é desempacotado apenas com a senha de login do SO.';

  @override
  String get modifierOnlyWithPassword => 'apenas com senha';

  @override
  String get threatBystanderUnlockedMachine =>
      'Curioso em máquina desbloqueada';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'Alguém se aproxima do seu computador já desbloqueado e abre o aplicativo enquanto você está longe.';

  @override
  String get threatLiveRamForensicsLocked => 'Dump de RAM em máquina bloqueada';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'Um invasor congela a RAM (ou a captura via DMA) e extrai o material de chave ainda residente a partir do instantâneo, mesmo com o aplicativo bloqueado.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'Comprometimento do kernel ou do chaveiro do sistema';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'Vulnerabilidade no kernel, exfiltração do chaveiro ou um backdoor no chip de segurança de hardware. O sistema operacional deixa de ser um recurso confiável e passa a ser o atacante.';

  @override
  String get threatOfflineBruteForce =>
      'Força bruta offline contra senha fraca';

  @override
  String get threatOfflineBruteForceDescription =>
      'Um invasor que possui uma cópia da chave encapsulada ou do blob selado testa todas as senhas no próprio ritmo, sem qualquer limitador de taxa.';

  @override
  String get legendProtects => 'Protegido';

  @override
  String get legendDoesNotProtect => 'Não protegido';

  @override
  String get colT0 => 'T0 Plaintext';

  @override
  String get colT1 => 'T1 Chaveiro';

  @override
  String get colT1Password => 'T1 + senha';

  @override
  String get colT1PasswordBiometric => 'T1 + senha + biometria';

  @override
  String get colT2Password => 'T2 + senha';

  @override
  String get colT2PasswordBiometric => 'T2 + senha + biometria';

  @override
  String get colParanoid => 'Paranoid';

  @override
  String get securityComparisonTableThreatColumn => 'Ameaça';

  @override
  String get compareAllTiers => 'Comparar todos os níveis';

  @override
  String get resetAllDataTitle => 'Redefinir todos os dados';

  @override
  String get resetAllDataSubtitle =>
      'Excluir todas as sessões, chaves, configurações e artefatos de segurança. Também limpa entradas do keychain e slots do cofre de hardware.';

  @override
  String get resetAllDataConfirmTitle => 'Redefinir todos os dados?';

  @override
  String get resetAllDataConfirmBody =>
      'Todas as sessões, chaves SSH, known hosts, snippets, tags, preferências e todos os artefatos de segurança (entradas do keychain, dados do cofre de hardware, sobreposição biométrica) serão excluídos permanentemente. Esta ação não pode ser desfeita.';

  @override
  String get resetAllDataConfirmAction => 'Redefinir tudo';

  @override
  String resetAllDataConfirmTypePrompt(String phrase) {
    return 'Digite $phrase abaixo para confirmar:';
  }

  @override
  String get resetAllDataInProgress => 'Redefinindo…';

  @override
  String get resetAllDataDone => 'Todos os dados redefinidos';

  @override
  String get resetAllDataFailed => 'Falha ao redefinir';

  @override
  String get recordingsTitle => 'Gravações';

  @override
  String get recordingsStorageUsedLabel => 'Em uso';

  @override
  String get recordingsCapLabel => 'Limite';

  @override
  String get recordingsCapHint =>
      'Limite rígido para a pasta recordings/. Ao exceder, a gravação mais antiga é apagada primeiro; a gravação em andamento nunca é tocada.';

  @override
  String get recordingsClearAllAction => 'Apagar todas as gravações';

  @override
  String get recordingsClearAllConfirmTitle => 'Apagar todas as gravações?';

  @override
  String get recordingsClearAllConfirmBody =>
      'Toda sessão gravada em <app>/recordings/ será apagada. A gravação em andamento (se houver) permanece. Esta ação não pode ser desfeita.';

  @override
  String recordingsClearAllResult(int count) {
    return '$count gravações removidas';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return 'Limite atualizado. $bytes liberados.';
  }

  @override
  String get recordingsCapChangedNoChange =>
      'Limite atualizado. Nada para remover.';

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
      'O bloqueio automático exige uma senha no nível ativo.';

  @override
  String get recommendedBadge => 'RECOMENDADO';

  @override
  String get tierHardwareSubtitleHonest =>
      'Avançado: chave vinculada ao hardware, sempre protegida por senha. Os dados são irrecuperáveis se o chip deste dispositivo for perdido ou substituído.';

  @override
  String get tierParanoidSubtitleHonest =>
      'Alternativa: senha mestra, sem confiança no OS. Protege contra o comprometimento do OS. Não melhora a proteção em tempo de execução em relação a T1/T2.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'Ameaças em runtime (malware do mesmo usuário, dump de memória de processo em execução) aparecem como ✗ em todos os níveis. Elas são tratadas por funcionalidades de mitigação separadas, aplicadas independentemente do nível escolhido.';

  @override
  String get currentTierBadge => 'ATUAL';

  @override
  String get paranoidAlternativeHeader => 'ALTERNATIVA';

  @override
  String get modifierPasswordLabel => 'Senha';

  @override
  String get modifierPasswordSubtitle =>
      'Barreira de segredo digitado antes do desbloqueio do cofre.';

  @override
  String get modifierPasswordRequired =>
      'Obrigatório — a camada Hardware é sempre protegida por senha.';

  @override
  String get modifierBiometricLabel => 'Atalho biométrico';

  @override
  String get modifierBiometricSubtitle =>
      'Liberar a senha de um slot do sistema protegido por biometria, em vez de digitá-la.';

  @override
  String get biometricRequiresPassword =>
      'Ative primeiro uma senha — a biometria é um atalho para digitá-la.';

  @override
  String get biometricRequiresActiveTier =>
      'Selecione este nível primeiro para ativar o desbloqueio biométrico';

  @override
  String get autoLockRequiresActiveTier =>
      'Selecione este nível primeiro para configurar o bloqueio automático';

  @override
  String get biometricForbiddenParanoid =>
      'O nível Paranoid não permite biometria por design.';

  @override
  String get fprintdNotAvailable =>
      'fprintd não instalado ou nenhuma impressão digital registrada.';

  @override
  String get t2RequiresPasswordTitle =>
      'Defina uma senha mestre para a camada Hardware';

  @override
  String get t2RequiresPasswordBody =>
      'A camada Hardware precisa de uma senha como modifier. O biométrico é um shortcut opcional por cima.';

  @override
  String get t2MigrationPromptTitle => 'A camada Hardware precisa de senha';

  @override
  String get t2MigrationPromptBody =>
      'Instalações Hardware existentes sem senha precisam definir uma agora para continuar.';

  @override
  String get t2MigrationContinue => 'Continuar';

  @override
  String get t2MigrationSetPasswordTitle =>
      'Defina uma senha para manter a camada Hardware';

  @override
  String get t2MigrationSetPasswordBody =>
      'Digite uma nova master password. A DB key já sealed dentro do módulo hardware é re-sealed sob esta senha — sessões e keys ficam intactas.';

  @override
  String get t2MigrationWipeAndRestart => 'Wipe e começar do zero';

  @override
  String get t2MigrationResealFailed =>
      'Re-seal da camada Hardware falhou — escolha outra senha ou wipe para começar do zero.';

  @override
  String get biometricOverlayEnable =>
      'Ativar shortcut biométrico na camada Hardware';

  @override
  String get biometricOverlayEnableSubtitle =>
      'Libera sua senha a partir de um slot do OS protegido por biométrico.';

  @override
  String get biometricOverlayUnavailable =>
      'O overlay biométrico ainda não está disponível nesta plataforma.';

  @override
  String get biometricOverlayRequiresPassword =>
      'Defina primeiro a senha da camada Hardware.';

  @override
  String get t2UnlockTitle => 'Desbloquear com sua senha mestre';

  @override
  String get t2UnlockSubtitle =>
      'A chave hardware-bound é protegida pela sua senha.';

  @override
  String get t2UnlockUseBiometricButton => 'Usar biométrico';

  @override
  String get t2PasswordChanged => 'Senha da camada Hardware atualizada.';

  @override
  String get paranoidMasterPasswordNote =>
      'Uma senha longa é fortemente recomendada — o Argon2id apenas torna o ataque por força bruta mais lento, não o impede.';

  @override
  String get plaintextWarningTitle => 'Texto simples: sem criptografia';

  @override
  String get plaintextWarningBody =>
      'Sessões, chaves e known hosts serão armazenados sem criptografia. Qualquer pessoa com acesso ao sistema de arquivos deste computador poderá lê-los.';

  @override
  String get plaintextAcknowledge =>
      'Entendo que meus dados não serão criptografados';

  @override
  String get plaintextAcknowledgeRequired =>
      'Confirme que entendeu antes de continuar.';

  @override
  String get passwordLabel => 'Senha';

  @override
  String get masterPasswordLabel => 'Senha mestra';

  @override
  String get globalErrorTitle => 'Erro inesperado';

  @override
  String get globalErrorBody =>
      'Ocorreu um erro inesperado. O app continuará funcionando.';

  @override
  String get globalErrorLogSavedNote =>
      'Todos os detalhes foram gravados no arquivo de log.';

  @override
  String get globalErrorLogDisabledNote =>
      'Ative o log nas Configurações para salvar os detalhes do erro.';

  @override
  String globalErrorTechnicalLine(String detail) {
    return 'Erro: $detail';
  }

  @override
  String get globalErrorEnableLoggingButton => 'Ativar log';

  @override
  String get globalErrorLoggingEnabledToast =>
      'Log ativado — os erros serão gravados no arquivo de log';

  @override
  String get fatalErrorQuitButton => 'Sair';

  @override
  String get fatalErrorWipeButton => 'Apagar todos os dados';

  @override
  String get fatalErrorWipingButton => 'Apagando…';

  @override
  String get fatalErrorWipeExplanation =>
      'Apagar remove todos os arquivos do app (config, banco de dados, blobs do vault, logs); a próxima inicialização começa de uma instalação limpa. Não pode ser desfeito.';

  @override
  String get fatalErrorWipeConfirmTitle => 'Apagar todos os dados?';

  @override
  String get fatalErrorWipeConfirmBody =>
      'Isto apaga permanentemente todos os arquivos de config, banco de dados e vault. O app reiniciará de uma instalação vazia. Continuar?';

  @override
  String get fatalErrorWipeConfirmAction => 'Apagar tudo';

  @override
  String get unencryptedArchiveWarning =>
      'Este arquivo não é protegido por senha. Qualquer um com o arquivo pode ler o conteúdo.';

  @override
  String get clipboardCopyFailed =>
      'Falha ao copiar para a área de transferência.';

  @override
  String get nonAsciiHostnameWarning =>
      'O nome de host contém caracteres não ASCII — verifique cada caractere contra o que você digitou. Codepoints visualmente parecidos (cirílico / grego) podem falsificar um domínio latino.';

  @override
  String get playbackPause => 'Pausar';

  @override
  String get recordingPlayLocked =>
      'Desbloqueie o app para reproduzir esta gravação criptografada.';

  @override
  String get recordToggleStart => 'Iniciar gravação';

  @override
  String get recordToggleStop => 'Parar gravação';

  @override
  String get foregroundServiceTitle => 'SSH ativo';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conexões ativas',
      one: '1 conexão ativa',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => 'Tipo de sessão';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => 'Usuário';

  @override
  String get webDavAuthMethod => 'Método de auth';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer token';

  @override
  String get trustedCert => 'Certificado confiável (PEM)';

  @override
  String get trustedCertHint => '-----BEGIN CERTIFICATE-----';

  @override
  String get trustedCertHelp =>
      'Cola o certificado do servidor (um ou mais blocos PEM). Adicionado como CA raiz adicional apenas para esta sessão — não afeta outras apps. Deixa vazio para usar o trust store do sistema.';

  @override
  String get acceptAnyCert => 'Aceitar qualquer certificado';

  @override
  String get acceptAnyCertHelp =>
      'Ignora todas as verificações de certificado e hostname nos handshakes TLS desta sessão. Saída de emergência quando nem o trust store do sistema nem um certificado fixado servem.';

  @override
  String get acceptAnyCertWarn =>
      'Vulnerável a ataques MITM — qualquer pessoa na rede pode se passar pelo servidor. Use apenas em redes privadas de confiança.';

  @override
  String get webDavCopyUrl => 'Copiar URL WebDAV';

  @override
  String get webDavOpenInBrowser => 'Abrir no navegador';

  @override
  String get errWebDavAuthFailed => 'Falha de autenticação WebDAV';

  @override
  String get errWebDavNotFound => 'Caminho não encontrado';

  @override
  String get errWebDavConflict => 'Operação conflita com o estado atual';

  @override
  String errWebDavGeneric(String detail) {
    return 'Servidor WebDAV rejeitou a requisição: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'Base URL do WebDAV é obrigatória';

  @override
  String get errWebDavBaseUrlInvalid =>
      'Base URL precisa ser http:// ou https://';

  @override
  String get sessionKindS3 => 'S3';

  @override
  String get s3AccessKeyId => 'Access key ID';

  @override
  String get s3SecretKey => 'Secret access key';

  @override
  String get s3Region => 'Region';

  @override
  String get s3RegionHint => 'us-east-1, eu-west-2, auto';

  @override
  String get s3Endpoint => 'Endpoint';

  @override
  String get s3EndpointHint =>
      'Vazio para AWS, ou preenche para MinIO / R2 / Spaces';

  @override
  String get s3PathStyle => 'Endereçamento path-style';

  @override
  String get s3PathStyleHint => 'Necessário para MinIO; deixa off para AWS';

  @override
  String get s3DefaultBucket => 'Bucket padrão';

  @override
  String get s3DefaultPrefix => 'Prefix padrão';

  @override
  String get s3GeneratePresignedUrl => 'Gerar presigned URL';

  @override
  String get s3PresignedUrlExpiry => 'Expira em';

  @override
  String get s3CopyUri => 'Copiar URI s3://bucket/key';

  @override
  String get s3PresignedUrlExpiry15min => '15 minutos';

  @override
  String get s3PresignedUrlExpiry1hour => '1 hora';

  @override
  String get s3PresignedUrlExpiry4hour => '4 horas';

  @override
  String get s3PresignedUrlExpiry24hour => '24 horas';

  @override
  String get s3PresignedUrlExpiry7day => '7 dias';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (confere access key + secret)';

  @override
  String get errS3NoSuchBucket => 'Bucket não existe ou está inacessível';

  @override
  String get errS3RegionMismatch =>
      'Bucket está em uma region diferente da configurada';

  @override
  String errS3Generic(String detail) {
    return 'Servidor S3 rejeitou a requisição: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'Ativar sync por WebDAV';

  @override
  String get syncPassphrase => 'Passphrase de sync';

  @override
  String get syncPassphraseHint =>
      'Criptografa o arquivo de sync. Deve ser diferente da master password.';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Passphrase de sync não pode ser igual à master password.';

  @override
  String get syncRemotePath => 'Caminho remoto';

  @override
  String get syncRemotePathHint =>
      'Caminho sob a base URL do WebDAV — padrão letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return 'Último push: $when';
  }

  @override
  String syncLastPulled(String when) {
    return 'Último pull: $when';
  }

  @override
  String get syncNeverRun => 'Nunca';

  @override
  String get syncUpToDate => 'Sync em dia';

  @override
  String syncPushedBytes(String bytes) {
    return 'Push de $bytes';
  }

  @override
  String syncPullApplied(int count) {
    return 'Aplicadas $count mudanças do remote';
  }

  @override
  String get errSyncDisabled => 'Sync desativado';

  @override
  String get errSyncEtagMismatch => 'Remote mudou — pull primeiro, depois push';

  @override
  String get errSyncUnauthorized => 'Autenticação WebDAV falhou';

  @override
  String errSyncNetwork(String detail) {
    return 'Erro de rede: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion =>
      'Arquivo de sync remoto precisa de um build mais recente';

  @override
  String get hardwareKey => 'Hardware key';

  @override
  String get hardwareKeyTapPrompt => 'Toque seu hardware key';

  @override
  String get hardwareKeyPin => 'PIN do hardware key';

  @override
  String get hardwareKeyTimeout => 'Hardware key não respondeu';

  @override
  String get hardwareKeyNotFound => 'Nenhum hardware key encontrado';

  @override
  String get hardwareKeyUnsupported =>
      'Acesso direto a hardware key não está disponível nesta plataforma';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'Requer entitlement do Apple Developer Program; use ssh-agent no macOS';

  @override
  String get skKeyRequiresDevice =>
      'Esta chave SSH precisa de um hardware key — toque para autenticar';

  @override
  String get errSkWrongPin => 'PIN incorreto';

  @override
  String get hardwareKeyImport => 'Importar hardware key (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => 'Prompt do hardware key cancelado';

  @override
  String get agentEndpointSectionTitle =>
      'Integração com clientes SSH externos';

  @override
  String get agentEndpointToggleTitle =>
      'Expor hardware keys aos clientes SSH do sistema';

  @override
  String get agentEndpointToggleSubtitle =>
      'Permite que git, ssh e plugins de IDE neste dispositivo usem suas keys FIDO2 / smart-card / TPM.';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'Copiar comando export';

  @override
  String get agentEndpointCopyPipeName => 'Copiar nome do pipe';

  @override
  String get agentEndpointSignatureRequestTitle => 'Solicitação de assinatura';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester quer assinar com $keyLabel';
  }

  @override
  String get agentEndpointRequesterUnknown => 'Um cliente SSH externo';

  @override
  String get agentEndpointAuthorizeOnce => 'Autorizar uma vez';

  @override
  String get agentEndpointAuthorizeAlways => 'Autorizar e lembrar';

  @override
  String get agentEndpointDeny => 'Recusar';

  @override
  String get agentEndpointStatusRunning => 'Em execução';

  @override
  String get agentEndpointStatusStopped => 'Parado';

  @override
  String get agentEndpointStatusUnsupported => 'Indisponível nesta plataforma';

  @override
  String get agentEndpointRefusedAddIdentity =>
      'Recusado: clientes externos não podem adicionar keys.';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'Não foi possível iniciar o ssh-agent endpoint: $detail';
  }

  @override
  String get pkcs11AddTitle => 'Adicionar chave de smartcard / token';

  @override
  String get pkcs11ModuleLabel => 'Módulo PKCS#11';

  @override
  String get pkcs11ModuleAutoDetected => 'Detectado automaticamente';

  @override
  String get pkcs11ModuleCustom => 'Módulo personalizado...';

  @override
  String get pkcs11ModulePickerTitle => 'Escolher biblioteca PKCS#11';

  @override
  String get pkcs11NoModuleFound =>
      'Nenhum módulo PKCS#11 encontrado. Instale OpenSC ou escolha uma biblioteca do fornecedor.';

  @override
  String get pkcs11InitializeFailed => 'O módulo PKCS#11 não inicializou.';

  @override
  String get pkcs11NoTokenPresent => 'Nenhum token em nenhum leitor.';

  @override
  String pkcs11TokenLabel(String label) {
    return 'Token: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return 'Número de série: $serial';
  }

  @override
  String get pkcs11LoginRequired => 'O token requer login.';

  @override
  String pkcs11PinPrompt(String token) {
    return 'PIN para $token';
  }

  @override
  String get pkcs11PinPad => 'Confirme no PIN-pad do token.';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'PIN incorreto. Restam $remaining tentativas.';
  }

  @override
  String get pkcs11PinLocked =>
      'PIN do token bloqueado. Desbloqueie com o PUK.';

  @override
  String get pkcs11NoSignableKeys =>
      'O token não tem chaves utilizáveis por SSH (RSA, ECDSA, Ed25519).';

  @override
  String get pkcs11GostUnsupported => 'Chaves GOST não funcionam com SSH.';

  @override
  String pkcs11TokenUnplugged(String label) {
    return 'O token \"$label\" não está conectado.';
  }

  @override
  String get pkcs11UriRebindFailed =>
      'Token salvo não encontrado. Reconecte e tente novamente.';

  @override
  String pkcs11SignFailed(String reason) {
    return 'Falha na assinatura: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      'Smartcards / tokens PKCS#11 não estão disponíveis nesta plataforma.';

  @override
  String get pkcs11Badge => 'Smartcard / token';

  @override
  String pkcs11InfoModulePath(String path) {
    return 'Módulo: $path';
  }

  @override
  String pkcs11InfoTokenSerial(String serial) {
    return 'Serial do token: $serial';
  }

  @override
  String pkcs11InfoObjectLabel(String label) {
    return 'Objeto: $label';
  }

  @override
  String get pkcs11WizardStepModule => 'Selecione o módulo PKCS#11';

  @override
  String get pkcs11WizardStepToken => 'Selecione o token';

  @override
  String get pkcs11WizardStepKey => 'Selecione a chave';

  @override
  String get pkcs11WizardStepPin => 'Digite o PIN';

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
  String get pkcs11SaveCta => 'Importar chave';

  @override
  String get pkcs11SaveInProgress => 'Lendo chave pública do token...';

  @override
  String get pkcs11SaveSuccess => 'Chave do smartcard adicionada.';

  @override
  String get pkcs11ScanInProgress => 'Procurando módulos PKCS#11...';

  @override
  String get pkcs11LoadingTokens => 'Carregando tokens...';

  @override
  String get pkcs11LoadingKeys => 'Carregando chaves...';

  @override
  String get pkcs11ModuleStatusReady => 'Módulo carregado.';

  @override
  String get pkcs11ModuleStatusNoToken => 'Nenhum token presente.';

  @override
  String get pkcs11ModuleStatusFailed => 'Falha ao carregar o módulo.';

  @override
  String get pkcs11PinPadHint => '(PIN pad no dispositivo)';

  @override
  String get pkcs11WizardBack => 'Voltar';

  @override
  String get pkcs11WizardNext => 'Próximo';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => 'Adicionar chave hardware';

  @override
  String get sshKeyHardwareBoundExplainer =>
      'A chave privada vive no hardware seguro do dispositivo e não pode ser exportada.';

  @override
  String get sshKeyEnclaveDeviceBound => 'Esta chave só funciona neste Mac.';

  @override
  String get sshKeyEnclaveDeviceBoundIos =>
      'Esta chave só funciona neste iPhone.';

  @override
  String get sshKeyHelloDeviceBound => 'Esta chave só funciona neste PC.';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'Exigir Touch ID / Face ID';

  @override
  String get sshKeyEnclavePasscodeFallback =>
      'Permitir o passcode do dispositivo como fallback';

  @override
  String get sshKeyHelloPinRequired =>
      'Exigir Windows Hello (PIN, digital ou rosto)';

  @override
  String get sshKeyHardwareUnavailableTitle => 'Chaves hardware indisponíveis';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'O app precisa estar assinado para usar o Secure Enclave.';

  @override
  String get sshKeyHardwareUnavailableHello =>
      'Windows Hello não está configurado neste PC.';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'TPM não detectado — apenas software-backed.';

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
  String get sshKeyGenerateCta => 'Gerar';

  @override
  String get sshKeyGenerateInProgress => 'Gerando chave no hardware seguro...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Code-signing necessário — veja USER_GUIDE.md → Hardware-bound keys.';

  @override
  String get sshKeySignInProgress => 'Assinando com hardware seguro...';

  @override
  String get sshKeyPublicCopy => 'Copiar chave pública';

  @override
  String get sshKeyAuthorizedKeysHint =>
      'Adicione esta linha em ~/.ssh/authorized_keys no servidor.';

  @override
  String get sshKeyEnclaveWizardTitle => 'Chave SSH do Secure Enclave';

  @override
  String get sshKeyEnclaveWizardLabelHint => 'Nome da chave';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'Chave SSH do Windows Hello';

  @override
  String get helloWizardLabelHint => 'Etiqueta da chave';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'Autenticar com o Windows Hello';

  @override
  String get helloPromptDescription =>
      'PIN, impressão digital ou rosto — o Windows Hello assina este desafio SSH.';

  @override
  String get helloSoftwareGatedWarning =>
      'Este dispositivo não tem TPM. A chave fica no armazenamento de usuário; o Windows Hello ainda exige cada assinatura.';

  @override
  String get helloP384NotSupported =>
      'O firmware do TPM não suporta P-384. Escolha P-256 ou RSA-2048.';

  @override
  String get helloConfigureFirst =>
      'Configure o Windows Hello primeiro em Configurações -> Opções de entrada.';

  @override
  String get tpmSshTitle => 'Gerar chave SSH adossada ao TPM';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (recomendado)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported =>
      'Algorithm não suportado pelo firmware deste TPM.';

  @override
  String get tpmSshPinProtect => 'Proteger com PIN';

  @override
  String get tpmSshPinLockoutWarning =>
      'TPM trava a chave após várias tentativas de PIN erradas.';

  @override
  String get tpmSshPinMismatch => 'Os PINs não conferem.';

  @override
  String get tpmSshStorageBlob => 'Armazenar chave envelopada nos dados do app';

  @override
  String get tpmSshStorageHandle => 'Persistir em slot de memória do TPM';

  @override
  String get tpmSshStorageHandleHelp =>
      'Assinatura mais rápida. Consome um dos slots persistentes do TPM.';

  @override
  String get tpmSshLabel => 'Rótulo da chave';

  @override
  String get tpmSshImportTitle => 'Importar chave SSH protegida por TPM';

  @override
  String get tpmSshImportFormat => 'Arquivo TPM 2.0 (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return 'PIN do TPM para $label';
  }

  @override
  String get tpmSshPinIncorrect => 'PIN incorreto.';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM em cooldown de lockout. Aguarde $duration e tente de novo.';
  }

  @override
  String get tpmSshGenerating => 'Gerando chave no TPM...';

  @override
  String get tpmSshSigning => 'Assinando com TPM...';

  @override
  String get tpmSshUnavailable => 'Nenhum TPM detectado neste dispositivo.';

  @override
  String get tpmSshUnavailableFwDisabled => 'TPM desativado no firmware.';

  @override
  String get tpmSshUnavailableNoPermission =>
      'O app não consegue acessar o TPM. Adicione o usuário ao grupo `tss`.';

  @override
  String tpmSshHandleInUse(String handle) {
    return 'O slot persistente $handle já está em uso.';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      'Esta chave assina SEM prompt de Hello / PIN — qualquer pessoa com acesso ao desktop enquanto você está logado pode usá-la.';

  @override
  String get keystoreWizardTitle => 'Android Hardware Key';

  @override
  String get keystoreBadge => 'Android Keystore';

  @override
  String get keystoreKeyAndroidLabel => 'Android Keystore (hardware-bound)';

  @override
  String get keystoreKeyStrongBoxLabel => 'StrongBox HSM';

  @override
  String get keystoreKeyTeeLabel => 'TEE (hardware-backed)';

  @override
  String get keystoreKeyGenerating => 'Gerando chave hardware-bound...';

  @override
  String get keystoreKeyAuthPrompt => 'Autentique para usar a chave SSH';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      'Chave destruída: nova biometria foi registrada. Registre novamente a chave pública nos seus servidores.';

  @override
  String get keystoreKeyStrongBoxUnavailable =>
      'StrongBox HSM indisponível neste dispositivo';

  @override
  String get keystoreKeyUserAuthRequired =>
      'Exigir biometria / desbloqueio do dispositivo a cada assinatura';

  @override
  String get keystoreKeyExportDisabled =>
      'Chaves hardware-bound não podem ser exportadas';

  @override
  String get keystoreKeyDeleteWarning =>
      'Apagar esta chave remove-a do armazenamento de hardware. Os servidores vão rejeitá-la até você registrar uma nova.';

  @override
  String get keystoreKeyBiometricNotEnrolled =>
      'Configure biometria ou PIN do dispositivo primeiro';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (StrongBox-eligible)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+, só TEE)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (compatibilidade máxima)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM indisponível';

  @override
  String get keystoreStrongBoxFallbackBody =>
      'Teu device não expõe o StrongBox HSM. Criar uma chave adossada ao TEE em vez disso? Continua hardware-backed, só sem o isolamento do StrongBox.';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'Usar TEE';

  @override
  String get keystoreStrongBoxFallbackCancel => 'Cancelar';

  @override
  String get fido2BrokerSectionTitle => 'Chaves de segurança em hardware';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / security key';

  @override
  String get fido2BrokerMacosLabel => 'Diálogo do sistema de security key';

  @override
  String get fido2BrokerIosLabel => 'Security key do sistema (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel =>
      'Security key do sistema (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => 'USB HID direto (CTAP2)';

  @override
  String get fido2BrokerTransportNone => 'Indisponível nesta plataforma';

  @override
  String get fido2BrokerPreferDirectHidTitle =>
      'Preferir USB HID direto ao diálogo do sistema';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return 'Avançado: ignorar o $brokerLabel em plataformas onde os dois caminhos funcionam. O HID direto expõe mais features do authenticator mas exige permissão por app.';
  }

  @override
  String get sshIntegrationSection => 'Integração SSH';

  @override
  String get fido2BrokerNoTransportSubtitle =>
      'O suporte a chaves de hardware não está disponível neste dispositivo.';

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return 'Apenas $transport está disponível neste dispositivo; o toggle está desativado.';
  }

  @override
  String get hardwareKeyStubBadge => 'Stub importado';

  @override
  String get hardwareKeyStubSubtitle =>
      'Estava em outro dispositivo — regenere aqui para usar';

  @override
  String get hardwareKeyStubRegenerateAction => 'Regenerar aqui';

  @override
  String get hardwareKeyStubRemoveAction => 'Remover stub';

  @override
  String get hardwareKeyStubPickerTooltip =>
      'Regenere esta chave neste dispositivo antes de usar';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return 'Localize o módulo PKCS#11 para o token \"$token\"';
  }

  @override
  String get arrowLeft => 'Seta esquerda';

  @override
  String get arrowUp => 'Seta cima';

  @override
  String get arrowDown => 'Seta baixo';

  @override
  String get arrowRight => 'Seta direita';

  @override
  String get copyMode => 'Modo de cópia';

  @override
  String get exitCopyMode => 'Sair do modo de cópia';

  @override
  String importedGeneric(String items) {
    return 'Importado: $items';
  }
}
