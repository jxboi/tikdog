import SwiftUI
import TikDogCore

extension Color {
    static let dogOrange = Color(red: 1, green: 136/255, blue: 77/255)
    static let dogCream = Color(red: 250/255, green: 248/255, blue: 244/255)
    static let dogInk = Color(red: 33/255, green: 32/255, blue: 29/255)
    static let dogMuted = Color(red: 104/255, green: 101/255, blue: 95/255)
}
@MainActor enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func like() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight; self.design = design
    }
    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight, design: design)) }
}
extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, relativeTo: Font.TextStyle = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: relativeTo))
    }
}
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var dark = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(dark ? .white : Color.dogInk).background(dark ? Color.dogInk : Color.dogOrange, in: RoundedRectangle(cornerRadius: 18))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
struct DogAvatar: View {
    let dog: Dog
    var size: CGFloat = 48
    var body: some View {
        MediaImage(path: dog.displayAvatarPath ?? dog.avatarPath, contentMode: .fill)
            .frame(width: size, height: size).background(Color.dogOrange.opacity(0.2)).clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
            .accessibilityLabel("\(dog.name)'s profile photo")
    }
}
struct MediaImage: View {
    let path: String
    var contentMode: ContentMode = .fill
    var body: some View {
        Group {
            if path.hasPrefix("https://"), let url = URL(string: path) {
                AsyncImage(url: url) { image in image.resizable().aspectRatio(contentMode: contentMode) } placeholder: { placeholder }
            } else if let image = localImage {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else { placeholder }
        }.clipped()
    }
    private var localImage: UIImage? {
        if let url = URL(string: path), url.isFileURL { return UIImage(contentsOfFile: url.path) }
        if let url = Bundle.main.url(forResource: path, withExtension: nil) { return UIImage(contentsOfFile: url.path) }
        return UIImage(named: path)
    }
    private var placeholder: some View { Rectangle().fill(Color.dogOrange.opacity(0.15)).overlay { Image(systemName: "pawprint.fill").font(.title).foregroundStyle(Color.dogOrange) } }
}
extension Int {
    var compactCount: String { if self >= 1_000_000 { return String(format: "%.1fM", Double(self)/1_000_000).replacingOccurrences(of: ".0", with: "") }; if self >= 1000 { return String(format: "%.1fK", Double(self)/1000).replacingOccurrences(of: ".0", with: "") }; return String(self) }
}
struct EmptyState: View {
    let icon: String; let title: String; let message: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(Color.dogOrange).padding(22).background(Color.dogOrange.opacity(0.1), in: Circle())
            Text(title).font(.system(size: 23, weight: .bold, design: .rounded))
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 290)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
