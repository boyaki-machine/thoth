<div align="center">
  <img src="./Resources/clipy_logo.png" width="400">
</div>

<br>

A clipboard extension app for macOS. This is a personal, feature-extended fork of the original [Clipy](https://github.com/Clipy/Clipy), adding secure item management, password generation, and file encryption.

> 日本語版は [README_JP.md](README_JP.md) を参照してください。

---

## 1. About This App

This project is a fork of **[Clipy](https://github.com/Clipy/Clipy)** (MIT licensed), an open-source clipboard extension app for macOS, extended with additional features.

It keeps the clipboard history and snippet features of the original Clipy, and adds:

- **Secure item management** — paste passwords, TOTP, and other sensitive values directly without leaving them on the clipboard
- **Password generation** — generate random passwords with configurable rules
- **File encryption / decryption** — encrypt files and folders in an openssl-compatible format

### Acknowledgements

Deep thanks to the developers of Clipy for publishing such a great app as open source, and to [@naotaka](https://github.com/naotaka) who published its origin, [ClipMenu](https://github.com/naotaka/ClipMenu). This project stands on the shoulders of these predecessors.

This app is provided under the MIT license. The attribution and original developers' credits are preserved as-is in the source code and commit history.

> For developer information (environment, build steps), see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
> For data formats, cryptographic specifications, and design policy, see [docs/DESIGN.md](docs/DESIGN.md).

---

## 2. Features

### 2-1. Clipboard History & Snippets (from the original Clipy)

Keeps a history of copied content that you can re-paste from a menu. Frequently used boilerplate text can be registered as snippets.

**How to use:**

- Content you copy (⌘C) is automatically accumulated in the history
- Open a menu with a hotkey and select an item to paste it into the frontmost app

| Menu | Default hotkey |
|---|---|
| Main menu (history + snippets + tools) | **⌘⇧V** |
| History menu | **⌘⌃V** |
| Snippet menu | **⌘⇧B** |

- Inside menus you can navigate with arrow keys or vim-style `hjkl` keys
- The maximum history size, display format, excluded apps, etc. can be adjusted in Preferences (see [4. Settings](#4-settings))

### 2-2. Secure Items

Paste passwords, TOTP, and other sensitive values directly into any app **without ever placing them on the clipboard**. Items are stored encrypted in the macOS Keychain and protected by Touch ID / password authentication every time the menu is opened.

| Feature | Detail |
|---|---|
| **Keychain storage** | All values are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — never synced to iCloud |
| **Biometric lock** | Touch ID (or login password) is required before the menu appears. Within 30 seconds of a successful authentication, re-authentication is skipped so you can pick ID / password / TOTP in a row |
| **Two-level menu** | Select a parent item (e.g. "GitHub"), then a specific field (e.g. "Password") |
| **Direct paste** | The selected value is pasted into the frontmost app without touching the clipboard. TOTP is typed as keystrokes directly, leaving no trace in any history |
| **Continue-paste mode** | Re-opening the menu within 30 seconds highlights the previously selected field automatically |
| **TOTP support** | Register from an otpauth URI / QR code; a one-time code is generated and typed at selection time |

**Step 1 — Register your credentials**

Open the menu bar icon → **Manage Secure Items…**, then click **+** to add a new item.

1. Enter a **Title** (e.g. "GitHub", "AWS Console")
2. Click **+** in the field list to add a field
3. Fill in **Label** (e.g. "Password") and **Value**
4. Check 🔒 if the value should be masked
5. To add TOTP, use the **Add TOTP...** button to import an otpauth URI / QR code
6. Click **Save**

**Step 2 — Paste a credential**

1. Click into the input field of the target app
2. Press the hotkey (default: **⌘⇧.**) — a Touch ID / password prompt appears
3. After authentication, the two-level menu opens
4. Select the parent item, then the field to paste

The hotkey can be changed in **Preferences → Shortcuts → Secure Menu**.

**Security characteristics:**

- Values are read from Keychain only at the moment of authentication
- Pasting a regular field temporarily uses the clipboard, but with a marker that keeps it out of history (`org.nspasteboard.ConcealedType`), and it is cleared automatically after pasting
- TOTP never touches the clipboard; it is typed as keystrokes directly

### 2-3. Password Generation

Generates a random password with configurable rules. Randomness comes from the OS CSPRNG (`SecRandomCopyBytes`).

**How to use:**

Choose **Generate New Password** from the main menu (also launchable with the `p` key while the menu is open) to open the generator window.

- **Length**: set with a slider or a numeric field
- **Character types**: any combination of letters / digits / symbols / distinguish upper and lower case
- **Easy-to-type password**: a mode that groups characters by type to reduce keyboard-type switching (e.g. on smartphones)
- **Copy** puts the result on the clipboard (with a concealed marker; auto-cleared after a while)

Password generation can also be invoked from the secure item edit sheet and the fingerprint-password management window.

### 2-4. File Encryption / Decryption

Encrypts and decrypts files and folders with a password. Encryption is done entirely in-process (passwords are never passed to an external command), and uses an **openssl-compatible container format**, so files can be decrypted with only the `openssl` command even on a machine where Clipy is not installed.

**How to use:**

Choose **Encrypt / Decrypt** from the main menu (also launchable with the `e` key while the menu is open) to open the window.

1. Choose a target file / folder with the "Choose..." button
2. Enter a password (you can also recall a registered fixed password via Touch ID using the fingerprint icon)
3. Run **Encrypt** (⌘E) or **Decrypt** (⌘D)
4. After encryption, an example openssl decryption command is shown in the window ("Copy Command" to grab it)

- Encrypted files use the `.enc` extension
- Folders are packed into a tar archive before encryption and unpacked automatically on decryption

#### Decrypting with openssl (recovery without Clipy)

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

**Requirements:** macOS 11.0 or later · Apple Silicon (arm64)

**Outline:**

1. Clone the repository
2. Install dependencies (`bundle exec pod install`)
3. Build (open `Clipy.xcworkspace` in Xcode, or use `xcodebuild` from the CLI)
4. Place the built `Clipy.app` in `/Applications` and launch it

**First-launch notes:**

- On launch, the app re-signs itself with a device-specific certificate and then relaunches (so that secure items remain readable across versions). A macOS confirmation dialog may appear on the first launch only — choose "Always Allow".
- After re-signing, you must grant **Accessibility permission** (required for the paste feature; no need to re-grant on later version updates).
- See "Code Signing and Accessibility Permission" in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for details.

---

## 4. Settings

The Preferences window (menu bar icon → "Preferences") lets you adjust:

| Category | Main settings |
|---|---|
| **General** | Launch at login, maximum history size, behavior after pasting, etc. |
| **Menu** | Number of items shown (inline / inside folders), numbering, icon/image/tooltip/color-preview display, maximum title length, etc. |
| **Type** | Which data types (string / RTF / PDF / image / filenames / URL, etc.) are saved to history |
| **Shortcuts** | Hotkey assignments for each menu (main / history / snippet / secure menu) |
| **Update** | Enable automatic update checks and set the check interval |
| **Excluded** | Register apps to exclude from clipboard-history capture |

- **Excluded apps**: register apps whose content you don't want in history (e.g. password managers). Also, copies carrying a concealed marker such as `org.nspasteboard.ConcealedType` (e.g. copies from other password managers) are automatically kept out of history regardless of the exclude list.
- **Secure item Export / Import**: from the Manage Secure Items window, you can export/import secure items and the fingerprint password as a JSON file. This is useful for using the same information across multiple machines (**the exported file is plaintext — handle with care**). The exported file schema is described in [docs/DESIGN.md](docs/DESIGN.md).

---

## License

This app is provided under the MIT license. See the LICENSE file for details. Icons are copyrighted by their respective authors.

## Special Thanks

**Thanks to [@naotaka](https://github.com/naotaka) for publishing [ClipMenu](https://github.com/naotaka/ClipMenu) as open source, and to the developers of [Clipy](https://github.com/Clipy/Clipy).**
