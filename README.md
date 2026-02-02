# TalkKey

Простое macOS приложение для голосового ввода текста. Аналог SuperWhisper, но проще.

## Как работает

1. Зажми **правый ⌘ (Command)** — начнётся запись голоса
2. Говори текст
3. Отпусти **правый ⌘** — текст автоматически появится там, где стоит курсор

## Особенности

- Работает в любом приложении где есть текстовое поле
- Текст вводится напрямую (не через буфер обмена)
- Визуальный индикатор записи с waveform
- Отмена записи по **Esc**
- Menu bar приложение (не занимает место в Dock)

## Требования

- macOS 13.0+
- OpenAI API ключ (для транскрипции через Whisper)
- Разрешения:
  - **Microphone** — для записи голоса
  - **Accessibility** — для ввода текста в активное окно

## Установка

1. Клонируй репозиторий
2. Собери проект: `swift build`
3. Запусти: `open PressToTalk.app`
4. Добавь OpenAI API ключ в настройках
5. Выдай разрешения (Microphone, Accessibility)

## Технологии

- Swift / SwiftUI
- AVAudioRecorder для записи
- OpenAI Whisper API для транскрипции
- CGEvent для прямого ввода текста

## Структура проекта

```
Sources/PressToTalk/
├── App/
│   ├── PressToTalkApp.swift    # Точка входа
│   └── AppDelegate.swift       # NSStatusItem, setup
├── Core/
│   ├── HotkeyManager.swift     # Глобальные горячие клавиши
│   ├── AudioRecorder.swift     # Запись аудио
│   ├── TranscriptionService.swift  # Whisper API
│   └── PasteboardManager.swift # Прямой ввод текста
├── Services/
│   ├── AppState.swift          # Состояние приложения
│   ├── KeychainService.swift   # Хранение API ключа
│   └── PermissionsManager.swift # Управление разрешениями
└── Views/
    ├── MainWindowView.swift    # Главное окно настройки
    ├── MenuBarView.swift       # Меню в menu bar
    └── RecordingOverlayView.swift # Индикатор записи
```

## Лицензия

MIT
