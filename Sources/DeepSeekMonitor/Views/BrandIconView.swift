import AppKit
import SwiftUI

private enum BrandImageLoader {
    static let image: NSImage? = {
        if let pngURL = Bundle.main.url(forResource: "deepseek-color", withExtension: "png"),
           let image = NSImage(contentsOf: pngURL) {
            return image
        }

        if let svgURL = Bundle.main.url(forResource: "deepseek-color", withExtension: "svg"),
           let image = NSImage(contentsOf: svgURL) {
            return image
        }

        return nil
    }()
}

struct BrandIconView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = BrandImageLoader.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "chart.pie.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.brand)
                    .padding(size * 0.14)
            }
        }
        .frame(width: size, height: size)
    }
}
