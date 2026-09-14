# Document conversion

YuanGUI 2.9.0 converts one local document at a time on Apple Silicon Macs. First-use
installation is explicit; opening the app does not install anything. Documents are
processed locally, without cloud converters or third-party plugins. Closing the window
cancels its active task.

## Input formats

The first supported set is PDF, XPS, EPUB, FB2, TXT, PNG, JPEG and TIFF. PDF and XPS
show automatic OCR and header/footer options. EPUB/FB2 hide both options and retain
their content; the pinned PyMuPDF converts these read-only formats to an in-memory
PDF for Layout without saving over the source. The runtime versions, pruning rules,
hybrid PDF OCR and inline image output are unchanged.

TXT is read directly (UTF-8 or UTF-16). Images go straight to `VisionOCRService` for
local text recognition, one correctly oriented frame at a time, including multi-page
TIFF. Neither path needs Python installed. Image input provides recognized text,
not Python Layout's document reconstruction. Screenshot OCR uses this same Vision
backend; PDF OCR keeps its separate existing backend, with no Swift/Python OCR bridge.

MOBI is supported by PyMuPDF in principle but is not exposed in this first set because
we do not yet have a verified fixture. Office formats and scrolling capture are not
part of this change. `script/test_document_formats.py` generates local EPUB/FB2/XPS
fixtures and is exercised by the opt-in real installation test.

## Runtime installation

The private runtime lives beneath the user's Application Support/YuanGUI/PDFConversion
directory. Python 3.12.13 and uv 0.12.13 are pinned, and the uv archive is checked
against the SHA-256 digest published by the official astral-sh/uv GitHub Release for
`aarch64-apple-darwin`. Apple Silicon is the only supported platform: there is no Intel
branch, archive, checksum or dependency pin, and the source does not compile for
`x86_64`. Python is installed with `--no-bin`, so no commands are added to the user's
command directory.

`requirements.lock` is compiled for `aarch64-apple-darwin` and pins every wheel with its
hash:

| Package | Pin | Role |
| --- | --- | --- |
| PyMuPDF4LLM, PyMuPDF, PyMuPDF Layout | 1.28.2 | Markdown conversion and the local layout model |
| ONNX Runtime | 1.23.2 | Runs the Layout model, and RapidOCR when OCR is enabled |
| RapidOCR-ONNXRuntime | 1.4.4 | Optional Chinese/English text recognition |
| OpenCV | 4.11.0.86 | Image processing for RapidOCR only |

The pins were re-checked rather than refreshed: `pymupdf4llm` and `rapidocr-onnxruntime`
1.4.4 are themselves the newest releases, and newer ONNX Runtime (1.30) and OpenCV (5.0)
builds are deliberately not taken. Nothing in this version needs them, OpenCV 5 is a
major-version change to the OCR dependency chain, and the current set is verified
end-to-end by the installation self-check. Failed installations are removed and can be
retried; completed installations are reused without downloads.

Only one runtime revision is kept. After an install passes verification — or when a
window opens and finds the current revision ready — sibling revision directories such as
an earlier `markitdown-0.1.7-v1` are removed. The current revision is never removed, nor
is a revision installed after it, which a newer app version may own. A failed install
deletes only its own partial directory, nothing outside
Application Support/YuanGUI/PDFConversion is touched, and the install lock is held
during the cleanup so a concurrent installer is never disturbed.

Uninstall removes payload children while preserving the root and `.install-lock` inode.
Deleting the locked file would allow another installer to open a new inode and hold a
second independent lock. The regression test retains a descriptor across uninstall
and verifies that it still excludes subsequent operations. Real pruning assertions
for `sympy`, `mpmath` and `networkx` all resolve beneath the same
`venv/lib/python3.12/site-packages` directory.

## Runtime size

An install ends by removing what this configuration provably never reads, and then runs
the self-check on what is left, so the verified tree is the tree that ships. The audit
behind the list:

- The only ONNX models loaded are the default layout model
  (`layout_rf2.4.1+imf1.onnx`), its image-feature model (`feature_imf1.onnx`) and the
  V4-EP table-grid model (`table_grid_model_v4_ep.onnx`). Tracing
  `onnxruntime.InferenceSession` shows exactly these three at import and no others while
  converting text, ruled-table, figure, scan and 400-page documents. The alternative
  feature sets and table-grid versions (V1, V1A, V1B, V1T, V2, V2A, V2B, V2C, V3,
  V4, V4-DO, `feature_imf2`) are reachable only through constructor arguments YuanGUI
  never passes; the package reads no environment variable or config file, and the
  version map is a static table. Those model files and their YAML configs are removed
  (~35 MB).
- `sympy`, `mpmath` and `networkx` are declared by onnxruntime and pymupdf-layout but
  imported only by onnxruntime's model tooling (`tools/symbolic_shape_infer.py`), which
  is not part of inference, so they and `onnxruntime/{tools,transformers,quantization}`
  are removed (~43 MB).
- The installer's own `uv` binary is removed once it has done its work (~35 MB); the
  downloaded archive and uv cache were already deleted. PyMuPDF's `mupdf-devel`
  directory (C headers and static libraries for building native extensions, reached only
  through a `pymupdf._mupdf_devel()` helper this app never calls) goes as well.
- OpenCV, Shapely, Pillow, PyYAML, pyclipper and RapidOCR stay. RapidOCR imports OpenCV,
  and the layout package also imports OpenCV in its non-default table-grid extractors and
  its visualization helpers, so it is not provably unneeded.

That takes a fresh installation from about 490 MB to 358 MB as measured after a real
install (about 290 MB of venv plus the managed Python). Nothing about the conversion path
changes: the pruned
runtime produces byte-identical Markdown, images and manifests for the whole validation
corpus, including the 400-page document and an OCR run. An installation made by an
earlier build keeps its extra files until it is reinstalled — the window's uninstall
button is the quickest way to get the smaller tree.

The window shows how much disk the installed runtime occupies and offers **Uninstall…**
behind a confirmation. Uninstalling takes the same lock the installer uses, deletes only
Application Support/YuanGUI/PDFConversion, and leaves the window ready to install again.

## Preflight

Before any model is loaded, the worker opens the PDF with PyMuPDF alone and reports the
page count, whether the document is encrypted, and whether it has a text layer. It
samples up to five pages (the first three, the middle and the last); a page counts as
having a text layer when `get_text()` yields at least 32 non-whitespace characters, and
the document is reported as a probable scan when no sampled page does. There is no
classifier beyond that heuristic.

The window shows the page count and, for a probable scan, a note that OCR will be used.
Nothing is switched on behind the user's back: hybrid OCR is already on by default, and
the note changes to a hint to enable it if the checkbox was cleared. Password-protected
PDFs are reported from the probe and fail the conversion before the Layout model starts.

## Conversion

Markdown text is produced by PyMuPDF4LLM with its local Layout model explicitly enabled.
Missing Layout support fails rather than falling back to legacy extraction.

**Figures.** Layout classifies each page into text, table, picture and formula areas, and
the engine writes every picture area it finds to disk and links it where it appears in
the text. That covers bitmap objects and vector figures and diagrams drawn from PDF
graphics operators, which the previous hand-written pass could not see. Pictures are
renamed to `figure-<page>-<box>.<format>` and the Markdown references them as
`_assets/<name>`; no temporary path can reach the Markdown because links are rewritten
from a mapping of the files the engine actually wrote. There is no second pass over the
document, no `get_image_info()` bounds arithmetic, and no append-at-the-end block.

**Headers and footers.** With **Remove headers and footers** on (the default), the boxes
Layout classifies as running page headers and footers are dropped: document title, page
number, chapter header and copyright lines repeated on every page. Turn the option off
for a document whose pages carry only a single headline, which the model can read as a
header.

**OCR.** Hybrid OCR is on by default and never forced: the worker passes `--ocr`, the
engine decides page by page whether recognition is worth it, and only then does RapidOCR
read the text of picture areas. A document with its own text layer therefore converts
exactly as it would with OCR off — measured on the text fixture, both settings take 0.4 s,
import neither RapidOCR nor OpenCV, and produce identical Markdown. A page that has no
usable text layer, or that already carries an OCR layer the engine prefers to keep, is
handled accordingly. Clearing the checkbox drops `--ocr`, and the worker then reads only
the PDF's own text layer, so a scanned page stays empty. RapidOCR's Chinese/English
models ship inside the installed distribution: conversion never downloads models and
needs no system Tesseract. ONNX Runtime is loaded either way because the Layout model runs
on it, and the models stay installed, so toggling OCR needs no reinstallation.

Display rotation metadata is cleared only on the in-memory document used by Layout, which
otherwise missed text in rotated-page fixtures. The input PDF is never saved.

## Export

Export writes `<name>.md` next to `<name>_assets/`. Picture links are rewritten to that
folder, percent-encoded where the folder name needs it, and every picture file is copied
into it. Existing names are numbered rather than overwritten, and the whole export is
staged in a hidden directory before being moved into place, so a failure leaves no
half-written Markdown or asset folder behind. Copying copies only the text, with its
`_assets` links.

## Limits

There is no formula reconstruction, custom multi-column repair, batch queue, cloud
account, or persistent conversion history. A scanned document produces no text until
automatic OCR is enabled, and some full-page scans are reported as neither text nor
picture without OCR. Reading order, tables and code in complex papers still need review,
and OCR accuracy depends on scan quality.

## Performance

A 400-page synthetic technical document (text, running headers and footers, code blocks,
tables, vector diagrams and bitmaps on every page) was converted with the installed
runtime on Apple Silicon, measuring wall time, peak resident memory of the worker, and
the resulting structure:

| Mode | Time | Peak RSS | Markdown | Headings | Code fences | Pictures |
| --- | --- | --- | --- | --- | --- | --- |
| Whole document | 36.9 s | 461 MiB | 1,176,796 chars | 400 | 468 | 214 |
| 16-page chunks | 37.0 s | 440 MiB | 1,177,034 chars | 400 | 468 | 214 |
| 32-page chunks | 37.1 s | 435 MiB | 1,177,022 chars | 400 | 468 | 214 |
| 64-page chunks | 37.2 s | 444 MiB | 1,177,016 chars | 400 | 468 | 214 |

Chunking is not worth it: it saves about 5% of peak memory, costs the same wall time
because the layout model dominates, and risks splitting a table or code fence across a
chunk boundary. Every mode produced the same headings, code fences, tables and pictures.
Conversion therefore stays a single whole-document pass, and the window shows a stage
with elapsed time rather than a page counter it cannot measure. An outside measurement of
the whole-document run reports 444 MiB maximum resident size. An earlier 405-page FreeRTOS
V10.0.0 reference manual run took 42–53 s and 1.1–1.2 GiB with the previous per-page image
pass and OCR enabled; that heavier path no longer exists. These are local observations on
one Apple Silicon Mac, not cross-device guarantees.

## Reusing Apple Vision OCR (design note, not implemented)

Standalone image input now uses Vision directly as described above. The following
note concerns replacing the existing **PDF** OCR backend, which remains out of scope.

YuanGUI already ships `VisionOCRService` for screenshot translation, with bounding
boxes, confidence, detected language, reading order and low-confidence retries. Moving
PDF OCR onto it would let the runtime drop `rapidocr-onnxruntime` (17 MB), OpenCV
(101 MB) and their models — ONNX Runtime (64 MB) must stay for the Layout model, so the
saving is about 120 MB, not the whole OCR stack.

The seam already exists and is one function wide: `pymupdf4llm` calls the `ocr_function`
passed to `to_markdown` once per page or picture region with a rasterized image and
expects `[(box, text, score)]` back. Bridging it to Vision would require a helper
executable bundled and signed inside the app, a long-lived JSON-lines pipe to the Python
worker (one process per conversion, never per page), Vision's bottom-left normalized
coordinates converted to the engine's page coordinates, ordering rules matching what
`exec_ocr_full` expects, and cancellation, timeout and temporary-file handling on both
sides. That is a new interprocess protocol and a new signed artifact inside a release
that is otherwise a quality pass, so it is deliberately left out of 2.9.0.

If it is picked up later: keep `local_ocr` as the single seam, add the helper with the
existing `VisionOCRService` rather than a copy, prove one process per conversion with
cancellation, and compare OCR output against the RapidOCR baseline on the same fixtures
before removing any dependency.

## Validation

Ordinary product tests use temporary storage and fake operations; they do not download
or alter a user's conversion environment. To exercise installation and conversion:

```sh
YUANGUI_TEST_PDF_INSTALL=1 swift test --filter PDFConversionTests/testRealInstallationAndPDFConversion
```

This opt-in test installs in a temporary directory, generates PDF fixtures, runs the real
converter and removes the runtime afterward. It covers the probe on digital and rasterized
documents, inline picture links with their files, header and footer removal, locked and
invalid documents, and OCR on a scanned page. GUI drag/drop, file panels, focus, Spaces
and assistive technology behavior require manual validation.

## Third-party notices

- [PyMuPDF4LLM and PyMuPDF](https://github.com/pymupdf/pymupdf4llm), AGPL-3.0 or commercial license; includes the PyMuPDF Layout model distribution.
- [ONNX Runtime](https://github.com/microsoft/onnxruntime), MIT license.
- [RapidOCR](https://github.com/RapidAI/RapidOCR), Apache-2.0 license.
- [OpenCV](https://github.com/opencv/opencv-python), Apache-2.0 license.
- [uv](https://github.com/astral-sh/uv), MIT or Apache-2.0 license.
- [CPython](https://www.python.org/), Python Software Foundation license.

These projects are installed from their published distributions, which retain their
license metadata. YuanGUI's integration does not imply endorsement by these projects.
The application bundles the wrapper and dependency lock, not a fork of these engines.
