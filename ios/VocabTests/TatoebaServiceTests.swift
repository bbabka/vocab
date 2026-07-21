import XCTest
@testable import Vocab

final class TatoebaServiceTests: XCTestCase {
    func testIso639_3CoversEveryLanguageCommonOffers() {
        for language in Language.common {
            XCTAssertNotNil(TatoebaService.iso639_3[language.code], "\(language.code) has no ISO 639-3 mapping")
        }
    }

    func testFetchExampleReturnsNilForAnUnmappedLanguageCodeWithoutMakingANetworkCall() async {
        let result = await TatoebaService.fetchExample(term: "hello", languageCode: "xx-not-a-real-code", nativeLanguageCode: "en")
        XCTAssertNil(result)
    }
}
