//
//  StatusBarClockOverlay.swift
//  RyukSign
//
//  Surfaced port of MySign's StatusBarView: draws the user's clock in the
//  space the hidden system status bar gives up. The clock sits in the top-left
//  (matching where iOS draws it), tinted with the app's theme colour when the
//  user asks, and ignores touches so nothing underneath becomes un-tappable.
//

import SwiftUI

struct StatusBarClockOverlay: View {
	@ObservedObject private var _manager = StatusBarManager.shared

	var body: some View {
		GeometryReader { proxy in
			Group {
				if _manager.shouldShowClock {
					Text(_manager.timeString)
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(_manager.usesThemeColor ? Color.userTint : .primary)
						.fixedSize()
						.padding(.horizontal, 24)
						// Sit just below the system clock's zone: clear of the
						// Dynamic Island / notch on notched devices, near the
						// top edge on devices whose status bar simply hides.
						.padding(.top, max(proxy.safeAreaInsets.top, 6) + 3)
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
						.allowsHitTesting(false)
				}
			}
			.animation(.easeInOut(duration: 0.2), value: _manager.shouldShowClock)
			.animation(.easeInOut(duration: 0.2), value: _manager.timeString)
		}
		.ignoresSafeArea()
	}
}