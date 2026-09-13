//
//  FeedbackManager.swift
//  RyukSign
//
//  Ported from MySign (mysignipasigner)'s AudioManager + HapticManager.
//
//  One call site for tactile/audio feedback so every interaction in the app
//  sounds and feels the same. Haptics default on; sounds default off, because
//  silent-by-default is the app-store-friendly behaviour users expect.
//

import Foundation
import AudioToolbox
import UIKit
import NimbleExtensions

@MainActor
final class FeedbackManager: ObservableObject {
	static let shared = FeedbackManager()

	@Published var hapticsEnabled: Bool {
		didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Keys.haptics) }
	}

	@Published var soundsEnabled: Bool {
		didSet { UserDefaults.standard.set(soundsEnabled, forKey: Keys.sounds) }
	}

	@Published var soundStyle: SoundStyle {
		didSet { UserDefaults.standard.set(soundStyle.rawValue, forKey: Keys.soundStyle) }
	}

	/// The sound palette. Only the tap sound differs between styles — success and
	/// warning stay constant so they read consistently.
	enum SoundStyle: String, CaseIterable, Codable, Identifiable {
		case classic
		case soft
		case mechanical

		var id: String { rawValue }

		var title: String {
			switch self {
			case .classic:    return .localized("Classic")
			case .soft:       return .localized("Soft")
			case .mechanical: return .localized("Mechanical")
			}
		}

		/// System sound IDs — stable UIKit-provided clicks, no bundled assets needed.
		var tapSound: SystemSoundID {
			switch self {
			case .classic:    return 1104
			case .soft:       return 1103
			case .mechanical: return 1057
			}
		}

		var selectionSound: SystemSoundID {
			switch self {
			case .classic:    return 1103
			case .soft:       return 1151
			case .mechanical: return 1075
			}
		}
	}

	private enum Keys {
		static let haptics = "RyukSign.feedbackHaptics"
		static let sounds = "RyukSign.feedbackSounds"
		static let soundStyle = "RyukSign.feedbackSoundStyle"
	}

	private init() {
		let defaults = UserDefaults.standard

		// `object(forKey:)` so the shipped default (haptics on) survives a user
		// deliberately switching them off.
		hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
		soundsEnabled = defaults.object(forKey: Keys.sounds) as? Bool ?? false
		soundStyle = SoundStyle(rawValue: defaults.string(forKey: Keys.soundStyle) ?? "") ?? .classic
	}

	// MARK: - Feedback

	/// A primary press: install, get, sign.
	func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
		if hapticsEnabled { NBHaptic.tap(style) }
		if soundsEnabled { _play(soundStyle.tapSound) }
	}

	/// A toggle/picker change.
	func selection() {
		if hapticsEnabled { NBHaptic.selection() }
		if soundsEnabled { _play(soundStyle.selectionSound) }
	}

	/// A completed operation.
	func success() {
		if hapticsEnabled { NBHaptic.notify(.success) }
		if soundsEnabled { _play(1057) }
	}

	func warning() {
		if hapticsEnabled { NBHaptic.notify(.warning) }
	}

	func error() {
		if hapticsEnabled { NBHaptic.notify(.error) }
	}

	/// The moment a hold-to-confirm control completes.
	func held() {
		if hapticsEnabled { NBHaptic.tap(.medium) }
		if soundsEnabled { _play(soundStyle.tapSound) }
	}

	/// A short preview used by the settings screen so the choice is audible.
	func previewSound() {
		_play(soundStyle.tapSound)
	}

	// MARK: - Private

	/// Audio is deliberately *not* gated on `soundsEnabled` here — callers decide,
	/// which lets `previewSound()` play from the settings screen.
	private func _play(_ id: SystemSoundID) {
		AudioServicesPlaySystemSound(id)
	}
}
