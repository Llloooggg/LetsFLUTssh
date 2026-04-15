// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class SKo extends S {
  SKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => '확인';

  @override
  String get cancel => '취소';

  @override
  String get close => '닫기';

  @override
  String get delete => '삭제';

  @override
  String get save => '저장';

  @override
  String get connect => '연결';

  @override
  String get retry => '재시도';

  @override
  String get import_ => '가져오기';

  @override
  String get export_ => '내보내기';

  @override
  String get rename => '이름 변경';

  @override
  String get create => '생성';

  @override
  String get back => '뒤로';

  @override
  String get copy => '복사';

  @override
  String get paste => '붙여넣기';

  @override
  String get select => '선택';

  @override
  String get required => '필수';

  @override
  String get settings => '설정';

  @override
  String get appSettings => '앱 설정';

  @override
  String get yes => '예';

  @override
  String get no => '아니요';

  @override
  String get importWhatToImport => '가져올 내용:';

  @override
  String get enterMasterPasswordPrompt => '마스터 비밀번호 입력:';

  @override
  String get nextStep => '다음';

  @override
  String get includeCredentials => '비밀번호 및 SSH 키 포함';

  @override
  String get includePasswords => '세션 비밀번호';

  @override
  String get embeddedKeys => '내장 키';

  @override
  String get managerKeys => '관리자의 키';

  @override
  String get managerKeysMayBeLarge => '관리자 키는 QR 크기 제한을 초과할 수 있습니다';

  @override
  String get qrPasswordWarning => '비밀번호가 QR 코드에서 암호화되지 않습니다. 스캔한 누구나 볼 수 있습니다.';

  @override
  String get sshKeysMayBeLarge => '키가 QR 크기 제한을 초과할 수 있습니다';

  @override
  String exportTotalSize(String size) {
    return '총 크기: $size';
  }

  @override
  String get qrCredentialsWarning => '비밀번호와 SSH 키가 QR 코드에 표시됩니다';

  @override
  String get qrCredentialsTooLarge => '인증 정보로 QR 코드가 너무 큽니다';

  @override
  String get terminal => '터미널';

  @override
  String get files => '파일';

  @override
  String get transfer => '전송';

  @override
  String get open => '열기';

  @override
  String get search => '검색...';

  @override
  String get filter => '필터...';

  @override
  String get merge => '병합';

  @override
  String get replace => '교체';

  @override
  String get reconnect => '재연결';

  @override
  String get updateAvailable => '업데이트 가능';

  @override
  String updateVersionAvailable(String version, String current) {
    return '버전 $version을 사용할 수 있습니다 (현재: v$current).';
  }

  @override
  String get releaseNotes => '릴리스 노트:';

  @override
  String get skipThisVersion => '이 버전 건너뛰기';

  @override
  String get unskip => '건너뛰기 취소';

  @override
  String get downloadAndInstall => '다운로드 및 설치';

  @override
  String get openInBrowser => '브라우저에서 열기';

  @override
  String get couldNotOpenBrowser => '브라우저를 열 수 없습니다 — URL이 클립보드에 복사되었습니다';

  @override
  String get checkForUpdates => '업데이트 확인';

  @override
  String get checkForUpdatesOnStartup => '시작 시 업데이트 확인';

  @override
  String get checking => '확인 중...';

  @override
  String get youreUpToDate => '최신 버전입니다';

  @override
  String get updateCheckFailed => '업데이트 확인 실패';

  @override
  String get unknownError => '알 수 없는 오류';

  @override
  String downloadingPercent(int percent) {
    return '다운로드 중... $percent%';
  }

  @override
  String get downloadComplete => '다운로드 완료';

  @override
  String get installNow => '지금 설치';

  @override
  String get couldNotOpenInstaller => '설치 프로그램을 열 수 없습니다';

  @override
  String versionAvailable(String version) {
    return '버전 $version 사용 가능';
  }

  @override
  String currentVersion(String version) {
    return '현재: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'SSH 키 수신: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return 'QR을 통해 $count개 세션 가져옴';
  }

  @override
  String importedSessions(int count) {
    return '$count개 세션 가져옴';
  }

  @override
  String importFailed(String error) {
    return '가져오기 실패: $error';
  }

  @override
  String get sessions => '세션';

  @override
  String get emptyFolders => '빈 폴더';

  @override
  String get sessionsHeader => '세션';

  @override
  String get savedSessions => '저장된 세션';

  @override
  String get activeConnections => '활성 연결';

  @override
  String get openTabs => '열린 탭';

  @override
  String get noSavedSessions => '저장된 세션이 없습니다';

  @override
  String get addSession => '세션 추가';

  @override
  String get noSessions => '세션 없음';

  @override
  String get noSessionsToExport => '내보낼 세션이 없습니다';

  @override
  String nSelectedCount(int count) {
    return '$count개 선택됨';
  }

  @override
  String get selectAll => '전체 선택';

  @override
  String get deselectAll => '전체 해제';

  @override
  String get moveTo => '이동...';

  @override
  String get moveToFolder => '폴더로 이동';

  @override
  String get rootFolder => '/ (루트)';

  @override
  String get newFolder => '새 폴더';

  @override
  String get newConnection => '새 연결';

  @override
  String get editConnection => '연결 편집';

  @override
  String get duplicate => '복제';

  @override
  String get deleteSession => '세션 삭제';

  @override
  String get renameFolder => '폴더 이름 변경';

  @override
  String get deleteFolder => '폴더 삭제';

  @override
  String get deleteSelected => '선택 항목 삭제';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return '$parts을(를) 삭제하시겠습니까?\n\n이 작업은 되돌릴 수 없습니다.';
  }

  @override
  String nSessions(int count) {
    return '$count개 세션';
  }

  @override
  String nFolders(int count) {
    return '$count개 폴더';
  }

  @override
  String deleteFolderConfirm(String name) {
    return '폴더 \"$name\"을(를) 삭제하시겠습니까?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return '내부의 $count개 세션도 함께 삭제됩니다.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return '\"$name\"을(를) 삭제하시겠습니까?';
  }

  @override
  String get connection => '연결';

  @override
  String get auth => '인증';

  @override
  String get options => '옵션';

  @override
  String get sessionName => '세션 이름';

  @override
  String get hintMyServer => '내 서버';

  @override
  String get hostRequired => '호스트 *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => '포트';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => '사용자 이름 *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => '비밀번호';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => '키 암호';

  @override
  String get hintOptional => '선택 사항';

  @override
  String get hidePemText => 'PEM 텍스트 숨기기';

  @override
  String get pastePemKeyText => 'PEM 키 텍스트 붙여넣기';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => '추가 옵션이 아직 없습니다';

  @override
  String get saveAndConnect => '저장 및 연결';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst => '먼저 키 파일 또는 PEM 텍스트를 제공하세요';

  @override
  String get keyTextPem => '키 텍스트 (PEM)';

  @override
  String get selectKeyFile => '키 파일 선택';

  @override
  String get clearKeyFile => '키 파일 지우기';

  @override
  String get authOrDivider => '또는';

  @override
  String get providePasswordOrKey => '비밀번호 또는 SSH 키를 제공하세요';

  @override
  String get quickConnect => '빠른 연결';

  @override
  String get scanQrCode => 'QR 코드 스캔';

  @override
  String get qrGenerationFailed => 'QR 생성 실패';

  @override
  String get scanWithCameraApp => 'LetsFLUTssh가 설치된 기기의\n카메라 앱으로 스캔하세요.';

  @override
  String get noPasswordsInQr => '이 QR 코드에는 비밀번호나 키가 포함되어 있지 않습니다';

  @override
  String get copyLink => '링크 복사';

  @override
  String get linkCopied => '링크가 클립보드에 복사되었습니다';

  @override
  String get hostKeyChanged => '호스트 키가 변경되었습니다!';

  @override
  String get unknownHost => '알 수 없는 호스트';

  @override
  String get hostKeyChangedWarning =>
      '경고: 이 서버의 호스트 키가 변경되었습니다. 이는 중간자 공격을 나타낼 수 있으며, 서버가 재설치되었을 수도 있습니다.';

  @override
  String get unknownHostMessage => '이 호스트의 신뢰성을 확인할 수 없습니다. 연결을 계속하시겠습니까?';

  @override
  String get host => '호스트';

  @override
  String get keyType => '키 유형';

  @override
  String get fingerprint => '지문';

  @override
  String get fingerprintCopied => '지문이 복사되었습니다';

  @override
  String get copyFingerprint => '지문 복사';

  @override
  String get acceptAnyway => '그래도 수락';

  @override
  String get accept => '수락';

  @override
  String get importData => '데이터 가져오기';

  @override
  String get masterPassword => '마스터 비밀번호';

  @override
  String get confirmPassword => '비밀번호 확인';

  @override
  String get importModeMergeDescription => '새 세션 추가, 기존 세션 유지';

  @override
  String get importModeReplaceDescription => '모든 세션을 가져온 세션으로 교체';

  @override
  String errorPrefix(String error) {
    return '오류: $error';
  }

  @override
  String get folderName => '폴더 이름';

  @override
  String get newName => '새 이름';

  @override
  String deleteItems(String names) {
    return '$names을(를) 삭제하시겠습니까?';
  }

  @override
  String deleteNItems(int count) {
    return '$count개 항목 삭제';
  }

  @override
  String deletedItem(String name) {
    return '$name 삭제됨';
  }

  @override
  String deletedNItems(int count) {
    return '$count개 항목 삭제됨';
  }

  @override
  String failedToCreateFolder(String error) {
    return '폴더 생성 실패: $error';
  }

  @override
  String failedToRename(String error) {
    return '이름 변경 실패: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return '$name 삭제 실패: $error';
  }

  @override
  String get editPath => '경로 편집';

  @override
  String get root => '루트';

  @override
  String get controllersNotInitialized => '컨트롤러가 초기화되지 않았습니다';

  @override
  String get initializingSftp => 'SFTP 초기화 중...';

  @override
  String get clearHistory => '기록 지우기';

  @override
  String get noTransfersYet => '전송 내역이 없습니다';

  @override
  String get duplicateTab => '탭 복제';

  @override
  String get duplicateTabShortcut => '탭 복제 (Ctrl+\\)';

  @override
  String get copyDown => '아래에 복사';

  @override
  String get previous => '이전';

  @override
  String get next => '다음';

  @override
  String get closeEsc => '닫기 (Esc)';

  @override
  String get closeAll => '모두 닫기';

  @override
  String get closeOthers => '다른 탭 닫기';

  @override
  String get closeTabsToTheLeft => '왼쪽 탭 닫기';

  @override
  String get closeTabsToTheRight => '오른쪽 탭 닫기';

  @override
  String get sortByName => '이름순 정렬';

  @override
  String get sortByStatus => '상태순 정렬';

  @override
  String get noActiveSession => '활성 세션 없음';

  @override
  String get createConnectionHint => '새 연결을 만들거나 사이드바에서 선택하세요';

  @override
  String get hideSidebar => '사이드바 숨기기 (Ctrl+B)';

  @override
  String get showSidebar => '사이드바 표시 (Ctrl+B)';

  @override
  String get language => '언어';

  @override
  String get languageSystemDefault => '자동';

  @override
  String get theme => '테마';

  @override
  String get themeDark => '다크';

  @override
  String get themeLight => '라이트';

  @override
  String get themeSystem => '시스템';

  @override
  String get appearance => '외관';

  @override
  String get connectionSection => '연결';

  @override
  String get transfers => '전송';

  @override
  String get data => '데이터';

  @override
  String get logging => '로그';

  @override
  String get updates => '업데이트';

  @override
  String get about => '정보';

  @override
  String get resetToDefaults => '기본값으로 재설정';

  @override
  String get uiScale => 'UI 배율';

  @override
  String get terminalFontSize => '터미널 글꼴 크기';

  @override
  String get scrollbackLines => '스크롤백 줄 수';

  @override
  String get keepAliveInterval => 'Keep-Alive 간격 (초)';

  @override
  String get sshTimeout => 'SSH 시간 초과 (초)';

  @override
  String get defaultPort => '기본 포트';

  @override
  String get parallelWorkers => '병렬 워커 수';

  @override
  String get maxHistory => '최대 기록 수';

  @override
  String get calculateFolderSizes => '폴더 크기 계산';

  @override
  String get exportData => '데이터 내보내기';

  @override
  String get exportDataSubtitle => '세션, 설정 및 키를 암호화된 .lfs 파일로 저장';

  @override
  String get importDataSubtitle => '.lfs 파일에서 데이터 불러오기';

  @override
  String get importFromSshConfig => 'OpenSSH 설정에서 가져오기';

  @override
  String get importFromSshConfigSubtitle => '~/.ssh/config에서 호스트를 한 번만 가져오기';

  @override
  String get sshConfigPickerTitle => 'OpenSSH 설정 파일 선택';

  @override
  String get sshConfigPreviewTitle => 'SSH 설정 가져오기';

  @override
  String sshConfigPreviewHostsFound(int count) {
    return '호스트 $count개를 찾았습니다';
  }

  @override
  String get sshConfigPreviewNoHosts => '이 파일에서 가져올 수 있는 호스트를 찾을 수 없습니다.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return '다음 호스트의 키 파일을 읽을 수 없습니다: $hosts. 이 호스트는 자격 증명 없이 가져옵니다.';
  }

  @override
  String sshConfigPreviewFolderLabel(String folder) {
    return '폴더로 가져옴: $folder';
  }

  @override
  String sshConfigImportedHosts(int count) {
    return 'SSH 설정에서 호스트 $count개를 가져왔습니다';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '~/.ssh $date';
  }

  @override
  String get exportArchive => '아카이브 내보내기';

  @override
  String get exportArchiveSubtitle => '세션, 설정 및 키를 암호화된 .lfs 파일로 저장';

  @override
  String get exportQrCode => 'QR 코드 내보내기';

  @override
  String get exportQrCodeSubtitle => '선택한 세션과 키를 QR 코드로 공유';

  @override
  String get importArchive => '아카이브 가져오기';

  @override
  String get importArchiveSubtitle => '.lfs 파일에서 데이터 불러오기';

  @override
  String get importOpensshConfig => 'OpenSSH 설정 가져오기';

  @override
  String get importOpensshConfigSubtitle => '~/.ssh/config에서 호스트를 한 번만 가져오기';

  @override
  String get importSshKeys => '~/.ssh에서 SSH 키 가져오기';

  @override
  String get importSshKeysSubtitle => '~/.ssh를 스캔하여 개인 키를 찾아 선택한 키를 키 관리자에 추가';

  @override
  String get importSshKeysTitle => 'SSH 키 가져오기';

  @override
  String importSshKeysFound(int count) {
    return '키 $count개를 찾았습니다 — 가져올 항목을 선택하세요';
  }

  @override
  String get importSshKeysNoneFound => '~/.ssh에서 개인 키를 찾을 수 없습니다.';

  @override
  String importedSshKeys(int count) {
    return '키 $count개를 가져왔습니다';
  }

  @override
  String importedSshKeysWithSkipped(int imported, int skipped) {
    return '새 키 $imported개를 가져왔으며, $skipped개는 이미 저장소에 있습니다';
  }

  @override
  String get sshKeyAlreadyImported => '이미 저장소에 있음';

  @override
  String get setMasterPasswordHint => '아카이브를 암호화할 마스터 비밀번호를 설정하세요.';

  @override
  String get passwordsDoNotMatch => '비밀번호가 일치하지 않습니다';

  @override
  String exportedTo(String path) {
    return '내보내기 완료: $path';
  }

  @override
  String exportFailed(String error) {
    return '내보내기 실패: $error';
  }

  @override
  String get pathToLfsFile => '.lfs 파일 경로';

  @override
  String get hintLfsPath => '/path/to/export.lfs';

  @override
  String get browse => '찾아보기';

  @override
  String get shareViaQrCode => 'QR 코드로 공유';

  @override
  String get shareViaQrSubtitle => '다른 기기에서 스캔할 수 있도록 세션을 QR로 내보내기';

  @override
  String get dataLocation => '데이터 위치';

  @override
  String get pathCopied => '경로가 클립보드에 복사되었습니다';

  @override
  String get urlCopied => 'URL이 클립보드에 복사되었습니다';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — SSH/SFTP 클라이언트';
  }

  @override
  String get sourceCode => '소스 코드';

  @override
  String get enableLogging => '로그 활성화';

  @override
  String get logIsEmpty => '로그가 비어 있습니다';

  @override
  String logExportedTo(String path) {
    return '로그 내보내기 완료: $path';
  }

  @override
  String logExportFailed(String error) {
    return '로그 내보내기 실패: $error';
  }

  @override
  String get logsCleared => '로그가 지워졌습니다';

  @override
  String get copiedToClipboard => '클립보드에 복사되었습니다';

  @override
  String get copyLog => '로그 복사';

  @override
  String get exportLog => '로그 내보내기';

  @override
  String get clearLogs => '로그 지우기';

  @override
  String get local => '로컬';

  @override
  String get remote => '원격';

  @override
  String get pickFolder => '폴더 선택';

  @override
  String get refresh => '새로고침';

  @override
  String get up => '위로';

  @override
  String get emptyDirectory => '빈 디렉터리';

  @override
  String get cancelSelection => '선택 취소';

  @override
  String get openSftpBrowser => 'SFTP 브라우저 열기';

  @override
  String get openSshTerminal => 'SSH 터미널 열기';

  @override
  String get noActiveFileBrowsers => '활성 파일 브라우저가 없습니다';

  @override
  String get useSftpFromSessions => '세션에서 \"SFTP\"를 사용하세요';

  @override
  String get anotherInstanceRunning => 'LetsFLUTssh가 이미 실행 중입니다.';

  @override
  String importFailedShort(String error) {
    return '가져오기 실패: $error';
  }

  @override
  String get saveLogAs => '로그 저장';

  @override
  String get chooseSaveLocation => '저장 위치 선택';

  @override
  String get forward => '앞으로';

  @override
  String get name => '이름';

  @override
  String get size => '크기';

  @override
  String get modified => '수정일';

  @override
  String get mode => '권한';

  @override
  String get owner => '소유자';

  @override
  String get connectionError => '연결 오류';

  @override
  String get resizeWindowToViewFiles => '파일을 보려면 창 크기를 조정하세요';

  @override
  String get completed => '완료됨';

  @override
  String get connected => '연결됨';

  @override
  String get disconnected => '연결 해제됨';

  @override
  String get exit => '종료';

  @override
  String get exitConfirmation => '활성 세션이 연결 해제됩니다. 종료하시겠습니까?';

  @override
  String get hintFolderExample => '예: Production';

  @override
  String get credentialsNotSet => '자격 증명이 설정되지 않았습니다';

  @override
  String get exportSessionsViaQr => 'QR로 세션 내보내기';

  @override
  String get qrNoCredentialsWarning =>
      '비밀번호와 SSH 키는 포함되지 않습니다.\n가져온 세션에는 자격 증명을 다시 입력해야 합니다.';

  @override
  String get qrTooManyForSingleCode =>
      '하나의 QR 코드에 너무 많은 세션이 있습니다. 일부를 선택 해제하거나 .lfs 내보내기를 사용하세요.';

  @override
  String get qrTooLarge => '너무 큽니다 — 일부 항목을 선택 해제하거나 .lfs 파일 내보내기를 사용하세요.';

  @override
  String get exportAll => '모두 내보내기';

  @override
  String get showQr => 'QR 표시';

  @override
  String get sort => '정렬';

  @override
  String get resizePanelDivider => '패널 구분선 크기 조정';

  @override
  String get youreRunningLatest => '최신 버전을 사용 중입니다';

  @override
  String get liveLog => '실시간 로그';

  @override
  String transferNItems(int count) {
    return '$count개 항목 전송';
  }

  @override
  String get time => '시간';

  @override
  String get failed => '실패';

  @override
  String get errOperationNotPermitted => '작업이 허용되지 않습니다';

  @override
  String get errNoSuchFileOrDirectory => '파일 또는 디렉터리가 없습니다';

  @override
  String get errNoSuchProcess => '해당 프로세스가 없습니다';

  @override
  String get errIoError => 'I/O 오류';

  @override
  String get errBadFileDescriptor => '잘못된 파일 디스크립터';

  @override
  String get errResourceTemporarilyUnavailable => '리소스를 일시적으로 사용할 수 없습니다';

  @override
  String get errOutOfMemory => '메모리 부족';

  @override
  String get errPermissionDenied => '권한이 거부되었습니다';

  @override
  String get errFileExists => '파일이 이미 존재합니다';

  @override
  String get errNotADirectory => '디렉터리가 아닙니다';

  @override
  String get errIsADirectory => '디렉터리입니다';

  @override
  String get errInvalidArgument => '잘못된 인수';

  @override
  String get errTooManyOpenFiles => '열린 파일이 너무 많습니다';

  @override
  String get errNoSpaceLeftOnDevice => '장치에 남은 공간이 없습니다';

  @override
  String get errReadOnlyFileSystem => '읽기 전용 파일 시스템';

  @override
  String get errBrokenPipe => '파이프가 끊어졌습니다';

  @override
  String get errFileNameTooLong => '파일 이름이 너무 깁니다';

  @override
  String get errDirectoryNotEmpty => '디렉터리가 비어 있지 않습니다';

  @override
  String get errAddressAlreadyInUse => '주소가 이미 사용 중입니다';

  @override
  String get errCannotAssignAddress => '요청한 주소를 할당할 수 없습니다';

  @override
  String get errNetworkIsDown => '네트워크가 다운되었습니다';

  @override
  String get errNetworkIsUnreachable => '네트워크에 연결할 수 없습니다';

  @override
  String get errConnectionResetByPeer => '피어에 의해 연결이 재설정되었습니다';

  @override
  String get errConnectionTimedOut => '연결 시간이 초과되었습니다';

  @override
  String get errConnectionRefused => '연결이 거부되었습니다';

  @override
  String get errHostIsDown => '호스트가 다운되었습니다';

  @override
  String get errNoRouteToHost => '호스트로의 경로가 없습니다';

  @override
  String get errConnectionAborted => '연결이 중단되었습니다';

  @override
  String get errAlreadyConnected => '이미 연결되어 있습니다';

  @override
  String get errNotConnected => '연결되지 않았습니다';

  @override
  String errSshConnectFailed(String host, int port) {
    return '$host:$port에 연결하지 못했습니다';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return '$user@$host 인증에 실패했습니다';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return '$host:$port에 연결하지 못했습니다';
  }

  @override
  String get errSshAuthAborted => '인증이 중단되었습니다';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return '$host:$port의 호스트 키가 거부되었습니다 — 호스트 키를 수락하거나 known_hosts를 확인하세요';
  }

  @override
  String get errSshOpenShellFailed => '셸을 열지 못했습니다';

  @override
  String get errSshLoadKeyFileFailed => 'SSH 키 파일을 로드하지 못했습니다';

  @override
  String get errSshParseKeyFailed => 'PEM 키 데이터를 파싱하지 못했습니다';

  @override
  String get errSshConnectionDisposed => '연결이 폐기되었습니다';

  @override
  String get errSshNotConnected => '연결되지 않았습니다';

  @override
  String get errConnectionFailed => '연결에 실패했습니다';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return '$seconds초 후 연결 시간이 초과되었습니다';
  }

  @override
  String get errSessionClosed => '세션이 종료되었습니다';

  @override
  String errShellError(String error) {
    return '셸 오류: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return '재연결 실패: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'SFTP 초기화 실패: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return '다운로드 실패: $error';
  }

  @override
  String get errDecryptionFailed => '자격 증명 복호화에 실패했습니다. 키 파일이 손상되었을 수 있습니다.';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => '로그인';

  @override
  String get protocol => '프로토콜';

  @override
  String get typeLabel => '유형';

  @override
  String get folder => '폴더';

  @override
  String nSubitems(int count) {
    return '$count개 항목';
  }

  @override
  String get subitems => '항목';

  @override
  String get storagePermissionRequired => '로컬 파일을 탐색하려면 저장소 권한이 필요합니다';

  @override
  String get grantPermission => '권한 부여';

  @override
  String get storagePermissionLimited => '제한된 접근 — 모든 파일에 대한 전체 저장소 권한을 부여하세요';

  @override
  String progressConnecting(String host, int port) {
    return '$host:$port에 연결 중';
  }

  @override
  String get progressVerifyingHostKey => '호스트 키 확인 중';

  @override
  String progressAuthenticating(String user) {
    return '$user(으)로 인증 중';
  }

  @override
  String get progressOpeningShell => '셸 열기';

  @override
  String get progressOpeningSftp => 'SFTP 채널 열기';

  @override
  String get transfersLabel => '전송:';

  @override
  String transferCountActive(int count) {
    return '$count개 활성';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count개 대기 중';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count개 기록';
  }

  @override
  String transferTooltipCreated(String time) {
    return '생성: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return '시작: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return '종료: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return '소요 시간: $duration';
  }

  @override
  String get transferStatusQueued => '대기 중';

  @override
  String get transferStartingUpload => '업로드 시작 중...';

  @override
  String get transferStartingDownload => '다운로드 시작 중...';

  @override
  String get transferCopying => '복사 중...';

  @override
  String get transferDone => '완료';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total 파일';
  }

  @override
  String get folderNameLabel => '폴더 이름';

  @override
  String folderAlreadyExists(String name) {
    return '폴더 \"$name\"이(가) 이미 존재합니다';
  }

  @override
  String get dropKeyFileHere => '키 파일을 여기에 드롭하세요';

  @override
  String get sessionNoCredentials => '세션에 인증 정보가 없습니다 — 비밀번호 또는 키를 추가하려면 편집하세요';

  @override
  String dragItemCount(int count) {
    return '$count개 항목';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return '모두 선택 ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return '크기: $size KB / 최대 $max KB';
  }

  @override
  String get noActiveTerminals => '활성 터미널 없음';

  @override
  String get connectFromSessionsTab => '세션 탭에서 연결';

  @override
  String fileNotFound(String path) {
    return '파일을 찾을 수 없음: $path';
  }

  @override
  String get sshConnectionChannel => 'SSH 연결';

  @override
  String get sshConnectionChannelDesc => 'SSH 연결을 백그라운드에서 유지합니다.';

  @override
  String get sshActive => 'SSH 활성';

  @override
  String activeConnectionCount(int count) {
    return '$count개 활성 연결';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count개 항목, $size';
  }

  @override
  String get maximize => '최대화';

  @override
  String get restore => '복원';

  @override
  String get duplicateDownShortcut => '아래로 복제 (Ctrl+Shift+\\)';

  @override
  String get security => '보안';

  @override
  String get knownHosts => '알려진 호스트';

  @override
  String get knownHostsSubtitle => '신뢰할 수 있는 SSH 서버 지문 관리';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '알려진 호스트 $count개',
      zero: '알려진 호스트 없음',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty => '알려진 호스트가 없습니다. 서버에 연결하여 추가하세요.';

  @override
  String get removeHost => '호스트 제거';

  @override
  String removeHostConfirm(String host) {
    return '알려진 호스트에서 $host을(를) 제거하시겠습니까? 다음 연결 시 키를 다시 확인해야 합니다.';
  }

  @override
  String get clearAllKnownHosts => '모든 알려진 호스트 삭제';

  @override
  String get clearAllKnownHostsConfirm =>
      '모든 알려진 호스트를 제거하시겠습니까? 각 서버 키를 다시 확인해야 합니다.';

  @override
  String get importKnownHosts => '알려진 호스트 가져오기';

  @override
  String get importKnownHostsSubtitle => 'OpenSSH known_hosts 파일에서 가져오기';

  @override
  String get exportKnownHosts => '알려진 호스트 내보내기';

  @override
  String importedHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '새 호스트 $count개 가져옴',
      zero: '새 호스트를 가져오지 않음',
    );
    return '$_temp0';
  }

  @override
  String get clearedAllHosts => '모든 알려진 호스트를 삭제했습니다';

  @override
  String removedHost(String host) {
    return '$host 제거됨';
  }

  @override
  String get noHostsToExport => '내보낼 호스트가 없습니다';

  @override
  String get tools => '도구';

  @override
  String get sshKeys => 'SSH 키';

  @override
  String get sshKeysSubtitle => '인증용 SSH 키 쌍 관리';

  @override
  String get noKeys => 'SSH 키가 없습니다. 가져오거나 생성하세요.';

  @override
  String get generateKey => '키 생성';

  @override
  String get importKey => '키 가져오기';

  @override
  String get keyLabel => '키 이름';

  @override
  String get keyLabelHint => '예: 업무 서버, GitHub';

  @override
  String get selectKeyType => '키 유형';

  @override
  String get generating => '생성 중...';

  @override
  String keyGenerated(String label) {
    return '키 생성됨: $label';
  }

  @override
  String keyImported(String label) {
    return '키 가져옴: $label';
  }

  @override
  String get deleteKey => '키 삭제';

  @override
  String deleteKeyConfirm(String label) {
    return '키 \"$label\"을(를) 삭제하시겠습니까? 이 키를 사용하는 세션은 접근할 수 없게 됩니다.';
  }

  @override
  String keyDeleted(String label) {
    return '키 삭제됨: $label';
  }

  @override
  String get publicKey => '공개 키';

  @override
  String get publicKeyCopied => '공개 키가 클립보드에 복사되었습니다';

  @override
  String get pastePrivateKey => '개인 키 붙여넣기 (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => '잘못된 PEM 키 데이터';

  @override
  String get selectFromKeyStore => '키 저장소에서 선택';

  @override
  String get noKeySelected => '선택된 키 없음';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '키 $count개',
      zero: '키 없음',
    );
    return '$_temp0';
  }

  @override
  String get generated => '생성됨';

  @override
  String get passphraseRequired => '암호문 필요';

  @override
  String passphrasePrompt(String host) {
    return '$host의 SSH 키가 암호화되어 있습니다. 잠금을 해제하려면 암호문을 입력하세요.';
  }

  @override
  String get passphraseWrong => '암호문이 올바르지 않습니다. 다시 시도하세요.';

  @override
  String get passphrase => '암호문';

  @override
  String get rememberPassphrase => '이 세션에서 기억';

  @override
  String get unlock => '잠금 해제';

  @override
  String get masterPasswordSubtitle => '저장된 인증 정보를 비밀번호로 보호';

  @override
  String get setMasterPassword => '마스터 비밀번호 설정';

  @override
  String get changeMasterPassword => '마스터 비밀번호 변경';

  @override
  String get removeMasterPassword => '마스터 비밀번호 제거';

  @override
  String get masterPasswordEnabled => '인증 정보가 마스터 비밀번호로 보호됩니다';

  @override
  String get masterPasswordDisabled => '인증 정보가 자동 생성 키 사용 (비밀번호 없음)';

  @override
  String get enterMasterPassword => '저장된 인증 정보에 접근하려면 마스터 비밀번호를 입력하세요.';

  @override
  String get wrongMasterPassword => '비밀번호가 올바르지 않습니다. 다시 시도하세요.';

  @override
  String get newPassword => '새 비밀번호';

  @override
  String get currentPassword => '현재 비밀번호';

  @override
  String get passwordTooShort => '비밀번호는 최소 8자 이상이어야 합니다';

  @override
  String get masterPasswordSet => '마스터 비밀번호가 활성화되었습니다';

  @override
  String get masterPasswordChanged => '마스터 비밀번호가 변경되었습니다';

  @override
  String get masterPasswordRemoved => '마스터 비밀번호가 제거되었습니다';

  @override
  String get masterPasswordWarning =>
      '이 비밀번호를 잊으면 저장된 모든 비밀번호와 SSH 키가 손실됩니다. 복구할 수 없습니다.';

  @override
  String get forgotPassword => '비밀번호를 잊으셨나요?';

  @override
  String get forgotPasswordWarning =>
      '저장된 모든 비밀번호, SSH 키, 암호문이 삭제됩니다. 세션과 설정은 유지됩니다. 이 작업은 되돌릴 수 없습니다.';

  @override
  String get resetAndDeleteCredentials => '재설정 및 데이터 삭제';

  @override
  String get credentialsReset => '저장된 모든 인증 정보가 삭제되었습니다';

  @override
  String get derivingKey => '암호화 키 생성 중...';

  @override
  String get reEncrypting => '데이터 재암호화 중...';

  @override
  String get confirmRemoveMasterPassword =>
      '마스터 비밀번호 보호를 해제하려면 현재 비밀번호를 입력하세요. 인증 정보는 자동 생성 키로 재암호화됩니다.';

  @override
  String get securitySetupTitle => '보안 설정';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'OS 키체인이 감지되었습니다 ($keychainName). 데이터가 시스템 키체인을 사용하여 자동으로 암호화됩니다.';
  }

  @override
  String get securitySetupKeychainOptional =>
      '추가 보호를 위해 마스터 비밀번호를 설정할 수도 있습니다.';

  @override
  String get securitySetupNoKeychain =>
      'OS 키체인이 감지되지 않았습니다. 키체인 없이는 세션 데이터(호스트, 비밀번호, 키)가 평문으로 저장됩니다.';

  @override
  String get securitySetupNoKeychainHint =>
      'WSL, 헤드리스 Linux 또는 최소 설치에서는 정상입니다. Linux에서 키체인을 활성화하려면: libsecret과 키링 데몬(예: gnome-keyring)을 설치하세요.';

  @override
  String get securitySetupRecommendMasterPassword =>
      '데이터를 보호하기 위해 마스터 비밀번호 설정을 권장합니다.';

  @override
  String get continueWithKeychain => '키체인으로 계속';

  @override
  String get continueWithoutEncryption => '암호화 없이 계속';

  @override
  String get securityLevel => '보안 수준';

  @override
  String get securityLevelPlaintext => '없음 (평문)';

  @override
  String get securityLevelKeychain => 'OS 키체인';

  @override
  String get securityLevelMasterPassword => '마스터 비밀번호';

  @override
  String get keychainStatus => '키체인';

  @override
  String keychainAvailable(String name) {
    return '사용 가능 ($name)';
  }

  @override
  String get keychainNotAvailable => '사용 불가';

  @override
  String get enableKeychain => '키체인 암호화 활성화';

  @override
  String get enableKeychainSubtitle => 'OS 키체인을 사용하여 저장된 데이터 재암호화';

  @override
  String get keychainEnabled => '키체인 암호화 활성화됨';

  @override
  String get manageMasterPassword => '마스터 비밀번호 관리';

  @override
  String get manageMasterPasswordSubtitle => '마스터 비밀번호 설정, 변경 또는 제거';

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
  String get fullBackup => '전체 백업';

  @override
  String get sessionsOnly => '세션';

  @override
  String get sessionKeysFromManager => '관리자의 세션 키';

  @override
  String get allKeysFromManager => '관리자의 모든 키';

  @override
  String exportTags(int count) {
    return '태그 ($count)';
  }

  @override
  String exportSnippets(int count) {
    return '스니펫 ($count)';
  }

  @override
  String get disableKeychain => '키체인 암호화 비활성화';

  @override
  String get disableKeychainSubtitle => '일반 텍스트 저장으로 전환 (권장하지 않음)';

  @override
  String get disableKeychainConfirm =>
      '데이터베이스가 키 없이 다시 암호화됩니다. 세션과 키가 디스크에 일반 텍스트로 저장됩니다. 계속하시겠습니까?';

  @override
  String get keychainDisabled => '키체인 암호화가 비활성화되었습니다';

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
