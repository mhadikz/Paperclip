import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem { Label("General", systemImage: "gearshape") }

            AIPreferencesView()
                .tabItem { Label("AI Memory", systemImage: "brain.head.profile") }

            IgnoredAppsPreferencesView()
                .tabItem { Label("Ignored Apps", systemImage: "eye.slash") }

            ClipsManagementPreferencesView()
                .tabItem { Label("Clips", systemImage: "doc.on.clipboard") }

            AboutPreferencesView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 520, minHeight: 480)
        .appWindowFill()
        .appWindowContainer()
        .toggleStyle(AppSwitchToggleStyle())
        .appBrandChrome()
    }
}
