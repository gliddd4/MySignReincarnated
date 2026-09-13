//
//  DefaultTweaksView.swift
//  RyukSign
//
//  "Inject by default" already existed, but only on each tweak's own screen — so
//  answering "which tweaks do I always want?" meant opening every tweak in turn.
//  This is the one place that answers it: every injectable tweak, one toggle
//  each, plus bulk selection.
//
//  A tweak only appears here once it is enabled and has a version installed,
//  because a default that cannot actually inject is just a confusing entry.
//

import SwiftUI
import NimbleViews

struct DefaultTweaksView: View {
	@ObservedObject private var _manager = TweakManager.shared

	@State private var _searchText: String = ""

	private var _selected: [ManagedTweak] {
		_manager.injectableTweaks
			.filter { $0.injectByDefault }
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	private var _emptyMessage: String {
		_manager.tweaks.isEmpty ? .localized("No tweaks installed yet.") : .localized("No tweaks match your search.")
	}

	private var _all: [ManagedTweak] {
		let sorted = _manager.injectableTweaks
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		let query = _searchText.trimmingCharacters(in: .whitespaces)
		guard !query.isEmpty else { return sorted }
		return sorted.filter { $0.name.localizedCaseInsensitiveContains(query) }
	}

	var body: some View {
		NBList(.localized("Default Tweaks"), displayMode: .inline) {
			NBSection(.localized("Injected Into Everything"), secondary: "\(_selected.count)") {
				if _selected.isEmpty {
					Text(.localized("Nothing is set to inject by default yet. Pick the tweaks you always want — a sideload fix, or a patch you rely on for every app you sign."))
						.font(.footnote)
						.foregroundStyle(.secondary)
				} else {
					ForEach(_selected) { tweak in
						_label(tweak)
					}
				}
			} footer: {
				Text(.localized("Anything selected here is injected into every app you sign. A tweak's own screen can still exclude individual bundle IDs from that."))
			}

			NBSection(.localized("All Tweaks"), secondary: "\(_all.count)") {
				if _all.isEmpty {
					Text(verbatim: _emptyMessage)
						.font(.footnote)
						.foregroundStyle(.secondary)
				} else {
					ForEach(_all) { tweak in
						Toggle(isOn: _binding(for: tweak)) {
							_label(tweak)
						}
					}
				}
			} footer: {
				Text(.localized("Only tweaks that are enabled and have a version installed can be injected, so those are the only ones listed."))
			}

			if _manager.injectableTweaks.count > 1 {
				NBSection(.localized("Bulk")) {
					Button(.localized("Select All"), systemImage: "checkmark.circle") {
						_setAll(true)
					}
					Button(.localized("Clear Selection"), systemImage: "xmark.circle", role: .destructive) {
						_setAll(false)
					}
				}
			}
		}
		.searchable(
			text: $_searchText,
			placement: .navigationBarDrawer(displayMode: .always),
			prompt: .localized("Search tweaks")
		)
	}

	// MARK: - Pieces

	/// Reads back through the manager rather than the captured value, so the
	/// toggle stays correct while the library changes underneath it.
	private func _binding(for tweak: ManagedTweak) -> Binding<Bool> {
		Binding(
			get: { _manager.tweak(tweak.id)?.injectByDefault ?? false },
			set: { value in
				_manager.mutate(tweak.id) { $0.injectByDefault = value }
			}
		)
	}

	private func _label(_ tweak: ManagedTweak) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(tweak.name)

			if let notes = tweak.notes, !notes.isEmpty {
				Text(notes)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			} else if !tweak.autoInjectBundleIds.isEmpty {
				Text(verbatim: .localized("%lld bundle ID rule(s)", arguments: tweak.autoInjectBundleIds.count))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func _setAll(_ value: Bool) {
		for tweak in _manager.injectableTweaks where tweak.injectByDefault != value {
			_manager.mutate(tweak.id) { $0.injectByDefault = value }
		}
	}
}
