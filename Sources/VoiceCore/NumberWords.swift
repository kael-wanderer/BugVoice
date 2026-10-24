import Foundation

/// Number words are only comparison candidates, never lost-detail tokens. This
/// deliberately leaves ambiguous words (for example Vietnamese “năm”) unflagged.
enum NumberWords {
    private static let units: [String: Int] = {
        var result: [String: Int] = [:]
        let groups = [
            ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"],
            ["cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce", "trece", "catorce", "quince", "dieciséis", "diecisiete", "dieciocho", "diecinueve"],
            ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"]
        ]
        for group in groups { for (n, word) in group.enumerated() { result[word] = n } }
        for (word, value) in ["un": 1, "una": 1, "mốt": 1, "tư": 4, "lăm": 5,
                               "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
                               "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
                               "nhất": 1, "primero": 1, "primera": 1, "segundo": 2,
                               "segunda": 2, "tercero": 3, "tercera": 3] { result[word] = value }
        for (i, word) in ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"].enumerated() { result[word] = (i + 2) * 10 }
        for (i, word) in ["veinte", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa"].enumerated() { result[word] = (i + 2) * 10 }
        for (i, word) in ["veintiuno", "veintidós", "veintitrés", "veinticuatro", "veinticinco", "veintiséis", "veintisiete", "veintiocho", "veintinueve"].enumerated() { result[word] = i + 21 }
        return result
    }()
    private static let scales = ["hundred": 100, "trăm": 100, "cien": 100, "ciento": 100,
                                 "thousand": 1000, "nghìn": 1000, "ngàn": 1000, "mil": 1000,
                                 "million": 1000000, "triệu": 1000000, "millón": 1000000, "millones": 1000000]

    static func values(in text: String) -> Set<Decimal> {
        let words = text.lowercased().precomposedStringWithCanonicalMapping
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        var values = Set<Decimal>()
        var subtotal: Decimal = 0
        var total: Decimal = 0
        var active = false
        func flush() {
            if active { values.insert(total + subtotal) }
            subtotal = 0; total = 0; active = false
        }
        for (i, word) in words.enumerated() {
            if let n = units[word] {
                // Adjacent independent units are possible in dictation. Retain
                // their candidates as well as the composed phrase.
                values.insert(Decimal(n))
                subtotal += Decimal(n); active = true
            } else if word == "mươi" || word == "mười" {
                subtotal = max(subtotal, 1) * 10; active = true
            } else if let scale = scales[word] {
                if scale == 100 { subtotal = max(subtotal, 1) * 100 }
                else { total += max(subtotal, 1) * Decimal(scale); subtotal = 0 }
                active = true
            } else if ["and", "y", "linh", "lẻ"].contains(word), active,
                      i + 1 < words.count, units[words[i + 1]] != nil {
                continue
            } else { flush() }
        }
        flush()
        return values
    }
}
