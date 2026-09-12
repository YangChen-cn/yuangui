"""Local PDF conversion only. stdout is JSON events; document data stays in files."""
import json
import sys
from pathlib import Path


def event(**values):
    print(json.dumps(values), flush=True)


def convert(source, destination):
    import pdfplumber
    from markitdown import MarkItDown

    destination.mkdir(parents=True, exist_ok=True)
    event(stage="text")
    # Passing a local stream prevents URL interpretation and remote converters.
    with source.open("rb") as stream:
        result = MarkItDown(enable_plugins=False).convert_stream(stream, file_extension=".pdf")
    body = result.markdown.strip()
    (destination / "body.md").write_text(body, encoding="utf-8")
    images = []
    failed_pages = []
    event(stage="images")
    with pdfplumber.open(source) as pdf:
        for page in pdf.pages:
            try:
                # Render only image regions, never infer vector figure boundaries.
                seen = set()
                for item in sorted(page.images, key=lambda image: (image["top"], image["x0"])):
                    bounds = (max(page.bbox[0], item["x0"]), max(page.bbox[1], item["top"]),
                              min(page.bbox[2], item["x1"]), min(page.bbox[3], item["bottom"]))
                    if bounds in seen or bounds[2] <= bounds[0] or bounds[3] <= bounds[1]:
                        continue
                    seen.add(bounds)
                    name = f"page-{page.page_number:04d}-{len(seen):03d}.png"
                    # Bound raster memory even for unusually large page dimensions.
                    resolution = min(144, 4096 * 72 / max(bounds[2] - bounds[0], bounds[3] - bounds[1]))
                    rendered = page.crop(bounds).to_image(resolution=resolution)
                    try:
                        rendered.original.save(destination / name, format="PNG")
                    finally:
                        rendered.original.close()
                    images.append({"name": name, "page": page.page_number})
            except Exception as exc:
                failed_pages.append(page.page_number)
                print(f"Image extraction, page {page.page_number}: {exc}", file=sys.stderr)
            finally:
                page.close()
    (destination / "result.json").write_text(json.dumps({
        "images": images, "failedPages": failed_pages, "emptyText": not bool(body)
    }), encoding="utf-8")
    event(stage="finished")


if __name__ == "__main__":
    try:
        convert(Path(sys.argv[1]), Path(sys.argv[2]))
    except Exception as exc:
        name = type(exc).__name__.lower()
        description = str(exc).lower()
        code = "locked" if any(word in name + description for word in ("password", "encrypt")) else "invalid"
        event(error=code)
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)
