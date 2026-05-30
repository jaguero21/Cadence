import Testing
import Foundation
@testable import Cadence

// MARK: - StoreService: isPro computed property

@Suite("StoreService – isPro logic")
struct StoreServiceIsProTests {

    @Test("isPro returns false when purchasedProductIDs is empty")
    @MainActor
    func isPro_emptySet_returnsFalse() {
        let store = StoreService.shared
        store.purchasedProductIDs = []
        #expect(store.isPro == false)
    }

    @Test("isPro returns true when proOneTime is in purchasedProductIDs")
    @MainActor
    func isPro_containsProOneTime_returnsTrue() {
        let store = StoreService.shared
        store.purchasedProductIDs = [StoreKitID.proOneTime]
        #expect(store.isPro == true)
        store.purchasedProductIDs = []
    }

    @Test("isPro returns true when proMonthly is in purchasedProductIDs")
    @MainActor
    func isPro_containsProMonthly_returnsTrue() {
        let store = StoreService.shared
        store.purchasedProductIDs = [StoreKitID.proMonthly]
        #expect(store.isPro == true)
        store.purchasedProductIDs = []
    }

    @Test("isPro returns true when both product IDs are present")
    @MainActor
    func isPro_containsBoth_returnsTrue() {
        let store = StoreService.shared
        store.purchasedProductIDs = [StoreKitID.proOneTime, StoreKitID.proMonthly]
        #expect(store.isPro == true)
        store.purchasedProductIDs = []
    }
}

// MARK: - StoreKitID constants

@Suite("StoreKitID – product ID constants")
struct StoreKitIDTests {

    @Test("proOneTime has the expected bundle-qualified product ID")
    func proOneTime_hasExpectedValue() {
        #expect(StoreKitID.proOneTime == "com.carpecadence.pro.lifetime")
    }

    @Test("proMonthly has the expected bundle-qualified product ID")
    func proMonthly_hasExpectedValue() {
        #expect(StoreKitID.proMonthly == "com.carpecadence.pro.monthly")
    }

    @Test("proOneTime and proMonthly are distinct identifiers")
    func productIDs_areDistinct() {
        #expect(StoreKitID.proOneTime != StoreKitID.proMonthly)
    }
}
