// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal enum L10n {
  /// Add
  internal static let add = L10n.tr("Localizable", "Add")
  /// Add Field
  internal static let addField = L10n.tr("Localizable", "Add Field")
  /// Add Item
  internal static let addSecureItem = L10n.tr("Localizable", "Add Secure Item")
  /// Add TOTP...
  internal static let addTOTP = L10n.tr("Localizable", "Add TOTP")
  /// Are you sure want to delete this item?
  internal static let areYouSureWantToDeleteThisItem = L10n.tr("Localizable", "Are you sure want to delete this item?")
  /// Are you sure you want to delete this item?
  internal static let areYouSureWantToDeleteThisSecureItem = L10n.tr("Localizable", "Are you sure want to delete this secure item?")
  /// Are you sure you want to clear your clipboard history?
  internal static let areYouSureYouWantToClearYourClipboardHistory = L10n.tr("Localizable", "Are you sure you want to clear your clipboard history?")
  /// Cancel
  internal static let cancel = L10n.tr("Localizable", "Cancel")
  /// Character Types:
  internal static let characterTypes = L10n.tr("Localizable", "Character Types")
  /// Clear History
  internal static let clearHistory = L10n.tr("Localizable", "Clear History")
  /// Close
  internal static let close = L10n.tr("Localizable", "Close")
  /// Copied
  internal static let copied = L10n.tr("Localizable", "Copied")
  /// Copy
  internal static let copyPassword = L10n.tr("Localizable", "Copy Password")
  /// Choose...
  internal static let cryptoChoose = L10n.tr("Localizable", "Crypto Choose")
  /// Copy Command
  internal static let cryptoCopyCommand = L10n.tr("Localizable", "Crypto Copy Command")
  /// Decrypt
  internal static let cryptoDecrypt = L10n.tr("Localizable", "Crypto Decrypt")
  /// Decrypting...
  internal static let cryptoDecrypting = L10n.tr("Localizable", "Crypto Decrypting")
  /// Done
  internal static let cryptoDone = L10n.tr("Localizable", "Crypto Done")
  /// Encrypt
  internal static let cryptoEncrypt = L10n.tr("Localizable", "Crypto Encrypt")
  /// Encrypted. It can also be decrypted without Clipy using the openssl command below:
  internal static let cryptoEncryptedWithCommand = L10n.tr("Localizable", "Crypto Encrypted With Command")
  /// Encrypting...
  internal static let cryptoEncrypting = L10n.tr("Localizable", "Crypto Encrypting")
  /// Please enter an output file name.
  internal static let cryptoErrorEmptyOutputName = L10n.tr("Localizable", "Crypto Error Empty Output Name")
  /// Please enter a password.
  internal static let cryptoErrorEmptyPassword = L10n.tr("Localizable", "Crypto Error Empty Password")
  /// Operation failed. Check the password or file and try again.
  internal static let cryptoErrorFailed = L10n.tr("Localizable", "Crypto Error Failed")
  /// Please choose a file or folder.
  internal static let cryptoErrorInputNotFound = L10n.tr("Localizable", "Crypto Error Input Not Found")
  /// A file with the same name already exists.
  internal static let cryptoErrorOutputExists = L10n.tr("Localizable", "Crypto Error Output Exists")
  /// Use fingerprint password
  internal static let cryptoFingerprint = L10n.tr("Localizable", "Crypto Fingerprint")
  /// Fingerprint password applied.
  internal static let cryptoFingerprintApplied = L10n.tr("Localizable", "Crypto Fingerprint Applied")
  /// Authentication failed.
  internal static let cryptoFingerprintFailed = L10n.tr("Localizable", "Crypto Fingerprint Failed")
  /// Fingerprint password saved.
  internal static let cryptoFingerprintPasswordSaved = L10n.tr("Localizable", "Crypto Fingerprint Password Saved")
  /// Authenticate to use the fingerprint password
  internal static let cryptoFingerprintReason = L10n.tr("Localizable", "Crypto Fingerprint Reason")
  /// Password:
  internal static let cryptoKey = L10n.tr("Localizable", "Crypto Key")
  /// Encryption password
  internal static let cryptoKeyPlaceholder = L10n.tr("Localizable", "Crypto Key Placeholder")
  /// Manage Fingerprint Password...
  internal static let cryptoManageFingerprintPassword = L10n.tr("Localizable", "Crypto Manage Fingerprint Password")
  /// No fingerprint password is registered. Register one from the manager.
  internal static let cryptoNoFingerprintPassword = L10n.tr("Localizable", "Crypto No Fingerprint Password")
  /// Output name:
  internal static let cryptoOutputName = L10n.tr("Localizable", "Crypto Output Name")
  /// Register / Update
  internal static let cryptoRegisterUpdate = L10n.tr("Localizable", "Crypto Register Update")
  /// Target:
  internal static let cryptoTarget = L10n.tr("Localizable", "Crypto Target")
  /// Choose a file or folder
  internal static let cryptoTargetPlaceholder = L10n.tr("Localizable", "Crypto Target Placeholder")
  /// Delete Item
  internal static let deleteItem = L10n.tr("Localizable", "Delete Item")
  /// Delete Item
  internal static let deleteSecureItem = L10n.tr("Localizable", "Delete Secure Item")
  /// Don't Launch
  internal static let donTLaunch = L10n.tr("Localizable", "Don't Launch")
  /// Easy-to-type password
  internal static let easyToTypePassword = L10n.tr("Localizable", "Easy To Type Password")
  /// Edit Item
  internal static let editSecureItem = L10n.tr("Localizable", "Edit Secure Item")
  /// Edit Snippets...
  internal static let editSnippets = L10n.tr("Localizable", "Edit Snippets")
  /// Encrypt / Decrypt File
  internal static let encryptDecrypt = L10n.tr("Localizable", "Encrypt Decrypt")
  /// Export...
  internal static let exportSecureItems = L10n.tr("Localizable", "Export Secure Items")
  /// General
  internal static let general = L10n.tr("Localizable", "General")
  /// Generate New Password
  internal static let generateNewPassword = L10n.tr("Localizable", "Generate New Password")
  /// Generate
  internal static let generatePassword = L10n.tr("Localizable", "Generate Password")
  /// History
  internal static let history = L10n.tr("Localizable", "History")
  /// Import...
  internal static let importSecureItems = L10n.tr("Localizable", "Import Secure Items")
  /// Imported %d item(s).
  internal static func importedSecureItemsFormat(_ p1: Int) -> String {
    return L10n.tr("Localizable", "Imported Secure Items Format", p1)
  }
  /// Launch Clipy on system startup?
  internal static let launchClipyOnSystemStartup = L10n.tr("Localizable", "Launch Clipy on system startup?")
  /// Launch on system startup
  internal static let launchOnSystemStartup = L10n.tr("Localizable", "Launch on system startup")
  /// Manage Secure Items...
  internal static let manageSecureItems = L10n.tr("Localizable", "Manage Secure Items")
  /// Menu
  internal static let menu = L10n.tr("Localizable", "Menu")
  /// No history
  internal static let noValueHistory = L10n.tr("Localizable", "No Value History")
  /// Open System Preferences
  internal static let openSystemPreferences = L10n.tr("Localizable", "Open System Preferences")
  /// Digits (0-9)
  internal static let passwordDigits = L10n.tr("Localizable", "Password Digits")
  /// Distinguish upper/lower case
  internal static let passwordDistinguishCase = L10n.tr("Localizable", "Password Distinguish Case")
  /// Password Generator
  internal static let passwordGenerator = L10n.tr("Localizable", "Password Generator")
  /// Length:
  internal static let passwordLength = L10n.tr("Localizable", "Password Length")
  /// Letters (a-z)
  internal static let passwordLetters = L10n.tr("Localizable", "Password Letters")
  /// Symbols
  internal static let passwordSymbols = L10n.tr("Localizable", "Password Symbols")
  /// Please allow Accessibility.
  internal static let pleaseAllowAccessibility = L10n.tr("Localizable", "Please allow Accessibility")
  /// Please fill in the contents of the snippet
  internal static let pleaseFillInTheContentsOfTheSnippet = L10n.tr("Localizable", "Please fill in the contents of the snippet")
  /// Preferences...
  internal static let preferences = L10n.tr("Localizable", "Preferences")
  /// Quit Clipy
  internal static let quitClipy = L10n.tr("Localizable", "Quit Clipy")
  /// The clipboard history database could not be opened. The encryption key may be missing or the file may be corrupted. You can quit and retry, or reset the database (this deletes all history and snippets).
  internal static let realmOpenFailedMessage = L10n.tr("Localizable", "Realm Open Failed Message")
  /// Quit
  internal static let realmOpenFailedQuit = L10n.tr("Localizable", "Realm Open Failed Quit")
  /// Reset Database
  internal static let realmOpenFailedReset = L10n.tr("Localizable", "Realm Open Failed Reset")
  /// Failed to open the history database
  internal static let realmOpenFailedTitle = L10n.tr("Localizable", "Realm Open Failed Title")
  /// Save
  internal static let save = L10n.tr("Localizable", "Save")
  /// Label (e.g. ID)
  internal static let secureFieldLabelPlaceholder = L10n.tr("Localizable", "Secure Field Label Placeholder")
  /// Value
  internal static let secureFieldValuePlaceholder = L10n.tr("Localizable", "Secure Field Value Placeholder")
  /// Title (e.g. Gmail)
  internal static let secureItemTitlePlaceholder = L10n.tr("Localizable", "Secure Item Title Placeholder")
  /// Secure Items
  internal static let secureItems = L10n.tr("Localizable", "Secure Items")
  /// The exported file will contain all values in plain text. Handle it with care.
  internal static let secureItemsExportWarning = L10n.tr("Localizable", "Secure Items Export Warning")
  /// Failed to read secure items from Keychain. This can happen when the app binary has changed (e.g. after an update or rebuild). If macOS shows a keychain permission dialog, choose "Always Allow". Saving is disabled to protect the existing data.
  internal static let secureItemsKeychainAccessDenied = L10n.tr("Localizable", "Secure Items Keychain Access Denied")
  /// Secure Menu
  internal static let secureMenu = L10n.tr("Localizable", "Secure Menu")
  /// Access Secure Menu
  internal static let secureMenuAuthenticationReason = L10n.tr("Localizable", "Secure Menu Authentication Reason")
  /// No matching items
  internal static let secureMenuNoResults = L10n.tr("Localizable", "Secure Menu No Results")
  /// Search...
  internal static let secureMenuSearchPlaceholder = L10n.tr("Localizable", "Secure Menu Search Placeholder")
  /// Shortcuts
  internal static let shortcuts = L10n.tr("Localizable", "Shortcuts")
  /// Snippet
  internal static let snippet = L10n.tr("Localizable", "Snippet")
  /// To do this action please allow Accessibility in Security & Privacy preferences, located in System Preferences.
  internal static let toDoThisActionPleaseAllowAccessibilityInSecurityPrivacyPreferencesLocatedInSystemPreferences = L10n.tr("Localizable", "To do this action please allow Accessibility in Security Privacy preferences located in System Preferences")
  /// Tools
  internal static let tools = L10n.tr("Localizable", "Tools")
  /// Type
  internal static let type = L10n.tr("Localizable", "Type")
  /// Updates
  internal static let updates = L10n.tr("Localizable", "Updates")
  /// Value history
  internal static let valueHistory = L10n.tr("Localizable", "Value History")
  /// You can change this setting in the Preferences if you want.
  internal static let youCanChangeThisSettingInThePreferencesIfYouWant = L10n.tr("Localizable", "You can change this setting in the Preferences if you want")
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension L10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg...) -> String {
    let format = BundleToken.bundle.localizedString(forKey: key, value: nil, table: table)
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
