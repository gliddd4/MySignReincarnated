//
//  DownloadHistory.swift
//  RyukSign
//
//  Ported from MySign (mysignipasigner)'s download log, which kept the app icon,
//  name, date and time for everything you had ever pulled from a repository. In
//  RyukSign a download simply vanished from the queue once it landed, so there
//  was no way to answer "what did I grab last week, and from where?".
//
//  Icons are the interesting part: a URL alone is useless a month later, so the
//  bytes are cached to disk through `RepositoryIconStore` (keyed per record).
//  The log therefore still renders correctly after the repository that supplied
//  it has gone away.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Record

enum DownloadRecordStatus: String, Codable {
	case started
	case completed
	case failed

	var label: String {
		switch self {
		case .started:   return .localized("Started")
		case .completed: return .localized("Completed")
		case .failed:    return .localized("Failed")
		}
	}

	var systemImage: String {
		switch self {
		case .started:   return "arrow.down.circle"
		case .completed: return "checkmark.circle.fill"
		case .failed:    return "exclamationmark.triangle.fill"
		}
	}
}

struct DownloadRecord: Codable, Identifiable, Hashable {
	/// Matches the `Download` it came from, so completion can update the entry.
	var id: String
	var name: String
	var bundleIdentifier: String?
	var version: String?
	var developer: String?
	var iconURL: String?
	var size: Int64?
	var date: Date
	var status: DownloadRecordStatus

	/// The key this record's icon is cached under.
	var iconKey: String { DownloadHistory.iconKey(for: id) }
}

// MARK: - History

@MainActor
final class DownloadHistory: ObservableObject {
	static let shared = DownloadHistory()

	/// Newest first — the order the list renders in.
	@Published private(set) var records: [DownloadRecord] = []

	/// Enough to answer "what did I download", not enough to grow forever.
	private let _limit = 500

	private var _fileURL: URL {
		URL.documentsDirectory.appendingPathComponent("DownloadHistory.json")
	}

	private init() {
		records = Self._load(from: _fileURL)
	}

	// MARK: - Icon key

	nonisolated static func iconKey(for id: String) -> String {
		"download.\(id)"
	}

	// MARK: - Mutate

	func record(_ record: DownloadRecord) {
		// A retried download reuses its id, so replace rather than duplicate.
		records.removeAll { $0.id == record.id }
		records.insert(record, at: 0)

		if records.count > _limit {
			let dropped = records.suffix(records.count - _limit)
			for entry in dropped {
				RepositoryIconStore.shared.remove(for: entry.iconKey)
			}
			records = Array(records.prefix(_limit))
		}

		_save()
	}

	func update(id: String, status: DownloadRecordStatus) {
		guard let index = records.firstIndex(where: { $0.id == id }) else { return }
		guard records[index].status != status else { return }
		records[index].status = status
		_save()
	}

	/// Warms the on-disk icon cache for a record. Safe to call repeatedly.
	func cacheIcon(for record: DownloadRecord) {
		guard let string = record.iconURL, let url = URL(string: string) else { return }
		RepositoryIconStore.shared.ensureIcon(for: record.iconKey, candidates: [url])
	}

	func remove(_ record: DownloadRecord) {
		records.removeAll { $0.id == record.id }
		RepositoryIconStore.shared.remove(for: record.iconKey)
		_save()
	}

	func clear() {
		for entry in records {
			RepositoryIconStore.shared.remove(for: entry.iconKey)
		}
		records.removeAll()
		_save()
	}

	// MARK: - Persistence

	private func _save() {
		guard let data = try? JSONEncoder().encode(records) else { return }
		try? data.write(to: _fileURL, options: .atomic)
	}

	private static func _load(from url: URL) -> [DownloadRecord] {
		guard
			let data = try? Data(contentsOf: url),
			let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data)
		else {
			return []
		}
		return decoded.sorted { $0.date > $1.date }
	}
}
