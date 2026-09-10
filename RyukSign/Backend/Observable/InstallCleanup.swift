//
//  InstallCleanup.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

@MainActor
enum InstallCleanup {
	static let deleteKey = "Feather.deleteAppAfterInstall"
	static let clearCacheKey = "Feather.clearCacheAfterInstall"
	private static let pendingKey = "Feather.installCleanupPending"

	/// Deleting now would pull the app out from under the card still showing it. On disk so a kill
	/// before `flush()` still cleans up.
	static func stage(_ app: AppInfoPresentable) {
		guard let uuid = app.uuid, !_pending.contains(uuid) else { return }
		_pending.append(uuid)
	}

	/// Only safe once the install UI is gone.
	static func flush() {
		let uuids = _pending
		guard !uuids.isEmpty else { return }
		_pending = []

		let defaults = UserDefaults.standard

		if defaults.bool(forKey: deleteKey) {
			let apps = Storage.shared.getAllApps().filter { uuids.contains($0.uuid ?? "") }
			Storage.shared.deleteApps(apps)
		}

		if defaults.bool(forKey: clearCacheKey) {
			StorageManager.purgeCaches()
		}
	}

	private static var _pending: [String] {
		get { UserDefaults.standard.stringArray(forKey: pendingKey) ?? [] }
		set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
	}
}
