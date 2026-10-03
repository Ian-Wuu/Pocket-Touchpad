import Foundation
import Network

@main
struct TransportCheck {
    static var server: NWListener!
    static var peers: [Channel] = []
    static var good: Channel!
    static var bad: Channel!
    static var received: [InputEvent] = []
    static var correctPassed = false
    static var wrongRejected = false
    static func finish() {
        if correctPassed && wrongRejected { print("PASS: TLS pairing, wrong-key rejection, ordered movement/text, Unicode round-trip"); exit(0) }
    }
    static func main() throws {
        assert(Motion.dualIntent(spread: 3, translation: 2) == "pending")
        assert(Motion.dualIntent(spread: 2, translation: 20) == "move")
        assert(Motion.dualIntent(spread: 24, translation: 5) == "zoom")
        assert(Motion.dualIntent(spread: 9, translation: 20) == "move")
        let key = TouchWire.newKey()
        assert(TouchWire.validKey(key))
        assert(!TouchWire.validKey("123456"))
        server = try NWListener(using: TouchWire.parameters(key: key), on: .any)
        server.newConnectionHandler = { connection in
            let peer = Channel(connection)
            peer.onEvent = { event in
                received.append(event)
                if event.kind == "text" {
                    precondition(event.text == "你好，Mac 👋🏽 café")
                    precondition(received.last(where: { $0.kind == "absolute" })?.x == 1)
                    precondition(received.suffix(2).map(\.kind) == ["key", "text"])
                    let scroll = received.filter { $0.kind == "scroll" }
                    precondition(scroll.first?.action == "begin" && scroll.last?.action == "end")
                    precondition(scroll.filter { $0.action == "change" }.map(\.y).reduce(0,+) == 50)
                    let pointer=received.filter { $0.kind == "pointer" }
                    precondition(pointer.count == 60)
                    precondition(pointer.enumerated().allSatisfy { $0.element.x == Double($0.offset) && $0.element.dt == 1/120 })
                    correctPassed = true
                    finish()
                }
            }
            peers.append(peer)
            peer.start()
        }
        server.stateUpdateHandler = { state in
            if case .ready = state {
                good = Channel(NWConnection(host: "127.0.0.1", port: server.port!, using: TouchWire.parameters(key: key)))
                good.onState = { ready, message in
                    guard ready else { print("Good peer failed: \(message)"); exit(1) }
                    for i in 0...100 { good.send(InputEvent(kind: "absolute", x: Double(i) / 100, y: 0.5)) }
                    good.send(InputEvent(kind: "scroll", action: "begin"))
                    for _ in 0..<50 { good.send(InputEvent(kind: "scroll", y: 1, action: "change")) }
                    good.send(InputEvent(kind: "scroll", action: "end"))
                    for i in 0..<60 { good.send(InputEvent(kind:"pointer",x:Double(i),dt:1/120)) }
                    good.send(InputEvent(kind: "key", action: "return"))
                    good.send(InputEvent(kind: "text", text: "你好，Mac 👋🏽 café"))
                }
                good.start()
                bad = Channel(NWConnection(host: "127.0.0.1", port: server.port!, using: TouchWire.parameters(key: TouchWire.newKey())))
                bad.onState = { ready, _ in
                    precondition(!ready, "Wrong key must never authenticate")
                    wrongRejected = true
                    finish()
                }
                bad.start()
            }
        }
        server.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { print("FAIL: network test timeout"); exit(1) }
        dispatchMain()
    }
}
