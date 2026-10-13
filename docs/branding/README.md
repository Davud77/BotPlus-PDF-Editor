# Логотип BotPlus PDF Editor

Новый знак создан из предоставленной пользователем картинки: бордовая плитка,
стопка PDF и панель редактирования. Исходный JPEG пользователя не изменялся.

- `AppIcon.png`: готовый PNG 1024 × 1024 с прозрачными краями.
- `BrandArtwork.png`: выбранный растровый результат imagegen, 1254 × 1254 с альфа-каналом.
- `AppIcon-legacy.svg`: предыдущий векторный логотип, сохранён для истории.
- `../../Assets.xcassets/AppIcon.appiconset`: 10 размеров для macOS 16–1024 px.
- `../../Assets.xcassets/BrandIcon.imageset`: тот же знак для интерфейса и окна «О программе».

## Повторный экспорт

Из корня проекта:

```sh
swift Tools/export_app_icon.swift
```

Экспортёр использует только Apple AppKit. Он нормализует плитку в сетку 1024 px
с отступом 72 px, применяет ровный закруглённый контур и сохраняет прозрачность.
Все размеры генерируются из одного исходника. Не заменяйте `BrandArtwork.png`
изображением другого размера без изменения геометрии экспортёра.

Знак появится в Dock/Finder после сборки и запуска новой версии приложения.

## Генерация

Использован встроенный imagegen, режим редактирования / background-extraction.
CLI/API и внешние зависимости не использовались.

Первичный запрос: сохранить бордовую плитку, стопку PDF, панели и диагональные
тени; убрать внешнее белое поле; получить иконку macOS с прозрачными краями.

Запрос уточнения для выбранного результата:

> Clean up this exact app icon cutout. KEEP the red rounded-square tile and all its interior artwork exactly as they are. Remove ALL disconnected red fragments/noise above the top edge and along the left/right edges. Outside the single rounded square must be completely transparent and spotless, with NO pixels, NO shadow, NO halo, NO flecks. Refine the perimeter into a smooth continuous antialiased rounded-square edge. Maintain fully opaque red background INSIDE the tile. Center square icon on square canvas with equal transparent margins. Preserve the white PDF paper stack, PDF text, orange lower editor panel, gear details and diagonal shadows unchanged. This is cleanup only.

Финальный контур обеспечивается воспроизводимым экспортом AppKit.
