//
//  BrowsePreferences.swift
//  RyukSign
//
//  Ported from MySign's Browse settings tab.
//
//  Every switch the repository browser honours. They live together so the
//  settings screen and the rows cannot drift apart on a key name, and so the
//  icon and colour caches can read the same values the toggles write.
//

import Foundation

enum BrowsePreferences {
	/// Hides the description under an app's icon inside a repository.
	static let hidesAppDescriptions = "RyukSign.browseHideAppDescriptions"

	/// Hides the app count beside a repository's name.
	static let hidesRepositoryAppCounts = "RyukSign.browseHideAppCounts"

	/// Hides the counts next to the Favourites and Repositories section titles.
	static let hidesRepositorySectionCounts = "RyukSign.browseHideSectionCounts"

	/// Stops generating a colour for repositories that do not declare one.
	static let disablesTintColorFallback = "RyukSign.browseDisableTintFallback"

	/// Stops borrowing an app's icon when a repository does not declare its own.
	static let disablesIconFallback = "RyukSign.browseDisableIconFallback"

	/// "1 year ago" rather than "1 yr. ago" in release dates.
	static let usesFullYearFormat = "RyukSign.browseFullYearDates"

	static func isEnabled(_ key: String) -> Bool {
		UserDefaults.standard.bool(forKey: key)
	}
}
