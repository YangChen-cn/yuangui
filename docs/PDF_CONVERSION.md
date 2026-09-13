# PDF conversion

YuanGUI 2.9.0 converts one local PDF at a time. First-use installation is explicit;
opening the app does not install anything. Documents are processed locally, without
cloud converters or third-party plugins. Closing the window cancels its active task.

The private runtime lives beneath the user's Application Support/YuanGUI/PDFConversion
directory. Python 3.12.13 and uv 0.12.13 are pinned; uv archives are checked against the
SHA-256 digests published by the official astral-sh/uv GitHub Release. The packaged
requirements.lock pins PyMuPDF4LLM, PyMuPDF and PyMuPDF Layout 1.28.2 and transitive dependencies with package hashes.
ONNX Runtime is pinned to 1.23.2 to retain Intel Mac wheel availability. Python is
installed with `--no-bin`, so no commands are added to the user's command directory.
uv supplies the checksum-verified managed Python distribution. Failed installations
are removed and can be retried; completed installations are reused without downloads.

Markdown text is produced by PyMuPDF4LLM with its default local Layout model explicitly
enabled. Missing Layout support fails rather than falling back to legacy extraction.

Automatic OCR uses RapidOCR-ONNXRuntime 1.4.4 and its packaged Chinese/English models;
there are no model downloads during conversion or dependencies on system Tesseract.
It is off by default and controlled by the **Automatic OCR** checkbox in the window, so
an ordinary text PDF never pays for recognition. The choice is remembered between
sessions and is fixed for the duration of a task. Enabling it appends `--ocr` to the
worker command; with the checkbox off the worker never imports RapidOCR or ONNX Runtime
and only reads the PDF's own text layer, so a scanned page stays empty. The models remain
installed either way, and installation always self-checks both Layout and a rasterized
text page, so enabling OCR later needs no reinstall. With the checkbox on, OCR runs only
where the engine considers it useful, rather than forcing every page through recognition;
enabling it costs the extra load time and memory of the recognition stack.

The new runtime has a separate revision directory from previous MarkItDown installations.
OpenCV is pinned to 4.11.0.86 for prebuilt wheels on both Mac architectures. Display
rotation metadata is cleared only on the in-memory document used by Layout, which
otherwise missed text in the rotated-page fixture. The input PDF is never saved.

Bitmap object bounds are located with
PyMuPDF and rendered to PNG at up to 144 DPI (maximum 4096 pixels on the longest
edge). These are cropped representations, not byte-identical embedded originals.
Images are appended by page in the exported Markdown with relative links. Copying
copies only the text. Keep the exported Markdown beside its `_assets` directory.

There is no formula reconstruction, vector figure detection, custom multi-column
repair, batch queue, cloud account, or persistent conversion history. A scanned document
produces no text until automatic OCR is enabled, and recognition can still miss blurry or
decorative pages. Image failures are reported by page while preserving the converted text.
Review complex papers before relying on their reading order.

## Third-party notices

- [PyMuPDF4LLM and PyMuPDF](https://github.com/pymupdf/pymupdf4llm), AGPL-3.0 or commercial license; includes the PyMuPDF Layout model distribution.
- [RapidOCR](https://github.com/RapidAI/RapidOCR), Apache-2.0 license.
- [uv](https://github.com/astral-sh/uv), MIT or Apache-2.0 license.
- [CPython](https://www.python.org/), Python Software Foundation license.

These projects are installed from their published distributions, which retain their
license metadata. YuanGUI's integration does not imply endorsement by these projects.
The application bundles the wrapper and dependency lock, not a fork of these engines.

## Validation

Ordinary product tests use temporary storage and fake operations; they do not download
or alter a user's conversion environment. To exercise installation and conversion:

```sh
YUANGUI_TEST_PDF_INSTALL=1 swift test --filter PDFConversionTests/testRealInstallationAndPDFConversion
```

This opt-in test installs in a temporary directory, generates PDF fixtures, runs the
real converter and removes the runtime afterward. GUI drag/drop, file panels, focus,
Spaces and assistive technology behavior require manual validation.

The 405-page FreeRTOS V10.0.0 reference manual was also checked with Layout and
automatic OCR enabled. It produced headings, fenced code and three bitmap images;
code indentation survived in the xTaskCreate example. Its printed contents were
still incorrectly split into table columns, and some code was fragmented across
multiple fences. This is the engine's output, not a lossless document reconstruction.
Exploratory full-file runs took approximately 42–53 seconds and 1.1–1.2 GiB peak
resident memory on the development Apple Silicon Mac; this model-based path is
heavier than the earlier model-free experiment. These are local observations, not
cross-device performance guarantees.
