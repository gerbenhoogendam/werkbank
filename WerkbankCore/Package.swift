// swift-tools-version: 5.9
import PackageDescription

// Foundation-only kern van Werkbank: parsen, klantnamen, afronding, eindtijdcorrectie,
// inplanregels en CSV-export. Geen UI, geen EventKit, geen SwiftData, zodat alles met
// `swift test` te testen is.
let package = Package(
    name: "WerkbankCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "WerkbankCore", targets: ["WerkbankCore"]),
    ],
    targets: [
        .target(name: "WerkbankCore"),
        .testTarget(name: "WerkbankCoreTests", dependencies: ["WerkbankCore"]),
    ]
)
