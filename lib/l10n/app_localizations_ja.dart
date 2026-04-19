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
  String get exportWhatToExport => 'エクスポートする内容：';

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
  String get passwordStrengthWeak => '弱い';

  @override
  String get passwordStrengthModerate => '普通';

  @override
  String get passwordStrengthStrong => '強い';

  @override
  String get passwordStrengthVeryStrong => '非常に強い';

  @override
  String get tierRecommendedBadge => '推奨';

  @override
  String get tierCurrentBadge => '現在';

  @override
  String get tierAlternativeBranchLabel => '代替 — OSを信頼しない';

  @override
  String get tierUpcomingTooltip => '今後のバージョンで提供されます。';

  @override
  String get tierUpcomingNotes =>
      'この層の基盤はまだ出荷されていません。オプションが存在することを知らせるために行は表示されています。';

  @override
  String get tierPlaintextLabel => 'プレーンテキスト';

  @override
  String get tierPlaintextSubtitle => '暗号化なし — ファイル権限のみ';

  @override
  String get tierPlaintextThreat1 => 'ファイルシステムにアクセスできる者が誰でもデータを読める';

  @override
  String get tierPlaintextThreat2 => '偶発的な同期またはバックアップがすべてを明らかにする';

  @override
  String get tierPlaintextNotes => '信頼された隔離環境でのみ使用してください。';

  @override
  String get tierKeychainLabel => 'キーチェーン';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'キーは $keychain に存在 — 起動時に自動ロック解除';
  }

  @override
  String get tierKeychainProtect1 => '同じマシン上の他のユーザー';

  @override
  String get tierKeychainProtect2 => 'OSログインなしで盗まれたディスク';

  @override
  String get tierKeychainThreat1 => 'あなたのOSアカウントで動作するマルウェア';

  @override
  String get tierKeychainThreat2 => 'あなたのOSログインを乗っ取る攻撃者';

  @override
  String get tierKeychainUnavailable => 'このインストールではOSキーチェーンが利用できません。';

  @override
  String get tierKeychainPassLabel => 'キーチェーン + パスワード';

  @override
  String get tierKeychainPassSubtitle => 'キーチェーンの前に短いパスワード（通行人ゲート）';

  @override
  String get tierKeychainPassProtect1 => 'あなたの机に座る同僚';

  @override
  String get tierKeychainPassProtect2 => 'ロック解除アクセスを持つ通行人';

  @override
  String get tierKeychainPassThreat1 => 'ディスク上のファイルを持つオフライン攻撃者';

  @override
  String get tierKeychainPassThreat2 => 'キーチェーンと同じOS侵害リスク';

  @override
  String get tierHardwareLabel => 'ハードウェア + PIN';

  @override
  String get tierHardwareSubtitle => 'ハードウェアバウンドボルト + ロックアウト付き短いPIN';

  @override
  String get tierHardwareProtect1 => 'PINのオフラインブルートフォース（ハードウェアレート制限）';

  @override
  String get tierHardwareProtect2 => 'ディスクとキーチェーンブロブの盗難';

  @override
  String get tierHardwareThreat1 => 'セキュアモジュールのOSまたはファームウェアのCVE';

  @override
  String get tierHardwareThreat2 => '強制生体認証ロック解除（有効な場合）';

  @override
  String get tierParanoidLabel => 'マスターパスワード（Paranoid）';

  @override
  String get tierParanoidSubtitle => '長いパスワード + Argon2id。キーはOSに入りません。';

  @override
  String get tierParanoidProtect1 => 'OSキーチェーン侵害';

  @override
  String get tierParanoidProtect2 => '盗まれたディスク（パスワードが強い限り）';

  @override
  String get tierParanoidThreat1 => 'パスワードをキャプチャするキーロガー';

  @override
  String get tierParanoidThreat2 => '弱いパスワード + オフラインArgon2idクラッキング';

  @override
  String get tierParanoidNotes => 'この層では生体認証は設計上無効化されています。';

  @override
  String get tierHardwareUnavailable => 'このインストールではハードウェアボールトを利用できません。';

  @override
  String get tierKeychainPassSetPrompt => '短いパスワードを設定';

  @override
  String get tierKeychainPassSetHint => 'キーチェーンの前のゲートとして使用';

  @override
  String get tierHardwarePinSetPrompt => '4〜6 桁の PIN を設定';

  @override
  String get tierHardwarePinSetHint => 'ハードウェアロックアウトにより PIN 推測が遅くなります';

  @override
  String get pinLabel => 'PIN';

  @override
  String get confirmPin => 'PIN の確認';

  @override
  String get pinMustBe4To6Digits => 'PIN は 4〜6 桁の数字である必要があります';

  @override
  String get pinsDoNotMatch => 'PIN が一致しません';

  @override
  String get l2UnlockTitle => 'パスワードが必要です';

  @override
  String get l2UnlockHint => '短いパスワードを入力して続行';

  @override
  String get l2WrongPassword => 'パスワードが違います';

  @override
  String get l3UnlockTitle => 'PIN を入力';

  @override
  String get l3UnlockHint => '短い PIN でハードウェア連携のボールトを解除';

  @override
  String get l3WrongPin => 'PIN が違います';

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
  String get errExportPickerUnavailable =>
      'システムのフォルダピッカーを利用できません。別の場所を試すか、アプリのストレージ権限を確認してください。';

  @override
  String get biometricUnlockPrompt => 'LetsFLUTssh のロックを解除';

  @override
  String get biometricUnlockTitle => '生体認証でロック解除';

  @override
  String get biometricUnlockSubtitle => 'アプリ起動時にマスターパスワードの入力を省略できます。';

  @override
  String get biometricNotAvailable => 'このデバイスでは生体認証によるロック解除を利用できません。';

  @override
  String get biometricEnableFailed => '生体認証によるロック解除を有効にできませんでした。';

  @override
  String get biometricEnabled => '生体認証によるロック解除を有効にしました';

  @override
  String get biometricDisabled => '生体認証によるロック解除を無効にしました';

  @override
  String get biometricUnlockFailed => '生体認証によるロック解除に失敗しました。マスターパスワードを入力してください。';

  @override
  String get biometricUnlockCancelled => '生体認証によるロック解除がキャンセルされました。';

  @override
  String get biometricNotEnrolled => 'このデバイスには生体情報が登録されていません。';

  @override
  String get biometricRequiresMasterPassword =>
      '生体認証によるロック解除を有効にするには、まずマスターパスワードを設定してください。';

  @override
  String get biometricSensorNotAvailable => 'このデバイスには生体センサーがありません。';

  @override
  String get biometricSystemServiceMissing =>
      '指紋サービス (fprintd) がインストールされていません。README → Installation を参照してください。';

  @override
  String get biometricBackingHardware => 'ハードウェア保護 (Secure Enclave / TPM)';

  @override
  String get biometricBackingSoftware => 'ソフトウェア保護';

  @override
  String get autoLockRequiresMasterPassword =>
      '自動ロックを有効にするには、まずマスターパスワードを設定してください。';

  @override
  String get currentPasswordIncorrect => '現在のパスワードが正しくありません';

  @override
  String get wrongPassword => 'パスワードが間違っています';

  @override
  String get useKeychain => 'OS のキーチェーンで暗号化';

  @override
  String get useKeychainSubtitle =>
      'データベースキーをシステムの認証情報ストアに保存します。オフ = 平文のデータベース。';

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
      'この時間操作がないと UI をロックします。暗号化データベースはアクティブな SSH セッションがない場合のみ再ロックされ、長時間の処理は接続を維持します。';

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
      '更新が拒否されました：ダウンロードされたファイルが、アプリに固定されているリリース鍵で署名されていません。ダウンロードが途中で改ざんされたか、現在のリリースがこのインストールに対応していない可能性があります。インストールしないでください — 公式リリースページから手動で再インストールしてください。';

  @override
  String get updateSecurityWarningTitle => '更新の検証に失敗しました';

  @override
  String get updateReinstallAction => 'リリースページを開く';

  @override
  String get errLfsNotArchive => '選択したファイルは LetsFLUTssh のアーカイブではありません。';

  @override
  String get errLfsDecryptFailed => 'マスターパスワードが間違っているか、.lfs アーカイブが破損しています';

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
  String get progressReencrypting => 'ストアを再暗号化中…';

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
  String get importKnownHostsSubtitle => 'OpenSSH known_hosts ファイルからインポート';

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
  String get legacyKdfTitle => 'セキュリティ更新が必要です';

  @override
  String get legacyKdfBody =>
      'このインストールでは、マスターパスワードが古い鍵導出アルゴリズム（PBKDF2）で保護されています。これはGPU/ASICによる解読に対してはるかに強い耐性を持つArgon2idに置き換えられました。新しい形式には後方互換性がないため、古いソルトファイルを自動的に移行することはできません。';

  @override
  String get legacyKdfWarning =>
      '「リセットして続行」を選択すると、保存されているすべての認証情報（パスワード、SSHキー、既知のホスト）が完全に削除されます。セッションと設定は保持されます。認証情報を復元する必要がある場合は、アプリを終了し、まず以前のバージョンのLetsFLUTsshを再インストールしてデータをエクスポートしてください。';

  @override
  String get legacyKdfResetContinue => 'リセットして続行';

  @override
  String get legacyKdfExit => 'LetsFLUTsshを終了';

  @override
  String get dbCorruptTitle => 'データベースを開けません';

  @override
  String get dbCorruptBody =>
      'ディスク上の暗号化データベースが、このインストールに記録されているセキュリティ階層と一致しません。通常、以前のセットアップが中断されたか、データが別の暗号を使用したビルドのものであることを意味します。\n\n一致するビルドの正しい認証情報でデータベースを開くか、消去して新規にセットアップするまで、LetsFLUTssh は続行できません。';

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
      'このインストールには、異なる層モデルを使用していた以前のバージョンのLetsFLUTsshのセキュリティデータが含まれています。新しいモデルは互換性のない変更であり、自動移行パスはありません。続行するには、このインストールに保存されているすべてのセッション、認証情報、SSHキー、既知のホストを消去し、初回起動のセットアップウィザードをゼロから実行する必要があります。';

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
  String get securityLevelPlaintext => 'なし';

  @override
  String get securityLevelKeychain => 'OS キーチェーン';

  @override
  String get securityLevelMasterPassword => 'マスターパスワード';

  @override
  String get keychainStatus => 'キーチェーン';

  @override
  String get keychainAvailable => '利用可能';

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
  String get changeSecurityTier => 'セキュリティ階層を変更';

  @override
  String get changeSecurityTierSubtitle => '階層ラダーを開き、別のセキュリティ階層に切り替え';

  @override
  String get changeSecurityTierConfirm =>
      '新しい階層でデータベースを再暗号化中。中断できません — 完了するまでアプリを開いたままにしてください。';

  @override
  String get changeSecurityTierDone => 'セキュリティ階層が変更されました';

  @override
  String get changeSecurityTierFailed => 'セキュリティ階層を変更できませんでした';

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
  String get runSnippet => '実行';

  @override
  String get pinToSession => 'このセッションに固定';

  @override
  String get unpinFromSession => 'このセッションから外す';

  @override
  String get pinnedSnippets => '固定済み';

  @override
  String get allSnippets => 'すべて';

  @override
  String get sendToTerminal => 'ターミナルへ送信';

  @override
  String get commandCopied => 'コマンドをコピーしました';

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
  String get threatBystanderUnlockedMachine => 'ロック解除済み端末のそばにいる第三者';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'あなたが離席している間に、すでにロック解除済みのコンピューターへ誰かが近づき、このアプリを開く状況。';

  @override
  String get threatSameUserMalware => '同一ユーザー権限のマルウェア';

  @override
  String get threatSameUserMalwareDescription =>
      'あなたのユーザーアカウントで動作する悪意あるプロセス。ファイル・キーチェーン・メモリへの権限はこのアプリと同等であり、侵害済みのホストではどの階層でも防御できません。';

  @override
  String get threatLiveProcessMemoryDump => '動作中プロセスのメモリダンプ';

  @override
  String get threatLiveProcessMemoryDumpDescription =>
      'デバッガーや ptrace のアクセス権を持つ攻撃者が、稼働中のアプリのメモリから解錠済みのデータベース鍵を直接読み出します。';

  @override
  String get threatLiveRamForensicsLocked => 'ロック状態の端末に対する RAM フォレンジック';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      '攻撃者が RAM を凍結したり DMA で取得したりして、アプリがロック中でもスナップショットから残存する鍵素材を引き出します。';

  @override
  String get threatOsKernelOrKeychainBreach => 'OS カーネルまたはキーチェーンの侵害';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'カーネル脆弱性、キーチェーンの窃取、あるいはハードウェアセキュリティチップのバックドア。OS 自体が信頼できる基盤ではなく、攻撃者側の存在になります。';

  @override
  String get threatOfflineBruteForce => '弱いパスワードへのオフライン総当たり';

  @override
  String get threatOfflineBruteForceDescription =>
      'ラップされた鍵や封印ブロブのコピーを持つ攻撃者が、レート制限を一切受けずに自分のペースで全パスワードを試せる状況。';

  @override
  String get legendProtects => '保護あり';

  @override
  String get legendDoesNotProtect => '保護なし';

  @override
  String get legendNotApplicable => '該当なし — この階層にはユーザー秘密がありません';

  @override
  String get legendWeakPasswordWarning =>
      '弱いパスワードでも可 — 別の層（ハードウェアのレート制限、またはラップされた鍵のバインディング）が安全性を担います';

  @override
  String get legendStrongPasswordRecommended =>
      '長いパスフレーズの使用を強く推奨 — この階層の安全性はそれに依存します';

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
  String get securityComparisonTableTitle => 'セキュリティ階層 — 横並び比較';

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
  String get compareAllTiersSubtitle => '各階層の防御範囲を並べて比較できます。';

  @override
  String get autoLockRequiresPassword => '自動ロックにはアクティブな階層にパスワードが必要です。';

  @override
  String get recommendedBadge => '推奨';

  @override
  String get continueWithRecommended => '推奨設定で続行';

  @override
  String get customizeSecurity => 'セキュリティをカスタマイズ';

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
  String get securitySetupContinue => '続行';

  @override
  String get currentTierBadge => '現在';

  @override
  String get paranoidAlternativeHeader => '代替';

  @override
  String get modifierPasswordLabel => 'パスワード';

  @override
  String get modifierPasswordSubtitle => 'ボールト解錠前に入力する秘密のゲート。';

  @override
  String get modifierBiometricLabel => '生体認証ショートカット';

  @override
  String get modifierBiometricSubtitle =>
      'パスワードを入力する代わりに、生体認証で保護されたOSスロットから取り出します。';

  @override
  String get biometricRequiresPassword =>
      '先にパスワードを有効にしてください — 生体認証は入力のショートカットです。';

  @override
  String get biometricForbiddenParanoid => 'Paranoid は設計上、生体認証を許可しません。';

  @override
  String get fprintdNotAvailable => 'fprintd がインストールされていないか、指紋が登録されていません。';

  @override
  String get linuxTpmWithoutPasswordNote =>
      'パスワードなしの TPM は分離を提供するだけで、認証にはなりません。このアプリを実行できる人なら誰でもデータを解錠できます。';

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
