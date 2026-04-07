// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class SJa extends S {
  SJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'キャンセル';

  @override
  String get close => '閉じる';

  @override
  String get delete => '削除';

  @override
  String get save => '保存';

  @override
  String get connect => '接続';

  @override
  String get retry => '再試行';

  @override
  String get import_ => 'インポート';

  @override
  String get export_ => 'エクスポート';

  @override
  String get rename => '名前変更';

  @override
  String get create => '作成';

  @override
  String get back => '戻る';

  @override
  String get copy => 'コピー';

  @override
  String get paste => '貼り付け';

  @override
  String get select => '選択';

  @override
  String get required => '必須';

  @override
  String get settings => '設定';

  @override
  String get terminal => 'ターミナル';

  @override
  String get files => 'ファイル';

  @override
  String get transfer => '転送';

  @override
  String get open => '開く';

  @override
  String get search => '検索...';

  @override
  String get filter => 'フィルター...';

  @override
  String get merge => 'マージ';

  @override
  String get replace => '置換';

  @override
  String get reconnect => '再接続';

  @override
  String get updateAvailable => 'アップデートあり';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'バージョン $version が利用可能です（現在: v$current）。';
  }

  @override
  String get releaseNotes => 'リリースノート:';

  @override
  String get skipThisVersion => 'このバージョンをスキップ';

  @override
  String get unskip => 'スキップ解除';

  @override
  String get downloadAndInstall => 'ダウンロードしてインストール';

  @override
  String get openInBrowser => 'ブラウザで開く';

  @override
  String get couldNotOpenBrowser => 'ブラウザを開けませんでした — URLをクリップボードにコピーしました';

  @override
  String get checkForUpdates => 'アップデートを確認';

  @override
  String get checkForUpdatesOnStartup => '起動時にアップデートを確認';

  @override
  String get checking => '確認中...';

  @override
  String get youreUpToDate => '最新バージョンです';

  @override
  String get updateCheckFailed => 'アップデート確認に失敗しました';

  @override
  String get unknownError => '不明なエラー';

  @override
  String downloadingPercent(int percent) {
    return 'ダウンロード中... $percent%';
  }

  @override
  String get downloadComplete => 'ダウンロード完了';

  @override
  String get installNow => '今すぐインストール';

  @override
  String get couldNotOpenInstaller => 'インストーラーを開けませんでした';

  @override
  String versionAvailable(String version) {
    return 'バージョン $version が利用可能';
  }

  @override
  String currentVersion(String version) {
    return '現在: v$version';
  }

  @override
  String sshKeyReceived(String filename) {
    return 'SSH鍵を受信しました: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return 'QR経由で $count 件のセッションをインポートしました';
  }

  @override
  String importedSessions(int count) {
    return '$count 件のセッションをインポートしました';
  }

  @override
  String importFailed(String error) {
    return 'インポート失敗: $error';
  }

  @override
  String get sessions => 'セッション';

  @override
  String get sessionsHeader => 'セッション';

  @override
  String get savedSessions => '保存済みセッション';

  @override
  String get activeConnections => 'アクティブな接続';

  @override
  String get openTabs => '開いているタブ';

  @override
  String get noSavedSessions => '保存済みセッションはありません';

  @override
  String get addSession => 'セッションを追加';

  @override
  String get noSessions => 'セッションなし';

  @override
  String get noSessionsToExport => 'エクスポートするセッションがありません';

  @override
  String nSelectedCount(int count) {
    return '$count 件選択中';
  }

  @override
  String get selectAll => 'すべて選択';

  @override
  String get moveTo => '移動先...';

  @override
  String get moveToFolder => 'フォルダーに移動';

  @override
  String get rootFolder => '/ (ルート)';

  @override
  String get newFolder => '新規フォルダー';

  @override
  String get newConnection => '新規接続';

  @override
  String get editConnection => '接続を編集';

  @override
  String get duplicate => '複製';

  @override
  String get deleteSession => 'セッションを削除';

  @override
  String get renameFolder => 'フォルダー名を変更';

  @override
  String get deleteFolder => 'フォルダーを削除';

  @override
  String get deleteSelected => '選択項目を削除';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return '$parts を削除しますか？\n\nこの操作は元に戻せません。';
  }

  @override
  String nSessions(int count) {
    return '$count 件のセッション';
  }

  @override
  String nFolders(int count) {
    return '$count 件のフォルダー';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'フォルダー「$name」を削除しますか？';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return '内部の $count 件のセッションも削除されます。';
  }

  @override
  String deleteSessionConfirm(String name) {
    return '「$name」を削除しますか？';
  }

  @override
  String get connection => '接続';

  @override
  String get auth => '認証';

  @override
  String get options => 'オプション';

  @override
  String get sessionName => 'セッション名';

  @override
  String get hintMyServer => 'マイサーバー';

  @override
  String get hostRequired => 'ホスト *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'ポート';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'ユーザー名 *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'パスワード';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => '鍵のパスフレーズ';

  @override
  String get hintOptional => '任意';

  @override
  String get hidePemText => 'PEMテキストを隠す';

  @override
  String get pastePemKeyText => 'PEM鍵テキストを貼り付け';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => '追加オプションはまだありません';

  @override
  String get saveAndConnect => '保存して接続';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst => '先に鍵ファイルまたはPEMテキストを指定してください';

  @override
  String get keyTextPem => '鍵テキスト (PEM)';

  @override
  String get selectKeyFile => '鍵ファイルを選択';

  @override
  String get clearKeyFile => '鍵ファイルをクリア';

  @override
  String get authOrDivider => 'または';

  @override
  String get providePasswordOrKey => 'パスワードまたはSSH鍵を入力してください';

  @override
  String get quickConnect => 'クイック接続';

  @override
  String get scanQrCode => 'QRコードをスキャン';

  @override
  String get qrGenerationFailed => 'QRコード生成に失敗しました';

  @override
  String get scanWithCameraApp =>
      'LetsFLUTsshがインストールされている\nデバイスのカメラアプリでスキャンしてください。';

  @override
  String get noPasswordsInQr => 'このQRコードにパスワードや鍵は含まれていません';

  @override
  String get copyLink => 'リンクをコピー';

  @override
  String get linkCopied => 'リンクをクリップボードにコピーしました';

  @override
  String get hostKeyChanged => 'ホスト鍵が変更されました！';

  @override
  String get unknownHost => '不明なホスト';

  @override
  String get hostKeyChangedWarning =>
      '警告: このサーバーのホスト鍵が変更されました。中間者攻撃の可能性があるか、サーバーが再インストールされた可能性があります。';

  @override
  String get unknownHostMessage => 'このホストの信頼性を確認できません。接続を続行しますか？';

  @override
  String get host => 'ホスト';

  @override
  String get keyType => '鍵の種類';

  @override
  String get fingerprint => 'フィンガープリント';

  @override
  String get fingerprintCopied => 'フィンガープリントをコピーしました';

  @override
  String get copyFingerprint => 'フィンガープリントをコピー';

  @override
  String get acceptAnyway => 'それでも承認';

  @override
  String get accept => '承認';

  @override
  String get importData => 'データをインポート';

  @override
  String get masterPassword => 'マスターパスワード';

  @override
  String get confirmPassword => 'パスワードを確認';

  @override
  String get importModeMergeDescription => '新しいセッションを追加し、既存のものを保持';

  @override
  String get importModeReplaceDescription => 'すべてのセッションをインポートしたもので置換';

  @override
  String errorPrefix(String error) {
    return 'エラー: $error';
  }

  @override
  String get folderName => 'フォルダー名';

  @override
  String get newName => '新しい名前';

  @override
  String deleteItems(String names) {
    return '$names を削除しますか？';
  }

  @override
  String deleteNItems(int count) {
    return '$count 件のアイテムを削除';
  }

  @override
  String deletedItem(String name) {
    return '$name を削除しました';
  }

  @override
  String deletedNItems(int count) {
    return '$count 件のアイテムを削除しました';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'フォルダーの作成に失敗しました: $error';
  }

  @override
  String failedToRename(String error) {
    return '名前変更に失敗しました: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return '$name の削除に失敗しました: $error';
  }

  @override
  String get editPath => 'パスを編集';

  @override
  String get root => 'ルート';

  @override
  String get controllersNotInitialized => 'コントローラーが初期化されていません';

  @override
  String get initializingSftp => 'SFTPを初期化中...';

  @override
  String get clearHistory => '履歴をクリア';

  @override
  String get noTransfersYet => '転送履歴はまだありません';

  @override
  String get copyRight => '右にコピー';

  @override
  String get copyDown => '下にコピー';

  @override
  String get closePane => 'ペインを閉じる';

  @override
  String get previous => '前へ';

  @override
  String get next => '次へ';

  @override
  String get closeEsc => '閉じる (Esc)';

  @override
  String get copyRightShortcut => '右にコピー (Ctrl+\\)';

  @override
  String get copyDownShortcut => '下にコピー (Ctrl+Shift+\\)';

  @override
  String get closeAll => 'すべて閉じる';

  @override
  String get closeOthers => '他を閉じる';

  @override
  String get closeTabsToTheLeft => '左のタブを閉じる';

  @override
  String get closeTabsToTheRight => '右のタブを閉じる';

  @override
  String get sortByName => '名前で並べ替え';

  @override
  String get sortByStatus => 'ステータスで並べ替え';

  @override
  String get noActiveSession => 'アクティブなセッションがありません';

  @override
  String get createConnectionHint => '新しい接続を作成するか、サイドバーから選択してください';

  @override
  String get hideSidebar => 'サイドバーを隠す (Ctrl+B)';

  @override
  String get showSidebar => 'サイドバーを表示 (Ctrl+B)';

  @override
  String get language => '言語';

  @override
  String get languageSystemDefault => '自動';

  @override
  String get theme => 'テーマ';

  @override
  String get themeDark => 'ダーク';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeSystem => 'システム';

  @override
  String get appearance => '外観';

  @override
  String get connectionSection => '接続';

  @override
  String get transfers => '転送';

  @override
  String get data => 'データ';

  @override
  String get logging => 'ログ';

  @override
  String get updates => 'アップデート';

  @override
  String get about => 'このアプリについて';

  @override
  String get resetToDefaults => 'デフォルトに戻す';

  @override
  String get uiScale => 'UI スケール';

  @override
  String get terminalFontSize => 'ターミナルのフォントサイズ';

  @override
  String get scrollbackLines => 'スクロールバック行数';

  @override
  String get keepAliveInterval => 'キープアライブ間隔（秒）';

  @override
  String get sshTimeout => 'SSHタイムアウト（秒）';

  @override
  String get defaultPort => 'デフォルトポート';

  @override
  String get parallelWorkers => '並列ワーカー数';

  @override
  String get maxHistory => '最大履歴数';

  @override
  String get calculateFolderSizes => 'フォルダーサイズを計算';

  @override
  String get exportData => 'データをエクスポート';

  @override
  String get exportDataSubtitle => 'セッション、設定、鍵を暗号化された .lfs ファイルに保存';

  @override
  String get importDataSubtitle => '.lfs ファイルからデータを読み込み';

  @override
  String get setMasterPasswordHint => 'アーカイブを暗号化するためのマスターパスワードを設定してください。';

  @override
  String get passwordsDoNotMatch => 'パスワードが一致しません';

  @override
  String exportedTo(String path) {
    return 'エクスポート先: $path';
  }

  @override
  String exportFailed(String error) {
    return 'エクスポート失敗: $error';
  }

  @override
  String get pathToLfsFile => '.lfs ファイルのパス';

  @override
  String get hintLfsPath => '/path/to/export.lfs';

  @override
  String get browse => '参照';

  @override
  String get shareViaQrCode => 'QRコードで共有';

  @override
  String get shareViaQrSubtitle => 'セッションをQRコードにエクスポートして別のデバイスでスキャン';

  @override
  String get dataLocation => 'データの保存場所';

  @override
  String get pathCopied => 'パスをクリップボードにコピーしました';

  @override
  String get urlCopied => 'URLをクリップボードにコピーしました';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — SSH/SFTPクライアント';
  }

  @override
  String get sourceCode => 'ソースコード';

  @override
  String get enableLogging => 'ログを有効にする';

  @override
  String get logIsEmpty => 'ログは空です';

  @override
  String logExportedTo(String path) {
    return 'ログのエクスポート先: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'ログのエクスポートに失敗しました: $error';
  }

  @override
  String get logsCleared => 'ログをクリアしました';

  @override
  String get copiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get copyLog => 'ログをコピー';

  @override
  String get exportLog => 'ログをエクスポート';

  @override
  String get clearLogs => 'ログをクリア';

  @override
  String get local => 'ローカル';

  @override
  String get remote => 'リモート';

  @override
  String get pickFolder => 'フォルダーを選択';

  @override
  String get refresh => '更新';

  @override
  String get up => '上へ';

  @override
  String get emptyDirectory => '空のディレクトリ';

  @override
  String get cancelSelection => '選択を解除';

  @override
  String get openSftpBrowser => 'SFTPブラウザを開く';

  @override
  String get openSshTerminal => 'SSHターミナルを開く';

  @override
  String get noActiveFileBrowsers => 'アクティブなファイルブラウザはありません';

  @override
  String get useSftpFromSessions => 'セッションから「SFTP」を使用してください';

  @override
  String get anotherInstanceRunning => 'LetsFLUTsshの別のインスタンスが既に実行中です。';

  @override
  String importFailedShort(String error) {
    return 'インポート失敗: $error';
  }

  @override
  String get saveLogAs => 'ログを名前を付けて保存';

  @override
  String get chooseSaveLocation => '保存場所を選択';

  @override
  String get forward => '進む';

  @override
  String get name => '名前';

  @override
  String get size => 'サイズ';

  @override
  String get modified => '更新日時';

  @override
  String get mode => 'パーミッション';

  @override
  String get owner => '所有者';

  @override
  String get connectionError => '接続エラー';

  @override
  String get resizeWindowToViewFiles => 'ウィンドウサイズを変更してファイルを表示';

  @override
  String get completed => '完了';

  @override
  String get connected => '接続済み';

  @override
  String get disconnected => '切断済み';

  @override
  String get exit => '終了';

  @override
  String get exitConfirmation => 'アクティブなセッションが切断されます。終了しますか？';

  @override
  String get hintFolderExample => '例: Production';

  @override
  String get credentialsNotSet => '認証情報が未設定です';

  @override
  String get exportSessionsViaQr => 'QRでセッションをエクスポート';

  @override
  String get qrNoCredentialsWarning =>
      'パスワードとSSH鍵は含まれません。\nインポートしたセッションには認証情報の入力が必要です。';

  @override
  String get qrTooManyForSingleCode =>
      '1つのQRコードには多すぎます。選択を減らすか、.lfsエクスポートを使用してください。';

  @override
  String get qrTooLarge => 'データが大きすぎます — 選択を減らすか、.lfsファイルエクスポートを使用してください。';

  @override
  String get exportAll => 'すべてエクスポート';

  @override
  String get showQr => 'QRを表示';

  @override
  String get sort => '並べ替え';

  @override
  String get resizePanelDivider => 'パネル分割線のサイズ変更';

  @override
  String get youreRunningLatest => '最新バージョンを使用中です';

  @override
  String get liveLog => 'ライブログ';

  @override
  String transferNItems(int count) {
    return '$count 項目を転送';
  }

  @override
  String get time => '時間';

  @override
  String get failed => '失敗';

  @override
  String get errOperationNotPermitted => '操作が許可されていません';

  @override
  String get errNoSuchFileOrDirectory => 'ファイルまたはディレクトリが存在しません';

  @override
  String get errNoSuchProcess => 'プロセスが存在しません';

  @override
  String get errIoError => 'I/Oエラー';

  @override
  String get errBadFileDescriptor => '不正なファイルディスクリプタ';

  @override
  String get errResourceTemporarilyUnavailable => 'リソースが一時的に利用不可';

  @override
  String get errOutOfMemory => 'メモリ不足';

  @override
  String get errPermissionDenied => 'アクセスが拒否されました';

  @override
  String get errFileExists => 'ファイルが既に存在します';

  @override
  String get errNotADirectory => 'ディレクトリではありません';

  @override
  String get errIsADirectory => 'ディレクトリです';

  @override
  String get errInvalidArgument => '無効な引数';

  @override
  String get errTooManyOpenFiles => '開いているファイルが多すぎます';

  @override
  String get errNoSpaceLeftOnDevice => 'デバイスに空き容量がありません';

  @override
  String get errReadOnlyFileSystem => '読み取り専用ファイルシステム';

  @override
  String get errBrokenPipe => 'パイプが切断されました';

  @override
  String get errFileNameTooLong => 'ファイル名が長すぎます';

  @override
  String get errDirectoryNotEmpty => 'ディレクトリが空ではありません';

  @override
  String get errAddressAlreadyInUse => 'アドレスが既に使用中です';

  @override
  String get errCannotAssignAddress => '要求されたアドレスを割り当てできません';

  @override
  String get errNetworkIsDown => 'ネットワークがダウンしています';

  @override
  String get errNetworkIsUnreachable => 'ネットワークに到達できません';

  @override
  String get errConnectionResetByPeer => '接続がピアによってリセットされました';

  @override
  String get errConnectionTimedOut => '接続がタイムアウトしました';

  @override
  String get errConnectionRefused => '接続が拒否されました';

  @override
  String get errHostIsDown => 'ホストがダウンしています';

  @override
  String get errNoRouteToHost => 'ホストへのルートがありません';

  @override
  String get errConnectionAborted => '接続が中断されました';

  @override
  String get errAlreadyConnected => '既に接続されています';

  @override
  String get errNotConnected => '接続されていません';

  @override
  String errSshConnectFailed(String host, int port) {
    return '$host:$port への接続に失敗しました';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return '$user@$host の認証に失敗しました';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return '$host:$port への接続に失敗しました';
  }

  @override
  String get errSshAuthAborted => '認証が中断されました';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return '$host:$port のホスト鍵が拒否されました — ホスト鍵を承認するか known_hosts を確認してください';
  }

  @override
  String get errSshOpenShellFailed => 'シェルのオープンに失敗しました';

  @override
  String get errSshLoadKeyFileFailed => 'SSH鍵ファイルの読み込みに失敗しました';

  @override
  String get errSshParseKeyFailed => 'PEM鍵データの解析に失敗しました';

  @override
  String get errSshConnectionDisposed => '接続が破棄されました';

  @override
  String get errSshNotConnected => '接続されていません';

  @override
  String get errConnectionFailed => '接続に失敗しました';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return '$seconds 秒後に接続がタイムアウトしました';
  }

  @override
  String get errSessionClosed => 'セッションが閉じられました';

  @override
  String errShellError(String error) {
    return 'シェルエラー: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return '再接続に失敗しました: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'SFTPの初期化に失敗しました: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'ダウンロードに失敗しました: $error';
  }

  @override
  String get errDecryptionFailed => '認証情報の復号に失敗しました。鍵ファイルが破損している可能性があります。';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error（$cause）';
  }

  @override
  String get login => 'ログイン';

  @override
  String get protocol => 'プロトコル';

  @override
  String get typeLabel => 'タイプ';

  @override
  String get folder => 'フォルダー';

  @override
  String nSubitems(int count) {
    return '$count 個のアイテム';
  }

  @override
  String get subitems => 'アイテム';

  @override
  String get storagePermissionRequired => 'ローカルファイルを閲覧するにはストレージ権限が必要です';

  @override
  String get grantPermission => '権限を付与';

  @override
  String get storagePermissionLimited =>
      '制限付きアクセス — すべてのファイルにアクセスするにはストレージ権限を付与してください';
}
