//
//  AppVersionInfo.swift
//  RyukSign
//
//  Created by Nagata Asami on 27/7/25.
//

import SwiftUI

struct AppVersionInfo: View {
    let version: String
    let date: Date?
    let description: String

    /// Browse settings (Settings → Browse).
    @AppStorage(BrowsePreferences.usesFullYearFormat) private var _usesFullYearDates = false

    /// "1 year ago" rather than "1 yr. ago". MySign exposed this as one of its
    /// Browse switches, and the abbreviated form is what people wanted shorter.
    private var _relativeStyle: Date.RelativeFormatStyle {
        Date.RelativeFormatStyle(
            presentation: .named,
            unitsStyle: _usesFullYearDates ? .wide : .abbreviated
        )
    }
    
    init(
        version: String,
        date: Date? = nil,
        description: String
    ) {
        self.version = version
        self.date = date
        self.description = description
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if let date {
                    Text(date.formatted(_relativeStyle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            
            ExpandableText(text: description, lineLimit: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
} 
