//
//  FRIconCellView.swift
//  NimbleKit
//
//  Created by samara on 3.05.2025.
//

import SwiftUI
import NukeUI
import NimbleViews

// MARK: - View
struct FRIconCellView: View {
	var title: String
	var subtitle: String
	var iconUrl: URL?
	var size: CGFloat = 56
	var isCircle: Bool = false
	/// Gap between the icon and the text. Long lists tighten this; screens with a
	/// handful of rows keep the roomy default.
	var spacing: CGFloat = 18
	/// 0 means unlimited, so a long app description wraps across as many lines as
	/// it likes — fine on a settings screen, wasteful in a list of thousands.
	var lineLimit: Int = 0
	/// Small icon tucked into the corner of the icon itself — the repository an app
	/// came from in a mixed-source list. It belongs on the icon rather than on the
	/// row, because an overlay on the row is aligned against the title and subtitle
	/// too, which is how the repository badge ended up sitting across the app name.
	var badgeIconURL: URL?

	// MARK: Body
	var body: some View {
		HStack(spacing: spacing) {
			iconView
			
			NBTitleWithSubtitleView(
				title: title,
				subtitle: subtitle,
				linelimit: lineLimit
			)
		}
	}
	
	@ViewBuilder
	private var iconView: some View {
		Group {
			if let iconURL = iconUrl {
				LazyImage(url: iconURL) { state in
					if let image = state.image {
						image.appIconStyle(size: size, isCircle: isCircle)
					} else {
						standardIcon
					}
				}
			} else {
				standardIcon
			}
		}
		// Pinned so the badge aligns to the icon's corner, not to the text baseline.
		.frame(width: size, height: size)
		.overlay(alignment: .bottomTrailing) {
			if let badgeIconURL {
				LazyImage(url: badgeIconURL) { state in
					if let image = state.image {
						image.appIconStyle(
							size: max(14, size * 0.5),
							lineWidth: 1,
							isCircle: true,
							background: Color(uiColor: .secondarySystemBackground)
						)
					}
				}
			}
		}
	}
	
	var standardIcon: some View {
		Image("App_Unknown")
			.appIconStyle(size: size, isCircle: isCircle)
	}
}
