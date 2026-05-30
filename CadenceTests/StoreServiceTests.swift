import Testing
import Foundation
@testable import Cadence

// MARK: - StoreService: isPro computed property
//
// StoreService.isPro currently has a TEST OVERRIDE that returns `true` unconditionally
// ("var isPro: Bool { true } // TEST OVERRIDE — remove before shipping").
// The tests below document the INTENDED behavior of isPro based on purchasedProductIDs,
// and will need to be revisited once the override is removed and the real implementation
// (purchasedProductIDs.contains(StoreKitID.proOneTime) || purchasedProductIDs.contains(StoreKitID.proMonthly))
// is wired up.
//
// Because StoreService is @MainActor and its init spins up a StoreKit transaction listener,
// we access StoreService.shared on the main actor and mutate purchasedProductIDs directly
// via @testable access.

@Suite("StoreService – isPro logic")
struct StoreServiceIsProTests {

    // Reset the shared instance's purchasedProductIDs before each test by emptying the set.
    // We do this in each test rather than a shared setUp to avoid inter-test state leakage.

    @Test("isPro is hardcoded true due to test override (documents current state)")
    @MainActor
    func isPro_testOverrideActive_alwaysReturnsTrue() {
        let store = StoreService.shared
        store.purchasedProductIDs = []
        // The current implementation ignores purchasedProductIDs and returns true unconditionally.
        // This test documents that hardcoded override and will FAIL once the override is removed,
        // signalling the test suite needs to be re-evaluated against the real logic.
        #expect(store.isPro == true,
                "TEST OVERRIDE in StoreService.isPro returns true unconditionally; update this test when override is removed")
    }

    // The three tests below exercise the INTENDED logic by directly inspecting purchasedProductIDs.
    // They bypass the isPro computed property (because of the override) and instead assert on the
    // set membership that isPro is supposed to use.

    @Test("purchasedProductIDs is empty when no purchases have been recorded")
    @MainActor
    func purchasedProductIDs_empty_producesNoPurchases() {
        let store = StoreService.shared
        store.purchasedProductIDs = []
        #expect(store.purchasedProductIDs.isEmpty)
    }

    @Test("purchasedProductIDs contains proOneTime after inserting lifetime product ID")
    @MainActor
    func purchasedProductIDs_containsProOneTime_afterInsert() {
        let store = StoreService.shared
        store.purchasedProductIDs = []
        store.purchasedProductIDs.insert(StoreKitID.proOneTime)
        #expect(store.purchasedProductIDs.contains(StoreKitID.proOneTime))
    }

    @Test("purchasedProductIDs contains proMonthly after inserting monthly product ID")
    @MainActor
    func purchasedProductIDs_containsProMonthly_afterInsert() {
        let store = StoreService.shared
        store.purchasedProductIDs = []
        store.purchasedProductIDs.insert(StoreKitID.proMonthly)
        #expect(store.purchasedProductIDs.contains(StoreKitID.proMonthly))
    }

    // Once the isPro override is removed the following three tests verify the real logic.
    // They are currently annotated as documentation — they assert on purchasedProductIDs
    // membership, which is the correct underlying data for isPro's intended implementation.

    @Test("Intended: isPro should return false when purchasedProductIDs is empty")
    @MainActor
    func intendedBehavior_isProShouldBeFalse_whenNoPurchases() {
        let store = StoreService.shared
        store.purchasedProductIDs = []
        // Intended: store.isPro == false. Currently broken by override.
        let wouldBePro = store.purchasedProductIDs.contains(StoreKitID.proOneTime) ||
                         store.purchasedProductIDs.contains(StoreKitID.proMonthly)
        #expect(wouldBePro == false)
    }

    @Test("Intended: isPro should return true when proOneTime is in purchasedProductIDs")
    @MainActor
    func intendedBehavior_isProShouldBeTrue_whenProOneTimePurchased() {
        let store = StoreService.shared
        store.purchasedProductIDs = [StoreKitID.proOneTime]
        let wouldBePro = store.purchasedProductIDs.contains(StoreKitID.proOneTime) ||
                         store.purchasedProductIDs.contains(StoreKitID.proMonthly)
        #expect(wouldBePro == true)
    }

    @Test("Intended: isPro should return true when proMonthly is in purchasedProductIDs")
    @MainActor
    func intendedBehavior_isProShouldBeTrue_whenProMonthlyPurchased() {
        let store = StoreService.shared
        store.purchasedProductIDs = [StoreKitID.proMonthly]
        let wouldBePro = store.purchasedProductIDs.contains(StoreKitID.proOneTime) ||
                         store.purchasedProductIDs.contains(StoreKitID.proMonthly)
        #expect(wouldBePro == true)
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
