# BotPlus PDF Editor

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Dependencies](https://img.shields.io/badge/external%20dependencies-zero-success)](#technology)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-777777?logo=apple)](https://developer.apple.com/)

A native macOS PDF workspace built with SwiftUI, AppKit, and Apple PDFKit. Its ribbon ergonomics, dockable panels, and drafting-oriented workflows take inspiration from PDF-XChange Editor, with a bilingual Russian and English interface. Ribbon tab widths remain fixed when the active tab changes.

## Features

- Windows-style dark ribbon with 13 localized tabs, grouped commands, and a 40 pt quick-access/title/search row drawn into the transparent native titlebar area beside the macOS traffic lights.
- PDFKit viewport with PDF opening, drag and drop, continuous/single/two-page display, hand and text selection, page navigation, zoom, rotation, and guarded printing.
- Live free-text editing with font size, color, opacity, and border controls; highlight/underline; rectangle, line, arrow, and grouped callout annotations.
- Annotation selection, dragging, four-corner resizing, Delete/Backspace removal, and live vector drag previews.
- Page insertion, duplication with annotations, deletion, and rotation. Save / Save As continues writing to the selected export URL.
- Panel icon strips, one drawer per sidebar, direct left/right docking buttons, detachable NSPanel windows, and persistent docking/width state (200–600 pt).
- Crop-box rulers based on PDFView coordinate conversion, with points/mm/inches, rotated-page support, clip-view scroll notifications, scale/page notifications, and live cursor hairlines.
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

## Workspace and editing

Enable **View → Rulers** and choose pt/mm/in from the ruler corner or status bar. Two-finger scrolling pans the document with every tool. Pinch on the trackpad to zoom around the cursor; Command/Control-scroll also zooms. Coordinates are relative to the crop box: X increases to the right and Y increases upward in page space. Page rotation changes which PDF axis is shown by each ruler; ticks remain aligned with the displayed PDF.

Use the side-strip icons to open or collapse a drawer. The side strip selects the active panel; no duplicate bottom tabs are shown. The header arrows move a panel directly left or right. Detach opens an NSPanel; its native close button re-docks it. The panel header X hides the panel. Resize with the divider; widths are also constrained by the space available for the document viewport.

Use **Comment → Typewriter** and click a page to type in the live editor. Click Done or outside the popover to commit; Cancel restores existing text or removes a new annotation. Select PDF text and choose Highlight or Underline to create markup. Drag with Rectangle, Line, Arrow, or Callout to place vectors. Adjust defaults in the Properties inspector, or select an annotation and choose Apply to selected.

Use **Home → Select Comments** to select an annotation. Drag its body to move it, drag one of its four handles to resize it, or press Delete/Backspace to remove it. Double-click a free-text annotation to reopen its editor. Callouts use a standard line and free-text annotation linked by persisted BotPlus metadata; moving the text updates the leader, and deleting either component removes the group.

**Organize → Pages** inserts a blank page before the current page, duplicates the current page after it, or deletes it. Deletion keeps at least one page in the document.

BotPlus preserves appearance settings and callout associations in a hidden, non-printing metadata annotation on each annotated page. Visible annotations are standard PDF types, and existing document metadata remains unchanged. PDFKit appearance streams retain transparency for other PDF readers.

## Release build, DMG, and Git deployment

```sh
./build_and_deploy.sh --package-only
```

This builds Release for arm64, signs a staging copy, creates a writable HFS+ image, mounts it, adds the app and an Applications shortcut, detaches it, converts it to compressed UDZO, and verifies the result. Output files are `dist/BotPlus-PDF-Editor.dmg` and its SHA-256 checksum. Temporary mounts are cleaned up on failure or interruption.

```sh
./build_and_deploy.sh
```

GitHub Actions also runs the native checks and this packaging pipeline after a push to main. The resulting DMG and checksum are available as the workflow artifact.

The default command also stages source changes, commits with `feat: add dynamic rulers, dockable panels, and editing tools`, and pushes `main` to `https://github.com/Davud77/BotPlus-PDF-Editor.git`. Git credentials and the remote repository must already be available. Release binaries are ignored by Git.

An ad-hoc signature is the default for local use. Set `BOTPLUS_SIGNING_IDENTITY` to an installed Developer ID Application certificate name for distribution signing. Set `BOTPLUS_NOTARY_PROFILE` to an existing notarytool Keychain profile to submit the DMG and staple its notarization ticket. These credentials are read from the environment, never stored in the repository. Set `BOTPLUS_DERIVED_DATA` to choose another Xcode build directory.

## Native verification

```sh
./Tools/verify_native.sh
```

The checks exercise coordinate conversions at 0/90/180/270°, pan/zoom geometry, anchored gesture magnification, live text, PDF annotation and opacity round-trips, callout grouping, drag/resize/delete, page edits, and panel state. The test runner creates a hidden window and temporary PDFs; it does not modify project PDFs.

## Help and community

Help → Support opens the GitHub repository. Help → Telegram opens [t.me/botplus_pdf](https://t.me/botplus_pdf). The About dialog shows the app name, version, and © 2026 BotPlus.

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
