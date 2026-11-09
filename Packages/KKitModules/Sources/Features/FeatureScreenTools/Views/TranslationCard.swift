import KKitUI
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// What the translation card shows.
@MainActor
@Observable
final class TranslationModel {
    let source: String
    var target: String

    private(set) var result: String?
    private(set) var errorMessage: String?
    private(set) var isWorking = false

    @ObservationIgnored var onTargetChange: (@MainActor (String) -> Void)?

    init(source: String, target: String) {
        self.source = source
        self.target = target
    }

    func begin() {
        isWorking = true
        result = nil
        errorMessage = nil
    }

    func finish(_ text: String) {
        isWorking = false
        result = text
    }

    func fail(_ message: String) {
        isWorking = false
        errorMessage = message
    }
}

/// A small floating card: the source text, the translation, a language menu and Copy.
struct TranslationCard: View {
    static let size = CGSize(width: 380, height: 250)

    @Bindable var model: TranslationModel
    let copy: @MainActor (String) -> Void
    let close: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            HStack(spacing: KKSpacing.s) {
                Image(systemName: "translate")
                    .foregroundStyle(.secondary)
                Picker(String(localized: "Translate into"), selection: $model.target) {
                    ForEach(TranslationLanguage.common) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(Text("Close"))
            }
            ScrollView {
                Text(model.source)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 56)
            Divider()
            ScrollView {
                Group {
                    if let result = model.result {
                        Text(result)
                            .textSelection(.enabled)
                    } else if let message = model.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        HStack(spacing: KKSpacing.s) {
                            ProgressView().controlSize(.small)
                            Text("Translating…").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("On this Mac")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(String(localized: "Copy")) {
                    if let result = model.result { copy(result) }
                }
                .disabled(model.result == nil)
            }
        }
        .padding(KKSpacing.m)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: KKRadius.panel))
        .modifier(TranslationRunner(model: model))
        .onChange(of: model.target) {
            model.onTargetChange?(model.target)
        }
    }
}

/// Runs the system translation (macOS 15) whenever the card appears or the target changes.
private struct TranslationRunner: ViewModifier {
    let model: TranslationModel

    @ViewBuilder
    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(macOS 15, *) {
            content.modifier(SystemTranslation(model: model))
        } else {
            unsupported(content)
        }
        #else
        unsupported(content)
        #endif
    }

    private func unsupported(_ content: Content) -> some View {
        content.onAppear {
            model.fail(String(localized: "Translation needs macOS 15 or later."))
        }
    }
}

#if canImport(Translation)
@available(macOS 15, *)
private struct SystemTranslation: ViewModifier {
    let model: TranslationModel
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        let model = model
        let text = model.source
        return content
            .translationTask(configuration) { @Sendable session in
                await SystemTranslation.translate(text, with: session, into: model)
            }
            .onAppear { configure() }
            .onChange(of: model.target) { configure() }
    }

    private func configure() {
        model.begin()
        // No source: the framework detects it.
        configuration = TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: model.target))
    }

    nonisolated private static func translate(_ text: String, with session: TranslationSession, into model: TranslationModel) async {
        do {
            let response = try await session.translate(text)
            let translated = response.targetText
            await model.finish(translated)
        } catch {
            let message = error.localizedDescription
            await model.fail(message)
        }
    }
}
#endif
