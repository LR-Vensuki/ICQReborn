# ICQ Reborn

Твик Cydia Substrate для **iOS 6**, который перенаправляет весь сетевой трафик
старых клиентов ICQ (сборки на базе AIM, 2010 г.) на ваш сервер, указанный в
настройках. Оригинальные серверы ICQ отключены — этот твик даёт клиенту говорить
по тому же протоколу, но с вашей реализацией сервера («reborn»).

Исходники под [theos](https://github.com/theos/theos).

**Установка**: Cydia-репозиторий LegacyReborn — `http://repo.legacyreborn.cfd/`
(пакет `com.icqreborn.tweak`), или `.deb` со [страницы релизов](https://github.com/LR-Vensuki/ICQReborn/releases).

---

## Что именно перехватывается

Оба приложения — это ребрендированный клиент **AIM 2.0** (проект «ICQ Latest»,
Vladimir Kofman). Они не используют «сырой» OSCAR-сокет, а ходят по HTTP-API
**WIM** поверх `NSURLConnection`:

| Назначение | Хост (по умолчанию) | Протокол |
|------------|---------------------|----------|
| Авторизация (`ClientLogin`) | `api.login.icq.net` | HTTPS |
| WIM API (сессия, сообщения, presence, контакт-лист…) | `api.icq.net` | HTTP |
| Long-poll событий | `fetchBaseURL` из ответа `aim/startSession` | HTTP |

Твик хукает **все** точки входа `NSURLConnection`
(`connectionWithRequest:delegate:`, `initWithRequest:delegate:[startImmediately:]`,
`sendSynchronousRequest:…`, `sendAsynchronousRequest:…`) и подменяет у исходящего
запроса только `scheme://host:port`, **сохраняя путь и query-строку без изменений**.
То есть на ваш сервер приходит ровно тот же протокольный запрос, что ушёл бы в ICQ.

Дополнительно:
- Хук `-[NSMutableURLRequest setURL:]` — подстраховка для запросов, собираемых
  через `AOLURLRequest`.
- Категория `+[NSURLRequest allowsAnyHTTPSCertificateForHost:]` — позволяет
  принять **самоподписанный сертификат** вашего сервера (клиент не реализует
  собственную обработку TLS-challenge, поэтому CFNetwork спрашивает именно этот
  приватный метод). Доверие выдаётся только вашему хосту.

Твик работает во время выполнения и **не патчит бинарник**, поэтому неважно, что
одна из сборок (Free) зашифрована FairPlay, — перехват идёт на уровне Foundation.

## Поддерживаемые приложения

| Приложение | Bundle ID | Исполняемый файл |
|-----------|-----------|------------------|
| ICQ Premium 2.0 | `com.icq.icqpaid` | `AIM` |
| ICQ (Free) 2.0 | `com.icq.icqfree` | `AIM Free` |

Оба заданы в фильтре `ICQReborn.plist`.

---

## Сборка

Требуется установленный theos и переменная `$THEOS`. Цель — `armv7`, deployment
target `6.0` (устройства iOS 6 — только armv7; armv6-устройства не поднимаются
выше iOS 4.2.1).

```bash
cd ICQReborn
make clean
make package
```

Получите `.deb` в каталоге `packages/`. Соберётся и сам твик, и подпроект
настроек `prefs/` (бандл `ICQRebornPrefs.bundle` + запись PreferenceLoader).

> Если у вас современный toolchain и итоговый dylib не грузится на iOS 6, укажите
> старый SDK через `SDKVERSION`/`SYSROOT` (например SDK 6.1/7.x), сохранив
> `TARGET = iphone:clang:latest:6.0`.

## Установка

Через theos прямо на устройство:

```bash
make package install THEOS_DEVICE_IP=<ip_устройства>
```

Или вручную:

```bash
scp packages/com.icqreborn.tweak_1.0.0_iphoneos-arm.deb root@<ip>:/tmp/
ssh root@<ip> "dpkg -i /tmp/com.icqreborn.tweak_1.0.0_iphoneos-arm.deb; killall -9 AIM 'AIM Free' SpringBoard"
```

Зависимости пакета: `mobilesubstrate`, `preferenceloader`.

## Настройка

**Настройки → ICQ Reborn**:

- **Язык / Language** — язык меню твика: `Русский` / `English` (переключается на лету).
- **Включено** — главный тумблер.
- **Хост / Порт** — адрес, куда твик перенаправляет трафик (в режиме OSCAR — мост).
- **Использовать HTTPS** — HTTP по умолчанию; HTTPS — если мост за TLS.
- **Протокол сервера** — `WIM` (сервер уже говорит по WIM, напрямую) или `OSCAR`
  (сервер по OSCAR, перевод делает мост).
- **Расположение моста** *(появляется при OSCAR)* — `На сервере` / `На устройстве`.
- **OSCAR-сервер: хост / порт** *(появляется при OSCAR + «На сервере»)* — адрес
  твоего OSCAR-сервера; отправляется мосту при регистрации.
- **Подключиться и проверить** *(кнопка, при OSCAR)* — регистрирует устройство на
  мосту и шлёт ему адрес OSCAR-сервера; результат виден в плашке.
- **Что перенаправлять**: *Хосты ICQ* (по умолчанию) / *AOL-AIM* / *весь трафик*.
- **Принимать любой сертификат** — для самоподписанного HTTPS.
- **Логировать перенаправления** — писать подмены в syslog.

Поле **OSCAR-сервера показывается только в режиме OSCAR + «На сервере»** — в
остальных режимах его нет, чтобы не путать. Вверху панели — **статус-плашка** с
логотипом: серая (idle / устройство-режим), синяя (регистрация/настройка),
зелёная (OK), красная (ошибка + текст). Твик помечает форвардящийся трафик
заголовком `X-ICQR-Device`, по которому мультитенантный мост понимает, чей это
трафик и на какой OSCAR-сервер его слать.

> **Логотип в Settings.** iOS кэширует список PreferenceLoader, поэтому после
> установки сделай **респринг** (`killall -9 SpringBoard`) — иконка твика в
> «Настройках» появится. Логотип в шапке самой панели виден сразу.

Изменения применяются на лету (Darwin-нотификация `com.icqreborn.tweak/prefsChanged`),
перезапускать приложение не обязательно.

---

## Что должен реализовать сервер

Твик лишь доставляет трафик — протокол WIM должен реализовать сам сервер. Роутинг
по префиксу пути (всё на один ваш хост):

**Авторизация** (то, что шло на `api.login.icq.net`):
```
/auth/clientLogin                 → выдать sessionKey / token / sessionSecret
/auth/getTokenFromFacebookSession (опционально)
```

**WIM API** (то, что шло на `api.icq.net`, префикс базового URL):
```
aim/startSession   aim/endSession   aim/startNotify   aim/setSessionParam
aim/reportAction   aim/addTempBuddy  aim/removeTempBuddy  aim/getHostBuddyInfo
im/sendIM          im/sendDataIM
presence/get       presence/setState  presence/setStatus  presence/setProfile
buddylist/get      buddylist/addBuddy  buddylist/removeBuddy  buddylist/moveGroup
buddylist/removeGroup  buddylist/setBuddyAttribute  buddylist/getIMF  buddylist/setIMF
preference/getPermitDeny  preference/setPermitDeny
service/*  location/*  expressions/*  lifestream/*   (по необходимости)
```

Ключевой момент — цикл событий: ответ `aim/startSession` должен содержать
`response.data.fetchBaseURL` и `response.data.timeToNextFetch`. Клиент делает по
`fetchBaseURL` long-poll GET-запросы за событиями (входящие сообщения, смена
статусов). `fetchBaseURL` можно указывать сразу на ваш сервер — тогда его даже не
нужно переписывать; либо оставить хост `*.icq.net`, и твик перенаправит его сам.

Формат ответов — JSON вида `{"response":{"statusCode":200,"data":{…}}}`, как в
оригинальном WIM (клиент разбирает `statusCode`, `data`, `aimsid`, `myInfo` и т.д.).

---

## Ограничения

- Веб-логин через `UIWebView` (AOL/Facebook SSO, `my.screenname.aol.com/_cqr/login`)
  идёт мимо `NSURLConnection` и **не** перенаправляется. Используйте обычный вход
  по логину/паролю (`ClientLogin`) — он покрыт полностью.
- Твик именно **перенаправляет** трафик; сам протокол ICQ/WIM он не эмулирует —
  это задача сервера.
- Только iOS 6, только перечисленные bundle ID.

## Отладка

Включите «Логировать перенаправления» и смотрите syslog устройства — каждая
подмена печатается как `[ICQReborn] <исходный URL> -> <новый URL>`. Если
перенаправлений нет: проверьте, что включён главный тумблер и заполнен хост, а в
разделе «Что перенаправлять» активны нужные хосты.

## Структура проекта

```
ICQReborn/
├── Makefile                 # сборка твика + подпроекта настроек
├── control                  # метаданные .deb
├── ICQReborn.plist          # фильтр Substrate (com.icq.icqpaid / com.icq.icqfree)
├── Tweak.xm                 # хуки перехвата трафика
├── icon.png                 # иконка (исходный размер)
├── README.md
├── depiction/               # описание пакета для Cydia-репозитория
└── prefs/                   # панель настроек (PreferenceLoader bundle)
    ├── Makefile
    ├── entry.plist          # запись в Настройках (со ссылкой на иконку)
    ├── ICQReborn.png            # иконка 29x29 (Settings / Cydia)
    ├── ICQReborn@2x.png         # иконка 58x58 (Settings retina / Cydia)
    ├── ICQRebornPrefsListController.h
    ├── ICQRebornPrefsListController.m   # язык, условные поля, плашка, регистрация
    └── Resources/
        ├── Info.plist
        ├── Root.plist       # меню (RU)
        ├── Root_en.plist    # меню (EN)
        └── ICQReborn@2x.png # логотип для шапки панели
```
