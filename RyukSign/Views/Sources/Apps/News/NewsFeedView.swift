//
//  NewsFeedView.swift
//  RyukSign
//
//  Every repository's announcements in one list. The single-source carousel
//  already existed inside a repository; this is the view for the whole set,
//  which is where a revoked certificate or a repository move actually gets
//  noticed.
//

import SwiftUI
import AltSourceKit
import NimbleViews

// MARK: - View
struct NewsFeedView: View {
	@ObservedObject private var _feed = NewsFeed.shared
	@Environment(\.dismiss) private var dismiss

	@State private var _selected: NewsFeed.Item?

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("News"), displayMode: .inline) {
			Group {
				if _feed.items.isEmpty {
					NBContentUnavailable(
						.localized("Nothing Published"),
						systemImage: "newspaper",
						description: .localized("Announcements from every one of your repositories land here, so you do not have to open each source to find out what changed.")
					)
				} else {
					List {
						ForEach(_feed.items) { item in
							Button {
								_selected = item
							} label: {
								_row(item)
							}
							.buttonStyle(.plain)
						}
					}
					.listStyle(.plain)
				}
			}
			.toolbar {
				NBToolbarButton(role: .dismiss)
			}
			.onAppear {
				// Rebuild first: the seen-set is applied to whatever this pass
				// collected, not to a stale list from an earlier launch.
				_feed.rebuild()
				_feed.markAllSeen()
			}
			.fullScreenCover(item: $_selected) { item in
				SourceNewsCardInfoView(new: item.news)
			}
		}
	}

	// MARK: - Row
	@ViewBuilder
	private func _row(_ item: NewsFeed.Item) -> some View {
		HStack(alignment: .top, spacing: 10) {
			// The repository's own tint, so a feed mixing many sources still
			// shows at a glance who is talking.
			RoundedRectangle(cornerRadius: 2, style: .continuous)
				.fill(item.news.tintColor ?? Color.secondary)
				.frame(width: 4)

			VStack(alignment: .leading, spacing: 3) {
				Text(item.news.title)
					.font(.subheadline.weight(.semibold))
					.multilineTextAlignment(.leading)
					.lineLimit(2)

				if !item.news.caption.isEmpty {
					Text(item.news.caption)
						.font(.caption)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.leading)
						.lineLimit(3)
				}

				HStack(spacing: 5) {
					Text(item.sourceName)
					if let date = item.news.date?.date {
						Text(verbatim: "·")
						Text(verbatim: date.formatted(.relative(presentation: .named)))
					}
				}
				.font(.caption2)
				.foregroundStyle(.tertiary)
			}

			Spacer(minLength: 0)
		}
		.padding(.vertical, 4)
		.contentShape(Rectangle())
	}
}
