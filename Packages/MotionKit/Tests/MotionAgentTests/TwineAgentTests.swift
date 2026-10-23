import Testing
import Foundation
import MotionModel
import MotionEditing
import MotionExport
import MotionEvaluation
@testable import MotionAgent

/// A host on a plain store, as the app's is on the open document.
@MainActor
final class TestHost: AgentHost {
    var store: ProjectStore?
    var projectURL: URL? = URL(fileURLWithPath: "/tmp/Test.twine")
    var isAnimating = true
    var playhead = 0.0
    var selectedLayers: Set<UUID> = []
    var selectedActions: Set<UUID> = []
    var newComposition = Composition()
    var newAction: (duration: Double, easing: Easing) = (0.5, .default)
    var opened: URL?
    var exported: AgentExport?

    init(_ project: Project = Project()) {
        store = ProjectStore(project: project, undoManager: UndoManager())
        store?.undoManager.groupsByEvent = false
    }

    func perform(_ command: EditorCommand) throws { try store?.perform(command) }

    func undo(redo: Bool) -> String? {
        guard let undo = store?.undoManager else { return nil }
        if redo {
            guard undo.canRedo else { return nil }
            let name = undo.redoActionName
            undo.redo()
            return name
        }
        guard undo.canUndo else { return nil }
        let name = undo.undoActionName
        undo.undo()
        return name
    }

    func projects() -> [AgentProject] {
        [AgentProject(name: "Launch", url: URL(fileURLWithPath: "/tmp/Launch.twine"), folder: nil, modified: Date())]
    }
    func openProject(at url: URL) async throws { opened = url }
    func newProject(named name: String?, project: Project) async throws { store = ProjectStore(project: project, undoManager: UndoManager()) }
    func render(at time: Double?, maxSide: Int) async throws -> Data { Data([0x89, 0x50, 0x4E, 0x47]) }
    func importFiles(_ urls: [URL], center: Vec2?) async throws -> [UUID] { [] }
    func fillTemplate(_ frameID: UUID, from slot: Int, with urls: [URL]) async throws {}
    func export(_ request: AgentExport) async throws -> URL {
        exported = request
        return request.url ?? URL(fileURLWithPath: "/tmp/out.mp4")
    }
}

@MainActor
struct TwineAgentTests {
    /// The tool's reply as JSON, failing the test on an error.
    func call(_ agent: TwineAgent, _ name: String, _ args: JSONValue = [:]) async throws -> JSONValue {
        let out = await agent.call(name, args)
        guard case .text(let text)? = out.parts.first else { Issue.record("no text"); return .null }
        #expect(!out.isError, "\(name): \(text)")
        return try JSONValue.parse(Data(text.utf8))
    }

    func refusal(_ agent: TwineAgent, _ name: String, _ args: JSONValue) async -> String {
        let out = await agent.call(name, args)
        #expect(out.isError)
        if case .text(let text)? = out.parts.first { return text }
        return ""
    }

    @Test func aRectangleGoesInWhereItIsAskedAndUndoesInOneStep() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        let reply = try await call(agent, "add_layer", ["type": "rectangle", "x": 100, "y": 50, "width": 300, "height": 200,
                                                        "fill": "#217FD8", "corner_radius": 24, "name": "Card"])
        let id = try #require(UUID(uuidString: reply["id"]?.string ?? ""))
        let layer = try #require(host.store?.project.layer(withID: id))
        #expect(layer.name == "Card")
        #expect(layer.size == Size2(300, 200))
        #expect(ProjectOutline.topLeft(of: layer) == Vec2(100, 50))
        #expect(layer.look?.fills.last?.paint == .solid(RGBA(hex: "217FD8")!))
        #expect(layer.look?.geometry == .rectangle(cornerRadii: CornerRadii(all: 24)))
        #expect(host.undo(redo: false) == "Add Card")
        #expect(host.store?.project.layers.isEmpty == true)
    }

    @Test func textIsPlacedByItsTopLeftAndFitsItsWords() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        let reply = try await call(agent, "add_layer", ["type": "text", "text": "Hello there", "x": 40, "y": 60,
                                                        "font_size": 96, "color": "#FF0000"])
        let id = try #require(UUID(uuidString: reply["id"]?.string ?? ""))
        let layer = try #require(host.store?.project.layer(withID: id))
        guard case .text(let t) = layer.content else { Issue.record("not text"); return }
        #expect(t.text == "Hello there")
        #expect(t.fontSize == 96)
        #expect(t.color == RGBA(hex: "FF0000")!)
        #expect(layer.name == "Hello there")
        let corner = ProjectOutline.topLeft(of: layer)
        #expect(abs(corner.x - 40) < 0.001 && abs(corner.y - 60) < 0.001)
        #expect(layer == layer.fittedText())
    }

    @Test func movingALayerCarriesItsMoveToAlong() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        let id = try #require(UUID(uuidString: try await call(agent, "add_layer", ["type": "ellipse", "x": 0, "y": 0])["id"]?.string ?? ""))
        let added = try await call(agent, "add_action", ["layer_ids": [.string(id.uuidString)], "kind": "move", "start": 0.5,
                                                         "duration": 1, "easing": "bounce",
                                                         "values": ["mode": "to", "end": ["x": 500, "y": 400]]])
        let actionID = try #require(UUID(uuidString: added["actions"]?.array?.first?["id"]?.string ?? ""))
        let before = try #require(host.store?.project.actions.first { $0.id == actionID })
        #expect(before.start == 0.5)
        #expect(before.duration == 1)
        #expect(before.easing == .preset(.bounce, intensity: Easing.standardIntensity))
        guard case .move(let move) = before.spec else { Issue.record("not a move"); return }
        #expect(move.mode == .to && move.end == Vec2(500, 400))

        _ = try await call(agent, "update_layers", ["updates": [["id": .string(id.uuidString), "x": 100]]])
        guard case .move(let moved)? = host.store?.project.actions.first(where: { $0.id == actionID })?.spec else { return }
        #expect(moved.end == Vec2(600, 400))
    }

    @Test func aPatchChangesTheFileJSONAndTakesHexColours() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        let id = try await call(agent, "add_layer", ["type": "rectangle"])["id"]?.string ?? ""
        _ = try await call(agent, "update_layers", ["updates": [[
            "id": .string(id),
            "patch": ["effects": [["kind": ["type": "dropShadow",
                                            "shadow": ["color": "#000000", "offset": ["x": 0, "y": 8], "blur": 24, "opacity": 0.3]]]],
                      "content": ["shape": ["strokes": [["paint": ["type": "solid", "color": "#00FF00"], "width": 3]]]]],
        ]]])
        let layer = try #require(host.store?.project.layer(withID: UUID(uuidString: id)!))
        #expect(layer.effects.count == 1)
        #expect(layer.look?.strokes.first?.width == 3)
        #expect(layer.look?.strokes.first?.paint == .solid(RGBA(hex: "00FF00")!))
        // The id never changes, whatever the patch says.
        let refused = await agent.call("update_layers", ["updates": [["id": .string(id), "patch": ["opacity": "lots"]]]])
        #expect(refused.isError)
        #expect(host.store?.project.layer(withID: UUID(uuidString: id)!)?.opacity == 1)
    }

    @Test func presetsAreFoundByNameEitherWay() throws {
        #expect(try TwineAgent.preset(named: "Fade").kind == .fadeIn)
        #expect(try TwineAgent.preset(named: "Fade Out").kind == .fadeOut)
        #expect(try TwineAgent.preset(named: "slide-out").kind == .slideOut)
        #expect(try TwineAgent.preset(named: "Letters Rise").isText)
        #expect(throws: AgentError.self) { try TwineAgent.preset(named: "Teleport") }
    }

    @Test func aPresetGoesOnAsOneBarWithItsSettings() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        let id = try await call(agent, "add_layer", ["type": "rectangle"])["id"]?.string ?? ""
        let reply = try await call(agent, "add_preset", ["layer_ids": [.string(id)], "preset": "Slide In", "start": 1,
                                                         "settings": ["direction": "left", "distance": 300]])
        let action = try #require(host.store?.project.actions.first)
        #expect(reply["actions"]?.array?.count == 1)
        #expect(action.start == 1)
        guard case .preset(let preset) = action.spec else { Issue.record("not a preset"); return }
        #expect(preset.preset == .slideIn)
        #expect(preset.direction == .left)
        #expect(preset.distance == 300)
    }

    @Test func anActionALayerCannotTakeIsRefusedPlainly() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        let id = try await call(agent, "add_layer", ["type": "text", "text": "Hi"])["id"]?.string ?? ""
        let message = await refusal(agent, "add_action", ["layer_ids": [.string(id)], "kind": "resize"])
        #expect(message.contains("cannot take resize"))
        #expect(host.store?.project.actions.isEmpty == true)
    }

    @Test func groupingAndUngroupingKeepTheLayers() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        let a = try await call(agent, "add_layer", ["type": "rectangle", "x": 0, "y": 0])["id"]?.string ?? ""
        let b = try await call(agent, "add_layer", ["type": "ellipse", "x": 300, "y": 0])["id"]?.string ?? ""
        let grouped = try await call(agent, "arrange_layers", ["operation": "frame", "layer_ids": [.string(a), .string(b)], "name": "Row"])
        let frameID = try #require(UUID(uuidString: grouped["id"]?.string ?? ""))
        #expect(host.store?.project.layer(withID: frameID)?.isFrame == true)
        #expect(host.store?.project.layer(withID: frameID)?.children.count == 2)
        _ = try await call(agent, "arrange_layers", ["operation": "ungroup", "layer_ids": [.string(frameID.uuidString)]])
        #expect(host.store?.project.layers.count == 2)
    }

    @Test func theOutlineListsLayersFrontFirstWithTheirActions() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        _ = try await call(agent, "add_layer", ["type": "rectangle", "name": "Back"])
        let front = try await call(agent, "add_layer", ["type": "ellipse", "name": "Front"])["id"]?.string ?? ""
        _ = try await call(agent, "add_action", ["layer_ids": [.string(front)], "kind": "opacity", "values": ["initial": 0, "end": 1]])
        let outline = try await call(agent, "get_project")
        #expect(outline["layers"]?.array?.map { $0["name"]?.string } == ["Front", "Back"])
        let action = outline["actions"]?.array?.first
        #expect(action?["kind"]?.string == "opacity")
        #expect(action?["values"]?["initial"]?.number == 0)
        let whole = try await call(agent, "get_project", ["layer_ids": [.string(front)]])
        #expect(whole["layers"]?.array?.first?["id"]?.string == front)
        #expect(whole["actions"]?.array?.count == 1)
    }

    @Test func compositionAndViewChangeAsAsked() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        _ = try await call(agent, "set_composition", ["width": 1080, "height": 1920, "duration": 8, "fps": 30, "background": "#101010"])
        let c = try #require(host.store?.project.composition)
        #expect(c.width == 1080 && c.height == 1920 && c.duration == 8 && c.frameRate == .fps30)
        #expect(c.background.color == RGBA(hex: "101010")!)
        _ = try await call(agent, "set_view", ["mode": "design", "time": 2.5])
        #expect(!host.isAnimating)
        #expect(host.playhead == 2.5)
    }

    @Test func templatesTakeTheirSettings() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        let kind = TemplateKind.ringStream
        let control = try #require(TemplateRecipes.controls(kind).first { if case .number = $0.kind { true } else { false } })
        guard case .number(_, let hi, _, _) = control.kind else { return }
        let reply = try await call(agent, "add_template", ["template": "Ring Stream", "settings": [control.key: .number(hi + 1000)]])
        let id = try #require(UUID(uuidString: reply["id"]?.string ?? ""))
        let setup = try #require(host.store?.project.layer(withID: id)?.template)
        #expect(setup.kind == kind)
        #expect(setup.settings[control.key] == .number(hi))
        #expect(host.store?.project.actions.count == 1)
    }

    @Test func undoAndRedoNameTheirSteps() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        _ = try await call(agent, "add_layer", ["type": "star", "name": "Spark"])
        #expect(try await call(agent, "undo")["undone"]?.array == ["Add Spark"])
        #expect(try await call(agent, "undo", ["redo": true])["redone"]?.array == ["Add Spark"])
        #expect(host.store?.project.layers.count == 1)
    }

    @Test func withNothingOpenTheToolsSaySo() async {
        let host = TestHost()
        host.store = nil
        let agent = TwineAgent(host: host)
        #expect(await refusal(agent, "get_project", [:]).contains("No project is open"))
    }

    @Test func exportsAreAskedForPlainly() async throws {
        let host = TestHost()
        let agent = TwineAgent(host: host)
        let reply = try await call(agent, "export", ["format": "gif", "path": "/tmp/loop.gif", "start": 1, "end": 3, "scale": 0.5])
        #expect(reply["path"]?.string == "/tmp/loop.gif")
        #expect(host.exported?.format == .gif)
        #expect(host.exported?.range == 1...3)
        #expect(host.exported?.scale == 0.5)
    }

    @Test func theCatalogCoversEveryKindAndPreset() throws {
        let actions = try #require(AgentCatalog.describe("actions")?["actions"]?["kinds"]?.array)
        let kinds = Set(actions.compactMap { $0["kind"]?.string })
        for kind in ActionKind.allCases where kind != .preset && kind != .template {
            #expect(kinds.contains(kind.rawValue), "\(kind) is missing")
        }
        let presets = try #require(AgentCatalog.describe("presets")?["presets"]?["presets"]?.array)
        #expect(presets.count == Presets.library.count)
        #expect(AgentCatalog.describe("templates")?["templates"]?["templates"]?.array?.count == Templates.library.count)
    }
}

@MainActor
struct MCPServerTests {
    func server() -> MCPServer { TwineAgent(host: TestHost()).server(version: "1") }

    func send(_ server: MCPServer, _ message: JSONValue) async throws -> JSONValue? {
        guard let reply = await server.handle(try message.data()) else { return nil }
        #expect(reply.last == 0x0A)
        #expect(!reply.dropLast().contains(0x0A))
        return try JSONValue.parse(reply)
    }

    @Test func theHandshakeAgreesAVersionAndListsTheTools() async throws {
        let server = server()
        let hello = try await send(server, ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                            "params": ["protocolVersion": "2025-03-26", "capabilities": [:],
                                                       "clientInfo": ["name": "test", "version": "1"]]])
        #expect(hello?["result"]?["protocolVersion"]?.string == "2025-03-26")
        #expect(hello?["result"]?["serverInfo"]?["name"]?.string == "twine")
        #expect(try await send(server, ["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)
        let list = try await send(server, ["jsonrpc": "2.0", "id": "two", "method": "tools/list"])
        #expect(list?["id"]?.string == "two")
        let names = list?["result"]?["tools"]?.array?.compactMap { $0["name"]?.string } ?? []
        #expect(names.count == TwineAgent.tools.count)
        #expect(Set(names).count == names.count)
        for tool in list?["result"]?["tools"]?.array ?? [] {
            #expect(tool["inputSchema"]?["type"]?.string == "object")
        }
    }

    @Test func aCallAnswersWithContentAndErrorsStayInTheResult() async throws {
        let server = server()
        let ok = try await send(server, ["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                         "params": ["name": "get_status", "arguments": [:]]])
        #expect(ok?["result"]?["isError"]?.bool == false)
        #expect(ok?["result"]?["content"]?.array?.first?["type"]?.string == "text")
        let bad = try await send(server, ["jsonrpc": "2.0", "id": 4, "method": "tools/call",
                                          "params": ["name": "add_layer", "arguments": ["type": "hexagon"]]])
        #expect(bad?["result"]?["isError"]?.bool == true)
        let unknown = try await send(server, ["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "fly"]])
        #expect(unknown?["error"]?["code"]?.number == -32602)
        let garbage = await server.handle(Data("{nope".utf8))
        #expect(garbage.flatMap { try? JSONValue.parse($0) }?["error"]?["code"]?.number == -32700)
    }

    /// The bridge answers everything but tool calls without the project, so
    /// an AI app saying hello never opens Twine.
    @Test func theBridgeAnswersAllButToolCallsWithoutTwine() throws {
        let listing = TwineAgent.listing(version: "1")
        let hello: JSONValue = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]]
        guard case .answered(let reply) = listing.answer(try hello.data()) else { Issue.record("not answered"); return }
        #expect(try JSONValue.parse(reply)["result"]?["serverInfo"]?["name"]?.string == "twine")
        for method in ["tools/list", "ping", "resources/list", "prompts/list"] {
            let message: JSONValue = ["jsonrpc": "2.0", "id": 2, "method": .string(method)]
            guard case .answered = listing.answer(try message.data()) else { Issue.record("\(method) needed Twine"); continue }
        }
        let initialized: JSONValue = ["jsonrpc": "2.0", "method": "notifications/initialized"]
        #expect(listing.answer(try initialized.data()) == .silent)
        let unknown: JSONValue = ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "fly"]]
        guard case .answered = listing.answer(try unknown.data()) else { Issue.record("an unknown tool needed Twine"); return }
        let call: JSONValue = ["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "get_status", "arguments": [:]]]
        #expect(listing.answer(try call.data()) == .toolCall(id: 4, name: "get_status", arguments: [:]))
    }

    @Test func picturesComeBackAsImages() async throws {
        let server = server()
        let reply = try await send(server, ["jsonrpc": "2.0", "id": 6, "method": "tools/call",
                                            "params": ["name": "render_frame", "arguments": [:]]])
        let image = reply?["result"]?["content"]?.array?.first { $0["type"]?.string == "image" }
        #expect(image?["mimeType"]?.string == "image/png")
        #expect(image?["data"]?.string == Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())
    }
}

struct JSONValueTests {
    @Test func mergePatchFollowsRFC7386() throws {
        let base: JSONValue = ["a": "b", "c": ["d": "e", "f": "g"], "list": [1, 2]]
        let patch: JSONValue = ["a": "z", "c": ["f": nil], "list": [3]]
        #expect(base.merged(with: patch) == ["a": "z", "c": ["d": "e"], "list": [3]])
        #expect(base.merged(with: "plain") == "plain")
    }

    @Test func numbersRoundTrip() throws {
        let value: JSONValue = ["whole": 3, "part": 0.25, "flag": true, "none": nil]
        #expect(try JSONValue.parse(value.data()) == value)
        #expect(String(data: try JSONValue.number(3).data(), encoding: .utf8) == "3")
    }
}
