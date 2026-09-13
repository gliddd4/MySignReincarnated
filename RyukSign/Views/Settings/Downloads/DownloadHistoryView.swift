//
//  DownloadHistoryView.swift
//  RyukSign
//
//  The list MySign kept: every download with its icon, name, date and time still
//  attached, long after the queue it came from has emptied.
//

import SwiftUI
import NimbleViews

struct DownloadHistoryView: View {
	@ObservedObject private var _history = DownloadHistory.shared
	@ObservedObject private var _icons = RepositoryIconStore.shared

	@State private var _searchText: String = ""
	@State private var _isConfirmingClear = false

	private var _filtered: [DownloadRecord] {
		let query = _searchText.trimmingCharacters(in: .whitespaces)
		guard !query.isEmpty else { return _history.records }

		return _history.records.filter { record in
			record.name.localizedCaseInsensitiveContains(query)
				|| (record.developer?.localizedCaseInsensitiveContains(query) ?? false)
				|| (record.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
		}
	}

	var body: some View {
		NBList(.localized("Download History"), displayMode: .inline) {
			if _history.records.isEmpty {
				NBSection(.localized("History")) {
					Text(.localized("Nothing downloaded yet. Apps you pull from a repository will show up here."))
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			} else if _filtered.isEmpty {
				NBSection(.localized("History")) {
					Text(.localized("No downloads match your search."))
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			} else {
				NBSection(.localized("Downloads"), secondary: "\(_filtered.count)") {
					ForEach(_filtered) { record in
						_row(record)
							.swipeActions {
								Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
									_history.remove(record)
								}
							}
					}
				}
			}
		}
		.searchable(
			text: $_searchText,
			placement: .navigationBarDrawer(displayMode: .always),
			prompt: .localized("Search downloads")
		)
		.toolbar {
			if !_history.records.isEmpty {
				Button(.localized("Clear"), systemImage: "trash", role: .destructive) {
					_isConfirmingClear = true
				}
			}
		}
		.confirmationDialog(
			.localized("Clear all download history?"),
			isPresented: $_isConfirmingClear,
			titleVisibility: .visible
		) {
			Button(.localized("Clear All"), role: .destructive) {
				_history.clear()
				FeedbackManager.shared.success()
			}
		}
		.onAppear {
			// Resolve any icons this install hasn't fetched yet — the log survives
			// the repository it came from, so the bytes have to live here too.
			for record in _history.records {
				_history.cacheIcon(for: record)
			}
		}
	}

	// MARK: - Row

	private func _row(_ record: DownloadRecord) -> some View {
		HStack(spacing: 12) {
			if let icon = _icons.image(for: record.iconKey) {
				Image(uiImage: icon)
					.appIconStyle(size: 40)
			} else {
				Image("App_Unknown")
					.appIconStyle(size: 40)
			}

			VStack(alignment: .leading, spacing: 2) {
				Text(record.name)
					.font(.headline)
					.lineLimit(1)
				Text(_subtitle(record))
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}

			Spacer(minLength: 0)

			Image(systemName: record.status.systemImage)
				.font(.footnote)
				.foregroundStyle(_color(for: record.status))
		}
		.padding(.vertical, 2)
		.contextMenu {
			if let identifier = record.bundleIdentifier, !identifier.isEmpty {
				Button(.localized("Copy Bundle ID"), systemImage: "doc.on.clipboard") {
					UIPasteboard.general.string = identifier
					Toast.success(.localized("Bundle ID copied"), systemImage: "doc.on.clipboard")
				}
			}

			Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
				_history.remove(record)
			}
		}
	}

	private func _subtitle(_ record: DownloadRecord) -> String {
		var parts: [String] = []

		if let version = record.version, !version.isEmpty {
			parts.append("v\(version)")
		}
		if let developer = record.developer, !developer.isEmpty {
			parts.append(developer)
		}
		if let size = record.size, size > 0 {
			parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
		}

		parts.append(record.date.formatted(date: .abbreviated, time: .shortened))
		parts.append(record.status.label)

		return parts.joined(separator: " · ")
	}

	private func _color(for status: DownloadRecordStatus) -> Color {
		switch status {
		case .started:   return .secondary
		case .completed: return .green
		case .failed:    return .red
		}
	}
}
