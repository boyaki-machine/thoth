<div align="center">
  <img src="./Resources/thoth_logo.png" width="400">
</div>

<br>

**Thoth** is a clipboard extension app for macOS. It is a personal, feature-extended fork of the original [Clipy](https://github.com/Clipy/Clipy), adding secure item management, password generation, and file encryption.

**Requirements:** macOS 15.0 (Sequoia) or later · Macs with Apple silicon (M-series) only (does not run on Intel Macs)

> 日本語版は [README_JP.md](README_JP.md) を参照してください。

---

## Table of Contents

- [1. About This App](#1-about-this-app)
- [2. Features](#2-features)
- [3. Installation & Running](#3-installation--running)
- [4. Settings](#4-settings)
- [License](#license)
- [Special Thanks](#special-thanks)

---

## 1. About This App

This project is a fork of **[Clipy](https://github.com/Clipy/Clipy)** (MIT licensed), an open-source clipboard extension app for macOS, extended with additional features.

It keeps the clipboard history and snippet features of the original Clipy, and adds:

- **Secure item management** — paste passwords, TOTP, and other sensitive values directly without leaving them on the clipboard. Related URLs and memos can be kept alongside them
- **Password generation** — generate random passwords with configurable rules
- **File encryption / decryption** — encrypt files and folders in an openssl-compatible format

### About the Name "Thoth"

This app started as a fork of Clipy, but as its own features grew and the differences became substantial — and out of respect for the original developers' wish that derivatives not use the Clipy name — it was renamed **Thoth**.

Thoth is the ancient Egyptian god of **scribes, records, and wisdom**. The name of the god who writes down every word and guards secret knowledge felt fitting for an app that records your clipboard and manages your secrets. In Japanese, "Thoth" also happens to sound exactly like "tote (bag)" — a bag you can toss anything into. In the hieroglyph display mode (a joke feature), the app name is written as 𓍹𓆓𓎛𓅱𓏏𓇋𓍺, the spelling of Djehuty, Thoth's ancient Egyptian name.

### Acknowledgements

Deep thanks to the developers of Clipy for publishing such a great app as open source, and to [@naotaka](https://github.com/naotaka) who published its origin, [ClipMenu](https://github.com/naotaka/ClipMenu). This project stands on the shoulders of these predecessors.

This app is provided under the MIT license. The attribution and original developers' credits are preserved as-is in the source code and commit history.

> For developer information (environment, build steps), see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
> For data formats, cryptographic specifications, and design policy, see [docs/DESIGN.md](docs/DESIGN.md).

### A Note from the Developer

All new implementation in this application was written by an AI Agent. The only thing the developer actually wrote is this sentence — everything else was implemented by the AI Agent based on the developer's specifications. Testing and security checks were done with care, but please use this app at your own risk.

---

## 2. Features

### 2-1. Clipboard History & Snippets (from the original Clipy)

Keeps a history of copied content that you can re-paste from a menu. Frequently used boilerplate text can be registered as snippets.

**How to use:**

- Content you copy (⌘C) is automatically accumulated in the history
- Open a menu with a hotkey and select an item to paste it into the frontmost app

| Menu | Default hotkey |
|---|---|
| Main menu (search + history + snippets + tools + settings) | **⌘⇧V** |
| Copy history window (search + history only) | **⌘⌃V** |
| Snippet menu | **⌘⇧B** |

- The main menu and the copy history window appear as panels with a search box at the top (clicking the status bar icon also opens the main menu)
- Copy history is shown in groups of 10 (`0 - 9`, `10 - 19`, ...); hovering over a group shows its items in a submenu, where the number keys `0`–`9` select an item directly
- Press `/` to move to the search box and narrow the history down incrementally. The search covers not only titles but the **full text of the copied content**, and hits stay in their original groups
- Inside menus you can navigate with arrow keys or vim-style `hjkl` keys
- The maximum history size, display format, excluded apps, etc. can be adjusted in Preferences (see [4. Settings](#4-settings))

### 2-2. Secure Items

Paste passwords, TOTP, and other sensitive values directly into any app **without leaving them in the copy history** (TOTP never touches the clipboard at all; other values are on the clipboard only for the moment of pasting, and the previous content is put back right after). Items are stored encrypted in the macOS Keychain and protected by Touch ID / password authentication every time the menu is opened.

**How to use:**

- Press the hotkey to authenticate, then pick a parent item and a field to paste it directly into the frontmost app

| Menu | Default hotkey |
|---|---|
| Secure menu | **⌘⇧.** |

- Inside the menu you can navigate with arrow keys or vim-style `hjkl` keys
- Press `/` to move to the search box and narrow items down incrementally. The search covers titles and labels plus **the values of unmasked text / URL fields and memo bodies** (masked values and TOTP secrets are excluded). The Secure Info window's search uses the same rules
- The hotkey can be changed in **Preferences → Shortcuts → Secure Menu**

| Feature | Detail |
|---|---|
| **Keychain storage** | All values are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — never synced to iCloud |
| **Biometric lock** | Touch ID (or login password) is required before the menu appears. Within 30 seconds of a successful authentication, re-authentication is skipped so you can pick ID / password / TOTP in a row |
| **Two-level menu** | Select a parent item (e.g. "GitHub"), then a specific field (e.g. "Password") |
| **Direct paste** | The selected value is pasted straight into the app you were using when you pressed the hotkey. It stays out of Thoth's copy history, and once the paste is done the clipboard goes back to what it held before. TOTP is typed as keystrokes directly, leaving no trace in any history |
| **Continue-paste mode** | Re-opening the menu within 30 seconds highlights the previously selected field automatically |
| **TOTP support** | Register from an otpauth URI / QR code; a one-time code is generated and typed at selection time |

**Field kinds:**

An item can hold several fields, each of one of these kinds.

| Kind | Purpose | In the picker panel (⌘⇧.) |
|---|---|---|
| **Text** | Ordinary values such as an ID | Shown, can be pasted |
| **Password** | Values that should be masked | Shown as `••••••••`, can be pasted |
| **URL** | The login address | Shown with `🔗`, can be pasted. Can be opened in a browser from the Secure Info window |
| **Memo** | Multi-line notes such as a contract number, support contact, or what the credential is for | **Not shown** (too long for the panel — Secure Info window only), but its body is still searchable |
| **TOTP** | One-time password | Current code and remaining seconds are shown; typed on selection |

**Step 1 — Register your credentials**

Choose **Secure Info** from the main menu (**⌘⇧V**, also launchable with the `s` key while the menu is open). After a Touch ID / password prompt, the **Secure Info window** opens. The same window also opens from **Secure Info (&s)** at the bottom of the secure item picker panel (**⌘⇧.**).

Pick an item in the left pane and edit its contents in the right pane.

1. Click **+** at the bottom left to add an item, then enter its **title** (e.g. "GitHub", "AWS Console")
2. Use **Add Field** at the bottom right to choose a kind (Text / Password / URL / Memo)
3. Fill in the **label** (e.g. "Password") and the **value**
4. To add TOTP, use **Add TOTP...** to import an otpauth URI / QR code
5. Use **Password Generator...** (**⌘G**) to create a password, then **Copy** it and paste it into the value field (reveal a masked field with 👁 first)
6. Edits are saved automatically (**⌘S** saves explicitly)

Export / Import live in the **⚙** menu at the bottom of the left pane, together with undo / redo.

| Action | Key |
|---|---|
| Move the item selection | `j` / `k` |
| Reorder items / fields | `Ctrl+j` / `Ctrl+k` |
| Move to the right pane / back to the list | `l`, `→`, `Return` / `h`, `←` |
| Search | `/` or `⌘F` |
| Add / delete an item | `⌘N` / `⌘⌫` |
| Generate a password | `⌘G` |
| Undo / redo | `⌘Z` / `⌘⇧Z` |
| Save / close the window | `⌘S` / `⌘W`, `Esc` |

**Step 2 — Paste a credential**

1. Click into the input field of the target app
2. Press the hotkey (default: **⌘⇧.**) — a Touch ID / password prompt appears
3. After authentication, the two-level menu opens
4. Select the parent item, then the field to paste

**Security characteristics:**

- Values are read from Keychain only at the moment of authentication
- Pasting a regular field temporarily uses the clipboard, but with a marker that keeps it out of history (`org.nspasteboard.ConcealedType`), and **about 2 seconds after the paste the clipboard is restored to its previous content** (so the pasted value cannot be pasted again with ⌘V; if you copy something else in the meantime, that is kept)
- When Thoth cannot paste for you (the “Input "⌘ + V" after menu item selection” preference is off, or Accessibility permission is missing), the value is left on the clipboard so you can paste it yourself, and cleared after 30 seconds
- TOTP never touches the clipboard; it is typed as keystrokes directly
- The Secure Info window shows values in plaintext, so it is protected as follows:
  - Touch ID / password authentication is required before it opens
  - Passwords are always masked. 👁 reveals a value temporarily, but it is **re-masked automatically after 30 seconds**, and immediately when the window becomes inactive
  - TOTP secrets are never shown — only the current code is
  - The window is **excluded from screen sharing and screen recording** (so it cannot leak into a shared screen; as a trade-off it does not appear in screenshots either)
  - Screen lock and sleep close the window automatically, and its in-memory contents are discarded on close
  - Copying a value also uses the history-excluding marker and clears the clipboard after a short delay

### 2-3. Password Generation

Generates a random password with configurable rules. Randomness comes from the OS CSPRNG (`SecRandomCopyBytes`).

**How to use:**

Choose **Generate New Password** from the main menu (also launchable with the `p` key while the menu is open) to open the generator window.

- **Length**: set with a slider or a numeric field
- **Character types**: any combination of letters / digits / symbols / distinguish upper and lower case
- **Easy-to-type password**: a mode that groups characters by type to reduce keyboard-type switching (e.g. on smartphones)
- **Copy** puts the result on the clipboard (with a concealed marker; auto-cleared after a while)
- A **QR code** of the generated password is shown below the result so you can photograph it with your smartphone (see ["Passing the fingerprint password via QR code" in 2-4](#passing-the-fingerprint-password-via-qr-code))

Password generation can also be invoked from the Secure Info window (**Password Generator...** / **⌘G**) and the fingerprint-password management window. The window is the same wherever it is opened from; you take the result with **Copy**.

### 2-4. File Encryption / Decryption

Encrypts and decrypts files and folders with a password. Encryption is done entirely in-process (passwords are never passed to an external command), and uses an **openssl-compatible container format**, so files can be decrypted with only the `openssl` command even on a machine where Thoth is not installed.

**How to use:**

Choose **Encrypt / Decrypt** from the main menu (also launchable with the `e` key while the menu is open) to open the window.

1. Choose a target file / folder with the "Choose..." button
2. Enter a password (you can also recall a registered fixed password via Touch ID using the fingerprint icon)
3. Run **Encrypt** (⌘E) or **Decrypt** (⌘D)
4. After encryption, an example openssl decryption command is shown in the window ("Copy Command" to grab it)

- Encrypted files use the `.enc` extension
- Folders are packed into a tar archive before encryption and unpacked automatically on decryption

#### Passing the Fingerprint Password via QR Code

This feature hands the fingerprint password (the fixed password recalled via Touch ID) over to another machine using a QR code, so you never have to send the password itself through plaintext e-mail or chat when exchanging encrypted files across machines.

**How to use (sender → receiver):**

1. Open the fingerprint password manager (Encrypt / Decrypt window → **Manage Fingerprint Password...**) and authenticate with Touch ID
2. A **QR code generated live** from the password field appears below it
3. **Photograph the QR code with your smartphone** and carry it over
4. On the receiving Mac, open the same manager window and press **Read QR Code** (camera access permission is required on first use)
5. Hold the QR code photo on your smartphone up to the camera — the decoded password fills the field
6. Verify the content and press **Register / Update** to save

- The QR code embeds the password with a `thoth-cpw:v1:` prefix that is validated on reading, so unrelated QR codes (such as TOTP otpauth codes) are never imported by mistake
- The password generator window ([2-3](#2-3-password-generation)) shows a QR code in the same format, enabling a "generate → photograph → read on another machine" flow for distributing a new shared password

> **Note:** The QR code represents the password itself. Handle the photo carefully (cloud sync, sharing, etc.) and delete it once the transfer is done.

#### Decrypting with openssl (recovery without Thoth)

An encrypted file is a 45-byte custom header followed by a standard `openssl enc` body. **Strip the 45-byte header first** before passing it to openssl (passing it directly causes a `bad magic number` error).

```sh
# Decrypt a file (default iteration count is 200000)
tail -c +46 secret.txt.enc | openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -pass pass:YOUR_PASSWORD -out secret.txt

# For a folder, the output is a tar archive
tail -c +46 myfolder.enc | openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -pass pass:YOUR_PASSWORD -out myfolder.tar && tar -xf myfolder.tar
```

#### Decrypting an openssl-encrypted file in this app

This app can also read standard files produced by `openssl enc` (it auto-detects them as a legacy format even without the app's custom header). A file encrypted with openssl as below can be opened via "Decrypt".

```sh
# Encrypt with openssl (a format this app can decrypt)
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt \
  -in secret.txt -out secret.txt.enc -pass pass:YOUR_PASSWORD
```

> **Notes:**
> - In-app decryption verifies the header's HMAC-SHA256 tag before decrypting (Encrypt-then-MAC), reliably detecting tampering and wrong passwords. The openssl CLI path skips this verification (most wrong passwords are still caught by CBC padding errors).
> - The detailed encryption container specification is in [docs/DESIGN.md](docs/DESIGN.md).

---

## 3. Installation & Running

No pre-built binary is provided; build from source. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for detailed build steps.

### Requirements

| Item | Requirement |
|---|---|
| **macOS** | **15.0 (Sequoia) or later** (verified on macOS 27) |
| **CPU** | **Apple silicon (M1 or later M-series) only.** The app is built for arm64 only, so it does not launch on Intel Macs (Rosetta 2 runs Intel apps on Apple silicon, not the other way round) |
| **Build environment** | Xcode 27 (see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)) |

> v1.4.0 raised the minimum to macOS 15.0. v1.3.1 and earlier support macOS 11.0 or later (also Apple silicon only).

**Outline:**

1. Clone the repository
2. Build (open `Thoth.xcodeproj` in Xcode, or use `xcodebuild` from the CLI; dependencies and development tools are fetched automatically during the build)
3. Place the built `Thoth.app` in `/Applications` and launch it

**First-launch notes:**

- The app is not notarized by Apple, so copying it to another Mac and launching it triggers a Gatekeeper block ("cannot verify the developer", etc.). See "Handling the Gatekeeper alert on first launch" below to allow it (first launch only).
- On launch, the app re-signs itself with a device-specific certificate and then relaunches (so that secure items remain readable across versions). A macOS confirmation dialog may appear on the first launch only — choose "Always Allow".
- After re-signing, you must grant **Accessibility permission** (required for the paste feature; no need to re-grant on later version updates).
- See "Code Signing and Accessibility Permission" in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for details.

**Permissions the app requests:**

| Permission | Required? | Purpose |
|---|---|---|
| Accessibility | Required | Used for pasting (sending ⌘V / typing keystrokes) |
| **Desktop folder** | **Optional** | Requested only when the "Save screenshots in history" beta feature is enabled. Needed to read files added to the screenshot location (the Desktop by default). Not requested if you save screenshots somewhere other than the Desktop, Documents, or Downloads (e.g. `~/Pictures`) |

> Desktop folder access is requested **only if you enable the "Save screenshots in history" feature** (disabled by default). If you don't use it, you can deny the request — clipboard history, snippets, secure items, encryption, password generation, and all other features work unaffected.

> **About "Save screenshots in history":** Thoth watches the screenshot folder directly (it also follows a location changed under ⌘⇧5 → Options → Save to) and adds each screenshot to the history as soon as it is saved (since v1.6.0; earlier versions waited for the Spotlight index, so screenshots appeared seconds to tens of seconds late or were missed).
> While macOS's "**Show Floating Thumbnail**" is on (the default), however, macOS does not write the file until the thumbnail in the bottom-right corner goes away, so the history entry also appears about 5 seconds late. To have it added right away, turn that option off under ⌘⇧5 → Options.
> Screenshots taken before the feature was enabled, and files moved into the folder later, are not added.

### Handling the Gatekeeper Alert on First Launch

When you launch a distributed copy of Thoth for the first time on another Mac, you may see an alert such as "Thoth Not Opened" / "Apple could not verify Thoth is free of malware…" that only offers "Move to Trash" and "Done" (on recent macOS). This is the default block for un-notarized apps. Allow it once with either of the methods below and it will launch normally from then on.

First, dismiss the alert with **"Done"** (not "Move to Trash").

**Method A: GUI (System Settings)**

1. Apple menu → **System Settings** → **Privacy & Security**
2. Scroll down until you see **"Thoth was blocked to protect your Mac"** with an **"Open Anyway"** button, and click it
3. Authenticate with Touch ID or your password
4. If a confirmation dialog appears, choose **"Open"**

**Method B: CLI (Terminal)**

Remove the quarantine attribute from the app. The example assumes it is in `/Applications` (adjust the path to where you placed it).

```sh
xattr -dr com.apple.quarantine /Applications/Thoth.app
```

Then double-click `Thoth.app` to launch it normally. To check whether the attribute is present (nothing printed means it is not):

```sh
xattr -p com.apple.quarantine /Applications/Thoth.app 2>/dev/null
```

> **Note:** These steps are needed only because the app is not notarized. Signing with a Developer ID plus notarization (via the paid Apple Developer Program) would remove the need for them.

---

## 4. Settings

The Preferences window (menu bar icon → "Preferences") lets you adjust:

| Category | Main settings |
|---|---|
| **General** | Launch at login, maximum history size, behavior after pasting, etc. |
| **Menu** | Number of items shown (inline / inside folders), numbering, icon/image/tooltip/color-preview display, maximum title length, etc. |
| **Type** | Which data types (string / RTF / PDF / image / filenames / URL, etc.) are saved to history |
| **Shortcuts** | Hotkey assignments for each menu (main / history / snippet / secure menu) |
| **Original** | Tribute to the original Clipy project, with a link to its repository and the app version |
| **Excluded** | Register apps to exclude from clipboard-history capture |

- **Excluded apps**: register apps whose content you don't want in history (e.g. password managers). Also, copies carrying a concealed marker such as `org.nspasteboard.ConcealedType` (e.g. copies from other password managers) are automatically kept out of history regardless of the exclude list.
- **Secure item Export / Import**: from the **⚙** menu in the Secure Info window, you can export/import secure items and the fingerprint password as a JSON file. This is useful for using the same information across multiple machines (**the exported file is plaintext — handle with care**). The exported file schema is described in [docs/DESIGN.md](docs/DESIGN.md).

---

## License

This app is provided under the MIT license. See the LICENSE file for details. Icons are copyrighted by their respective authors.

The copyright notices of Clipy and ClipMenu, which Thoth is derived from ([LICENSE](LICENSE), [LICENSE_CLIPMENU](LICENSE_CLIPMENU)), and the third-party library licenses are listed in [NOTICE](NOTICE) (also viewable in-app via Preferences > Original > Third-Party Licenses; the distributed `Thoth.app` carries the same list).

All dependencies use permissive licenses compatible with distribution under the MIT License (MIT, ISC, BSD, Apache-2.0, Boost). Moving from CocoaPods to Swift Package Manager in v1.5.1 does not change Thoth's license. Because Realm's database engine (realm-core) is now built from source and bundled, however, the licenses of the third-party code it includes (Intel's decimal floating-point library, JSON for Modern C++, and others) are also listed since v1.6.0.

## Special Thanks

**Thanks to [@naotaka](https://github.com/naotaka) for publishing [ClipMenu](https://github.com/naotaka/ClipMenu) as open source, and to the developers of [Clipy](https://github.com/Clipy/Clipy).**
