import Testing
import UIKit
@testable import AOXFoundationKit

@Suite @MainActor
struct RegistryAndModuleReviewTests {
    @Test
    func sameShortTypeNamesAndTagsHaveIndependentRegistrations() throws {
        let registry = ServiceRegistry()
        registry.register(FirstNamespace.Service.self) { FirstNamespace.Service(value: 1) }
        registry.register(SecondNamespace.Service.self) { SecondNamespace.Service(value: 2) }
        registry.register(FirstNamespace.Service.self, tag: "same") { FirstNamespace.Service(value: 3) }
        registry.register(SecondNamespace.Service.self, tag: "same") { SecondNamespace.Service(value: 4) }

        #expect(try #require(registry.resolveOptional(FirstNamespace.Service.self)).value == 1)
        #expect(try #require(registry.resolveOptional(SecondNamespace.Service.self)).value == 2)
        #expect(try #require(registry.resolveOptional(FirstNamespace.Service.self, tag: "same")).value == 3)
        #expect(try #require(registry.resolveOptional(SecondNamespace.Service.self, tag: "same")).value == 4)
    }

    @Test
    func aliasesAndNestedSingletonResolutionKeepWorking() throws {
        let registry = ServiceRegistry()
        registry.register(SecondNamespace.Service.self) { SecondNamespace.Service(value: 8) }
        registry.register(RegistryConcreteService.self) {
            RegistryConcreteService(value: registry.resolve(SecondNamespace.Service.self).value)
        }
        registry.registerAlias((any RegistryReviewProtocol).self, for: RegistryConcreteService.self)

        let concrete = try #require(registry.resolveOptional(RegistryConcreteService.self))
        let alias = try #require(registry.resolveOptional((any RegistryReviewProtocol).self))
        #expect(concrete.value == 8)
        #expect(alias === concrete)
        #expect(registry.isRegistered((any RegistryReviewProtocol).self))
    }

    @Test
    func repeatedPrivacyAndRemainingRegistrationRegisterEachModuleOnce() {
        let manager = ModuleManager()
        let privacy = PrivacyReviewModule()
        let regular = RegularReviewModule()
        manager.add([privacy, regular])
        let context = AppContext(application: UIApplication.shared)

        manager.registerPrivacyModules(context: context)
        manager.registerPrivacyModules(context: context)
        #expect(privacy.registrations == 1)
        #expect(regular.registrations == 0)
        manager.registerRemainingModules()
        manager.registerRemainingModules()
        manager.registerAll(context: context)
        manager.initializeAll()
        manager.initializeAll()

        #expect(privacy.registrations == 1)
        #expect(regular.registrations == 1)
        #expect(privacy.initializations == 1)
        #expect(regular.initializations == 1)
        manager.reset()
    }

    @Test
    func privacyToRegisterAllAndResetPreserveRegistrationLifecycle() {
        let manager = ModuleManager()
        let privacy = PrivacyReviewModule()
        let regular = RegularReviewModule()
        manager.add([privacy, regular])
        let context = AppContext(application: UIApplication.shared)

        manager.registerPrivacyModules(context: context)
        manager.registerAll(context: context)
        #expect(privacy.registrations == 1)
        #expect(regular.registrations == 1)
        manager.reset()
        manager.add([privacy, regular])
        manager.registerAll(context: context)
        #expect(privacy.registrations == 2)
        #expect(regular.registrations == 2)
        manager.reset()
    }
}

private enum FirstNamespace {
    struct Service { let value: Int }
}
private enum SecondNamespace {
    struct Service { let value: Int }
}

private protocol RegistryReviewProtocol: AnyObject {
    var value: Int { get }
}
private final class RegistryConcreteService: RegistryReviewProtocol {
    let value: Int
    init(value: Int) { self.value = value }
}

@MainActor
private final class PrivacyReviewModule: AppModule {
    static var supportsPrivacyMode: Bool { true }
    var registrations = 0
    var initializations = 0
    func register(context: AppContext) { registrations += 1 }
    func initialize(context: AppContext) { initializations += 1 }
}

@MainActor
private final class RegularReviewModule: AppModule {
    var registrations = 0
    var initializations = 0
    func register(context: AppContext) { registrations += 1 }
    func initialize(context: AppContext) { initializations += 1 }
}
