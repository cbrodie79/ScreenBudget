//
//  ScreenBudgetWidgetBundle.swift
//  ScreenBudgetWidget
//
//  Created by Colin Brodie on 9/11/26.
//

import WidgetKit
import SwiftUI

@main
struct ScreenBudgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScreenBudgetWidget()
        ScreenBudgetWidgetControl()
    }
}
