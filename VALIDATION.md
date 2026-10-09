# Validation

Verified locally on Apple Silicon with Swift 6 and the installed macOS SDK:

- Release `xcodebuild` completed successfully for arm64.
- `Tools/verify_native.sh` passed. It exercises PDF coordinate round-trips at 0/90/180/270°, ruler pan/zoom geometry, two-finger scrolling, cursor-anchored magnification within native clip alignment, live text changes, saved opacity and callout associations, synthetic annotation drag/resize/Delete events, page insertion/deletion/duplication, PDF reopen, and panel state invariants.
- Saved editor metadata is hidden and non-printing. Visible annotations remain standard PDF annotations.
- Shell syntax and Git whitespace checks passed.
- App signing and `codesign --verify --strict` passed with an ad-hoc signature during packaging validation.

The local execution sandbox prevents `hdiutil` from starting `hdiejectd`; disk-image creation returns “Device not configured.” The mounted-volume and UDZO steps therefore run in the included GitHub Actions workflow or a normal macOS Terminal session. This limitation does not indicate a Swift compilation failure.

The native checks use a hidden window and synchronous PDFKit operations. Physical trackpad gestures and a full interactive GUI session should also be checked on the release machine. Public Gatekeeper-trusted distribution requires an installed Developer ID certificate and notarization credentials; the pipeline supports both through environment variables.
