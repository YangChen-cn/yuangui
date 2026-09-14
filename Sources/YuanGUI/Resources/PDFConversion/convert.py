"""Local PDF conversion only. stdout is JSON events; document data stays in files.

Usage:
    convert.py SOURCE DESTINATION [--ocr] [--keep-header-footer]
    convert.py --probe SOURCE
    convert.py --self-test

Automatic OCR is opt-in: without --ocr only the PDF's own text layer is read.
Page headers and footers are removed unless --keep-header-footer is given.
"""

import json
import re
import shutil
import sys
from contextlib import contextmanager, redirect_stdout
from functools import lru_cache
from pathlib import Path

# Markdown links to exported pictures are relative so no temporary path can leak.
ASSETS = "_assets"
# Pictures are written by the engine as "<source name>-<page>-<box>.<format>". The source
# name may hold spaces or non-ASCII text, so the exported files get a stable ASCII name.
RENDERED_NAME = re.compile(r"^.*-(?P<page>\d+)-(?P<box>\d+)\.(?P<format>[A-Za-z0-9]+)$")
RENDERED_LINK = re.compile(r"!\[\]\((?P<target>[^)]+)\)")
# A page below this many characters counts as having no text layer. Sampling a handful
# of pages is enough to tell a scanned document from a digital one.
TEXT_LAYER_MINIMUM = 32


def event(**values):
    print(json.dumps(values), flush=True)


def probe(source):
    """Report whether the document is worth converting before any model is loaded.

    This runs with PyMuPDF only: the Layout model is expensive and must not be loaded
    for a document that cannot be read at all.
    """
    # Keep third-party chatter off the JSON event channel.
    with redirect_stdout(sys.stderr):
        result = inspect_document(source)
    event(probe=result)


def inspect_document(source):
    import pymupdf

    with pymupdf.open(source) as document:
        pages = document.page_count
        # An encrypted document opens but exposes no page content before unlocking.
        if document.needs_pass:
            return {"pages": pages, "encrypted": True, "textPages": 0, "sampledPages": 0,
                    "scanned": False}
        sampled = sample_pages(pages)
        text_pages = sum(
            1 for number in sampled
            if len(document[number].get_text().strip()) >= TEXT_LAYER_MINIMUM
        )
        return {"pages": pages, "encrypted": False, "textPages": text_pages,
                "sampledPages": len(sampled), "scanned": bool(sampled) and not text_pages}


def sample_pages(count):
    """Pick a few cheap pages: the start of the document, its middle and its end."""
    if count <= 5:
        return list(range(count))
    return sorted({0, 1, 2, count // 2, count - 1})


def engine():
    import importlib.metadata
    import pymupdf
    pymupdf.set_messages(stream=sys.stderr)
    import pymupdf4llm
    assert importlib.metadata.version("pymupdf4llm") == "1.28.2"
    # Fail installation/conversion if Layout cannot load; never silently use legacy mode.
    pymupdf4llm.use_layout(True)
    return pymupdf4llm


@lru_cache(maxsize=1)
def ocr_engine():
    from rapidocr_onnxruntime import RapidOCR
    return RapidOCR()


def local_ocr(page, dpi=150, language=None, keep_ocr_text=False):
    from pymupdf4llm.ocr.exec_ocr_interface import exec_ocr_full

    def recognize(image):
        results, _ = ocr_engine()(image)
        # RapidOCR returns None for image regions containing no text.
        return [(box, text, float(score)) for box, text, score in (results or [])]

    return exec_ocr_full(page, recognize, dpi=dpi, language=language, keep_ocr_text=keep_ocr_text)


def self_test():
    import tempfile
    import pymupdf
    converter, ocr = engine(), local_ocr
    with pymupdf.open() as document:
        page = document.new_page()
        page.insert_text((72, 200), "Layout installation test", fontsize=20)
        for line in range(3):
            page.insert_text((72, 230 + line * 18), f"Body line {line} of the installation check.", fontsize=11)
        page.draw_rect(pymupdf.Rect(72, 320, 320, 460), color=(0, 0, 1), width=2)
        page.draw_line(pymupdf.Point(72, 320), pymupdf.Point(320, 460), color=(1, 0, 0))
        # Rasterize the text so this check actually exercises the bundled OCR models.
        pixels = page.get_pixmap(matrix=pymupdf.Matrix(2, 2))
        with pymupdf.open() as scanned:
            scanned.new_page().insert_image(page.rect, pixmap=pixels)
            assert "installation" in converter.to_markdown(
                scanned, use_ocr=True, ocr_function=ocr).lower()
        # Conversion must keep the text and write the vector drawing as a picture file.
        with tempfile.TemporaryDirectory() as folder:
            markdown = converter.to_markdown(
                document, header=False, footer=False, write_images=True, image_path=folder,
                use_ocr=True, ocr_function=ocr)
            assert "installation" in markdown
            assert "![](" in markdown and any(Path(folder).iterdir()), "Layout wrote no picture file"


def publish_images(rendered, destination):
    """Move the engine's pictures into the conversion directory under stable names.

    Returns the mapping of engine file names to the names now living next to body.md.
    """
    if not rendered.is_dir():
        return {}
    renames = {}
    for path in sorted(rendered.iterdir()):
        if not path.is_file():
            continue
        match = RENDERED_NAME.match(path.name)
        stem = f"figure-{int(match['page']):04d}-{int(match['box']):02d}" if match else f"figure-{len(renames) + 1:04d}"
        name = f"{stem}{path.suffix.lower()}"
        while (destination / name).exists():
            stem += "x"
            name = f"{stem}{path.suffix.lower()}"
        shutil.move(str(path), str(destination / name))
        renames[path.name] = name
    shutil.rmtree(rendered, ignore_errors=True)
    return renames


def rewrite_links(body, renames):
    """Point picture links at the exported assets directory instead of a temporary path."""

    def replace(match):
        source = Path(match.group("target")).name
        name = renames.get(source)
        if name:
            return f"![]({ASSETS}/{name})"
        # Never leave a temporary path or a broken link in the Markdown.
        print(f"Dropped picture link outside the conversion: {source}", file=sys.stderr)
        return ""

    return RENDERED_LINK.sub(replace, body)


@contextmanager
def conversion_document(source):
    import pymupdf
    with pymupdf.open(source) as original:
        if original.needs_pass:
            raise ValueError("password protected document")
        if original.is_pdf:
            yield original
        else:
            # Layout edits pages during OCR and requires PDF page methods. Convert
            # supported read-only formats in memory without changing the runtime.
            with pymupdf.open("pdf", original.convert_to_pdf()) as document:
                yield document


def convert(source, destination, use_ocr=False, keep_header_footer=False):
    import pymupdf

    destination.mkdir(parents=True, exist_ok=True)
    event(stage="text")
    rendered = destination / "rendered"
    # Third-party informational output belongs on stderr, not the JSON event channel.
    with redirect_stdout(sys.stderr):
        with conversion_document(source) as document:
            # Refuse locked documents before the Layout model costs seconds of work.
            if document.needs_pass:
                raise ValueError("password protected PDF")
            # Layout can drop text on pages with display rotation. Analyze native
            # content coordinates; the source and exported image orientation stay intact.
            for page in document:
                if page.rotation:
                    page.set_rotation(0)
            converter = engine()
            if source.suffix.lower() in (".epub", ".fb2"):
                use_ocr = False
                keep_header_footer = True
            # Pictures are written next to their position in the text, including vector
            # figures, which Layout reports as picture areas of the page.
            body = converter.to_markdown(
                document,
                write_images=True,
                image_path=str(rendered),
                image_format="png",
                header=keep_header_footer,
                footer=keep_header_footer,
                # Omitting the function keeps RapidOCR unloaded when OCR is disabled.
                use_ocr=use_ocr,
                ocr_function=local_ocr if use_ocr else None,
            ).strip()
    renames = publish_images(rendered, destination)
    body = rewrite_links(body, renames)
    (destination / "body.md").write_text(body, encoding="utf-8")
    # A page that only produced pictures still counts as having no text.
    text = RENDERED_LINK.sub("", body).strip()
    (destination / "result.json").write_text(json.dumps({
        "images": sorted(renames.values()), "emptyText": not text
    }), encoding="utf-8")
    event(stage="finished")


if __name__ == "__main__":
    try:
        arguments = sys.argv[1:]
        if arguments == ["--self-test"]:
            with redirect_stdout(sys.stderr):
                self_test()
        elif len(arguments) == 2 and arguments[0] == "--probe":
            probe(Path(arguments[1]))
        else:
            ocr = "--ocr" in arguments
            margins = "--keep-header-footer" in arguments
            paths = [a for a in arguments if not a.startswith("--")]
            if len(paths) != 2:
                raise ValueError("usage: convert.py SOURCE DESTINATION [--ocr] [--keep-header-footer]")
            convert(Path(paths[0]), Path(paths[1]), use_ocr=ocr, keep_header_footer=margins)
    except Exception as exc:
        name = type(exc).__name__.lower()
        description = str(exc).lower()
        code = "locked" if any(word in name + description for word in ("password", "encrypt")) else "invalid"
        event(error=code)
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)
