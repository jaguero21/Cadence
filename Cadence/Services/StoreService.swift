import StoreKit
import SwiftUI
import OSLog

@MainActor
@Observable
final class StoreService {
    static let shared = StoreService()
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var productsLoadFailed = false
    private var updates: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.carpecadence", category: "StoreService")
    init() { updates = listenForTransactionUpdates() }
    @MainActor deinit { updates?.cancel() }

    var lifetimeProduct: Product? { products.first { $0.id == StoreKitID.proOneTime } }
    var monthlyProduct: Product? { products.first { $0.id == StoreKitID.proMonthly } }

    func loadProducts() async {
        productsLoadFailed = false
        do {
            products = try await Product.products(for: [StoreKitID.proOneTime, StoreKitID.proMonthly])
        } catch {
            products = []
            productsLoadFailed = true
            Self.log.error("Failed to load StoreKit products: \(error, privacy: .public)")
        }
    }

    // Distinguishes the three outcomes StoreKit reports. A `Bool` collapsed
    // `.pending` into `.userCancelled`, so a family-sharing child hitting Ask
    // to Buy — or a European card triggering SCA — saw the tap do nothing at
    // all, then got Pro silently later when approval landed via
    // Transaction.updates.
    enum PurchaseOutcome {
        case purchased
        case cancelled
        case pending
    }

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            purchasedProductIDs.insert(product.id)
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            // Unknown future cases are reported as cancelled, never as
            // purchased: entitlement is granted by refreshEntitlements and
            // Transaction.updates, both of which verify.
            return .cancelled
        }
    }

    // Rebuilds the entitlement set from StoreKit's authoritative
    // `currentEntitlements`. This must run at launch: StoreKit caches nothing
    // for us across launches and `Transaction.updates` only delivers NEW
    // transactions, so without it a returning Pro user (reinstall, new device,
    // or just a cold start) reads as free.
    //
    // REBUILDS rather than unions: `currentEntitlements` omits expired
    // subscriptions and revoked purchases, so assigning the whole set is what
    // makes Pro actually lapse. Unioning would make every grant permanent for
    // the life of the process.
    func refreshEntitlements() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  transaction.revocationDate == nil else { continue }
            owned.insert(transaction.productID)
            await transaction.finish()
        }
        purchasedProductIDs = owned
    }

    func restorePurchases() async {
        await refreshEntitlements()
    }

    var isPro: Bool {
        purchasedProductIDs.contains(StoreKitID.proOneTime) ||
        purchasedProductIDs.contains(StoreKitID.proMonthly)
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let safe): return safe
        }
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        // Inside an @MainActor class, Task { } inherits MainActor isolation —
        // so the insert below runs on the main thread directly, no hop needed.
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.checkVerified(result) else { continue }
                // `Transaction.updates` also delivers a transaction when it is
                // REVOKED (refund, family-sharing removal). Inserting on that
                // would re-grant Pro to a refunded user, so branch on
                // revocationDate rather than treating every update as a grant.
                if transaction.revocationDate == nil {
                    self.purchasedProductIDs.insert(transaction.productID)
                } else {
                    self.purchasedProductIDs.remove(transaction.productID)
                }
                await transaction.finish()
            }
        }
    }
}

enum StoreError: Error { case failedVerification }
