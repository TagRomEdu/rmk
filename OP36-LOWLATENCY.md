# OP36 low-latency

Личная ветка `op36-lowlatency` поверх официальной прошивки Ergohaven RMK для Omega Point 36.
Отличается от релиза только задержками; раскладка, Vial и Entropy работают как в оригинале.

Remotes: `origin` — апстрим `ergohaven/rmk`, `fork` — этот репозиторий.

## Что изменено относительно релиза

| Параметр | Релиз | Здесь | Где |
|---|---|---|---|
| Debounce матрицы | 20 мс | 5 мс | `keyboards/op36/keyboard.toml`, `[rmk] debounce_time` |
| Интервал связи правой половинки с левой | 15 мс | 7.5 мс | `rmk/src/split/ble/central.rs`, `active_central_conn_param` |
| Шаг mouse keys | 20 мс (50 Гц) | 8 мс (125 Гц) | `keyboards/op36/keyboard.toml`, `[rmk] mouse_key_interval` |
| Сдвиг курсора за шаг | 5 px | 2 px | `rmk/src/config/behavior.rs`, `MouseKeyConfig::default` |
| Шагов до макс. скорости | 50 | 125 | там же, `ticks_to_max` |
| Макс. множитель скорости курсора | 3 | 4 | там же, `max_speed` |
| Опрос заряда `08 E8 01` | будит клавиатуру | не считается активностью | `rmk/src/host/via/mod.rs`, `is_battery_halves_query` |

Курсор: 250 px/с на старте (как в релизе), 1000 px/с максимум (в релизе 750), разгон ~1 с.

Опрос заряда: каждый Vial-пакет по BLE считался активностью — сбрасывал таймеры сна и на 30 с
выключал peripheral latency связи с ПК. Виджет в баре опрашивает раз в минуту, поэтому
клавиатура не засыпала, а оба split-линка постоянно работали на 7.5 мс. Теперь команда
заряда половинок проходит мимо таймеров; остальные Vial-команды (Entropy) будят как раньше.

Цена 7.5 мс на split-линке — правая половинка расходует батарею быстрее.

Инфраструктура сборки (в апстриме её нет):

- `flake.nix` — devShell дополнен `libclang`, `gcc-arm-embedded` (заголовки для bindgen в
  `nrf-mpsl-sys`, `arm-none-eabi-objcopy`) и `perl`;
- `scripts/op36_uf2.sh` — сборка и упаковка UF2 одной командой.

## Сборка

```sh
nix develop -c scripts/op36_uf2.sh
```

Файлы появятся в `keyboards/op36/target/uf2/`: `op36_left.uf2`, `op36_right.uf2` и их SHA256.
Если зарубежные ресурсы недоступны напрямую — запускать через прокси (`px nix develop ...`),
cargo тянет крейты и git-зависимости.

Предупреждение `[storage].start_addr = 0xcc000 has no effect with DFU` есть и в релизной
сборке, на работу не влияет.

## Прошивка

Для каждой половинки (сначала левая — она central, потом правая):

1. Подключить по USB-C, дважды быстро нажать `Reset` на дне. Для левой можно `QK_BOOT` на слое Adjust.
2. Появится диск `NRF52BOOT` — скопировать на него `op36_left.uf2` или `op36_right.uf2`.
3. Половинка перезагрузится сама. Ошибку извлечения диска игнорировать.

После обеих — одновременно нажать `Reset` на двух половинках.

`settings_reset.uf2` **не нужен**: при смене `BUILD_HASH` прошивка только обновляет метку
в хранилище (`rmk/src/storage/mod.rs`, `check_enable`), раскладка, настройки Tap-Hold и
BT-пары сохраняются. Сброс нужен только при переходе с другой прошивки (ZMK) или при поломке
хранилища.

Правая после прошивки по USB не видна — это нормально, peripheral работает только по BLE.

## Обновление на новую версию Ergohaven

```sh
git fetch origin --tags
git switch op36-lowlatency
git rebase <новый-тег>          # например v0.1.9
nix develop -c scripts/op36_uf2.sh
git push --force-with-lease fork op36-lowlatency
```

Что проверить после rebase:

- `keyboards/op36/keyboard.toml` — строки `debounce_time` и `mouse_key_interval` на месте;
- `active_central_conn_param` в `rmk/src/split/ble/central.rs` — `Keyboard` остался 7.5 мс
  (функция может переехать или переименоваться — искать по `SplitLinkProfile::Keyboard`);
- `MouseKeyConfig::default` — `move_delta: 2`, `max_speed: 4`, `ticks_to_max: 125`;
- в `rmk/src/ble/mod.rs` перед `VIAL_BLE_ACTIVITY.signal` осталась проверка `is_battery_halves_query`;
- тест `keyboard_profile_uses_7_5_ms_cadence` — если апстрим поменял значение, обновить;
- в CHANGELOG апстрима — не сменилась ли схема хранилища (тогда может понадобиться
  `settings_reset.uf2` и повторный импорт раскладки).

Прошитый релиз записан в `BUILD_COMMIT.txt` официального архива — от этого коммита и вести ветку.

## Откат

Официальные UF2 — в [релизах Ergohaven](https://github.com/ergohaven/rmk/releases)
(`op36-vX.Y.Z.zip`). Шьются так же, без сброса настроек, если версия та же.

## Проверка UF2 перед прошивкой

Для nRF52840 с Adafruit bootloader и SoftDevice S140 6.1.1 (`INFO_UF2.TXT` на диске загрузчика):
все блоки должны иметь family `0xADA52840`, адреса начинаться с `0x26000` и заканчиваться
ниже области хранилища и загрузчика. Загрузчик копированием UF2 не перезаписывается —
двойной `Reset` всегда возвращает в режим прошивки.
