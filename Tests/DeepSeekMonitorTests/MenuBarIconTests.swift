import AppKit
import Foundation
import XCTest

final class MenuBarIconTests: XCTestCase {
    private let logicalSize = NSSize(width: 18, height: 18)

    func testTemplateAssetsUseNativeMenuBarDimensions() throws {
        let oneX = try loadRepresentation(named: "DeepSeekMenuBarTemplate.png")
        let twoX = try loadRepresentation(named: "DeepSeekMenuBarTemplate@2x.png")

        XCTAssertEqual(oneX.pixelsWide, 18)
        XCTAssertEqual(oneX.pixelsHigh, 18)
        XCTAssertTrue(oneX.hasAlpha)
        XCTAssertEqual(twoX.pixelsWide, 36)
        XCTAssertEqual(twoX.pixelsHigh, 36)
        XCTAssertTrue(twoX.hasAlpha)

        assertUsefulAlphaCoverage(oneX)
        assertUsefulAlphaCoverage(twoX)
    }

    @MainActor
    func testTemplateIconRendersInLightAndDarkAppearances() throws {
        let icon = try makeTemplateImage()

        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.size, logicalSize)
        XCTAssertEqual(icon.representations.map(\.size), [logicalSize, logicalSize])

        let light = try render(icon, appearance: .aqua)
        let dark = try render(icon, appearance: .darkAqua)

        XCTAssertGreaterThan(light.visiblePixelCount, 0)
        XCTAssertLessThan(light.meanLuminance, 0.2)
        XCTAssertGreaterThan(dark.visiblePixelCount, 0)
        XCTAssertGreaterThan(dark.meanLuminance, 0.8)
    }

    private func makeTemplateImage() throws -> NSImage {
        let oneX = try loadRepresentation(named: "DeepSeekMenuBarTemplate.png")
        let twoX = try loadRepresentation(named: "DeepSeekMenuBarTemplate@2x.png")
        oneX.size = logicalSize
        twoX.size = logicalSize

        let image = NSImage(size: logicalSize)
        image.addRepresentation(oneX)
        image.addRepresentation(twoX)
        image.isTemplate = true
        return image
    }

    private func loadRepresentation(named name: String) throws -> NSBitmapImageRep {
        let data = try Data(contentsOf: imageSetURL.appendingPathComponent(name))
        return try XCTUnwrap(NSBitmapImageRep(data: data))
    }

    private func assertUsefulAlphaCoverage(
        _ representation: NSBitmapImageRep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let pixelCount = representation.pixelsWide * representation.pixelsHigh
        let visiblePixelCount = pixels(in: representation).filter { $0.alphaComponent > 0.01 }.count

        XCTAssertGreaterThan(visiblePixelCount, pixelCount / 4, file: file, line: line)
        XCTAssertLessThan(visiblePixelCount, pixelCount * 3 / 4, file: file, line: line)
    }

    @MainActor
    private func render(
        _ image: NSImage,
        appearance: NSAppearance.Name
    ) throws -> RenderStatistics {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.appearance = NSAppearance(named: appearance)
        button.image = image
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly

        let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
        button.cacheDisplay(in: button.bounds, to: bitmap)

        let visiblePixels = pixels(in: bitmap).filter { $0.alphaComponent > 0.01 }
        let luminance = visiblePixels.reduce(0.0) { result, color in
            result + 0.2126 * color.redComponent
                + 0.7152 * color.greenComponent
                + 0.0722 * color.blueComponent
        }

        return RenderStatistics(
            visiblePixelCount: visiblePixels.count,
            meanLuminance: visiblePixels.isEmpty ? 0 : luminance / Double(visiblePixels.count)
        )
    }

    private func pixels(in representation: NSBitmapImageRep) -> [NSColor] {
        (0..<representation.pixelsHigh).flatMap { y in
            (0..<representation.pixelsWide).compactMap { x in
                representation.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
            }
        }
    }

    private var imageSetURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Assets.xcassets/DeepSeekMenuBarTemplate.imageset")
    }
}

private struct RenderStatistics {
    let visiblePixelCount: Int
    let meanLuminance: Double
}
