import Foundation
import KKitCore
import Testing

struct FuzzyMatchTests {
    @Test func ranksTheKindsOfMatch() throws {
        let exact = try #require(FuzzyMatch.score("safari", in: "Safari"))
        let prefix = try #require(FuzzyMatch.score("saf", in: "Safari"))
        let word = try #require(FuzzyMatch.score("shift", in: "Night Shift"))
        let words = try #require(FuzzyMatch.score("sys set", in: "System Settings"))
        let initials = try #require(FuzzyMatch.score("ns", in: "Night Shift"))
        let contains = try #require(FuzzyMatch.score("ari", in: "Safari"))
        let letters = try #require(FuzzyMatch.score("sfr", in: "Safari"))
        #expect(exact == 1)
        #expect(prefix > word)
        #expect(word > words)
        #expect(words > initials)
        #expect(initials > contains)
        #expect(contains > letters)
        #expect(FuzzyMatch.score("xyz", in: "Safari") == nil)
        #expect(FuzzyMatch.score("", in: "Safari") == nil)
    }

    @Test func ignoresCaseAccentsAndSpacing() {
        #expect(FuzzyMatch.score("CAFE", in: "Café") == 1)
        #expect(FuzzyMatch.score("night   shift", in: "Night Shift") == 1)
        #expect(FuzzyMatch.normalize("  Héllo   World ") == "hello world")
    }

    @Test func keywordsCountALittleLess() throws {
        let title = try #require(FuzzyMatch.score("lock", title: "Lock Screen"))
        let keyword = try #require(FuzzyMatch.score("lock", title: "Sleep Display", keywords: ["lock"]))
        #expect(title > keyword)
        #expect(keyword == 0.85)
    }
}

struct CommandArgumentParserTests {
    @Test func parsesPercentages() {
        #expect(CommandArgumentParser.parsePercent("30") == 30)
        #expect(CommandArgumentParser.parsePercent("150 %") == 150)
        #expect(CommandArgumentParser.parsePercent("12.5%") == 12.5)
        #expect(CommandArgumentParser.parsePercent("-5") == nil)
        #expect(CommandArgumentParser.parsePercent("2000") == nil)
        #expect(CommandArgumentParser.parsePercent("abc") == nil)
    }

    @Test func parsesDurations() {
        #expect(CommandArgumentParser.parseDuration("25m") == .seconds(1500))
        #expect(CommandArgumentParser.parseDuration("1h30m") == .seconds(5400))
        #expect(CommandArgumentParser.parseDuration("1h 30") == .seconds(5400))
        #expect(CommandArgumentParser.parseDuration("90s") == .seconds(90))
        #expect(CommandArgumentParser.parseDuration("1.5 hours") == .seconds(5400))
        #expect(CommandArgumentParser.parseDuration("2 days") == .seconds(172_800))
        #expect(CommandArgumentParser.parseDuration("45") == .seconds(2700))
        #expect(CommandArgumentParser.parseDuration("0m") == nil)
        #expect(CommandArgumentParser.parseDuration("soon") == nil)
    }

    @Test func matchesChoicesAndText() {
        let choices = CommandParameter.choice(["Left Half", "Right Half", "Maximize"])
        #expect(CommandArgumentParser.parse("max", for: choices) == .choice("Maximize"))
        #expect(CommandArgumentParser.parse("right half", for: choices) == .choice("Right Half"))
        #expect(CommandArgumentParser.parse("l", for: choices) == .choice("Left Half"))
        #expect(CommandArgumentParser.parse("half", for: choices) == nil)
        #expect(CommandArgumentParser.parse("  tea ", for: .text(placeholder: "")) == .text("tea"))
        #expect(CommandArgumentParser.parse("   ", for: .text(placeholder: "")) == nil)
    }

    @Test func displaysArguments() {
        #expect(CommandArgumentParser.display(.percent(150)) == "150%")
        #expect(CommandArgumentParser.display(.duration(.seconds(5400))) == "1h 30m")
        #expect(CommandArgumentParser.display(.text("tea")) == "“tea”")
        #expect(CommandArgumentParser.formatDuration(.seconds(30)) == "30s")
    }
}

struct KKitLinkTests {
    @Test func parsesRunLinks() {
        #expect(KKitLink(URL(string: "kkit://run/nightShift.setIntensity?value=150")!) == .run("nightShift.setIntensity", value: "150"))
        #expect(KKitLink(URL(string: "kkit://run?command=timer.start&arg=25m")!) == .run("timer.start", value: "25m"))
        #expect(KKitLink(URL(string: "KKIT://run/power.toggleAwake")!) == .run("power.toggleAwake", value: nil))
        #expect(KKitLink(URL(string: "kkit://run/")!) == nil)
        #expect(KKitLink(URL(string: "https://run/timer.start")!) == nil)
    }

    @Test func parsesSearchLinks() {
        #expect(KKitLink(URL(string: "kkit://search?q=night%20shift")!) == .search("night shift"))
        #expect(KKitLink(URL(string: "kkit://search")!) == .search(nil))
    }

    @Test func roundTrips() {
        let links: [KKitLink] = [.run("timer.start", value: "1h 30m"), .search("f report"), .run("app.openSettings", value: nil)]
        for link in links {
            #expect(KKitLink(link.url) == link)
        }
    }
}
