# PDF conversion

YuanGUI 2.9.0 converts one local PDF at a time. First-use installation is explicit;
opening the app does not install anything. Documents are processed locally, without
cloud converters or third-party plugins. Closing the window cancels its active task.

The private runtime lives beneath the user's Application Support/YuanGUI/PDFConversion
directory. Python 3.12.13 and uv 0.12.13 are pinned; uv archives are checked against the
SHA-256 digests published by the official astral-sh/uv GitHub Release. The packaged
requirements.lock pins MarkItDown 0.1.7 and transitive dependencies with package hashes.
ONNX Runtime is pinned to 1.23.2 to retain Intel Mac wheel availability. Python is
installed with `--no-bin`, so no commands are added to the user's command directory.
uv supplies the checksum-verified managed Python distribution. Failed installations
are removed and can be retried; completed installations are reused without downloads.

Markdown text is produced by MarkItDown. Bitmap object bounds are located with
pdfplumber and rendered to PNG at up to 144 DPI (maximum 4096 pixels on the longest
edge). These are cropped representations, not byte-identical embedded originals.
Images are appended by page in the exported Markdown with relative links. Copying
copies only the text. Keep the exported Markdown beside its `_assets` directory.

There is no OCR, formula reconstruction, vector figure detection, multi-column
repair, batch queue, cloud account, or persistent conversion history. A scanned
document can produce no text. Image failures are reported by page while preserving
the converted text. Review complex papers before relying on their reading order.

## Third-party notices

- [Microsoft MarkItDown](https://github.com/microsoft/markitdown), MIT license.
- [pdfplumber](https://github.com/jsvine/pdfplumber), MIT license.
- [uv](https://github.com/astral-sh/uv), MIT or Apache-2.0 license.
- [CPython](https://www.python.org/), Python Software Foundation license.

These projects are installed from their published distributions, which retain their
license metadata. YuanGUI's integration does not imply Microsoft sponsorship.
The application bundles the wrapper and dependency lock, not a fork of MarkItDown.

## Validation

Ordinary product tests use temporary storage and fake operations; they do not download
or alter a user's conversion environment. To exercise installation and conversion:

```sh
YUANGUI_TEST_PDF_INSTALL=1 swift test --filter PDFConversionTests/testRealInstallationAndPDFConversion
```

This opt-in test installs in a temporary directory, generates PDF fixtures, runs the
real converter and removes the runtime afterward. GUI drag/drop, file panels, focus,
Spaces and assistive technology behavior require manual validation.
