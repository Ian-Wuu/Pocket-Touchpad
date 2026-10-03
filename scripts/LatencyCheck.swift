import Foundation
import Network

@main
struct LatencyCheck {
    static var listener: NWListener!
    static var server: Channel!
    static var client: Channel!
    static var timer: DispatchSourceTimer?
    static var samples: [Double] = []
    static var sent = 0
    static func main() throws {
        let key = TouchWire.newKey()
        listener = try NWListener(using: TouchWire.parameters(key: key), on: .any)
        listener.newConnectionHandler = { connection in
            server = Channel(connection)
            server.onEvent = { server.send($0) }
            server.start()
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            client = Channel(NWConnection(host: "127.0.0.1", port: listener.port!, using: TouchWire.parameters(key: key)))
            client.onState = { ready, reason in
                guard ready else { print(reason); exit(1) }
                timer = DispatchSource.makeTimerSource(queue: .main)
                timer?.schedule(deadline: .now(), repeating: 1.0 / 120)
                timer?.setEventHandler {
                    client.send(InputEvent(kind: "probe", x: ProcessInfo.processInfo.systemUptime))
                    sent += 1
                    if sent == 240 { timer?.cancel() }
                }
                timer?.resume()
            }
            client.onEvent = { event in
                samples.append((ProcessInfo.processInfo.systemUptime - event.x) * 1000)
                if samples.count == 240 {
                    let sorted = samples.sorted()
                    print(String(format: "loopback TLS RTT: median %.3f ms; p95 %.3f ms; max %.3f ms; 240 packets at 120 Hz", sorted[120], sorted[228], sorted[239]))
                    exit(0)
                }
            }
            client.start()
        }
        listener.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { print("FAIL: latency check timeout"); exit(1) }
        dispatchMain()
    }
}
