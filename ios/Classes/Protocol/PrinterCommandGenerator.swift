import Foundation
import UIKit

/// Base protocol for printer command generators
protocol PrinterCommandGenerator {
    func generateTextCommand(_ text: String) -> Data
    func generateImageCommand(_ image: UIImage, maxWidth: Int) -> Data
    func generateCutCommand() -> Data
    func generateFeedCommand(lines: Int) -> Data
}

