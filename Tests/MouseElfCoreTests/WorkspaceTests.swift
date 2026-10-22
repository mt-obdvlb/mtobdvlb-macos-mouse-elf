import Foundation
import XCTest
@testable import MouseElfCore

final class WorkspaceTests: XCTestCase {
    private func temporaryRepository() -> WorkspaceRepository {
        WorkspaceRepository(url: FileManager.default.temporaryDirectory.appendingPathComponent("MouseElfTests-\(UUID())/workspace.json"))
    }

    func testMissingWorkspaceStartsEmpty() throws {
        let workspace = try temporaryRepository().load()
        XCTAssertTrue(workspace.scripts.isEmpty)
        XCTAssertEqual(workspace.clickConfiguration.repeatCount, 10)
        XCTAssertFalse(workspace.preferences.recordKeyboard)
    }

    func testWorkspaceRoundTripPreservesEditsAndSettings() throws {
        let repository = temporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository.url.deletingLastPathComponent()) }
        var workspace = Workspace()
        var script = MouseScript(name: "表单确认")
        var click = ScriptStep(kind: .click); click.x = -180; click.y = 410; click.button = .right
        script.steps = [click, ScriptStep(kind: .wait)]
        script.loopCount = 4; script.speed = 2
        workspace.scripts = [script]; workspace.selectedScriptID = script.id
        workspace.preferences.theme = .dark
        workspace.clickConfiguration.intervalMilliseconds = 250
        try repository.save(workspace)
        let loaded = try repository.load()
        XCTAssertEqual(loaded.scripts.first?.steps, script.steps)
        XCTAssertEqual(loaded.scripts.first?.loopCount, 4)
        XCTAssertEqual(loaded.selectedScriptID, script.id)
        XCTAssertEqual(loaded.preferences.theme, .dark)
        XCTAssertEqual(loaded.clickConfiguration.intervalMilliseconds, 250)
    }

    func testCorruptWorkspaceIsNotOverwrittenByLoading() throws {
        let repository = temporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository.url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: repository.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{broken".utf8)
        try original.write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.url), original)
    }

    func testExportImportAssignsFreshIdentities() throws {
        var script = MouseScript(name: "多屏拖拽")
        script.steps = [ScriptStep(kind: .mouseDown), ScriptStep(kind: .move), ScriptStep(kind: .mouseUp)]
        script.steps[1].x = -100
        let imported = try WorkspaceRepository.importScript(from: WorkspaceRepository.exportScript(script))
        XCTAssertNotEqual(imported.id, script.id)
        XCTAssertEqual(imported.name, script.name)
        XCTAssertEqual(imported.steps.map(\.kind), script.steps.map(\.kind))
        XCTAssertEqual(imported.steps[1].x, -100)
        XCTAssertTrue(Set(imported.steps.map(\.id)).isDisjoint(with: Set(script.steps.map(\.id))))
    }

    func testRejectsInvalidImportWithoutReplacingGoodFile() throws {
        let repository = temporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository.url.deletingLastPathComponent()) }
        let valid = Workspace()
        try repository.save(valid)
        let original = try Data(contentsOf: repository.url)
        var invalid = valid
        invalid.clickConfiguration.intervalMilliseconds = -1
        XCTAssertThrowsError(try repository.save(invalid))
        XCTAssertEqual(try Data(contentsOf: repository.url), original)
        XCTAssertThrowsError(try WorkspaceRepository.importScript(from: Data("{}".utf8)))
        XCTAssertThrowsError(try WorkspaceRepository.importScript(from: Data(repeating: 32, count: 5_000_001)))
    }

    func testBoundsAndNonFiniteNumbersAreRejected() throws {
        var config = ClickConfiguration()
        config.repeatCount = 0
        XCTAssertNoThrow(try config.validate())
        config.intervalMilliseconds = .infinity
        XCTAssertThrowsError(try config.validate())
        var script = MouseScript()
        script.steps = [ScriptStep(kind: .scroll)]
        script.steps[0].scrollY = .min
        XCTAssertThrowsError(try script.validate())
        script.steps[0].scrollY = -3
        script.steps[0].x = .nan
        XCTAssertThrowsError(try script.validate())
    }

    func testDuplicateHotkeysAndStepsRejected() throws {
        var workspace = Workspace()
        workspace.preferences.hotkeys[.record] = workspace.preferences.hotkeys[.stop]
        XCTAssertThrowsError(try workspace.validate())
        var script = MouseScript()
        let step = ScriptStep(kind: .click)
        script.steps = [step, step]
        XCTAssertThrowsError(try script.validate())
    }

    func testUnknownDocumentVersionRejected() throws {
        let script = MouseScript(name: "未来版本")
        var document = ScriptDocument(script: script)
        document.schemaVersion = 99
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertThrowsError(try WorkspaceRepository.importScript(from: encoder.encode(document)))
    }

    func testDurationUsesOnlyEnabledStepsAndPlaybackSpeed() {
        var script = MouseScript()
        var wait = ScriptStep(kind: .wait); wait.durationMilliseconds = 1000; wait.delayMilliseconds = 200
        var skipped = ScriptStep(kind: .wait); skipped.enabled = false; skipped.durationMilliseconds = 5000
        script.steps = [wait, skipped]; script.speed = 2
        XCTAssertEqual(script.estimatedMilliseconds, 600)
    }

    func testCannotWriteFilesThatExceedOwnReadLimits() throws {
        let repository = temporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository.url.deletingLastPathComponent()) }
        try repository.save(Workspace())
        let original = try Data(contentsOf: repository.url)
        var script = MouseScript(name: "容量边界")
        script.steps = (0..<2_600).map { _ in
            var step = ScriptStep(kind: .text)
            step.text = String(repeating: "a", count: 10_000)
            return step
        }
        XCTAssertThrowsError(try WorkspaceRepository.exportScript(script))
        var workspace = Workspace(); workspace.scripts = [script]
        XCTAssertThrowsError(try repository.save(workspace))
        XCTAssertEqual(try Data(contentsOf: repository.url), original)
        XCTAssertNoThrow(try repository.load())
    }
}
