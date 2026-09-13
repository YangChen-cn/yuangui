# Third-party notices

## Mole

The Cleanup House rule catalog is a native Swift reimplementation informed by [tw93/Mole](https://github.com/tw93/Mole), checked source revision `27123a964aa671d2e64222634d29d4bd2dc866ed`, licensed GPL-3.0. The derived rule comments identify the source revision. YuanGUI keeps only conservative user-scoped cache, project-artifact, and installer detection; it does not copy Mole shell scripts and excludes its sudo/system optimization, service reset, swap, Spotlight, and whole-disk features.

## QuickTranslate

The system-shortcut integration follows the JSON input protocol documented by [ringozzt/quicktranslate](https://github.com/ringozzt/quicktranslate), licensed MIT. YuanGUI does not bundle QuickTranslate source code.

## PDF conversion components

The optional local Python runtime is built for Apple Silicon Macs and installs PyMuPDF,
PyMuPDF4LLM and PyMuPDF Layout 1.28.2 (AGPL-3.0 or Artifex commercial license),
ONNX Runtime 1.23.2 (MIT, and required by the Layout model), RapidOCR-ONNXRuntime 1.4.4
(Apache-2.0) with OpenCV 4.11.0.86 (Apache-2.0) for the optional OCR pass, plus their
version-locked dependencies. Layout and OCR models run on the user's Mac. Published
distributions retain their license metadata; YuanGUI does not fork these engines. See
[PDF conversion](docs/PDF_CONVERSION.md) for the installation details and upstream
project links.

## Service acknowledgements

YuanGUI interoperates with Apple frameworks and services (Vision, Music, Finder automation, Shortcuts), Open-Meteo, LRCLIB, Bilibili, GitHub Releases, and user-configured OpenAI-compatible APIs. These are service/API acknowledgements, not bundled source-code notices or endorsements.
