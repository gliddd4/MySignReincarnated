//
//  IconTintCache.swift
//  RyukSign
//
//  A repository's icon already carries its identity — pulling a colour out of it
//  makes a long source list easier to scan. The colour is taken from a blurred
//  average of the icon (so a busy logo yields one usable hue instead of noise)
//  and cached on disk, keyed by source identifier, so it is extracted once.
//
//  Tints can be refreshed from Settings → Source Cache.
//

import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Combine
import AltSourceKit

@MainActor
final class IconTintCache: ObservableObject {
	static let shared = IconTintCache()

	@Published private(set) var tints: [String: Color] = [:]

	private struct Entry: Codable {
		var hex: String
		var updated: Date
	}

	private var _entries: [String: Entry] = [:]
	private var _inFlight: Set<String> = []

	private var _fileURL: URL {
		URL.documentsDirectory.appendingPathComponent("IconTints.json")
	}

	private init() {
		_entries = Self._load(from: _fileURL)
		tints = _entries.compactMapValues { Color(hex: $0.hex) }
	}

	// MARK: - Query

	func tint(for key: String) -> Color? {
		tints[key]
	}

	var cachedCount: Int { tints.count }

	// MARK: - Extract

	/// Extracts a tint if we don't have one yet. Safe to call on every row render.
	func ensureTint(for key: String, iconURL: URL?) {
		guard tints[key] == nil, !_inFlight.contains(key) else { return }
		_extract(key: key, iconURL: iconURL)
	}

	/// Re-runs extraction for one source.
	func refreshTint(for key: String, iconURL: URL?) {
		_entries[key] = nil
		tints[key] = nil
		_extract(key: key, iconURL: iconURL)
	}

	func clear() {
		_entries.removeAll()
		tints.removeAll()
		try? FileManager.default.removeItem(at: _fileURL)
	}

	// MARK: - Private

	private func _extract(key: String, iconURL: URL?) {
		guard let iconURL, !key.isEmpty else { return }
		_inFlight.insert(key)

		let url = iconURL
		DispatchQueue.global(qos: .utility).async {
			let data = try? Data(contentsOf: url)
			let uiColor = data.flatMap { Self.dominantColor(from: $0) }

			DispatchQueue.main.async { [weak self] in
				guard let self else { return }
				self._inFlight.remove(key)

				guard let uiColor else { return }
				let hex = Color(uiColor: uiColor).toHex()
				self._entries[key] = Entry(hex: hex, updated: Date())
				self.tints[key] = Color(hex: hex)
				self._save()
			}
		}
	}

	private func _save() {
		guard let data = try? JSONEncoder().encode(_entries) else { return }
		try? data.write(to: _fileURL, options: .atomic)
	}

	private static func _load(from url: URL) -> [String: Entry] {
		guard
			let data = try? Data(contentsOf: url),
			let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
		else {
			return [:]
		}
		return decoded
	}

	// MARK: - Colour maths

	/// Average colour of a Gaussian-blurred icon, nudged into a range that stays
	/// legible as a tint on both light and dark backgrounds.
	static func dominantColor(from data: Data, blurRadius: Double = 18) -> UIColor? {
		guard let image = CIImage(data: data) else { return nil }

		// Blur first: it turns multi-colour logos into a single representative hue.
		let blurred = image
			.applyingGaussianBlur(sigma: blurRadius)
			.cropped(to: image.extent)

		let filter = CIFilter.areaAverage()
		filter.inputImage = blurred
		filter.extent = blurred.extent

		guard let output = filter.outputImage else { return nil }

		var bitmap = [UInt8](repeating: 0, count: 4)
		CIContext(options: [.workingColorSpace: NSNull()]).render(
			output,
			toBitmap: &bitmap,
			rowBytes: 4,
			bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
			format: .RGBA8,
			colorSpace: CGColorSpaceCreateDeviceRGB()
		)

		guard bitmap[3] > 0 else { return nil }

		let color = UIColor(
			red: CGFloat(bitmap[0]) / 255,
			green: CGFloat(bitmap[1]) / 255,
			blue: CGFloat(bitmap[2]) / 255,
			alpha: 1
		)

		return _legible(color)
	}

	/// Pushes a washed-out or near-black average into a usable accent range.
	private static func _legible(_ color: UIColor) -> UIColor {
		var hue: CGFloat = 0
		var saturation: CGFloat = 0
		var brightness: CGFloat = 0
		var alpha: CGFloat = 0

		guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
			return color
		}

		return UIColor(
			hue: hue,
			saturation: min(max(saturation * 1.25, 0.35), 0.9),
			brightness: min(max(brightness * 1.05, 0.45), 0.92),
			alpha: 1
		)
	}
}
