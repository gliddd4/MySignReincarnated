//
//  HoldToConfirm.swift
//  RyukSign
//
//  Ported from MySign (mysignipasigner)'s HoldAndReleaseButton.
//
//  Press-and-hold to confirm. Used on destructive or irreversible actions
//  (signing, installing, deleting) so a stray tap can't kick one off.
//

import SwiftUI

struct HoldToConfirm<Content: View>: View {
	/// How long the press must be held.
	var duration: Double = 1.1
	var isDisabled: Bool = false
	/// Tint of the fill that sweeps across while holding.
	var fill: Color = .white.opacity(0.22)
	var onComplete: () -> Void
	@ViewBuilder var content: Content

	@State private var _progress: CGFloat = 0
	@State private var _isHolding = false

	var body: some View {
		content
			.overlay {
				if _isHolding {
					GeometryReader { geometry in
						Rectangle()
							.fill(fill)
							.frame(width: geometry.size.width * _progress)
					}
					.allowsHitTesting(false)
				}
			}
			// Without this the gesture only registers on the label's drawn pixels.
			.contentShape(Rectangle())
			.onLongPressGesture(
				minimumDuration: duration,
				pressing: { pressing in
					if pressing {
						_begin()
					} else {
						_cancel()
					}
				},
				perform: {
					// The hold finished: snap the fill back before running the action.
					_cancel()
					onComplete()
				}
			)
			.disabled(isDisabled)
			.opacity(isDisabled ? 0.5 : 1)
	}

	private func _begin() {
		guard !isDisabled else { return }
		_isHolding = true
		FeedbackManager.shared.tap()
		withAnimation(.linear(duration: duration)) {
			_progress = 1
		}
	}

	private func _cancel() {
		// Release before the timer finished — unwind without firing the action.
		withAnimation(.easeOut(duration: 0.2)) {
			_progress = 0
		}
		_isHolding = false
	}
}
