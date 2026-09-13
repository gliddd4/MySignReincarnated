//
//  DownloadsTabView.swift
//  RyukSign
//
//  Downloads as a place you can sit in rather than a bubble you catch while it
//  floats past. The queue always existed, but it was only ever reachable from the
//  header that appears while something is downloading — so a finished or failed
//  transfer had nowhere to be looked at, and the list vanished the moment the
//  header did.
//
//  The rows are the existing `DownloadItemView`, so the phase ring, the progress
//  bar and the cancel button all behave exactly as they do in the header.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct DownloadsTabView: View {
	@ObservedObject private var _manager = DownloadManager.shared

	var body: some View {
		Group {
			if _manager.downloads.isEmpty {
				NBContentUnavailable(
					.localized("No Downloads"),
					systemImage: "arrow.down.circle",
					description: .localized("Anything you download shows up here while it downloads, unpacks and imports.")
				)
			} else {
				List {
					ForEach(_manager.downloads) { download in
						DownloadItemView(download: download)
					}
				}
				.listStyle(.plain)
			}
		}
	}
}
