//
//  VariedTabbarView.swift
//  RyukSign
//
//  Created by samara on 11.04.2025.
//
import SwiftUI

struct VariedTabbarView: View {
	@AppStorage("Feather.tabBarStyle") private var _style: TabBarStyle = .system

	init() {}
	
	var body: some View {
		if _style == .glassSwitcher {
			GlassTabSwitcherView()
		} else if #available(iOS 18, *) {
			ExtendedTabbarView()
		} else {
			TabbarView()
		}
	}
}
