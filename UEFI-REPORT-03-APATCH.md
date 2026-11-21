# Обновление для APatch

Создание service.d больше не требует установленного Magisk. Поддерживается
общий механизм /data/adb/service.d, используемый APatch. На реальном APatch
ещё не проверено; если автозапуск не сработает, используй collect вручную.
Прошивка UEFI та же 03, повторно запускать её ради обновления скрипта не нужно.
Архив распаковывается в прежнюю папку DBY-W09-UEFI-report-03: приватное
состояние и существующие резервные копии не удаляются.

ВАЖНО: ранее опубликованный DBY-W09-RESTORE-BOOT-03.zip содержит прежний
предоставленный boot, а не новый APatch boot. После восстановления APatch
может исчезнуть/смениться прежним root. prepare сохранит текущий APatch boot
локально, но если Data в recovery зашифрована, этот бэкап там недоступен.
Для sideload-восстановления именно нынешнего APatch нужен его boot.img;
без него создать такой rescue ZIP невозможно. Root-доступ после возврата
нужен и для автоматического сбора. Не перепрошивай UEFI ради проверки APatch.

# DBY-W09 UEFI 03: этапы загрузки и отчёты

Экспериментальная сборка. Аппаратно не проверена. Windows ещё не готова.
Образ без подписи Huawei/AVB. start заменяет boot, автоматического возврата
Android нет. Для возврата нужен TWRP/OrangeFox и sideload с другого смартфона.
Data не форматировать. Бэкап во внутренней памяти может быть зашифрован!

## До запуска

Скачай DBY-W09-RESTORE-BOOT-03.zip на ДРУГОЙ смартфон заранее:
https://raw.githubusercontent.com/danilafilippkin092-debug/Gpt6astra/main/DBY-W09-RESTORE-BOOT-03.zip
Этот ZIP поддерживает UEFI 01/02/03. Старый rescue ZIP не поддерживает 03.
Проверь, что можешь войти кнопками в recovery и подключиться через sideload.
Сохрани смартфон, ZIP, кабель и OTG до полного восстановления Android.

В обычном Termux (не su):

```sh
pkg install python curl tar
cd ~
curl -fL -o DBY-W09-UEFI-report-03-APatch.tar.gz https://raw.githubusercontent.com/danilafilippkin092-debug/Gpt6astra/main/DBY-W09-UEFI-report-03-APatch.tar.gz
curl -fL -o DBY-W09-UEFI-report-03-APatch.tar.gz.sha256 https://raw.githubusercontent.com/danilafilippkin092-debug/Gpt6astra/main/DBY-W09-UEFI-report-03-APatch.tar.gz.sha256
sha256sum -c DBY-W09-UEFI-report-03-APatch.tar.gz.sha256
```

Продолжай только если проверка завершилась OK:

```sh
tar -xzf DBY-W09-UEFI-report-03-APatch.tar.gz &&
cd DBY-W09-UEFI-report-03 &&
sha256sum -c SHA256SUMS &&
python uefi_test.py prepare
```

Разреши root. prepare сохраняет boot и устанавливает сборщик APatch/Magisk
/data/adb/service.d/95-dby-uefi-report.sh. Разделы не прошивает.
Папка теста: /sdcard/DBY-UEFI-REPORT-03. Требуется >=384 МиБ свободного места.
Если prepare завершился STOP, не обходи проверки.
Только при готовом recovery и ZIP на другом смартфоне:

```sh
python uefi_test.py start --recovery-checked --rescue-ready
```

Флаги подтверждают проверенный вход в recovery и готовность внешнего
восстановления через sideload. Это не проверка расшифровки Data.
Команда автоматически проверяет и прошивает boot, затем перезагружает планшет.

## Что записывает UEFI

Метки [DBY03] начиная с BDS: EndOfDxe, отложенные драйверы, консоль,
подключение контроллеров, меню, LoadImage/StartImage. Это не полный debug log.
Буфер 16 КиБ, работает только до ExitBootServices. Более ранний сбой
SEC/PEI/DXE или аппаратный reset может не оставить меток вообще.
Программный watchdog отключается при достижении соответствующего этапа;
это не отключение всех аппаратных watchdog и не гарантия остановки бутлупа.

Если подключена FAT USB-флешка и заработали USB/SFS, после подключения
контроллеров UEFI создаст на ней reports_uefi/UEFI03-NNN.log и будет
обновлять журнал при следующих отметках. Внутренние разделы для журнала
не открываются. Лог на USB возможен только ПОСЛЕ успешного подключения;
сбой внутри подключения может остаться лишь на экране. Сохранение до
аварийного сброса не гарантируется. При отсутствии носителя — экран и RAM.
Журнал USB НЕ копируется в Android автоматически: это отдельный носитель.

Меню, Shell, EFI browser и базовый ACPI сохранены. Периферийный ACPI и
драйверы Windows не готовы. Shell/запущенные вручную EFI могут менять диски.

## Вернуть Android

В TWRP включи ADB Sideload. На другом смартфоне через Bugjaeger передай
DBY-W09-RESTORE-BOOT-03.zip. Только после SUCCESS и проверки SHA256
выбери Reboot System. При ERROR не перезагружайся и пришли текст.
ZIP восстанавливает только предоставленный оригинальный boot и не форматирует Data.

## Где отчёт

После успешного восстановления Android и разблокировки экрана APatch/Magisk-сборщик
ожидает до 10 минут доступности памяти. При успехе создаёт:

/sdcard/reports_uefi/android-after-uefi-ДАТА-ВРЕМЯ-PID.tar.gz

Внутри: состояние теста, текущий хеш boot, Android dmesg (до 1 МиБ),
причина загрузки, ядро и до 8 файлов pstore по 256 КиБ. Android dmesg —
журнал ТЕКУЩЕГО Android, pstore может быть пустым или относиться к другому
сбою. Это НЕ автоматически записанный вывод UEFI и не доказательство его запуска.
В архив не включаются образы разделов. Логи могут содержать сведения об устройстве;
перед отправкой их можно просмотреть. Сборщик ничего не отправляет по сети.

Если автоматического архива нет, в Termux:

```sh
cd ~/DBY-W09-UEFI-report-03
python uefi_test.py collect
```

Это только сбор, без прошивки и перезагрузки. Для добавления своих наблюдений:

```sh
python uefi_test.py report
```

Введи описание и Enter, затем пришли новый архив из reports_uefi.
Если есть USB-лог, пришли его отдельно. Перезапускать UEFI для отчёта не нужно.

## Удалить автосборщик после теста

```sh
su -c 'rm -f /data/adb/service.d/95-dby-uefi-report.sh /data/adb/dby-uefi-report/pending /data/adb/dby-uefi-report/collect.sh'
```

Сборщик запускается только для заранее отмеченного теста и после успеха
снимает отметку. Отчёты и резервные копии эта команда не удаляет.

## Проверки и исходники

19 Python-тестов установки/отката и исходного Linux boot; host-имитация
сборщика; 5 сценариев rescue. Проверено совпадение 48 родных vendor EFI,
BootShim+FD, DTB, адресов и контрольных сумм четырёх базовых ACPI-таблиц.
Ни один из этих тестов не подтверждает работу нового образа на планшете.
source/ содержит изменённый BootManager и основу 02, JOURNAL-03.patch —
изменения журналирования; UEFI-SOURCE-CHANGES.patch — первоначальная адаптация.
Upstream WQSQW/uefi-dby_w09, база 423e222159dfa159d788769554007455d34e6193,
DEBUG CLANGPDB/Clang19, FD 0xce000000 / 8 МиБ, Secure Boot disabled.
