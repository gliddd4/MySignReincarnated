//
//  FlowingTextView.swift
//  RyukSign
//
//  Text whose first line is indented and whose remaining lines are not, so an app
//  description can carry on from the line it started on and then run the full width
//  of the row underneath the icon and the download button.
//
//  The platform has done this since iOS 7 — `NSParagraphStyle.firstLineHeadIndent` for
//  the indent, and `NSTextContainer.exclusionPaths` when the text has to flow around a
//  shape rather than a single indent. SwiftUI exposes neither: `Text` cannot wrap
//  around anything, and paragraph styles are not part of its attribute scope, so they
//  are ignored in an `AttributedString`. Hence the bridge — the layout is Apple's, only
//  the way in is ours.
//

import SwiftUI
import UIKit

// MARK: - View

struct FlowingTextView: UIViewRepresentable {
	var text: String
	/// Point size. A plain value on purpose: resolving a text style here would be a
	/// UIKit call in a default argument, which does not run on the main actor.
	var fontSize: CGFloat = 15
	var color: UIColor = .secondaryLabel
	/// Indent for the first line only — the width the text has to clear before it can
	/// continue, normally the icon column plus the gap after it.
	var firstLineIndent: CGFloat = 0
	/// Regions every line has to flow around, not just the first. Empty for a plain
	/// hanging indent; this is the same lever that would let a description start on the
	/// line beside an icon rather than below it.
	var exclusions: [CGRect] = []

	// MARK: Body
	func makeUIView(context: Context) -> UITextView {
		let view = UITextView()
		view.isEditable = false
		view.isSelectable = false
		view.isScrollEnabled = false
		view.backgroundColor = .clear
		view.textContainerInset = .zero
		view.textContainer.lineFragmentPadding = 0
		view.setContentCompressionResistancePriority(.required, for: .vertical)
		view.setContentHuggingPriority(.required, for: .vertical)
		return view
	}

	func updateUIView(_ view: UITextView, context: Context) {
		_apply(to: view)
	}

	/// A non-scrolling text view has no intrinsic height until it is told how wide it
	/// has to be, so the row's height is settled here rather than left to the cell.
	func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
		guard let width = proposal.width, width > 0 else { return nil }
		_apply(to: uiView)
		let height = uiView.sizeThatFits(
			CGSize(width: width, height: .greatestFiniteMagnitude)
		).height
		return CGSize(width: width, height: ceil(height))
	}

	/// Layout and sizing must agree on one text container, so both go through here.
	private func _apply(to view: UITextView) {
		let paragraph = NSMutableParagraphStyle()
		paragraph.firstLineHeadIndent = firstLineIndent
		paragraph.lineBreakMode = .byWordWrapping

		view.attributedText = NSAttributedString(
			string: text,
			attributes: [
				.font: UIFont.systemFont(ofSize: fontSize),
				.foregroundColor: color,
				.paragraphStyle: paragraph
			]
		)
		view.textContainer.exclusionPaths = exclusions.map { UIBezierPath(rect: $0) }
	}
}
