import BreathNotes
import Testing

@Suite("Note tab titles")
struct NoteTabTitleTests {
    @Test("same-name tabs use only the shortest distinguishing parent path")
    func shortestDistinguishingParent() {
        let paths = [
            "team/ios/README.md",
            "archive/ios/README.md",
            "server/README.md",
            "README.md",
        ]

        #expect(
            NoteTabTitle.disambiguated(
                relativePath: paths[0],
                among: paths
            ) == "team/ios/README.md"
        )
        #expect(
            NoteTabTitle.disambiguated(
                relativePath: paths[1],
                among: paths
            ) == "archive/ios/README.md"
        )
        #expect(
            NoteTabTitle.disambiguated(
                relativePath: paths[2],
                among: paths
            ) == "server/README.md"
        )
        #expect(
            NoteTabTitle.disambiguated(
                relativePath: paths[3],
                among: paths
            ) == "README.md — /"
        )
        #expect(
            NoteTabTitle.disambiguated(
                relativePath: "unique.md",
                among: paths + ["unique.md"]
            ) == "unique.md"
        )
    }
}
