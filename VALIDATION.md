# Validation

The source-text editor uses the pinned PDFium arm64 library in addition to Apple SDKs. Verified locally on Apple Silicon with Swift 6 and the installed macOS SDK:

- Release `xcodebuild` completed successfully for arm64.
- `Tools/verify_native.sh` passed. It exercises PDF coordinate round-trips at 0/90/180/270°, ruler pan/zoom geometry, two-finger scrolling, cursor-anchored magnification within native clip alignment, live text changes, saved opacity and callout associations, synthetic annotation drag/resize/Delete events, page insertion/deletion/duplication, PDF reopen, and panel state invariants.
- Saved editor metadata is hidden and non-printing. Visible annotations remain standard PDF annotations.
- Source-content checks cover searchable Cyrillic replacement, removal of the old text without an overlay annotation, insertion/deletion, vector preservation, and editing imported PDF content. Clipboard serialization and light/dark palette checks are included.
- Text-block regressions cover fragmented words, paragraph wrapping, separate columns, CAD duplicate drawing passes, explicit Unicode punctuation mappings, and text scopes spanning several content streams.
- A private 36-page CAD sample was checked separately on pages 1 and 3. All visible characters outside the edited block and 443 / 22,220 vector paths respectively survived reopening. Rendered pages were also inspected. The private sample is not distributed or uploaded.
- In-page editing checks cover rich text selection, partial size/color/bold changes, PDF-space movement/rotation, field stretching, source persistence and editor cleanup.
- Empty vector previews contain a valid content stream; the CoreGraphics empty-/Contents diagnostic no longer appears in native checks.
- Font catalog checks include every available system family and embedded PDF font names; system collection fonts survive saving/reopening with searchable text. Editor/viewport clipping and transparent editing are checked. Thumbnail target-specific commands and vertical centering of short pages are checked.
- An interactive preview opened the private CAD sample, showed text frames and in-place handles, switched document/text properties, displayed 984 installed/PDF font entries, and displayed the thumbnail context menu. The original sample was not saved.
- First-party source whitespace and shell syntax checks passed; upstream license files are retained verbatim.
- App signing and `codesign --verify --strict` passed with an ad-hoc signature during packaging validation.

The local execution sandbox prevents `hdiutil` from starting `hdiejectd`; disk-image creation returns “Device not configured.” The mounted-volume and UDZO steps therefore run in the included GitHub Actions workflow or a normal macOS Terminal session. This limitation does not indicate a Swift compilation failure.

The native checks use a hidden window and synchronous PDFKit operations. Physical trackpad gestures and a full interactive GUI session should also be checked on the release machine. Public Gatekeeper-trusted distribution requires an installed Developer ID certificate and notarization credentials; the pipeline supports both through environment variables.
