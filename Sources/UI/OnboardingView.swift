import SwiftUI

/// First-launch step-by-step "Get Started" guide to gterm's core functions.
/// Also reachable from the Settings tab. Calls `onDone` when finished or skipped.
/// Modeled on the runse guide (step dots, per-step page, Back/Next, Start).
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var currentStep = 0

    private let steps = GuideStep.steps
    private var step: GuideStep { steps[currentStep] }
    private var isLastStep: Bool { currentStep == steps.count - 1 }
    private let accent = Color(red: 0.18, green: 0.80, blue: 0.89)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(steps.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == currentStep ? accent : Color.secondary.opacity(0.25))
                            .frame(width: index == currentStep ? 26 : 8, height: 8)
                    }
                }
                .padding(.top, 18)
                .accessibilityLabel("Step \(currentStep + 1) of \(steps.count)")

                GuideStepPageView(step: step, stepNumber: currentStep + 1, stepCount: steps.count, accent: accent)
                    .id(currentStep)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: currentStep)

                Spacer(minLength: 0)
            }
            .navigationTitle("gterm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone).fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation { currentStep = max(0, currentStep - 1) }
                    } label: {
                        Label("Back", systemImage: "chevron.left").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentStep == 0)

                    Button {
                        if isLastStep {
                            onDone()
                        } else {
                            withAnimation { currentStep += 1 }
                        }
                    } label: {
                        Label(isLastStep ? "Start" : "Next", systemImage: isLastStep ? "checkmark" : "chevron.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.bar)
            }
        }
    }
}

private struct GuideStep {
    let title: String
    let detail: String
    let systemImage: String
    let example: String

    static let steps: [GuideStep] = [
        GuideStep(
            title: "Add a host",
            detail: "Open the Hosts tab and tap + to add an SSH server — host, port, and username. Save the password to the Keychain, or leave it blank to be asked each time.",
            systemImage: "server.rack",
            example: "gterm connects straight to your servers over SSH — nothing routes through a third party."
        ),
        GuideStep(
            title: "Bring your keys",
            detail: "In the Keys tab, import an Ed25519 or ECDSA private key from a file or pasted text. Then pick which keys a host should try for public-key auth.",
            systemImage: "key.fill",
            example: "Keys are stored in the device Keychain — device-only, never synced to iCloud."
        ),
        GuideStep(
            title: "A real terminal",
            detail: "Tap a host to connect. You get Ghostty's GPU-rendered terminal with full xterm/VT emulation, plus an accessory bar for the keys iOS forgets: Esc, Ctrl, Alt, Tab, arrows.",
            systemImage: "apple.terminal.fill",
            example: "Pinch to resize the font, swipe with one finger to scroll, and press-and-hold to select & copy."
        ),
        GuideStep(
            title: "Ask the AI",
            detail: "Tap the sparkles button in a session and describe what you want. The AI proposes a command and shows it for review before it runs. Configure your provider in the AI tab.",
            systemImage: "sparkles",
            example: "Bring your own API key — it's stored masked in the Keychain and sent only to the provider you choose."
        ),
        GuideStep(
            title: "Forward ports & browse",
            detail: "Forward a local port over SSH to a service on (or reachable from) your server, then open it in the built-in browser. Tap a URL in the terminal to open it there too.",
            systemImage: "arrow.left.arrow.right",
            example: "Handy for a web dashboard or dev server running on a remote box."
        ),
        GuideStep(
            title: "Make it yours",
            detail: "Open the Settings tab to revisit this guide anytime, check the app version, or read the privacy policy.",
            systemImage: "gearshape",
            example: "You can reopen this guide later from Settings → Get Started Guide."
        ),
    ]
}

private struct GuideStepPageView: View {
    let step: GuideStep
    let stepNumber: Int
    let stepCount: Int
    let accent: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    Circle().fill(accent.opacity(0.14))
                    Image(systemName: step.systemImage)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 92, height: 92)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Step \(stepNumber) of \(stepCount)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(step.title)
                        .font(.largeTitle.bold())
                    Text(step.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(step.example)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
