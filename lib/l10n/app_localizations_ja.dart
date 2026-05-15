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
  String get copyModeSetAnchor => 'アンカーを設定';

  @override
  String get copyModeCopySelection => '選択をコピー';

  @override
  String get required => '必須';

  @override
  String get errFillRequiredFields => '* の付いた必須項目を入力してください';

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
  String get sectionAuthentication => '認証';

  @override
  String get sectionAdvanced => '詳細';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ポート転送ルール $countString 件',
      zero: 'ポート転送ルールなし',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => '管理…';

  @override
  String get authMethodAgent => 'システムの ssh-agent を使う';

  @override
  String get authMethodAgentSubtitle =>
      '\$SSH_AUTH_SOCK (Linux/macOS) または OpenSSH named pipe (Windows) 経由で認証します。gpg-agent、Pageant、システムの ssh-agent に key を置いている場合に便利です。';

  @override
  String get authMethodAgentMobileUnsupported =>
      'モバイルでは利用できません — システム ssh-agent の endpoint はデスクトップ専用です。';

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
  String get savedTypeToChange => '保存済み — 変更するには入力';

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
  String a11yConnectingTo(String host) {
    return '$host に接続中';
  }

  @override
  String a11yConnectedTo(String host) {
    return '$host に接続しました';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return '$host から切断しました';
  }

  @override
  String a11yConnectionFailed(String host) {
    return '$host への接続に失敗しました';
  }

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
  String get qrTooManyForSingleCode =>
      '1つのQRコードには多すぎます。選択を減らすか、.lfsエクスポートを使用してください。';

  @override
  String get qrTooLarge => 'データが大きすぎます — 選択を減らすか、.lfsファイルエクスポートを使用してください。';

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
  String get archivedLog => 'アーカイブログ';

  @override
  String get loggingLevel => 'ログレベル';

  @override
  String get loggingLevelSubtitleInfo => '通常エントリ + 警告 + エラー';

  @override
  String get loggingLevelSubtitleWarn => '降格パスとエラーのみ';

  @override
  String get loggingLevelSubtitleError => 'エラーのみ';

  @override
  String get loggingLevelSubtitleOff => '通常ログは書き込まれません';

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
  String get sshCertificate => '証明書';

  @override
  String get certImport => '証明書をインポート';

  @override
  String get certImportPickerTitle => 'OpenSSH 証明書ファイルを選択';

  @override
  String get certValidFrom => '有効開始';

  @override
  String get certValidTo => '有効期限';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => 'この証明書は間もなく期限切れになります。';

  @override
  String get certExpired => '期限切れ';

  @override
  String get certRemove => '証明書を削除';

  @override
  String get certRemoveConfirmTitle => '証明書を削除しますか？';

  @override
  String get certRemoveConfirmBody => '削除すると、次回接続時は通常の公開鍵認証にフォールバックします。';

  @override
  String errCertParse(String detail) {
    return '証明書をパースできませんでした：$detail';
  }

  @override
  String get errCertPairFingerprintMismatch => 'この証明書は選択中の鍵とペアになっていません。';

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
  String get passphrase => 'パスフレーズ';

  @override
  String get enterMasterPassword => '保存された認証情報にアクセスするにはマスターパスワードを入力してください。';

  @override
  String get wrongMasterPassword => 'パスワードが正しくありません。もう一度お試しください。';

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
  String get snippetTokensHint => 'タップしてプレースホルダーを挿入。実行時にアクティブセッションの値で置換されます:';

  @override
  String get snippetCustomTokensHint => '二重波括弧のその他の項目は、実行時に値を尋ねます。';

  @override
  String get snippetFillTitle => 'スニペットのパラメーターを入力';

  @override
  String get snippetFillSubmit => '実行';

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
  String get localForward => 'ローカル';

  @override
  String get remoteForward => 'リモート';

  @override
  String get dynamicForward => '動的';

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
  String get forwardKindLocalHelp =>
      'ローカル: このデバイスでポートを開き、SSH サーバーから到達可能なターゲットへトンネルします。リモート DB や管理 UI に localhost:bindPort 経由でアクセスするのに便利。';

  @override
  String get forwardKindRemoteHelp =>
      'リモート: SSH サーバーにポートを開いてもらい、このデバイスから到達可能なターゲットへ戻すトンネルです。ローカル開発サーバーをリモートホストと共有するのに便利 (サーバーは非ループバックバインドに GatewayPorts yes が必要な場合あり)。';

  @override
  String get forwardKindDynamicHelp =>
      '動的: このデバイス上の SOCKS5 プロキシで、すべての接続を SSH サーバー経由でルーティングします。ブラウザや curl を localhost:bindPort に向けると、すべてのトラフィックが SSH 経由で送信されます。';

  @override
  String get proxyJump => '経由先';

  @override
  String get proxyJumpNone => '直接接続';

  @override
  String get proxyJumpSavedSession => '保存済みセッション';

  @override
  String get proxyJumpCustom => 'カスタム';

  @override
  String get proxyJumpCustomNote =>
      'カスタム経由はこのセッションの認証情報を使用します。別の踏み台認証が必要な場合は、踏み台を独立したセッションとして保存してください。';

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
  String get recordingsBrowserTitle => '録画';

  @override
  String get recordingsBrowserSubtitle => '録画したセッションの閲覧、再生、削除';

  @override
  String get recordingsEmpty => '録画はまだありません';

  @override
  String get playRecording => '再生';

  @override
  String get deleteRecording => '削除';

  @override
  String get recordingPlaybackTitle => '録画を再生';

  @override
  String get recordingSpeed => '速度';

  @override
  String get recordingSpeedInstant => '即時';

  @override
  String get recordingScrubTooltipUnavailable =>
      'スクラブバーには sidecar index が必要です。このビルド以前の録画にはありません。新しい録画はシークできます。';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

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
  String resetAllDataConfirmTypePrompt(String phrase) {
    return '確認のため、下に $phrase と入力してください:';
  }

  @override
  String get resetAllDataInProgress => 'リセット中…';

  @override
  String get resetAllDataDone => 'すべてのデータをリセットしました';

  @override
  String get resetAllDataFailed => 'リセットに失敗しました';

  @override
  String get recordingsTitle => '録画';

  @override
  String get recordingsStorageUsedLabel => '使用中';

  @override
  String get recordingsCapLabel => '上限';

  @override
  String get recordingsCapHint =>
      'recordings/ フォルダのハードリミット。超過時は最も古い録画から削除されます。録画中のファイルは削除されません。';

  @override
  String get recordingsClearAllAction => 'すべての録画を削除';

  @override
  String get recordingsClearAllConfirmTitle => 'すべての録画を削除しますか？';

  @override
  String get recordingsClearAllConfirmBody =>
      '<app>/recordings/ 配下の録画セッションがすべて削除されます。録画中のファイル（ある場合）は残ります。この操作は取り消せません。';

  @override
  String recordingsClearAllResult(int count) {
    return '$count 件の録画を削除しました';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return '上限を更新しました。$bytes を解放しました。';
  }

  @override
  String get recordingsCapChangedNoChange => '上限を更新しました。削除対象はありません。';

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
  String get autoLockRequiresPassword => '自動ロックにはアクティブな階層にパスワードが必要です。';

  @override
  String get recommendedBadge => '推奨';

  @override
  String get tierHardwareSubtitleHonest =>
      '上級: ハードウェアに紐づく鍵、常にパスワード保護されます。このデバイスのチップが失われたり交換されたりすると、データは復元できません。';

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
  String get modifierPasswordRequired => '必須 — Hardware ティアは常にパスワード保護されます。';

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
  String get t2RequiresPasswordTitle => 'Hardware ティアにマスターパスワードを設定';

  @override
  String get t2RequiresPasswordBody =>
      'Hardware ティアは modifier としてパスワードが必要です。バイオメトリクスはその上のオプショナル shortcut です。';

  @override
  String get t2MigrationPromptTitle => 'Hardware ティアにパスワードが必要';

  @override
  String get t2MigrationPromptBody =>
      '既存のパスワードなし Hardware インストールは続行のため今すぐ設定する必要があります。';

  @override
  String get t2MigrationContinue => '続行';

  @override
  String get t2MigrationSetPasswordTitle => 'Hardware ティアを維持するためパスワードを設定';

  @override
  String get t2MigrationSetPasswordBody =>
      '新しいマスターパスワードを入力してください。hardware モジュール内で既に sealed された DB key はこのパスワードで re-seal されます — セッションと key はそのまま残ります。';

  @override
  String get t2MigrationWipeAndRestart => 'Wipe してやり直す';

  @override
  String get t2MigrationResealFailed =>
      'Hardware ティアの re-seal が失敗 — 別のパスワードを選ぶか wipe してください。';

  @override
  String get biometricOverlayEnable => 'Hardware ティアでバイオメトリクス shortcut を有効化';

  @override
  String get biometricOverlayEnableSubtitle =>
      'バイオメトリクス保護された OS スロットからパスワードを解放します。';

  @override
  String get biometricOverlayUnavailable =>
      'バイオメトリクス overlay はこのプラットフォームではまだ利用できません。';

  @override
  String get biometricOverlayRequiresPassword =>
      '先に Hardware ティアのパスワードを設定してください。';

  @override
  String get t2UnlockTitle => 'マスターパスワードでアンロック';

  @override
  String get t2UnlockSubtitle => 'hardware-bound 鍵はパスワードで保護されています。';

  @override
  String get t2UnlockUseBiometricButton => 'バイオメトリクスを使う';

  @override
  String get t2PasswordChanged => 'Hardware ティアのパスワードを更新しました。';

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

  @override
  String get globalErrorTitle => 'Unexpected Error';

  @override
  String get globalErrorBody =>
      'An unexpected error occurred. The app will continue running.';

  @override
  String get globalErrorLogSavedNote =>
      'Full details have been saved to the log file.';

  @override
  String get globalErrorLogDisabledNote =>
      'Enable logging in Settings to save error details.';

  @override
  String globalErrorTechnicalLine(String detail) {
    return 'Error: $detail';
  }

  @override
  String get globalErrorEnableLoggingButton => 'Enable Logging';

  @override
  String get globalErrorLoggingEnabledToast =>
      'Logging enabled — errors will be saved to log file';

  @override
  String get fatalErrorQuitButton => 'Quit';

  @override
  String get fatalErrorWipeButton => 'Wipe all data';

  @override
  String get fatalErrorWipingButton => 'Wiping…';

  @override
  String get fatalErrorWipeExplanation =>
      'Wipe deletes every app-support file (config, database, vault blobs, logs) so the next launch starts from a clean install. Cannot be undone.';

  @override
  String get fatalErrorWipeConfirmTitle => 'Wipe all data?';

  @override
  String get fatalErrorWipeConfirmBody =>
      'This permanently deletes every config, database, and vault file. The app will restart from a blank install. Continue?';

  @override
  String get fatalErrorWipeConfirmAction => 'Wipe everything';

  @override
  String get unencryptedArchiveWarning =>
      'This archive is not password-protected. Anyone with the file can read its contents.';

  @override
  String get clipboardCopyFailed => 'Copy to clipboard failed.';

  @override
  String get nonAsciiHostnameWarning =>
      'Hostname contains non-ASCII characters — verify each character against the literal you typed. Visually similar codepoints (Cyrillic / Greek) can spoof a Latin domain.';

  @override
  String get recordingPlayLocked =>
      'Unlock the app to play this encrypted recording';

  @override
  String get foregroundServiceTitle => 'SSH 接続中';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '接続 $count 件',
      one: '接続 1 件',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => 'セッション種別';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => 'ユーザー名';

  @override
  String get webDavAuthMethod => 'Auth 方式';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer トークン';

  @override
  String get webDavSelfSignedFingerprint => 'Self-signed 証明書の Fingerprint(任意)';

  @override
  String get webDavSelfSignedFingerprintHint => 'SHA-256、空ならシステム trust を使用';

  @override
  String get webDavCopyUrl => 'WebDAV URL をコピー';

  @override
  String get webDavOpenInBrowser => 'ブラウザで開く';

  @override
  String get errWebDavAuthFailed => 'WebDAV 認証に失敗';

  @override
  String get errWebDavNotFound => 'パスが見つかりません';

  @override
  String get errWebDavConflict => '現在の状態と競合しています';

  @override
  String errWebDavGeneric(String detail) {
    return 'WebDAV サーバーがリクエストを拒否しました: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'WebDAV の Base URL が必要です';

  @override
  String get errWebDavBaseUrlInvalid =>
      'Base URL は http:// または https:// で始める必要があります';

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
  String get s3EndpointHint => 'AWS は空のまま、MinIO / R2 / Spaces は endpoint を指定';

  @override
  String get s3PathStyle => 'Path-style アドレッシング';

  @override
  String get s3PathStyleHint => 'MinIO では必須、AWS では off';

  @override
  String get s3DefaultBucket => 'デフォルト bucket';

  @override
  String get s3DefaultPrefix => 'デフォルト prefix';

  @override
  String get s3GeneratePresignedUrl => 'Presigned URL を生成';

  @override
  String get s3PresignedUrlExpiry => '有効期限';

  @override
  String get s3CopyUri => 's3://bucket/key URI をコピー';

  @override
  String get s3PresignedUrlExpiry15min => '15 分';

  @override
  String get s3PresignedUrlExpiry1hour => '1 時間';

  @override
  String get s3PresignedUrlExpiry4hour => '4 時間';

  @override
  String get s3PresignedUrlExpiry24hour => '24 時間';

  @override
  String get s3PresignedUrlExpiry7day => '7 日';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (access key + secret を確認)';

  @override
  String get errS3NoSuchBucket => 'Bucket が存在しないかアクセスできません';

  @override
  String get errS3RegionMismatch => 'Bucket が設定とは別の region にあります';

  @override
  String errS3Generic(String detail) {
    return 'S3 サーバーがリクエストを拒否しました: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'WebDAV sync を有効化';

  @override
  String get syncPassphrase => 'Sync パスフレーズ';

  @override
  String get syncPassphraseHint => 'Sync アーカイブを暗号化します。マスターパスワードと異なる必要があります。';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Sync パスフレーズはマスターパスワードと同じにできません。';

  @override
  String get syncRemotePath => 'Remote パス';

  @override
  String get syncRemotePathHint =>
      'WebDAV Base URL 配下のパス — 既定は letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return '前回の push: $when';
  }

  @override
  String syncLastPulled(String when) {
    return '前回の pull: $when';
  }

  @override
  String get syncNeverRun => '未実行';

  @override
  String get syncUpToDate => 'Sync は最新です';

  @override
  String syncPushedBytes(String bytes) {
    return '$bytes を push しました';
  }

  @override
  String syncPullApplied(int count) {
    return 'Remote から $count 件の変更を適用';
  }

  @override
  String get errSyncDisabled => 'Sync は無効です';

  @override
  String get errSyncEtagMismatch => 'Remote が変わりました — まず pull、それから push';

  @override
  String get errSyncUnauthorized => 'WebDAV 認証に失敗しました';

  @override
  String errSyncNetwork(String detail) {
    return 'ネットワークエラー: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion => 'Remote の sync アーカイブには新しいビルドが必要です';

  @override
  String get hardwareKey => 'ハードウェアキー';

  @override
  String get hardwareKeyTapPrompt => 'ハードウェアキーをタップ';

  @override
  String get hardwareKeyPin => 'ハードウェアキーの PIN';

  @override
  String get hardwareKeyTimeout => 'ハードウェアキーが応答しませんでした';

  @override
  String get hardwareKeyNotFound => 'ハードウェアキーが見つかりません';

  @override
  String get hardwareKeyUnsupported => 'このプラットフォームでは直接のハードウェアキーアクセスは利用できません';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'Apple Developer Program entitlement が必要です。macOS では ssh-agent を使用してください';

  @override
  String get skKeyRequiresDevice => 'この SSH キーはハードウェアキーが必要です — タップして認証してください';

  @override
  String get errSkWrongPin => 'PIN が違います';

  @override
  String get hardwareKeyImport => 'ハードウェアキーをインポート (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => 'ハードウェアキーのプロンプトをキャンセルしました';

  @override
  String get agentEndpointSectionTitle => '外部 SSH クライアント連携';

  @override
  String get agentEndpointToggleTitle => 'ハードウェアキーを SSH クライアントに公開する';

  @override
  String get agentEndpointToggleSubtitle =>
      'この端末の git・ssh・IDE プラグインから FIDO2 / smart-card / TPM キーを利用できるようにします。';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'export コマンドをコピー';

  @override
  String get agentEndpointCopyPipeName => 'pipe 名をコピー';

  @override
  String get agentEndpointSignatureRequestTitle => '署名リクエスト';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester が $keyLabel で署名しようとしています';
  }

  @override
  String get agentEndpointRequesterUnknown => '外部 SSH クライアント';

  @override
  String get agentEndpointAuthorizeOnce => '今回だけ許可';

  @override
  String get agentEndpointAuthorizeAlways => '許可して記憶する';

  @override
  String get agentEndpointDeny => '拒否';

  @override
  String get agentEndpointStatusRunning => '実行中';

  @override
  String get agentEndpointStatusStopped => '停止';

  @override
  String get agentEndpointStatusUnsupported => 'このプラットフォームでは利用できません';

  @override
  String get agentEndpointRefusedAddIdentity =>
      '拒否: 外部クライアントから key を追加することはできません。';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'ssh-agent エンドポイントを開始できません: $detail';
  }

  @override
  String get pkcs11AddTitle => 'スマートカード / トークン キーを追加';

  @override
  String get pkcs11ModuleLabel => 'PKCS#11 モジュール';

  @override
  String get pkcs11ModuleAutoDetected => '自動検出';

  @override
  String get pkcs11ModuleCustom => 'カスタムモジュール...';

  @override
  String get pkcs11ModulePickerTitle => 'PKCS#11 ライブラリを選択';

  @override
  String get pkcs11NoModuleFound =>
      'PKCS#11 モジュールが見つかりません。OpenSC をインストールするか、ベンダーライブラリを選択してください。';

  @override
  String get pkcs11InitializeFailed => 'PKCS#11 モジュールを初期化できませんでした。';

  @override
  String get pkcs11NoTokenPresent => 'リーダーにトークンがありません。';

  @override
  String pkcs11TokenLabel(String label) {
    return 'トークン: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return 'シリアル: $serial';
  }

  @override
  String get pkcs11LoginRequired => 'トークンへのログインが必要です。';

  @override
  String pkcs11PinPrompt(String token) {
    return '$token の PIN';
  }

  @override
  String get pkcs11PinPad => 'トークンの PIN パッドで確認してください。';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'PIN が違います。残り $remaining 回。';
  }

  @override
  String get pkcs11PinLocked => 'トークンの PIN がロックされています。PUK で解除してください。';

  @override
  String get pkcs11NoSignableKeys =>
      'SSH で使えるキー (RSA、ECDSA、Ed25519) がトークンにありません。';

  @override
  String get pkcs11GostUnsupported => 'GOST キーは SSH では使えません。';

  @override
  String pkcs11TokenUnplugged(String label) {
    return 'トークン \"$label\" が挿入されていません。';
  }

  @override
  String get pkcs11UriRebindFailed => '保存されたトークンが見つかりません。再接続してください。';

  @override
  String pkcs11SignFailed(String reason) {
    return '署名に失敗しました: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      'このプラットフォームではスマートカード / PKCS#11 トークンは利用できません。';

  @override
  String get pkcs11Badge => 'スマートカード / トークン';

  @override
  String pkcs11InfoModulePath(String path) {
    return 'モジュール: $path';
  }

  @override
  String pkcs11InfoTokenSerial(String serial) {
    return 'トークンのシリアル: $serial';
  }

  @override
  String pkcs11InfoObjectLabel(String label) {
    return 'オブジェクト: $label';
  }

  @override
  String get pkcs11WizardStepModule => 'PKCS#11 モジュールを選択';

  @override
  String get pkcs11WizardStepToken => 'トークンを選択';

  @override
  String get pkcs11WizardStepKey => '鍵を選択';

  @override
  String get pkcs11WizardStepPin => 'PIN を入力';

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
  String get pkcs11SaveCta => '鍵をインポート';

  @override
  String get pkcs11SaveInProgress => 'トークンから公開鍵を読み込み中...';

  @override
  String get pkcs11SaveSuccess => 'スマートカードの鍵を追加しました。';

  @override
  String get pkcs11ScanInProgress => 'PKCS#11 モジュールをスキャン中...';

  @override
  String get pkcs11LoadingTokens => 'トークンを読み込み中...';

  @override
  String get pkcs11LoadingKeys => '鍵を読み込み中...';

  @override
  String get pkcs11ModuleStatusReady => 'モジュール読み込み完了。';

  @override
  String get pkcs11ModuleStatusNoToken => 'トークンが見つかりません。';

  @override
  String get pkcs11ModuleStatusFailed => 'モジュールの読み込みに失敗しました。';

  @override
  String get pkcs11PinPadHint => '(デバイスの PIN パッド)';

  @override
  String get pkcs11WizardBack => '戻る';

  @override
  String get pkcs11WizardNext => '次へ';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => 'ハードウェアキーを追加';

  @override
  String get sshKeyHardwareBoundExplainer =>
      'プライベートキーはデバイスのセキュアハードウェアにあり、エクスポートできません。';

  @override
  String get sshKeyEnclaveDeviceBound => 'このキーはこの Mac でのみ使用できます。';

  @override
  String get sshKeyEnclaveDeviceBoundIos => 'このキーはこの iPhone でのみ使用できます。';

  @override
  String get sshKeyHelloDeviceBound => 'このキーはこの PC でのみ使用できます。';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'Touch ID / Face ID を要求';

  @override
  String get sshKeyEnclavePasscodeFallback => 'デバイスパスコードを fallback として許可';

  @override
  String get sshKeyHelloPinRequired => 'Windows Hello を要求 (PIN、指紋、または顔)';

  @override
  String get sshKeyHardwareUnavailableTitle => 'ハードウェアキーが利用できません';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'Secure Enclave を使うにはアプリが code-signed である必要があります。';

  @override
  String get sshKeyHardwareUnavailableHello =>
      'この PC では Windows Hello が設定されていません。';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'TPM が検出されません — software-backed のみ。';

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
  String get sshKeyGenerateCta => '生成';

  @override
  String get sshKeyGenerateInProgress => 'セキュアハードウェアでキーを生成中...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Code-signing が必要 — USER_GUIDE.md → Hardware-bound keys を参照。';

  @override
  String get sshKeySignInProgress => 'セキュアハードウェアで署名中...';

  @override
  String get sshKeyPublicCopy => 'パブリックキーをコピー';

  @override
  String get sshKeyAuthorizedKeysHint =>
      'この行をサーバーの ~/.ssh/authorized_keys に追加してください。';

  @override
  String get sshKeyEnclaveWizardTitle => 'Secure Enclave SSH キー';

  @override
  String get sshKeyEnclaveWizardLabelHint => 'キー名';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'Windows Hello SSH キー';

  @override
  String get helloWizardLabelHint => 'キーのラベル';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'Windows Hello で認証';

  @override
  String get helloPromptDescription =>
      'PIN・指紋・顔のいずれかで Windows Hello が SSH チャレンジに署名します。';

  @override
  String get helloSoftwareGatedWarning =>
      'この端末には TPM がありません。鍵はユーザー領域に置かれますが、署名のたびに Windows Hello を通します。';

  @override
  String get helloP384NotSupported =>
      'TPM ファームウェアが P-384 をサポートしていません。P-256 か RSA-2048 を選択してください。';

  @override
  String get helloConfigureFirst =>
      'まず 設定 -> サインイン オプション で Windows Hello を有効化してください。';

  @override
  String get tpmSshTitle => 'TPM-backed SSH キーを生成';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (推奨)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported => 'この TPM ファームウェアではサポートされていない算法。';

  @override
  String get tpmSshPinProtect => 'PIN で保護する';

  @override
  String get tpmSshPinLockoutWarning => 'PIN を何度も間違えると TPM がキーをロックします。';

  @override
  String get tpmSshPinMismatch => 'PIN が一致しません。';

  @override
  String get tpmSshStorageBlob => 'ラップしたキーをアプリデータに保存';

  @override
  String get tpmSshStorageHandle => 'TPM メモリスロットに保持';

  @override
  String get tpmSshStorageHandleHelp => '署名が速くなります。TPM の永続スロットを 1 つ消費します。';

  @override
  String get tpmSshLabel => 'キーラベル';

  @override
  String get tpmSshImportTitle => 'TPM 保護の SSH キーをインポート';

  @override
  String get tpmSshImportFormat => 'TPM 2.0 キーファイル (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return '$label の TPM PIN';
  }

  @override
  String get tpmSshPinIncorrect => 'PIN が違います。';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM はロックアウトのクールダウン中です。$duration 待ってから再試行してください。';
  }

  @override
  String get tpmSshGenerating => 'TPM でキーを生成中...';

  @override
  String get tpmSshSigning => 'TPM で署名中...';

  @override
  String get tpmSshUnavailable => 'このデバイスで TPM が検出されません。';

  @override
  String get tpmSshUnavailableFwDisabled => 'TPM はファームウェアで無効化されています。';

  @override
  String get tpmSshUnavailableNoPermission =>
      'アプリが TPM にアクセスできません。ユーザーを `tss` グループに追加してください。';

  @override
  String tpmSshHandleInUse(String handle) {
    return '永続スロット $handle はすでに使用中です。';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      'このキーは Hello / PIN プロンプトなしで署名します — ログイン中にデスクトップへアクセスできる人なら誰でも使えてしまいます。';

  @override
  String get keystoreWizardTitle => 'Android Hardware Key';

  @override
  String get keystoreBadge => 'Android Keystore';

  @override
  String get keystoreKeyAndroidLabel => 'Android Keystore (ハードウェアバインド)';

  @override
  String get keystoreKeyStrongBoxLabel => 'StrongBox HSM';

  @override
  String get keystoreKeyTeeLabel => 'TEE (ハードウェアバックド)';

  @override
  String get keystoreKeyGenerating => 'ハードウェアバインドキーを生成中...';

  @override
  String get keystoreKeyAuthPrompt => 'SSH キーを使うため認証してください';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      'キーが破棄されました: 新しい生体情報が登録されました。サーバーで公開鍵を再登録してください。';

  @override
  String get keystoreKeyStrongBoxUnavailable =>
      'このデバイスでは StrongBox HSM を利用できません';

  @override
  String get keystoreKeyUserAuthRequired => '署名ごとに生体認証 / デバイスロック解除を要求';

  @override
  String get keystoreKeyExportDisabled => 'ハードウェアバインドキーはエクスポートできません';

  @override
  String get keystoreKeyDeleteWarning =>
      'このキーを削除するとハードウェアストアから消えます。新しく登録するまでサーバーは拒否します。';

  @override
  String get keystoreKeyBiometricNotEnrolled => '先に生体認証またはデバイス PIN を登録してください';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (StrongBox 対応)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+, TEE のみ)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (最大互換)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM が利用不可';

  @override
  String get keystoreStrongBoxFallbackBody =>
      'このデバイスは StrongBox HSM を公開していません。代わりに TEE 裏付けのキーを作成しますか？ハードウェア裏付けは維持されますが、StrongBox の分離はありません。';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'TEE を使う';

  @override
  String get keystoreStrongBoxFallbackCancel => 'キャンセル';

  @override
  String get fido2BrokerSectionTitle => 'ハードウェアセキュリティキー';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / security key';

  @override
  String get fido2BrokerMacosLabel => 'システムの security key ダイアログ';

  @override
  String get fido2BrokerIosLabel => 'システム security key (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel => 'システム security key (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => '直接 USB HID (CTAP2)';

  @override
  String get fido2BrokerTransportNone => 'このプラットフォームでは利用不可';

  @override
  String get fido2BrokerCurrentTransportLabel => '現在のトランスポート';

  @override
  String get fido2BrokerPreferDirectHidTitle => 'システムダイアログより直接 USB HID を優先';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return '上級者向け：両方のパスが動作するプラットフォームで $brokerLabel を回避します。直接 HID は authenticator の機能をより多く扱えますが、アプリごとの権限付与が必要です。';
  }

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return 'このデバイスでは $transport のみ利用可能です。トグルは無効化されています。';
  }

  @override
  String get hardwareKeyStubBadge => 'インポート済みスタブ';

  @override
  String get hardwareKeyStubSubtitle => '別のデバイスにあったため、ここで再生成して使用してください';

  @override
  String get hardwareKeyStubRegenerateAction => 'ここで再生成';

  @override
  String get hardwareKeyStubRemoveAction => 'スタブを削除';

  @override
  String get hardwareKeyStubPickerTooltip => '使用前にこのデバイスでこのキーを再生成してください';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return 'トークン \"$token\" の PKCS#11 モジュールを指定してください';
  }
}
