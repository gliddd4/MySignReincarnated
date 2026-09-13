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

	/// One source of truth for the icon column: the icon is this wide and the text
	/// starts this far in, which is what lets the description below line up with it.
	private static let _iconSize: CGFloat = 30
	private static let _iconSpacing: CGFloat = 10
	private var _textColumn: CGFloat { Self._iconSize + Self._iconSpacing }

	/// "Big Description" cell appearance, less the two settings that turn descriptions
	/// off altogether.
	private var _flowsDescriptionBelow: Bool {
		_storeCellAppearance != 0
			&& !_hidesAppDescriptions
			&& !(app.localizedDescription ?? "").isEmpty
	}
	
	var body: some View {
		VStack {
			HStack(spacing: 2) {
				FRIconCellView(
					title: app.currentName,
					// When the description flows underneath, this line keeps only the version
					// and the text below carries on from where this line left off.
					subtitle: _flowsDescriptionBelow
						? (app.currentVersion ?? "")
						: Self.appDescription(app: app),
					iconUrl: app.iconURL,
					// 30pt and a single text line: this list can hold 15,000 apps, so
					// every row has to stay the same short height all the way down.
					size: Self._iconSize,
					spacing: Self._iconSpacing,
					lineLimit: 1,
					// The repository the app came from, tucked into the icon's own corner.
					badgeIconURL: source.currentIconURL
				)
				DownloadButtonView(app: app)
			}
			
			if _flowsDescriptionBelow, let desc = app.localizedDescription {
				FlowingTextView(
					text: desc,
					// The first line starts under the text column above, so it reads as the
					// description carrying on; every line after that runs the full width of
					// the row, under the icon and the download button alike.
					firstLineIndent: _textColumn
				)
				.padding(.top, 2)
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
