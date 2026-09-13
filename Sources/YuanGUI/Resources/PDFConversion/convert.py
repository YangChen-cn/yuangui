"""Local PDF conversion only. stdout is JSON events; document data stays in files.

Automatic OCR is opt-in: without --ocr the conversion extracts the PDF's own text layer.
"""
import json
import sys
from contextlib import redirect_stdout
from functools import lru_cache
from pathlib import Path


def event(**values):
    print(json.dumps(values), flush=True)


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
    import pymupdf
    converter, ocr = engine(), local_ocr
    with pymupdf.open() as document:
        page = document.new_page()
        page.insert_text((72, 72), "Layout installation test", fontsize=24)
        assert "installation" in converter.to_markdown(document, use_ocr=True, ocr_function=ocr)
        # Rasterize the text so this check actually exercises the bundled OCR models.
        pixels = page.get_pixmap(matrix=pymupdf.Matrix(2, 2))
        with pymupdf.open() as scanned:
            scanned.new_page().insert_image(page.rect, pixmap=pixels)
            assert "installation" in converter.to_markdown(scanned, use_ocr=True, ocr_function=ocr).lower()


def render_image(page, bounds, path):
    import pymupdf
    clip = pymupdf.Rect(bounds) * page.rotation_matrix
    clip &= page.rect
    if clip.is_empty or clip.is_infinite:
        return False
    scale = min(2, 4096 / max(clip.width, clip.height))
    pixels = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), clip=clip, alpha=False)
    pixels.save(path)
    return True


def convert(source, destination, use_ocr=False):
    import pymupdf

    destination.mkdir(parents=True, exist_ok=True)
    event(stage="text")
    # Third-party informational output belongs on stderr, not the JSON event channel.
    with redirect_stdout(sys.stderr):
        converter = engine()
        with pymupdf.open(source) as document:
            if document.needs_pass:
                raise ValueError("password protected PDF")
            # Layout can drop text on pages with display rotation. Analyze native
            # content coordinates; the source and exported image orientation stay intact.
            for page in document:
                if page.rotation:
                    page.set_rotation(0)
            # Omitting the function keeps RapidOCR and ONNX Runtime unloaded when disabled.
            body = converter.to_markdown(document, use_ocr=use_ocr, ocr_function=local_ocr if use_ocr else None).strip()
    (destination / "body.md").write_text(body, encoding="utf-8")
    images = []
    failed_pages = []
    event(stage="images")
    with pymupdf.open(source) as pdf:
        for page in pdf:
            page_number = page.number + 1
            try:
                # Render only image regions, never infer vector figure boundaries.
                seen = set()
                for item in sorted(page.get_image_info(), key=lambda image: (image["bbox"][1], image["bbox"][0])):
                    bounds = tuple(item["bbox"])
                    if bounds in seen or bounds[2] <= bounds[0] or bounds[3] <= bounds[1]:
                        continue
                    seen.add(bounds)
                    name = f"page-{page_number:04d}-{len(seen):03d}.png"
                    if render_image(page, bounds, destination / name):
                        images.append({"name": name, "page": page_number})
            except Exception as exc:
                failed_pages.append(page_number)
                print(f"Image extraction, page {page_number}: {exc}", file=sys.stderr)
            finally:
                # MuPDF's image/font cache otherwise grows across a large document.
                pymupdf.TOOLS.store_shrink(100)
    (destination / "result.json").write_text(json.dumps({
        "images": images, "failedPages": failed_pages, "emptyText": not bool(body)
    }), encoding="utf-8")
    event(stage="finished")


if __name__ == "__main__":
    try:
        arguments = sys.argv[1:]
        if arguments == ["--self-test"]:
            with redirect_stdout(sys.stderr):
                self_test()
        else:
            ocr = "--ocr" in arguments
            paths = [argument for argument in arguments if argument != "--ocr"]
            if len(paths) != 2:
                raise ValueError("usage: convert.py SOURCE DESTINATION [--ocr]")
            convert(Path(paths[0]), Path(paths[1]), use_ocr=ocr)
    except Exception as exc:
        name = type(exc).__name__.lower()
        description = str(exc).lower()
        code = "locked" if any(word in name + description for word in ("password", "encrypt")) else "invalid"
        event(error=code)
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)
