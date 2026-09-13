//
//  SourceAppsCellView.swift
//  RyukSign
//
//  Created by samara on 3.05.2025.
//
import SwiftUI
import AltSourceKit
import NimbleViews
import Combine
import NukeUI

struct SourceAppsCellView: View {
	@AppStorage("Feather.storeCellAppearance") private var _storeCellAppearance: Int = 0

	/// Browse settings (Settings → Browse).
	@AppStorage(BrowsePreferences.hidesAppDescriptions) private var _hidesAppDescriptions = false
	
	var source: ASRepository
	var app: ASRepository.App
	
	var body: some View {
		VStack {
			HStack(spacing: 2) {
				FRIconCellView(
					title: app.currentName,
					subtitle: Self.appDescription(app: app),
					iconUrl: app.iconURL,
					// 30pt and a single text line: this list can hold 15,000 apps, so
					// every row has to stay the same short height all the way down.
					size: 30,
					spacing: 10,
					lineLimit: 1
				)
				.overlay(alignment: .bottomLeading) {
					if let iconURL = source.currentIconURL {
						LazyImage(url: iconURL) { state in
							if let image = state.image {
								image
									.appIconStyle(size: 20, isCircle: true, background: Color(uiColor: .secondarySystemBackground))
									.offset(x: 41, y: 4)
							}
						}
					}
				}
				DownloadButtonView(app: app)
			}
			
			if _storeCellAppearance != 0,
			   !_hidesAppDescriptions,
			   let desc = app.localizedDescription {
				Text(desc)
					.frame(maxWidth: .infinity, alignment: .leading)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.padding(.top, 2)
					// Bounded, so one verbose description cannot stretch the row.
					.lineLimit(2)
			}
		}
	}
	
	static func appDescription(app: ASRepository.App) -> String {
		let optionalComponents: [String?] = [
			app.currentVersion,
			app.currentDescription ?? .localized("An awesome application")
		]
		
		let components: [String] = optionalComponents.compactMap { value in
			guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
				  !trimmed.isEmpty else {
				return nil
			}
			
			return trimmed
		}
		
		return components.joined(separator: " • ")
	}
}
