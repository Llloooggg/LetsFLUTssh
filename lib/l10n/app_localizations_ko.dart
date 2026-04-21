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
  String get exportWhatToExport => '내보낼 내용:';

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
  String get qrPasswordWarning => 'SSH 키는 내보내기 시 기본적으로 비활성화됩니다.';

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
  String get tierRecommendedBadge => '권장';

  @override
  String get tierCurrentBadge => '현재';

  @override
  String get tierAlternativeBranchLabel => '대안 — OS를 신뢰하지 마세요';

  @override
  String get tierUpcomingTooltip => '향후 버전에서 제공됩니다.';

  @override
  String get tierUpcomingNotes =>
      '이 계층의 기본 인프라가 아직 제공되지 않았습니다. 옵션이 존재함을 알 수 있도록 행이 표시됩니다.';

  @override
  String get tierPlaintextLabel => '일반 텍스트';

  @override
  String get tierPlaintextSubtitle => '암호화 없음 — 파일 권한만';

  @override
  String get tierPlaintextThreat1 => '파일 시스템에 접근할 수 있는 누구나 데이터를 읽음';

  @override
  String get tierPlaintextThreat2 => '우발적인 동기화 또는 백업이 모든 것을 드러냄';

  @override
  String get tierPlaintextNotes => '신뢰할 수 있는 격리된 환경에서만 사용하세요.';

  @override
  String get tierKeychainLabel => '키체인';

  @override
  String tierKeychainSubtitle(String keychain) {
    return '키가 $keychain에 있음 — 실행 시 자동 잠금 해제';
  }

  @override
  String get tierKeychainProtect1 => '동일한 기기의 다른 사용자';

  @override
  String get tierKeychainProtect2 => 'OS 로그인 없이 도난당한 디스크';

  @override
  String get tierKeychainThreat1 => 'OS 계정으로 실행되는 멀웨어';

  @override
  String get tierKeychainThreat2 => 'OS 로그인을 탈취하는 공격자';

  @override
  String get tierKeychainUnavailable => '이 설치에서 OS 키체인을 사용할 수 없습니다.';

  @override
  String get tierKeychainPassProtect1 => '당신의 책상에 앉은 동료';

  @override
  String get tierKeychainPassProtect2 => '잠금이 풀린 접근을 가진 행인';

  @override
  String get tierKeychainPassThreat1 => '디스크의 파일을 가진 오프라인 공격자';

  @override
  String get tierKeychainPassThreat2 => '키체인과 동일한 OS 침해 위험';

  @override
  String get tierHardwareLabel => '하드웨어';

  @override
  String get tierHardwareSubtitle => '하드웨어 바운드 볼트 + 잠금 있는 짧은 PIN';

  @override
  String get tierHardwareProtect1 => 'PIN의 오프라인 무차별 대입(하드웨어 속도 제한)';

  @override
  String get tierHardwareProtect2 => '디스크와 키체인 블롭 탈취';

  @override
  String get tierHardwareThreat1 => '보안 모듈의 OS 또는 펌웨어 CVE';

  @override
  String get tierHardwareThreat2 => '강제 생체 인식 잠금 해제(활성화된 경우)';

  @override
  String get tierParanoidLabel => '마스터 비밀번호(Paranoid)';

  @override
  String get tierParanoidSubtitle => '긴 비밀번호 + Argon2id. 키가 OS에 들어가지 않음.';

  @override
  String get tierParanoidProtect1 => 'OS 키체인 침해';

  @override
  String get tierParanoidProtect2 => '도난당한 디스크(비밀번호가 강한 한)';

  @override
  String get tierParanoidThreat1 => '비밀번호를 캡처하는 키로거';

  @override
  String get tierParanoidThreat2 => '약한 비밀번호 + 오프라인 Argon2id 크래킹';

  @override
  String get tierParanoidNotes => '이 계층에서는 생체 인식이 설계상 비활성화되어 있습니다.';

  @override
  String get tierHardwareUnavailable => '이 설치에서는 하드웨어 금고를 사용할 수 없습니다.';

  @override
  String get pinLabel => 'PIN';

  @override
  String get l2UnlockTitle => '비밀번호 필요';

  @override
  String get l2UnlockHint => '계속하려면 짧은 비밀번호를 입력하세요';

  @override
  String get l2WrongPassword => '잘못된 비밀번호';

  @override
  String get l3UnlockTitle => 'PIN 입력';

  @override
  String get l3UnlockHint => '짧은 PIN으로 하드웨어 연결 금고 잠금 해제';

  @override
  String get l3WrongPin => '잘못된 PIN';

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
  String get errExportPickerUnavailable =>
      '시스템 폴더 선택기를 사용할 수 없습니다. 다른 위치를 시도하거나 앱의 저장소 권한을 확인하세요.';

  @override
  String get biometricUnlockPrompt => 'LetsFLUTssh 잠금 해제';

  @override
  String get biometricUnlockTitle => '생체 인식으로 잠금 해제';

  @override
  String get biometricUnlockSubtitle => '비밀번호 입력 없이 기기의 생체 인식 센서로 잠금을 해제합니다.';

  @override
  String get biometricNotAvailable => '이 기기에서는 생체 인식 잠금 해제를 사용할 수 없습니다.';

  @override
  String get biometricEnableFailed => '생체 인식 잠금 해제를 활성화하지 못했습니다.';

  @override
  String get biometricEnabled => '생체 인식 잠금 해제가 활성화되었습니다';

  @override
  String get biometricDisabled => '생체 인식 잠금 해제가 비활성화되었습니다';

  @override
  String get biometricUnlockFailed => '생체 인증 잠금 해제에 실패했습니다. 마스터 비밀번호를 입력하세요.';

  @override
  String get biometricUnlockCancelled => '생체 인증 잠금 해제가 취소되었습니다.';

  @override
  String get biometricNotEnrolled => '이 기기에 등록된 생체 정보가 없습니다.';

  @override
  String get biometricRequiresMasterPassword =>
      '생체 인증 잠금 해제를 사용하려면 먼저 마스터 비밀번호를 설정하세요.';

  @override
  String get biometricSensorNotAvailable => '이 기기에는 생체 인식 센서가 없습니다.';

  @override
  String get biometricSystemServiceMissing =>
      '지문 서비스(fprintd)가 설치되어 있지 않습니다. README → Installation을 참조하세요.';

  @override
  String get biometricBackingHardware => '하드웨어 기반 (Secure Enclave / TPM)';

  @override
  String get biometricBackingSoftware => '소프트웨어 기반';

  @override
  String get currentPasswordIncorrect => '현재 비밀번호가 올바르지 않습니다';

  @override
  String get wrongPassword => '잘못된 비밀번호';

  @override
  String get useKeychain => 'OS 키체인으로 암호화';

  @override
  String get useKeychainSubtitle =>
      '데이터베이스 키를 시스템 자격 증명 저장소에 보관합니다. 끄기 = 평문 데이터베이스.';

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
  String get progressParsingArchive => '아카이브 파싱 중…';

  @override
  String get progressImportingSessions => '세션 가져오는 중';

  @override
  String get progressImportingFolders => '폴더 가져오는 중';

  @override
  String get progressImportingManagerKeys => 'SSH 키 가져오는 중';

  @override
  String get progressImportingTags => '태그 가져오는 중';

  @override
  String get progressImportingSnippets => '스니펫 가져오는 중';

  @override
  String get progressApplyingConfig => '구성 적용 중…';

  @override
  String get progressImportingKnownHosts => 'known_hosts 가져오는 중…';

  @override
  String get progressCollectingData => '데이터 수집 중…';

  @override
  String get progressEncrypting => '암호화 중…';

  @override
  String get progressWritingArchive => '아카이브 쓰는 중…';

  @override
  String get progressReencrypting => '저장소 재암호화 중…';

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
  String get saveSessionToAssignTags => '태그를 할당하려면 먼저 세션을 저장하세요';

  @override
  String get noTagsAssigned => '할당된 태그 없음';

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
  String get importKnownHostsSubtitle => 'OpenSSH known_hosts 파일에서 가져오기';

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
  String get securityLevelPlaintext => '없음';

  @override
  String get securityLevelKeychain => 'OS 키체인';

  @override
  String get securityLevelMasterPassword => '마스터 비밀번호';

  @override
  String get keychainStatus => '키체인';

  @override
  String get keychainAvailable => '사용 가능';

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
  String get changeSecurityTier => '보안 등급 변경';

  @override
  String get changeSecurityTierSubtitle => '등급 사다리를 열고 다른 보안 등급으로 전환';

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
  String get firstLaunchSecurityHardwareUnavailableWindows =>
      '하드웨어 기반 저장소를 사용할 수 없습니다 — 이 기기에서 TPM 2.0이 감지되지 않았습니다.';

  @override
  String get firstLaunchSecurityHardwareUnavailableApple =>
      '하드웨어 기반 저장소를 사용할 수 없습니다 — 이 기기는 Secure Enclave를 보고하지 않습니다.';

  @override
  String get firstLaunchSecurityHardwareUnavailableLinux =>
      '하드웨어 기반 저장소를 사용할 수 없습니다 — 활성화하려면 tpm2-tools와 TPM 2.0 기기를 설치하세요.';

  @override
  String get firstLaunchSecurityHardwareUnavailableAndroid =>
      '하드웨어 기반 저장소를 사용할 수 없습니다 — 이 기기는 StrongBox 또는 TEE를 보고하지 않습니다.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      '이 기기에서는 하드웨어 기반 저장소를 사용할 수 없습니다.';

  @override
  String get firstLaunchSecurityOpenSettings => '설정 열기';

  @override
  String get firstLaunchSecurityDismiss => '확인';

  @override
  String get securityHardwareUpgradeTitle => '하드웨어 기반 저장소 사용 가능';

  @override
  String get securityHardwareUpgradeBody =>
      '업그레이드하여 비밀을 TPM / Secure Enclave에 바인딩하세요.';

  @override
  String get securityHardwareUpgradeAction => '업그레이드';

  @override
  String get securityHardwareUnavailableTitle => '하드웨어 기반 저장소를 사용할 수 없습니다';

  @override
  String get wizardReducedBanner =>
      '이 설치에서는 OS 키체인에 접근할 수 없습니다. 암호화 없음(T0)과 마스터 암호(Paranoid) 중에서 선택하세요. Keychain 등급을 활성화하려면 gnome-keyring, kwallet 또는 다른 libsecret 공급자를 설치하세요.';

  @override
  String get tierBlockProtectsHeader => '보호하는 위협';

  @override
  String get tierBlockDoesNotProtectHeader => '보호하지 않는 위협';

  @override
  String get tierBlockProtectsEmpty => '이 등급에서 보호되는 항목이 없습니다.';

  @override
  String get tierBlockDoesNotProtectEmpty => '노출된 위협이 없습니다.';

  @override
  String get tierBadgeCurrent => '현재';

  @override
  String get securitySetupEnable => '활성화';

  @override
  String get securitySetupApply => '적용';

  @override
  String get passwordDisabledPlaintext => '암호화 없음 등급은 암호로 보호할 비밀이 없습니다.';

  @override
  String get passwordDisabledParanoid =>
      'Paranoid는 데이터베이스 키를 비밀번호에서 파생합니다 — 항상 켜짐.';

  @override
  String get passwordSubtitleOn => '켜짐 — 잠금 해제 시 비밀번호 필요';

  @override
  String get passwordSubtitleOff => '꺼짐 — 이 등급에 비밀번호를 추가하려면 탭';

  @override
  String get passwordSubtitleParanoid => '필수 — 마스터 비밀번호가 등급의 비밀';

  @override
  String get passwordSubtitlePlaintext => '해당 없음 — 이 등급에는 암호화가 없습니다';

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
  String get runSnippet => '실행';

  @override
  String get pinToSession => '이 세션에 고정';

  @override
  String get unpinFromSession => '이 세션에서 고정 해제';

  @override
  String get pinnedSnippets => '고정됨';

  @override
  String get allSnippets => '전체';

  @override
  String get sendToTerminal => '터미널로 전송';

  @override
  String get commandCopied => '명령이 클립보드에 복사되었습니다';

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
  String get presetFullImport => '전체 가져오기';

  @override
  String get presetSelective => '선택적';

  @override
  String get presetCustom => '사용자 지정';

  @override
  String get sessionSshKeys => '세션 SSH 키';

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
  String get enableLoggingSubtitle => '앱 이벤트를 순환 로그 파일에 기록';

  @override
  String get exportWithoutPassword => '비밀번호 없이 내보내시겠습니까?';

  @override
  String get exportWithoutPasswordWarning =>
      '아카이브가 암호화되지 않습니다. 파일에 접근할 수 있는 사람은 비밀번호와 개인 키를 포함한 모든 데이터를 읽을 수 있습니다.';

  @override
  String get continueWithoutPassword => '비밀번호 없이 계속';

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
  String get legendNotApplicable => '해당 없음 — 이 티어에는 사용자 비밀이 없습니다';

  @override
  String get legendWeakPasswordWarning =>
      '약한 비밀번호 허용 — 다른 계층(하드웨어 속도 제한 또는 래핑된 키 바인딩)이 보안을 담당합니다';

  @override
  String get legendStrongPasswordRecommended =>
      '긴 암호 문구 사용을 강력히 권장합니다 — 이 티어의 보안은 여기에 달려 있습니다';

  @override
  String get colT0 => 'T0 평문';

  @override
  String get colT1 => 'T1 키체인';

  @override
  String get colT1Password => 'T1 + 비밀번호';

  @override
  String get colT1PasswordBiometric => 'T1 + 비밀번호 + 생체 인식';

  @override
  String get colT2 => 'T2 하드웨어';

  @override
  String get colT2Password => 'T2 + 비밀번호';

  @override
  String get colT2PasswordBiometric => 'T2 + 비밀번호 + 생체 인식';

  @override
  String get colParanoid => '편집증';

  @override
  String get securityComparisonTableTitle => '보안 티어 — 나란히 비교';

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
  String get resetAllDataInProgress => '재설정 중…';

  @override
  String get resetAllDataDone => '모든 데이터가 재설정되었습니다';

  @override
  String get resetAllDataFailed => '재설정 실패';

  @override
  String get compareAllTiersSubtitle => '각 티어가 무엇을 방어하는지 나란히 비교하세요.';

  @override
  String get autoLockRequiresPassword => '자동 잠금을 사용하려면 현재 티어에 비밀번호가 필요합니다.';

  @override
  String get recommendedBadge => '권장';

  @override
  String get continueWithRecommended => '권장 설정으로 계속';

  @override
  String get customizeSecurity => '보안 사용자 지정';

  @override
  String get tierHardwareSubtitleHonest =>
      '고급: 하드웨어에 바인딩된 키. 이 기기의 칩이 분실되거나 교체되면 데이터를 복구할 수 없습니다.';

  @override
  String get tierParanoidSubtitleHonest =>
      '대안: 마스터 비밀번호를 사용하며 OS를 신뢰하지 않습니다. OS 침해로부터 보호하지만 T1/T2에 비해 런타임 보호는 향상되지 않습니다.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'runtime 위협(동일 사용자 malware, 실행 중 프로세스 메모리 덤프)은 모든 티어에서 ✗로 표시됩니다. 이는 티어 선택과 무관하게 적용되는 별도의 완화 기능으로 대응됩니다.';

  @override
  String get securitySetupContinue => '계속';

  @override
  String get currentTierBadge => '현재';

  @override
  String get paranoidAlternativeHeader => '대안';

  @override
  String get modifierPasswordLabel => '비밀번호';

  @override
  String get modifierPasswordSubtitle => '볼트 잠금 해제 전에 입력하는 비밀 관문.';

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
  String get linuxTpmWithoutPasswordNote =>
      '비밀번호 없는 TPM은 격리는 제공하지만 인증은 제공하지 않습니다. 이 앱을 실행할 수 있는 사람은 누구나 데이터의 잠금을 해제할 수 있습니다.';

  @override
  String get paranoidMasterPasswordNote =>
      '긴 암호문을 강력히 권장합니다 — Argon2id는 무차별 대입 공격을 늦출 뿐 막지는 못합니다.';

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
}
