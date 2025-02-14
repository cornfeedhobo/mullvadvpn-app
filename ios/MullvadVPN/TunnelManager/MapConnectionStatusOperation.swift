//
//  MapConnectionStatusOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 15/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadLogging
import MullvadREST
import MullvadTypes
import NetworkExtension
import Operations
import TunnelProviderMessaging

class MapConnectionStatusOperation: AsyncOperation {
    private let interactor: TunnelInteractor
    private let connectionStatus: NEVPNStatus
    private var request: Cancellable?
    private var pathStatus: Network.NWPath.Status?

    private let logger = Logger(label: "TunnelManager.MapConnectionStatusOperation")

    init(
        queue: DispatchQueue,
        interactor: TunnelInteractor,
        connectionStatus: NEVPNStatus,
        networkStatus: Network.NWPath.Status?
    ) {
        self.interactor = interactor
        self.connectionStatus = connectionStatus
        pathStatus = networkStatus

        super.init(dispatchQueue: queue)
    }

    override func main() {
        guard let tunnel = interactor.tunnel else {
            setTunnelDisconnectedStatus()

            finish()
            return
        }

        let tunnelState = interactor.tunnelStatus.state

        switch connectionStatus {
        case .connecting:
            switch tunnelState {
            case .connecting:
                break

            default:
                interactor.updateTunnelStatus { tunnelStatus in
                    tunnelStatus.state = .connecting(nil)
                }
            }

            fetchTunnelStatus(tunnel: tunnel) { packetTunnelStatus in
                if packetTunnelStatus.isNetworkReachable {
                    return packetTunnelStatus.tunnelRelay.map { .connecting($0) }
                } else {
                    return .waitingForConnectivity(.noConnection)
                }
            }
            return

        case .reasserting:
            fetchTunnelStatus(tunnel: tunnel) { packetTunnelStatus in
                if packetTunnelStatus.isNetworkReachable {
                    return packetTunnelStatus.tunnelRelay.map { .reconnecting($0) }
                } else {
                    return .waitingForConnectivity(.noConnection)
                }
            }
            return

        case .connected:
            fetchTunnelStatus(tunnel: tunnel) { packetTunnelStatus in
                if packetTunnelStatus.isNetworkReachable {
                    return packetTunnelStatus.tunnelRelay.map { .connected($0) }
                } else {
                    return .waitingForConnectivity(.noConnection)
                }
            }
            return

        case .disconnected:
            switch tunnelState {
            case .pendingReconnect:
                logger.debug("Ignore disconnected state when pending reconnect.")

            case .disconnecting(.reconnect):
                logger.debug("Restart the tunnel on disconnect.")
                interactor.updateTunnelStatus { tunnelStatus in
                    tunnelStatus = TunnelStatus()
                    tunnelStatus.state = .pendingReconnect
                }
                interactor.startTunnel()

            default:
                setTunnelDisconnectedStatus()
            }

        case .disconnecting:
            switch tunnelState {
            case .disconnecting:
                break
            default:
                interactor.updateTunnelStatus { tunnelStatus in
                    let packetTunnelStatus = tunnelStatus.packetTunnelStatus

                    tunnelStatus = TunnelStatus()
                    tunnelStatus.state = packetTunnelStatus.isNetworkReachable
                        ? .disconnecting(.nothing)
                        : .waitingForConnectivity(.noNetwork)
                }
            }

        case .invalid:
            setTunnelDisconnectedStatus()

        @unknown default:
            logger.debug("Unknown NEVPNStatus: \(connectionStatus.rawValue)")
        }

        finish()
    }

    override func operationDidCancel() {
        request?.cancel()
    }

    private func setTunnelDisconnectedStatus() {
        interactor.updateTunnelStatus { tunnelStatus in
            tunnelStatus = TunnelStatus()
            tunnelStatus.state = pathStatus == .unsatisfied
                ? .waitingForConnectivity(.noNetwork)
                : .disconnected
        }
    }

    private func fetchTunnelStatus(
        tunnel: Tunnel,
        mapToState: @escaping (PacketTunnelStatus) -> TunnelState?
    ) {
        request = tunnel.getTunnelStatus { [weak self] completion in
            guard let self = self else { return }

            self.dispatchQueue.async {
                if case let .success(packetTunnelStatus) = completion, !self.isCancelled {
                    self.interactor.updateTunnelStatus { tunnelStatus in
                        tunnelStatus.packetTunnelStatus = packetTunnelStatus

                        if let newState = mapToState(packetTunnelStatus) {
                            tunnelStatus.state = newState
                        }
                    }
                }

                self.finish()
            }
        }
    }
}
