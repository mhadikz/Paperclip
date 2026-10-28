import SwiftUI
import AppKit

/// Project links shown in About. Set a link to `nil` to hide its button.
enum ProjectLinks {
    static let repository: URL? = URL(string: "https://github.com/mhadikz/Paperclip")
    static let issues: URL? = URL(string: "https://github.com/mhadikz/Paperclip/issues")
    static let license = "MIT License"
    static let copyright = "© 2026 mhadikz"
}

struct AboutPreferencesView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: AppTheme.spaceL) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppTheme.spaceXS) {
                    Text("Paperclip")
                        .font(AppTheme.display)
                    Text(version)
                        .foregroundStyle(.secondary)
                        .font(AppTheme.body)
                    Text("A private clipboard history for your Mac, with an optional on-device memory layer. Text, images, files, pinboards and a desktop widget — all stored locally.")
                        .foregroundStyle(.secondary)
                        .font(AppTheme.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(AppTheme.spaceXL)

            VStack(alignment: .leading, spacing: AppTheme.spaceS) {
                principle("lock.shield", "Local only", "No account, no server, no analytics. Clipboard data never leaves this Mac.")
                principle("cpu", "On-device intelligence", "Apple Foundation Models run on your Mac when available; heuristics otherwise.")
                principle("chevron.left.forwardslash.chevron.right", "Open source", ProjectLinks.license)
            }
            .padding(.horizontal, AppTheme.spaceXL)

            Spacer()

            HStack(spacing: AppTheme.spaceS) {
                if let repository = ProjectLinks.repository {
                    Link("Source Code", destination: repository)
                }
                if let issues = ProjectLinks.issues {
                    Link("Report an Issue", destination: issues)
                }
                Button("Show Data Folder") { settingsViewModel.revealDataFolder() }
                    .buttonStyle(.plain)
            }
            .font(AppTheme.caption)
            .foregroundStyle(AppPalette.link)
            .padding(.bottom, AppTheme.spaceXS)

            Text(ProjectLinks.copyright)
                .font(AppTheme.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, AppTheme.spaceL)
        }
    }

    private func principle(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spaceS) {
            Image(systemName: symbol)
                .foregroundStyle(AppPalette.brand)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.calloutMedium)
                Text(detail)
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
