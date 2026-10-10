# BotPlus PDF Editor Roadmap

This roadmap records the planned engineering work after the 1.1 desktop foundation. Dates are intentionally omitted until delivery windows are agreed.

## Milestone 1 — Engineering Measurement Subsystem

- Add document-level scale calibration, including a two-point calibration flow such as 10 mm on the drawing representing 1 m in the real world.
- Implement distance, perimeter, and area tools with live dimension previews, unit conversion, and persistent PDF annotations.
- Add snapping to vector paths and endpoints, with a configurable snap radius and visible snap feedback.
- Provide engineering callout stamps and editable measurement properties.
- Validate behavior across rotated pages, different PDF page boxes, and saved/reopened documents.

## Milestone 2 — Advanced Bookmarks & TOC Engine

- Parse and preserve nested PDF outline structures.
- Generate bookmarks from page text, imported text files, and detected table-of-contents entries.
- Add batch operations for rename, case changes, sorting, action cleanup, duplicate merging, and validation.
- Export and import bookmark trees in documented formats, with a preview before applying destructive batch changes.

## Milestone 3 — Interactive Form Filling & Digital Signatures

- Implement AcroForm field editing, keyboard navigation, validation, and persistence.
- Add signature appearance creation and placement workflows.
- Integrate standards-based PDF digital signing using PKCS#7, with certificate selection and signature verification.
- Clearly distinguish visual signatures from cryptographically verifiable signatures and report certificate trust status.

## Milestone 4 — Vector Layer Visibility & OCR Integration

- Add visibility and lock controls for the non-destructive vector annotation layer.
- Define a durable annotation model and serialization strategy that survives document reopen and export.
- Integrate OCR behind an explicit user action, with language selection, progress, and text review.
- Preserve privacy by processing locally where supported and explain any platform service dependencies.

## Release quality gates

- Build with the current supported Xcode and macOS SDK using Swift 6 strict concurrency checks.
- Verify open, save, save-as, print, multi-tab navigation, panel persistence, and annotation round-trips on Apple Silicon.
- Keep the project free of third-party runtime dependencies unless a later decision documents a concrete requirement.
