# Design Notes

This document describes the data formats (Export/Import, encryption container), cryptographic specifications, interoperability conventions for other platforms, and the performance/design policy. Use it to get an overview before reading the source code.

For a user-facing overview see [../README.md](../README.md); for environment and build steps see [DEVELOPMENT.md](DEVELOPMENT.md).

> 日本語版は [DESIGN_JP.md](DESIGN_JP.md) を参照してください。

---

## 1. Export / Import File Schema

The JSON produced by Export in the Secure Info window (⚙ menu) is the **user-configured sensitive information** (`SecureUserData`). Import reads this file. Information the app generates automatically (encryption keys, etc.) is not included in the Export (see [4. Classification of Information](#4-classification-of-information-user-configured--app-generated)).

> **Note:** The Export file is plaintext JSON. Handle it with care.

### `SecureUserData` (Export/Import root)

| Key | Type | Description |
|---|---|---|
| `version` | Int | Schema version (currently `2`) |
| `items` | `SecureMenuItem[]` | Array of secure items |
| `cryptoPassword` | String? (optional) | The fixed file-encryption password (fingerprint password). Omitted if unregistered |

### `SecureMenuItem`

| Key | Type | Description |
|---|---|---|
| `itemID` | String | Stable item ID (UUID) |
| `title` | String | Display name (e.g. "GitHub") |
| `fields` | `Field[]` | Array of fields |
| `displayOrder` | Int | Display order in the menu |

### `SecureMenuItem.Field`

| Key | Type | Description |
|---|---|---|
| `fieldID` | String | Stable field ID (UUID). Used so history follows the field even after a label change |
| `label` | String | Field name (e.g. "Password") |
| `value` | String | The value. For TOTP, an otpauth URI / Base32 secret |
| `isPassword` | Bool | Whether to mask the value |
| `kind` | String | `"plain"` or `"totp"` (only these two values are ever written — see forward compatibility below) |
| `contentKind` | String (optional) | Extended kind `"url"` / `"note"`. Added in v1.2.0. Omitted for the base kinds |
| `history` | `FieldHistoryEntry[]` | Value change history (recorded for `plain` / `url` only; `totp` and `note` keep none) |
| `createdAt` | Date | Creation timestamp |

#### Field Kinds

| Kind | JSON representation | Purpose |
|---|---|---|
| `plain` | `kind: "plain"` | Ordinary text such as an ID or password |
| `totp` | `kind: "totp"` | `value` holds an otpauth URI / Base32 secret; a one-time code is generated on selection |
| `url` | `kind: "plain"` + `contentKind: "url"` | Login URL. Can be opened in a browser |
| `note` | `kind: "plain"` + `contentKind: "note"` | Multi-line memo such as a contract number or contact details |

### `FieldHistoryEntry`

| Key | Type | Description |
|---|---|---|
| `value` | String | The previous value |
| `replacedAt` | Date | When it was replaced |

### Backward Compatibility

- Decoding is lenient; missing keys are filled with defaults (current version if `version` is missing, `plain` if `kind` is missing, empty if `history` is missing, etc.).
- **An unknown kind falls back to `plain`.** A kind written by a future version still decodes successfully in an older binary, and the value is preserved.
- Import prefers the current format (`SecureUserData` object), and **also reads the legacy format (an array of `SecureMenuItem` only)** as a fallback. Files exported by older versions can be imported as-is.

### Forward Compatibility (Downgrading)

Writing an extended kind (`url` / `note`) directly into the `kind` key would make v1.1.x and earlier **throw while decoding, rendering every secure item unreadable** — and saving over unreadable data would lose all of it. Extended kinds are therefore kept in a separate `contentKind` key.

- Older versions ignore `contentKind` as an unknown key and read the field as `kind: "plain"`.
- **No value is lost.** TOTP secrets keep `kind: "totp"` as well.
- However, re-saving in an older version drops `contentKind`, demoting URL / note fields to plain text (values survive). Editing a note in an older version's single-line field also flattens its newlines.

### Protection When Data Cannot Be Read

If the Keychain read succeeds but the contents cannot be decoded (corruption, for example), `SecureMenuService` returns `errSecDecode`, treats the data as unreadable, and **rejects every write**. This prevents overwriting existing data with an empty set. Migration from legacy entries is likewise aborted — leaving the legacy entries in place — when the old data cannot be decoded.

---

## 2. Encryption / Decryption Specification

### 2-1. File Encryption Container (current: version 2)

**Design requirement:** files must be decryptable with only the `openssl` command even on a machine without the app. Therefore the encrypted body is fully compatible with `openssl enc` output, and an HMAC-SHA256 authentication (Encrypt-then-MAC) is added around it.

**Byte layout:**

| Offset | Size | Content |
|---|---|---|
| 0 | 7 | Magic `"CLPYENC"` (ASCII) |
| 7 | 1 | Version `0x02` |
| 8 | 1 | Flags (bit0: folder-derived → untar after decryption) |
| 9 | 4 | PBKDF2 iteration count (UInt32 big-endian, default 200000) |
| 13 | 32 | HMAC-SHA256 tag (authenticates the first 13 bytes + the entire body) |
| 45 | variable | Body = fully `openssl enc`-compatible:<br>`"Salted__"(8B) + salt(8B) + AES-256-CBC ciphertext (PKCS7 padding)` |

**Key derivation:** PBKDF2-HMAC-SHA256 derives **80 bytes** at once, split as follows.

- Encryption key: first 32 bytes
- IV: next 16 bytes
- HMAC key: next 32 bytes

The first 48 bytes (encryption key + IV) match the key derivation of `openssl enc -pbkdf2` (PBKDF2 output is block-independent, so the prefix does not change when deriving more). This is the basis of openssl compatibility.

**Authentication:** the header (first 13 bytes) and the entire body are authenticated with HMAC-SHA256. In-app decryption **verifies this HMAC tag before decrypting**, reliably detecting tampering and wrong passwords. The openssl CLI path does not perform this verification (most wrong passwords are still caught by CBC PKCS7 padding errors).

**Decryption with openssl:**

```sh
# Strip the 45-byte header before passing to openssl enc
tail -c +46 file.enc | openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -pass pass:PASSWORD -out restored
# If folder-derived (bit0 of the flag at offset 8 is 1), untar with tar -xf restored
```

### 2-2. Formats Supported for Decryption Only

The app's decryption also auto-detects and reads these past formats (encryption always outputs the current version 2).

| Format | Detection | Specification |
|---|---|---|
| Version 1 | `"CLPYENC" + 0x01` | AES-256-GCM format (old implementation, briefly used). 29B header + 12B nonce + ciphertext + 16B tag |
| Legacy | Does not start with the magic | `8B marker + openssl enc output`. Marker is `"CLIPYDIR"` (folder) or 8 zero bytes (file). Key derivation is PBKDF2-HMAC-SHA256, 100000 iterations |

A standard file produced by `openssl enc -aes-256-cbc -pbkdf2` (without a marker) can also be decrypted as the file variant of the legacy format.

### 2-3. Clipboard History and Snippet Encryption (encryption at rest)

History and snippets live in a SwiftData store (`Thoth.store`); clip payloads live in individual `.data` files. Both are encrypted with app-internal keys and are **device-specific** (not included in Export, not interoperable across machines).

| Target | Method |
|---|---|
| Contents of the store (SwiftData) | AES-256-GCM per field. Format: `"TSF"(3B) + version 0x01(1B) + 12B nonce + ciphertext + 16B tag`. Authenticated data: `Thoth.store/v1\|<model>\|<id>\|<field>` |
| Clip `.data` files | AES-256-GCM. Format: `"CLPYDAT"(7B) + version 0x01(1B) + AES-GCM combined (12B nonce + ciphertext + 16B tag)` |

SwiftData (SQLite underneath) has no encryption at rest, so everything shown in the UI is packed into an encrypted JSON blob (`sealedPayload`). Only the columns needed for ordering, lookup and structure stay in plaintext.

| Model | Plaintext columns | Encrypted contents |
|---|---|---|
| `StoredClip` | id (content key), copy time, `.data` path, whether a thumbnail exists | Title, type, whether it is a color code |
| `StoredClip` thumbnail | — | Downscaled PNG (`sealedThumbnail`) |
| `StoredFolder` | id, index, enabled | Folder name |
| `StoredSnippet` | id, index, enabled, owning folder | Title, body |

Because the **authenticated data contains the model name, id and field name**, a ciphertext moved to another row or another field fails to decrypt instead of being silently accepted.

**No new Keychain entry is created for these keys.** Two keys are derived from the `.data` key (`clipDataEncryptionKey`) with HKDF-SHA256 (salt: `io.github.boyaki-machine.Thoth.store`).

| Purpose | info |
|---|---|
| Field encryption | `io.github.boyaki-machine.Thoth.store.seal.v1` |
| Content key (HMAC) | `io.github.boyaki-machine.Thoth.store.content-key.v1` |

**A clip's id is an HMAC-SHA256 (content key) of the content hash, not the hash itself**, so that a plaintext column cannot be used to confirm guesses for short secrets such as copied passwords. Identical content still maps to the same id, so "overwrite the same history" keeps working.

The derivation constants, the shape of the authenticated data and the ciphertext format all decide whether stored data can still be read; changing them requires a migration. `FieldCipherSpec` pins them against values computed independently of the Swift implementation (HKDF/HMAC with Python's `hmac`, AES-GCM with Ruby's OpenSSL).

- Thumbnails are PNGs redrawn at twice the display size in pixels. Up to v1.4.x they were not actually downscaled: the original-resolution image stayed in a plaintext cache under `~/Library/Caches` (v1.5 regenerates them encrypted and deletes the old cache).
- Existing plaintext `.data` files are migrated to the encrypted format by background processing after launch (pre-migration files remain readable).
- Keys are stored in the macOS Keychain (see [4. Classification of Information](#4-classification-of-information-user-configured--app-generated)).

### 2-4. TOTP

Conforms to RFC 6238.

| Item | Value |
|---|---|
| Algorithm | HMAC-SHA1 / SHA256 / SHA512 (from the otpauth URI `algorithm`, default SHA1) |
| Digits | Default 6 (`digits`) |
| Period | Default 30 seconds (`period`) |
| Input format | `otpauth://totp/...` URI, or a raw Base32 secret |

Base32 decoding does not perform RFC 4648 strict trailing-bit validation, so it accepts random secrets issued by real services (whose trailing bits may be non-zero) — matching the lenient behavior of major authenticator apps.

---

## 3. Interoperability Conventions for Other Platforms

If you later implement an app on another OS (e.g. Windows) that interoperates with this one, the following are the platform-independent compatibility points. Conversely, everything else (the SwiftData store, `.data` files, the Keychain) is device-specific and out of scope for porting/sharing.

### Interoperable Items

| Target | Format | Notes |
|---|---|---|
| **Encrypted files** (`.enc`) | The container format in 2-1 | Built only from standard primitives (PBKDF2-HMAC-SHA256 + AES-256-CBC + HMAC-SHA256). Re-implementable with any language's standard library. Encrypt on Mac → decrypt elsewhere is possible |
| **Secure info Export/Import** | The `SecureUserData` JSON in 1 | Plain JSON. The `version` field accommodates future format changes. Shareable across machines via a file |
| **TOTP** | RFC 6238 + otpauth URI | Fully standard-compliant |

### Implementation Guidance

- When re-implementing the encryption container, strictly follow the 45-byte header layout and the 80-byte PBKDF2 derivation (32+16+32 split). The HMAC covers "the first 13 bytes + the entire body".
- When changing the JSON schema, bump `version` and decode leniently so old versions remain readable (this app's existing decoding follows the same policy).
- To prevent interoperability regressions, it is recommended to prepare test vectors (fixed ciphertext / fixed JSON) shared by both implementations. See the fixed fixtures in `CryptoServiceSpec` / `SecureMenuItemSpec` in this repository.

---

## 4. Classification of Information (User-configured / App-generated)

The information this app stores in the Keychain is consolidated into **two entries** based on its nature. This classification coincides with the boundary of "included in Export or not" and "shareable across devices or not".

| Classification | Keychain entry | Content (JSON schema) | Export | Cross-device |
|---|---|---|---|---|
| **User-configured** | service: `io.github.boyaki-machine.Thoth.SecureMenu`<br>account: `user-data` | `SecureUserData`<br>`{version, items, cryptoPassword}` | Included | Possible |
| **App-generated** | service: `io.github.boyaki-machine.Thoth.Database`<br>account: `app-keys` | `AppGeneratedKeys`<br>`{version, realmEncryptionKey, clipDataEncryptionKey}` | Excluded | Not possible (device-specific) |

In addition, a self-signed certificate for code-signature stabilization (`kSecClassIdentity`, CN: `Thoth Local Signing`) is stored in the Keychain (see "Code Signing" in [DEVELOPMENT.md](DEVELOPMENT.md)).

### Key Management Fail-safes

The handling of app-generated keys (DB / `.data` encryption keys) includes safeguards to prevent data loss.

- If a Keychain read fails with anything **other than** `errSecItemNotFound`, the key is **not** created anew (creating a new key while an existing one is present-but-unreadable would make existing encrypted data permanently unopenable).
- A new key is created **only while running stably-signed (Thoth Local Signing)** (creating it while ad-hoc-signed would make it unreadable after re-signing). Otherwise, encryption is deferred and the app runs in plaintext, retrying on a later launch.
- A newly created key is used only after being **read back and verified** to match.
- Migration from a legacy format (separate entries) deletes the legacy entry only after a successful write and read-back verification of the new entry.

---

## 5. Performance and Design Policy

This section summarizes the overall design policy that speeds up understanding before reading the code.

### 5-1. Launch Sequence (minimizing time to menu-bar display)

The launch process is split into phases, prioritizing display of the menu-bar icon (see the sequence diagram comment in `AppDelegate.swift` for details).

- **Lightweight synchronous work** (DI, icon display) is done first so the menu-bar icon appears immediately.
- **Heavy initialization** (reading the key, opening the store, and on the first launch migrating from Realm) runs in the background (`LibraryProvider.prepare`). Completion is tracked by the `LibraryProvider.isReady` flag, guarding against menu rebuilds and the like touching the storage layer before it is ready.
- **Self re-signing** (external commands like `codesign --deep` that take seconds) runs in the background and falls back to normal launch only on failure.
- **The login-item confirmation dialog** (modal) is shown deferred, after service startup completes.

### 5-2. Clipboard Monitoring and Threads

- Since NSPasteboard has no change-notification API, `changeCount` is **polled at 100 ms intervals** to detect changes. This resident work runs at `.utility` QoS (reading `changeCount` is extremely lightweight, so efficiency cores suffice; the upper bound of perceived latency is the 100 ms polling interval and does not depend on core speed).
- Save processing (dedup check, thumbnail generation, archiving, file write, insertion into the storage layer) is offloaded onto a dedicated serial queue (`.userInitiated`) so it does not block the main thread.
- SwiftData's `ModelContext` cannot cross threads, so it is used only inside the storage layer's own serial queue. Callers may call from any thread and exchange value types.
- Work the user is waiting on, such as pasting and clip loading, runs at `.userInitiated`; menu display/building runs on the main thread (`.userInteractive` equivalent).

> macOS has no API to pin a specific CPU core. The use of P cores / E cores is delegated to the OS scheduler via QoS classes. The intent is "quiet on efficiency cores while idle, responsive on performance cores when operated".

### 5-3. Lazy Menu Rebuilding

Menus (NSMenu) keep a fixed instance and rebuild only their content just before display. Changes to history, snippets, and settings only advance a **generation counter**; the actual build cost (proportional to history size) is not paid until the moment the menu is opened. This eliminates rebuilding all menus on every copy (see `MenuManager`).

### 5-4. Clipboard Concealment

- Regular secure-menu items and password-generation results are written with `org.nspasteboard.ConcealedType` / `TransientType` markers, and `ClipService` excludes copies carrying these markers from history. This keeps both the app's own concealed copies and copies from other password managers that support the same convention out of history.
- TOTP never touches the clipboard; it is pasted by direct keystroke injection via `CGEvent` (leaving no trace in the OS copy history or the app's history).
- A paste from the secure menu saves the clipboard's previous content (every item and type) in a `PasteboardSnapshot`, and about 2 seconds after sending ⌘V (`PasteService.concealedPasteRestoreDelay`) puts that content back. The secret therefore does not linger on the clipboard where ⌘V could paste it again, and whatever the user had copied before is not lost. `ClipService.incrementChangeCount()` is called just before restoring so the restored content is not recorded as a new copy.
- When Thoth cannot paste automatically (the “Input "⌘ + V" after menu item selection” preference is off, or Accessibility permission is missing), and for "Copy" in the confirmation window and the password generator, the user pastes by hand, so the clipboard is cleared after 30 seconds.
- In every case the `changeCount` is checked so that content the user copied in the meantime is not cleared.
- A value chosen from a panel (history or secure items) is sent only after the target app has been brought back to the front (`CallerAppActivator`). The target is the frontmost app at the moment the hotkey was pressed, unaffected by an authentication dialog in between. Because `activate` is asynchronous, Thoth waits at least 0.2 seconds after requesting it, then sends ⌘V or the keystrokes once that app is both frontmost and the owner of keyboard focus (the Accessibility focused application), waiting up to 1 second. Sent any earlier, Thoth itself would receive them, and it would beep or nothing would happen. `NSWorkspace.frontmostApplication` and `NSRunningApplication.isActive` already point to the target a few milliseconds after the request, so they cannot be used on their own.

### 5-5. Code-Signature Stabilization

As noted above, to cope with the macOS behavior of binding keychain ACLs to code signatures, `CodeSignService` self-re-signs with a device-specific certificate at launch. This lets you keep reading secure items across repeated local builds (see [DEVELOPMENT.md](DEVELOPMENT.md)).

### 5-6. Secure Info Window

A two-pane window for browsing and editing secure information (main menu → **Secure Info**, or **Secure Info (&s)** at the bottom of the picker panel). The design decisions are as follows.

**Retiring the Manage Secure Items window (v1.3.0)**

Through v1.2.x there were two screens with the same job: the Manage Secure Items window (`p` from the picker panel; a list plus an edit sheet) and this Secure Info window (`s` from the main menu; two panes). By the end of v1.2.x the Secure Info window had grown into an almost complete superset, and maintaining both stopped paying for itself.

**Security decided it before features did.** The Manage window has neither `sharingType = .none` (exclusion from screen sharing and recording) nor an authentication gate before display. Leaving the same plaintext reachable through a less-protected path was not worth keeping.

What was carried over, and what was not:

| Feature of the Manage window | Decision | Reason |
|---|---|---|
| Access to the password generator | **Ported** (and improved) | The only real gap. See below |
| Multi-select bulk delete | Not ported | The Secure Info window shows the selected item's detail in the right pane, which fits poorly with multi-selection; ⌘Z makes one-at-a-time deletion sufficient |
| Deleting individual history entries | Not ported | Old values are the fallback path after an authentication-side rollback; this screen must not offer a way to lose them (see "Value history") |
| The "fields" count column in the list | Not ported | The selected item's detail is always in the right pane instead |
| Cancel (discard) in the edit sheet | Not ported | The Secure Info window is built on autosave + ⌘Z; adding "discard" would give it two competing save models |

The picker panel's trailing row now points at the Secure Info window, and its key is aligned with the main menu: `p` → `s` (`p` is left unassigned). **The row's label and its key handling live in different files**, so changing only one produces a row that reads `(&s)` but does not respond to `s`. `CPYSecurePickerPanelSpec` pins both together.

The picker panel is only reachable after authentication, so opening the Secure Info window from it falls inside `SecureMenuService.authenticationGracePeriod` (30 s) and does not prompt for Touch ID again.

**Division of labor with the picker panel (⌘⇧.)**

The picker panel is a 260px-wide, 22px-per-row UI built for "pick fast and paste", with no room for long text. Memo (`note`) fields are excluded from it and belong to the Secure Info window (**only from the display — they are still searched**; see "Search rules" below). URLs are worth pasting, so they do appear in the panel, prefixed with `🔗`.

Which fields go into the sub-panel is decided in exactly one place: `CPYSecurePickerPanel.subPanelFields(for:)`. The `fieldIndex` recorded on selection is an index into that array, and it is also used to restore "continue-paste mode". If either the display side or the open/close check used `item.fields` directly, re-opening the panel would paste a different field.

**Search rules (v1.3.1) — shared with the picker panel**

Filtering lives in `SecureItemSearch` (UI-independent), and **the Secure Info window's search box and the picker panel's (⌘⇧.) behave identically**. Change the rules there and nowhere else.

Up to v1.3.0 each screen had its own implementation and the rules had drifted apart: the Secure Info window matched titles, labels and memo bodies, while the picker matched titles and labels only — and its multi-word AND only applied *within a single label*. The same query surfaced an item on one screen but not the other, which reads to the user as **"the thing I saved is gone"**. Hence the unification.

| Item | Treatment |
|---|---|
| Title, every field label | Matched |
| Values of unmasked (🔒 off) text and URL fields | Matched — lets you find "which account was it" from a login ID or a URL's domain |
| Memo bodies | Matched — finding an account by contract number is a real use case |
| **Masked field values** | **Not matched** |
| **TOTP secrets** | **Not matched** |
| Multiple words (split on whitespace/newlines) | AND; words may match across title, labels and values ("github password") |
| Case | Ignored |

Masked values and TOTP secrets stay out because there is no use case for searching by a fragment of those, and including them would invite typing secrets into a search box that does not mask what you type. Memo is a kind with no mask concept, so its body is matched even when legacy data or an imported JSON left `isPassword` set.

The per-kind rule lives in `SecureMenuItem.Field.Kind.valueSearchability`, and `Field.isValueSearchable` combines it with the mask flag. Both are `default`-less switches, so adding a kind surfaces every place that needs a decision as a compile error.

**Memo fields are searched from the picker panel too, even though they are not displayed there.** Filtering only reorders which parent items are listed, and neither screen shows the matched value itself, so there is no reason to vary the target per screen — and varying it would bring back the "shows up in one screen but not the other" gap. `SecureItemSearchSpec`'s "画面間で条件が揃っていること" pins the two screens to the same results.

**Why the right pane is not an NSTableView**

- A memo's `NSTextView` has a variable row height, which fits poorly with a table's automatic row heights
- With cell reuse, a password revealed with 👁 could leave its revealed state on a different field's row. Making row views disposable removes that hazard structurally

**Commit timing**

There is deliberately no per-keystroke debounce. `SecureMenuService.save(_:)` appends one history entry each time a value changes (capped at 10), so debounced saves would fill the history with partial keystrokes and push out the real previous value. Commits happen only at: end of editing, just before switching the selected item, window deactivation, app termination, ⌘S, and 20 seconds after the last input (a safety net).

**Masked values cannot be edited**

Editing a value while it is masked would save the visible `••••••••` as the value itself. Revealing it with 👁 is required first. TOTP is never editable because its secret is not displayed. When the Keychain cannot be read (`isKeychainAccessDenied`), input is blocked up front — otherwise the user would type into fields whose save is going to be rejected, losing the input.

**Protecting displayed plaintext**

| Protection | Detail |
|---|---|
| Authentication gate | `secureMenuService.authenticate()` before display (sharing the 30-second grace period) |
| Auto re-mask | A value revealed with 👁 returns to mask after 30 seconds, and immediately on window deactivation |
| Screen-capture exclusion | `NSWindow.sharingType = .none` |
| Screen lock / sleep | `com.apple.screenIsLocked` (distributed notification) and `NSWorkspace.willSleepNotification` commit and then close the window |
| Memory | Plaintext held in memory is discarded on close and re-read on the next open |
| Opening URLs | Only `http` / `https` with a host. Prevents `file://` or custom schemes from imported data launching unintended apps |

**Synchronizing across screens**

Every screen that touches secure items shares one `SecureMenuService`. Changes are announced via `Notification.Name.secureItemsDidChange`, posted from two places: `saveAllItems` (save / delete / reorder) and `deleteAllItems` (which does not go through `saveAllItems`, so covering only the former would fail to synchronize a full delete).

This machinery stays after the Manage window was retired in v1.3.0: the Secure Info window can be left open while the app is re-activated to use the picker panel, and any future screen needs the same foundation.

The Secure Info window uses `SecureMenuService.itemsChangeToken` to tell whether a change was its own. Reloading after its own save would rebuild the row views and throw away editing focus and cursor position. When unsaved edits exist it does not reload at all; it shows a banner and leaves the decision to the user.

**Undo (⌘Z) — a two-layer model**

Added in v1.2.1. Undo is split into two layers:

| Layer | Owner | Granularity | Lifetime |
|---|---|---|---|
| While typing | AppKit (field editor / `NSTextView`) | Per keystroke | Until focus leaves |
| After committing | `SecureInfoUndoStack` | One save | Until the window closes |

The app-level unit is **one write to the Keychain**. That reuses the existing commit design (no per-keystroke debounce; commits happen only at editing boundaries) as the undo granularity. While typing, `keyAction(...)` returns `nil` for ⌘Z so the event falls through to the standard keystroke undo.

Snapshots are pushed only on the five paths that write to the Keychain. Every edit (title, label, value, mask flag, adding / removing / reordering fields) goes through `save(_:)`, so one push there covers them all; the rest are adding, deleting and reordering items, and import.

**Restoring uses `reorderItems(_:)`, not `save(_:)`.** `save(_:)` appends one history entry each time a value changes (capped at 10), so undoing through it would consume the history and push out the real previous value. `reorderItems(_:)` writes the given array verbatim and leaves history untouched.

**The stack holds plaintext from before the deletion or edit.** It is cleared in three places; missing any one of them either leaves secrets in memory or rolls back another window's change.

| When | Why |
|---|---|
| Closing the window | Leave no plaintext behind (called alongside `clearSensitiveData()`) |
| Reloading data | Snapshots no longer match the current data |
| Showing the external-change banner | This path does not reload; keeping stale snapshots would roll back the other window's change on undo |

**Deletion is guarded by "hide it and make it reversible", not by a confirmation dialog**

v1.2.0 showed a confirmation dialog for field deletion, but because it appeared every time it was dismissed by reflex — and once dismissed there was no way back. The direct cause of misclicks was copy ⧉ sitting 2pt away from delete 🗑.

v1.2.1 drops the dialog, moves 🗑 **outside the button stack** with a 10pt gap, and shows it only while the pointer is over the row (or while that row is being edited). Keeping it in the stack and toggling `isHidden` would collapse its width and shift the other buttons sideways, making them impossible to aim at — hence the structural separation. A right-click menu on the row provides a discoverable second path to delete.

**Item deletion keeps its confirmation**, because it is broader in effect and, once done, the selection clears and nothing on screen shows what was removed.

**Drag-and-drop reordering**

The left pane (items) uses the standard `NSTableView` mechanism. **Dragging is refused while the list is filtered**, because the visible order does not match the stored order and a row number cannot be turned into a correct destination (keyboard reordering is blocked for the same reason).

The right pane (fields) is an `NSStackView`, so this is hand-rolled. A `≡` handle sits at the leading edge of each row and **drags start only from there** — making the whole row draggable would collide with text selection in the value field. The handle's `NSImageView` is an `NSControl` and would swallow `mouseDown`, so `hitTest` routes just that area back to the row.

The pasteboard carries only the `fieldID` or the row number — **never a value** — because a drag pasteboard is readable by other apps. `draggingSession(_:sourceOperationMaskFor:)` also refuses anything but `.withinApplication`, so a row cannot be dragged out of the app.

**The drag image is not a snapshot of the row.** A drag image is drawn in a system-owned window, outside this window, so `NSWindow.sharingType = .none` (which keeps the window out of screen sharing and recording) does not cover it. Snapshotting the whole row would put a password revealed with 👁 — or a memo's body — into a surface that *can* be recorded. Drawing **only the label** leaks nothing beyond what the picker panel already displays, while still showing which field is being dragged (values are searchable, but neither screen ever displays them, so that is not a justification). Everything that leaves the row is decided in one place: `SecureFieldRowView.makeDraggingItem()`.

**Import / export**

The logic lives in `SecureItemsTransfer` (UI-independent) and is reached from the ⚙ menu at the bottom of the left pane.

**Neither runs when the Keychain cannot be read (`isKeychainAccessDenied`).** Import would merely be rejected by `saveAllItems`, but export would write a JSON file with zero items — inviting the user to overwrite an existing backup with an empty one.

That check lives **inside `SecureItemsTransfer.exportData(using:)`**. The caller-side gates (the ⚙ menu's enabled state, `allowsTransfer`) only consult a cached copy of the last read result, so they miss the case where the Keychain becomes unreadable while the save panel is open. The read has to be re-verified immediately before writing.

Import is the least reversible operation here, so undo remains available afterwards (`reloadItems(clearsUndoHistory: false)`).

**Undo restores items only — not the fingerprint password.** Replacing it happens only after a confirmation that spells out "files encrypted with the current password will no longer open", so a partial undo is accepted here deliberately.

**Value history (v1.2.2)**

The same value history the retired edit sheet showed (`Field.history`, capped at 10) is readable from the Secure Info window. There are two uses, and both require the value to be *visible*:

1. Authentication systems that reject "the same password as any of the last N" force the user to **compare past values by eye** before choosing a new one
2. After a rollback on the authentication side, an old password is the **fallback** that still gets you in

**History expands inline under the row — not in a menu.** Once the value is on screen, where it is drawn decides whether it is protected. `NSWindow.sharingType = .none` (exclusion from screen sharing and recording) covers only the window's own surface; NSMenu and NSPopover are drawn in separate windows and are not covered — the same point as the drag image. The retired edit sheet did list plaintext in a menu, but the Secure Info window is built on the promise of protecting plaintext, so it does not copy that.

History inherits the row's discipline verbatim: masked by default / 👁 reveals and `revealTimeout` seconds re-masks / immediate re-mask on window deactivation / concealed copy with auto-clear. The timeout comes from `SecureFieldRowView.revealTimeout` so that "how long plaintext may stay on screen" is decided in one place. If `startRefreshTimerIfNeeded()` did not count revealed *history* values, opening only a history entry would leave the auto re-mask unarmed.

🕘 appears only on rows that **have at least one history entry**, and only while hovered or being edited. Because it sits in the middle of the button stack, it is toggled with `alphaValue` rather than `isHidden` — the width stays reserved so copy ⧉ does not slide sideways the moment it appears. Kinds that keep no history (TOTP, memo) never show it: a TOTP secret is deliberately never recorded, so even legacy data carrying one is not displayed.

**History is read-only here.** There is no delete and no "restore this value". Use 2 above means this screen must not offer a way to lose history. To go back to an old value the user edits the current one, which pushes the current value into history automatically. Viewing is non-destructive, so it works in read-only mode too.

**Password generation (v1.3.0)**

An affordance inherited from the retired Manage window's edit sheet: **Password Generator...** (**⌘G**) in the bottom bar opens the existing generator as a sheet.

**There is no path that writes the generated value straight into a field.** The user copies the result and pastes it. That path was built and then withdrawn, failing in this order:

1. It first filled **the field that last held editing focus**. A masked value cell is not editable (`isValueEditable`), so it never takes focus — the record was almost always empty, and the feature only worked for users who clicked the *label*
2. A fallback of "use the masked field when there is exactly one" was added. On an item with a text field and a password field it always chose the password field, never the text field the user was looking at. Since **a masked field renders `••••••••` even when empty**, the mistake was invisible; and an item with two password fields could not be narrowed down at all, so the affordance disappeared
3. A "Fill into" popup on the sheet fixed the ambiguity, but **made the generator noticeably heavier to operate**

The generator is not opened often, so the copy-and-paste round trip is an acceptable cost. The point this decision turns on: **do not decide "where it lands" outside the user's view.**

**How history behaves on export / import (as investigated for v1.2.2)**

| Path | Behavior |
|---|---|
| Export | History **is included** (past passwords land in the JSON in cleartext) |
| Import | History **is read back** |
| Re-import over an existing item | The current history is **replaced by the file's** (plus one entry if the value differs) |

The third follows from `mergeFieldHistories` taking the incoming `field.history` as its base — intentional, so that deleting an entry from the popup survives a save. On the import path it shows up as "restoring an old backup rewinds the history".

**Why undo also lives in the ⚙ menu**

Since the delete button only appears on hover, the fact that deletions *are* reversible has to be visible somewhere. The menu item is titled from `undoAction` (e.g. "Undo Delete Item") so it also says what will come back.

### 5-7. Migration from Realm to SwiftData (v1.5)

Storage moved from Realm to SwiftData. The migration runs **once, on the first launch of v1.5.x**.

1. Open Realm **read-only** and read everything into value types (`ClipRecord` / `SnippetFolderRecord` / `SnippetRecord`)
2. Create the new store at its final location (`Thoth.store`) and write the data encrypted (clip ids are replaced with content keys)
3. **Read it back with a fresh `ModelContext`** and verify counts, every field and the ordering
4. Only when verification passes, write the **completion marker** (`Thoth.store.ready`) next to it

- **The Realm file is never written to.** It is kept until v1.6.x, so rolling back to v1.4.x shows the data as of the migration (changes made in v1.5.x afterwards are not visible there, and changes made in the old version are not picked up later — a known limitation).
- **A store without the completion marker is an interrupted migration.** The app only uses stores that have the marker, so such a store holds no user data; it is deleted before opening on the next launch and the migration is retried.
- A store that has the marker but cannot be opened is moved aside as `Thoth.store.broken-<timestamp>` instead of being deleted.
- The migration does not write to a temporary file and then move it: SwiftData has no way to close a store, and moving files that have been opened corrupts SQLite (`SQLITE_IOERR_VNODE`).
- Thumbnails are not carried over from the old plaintext cache; they are regenerated from the `.data` files, after which the old cache directory is deleted.

**When the encryption key is unavailable, nothing is written to disk for that session.** Three situations count as unavailable:

| Situation | Examples |
|---|---|
| The key exists but cannot be read | The login keychain is locked, access was denied, or the signature changed and no longer matches the ACL |
| The key does not exist yet and cannot be created | Self re-signing failed, so the app is still ad-hoc signed |
| The key is readable but does not match | The keychain was reset and a new key was created |

- History is kept in memory only (still usable for pasting during that session).
- **Snippets are neither shown nor editable.** An empty-looking list invites re-creating them, which would silently vanish at quit and duplicate after recovery. The menu shows a single row explaining why, and the editor refuses edits and explains in a sheet (the same approach as `isKeychainAccessDenied` for secure items).
- The store is never deleted, and never overwritten with a new key. Once the cause is resolved, the next launch reads everything as before.
- Secure items (passwords, TOTP) live in a different Keychain entry and do not use this key, so they are unaffected.
