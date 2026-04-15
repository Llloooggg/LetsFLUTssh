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
  String get appSettings => 'アプリ設定';

  @override
  String get yes => 'はい';

  @override
  String get no => 'いいえ';

  @override
  String get importWhatToImport => 'インポートする内容：';

  @override
  String get enterMasterPasswordPrompt => 'マスターパスワードを入力:';

  @override
  String get nextStep => '次へ';

  @override
  String get includeCredentials => 'パスワードとSSH鍵を含む';

  @override
  String get includePasswords => 'セッションパスワード';

  @override
  String get embeddedKeys => '埋め込みキー';

  @override
  String get managerKeys => 'マネージャーのキー';

  @override
  String get managerKeysMayBeLarge => 'マネージャーキーはQRサイズ制限を超える可能性があります';

  @override
  String get qrPasswordWarning => 'SSHキーはエクスポート時、既定で無効です。';

  @override
  String get sshKeysMayBeLarge => '鍵がQRサイズ制限を超える可能性があります';

  @override
  String exportTotalSize(String size) {
    return '合計サイズ: $size';
  }

  @override
  String get qrCredentialsWarning => 'パスワードとSSH鍵はQRコードに表示されます';

  @override
  String get qrCredentialsTooLarge => '認証情報でQRコードが大きすぎます';

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
  String get emptyFolders => '空のフォルダ';

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
  String get deselectAll => 'すべて解除';

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
  String get keyType => 'キータイプ';

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
  String get confirmPassword => 'パスワード確認';

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
  String get duplicateTab => 'タブを複製';

  @override
  String get duplicateTabShortcut => 'タブを複製 (Ctrl+\\)';

  @override
  String get copyDown => '下にコピー';

  @override
  String get previous => '前へ';

  @override
  String get next => '次へ';

  @override
  String get closeEsc => '閉じる (Esc)';

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
  String sshConfigPreviewHostsFound(int count) {
    return '$count 件のホストが見つかりました';
  }

  @override
  String get sshConfigPreviewNoHosts => 'このファイルにインポート可能なホストが見つかりません。';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return '次のホストの鍵ファイルを読み込めませんでした: $hosts。これらのホストは認証情報なしでインポートされます。';
  }

  @override
  String sshConfigPreviewFolderLabel(String folder) {
    return 'フォルダにインポート: $folder';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'アーカイブをエクスポート';

  @override
  String get exportArchiveSubtitle => 'セッション、設定、鍵を暗号化された .lfs ファイルに保存';

  @override
  String get exportQrCode => 'QR コードをエクスポート';

  @override
  String get exportQrCodeSubtitle => '選択したセッションと鍵を QR コードで共有';

  @override
  String get importArchive => 'アーカイブをインポート';

  @override
  String get importArchiveSubtitle => '.lfs ファイルからデータを読み込み';

  @override
  String get importFromSshDir => '~/.ssh からインポート';

  @override
  String get importFromSshDirSubtitle => '設定ファイルからホスト、~/.ssh から秘密鍵を選択';

  @override
  String get sshDirImportHostsSection => '設定ファイルのホスト';

  @override
  String get sshDirImportKeysSection => '~/.ssh の鍵';

  @override
  String importSshKeysFound(int count) {
    return '$count 件の鍵が見つかりました — インポートするものを選択';
  }

  @override
  String get importSshKeysNoneFound => '~/.ssh に秘密鍵が見つかりません。';

  @override
  String get sshKeyAlreadyImported => '既にストアにあります';

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
  String get errLfsDecryptFailed =>
      'Wrong master password or corrupted .lfs archive';

  @override
  String get progressReadingArchive => 'Reading archive…';

  @override
  String get progressDecrypting => 'Decrypting…';

  @override
  String get progressParsingArchive => 'Parsing archive…';

  @override
  String get progressImportingSessions => 'Importing sessions';

  @override
  String get progressImportingFolders => 'Importing folders';

  @override
  String get progressImportingManagerKeys => 'Importing SSH keys';

  @override
  String get progressImportingTags => 'Importing tags';

  @override
  String get progressImportingSnippets => 'Importing snippets';

  @override
  String get progressApplyingConfig => 'Applying configuration…';

  @override
  String get progressImportingKnownHosts => 'Importing known_hosts…';

  @override
  String get progressCollectingData => 'Collecting data…';

  @override
  String get progressEncrypting => 'Encrypting…';

  @override
  String get progressWritingArchive => 'Writing archive…';

  @override
  String get progressReencrypting => 'Re-encrypting stores…';

  @override
  String get progressWorking => 'Working…';

  @override
  String get saveSessionToAssignTags => 'Save the session first to assign tags';

  @override
  String get noTagsAssigned => 'No tags assigned';

  @override
  String get manageTags => 'Manage Tags';

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

  @override
  String progressConnecting(String host, int port) {
    return '$host:$port に接続中';
  }

  @override
  String get progressVerifyingHostKey => 'ホスト鍵を検証中';

  @override
  String progressAuthenticating(String user) {
    return '$user として認証中';
  }

  @override
  String get progressOpeningShell => 'シェルを起動中';

  @override
  String get progressOpeningSftp => 'SFTPチャネルを起動中';

  @override
  String get transfersLabel => '転送：';

  @override
  String transferCountActive(int count) {
    return '$count 件アクティブ';
  }

  @override
  String transferCountQueued(int count) {
    return '、$count 件待機中';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count 件の履歴';
  }

  @override
  String transferTooltipCreated(String time) {
    return '作成：$time';
  }

  @override
  String transferTooltipStarted(String time) {
    return '開始：$time';
  }

  @override
  String transferTooltipEnded(String time) {
    return '終了：$time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return '所要時間：$duration';
  }

  @override
  String get transferStatusQueued => '待機中';

  @override
  String get transferStartingUpload => 'アップロード開始...';

  @override
  String get transferStartingDownload => 'ダウンロード開始...';

  @override
  String get transferCopying => 'コピー中...';

  @override
  String get transferDone => '完了';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total ファイル';
  }

  @override
  String get folderNameLabel => 'フォルダ名';

  @override
  String folderAlreadyExists(String name) {
    return 'フォルダ「$name」は既に存在します';
  }

  @override
  String get dropKeyFileHere => '鍵ファイルをここにドロップ';

  @override
  String get sessionNoCredentials =>
      'セッションに認証情報がありません — パスワードまたは鍵を追加するために編集してください';

  @override
  String dragItemCount(int count) {
    return '$count 個の項目';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'すべて選択 ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'サイズ：$size KB / 最大 $max KB';
  }

  @override
  String get noActiveTerminals => 'アクティブなターミナルがありません';

  @override
  String get connectFromSessionsTab => 'セッションタブから接続';

  @override
  String fileNotFound(String path) {
    return 'ファイルが見つかりません：$path';
  }

  @override
  String get sshConnectionChannel => 'SSH 接続';

  @override
  String get sshConnectionChannelDesc => 'SSH 接続をバックグラウンドで維持します。';

  @override
  String get sshActive => 'SSH アクティブ';

  @override
  String activeConnectionCount(int count) {
    return '$count 件のアクティブな接続';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count 個の項目、$size';
  }

  @override
  String get maximize => '最大化';

  @override
  String get restore => '元に戻す';

  @override
  String get duplicateDownShortcut => '下に複製 (Ctrl+Shift+\\)';

  @override
  String get security => 'セキュリティ';

  @override
  String get knownHosts => '既知のホスト';

  @override
  String get knownHostsSubtitle => '信頼済み SSH サーバーのフィンガープリントを管理';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '既知のホスト $count 件',
      zero: '既知のホストなし',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty => '既知のホストがありません。サーバーに接続して追加してください。';

  @override
  String get removeHost => 'ホストを削除';

  @override
  String removeHostConfirm(String host) {
    return '既知のホストから $host を削除しますか？次回接続時にキーの再確認が必要になります。';
  }

  @override
  String get clearAllKnownHosts => 'すべての既知のホストを削除';

  @override
  String get clearAllKnownHostsConfirm =>
      'すべての既知のホストを削除しますか？各サーバーキーの再確認が必要になります。';

  @override
  String get importKnownHosts => '既知のホストをインポート';

  @override
  String get importKnownHostsSubtitle => 'OpenSSH known_hosts ファイルからインポート';

  @override
  String get exportKnownHosts => '既知のホストをエクスポート';

  @override
  String importedHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の新しいホストをインポートしました',
      zero: '新しいホストはインポートされませんでした',
    );
    return '$_temp0';
  }

  @override
  String get clearedAllHosts => 'すべての既知のホストを削除しました';

  @override
  String removedHost(String host) {
    return '$host を削除しました';
  }

  @override
  String get noHostsToExport => 'エクスポートするホストがありません';

  @override
  String get tools => 'ツール';

  @override
  String get sshKeys => 'SSH キー';

  @override
  String get sshKeysSubtitle => '認証用 SSH キーペアの管理';

  @override
  String get noKeys => 'SSH キーがありません。インポートまたは生成してください。';

  @override
  String get generateKey => 'キーを生成';

  @override
  String get importKey => 'キーをインポート';

  @override
  String get keyLabel => 'キー名';

  @override
  String get keyLabelHint => '例：業務サーバー、GitHub';

  @override
  String get selectKeyType => 'キータイプ';

  @override
  String get generating => '生成中...';

  @override
  String keyGenerated(String label) {
    return 'キーを生成しました：$label';
  }

  @override
  String keyImported(String label) {
    return 'キーをインポートしました：$label';
  }

  @override
  String get deleteKey => 'キーを削除';

  @override
  String deleteKeyConfirm(String label) {
    return 'キー「$label」を削除しますか？このキーを使用するセッションはアクセスできなくなります。';
  }

  @override
  String keyDeleted(String label) {
    return 'キーを削除しました：$label';
  }

  @override
  String get publicKey => '公開鍵';

  @override
  String get publicKeyCopied => '公開鍵をクリップボードにコピーしました';

  @override
  String get pastePrivateKey => '秘密鍵を貼り付け (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => '無効な PEM キーデータ';

  @override
  String get selectFromKeyStore => 'キーストアから選択';

  @override
  String get noKeySelected => 'キーが選択されていません';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'キー $count 個',
      zero: 'キーなし',
    );
    return '$_temp0';
  }

  @override
  String get generated => '生成済み';

  @override
  String get passphraseRequired => 'パスフレーズが必要です';

  @override
  String passphrasePrompt(String host) {
    return '$host の SSH キーは暗号化されています。パスフレーズを入力してください。';
  }

  @override
  String get passphraseWrong => 'パスフレーズが正しくありません。もう一度お試しください。';

  @override
  String get passphrase => 'パスフレーズ';

  @override
  String get rememberPassphrase => 'このセッションで記憶';

  @override
  String get unlock => 'ロック解除';

  @override
  String get masterPasswordSubtitle => '保存された認証情報をパスワードで保護';

  @override
  String get setMasterPassword => 'マスターパスワードを設定';

  @override
  String get changeMasterPassword => 'マスターパスワードを変更';

  @override
  String get removeMasterPassword => 'マスターパスワードを削除';

  @override
  String get masterPasswordEnabled => '認証情報はマスターパスワードで保護されています';

  @override
  String get masterPasswordDisabled => '認証情報は自動生成キーを使用（パスワードなし）';

  @override
  String get enterMasterPassword => '保存された認証情報にアクセスするにはマスターパスワードを入力してください。';

  @override
  String get wrongMasterPassword => 'パスワードが正しくありません。もう一度お試しください。';

  @override
  String get newPassword => '新しいパスワード';

  @override
  String get currentPassword => '現在のパスワード';

  @override
  String get passwordTooShort => 'パスワードは 8 文字以上必要です';

  @override
  String get masterPasswordSet => 'マスターパスワードを有効にしました';

  @override
  String get masterPasswordChanged => 'マスターパスワードを変更しました';

  @override
  String get masterPasswordRemoved => 'マスターパスワードを削除しました';

  @override
  String get masterPasswordWarning =>
      'このパスワードを忘れると、保存されたすべてのパスワードと SSH キーが失われます。復旧はできません。';

  @override
  String get forgotPassword => 'パスワードを忘れましたか？';

  @override
  String get forgotPasswordWarning =>
      '保存されたすべてのパスワード、SSH キー、パスフレーズが削除されます。セッションと設定は保持されます。この操作は元に戻せません。';

  @override
  String get resetAndDeleteCredentials => 'リセットしてデータを削除';

  @override
  String get credentialsReset => '保存された認証情報がすべて削除されました';

  @override
  String get derivingKey => '暗号化キーを生成中...';

  @override
  String get reEncrypting => 'データを再暗号化中...';

  @override
  String get confirmRemoveMasterPassword =>
      'マスターパスワード保護を解除するには現在のパスワードを入力してください。認証情報は自動生成キーで再暗号化されます。';

  @override
  String get securitySetupTitle => 'セキュリティ設定';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'OS キーチェーンを検出しました ($keychainName)。データはシステムキーチェーンを使用して自動的に暗号化されます。';
  }

  @override
  String get securitySetupKeychainOptional => '追加の保護としてマスターパスワードを設定することもできます。';

  @override
  String get securitySetupNoKeychain =>
      'OS キーチェーンが検出されませんでした。キーチェーンがない場合、セッションデータ（ホスト、パスワード、キー）は平文で保存されます。';

  @override
  String get securitySetupNoKeychainHint =>
      'WSL、ヘッドレス Linux、最小インストールでは正常です。Linux でキーチェーンを有効にするには：libsecret とキーリングデーモン（gnome-keyring など）をインストールしてください。';

  @override
  String get securitySetupRecommendMasterPassword =>
      'データを保護するためにマスターパスワードの設定を推奨します。';

  @override
  String get continueWithKeychain => 'キーチェーンで続行';

  @override
  String get continueWithoutEncryption => '暗号化なしで続行';

  @override
  String get securityLevel => 'セキュリティレベル';

  @override
  String get securityLevelPlaintext => 'なし（平文）';

  @override
  String get securityLevelKeychain => 'OS キーチェーン';

  @override
  String get securityLevelMasterPassword => 'マスターパスワード';

  @override
  String get keychainStatus => 'キーチェーン';

  @override
  String keychainAvailable(String name) {
    return '利用可能 ($name)';
  }

  @override
  String get keychainNotAvailable => '利用不可';

  @override
  String get enableKeychain => 'キーチェーン暗号化を有効にする';

  @override
  String get enableKeychainSubtitle => 'OS キーチェーンを使用して保存データを再暗号化';

  @override
  String get keychainEnabled => 'キーチェーン暗号化が有効になりました';

  @override
  String get manageMasterPassword => 'マスターパスワード管理';

  @override
  String get manageMasterPasswordSubtitle => 'マスターパスワードの設定、変更、削除';

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
  String get editTags => 'Edit Tags';

  @override
  String get fullBackup => 'フルバックアップ';

  @override
  String get sessionsOnly => 'セッション';

  @override
  String get sessionKeysFromManager => 'マネージャーのセッション鍵';

  @override
  String get allKeysFromManager => 'マネージャーの全ての鍵';

  @override
  String exportTags(int count) {
    return 'タグ ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'スニペット ($count)';
  }

  @override
  String get disableKeychain => 'キーチェーン暗号化を無効にする';

  @override
  String get disableKeychainSubtitle => '平文保存に切り替える（非推奨）';

  @override
  String get disableKeychainConfirm =>
      'データベースは鍵なしで再暗号化されます。セッションと鍵はディスクに平文で保存されます。続行しますか？';

  @override
  String get keychainDisabled => 'キーチェーン暗号化が無効になりました';

  @override
  String get presetFullImport => '完全インポート';

  @override
  String get presetSelective => '選択的';

  @override
  String get presetCustom => 'カスタム';

  @override
  String get sessionSshKeys => 'セッションの SSH 鍵';

  @override
  String get allManagerKeys => 'マネージャーのすべての鍵';

  @override
  String get browseFiles => 'ファイルを選択…';

  @override
  String get sshDirSessionAlreadyImported => 'すでにセッションにあります';

  @override
  String get languageSubtitle => 'インターフェースの言語';

  @override
  String get themeSubtitle => 'ダーク、ライト、またはシステムに従う';

  @override
  String get uiScaleSubtitle => 'インターフェース全体のスケール';

  @override
  String get terminalFontSizeSubtitle => 'ターミナル出力のフォントサイズ';

  @override
  String get scrollbackLinesSubtitle => 'ターミナル履歴バッファのサイズ';

  @override
  String get keepAliveIntervalSubtitle => 'SSH keep-alive パケット間の秒数 (0 = 無効)';

  @override
  String get sshTimeoutSubtitle => '接続タイムアウト (秒)';

  @override
  String get defaultPortSubtitle => '新しいセッションのデフォルトポート';

  @override
  String get parallelWorkersSubtitle => '並列 SFTP 転送ワーカー';

  @override
  String get maxHistorySubtitle => '履歴に保存される最大コマンド数';

  @override
  String get calculateFolderSizesSubtitle => 'サイドバーのフォルダー横に合計サイズを表示';

  @override
  String get checkForUpdatesOnStartupSubtitle => 'アプリ起動時に GitHub で新バージョンを確認';

  @override
  String get enableLoggingSubtitle => 'アプリのイベントをローテーションログファイルに記録';
}
