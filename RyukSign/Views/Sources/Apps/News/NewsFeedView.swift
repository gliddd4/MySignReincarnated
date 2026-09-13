//
//  NewsFeedView.swift
//  RyukSign
//
//  Every repository's announcements in one list. The single-source carousel
//  already existed inside a repository; this is the view for the whole set,
//  which is where a revoked certificate or a repository move actually gets
//  noticed.
//
//  Each entry is drawn in full — image included — rather than opening into a
//  detail sheet, so the feed is read by scrolling instead of by tapping.
//

import SwiftUI
import AltSourceKit
import NukeUI
import NimbleViews

// MARK: - View
struct NewsFeedView: View {
	@ObservedObject private var _feed = NewsFeed.shared

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
					ScrollView {
						LazyVStack(alignment: .leading, spacing: 20) {
							ForEach(_feed.items) { item in
								_item(item)
							}
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 12)
					}
				}
			}
			.toolbar {
				// `.dismiss` renders a `chevron.left` at the leading edge, which looks like a
				// Back button on a sheet with nothing behind it. xmark is the real dismiss.
				NBToolbarButton(role: .cancel)
			}
			.onAppear {
				// Rebuild first: the seen-set is applied to whatever this pass
				// collected, not to a stale list from an earlier launch.
				_feed.rebuild()
				_feed.markAllSeen()
			}
		}
	}

	// MARK: - Item
	@ViewBuilder
	private func _item(_ item: NewsFeed.Item) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			// The announcement's artwork, with its headline laid over the bottom
			// edge the same way the card inside a repository does. White on the
			// gradient is what keeps the title legible over arbitrary artwork.
			ZStack(alignment: .bottomLeading) {
				_artwork(item)

				LinearGradient(
					gradient: Gradient(colors: [.black.opacity(0.8), .clear]),
					startPoint: .bottom,
					endPoint: .top
				)
				.frame(height: 90)
				.frame(maxWidth: .infinity, alignment: .bottom)
				.allowsHitTesting(false)

				Text(item.news.title)
					.font(.headline)
					.foregroundStyle(.white)
					.multilineTextAlignment(.leading)
					.padding(12)
			}
			.frame(height: 180)
			.frame(maxWidth: .infinity)
			.background(item.news.tintColor ?? Color.secondary)
			.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
			)

			if !item.news.caption.isEmpty {
				Text(item.news.caption)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.leading)
			}

			HStack(spacing: 5) {
				// The repository saying it, so a feed mixing many sources still
				// shows at a glance who is talking.
				Text(item.sourceName)
				if let date = item.news.date?.date {
					Text(verbatim: "·")
					Text(verbatim: date.formatted(.relative(presentation: .named)))
				}
			}
			.font(.caption)
			.foregroundStyle(.tertiary)
		}
	}

	// MARK: - Artwork
	@ViewBuilder
	private func _artwork(_ item: NewsFeed.Item) -> some View {
		Group {
			if let imageURL = item.news.imageURL {
				LazyImage(url: imageURL) { state in
					if let image = state.image {
						image
							.resizable()
							.aspectRatio(contentMode: .fill)
					} else {
						Color.gray.opacity(0.2)
					}
				}
			} else {
				Color.gray.opacity(0.2)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.clipped()
	}
}
