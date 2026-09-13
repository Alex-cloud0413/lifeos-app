import SwiftUI

/// A compact, zero-padded date label; editing still uses the system calendar.
struct LifeDatePicker: View {
    let title: String
    @Binding var selection: Date
    var range: ClosedRange<Date> = Date.distantPast...Date.distantFuture
    var displayedComponents: DatePickerComponents = [.date, .hourAndMinute]
    @State private var presented = false
    init(_ title: String, selection: Binding<Date>, in range: ClosedRange<Date> = Date.distantPast...Date.distantFuture, displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.title = title; _selection = selection; self.range = range; self.displayedComponents = displayedComponents
    }
    init(_ title: String, selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(title, selection: selection, in: range.lowerBound...Date.distantFuture, displayedComponents: displayedComponents)
    }
    init(_ title: String, selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(title, selection: selection, in: Date.distantPast...range.upperBound, displayedComponents: displayedComponents)
    }
    private var label: String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: selection)
        let date = String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return displayedComponents.contains(.hourAndMinute) ? date + String(format: " · %02d:%02d", c.hour ?? 0, c.minute ?? 0) : date
    }
    var body: some View {
        #if os(macOS)
        LabeledContent(title) {
            Button { presented = true } label: {
                HStack(spacing: 8) { Text(label).monospacedDigit(); Image(systemName: "calendar").foregroundStyle(.secondary) }.padding(.horizontal, 8).padding(.vertical, 5)
            }.buttonStyle(.ink).background(Color.paperInset, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityLabel(title + " " + label)
                .popover(isPresented: $presented) {
                    VStack(spacing: 14) {
                        DatePicker(title, selection: $selection, in: range, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                        if displayedComponents.contains(.hourAndMinute) { DatePicker("时间", selection: $selection, in: range, displayedComponents: .hourAndMinute) }
                        Button("完成") { presented = false }.buttonStyle(.ink)
                    }.padding(18).frame(width: 300).daylineTheme()
                }
        }
        #else
        DatePicker(title, selection: $selection, in: range, displayedComponents: displayedComponents).datePickerStyle(.compact)
        #endif
    }
}
