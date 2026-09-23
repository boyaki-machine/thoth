// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal enum L10n {
  /// Add
  internal static let add = L10n.tr("Localizable", "Add", fallback: "Add")
  /// Add Field
  internal static let addField = L10n.tr("Localizable", "Add Field", fallback: "Add Field")
  /// Add Item
  internal static let addSecureItem = L10n.tr("Localizable", "Add Secure Item", fallback: "Add Item")
  /// Add TOTP...
  internal static let addTOTP = L10n.tr("Localizable", "Add TOTP", fallback: "Add TOTP...")
  /// Are you sure want to delete this item?
  internal static let areYouSureWantToDeleteThisItem = L10n.tr("Localizable", "Are you sure want to delete this item?", fallback: "Are you sure want to delete this item?")
  /// Are you sure you want to delete this item?
  internal static let areYouSureWantToDeleteThisSecureItem = L10n.tr("Localizable", "Are you sure want to delete this secure item?", fallback: "Are you sure you want to delete this item?")
  /// Are you sure you want to clear your clipboard history?
  internal static let areYouSureYouWantToClearYourClipboardHistory = L10n.tr("Localizable", "Are you sure you want to clear your clipboard history?", fallback: "Are you sure you want to clear your clipboard history?")
  /// Language:
  internal static let betaLanguage = L10n.tr("Localizable", "Beta Language", fallback: "Language:")
  /// 𓂀 Hieroglyphs
  internal static let betaLanguageHieroglyphs = L10n.tr("Localizable", "Beta Language Hieroglyphs", fallback: "𓂀 Hieroglyphs")
  /// Lingua Latina (Latin)
  internal static let betaLanguageLatin = L10n.tr("Localizable", "Beta Language Latin", fallback: "Lingua Latina (Latin)")
  /// The language change will take effect after restarting Thoth.
  internal static let betaLanguageRestartMessage = L10n.tr("Localizable", "Beta Language Restart Message", fallback: "The language change will take effect after restarting Thoth.")
  /// Restart Now
  internal static let betaLanguageRestartNow = L10n.tr("Localizable", "Beta Language Restart Now", fallback: "Restart Now")
  /// System Default
  internal static let betaLanguageSystemDefault = L10n.tr("Localizable", "Beta Language System Default", fallback: "System Default")
  /// Looking for a QR code…
  internal static let cameraQRGuide = L10n.tr("Localizable", "Camera QR Guide", fallback: "Looking for a QR code…")
  /// No camera is available on this Mac.
  internal static let cameraQRNoCamera = L10n.tr("Localizable", "Camera QR No Camera", fallback: "No camera is available on this Mac.")
  /// Open System Settings
  internal static let cameraQROpenSettings = L10n.tr("Localizable", "Camera QR Open Settings", fallback: "Open System Settings")
  /// Camera access is denied. Allow Thoth in System Settings > Privacy & Security > Camera.
  internal static let cameraQRPermissionDenied = L10n.tr("Localizable", "Camera QR Permission Denied", fallback: "Camera access is denied. Allow Thoth in System Settings > Privacy & Security > Camera.")
  /// Hold the QR code up to the camera
  internal static let cameraQRTitle = L10n.tr("Localizable", "Camera QR Title", fallback: "Hold the QR code up to the camera")
  /// This QR code is not a Thoth password QR.
  internal static let cameraQRWrongPayload = L10n.tr("Localizable", "Camera QR Wrong Payload", fallback: "This QR code is not a Thoth password QR.")
  /// Cancel
  internal static let cancel = L10n.tr("Localizable", "Cancel", fallback: "Cancel")
  /// Character Types:
  internal static let characterTypes = L10n.tr("Localizable", "Character Types", fallback: "Character Types:")
  /// Clear History
  internal static let clearHistory = L10n.tr("Localizable", "Clear History", fallback: "Clear History")
  /// Close
  internal static let close = L10n.tr("Localizable", "Close", fallback: "Close")
  /// Copied
  internal static let copied = L10n.tr("Localizable", "Copied", fallback: "Copied")
  /// Copy
  internal static let copyPassword = L10n.tr("Localizable", "Copy Password", fallback: "Copy")
  /// Choose...
  internal static let cryptoChoose = L10n.tr("Localizable", "Crypto Choose", fallback: "Choose...")
  /// Copy Command
  internal static let cryptoCopyCommand = L10n.tr("Localizable", "Crypto Copy Command", fallback: "Copy Command")
  /// Decrypt
  internal static let cryptoDecrypt = L10n.tr("Localizable", "Crypto Decrypt", fallback: "Decrypt")
  /// Decrypting...
  internal static let cryptoDecrypting = L10n.tr("Localizable", "Crypto Decrypting", fallback: "Decrypting...")
  /// Done
  internal static let cryptoDone = L10n.tr("Localizable", "Crypto Done", fallback: "Done")
  /// Encrypt
  internal static let cryptoEncrypt = L10n.tr("Localizable", "Crypto Encrypt", fallback: "Encrypt")
  /// Encrypted. It can also be decrypted without Thoth using the openssl command below:
  internal static let cryptoEncryptedWithCommand = L10n.tr("Localizable", "Crypto Encrypted With Command", fallback: "Encrypted. It can also be decrypted without Thoth using the openssl command below:")
  /// Encrypting...
  internal static let cryptoEncrypting = L10n.tr("Localizable", "Crypto Encrypting", fallback: "Encrypting...")
  /// Please enter an output file name.
  internal static let cryptoErrorEmptyOutputName = L10n.tr("Localizable", "Crypto Error Empty Output Name", fallback: "Please enter an output file name.")
  /// Please enter a password.
  internal static let cryptoErrorEmptyPassword = L10n.tr("Localizable", "Crypto Error Empty Password", fallback: "Please enter a password.")
  /// Operation failed. Check the password or file and try again.
  internal static let cryptoErrorFailed = L10n.tr("Localizable", "Crypto Error Failed", fallback: "Operation failed. Check the password or file and try again.")
  /// Please choose a file or folder.
  internal static let cryptoErrorInputNotFound = L10n.tr("Localizable", "Crypto Error Input Not Found", fallback: "Please choose a file or folder.")
  /// A file with the same name already exists.
  internal static let cryptoErrorOutputExists = L10n.tr("Localizable", "Crypto Error Output Exists", fallback: "A file with the same name already exists.")
  /// Use fingerprint password
  internal static let cryptoFingerprint = L10n.tr("Localizable", "Crypto Fingerprint", fallback: "Use fingerprint password")
  /// Fingerprint password applied.
  internal static let cryptoFingerprintApplied = L10n.tr("Localizable", "Crypto Fingerprint Applied", fallback: "Fingerprint password applied.")
  /// Authentication failed.
  internal static let cryptoFingerprintFailed = L10n.tr("Localizable", "Crypto Fingerprint Failed", fallback: "Authentication failed.")
  /// Fingerprint password saved.
  internal static let cryptoFingerprintPasswordSaved = L10n.tr("Localizable", "Crypto Fingerprint Password Saved", fallback: "Fingerprint password saved.")
  /// Authenticate to use the fingerprint password
  internal static let cryptoFingerprintReason = L10n.tr("Localizable", "Crypto Fingerprint Reason", fallback: "Authenticate to use the fingerprint password")
  /// Password:
  internal static let cryptoKey = L10n.tr("Localizable", "Crypto Key", fallback: "Password:")
  /// Encryption password
  internal static let cryptoKeyPlaceholder = L10n.tr("Localizable", "Crypto Key Placeholder", fallback: "Encryption password")
  /// Manage Fingerprint Password...
  internal static let cryptoManageFingerprintPassword = L10n.tr("Localizable", "Crypto Manage Fingerprint Password", fallback: "Manage Fingerprint Password...")
  /// No fingerprint password is registered. Register one from the manager.
  internal static let cryptoNoFingerprintPassword = L10n.tr("Localizable", "Crypto No Fingerprint Password", fallback: "No fingerprint password is registered. Register one from the manager.")
  /// Output name:
  internal static let cryptoOutputName = L10n.tr("Localizable", "Crypto Output Name", fallback: "Output name:")
  /// Scan with your smartphone to carry this password.
  internal static let cryptoQRCaption = L10n.tr("Localizable", "Crypto QR Caption", fallback: "Scan with your smartphone to carry this password.")
  /// Password read from QR. Press Register / Update to save it.
  internal static let cryptoQRScanned = L10n.tr("Localizable", "Crypto QR Scanned", fallback: "Password read from QR. Press Register / Update to save it.")
  /// Read QR Code
  internal static let cryptoReadQRCamera = L10n.tr("Localizable", "Crypto Read QR Camera", fallback: "Read QR Code")
  /// Register / Update
  internal static let cryptoRegisterUpdate = L10n.tr("Localizable", "Crypto Register Update", fallback: "Register / Update")
  /// Target:
  internal static let cryptoTarget = L10n.tr("Localizable", "Crypto Target", fallback: "Target:")
  /// Choose a file or folder
  internal static let cryptoTargetPlaceholder = L10n.tr("Localizable", "Crypto Target Placeholder", fallback: "Choose a file or folder")
  /// Delete Item
  internal static let deleteItem = L10n.tr("Localizable", "Delete Item", fallback: "Delete Item")
  /// Delete Item
  internal static let deleteSecureItem = L10n.tr("Localizable", "Delete Secure Item", fallback: "Delete Item")
  /// Don't Launch
  internal static let donTLaunch = L10n.tr("Localizable", "Don't Launch", fallback: "Don't Launch")
  /// Easy-to-type password
  internal static let easyToTypePassword = L10n.tr("Localizable", "Easy To Type Password", fallback: "Easy-to-type password")
  /// Edit Item
  internal static let editSecureItem = L10n.tr("Localizable", "Edit Secure Item", fallback: "Edit Item")
  /// Edit Snippets...
  internal static let editSnippets = L10n.tr("Localizable", "Edit Snippets", fallback: "Edit Snippets...")
  /// Encrypt / Decrypt File
  internal static let encryptDecrypt = L10n.tr("Localizable", "Encrypt Decrypt", fallback: "Encrypt / Decrypt File")
  /// Export...
  internal static let exportSecureItems = L10n.tr("Localizable", "Export Secure Items", fallback: "Export...")
  /// General
  internal static let general = L10n.tr("Localizable", "General", fallback: "General")
  /// Generate New Password
  internal static let generateNewPassword = L10n.tr("Localizable", "Generate New Password", fallback: "Generate New Password")
  /// Generate
  internal static let generatePassword = L10n.tr("Localizable", "Generate Password", fallback: "Generate")
  /// History
  internal static let history = L10n.tr("Localizable", "History", fallback: "History")
  /// Search...
  internal static let historySearch = L10n.tr("Localizable", "History Search", fallback: "Search...")
  /// Search history...
  internal static let historySearchPlaceholder = L10n.tr("Localizable", "History Search Placeholder", fallback: "Search history...")
  /// Import...
  internal static let importSecureItems = L10n.tr("Localizable", "Import Secure Items", fallback: "Import...")
  /// Imported %d item(s).
  internal static func importedSecureItemsFormat(_ p1: Int) -> String {
    return L10n.tr("Localizable", "Imported Secure Items Format", p1, fallback: "Imported %d item(s).")
  }
  /// Launch on system startup
  internal static let launchOnSystemStartup = L10n.tr("Localizable", "Launch on system startup", fallback: "Launch on system startup")
  /// Launch Thoth on system startup?
  internal static let launchThothOnSystemStartup = L10n.tr("Localizable", "Launch Thoth on system startup?", fallback: "Launch Thoth on system startup?")
  /// Thoth could not read its encryption key, so nothing is written to disk during this session: clipboard history is kept in memory only, and snippets cannot be shown or edited. Your saved data is left untouched. Unlock your login keychain (or allow access when asked) and start Thoth again.
  internal static let libraryUnavailableMessage = L10n.tr("Localizable", "Library Unavailable Message", fallback: "Thoth could not read its encryption key, so nothing is written to disk during this session: clipboard history is kept in memory only, and snippets cannot be shown or edited. Your saved data is left untouched. Unlock your login keychain (or allow access when asked) and start Thoth again.")
  /// Encryption key unavailable
  internal static let libraryUnavailableTitle = L10n.tr("Localizable", "Library Unavailable Title", fallback: "Encryption key unavailable")
  /// Menu
  internal static let menu = L10n.tr("Localizable", "Menu", fallback: "Menu")
  /// New Item
  internal static let newSecureItemTitle = L10n.tr("Localizable", "New Secure Item Title", fallback: "New Item")
  /// No history
  internal static let noValueHistory = L10n.tr("Localizable", "No Value History", fallback: "No history")
  /// Open System Preferences
  internal static let openSystemPreferences = L10n.tr("Localizable", "Open System Preferences", fallback: "Open System Preferences")
  /// Digits (0-9)
  internal static let passwordDigits = L10n.tr("Localizable", "Password Digits", fallback: "Digits (0-9)")
  /// Distinguish upper/lower case
  internal static let passwordDistinguishCase = L10n.tr("Localizable", "Password Distinguish Case", fallback: "Distinguish upper/lower case")
  /// Password Generator
  internal static let passwordGenerator = L10n.tr("Localizable", "Password Generator", fallback: "Password Generator")
  /// Length:
  internal static let passwordLength = L10n.tr("Localizable", "Password Length", fallback: "Length:")
  /// Letters (a-z)
  internal static let passwordLetters = L10n.tr("Localizable", "Password Letters", fallback: "Letters (a-z)")
  /// Symbols
  internal static let passwordSymbols = L10n.tr("Localizable", "Password Symbols", fallback: "Symbols")
  /// Please allow Accessibility.
  internal static let pleaseAllowAccessibility = L10n.tr("Localizable", "Please allow Accessibility", fallback: "Please allow Accessibility.")
  /// Please fill in the contents of the snippet
  internal static let pleaseFillInTheContentsOfTheSnippet = L10n.tr("Localizable", "Please fill in the contents of the snippet", fallback: "Please fill in the contents of the snippet")
  /// Version
  internal static let preferenceVersionTab = L10n.tr("Localizable", "Preference Version Tab", fallback: "Version")
  /// Preferences...
  internal static let preferences = L10n.tr("Localizable", "Preferences", fallback: "Preferences...")
  /// Quit Thoth
  internal static let quitThoth = L10n.tr("Localizable", "Quit Thoth", fallback: "Quit Thoth")
  /// Save
  internal static let save = L10n.tr("Localizable", "Save", fallback: "Save")
  /// Copy History
  internal static let sectionCopyHistory = L10n.tr("Localizable", "Section Copy History", fallback: "Copy History")
  /// Settings
  internal static let sectionSettings = L10n.tr("Localizable", "Section Settings", fallback: "Settings")
  /// Fields
  internal static let secureColumnFields = L10n.tr("Localizable", "Secure Column Fields", fallback: "Fields")
  /// Label
  internal static let secureColumnLabel = L10n.tr("Localizable", "Secure Column Label", fallback: "Label")
  /// Title
  internal static let secureColumnTitle = L10n.tr("Localizable", "Secure Column Title", fallback: "Title")
  /// Value
  internal static let secureColumnValue = L10n.tr("Localizable", "Secure Column Value", fallback: "Value")
  /// Memo
  internal static let secureFieldDefaultLabelNote = L10n.tr("Localizable", "Secure Field Default Label Note", fallback: "Memo")
  /// Password
  internal static let secureFieldDefaultLabelPassword = L10n.tr("Localizable", "Secure Field Default Label Password", fallback: "Password")
  /// Text
  internal static let secureFieldDefaultLabelText = L10n.tr("Localizable", "Secure Field Default Label Text", fallback: "Text")
  /// URL
  internal static let secureFieldDefaultLabelURL = L10n.tr("Localizable", "Secure Field Default Label URL", fallback: "URL")
  /// Label (e.g. ID)
  internal static let secureFieldLabelPlaceholder = L10n.tr("Localizable", "Secure Field Label Placeholder", fallback: "Label (e.g. ID)")
  /// Value
  internal static let secureFieldValuePlaceholder = L10n.tr("Localizable", "Secure Field Value Placeholder", fallback: "Value")
  /// Secure Info
  internal static let secureInfo = L10n.tr("Localizable", "Secure Info", fallback: "Secure Info")
  /// Add Item
  internal static let secureInfoActionAdd = L10n.tr("Localizable", "Secure Info Action Add", fallback: "Add Item")
  /// Delete Item
  internal static let secureInfoActionDelete = L10n.tr("Localizable", "Secure Info Action Delete", fallback: "Delete Item")
  /// Edit
  internal static let secureInfoActionEdit = L10n.tr("Localizable", "Secure Info Action Edit", fallback: "Edit")
  /// Import
  internal static let secureInfoActionImport = L10n.tr("Localizable", "Secure Info Action Import", fallback: "Import")
  /// Reorder
  internal static let secureInfoActionReorder = L10n.tr("Localizable", "Secure Info Action Reorder", fallback: "Reorder")
  /// Actions
  internal static let secureInfoActions = L10n.tr("Localizable", "Secure Info Actions", fallback: "Actions")
  /// Add Field
  internal static let secureInfoAddField = L10n.tr("Localizable", "Secure Info Add Field", fallback: "Add Field")
  /// View secure info
  internal static let secureInfoAuthenticationReason = L10n.tr("Localizable", "Secure Info Authentication Reason", fallback: "View secure info")
  /// Copy
  internal static let secureInfoCopyValue = L10n.tr("Localizable", "Secure Info Copy Value", fallback: "Copy")
  /// Changed in another window.
  internal static let secureInfoExternalChange = L10n.tr("Localizable", "Secure Info External Change", fallback: "Changed in another window.")
  /// Move Down
  internal static let secureInfoMoveDown = L10n.tr("Localizable", "Secure Info Move Down", fallback: "Move Down")
  /// Drag to reorder
  internal static let secureInfoMoveField = L10n.tr("Localizable", "Secure Info Move Field", fallback: "Drag to reorder")
  /// Move Up
  internal static let secureInfoMoveUp = L10n.tr("Localizable", "Secure Info Move Up", fallback: "Move Up")
  /// Select an item to view its details.
  internal static let secureInfoNoSelection = L10n.tr("Localizable", "Secure Info No Selection", fallback: "Select an item to view its details.")
  /// Open in browser
  internal static let secureInfoOpenURL = L10n.tr("Localizable", "Secure Info Open URL", fallback: "Open in browser")
  /// Redo %@
  internal static func secureInfoRedoFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "Secure Info Redo Format", String(describing: p1), fallback: "Redo %@")
  }
  /// Reload
  internal static let secureInfoReload = L10n.tr("Localizable", "Secure Info Reload", fallback: "Reload")
  /// Remove Field
  internal static let secureInfoRemoveField = L10n.tr("Localizable", "Secure Info Remove Field", fallback: "Remove Field")
  /// Are you sure you want to remove this field?
  internal static let secureInfoRemoveFieldConfirmation = L10n.tr("Localizable", "Secure Info Remove Field Confirmation", fallback: "Are you sure you want to remove this field?")
  /// Show / hide the value
  internal static let secureInfoRevealValue = L10n.tr("Localizable", "Secure Info Reveal Value", fallback: "Show / hide the value")
  /// Failed to save to Keychain. Your edits are kept — press Command-S to try again. See Console.app for details (filter: SecureMenuService).
  internal static let secureInfoSaveFailed = L10n.tr("Localizable", "Secure Info Save Failed", fallback: "Failed to save to Keychain. Your edits are kept — press Command-S to try again. See Console.app for details (filter: SecureMenuService).")
  /// Enter a title before saving. Your edits are kept.
  internal static let secureInfoTitleRequired = L10n.tr("Localizable", "Secure Info Title Required", fallback: "Enter a title before saving. Your edits are kept.")
  /// Mask / unmask the value
  internal static let secureInfoToggleMask = L10n.tr("Localizable", "Secure Info Toggle Mask", fallback: "Mask / unmask the value")
  /// Undo %@
  internal static func secureInfoUndoFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "Secure Info Undo Format", String(describing: p1), fallback: "Undo %@")
  }
  /// Title (e.g. Gmail)
  internal static let secureItemTitlePlaceholder = L10n.tr("Localizable", "Secure Item Title Placeholder", fallback: "Title (e.g. Gmail)")
  /// Enter a title before saving.
  internal static let secureItemTitleRequired = L10n.tr("Localizable", "Secure Item Title Required", fallback: "Enter a title before saving.")
  /// Secure Items
  internal static let secureItems = L10n.tr("Localizable", "Secure Items", fallback: "Secure Items")
  /// The exported file will contain all values in plain text. Handle it with care.
  internal static let secureItemsExportWarning = L10n.tr("Localizable", "Secure Items Export Warning", fallback: "The exported file will contain all values in plain text. Handle it with care.")
  /// This file contains a fingerprint password that differs from the one registered on this Mac. Importing replaces it, and files previously encrypted with the current password will no longer open with the stored password. Continue?
  internal static let secureItemsImportOverwritesCryptoPassword = L10n.tr("Localizable", "Secure Items Import Overwrites Crypto Password", fallback: "This file contains a fingerprint password that differs from the one registered on this Mac. Importing replaces it, and files previously encrypted with the current password will no longer open with the stored password. Continue?")
  /// Failed to read secure items from Keychain. This can happen when the app binary has changed (e.g. after an update or rebuild). If macOS shows a keychain permission dialog, choose "Always Allow". Saving is disabled to protect the existing data.
  internal static let secureItemsKeychainAccessDenied = L10n.tr("Localizable", "Secure Items Keychain Access Denied", fallback: "Failed to read secure items from Keychain. This can happen when the app binary has changed (e.g. after an update or rebuild). If macOS shows a keychain permission dialog, choose \"Always Allow\". Saving is disabled to protect the existing data.")
  /// Failed to save to Keychain. See Console.app for details (filter: SecureMenuService).
  internal static let secureItemsSaveFailed = L10n.tr("Localizable", "Secure Items Save Failed", fallback: "Failed to save to Keychain. See Console.app for details (filter: SecureMenuService).")
  /// Secure Menu
  internal static let secureMenu = L10n.tr("Localizable", "Secure Menu", fallback: "Secure Menu")
  /// Access Secure Menu
  internal static let secureMenuAuthenticationReason = L10n.tr("Localizable", "Secure Menu Authentication Reason", fallback: "Access Secure Menu")
  /// No matching items
  internal static let secureMenuNoResults = L10n.tr("Localizable", "Secure Menu No Results", fallback: "No matching items")
  /// Search...
  internal static let secureMenuSearchPlaceholder = L10n.tr("Localizable", "Secure Menu Search Placeholder", fallback: "Search...")
  /// Shortcuts
  internal static let shortcuts = L10n.tr("Localizable", "Shortcuts", fallback: "Shortcuts")
  /// Show Snippet Menu
  internal static let showSnippetMenu = L10n.tr("Localizable", "Show Snippet Menu", fallback: "Show Snippet Menu")
  /// Snippet
  internal static let snippet = L10n.tr("Localizable", "Snippet", fallback: "Snippet")
  /// Snippets are unavailable
  internal static let snippetsUnavailable = L10n.tr("Localizable", "Snippets Unavailable", fallback: "Snippets are unavailable")
  /// Thoth could not read its encryption key, so snippets cannot be shown or edited during this session. Nothing has been deleted. Unlock your login keychain (or allow access when asked) and start Thoth again.
  internal static let snippetsUnavailableMessage = L10n.tr("Localizable", "Snippets Unavailable Message", fallback: "Thoth could not read its encryption key, so snippets cannot be shown or edited during this session. Nothing has been deleted. Unlock your login keychain (or allow access when asked) and start Thoth again.")
  /// Third Party Licenses
  internal static let thirdPartyLicenses = L10n.tr("Localizable", "Third Party Licenses", fallback: "Third Party Licenses")
  /// Failed to load the third-party licenses list.
  internal static let thirdPartyLicensesLoadFailed = L10n.tr("Localizable", "Third Party Licenses Load Failed", fallback: "Failed to load the third-party licenses list.")
  /// To do this action please allow Accessibility in Security & Privacy preferences, located in System Preferences.
  internal static let toDoThisActionPleaseAllowAccessibilityInSecurityPrivacyPreferencesLocatedInSystemPreferences = L10n.tr("Localizable", "To do this action please allow Accessibility in Security Privacy preferences located in System Preferences", fallback: "To do this action please allow Accessibility in Security & Privacy preferences, located in System Preferences.")
  /// Tools
  internal static let tools = L10n.tr("Localizable", "Tools", fallback: "Tools")
  /// One-Time Password (TOTP)
  internal static let totpDefaultFieldLabel = L10n.tr("Localizable", "TOTP Default Field Label", fallback: "One-Time Password (TOTP)")
  /// From Clipboard
  internal static let totpFromClipboard = L10n.tr("Localizable", "TOTP From Clipboard", fallback: "From Clipboard")
  /// Enter an otpauth:// URI or a secret, or read one from the clipboard or a QR code on screen.
  internal static let totpImportDescription = L10n.tr("Localizable", "TOTP Import Description", fallback: "Enter an otpauth:// URI or a secret, or read one from the clipboard or a QR code on screen.")
  /// otpauth://totp/... or Base32 secret
  internal static let totpImportPlaceholder = L10n.tr("Localizable", "TOTP Import Placeholder", fallback: "otpauth://totp/... or Base32 secret")
  /// Add One-Time Password (TOTP)
  internal static let totpImportTitle = L10n.tr("Localizable", "TOTP Import Title", fallback: "Add One-Time Password (TOTP)")
  /// Imported from the clipboard.
  internal static let totpImportedFromClipboard = L10n.tr("Localizable", "TOTP Imported From Clipboard", fallback: "Imported from the clipboard.")
  /// Enter a valid otpauth:// URI or secret.
  internal static let totpInvalidInput = L10n.tr("Localizable", "TOTP Invalid Input", fallback: "Enter a valid otpauth:// URI or secret.")
  /// No valid TOTP / QR code found in the clipboard.
  internal static let totpNotFoundInClipboard = L10n.tr("Localizable", "TOTP Not Found In Clipboard", fallback: "No valid TOTP / QR code found in the clipboard.")
  /// Could not read a QR code.
  internal static let totpReadQRFailed = L10n.tr("Localizable", "TOTP Read QR Failed", fallback: "Could not read a QR code.")
  /// Read QR on Screen
  internal static let totpReadQROnScreen = L10n.tr("Localizable", "TOTP Read QR On Screen", fallback: "Read QR on Screen")
  /// QR code has been read.
  internal static let totpReadQRSuccess = L10n.tr("Localizable", "TOTP Read QR Success", fallback: "QR code has been read.")
  /// Registered %@
  internal static func totpRegisteredAtFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "TOTP Registered At Format", String(describing: p1), fallback: "Registered %@")
  }
  /// Type
  internal static let type = L10n.tr("Localizable", "Type", fallback: "Type")
  /// Updates
  internal static let updates = L10n.tr("Localizable", "Updates", fallback: "Updates")
  /// Link to the original Clipy repository
  internal static let updatesOriginalRepositoryLink = L10n.tr("Localizable", "Updates Original Repository Link", fallback: "Link to the original Clipy repository")
  /// This application is a fork of Clipy, the open-source clipboard extension for macOS. Deep respect and gratitude go to the developers of the original Clipy, and to naotaka, the author of its predecessor ClipMenu. This project stands on their great work.
  internal static let updatesRespectMessage = L10n.tr("Localizable", "Updates Respect Message", fallback: "This application is a fork of Clipy, the open-source clipboard extension for macOS. Deep respect and gratitude go to the developers of the original Clipy, and to naotaka, the author of its predecessor ClipMenu. This project stands on their great work.")
  /// Third-Party Licenses
  internal static let updatesThirdPartyLicensesButton = L10n.tr("Localizable", "Updates Third Party Licenses Button", fallback: "Third-Party Licenses")
  /// Value history
  internal static let valueHistory = L10n.tr("Localizable", "Value History", fallback: "Value history")
  /// Release date: %@
  internal static func versionReleaseDate(_ p1: Any) -> String {
    return L10n.tr("Localizable", "Version Release Date", String(describing: p1), fallback: "Release date: %@")
  }
  /// You can change this setting in the Preferences if you want.
  internal static let youCanChangeThisSettingInThePreferencesIfYouWant = L10n.tr("Localizable", "You can change this setting in the Preferences if you want", fallback: "You can change this setting in the Preferences if you want.")
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension L10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg..., fallback value: String) -> String {
    let format = BundleToken.bundle.localizedString(forKey: key, value: value, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle(for: BundleToken.self)
    #endif
  }()
}
// swiftlint:enable convenience_type
