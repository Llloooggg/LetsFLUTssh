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
  String get paste => 'Вставить';

  @override
  String get select => 'Выбрать';

  @override
  String get required => 'Обязательное поле';

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
  String get includeCredentials => 'Включить пароли и SSH ключи';

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
  String get qrCredentialsWarning => 'Пароли и SSH ключи БУДУТ видны в QR-коде';

  @override
  String get qrCredentialsTooLarge =>
      'Учётные данные делают QR-код слишком большим';

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
  String sshKeyReceived(String filename) {
    return 'SSH-ключ получен: $filename';
  }

  @override
  String importedSessionsViaQr(int count) {
    return 'Импортировано сессий через QR: $count';
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
  String get noSessionsToExport => 'Нет сессий для экспорта';

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
  String get options => 'Параметры';

  @override
  String get sessionName => 'Имя сессии';

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
  String get hidePemText => 'Скрыть PEM-текст';

  @override
  String get pastePemKeyText => 'Вставить PEM-текст ключа';

  @override
  String get hintPemKey => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get noAdditionalOptionsYet => 'Дополнительных параметров пока нет';

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
  String errorPrefix(String error) {
    return 'Ошибка: $error';
  }

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
  String get initializingSftp => 'Инициализация SFTP...';

  @override
  String get clearHistory => 'Очистить историю';

  @override
  String get noTransfersYet => 'Передач пока нет';

  @override
  String get duplicateTab => 'Дублировать вкладку';

  @override
  String get duplicateTabShortcut => 'Дублировать вкладку (Ctrl+\\)';

  @override
  String get copyDown => 'Копировать вниз';

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
  String get exportDataSubtitle =>
      'Сохранить сессии, конфигурацию и ключи в зашифрованный файл .lfs';

  @override
  String get importDataSubtitle => 'Загрузить данные из файла .lfs';

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
  String sshConfigPreviewFolderLabel(String folder) {
    return 'Импортировано в папку: $folder';
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
  String get hintLfsPath => '/путь/к/файлу.lfs';

  @override
  String get browse => 'Обзор';

  @override
  String get shareViaQrCode => 'Поделиться через QR-код';

  @override
  String get shareViaQrSubtitle =>
      'Экспортировать сессии в QR для сканирования другим устройством';

  @override
  String get dataLocation => 'Расположение данных';

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
  String get enableLogging => 'Включить журналирование';

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
  String get anotherInstanceRunning =>
      'Другой экземпляр LetsFLUTssh уже запущен.';

  @override
  String importFailedShort(String error) {
    return 'Ошибка импорта: $error';
  }

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
  String get qrNoCredentialsWarning =>
      'Пароли и SSH-ключи НЕ включены.\nДля импортированных сессий потребуется заполнить учётные данные.';

  @override
  String get qrTooManyForSingleCode =>
      'Слишком много сессий для одного QR-кода. Снимите часть выделения или используйте экспорт в .lfs.';

  @override
  String get qrTooLarge =>
      'Слишком большой объём — снимите часть выделения или используйте экспорт в файл .lfs.';

  @override
  String get exportAll => 'Экспортировать все';

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
  String errShellError(String error) {
    return 'Ошибка оболочки: $error';
  }

  @override
  String errReconnectFailed(String error) {
    return 'Ошибка повторного подключения: $error';
  }

  @override
  String errSftpInitFailed(String error) {
    return 'Не удалось инициализировать SFTP: $error';
  }

  @override
  String errDownloadFailed(String error) {
    return 'Ошибка загрузки: $error';
  }

  @override
  String get errDecryptionFailed =>
      'Не удалось расшифровать учётные данные. Файл ключа может быть повреждён.';

  @override
  String get errExportPickerUnavailable =>
      'Системный выбор папки недоступен. Попробуйте другое расположение или проверьте разрешения на доступ к хранилищу.';

  @override
  String get biometricUnlockPrompt => 'Разблокировать LetsFLUTssh';

  @override
  String get biometricUnlockTitle => 'Разблокировка по биометрии';

  @override
  String get biometricUnlockSubtitle =>
      'Не вводить мастер-пароль при запуске приложения.';

  @override
  String get biometricNotAvailable =>
      'Биометрическая разблокировка недоступна на этом устройстве.';

  @override
  String get biometricEnableFailed =>
      'Не удалось включить биометрическую разблокировку.';

  @override
  String get biometricEnabled => 'Биометрическая разблокировка включена';

  @override
  String get biometricDisabled => 'Биометрическая разблокировка отключена';

  @override
  String get biometricUnlockFailed =>
      'Разблокировка по биометрии не удалась. Введите мастер-пароль.';

  @override
  String get biometricUnlockCancelled => 'Разблокировка по биометрии отменена.';

  @override
  String get biometricNotEnrolled =>
      'На этом устройстве не зарегистрированы биометрические данные.';

  @override
  String get biometricRequiresMasterPassword =>
      'Сначала задайте мастер-пароль, чтобы включить разблокировку по биометрии.';

  @override
  String get biometricSensorNotAvailable =>
      'На этом устройстве нет биометрического датчика.';

  @override
  String get autoLockRequiresMasterPassword =>
      'Сначала задайте мастер-пароль, чтобы включить авто-блокировку.';

  @override
  String get currentPasswordIncorrect => 'Неверный текущий пароль';

  @override
  String get wrongPassword => 'Неверный пароль';

  @override
  String get useKeychain => 'Шифровать ключом ОС';

  @override
  String get useKeychainSubtitle =>
      'Хранить ключ базы данных в системном хранилище учётных данных. Выкл. = база данных без шифрования.';

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
      'Блокировать интерфейс после указанного периода бездействия. Зашифрованная база перезакрывается только когда нет активных SSH-сессий — длительные операции не прерываются.';

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
  String get progressParsingArchive => 'Разбор архива…';

  @override
  String get progressImportingSessions => 'Импорт сессий';

  @override
  String get progressImportingFolders => 'Импорт папок';

  @override
  String get progressImportingManagerKeys => 'Импорт SSH-ключей';

  @override
  String get progressImportingTags => 'Импорт тегов';

  @override
  String get progressImportingSnippets => 'Импорт сниппетов';

  @override
  String get progressApplyingConfig => 'Применение конфигурации…';

  @override
  String get progressImportingKnownHosts => 'Импорт known_hosts…';

  @override
  String get progressCollectingData => 'Сбор данных…';

  @override
  String get progressEncrypting => 'Шифрование…';

  @override
  String get progressWritingArchive => 'Запись архива…';

  @override
  String get progressReencrypting => 'Повторное шифрование…';

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
  String get saveSessionToAssignTags =>
      'Сначала сохраните сессию, чтобы назначить теги';

  @override
  String get noTagsAssigned => 'Теги не назначены';

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
  String get storagePermissionRequired =>
      'Для просмотра локальных файлов необходимо разрешение на доступ к хранилищу';

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
  String get transferStartingUpload => 'Начало загрузки...';

  @override
  String get transferStartingDownload => 'Начало скачивания...';

  @override
  String get transferCopying => 'Копирование...';

  @override
  String get transferDone => 'Готово';

  @override
  String transferFilesProgress(int done, int total) {
    return '$done/$total файлов';
  }

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
  String get sshConnectionChannel => 'SSH-соединение';

  @override
  String get sshConnectionChannelDesc =>
      'Поддержание SSH-соединений в фоновом режиме.';

  @override
  String get sshActive => 'SSH активен';

  @override
  String activeConnectionCount(int count) {
    return '$count активных соединений';
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
  String get importKnownHosts => 'Импорт известных хостов';

  @override
  String get importKnownHostsSubtitle => 'Импорт из файла OpenSSH known_hosts';

  @override
  String get exportKnownHosts => 'Экспорт известных хостов';

  @override
  String importedHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Импортировано $count новых хостов',
      few: 'Импортировано $count новых хоста',
      one: 'Импортирован 1 новый хост',
      zero: 'Не добавлено новых хостов',
    );
    return '$_temp0';
  }

  @override
  String get clearedAllHosts => 'Все известные хосты очищены';

  @override
  String removedHost(String host) {
    return 'Удалён $host';
  }

  @override
  String get noHostsToExport => 'Нет хостов для экспорта';

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
  String get pastePrivateKey => 'Вставить приватный ключ (PEM)';

  @override
  String get pemHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get invalidPem => 'Некорректный PEM-ключ';

  @override
  String get selectFromKeyStore => 'Выбрать из хранилища ключей';

  @override
  String get noKeySelected => 'Ключ не выбран';

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
  String get passphraseRequired => 'Требуется парольная фраза';

  @override
  String passphrasePrompt(String host) {
    return 'SSH-ключ для $host зашифрован. Введите парольную фразу для разблокировки.';
  }

  @override
  String get passphraseWrong => 'Неверная парольная фраза. Попробуйте ещё раз.';

  @override
  String get passphrase => 'Парольная фраза';

  @override
  String get rememberPassphrase => 'Запомнить для этой сессии';

  @override
  String get masterPasswordSubtitle =>
      'Защита сохранённых учётных данных паролем';

  @override
  String get setMasterPassword => 'Установить мастер-пароль';

  @override
  String get changeMasterPassword => 'Изменить мастер-пароль';

  @override
  String get removeMasterPassword => 'Удалить мастер-пароль';

  @override
  String get masterPasswordEnabled => 'Учётные данные защищены мастер-паролем';

  @override
  String get masterPasswordDisabled =>
      'Учётные данные используют автогенерированный ключ (без пароля)';

  @override
  String get enterMasterPassword =>
      'Введите мастер-пароль для доступа к сохранённым учётным данным.';

  @override
  String get wrongMasterPassword => 'Неверный пароль. Попробуйте ещё раз.';

  @override
  String get newPassword => 'Новый пароль';

  @override
  String get currentPassword => 'Текущий пароль';

  @override
  String get masterPasswordSet => 'Мастер-пароль установлен';

  @override
  String get masterPasswordChanged => 'Мастер-пароль изменён';

  @override
  String get masterPasswordRemoved => 'Мастер-пароль удалён';

  @override
  String get masterPasswordWarning =>
      'Если вы забудете этот пароль, все сохранённые пароли и SSH-ключи будут потеряны. Восстановление невозможно.';

  @override
  String get forgotPassword => 'Забыли пароль?';

  @override
  String get forgotPasswordWarning =>
      'Это удалит ВСЕ сохранённые пароли, SSH-ключи и парольные фразы. Сессии и настройки будут сохранены. Это действие необратимо.';

  @override
  String get resetAndDeleteCredentials => 'Сбросить и удалить данные';

  @override
  String get credentialsReset => 'Все сохранённые учётные данные удалены';

  @override
  String get derivingKey => 'Генерация ключа шифрования...';

  @override
  String get reEncrypting => 'Перешифрование данных...';

  @override
  String get confirmRemoveMasterPassword =>
      'Введите текущий пароль для отключения защиты мастер-паролем. Учётные данные будут перешифрованы автогенерированным ключом.';

  @override
  String get securitySetupTitle => 'Настройка безопасности';

  @override
  String securitySetupKeychainFound(String keychainName) {
    return 'Обнаружена связка ключей ОС ($keychainName). Ваши данные будут автоматически зашифрованы с использованием системной связки ключей.';
  }

  @override
  String get securitySetupKeychainOptional =>
      'Вы также можете установить мастер-пароль для дополнительной защиты.';

  @override
  String get securitySetupNoKeychain =>
      'Связка ключей ОС не обнаружена. Без неё данные сессий (хосты, пароли, ключи) будут храниться в открытом виде.';

  @override
  String get securitySetupNoKeychainHint =>
      'Это нормально для WSL, безголового Linux или минимальных установок. Для включения связки ключей в Linux: установите libsecret и демон связки ключей (напр. gnome-keyring).';

  @override
  String get securitySetupRecommendMasterPassword =>
      'Рекомендуем установить мастер-пароль для защиты ваших данных.';

  @override
  String get continueWithKeychain => 'Продолжить со связкой ключей';

  @override
  String get continueWithoutEncryption => 'Продолжить без шифрования';

  @override
  String get securityLevel => 'Уровень безопасности';

  @override
  String get securityLevelPlaintext => 'Нет';

  @override
  String get securityLevelKeychain => 'Связка ключей ОС';

  @override
  String get securityLevelMasterPassword => 'Мастер-пароль';

  @override
  String get keychainStatus => 'Связка ключей';

  @override
  String get keychainAvailable => 'Доступна';

  @override
  String get keychainNotAvailable => 'Недоступна';

  @override
  String get enableKeychain => 'Включить шифрование через связку ключей';

  @override
  String get enableKeychainSubtitle =>
      'Перешифровать сохранённые данные с помощью связки ключей ОС';

  @override
  String get keychainEnabled => 'Шифрование через связку ключей включено';

  @override
  String get manageMasterPassword => 'Управление мастер-паролем';

  @override
  String get manageMasterPasswordSubtitle =>
      'Установить, изменить или удалить мастер-пароль';

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
  String get runSnippet => 'Запустить';

  @override
  String get pinToSession => 'Закрепить за этой сессией';

  @override
  String get unpinFromSession => 'Открепить от этой сессии';

  @override
  String get pinnedSnippets => 'Закреплённые';

  @override
  String get allSnippets => 'Все';

  @override
  String get sendToTerminal => 'Отправить в терминал';

  @override
  String get commandCopied => 'Команда скопирована';

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
  String get sessionKeysFromManager => 'Ключи сессий из менеджера';

  @override
  String get allKeysFromManager => 'Все ключи из менеджера';

  @override
  String exportTags(int count) {
    return 'Теги ($count)';
  }

  @override
  String exportSnippets(int count) {
    return 'Сниппеты ($count)';
  }

  @override
  String get disableKeychain => 'Отключить шифрование связки ключей';

  @override
  String get disableKeychainSubtitle =>
      'Перейти к хранению в открытом виде (не рекомендуется)';

  @override
  String get disableKeychainConfirm =>
      'База данных будет перешифрована без ключа. Сессии и ключи будут храниться на диске в открытом виде. Продолжить?';

  @override
  String get keychainDisabled => 'Шифрование связки ключей отключено';

  @override
  String get presetFullImport => 'Полный импорт';

  @override
  String get presetSelective => 'Выборочно';

  @override
  String get presetCustom => 'Настраиваемый';

  @override
  String get sessionSshKeys => 'SSH-ключи сессий';

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
  String get enableLoggingSubtitle =>
      'Записывать события приложения в ротируемый лог-файл';

  @override
  String get exportWithoutPassword => 'Экспортировать без пароля?';

  @override
  String get exportWithoutPasswordWarning =>
      'Архив не будет зашифрован. Любой, кто получит доступ к файлу, сможет прочитать ваши данные, включая пароли и приватные ключи.';

  @override
  String get continueWithoutPassword => 'Продолжить без пароля';
}
