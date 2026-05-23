// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class SRu extends S {
  SRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'LetsFLUTssh';

  @override
  String get ok => 'OK';

  @override
  String get infoDialogProtectsHeader => 'Защищает от';

  @override
  String get infoDialogDoesNotProtectHeader => 'Не защищает от';

  @override
  String get cancel => 'Отмена';

  @override
  String get close => 'Закрыть';

  @override
  String get delete => 'Удалить';

  @override
  String get save => 'Сохранить';

  @override
  String get connect => 'Подключиться';

  @override
  String get retry => 'Повторить';

  @override
  String get import_ => 'Импорт';

  @override
  String get export_ => 'Экспорт';

  @override
  String get rename => 'Переименовать';

  @override
  String get create => 'Создать';

  @override
  String get back => 'Назад';

  @override
  String get copy => 'Копировать';

  @override
  String get cut => 'Вырезать';

  @override
  String get paste => 'Вставить';

  @override
  String get select => 'Выбрать';

  @override
  String get copyModeTapToStart => 'Коснитесь, чтобы отметить начало выделения';

  @override
  String get copyModeExtending => 'Ведите пальцем, чтобы расширить выделение';

  @override
  String get copyModeSetAnchor => 'Поставить якорь';

  @override
  String get copyModeCopySelection => 'Скопировать выделение';

  @override
  String get required => 'Обязательное поле';

  @override
  String get errFillRequiredFields =>
      'Заполните обязательные поля, отмеченные *';

  @override
  String get settings => 'Настройки';

  @override
  String get appSettings => 'Настройки приложения';

  @override
  String get yes => 'Да';

  @override
  String get no => 'Нет';

  @override
  String get importWhatToImport => 'Что импортировать:';

  @override
  String get exportWhatToExport => 'Что экспортировать:';

  @override
  String get enterMasterPasswordPrompt => 'Введите мастер-пароль:';

  @override
  String get nextStep => 'Далее';

  @override
  String get includePasswords => 'Пароли сессий';

  @override
  String get embeddedKeys => 'Встроенные ключи';

  @override
  String get managerKeys => 'Ключи из менеджера';

  @override
  String get managerKeysMayBeLarge =>
      'Ключи из менеджера могут превысить размер QR';

  @override
  String get qrPasswordWarning =>
      'SSH-ключи отключены по умолчанию для экспорта.';

  @override
  String get sshKeysMayBeLarge => 'Ключи могут превысить размер QR';

  @override
  String exportTotalSize(String size) {
    return 'Общий размер: $size';
  }

  @override
  String get terminal => 'Терминал';

  @override
  String get files => 'Файлы';

  @override
  String get transfer => 'Передача';

  @override
  String get open => 'Открыть';

  @override
  String get search => 'Поиск...';

  @override
  String get noResults => 'Ничего не найдено';

  @override
  String get filter => 'Фильтр...';

  @override
  String get merge => 'Объединить';

  @override
  String get replace => 'Заменить';

  @override
  String get reconnect => 'Переподключиться';

  @override
  String get updateAvailable => 'Доступно обновление';

  @override
  String updateVersionAvailable(String version, String current) {
    return 'Доступна версия $version (текущая: v$current).';
  }

  @override
  String get releaseNotes => 'Примечания к выпуску:';

  @override
  String get skipThisVersion => 'Пропустить эту версию';

  @override
  String get unskip => 'Отменить пропуск';

  @override
  String get downloadAndInstall => 'Скачать и установить';

  @override
  String get openInBrowser => 'Открыть в браузере';

  @override
  String get couldNotOpenBrowser =>
      'Не удалось открыть браузер — URL скопирован в буфер обмена';

  @override
  String get checkForUpdates => 'Проверить обновления';

  @override
  String get checkNow => 'Проверить';

  @override
  String get checkForUpdatesOnStartup => 'Проверять обновления при запуске';

  @override
  String get checking => 'Проверка...';

  @override
  String get youreUpToDate => 'У вас последняя версия';

  @override
  String get updateCheckFailed => 'Не удалось проверить обновления';

  @override
  String get unknownError => 'Неизвестная ошибка';

  @override
  String downloadingPercent(int percent) {
    return 'Загрузка... $percent%';
  }

  @override
  String get updateVerifying => 'Проверка…';

  @override
  String get downloadComplete => 'Загрузка завершена';

  @override
  String get installNow => 'Установить сейчас';

  @override
  String get openReleasePage => 'Открыть страницу релиза';

  @override
  String get couldNotOpenInstaller => 'Не удалось открыть установщик';

  @override
  String get installerFailedOpenedReleasePage =>
      'Не удалось запустить установщик; открыта страница релиза в браузере';

  @override
  String versionAvailable(String version) {
    return 'Доступна версия $version';
  }

  @override
  String currentVersion(String version) {
    return 'Текущая: v$version';
  }

  @override
  String importedSessions(int count) {
    return 'Импортировано сессий: $count';
  }

  @override
  String importFailed(String error) {
    return 'Ошибка импорта: $error';
  }

  @override
  String importSkippedLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'отброшено $count связей (цели отсутствуют)',
      many: 'отброшено $count связей (цели отсутствуют)',
      few: 'отброшено $count связи (цели отсутствуют)',
      one: 'отброшена $count связь (цель отсутствует)',
    );
    return '$_temp0';
  }

  @override
  String importSkippedSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'пропущено $count повреждённых сессий',
      many: 'пропущено $count повреждённых сессий',
      few: 'пропущено $count повреждённых сессии',
      one: 'пропущена $count повреждённая сессия',
    );
    return '$_temp0';
  }

  @override
  String get sessions => 'Сессии';

  @override
  String get emptyFolders => 'Пустые папки';

  @override
  String get sessionsHeader => 'СЕССИИ';

  @override
  String get savedSessions => 'Сохранённые сессии';

  @override
  String get activeConnections => 'Активные подключения';

  @override
  String get openTabs => 'Открытые вкладки';

  @override
  String get noSavedSessions => 'Нет сохранённых сессий';

  @override
  String get addSession => 'Добавить сессию';

  @override
  String get noSessions => 'Нет сессий';

  @override
  String nSelectedCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get selectAll => 'Выбрать все';

  @override
  String get deselectAll => 'Снять все';

  @override
  String get moveTo => 'Переместить в...';

  @override
  String get moveToFolder => 'Переместить в папку';

  @override
  String get rootFolder => '/ (корень)';

  @override
  String get newFolder => 'Новая папка';

  @override
  String get newConnection => 'Новое подключение';

  @override
  String get editConnection => 'Редактировать подключение';

  @override
  String get duplicate => 'Дублировать';

  @override
  String get deleteSession => 'Удалить сессию';

  @override
  String get renameFolder => 'Переименовать папку';

  @override
  String get deleteFolder => 'Удалить папку';

  @override
  String get deleteSelected => 'Удалить выбранное';

  @override
  String deleteNSessionsAndFolders(String parts) {
    return 'Удалить $parts?\n\nЭто действие нельзя отменить.';
  }

  @override
  String nSessions(int count) {
    return 'сессий: $count';
  }

  @override
  String nFolders(int count) {
    return 'папок: $count';
  }

  @override
  String deleteFolderConfirm(String name) {
    return 'Удалить папку \"$name\"?';
  }

  @override
  String willDeleteSessionsInside(int count) {
    return 'Также будут удалены сессии внутри: $count.';
  }

  @override
  String deleteSessionConfirm(String name) {
    return 'Удалить \"$name\"?';
  }

  @override
  String get connection => 'Подключение';

  @override
  String get auth => 'Авторизация';

  @override
  String get sectionAuthentication => 'Аутентификация';

  @override
  String get sectionAdvanced => 'Дополнительно';

  @override
  String get moreOptions => 'Дополнительно';

  @override
  String forwardRulesSummary(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString правил проброса',
      many: '$countString правил проброса',
      few: '$countString правила проброса',
      one: '$countString правило проброса',
      zero: 'Нет правил проброса портов',
    );
    return '$_temp0';
  }

  @override
  String get manageRules => 'Управлять…';

  @override
  String get authMethodAgent => 'Использовать системный ssh-agent';

  @override
  String get options => 'Параметры';

  @override
  String get sessionName => 'Имя сессии';

  @override
  String get sessionNameAutoFromHost => 'Авто из host';

  @override
  String get sessionNameAutoFromUrl => 'Авто из host\'а URL';

  @override
  String get sessionNameAutoFromBucket => 'Авто из default bucket';

  @override
  String get hintMyServer => 'Мой сервер';

  @override
  String get hostRequired => 'Хост *';

  @override
  String get hintHost => '192.168.1.1';

  @override
  String get port => 'Порт';

  @override
  String get hintPort => '22';

  @override
  String get usernameRequired => 'Имя пользователя *';

  @override
  String get hintUsername => 'root';

  @override
  String get password => 'Пароль';

  @override
  String get hintPassword => '••••••••';

  @override
  String get keyPassphrase => 'Парольная фраза ключа';

  @override
  String get hintOptional => 'Необязательно';

  @override
  String get savedTypeToChange => 'Сохранено — введите для замены';

  @override
  String get hidePemText => 'Скрыть PEM-текст';

  @override
  String get pastePemKeyText => 'Вставить PEM-текст ключа';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get saveAndConnect => 'Сохранить и подключиться';

  @override
  String get portRange => '1-65535';

  @override
  String get provideKeyFirst => 'Сначала укажите файл ключа или PEM-текст';

  @override
  String get keyTextPem => 'Текст ключа (PEM)';

  @override
  String get selectKeyFile => 'Выбрать файл ключа';

  @override
  String get clearKeyFile => 'Очистить файл ключа';

  @override
  String get authOrDivider => 'ИЛИ';

  @override
  String get providePasswordOrKey => 'Укажите пароль или SSH-ключ';

  @override
  String get quickConnect => 'Быстрое подключение';

  @override
  String get scanQrCode => 'Сканировать QR-код';

  @override
  String get emptyFolder => 'Папка пуста';

  @override
  String get qrGenerationFailed => 'Не удалось создать QR-код';

  @override
  String get scanWithCameraApp =>
      'Сканируйте любым приложением камеры на устройстве,\nгде установлен LetsFLUTssh.';

  @override
  String get noPasswordsInQr => 'В этом QR-коде нет паролей и ключей';

  @override
  String get qrContainsCredentialsWarning =>
      'QR-код содержит учётные данные. Не показывайте экран посторонним.';

  @override
  String get copyLink => 'Копировать ссылку';

  @override
  String get linkCopied => 'Ссылка скопирована в буфер обмена';

  @override
  String get hostKeyChanged => 'Ключ хоста изменился!';

  @override
  String get unknownHost => 'Неизвестный хост';

  @override
  String get hostKeyChangedWarning =>
      'ВНИМАНИЕ: Ключ хоста для этого сервера изменился. Это может означать атаку \"человек посередине\" или переустановку сервера.';

  @override
  String get unknownHostMessage =>
      'Подлинность этого хоста не может быть подтверждена. Вы уверены, что хотите продолжить подключение?';

  @override
  String get host => 'Хост';

  @override
  String get keyType => 'Тип ключа';

  @override
  String get fingerprint => 'Отпечаток';

  @override
  String get fingerprintCopied => 'Отпечаток скопирован';

  @override
  String get copyFingerprint => 'Копировать отпечаток';

  @override
  String get acceptAnyway => 'Всё равно принять';

  @override
  String get accept => 'Принять';

  @override
  String get importData => 'Импорт данных';

  @override
  String get masterPassword => 'Мастер-пароль';

  @override
  String get confirmPassword => 'Подтверждение пароля';

  @override
  String get importModeMergeDescription =>
      'Добавить новые сессии, сохранить существующие';

  @override
  String get importModeReplaceDescription =>
      'Заменить все сессии импортированными';

  @override
  String get folderName => 'Имя папки';

  @override
  String get newName => 'Новое имя';

  @override
  String deleteItems(String names) {
    return 'Удалить $names?';
  }

  @override
  String deleteNItems(int count) {
    return 'Удалить элементов: $count';
  }

  @override
  String deletedItem(String name) {
    return 'Удалено: $name';
  }

  @override
  String deletedNItems(int count) {
    return 'Удалено элементов: $count';
  }

  @override
  String failedToCreateFolder(String error) {
    return 'Не удалось создать папку: $error';
  }

  @override
  String failedToRename(String error) {
    return 'Не удалось переименовать: $error';
  }

  @override
  String failedToDeleteItem(String name, String error) {
    return 'Не удалось удалить $name: $error';
  }

  @override
  String get editPath => 'Редактировать путь';

  @override
  String get root => 'Корень';

  @override
  String get controllersNotInitialized => 'Контроллеры не инициализированы';

  @override
  String get clearHistory => 'Очистить историю';

  @override
  String get noTransfersYet => 'Передач пока нет';

  @override
  String get duplicateTab => 'Дублировать вкладку';

  @override
  String get duplicateTabShortcut => 'Дублировать вкладку (Ctrl+\\)';

  @override
  String get previous => 'Предыдущий';

  @override
  String get next => 'Следующий';

  @override
  String get closeEsc => 'Закрыть (Esc)';

  @override
  String get closeAll => 'Закрыть все';

  @override
  String get closeOthers => 'Закрыть остальные';

  @override
  String get closeTabsToTheLeft => 'Закрыть вкладки слева';

  @override
  String get closeTabsToTheRight => 'Закрыть вкладки справа';

  @override
  String get noActiveSession => 'Нет активной сессии';

  @override
  String get createConnectionHint =>
      'Создайте новое подключение или выберите из боковой панели';

  @override
  String get hideSidebar => 'Скрыть боковую панель (Ctrl+B)';

  @override
  String get showSidebar => 'Показать боковую панель (Ctrl+B)';

  @override
  String get language => 'Язык';

  @override
  String get languageSystemDefault => 'Авто';

  @override
  String get theme => 'Тема';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeSystem => 'Системная';

  @override
  String get appearance => 'Внешний вид';

  @override
  String get connectionSection => 'Подключение';

  @override
  String get transfers => 'Передачи';

  @override
  String get data => 'Данные';

  @override
  String get logging => 'Журналирование';

  @override
  String get updates => 'Обновления';

  @override
  String get about => 'О программе';

  @override
  String get resetToDefaults => 'Сбросить настройки';

  @override
  String get uiScale => 'Масштаб интерфейса';

  @override
  String get terminalFontSize => 'Размер шрифта терминала';

  @override
  String get scrollbackLines => 'Строки прокрутки';

  @override
  String get keepAliveInterval => 'Интервал Keep-Alive (сек)';

  @override
  String get sshTimeout => 'Таймаут SSH (сек)';

  @override
  String get defaultPort => 'Порт по умолчанию';

  @override
  String get parallelWorkers => 'Параллельные потоки';

  @override
  String get maxHistory => 'Макс. история';

  @override
  String get calculateFolderSizes => 'Вычислять размеры папок';

  @override
  String get exportData => 'Экспорт данных';

  @override
  String get exportRecordings => 'Записи сессий';

  @override
  String sshConfigPreviewHostsFound(int count) {
    return 'Найдено хостов: $count';
  }

  @override
  String get sshConfigPreviewNoHosts =>
      'В этом файле не найдено хостов для импорта.';

  @override
  String sshConfigPreviewMissingKeys(String hosts) {
    return 'Не удалось прочитать файлы ключей для: $hosts. Эти хосты будут импортированы без учётных данных.';
  }

  @override
  String sshConfigImportFolderName(String date) {
    return '.ssh $date';
  }

  @override
  String get exportArchive => 'Экспорт архива';

  @override
  String get exportArchiveSubtitle =>
      'Сохранить сессии, конфигурацию и ключи в зашифрованный файл .lfs';

  @override
  String get exportQrCode => 'Экспорт QR-кода';

  @override
  String get exportQrCodeSubtitle =>
      'Поделиться выбранными сессиями и ключами через QR-код';

  @override
  String get importArchive => 'Импорт архива';

  @override
  String get importArchiveSubtitle => 'Загрузить данные из файла .lfs';

  @override
  String get importFromSshDir => 'Импорт из ~/.ssh';

  @override
  String get importFromSshDirSubtitle =>
      'Выберите хосты из файла конфигурации и/или приватные ключи из ~/.ssh';

  @override
  String get sshDirImportHostsSection => 'Хосты из файла конфигурации';

  @override
  String get sshDirImportKeysSection => 'Ключи в ~/.ssh';

  @override
  String importSshKeysFound(int count) {
    return 'Найдено ключей: $count — выберите, какие импортировать';
  }

  @override
  String get importSshKeysNoneFound => 'В ~/.ssh не найдено приватных ключей.';

  @override
  String get sshKeyAlreadyImported => 'уже в хранилище';

  @override
  String get setMasterPasswordHint =>
      'Задайте мастер-пароль для шифрования архива.';

  @override
  String get passwordsDoNotMatch => 'Пароли не совпадают';

  @override
  String get passwordStrengthWeak => 'Слабый';

  @override
  String get passwordStrengthModerate => 'Средний';

  @override
  String get passwordStrengthStrong => 'Сильный';

  @override
  String get passwordStrengthVeryStrong => 'Очень сильный';

  @override
  String get tierPlaintextLabel => 'Без шифрования';

  @override
  String get tierPlaintextSubtitle =>
      'Без шифрования — только права доступа к файлам';

  @override
  String get tierKeychainLabel => 'Keychain';

  @override
  String tierKeychainSubtitle(String keychain) {
    return 'Ключ в $keychain — автоматическая разблокировка при запуске';
  }

  @override
  String get tierKeychainUnavailable =>
      'Keychain ОС недоступен в этой установке.';

  @override
  String get tierHardwareLabel => 'Аппаратное';

  @override
  String get tierParanoidLabel => 'Мастер-пароль (Paranoid)';

  @override
  String get tierHardwareUnavailable =>
      'Аппаратное хранилище недоступно на этой установке.';

  @override
  String get pinLabel => 'Пароль';

  @override
  String get l2UnlockTitle => 'Требуется пароль';

  @override
  String get l2UnlockHint => 'Введите короткий пароль для продолжения';

  @override
  String get l2WrongPassword => 'Неверный пароль';

  @override
  String get l3UnlockTitle => 'Введите пароль';

  @override
  String get l3UnlockHint => 'Пароль разблокирует аппаратное хранилище';

  @override
  String get l3WrongPin => 'Неверный пароль';

  @override
  String tierCooldownHint(int seconds) {
    return 'Повтор через $seconds с';
  }

  @override
  String exportedTo(String path) {
    return 'Экспортировано в: $path';
  }

  @override
  String exportFailed(String error) {
    return 'Ошибка экспорта: $error';
  }

  @override
  String get pathToLfsFile => 'Путь к файлу .lfs';

  @override
  String get dataLocation => 'Расположение данных';

  @override
  String get dataStorageSection => 'Хранилище';

  @override
  String get pathCopied => 'Путь скопирован в буфер обмена';

  @override
  String get urlCopied => 'URL скопирован в буфер обмена';

  @override
  String aboutSubtitle(String version) {
    return 'v$version — SSH/SFTP клиент';
  }

  @override
  String get sourceCode => 'Исходный код';

  @override
  String get logIsEmpty => 'Журнал пуст';

  @override
  String logExportedTo(String path) {
    return 'Журнал экспортирован в: $path';
  }

  @override
  String logExportFailed(String error) {
    return 'Ошибка экспорта журнала: $error';
  }

  @override
  String get logsCleared => 'Журнал очищен';

  @override
  String get copiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get copyLog => 'Копировать журнал';

  @override
  String get exportLog => 'Экспортировать журнал';

  @override
  String get clearLogs => 'Очистить журнал';

  @override
  String get local => 'Локальный';

  @override
  String get remote => 'Удалённый';

  @override
  String get pickFolder => 'Выбрать папку';

  @override
  String get refresh => 'Обновить';

  @override
  String get up => 'Вверх';

  @override
  String get emptyDirectory => 'Пустая директория';

  @override
  String get cancelSelection => 'Отменить выделение';

  @override
  String get openSftpBrowser => 'Открыть SFTP-браузер';

  @override
  String get openSshTerminal => 'Открыть SSH-терминал';

  @override
  String get noActiveFileBrowsers => 'Нет активных файловых менеджеров';

  @override
  String get useSftpFromSessions => 'Используйте \"SFTP\" из раздела Сессии';

  @override
  String get saveLogAs => 'Сохранить журнал как';

  @override
  String get chooseSaveLocation => 'Выберите место сохранения';

  @override
  String get forward => 'Вперёд';

  @override
  String get name => 'Имя';

  @override
  String get size => 'Размер';

  @override
  String get modified => 'Изменён';

  @override
  String get mode => 'Права';

  @override
  String get owner => 'Владелец';

  @override
  String get connectionError => 'Ошибка подключения';

  @override
  String get resizeWindowToViewFiles =>
      'Измените размер окна для просмотра файлов';

  @override
  String get completed => 'Завершено';

  @override
  String get connected => 'Подключено';

  @override
  String get disconnected => 'Отключено';

  @override
  String a11yConnectingTo(String host) {
    return 'Подключение к $host';
  }

  @override
  String a11yConnectedTo(String host) {
    return 'Подключено к $host';
  }

  @override
  String a11yDisconnectedFrom(String host) {
    return 'Отключено от $host';
  }

  @override
  String a11yConnectionFailed(String host) {
    return 'Не удалось подключиться к $host';
  }

  @override
  String get exit => 'Выход';

  @override
  String get exitConfirmation => 'Активные сессии будут отключены. Выйти?';

  @override
  String get hintFolderExample => 'напр. Production';

  @override
  String get credentialsNotSet => 'Учётные данные не заданы';

  @override
  String get exportSessionsViaQr => 'Экспорт сессий через QR';

  @override
  String get qrTooManyForSingleCode =>
      'Слишком много сессий для одного QR-кода. Снимите часть выделения или используйте экспорт в .lfs.';

  @override
  String get qrTooLarge =>
      'Слишком большой объём — снимите часть выделения или используйте экспорт в файл .lfs.';

  @override
  String get showQr => 'Показать QR';

  @override
  String get sort => 'Сортировка';

  @override
  String get resizePanelDivider => 'Изменить размер разделителя панелей';

  @override
  String get youreRunningLatest => 'У вас установлена последняя версия';

  @override
  String get liveLog => 'Лог в реальном времени';

  @override
  String get archivedLog => 'Архивный лог';

  @override
  String get loggingLevel => 'Уровень логирования';

  @override
  String get loggingLevelSubtitleInfo =>
      'Обычные записи + предупреждения + ошибки';

  @override
  String get loggingLevelSubtitleWarn => 'Только проблемные пути и ошибки';

  @override
  String get loggingLevelSubtitleError => 'Только ошибки';

  @override
  String get loggingLevelSubtitleOff => 'Обычные логи не пишутся';

  @override
  String transferNItems(int count) {
    return 'Передать $count элементов';
  }

  @override
  String get time => 'Время';

  @override
  String get failed => 'Ошибка';

  @override
  String get errOperationNotPermitted => 'Операция не разрешена';

  @override
  String get errNoSuchFileOrDirectory => 'Нет такого файла или каталога';

  @override
  String get errNoSuchProcess => 'Нет такого процесса';

  @override
  String get errIoError => 'Ошибка ввода-вывода';

  @override
  String get errBadFileDescriptor => 'Неверный файловый дескриптор';

  @override
  String get errResourceTemporarilyUnavailable => 'Ресурс временно недоступен';

  @override
  String get errOutOfMemory => 'Недостаточно памяти';

  @override
  String get errPermissionDenied => 'Доступ запрещён';

  @override
  String get errFileExists => 'Файл уже существует';

  @override
  String get errNotADirectory => 'Не является каталогом';

  @override
  String get errIsADirectory => 'Является каталогом';

  @override
  String get errInvalidArgument => 'Недопустимый аргумент';

  @override
  String get errTooManyOpenFiles => 'Слишком много открытых файлов';

  @override
  String get errNoSpaceLeftOnDevice =>
      'На устройстве не осталось свободного места';

  @override
  String get errReadOnlyFileSystem => 'Файловая система только для чтения';

  @override
  String get errBrokenPipe => 'Разрыв канала';

  @override
  String get errFileNameTooLong => 'Имя файла слишком длинное';

  @override
  String get errDirectoryNotEmpty => 'Каталог не пуст';

  @override
  String get errAddressAlreadyInUse => 'Адрес уже используется';

  @override
  String get errCannotAssignAddress => 'Невозможно назначить запрошенный адрес';

  @override
  String get errNetworkIsDown => 'Сеть недоступна';

  @override
  String get errNetworkIsUnreachable => 'Сеть недостижима';

  @override
  String get errConnectionResetByPeer =>
      'Соединение сброшено удалённой стороной';

  @override
  String get errConnectionTimedOut => 'Время ожидания соединения истекло';

  @override
  String get errConnectionRefused => 'Соединение отклонено';

  @override
  String get errHostIsDown => 'Хост недоступен';

  @override
  String get errNoRouteToHost => 'Нет маршрута до хоста';

  @override
  String get errConnectionAborted => 'Соединение прервано';

  @override
  String get errAlreadyConnected => 'Уже подключено';

  @override
  String get errNotConnected => 'Не подключено';

  @override
  String errSshConnectFailed(String host, int port) {
    return 'Не удалось подключиться к $host:$port';
  }

  @override
  String errSshAuthFailed(String user, String host) {
    return 'Ошибка аутентификации для $user@$host';
  }

  @override
  String errSshConnectionFailed(String host, int port) {
    return 'Ошибка подключения к $host:$port';
  }

  @override
  String get errSshAuthAborted => 'Аутентификация прервана';

  @override
  String errSshHostKeyRejected(String host, int port) {
    return 'Ключ хоста отклонён для $host:$port — примите ключ хоста или проверьте known_hosts';
  }

  @override
  String get errSshOpenShellFailed => 'Не удалось открыть оболочку';

  @override
  String get errSshLoadKeyFileFailed => 'Не удалось загрузить файл SSH-ключа';

  @override
  String get errSshParseKeyFailed => 'Не удалось разобрать данные PEM-ключа';

  @override
  String get errSshConnectionDisposed => 'Соединение завершено';

  @override
  String get errSshNotConnected => 'Не подключено';

  @override
  String get errConnectionFailed => 'Ошибка подключения';

  @override
  String errConnectionTimedOutSeconds(int seconds) {
    return 'Время ожидания подключения истекло через $seconds секунд';
  }

  @override
  String get errSessionClosed => 'Сессия закрыта';

  @override
  String errSftpInitFailed(String error) {
    return 'Не удалось инициализировать SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Ошибка загрузки: $error';
  }

  @override
  String get errExportPickerUnavailable =>
      'Системный выбор папки недоступен. Попробуйте другое расположение или проверьте разрешения на доступ к хранилищу.';

  @override
  String get biometricUnlockPrompt => 'Разблокировать LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'Разблокировка по биометрии';

  @override
  String get biometricUnlockSubtitle =>
      'Не вводить пароль — разблокировать биометрическим сенсором устройства.';

  @override
  String get biometricEnableFailed =>
      'Не удалось включить биометрическую разблокировку.';

  @override
  String get biometricUnlockFailed =>
      'Разблокировка по биометрии не удалась. Введите мастер-пароль.';

  @override
  String get biometricUnlockCancelled => 'Разблокировка по биометрии отменена.';

  @override
  String get biometricNotEnrolled =>
      'На этом устройстве не зарегистрированы биометрические данные.';

  @override
  String get biometricSensorNotAvailable =>
      'На этом устройстве нет биометрического датчика.';

  @override
  String get biometricSystemServiceMissing =>
      'Служба отпечатков пальцев (fprintd) не установлена. См. README → Installation.';

  @override
  String get currentPasswordIncorrect => 'Неверный текущий пароль';

  @override
  String get wrongPassword => 'Неверный пароль';

  @override
  String get lockScreenTitle => 'LetsFLUTssh заблокирован';

  @override
  String get lockScreenSubtitle =>
      'Введите мастер-пароль или используйте биометрию, чтобы продолжить.';

  @override
  String get unlock => 'Разблокировать';

  @override
  String get autoLockTitle => 'Автоблокировка при бездействии';

  @override
  String get autoLockSubtitle =>
      'Блокировать интерфейс после указанного периода бездействия. Ключ базы данных стирается и зашифрованное хранилище закрывается при каждой блокировке; активные сессии остаются подключёнными благодаря кэшу учётных данных, который очищается при закрытии сессии.';

  @override
  String get autoLockOff => 'Выкл.';

  @override
  String autoLockMinutesValue(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes минуты',
      many: '$minutes минут',
      few: '$minutes минуты',
      one: '$minutes минута',
    );
    return '$_temp0';
  }

  @override
  String get errReleaseSignatureInvalid =>
      'Обновление отклонено: скачанные файлы не подписаны закреплённым в приложении ключом. Это может означать, что загрузку подделали по пути, либо текущий релиз не предназначен для этой установки. НЕ устанавливайте — вместо этого переустановите приложение вручную с официальной страницы Releases.';

  @override
  String get errReleaseManifestUnavailable =>
      'Не удалось получить manifest релиза. Скорее всего, это проблема с сетью, либо релиз ещё публикуется. Попробуйте ещё раз через пару минут.';

  @override
  String get updateSecurityWarningTitle => 'Проверка обновления не пройдена';

  @override
  String get updateReinstallAction => 'Открыть страницу Releases';

  @override
  String get errLfsNotArchive =>
      'Выбранный файл не является архивом LetsFLUTssh.';

  @override
  String get errLfsDecryptFailed =>
      'Неверный мастер-пароль или повреждённый архив .lfs';

  @override
  String get errLfsArchiveTruncated =>
      'Архив неполный. Перекачайте или пересоздайте его на исходном устройстве.';

  @override
  String errLfsArchiveTooLarge(String sizeMb, String limitMb) {
    return 'Архив слишком большой ($sizeMb МБ). Лимит — $limitMb МБ — прерывание до расшифровки для защиты памяти.';
  }

  @override
  String errLfsKnownHostsTooLarge(String sizeMb, String limitMb) {
    return 'Запись known_hosts слишком большая ($sizeMb МБ). Лимит — $limitMb МБ — импорт прерван, чтобы интерфейс оставался отзывчивым.';
  }

  @override
  String errLfsImportRolledBack(String cause) {
    return 'Импорт не удался — данные восстановлены до состояния перед импортом. ($cause)';
  }

  @override
  String errLfsUnsupportedVersion(int found, int supported) {
    return 'Архив использует схему v$found, а эта сборка поддерживает только до v$supported. Обновите приложение для импорта.';
  }

  @override
  String get progressReadingArchive => 'Чтение архива…';

  @override
  String get progressDecrypting => 'Расшифровка…';

  @override
  String get progressCollectingData => 'Сбор данных…';

  @override
  String get progressEncrypting => 'Шифрование…';

  @override
  String get progressWritingArchive => 'Запись архива…';

  @override
  String get progressWorking => 'Обработка…';

  @override
  String get importFromLink => 'Импорт из QR-ссылки';

  @override
  String get importFromLinkSubtitle =>
      'Вставьте letsflutssh://-ссылку, скопированную с другого устройства';

  @override
  String get pasteImportLinkTitle => 'Вставить ссылку импорта';

  @override
  String get pasteImportLinkDescription =>
      'Вставьте ссылку letsflutssh://import?d=… (или сырой payload), сгенерированную на другом устройстве. Камера не нужна.';

  @override
  String get pasteFromClipboard => 'Вставить из буфера';

  @override
  String get invalidImportLink =>
      'Ссылка не содержит корректные данные LetsFLUTssh';

  @override
  String get importAction => 'Импортировать';

  @override
  String get noTagsAvailable => 'Тегов пока нет — создайте в Tools → Tags.';

  @override
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }

  @override
  String get login => 'Логин';

  @override
  String get protocol => 'Протокол';

  @override
  String get typeLabel => 'Тип';

  @override
  String get folder => 'Папка';

  @override
  String nSubitems(int count) {
    return '$count элемент(ов)';
  }

  @override
  String get subitems => 'Элементы';

  @override
  String get grantPermission => 'Дать разрешение';

  @override
  String get storagePermissionLimited =>
      'Ограниченный доступ — предоставьте полный доступ к хранилищу для всех файлов';

  @override
  String progressConnecting(String host, int port) {
    return 'Подключение к $host:$port';
  }

  @override
  String get progressVerifyingHostKey => 'Проверка ключа хоста';

  @override
  String progressAuthenticating(String user) {
    return 'Аутентификация как $user';
  }

  @override
  String get progressOpeningShell => 'Открытие терминала';

  @override
  String get progressOpeningSftp => 'Открытие SFTP-канала';

  @override
  String get transfersLabel => 'Передачи:';

  @override
  String transferCountActive(int count) {
    return '$count активных';
  }

  @override
  String transferCountQueued(int count) {
    return ', $count в очереди';
  }

  @override
  String transferCountInHistory(int count) {
    return '$count в истории';
  }

  @override
  String transferTooltipCreated(String time) {
    return 'Создано: $time';
  }

  @override
  String transferTooltipStarted(String time) {
    return 'Начато: $time';
  }

  @override
  String transferTooltipEnded(String time) {
    return 'Завершено: $time';
  }

  @override
  String transferTooltipDuration(String duration) {
    return 'Длительность: $duration';
  }

  @override
  String get transferStatusQueued => 'В очереди';

  @override
  String get fileConflictTitle => 'Файл уже существует';

  @override
  String fileConflictMessage(String fileName, String targetDir) {
    return '\"$fileName\" уже существует в $targetDir. Что сделать?';
  }

  @override
  String get fileConflictSkip => 'Пропустить';

  @override
  String get fileConflictKeepBoth => 'Сохранить оба';

  @override
  String get fileConflictReplace => 'Заменить';

  @override
  String get fileConflictApplyAll => 'Применить ко всем оставшимся';

  @override
  String get folderNameLabel => 'ИМЯ ПАПКИ';

  @override
  String folderAlreadyExists(String name) {
    return 'Папка \"$name\" уже существует';
  }

  @override
  String get dropKeyFileHere => 'Перетащите файл ключа сюда';

  @override
  String get sessionNoCredentials =>
      'У сессии нет учётных данных — отредактируйте её, чтобы добавить пароль или ключ';

  @override
  String dragItemCount(int count) {
    return '$count элементов';
  }

  @override
  String qrSelectAll(int selected, int total) {
    return 'Выбрать все ($selected/$total)';
  }

  @override
  String qrPayloadSize(String size, String max) {
    return 'Размер: $size КБ / $max КБ макс.';
  }

  @override
  String get noActiveTerminals => 'Нет активных терминалов';

  @override
  String get connectFromSessionsTab => 'Подключитесь из вкладки Сессии';

  @override
  String fileNotFound(String path) {
    return 'Файл не найден: $path';
  }

  @override
  String itemCountWithSize(int count, String size) {
    return '$count элементов, $size';
  }

  @override
  String get maximize => 'Развернуть';

  @override
  String get restore => 'Восстановить';

  @override
  String get duplicateDownShortcut => 'Дублировать вниз (Ctrl+Shift+\\)';

  @override
  String get security => 'Безопасность';

  @override
  String get knownHosts => 'Известные хосты';

  @override
  String get knownHostsSubtitle =>
      'Управление доверенными отпечатками SSH-серверов';

  @override
  String knownHostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count известных хостов',
      few: '$count известных хоста',
      one: '1 известный хост',
      zero: 'Нет известных хостов',
    );
    return '$_temp0';
  }

  @override
  String get knownHostsEmpty =>
      'Нет известных хостов. Подключитесь к серверу, чтобы добавить.';

  @override
  String get removeHost => 'Удалить хост';

  @override
  String removeHostConfirm(String host) {
    return 'Удалить $host из известных хостов? При следующем подключении потребуется повторная проверка ключа.';
  }

  @override
  String get clearAllKnownHosts => 'Очистить все известные хосты';

  @override
  String get clearAllKnownHostsConfirm =>
      'Удалить все известные хосты? При подключении к каждому серверу потребуется повторная проверка ключа.';

  @override
  String get clearedAllHosts => 'Все известные хосты очищены';

  @override
  String removedHost(String host) {
    return 'Удалён $host';
  }

  @override
  String get tools => 'Инструменты';

  @override
  String get sshKeys => 'SSH-ключи';

  @override
  String get sshKeysSubtitle =>
      'Управление парами SSH-ключей для аутентификации';

  @override
  String get noKeys => 'Нет SSH-ключей. Импортируйте или сгенерируйте.';

  @override
  String get generateKey => 'Сгенерировать ключ';

  @override
  String get addKey => 'Добавить ключ';

  @override
  String get addKeyMenuPaste => 'Вставить PEM';

  @override
  String get filePickerUnavailable =>
      'Файловый пикер недоступен в этой системе';

  @override
  String get importKey => 'Импортировать ключ';

  @override
  String get keyLabel => 'Название ключа';

  @override
  String get keyLabelHint => 'напр. Рабочий сервер, GitHub';

  @override
  String get selectKeyType => 'Тип ключа';

  @override
  String get generating => 'Генерация...';

  @override
  String keyGenerated(String label) {
    return 'Ключ сгенерирован: $label';
  }

  @override
  String keyImported(String label) {
    return 'Ключ импортирован: $label';
  }

  @override
  String get deleteKey => 'Удалить ключ';

  @override
  String deleteKeyConfirm(String label) {
    return 'Удалить ключ \"$label\"? Сессии, использующие его, потеряют доступ.';
  }

  @override
  String keyDeleted(String label) {
    return 'Ключ удалён: $label';
  }

  @override
  String get publicKey => 'Публичный ключ';

  @override
  String get publicKeyCopied => 'Публичный ключ скопирован в буфер обмена';

  @override
  String get sshCertificate => 'Сертификат';

  @override
  String get certImport => 'Импортировать сертификат';

  @override
  String get certImportTooltip =>
      'Прикрепить OpenSSH-сертификат, подписанный вашим CA (файл `-cert.pub` от `ssh-keygen -s …`). Используйте, когда серверы проверяют по подписи CA вместо `authorized_keys`. Пропустите, если ваши серверы используют plain key auth.';

  @override
  String get certImportPickerTitle => 'Выберите файл сертификата OpenSSH';

  @override
  String get certValidFrom => 'Действителен с';

  @override
  String get certValidTo => 'Действителен до';

  @override
  String get certPrincipals => 'Principals';

  @override
  String get certCriticalOptions => 'Critical options';

  @override
  String get certExpiringBanner => 'Срок действия сертификата скоро истекает.';

  @override
  String get certExpired => 'Истёк';

  @override
  String get certRemove => 'Удалить сертификат';

  @override
  String get certRemoveConfirmTitle => 'Удалить сертификат?';

  @override
  String get certRemoveConfirmBody =>
      'После удаления сертификата сессия будет подключаться по обычному публичному ключу.';

  @override
  String errCertParse(String detail) {
    return 'Не удалось разобрать сертификат: $detail';
  }

  @override
  String get errCertPairFingerprintMismatch =>
      'Этот сертификат не привязан к выбранному ключу.';

  @override
  String get pastePrivateKey => 'Вставить приватный ключ (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Некорректный PEM-ключ';

  @override
  String get selectFromKeyStore => 'Выбрать из хранилища ключей';

  @override
  String keyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ключей',
      few: '$count ключа',
      one: '1 ключ',
      zero: 'Нет ключей',
    );
    return '$_temp0';
  }

  @override
  String get generated => 'Сгенерирован';

  @override
  String get passphrase => 'Парольная фраза';

  @override
  String get enterMasterPassword =>
      'Введите мастер-пароль для доступа к сохранённым учётным данным.';

  @override
  String get wrongMasterPassword => 'Неверный пароль. Попробуйте ещё раз.';

  @override
  String get currentPassword => 'Текущий пароль';

  @override
  String get forgotPassword => 'Забыли пароль?';

  @override
  String get credentialsReset => 'Все сохранённые учётные данные удалены';

  @override
  String get migrationToast => 'Хранилище обновлено до текущего формата';

  @override
  String get dbCorruptTitle => 'Не удалось открыть базу данных';

  @override
  String get dbCorruptBody =>
      'Данные на диске не открываются. Попробуйте другие учётные данные или сбросьте и настройте заново.';

  @override
  String get dbCorruptWarning =>
      'Сброс навсегда удалит зашифрованную базу данных и все связанные с безопасностью файлы. Восстановить данные будет невозможно.';

  @override
  String get dbCorruptTryOther => 'Попробовать другие учётные данные';

  @override
  String get dbCorruptResetContinue => 'Сбросить и настроить заново';

  @override
  String get dbCorruptExit => 'Выйти из LetsFLUTssh';

  @override
  String get tierResetTitle => 'Требуется сброс безопасности';

  @override
  String get tierResetBody =>
      'В этой установке есть данные безопасности от прежней версии LetsFLUTssh, использовавшей другую модель уровней. Новая модель — несовместимое изменение, автоматической миграции нет. Чтобы продолжить, все сохранённые сессии, учётные данные, SSH-ключи и известные хосты в этой установке должны быть удалены, а мастер первого запуска — запущен заново.';

  @override
  String get tierResetWarning =>
      'Выбор «Сбросить и настроить заново» безвозвратно удалит зашифрованную базу данных и все связанные с безопасностью файлы. Если нужно восстановить данные, закройте приложение сейчас и переустановите предыдущую версию LetsFLUTssh, чтобы сначала экспортировать их.';

  @override
  String get tierResetResetContinue => 'Сбросить и настроить заново';

  @override
  String get tierResetExit => 'Выйти из LetsFLUTssh';

  @override
  String get derivingKey => 'Генерация ключа шифрования...';

  @override
  String get securitySetupTitle => 'Настройка безопасности';

  @override
  String get keychainAvailable => 'Доступна';

  @override
  String get changeSecurityTierConfirm =>
      'Переашифровываем базу новым уровнем. Не закрывайте приложение до завершения.';

  @override
  String get changeSecurityTierDone => 'Уровень безопасности изменён';

  @override
  String get changeSecurityTierFailed =>
      'Не удалось сменить уровень безопасности';

  @override
  String get firstLaunchSecurityTitle => 'Безопасное хранилище включено';

  @override
  String get firstLaunchSecurityBody =>
      'Данные шифруются ключом из системного хранилища. Разблокировка на этом устройстве — автоматическая.';

  @override
  String get firstLaunchSecurityUpgradeAvailable =>
      'На устройстве доступно аппаратное хранилище. Повысьте уровень в Настройки → Безопасность для привязки к TPM / Secure Enclave.';

  @override
  String get firstLaunchSecurityHardwareUnavailableGeneric =>
      'Аппаратное хранилище недоступно на этом устройстве.';

  @override
  String get firstLaunchSecurityOpenSettings => 'Открыть настройки';

  @override
  String get wizardReducedBanner =>
      'Системное хранилище ключей недоступно на этой установке. Выберите между «без шифрования» (T0) и мастер-паролем (Paranoid). Установите gnome-keyring, kwallet или другой провайдер libsecret, чтобы активировать уровень Keychain.';

  @override
  String get tierBadgeCurrent => 'Текущий';

  @override
  String get securitySetupEnable => 'Включить';

  @override
  String get securitySetupApply => 'Применить';

  @override
  String get hwProbeLinuxDeviceMissing =>
      'TPM не обнаружен на /dev/tpmrm0. Включите fTPM / PTT в BIOS, если машина поддерживает; иначе аппаратный уровень на этом устройстве недоступен.';

  @override
  String get hwProbeLinuxBinaryMissing =>
      'tpm2-tools не установлен. Выполните `sudo apt install tpm2-tools` (или эквивалент в вашем дистрибутиве), чтобы активировать аппаратный уровень.';

  @override
  String get hwProbeLinuxProbeFailed =>
      'Проверка аппаратного уровня не прошла. Проверьте права на /dev/tpmrm0 и udev-правила — подробности в логах.';

  @override
  String get hwProbeWindowsSoftwareOnly =>
      'TPM 2.0 не обнаружен. Включите fTPM / PTT в прошивке UEFI или примите, что аппаратный уровень на этом устройстве недоступен — приложение переходит на программное хранилище учётных данных.';

  @override
  String get hwProbeWindowsProvidersMissing =>
      'Ни Microsoft Platform Crypto Provider, ни Software Key Storage Provider недоступны — вероятно, повреждённая криптоподсистема Windows или Group Policy блокирует CNG. Проверьте Event Viewer → Applications and Services Logs.';

  @override
  String get hwProbeMacosNoSecureEnclave =>
      'На этом Mac нет Secure Enclave (Intel Mac до 2017 года без чипа безопасности T1 / T2). Аппаратный уровень недоступен — используйте мастер-пароль.';

  @override
  String get hwProbeMacosPasscodeNotSet =>
      'На этом Mac не задан пароль входа. Secure Enclave требует его для создания ключа — установите пароль входа в System Settings → Touch ID & Password (или Login Password).';

  @override
  String get hwProbeMacosSigningIdentityMissing =>
      'Secure Enclave отклонил подпись приложения (-34018). Запустите скрипт `macos-resign.sh` из релизного архива, чтобы дать установке стабильную самоподписанную идентичность, и перезапустите приложение.';

  @override
  String get hwProbeIosPasscodeNotSet =>
      'На устройстве не задан код-пароль. Secure Enclave требует его для создания ключа — установите код-пароль в Настройки → Face ID и код-пароль (или Touch ID и код-пароль).';

  @override
  String get hwProbeIosSimulator =>
      'Запуск на iOS Simulator, у которого нет Secure Enclave. Аппаратный уровень доступен только на физических устройствах iOS.';

  @override
  String get hwProbeAndroidApiTooLow =>
      'Для аппаратного уровня требуется Android 9 или новее (StrongBox и инвалидация ключа при изменении биометрии не работают надёжно на более старых версиях).';

  @override
  String get hwProbeAndroidBiometricNone =>
      'На этом устройстве нет биометрического оборудования (отпечаток или лицо). Используйте мастер-пароль.';

  @override
  String get hwProbeAndroidBiometricNotEnrolled =>
      'Биометрия не настроена. Добавьте отпечаток или лицо в Настройки → Безопасность и конфиденциальность → Биометрия, затем повторно включите аппаратный уровень.';

  @override
  String get hwProbeAndroidBiometricUnavailable =>
      'Биометрическое оборудование временно недоступно (блокировка после неудачных попыток или ожидание обновления безопасности). Повторите через несколько минут.';

  @override
  String get hwProbeAndroidKeystoreRejected =>
      'Android Keystore отказал в создании аппаратного ключа на этой сборке устройства (StrongBox недоступен, кастомная ROM или сбой драйвера). Аппаратный уровень недоступен.';

  @override
  String get securityRecheck => 'Проверить поддержку уровней';

  @override
  String get securityRecheckUpdated =>
      'Поддержка уровней обновилась — см. карточки выше';

  @override
  String get securityRecheckUnchanged => 'Поддержка уровней без изменений';

  @override
  String get securityMacosEnableSecureTiers =>
      'Разблокировать безопасные уровни на этом Mac';

  @override
  String get securityMacosEnableSecureTiersSubtitle =>
      'Переподписать приложение личным сертификатом, чтобы Keychain (T1) и Secure Enclave (T2) работали после обновлений';

  @override
  String get securityMacosEnableSecureTiersPrompt =>
      'macOS один раз попросит ваш пароль';

  @override
  String get securityMacosEnableSecureTiersSuccess =>
      'Безопасные уровни разблокированы — T1 и T2 доступны';

  @override
  String get securityMacosEnableSecureTiersFailed =>
      'Не удалось разблокировать безопасные уровни';

  @override
  String get securityMacosOfferTitle => 'Включить Keychain + Secure Enclave?';

  @override
  String get securityMacosOfferBody =>
      'macOS привязывает шифрованное хранилище к identity подписи приложения. Без стабильного сертификата Keychain (T1) и Secure Enclave (T2) отказывают. Можем создать личный самоподписанный сертификат и переподписать приложение — обновления продолжат работать, а секреты переживут релизы. macOS один раз попросит ваш логин-пароль, чтобы доверять новому сертификату.';

  @override
  String get securityMacosOfferAccept => 'Включить';

  @override
  String get securityMacosOfferDecline =>
      'Пропустить — выбрать T0 или Paranoid';

  @override
  String get securityMacosRemoveIdentity =>
      'Удалить подписывающую идентичность';

  @override
  String get securityMacosRemoveIdentitySubtitle =>
      'Удалит личный сертификат. T1 / T2 данные к нему привязаны — сперва переключитесь на T0 или Paranoid, потом удаляйте.';

  @override
  String get securityMacosRemoveIdentityConfirmTitle =>
      'Удалить подписывающую идентичность?';

  @override
  String get securityMacosRemoveIdentityConfirmBody =>
      'Удаляет личный сертификат из login keychain. T1 / T2 сохранённые секреты станут нечитаемыми. Откроется визард для миграции на T0 (plaintext) или Paranoid (master password) перед удалением.';

  @override
  String get securityMacosRemoveIdentitySuccess =>
      'Подписывающая идентичность удалена';

  @override
  String get securityMacosRemoveIdentityFailed =>
      'Не удалось удалить подписывающую идентичность';

  @override
  String get keyringProbeLinuxNoSecretService =>
      'D-Bus работает, но secret-service daemon не запущен. Установите gnome-keyring (`sudo apt install gnome-keyring`) или KWalletManager и включите автозапуск при входе.';

  @override
  String get keyringProbeFailed =>
      'OS keychain недоступен на этом устройстве. Подробности в логах; приложение переходит на мастер-пароль.';

  @override
  String get snippets => 'Сниппеты';

  @override
  String get snippetsSubtitle =>
      'Управление переиспользуемыми командными сниппетами';

  @override
  String get noSnippets => 'Сниппетов пока нет';

  @override
  String get addSnippet => 'Добавить сниппет';

  @override
  String get editSnippet => 'Редактировать сниппет';

  @override
  String get deleteSnippet => 'Удалить сниппет';

  @override
  String deleteSnippetConfirm(String title) {
    return 'Удалить сниппет «$title»?';
  }

  @override
  String get snippetTitle => 'Название';

  @override
  String get snippetTitleHint => 'например, Деплой, Перезапуск';

  @override
  String get snippetCommand => 'Команда';

  @override
  String get snippetCommandHint => 'например, sudo systemctl restart nginx';

  @override
  String get snippetDescription => 'Описание (необязательно)';

  @override
  String get snippetDescriptionHint => 'Что делает эта команда?';

  @override
  String get snippetSaved => 'Сниппет сохранён';

  @override
  String snippetDeleted(String title) {
    return 'Сниппет «$title» удалён';
  }

  @override
  String snippetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сниппета',
      many: '$count сниппетов',
      few: '$count сниппета',
      one: '1 сниппет',
      zero: 'Нет сниппетов',
    );
    return '$_temp0';
  }

  @override
  String get pinToSession => 'Закрепить за этой сессией';

  @override
  String get unpinFromSession => 'Открепить от этой сессии';

  @override
  String get pinnedSnippets => 'Закреплённые';

  @override
  String get allSnippets => 'Все';

  @override
  String get commandCopied => 'Команда скопирована';

  @override
  String get snippetTokensHint =>
      'Нажми чтобы вставить плейсхолдер. Они подставляются при запуске значениями из активной сессии:';

  @override
  String get snippetCustomTokensHint =>
      'Любое другое имя в двойных фигурных скобках спросит у тебя значение при выполнении.';

  @override
  String get snippetFillTitle => 'Заполните параметры сниппета';

  @override
  String get snippetFillSubmit => 'Выполнить';

  @override
  String get broadcastSetDriver => 'Транслировать из этой панели';

  @override
  String get broadcastClearDriver => 'Прекратить трансляцию из этой панели';

  @override
  String get broadcastAddReceiver => 'Принимать трансляцию здесь';

  @override
  String get broadcastRemoveReceiver => 'Прекратить приём трансляции';

  @override
  String get broadcastClearAll => 'Остановить всю трансляцию';

  @override
  String get broadcastPasteTitle => 'Отправить вставку во все панели?';

  @override
  String broadcastPasteBody(int chars, int count) {
    return '$chars символов будут отправлены в $count других панелей.';
  }

  @override
  String get broadcastPasteSend => 'Отправить';

  @override
  String get portForwarding => 'Туннели';

  @override
  String get portForwardingEmpty => 'Правил пока нет';

  @override
  String get addForwardRule => 'Добавить правило';

  @override
  String get editForwardRule => 'Изменить правило';

  @override
  String get deleteForwardRule => 'Удалить правило';

  @override
  String get localForward => 'Локальный';

  @override
  String get remoteForward => 'Удалённый';

  @override
  String get dynamicForward => 'Динамический';

  @override
  String get forwardKind => 'Тип';

  @override
  String get bindAddress => 'Адрес слушания';

  @override
  String get bindPort => 'Порт слушания';

  @override
  String get targetHost => 'Целевой хост';

  @override
  String get targetPort => 'Целевой порт';

  @override
  String get forwardDescription => 'Описание (необязательно)';

  @override
  String get forwardEnabled => 'Включено';

  @override
  String get forwardBindWildcardWarning =>
      'Привязка к 0.0.0.0 открывает туннель на всех интерфейсах — обычно нужен 127.0.0.1.';

  @override
  String get forwardKindLocalHelp =>
      'Локальный: открывает порт на этом устройстве и туннелирует к цели, доступной с SSH-сервера. Удобно для доступа к удалённым БД или админкам через localhost:bindPort.';

  @override
  String get forwardKindRemoteHelp =>
      'Удалённый: просит SSH-сервер открыть порт, туннелирующий обратно к цели, доступной с этого устройства. Удобно чтобы поделиться локальным dev-сервером с удалённым хостом (сервер может требовать GatewayPorts yes для не-loopback bind).';

  @override
  String get forwardKindDynamicHelp =>
      'Динамический: SOCKS5-прокси на этом устройстве, маршрутизирующий каждое соединение через SSH-сервер. Укажи браузеру или curl на localhost:bindPort — весь трафик пойдёт через SSH.';

  @override
  String get proxyJump => 'Подключаться через';

  @override
  String get proxyJumpNone => 'Прямое подключение';

  @override
  String get proxyJumpSavedSession => 'Сохранённая сессия';

  @override
  String get proxyJumpCustom => 'Своё';

  @override
  String get proxyJumpCustomNote =>
      'Свои хопы используют учётные данные этой сессии. Для другой аутентификации бастиона сохрани бастион отдельной сессией.';

  @override
  String viaSessionLabel(String label) {
    return 'через $label';
  }

  @override
  String get recordSession => 'Записывать сессию';

  @override
  String get recordSessionHelp =>
      'Сохранять вывод терминала на диск для этой сессии. Шифруется на диске когда мастер-пароль или аппаратный ключ защищает базу сессий; иначе пишется plaintext рядом с базой.';

  @override
  String get recordingsBrowserTitle => 'Записи';

  @override
  String get recordingsBrowserSubtitle =>
      'Просмотр, воспроизведение и удаление записанных сессий';

  @override
  String get recordingsEmpty => 'Записей пока нет';

  @override
  String get playRecording => 'Воспроизвести';

  @override
  String get deleteRecording => 'Удалить';

  @override
  String get recordingPlaybackTitle => 'Воспроизвести запись';

  @override
  String recordingScrubPositionLabel(String current, String total) {
    return '$current / $total';
  }

  @override
  String get tags => 'Теги';

  @override
  String get tagsSubtitle => 'Организуйте сессии и папки цветными тегами';

  @override
  String get noTags => 'Тегов пока нет';

  @override
  String get addTag => 'Добавить тег';

  @override
  String get deleteTag => 'Удалить тег';

  @override
  String deleteTagConfirm(String name) {
    return 'Удалить тег «$name»? Он будет снят со всех сессий и папок.';
  }

  @override
  String get tagName => 'Имя тега';

  @override
  String get tagNameHint => 'например, Production, Staging';

  @override
  String get tagColor => 'Цвет';

  @override
  String get tagCreated => 'Тег создан';

  @override
  String tagDeleted(String name) {
    return 'Тег «$name» удалён';
  }

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count тега',
      many: '$count тегов',
      few: '$count тега',
      one: '1 тег',
      zero: 'Нет тегов',
    );
    return '$_temp0';
  }

  @override
  String get manageTags => 'Управление тегами';

  @override
  String get editTags => 'Редактировать теги';

  @override
  String get fullBackup => 'Полная резервная копия';

  @override
  String get sessionsOnly => 'Сессии';

  @override
  String get presetFullImport => 'Полный импорт';

  @override
  String get presetSelective => 'Выборочно';

  @override
  String get presetCustom => 'Настраиваемый';

  @override
  String get sessionSshKeys => 'Ключи сессий (из менеджера)';

  @override
  String get allManagerKeys => 'Все ключи из менеджера';

  @override
  String get browseFiles => 'Выбрать файл…';

  @override
  String get sshDirSessionAlreadyImported => 'уже есть в сессиях';

  @override
  String get languageSubtitle => 'Язык интерфейса';

  @override
  String get themeSubtitle => 'Тёмная, светлая или следовать системе';

  @override
  String get uiScaleSubtitle => 'Масштабирование всего интерфейса';

  @override
  String get terminalFontSizeSubtitle => 'Размер шрифта в выводе терминала';

  @override
  String get scrollbackLinesSubtitle => 'Размер буфера истории терминала';

  @override
  String get keepAliveIntervalSubtitle =>
      'Секунды между SSH keep-alive пакетами (0 = выкл)';

  @override
  String get sshTimeoutSubtitle => 'Таймаут подключения в секундах';

  @override
  String get defaultPortSubtitle => 'Порт по умолчанию для новых сессий';

  @override
  String get parallelWorkersSubtitle => 'Параллельных SFTP-воркеров';

  @override
  String get maxHistorySubtitle => 'Максимум сохранённых команд в истории';

  @override
  String get calculateFolderSizesSubtitle =>
      'Показывать суммарный размер рядом с папками в сайдбаре';

  @override
  String get checkForUpdatesOnStartupSubtitle =>
      'Проверять новую версию на GitHub при запуске приложения';

  @override
  String get threatColdDiskTheft => 'Кража диска с выключенной машины';

  @override
  String get threatColdDiskTheftDescription =>
      'Машина выключена, диск вытащили и прочитали на другом компе — или кто-то с доступом к вашему home-каталогу скопировал файл базы.';

  @override
  String get threatKeyringFileTheft => 'Кража файла keyring / keychain';

  @override
  String get threatKeyringFileTheftDescription =>
      'Атакующий читает файл системного хранилища прямо с диска (libsecret keyring, Windows Credential Manager, macOS login keychain) и вытаскивает оттуда wrapped-ключ базы. Hardware-tier защищает независимо от пароля — чип не отдаёт ключ наружу. Для keychain-tier нужен пароль сверху, иначе украденный файл расшифровывается одним OS-паролем входа.';

  @override
  String get modifierOnlyWithPassword => 'только с паролем';

  @override
  String get threatBystanderUnlockedMachine =>
      'Посторонний у разблокированной машины';

  @override
  String get threatBystanderUnlockedMachineDescription =>
      'Кто-то подходит к уже разблокированной машине и открывает приложение, пока вас нет рядом.';

  @override
  String get threatLiveRamForensicsLocked =>
      'Снятие дампа ОЗУ с заблокированной машины';

  @override
  String get threatLiveRamForensicsLockedDescription =>
      'Атакующий морозит ОЗУ (или снимает дамп через DMA) и вытаскивает из дампа ещё живые ключи — даже если приложение заблокировано.';

  @override
  String get threatOsKernelOrKeychainBreach =>
      'Компрометация ядра ОС или keychain';

  @override
  String get threatOsKernelOrKeychainBreachDescription =>
      'Дыра в ядре, утечка keychain или бэкдор в hardware-чипе безопасности. Сама ОС становится атакующим — полагаться на неё больше нельзя.';

  @override
  String get threatOfflineBruteForce => 'Офлайн-перебор слабого пароля';

  @override
  String get threatOfflineBruteForceDescription =>
      'У атакующего есть копия wrapped key или sealed blob — он перебирает пароли в своём темпе, без rate-limit.';

  @override
  String get legendProtects => 'Защищает';

  @override
  String get legendDoesNotProtect => 'Не защищает';

  @override
  String get colT0 => 'T0 Открытый текст';

  @override
  String get colT1 => 'T1 Ключница';

  @override
  String get colT1Password => 'T1 + пароль';

  @override
  String get colT1PasswordBiometric => 'T1 + пароль + биометрия';

  @override
  String get colT2Password => 'T2 + пароль';

  @override
  String get colT2PasswordBiometric => 'T2 + пароль + биометрия';

  @override
  String get colParanoid => 'Параноидальный';

  @override
  String get securityComparisonTableThreatColumn => 'Угроза';

  @override
  String get compareAllTiers => 'Сравнить все уровни';

  @override
  String get resetAllDataTitle => 'Сбросить все данные';

  @override
  String get resetAllDataSubtitle =>
      'Удалить все сессии, ключи, конфигурации и артефакты безопасности. Также очищает записи в связке ключей ОС и слоты аппаратного хранилища.';

  @override
  String get resetAllDataConfirmTitle => 'Сбросить все данные?';

  @override
  String get resetAllDataConfirmBody =>
      'Все сессии, SSH ключи, known hosts, сниппеты, теги, настройки и все артефакты безопасности (записи связки ключей, данные аппаратного хранилища, биометрическая оболочка) будут безвозвратно удалены. Это действие нельзя отменить.';

  @override
  String get resetAllDataConfirmAction => 'Сбросить всё';

  @override
  String resetAllDataConfirmTypePrompt(String phrase) {
    return 'Введите $phrase ниже для подтверждения:';
  }

  @override
  String get resetAllDataInProgress => 'Сброс…';

  @override
  String get resetAllDataDone => 'Все данные сброшены';

  @override
  String get resetAllDataFailed => 'Не удалось выполнить сброс';

  @override
  String get recordingsTitle => 'Записи';

  @override
  String get recordingsStorageUsedLabel => 'Занято';

  @override
  String get recordingsCapLabel => 'Лимит';

  @override
  String get recordingsCapHint =>
      'Жёсткий лимит на папку recordings/. При превышении первой удаляется самая старая запись; текущая запись не трогается.';

  @override
  String get recordingsClearAllAction => 'Удалить все записи';

  @override
  String get recordingsClearAllConfirmTitle => 'Удалить все записи?';

  @override
  String get recordingsClearAllConfirmBody =>
      'Каждая запись сессии в <app>/recordings/ будет удалена. Текущая запись (если есть) останется. Действие необратимо.';

  @override
  String recordingsClearAllResult(int count) {
    return 'Удалено записей: $count';
  }

  @override
  String recordingsCapChangedReclaimed(String bytes) {
    return 'Лимит обновлён. Освобождено: $bytes.';
  }

  @override
  String get recordingsCapChangedNoChange => 'Лимит обновлён. Удалять нечего.';

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
      'Для авто-блокировки нужен пароль на активном уровне.';

  @override
  String get recommendedBadge => 'РЕКОМЕНДУЕТСЯ';

  @override
  String get tierHardwareSubtitleHonest =>
      'Продвинутый: ключ привязан к оборудованию, всегда защищён паролем. Данные невосстановимы, если чип этого устройства утерян или заменён.';

  @override
  String get tierParanoidSubtitleHonest =>
      'Альтернативный: мастер-пароль, без доверия к ОС. Защищает от компрометации ОС. Не улучшает защиту во время выполнения по сравнению с T1/T2.';

  @override
  String get mitigationsNoteRuntimeThreats =>
      'Угрозы во время выполнения (runtime — malware от того же пользователя, дамп памяти живого процесса) показаны как ✗ во всех уровнях. Они устраняются отдельными функциями защиты, применяемыми независимо от выбранного уровня.';

  @override
  String get currentTierBadge => 'ТЕКУЩИЙ';

  @override
  String get paranoidAlternativeHeader => 'АЛЬТЕРНАТИВА';

  @override
  String get modifierPasswordLabel => 'Пароль';

  @override
  String get modifierPasswordSubtitle =>
      'Вводимый секрет — барьер перед разблокировкой хранилища.';

  @override
  String get modifierPasswordRequired =>
      'Обязательно — Hardware-уровень всегда защищён паролем.';

  @override
  String get modifierBiometricLabel => 'Биометрический ярлык';

  @override
  String get modifierBiometricSubtitle =>
      'Получение пароля из биометрически защищённого слота ОС вместо ввода вручную.';

  @override
  String get biometricRequiresPassword =>
      'Сначала включите пароль — биометрия это ярлык для его ввода.';

  @override
  String get biometricRequiresActiveTier =>
      'Сначала выберите этот уровень, чтобы включить биометрический разблок';

  @override
  String get autoLockRequiresActiveTier =>
      'Сначала выберите этот уровень, чтобы настроить автоблокировку';

  @override
  String get biometricForbiddenParanoid =>
      'Paranoid не допускает биометрию по замыслу.';

  @override
  String get fprintdNotAvailable =>
      'fprintd не установлен или нет зарегистрированного отпечатка.';

  @override
  String get t2RequiresPasswordTitle =>
      'Задайте мастер-пароль для Hardware-уровня';

  @override
  String get t2RequiresPasswordBody =>
      'Hardware-уровень требует пароль как модификатор. Биометрия — опциональный ярлык поверх него.';

  @override
  String get t2MigrationPromptTitle => 'Hardware-уровень требует пароль';

  @override
  String get t2MigrationPromptBody =>
      'Существующие установки Hardware без пароля должны задать его сейчас, чтобы продолжить.';

  @override
  String get t2MigrationContinue => 'Продолжить';

  @override
  String get t2MigrationSetPasswordTitle => 'Задайте пароль для Hardware-тира';

  @override
  String get t2MigrationSetPasswordBody =>
      'Введите новый мастер-пароль. DB-ключ, уже запечатанный в hardware-модуле, перезапечатается под этим паролем — сессии и ключи останутся целы.';

  @override
  String get t2MigrationWipeAndRestart => 'Стереть и начать заново';

  @override
  String get t2MigrationResealFailed =>
      'Не удалось перезапечатать Hardware-тир — выберите другой пароль или сотрите всё.';

  @override
  String get biometricOverlayEnable =>
      'Включить биометрический ярлык на Hardware-уровне';

  @override
  String get biometricOverlayEnableSubtitle =>
      'Освобождает пароль из биометрически защищённого слота ОС.';

  @override
  String get biometricOverlayUnavailable =>
      'Биометрическая оболочка пока недоступна на этой платформе.';

  @override
  String get biometricOverlayRequiresPassword =>
      'Сначала задайте пароль Hardware-уровня.';

  @override
  String get t2UnlockTitle => 'Разблокировать мастер-паролем';

  @override
  String get t2UnlockSubtitle => 'Hardware-bound ключ защищён вашим паролем.';

  @override
  String get t2UnlockUseBiometricButton => 'Использовать биометрию';

  @override
  String get t2PasswordChanged => 'Пароль Hardware-уровня обновлён.';

  @override
  String get paranoidMasterPasswordNote =>
      'Настоятельно рекомендуется длинная парольная фраза — Argon2id лишь замедляет перебор, но не блокирует его.';

  @override
  String get plaintextWarningTitle => 'Открытый текст: без шифрования';

  @override
  String get plaintextWarningBody =>
      'Сессии, ключи и known hosts будут храниться без шифрования. Любой, у кого есть доступ к файловой системе этого компьютера, сможет их прочитать.';

  @override
  String get plaintextAcknowledge =>
      'Я понимаю, что мои данные не будут зашифрованы';

  @override
  String get plaintextAcknowledgeRequired =>
      'Подтвердите понимание, прежде чем продолжить.';

  @override
  String get passwordLabel => 'Пароль';

  @override
  String get masterPasswordLabel => 'Мастер-пароль';

  @override
  String get globalErrorTitle => 'Непредвиденная ошибка';

  @override
  String get globalErrorBody =>
      'Произошла непредвиденная ошибка. Приложение продолжит работу.';

  @override
  String get globalErrorLogSavedNote => 'Подробности записаны в журнал.';

  @override
  String get globalErrorLogDisabledNote =>
      'Включите логирование в настройках, чтобы сохранять детали ошибок.';

  @override
  String globalErrorTechnicalLine(String detail) {
    return 'Ошибка: $detail';
  }

  @override
  String get globalErrorEnableLoggingButton => 'Включить логирование';

  @override
  String get globalErrorLoggingEnabledToast =>
      'Логирование включено — ошибки будут сохраняться в журнал';

  @override
  String get fatalErrorQuitButton => 'Выйти';

  @override
  String get fatalErrorWipeButton => 'Удалить все данные';

  @override
  String get fatalErrorWipingButton => 'Удаление…';

  @override
  String get fatalErrorWipeExplanation =>
      'Удаление сотрёт все файлы приложения (конфигурацию, базу, vault-блобы, логи) — следующий запуск начнётся с чистой установки. Это необратимо.';

  @override
  String get fatalErrorWipeConfirmTitle => 'Удалить все данные?';

  @override
  String get fatalErrorWipeConfirmBody =>
      'Это безвозвратно удалит все файлы конфигурации, базы данных и хранилищ. Приложение перезапустится с пустой установкой. Продолжить?';

  @override
  String get fatalErrorWipeConfirmAction => 'Удалить всё';

  @override
  String get unencryptedArchiveWarning =>
      'Архив не защищён паролем. Любой, у кого есть файл, может прочитать содержимое.';

  @override
  String get clipboardCopyFailed => 'Не удалось скопировать в буфер.';

  @override
  String get nonAsciiHostnameWarning =>
      'Имя хоста содержит не-ASCII символы — проверьте каждый символ. Визуально похожие кодпоинты (кириллица / греческий) могут подменить латинский домен.';

  @override
  String get playbackPause => 'Пауза';

  @override
  String get recordingPlayLocked =>
      'Разблокируйте приложение, чтобы воспроизвести зашифрованную запись';

  @override
  String get recordToggleStart => 'Начать запись';

  @override
  String get recordToggleStop => 'Остановить запись';

  @override
  String get foregroundServiceTitle => 'SSH активен';

  @override
  String foregroundServiceConnections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count активных подключений',
      few: '$count активных подключения',
      one: '1 активное подключение',
      zero: 'Нет активных подключений',
    );
    return '$_temp0';
  }

  @override
  String get sessionKindSsh => 'SSH / SFTP';

  @override
  String get sessionKindWebDav => 'WebDAV';

  @override
  String get sessionKindLabel => 'Тип сессии';

  @override
  String get webDavBaseUrl => 'Base URL';

  @override
  String get webDavBaseUrlHint =>
      'https://example.com/remote.php/dav/files/alice/';

  @override
  String get webDavUsername => 'Имя пользователя';

  @override
  String get webDavAuthMethod => 'Метод аутентификации';

  @override
  String get webDavAuthBasic => 'Basic';

  @override
  String get webDavAuthDigest => 'Digest';

  @override
  String get webDavAuthBearer => 'Bearer токен';

  @override
  String get trustedCert => 'Доверенный сертификат (PEM)';

  @override
  String get trustedCertHint => '-----BEGIN CERTIFICATE-----';

  @override
  String get trustedCertHelp =>
      'Вставьте сертификат сервера (один или несколько PEM-блоков). Добавляется как дополнительный root CA только для этой сессии — другие приложения не затрагиваются. Оставьте пустым, чтобы использовать системный trust store.';

  @override
  String get acceptAnyCert => 'Принимать любой сертификат';

  @override
  String get acceptAnyCertHelp =>
      'Пропустить все проверки сертификата и hostname для TLS-handshake\'ов этой сессии. Аварийный выход когда ни системный trust store, ни pinned cert не подходят.';

  @override
  String get acceptAnyCertWarn =>
      'Уязвимо к MITM-атакам — любой в сети может выдать себя за сервер. Используй только в доверенных приватных сетях.';

  @override
  String get webDavCopyUrl => 'Скопировать WebDAV URL';

  @override
  String get webDavOpenInBrowser => 'Открыть в браузере';

  @override
  String get errWebDavAuthFailed => 'Сбой аутентификации WebDAV';

  @override
  String get errWebDavNotFound => 'Путь не найден';

  @override
  String get errWebDavConflict => 'Операция конфликтует с текущим состоянием';

  @override
  String errWebDavGeneric(String detail) {
    return 'WebDAV сервер отклонил запрос: $detail';
  }

  @override
  String get errWebDavBaseUrlRequired => 'Нужен base URL WebDAV';

  @override
  String get errWebDavBaseUrlInvalid =>
      'Base URL должен быть http:// или https://';

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
      'Пусто для AWS, или укажи для MinIO / R2 / Spaces';

  @override
  String get s3PathStyle => 'Path-style адресация';

  @override
  String get s3PathStyleHint => 'Нужно для MinIO; выключи для AWS';

  @override
  String get s3DefaultBucket => 'Bucket по умолчанию';

  @override
  String get s3DefaultPrefix => 'Prefix по умолчанию';

  @override
  String get s3GeneratePresignedUrl => 'Сгенерировать presigned URL';

  @override
  String get s3PresignedUrlExpiry => 'Истекает через';

  @override
  String get s3CopyUri => 'Скопировать s3://bucket/key URI';

  @override
  String get s3PresignedUrlExpiry15min => '15 минут';

  @override
  String get s3PresignedUrlExpiry1hour => '1 час';

  @override
  String get s3PresignedUrlExpiry4hour => '4 часа';

  @override
  String get s3PresignedUrlExpiry24hour => '24 часа';

  @override
  String get s3PresignedUrlExpiry7day => '7 дней';

  @override
  String get errS3AuthFailed =>
      'S3 authentication failed (проверь access key + secret)';

  @override
  String get errS3NoSuchBucket => 'Bucket не существует или недоступен';

  @override
  String get errS3RegionMismatch => 'Bucket в другом регионе, чем настроено';

  @override
  String errS3Generic(String detail) {
    return 'S3 сервер отклонил запрос: $detail';
  }

  @override
  String get syncSection => 'Sync';

  @override
  String get syncEnable => 'Включить WebDAV sync';

  @override
  String get syncPassphrase => 'Sync passphrase';

  @override
  String get syncPassphraseHint =>
      'Шифрует sync-архив. Должен отличаться от мастер-пароля.';

  @override
  String get syncPassphraseSameAsMasterError =>
      'Sync passphrase не должен совпадать с мастер-паролем.';

  @override
  String get syncRemotePath => 'Remote path';

  @override
  String get syncRemotePathHint =>
      'Путь под base URL WebDAV — по умолчанию letsflutssh.lfs';

  @override
  String get syncPushNow => 'Push';

  @override
  String get syncPullNow => 'Pull';

  @override
  String syncLastPushed(String when) {
    return 'Последний push: $when';
  }

  @override
  String syncLastPulled(String when) {
    return 'Последний pull: $when';
  }

  @override
  String get syncNeverRun => 'Никогда';

  @override
  String get syncUpToDate => 'Sync актуален';

  @override
  String syncPushedBytes(String bytes) {
    return 'Отправлено $bytes';
  }

  @override
  String syncPullApplied(int count) {
    return 'Применено $count изменений с remote';
  }

  @override
  String get errSyncDisabled => 'Sync выключён';

  @override
  String get errSyncEtagMismatch =>
      'Remote изменился — сначала pull, потом push';

  @override
  String get errSyncUnauthorized => 'WebDAV-аутентификация не прошла';

  @override
  String errSyncNetwork(String detail) {
    return 'Сетевая ошибка: $detail';
  }

  @override
  String get errSyncArchiveFutureVersion =>
      'Sync-архив с remote требует более новой сборки';

  @override
  String get hardwareKey => 'Hardware key';

  @override
  String get hardwareKeyTapPrompt => 'Коснитесь hardware key';

  @override
  String get hardwareKeyPin => 'PIN hardware key';

  @override
  String get hardwareKeyTimeout => 'Hardware key не ответил';

  @override
  String get hardwareKeyNotFound => 'Hardware key не найден';

  @override
  String get hardwareKeyUnsupported =>
      'Прямой доступ к hardware key недоступен на этой платформе';

  @override
  String get hardwareKeyAppleEntitlementRequired =>
      'Требуется Apple Developer Program entitlement; используйте ssh-agent на macOS';

  @override
  String get skKeyRequiresDevice =>
      'Этому SSH-ключу нужен hardware key — коснитесь устройства для аутентификации';

  @override
  String get errSkWrongPin => 'Неверный PIN';

  @override
  String get hardwareKeyImport => 'Импорт hardware key (sk-*)';

  @override
  String get hardwareKeyBadge => 'Hardware-bound (FIDO2)';

  @override
  String get hardwareKeyPromptCancelled => 'Запрос hardware key отменён';

  @override
  String get agentEndpointSectionTitle => 'Интеграция с внешними SSH-клиентами';

  @override
  String get agentEndpointToggleTitle =>
      'Открыть hardware-bound ключи системным SSH-клиентам';

  @override
  String get agentEndpointToggleSubtitle =>
      'Позволяет git, ssh, плагинам IDE на этом устройстве использовать ваши FIDO2 / smart-card / TPM ключи.';

  @override
  String get agentEndpointPathLabel => 'SSH_AUTH_SOCK';

  @override
  String get agentEndpointPathLabelWindows => 'OpenSSH named pipe';

  @override
  String get agentEndpointCopyEnvVar => 'Скопировать export-команду';

  @override
  String get agentEndpointCopyPipeName => 'Скопировать имя pipe';

  @override
  String get agentEndpointSignatureRequestTitle => 'Запрос на подпись';

  @override
  String agentEndpointSignatureRequestBody(String requester, String keyLabel) {
    return '$requester запрашивает подпись ключом $keyLabel';
  }

  @override
  String get agentEndpointRequesterUnknown => 'Внешний SSH-клиент';

  @override
  String get agentEndpointAuthorizeOnce => 'Разрешить один раз';

  @override
  String get agentEndpointAuthorizeAlways => 'Разрешить и запомнить';

  @override
  String get agentEndpointDeny => 'Отклонить';

  @override
  String get agentEndpointStatusRunning => 'Работает';

  @override
  String get agentEndpointStatusStopped => 'Остановлено';

  @override
  String get agentEndpointStatusUnsupported =>
      'Не поддерживается на этой платформе';

  @override
  String get agentEndpointRefusedAddIdentity =>
      'Отказано: внешние клиенты не могут добавлять ключи.';

  @override
  String agentEndpointStartFailed(String detail) {
    return 'Не удалось запустить ssh-agent endpoint: $detail';
  }

  @override
  String get pkcs11AddTitle => 'Добавить ключ со смарт-карты или токена';

  @override
  String get pkcs11ModuleLabel => 'Модуль PKCS#11';

  @override
  String get pkcs11ModuleAutoDetected => 'Найдено автоматически';

  @override
  String get pkcs11ModuleCustom => 'Указать модуль...';

  @override
  String get pkcs11ModulePickerTitle => 'Выбор библиотеки PKCS#11';

  @override
  String get pkcs11NoModuleFound =>
      'Модуль PKCS#11 не найден. Установите OpenSC или укажите библиотеку вендора.';

  @override
  String get pkcs11InitializeFailed => 'Модуль PKCS#11 не инициализировался.';

  @override
  String get pkcs11NoTokenPresent => 'Нет токена в считывателе.';

  @override
  String pkcs11TokenLabel(String label) {
    return 'Токен: $label';
  }

  @override
  String pkcs11TokenSerial(String serial) {
    return 'Серийный номер: $serial';
  }

  @override
  String get pkcs11LoginRequired => 'Требуется вход на токен.';

  @override
  String pkcs11PinPrompt(String token) {
    return 'PIN для $token';
  }

  @override
  String get pkcs11PinPad => 'Подтвердите на PIN-паде токена.';

  @override
  String pkcs11PinIncorrect(String remaining) {
    return 'Неверный PIN. Осталось попыток: $remaining.';
  }

  @override
  String get pkcs11PinLocked => 'PIN заблокирован. Разблокируйте через PUK.';

  @override
  String get pkcs11NoSignableKeys =>
      'На токене нет ключей, пригодных для SSH (RSA, ECDSA, Ed25519).';

  @override
  String get pkcs11GostUnsupported => 'Ключи GOST не работают по SSH.';

  @override
  String pkcs11TokenUnplugged(String label) {
    return 'Токен \"$label\" не вставлен.';
  }

  @override
  String get pkcs11UriRebindFailed =>
      'Сохранённый токен не найден. Переподключите и повторите.';

  @override
  String pkcs11SignFailed(String reason) {
    return 'Подпись не удалась: $reason';
  }

  @override
  String get pkcs11HwUnavailableMobile =>
      'Смарт-карты и токены PKCS#11 недоступны на этой платформе.';

  @override
  String get pkcs11Badge => 'Смарт-карта / токен';

  @override
  String pkcs11InfoModulePath(String path) {
    return 'Модуль: $path';
  }

  @override
  String pkcs11InfoTokenSerial(String serial) {
    return 'Серийный номер токена: $serial';
  }

  @override
  String pkcs11InfoObjectLabel(String label) {
    return 'Объект: $label';
  }

  @override
  String get pkcs11WizardStepModule => 'Выберите модуль PKCS#11';

  @override
  String get pkcs11WizardStepToken => 'Выберите токен';

  @override
  String get pkcs11WizardStepKey => 'Выберите ключ';

  @override
  String get pkcs11WizardStepPin => 'Введите PIN';

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
  String get pkcs11SaveCta => 'Импортировать ключ';

  @override
  String get pkcs11SaveInProgress => 'Чтение публичного ключа с токена...';

  @override
  String get pkcs11SaveSuccess => 'Ключ со смарт-карты добавлен.';

  @override
  String get pkcs11ScanInProgress => 'Поиск модулей PKCS#11...';

  @override
  String get pkcs11LoadingTokens => 'Загрузка токенов...';

  @override
  String get pkcs11LoadingKeys => 'Загрузка ключей...';

  @override
  String get pkcs11ModuleStatusReady => 'Модуль загружен.';

  @override
  String get pkcs11ModuleStatusNoToken => 'Токен не вставлен.';

  @override
  String get pkcs11ModuleStatusFailed => 'Не удалось загрузить модуль.';

  @override
  String get pkcs11PinPadHint => '(PIN-пад на устройстве)';

  @override
  String get pkcs11WizardBack => 'Назад';

  @override
  String get pkcs11WizardNext => 'Далее';

  @override
  String get sshKeyBackendSoftware => 'Software';

  @override
  String get sshKeyBackendEnclave => 'Secure Enclave';

  @override
  String get sshKeyBackendHello => 'Windows Hello';

  @override
  String get sshKeyBackendFido2 => 'Security key';

  @override
  String get sshKeyAddHardwareBound => 'Добавить hardware-ключ';

  @override
  String get sshKeyHardwareBoundExplainer =>
      'Приватный ключ хранится в защищённом hardware и не может быть экспортирован.';

  @override
  String get sshKeyEnclaveDeviceBound =>
      'Этот ключ работает только на этом Mac.';

  @override
  String get sshKeyEnclaveDeviceBoundIos =>
      'Этот ключ работает только на этом iPhone.';

  @override
  String get sshKeyHelloDeviceBound => 'Этот ключ работает только на этом PC.';

  @override
  String get sshKeyEnclaveTouchIdRequired => 'Требовать Touch ID / Face ID';

  @override
  String get sshKeyEnclavePasscodeFallback =>
      'Разрешить passcode устройства как fallback';

  @override
  String get sshKeyHelloPinRequired =>
      'Требовать Windows Hello (PIN, отпечаток или лицо)';

  @override
  String get sshKeyHardwareUnavailableTitle => 'Hardware-ключи недоступны';

  @override
  String get sshKeyHardwareUnavailableSe =>
      'Для Secure Enclave приложение должно быть подписано.';

  @override
  String get sshKeyHardwareUnavailableHello =>
      'Windows Hello не настроен на этом PC.';

  @override
  String get sshKeyHardwareUnavailableTpm =>
      'TPM не обнаружен — только software-backed.';

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
  String get sshKeyGenerateCta => 'Сгенерировать';

  @override
  String get sshKeyGenerateInProgress =>
      'Генерация ключа в защищённом hardware...';

  @override
  String get sshKeyGenerateMissingEntitlement =>
      'Требуется code-signing — см. USER_GUIDE.md → Hardware-bound keys.';

  @override
  String get sshKeySignInProgress => 'Подписание через защищённое hardware...';

  @override
  String get sshKeyPublicCopy => 'Скопировать публичный ключ';

  @override
  String get sshKeyAuthorizedKeysHint =>
      'Добавьте эту строку в ~/.ssh/authorized_keys на сервере.';

  @override
  String get sshKeyEnclaveWizardTitle => 'SSH-ключ в Secure Enclave';

  @override
  String get sshKeyEnclaveWizardLabelHint => 'Название ключа';

  @override
  String get sshKeyEnclaveBadge => 'Secure Enclave';

  @override
  String get helloWizardTitle => 'SSH-ключ Windows Hello';

  @override
  String get helloWizardLabelHint => 'Метка ключа';

  @override
  String get helloBadge => 'Windows Hello';

  @override
  String get helloPromptTitle => 'Подтвердите через Windows Hello';

  @override
  String get helloPromptDescription =>
      'PIN, отпечаток или лицо — Windows Hello подпишет SSH-запрос.';

  @override
  String get helloSoftwareGatedWarning =>
      'На устройстве нет TPM. Ключ ляжет в пользовательское хранилище; Windows Hello всё равно прогоняет каждую подпись.';

  @override
  String get helloP384NotSupported =>
      'Прошивка TPM не поддерживает P-384. Выберите P-256 или RSA-2048.';

  @override
  String get helloConfigureFirst =>
      'Сначала настройте Windows Hello: Параметры -> Варианты входа.';

  @override
  String get tpmSshTitle => 'Создать SSH-ключ через TPM';

  @override
  String get tpmSshAlgEcdsa => 'ECDSA P-256 (рекомендуется)';

  @override
  String get tpmSshAlgRsa => 'RSA-2048';

  @override
  String get tpmSshAlgUnsupported =>
      'Прошивка TPM не поддерживает этот algorithm.';

  @override
  String get tpmSshPinProtect => 'Защитить PIN';

  @override
  String get tpmSshPinLockoutWarning =>
      'После нескольких неверных PIN TPM блокирует ключ.';

  @override
  String get tpmSshPinMismatch => 'PIN не совпадают.';

  @override
  String get tpmSshStorageBlob => 'Хранить wrapped-ключ в данных приложения';

  @override
  String get tpmSshStorageHandle => 'Положить в слот памяти TPM';

  @override
  String get tpmSshStorageHandleHelp =>
      'Подпись быстрее. Занимает один из persistent-слотов TPM.';

  @override
  String get tpmSshLabel => 'Метка ключа';

  @override
  String get tpmSshImportTitle => 'Импортировать SSH-ключ под TPM';

  @override
  String get tpmSshImportFormat => 'Файл TPM 2.0 (.tpm, TSS2 PRIVATE KEY)';

  @override
  String tpmSshPinPrompt(String label) {
    return 'TPM PIN для $label';
  }

  @override
  String get tpmSshPinIncorrect => 'PIN неверный.';

  @override
  String tpmSshPinLockedCooldown(String duration) {
    return 'TPM в lockout-кулдауне. Подождите $duration и повторите.';
  }

  @override
  String get tpmSshGenerating => 'Создаём ключ в TPM...';

  @override
  String get tpmSshSigning => 'Подписываем через TPM...';

  @override
  String get tpmSshUnavailable => 'TPM на устройстве не найден.';

  @override
  String get tpmSshUnavailableFwDisabled => 'TPM выключен в прошивке.';

  @override
  String get tpmSshUnavailableNoPermission =>
      'Приложение не может обратиться к TPM. Добавьте пользователя в группу `tss`.';

  @override
  String tpmSshHandleInUse(String handle) {
    return 'Слот $handle уже занят.';
  }

  @override
  String get tpmSshBadge => 'TPM 2.0';

  @override
  String get tpmSshSilentWarning =>
      'Ключ подписывает БЕЗ запроса Hello / PIN — пока вы залогинены, любой с доступом к рабочему столу сможет им подписать.';

  @override
  String get keystoreWizardTitle => 'Android Hardware Key';

  @override
  String get keystoreBadge => 'Android Keystore';

  @override
  String get keystoreKeyAndroidLabel => 'Android Keystore (hardware-bound)';

  @override
  String get keystoreKeyStrongBoxLabel => 'StrongBox HSM';

  @override
  String get keystoreKeyTeeLabel => 'TEE (аппаратная привязка)';

  @override
  String get keystoreKeyGenerating => 'Генерируется аппаратный ключ...';

  @override
  String get keystoreKeyAuthPrompt =>
      'Подтвердите личность для использования SSH-ключа';

  @override
  String get keystoreKeyInvalidatedByEnrollment =>
      'Ключ уничтожен: добавлен новый биометрический шаблон. Зарегистрируйте новый публичный ключ на серверах.';

  @override
  String get keystoreKeyStrongBoxUnavailable =>
      'StrongBox HSM недоступен на этом устройстве';

  @override
  String get keystoreKeyUserAuthRequired =>
      'Требовать биометрию / разблокировку устройства для каждой подписи';

  @override
  String get keystoreKeyExportDisabled =>
      'Аппаратные ключи нельзя экспортировать';

  @override
  String get keystoreKeyDeleteWarning =>
      'Удаление ключа сотрёт его из аппаратного хранилища. Серверы будут отклонять этот ключ, пока вы не зарегистрируете новый.';

  @override
  String get keystoreKeyBiometricNotEnrolled =>
      'Сначала настройте биометрию или PIN устройства';

  @override
  String get keystoreAlgEcdsaP256 => 'ECDSA P-256 (поддерживает StrongBox)';

  @override
  String get keystoreAlgEd25519 => 'Ed25519 (Android 13+, только TEE)';

  @override
  String get keystoreAlgRsa2048 => 'RSA-2048 (максимальная совместимость)';

  @override
  String get keystoreStrongBoxFallbackTitle => 'StrongBox HSM недоступен';

  @override
  String get keystoreStrongBoxFallbackBody =>
      'Устройство не отдаёт StrongBox HSM. Создать вместо этого ключ с привязкой к TEE? Аппаратная привязка останется, только без изоляции StrongBox.';

  @override
  String get keystoreStrongBoxFallbackConfirm => 'Использовать TEE';

  @override
  String get keystoreStrongBoxFallbackCancel => 'Отмена';

  @override
  String get fido2BrokerSectionTitle => 'Аппаратные ключи безопасности';

  @override
  String get fido2BrokerWindowsLabel => 'Windows Hello / security key';

  @override
  String get fido2BrokerMacosLabel => 'Системный диалог security key';

  @override
  String get fido2BrokerIosLabel => 'Системный security key (USB / NFC)';

  @override
  String get fido2BrokerAndroidLabel =>
      'Системный security key (USB / NFC / BLE)';

  @override
  String get fido2BrokerTransportDirectHid => 'Прямой USB HID (CTAP2)';

  @override
  String get fido2BrokerTransportNone => 'Недоступно на этой платформе';

  @override
  String get fido2BrokerPreferDirectHidTitle =>
      'Использовать прямой USB HID вместо системного диалога';

  @override
  String fido2BrokerPreferDirectHidSubtitle(String brokerLabel) {
    return 'Для продвинутых пользователей: обойти $brokerLabel там, где работают оба пути. Прямой HID поддерживает больше возможностей аутентификатора, но требует разрешений на доступ к устройству.';
  }

  @override
  String get sshIntegrationSection => 'SSH-интеграция';

  @override
  String get fido2BrokerNoTransportSubtitle =>
      'Поддержка аппаратных ключей недоступна на этом устройстве.';

  @override
  String fido2BrokerSinglePathSubtitle(String transport) {
    return 'На этом устройстве доступен только $transport; переключатель отключён.';
  }

  @override
  String get hardwareKeyStubBadge => 'Импортированный стаб';

  @override
  String get hardwareKeyStubSubtitle =>
      'Импортирован с другого устройства — сгенерируйте здесь, чтобы использовать';

  @override
  String get hardwareKeyStubRegenerateAction => 'Сгенерировать здесь';

  @override
  String get hardwareKeyStubRemoveAction => 'Удалить стаб';

  @override
  String get hardwareKeyStubPickerTooltip =>
      'Сгенерируйте этот ключ на этом устройстве перед использованием';

  @override
  String pkcs11ModuleResolveOnFirstUse(String token) {
    return 'Укажите путь к модулю PKCS#11 для токена «$token»';
  }
}
