import XCTest
@testable import Vocab

final class TatoebaServiceTests: XCTestCase {
    /// Regression test for the bug this replaced a hand-mapped ~18-language
    /// table to fix: Danish (and any other ISO 639-1 code Foundation knows)
    /// silently got no example sentence because it simply wasn't a key in
    /// that table, even though `Language.common`'s picker offered it.
    func testIso639_3ResolvesDanishViaLocaleLanguageCode() {
        XCTAssertEqual(TatoebaService.iso639_3(for: "da"), "dan")
    }

    func testIso639_3UsesTheChineseOverrideInsteadOfTheMacrolanguageCode() {
        // `Locale.LanguageCode("zh").identifier(.alpha3)` derives "zho" (the
        // Chinese macrolanguage code); Tatoeba expects "cmn" (Mandarin).
        XCTAssertEqual(TatoebaService.iso639_3(for: "zh"), "cmn")
    }

    func testIso639_3ReturnsNilForAnUnrecognizedCode() {
        XCTAssertNil(TatoebaService.iso639_3(for: "xx-not-a-real-code"))
    }

    /// What must still hold now that the table is just the Chinese
    /// exception rather than a full hand-maintained list: every override is
    /// for a code the picker actually offers, so there's no dead/stale
    /// entry left behind.
    func testOverrideEntriesAreAllOfferedByLanguageCommon() {
        let commonCodes = Set(Language.common.map(\.code))
        for code in TatoebaService.iso639_3Overrides.keys {
            XCTAssertTrue(commonCodes.contains(code), "\(code) in TatoebaService.iso639_3Overrides is not offered by Language.common")
        }
    }

    func testFetchExampleReturnsNilForAnUnmappedLanguageCodeWithoutMakingANetworkCall() async {
        let result = await TatoebaService.fetchExample(term: "hello", languageCode: "xx-not-a-real-code", nativeLanguageCode: "en")
        XCTAssertNil(result)
    }
}
