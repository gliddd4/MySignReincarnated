//
//  SourceFavorites.swift
//  RyukSign
//
//  Ported from MySign (mysignipasigner)'s FavoritesManager.
//
//  RyukSign had no way to mark a repository as important. Favourites are kept as
//  identifiers in UserDefaults (they must survive the Core Data store being
//  rebuilt) and are pulled into their own section at the top of the browser.
//

import Foundation
import CoreData
import SwiftUI

@MainActor
final class SourceFavorites: ObservableObject {
	static let shared = SourceFavorites()

	@Published private(set) var identifiers: Set<String> = []

	private let _key = "RyukSign.sourceFavorites"

	private init() {
		identifiers = Set(UserDefaults.standard.stringArray(forKey: _key) ?? [])
	}

	// MARK: - Query

	func isFavorite(_ identifier: String) -> Bool {
		identifiers.contains(identifier)
	}

	var count: Int { identifiers.count }

	// MARK: - Mutate

	func toggle(_ identifier: String) {
		guard !identifier.isEmpty else { return }

		if identifiers.contains(identifier) {
			identifiers.remove(identifier)
			Toast.info(.localized("Removed from Favourites"), systemImage: "star.slash")
		} else {
			identifiers.insert(identifier)
			Toast.success(.localized("Added to Favourites"), systemImage: "star.fill")
		}
		_persist()
	}

	func remove(_ identifier: String) {
		guard identifiers.contains(identifier) else { return }
		identifiers.remove(identifier)
		_persist()
	}

	func clear() {
		identifiers.removeAll()
		_persist()
	}

	/// Stable key for a source: its identifier, falling back to its URL.
	static func key(for source: AltSource) -> String {
		source.identifier ?? source.sourceURL?.absoluteString ?? ""
	}

	// MARK: - Private

	private func _persist() {
		UserDefaults.standard.set(Array(identifiers), forKey: _key)
	}
}
