import XCTest
@testable import WerkbankCore

final class SiteIconsTests: XCTestCase {
    func testPrefersAppleTouchIconThenLargestIcon() {
        let html = """
        <link rel="icon" href="/favicon-16.png" sizes="16x16">
        <link rel='icon' href='https://cdn.example.nl/icon-192.png' sizes='192x192'>
        <link rel="mask-icon" href="/mask.svg">
        <link href="/apple-touch-icon.png" rel="apple-touch-icon">
        <link rel="stylesheet" href="/x.css">
        """
        let urls = SiteIcons.candidates(html: html, baseURL: URL(string: "https://www.example.nl/")!)
        XCTAssertEqual(urls.map(\.absoluteString), ["https://www.example.nl/apple-touch-icon.png",
                                                      "https://cdn.example.nl/icon-192.png",
                                                      "https://www.example.nl/favicon-16.png"])
    }

    func testSkipsGenericAndSVG() {
        let html = """
        <link rel="icon" href="https://example.nl/wp-includes/images/w-logo-blue-white-bg.png">
        <link rel="icon" href="/logo.svg">
        """
        XCTAssertTrue(SiteIcons.candidates(html: html, baseURL: URL(string: "https://example.nl/")!).isEmpty)
        XCTAssertTrue(SiteIcons.isGeneric(URL(string: "https://static.wixstatic.com/x/parastorage.com/favicon.ico")!))
        XCTAssertFalse(SiteIcons.isGeneric(URL(string: "https://itgsolutions.nl/favicon.ico")!))
    }
}
