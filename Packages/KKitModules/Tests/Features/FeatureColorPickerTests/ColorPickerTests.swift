import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureColorPicker

private let orange = RGBAColor(red: 1, green: 0.5, blue: 0)

private func near(_ lhs: RGBAColor?, _ rhs: RGBAColor, tolerance: Double = 0.003) -> Bool {
    guard let lhs else { return false }
    return abs(lhs.red - rhs.red) < tolerance
        && abs(lhs.green - rhs.green) < tolerance
        && abs(lhs.blue - rhs.blue) < tolerance
        && abs(lhs.alpha - rhs.alpha) < tolerance
}

struct ColorFormatterTests {
    @Test func formats() {
        #expect(ColorFormatter.string(orange, as: .rgb) == "rgb(255, 128, 0)")
        #expect(ColorFormatter.string(orange, as: .hsl) == "hsl(30, 100%, 50%)")
        #expect(ColorFormatter.string(orange, as: .css) == "rgb(255 128 0)")
        #expect(ColorFormatter.string(orange, as: .swiftUI) == "Color(red: 1, green: 0.5, blue: 0)")
        #expect(ColorFormatter.string(orange, as: .nsColor) == "NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)")
        #expect(ColorFormatter.string(orange, as: .hex) == "#FF8000")
        #expect(ColorFormatter.string(orange, as: .hex, lowercaseHex: true) == "#ff8000")
    }

    @Test func includesAlphaWhenTranslucent() {
        let clear = RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        #expect(ColorFormatter.string(clear, as: .rgb) == "rgba(0, 0, 255, 0.5)")
        #expect(ColorFormatter.string(clear, as: .css) == "rgb(0 0 255 / 50%)")
        #expect(ColorFormatter.string(clear, as: .hsl) == "hsla(240, 100%, 50%, 0.5)")
    }

    @Test func greysHaveNoHue() {
        let (hue, saturation, lightness) = ColorFormatter.hsl(RGBAColor(red: 0.5, green: 0.5, blue: 0.5))
        #expect(hue == 0)
        #expect(saturation == 0)
        #expect(abs(lightness - 0.5) < 0.0001)
    }

    @Test func trimsDecimals() {
        #expect(ColorFormatter.decimal(0.5, places: 3) == "0.5")
        #expect(ColorFormatter.decimal(1, places: 3) == "1")
        #expect(ColorFormatter.decimal(0.50196, places: 3) == "0.502")
    }
}

struct ColorParserTests {
    @Test func readsHex() {
        #expect(near(ColorParser.parse("#FF8000"), orange))
        #expect(near(ColorParser.parse("  #ff8000 "), orange))
        #expect(near(ColorParser.parse("0xFF8000"), orange))
        #expect(ColorParser.parse("#F80") == RGBAColor(hex: "#FF8800"))
        #expect(near(ColorParser.parse("#F808"), RGBAColor(red: 1, green: 136.0 / 255, blue: 0, alpha: 136.0 / 255)))
        #expect(near(ColorParser.parse("#FF800080"), RGBAColor(red: 1, green: 128.0 / 255, blue: 0, alpha: 128.0 / 255)))
        #expect(ColorParser.parse("#GG0000") == nil)
        #expect(ColorParser.parse("#FF80") != nil)
        #expect(ColorParser.parse("#FF800") == nil)
        #expect(ColorParser.hex("facade") != nil)
    }

    @Test func readsRGB() {
        let expected = RGBAColor(red: 1, green: 128.0 / 255, blue: 0)
        #expect(near(ColorParser.parse("rgb(255, 128, 0)"), expected))
        #expect(near(ColorParser.parse("RGB(255 128 0)"), expected))
        #expect(near(ColorParser.parse("rgba(255, 128, 0, 0.5)"), RGBAColor(red: 1, green: 128.0 / 255, blue: 0, alpha: 0.5)))
        #expect(near(ColorParser.parse("rgb(255 128 0 / 50%)"), RGBAColor(red: 1, green: 128.0 / 255, blue: 0, alpha: 0.5)))
        #expect(near(ColorParser.parse("rgb(100%, 50%, 0%)"), orange))
        #expect(ColorParser.parse("rgb(300, 0, 0)") == nil)
        #expect(ColorParser.parse("rgb(1, 2)") == nil)
        #expect(ColorParser.parse("rgb(1, 2, 3") == nil)
    }

    @Test func readsHSL() {
        #expect(near(ColorParser.parse("hsl(30, 100%, 50%)"), orange))
        #expect(near(ColorParser.parse("hsl(30deg 100% 50%)"), orange))
        #expect(near(ColorParser.parse("hsla(240, 100%, 50%, 0.5)"), RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.5)))
        #expect(near(ColorParser.parse("hsl(0.5turn 100% 50%)"), RGBAColor(red: 0, green: 1, blue: 1)))
        #expect(near(ColorParser.parse("hsl(-120, 100%, 50%)"), RGBAColor(red: 0, green: 0, blue: 1)))
        #expect(near(ColorParser.parse("hsl(0, 0%, 50%)"), RGBAColor(red: 0.5, green: 0.5, blue: 0.5)))
        #expect(ColorParser.parse("hsl(30, 150%, 50%)") == nil)
    }

    @Test func readsCode() {
        #expect(near(ColorParser.parse("Color(red: 1, green: 0.5, blue: 0)"), orange))
        #expect(near(ColorParser.parse("Color(red: 0, green: 0, blue: 1, opacity: 0.5)"), RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.5)))
        #expect(near(ColorParser.parse("NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)"), orange))
        #expect(ColorParser.parse("Color(red: 2, green: 0, blue: 0)") == nil)
    }

    @Test func ignoresOtherText() {
        #expect(ColorParser.parse("") == nil)
        #expect(ColorParser.parse("red") == nil)
        #expect(ColorParser.parse("facade") == nil)
        #expect(ColorParser.parse("rgb") == nil)
        #expect(ColorParser.parse("2 + 2") == nil)
    }

    /// Everything KKit copies can be read back.
    @Test func roundTripsEveryFormat() {
        let colors = [
            orange,
            RGBAColor(red: 0.2, green: 0.4, blue: 0.6),
            RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.5),
            RGBAColor(red: 1, green: 1, blue: 1),
        ]
        for color in colors {
            for format in ColorFormat.allCases {
                let text = ColorFormatter.string(color, as: format)
                // HSL rounds to whole percentages.
                let tolerance = format == .hsl ? 0.02 : 0.003
                #expect(near(ColorParser.parse(text), color, tolerance: tolerance), "\(text)")
            }
        }
    }
}

@MainActor
struct ColorPickerControllerTests {
    private func make() -> (TestEnvironment, ColorPickerController) {
        let environment = TestEnvironment()
        let context = environment.makeContext(for: ColorPickerFeature.manifest.id)
        return (environment, ColorPickerController(context: context))
    }

    @Test func picksCopiesAndShowsTheColour() async {
        let (environment, controller) = make()
        controller.sample = { orange }
        await controller.pick()
        #expect(environment.pasteboard.writes.last?.string == "#FF8000")
        #expect(controller.current == orange)
        #expect(environment.island.activity(ColorPickerController.pickedActivity) != nil)
        #expect(!controller.isPicking)
    }

    @Test func cancellingCopiesNothing() async {
        let (environment, controller) = make()
        controller.sample = { nil }
        await controller.pick()
        #expect(environment.pasteboard.writes.isEmpty)
        #expect(controller.history.isEmpty)
        #expect(environment.island.activityIDs.isEmpty)
    }

    @Test func copiesInTheChosenFormat() {
        let (environment, controller) = make()
        controller.settings[ColorPickerSettings.format] = .rgb
        controller.copy(RGBAColor(red: 0, green: 1, blue: 0))
        #expect(environment.pasteboard.writes.last?.string == "rgb(0, 255, 0)")
        controller.copy(orange, format: .hex)
        #expect(environment.pasteboard.writes.last?.string == "#FF8000")
        controller.settings[ColorPickerSettings.lowercaseHex] = true
        controller.copy(orange, format: .hex)
        #expect(environment.pasteboard.writes.last?.string == "#ff8000")
    }

    @Test func keepsRecentColoursNewestFirstWithoutRepeats() {
        let (environment, controller) = make()
        let red = RGBAColor(red: 1, green: 0, blue: 0)
        let blue = RGBAColor(red: 0, green: 0, blue: 1)
        controller.copy(red)
        controller.copy(blue)
        controller.copy(red)
        #expect(controller.history == [red, blue])
        #expect(controller.settings[ColorPickerSettings.history] == [red.hex, blue.hex])

        // A new controller (next launch) reads them back.
        let again = ColorPickerController(context: environment.makeContext(for: ColorPickerFeature.manifest.id))
        #expect(again.history == [red, blue])

        controller.remove(red)
        #expect(controller.history == [blue])
        controller.clearHistory()
        #expect(controller.history.isEmpty)
        #expect(controller.settings[ColorPickerSettings.history].isEmpty)
    }

    @Test func historyIsCapped() {
        let (_, controller) = make()
        for index in 0..<(ColorPickerSettings.maxHistory + 5) {
            controller.copy(RGBAColor(red: Double(index) / 255, green: 0, blue: 0), announce: false)
        }
        #expect(controller.history.count == ColorPickerSettings.maxHistory)
        #expect(controller.history.first == RGBAColor(red: Double(ColorPickerSettings.maxHistory + 4) / 255, green: 0, blue: 0))
    }

    @Test func quietCopiesAndTheIslandSettingSkipTheIsland() {
        let (environment, controller) = make()
        controller.copy(orange, announce: false)
        #expect(environment.island.activityIDs.isEmpty)
        controller.settings[ColorPickerSettings.showInIsland] = false
        controller.copy(orange)
        #expect(environment.island.activityIDs.isEmpty)
        #expect(environment.pasteboard.writes.count == 2)
    }
}

@MainActor
struct ColorProviderTests {
    private func make() -> (TestEnvironment, ColorPickerController, ColorProvider) {
        let environment = TestEnvironment()
        let controller = ColorPickerController(context: environment.makeContext(for: ColorPickerFeature.manifest.id))
        return (environment, controller, ColorProvider(controller: controller))
    }

    @Test func convertsATypedColourIntoEveryFormat() async throws {
        let (environment, controller, provider) = make()
        controller.settings[ColorPickerSettings.format] = .hsl
        let results = provider.search(SearchQuery(text: "rgb(255 128 0)"))
        #expect(results.count == ColorFormat.allCases.count)
        #expect(results.first?.title == "hsl(30, 100%, 50%)")
        #expect(results.map(\.subtitle).contains("SwiftUI"))
        #expect(results.first?.icon == .swatch(red: 1, green: 128.0 / 255, blue: 0, alpha: 1))
        let scores = results.map(\.score)
        #expect(scores == scores.sorted(by: >))
        let perform = try #require(results.first?.perform)
        try await perform()
        #expect(environment.pasteboard.writes.last?.string == "hsl(30, 100%, 50%)")
        #expect(controller.history.count == 1)
    }

    @Test func hashPrefixReadsHexAndListsRecentColours() {
        let (_, controller, provider) = make()
        #expect(provider.search(SearchQuery(text: "ff8000", isScoped: true)).first?.title == "#FF8000")
        #expect(provider.search(SearchQuery(text: "nonsense", isScoped: true)).isEmpty)

        controller.copy(orange, announce: false)
        let listed = provider.search(SearchQuery(text: "", isScoped: true))
        #expect(listed.first?.kind == .command(ColorPickerFeature.pickCommand, argument: nil))
        #expect(listed.count == 2)
        #expect(listed.last?.title == "#FF8000")
    }

    @Test func rootSearchIgnoresOrdinaryText() {
        let (_, _, provider) = make()
        #expect(provider.search(SearchQuery(text: "safari")).isEmpty)
        #expect(provider.search(SearchQuery(text: "facade")).isEmpty)
        #expect(provider.search(SearchQuery(text: "")).isEmpty)
    }
}

@MainActor
struct ColorPickerFeatureTests {
    private func make() -> (TestEnvironment, ColorPickerFeature) {
        let environment = TestEnvironment()
        return (environment, ColorPickerFeature(context: environment.makeContext(for: ColorPickerFeature.manifest.id)))
    }

    /// "color picker" (American spelling) found nothing before: the title is British.
    @Test func pickCommandIsFoundEitherSpelling() throws {
        let (_, feature) = make()
        let command = try #require(feature.commands.first { $0.id == ColorPickerFeature.pickCommand })
        let keywords = command.keywords + [ColorPickerFeature.manifest.name]
        for query in ["color picker", "colour picker", "pick color", "pick colour", "eyedropper", "color pick"] {
            #expect(FuzzyMatch.score(query, title: command.title, keywords: keywords) != nil, "\(query)")
        }
        #expect(command.defaultShortcut == Shortcut(keyCode: Shortcut.Key.p, modifiers: [.control, .option]))
    }

    @Test func commandIDsBelongToTheFeature() {
        let (_, feature) = make()
        for command in feature.commands {
            #expect(command.id.rawValue.hasPrefix("colorPicker."))
        }
    }

    @Test func islandPageFollowsItsSetting() async throws {
        let (environment, feature) = make()
        #expect(feature.islandPages.map(\.id) == [ColorPickerFeature.pageID])
        let show = try #require(feature.commands.first { $0.id == "colorPicker.showColors" })
        try await show.perform(CommandInvocation())
        #expect(environment.island.expansions.last?.page == ColorPickerFeature.pageID)

        feature.controller.settings[ColorPickerSettings.showIslandPage] = false
        #expect(feature.islandPages.isEmpty)
        try await show.perform(CommandInvocation())
        #expect(environment.floatingBar.shownQueries.last == "#")
    }
}
