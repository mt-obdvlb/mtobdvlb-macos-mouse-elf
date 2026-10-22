import Foundation
import XCTest
import MouseElfCore
@testable import MouseElf

@MainActor
final class AppStoreTests: XCTestCase {
    private func store() -> AppStore {
        AppStore(repository: WorkspaceRepository(url: FileManager.default.temporaryDirectory.appendingPathComponent("MouseElfStoreTests-\(UUID())/workspace.json")), systemIntegration: false)
    }

    func testScriptAndStepEditingPersistsAcrossRestart() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MouseElfStoreTests-\(UUID())/workspace.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = WorkspaceRepository(url: url)
        let store = AppStore(repository: repository, systemIntegration: false)
        store.newScript()
        store.addStep(.click)
        let click = try XCTUnwrap(store.selectedStep)
        store.addStep(.wait)
        let wait = try XCTUnwrap(store.selectedStep)
        store.moveStep(wait.id, by: -1)
        XCTAssertEqual(store.selectedScript?.steps.first?.id, wait.id)
        store.duplicateStep(click.id)
        XCTAssertEqual(store.selectedScript?.steps.count, 3)
        var edited = try XCTUnwrap(store.selectedStep)
        edited.x = -300; edited.button = .middle; edited.title = "中键确认"
        store.updateStep(edited)
        store.deleteStep(click.id)
        store.save()
        let reloaded = AppStore(repository: repository, systemIntegration: false)
        XCTAssertEqual(reloaded.selectedScript?.steps.count, 2)
        XCTAssertEqual(reloaded.selectedScript?.steps.last?.title, "中键确认")
        XCTAssertEqual(reloaded.selectedScript?.steps.last?.x, -300)
    }

    func testDeletingSelectedScriptKeepsSelectionValid() {
        let store = store()
        store.newScript()
        let firstID = store.selectedScriptID!
        store.newScript()
        store.deleteScript(store.selectedScriptID!)
        XCTAssertEqual(store.selectedScriptID, firstID)
        store.deleteScript(firstID)
        XCTAssertNil(store.selectedScriptID)
        XCTAssertNil(store.selectedStepID)
    }

    func testDuplicateScriptHasDistinctIdentityAndSteps() {
        let store = store()
        store.newScript(); store.addStep(.click)
        let original = store.selectedScript!
        store.duplicateScript(original.id)
        XCTAssertNotEqual(store.selectedScriptID, original.id)
        XCTAssertNotEqual(store.selectedStepID, original.steps[0].id)
        XCTAssertTrue(store.selectedScript!.name.hasSuffix("副本"))
    }

    func testOutOfRangeMoveDoesNothing() {
        let store = store()
        store.addStep(.wait)
        let step = store.selectedStep!
        store.moveStep(step.id, by: -1)
        XCTAssertEqual(store.selectedScript!.steps.map(\.id), [step.id])
        store.moveStep(step.id, by: 1)
        XCTAssertEqual(store.selectedScript!.steps.map(\.id), [step.id])
    }

    func testCorruptWorkspaceBlocksAutomaticAndExplicitOverwrite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MouseElfStoreTests-\(UUID())/workspace.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let broken = Data("invalid".utf8)
        try broken.write(to: url)
        let store = AppStore(repository: WorkspaceRepository(url: url), systemIntegration: false)
        XCTAssertNotNil(store.errorMessage)
        store.newScript(); store.save()
        XCTAssertEqual(try Data(contentsOf: url), broken)
    }

    func testQuitIsCancelledUntilInvalidEditsAreFixed() {
        let store = store()
        store.newScript()
        var script = store.selectedScript!
        script.name = ""
        store.updateScript(script)
        XCTAssertFalse(store.shutdown())
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertNotNil(store.lastSaveError)
        script.name = "已修复"
        store.updateScript(script)
        XCTAssertTrue(store.shutdown())
        XCTAssertFalse(store.hasUnsavedChanges)
    }
}
