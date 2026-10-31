//
//  ScreenGaugeReportExtension.swift
//  ScreenGaugeReportExtension
//
//  Created by Colin Brodie on 9/7/26.
//

import DeviceActivity
import SwiftUI

@main
struct ScreenGaugeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // Create a report for each DeviceActivityReport.Context that your app supports.
        TotalActivityReport { configuration in
            TotalActivityView(configuration: configuration)
        }
        // Add more reports here...
    }
}
