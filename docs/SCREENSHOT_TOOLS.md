# Screenshot tools

YuanGUI keeps capture geometry and pointer drawing in AppKit. No OCR, screenshot,
window enumeration or asynchronous work runs from selection dragging. Window targets
are fetched once before a window-selection session using the existing ScreenCaptureKit
cache. Commit captures a display region or a `desktopIndependentWindow` filter.

YuanGUI's own windows are ordinary capture targets: a screenshot may include the pet,
dashboard, settings, chat history, diary, music player, screenshot editor and pinned
shots, and Window mode may pick any of them. Capture hides exactly one thing — the
running session's own selection overlays, matched by window number through
`CaptureSelectionController.windowNumbers`. Nothing is filtered by owning process, and
`CaptureWindowPolicy` is where that rule lives so it stays testable.

## Capture

- Region selection remains visible after mouse-up. Drag inside to move, or drag any
  of eight handles or an edge to resize. Click outside to select again.
- Enter or double-click confirms; Escape cancels. Arrows move one point;
  Shift-arrows resize one point. Shift while making a selection locks a square
  for the rest of that drag, including after releasing Shift. A new selection
  starts unconstrained. The compact toolbar fits its buttons and sits six points
  from the selection when screen space permits.
  Option while resizing keeps its center. `R` restores the last area on that display.
- The compact selection toolbar offers Copy, Annotate, Capture Text, Translate,
  Pin and Save. Command-C/Command-S copy/save directly. Only Annotate opens the editor.
- Window and Screen modes are available in the Tools menu, dashboard and Quick Tools
  settings. Point at a window and click, or click the target display. Settings also
  offer a 0/3/5-second selection delay.
- New users default to Quick Access, a small captured-image panel with post-capture
  actions. Existing saved screenshot hotkeys retain the editor default. Settings
  let either group choose Quick Access, Annotate, Copy or Save.
- Capture Text has its own configurable hotkey (initially Control-Shift-O), menu,
  dashboard and pet-menu entry. Confirming the region recognizes text using
  `VisionOCRService`, copies the result, announces the character count and closes.
  Empty recognition shows a brief notice without changing the clipboard.
- Pin creates a draggable floating image with a bottom-right resize grip, Escape/close
  button and Copy, Save, Close and Lock Position context-menu commands. Pins have no
  persistent history or click-through mode.

## Annotate existing images or captures

Open PNG/JPEG/TIFF images from the menu/editor, drop them onto the canvas, or focus
the canvas and paste an image with Command-V. Replacing the image starts a new edit.
Image actions use the same editor store, renderer and PNG output service.

| Key | Tool/action |
| --- | --- |
| V | Select annotation; drag to move |
| P / H | Pen / Highlighter |
| L / A | Line / Arrow |
| R / E | Rectangle / Ellipse |
| T | Inline text |
| B / U | Mosaic / Gaussian blur |
| N | Numbered marker |
| Delete / Backspace | Delete the selected annotation |
| [ / ] or Option-scroll | Adjust stroke width, text size or marker size |
| Command-Z / Command-Shift-Z | Undo / Redo |
| Command-C / Command-S / Command-Shift-C | Copy / Save / Copy and Save |
| Pinch / Command-scroll | Zoom (25–800%) |
| Space-drag | Pan |
| 0 / 1 | Fit to window / 100% |

The grouped toolbar displays shortcut badges when space permits and keeps tool/key
tooltips at every width. The keyboard button opens a grouped shortcut reference.
The text icon is a literal T, independent of system symbol localization. Color uses
a 24-point swatch; size lives in a small popover and follows the selected tool or
annotation. Blur exposes no unsupported intensity setting.

Selected annotations have an outline. Color and stroke-width controls update the
selection with undo support. A continuous slider drag or color-panel interaction
forms one undo transaction. Clear All cancels active gestures, clears selection and
starts marker numbering at 1; deleting one marker does not renumber other markers.
Undo/Redo recalculate the next number from the restored annotations. Switching from
Select to a drawing tool clears the selected annotation, so later style changes only
affect new drawing. The last drawing tool, color, width and font size are saved locally
for the next editor; Select itself is never saved as the default tool.
Shift constrains lines/arrows to 45-degree increments and rectangles/ellipses to
squares/circles. Text is entered on the canvas: Command-Enter or an outside click
commits, Escape cancels. The first outside click only commits text and is consumed.
Window-level shortcuts work after toolbar interactions but leave text responders
and system menu shortcuts alone. Escape cancels an active drawing gesture before
closing the editor. Zoom and pan remain in the AppKit canvas and do not change
export resolution or annotation coordinates.
Mosaic/blur images are cached for the current canvas image, rather than regenerated
on every pointer event. The blur uses Core Image with a region clip; no new dependency.

## Design references and validation

Behavior references: [Flameshot keys](https://flameshot.org/docs/guide/key-bindings/),
[ksnip features](https://github.com/ksnip/ksnip), [TRex](https://github.com/amebalabs/TRex),
and [Capso's product description](https://github.com/lzhgus/Capso#readme).
The implementation is original YuanGUI code. No Capso source was copied.

Automated coverage exercises selection states, handles, screen clamping, keyboard
geometry, annotation edits/undo, constrained drawing, marker numbering, rendering and
the capture window policy (own-process windows stay selectable, only session overlays
are hidden).
Run `swift test --skip 'YuanGUIBenchmarks'` and `./script/build_and_run.sh --verify`.
Actual capture permissions, display arrangements/scales, window hover targets,
Spaces, keyboard focus, dragging, paste/drop, HUD placement and visual appearance
still need manual acceptance on the user's displays. Building/launching alone does
not verify those interactions.
