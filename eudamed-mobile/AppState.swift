import Observation
import EudamedClient

@MainActor
@Observable
final class AppState {
    let actorRepository: any ActorRepository
    let deviceRepository: any UdiDevicesRepository

    init() {
        actorRepository = try! RemoteActorRepository()
        deviceRepository = try! RemoteUdiDevicesRepository()
    }
}
