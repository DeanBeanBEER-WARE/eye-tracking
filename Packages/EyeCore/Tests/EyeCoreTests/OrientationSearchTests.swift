import Testing

@testable import TrackingKit

@Suite("Orientation search")
struct OrientationSearchTests {
    @Test("A face at the start locks the orientation without searching")
    func immediateFace() {
        var search = OrientationSearch()
        #expect(search.update(faceFound: true, now: 0) == nil)
        #expect(search.isLocked)
        #expect(search.update(faceFound: false, now: 60) == nil)
        #expect(search.offset == 0)
    }

    @Test("Without a face the search waits, then tries every quarter turn until a face appears")
    func search() {
        var search = OrientationSearch()
        #expect(search.update(faceFound: false, now: 0) == nil)
        #expect(search.update(faceFound: false, now: 2.9) == nil)
        #expect(search.update(faceFound: false, now: 3) == 90)
        #expect(search.update(faceFound: false, now: 4) == nil)
        #expect(search.update(faceFound: false, now: 4.5) == 180)
        #expect(search.update(faceFound: false, now: 6) == 270)
        #expect(search.update(faceFound: false, now: 7.5) == 0)
        #expect(search.update(faceFound: false, now: 9) == 90)
        #expect(search.update(faceFound: true, now: 9.1) == nil)
        #expect(search.isLocked && search.offset == 90)
        #expect(search.update(faceFound: false, now: 20) == nil)
    }

    @Test("A stored offset is normalized and used first")
    func storedOffset() {
        #expect(OrientationSearch(offset: 270).offset == 270)
        #expect(OrientationSearch(offset: -90).offset == 270)
        #expect(OrientationSearch(offset: 450).offset == 90)
        var search = OrientationSearch(offset: 180)
        #expect(search.update(faceFound: false, now: 0) == nil)
        #expect(search.update(faceFound: false, now: 3) == 270)
    }
}
