//
//  MachOEntitlements.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

enum MachOEntitlements {
	private static let codeSignatureCommand: UInt32 = 0x1d
	private static let embeddedSignatureMagic: UInt32 = 0xfade0cc0
	private static let entitlementsMagic: UInt32 = 0xfade7171
	private static let entitlementsSlot: UInt32 = 0x5

	static func keychainAccessGroups(forExecutableAt url: URL) -> [String] {
		read(forExecutableAt: url)?["keychain-access-groups"] as? [String] ?? []
	}

	static func read(forExecutableAt url: URL) -> [String: Any]? {
		guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }

		let slice = MachOReader.sliceOffset(in: data)

		// iOS binaries are 64-bit
		let bigEndian: Bool
		switch MachOReader.u32(data, at: slice, bigEndian: false) {
		case MachOReader.machO64: bigEndian = false
		case MachOReader.machO64Swapped: bigEndian = true
		default: return nil
		}

		guard let ncmds = MachOReader.u32(data, at: slice + 16, bigEndian: bigEndian) else { return nil }
		var cmd = slice + MachOReader.machHeader64Size

		for _ in 0..<ncmds {
			guard
				let cmdId = MachOReader.u32(data, at: cmd, bigEndian: bigEndian),
				let cmdSize = MachOReader.u32(data, at: cmd + 4, bigEndian: bigEndian),
				cmdSize >= 8
			else { return nil }

			if cmdId == codeSignatureCommand, let off = MachOReader.u32(data, at: cmd + 8, bigEndian: bigEndian) {
				return entitlements(in: data, at: slice + Int(off))
			}

			cmd += Int(cmdSize)
		}

		return nil
	}

	// Code signature blobs are always big-endian, regardless of the host or Mach-O slice.
	private static func entitlements(in data: Data, at codeSig: Int) -> [String: Any]? {
		guard
			MachOReader.u32(data, at: codeSig, bigEndian: true) == embeddedSignatureMagic,
			let count = MachOReader.u32(data, at: codeSig + 8, bigEndian: true)
		else { return nil }

		for i in 0..<Int(count) {
			let index = codeSig + 12 + i * 8
			guard
				let type = MachOReader.u32(data, at: index, bigEndian: true),
				let blobOff = MachOReader.u32(data, at: index + 4, bigEndian: true)
			else { return nil }

			guard type == entitlementsSlot else { continue }

			let blob = codeSig + Int(blobOff)
			guard
				MachOReader.u32(data, at: blob, bigEndian: true) == entitlementsMagic,
				let length = MachOReader.u32(data, at: blob + 4, bigEndian: true),
				length > 8
			else { return nil }

			let start = blob + 8
			let end = blob + Int(length)
			guard start <= end, end <= data.count else { return nil }

			let plist = data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))
			return (try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)) as? [String: Any]
		}

		return nil
	}
}
