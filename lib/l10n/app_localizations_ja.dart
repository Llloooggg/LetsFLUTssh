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
  String get infoDialogProtectsHeader => '保護する';

  @override
  String get infoDialogDoesNotProtectHeader => '保護しない';

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
  String get cut => '切り取り';

  @override
  String get paste => '貼り付け';

  @override
  String get select => '選択';

  @override
  String get copyModeTapToStart => 'タップして選択開始位置を指定';

  @override
  String get copyModeExtending => 'ドラッグで選択範囲を拡大';

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
  String get exportWhatToExport => 'エクスポートする内容：';

  @override
  String get enterMasterPasswordPrompt => 'マスターパスワードを入力:';

  @override
  String get nextStep => '次へ';

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
  String get noResults => '結果なし';

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
  String get checkNow => '今すぐ確認';

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
  String get updateVerifying => '検証中…';

  @override
  String get downloadComplete => 'ダウンロード完了';

  @override
  String get installNow => '今すぐインストール';

  @override
  String get openReleasePage => 'リリースページを開く';

  @override
  String get couldNotOpenInstaller => 'インストーラーを開けませんでした';

  @override
  String get installerFailedOpenedReleasePage =>
      'インストーラーの起動に失敗しました。ブラウザーでリリースページを開きました';

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
  String importedSessions(int count) {
    return '$count 件のセッションをインポートしました';
  }

  @override
  String importFailed(String error) {
    return 'インポート失敗: $error';
  }

  @override
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '関連付け$count件を破棄しました（対象が存在しません）',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '破損したセッション$count件をスキップしました',
    );
    return '$_temp0';
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
  String get emptyFolder => '空のフォルダ';

  @override
  String get qrGenerationFailed => 'QRコード生成に失敗しました';

  @override
  String get scanWithCameraApp =>
      'LetsFLUTsshがインストールされている\nデバイスのカメラアプリでスキャンしてください。';

  @override
  String get noPasswordsInQr => 'このQRコードにパスワードや鍵は含まれていません';

  @override
  String get qrContainsCredentialsWarning =>
      'このQRコードには認証情報が含まれています。画面を他人に見せないでください。';

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
  String get clearHistory => '履歴をクリア';

  @override
  String get noTransfersYet => '転送履歴はまだありません';

  @override
  String get duplicateTab => 'タブを複製';

  @override
  String get duplicateTabShortcut => 'タブを複製 (Ctrl+\\)';

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
  String get passwordStrengthWeak => '弱い';

  @override
  String get passwordStrengthModerate => '普通';

  @override
  String get passwordStrengthStrong => '強い';

  @override
  String get passwordStrengthVeryStrong => '非常に強い';

  @override
  String get tierPlaintextLabel => 'プレーンテキスト';

  @override
  String get tierPlaintextSubtitle => '暗号化なし — ファイル権限のみ';

  @override
  String get tierKeychainLabel => 'キーチェーン';

  @override
  String tierKeychainSubtitle(String keychain) {
    return '鍵は $keychain に保管 — 起動時に自動でロック解除';
  }

  @override
  String get tierKeychainUnavailable => 'このインストールではOSキーチェーンが利用できません。';

  @override
  String get tierHardwareLabel => 'ハードウェア';

  @override
  String get tierParanoidLabel => 'マスターパスワード（Paranoid）';

  @override
  String get tierHardwareUnavailable => 'このインストールではハードウェアボールトを利用できません。';

  @override
  String get pinLabel => 'パスワード';

  @override
  String get l2UnlockTitle => 'パスワードが必要です';

  @override
  String get l2UnlockHint => '短いパスワードを入力して続行';

  @override
  String get l2WrongPassword => 'パスワードが違います';

  @override
  String get l3UnlockTitle => 'パスワードを入力';

  @override
  String get l3UnlockHint => 'パスワードでハードウェアに紐付いたボールトを解除';

  @override
  String get l3WrongPin => 'パスワードが違います';

  @override
  String tierCooldownHint(int seconds) {
    return '$seconds 秒後に再試行';
  }

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
  String get dataLocation => 'データの保存場所';

  @override
  String get dataStorageSection => 'ストレージ';

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
  String get errCannotAssignAddress => '要求されたアドレスを割り当てられません';

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
  String errSftpInitFailed(String error) {
    return 'SFTPの初期化に失敗しました: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'ダウンロードに失敗しました: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'システムのフォルダピッカーを利用できません。別の場所を試すか、アプリのストレージ権限を確認してください。';

  @override
  String get biometricUnlockPrompt => 'LetsFLUTssh のロックを解除';

  @override
  String get biometricUnlockTitle => '生体認証でロック解除';

  @override
  String get biometricUnlockSubtitle => 'パスワードを入力せず、デバイスの生体認証でロック解除できます。';

  @override
  String get biometricEnableFailed => '生体認証によるロック解除を有効にできませんでした。';

  @override
  String get biometricUnlockFailed => '生体認証によるロック解除に失敗しました。マスターパスワードを入力してください。';

  @override
  String get biometricUnlockCancelled => '生体認証によるロック解除がキャンセルされました。';

  @override
  String get biometricNotEnrolled => 'このデバイスには生体情報が登録されていません。';

  @override
  String get biometricSensorNotAvailable => 'このデバイスには生体センサーがありません。';

  @override
  String get biometricSystemServiceMissing =>
      '指紋サービス (fprintd) がインストールされていません。README → Installation を参照してください。';

  @override
  String get currentPasswordIncorrect => '現在のパスワードが正しくありません';

  @override
  String get wrongPassword => 'パスワードが間違っています';

  @override
  String get lockScreenTitle => 'LetsFLUTssh はロックされています';

  @override
  String get lockScreenSubtitle => '続行するにはマスターパスワードを入力するか、生体認証を使用してください。';

  @override
  String get unlock => 'ロック解除';

  @override
  String get autoLockTitle => '操作がないときに自動ロック';

  @override
  String get autoLockSubtitle =>
      'この時間操作がないと UI をロックします。ロックのたびに DB 鍵を消去し、暗号化ストアを閉じます。アクティブなセッションはセッションごとの認証情報キャッシュで接続を維持し、セッション終了時にそのキャッシュはクリアされます。';

  @override
  String get autoLockOff => 'オフ';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes 分',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'アップデートを拒否しました：ダウンロードしたファイルが、アプリに埋め込まれたリリース鍵で署名されていません。ダウンロード中に改ざんされたか、このリリースがこのインストールに対応していない可能性があります。インストールしないでください — 公式リリースページから手動で再インストールしてください。';

  @override
  String get errReleaseManifestUnavailable =>
      'リリースの manifest を取得できませんでした。ネットワークの問題か、リリースが公開処理中の可能性があります。数分後にもう一度お試しください。';

  @override
  String get updateSecurityWarningTitle => '更新の検証に失敗しました';

  @override
  String get updateReinstallAction => 'リリースページを開く';

  @override
  String get errLfsNotArchive => '選択したファイルは LetsFLUTssh のアーカイブではありません。';

  @override
  String get errLfsDecryptFailed => 'マスターパスワードが間違っているか、.lfs アーカイブが破損しています';

  @override
  String get errLfsArchiveTruncated =>
      'アーカイブが不完全です。再ダウンロードするか、元のデバイスから再エクスポートしてください。';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'アーカイブが大きすぎます ($sizeMb MB)。上限は $limitMb MB です。メモリ保護のため、復号前に中止しました。';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'known_hosts エントリが大きすぎます ($sizeMb MB)。上限は $limitMb MB です。インポートの応答性を保つため中止しました。';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'インポート失敗 — データはインポート前の状態に復元されました。($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'アーカイブはスキーマ v$found を使用していますが、このビルドは v$supported までしか対応していません。インポートするにはアプリを更新してください。';
  }

  @override
  String get progressReadingArchive => 'アーカイブを読み込み中…';

  @override
  String get progressDecrypting => '復号中…';

  @override
  String get progressParsingArchive => 'アーカイブを解析中…';

  @override
  String get progressImportingSessions => 'セッションをインポート中';

  @override
  String get progressImportingFolders => 'フォルダをインポート中';

  @override
  String get progressImportingManagerKeys => 'SSH キーをインポート中';

  @override
  String get progressImportingTags => 'タグをインポート中';

  @override
  String get progressImportingSnippets => 'スニペットをインポート中';

  @override
  String get progressApplyingConfig => '設定を適用中…';

  @override
  String get progressImportingKnownHosts => 'known_hosts をインポート中…';

  @override
  String get progressCollectingData => 'データを収集中…';

  @override
  String get progressEncrypting => '暗号化中…';

  @override
  String get progressWritingArchive => 'アーカイブを書き込み中…';

  @override
  String get progressWorking => '処理中…';

  @override
  String get importFromLink => 'QR リンクからインポート';

  @override
  String get importFromLinkSubtitle =>
      '別の端末からコピーした letsflutssh:// ディープリンクを貼り付け';

  @override
  String get pasteImportLinkTitle => 'インポートリンクを貼り付け';

  @override
  String get pasteImportLinkDescription =>
      '別の端末で生成された letsflutssh://import?d=… リンク（または生ペイロード）を貼り付けてください。カメラは不要です。';

  @override
  String get pasteFromClipboard => 'クリップボードから貼り付け';

  @override
  String get invalidImportLink => 'リンクに有効な LetsFLUTssh ペイロードが含まれていません';

  @override
  String get importAction => 'インポート';

  @override
  String get saveSessionToAssignTags => 'タグを割り当てるには、まずセッションを保存してください';

  @override
  String get noTagsAssigned => 'タグが割り当てられていません';

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
  String get fileConflictTitle => 'ファイルは既に存在します';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '「$fileName」は $targetDir に既に存在します。どうしますか？';
  }

  @override
  String get fileConflictSkip => 'スキップ';

  @override
  String get fileConflictKeepBoth => '両方を保持';

  @override
  String get fileConflictReplace => '置き換え';

  @override
  String get fileConflictApplyAll => '残りすべてに適用';

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
  String get clearedAllHosts => 'すべての既知のホストを削除しました';

  @override
  String removedHost(String host) {
    return '$host を削除しました';
  }

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
  String get addKey => 'キーを追加';

  @override
  String get filePickerUnavailable => 'このシステムではファイルピッカーを利用できません';

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
  String get enterMasterPassword => '保存された認証情報にアクセスするにはマスターパスワードを入力してください。';

  @override
  String get wrongMasterPassword => 'パスワードが正しくありません。もう一度お試しください。';

  @override
  String get newPassword => '新しいパスワード';

  @override
  String get currentPassword => '現在のパスワード';

  @override
  String get forgotPassword => 'パスワードを忘れましたか？';

  @override
  String get credentialsReset => '保存された認証情報がすべて削除されました';

  @override
  String get migrationToast => 'ストレージを最新の形式にアップグレードしました';

  @override
  String get dbCorruptTitle => 'データベースを開けません';

  @override
  String get dbCorruptBody => 'ディスク上のデータを開けません。別の認証情報を試すか、リセットして最初からやり直してください。';

  @override
  String get dbCorruptWarning =>
      'リセットすると、暗号化データベースとすべてのセキュリティ関連ファイルが完全に削除されます。データは復元されません。';

  @override
  String get dbCorruptTryOther => '別の認証情報で試す';

  @override
  String get dbCorruptResetContinue => 'リセットして新規セットアップ';

  @override
  String get dbCorruptExit => 'LetsFLUTssh を終了';

  @override
  String get tierResetTitle => 'セキュリティリセットが必要です';

  @override
  String get tierResetBody =>
      'このインストールには、以前のバージョンの LetsFLUTssh（別の階層モデルを使用）のセキュリティデータが残っています。新しいモデルは破壊的変更のため、自動マイグレーションはありません。続行するには、このインストールに保存されたセッション・認証情報・SSH 鍵・既知のホストをすべて消去し、初回起動のセットアップウィザードを最初から実行する必要があります。';

  @override
  String get tierResetWarning =>
      '「リセットして新規セットアップ」を選択すると、暗号化データベースとすべてのセキュリティ関連ファイルが完全に削除されます。データを復元する必要がある場合は、今アプリを終了し、まず以前のバージョンのLetsFLUTsshを再インストールしてエクスポートしてください。';

  @override
  String get tierResetResetContinue => 'リセットして新規セットアップ';

  @override
  String get tierResetExit => 'LetsFLUTsshを終了';

  @override
  String get derivingKey => '暗号化キーを生成中...';

  @override
  String get securitySetupTitle => 'セキュリティ設定';

  @override
  String get keychainAvailable => '利用可能';

  @override
  String get changeSecurityTierConfirm =>
      '新しい階層でデータベースを再暗号化中。中断できません — 完了するまでアプリを開いたままにしてください。';

  @override
  String get changeSecurityTierDone => 'セキュリティ階層が変更されました';

  @override
  String get changeSecurityTierFailed => 'セキュリティ階層を変更できませんでした';

  @override
  String get firstLaunchSecurityTitle => 'セキュアストレージが有効になりました';

  @override
  String get firstLaunchSecurityBody =>
      'データは OS キーチェーンに保管された鍵で暗号化されます。このデバイスでのロック解除は自動です。';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'このデバイスではハードウェア保護ストレージが利用できます。TPM / Secure Enclave 連携を使うには、設定 → セキュリティからアップグレードしてください。';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'このデバイスではハードウェア保護ストレージを利用できません。';

  @override
  String get firstLaunchSecurityOpenSettings => '設定を開く';

  @override
  String get wizardReducedBanner =>
      'このインストールでは OS キーチェーンに到達できません。暗号化なし (T0) とマスターパスワード (Paranoid) のいずれかを選択してください。Keychain 階層を有効にするには、gnome-keyring、kwallet、またはその他の libsecret プロバイダをインストールしてください。';

  @override
  String get tierBlockProtectsEmpty => 'この階層では何も保護しません。';

  @override
  String get tierBlockDoesNotProtectEmpty => '未カバーの脅威はありません。';

  @override
  String get tierBadgeCurrent => '現在';

  @override
  String get securitySetupEnable => '有効化';

  @override
  String get securitySetupApply => '適用';

  @override
  String get hwProbeLinuxDeviceMissing =>
      '/dev/tpmrm0 に TPM が見つかりません。マシンが対応していれば BIOS で fTPM / PTT を有効にしてください。そうでなければ、このデバイスではハードウェア階層を使用できません。';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools がインストールされていません。ハードウェア階層を有効にするには `sudo apt install tpm2-tools`（またはディストリビューションの同等コマンド）を実行してください。';

  @override
  String get hwProbeLinuxProbeFailed =>
      'ハードウェア階層のプローブに失敗しました。/dev/tpmrm0 の権限と udev ルールを確認してください — 詳細はログを参照してください。';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'TPM 2.0 が検出されませんでした。UEFI ファームウェアで fTPM / PTT を有効にしてください。対応していないデバイスではハードウェア階層は使用できず、アプリはソフトウェアベースの認証情報ストアにフォールバックします。';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Microsoft Platform Crypto Provider も Software Key Storage Provider にも到達できません — Windows 暗号サブシステムの破損、または CNG をブロックするグループポリシーが考えられます。イベントビューアー → アプリケーションとサービスログを確認してください。';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'この Mac には Secure Enclave がありません（T1 / T2 セキュリティチップ非搭載の 2017 年以前の Intel Mac）。ハードウェア階層は利用できません。マスターパスワードを使用してください。';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'この Mac にログインパスワードが設定されていません。Secure Enclave キー作成に必要です — システム設定 → Touch ID とパスワード（またはログインパスワード）で設定してください。';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave がアプリの署名 ID を拒否しました (-34018)。リリースに同梱の `macos-resign.sh` スクリプトを実行してこのインストールに安定した自己署名 ID を付与し、アプリを再起動してください。';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'デバイスのパスコードが設定されていません。Secure Enclave キー作成に必要です — 設定 → Face ID とパスコード（または Touch ID とパスコード）で設定してください。';

  @override
  String get hwProbeIosSimulator =>
      'iOS シミュレーターで実行中で、Secure Enclave がありません。ハードウェア階層は物理 iOS デバイスでのみ利用可能です。';

  @override
  String get hwProbeAndroidApiTooLow =>
      'ハードウェア階層には Android 9 以降が必要です（StrongBox と鍵ごとの enrolment 無効化は古いバージョンでは信頼性に欠けます）。';

  @override
  String get hwProbeAndroidBiometricNone =>
      'このデバイスには生体認証ハードウェア（指紋または顔）がありません。マスターパスワードを使用してください。';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      '生体認証が登録されていません。設定 → セキュリティとプライバシー → 生体認証で指紋または顔を追加してから、ハードウェア階層を再度有効にしてください。';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      '生体認証ハードウェアが一時的に使用できません（失敗試行後のロックアウトまたは保留中のセキュリティ更新）。数分後に再試行してください。';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'Android Keystore がこのデバイスビルドでハードウェアキーのバックを拒否しました（StrongBox 非対応、カスタム ROM、またはドライバーの不具合）。ハードウェア層は利用できません。';

  @override
  String get securityRecheck => '階層サポートを再確認';

  @override
  String get securityRecheckUpdated => '階層サポートが更新されました — 上のカードを確認';

  @override
  String get securityRecheckUnchanged => '階層サポートに変更はありません';

  @override
  String get securityMacosEnableSecureTiers => 'この Mac でセキュア階層をロック解除';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'アプリを個人証明書で再署名し、キーチェーン (T1) と Secure Enclave (T2) が更新後も動作するようにします';

  @override
  String get securityMacosEnableSecureTiersPrompt => 'macOS は一度だけパスワードを要求します';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'セキュア階層がロック解除されました — T1 と T2 が利用可能です';

  @override
  String get securityMacosEnableSecureTiersFailed => 'セキュア階層のロック解除に失敗しました';

  @override
  String get securityMacosOfferTitle => 'キーチェーン + Secure Enclave を有効化?';

  @override
  String get securityMacosOfferBody =>
      'macOS は暗号化ストレージをアプリの署名 ID に紐付けます。安定した証明書がないと、キーチェーン (T1) と Secure Enclave (T2) はアクセスを拒否します。この Mac 上に個人の自己署名証明書を作成し、アプリを再署名できます — アップデートは継続動作し、秘密情報はリリース間で保持されます。macOS は新しい証明書を信頼するために一度だけログインパスワードを要求します。';

  @override
  String get securityMacosOfferAccept => '有効化';

  @override
  String get securityMacosOfferDecline => 'スキップ — T0 または Paranoid を選択';

  @override
  String get securityMacosRemoveIdentity => '署名 ID を削除';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      '個人証明書を削除します。T1 / T2 データはこれに紐付いています — まず T0 または Paranoid に切り替えてから削除してください。';

  @override
  String get securityMacosRemoveIdentityConfirmTitle => '署名 ID を削除しますか?';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'ログインキーチェーンから個人証明書を削除します。T1 / T2 に保存された秘密は読めなくなります。ウィザードが開き、削除前に T0 (平文) または Paranoid (マスターパスワード) に移行できます。';

  @override
  String get securityMacosRemoveIdentitySuccess => '署名 ID を削除しました';

  @override
  String get securityMacosRemoveIdentityFailed => '署名 ID の削除に失敗しました';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus は動作していますが、secret-service デーモンが実行されていません。gnome-keyring（`sudo apt install gnome-keyring`）または KWalletManager をインストールし、ログイン時に起動するようにしてください。';

  @override
  String get keyringProbeFailed =>
      'このデバイスでは OS キーチェーンに到達できません。プラットフォーム固有のエラーはログを参照してください。アプリはマスターパスワードにフォールバックします。';

  @override
  String get snippets => 'スニペット';

  @override
  String get snippetsSubtitle => '再利用可能なコマンドスニペットを管理';

  @override
  String get noSnippets => 'スニペットはまだありません';

  @override
  String get addSnippet => 'スニペットを追加';

  @override
  String get editSnippet => 'スニペットを編集';

  @override
  String get deleteSnippet => 'スニペットを削除';

  @override
  String deleteSnippetConfirm(String title) {
    return 'スニペット「$title」を削除しますか？';
  }

  @override
  String get snippetTitle => 'タイトル';

  @override
  String get snippetTitleHint => '例: デプロイ、サービス再起動';

  @override
  String get snippetCommand => 'コマンド';

  @override
  String get snippetCommandHint => '例: sudo systemctl restart nginx';

  @override
  String get snippetDescription => '説明（任意）';

  @override
  String get snippetDescriptionHint => 'このコマンドの動作は？';

  @override
  String get snippetSaved => 'スニペットを保存しました';

  @override
  String snippetDeleted(String title) {
    return 'スニペット「$title」を削除しました';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のスニペット',
      zero: 'スニペットなし',
    );
    return '$_temp0';
  }

  @override
  String get pinToSession => 'このセッションに固定';

  @override
  String get unpinFromSession => 'このセッションから外す';

  @override
  String get pinnedSnippets => '固定済み';

  @override
  String get allSnippets => 'すべて';

  @override
  String get commandCopied => 'コマンドをコピーしました';

  @override
  String get snippetFillTitle => 'スニペットのパラメーターを入力';

  @override
  String get snippetFillSubmit => '実行';

  @override
  String get snippetPreview => 'プレビュー';

  @override
  String get broadcastSetDriver => 'このペインから配信';

  @override
  String get broadcastClearDriver => 'このペインからの配信を停止';

  @override
  String get broadcastAddReceiver => 'ここで受信';

  @override
  String get broadcastRemoveReceiver => '受信を停止';

  @override
  String get broadcastClearAll => 'すべての配信を停止';

  @override
  String get broadcastPasteTitle => '貼り付けをすべてのペインに送信?';

  @override
  String broadcastPasteBody(int chars, int count) {
    return '$chars 文字を他の $count ペインに送信します。';
  }

  @override
  String get broadcastPasteSend => '送信';

  @override
  String get portForwarding => '転送';

  @override
  String get portForwardingEmpty => 'ルールはまだありません';

  @override
  String get addForwardRule => 'ルールを追加';

  @override
  String get editForwardRule => 'ルールを編集';

  @override
  String get deleteForwardRule => 'ルールを削除';

  @override
  String get localForward => 'ローカル (-L)';

  @override
  String get remoteForward => 'リモート (-R)';

  @override
  String get dynamicForward => '動的 (-D)';

  @override
  String get forwardKind => '種類';

  @override
  String get bindAddress => 'バインドアドレス';

  @override
  String get bindPort => 'バインドポート';

  @override
  String get targetHost => 'ターゲットホスト';

  @override
  String get targetPort => 'ターゲットポート';

  @override
  String get forwardDescription => '説明（任意）';

  @override
  String get forwardEnabled => '有効';

  @override
  String get forwardBindWildcardWarning =>
      '0.0.0.0 にバインドすると全インターフェースに公開されます — 通常は 127.0.0.1 を使用してください。';

  @override
  String get forwardOnlyLocalSupported =>
      'ローカル (-L)、リモート (-R)、動的 SOCKS5 (-D) 転送すべて動作します。';

  @override
  String get forwardKindLocalHelp =>
      'Local: open a port on this device that tunnels to a target reachable from the SSH server. Useful for accessing remote databases or admin UIs at localhost:bindPort.';

  @override
  String get forwardKindRemoteHelp =>
      'Remote: ask the SSH server to open a port that tunnels back to a target reachable from this device. Useful for sharing a local dev server with a remote host (server may need GatewayPorts yes for non-loopback binds).';

  @override
  String get forwardKindDynamicHelp =>
      'Dynamic: a SOCKS5 proxy on this device that routes every connection through the SSH server. Point your browser or curl at localhost:bindPort to send all traffic over SSH.';

  @override
  String get forwardExample => 'Example';

  @override
  String get forwardLocalExample =>
      'ssh -L 8080:db.internal:5432 → access remote DB via localhost:8080';

  @override
  String get forwardRemoteExample =>
      'ssh -R 9000:localhost:3000 → expose your dev server at server\'s port 9000';

  @override
  String get forwardDynamicExample =>
      'ssh -D 1080 → set browser SOCKS5 to localhost:1080';

  @override
  String get proxyJump => '経由先';

  @override
  String get proxyJumpNone => '直接接続';

  @override
  String get proxyJumpSavedSession => '保存済みセッション';

  @override
  String get proxyJumpCustom => 'カスタム (user@host:port)';

  @override
  String get proxyJumpCustomNote =>
      'カスタム経由はこのセッションの認証情報を使用します。別の踏み台認証が必要な場合は、踏み台を独立したセッションとして保存してください。';

  @override
  String get errProxyJumpCycle => 'プロキシチェーンがループしています。';

  @override
  String errProxyJumpDepth(int max) {
    return 'プロキシチェーンが深すぎます (最大 $max ホップ)。';
  }

  @override
  String errProxyJumpBastionFailed(String label) {
    return '踏み台 $label に接続できませんでした。';
  }

  @override
  String viaSessionLabel(String label) {
    return '$label 経由';
  }

  @override
  String get recordSession => 'セッションを記録';

  @override
  String get recordSessionHelp =>
      'このセッションの端末出力をディスクに保存します。マスターパスワードまたはハードウェアキー有効時は保存時に暗号化されます。';

  @override
  String get tags => 'タグ';

  @override
  String get tagsSubtitle => 'セッションとフォルダをカラータグで整理';

  @override
  String get noTags => 'タグはまだありません';

  @override
  String get addTag => 'タグを追加';

  @override
  String get deleteTag => 'タグを削除';

  @override
  String deleteTagConfirm(String name) {
    return 'タグ「$name」を削除しますか？すべてのセッションとフォルダから削除されます。';
  }

  @override
  String get tagName => 'タグ名';

  @override
  String get tagNameHint => '例: Production、Staging';

  @override
  String get tagColor => '色';

  @override
  String get tagCreated => 'タグを作成しました';

  @override
  String tagDeleted(String name) {
    return 'タグ「$name」を削除しました';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のタグ',
      zero: 'タグなし',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'タグを管理';

  @override
  String get editTags => 'タグを編集';

  @override
  String get fullBackup => 'フルバックアップ';

  @override
  String get sessionsOnly => 'セッション';

  @override
  String get presetFullImport => '完全インポート';

  @override
  String get presetSelective => '選択的';

  @override
  String get presetCustom => 'カスタム';

  @override
  String get sessionSshKeys => 'セッション鍵 (マネージャー)';

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

  @override
  String get exportWithoutPassword => 'パスワードなしでエクスポートしますか？';

  @override
  String get exportWithoutPasswordWarning =>
      'アーカイブは暗号化されません。ファイルにアクセスできる人は誰でも、パスワードや秘密鍵を含むすべてのデータを読み取ることができます。';

  @override
  String get continueWithoutPassword => 'パスワードなしで続行';

  @override
  String get threatColdDiskTheft => '電源オフ時のディスク窃取';

  @override
  String get threatColdDiskTheftDescription =>
      '電源を切った端末からドライブを取り外して別のコンピューターで読み出す、あるいはホームディレクトリへアクセスできる者がデータベースファイルを複製するケース。';

  @override
  String get threatKeyringFileTheft => 'keyring / keychain ファイルの窃取';

  @override
  String get threatKeyringFileTheftDescription =>
      '攻撃者がプラットフォームの認証情報ストアファイル（libsecret keyring、Windows Credential Manager、macOS ログインキーチェーン）をディスクから直接読み取り、そこからラップされたデータベース鍵を取り出すケース。ハードウェア階層ではパスワードの有無に関係なくこの攻撃を防げます。チップが鍵マテリアルの書き出しを拒否するためです。一方キーチェーン階層ではパスワードの併用が必須です。そうしないと盗まれたファイルは OS のログインパスワードだけで復号できてしまいます。';

  @override
  String get modifierOnlyWithPassword => 'パスワード必須';

  @override
  String get threatBystanderUnlockedMachine => 'ロック解除済み端末のそばにいる第三者';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'あなたが離席している間に、すでにロック解除済みのコンピューターへ誰かが近づき、このアプリを開く状況。';

  @override
  String get threatLiveRamForensicsLocked => 'ロック状態の端末に対する RAM フォレンジック';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      '攻撃者が RAM を凍結したり DMA で取得したりして、アプリがロック中でもスナップショットから残存する鍵素材を引き出します。';

  @override
  String get threatOsKernelOrKeychainBreach => 'OS カーネルまたはキーチェーンの侵害';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'カーネルの脆弱性、キーチェーンの漏洩、あるいはハードウェアセキュリティチップのバックドア。OS そのものが信頼できる基盤ではなく、攻撃者側に回ってしまう状況です。';

  @override
  String get threatOfflineBruteForce => '弱いパスワードへのオフライン総当たり';

  @override
  String get threatOfflineBruteForceDescription =>
      'ラップされた鍵や封印済み blob のコピーを入手した攻撃者が、レート制限を一切受けずに自分のペースで総当たりを行える状況。';

  @override
  String get legendProtects => '保護あり';

  @override
  String get legendDoesNotProtect => '保護なし';

  @override
  String get colT0 => 'T0 平文';

  @override
  String get colT1 => 'T1 キーチェーン';

  @override
  String get colT1Password => 'T1 + パスワード';

  @override
  String get colT1PasswordBiometric => 'T1 + パスワード + 生体認証';

  @override
  String get colT2 => 'T2 ハードウェア';

  @override
  String get colT2Password => 'T2 + パスワード';

  @override
  String get colT2PasswordBiometric => 'T2 + パスワード + 生体認証';

  @override
  String get colParanoid => 'パラノイド';

  @override
  String get securityComparisonTableThreatColumn => '脅威';

  @override
  String get compareAllTiers => '全階層を比較';

  @override
  String get resetAllDataTitle => 'すべてのデータをリセット';

  @override
  String get resetAllDataSubtitle =>
      'すべてのセッション、鍵、設定、セキュリティアーティファクトを削除します。キーチェーンのエントリとハードウェアボールトのスロットもクリアします。';

  @override
  String get resetAllDataConfirmTitle => 'すべてのデータをリセットしますか？';

  @override
  String get resetAllDataConfirmBody =>
      'すべてのセッション、SSH 鍵、known hosts、スニペット、タグ、設定、およびすべてのセキュリティアーティファクト（キーチェーンエントリ、ハードウェアボールトのデータ、生体認証オーバーレイ）が完全に削除されます。この操作は取り消せません。';

  @override
  String get resetAllDataConfirmAction => 'すべてリセット';

  @override
  String get resetAllDataInProgress => 'リセット中…';

  @override
  String get resetAllDataDone => 'すべてのデータをリセットしました';

  @override
  String get resetAllDataFailed => 'リセットに失敗しました';

  @override
  String get autoLockRequiresPassword => '自動ロックにはアクティブな階層にパスワードが必要です。';

  @override
  String get recommendedBadge => '推奨';

  @override
  String get tierHardwareSubtitleHonest =>
      '上級: ハードウェアに紐づく鍵。このデバイスのチップが失われたり交換されたりすると、データは復元できません。';

  @override
  String get tierParanoidSubtitleHonest =>
      '代替: マスターパスワードを使用し、OS を信頼しません。OS の侵害から保護しますが、T1/T2 と比べてランタイム保護は向上しません。';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'runtime の脅威（同一ユーザーの malware、稼働中プロセスのメモリダンプ）は、すべての階層で ✗ と表示されます。これらは階層選択に関係なく適用される別途の緩和機能によって対処されます。';

  @override
  String get currentTierBadge => '現在';

  @override
  String get paranoidAlternativeHeader => '代替';

  @override
  String get modifierPasswordLabel => 'パスワード';

  @override
  String get modifierPasswordSubtitle => 'ボールトを復号する前に入力する秘密のゲート。';

  @override
  String get modifierBiometricLabel => '生体認証ショートカット';

  @override
  String get modifierBiometricSubtitle =>
      'パスワードを入力する代わりに、生体認証で保護された OS のスロットから取り出します。';

  @override
  String get biometricRequiresPassword =>
      '先にパスワードを有効にしてください — 生体認証は入力のショートカットです。';

  @override
  String get biometricRequiresActiveTier => '生体認証ロック解除を有効にするには、先にこの階層を選択してください';

  @override
  String get autoLockRequiresActiveTier => '自動ロックを設定するには、先にこの階層を選択してください';

  @override
  String get biometricForbiddenParanoid => 'Paranoid は設計上、生体認証を許可しません。';

  @override
  String get fprintdNotAvailable => 'fprintd がインストールされていないか、指紋が登録されていません。';

  @override
  String get linuxTpmWithoutPasswordNote =>
      'パスワードなしの TPM は分離を提供するだけで、認証にはなりません。このアプリを実行できる人なら誰でもデータを復号できます。';

  @override
  String get paranoidMasterPasswordNote =>
      '長いパスフレーズを強く推奨します — Argon2id は総当たり攻撃を遅らせるだけで、阻止はできません。';

  @override
  String get plaintextWarningTitle => '平文：暗号化なし';

  @override
  String get plaintextWarningBody =>
      'セッション、鍵、known hosts は暗号化されずに保存されます。このコンピュータのファイルシステムにアクセスできる人なら誰でも読み取れます。';

  @override
  String get plaintextAcknowledge => 'データが暗号化されないことを理解しました';

  @override
  String get plaintextAcknowledgeRequired => '続行する前に理解したことを確認してください。';

  @override
  String get passwordLabel => 'パスワード';

  @override
  String get masterPasswordLabel => 'マスターパスワード';
}
