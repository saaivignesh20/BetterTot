# Manual Testing

Run `scripts/test.sh` before this checklist. Test an app bundle built with
`scripts/bundle.sh`, not only `swift run`.

## Panel and Editing

- [ ] Return inserts a newline and never dismisses the panel.
- [ ] Return continues `- ` and `* ` bullets, including indented bullets.
- [ ] Return after `☐`, `☑`, or legacy Markdown checkbox markers creates a new
      unchecked `☐` checkbox.
- [ ] Clicking `☐` or `☑` toggles it without changing the task text.
- [ ] Command-Return toggles the checkbox on the current line and is undoable.
- [ ] Toggling a legacy `- [ ] ` or `- [x] ` line converts it to `☑` or `☐`.
- [ ] Return on an empty bullet or checkbox removes its marker and exits the
      list.
- [ ] Markdown headings, bold, italic, inline code, and web links style live;
      complete delimiters are hidden, bold follows the pad color, and exported
      text retains the original Markdown.
- [ ] The editor is focused when opened from both the status item and shortcut.
- [ ] Escape and outside clicks dismiss only an unpinned panel.
- [ ] Clicking the menu-bar icon while open closes it without reopening it.
- [ ] Dragging the panel background pins it at the dragged position.
- [ ] The pin button beside Settings reflects click-to-pin and drag-to-pin.
- [ ] Pinning does not recreate the editor or discard its undo history.
- [ ] The close button dismisses both modes; reopening a closed pinned panel
      returns it beneath the menu-bar icon.
- [ ] The Settings button closes the panel and opens Settings.
- [ ] The footer reports live line, word, character, and save status, with
      Settings at the right edge.
- [ ] Seven distinct colored pad selectors are visible, and selection does not
      rely on color alone.
- [ ] Control-Tab selects the next pad and Control-Shift-Tab selects the
      previous pad; Command-Left and Command-Right navigate within text without
      switching pads.
- [ ] Rapidly switching pads while typing never loses or crosses text.
- [ ] Undo after switching pads never edits the wrong pad.
- [ ] Selection and scroll position are restored for each pad.
- [ ] The panel remains correctly positioned on a second display and near each
      screen edge.
- [ ] Japanese or Chinese IME composition works; Escape cancels composition
      before it dismisses the panel, and Return remains owned by the IME while
      text is marked.

## Persistence and Recovery

- [ ] Type, immediately terminate BetterTot with `kill -9`, and confirm that the
      text is recovered on relaunch.
- [ ] Create a manual backup and restore it without losing newer data.
- [ ] Import into a non-empty pad using both Replace and Append.
- [ ] Export one pad and all pads, then verify the UTF-8 text files.

## Settings

- [ ] General, Pads, Editor, Storage, and Updates are reachable from the vertical
      navigation and fit within the compact window in light and dark appearances.
- [ ] Each settings icon remains inside one circular material container; the
      selected icon uses the accent color and inactive icons remain gray.
- [ ] A changed global shortcut works outside BetterTot and survives relaunch.
- [ ] Select each pad on the Pads page, assign a name and color, and confirm its
      panel dot, tooltip, and editor accessibility label update immediately.
- [ ] Relaunch BetterTot and confirm custom pad names and colors persist.
- [ ] Clearing a custom name restores `Scratchpad N`; overlong and multiline
      names show an error without changing the existing customization.
- [ ] Plain letters are rejected while recording a shortcut.
- [ ] Starting shortcut recording and then focusing a pinned pad ends recording
      and sends typing to the note.
- [ ] A shortcut already owned by another app produces an actionable alert and
      leaves the previous shortcut active.
- [ ] Font and text-substitution settings apply and survive relaunch.
- [ ] On an Apple Intelligence-compatible Mac running macOS 15.1 or later,
      Writing Tools & Siri is off by default; enabling it restores the system
      writing-tools cursor affordance, and disabling it removes that affordance.
- [ ] While a Writing Tools session is active, intermediate suggestions are not
      written to the pad file; ending the session saves the accepted text.
- [ ] Pads shows seven numbered colored circles, Color is a native pop-up, and
      the rounded Name field has a visible focus ring and current system styling.
- [ ] Storage contains no local-recovery, local-folder, mirror, enable, or
      destination controls.
- [ ] With iCloud Drive available, Back Up Now publishes to `BetterTot Backups
      (org.bettertot.BetterTot)` and Storage shows the latest time and size.
- [ ] With iCloud Drive unavailable, pad editing survives relaunch, no local
      `Backups` folder is created, and the status menu reports that backup needs
      attention.
- [ ] Place an unknown file in the deterministic iCloud folder. Recheck blocks
      backup and pruning, preserves the file unchanged, and shows the problem.
- [ ] Replace `BetterTot.app`, then reinstall it without deleting Application
      Support. Existing pads, journals, and iCloud backups are rediscovered.
- [ ] A bundled release checks once at launch, does not check again within 24
      hours after success, and still permits Check for Updates manually.
- [ ] Update checks never download or install software automatically.

## Accessibility

- [ ] VoiceOver announces pad changes as `Scratchpad N`, includes a custom name
      when present, and includes the empty state when appropriate.
- [ ] The editor identifies the selected pad.
- [ ] Every panel and settings control is keyboard-reachable and labelled.
