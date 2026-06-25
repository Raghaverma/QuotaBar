import SwiftUI

/// A System-Settings-style row label: a colored SF Symbol chip followed by a title and
/// an optional secondary subtitle. Designed to sit inside a grouped `Form` as the
/// `label:` of a `Picker`, `Toggle`, etc., so the control aligns on the trailing edge.
struct SettingRowLabel: View {
    let icon: String
    var color: Color = .gray
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
