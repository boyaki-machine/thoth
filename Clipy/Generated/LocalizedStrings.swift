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
  /// Are you sure want to delete this item?
  internal static let areYouSureWantToDeleteThisItem = L10n.tr("Localizable", "Are you sure want to delete this item?")
  /// Are you sure you want to delete this item?
  internal static let areYouSureWantToDeleteThisSecureItem = L10n.tr("Localizable", "Are you sure want to delete this secure item?")
  /// Are you sure you want to clear your clipboard history?
  internal static let areYouSureYouWantToClearYourClipboardHistory = L10n.tr("Localizable", "Are you sure you want to clear your clipboard history?")
  /// Cancel
  internal static let cancel = L10n.tr("Localizable", "Cancel")
  /// Clear History
  internal static let clearHistory = L10n.tr("Localizable", "Clear History")
  /// Close
  internal static let close = L10n.tr("Localizable", "Close")
  /// Delete Item
  internal static let deleteItem = L10n.tr("Localizable", "Delete Item")
  /// Delete Item
  internal static let deleteSecureItem = L10n.tr("Localizable", "Delete Secure Item")
  /// Don't Launch
  internal static let donTLaunch = L10n.tr("Localizable", "Don't Launch")
  /// Edit Item
  internal static let editSecureItem = L10n.tr("Localizable", "Edit Secure Item")
  /// Edit Snippets...
  internal static let editSnippets = L10n.tr("Localizable", "Edit Snippets")
  /// General
  internal static let general = L10n.tr("Localizable", "General")
  /// History
  internal static let history = L10n.tr("Localizable", "History")
  /// Launch Clipy on system startup?
  internal static let launchClipyOnSystemStartup = L10n.tr("Localizable", "Launch Clipy on system startup?")
  /// Launch on system startup
  internal static let launchOnSystemStartup = L10n.tr("Localizable", "Launch on system startup")
  /// Manage Secure Items...
  internal static let manageSecureItems = L10n.tr("Localizable", "Manage Secure Items")
  /// Menu
  internal static let menu = L10n.tr("Localizable", "Menu")
  /// Open System Preferences
  internal static let openSystemPreferences = L10n.tr("Localizable", "Open System Preferences")
  /// Please allow Accessibility.
  internal static let pleaseAllowAccessibility = L10n.tr("Localizable", "Please allow Accessibility")
  /// Please fill in the contents of the snippet
  internal static let pleaseFillInTheContentsOfTheSnippet = L10n.tr("Localizable", "Please fill in the contents of the snippet")
  /// Preferences...
  internal static let preferences = L10n.tr("Localizable", "Preferences")
  /// Quit Clipy
  internal static let quitClipy = L10n.tr("Localizable", "Quit Clipy")
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
  /// Type
  internal static let type = L10n.tr("Localizable", "Type")
  /// Updates
  internal static let updates = L10n.tr("Localizable", "Updates")
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
