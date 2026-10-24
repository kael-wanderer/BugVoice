import Foundation

func tone(seconds: Double, amplitude: Float) -> [Float] {
    (0..<Int(seconds * 16_000)).map { amplitude * Float(sin(2 * Double.pi * 220 * Double($0) / 16_000)) }
}
func silence(seconds: Double) -> [Float] { Array(repeating: 0, count: Int(seconds * 16_000)) }

