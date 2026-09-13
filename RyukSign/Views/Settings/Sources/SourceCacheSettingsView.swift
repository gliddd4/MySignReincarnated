//
//  SourceCacheSettingsView.swift
//  RyukSign
//
//  The repository browser now keeps three things on disk — response bodies +
//  app counts (SourceCache), icon colours (IconTintCache) and resolved icons
//  (RepositoryIconStore). Anything cached has to be inspectable and clearable,
//  otherwise a bad icon or a wrong colour is permanent with no way out. This is
//  that escape hatch, and it doubles as the "refresh" button the tint/icon
//  caches would otherwise lack.
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

struct SourceCacheSettingsView: View {
	@FetchRequest(sortDescriptors: []) private var _sources: FetchedResults<AltSource>

	@ObservedObject private var _cache = SourceCache.shared
	@ObservedObject private var _tints = IconTintCache.shared
	@ObservedObject private var _icons = RepositoryIconStore.shared

	@State private var _iconDiskSize: String = "—"

	var body: some View {
		NBList(.localized("Repository Cache"), displayMode: .inline) {
			NBSection(.localized("Cached Repositories"), secondary: "\(_cache.cachedSourceCount)") {
				_DetailRow(title: .localized("Repositories"), value: "\(_cache.cachedSourceCount)")
				_DetailRow(title: .localized("Apps Counted"), value: "\(_cache.counts.count)")
				_DetailRow(title: .localized("Bodies On Disk"), value: ByteCountFormatter.string(fromByteCount: _cache.sizeOnDisk(), countStyle: .file))
			} footer: {
				Text(.localized("Repository bodies are stored so the browser opens instantly instead of waiting on the network. App counts power the app-count sort and are refreshed on every successful load."))
			}

			NBSection(.localized("Icons & Colours")) {
				_DetailRow(title: .localized("Icons Resolved"), value: "\(_icons.cachedCount)")
				_DetailRow(title: .localized("Icons On Disk"), value: _iconDiskSize)
				_DetailRow(title: .localized("Colours Extracted"), value: "\(_tints.cachedCount)")
			} footer: {
				Text(.localized("A repository with no icon of its own falls back to one of its apps' icons. Colours are pulled from a blurred average of an icon and used to tint the row and its arrow."))
			}

			NBSection(.localized("Maintenance")) {
				Button(.localized("Refresh All Icon Colours"), systemImage: "paintpalette") {
					_refreshAllTints()
				}

				Button(.localized("Refresh All Icons"), systemImage: "photo.on.rectangle.angled") {
					_refreshAllIcons()
				}

				Button(.localized("Clear Icon Cache"), systemImage: "trash") {
					_icons.clear()
					_refreshDiskSizes()
				}

				Button(.localized("Clear Repository Cache"), systemImage: "trash", role: .destructive) {
					// `SourceCache.clear()` also drops the extracted colours and
					// app counts, since none of them mean anything without bodies.
					_cache.clear()
					_refreshDiskSizes()
				}
			} footer: {
				Text(.localized("Clearing the repository cache only costs the next load its head start; nothing about your sources or certificates is touched."))
			}

			NBSection(.localized("Counts")) {
				Button(.localized("Forget App Counts"), systemImage: "number", role: .destructive) {
					_cache.clearCounts()
				}
			} footer: {
				Text(.localized("Until the next refresh, rows show no app count and the app-count sort falls back to name order."))
			}
		}
		.onAppear(perform: _refreshDiskSizes)
	}

	// MARK: - Private

	/// Refreshing a colour needs the icon it is extracted from, so resolve each
	/// source's best candidate the same way the browser row does.
	private func _iconURL(for source: AltSource) -> URL? {
		if let icon = source.iconURL { return icon }
		if let repository = SourcesViewModel.shared.sources[source] {
			return repository.currentIconURL
		}
		return nil
	}

	private func _refreshAllTints() {
		for source in _sources {
			_tints.refreshTint(
				for: SourceFavorites.key(for: source),
				iconURL: _iconURL(for: source)
			)
		}
	}

	private func _refreshAllIcons() {
		for source in _sources {
			var candidates: [URL] = []
			if let icon = source.iconURL { candidates.append(icon) }

			if let repository = SourcesViewModel.shared.sources[source] {
				if let icon = repository.iconURL, !candidates.contains(icon) {
					candidates.append(icon)
				}
				for app in repository.apps.prefix(5) {
					if let icon = app.iconURL, !candidates.contains(icon) {
						candidates.append(icon)
					}
				}
			}

			_icons.refreshIcon(for: SourceFavorites.key(for: source), candidates: candidates)
		}
	}

	private func _refreshDiskSizes() {
		_iconDiskSize = ByteCountFormatter.string(fromByteCount: _icons.sizeOnDisk(), countStyle: .file)
	}
}

// MARK: - Row

private struct _DetailRow: View {
	var title: String
	var value: String

	var body: some View {
		HStack {
			Text(title)
			Spacer(minLength: 8)
			Text(value)
				.foregroundStyle(.secondary)
				.monospacedDigit()
		}
	}
}
