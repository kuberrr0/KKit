import Foundation

/// Why an expression has no answer.
enum MathError: Error, Equatable {
    case syntax
    case unknownName(String)
    case wrongArguments(String)
    /// Square root of a negative number, log of zero, a result too large.
    case domain
}

/// A small, safe expression evaluator: no `NSExpression` (which raises Objective-C
/// exceptions on bad input), no variables, no loops. DESIGN.md §3.17.
///
/// - Operators: `+ - * / × ÷ ^ **`, `mod` and `%` between numbers, `!` (factorial),
///   `°` (degrees to radians), implicit multiplication (`2pi`, `3(4+5)`), `x` between
///   numbers (`3 x 4`).
/// - Percentages: `50%` is 0.5; `200 + 10%` is 220; `15% of 80` is 12.
/// - Numbers: `1.5`, `2e3`, `1,000` (thousands), `0xff`, `0b1010`, `0o17`.
/// - Functions: sqrt cbrt abs sin cos tan asin acos atan sinh cosh tanh ln log log2
///   log10 exp floor ceil round min max, with or without parentheses (`sqrt 2`).
/// - Constants: pi π e tau τ phi φ.
struct MathExpression {
    /// The answer.
    let value: Double
    /// Something was computed: an operator, a function, a constant or a hex/binary
    /// literal. A bare number isn't worth showing as an answer in root search.
    let isCalculation: Bool

    static func evaluate(_ text: String) throws -> MathExpression {
        let tokens = try MathTokenizer.tokenize(text)
        guard !tokens.isEmpty else { throw MathError.syntax }
        var parser = MathParser(tokens: tokens)
        let value = try parser.parse()
        guard value.isFinite else { throw MathError.domain }
        let hasRadix = tokens.contains { token in
            if case .number(_, let radix) = token { return radix != 10 }
            return false
        }
        return MathExpression(value: value, isCalculation: parser.didCalculate || hasRadix)
    }

    /// The value, or `nil` if `text` isn't a valid expression.
    static func value(of text: String) -> Double? {
        try? evaluate(text).value
    }
}

enum MathToken: Equatable {
    case number(Double, radix: Int)
    case name(String)
    case op(Character)
    case open
    case close
    case comma
    case percent
    case bang
    case degree
}

enum MathTokenizer {
    static let functionNames: Set<String> = [
        "sqrt", "cbrt", "abs", "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh",
        "tanh", "ln", "log", "log2", "log10", "exp", "floor", "ceil", "round", "min", "max",
    ]

    static func tokenize(_ text: String) throws -> [MathToken] {
        let chars = Array(text)
        var tokens: [MathToken] = []
        var index = 0
        var depth = 0

        func previousEndsValue() -> Bool {
            switch tokens.last {
            case .number, .close, .percent, .bang, .degree: true
            case .name(let name): !functionNames.contains(name) && name != "mod" && name != "of"
            default: false
            }
        }

        while index < chars.count {
            let char = chars[index]
            if char.isWhitespace {
                index += 1
                continue
            }
            // Numbers
            if char.isASCII, char.isNumber || (char == "." && index + 1 < chars.count && chars[index + 1].isNumber) {
                let (value, radix, next) = try readNumber(chars, from: index)
                tokens.append(.number(value, radix: radix))
                index = next
                continue
            }
            // Names: letters, then digits only if that makes a function name (log2).
            if char.isLetter || "πτφ".contains(char) {
                var end = index
                while end < chars.count, chars[end].isLetter || "πτφ".contains(chars[end]) {
                    end += 1
                }
                var name = String(chars[index..<end]).lowercased()
                var digitsEnd = end
                while digitsEnd < chars.count, chars[digitsEnd].isASCII, chars[digitsEnd].isNumber {
                    digitsEnd += 1
                }
                if digitsEnd > end, functionNames.contains(name + String(chars[end..<digitsEnd])) {
                    name += String(chars[end..<digitsEnd])
                    end = digitsEnd
                }
                if name == "x", previousEndsValue() {
                    tokens.append(.op("*"))
                } else {
                    tokens.append(.name(name))
                }
                index = end
                continue
            }
            switch char {
            case "+":
                tokens.append(.op("+"))
            case "-", "−", "–":
                tokens.append(.op("-"))
            case "*":
                if index + 1 < chars.count, chars[index + 1] == "*" {
                    tokens.append(.op("^"))
                    index += 1
                } else {
                    tokens.append(.op("*"))
                }
            case "×", "·", "⋅":
                tokens.append(.op("*"))
            case "/", "÷":
                tokens.append(.op("/"))
            case "^":
                tokens.append(.op("^"))
            case "(", "[":
                depth += 1
                tokens.append(.open)
            case ")", "]":
                depth -= 1
                tokens.append(.close)
            case ",":
                // "1,000" outside parentheses is a thousands separator.
                if depth <= 0, case .number = tokens.last, isThousandsGroup(chars, at: index + 1) {
                    let (value, _, next) = try readNumber(chars, from: index + 1)
                    if case .number(let before, _) = tokens.removeLast() {
                        let digits = next - index - 1
                        tokens.append(.number(before * pow(10, Double(digits)) + value, radix: 10))
                    }
                    index = next
                    continue
                }
                tokens.append(.comma)
            case "%":
                tokens.append(.percent)
            case "!":
                tokens.append(.bang)
            case "°":
                tokens.append(.degree)
            case "=":
                // A trailing "=" ("2+2=") is harmless.
                guard chars[(index + 1)...].allSatisfy(\.isWhitespace) else { throw MathError.syntax }
            default:
                throw MathError.syntax
            }
            index += 1
        }
        return tokens
    }

    /// Exactly three digits, then the end, another group or anything but a digit or ".".
    private static func isThousandsGroup(_ chars: [Character], at start: Int) -> Bool {
        guard start + 3 <= chars.count else { return false }
        guard chars[start..<(start + 3)].allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        let after = start + 3
        return after == chars.count || !(chars[after].isNumber || chars[after] == ".")
    }

    private static func readNumber(_ chars: [Character], from start: Int) throws -> (Double, Int, Int) {
        var index = start
        if chars[index] == "0", index + 1 < chars.count {
            let marker = chars[index + 1].lowercased()
            let radix: Int? = marker == "x" ? 16 : marker == "b" ? 2 : marker == "o" ? 8 : nil
            if let radix {
                var end = index + 2
                while end < chars.count, chars[end].isHexDigit {
                    end += 1
                }
                let digits = String(chars[(index + 2)..<end])
                guard !digits.isEmpty, let value = Int(digits, radix: radix) else { throw MathError.syntax }
                return (Double(value), radix, end)
            }
        }
        while index < chars.count, chars[index].isASCII, chars[index].isNumber {
            index += 1
        }
        if index < chars.count, chars[index] == "." {
            index += 1
            while index < chars.count, chars[index].isASCII, chars[index].isNumber {
                index += 1
            }
        }
        // An exponent only when digits follow, so "2e" stays 2 × e.
        if index < chars.count, chars[index] == "e" || chars[index] == "E" {
            var probe = index + 1
            if probe < chars.count, chars[probe] == "+" || chars[probe] == "-" {
                probe += 1
            }
            if probe < chars.count, chars[probe].isASCII, chars[probe].isNumber {
                index = probe
                while index < chars.count, chars[index].isASCII, chars[index].isNumber {
                    index += 1
                }
            }
        }
        guard let value = Double(String(chars[start..<index])) else { throw MathError.syntax }
        return (value, 10, index)
    }
}

/// Recursive descent, lowest precedence first:
/// sum → product → unary → power → postfix → primary.
struct MathParser {
    private struct Value {
        var number: Double
        /// Written as a percentage ("10%"), for `x + 10%` and `10% of x`.
        var isPercent = false
    }

    private let tokens: [MathToken]
    private var position = 0
    private(set) var didCalculate = false

    init(tokens: [MathToken]) {
        self.tokens = tokens
    }

    mutating func parse() throws -> Double {
        let value = try parseSum()
        guard position == tokens.count else { throw MathError.syntax }
        return value.number
    }

    private var current: MathToken? {
        position < tokens.count ? tokens[position] : nil
    }

    private var next: MathToken? {
        position + 1 < tokens.count ? tokens[position + 1] : nil
    }

    private mutating func parseSum() throws -> Value {
        var left = try parseProduct()
        while case .op(let op) = current, op == "+" || op == "-" {
            position += 1
            let right = try parseProduct()
            didCalculate = true
            let sign: Double = op == "+" ? 1 : -1
            if right.isPercent, !left.isPercent {
                left = Value(number: left.number * (1 + sign * right.number))
            } else {
                left = Value(number: left.number + sign * right.number)
            }
        }
        return left
    }

    private mutating func parseProduct() throws -> Value {
        var left = try parseUnary()
        while let token = current {
            switch token {
            case .op("*"):
                position += 1
                let right = try parseUnary()
                left = Value(number: left.number * right.number)
            case .op("/"):
                position += 1
                let divisor = try parseUnary().number
                guard divisor != 0 else { throw MathError.domain }
                left = Value(number: left.number / divisor)
            case .percent, .name("mod"):
                position += 1
                let divisor = try parseUnary().number
                guard divisor != 0 else { throw MathError.domain }
                left = Value(number: fmod(left.number, divisor))
            case .name("of") where left.isPercent:
                position += 1
                let whole = try parseUnary()
                left = Value(number: left.number * whole.number)
            case .name, .open:
                // Implicit multiplication: 2pi, 3(4+5), 2 sqrt 9.
                let factor = try parsePower()
                left = Value(number: left.number * factor.number)
            default:
                return left
            }
            didCalculate = true
        }
        return left
    }

    private mutating func parseUnary() throws -> Value {
        if case .op(let op) = current, op == "-" || op == "+" {
            position += 1
            let operand = try parseUnary()
            if op == "-" {
                didCalculate = true
                return Value(number: -operand.number, isPercent: operand.isPercent)
            }
            return operand
        }
        return try parsePower()
    }

    private mutating func parsePower() throws -> Value {
        let base = try parsePostfix()
        guard case .op("^") = current else { return base }
        position += 1
        let exponent = try parseUnary()
        didCalculate = true
        return Value(number: pow(base.number, exponent.number))
    }

    private mutating func parsePostfix() throws -> Value {
        var value = try parsePrimary()
        while let token = current {
            switch token {
            case .bang:
                position += 1
                value = Value(number: try Self.factorial(value.number))
            case .degree:
                position += 1
                value = Value(number: value.number * .pi / 180)
            case .percent where !percentIsModulo:
                position += 1
                value = Value(number: value.number / 100, isPercent: true)
            default:
                return value
            }
            didCalculate = true
        }
        return value
    }

    /// `%` followed by a number or a bracket is modulo (`10 % 3`), otherwise percent.
    private var percentIsModulo: Bool {
        switch next {
        case .number, .open: true
        case .name(let name): name != "of" && name != "mod"
        default: false
        }
    }

    private mutating func parsePrimary() throws -> Value {
        guard let token = current else { throw MathError.syntax }
        position += 1
        switch token {
        case .number(let number, _):
            return Value(number: number)
        case .open:
            let inner = try parseSum()
            if case .close = current {
                position += 1
            } else if current != nil {
                throw MathError.syntax
            }
            // A missing ")" at the end is forgiven: "sqrt(2".
            return inner
        case .name(let name):
            if let constant = Self.constants[name] {
                didCalculate = true
                return Value(number: constant)
            }
            guard MathTokenizer.functionNames.contains(name) else { throw MathError.unknownName(name) }
            let arguments: [Double]
            if case .open = current {
                position += 1
                arguments = try parseArguments()
            } else {
                arguments = [try parsePower().number]
            }
            didCalculate = true
            return Value(number: try Self.apply(name, arguments))
        default:
            throw MathError.syntax
        }
    }

    private mutating func parseArguments() throws -> [Double] {
        var arguments: [Double] = []
        if case .close = current {
            position += 1
            return arguments
        }
        while true {
            arguments.append(try parseSum().number)
            switch current {
            case .comma:
                position += 1
            case .close:
                position += 1
                return arguments
            case nil:
                return arguments
            default:
                throw MathError.syntax
            }
        }
    }

    static let constants: [String: Double] = [
        "pi": .pi, "π": .pi,
        "e": M_E,
        "tau": 2 * .pi, "τ": 2 * .pi,
        "phi": (1 + 5.0.squareRoot()) / 2, "φ": (1 + 5.0.squareRoot()) / 2,
    ]

    static func apply(_ name: String, _ arguments: [Double]) throws -> Double {
        if name == "min" || name == "max" {
            guard !arguments.isEmpty else { throw MathError.wrongArguments(name) }
            return name == "min" ? arguments.min()! : arguments.max()!
        }
        if name == "log", arguments.count == 2 {
            guard arguments[0] > 0, arguments[1] > 0, arguments[1] != 1 else { throw MathError.domain }
            return log(arguments[0]) / log(arguments[1])
        }
        guard arguments.count == 1 else { throw MathError.wrongArguments(name) }
        let x = arguments[0]
        switch name {
        case "sqrt":
            guard x >= 0 else { throw MathError.domain }
            return x.squareRoot()
        case "cbrt": return cbrt(x)
        case "abs": return Swift.abs(x)
        case "sin": return sin(x)
        case "cos": return cos(x)
        case "tan": return tan(x)
        case "asin", "acos":
            guard (-1...1).contains(x) else { throw MathError.domain }
            return name == "asin" ? asin(x) : acos(x)
        case "atan": return atan(x)
        case "sinh": return sinh(x)
        case "cosh": return cosh(x)
        case "tanh": return tanh(x)
        case "ln", "log", "log2", "log10":
            guard x > 0 else { throw MathError.domain }
            switch name {
            case "ln": return log(x)
            case "log2": return log2(x)
            default: return log10(x)
            }
        case "exp": return exp(x)
        case "floor": return x.rounded(.down)
        case "ceil": return x.rounded(.up)
        case "round": return x.rounded()
        default: throw MathError.unknownName(name)
        }
    }

    static func factorial(_ x: Double) throws -> Double {
        guard x >= 0, x <= 170 else { throw MathError.domain }
        if x == x.rounded() {
            return (0..<Int(x)).reduce(1.0) { $0 * Double($1 + 1) }
        }
        return tgamma(x + 1)
    }
}
