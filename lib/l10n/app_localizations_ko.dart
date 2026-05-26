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
  String get infoDialogProtectsHeader => '보호함';

  @override
  String get infoDialogDoesNotProtectHeader => '보호하지 않음';

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
  String get cut => '잘라내기';

  @override
  String get paste => '붙여넣기';

  @override
  String get select => '선택';

  @override
  String get copyModeTapToStart => '선택 시작점을 터치하세요';

  @override
  String get copyModeExtending => '드래그하여 선택 영역 확장';

  @override
  String get copyModeSetAnchor => '앵커 설정';

  @override
  String get copyModeCopySelection => '선택 복사';

  @override
  String get required => '필수';

  @override
  String get errFillRequiredFields => '* 표시된 필수 항목을 입력하세요';

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
  String get exportWhatToExport => '내보낼 내용:';

  @override
  String get enterMasterPasswordPrompt => '마스터 비밀번호 입력:';

  @override
  String get nextStep => '다음';

  @override
  String get includePasswords => '세션 비밀번호';

  @override
  String get embeddedKeys => '내장 키';

  @override
  String get managerKeys => '키 관리자 항목';

  @override
  String get managerKeysMayBeLarge => '키 관리자 항목은 QR 크기 제한을 초과할 수 있습니다';

  @override
  String get qrPasswordWarning => 'SSH 키는 내보내기 시 기본적으로 비활성화됩니다.';

  @override
  String get sshKeysMayBeLarge => '키가 QR 크기 제한을 초과할 수 있습니다';

  @override
  String exportTotalSize(String size) {
    return '총 크기: $size';
  }

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
  String get noResults => '결과 없음';

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
  String get checkNow => '지금 확인';

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
  String get updateVerifying => '검증 중…';

  @override
  String get downloadComplete => '다운로드 완료';

  @override
  String get installNow => '지금 설치';

  @override
  String get openReleasePage => '릴리스 페이지 열기';

  @override
  String get couldNotOpenInstaller => '설치 프로그램을 열 수 없습니다';

  @override
  String get installerFailedOpenedReleasePage =>
      '설치 프로그램 실행 실패; 브라우저에서 릴리스 페이지 열림';

  @override
  String versionAvailable(String version) {
    return '버전 $version 사용 가능';
  }

  @override
  String currentVersion(String version) {
    return '현재: v$version';
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
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '연결 $count개를 삭제했습니다(대상 없음)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '손상된 세션 $count개를 건너뛰었습니다',
    );
    return '$_temp0';
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
  String get sectionAuthentication => '인증';

  @override
  String get sectionAdvanced => '고급';

  @override
  String get moreOptions => '추가 옵션';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '포트 포워딩 규칙 $countString개',
      zero: '포트 포워딩 규칙 없음',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => '관리…';

  @override
  String get authMethodAgent => '시스템 ssh-agent 사용';

  @override
  String get options => '옵션';

  @override
  String get sessionName => '세션 이름';

  @override
  String get sessionNameAutoFromHost => '호스트에서 자동';

  @override
  String get sessionNameAutoFromUrl => 'URL 호스트에서 자동';

  @override
  String get sessionNameAutoFromBucket => '기본 버킷에서 자동';

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
  String get keyPassphrase => '키 패스프레이즈';

  @override
  String get hintOptional => '선택 사항';

  @override
  String get savedTypeToChange => '저장됨 — 변경하려면 입력';

  @override
  String get hidePemText => 'PEM 텍스트 숨기기';

  @override
  String get pastePemKeyText => 'PEM 키 텍스트 붙여넣기';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

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
  String get emptyFolder => '빈 폴더';

  @override
  String get qrGenerationFailed => 'QR 생성 실패';

  @override
  String get scanWithCameraApp => 'LetsFLUTssh가 설치된 기기의\n카메라 앱으로 스캔하세요.';

  @override
  String get noPasswordsInQr => '이 QR 코드에는 비밀번호나 키가 포함되어 있지 않습니다';

  @override
  String get qrContainsCredentialsWarning =>
      '이 QR 코드에는 자격 증명이 포함되어 있습니다. 화면을 비공개로 유지하세요.';

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
  String get clearHistory => '기록 지우기';

  @override
  String get noTransfersYet => '전송 내역이 없습니다';

  @override
  String get duplicateTab => '탭 복제';

  @override
  String get duplicateTabShortcut => '탭 복제 (Ctrl+\\)';

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
  String get verboseConnectionLog => '상세 연결 로그';

  @override
  String get verboseConnectionLogSubtitle =>
      'SSH 핸드셰이크와 인증 전체 트레이스를 로그 파일에 기록 (연결 실패 진단용)';

  @override
  String get exportData => '데이터 내보내기';

  @override
  String get exportRecordings => '세션 녹화';

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
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
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
  String get importFromSshDir => '~/.ssh에서 가져오기';

  @override
  String get importFromSshDirSubtitle => '설정 파일에서 호스트, ~/.ssh에서 개인 키를 선택하세요';

  @override
  String get sshDirImportHostsSection => '설정 파일의 호스트';

  @override
  String get sshDirImportKeysSection => '~/.ssh의 키';

  @override
  String importSshKeysFound(int count) {
    return '키 $count개를 찾았습니다 — 가져올 항목을 선택하세요';
  }

  @override
  String get importSshKeysNoneFound => '~/.ssh에서 개인 키를 찾을 수 없습니다.';

  @override
  String get sshKeyAlreadyImported => '이미 저장소에 있음';

  @override
  String get setMasterPasswordHint => '아카이브를 암호화할 마스터 비밀번호를 설정하세요.';

  @override
  String get passwordsDoNotMatch => '비밀번호가 일치하지 않습니다';

  @override
  String get passwordStrengthWeak => '약함';

  @override
  String get passwordStrengthModerate => '보통';

  @override
  String get passwordStrengthStrong => '강함';

  @override
  String get passwordStrengthVeryStrong => '매우 강함';

  @override
  String get tierPlaintextLabel => '일반 텍스트';

  @override
  String get tierPlaintextSubtitle => '암호화 없음 — 파일 권한만';

  @override
  String get tierKeychainLabel => '키체인';

  @override
  String tierKeychainSubtitle(String keychain) {
    return '키가 $keychain에 있음 — 실행 시 자동 잠금 해제';
  }

  @override
  String get tierKeychainUnavailable => '이 설치에서 OS 키체인을 사용할 수 없습니다.';

  @override
  String get tierHardwareLabel => '하드웨어';

  @override
  String get tierParanoidLabel => '마스터 비밀번호(Paranoid)';

  @override
  String get tierHardwareUnavailable => '이 설치본에서는 하드웨어 볼트를 사용할 수 없습니다.';

  @override
  String get pinLabel => '비밀번호';

  @override
  String get l2UnlockTitle => '비밀번호 필요';

  @override
  String get l2UnlockHint => '계속하려면 짧은 비밀번호를 입력하세요';

  @override
  String get l2WrongPassword => '잘못된 비밀번호';

  @override
  String get l3UnlockTitle => '비밀번호 입력';

  @override
  String get l3UnlockHint => '비밀번호로 하드웨어 바인딩된 볼트 잠금 해제';

  @override
  String get l3WrongPin => '잘못된 비밀번호';

  @override
  String tierCooldownHint(int seconds) {
    return '$seconds초 후 재시도';
  }

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
  String get dataLocation => '데이터 위치';

  @override
  String get dataStorageSection => '저장소';

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
  String a11yConnectingTo(String host) {
    return '$host 연결 중';
  }

  @override
  String a11yConnectedTo(String host) {
    return '$host 연결됨';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return '$host 연결 끊김';
  }

  @override
  String a11yConnectionFailed(String host) {
    return '$host 연결 실패';
  }

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
  String get qrTooManyForSingleCode =>
      '하나의 QR 코드에 너무 많은 세션이 있습니다. 일부를 선택 해제하거나 .lfs 내보내기를 사용하세요.';

  @override
  String get qrTooLarge => '너무 큽니다 — 일부 항목을 선택 해제하거나 .lfs 파일 내보내기를 사용하세요.';

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
  String get archivedLog => '보관된 로그';

  @override
  String get loggingLevel => '로그 레벨';

  @override
  String get loggingLevelSubtitleInfo => '일반 항목 + 경고 + 오류';

  @override
  String get loggingLevelSubtitleWarn => '성능 저하 경로와 오류만';

  @override
  String get loggingLevelSubtitleError => '오류만';

  @override
  String get loggingLevelSubtitleOff => '일반 로그가 기록되지 않습니다';

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
  String errSftpInitFailed(String error) {
    return 'SFTP 초기화 실패: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return '다운로드 실패: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      '시스템 폴더 선택기를 사용할 수 없습니다. 다른 위치를 시도하거나 앱의 저장소 권한을 확인하세요.';

  @override
  String get biometricUnlockPrompt => 'LetsFLUTssh 잠금 해제';

  @override
  String get biometricUnlockTitle => '생체 인식으로 잠금 해제';

  @override
  String get biometricUnlockSubtitle => '비밀번호 입력 없이 기기의 생체 인식 센서로 잠금을 해제합니다.';

  @override
  String get biometricEnableFailed => '생체 인식 잠금 해제를 활성화하지 못했습니다.';

  @override
  String get biometricUnlockFailed => '생체 인증 잠금 해제에 실패했습니다. 마스터 비밀번호를 입력하세요.';

  @override
  String get biometricUnlockCancelled => '생체 인증 잠금 해제가 취소되었습니다.';

  @override
  String get biometricNotEnrolled => '이 기기에 등록된 생체 정보가 없습니다.';

  @override
  String get biometricSensorNotAvailable => '이 기기에는 생체 인식 센서가 없습니다.';

  @override
  String get biometricSystemServiceMissing =>
      '지문 서비스(fprintd)가 설치되어 있지 않습니다. README → Installation을 참조하세요.';

  @override
  String get currentPasswordIncorrect => '현재 비밀번호가 올바르지 않습니다';

  @override
  String get wrongPassword => '잘못된 비밀번호';

  @override
  String get lockScreenTitle => 'LetsFLUTssh이(가) 잠겨 있습니다';

  @override
  String get lockScreenSubtitle => '계속하려면 마스터 비밀번호를 입력하거나 생체 인식을 사용하세요.';

  @override
  String get unlock => '잠금 해제';

  @override
  String get autoLockTitle => '비활성 상태에서 자동 잠금';

  @override
  String get autoLockSubtitle =>
      '이 시간 동안 활동이 없으면 UI를 잠급니다. 잠금이 걸릴 때마다 데이터베이스 키가 지워지고 암호화된 저장소가 닫힙니다. 활성 세션은 세션별 자격 증명 캐시 덕분에 연결이 유지되며, 세션을 닫으면 캐시는 비워집니다.';

  @override
  String get autoLockOff => '끔';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes분',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      '업데이트가 거부되었습니다: 다운로드된 파일이 앱에 고정된 릴리스 키로 서명되지 않았습니다. 다운로드가 전송 중에 변조되었거나 현재 릴리스가 이 설치용이 아닐 수 있습니다. 설치하지 마세요 — 공식 릴리스 페이지에서 수동으로 다시 설치하세요.';

  @override
  String get errReleaseManifestUnavailable =>
      'Release manifest를 가져올 수 없습니다. 네트워크 문제이거나 release가 아직 배포 중일 수 있습니다. 잠시 후 다시 시도하세요.';

  @override
  String get updateSecurityWarningTitle => '업데이트 검증 실패';

  @override
  String get updateReinstallAction => '릴리스 페이지 열기';

  @override
  String get errLfsNotArchive => '선택한 파일은 LetsFLUTssh 아카이브가 아닙니다.';

  @override
  String get errLfsDecryptFailed => '마스터 비밀번호가 잘못되었거나 .lfs 아카이브가 손상되었습니다';

  @override
  String get errLfsArchiveTruncated =>
      '아카이브가 불완전합니다. 다시 다운로드하거나 원본 장치에서 다시 내보내세요.';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return '아카이브가 너무 큽니다 ($sizeMb MB). 제한은 $limitMb MB이며, 메모리 보호를 위해 복호화 전에 중단되었습니다.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'known_hosts 항목이 너무 큽니다 ($sizeMb MB). 제한은 $limitMb MB이며, 가져오기 응답성을 유지하기 위해 중단되었습니다.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return '가져오기 실패 — 데이터를 가져오기 전 상태로 복원했습니다. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return '아카이브는 스키마 v$found을(를) 사용하지만, 이 빌드는 v$supported까지만 지원합니다. 가져오려면 앱을 업데이트하세요.';
  }

  @override
  String get progressReadingArchive => '아카이브 읽는 중…';

  @override
  String get progressDecrypting => '복호화 중…';

  @override
  String get progressCollectingData => '데이터 수집 중…';

  @override
  String get progressEncrypting => '암호화 중…';

  @override
  String get progressWritingArchive => '아카이브 쓰는 중…';

  @override
  String get progressWorking => '처리 중…';

  @override
  String get importFromLink => 'QR 링크에서 가져오기';

  @override
  String get importFromLinkSubtitle => '다른 기기에서 복사한 letsflutssh:// 딥링크를 붙여넣기';

  @override
  String get pasteImportLinkTitle => '가져오기 링크 붙여넣기';

  @override
  String get pasteImportLinkDescription =>
      '다른 기기에서 생성된 letsflutssh://import?d=… 링크(또는 원시 페이로드)를 붙여넣으세요. 카메라 불필요.';

  @override
  String get pasteFromClipboard => '클립보드에서 붙여넣기';

  @override
  String get invalidImportLink => '링크에 유효한 LetsFLUTssh 페이로드가 없습니다';

  @override
  String get importAction => '가져오기';

  @override
  String get noTagsAvailable => '아직 태그가 없습니다 — Tools → Tags에서 만드세요.';

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
  String get fileConflictTitle => '파일이 이미 존재합니다';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\"이(가) $targetDir에 이미 있습니다. 어떻게 하시겠습니까?';
  }

  @override
  String get fileConflictSkip => '건너뛰기';

  @override
  String get fileConflictKeepBoth => '모두 유지';

  @override
  String get fileConflictReplace => '바꾸기';

  @override
  String get fileConflictApplyAll => '남은 모든 항목에 적용';

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
  String get clearedAllHosts => '모든 알려진 호스트를 삭제했습니다';

  @override
  String removedHost(String host) {
    return '$host 제거됨';
  }

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
  String get addKey => '키 추가';

  @override
  String get addKeyMenuPaste => 'PEM 붙여넣기';

  @override
  String get filePickerUnavailable => '이 시스템에서 파일 선택기를 사용할 수 없습니다';

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
  String get sshCertificate => '인증서';

  @override
  String get certImport => '인증서 가져오기';

  @override
  String get certImportTooltip =>
      'CA가 서명한 OpenSSH 인증서(`ssh-keygen -s …`로 생성한 `-cert.pub` 파일)를 첨부합니다. 서버가 `authorized_keys` 대신 CA 서명으로 검증할 때 사용합니다. 서버가 plain key auth를 쓰면 건너뜁니다.';

  @override
  String get certImportPickerTitle => 'OpenSSH 인증서 파일 선택';

  @override
  String get certValidFrom => '유효 시작';

  @override
  String get certValidTo => '유효 만료';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => '이 인증서는 곧 만료됩니다.';

  @override
  String get certExpired => '만료됨';

  @override
  String get certRemove => '인증서 제거';

  @override
  String get certRemoveConfirmTitle => '인증서를 제거하시겠습니까?';

  @override
  String get certRemoveConfirmBody => '제거 후 재접속 시 일반 공개 키 인증으로 폴백됩니다.';

  @override
  String errCertParse(String detail) {
    return '인증서 파싱 실패: $detail';
  }

  @override
  String get errCertPairFingerprintMismatch => '이 인증서는 선택한 키와 페어가 아닙니다.';

  @override
  String get pastePrivateKey => '개인 키 붙여넣기 (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => '잘못된 PEM 키 데이터';

  @override
  String get selectFromKeyStore => '키 저장소에서 선택';

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
  String get passphrase => '패스프레이즈';

  @override
  String get enterMasterPassword => '저장된 인증 정보에 접근하려면 마스터 비밀번호를 입력하세요.';

  @override
  String get wrongMasterPassword => '비밀번호가 올바르지 않습니다. 다시 시도하세요.';

  @override
  String get currentPassword => '현재 비밀번호';

  @override
  String get forgotPassword => '비밀번호를 잊으셨나요?';

  @override
  String get credentialsReset => '저장된 모든 인증 정보가 삭제되었습니다';

  @override
  String get migrationToast => '저장소가 최신 형식으로 업그레이드되었습니다';

  @override
  String get dbCorruptTitle => '데이터베이스를 열 수 없습니다';

  @override
  String get dbCorruptBody =>
      '디스크의 데이터를 열 수 없습니다. 다른 자격 증명을 시도하거나 재설정하여 새로 시작하세요.';

  @override
  String get dbCorruptWarning =>
      '재설정은 암호화된 데이터베이스와 모든 보안 관련 파일을 영구적으로 삭제합니다. 데이터는 복구되지 않습니다.';

  @override
  String get dbCorruptTryOther => '다른 자격 증명 시도';

  @override
  String get dbCorruptResetContinue => '재설정 후 새로 설정';

  @override
  String get dbCorruptExit => 'LetsFLUTssh 종료';

  @override
  String get tierResetTitle => '보안 재설정 필요';

  @override
  String get tierResetBody =>
      '이 설치본에는 다른 계층 모델을 사용하던 이전 버전의 LetsFLUTssh에서 가져온 보안 데이터가 포함되어 있습니다. 새 모델은 호환되지 않는 변경 사항이며 자동 마이그레이션 경로가 없습니다. 계속하려면 이 설치본에 저장된 모든 세션, 자격 증명, SSH 키, 알려진 호스트를 삭제하고 첫 실행 설정 마법사를 처음부터 다시 실행해야 합니다.';

  @override
  String get tierResetWarning =>
      '「재설정 및 새로 설정」을 선택하면 암호화된 데이터베이스와 모든 보안 관련 파일이 영구적으로 삭제됩니다. 데이터를 복구해야 하는 경우 지금 앱을 종료하고 LetsFLUTssh의 이전 버전을 다시 설치하여 먼저 내보내세요.';

  @override
  String get tierResetResetContinue => '재설정 및 새로 설정';

  @override
  String get tierResetExit => 'LetsFLUTssh 종료';

  @override
  String get derivingKey => '암호화 키 생성 중...';

  @override
  String get securitySetupTitle => '보안 설정';

  @override
  String get keychainAvailable => '사용 가능';

  @override
  String get changeSecurityTierConfirm =>
      '새 등급으로 데이터베이스를 다시 암호화하는 중입니다. 중단할 수 없습니다 — 완료될 때까지 앱을 열어 두세요.';

  @override
  String get changeSecurityTierDone => '보안 등급이 변경되었습니다';

  @override
  String get changeSecurityTierFailed => '보안 등급을 변경할 수 없습니다';

  @override
  String get firstLaunchSecurityTitle => '보안 저장소가 활성화되었습니다';

  @override
  String get firstLaunchSecurityBody =>
      '데이터는 운영체제 키체인에 보관된 키로 암호화됩니다. 이 기기에서는 잠금 해제가 자동으로 진행됩니다.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      '이 기기에서는 하드웨어 기반 저장소를 사용할 수 있습니다. TPM / Secure Enclave 바인딩을 위해 설정 → 보안에서 업그레이드하세요.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      '이 기기에서는 하드웨어 기반 저장소를 사용할 수 없습니다.';

  @override
  String get firstLaunchSecurityOpenSettings => '설정 열기';

  @override
  String get wizardReducedBanner =>
      '이 설치본에서는 OS 키체인에 접근할 수 없습니다. 암호화 없음(T0)과 마스터 비밀번호(Paranoid) 중에서 선택하세요. 키체인 등급을 활성화하려면 gnome-keyring, kwallet 또는 다른 libsecret 공급자를 설치하세요.';

  @override
  String get tierBadgeCurrent => '현재';

  @override
  String get securitySetupEnable => '활성화';

  @override
  String get securitySetupApply => '적용';

  @override
  String get hwProbeLinuxDeviceMissing =>
      '/dev/tpmrm0에서 TPM이 감지되지 않았습니다. 기기가 지원한다면 BIOS에서 fTPM / PTT를 활성화하세요. 그렇지 않으면 이 기기에서는 하드웨어 등급을 사용할 수 없습니다.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools가 설치되지 않았습니다. 하드웨어 등급을 활성화하려면 `sudo apt install tpm2-tools`(또는 배포판 대응 명령)를 실행하세요.';

  @override
  String get hwProbeLinuxProbeFailed =>
      '하드웨어 등급 점검이 실패했습니다. /dev/tpmrm0 권한과 udev 규칙을 확인하세요 — 자세한 내용은 로그를 참조하세요.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'TPM 2.0이 감지되지 않았습니다. UEFI 펌웨어에서 fTPM / PTT를 활성화하거나 이 기기에서 하드웨어 등급을 사용할 수 없음을 받아들이세요 — 앱은 소프트웨어 기반 자격 증명 저장소로 전환됩니다.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Microsoft Platform Crypto Provider와 Software Key Storage Provider 모두 접근할 수 없습니다 — Windows 암호화 하위 시스템 손상 또는 CNG를 차단하는 그룹 정책일 가능성이 높습니다. 이벤트 뷰어 → 응용 프로그램 및 서비스 로그를 확인하세요.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      '이 Mac에는 Secure Enclave가 없습니다(T1 / T2 보안 칩 없는 2017년 이전 Intel Mac). 하드웨어 등급을 사용할 수 없으므로 마스터 비밀번호를 사용하세요.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      '이 Mac에 로그인 비밀번호가 설정되지 않았습니다. Secure Enclave 키 생성에 필요합니다 — 시스템 설정 → Touch ID 및 비밀번호(또는 로그인 비밀번호)에서 설정하세요.';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave가 앱의 서명 ID를 거부했습니다 (-34018). 릴리스에 포함된 `macos-resign.sh` 스크립트를 실행하여 이 설치에 안정된 자체 서명 ID를 부여한 후 앱을 다시 시작하세요.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      '기기 암호가 설정되지 않았습니다. Secure Enclave 키 생성에 필요합니다 — 설정 → Face ID 및 암호(또는 Touch ID 및 암호)에서 설정하세요.';

  @override
  String get hwProbeIosSimulator =>
      'Secure Enclave가 없는 iOS 시뮬레이터에서 실행 중입니다. 하드웨어 등급은 실제 iOS 기기에서만 사용할 수 있습니다.';

  @override
  String get hwProbeAndroidApiTooLow =>
      '하드웨어 등급에는 Android 9 이상이 필요합니다(StrongBox와 키별 등록 무효화는 이전 버전에서 안정적이지 않습니다).';

  @override
  String get hwProbeAndroidBiometricNone =>
      '이 기기에는 생체 인식 하드웨어(지문 또는 얼굴)가 없습니다. 마스터 비밀번호를 사용하세요.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      '등록된 생체 인식이 없습니다. 설정 → 보안 및 개인정보 보호 → 생체 인식에서 지문 또는 얼굴을 추가한 다음 하드웨어 등급을 다시 활성화하세요.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      '생체 인식 하드웨어를 일시적으로 사용할 수 없습니다(실패한 시도 후 잠금 또는 보류 중인 보안 업데이트). 몇 분 후에 다시 시도하세요.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'Android Keystore가 이 기기 빌드에서 하드웨어 키 지원을 거부했습니다(StrongBox 사용 불가, 커스텀 ROM 또는 드라이버 오류). 하드웨어 계층을 사용할 수 없습니다.';

  @override
  String get securityRecheck => '계층 지원 다시 확인';

  @override
  String get securityRecheckUpdated => '계층 지원이 업데이트되었습니다 — 위 카드를 확인하세요';

  @override
  String get securityRecheckUnchanged => '계층 지원에 변경이 없습니다';

  @override
  String get securityMacosEnableSecureTiers => '이 Mac에서 보안 계층 잠금 해제';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      '개인 인증서로 앱을 다시 서명하여 키체인 (T1)과 Secure Enclave (T2)가 업데이트 후에도 작동하도록 합니다';

  @override
  String get securityMacosEnableSecureTiersPrompt => 'macOS가 비밀번호를 한 번 요청합니다';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      '보안 계층이 잠금 해제되었습니다 — T1과 T2 사용 가능';

  @override
  String get securityMacosEnableSecureTiersFailed => '보안 계층 잠금 해제에 실패했습니다';

  @override
  String get securityMacosOfferTitle => '키체인 + Secure Enclave 활성화?';

  @override
  String get securityMacosOfferBody =>
      'macOS는 암호화된 저장소를 앱의 서명 ID에 연결합니다. 안정적인 인증서가 없으면 키체인 (T1)과 Secure Enclave (T2)는 접근을 거부합니다. 이 Mac에서 개인 자체 서명 인증서를 만들고 앱을 다시 서명할 수 있습니다 — 업데이트가 계속 작동하고 비밀이 릴리스 간에 유지됩니다. macOS는 새 인증서를 신뢰하기 위해 로그인 비밀번호를 한 번 요청합니다.';

  @override
  String get securityMacosOfferAccept => '활성화';

  @override
  String get securityMacosOfferDecline => '건너뛰기 — T0 또는 Paranoid 선택';

  @override
  String get securityMacosRemoveIdentity => '서명 ID 제거';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      '개인 인증서를 삭제합니다. T1 / T2 데이터가 연결되어 있습니다 — 먼저 T0 또는 Paranoid로 전환한 후 제거하십시오.';

  @override
  String get securityMacosRemoveIdentityConfirmTitle => '서명 ID를 제거하시겠습니까?';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      '로그인 키체인에서 개인 인증서를 삭제합니다. T1 / T2에 저장된 비밀이 읽을 수 없게 됩니다. 마법사가 열려 제거 전에 T0 (평문) 또는 Paranoid (마스터 비밀번호)로 마이그레이션할 수 있습니다.';

  @override
  String get securityMacosRemoveIdentitySuccess => '서명 ID가 제거됨';

  @override
  String get securityMacosRemoveIdentityFailed => '서명 ID 제거 실패';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus는 작동 중이지만 secret-service 데몬이 실행 중이 아닙니다. gnome-keyring(`sudo apt install gnome-keyring`) 또는 KWalletManager를 설치하고 로그인 시 시작되도록 하세요.';

  @override
  String get keyringProbeFailed =>
      '이 기기에서 OS 키체인에 접근할 수 없습니다. 플랫폼별 오류는 로그를 참조하세요. 앱은 마스터 비밀번호로 전환됩니다.';

  @override
  String get snippets => '스니펫';

  @override
  String get snippetsSubtitle => '재사용 가능한 명령 스니펫을 관리합니다';

  @override
  String get noSnippets => '아직 스니펫이 없습니다';

  @override
  String get addSnippet => '스니펫 추가';

  @override
  String get editSnippet => '스니펫 편집';

  @override
  String get deleteSnippet => '스니펫 삭제';

  @override
  String deleteSnippetConfirm(String title) {
    return '스니펫 \"$title\"을(를) 삭제하시겠습니까?';
  }

  @override
  String get snippetTitle => '제목';

  @override
  String get snippetTitleHint => '예: 배포, 서비스 재시작';

  @override
  String get snippetCommand => '명령';

  @override
  String get snippetCommandHint => '예: sudo systemctl restart nginx';

  @override
  String get snippetDescription => '설명(선택)';

  @override
  String get snippetDescriptionHint => '이 명령은 무엇을 하나요?';

  @override
  String get snippetSaved => '스니펫이 저장되었습니다';

  @override
  String snippetDeleted(String title) {
    return '스니펫 \"$title\"이(가) 삭제되었습니다';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '스니펫 $count개',
      zero: '스니펫 없음',
    );
    return '$_temp0';
  }

  @override
  String get pinToSession => '이 세션에 고정';

  @override
  String get unpinFromSession => '이 세션에서 고정 해제';

  @override
  String get pinnedSnippets => '고정됨';

  @override
  String get allSnippets => '전체';

  @override
  String get commandCopied => '명령이 클립보드에 복사되었습니다';

  @override
  String get snippetTokensHint => '탭하여 자리 표시자 삽입. 실행 시 활성 세션의 값으로 대체됩니다:';

  @override
  String get snippetCustomTokensHint => '이중 중괄호의 다른 것들은 스니펫 실행 시 값을 묻습니다.';

  @override
  String get snippetFillTitle => '스니펫 매개변수 입력';

  @override
  String get snippetFillSubmit => '실행';

  @override
  String get broadcastSetDriver => '이 창에서 브로드캐스트';

  @override
  String get broadcastClearDriver => '이 창에서 브로드캐스트 중지';

  @override
  String get broadcastAddReceiver => '여기서 브로드캐스트 수신';

  @override
  String get broadcastRemoveReceiver => '브로드캐스트 수신 중지';

  @override
  String get broadcastClearAll => '모든 브로드캐스트 중지';

  @override
  String get broadcastPasteTitle => '붙여넣기를 모든 창에 보내시겠습니까?';

  @override
  String broadcastPasteBody(int chars, int count) {
    return '$chars자가 $count개의 다른 창에 전송됩니다.';
  }

  @override
  String get broadcastPasteSend => '보내기';

  @override
  String get portForwarding => '포워딩';

  @override
  String get portForwardingEmpty => '아직 규칙이 없습니다';

  @override
  String get addForwardRule => '규칙 추가';

  @override
  String get editForwardRule => '규칙 편집';

  @override
  String get deleteForwardRule => '규칙 삭제';

  @override
  String get localForward => '로컬';

  @override
  String get remoteForward => '원격';

  @override
  String get dynamicForward => '동적';

  @override
  String get forwardKind => '유형';

  @override
  String get bindAddress => '바인드 주소';

  @override
  String get bindPort => '바인드 포트';

  @override
  String get targetHost => '대상 호스트';

  @override
  String get targetPort => '대상 포트';

  @override
  String get forwardDescription => '설명(선택)';

  @override
  String get forwardEnabled => '사용';

  @override
  String get forwardBindWildcardWarning =>
      '0.0.0.0에 바인드하면 모든 인터페이스에 노출됩니다 — 보통 127.0.0.1을 사용하세요.';

  @override
  String get forwardKindLocalHelp =>
      '로컬: 이 기기에서 포트를 열어 SSH 서버에서 접근 가능한 대상으로 터널링합니다. localhost:bindPort 통해 원격 DB나 관리 UI 접근에 유용.';

  @override
  String get forwardKindRemoteHelp =>
      '원격: SSH 서버에 포트를 열어달라고 요청하여 이 기기에서 접근 가능한 대상으로 다시 터널링합니다. 로컬 개발 서버를 원격 호스트와 공유하는 데 유용 (서버는 non-loopback 바인드에 GatewayPorts yes가 필요할 수 있음).';

  @override
  String get forwardKindDynamicHelp =>
      '동적: 이 기기의 SOCKS5 프록시로 모든 연결을 SSH 서버를 통해 라우팅합니다. 브라우저나 curl을 localhost:bindPort로 설정하면 모든 트래픽이 SSH 통해 전송됩니다.';

  @override
  String get proxyJump => '경유 연결';

  @override
  String get proxyJumpNone => '직접 연결';

  @override
  String get proxyJumpSavedSession => '저장된 세션';

  @override
  String get proxyJumpCustom => '사용자 지정';

  @override
  String get proxyJumpCustomNote =>
      '사용자 지정 hop은 이 세션의 인증 정보를 사용합니다. 다른 bastion 인증이 필요하면 bastion을 별도 세션으로 저장하세요.';

  @override
  String viaSessionLabel(String label) {
    return '$label 경유';
  }

  @override
  String get recordSession => '세션 기록';

  @override
  String get recordSessionHelp =>
      '이 세션의 터미널 출력을 디스크에 저장합니다. 마스터 비밀번호 또는 하드웨어 키가 세션 데이터베이스를 보호하는 경우 저장 시 암호화되며, 그렇지 않으면 데이터베이스 옆에 평문으로 저장됩니다.';

  @override
  String get recordingsBrowserTitle => '녹화';

  @override
  String get recordingsBrowserSubtitle => '녹화된 세션 찾아보기, 재생, 삭제';

  @override
  String get recordingsEmpty => '아직 녹화가 없습니다';

  @override
  String get playRecording => '재생';

  @override
  String get deleteRecording => '삭제';

  @override
  String get recordingPlaybackTitle => '녹화 재생';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

  @override
  String get tags => '태그';

  @override
  String get tagsSubtitle => '세션과 폴더를 컬러 태그로 정리';

  @override
  String get noTags => '아직 태그가 없습니다';

  @override
  String get addTag => '태그 추가';

  @override
  String get deleteTag => '태그 삭제';

  @override
  String deleteTagConfirm(String name) {
    return '태그 \"$name\"을(를) 삭제하시겠습니까? 모든 세션과 폴더에서 제거됩니다.';
  }

  @override
  String get tagName => '태그 이름';

  @override
  String get tagNameHint => '예: Production, Staging';

  @override
  String get tagColor => '색상';

  @override
  String get tagCreated => '태그가 생성되었습니다';

  @override
  String tagDeleted(String name) {
    return '태그 \"$name\"이(가) 삭제되었습니다';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '태그 $count개',
      zero: '태그 없음',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => '태그 관리';

  @override
  String get editTags => '태그 편집';

  @override
  String get fullBackup => '전체 백업';

  @override
  String get sessionsOnly => '세션';

  @override
  String get presetFullImport => '전체 가져오기';

  @override
  String get presetSelective => '선택적';

  @override
  String get presetCustom => '사용자 지정';

  @override
  String get sessionSshKeys => '세션 키 (매니저)';

  @override
  String get allManagerKeys => '모든 관리자 키';

  @override
  String get browseFiles => '파일 찾아보기…';

  @override
  String get sshDirSessionAlreadyImported => '이미 세션에 있음';

  @override
  String get languageSubtitle => '인터페이스 언어';

  @override
  String get themeSubtitle => '다크, 라이트 또는 시스템 따라가기';

  @override
  String get uiScaleSubtitle => '전체 인터페이스 크기 조정';

  @override
  String get terminalFontSizeSubtitle => '터미널 출력의 글꼴 크기';

  @override
  String get scrollbackLinesSubtitle => '터미널 기록 버퍼 크기';

  @override
  String get keepAliveIntervalSubtitle => 'SSH keep-alive 패킷 사이 초 (0 = 끔)';

  @override
  String get sshTimeoutSubtitle => '연결 제한 시간(초)';

  @override
  String get defaultPortSubtitle => '새 세션의 기본 포트';

  @override
  String get parallelWorkersSubtitle => '동시 SFTP 전송 워커';

  @override
  String get maxHistorySubtitle => '기록에 저장되는 최대 명령 수';

  @override
  String get calculateFolderSizesSubtitle => '사이드바의 폴더 옆에 전체 크기 표시';

  @override
  String get checkForUpdatesOnStartupSubtitle => '앱 시작 시 GitHub에서 새 버전 확인';

  @override
  String get threatColdDiskTheft => '전원 꺼진 디스크 탈취';

  @override
  String get threatColdDiskTheftDescription =>
      '전원이 꺼진 기기에서 드라이브를 꺼내 다른 컴퓨터에서 읽거나, 홈 디렉터리에 접근할 수 있는 사람이 데이터베이스 파일을 복사하는 경우입니다.';

  @override
  String get threatKeyringFileTheft => 'keyring / keychain 파일 탈취';

  @override
  String get threatKeyringFileTheftDescription =>
      '공격자가 플랫폼의 자격 증명 저장소 파일을 디스크에서 직접 읽어(libsecret keyring, Windows Credential Manager, macOS 로그인 keychain), 그 안에 래핑된 데이터베이스 키를 복구합니다. 하드웨어 등급은 비밀번호와 무관하게 이를 차단합니다. 칩이 키 자료 내보내기를 거부하기 때문입니다. keychain 등급은 추가로 비밀번호가 필요하며, 그렇지 않으면 도난당한 파일이 OS 로그인 비밀번호만으로 풀립니다.';

  @override
  String get modifierOnlyWithPassword => '비밀번호가 있을 때만';

  @override
  String get threatBystanderUnlockedMachine => '잠금 해제된 기기 옆의 제3자';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      '자리를 비운 사이, 누군가 이미 잠금 해제된 컴퓨터에 다가가 이 앱을 여는 상황입니다.';

  @override
  String get threatLiveRamForensicsLocked => '잠긴 기기의 RAM 포렌식';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      '공격자가 RAM을 얼리거나 DMA로 캡처해, 앱이 잠긴 상태여도 스냅샷에서 아직 남아 있는 키 자료를 꺼내 갑니다.';

  @override
  String get threatOsKernelOrKeychainBreach => 'OS 커널 또는 키체인 침해';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      '커널 취약점, 키체인 유출, 또는 하드웨어 보안 칩에 숨겨진 백도어. 운영 체제가 신뢰할 수 있는 자원이 아니라 공격자 그 자체가 됩니다.';

  @override
  String get threatOfflineBruteForce => '약한 비밀번호에 대한 오프라인 무차별 대입';

  @override
  String get threatOfflineBruteForceDescription =>
      '래핑된 키 또는 봉인된 블롭의 사본을 가진 공격자가 어떤 속도 제한도 없이 자신의 속도로 모든 비밀번호를 시도합니다.';

  @override
  String get legendProtects => '보호됨';

  @override
  String get legendDoesNotProtect => '보호되지 않음';

  @override
  String get colT0 => 'T0 평문';

  @override
  String get colT1 => 'T1 키체인';

  @override
  String get colT1Password => 'T1 + 비밀번호';

  @override
  String get colT1PasswordBiometric => 'T1 + 비밀번호 + 생체 인식';

  @override
  String get colT2Password => 'T2 + 비밀번호';

  @override
  String get colT2PasswordBiometric => 'T2 + 비밀번호 + 생체 인식';

  @override
  String get colParanoid => 'Paranoid';

  @override
  String get securityComparisonTableThreatColumn => '위협';

  @override
  String get compareAllTiers => '모든 티어 비교';

  @override
  String get resetAllDataTitle => '모든 데이터 재설정';

  @override
  String get resetAllDataSubtitle =>
      '모든 세션, 키, 구성 및 보안 아티팩트를 삭제합니다. 키체인 항목과 하드웨어 볼트 슬롯도 함께 지웁니다.';

  @override
  String get resetAllDataConfirmTitle => '모든 데이터를 재설정할까요?';

  @override
  String get resetAllDataConfirmBody =>
      '모든 세션, SSH 키, known hosts, 스니펫, 태그, 환경설정 및 모든 보안 아티팩트(키체인 항목, 하드웨어 볼트 데이터, 생체 인증 오버레이)가 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다.';

  @override
  String get resetAllDataConfirmAction => '모두 재설정';

  @override
  String resetAllDataConfirmTypePrompt(String phrase) {
    return '확인하려면 아래에 $phrase을(를) 입력하세요:';
  }

  @override
  String get resetAllDataInProgress => '재설정 중…';

  @override
  String get resetAllDataDone => '모든 데이터가 재설정되었습니다';

  @override
  String get resetAllDataFailed => '재설정 실패';

  @override
  String get recordingsTitle => '녹화';

  @override
  String get recordingsStorageUsedLabel => '사용 중';

  @override
  String get recordingsCapLabel => '한도';

  @override
  String get recordingsCapHint =>
      'recordings/ 폴더에 대한 하드 한도. 초과 시 가장 오래된 녹화부터 삭제됩니다. 진행 중인 녹화는 절대 건드리지 않습니다.';

  @override
  String get recordingsClearAllAction => '모든 녹화 삭제';

  @override
  String get recordingsClearAllConfirmTitle => '모든 녹화를 삭제하시겠습니까?';

  @override
  String get recordingsClearAllConfirmBody =>
      '<app>/recordings/ 아래의 모든 녹화 세션이 삭제됩니다. 현재 진행 중인 녹화(있는 경우)는 유지됩니다. 이 작업은 취소할 수 없습니다.';

  @override
  String recordingsClearAllResult(int count) {
    return '$count개의 녹화를 삭제했습니다';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return '한도가 업데이트되었습니다. $bytes 확보됨.';
  }

  @override
  String get recordingsCapChangedNoChange => '한도가 업데이트되었습니다. 삭제할 대상이 없습니다.';

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
  String get autoLockRequiresPassword => '자동 잠금을 사용하려면 현재 티어에 비밀번호가 필요합니다.';

  @override
  String get recommendedBadge => '권장';

  @override
  String get tierHardwareSubtitleHonest =>
      '고급: 하드웨어에 바인딩된 키, 항상 패스워드로 보호됩니다. 이 기기의 칩이 분실되거나 교체되면 데이터를 복구할 수 없습니다.';

  @override
  String get tierParanoidSubtitleHonest =>
      '대안: 마스터 비밀번호를 사용하며 OS를 신뢰하지 않습니다. OS 침해로부터 보호하지만 T1/T2에 비해 런타임 보호는 향상되지 않습니다.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'runtime 위협(동일 사용자 malware, 실행 중 프로세스 메모리 덤프)은 모든 티어에서 ✗로 표시됩니다. 이는 티어 선택과 무관하게 적용되는 별도의 완화 기능으로 대응됩니다.';

  @override
  String get currentTierBadge => '현재';

  @override
  String get paranoidAlternativeHeader => '대안';

  @override
  String get modifierPasswordLabel => '비밀번호';

  @override
  String get modifierPasswordSubtitle => '볼트 잠금 해제 전에 입력하는 비밀 관문.';

  @override
  String get modifierPasswordRequired => '필수 — Hardware 티어는 항상 패스워드로 보호됩니다.';

  @override
  String get modifierBiometricLabel => '생체 인증 단축';

  @override
  String get modifierBiometricSubtitle =>
      '비밀번호를 직접 입력하는 대신 생체 인증으로 보호된 OS 슬롯에서 가져옵니다.';

  @override
  String get biometricRequiresPassword =>
      '먼저 비밀번호를 활성화하세요 — 생체 인증은 비밀번호 입력을 위한 단축 방식입니다.';

  @override
  String get biometricRequiresActiveTier =>
      '생체 인식 잠금 해제를 활성화하려면 먼저 이 등급을 선택하세요';

  @override
  String get autoLockRequiresActiveTier => '자동 잠금을 구성하려면 먼저 이 등급을 선택하세요';

  @override
  String get biometricForbiddenParanoid => 'Paranoid 단계는 설계상 생체 인증을 허용하지 않습니다.';

  @override
  String get fprintdNotAvailable => 'fprintd가 설치되지 않았거나 등록된 지문이 없습니다.';

  @override
  String get t2RequiresPasswordTitle => 'Hardware 티어용 마스터 패스워드 설정';

  @override
  String get t2RequiresPasswordBody =>
      'Hardware 티어는 modifier로 패스워드가 필요합니다. 바이오메트릭은 그 위의 선택적 shortcut입니다.';

  @override
  String get t2MigrationPromptTitle => 'Hardware 티어에 패스워드가 필요합니다';

  @override
  String get t2MigrationPromptBody =>
      '기존 패스워드 없는 Hardware 설치는 계속하려면 지금 하나를 설정해야 합니다.';

  @override
  String get t2MigrationContinue => '계속';

  @override
  String get t2MigrationSetPasswordTitle => 'Hardware 티어 유지를 위해 패스워드 설정';

  @override
  String get t2MigrationSetPasswordBody =>
      '새 master 패스워드를 입력하세요. hardware 모듈에 이미 sealed 된 DB key가 이 패스워드로 re-seal 됩니다 — 세션과 key는 그대로 유지됩니다.';

  @override
  String get t2MigrationWipeAndRestart => 'Wipe 후 처음부터 다시 시작';

  @override
  String get t2MigrationResealFailed =>
      'Hardware 티어 re-seal 실패 — 다른 패스워드를 선택하거나 wipe 하세요.';

  @override
  String get biometricOverlayEnable => 'Hardware 티어에서 바이오메트릭 shortcut 활성화';

  @override
  String get biometricOverlayEnableSubtitle =>
      '바이오메트릭 게이트가 있는 OS 슬롯에서 패스워드를 해제합니다.';

  @override
  String get biometricOverlayUnavailable =>
      '바이오메트릭 overlay는 이 플랫폼에서 아직 사용할 수 없습니다.';

  @override
  String get biometricOverlayRequiresPassword => 'Hardware 티어 패스워드를 먼저 설정하세요.';

  @override
  String get t2UnlockTitle => '마스터 패스워드로 잠금 해제';

  @override
  String get t2UnlockSubtitle => 'hardware-bound 키가 패스워드로 보호되어 있습니다.';

  @override
  String get t2UnlockUseBiometricButton => '바이오메트릭 사용';

  @override
  String get t2PasswordChanged => 'Hardware 티어 패스워드가 업데이트되었습니다.';

  @override
  String get paranoidMasterPasswordNote =>
      '긴 패스프레이즈를 강력히 권장합니다 — Argon2id는 무차별 대입 공격을 늦출 뿐 차단하지는 못합니다.';

  @override
  String get plaintextWarningTitle => '평문: 암호화 없음';

  @override
  String get plaintextWarningBody =>
      '세션, 키, known hosts가 암호화 없이 저장됩니다. 이 컴퓨터의 파일 시스템에 접근할 수 있는 사람은 누구나 읽을 수 있습니다.';

  @override
  String get plaintextAcknowledge => '내 데이터가 암호화되지 않는다는 것을 이해합니다';

  @override
  String get plaintextAcknowledgeRequired => '계속하기 전에 이해했음을 확인하세요.';

  @override
  String get passwordLabel => '비밀번호';

  @override
  String get masterPasswordLabel => '마스터 비밀번호';

  @override
  String get globalErrorTitle => '예기치 않은 오류';

  @override
  String get globalErrorBody => '예기치 않은 오류가 발생했습니다. 앱은 계속 실행됩니다.';

  @override
  String get globalErrorLogSavedNote => '전체 세부 정보가 로그 파일에 기록되었습니다.';

  @override
  String get globalErrorLogDisabledNote => '오류 세부 정보를 저장하려면 설정에서 로깅을 활성화하세요.';

  @override
  String globalErrorTechnicalLine(String detail) {
    return '오류: $detail';
  }

  @override
  String get globalErrorEnableLoggingButton => '로깅 활성화';

  @override
  String get globalErrorLoggingEnabledToast => '로깅 활성화됨 — 오류가 로그 파일에 기록됩니다';

  @override
  String get fatalErrorQuitButton => '종료';

  @override
  String get fatalErrorWipeButton => '모든 데이터 삭제';

  @override
  String get fatalErrorWipingButton => '삭제 중…';

  @override
  String get fatalErrorWipeExplanation =>
      '삭제하면 모든 앱 파일(config, 데이터베이스, vault blob, 로그)이 제거되고 다음 실행은 깨끗한 설치 상태에서 시작됩니다. 되돌릴 수 없습니다.';

  @override
  String get fatalErrorWipeConfirmTitle => '모든 데이터를 삭제할까요?';

  @override
  String get fatalErrorWipeConfirmBody =>
      'config, 데이터베이스, vault 파일이 모두 영구적으로 삭제됩니다. 앱은 빈 설치 상태에서 다시 시작됩니다. 계속할까요?';

  @override
  String get fatalErrorWipeConfirmAction => '전체 삭제';

  @override
  String get unencryptedArchiveWarning =>
      '이 아카이브는 비밀번호로 보호되어 있지 않습니다. 파일을 가진 사람은 누구나 내용을 읽을 수 있습니다.';

  @override
  String get clipboardCopyFailed => '클립보드 복사에 실패했습니다.';

  @override
  String get nonAsciiHostnameWarning =>
      '호스트 이름에 비 ASCII 문자가 있습니다 — 입력한 문자와 한 글자씩 대조하세요. 시각적으로 유사한 코드포인트(키릴 / 그리스 문자)는 Latin 도메인을 위장할 수 있습니다.';

  @override
  String get playbackPause => '일시정지';

  @override
  String get recordingPlayLocked => '이 암호화된 녹화를 재생하려면 앱 잠금을 해제하세요.';

  @override
  String get recordToggleStart => '녹화 시작';

  @override
  String get recordToggleStop => '녹화 중지';

  @override
  String get foregroundServiceTitle => 'SSH 활성';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '활성 연결 $count개',
      one: '활성 연결 1개',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => '세션 종류';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => '사용자명';

  @override
  String get webDavAuthMethod => 'Auth 방식';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer 토큰';

  @override
  String get trustedCert => '신뢰할 수 있는 인증서 (PEM)';

  @override
  String get trustedCertHint => '-----BEGIN CERTIFICATE-----';

  @override
  String get trustedCertHelp =>
      '서버 인증서를 붙여넣으세요 (하나 이상의 PEM 블록). 이 세션에만 추가 루트 CA로 등록되며 다른 앱에는 영향을 주지 않습니다. 시스템 trust store를 사용하려면 비워두세요.';

  @override
  String get acceptAnyCert => '모든 인증서 수락';

  @override
  String get acceptAnyCertHelp =>
      '이 세션의 TLS 핸드셰이크에서 인증서와 호스트 이름 검사를 모두 건너뜁니다. 시스템 trust store나 고정 인증서가 적합하지 않을 때 최후 수단.';

  @override
  String get acceptAnyCertWarn =>
      'MITM 공격에 취약 — 네트워크 상의 누구나 서버를 가장할 수 있습니다. 신뢰할 수 있는 사설 네트워크에서만 사용하세요.';

  @override
  String get webDavCopyUrl => 'WebDAV URL 복사';

  @override
  String get webDavOpenInBrowser => '브라우저에서 열기';

  @override
  String get errWebDavAuthFailed => 'WebDAV 인증 실패';

  @override
  String get errWebDavNotFound => '경로를 찾을 수 없음';

  @override
  String get errWebDavConflict => '현재 상태와 충돌';

  @override
  String errWebDavGeneric(String detail) {
    return 'WebDAV 서버가 요청을 거부함: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'WebDAV base URL이 필요합니다';

  @override
  String get errWebDavBaseUrlInvalid => 'Base URL은 http:// 또는 https:// 여야 합니다';

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
  String get s3EndpointHint => 'AWS면 비우고, MinIO / R2 / Spaces면 endpoint 지정';

  @override
  String get s3PathStyle => 'Path-style addressing';

  @override
  String get s3PathStyleHint => 'MinIO에 필요; AWS에서는 off';

  @override
  String get s3DefaultBucket => '기본 bucket';

  @override
  String get s3DefaultPrefix => '기본 prefix';

  @override
  String get s3GeneratePresignedUrl => 'Presigned URL 생성';

  @override
  String get s3PresignedUrlExpiry => '만료';

  @override
  String get s3CopyUri => 's3://bucket/key URI 복사';

  @override
  String get s3PresignedUrlExpiry15min => '15분';

  @override
  String get s3PresignedUrlExpiry1hour => '1시간';

  @override
  String get s3PresignedUrlExpiry4hour => '4시간';

  @override
  String get s3PresignedUrlExpiry24hour => '24시간';

  @override
  String get s3PresignedUrlExpiry7day => '7일';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (access key + secret 확인)';

  @override
  String get errS3NoSuchBucket => 'Bucket이 없거나 접근할 수 없음';

  @override
  String get errS3RegionMismatch => 'Bucket이 설정된 region과 다른 region에 있음';

  @override
  String errS3Generic(String detail) {
    return 'S3 서버가 요청을 거부함: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'WebDAV sync 활성화';

  @override
  String get syncPassphrase => 'Sync 패스프레이즈';

  @override
  String get syncPassphraseHint => 'Sync 아카이브를 암호화합니다. 마스터 비밀번호와 달라야 합니다.';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Sync 패스프레이즈는 마스터 비밀번호와 같을 수 없습니다.';

  @override
  String get syncRemotePath => 'Remote 경로';

  @override
  String get syncRemotePathHint =>
      'WebDAV base URL 아래 경로 — 기본값 letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return '마지막 push: $when';
  }

  @override
  String syncLastPulled(String when) {
    return '마지막 pull: $when';
  }

  @override
  String get syncNeverRun => '없음';

  @override
  String get syncUpToDate => 'Sync 최신 상태';

  @override
  String syncPushedBytes(String bytes) {
    return '$bytes push 완료';
  }

  @override
  String syncPullApplied(int count) {
    return 'Remote 에서 $count건 적용';
  }

  @override
  String get errSyncDisabled => 'Sync 비활성화됨';

  @override
  String get errSyncEtagMismatch => 'Remote 가 변경됨 — 먼저 pull 후 push';

  @override
  String get errSyncUnauthorized => 'WebDAV 인증 실패';

  @override
  String errSyncNetwork(String detail) {
    return '네트워크 오류: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion => 'Remote 의 sync 아카이브에 새 빌드가 필요합니다';

  @override
  String get hardwareKey => '하드웨어 키';

  @override
  String get hardwareKeyTapPrompt => '하드웨어 키를 탭하세요';

  @override
  String get hardwareKeyPin => '하드웨어 키 PIN';

  @override
  String get hardwareKeyTimeout => '하드웨어 키가 응답하지 않았습니다';

  @override
  String get hardwareKeyNotFound => '하드웨어 키를 찾을 수 없습니다';

  @override
  String get hardwareKeyUnsupported => '이 플랫폼에서는 직접 하드웨어 키 접근을 사용할 수 없습니다';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'Apple Developer Program entitlement 가 필요합니다. macOS 에서는 ssh-agent 를 사용하세요';

  @override
  String get skKeyRequiresDevice => '이 SSH 키는 하드웨어 키가 필요합니다 — 인증하려면 탭하세요';

  @override
  String get errSkWrongPin => 'PIN 이 올바르지 않습니다';

  @override
  String get hardwareKeyImport => '하드웨어 키 import (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => '하드웨어 키 프롬프트를 취소했습니다';

  @override
  String get agentEndpointSectionTitle => '외부 SSH 클라이언트 연동';

  @override
  String get agentEndpointToggleTitle => '하드웨어 키를 시스템 SSH 클라이언트에 노출';

  @override
  String get agentEndpointToggleSubtitle =>
      '이 기기의 git, ssh, IDE 플러그인에서 FIDO2 / smart-card / TPM 키를 사용할 수 있게 합니다.';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'export 명령 복사';

  @override
  String get agentEndpointCopyPipeName => 'pipe 이름 복사';

  @override
  String get agentEndpointSignatureRequestTitle => '서명 요청';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester가 $keyLabel로 서명하려고 합니다';
  }

  @override
  String get agentEndpointRequesterUnknown => '외부 SSH 클라이언트';

  @override
  String get agentEndpointAuthorizeOnce => '한 번 허용';

  @override
  String get agentEndpointAuthorizeAlways => '허용하고 기억';

  @override
  String get agentEndpointDeny => '거부';

  @override
  String get agentEndpointStatusRunning => '실행 중';

  @override
  String get agentEndpointStatusStopped => '중지됨';

  @override
  String get agentEndpointStatusUnsupported => '이 플랫폼에서는 사용할 수 없음';

  @override
  String get agentEndpointRefusedAddIdentity =>
      '거부됨: 외부 클라이언트는 key를 추가할 수 없습니다.';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'ssh-agent endpoint를 시작할 수 없습니다: $detail';
  }

  @override
  String get pkcs11AddTitle => '스마트카드 / 토큰 키 추가';

  @override
  String get pkcs11ModuleLabel => 'PKCS#11 모듈';

  @override
  String get pkcs11ModuleAutoDetected => '자동 감지됨';

  @override
  String get pkcs11ModuleCustom => '사용자 정의 모듈...';

  @override
  String get pkcs11ModulePickerTitle => 'PKCS#11 라이브러리 선택';

  @override
  String get pkcs11NoModuleFound =>
      'PKCS#11 모듈을 찾을 수 없습니다. OpenSC를 설치하거나 벤더 라이브러리를 선택하세요.';

  @override
  String get pkcs11InitializeFailed => 'PKCS#11 모듈이 초기화되지 않았습니다.';

  @override
  String get pkcs11NoTokenPresent => '리더에 토큰이 없습니다.';

  @override
  String pkcs11TokenLabel(String label) {
    return '토큰: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return '시리얼: $serial';
  }

  @override
  String get pkcs11LoginRequired => '토큰에 로그인이 필요합니다.';

  @override
  String pkcs11PinPrompt(String token) {
    return '$token PIN';
  }

  @override
  String get pkcs11PinPad => '토큰 PIN 패드에서 확인하세요.';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'PIN 틀림. $remaining회 남음.';
  }

  @override
  String get pkcs11PinLocked => '토큰 PIN이 잠겼습니다. PUK로 해제하세요.';

  @override
  String get pkcs11NoSignableKeys =>
      '토큰에 SSH 사용 가능한 키가 없습니다 (RSA, ECDSA, Ed25519).';

  @override
  String get pkcs11GostUnsupported => 'GOST 키는 SSH에 사용할 수 없습니다.';

  @override
  String pkcs11TokenUnplugged(String label) {
    return '토큰 \"$label\"이(가) 삽입되지 않았습니다.';
  }

  @override
  String get pkcs11UriRebindFailed => '저장된 토큰을 찾을 수 없습니다. 다시 연결하세요.';

  @override
  String pkcs11SignFailed(String reason) {
    return '서명 실패: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      '스마트카드 / PKCS#11 토큰은 이 플랫폼에서 사용할 수 없습니다.';

  @override
  String get pkcs11Badge => '스마트카드 / 토큰';

  @override
  String pkcs11InfoModulePath(String path) {
    return '모듈: $path';
  }

  @override
  String pkcs11InfoTokenSerial(String serial) {
    return '토큰 시리얼: $serial';
  }

  @override
  String pkcs11InfoObjectLabel(String label) {
    return '객체: $label';
  }

  @override
  String get pkcs11WizardStepModule => 'PKCS#11 모듈 선택';

  @override
  String get pkcs11WizardStepToken => '토큰 선택';

  @override
  String get pkcs11WizardStepKey => '키 선택';

  @override
  String get pkcs11WizardStepPin => 'PIN 입력';

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
  String get pkcs11SaveCta => '키 가져오기';

  @override
  String get pkcs11SaveInProgress => '토큰에서 공개 키를 읽는 중...';

  @override
  String get pkcs11SaveSuccess => '스마트카드 키를 추가했습니다.';

  @override
  String get pkcs11ScanInProgress => 'PKCS#11 모듈을 스캔하는 중...';

  @override
  String get pkcs11LoadingTokens => '토큰을 로드하는 중...';

  @override
  String get pkcs11LoadingKeys => '키를 로드하는 중...';

  @override
  String get pkcs11ModuleStatusReady => '모듈을 로드했습니다.';

  @override
  String get pkcs11ModuleStatusNoToken => '토큰이 없습니다.';

  @override
  String get pkcs11ModuleStatusFailed => '모듈 로드 실패.';

  @override
  String get pkcs11PinPadHint => '(기기 PIN pad)';

  @override
  String get pkcs11WizardBack => '뒤로';

  @override
  String get pkcs11WizardNext => '다음';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => '하드웨어 키 추가';

  @override
  String get sshKeyHardwareBoundExplainer =>
      '프라이빗 키는 디바이스의 시큐어 하드웨어에 있으며 내보낼 수 없습니다.';

  @override
  String get sshKeyEnclaveDeviceBound => '이 키는 이 Mac에서만 작동합니다.';

  @override
  String get sshKeyEnclaveDeviceBoundIos => '이 키는 이 iPhone에서만 작동합니다.';

  @override
  String get sshKeyHelloDeviceBound => '이 키는 이 PC에서만 작동합니다.';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'Touch ID / Face ID 요구';

  @override
  String get sshKeyEnclavePasscodeFallback => '디바이스 passcode를 fallback으로 허용';

  @override
  String get sshKeyHelloPinRequired => 'Windows Hello 요구 (PIN, 지문 또는 얼굴)';

  @override
  String get sshKeyHardwareUnavailableTitle => '하드웨어 키를 사용할 수 없음';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'Secure Enclave를 사용하려면 앱이 code-signed 되어야 합니다.';

  @override
  String get sshKeyHardwareUnavailableHello =>
      '이 PC에 Windows Hello가 설정되어 있지 않습니다.';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'TPM이 감지되지 않음 — software-backed만 가능.';

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
  String get sshKeyGenerateCta => '생성';

  @override
  String get sshKeyGenerateInProgress => '시큐어 하드웨어에서 키 생성 중...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Code-signing 필요 — USER_GUIDE.md → Hardware-bound keys 참조.';

  @override
  String get sshKeySignInProgress => '시큐어 하드웨어로 서명 중...';

  @override
  String get sshKeyPublicCopy => '퍼블릭 키 복사';

  @override
  String get sshKeyAuthorizedKeysHint =>
      '이 라인을 서버의 ~/.ssh/authorized_keys에 추가하세요.';

  @override
  String get sshKeyEnclaveWizardTitle => 'Secure Enclave SSH 키';

  @override
  String get sshKeyEnclaveWizardLabelHint => '키 이름';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'Windows Hello SSH 키';

  @override
  String get helloWizardLabelHint => '키 라벨';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'Windows Hello로 인증';

  @override
  String get helloPromptDescription =>
      'PIN, 지문, 얼굴 중 하나로 Windows Hello가 SSH 챌린지에 서명합니다.';

  @override
  String get helloSoftwareGatedWarning =>
      '이 기기에는 TPM이 없습니다. 키는 사용자 저장소에 들어가지만 서명마다 Windows Hello가 게이트 역할을 합니다.';

  @override
  String get helloP384NotSupported =>
      'TPM 펌웨어가 P-384를 지원하지 않습니다. P-256 또는 RSA-2048을 선택하세요.';

  @override
  String get helloConfigureFirst => '먼저 설정 -> 로그인 옵션에서 Windows Hello를 구성하세요.';

  @override
  String get tpmSshTitle => 'TPM 기반 SSH 키 생성';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (권장)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported => '이 TPM 펌웨어에서 지원하지 않는 알고리즘.';

  @override
  String get tpmSshPinProtect => 'PIN으로 보호';

  @override
  String get tpmSshPinLockoutWarning => 'PIN을 반복해서 틀리면 TPM이 키를 잠급니다.';

  @override
  String get tpmSshPinMismatch => 'PIN이 일치하지 않습니다.';

  @override
  String get tpmSshStorageBlob => '래핑된 키를 앱 데이터에 저장';

  @override
  String get tpmSshStorageHandle => 'TPM 메모리 슬롯에 영구 저장';

  @override
  String get tpmSshStorageHandleHelp => '서명이 더 빨라집니다. TPM의 영구 슬롯 하나를 소비합니다.';

  @override
  String get tpmSshLabel => '키 레이블';

  @override
  String get tpmSshImportTitle => 'TPM 보호 SSH 키 가져오기';

  @override
  String get tpmSshImportFormat => 'TPM 2.0 키 파일 (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return '$label의 TPM PIN';
  }

  @override
  String get tpmSshPinIncorrect => 'PIN이 올바르지 않습니다.';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM이 락아웃 쿨다운 중입니다. $duration 기다린 후 다시 시도하세요.';
  }

  @override
  String get tpmSshGenerating => 'TPM에서 키 생성 중...';

  @override
  String get tpmSshSigning => 'TPM으로 서명 중...';

  @override
  String get tpmSshUnavailable => '이 장치에서 TPM이 감지되지 않았습니다.';

  @override
  String get tpmSshUnavailableFwDisabled => 'TPM이 펌웨어에서 비활성화되어 있습니다.';

  @override
  String get tpmSshUnavailableNoPermission =>
      '앱이 TPM에 접근할 수 없습니다. 사용자를 `tss` 그룹에 추가하세요.';

  @override
  String tpmSshHandleInUse(String handle) {
    return '영구 슬롯 $handle이 이미 사용 중입니다.';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      '이 키는 Hello / PIN 프롬프트 없이 서명합니다 — 로그인 중에 데스크톱에 접근할 수 있는 사람은 누구나 사용할 수 있습니다.';

  @override
  String get keystoreWizardTitle => 'Android Hardware Key';

  @override
  String get keystoreBadge => 'Android Keystore';

  @override
  String get keystoreKeyAndroidLabel => 'Android Keystore (하드웨어 바인드)';

  @override
  String get keystoreKeyStrongBoxLabel => 'StrongBox HSM';

  @override
  String get keystoreKeyTeeLabel => 'TEE (하드웨어 백드)';

  @override
  String get keystoreKeyGenerating => '하드웨어 바인드 키 생성 중...';

  @override
  String get keystoreKeyAuthPrompt => 'SSH 키를 사용하려면 인증하세요';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      '키가 파기되었습니다: 새 생체 인식이 등록되었습니다. 서버에 공개키를 다시 등록하세요.';

  @override
  String get keystoreKeyStrongBoxUnavailable =>
      '이 기기에서는 StrongBox HSM을 사용할 수 없습니다';

  @override
  String get keystoreKeyUserAuthRequired => '서명마다 생체 인식 / 기기 잠금 해제를 요구';

  @override
  String get keystoreKeyExportDisabled => '하드웨어 바인드 키는 내보낼 수 없습니다';

  @override
  String get keystoreKeyDeleteWarning =>
      '이 키를 삭제하면 하드웨어 저장소에서도 제거됩니다. 새 키를 등록할 때까지 서버는 거부합니다.';

  @override
  String get keystoreKeyBiometricNotEnrolled => '먼저 생체 인식 또는 기기 PIN을 등록하세요';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (StrongBox 가능)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+, TEE 전용)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (최대 호환)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM 사용 불가';

  @override
  String get keystoreStrongBoxFallbackBody =>
      '이 기기는 StrongBox HSM 을 노출하지 않습니다. 대신 TEE 기반 키를 만들까요? 여전히 hardware-backed 이며 StrongBox isolation 만 빠집니다.';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'TEE 사용';

  @override
  String get keystoreStrongBoxFallbackCancel => '취소';

  @override
  String get fido2BrokerSectionTitle => '하드웨어 security key';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / security key';

  @override
  String get fido2BrokerMacosLabel => '시스템 security key 다이얼로그';

  @override
  String get fido2BrokerIosLabel => '시스템 security key (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel => '시스템 security key (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => '직접 USB HID (CTAP2)';

  @override
  String get fido2BrokerTransportNone => '이 플랫폼에서 사용할 수 없음';

  @override
  String get fido2BrokerPreferDirectHidTitle => '시스템 다이얼로그보다 직접 USB HID 우선';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return '고급: 두 경로가 모두 동작하는 플랫폼에서 $brokerLabel을 우회합니다. 직접 HID는 더 많은 authenticator 기능을 지원하지만 앱별 권한 부여가 필요합니다.';
  }

  @override
  String get sshIntegrationSection => 'SSH 통합';

  @override
  String get fido2BrokerNoTransportSubtitle => '이 기기에서는 하드웨어 키를 지원하지 않습니다.';

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return '이 기기에서는 $transport만 사용할 수 있습니다. 토글이 비활성화되어 있습니다.';
  }

  @override
  String get hardwareKeyStubBadge => '임포트 스텁';

  @override
  String get hardwareKeyStubSubtitle => '다른 기기에 있었음 — 사용하려면 여기서 재생성하세요';

  @override
  String get hardwareKeyStubRegenerateAction => '여기서 재생성';

  @override
  String get hardwareKeyStubRemoveAction => '스텁 제거';

  @override
  String get hardwareKeyStubPickerTooltip => '사용하기 전에 이 기기에서 키를 재생성하세요';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return '토큰 \"$token\"의 PKCS#11 모듈을 지정하세요';
  }

  @override
  String get arrowLeft => '왼쪽 화살표';

  @override
  String get arrowUp => '위 화살표';

  @override
  String get arrowDown => '아래 화살표';

  @override
  String get arrowRight => '오른쪽 화살표';

  @override
  String get copyMode => '복사 모드';

  @override
  String get exitCopyMode => '복사 모드 종료';

  @override
  String importedGeneric(String items) {
    return '가져옴: $items';
  }
}
