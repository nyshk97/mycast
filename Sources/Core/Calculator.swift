import Foundation

/// ルート検索に打った式を計算する（Raycast の Calculator 相当）。
///
/// 受け付けるのは `+ - * / ^ %`（`×` `÷` も）・括弧・小数・数字の中の `,`（桁区切り）だけ。
/// `%` は剰余、`^` は右結合で単項マイナスより強い（`-2^2` = -4）。
/// 末尾の閉じ括弧の不足は補う（打っている途中の `3 + (34 * 2` でも答えを出す）。
/// 二項演算子を 1 つも含まない入力（`3`・`-3`・`(3)`）は式として扱わない＝アプリ検索の邪魔をしない。
/// 書きかけ・0 除算・桁あふれは nil（エラーは出さずカードを出さないだけ）
enum Calculator {
    static func evaluate(_ input: String) -> Double? {
        guard let tokens = tokenize(input), hasBinaryOperator(tokens) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.atEnd, value.isFinite else { return nil }
        return value == 0 ? 0 : value // -0 を 0 に
    }

    /// 答えの文字列。`grouping` は表示用の桁区切り（コピーする値には付けない）
    static func format(_ value: Double, grouping: Bool) -> String {
        let magnitude = abs(value)
        if magnitude >= 1e15 || (magnitude != 0 && magnitude < 1e-9) {
            return String(format: "%.15g", value) // 1.15292150460685e+18
        }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = grouping
        f.groupingSeparator = ","
        f.groupingSize = 3
        // 15 桁で丸めて 0.1 + 0.2 = 0.30000000000000004 のような誤差を見せない
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = 15
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - 字句解析

    private enum Token: Equatable {
        case number(Double)
        case op(Character)
        case open, close
    }

    private static func tokenize(_ input: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
            } else if c.isASCIIDigit || c == "." {
                var text = ""
                while i < chars.count, chars[i].isASCIIDigit || chars[i] == "." || chars[i] == "," {
                    if chars[i] != "," { text.append(chars[i]) }
                    i += 1
                }
                guard let v = Double(text) else { return nil } // "1.2.3" や "."
                tokens.append(.number(v))
            } else if c == "(" {
                tokens.append(.open); i += 1
            } else if c == ")" {
                tokens.append(.close); i += 1
            } else if let op = normalizedOperator(c) {
                tokens.append(.op(op)); i += 1
            } else {
                return nil
            }
        }
        return tokens
    }

    /// 数か閉じ括弧の直後に演算子があるか（先頭や演算子の直後の `-` は符号なので数えない）
    private static func hasBinaryOperator(_ tokens: [Token]) -> Bool {
        zip(tokens, tokens.dropFirst()).contains { prev, t in
            guard case .op = t else { return false }
            if case .number = prev { return true }
            return prev == .close
        }
    }

    private static func normalizedOperator(_ c: Character) -> Character? {
        switch c {
        case "+", "-", "*", "/", "^", "%": return c
        case "×": return "*"
        case "÷": return "/"
        case "−": return "-" // U+2212
        default: return nil
        }
    }

    // MARK: - 構文解析（再帰下降）

    /// expr  = term (("+" | "-") term)*
    /// term  = unary (("*" | "/" | "%") unary)*
    /// unary = ("+" | "-") unary | power
    /// power = primary ("^" unary)?
    private struct Parser {
        let tokens: [Token]
        var pos = 0

        init(tokens: [Token]) { self.tokens = tokens }

        var atEnd: Bool { pos == tokens.count }

        private func peekOp() -> Character? {
            guard pos < tokens.count, case .op(let c) = tokens[pos] else { return nil }
            return c
        }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while let op = peekOp(), op == "+" || op == "-" {
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = op == "+" ? lhs + rhs : lhs - rhs
            }
            return lhs
        }

        private mutating func parseTerm() -> Double? {
            guard var lhs = parseUnary() else { return nil }
            while let op = peekOp(), op == "*" || op == "/" || op == "%" {
                pos += 1
                guard let rhs = parseUnary() else { return nil }
                switch op {
                case "*": lhs *= rhs
                case "/": lhs /= rhs
                default: lhs = fmod(lhs, rhs)
                }
            }
            return lhs
        }

        private mutating func parseUnary() -> Double? {
            if let op = peekOp(), op == "+" || op == "-" {
                pos += 1
                guard let v = parseUnary() else { return nil }
                return op == "-" ? -v : v
            }
            return parsePower()
        }

        private mutating func parsePower() -> Double? {
            guard let base = parsePrimary() else { return nil }
            if peekOp() == "^" {
                pos += 1
                guard let exp = parseUnary() else { return nil }
                return pow(base, exp)
            }
            return base
        }

        private mutating func parsePrimary() -> Double? {
            guard pos < tokens.count else { return nil }
            switch tokens[pos] {
            case .number(let v):
                pos += 1
                return v
            case .open:
                pos += 1
                guard let v = parseExpression() else { return nil }
                if pos < tokens.count {
                    guard tokens[pos] == .close else { return nil }
                    pos += 1
                }
                // 末尾で閉じ括弧が足りないときは閉じたものとみなす
                return v
            default:
                return nil
            }
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
