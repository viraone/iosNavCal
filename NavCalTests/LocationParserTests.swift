import Testing
@testable import NavCal

struct LocationParserTests {
    @Test(arguments: [
        ("Safeway 555", "Safeway 555"),
        ("Fred Meyer 658", "Fred Meyer 658"),
        ("Reset – Safeway 555", "Safeway 555"),
        ("Merch Reset Fred Meyer 658 aisle 4", "Fred Meyer 658"),
        ("Visit Safeway #1234", "Safeway 1234"),
        ("Pickup at WinCo Foods Store 12", "WinCo Foods 12"),
        ("Safeway No. 555 restock", "Safeway 555"),
    ])
    func findsStoreReferences(title: String, expected: String) {
        #expect(LocationParser.destination(in: [title]) == expected)
    }

    @Test(arguments: [
        "Shift 12",
        "Route 66",
        "Team call",
        "Starbucks 10:30",
        "Lunch 12 pm",
        "Meeting 2026",
    ])
    func ignoresNonLocations(title: String) {
        #expect(LocationParser.storeReference(in: title) == nil)
    }

    @Test func prefersNotesWhenTitleHasNothing() {
        #expect(LocationParser.destination(in: ["Morning shift", "Store: Fred Meyer 658"]) == "Fred Meyer 658")
    }

    @Test func detectsStreetAddress() {
        let result = LocationParser.destination(in: ["Delivery to 1 Infinite Loop, Cupertino, CA 95014"])
        #expect(result?.contains("1 Infinite Loop") == true)
    }

    @Test func normalizesMultilineLocations() {
        #expect(LocationParser.normalize("Safeway\n 123 Main St \n\nPortland, OR") == "Safeway, 123 Main St, Portland, OR")
    }
}
