import XCTest
@testable import Vocab

final class TatoebaServiceTests: XCTestCase {
    /// `Language.common` now spans every ISO 639-1 code Foundation knows a
    /// localized name for, well beyond Tatoeba's small hand-mapped table —
    /// full coverage is no longer the invariant (an unmapped language just
    /// falls back to the graceful "couldn't fetch" path below). What must
    /// still hold: every entry in the mapping is for a code the picker
    /// actually offers, so there's no dead/stale mapping left behind.
    func testIso639_3EntriesAreAllOfferedByLanguageCommon() {
        let commonCodes = Set(Language.common.map(\.code))
        for code in TatoebaService.iso639_3.keys {
            XCTAssertTrue(commonCodes.contains(code), "\(code) in TatoebaService.iso639_3 is not offered by Language.common")
        }
    }

    func testFetchExampleReturnsNilForAnUnmappedLanguageCodeWithoutMakingANetworkCall() async {
        let result = await TatoebaService.fetchExample(term: "hello", languageCode: "xx-not-a-real-code", nativeLanguageCode: "en")
        XCTAssertNil(result)
    }
}
