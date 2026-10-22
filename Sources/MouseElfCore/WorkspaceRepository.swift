import Foundation

public struct ScriptDocument: Codable {
    public var schemaVersion: Int = 1
    public var script: MouseScript
    public init(script: MouseScript) { self.script = script }
}

public struct WorkspaceRepository {
    public static let maximumWorkspaceBytes = 25_000_000
    public static let maximumScriptBytes = 5_000_000
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var applicationDefault: WorkspaceRepository {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return WorkspaceRepository(url: root.appendingPathComponent("MouseElf/workspace.json"))
    }
    public func load() throws -> Workspace {
        guard FileManager.default.fileExists(atPath: url.path) else { return Workspace() }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumWorkspaceBytes else { throw ValidationError.invalid("工作区文件不能超过 25 MB。原文件已保留。") }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumWorkspaceBytes else { throw ValidationError.invalid("工作区文件不能超过 25 MB。原文件已保留。") }
        let workspace = try Self.decoder.decode(Workspace.self, from: data)
        try workspace.validate()
        return workspace
    }
    public func save(_ workspace: Workspace) throws {
        try workspace.validate()
        let data = try Self.encoder.encode(workspace)
        guard data.count <= Self.maximumWorkspaceBytes else { throw ValidationError.invalid("工作区超过 25 MB，尚未覆盖原文件。请导出或整理大型脚本。") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    public static func importScript(from data: Data) throws -> MouseScript {
        guard data.count <= maximumScriptBytes else { throw ValidationError.invalid("导入文件不能超过 5 MB。") }
        let document = try decoder.decode(ScriptDocument.self, from: data)
        guard document.schemaVersion == 1 else { throw ValidationError.invalid("脚本文件版本不受支持。") }
        try document.script.validate()
        var result = document.script
        result.duplicateIdentity()
        return result
    }
    public static func exportScript(_ script: MouseScript) throws -> Data {
        try script.validate()
        let data = try encoder.encode(ScriptDocument(script: script))
        guard data.count <= maximumScriptBytes else { throw ValidationError.invalid("此脚本超过 5 MB，请拆分后导出。") }
        return data
    }
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return encoder
    }
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
}
