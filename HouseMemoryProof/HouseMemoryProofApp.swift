import SwiftUI

@main
struct HouseMemoryProofApp: App {
    var body: some Scene {
        WindowGroup { DeliveryProofView() }
    }
}

private struct DeliveryProofView: View {
    @State private var taps = 0
    @State private var showFraming = false

    private let navy = Color(red: 0.06, green: 0.10, blue: 0.19)
    private let mint = Color(red: 0.40, green: 0.92, blue: 0.72)

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
    }

    private var revision: String {
        Bundle.main.object(forInfoDictionaryKey: "ProofSourceRevision") as? String ?? "local"
    }

    var body: some View {
        ZStack {
            navy.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Label("HOUSE MEMORY", systemImage: "house")
                        .font(.caption.weight(.bold))
                        .tracking(3)
                        .foregroundStyle(mint)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hello from\nChatGPT.")
                            .font(.largeTitle.bold())
                        Text("A tiny native app. A real delivery test.")
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    VStack(spacing: 18) {
                        WallDrawing(showFraming: showFraming, accent: mint)
                            .frame(height: 180)
                            .accessibilityLabel(showFraming ? "Illustration of exposed framing" : "Illustration of a finished wall")
                        Toggle("Reveal the framing", isOn: $showFraming)
                            .tint(mint)
                        Text("Illustration only — no camera or house scan.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(22)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))

                    Button {
                        taps += 1
                    } label: {
                        HStack {
                            Text(taps == 0 ? "Tap to test" : "It works · \(taps)")
                            Spacer()
                            Image(systemName: taps == 0 ? "hand.tap" : "checkmark.circle.fill")
                        }
                        .font(.headline)
                        .padding(20)
                        .foregroundStyle(navy)
                        .background(mint, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("proofButton")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("VERSION 1.0 · BUILD \(build)")
                        Text("SOURCE \(revision)")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.55))
                    .textSelection(.enabled)
                }
                .padding(28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

private struct WallDrawing: View {
    let showFraming: Bool
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(showFraming ? Color.clear : Color.white.opacity(0.12))
                Path { path in
                    path.addRect(CGRect(x: 3, y: 3, width: width - 6, height: height - 6))
                    if showFraming {
                        for index in 1...5 {
                            let x = width * CGFloat(index) / 6
                            path.move(to: CGPoint(x: x, y: 3))
                            path.addLine(to: CGPoint(x: x, y: height - 3))
                        }
                    }
                }
                .stroke(showFraming ? accent : .white.opacity(0.35), lineWidth: 5)
                if showFraming {
                    Path { path in
                        path.move(to: CGPoint(x: width * 0.08, y: height * 0.7))
                        path.addLine(to: CGPoint(x: width * 0.78, y: height * 0.7))
                        path.addLine(to: CGPoint(x: width * 0.78, y: height * 0.28))
                    }
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                } else {
                    Image(systemName: "square.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                        .position(x: width * 0.78, y: height * 0.7)
                }
            }
        }
    }
}
