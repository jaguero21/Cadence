import Testing
import SwiftData
import Foundation
@testable import Cadence

// MARK: - SwiftData Schema Migration – Documentation Tests
//
// These tests document the CURRENT (known-incomplete) state of the migration plan.
// CadenceSchemaV1 and CadenceSchemaV2 list identical model types, making the migration
// a structural no-op. These tests will FAIL intentionally if someone:
//   • Adds a model to one version but not the other
//   • Adds or removes a migration stage
//   • Breaks the lightweight migration constructor
//
// They are not testing that a real migration happens correctly — they document the
// current state so regressions are caught immediately.

@Suite("CadenceSchema – version model parity")
struct SchemaVersionParityTests {

    @Test("CadenceSchemaV1 and CadenceSchemaV2 have the same number of model types")
    func schemaVersions_haveSameModelCount() {
        let v1Count = CadenceSchemaV1.models.count
        let v2Count = CadenceSchemaV2.models.count
        #expect(v1Count == v2Count,
                "V1 has \(v1Count) models, V2 has \(v2Count); they should be equal until a real migration is implemented")
    }

    @Test("Both schema versions list exactly 3 model types")
    func schemaVersions_listThreeModelTypes() {
        #expect(CadenceSchemaV1.models.count == 3)
        #expect(CadenceSchemaV2.models.count == 3)
    }

    @Test("CadenceSchemaV1 versionIdentifier is 1.0.0")
    func schemaV1_versionIdentifier_is1_0_0() {
        let version = CadenceSchemaV1.versionIdentifier
        #expect(version == Schema.Version(1, 0, 0))
    }

    @Test("CadenceSchemaV2 versionIdentifier is 2.0.0")
    func schemaV2_versionIdentifier_is2_0_0() {
        let version = CadenceSchemaV2.versionIdentifier
        #expect(version == Schema.Version(2, 0, 0))
    }
}

@Suite("CadenceMigrationPlan – structure")
struct MigrationPlanStructureTests {

    @Test("Migration plan has exactly one stage")
    func migrationPlan_hasExactlyOneStage() {
        #expect(CadenceMigrationPlan.stages.count == 1)
    }

    @Test("Migration plan schema list contains exactly two versions")
    func migrationPlan_schemaList_hasTwoVersions() {
        #expect(CadenceMigrationPlan.schemas.count == 2)
    }

    @Test("In-memory ModelContainer with migration plan initialises without throwing")
    func migrationPlan_inMemoryModelContainer_doesNotThrow() throws {
        let schema = Schema(CadenceSchemaV2.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // The lightweight stage is a no-op (identical schemas), so this must not throw.
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CadenceMigrationPlan.self,
            configurations: [config]
        )
        // Verify the container is usable by confirming its schema is non-nil
        #expect(container.schema.entities.isEmpty == false)
    }

    @Test("In-memory ModelContainer without migration plan also initialises (baseline)")
    func baselineSchema_inMemoryModelContainer_doesNotThrow() throws {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        #expect(container.schema.entities.isEmpty == false)
    }
}

@Suite("CadenceSchemaV2 models – types present")
struct SchemaV2ModelTypesTests {

    @Test("CadenceSchemaV2 models include DailyLog")
    func schemaV2_includesDailyLog() {
        let containsDailyLog = CadenceSchemaV2.models.contains { $0 == DailyLog.self }
        #expect(containsDailyLog)
    }

    @Test("CadenceSchemaV2 models include WeeklyReview")
    func schemaV2_includesWeeklyReview() {
        let containsWeeklyReview = CadenceSchemaV2.models.contains { $0 == WeeklyReview.self }
        #expect(containsWeeklyReview)
    }

    @Test("CadenceSchemaV2 models include SymptomTag")
    func schemaV2_includesSymptomTag() {
        let containsSymptomTag = CadenceSchemaV2.models.contains { $0 == SymptomTag.self }
        #expect(containsSymptomTag)
    }
}
