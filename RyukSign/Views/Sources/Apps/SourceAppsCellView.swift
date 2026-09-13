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
					lineLimit: 1,
					// The repository the app came from, tucked into the icon's own corner.
					badgeIconURL: source.currentIconURL
				)
				DownloadButtonView(app: app)
			}
			
			if _storeCellAppearance != 0,
			   !_hidesAppDescriptions,
			   let desc = app.localizedDescription {
				Text(desc)
					.frame(maxWidth: .infinity, alignment: .leading)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.leading)
					.padding(.top, 2)
					// Runs to as many lines as it needs, across the full width of the row —
					// under the icon, the name and the download button, rather than being
					// clamped above them. `fixedSize` on the vertical axis is what stops the
					// self-sizing cell compressing it back down. "Standard" cell appearance
					// and the Browse setting both still turn descriptions off entirely.
					.fixedSize(horizontal: false, vertical: true)
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
