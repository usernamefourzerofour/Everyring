import SwiftUI

struct SettingsView: View {
    @Environment(RingsModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    static let sourceURL = URL(string: "https://github.com/usernamefourzerofour/Everyring")!
    static let privacyURL = URL(string: "https://usernamefourzerofour.github.io/Everyring/privacy")!
    static let supportURL = URL(string: "https://usernamefourzerofour.github.io/Everyring/")!

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("First day of week", selection: $model.library.weekStart) {
                    ForEach(WeekStart.allCases, id: \.self) { start in
                        Text(title(for: start)).tag(start)
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Text("Used by rings that reset every week.")
            }

            Section {
                NavigationLink("Heart Minutes") { HeartMinuteSettingsView() }
            } header: {
                Text("Rings")
            } footer: {
                Text("How Heart Minutes rings count heart rate: zones, max heart rate and when background heart rate counts.")
            }

            Section {
                Text("Everyring only reads from Apple Health and never writes to it. To change what it can read, open the Health app, tap your profile picture, then Apps → Everyring.")
                    .font(.callout)
            } header: {
                Text("Apple Health")
            }

            Section {
                LabeledContent("Version", value: Self.version)
                Link("Support", destination: Self.supportURL)
                Link("Privacy Policy", destination: Self.privacyURL)
                Link("Source Code", destination: Self.sourceURL)
            } header: {
                Text("About")
            } footer: {
                Text("Everyring is free and open source. No ads, no account, no tracking: your data stays on your device.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", role: .confirm) { dismiss() }
            }
        }
    }

    private func title(for start: WeekStart) -> String {
        guard start == .system else { return start.title }
        let calendar = Calendar.current
        let day = calendar.standaloneWeekdaySymbols[calendar.firstWeekday - 1]
        return String(localized: "Region default (\(day))")
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
