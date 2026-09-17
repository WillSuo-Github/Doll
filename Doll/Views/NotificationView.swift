import SwiftUI
import Utils
import Monitor
import LaunchAtLogin

struct NotificationView: View {
    let icon: NSImage?
    let badgeText: String
    let onTap: () -> Void
    var body: some View {
        let iconSize: CGFloat = 20

        HStack(spacing: 8) {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .cornerRadius(4)
            }
            Text(badgeText)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor(calibratedWhite: 0.16, alpha: 0.96)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
