# ClipVault Features

## Overview
ClipVault is a macOS menu bar clipboard history manager built with Swift + SwiftUI (MVVM).

## Core App Behavior
- Runs as a menu bar app with a status bar icon.
- Opens a popover window (about `350x440`) from the menu bar icon.
- Also opens from a global shortcut (default: `Command + Shift + V`).
- Popover focuses search when opened from the global shortcut.
- Supports light/dark/system theme selection, with **Dark** as default.

## Clipboard Monitoring
- Monitors `NSPasteboard` every `0.5s` on a background queue.
- Detects clipboard changes using pasteboard `changeCount`.
- Captures supported content types:
- Text
- URL
- Image
- Ignores unsupported formats.
- Sends captured items to the ViewModel on the main thread for UI updates.

## Clipboard Item Model
Each clipboard item stores:
- `id`
- `content`
- `contentType` (`text`, `url`, `image`)
- `timestamp`
- `previewText`
- `isPinned`
- `duplicateKey` (internal key for deduplication)

## History + Deduplication
- Keeps clipboard history in newest-first order.
- Deduplicates by content signature (`duplicateKey`) for text, URL, and image.
- Duplicate handling:
- old duplicate is removed
- new copy is inserted at top
- pin state is preserved when applicable
- History limit: `100` non-pinned items.
- Pinned items are excluded from the limit and from clear-history removal.

## List UI
- Sections:
- `Pinned`
- `Recent`
- Search UI:
- compact search icon button
- expandable search text field
- real-time filtering
- Type filter menu:
- All
- Text
- Image
- URL
- Empty state uses `ContentUnavailableView`.

## Row UI + Actions
- Row shows:
- content type icon and label
- copy timestamp
- preview content (text/url/image thumbnail)
- pin toggle button
- image selection checkbox (images only)
- per-row copy button (`doc.on.doc` icon)
- Row click:
- copies item to clipboard
- closes popover
- attempts to paste into previously active app/input field
- Copy button click:
- copies item without closing popover
- shows small `Copied` toast

## Keyboard Navigation in Popover
- `Tab`: move selection to next visible item.
- `Shift + Tab`: move selection to previous visible item.
- `Enter`: activate selected item (copy + close + auto-paste flow).
- Selected row auto-scrolls into view.

## Auto-Paste Into Active Input
When an item is chosen from the popover:
- ClipVault remembers/targets the previously active non-ClipVault app.
- Refocuses that app.
- Waits until app is frontmost.
- Sends synthetic `Command + V`.

Accessibility requirement:
- Requires Accessibility permission (`System Settings > Privacy & Security > Accessibility`) to send the paste key event.
- If permission is not granted, ClipVault still returns focus to the target app so manual paste can be used.

## Preview System (Shift-to-Toggle)
- Hover a row and press `Shift` to toggle preview.
- Supports both text and image preview popovers.
- Preview stays usable while cursor moves from row to preview.
- Preview closes when neither row nor preview is hovered.
- Coordinator ensures only the actively hovered row can own preview state.

### Text Preview
- Side popover with editable text view.
- Multi-line selection and copy supported.
- Inline search field for preview content.
- Matches are highlighted.
- Auto-jumps to first match when query changes.
- `No matches found` hint when search has no result.
- Save icon appears when edited text differs from original.
- Saving edited text updates history, deduplicates, preserves pin semantics, and reorders item to top.

### Image Preview
- Large side preview popover for images.
- Supports dragging image files from preview area.

## Image Selection + Multi-Drag
- Images can be selected via:
- checkbox in row
- `Command + click` row behavior
- Multiple selected images can be dragged together.
- Drag payload exposes file URLs and file representations for broad app compatibility.
- Drag can start from image thumbnail and row drag handle area.
- Selection is cleared on normal item selection and when popover closes.
- Invalid/removed image selections are auto-pruned.

## Persistence + Security
- Clipboard history is persisted automatically to local app support.
- Auto-save is debounced.
- History file format is encrypted JSON (`.encjson`).
- Encryption:
- AES-GCM (`CryptoKit`)
- key stored in Keychain (`ThisDeviceOnly` / after first unlock)
- App can export encrypted archive.
- App can import encrypted archive and merge with existing history.
- Restore on launch includes normalization + dedup + history-limit enforcement.

## Settings
- Appearance section:
- Theme picker: System / Light / Dark
- Global Shortcut section:
- Record custom shortcut
- Reset to default
- supports Command/Shift/Option/Control combinations
- Data section:
- Export Encrypted JSON
- Import Encrypted JSON
- status messaging for export/import outcomes

## Footer Actions
- Clear history icon button with confirmation dialog.
- Settings icon button (`SettingsLink`).
- Quit app icon button.

## Architecture + Structure
- MVVM architecture.
- Main structure:
- `Models/ClipboardItem.swift`
- `ViewModels/ClipboardViewModel.swift`
- `Views/MenuBarView.swift`
- `Views/ClipboardListView.swift`
- `Views/ClipboardItemRow.swift`
- `Services/ClipboardMonitorService.swift`
- `Services/GlobalHotkeyManager.swift`
- `Services/ClipboardStorageService.swift`
- `AppDelegate.swift` (menu bar controller, popover lifecycle, active-app paste behavior)

## Notes / Current Constraints
- Unsupported clipboard formats are intentionally ignored.
- Some secure fields/apps may block synthetic paste even with accessibility access.
- Image dragging relies on temporary files generated in macOS temp directory.
