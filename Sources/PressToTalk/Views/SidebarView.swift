import SwiftUI

/// The dark rail down the left of the main window. Deliberately kept dark
/// against the light content area — it carries the app's identity and keeps
/// navigation visually separate from the page you are reading.
struct SidebarView: View {
    @Binding var selectedTab: Int
    let namespace: Namespace.ID
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            logo
                .padding(.horizontal, 16)
                .padding(.top, 44)      // clears the traffic lights
                .padding(.bottom, 24)

            SidebarButton(title: "Home", icon: "house.fill",
                          isSelected: selectedTab == 0, namespace: namespace) { onSelect(0) }
            SidebarButton(title: "History", icon: "clock.fill",
                          isSelected: selectedTab == 1, namespace: namespace) { onSelect(1) }
            SidebarButton(title: "Dictionary", icon: "character.book.closed.fill",
                          isSelected: selectedTab == 2, namespace: namespace) { onSelect(2) }
            SidebarButton(title: "Settings", icon: "gearshape.fill",
                          isSelected: selectedTab == 3, namespace: namespace) { onSelect(3) }

            Spacer()

            footer
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .frame(width: 216)
        .background(Theme.sidebarBackground)
        .environment(\.colorScheme, .dark)
    }

    private var logo: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.42, blue: 0.3),
                                     Color(red: 0.9, green: 0.25, blue: 0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text("TalkKey")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Theme.sidebarText)

            if LicenseManager.shared.isPro {
                Text("PRO")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.yellow)
                    .cornerRadius(4)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                NotificationCenter.default.post(name: .init("checkForUpdates"), object: nil)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                    Text("Check for Updates")
                        .font(.system(size: 12))
                }
                .foregroundColor(Theme.sidebarTextDim)
            }
            .buttonStyle(.plain)

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 11))
                .foregroundColor(Theme.sidebarTextFaint)
        }
    }
}

struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundColor(isSelected ? Theme.sidebarText
                                        : (isHovering ? Color.white.opacity(0.75) : Theme.sidebarTextDim))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.sidebarSelection)
                        .matchedGeometryEffect(id: "tab-pill", in: namespace)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.sidebarHover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
