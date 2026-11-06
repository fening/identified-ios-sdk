import CoreText
import Foundation

/// Static registration is lazy and thread safe. Font resources belong to the
/// SDK bundle, so integrators do not need UIAppFonts entries in their app.
enum BundledFonts {
    static let names = [
        "IdentifiedDMSans-Regular", "IdentifiedDMSans-Medium", "IdentifiedDMSans-SemiBold", "IdentifiedDMSans-Bold",
        "IdentifiedOutfit-Medium", "IdentifiedOutfit-SemiBold", "IdentifiedOutfit-Bold",
    ]

    static let register: Void = {
        for name in names {
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()
}
