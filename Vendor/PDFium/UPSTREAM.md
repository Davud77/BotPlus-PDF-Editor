# PDFium binary provenance

- PDFium build: chromium/8086 (157.0.8086.0), arm64 macOS, without V8.
- Distribution: https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F8086
- Archive: pdfium-mac-arm64.tgz
- Original archive SHA-256: e98679e052c07edbb5a627980902abb823d4b3f35744d877bd21668bd9fc13ab
- Upstream source and API: https://pdfium.googlesource.com/pdfium/

The dylib install name is adjusted to @rpath/libpdfium.dylib and the local copy is ad-hoc signed. The application embeds and signs this library; users do not install it separately. All upstream third-party notices are retained in licenses/ and copied into the app bundle.
