//
//  ImagePagerView.swift
//  RyukSign
//
//  Ported from MySign's image preview: tapping an image opens it full screen and
//  you can cycle through every other image in the same folder. The page order is
//  the folder's listing order, so cycling matches what was on screen behind it.
//

import SwiftUI

struct ImagePagerView: View {
	let directory: URL
	let start: FileEntry

	@Environment(\.dismiss) private var dismiss

	@State private var _images: [FileEntry] = []
	@State private var _index: Int = 0

	private var _current: FileEntry? {
		_images.indices.contains(_index) ? _images[_index] : nil
	}

	var body: some View {
		NavigationStack {
			ZStack {
				Color.black.ignoresSafeArea()

				if _images.isEmpty {
					Text(.localized("No images in this folder"))
						.font(.footnote)
						.foregroundStyle(.white.opacity(0.7))
				} else {
					TabView(selection: $_index) {
						ForEach(Array(_images.enumerated()), id: \.element.id) { offset, entry in
							ZoomableImage(url: entry.url)
								.tag(offset)
						}
					}
					.tabViewStyle(.page(indexDisplayMode: .never))
				}
			}
			.navigationTitle(_title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					Button(.localized("Done")) {
						dismiss()
					}
				}
				ToolbarItem(placement: .navigationBarTrailing) {
					Button {
						guard let current = _current else { return }
						UIActivityViewController.show(activityItems: [current.url])
					} label: {
						Image(systemName: "square.and.arrow.up")
					}
					.disabled(_current == nil)
				}
			}
			.toolbarBackground(.visible, for: .navigationBar)
			.toolbarColorScheme(.dark, for: .navigationBar)
		}
		.onAppear {
			// Ordered the same way the folder was listed, so page 1 is the first
			// image the user saw rather than an arbitrary order.
			_images = FileBrowser.shared.images(in: directory)
			_index = _images.firstIndex(of: start) ?? 0
		}
	}

	private var _title: String {
		guard !_images.isEmpty else { return .localized("Preview") }
		return "\(_index + 1) / \(_images.count)"
	}
}

// MARK: - Zoomable image

/// Pinch to zoom, drag to pan once zoomed, double-tap to toggle. Paging still
/// works at 1× because the drag gesture only claims the touch after zooming in.
private struct ZoomableImage: View {
	let url: URL

	@State private var _scale: CGFloat = 1
	@State private var _lastScale: CGFloat = 1
	@State private var _offset: CGSize = .zero
	@State private var _lastOffset: CGSize = .zero

	var body: some View {
		GeometryReader { proxy in
			if let image = UIImage(contentsOfFile: url.path) {
				Image(uiImage: image)
					.resizable()
					.scaledToFit()
					.frame(width: proxy.size.width, height: proxy.size.height)
					.scaleEffect(_scale)
					.offset(_offset)
					.gesture(
						MagnificationGesture()
							.onChanged { value in
								_scale = min(max(_lastScale * value, 1), 8)
							}
							.onEnded { _ in
								_lastScale = _scale
								if _scale <= 1 {
									_offset = .zero
									_lastOffset = .zero
								}
							}
					)
					.simultaneousGesture(
						DragGesture()
							.onChanged { value in
								guard _scale > 1 else { return }
								_offset = CGSize(
									width: _lastOffset.width + value.translation.width,
									height: _lastOffset.height + value.translation.height
								)
							}
							.onEnded { _ in
								_lastOffset = _offset
							}
					)
					.onTapGesture(count: 2) {
						withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
							if _scale > 1 {
								_scale = 1
								_lastScale = 1
								_offset = .zero
								_lastOffset = .zero
							} else {
								_scale = 3
								_lastScale = 3
							}
						}
					}
			} else {
				Text(.localized("Could not load image"))
					.font(.footnote)
					.foregroundStyle(.white.opacity(0.7))
					.frame(width: proxy.size.width, height: proxy.size.height)
			}
		}
	}
}
