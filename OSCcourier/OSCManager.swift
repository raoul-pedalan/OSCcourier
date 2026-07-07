//
//  OSCManager.swift
//  OSCcourier
//
//  Created by bernard pierre on 29/06/2026.
//


import Foundation
import Darwin
import Combine

class OSCManager: ObservableObject {
    @Published var address: String = "127.0.0.1:7400"
    @Published var isConnected = true

    // MARK: - Receiving OSC messages (transport control from the outside)
    private var listenSocketFD: Int32 = -1
    private var isListening = false
    // Called (on the main thread) whenever a message is received, with the
    // decoded address string (e.g. "/play"). Set this from ContentView.
    var onOSCMessageReceived: ((String) -> Void)?

    private func padTo4(_ data: Data) -> Data {
        let remainder = data.count % 4
        return remainder == 0 ? data : data + Data(repeating: 0, count: 4 - remainder)
    }

    func setupOSCConnection() {
        isConnected = true
    }

    func sendMessage(_ message: String) {
        let parts = address.split(separator: ":")
        guard parts.count == 2,
              let host = parts.first,
              let port = Int(parts.last!) else {
            print("OSC: Adresse invalide")
            return
        }

        let socketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFD >= 0 else {
            print("OSC: Impossible de créer le socket (errno: \(errno))")
            return
        }

        var serverAddress = sockaddr_in()
        memset(&serverAddress, 0, MemoryLayout<sockaddr_in>.size)
        serverAddress.sin_family = sa_family_t(AF_INET)
        serverAddress.sin_port = in_port_t(port).bigEndian

        var inAddr = in_addr()
        let hostString = String(host)
        if hostString.withCString({ inet_pton(AF_INET, $0, &inAddr) }) != 1 {
            print("OSC: Adresse IP invalide")
            close(socketFD)
            return
        }
        serverAddress.sin_addr = inAddr

        let addressData = padTo4(Data((message + "\0").utf8))
        let typeTagData = padTo4(Data(",\0".utf8))
        let data = addressData + typeTagData

        let bytesSent = data.withUnsafeBytes { buffer in
            var addr = sockaddr()
            memcpy(&addr, &serverAddress, MemoryLayout<sockaddr_in>.size)
            return sendto(socketFD, buffer.baseAddress, data.count, 0, &addr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }

        if bytesSent < 0 {
            print("OSC: Echec (errno: \(errno))")
        } else {
            print("OSC: \(message) envoyé")
        }

        close(socketFD)
    }

    func cancelConnection() {
        isConnected = false
    }

    // MARK: - Receiving

    // Starts listening for incoming UDP/OSC messages on the given port.
    // Stops any previous listener first, so it's safe to call again when the
    // port setting changes.
    func startListening(port: Int) {
        stopListening()

        let socketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFD >= 0 else {
            print("OSC: Impossible de créer le socket d'écoute (errno: \(errno))")
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
            print("OSC: Impossible de réserver le port \(port) pour l'écoute (errno: \(errno))")
            close(socketFD)
            return
        }

        listenSocketFD = socketFD
        isListening = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                guard let self = self, self.isListening else { break }
                let bytesRead = recv(socketFD, &buffer, buffer.count, 0)
                guard bytesRead > 0 else { continue }

                let data = Data(buffer[0..<bytesRead])
                // This app's own OSC messages are a null-terminated "address"
                // string followed by a padded type-tag chunk, but other
                // senders (e.g. Max's udpsend) may just send raw, unpadded
                // text with no null terminator at all — so fall back to
                // treating the whole datagram as the message in that case.
                let message: String
                if let nullIndex = data.firstIndex(of: 0) {
                    message = String(data: data[0..<nullIndex], encoding: .utf8) ?? ""
                } else {
                    message = String(data: data, encoding: .utf8) ?? ""
                }
                guard !message.isEmpty else { continue }

                DispatchQueue.main.async {
                    self.onOSCMessageReceived?(message)
                }
            }
        }

        print("OSC: écoute sur le port \(port)")
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
