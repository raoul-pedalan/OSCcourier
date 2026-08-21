//
//  OSCManager.swift
//  OSCcourier
//
//  Created by bernard pierre on 29/06/2026.
//


import Foundation
import Darwin
import Combine

// A parsed OSC argument. Only the types OSCcourier actually needs to
// receive are supported (float, int, string) — anything else in the type
// tag string is simply skipped rather than crashing the parser.
enum OSCValue {
    case float(Float)
    case int(Int32)
    case string(String)
}

class OSCManager: ObservableObject {
    @Published var address: String = "127.0.0.1:7400"
    @Published var isConnected = true
    // Set when startListening fails (most commonly: another window already
    // has this port bound) — surfaced as an alert by ContentView instead of
    // failing silently to the Xcode console, since each window can now pick
    // its own port and a collision is easy to hit by accident.
    @Published var lastListenError: String?

    // MARK: - Receiving OSC messages (transport control from the outside)
    private var listenSocketFD: Int32 = -1
    private var isListening = false
    // Called (on the main thread) whenever a message is received, with the
    // decoded address string (e.g. "/play") and any OSC arguments that came
    // with it (e.g. a float for "/goto 12.5"). Set this from ContentView.
    var onOSCMessageReceived: ((String, [OSCValue]) -> Void)?

    private func padTo4(_ data: Data) -> Data {
        let remainder = data.count % 4
        return remainder == 0 ? data : data + Data(repeating: 0, count: 4 - remainder)
    }

    func setupOSCConnection() {
        isConnected = true
    }

    // One UDP socket, opened lazily and kept open across sends — a curve
    // track sends continuously during playback (every tick, not just at
    // point crossings), so creating and closing a fresh socket() on every
    // single sendMessage() call added a real, avoidable syscall cost on
    // the main thread at up to 20 times/sec per curve track. Closed and
    // reset in cancelConnection()/deinit.
    private var sendSocketFD: Int32 = -1

    private func ensureSendSocket() -> Int32? {
        if sendSocketFD >= 0 { return sendSocketFD }
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            print("OSC: Could not create the socket (errno: \(errno))")
            return nil
        }
        sendSocketFD = fd
        return fd
    }

    func sendMessage(_ message: String) {
        let parts = address.split(separator: ":")
        guard parts.count == 2,
              let host = parts.first,
              let port = Int(parts.last!) else {
            print("OSC: Adresse invalide")
            return
        }

        guard let socketFD = ensureSendSocket() else { return }

        var serverAddress = sockaddr_in()
        memset(&serverAddress, 0, MemoryLayout<sockaddr_in>.size)
        serverAddress.sin_family = sa_family_t(AF_INET)
        serverAddress.sin_port = in_port_t(port).bigEndian

        var inAddr = in_addr()
        let hostString = String(host)
        if hostString.withCString({ inet_pton(AF_INET, $0, &inAddr) }) != 1 {
            // Just a bad destination string — the (now persistent) send
            // socket itself is still fine, so don't close it here.
            print("OSC: Adresse IP invalide")
            return
        }
        serverAddress.sin_addr = inAddr

        // `message` arrives as "/address value" (or just "/address" for a
        // bare trigger like a bang). Split it so the OSC address pattern and
        // the argument are encoded as separate, properly-typed OSC fields —
        // sending the whole string as the "address" with an empty type tag
        // (the old behavior) produces a malformed packet that lenient
        // receivers like Max tolerate but strict ones (e.g. Monitor OSC)
        // silently reject.
        let oscAddress: String
        let argument: String?
        if let spaceIdx = message.firstIndex(of: " ") {
            oscAddress = String(message[message.startIndex..<spaceIdx])
            argument = String(message[message.index(after: spaceIdx)...])
        } else {
            oscAddress = message
            argument = nil
        }

        let addressData = padTo4(Data((oscAddress + "\0").utf8))

        var typeTagData: Data
        var argumentData = Data()

        if let argument, argument != "bang", let floatValue = Float(argument) {
            typeTagData = padTo4(Data(",f\0".utf8))
            var bits = floatValue.bitPattern.bigEndian
            argumentData = Data(bytes: &bits, count: 4)
        } else if let argument, argument != "bang" {
            typeTagData = padTo4(Data(",s\0".utf8))
            argumentData = padTo4(Data((argument + "\0").utf8))
        } else {
            typeTagData = padTo4(Data(",\0".utf8))
        }

        let data = addressData + typeTagData + argumentData

        let bytesSent = data.withUnsafeBytes { buffer in
            var addr = sockaddr()
            memcpy(&addr, &serverAddress, MemoryLayout<sockaddr_in>.size)
            return sendto(socketFD, buffer.baseAddress, data.count, 0, &addr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }

        if bytesSent < 0 {
            print("OSC: Failed (errno: \(errno))")
        }
    }

    func cancelConnection() {
        isConnected = false
        if sendSocketFD >= 0 {
            close(sendSocketFD)
            sendSocketFD = -1
        }
    }

    deinit {
        if sendSocketFD >= 0 {
            close(sendSocketFD)
        }
    }

    // MARK: - Receiving

    // Starts listening for incoming UDP/OSC messages on the given port.
    // Stops any previous listener first, so it's safe to call again when the
    // port setting changes.
    func startListening(port: Int) {
        stopListening()

        let socketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFD >= 0 else {
            let errorCode = errno
            print("OSC: Could not create the listen socket (errno: \(errorCode))")
            lastListenError = "Could not create the listening connection needed to receive OSC. Try again, or restart the app if this keeps happening."
            return
        }

        var addr = sockaddr_in()
        memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let errorCode = errno
            print("OSC: Could not bind to port \(port) (errno: \(errorCode))")
            if errorCode == EADDRINUSE {
                lastListenError = "Port \(port) is already in use — probably by another window, or another app. Choose a different port."
            } else {
                lastListenError = "Could not listen for OSC on port \(port). Try a different port."
            }
            close(socketFD)
            return
        }

        listenSocketFD = socketFD
        isListening = true
        lastListenError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                guard let self = self, self.isListening else { break }
                let bytesRead = recv(socketFD, &buffer, buffer.count, 0)
                guard bytesRead > 0 else { continue }

                guard let (address, args) = self.parseOSCPacket(Array(buffer[0..<bytesRead])) else { continue }

                DispatchQueue.main.async {
                    self.onOSCMessageReceived?(address, args)
                }
            }
        }

        print("OSC: écoute sur le port \(port)")
    }

    // Parses a standard OSC packet: a null-terminated, 4-byte-padded address
    // string, optionally followed by a null-terminated, 4-byte-padded type
    // tag string (starting with ",") and the arguments it describes.
    //
    // This app's own outgoing messages (see sendMessage) are argument-less
    // (just an address + an empty "," type tag), but other senders (Max's
    // udpsend, TouchOSC, etc.) may send real arguments, or may not even
    // null-terminate the address at all for plain-text UDP — both are
    // handled here, falling back to "address only, no args" whenever the
    // packet doesn't look like a fully-formed OSC message.
    private func parseOSCPacket(_ bytes: [UInt8]) -> (address: String, args: [OSCValue])? {
        guard let addrNullIdx = bytes.firstIndex(of: 0) else {
            // No null terminator anywhere — raw text, no args possible.
            let address = String(bytes: bytes, encoding: .utf8) ?? ""
            return address.isEmpty ? nil : (address, [])
        }
        guard let address = String(bytes: bytes[0..<addrNullIdx], encoding: .utf8), !address.isEmpty else {
            return nil
        }

        var i = ((addrNullIdx / 4) + 1) * 4
        guard i < bytes.count, bytes[i] == UInt8(ascii: ",") else {
            // No type tag: either no arguments, or a non-OSC sender — either
            // way, just the address.
            return (address, [])
        }
        guard let tagNullIdx = bytes[i...].firstIndex(of: 0) else {
            return (address, [])
        }
        let typeTags = String(bytes: bytes[(i + 1)..<tagNullIdx], encoding: .utf8) ?? ""
        i = (((tagNullIdx - i) / 4) + 1) * 4 + i

        var args: [OSCValue] = []
        for tag in typeTags {
            switch tag {
            case "f":
                guard i + 4 <= bytes.count else { return (address, args) }
                let bits = (UInt32(bytes[i]) << 24) | (UInt32(bytes[i + 1]) << 16) | (UInt32(bytes[i + 2]) << 8) | UInt32(bytes[i + 3])
                args.append(.float(Float(bitPattern: bits)))
                i += 4
            case "i":
                guard i + 4 <= bytes.count else { return (address, args) }
                let bits = (UInt32(bytes[i]) << 24) | (UInt32(bytes[i + 1]) << 16) | (UInt32(bytes[i + 2]) << 8) | UInt32(bytes[i + 3])
                args.append(.int(Int32(bitPattern: bits)))
                i += 4
            case "s":
                guard let sNullIdx = bytes[i...].firstIndex(of: 0) else { return (address, args) }
                let str = String(bytes: bytes[i..<sNullIdx], encoding: .utf8) ?? ""
                args.append(.string(str))
                i = (((sNullIdx - i) / 4) + 1) * 4 + i
            default:
                // Unsupported tag (blob, true/false, etc.) — stop parsing
                // further arguments rather than misreading their bytes.
                return (address, args)
            }
        }
        return (address, args)
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        if listenSocketFD >= 0 {
            close(listenSocketFD)
            listenSocketFD = -1
        }
    }
}
