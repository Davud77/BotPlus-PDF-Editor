# BotPlus PDF Editor

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Dependencies](https://img.shields.io/badge/external%20dependencies-zero-success)](#technology)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-777777?logo=apple)](https://developer.apple.com/)

A native macOS PDF workspace built with SwiftUI, AppKit, and Apple PDFKit. Its ribbon ergonomics, dockable panels, and drafting-oriented workflows take inspiration from PDF-XChange Editor, with a bilingual Russian and English interface.

## Features

- Windows-style dark ribbon with 13 localized tabs, grouped commands, quick actions, search, and a multi-document tab strip.
- PDFKit viewport with PDF opening, drag and drop, continuous/single/two-page display, hand and text selection tools, page navigation, zoom, rotation, highlighting, save, save-as, and print.
- Dockable, floating, and resizable workspace panels with saved visibility, docking side, and width.
- Drafting-style viewport rulers synchronized to the PDF page position and zoom.
- Russian and English UI language selection under Help → UI Settings.
- BotPlus app mark available as SVG, a SwiftUI preview, and a native icon asset catalog.

Commands without implemented PDF behavior show a localized development notice. The engineering measurement tools, advanced bookmark editing, interactive forms, and cryptographic signing are planned in [ROADMAP.md](ROADMAP.md).

## Technology

- macOS 14 or later; Swift 6; Xcode 16 or later recommended.
- Apple Silicon is the primary target. The project uses only Apple SDK frameworks: SwiftUI, AppKit, PDFKit, and UniformTypeIdentifiers.
- No third-party packages or runtime dependencies.
- App Sandbox is enabled with user-selected PDF read/write access. Signing and notarization identities are configured in Xcode for your distribution account.

## Build with Xcode

1. Open `BotPlusPDFEditor.xcodeproj`.
2. Select the `BotPlusPDFEditor` scheme and a My Mac destination.
3. Choose **Product → Run** (⌘R).

Or build from Terminal:

```sh
xcodebuild -project BotPlusPDFEditor.xcodeproj \
  -scheme BotPlusPDFEditor \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData build
```

The app is written in `ContentView.swift` and compiles as the target’s single Swift source file. The Xcode project includes the icon asset catalog and sandbox entitlements.

## App icon

`AppIcon.svg` is the editable 1024 × 1024 vector master. `AppIconPreviewView` in `ContentView.swift` draws the mark using SwiftUI Canvas. To regenerate the standard macOS PNG icon set with Apple’s AppKit renderer:

```sh
swift Tools/export_app_icon.swift
```

This writes PNGs and `Contents.json` into `Assets.xcassets/AppIcon.appiconset`, already connected to the Xcode target. You can also open `AppIcon.svg` in a vector editor and export the standard icon sizes.

## Runtime notes

The app defines no AppIntents types or shortcut declarations. Xcode may still invoke its metadata scanner for an application target; the scanner reports that extraction was skipped because AppIntents.framework is not linked. Live Text interaction is disabled at runtime when the installed PDFKit exposes its setter. Viewport-to-SwiftUI state synchronization is deferred until after AppKit updates complete to avoid publishing ObservableObject changes during representable updates. Errors from macOS services such as `linkd.autoShortcut`, and PDFKit OCR model availability diagnostics, depend on the host runtime and cannot be suppressed by app code when those system services are unavailable.

## Repository setup

Review the files, then initialize and commit the local repository with:

```sh
./deploy_to_github.sh
```

To push after configuring Git credentials, run:

```sh
./deploy_to_github.sh --push
```

The script sets `origin` to `https://github.com/Davud77/BotPlus-PDF-Editor.git` and pushes the `main` branch only when `--push` is provided. Remote creation requires the explicit `--create-remote` option and an authenticated `gh` CLI; GitHub prompts for repository visibility.

## License

No license has been selected yet. Add a `LICENSE` file before distributing source code publicly.
