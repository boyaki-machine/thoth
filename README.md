<div align="center">
  <img src="./Resources/clipy_logo.png" width="400">
</div>

<br>

![CI](https://github.com/Clipy/Clipy/workflows/CI/badge.svg)
[![Release version](https://img.shields.io/github/release/Clipy/Clipy.svg)](https://github.com/Clipy/Clipy/releases/latest)
[![OpenCollective](https://opencollective.com/clipy/backers/badge.svg)](#backers)
[![OpenCollective](https://opencollective.com/clipy/sponsors/badge.svg)](#sponsors)

Clipy is a Clipboard extension app for macOS.

---

__Requirement__: macOS 10.13 High Sierra or later · Apple Silicon (arm64)

__Distribution Site__ : <https://clipy-app.com>

<img src="http://clipy-app.com/img/screenshot1.png" width="400">

### Secure Menu — Credential Paste without Exposing to Clipboard

Secure Menu lets you paste passwords and other sensitive values directly into any app **without ever placing them on the clipboard**. Items are stored encrypted in the **macOS Keychain** and protected by **Touch ID / password authentication** every time the menu is opened.

#### Features

| Feature | Detail |
|---------|--------|
| **Keychain storage** | All values are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — never synced to iCloud |
| **Biometric lock** | Touch ID (or login password) is required before the menu appears |
| **Two-level menu** | Select a parent item (e.g. "GitHub"), then choose a specific field (e.g. "Password") |
| **Direct paste** | The selected value is pasted into the frontmost app without touching the clipboard |
| **Continue-paste mode** | Re-opening the menu within 30 seconds highlights the previously selected field automatically |
| **Keyboard navigation** | Arrow keys and vim-style `hjkl` keys work inside the menu |

#### How to use

**Step 1 — Register your credentials**

Open the menu bar icon → **Manage Secure Items…**, or go to **Preferences → Shortcuts** and use the shortcut shown there.

In the management window, click **+** to add a new item:

1. Enter a **Title** (e.g. "GitHub", "AWS Console")
2. Click **+** in the field list to add a field
3. Fill in **Label** (e.g. "Password") and **Value**
4. Check 🔒 if the value should be masked
5. Click **Save**

**Step 2 — Paste a credential**

1. Click into the password field of the target app
2. Press the hotkey (default: **⌘⇧-**) — Touch ID / password prompt appears
3. After authentication, the two-level menu opens
4. Select the parent item, then select the field to paste

The hotkey can be changed in **Preferences → Shortcuts → Secure Menu**.

#### Security notes

- Values are read from Keychain only at the moment of authentication and are never written to the clipboard
- The Keychain item is tagged `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so it is not accessible on a locked screen and is not backed up to iCloud

---

### Development Environment
* macOS 10.15 Catalina
* Xcode 12.2
* Swift 5.3

### How to Build
0. Move to the project root directory
1. `bundle install --path=vendor/bundle && bundle exec pod install`
2. Open `Clipy.xcworkspace` on Xcode.
3. build.

### How to Run Tests

#### Run all tests (Debug mode)
```bash
SKIP_SWIFTLINT=1 xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug test -destination 'platform=macOS,arch=arm64' ENABLE_TESTABILITY=YES
```

#### Run specific test suite
```bash
SKIP_SWIFTLINT=1 xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug test -destination 'platform=macOS,arch=arm64' ENABLE_TESTABILITY=YES 2>&1 | grep -E "TestSuite.*passed|failed"
```

#### View test results summary
```bash
SKIP_SWIFTLINT=1 xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug test -destination 'platform=macOS,arch=arm64' ENABLE_TESTABILITY=YES 2>&1 | tail -5
```

#### Test Coverage
- **Total Tests**: 114
- **Test Suites**: 15
  - CryptoServiceSpec
  - DraggedDataSpec
  - FolderSpec
  - HotKeyServiceSpec
  - PasswordGenerateServiceSpec
  - PasteServiceTOTPSpec *(TOTP operations)*
  - SecureItemEditSpec
  - SecureItemEditTabNavigationSpec *(Tab navigation logic)*
  - SecureItemFieldReorderingSpec *(Drag & Drop logic)*
  - SecureMenuItemFieldSpec *(Field CRUD)*
  - SecureMenuItemSpec
  - SecureMenuServiceSpec *(Keychain operations & TOTP)*
  - SnippetSpec
  - TOTPRegistrationFlowSpec *(TOTP registration flow)*
  - TOTPServiceSpec *(RFC 6238 TOTP generation)*

#### Key Test Areas
- **Field Management**: CRUD operations, JSON serialization, history tracking
- **TOTP Support**: RFC 6238 compliance, URI parsing, Base32 decoding, code generation
- **Drag & Drop**: Row reordering logic with `.above` dropOperation semantics
- **Tab Navigation**: Focus order, TOTP field skipping, circular navigation
- **Keychain Storage**: Encryption/decryption, field persistence, access control
- **Security**: Biometric authentication, credential masking, clipboard bypass

### Contributing
1. Fork it ( https://github.com/Clipy/Clipy/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

### Localization Contributors
Clipy is looking for localization contributors.  
If you can contribute, please see [CONTRIBUTING.md](https://github.com/Clipy/Clipy/blob/master/.github/CONTRIBUTING.md)

### Distribution
If you distribute derived work, especially in the Mac App Store, I ask you to follow two rules:

1. Don't use `Clipy` and `ClipMenu` as your product name.
2. Follow the MIT license terms.

Thank you for your cooperation.

### Backers

Support us with a monthly donation and help us continue our activities. [[Become a backer](https://opencollective.com/clipy#backer)]

<a href="https://opencollective.com/clipy/backer/0/website" target="_blank"><img src="https://opencollective.com/clipy/backer/0/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/1/website" target="_blank"><img src="https://opencollective.com/clipy/backer/1/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/2/website" target="_blank"><img src="https://opencollective.com/clipy/backer/2/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/3/website" target="_blank"><img src="https://opencollective.com/clipy/backer/3/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/4/website" target="_blank"><img src="https://opencollective.com/clipy/backer/4/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/5/website" target="_blank"><img src="https://opencollective.com/clipy/backer/5/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/6/website" target="_blank"><img src="https://opencollective.com/clipy/backer/6/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/7/website" target="_blank"><img src="https://opencollective.com/clipy/backer/7/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/8/website" target="_blank"><img src="https://opencollective.com/clipy/backer/8/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/9/website" target="_blank"><img src="https://opencollective.com/clipy/backer/9/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/10/website" target="_blank"><img src="https://opencollective.com/clipy/backer/10/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/11/website" target="_blank"><img src="https://opencollective.com/clipy/backer/11/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/12/website" target="_blank"><img src="https://opencollective.com/clipy/backer/12/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/13/website" target="_blank"><img src="https://opencollective.com/clipy/backer/13/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/14/website" target="_blank"><img src="https://opencollective.com/clipy/backer/14/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/15/website" target="_blank"><img src="https://opencollective.com/clipy/backer/15/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/16/website" target="_blank"><img src="https://opencollective.com/clipy/backer/16/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/17/website" target="_blank"><img src="https://opencollective.com/clipy/backer/17/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/18/website" target="_blank"><img src="https://opencollective.com/clipy/backer/18/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/19/website" target="_blank"><img src="https://opencollective.com/clipy/backer/19/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/20/website" target="_blank"><img src="https://opencollective.com/clipy/backer/20/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/21/website" target="_blank"><img src="https://opencollective.com/clipy/backer/21/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/22/website" target="_blank"><img src="https://opencollective.com/clipy/backer/22/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/23/website" target="_blank"><img src="https://opencollective.com/clipy/backer/23/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/24/website" target="_blank"><img src="https://opencollective.com/clipy/backer/24/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/25/website" target="_blank"><img src="https://opencollective.com/clipy/backer/25/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/26/website" target="_blank"><img src="https://opencollective.com/clipy/backer/26/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/27/website" target="_blank"><img src="https://opencollective.com/clipy/backer/27/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/28/website" target="_blank"><img src="https://opencollective.com/clipy/backer/28/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/29/website" target="_blank"><img src="https://opencollective.com/clipy/backer/29/avatar.svg"></a>

### Sponsors

Become a sponsor and get your logo on our README on Github with a link to your site. [[Become a sponsor](https://opencollective.com/clipy#sponsor)]

<a href="https://opencollective.com/clipy/sponsor/0/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/0/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/1/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/1/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/2/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/2/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/3/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/3/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/4/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/4/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/5/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/5/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/6/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/6/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/7/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/7/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/8/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/8/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/9/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/9/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/10/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/10/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/11/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/11/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/12/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/12/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/13/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/13/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/14/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/14/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/15/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/15/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/16/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/16/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/17/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/17/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/18/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/18/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/19/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/19/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/20/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/20/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/21/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/21/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/22/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/22/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/23/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/23/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/24/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/24/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/25/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/25/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/26/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/26/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/27/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/27/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/28/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/28/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/29/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/29/avatar.svg"></a>

### Licence
Clipy is available under the MIT license. See the LICENSE file for more info.

Icons are copyrighted by their respective authors.

### Special Thanks
__Thank you for [@naotaka](https://github.com/naotaka) who have published [ClipMenu](https://github.com/naotaka/ClipMenu) as OSS.__
