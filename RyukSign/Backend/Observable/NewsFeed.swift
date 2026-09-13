//
//  NewsFeed.swift
//  RyukSign
//
//  Ported from MySign's news aggregation.
//
//  RyukSign only showed news while you were inside a single repository, so an
//  announcement from any of your other sources was invisible unless you happened
//  to open that source. This gathers every announcement from every loaded
//  repository into one feed, newest first, and keeps a seen-set so the toolbar
//  can say how much is new since last time.
//

import SwiftUI
import AltSourceKit

@MainActor
final class NewsFeed: ObservableObject {
	static let shared = NewsFeed()

	/// An announcement paired with the repository that published it. The same
	/// identifier can appear in more than one source, hence the composite id.
	struct Item: Identifiable {
		var id: String
		var news: ASRepository.News
		var sourceName: String
		var sourceKey: String
	}

	@Published private(set) var items: [Item] = []
	@Published private(set) var unseenCount: Int = 0

	private let _seenKey = "RyukSign.newsSeenIDs"
	private var _seen: Set<String> = []

	private init() {
		_seen = Set(UserDefaults.standard.stringArray(forKey: _seenKey) ?? [])
	}

	/// Rebuilds from the repositories already loaded in memory, so the feed costs
	/// nothing beyond what browsing the Sources tab already fetched.
	func rebuild() {
		var collected: [Item] = []

		for (source, repository) in SourcesViewModel.shared.sources {
			let key = SourceFavorites.key(for: source)
			let name = source.name ?? repository.name ?? .localized("Repository")

			for news in repository.news ?? [] {
				collected.append(
					Item(
						id: "\(key)|\(news.id)",
						news: news,
						sourceName: name,
						sourceKey: key
					)
				)
			}
		}

		items = collected.sorted(by: Self._isNewer)

		var unseen = 0
		for item in items where !_seen.contains(item.id) {
			unseen += 1
		}
		unseenCount = unseen
	}

	/// Opening the feed is what marks announcements as read. The badge exists to
	/// get you there, not to keep nagging once you have looked.
	func markAllSeen() {
		_seen.formUnion(items.map(\.id))
		UserDefaults.standard.set(Array(_seen), forKey: _seenKey)
		unseenCount = 0
	}

	private static func _isNewer(_ lhs: Item, _ rhs: Item) -> Bool {
		// Undated announcements sort last: they are not newer than a dated one,
		// and treating them as newest would park them on top permanently.
		switch (lhs.news.date?.date, rhs.news.date?.date) {
		case let (left?, right?):
			return left > right
		case (_?, nil):
			return true
		case (nil, _?):
			return false
		default:
			return lhs.news.title < rhs.news.title
		}
	}
}
