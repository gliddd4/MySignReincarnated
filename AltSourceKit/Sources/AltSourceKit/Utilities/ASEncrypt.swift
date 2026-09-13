//
//  ASEncrypt.swift
//  AltSourceKit
//
//  The other half of ASDecrypt. ESign repository codes are a repeating-key XOR
//  of a newline-joined URL list, base64-encoded, wrapped in `source[...]` — so
//  encoding is just the same loop run backwards, and anything this produces is
//  importable by ESign, Feather, KravaSign and RyukSign itself, because they all
//  share this decoder.
//

import Foundation

public class ASEncrypt {
	public init() {}

	public func encrypt(_ sources: [String]) -> String? {
		Self.encrypt(sources: sources)
	}

	/// Encodes repository URLs into a single shareable ESign code.
	///
	/// Returns nil for an empty list, and ignores blank entries so a stray
	/// newline in the input cannot produce a code that decodes to nothing.
	static public func encrypt(sources: [String]) -> String? {
		let joined = sources
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.joined(separator: "\n")

		guard !joined.isEmpty, let bytes = joined.data(using: .utf8) else {
			return nil
		}

		var encrypted = Data(capacity: bytes.count)
		var keyIndex = 0

		for byte in bytes {
			encrypted.append(byte ^ esign_key[keyIndex])
			keyIndex = (keyIndex + 1) % esign_key_len
		}

		return "source[\(encrypted.base64EncodedString())]"
	}
}
