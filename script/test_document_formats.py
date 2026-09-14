"""Exercise supported non-PDF formats using only the pinned conversion runtime.

All fixtures and outputs live in the caller's temporary directory.
"""
import json
import runpy
import sys
import zipfile
from pathlib import Path

import pymupdf


def fixtures(root):
    text = "Document conversion fixture. This is ordinary body text that must survive local conversion."
    (root / "book.fb2").write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info><genre>science</genre><author><first-name>Test</first-name><last-name>Fixture</last-name></author>
<book-title>Local document</book-title><lang>en</lang></title-info></description>
<body><section><title><p>Local document</p></title><p>{text}</p><p>{text}</p></section></body></FictionBook>''')
    with zipfile.ZipFile(root / "book.epub", "w") as archive:
        archive.writestr("mimetype", "application/epub+zip")
        archive.writestr("META-INF/container.xml", '''<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''')
        archive.writestr("content.opf", '''<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">local-fixture</dc:identifier><dc:title>Local document</dc:title><dc:language>en</dc:language></metadata><manifest><item id="body" href="body.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="body"/></spine></package>''')
        archive.writestr("body.xhtml", f'''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Local document</title></head><body><h1>Local document</h1><p>{text}</p><p>{text}</p></body></html>''')
    with zipfile.ZipFile(root / "page.xps", "w") as archive:
        archive.writestr("[Content_Types].xml", '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="fdseq" ContentType="application/vnd.ms-package.xps-fixeddocumentsequence+xml"/><Default Extension="fdoc" ContentType="application/vnd.ms-package.xps-fixeddocument+xml"/><Default Extension="fpage" ContentType="application/vnd.ms-package.xps-fixedpage+xml"/><Default Extension="ttf" ContentType="application/vnd.ms-opentype"/></Types>''')
        archive.writestr("_rels/.rels", '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Type="http://schemas.microsoft.com/xps/2005/06/fixedrepresentation" Target="/FixedDocumentSequence.fdseq"/></Relationships>''')
        archive.writestr("FixedDocumentSequence.fdseq", '''<FixedDocumentSequence xmlns="http://schemas.microsoft.com/xps/2005/06"><DocumentReference Source="/Documents/1/FixedDocument.fdoc"/></FixedDocumentSequence>''')
        archive.writestr("Documents/1/FixedDocument.fdoc", '''<FixedDocument xmlns="http://schemas.microsoft.com/xps/2005/06"><PageContent Source="Pages/1.fpage" Width="800" Height="1000"/></FixedDocument>''')
        archive.writestr("Documents/1/Pages/1.fpage", f'''<FixedPage xmlns="http://schemas.microsoft.com/xps/2005/06" Width="800" Height="1000" xml:lang="en-US"><Glyphs FontUri="/Resources/font.ttf" FontRenderingEmSize="14" OriginX="50" OriginY="250" UnicodeString="{text}" Fill="#FF000000"/><Glyphs FontUri="/Resources/font.ttf" FontRenderingEmSize="14" OriginX="50" OriginY="280" UnicodeString="{text}" Fill="#FF000000"/></FixedPage>''')
        archive.writestr("Resources/font.ttf", pymupdf.Font("cjk").buffer)


def main():
    worker = runpy.run_path(sys.argv[1])
    root = Path(sys.argv[2])
    root.mkdir(parents=True, exist_ok=True)
    fixtures(root)
    for name in ["book.epub", "book.fb2", "page.xps"]:
        source = root / name
        output = root / (name + "-output")
        facts = worker["inspect_document"](source)
        assert facts["pages"] > 0 and not facts["encrypted"], name
        worker["convert"](source, output, use_ocr=False, keep_header_footer=False)
        body = (output / "body.md").read_text()
        assert "conversion fixture" in body, (name, body)
        manifest = json.loads((output / "result.json").read_text())
        assert not manifest["emptyText"], name
        print(json.dumps({"format": source.suffix, "characters": len(body)}))


if __name__ == "__main__":
    main()
