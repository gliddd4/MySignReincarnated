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

	// MARK: Body
	var body: some View {
		HStack(spacing: spacing) {
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
			
			NBTitleWithSubtitleView(
				title: title,
				subtitle: subtitle,
				linelimit: lineLimit
			)
		}
	}
	
	var standardIcon: some View {
		Image("App_Unknown")
			.appIconStyle(size: size, isCircle: isCircle)
	}
}
