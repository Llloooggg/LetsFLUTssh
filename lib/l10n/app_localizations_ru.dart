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
  String get couldNotOpenInstaller => 'Не удалось открыть установщик';

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
  String get sessions => 'Сессии';

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
  String get quickConnect => 'Быстрое подключение';

  @override
  String get scanQrCode => 'Сканировать QR-код';

  @override
  String get qrGenerationFailed => 'Не удалось создать QR-код';

  @override
  String get scanWithCameraApp =>
      'Сканируйте любым приложением камеры на устройстве,\nгде установлен LetsFLUTssh.';

  @override
  String get noPasswordsInQr => 'В этом QR-коде нет паролей и ключей';

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
  String get confirmPassword => 'Подтвердите пароль';

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
  String get copyRight => 'Копировать вправо';

  @override
  String get copyDown => 'Копировать вниз';

  @override
  String get closePane => 'Закрыть панель';

  @override
  String get previous => 'Предыдущий';

  @override
  String get next => 'Следующий';

  @override
  String get closeEsc => 'Закрыть (Esc)';

  @override
  String get copyRightShortcut => 'Копировать вправо (Ctrl+\\)';

  @override
  String get copyDownShortcut => 'Копировать вниз (Ctrl+Shift+\\)';

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
  String errWithPath(String error, String path) {
    return '$error: $path';
  }

  @override
  String errWithCause(String error, String cause) {
    return '$error ($cause)';
  }
}
