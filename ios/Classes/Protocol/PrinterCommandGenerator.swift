import Foundation
import UIKit

/// Base protocol for printer command generators
protocol PrinterCommandGenerator {
    func generateTextCommand(_ text: String, alignment: String?) -> Data
    func generateImageCommand(_ image: UIImage, maxWidth: Int, alignment: String?) -> Data
    func generateCutCommand() -> Data
    func generateFeedCommand(lines: Int) -> Data
}

