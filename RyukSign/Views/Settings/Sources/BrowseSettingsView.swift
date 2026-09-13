//
//  BrowseSettingsView.swift
//  RyukSign
//
//  Ported from MySign's Browse settings tab.
//
//  These control what the repository browser draws, rather than how it looks —
//  the theming switches that sat beside them in MySign are deliberately not
//  carried over.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct BrowseSettingsView: View {
	@AppStorage(BrowsePreferences.hidesAppDescriptions) private var _hidesAppDescriptions = false
	@AppStorage(BrowsePreferences.hidesRepositoryAppCounts) private var _hidesAppCounts = false
	@AppStorage(BrowsePreferences.hidesRepositorySectionCounts) private var _hidesSectionCounts = false
	@AppStorage(BrowsePreferences.disablesTintColorFallback) private var _disablesTintFallback = false
	@AppStorage(BrowsePreferences.disablesIconFallback) private var _disablesIconFallback = false
	@AppStorage(BrowsePreferences.usesFullYearFormat) private var _usesFullYearDates = false

	// MARK: Body
	var body: some View {
		NBList(.localized("Browse"), displayMode: .inline) {
			NBSection(.localized("Rows")) {
				Toggle(.localized("Hide App Descriptions"), isOn: $_hidesAppDescriptions)
				Toggle(.localized("Hide App Counts"), isOn: $_hidesAppCounts)
				Toggle(.localized("Hide Section Counts"), isOn: $_hidesSectionCounts)
			} footer: {
				Text(.localized("App counts sit beside repository names and are what the \"Most Apps\" sort works from; hiding them only hides the number. Descriptions are only ever shown at all when Appearance → Store Cell Appearance is set to Big Description."))
			}

			NBSection(.localized("Fallbacks")) {
				Toggle(.localized("Disable Icon Colour Fallback"), isOn: $_disablesTintFallback)
				Toggle(.localized("Disable App Icon Fallback"), isOn: $_disablesIconFallback)
			} footer: {
				Text(.localized("A repository that declares no icon of its own borrows the first app icon it has, and a repository that declares no colour has one pulled from that icon. Turning these off makes every repository without its own icon look identical again, which is the point of them being here."))
			}

			NBSection(.localized("Dates")) {
				Toggle(.localized("Use Full Year"), isOn: $_usesFullYearDates)
			} footer: {
				Text(.localized("Shows \"1 year ago\" instead of \"1 yr. ago\" next to a release version."))
			}
		}
		.onChange(of: _disablesTintFallback) { _, disabled in
			// A fallback that is switched off should not leave its results behind.
			if disabled {
				IconTintCache.shared.clear()
				FeedbackManager.shared.success()
			}
		}
		.onChange(of: _disablesIconFallback) { _, disabled in
			if disabled {
				RepositoryIconStore.shared.clear()
				FeedbackManager.shared.success()
			}
		}
	}
}
