//
//  SourcesCellView.swift
//  RyukSign
//
//  Created by samara on 1.05.2025.
//
//  Reworked for the MySign merge:
//   • the repository URL is gone from the row — it ate the width that used to
//     make only ~20 repositories visible, and the name already identifies it
//   • the subtitle shows what is actually useful: how many apps it carries and
//     when it was last refreshed (cached on disk by SourceCache)
//   • a colour pulled from the repository's own icon tints the row
//   • favourites, cached JSON, debug info and a tint refresh in the context menu
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews
import NimbleExtensions

// MARK: - View
struct SourcesCellView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.dismiss) private var dismiss

	var source: AltSource
	var isEditMode: Bool = false

	@ObservedObject private var _cache = SourceCache.shared
	@ObservedObject private var _tints = IconTintCache.shared
	@ObservedObject private var _favorites = SourceFavorites.shared

	@State private var _isExcluded: Bool = false
	@State private var _isShowingJSON = false
	@State private var _isShowingDebug = false

	/// Stable key for favourites/tints: identifier, falling back to the URL.
	private var _key: String {
		SourceFavorites.key(for: source)
	}

	private var _sourceIdentifier: String {
		source.identifier ?? source.sourceURL?.absoluteString ?? ""
	}

	private var _isPremiumSource: Bool {
		guard let url = source.sourceURL else { return false }
		return RyukSignAPI.isPremiumSource(url)
	}

	private var _isFavorite: Bool {
		_favorites.isFavorite(_key)
	}

	private var _tint: Color? {
		_tints.tint(for: _key)
	}

	/// "1,204 apps · Aug 3, 2026" — or nothing until we know, so the row stays clean.
	private var _subtitle: String {
		guard let url = source.sourceURL else { return "" }

		var parts: [String] = []
		if let count = _cache.appCount(for: url) {
			parts.append(.localized("%lld apps", arguments: count))
		}
		if let updated = _cache.lastUpdated(for: url) {
			parts.append(updated.formatted(date: .abbreviated, time: .shortened))
		}
		return parts.joined(separator: " · ")
	}

	// MARK: Body
	var body: some View {
		let isRegular = horizontalSizeClass != .compact

		let cellContent = HStack(spacing: 12) {
			// 40pt rather than 56pt: the row is about scanning a long list, and the
			// icon is still unambiguous at this size.
			FRIconCellView(
				title: source.name ?? .localized("Unknown"),
				subtitle: _subtitle,
				iconUrl: source.iconURL,
				size: 40
			)

			Spacer(minLength: 0)

			if _isFavorite {
				Image(systemName: "star.fill")
					.foregroundStyle(.yellow)
					.font(.caption)
			}
			if _isPremiumSource {
				Image(systemName: "crown.fill")
					.foregroundStyle(.yellow)
					.font(.caption)
			}
			if _isExcluded {
				Image(systemName: "eye.slash")
					.foregroundStyle(.secondary)
					.font(.caption2)
			}
		}
		.padding(isRegular ? 10 : 0)
		.background(
			isRegular
			? RoundedRectangle(cornerRadius: 18, style: .continuous)
				.fill(_tint?.opacity(0.16) ?? Color(.quaternarySystemFill))
			: nil
		)
		.onAppear {
			_isExcluded = RyukSignAPI.isSourceExcluded(_sourceIdentifier)
			// Extract once per source; cached to disk from then on.
			_tints.ensureTint(for: _key, iconURL: source.iconURL)
		}

		if isEditMode {
			cellContent
		} else {
			cellContent
				.swipeActions {
					if !_isPremiumSource {
						_actions(for: source)
					}
					_excludeAction()
					_contextActions(for: source)
				}
				.contextMenu {
					_favoriteAction()
					Divider()
					_contextActions(for: source)
					_excludeAction()
					if !_isPremiumSource {
						Divider()
						_actions(for: source)
					}
				}
				.sheet(isPresented: $_isShowingJSON) {
					RepositoryJSONView(source: source)
				}
				.sheet(isPresented: $_isShowingDebug) {
					RepositoryDebugView(source: source)
				}
		}
	}
}

// MARK: - Extension: View (menu)
extension SourcesCellView {
	@ViewBuilder
	private func _actions(for source: AltSource) -> some View {
		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			// Drop the cached body and counts along with the source itself.
			if let url = source.sourceURL {
				SourceCache.shared.remove(for: url)
			}
			Storage.shared.deleteSource(for: source)
		}
	}

	@ViewBuilder
	private func _favoriteAction() -> some View {
		Button {
			_favorites.toggle(_key)
		} label: {
			Label(
				_isFavorite ? .localized("Remove from Favourites") : .localized("Add to Favourites"),
				systemImage: _isFavorite ? "star.slash" : "star"
			)
		}
		.tint(.yellow)
	}

	@ViewBuilder
	private func _contextActions(for source: AltSource) -> some View {
		Button(.localized("Copy"), systemImage: "doc.on.clipboard") {
			UIPasteboard.general.string = source.sourceURL?.absoluteString
		}
		Button(.localized("View JSON"), systemImage: "curlybraces") {
			_isShowingJSON = true
		}
		Button(.localized("Refresh Icon Colour"), systemImage: "paintpalette") {
			_tints.refreshTint(for: _key, iconURL: source.iconURL)
		}
		Button(.localized("Debug Info"), systemImage: "ladybug") {
			_isShowingDebug = true
		}
	}

	@ViewBuilder
	private func _excludeAction() -> some View {
		Button {
			let newValue = !_isExcluded
			RyukSignAPI.setSourceExcluded(_sourceIdentifier, excluded: newValue)
			_isExcluded = newValue
		} label: {
			Label(
				_isExcluded ? .localized("Show in All") : .localized("Hide from All"),
				systemImage: _isExcluded ? "eye" : "eye.slash"
			)
		}
		.tint(.orange)
	}
}

// MARK: - Extension: onAppear
extension SourcesCellView {
	func onAppearLoadExcluded() -> some View {
		self.onAppear {
			_isExcluded = RyukSignAPI.isSourceExcluded(_sourceIdentifier)
		}
	}
}

// MARK: - Cached repository JSON

/// Shows the exact body we cached for this repository, which is also what the
/// browser renders from on a cold launch.
struct RepositoryJSONView: View {
	var source: AltSource

	@Environment(\.dismiss) private var dismiss

	private var _text: String {
		guard
			let url = source.sourceURL,
			let data = SourceCache.shared.data(for: RyukSignAPI.catalogURL(for: url))
		else {
			return .localized("Nothing cached for this repository yet. Pull to refresh the Sources tab and try again.")
		}

		if
			let object = try? JSONSerialization.jsonObject(with: data),
			let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
			let string = String(data: pretty, encoding: .utf8)
		{
			return string
		}

		return String(data: data, encoding: .utf8) ?? ""
	}

	var body: some View {
		NBNavigationView(.localized("Repository JSON"), displayMode: .inline) {
			ScrollView {
				Text(_text)
					.font(.system(.caption, design: .monospaced))
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding()
			}
			.toolbar {
				NBToolbarButton(role: .dismiss)
			}
		}
	}
}

// MARK: - Repository debug info

/// Maintainer-facing detail: the effective URL, cache state and flags. Nothing
/// here is needed to browse, which is exactly why it hides behind a menu.
struct RepositoryDebugView: View {
	var source: AltSource

	@ObservedObject private var _cache = SourceCache.shared
	@ObservedObject private var _tints = IconTintCache.shared
	@ObservedObject private var _favorites = SourceFavorites.shared

	@Environment(\.dismiss) private var dismiss

	private var _key: String { SourceFavorites.key(for: source) }

	private var _identifier: String {
		source.identifier ?? "(none)"
	}

	private var _sourceURL: String {
		source.sourceURL?.absoluteString ?? "(none)"
	}

	private var _catalogURL: String {
		guard let url = source.sourceURL else { return "(none)" }
		return RyukSignAPI.catalogURL(for: url)
	}

	private var _cacheSize: String {
		guard let url = source.sourceURL, let data = SourceCache.shared.data(for: RyukSignAPI.catalogURL(for: url)) else {
			return .localized("Not cached")
		}
		return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
	}

	private var _appCount: String {
		guard let url = source.sourceURL, let count = _cache.appCount(for: url) else {
			return .localized("Unknown")
		}
		return String(count)
	}

	private var _lastRefresh: String {
		guard let url = source.sourceURL, let date = _cache.lastUpdated(for: url) else {
			return .localized("Never")
		}
		return date.formatted(date: .abbreviated, time: .standard)
	}

	var body: some View {
		NBNavigationView(.localized("Debug Info"), displayMode: .inline) {
			NBList {
				NBSection(.localized("Identity")) {
					_DetailRow(title: .localized("Name"), value: source.name ?? "(none)")
					_DetailRow(title: .localized("Identifier"), value: _identifier)
				}

				NBSection(.localized("URLs")) {
					_DetailRow(title: .localized("Source"), value: _sourceURL, copyable: true)
					_DetailRow(title: .localized("Resolved"), value: _catalogURL, copyable: true)
				}

				NBSection(.localized("Cache")) {
					_DetailRow(title: .localized("Apps"), value: _appCount)
					_DetailRow(title: .localized("Last Refresh"), value: _lastRefresh)
					_DetailRow(title: .localized("Body Size"), value: _cacheSize)
				}

				NBSection(.localized("Flags")) {
					_DetailRow(title: .localized("Favourite"), value: _favorites.isFavorite(_key) ? .localized("Yes") : .localized("No"))
					_DetailRow(title: .localized("Premium"), value: source.sourceURL.map { RyukSignAPI.isPremiumSource($0) } ?? false ? .localized("Yes") : .localized("No"))
					_DetailRow(title: .localized("Hidden from All"), value: RyukSignAPI.isSourceExcluded(_identifier) ? .localized("Yes") : .localized("No"))
					_DetailRow(title: .localized("Icon Colour"), value: _tints.tint(for: _key).map { $0.toHex() } ?? .localized("Not extracted"))
				}
			}
			.toolbar {
				NBToolbarButton(role: .dismiss)
			}
		}
	}
}

private struct _DetailRow: View {
	var title: String
	var value: String
	var copyable: Bool = false

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(title)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.footnote.monospaced())
				.textSelection(copyable ? .enabled : .disabled)
		}
		.padding(.vertical, 2)
	}
}
