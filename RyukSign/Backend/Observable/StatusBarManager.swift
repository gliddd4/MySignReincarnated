//
//  StatusBarManager.swift
//  RyukSign
//
//  Ported from MySign (mysignipasigner)'s StatusBarManager.
//
//  Draws the user's clock in place of the system status bar: hiding the system
//  bar gives the app the full top edge, and the themed clock sits in that space.
//  Every value is persisted, and the clock only republishes when the displayed
//  minute actually changes so the overlay isn't invalidating the view tree 60×/s.
//

import SwiftUI
import Combine
import UIKit

@MainActor
final class StatusBarManager: ObservableObject {
	static let shared = StatusBarManager()

	/// Replaces the system status bar with the themed clock.
	@Published var isEnabled: Bool {
		didSet {
			UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
			// The clock only makes sense in the space the system bar gives up.
			if isEnabled && !hidesSystemStatusBar {
				hidesSystemStatusBar = true
			}
		}
	}

	/// Hides the real status bar (`prefersStatusBarHidden`).
	@Published var hidesSystemStatusBar: Bool {
		didSet { UserDefaults.standard.set(hidesSystemStatusBar, forKey: Keys.hideSystem) }
	}

	@Published var uses24HourTime: Bool {
		didSet { UserDefaults.standard.set(uses24HourTime, forKey: Keys.use24) }
	}

	@Published var hidesAMPM: Bool {
		didSet { UserDefaults.standard.set(hidesAMPM, forKey: Keys.hideAMPM) }
	}

	/// Tints the clock with the user's theme colour instead of the label colour.
	@Published var usesThemeColor: Bool {
		didSet { UserDefaults.standard.set(usesThemeColor, forKey: Keys.useThemeColor) }
	}

	@Published private(set) var timeString: String = ""
	@Published private(set) var isLandscape: Bool = false

	private enum Keys {
		static let enabled = "RyukSign.statusBarClock"
		static let hideSystem = "RyukSign.statusBarHideSystem"
		static let use24 = "RyukSign.statusBar24Hour"
		static let hideAMPM = "RyukSign.statusBarHideAMPM"
		static let useThemeColor = "RyukSign.statusBarThemeColor"
	}

	private var _tick: AnyCancellable?
	private var _orientation: AnyCancellable?
	private var _lastMinute: Int = -1

	private init() {
		let defaults = UserDefaults.standard
		// Read into locals first: touching a property wrapper's value on `self`
		// before every stored property is initialised is a compile error.
		let enabled = defaults.bool(forKey: Keys.enabled)
		let hideSystem = defaults.bool(forKey: Keys.hideSystem)

		isEnabled = enabled
		hidesSystemStatusBar = hideSystem || enabled
		uses24HourTime = defaults.bool(forKey: Keys.use24)
		hidesAMPM = defaults.bool(forKey: Keys.hideAMPM)
		usesThemeColor = defaults.bool(forKey: Keys.useThemeColor)

		refreshTime()
		startTicking()
		startWatchingOrientation()
	}

	// MARK: - Public

	/// Whether the clock has a place to draw (enabled, and not in landscape on iPhone).
	var shouldShowClock: Bool {
		guard isEnabled else { return false }
		if UIDevice.current.userInterfaceIdiom == .pad { return true }
		return !isLandscape
	}

	func refreshTime() {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")

		if uses24HourTime {
			formatter.dateFormat = "HH:mm"
		} else {
			formatter.dateFormat = hidesAMPM ? "h:mm" : "h:mm a"
		}

		timeString = formatter.string(from: Date())
	}

	// MARK: - Private

	private func startTicking() {
		_tick = Timer.publish(every: 1, on: .main, in: .common)
			.autoconnect()
			.sink { [weak self] date in
				guard let self else { return }
				// Only touch @Published once a minute — the seconds never render.
				let minute = Calendar.current.component(.minute, from: date)
				guard minute != self._lastMinute else { return }
				self._lastMinute = minute
				self.refreshTime()
			}
	}

	private func startWatchingOrientation() {
		_orientation = NotificationCenter.default
			.publisher(for: UIDevice.orientationDidChangeNotification)
			.compactMap { _ -> UIInterfaceOrientation? in
				guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
				return scene.interfaceOrientation
			}
			.removeDuplicates()
			.sink { [weak self] orientation in
				self?.isLandscape = orientation.isLandscape
			}
	}
}
