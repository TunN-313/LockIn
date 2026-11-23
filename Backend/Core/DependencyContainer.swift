// DependencyContainer.swift — Khởi tạo và cung cấp các Backend modules cho Frontend thông qua protocols.
// Cung cấp factory makeLive() và makeForTesting() lắp ghép đầy đủ 8 modules mà không làm lộ chi tiết lưu trữ.

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class DependencyContainer {
    public let syncEventBus: SyncEventBus
    public let snapshotStore: AppGroupSnapshotStoreProtocol

    public let auth: AuthModuleProtocol
    public let security: SecurityModuleProtocol
    public let study: StudyModuleProtocol
    public let scheduler: SchedulerModuleProtocol
    public let theme: ThemeModuleProtocol
    public let lockScreen: LockScreenModuleProtocol
    public let backup: BackupModuleProtocol
    public let storageMaintenance: StorageMaintenanceProtocol

    public init(
        syncEventBus: SyncEventBus,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        auth: AuthModuleProtocol,
        security: SecurityModuleProtocol,
        study: StudyModuleProtocol,
        scheduler: SchedulerModuleProtocol,
        theme: ThemeModuleProtocol,
        lockScreen: LockScreenModuleProtocol,
        backup: BackupModuleProtocol,
        storageMaintenance: StorageMaintenanceProtocol
    ) {
        self.syncEventBus = syncEventBus
        self.snapshotStore = snapshotStore
        self.auth = auth
        self.security = security
        self.study = study
        self.scheduler = scheduler
        self.theme = theme
        self.lockScreen = lockScreen
        self.backup = backup
        self.storageMaintenance = storageMaintenance
    }

    public static func makeLive(
        appGroupId: String = AppConstants.resolvedAppGroupIdentifier
    ) throws -> DependencyContainer {
        let modelContainer = try SharedStoreContainer.makeShared(appGroupId: appGroupId)
        let snapshotStore = try AppGroupSnapshotStore.makeShared(appGroupId: appGroupId)
        let keychain = KeychainStorageService()
        return makeConfigured(
            modelContainer: modelContainer,
            snapshotStore: snapshotStore,
            keychain: keychain,
            notificationService: LocalNotificationService(),
            appGroupId: appGroupId,
            enableDarwinObserver: true
        )
    }

    public static func makeForTesting(
        modelContainer: ModelContainer,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        keychain: KeychainStorageProtocol,
        notificationService: LocalNotificationServiceProtocol = LocalNotificationService(),
        enableDarwinObserver: Bool = false
    ) -> DependencyContainer {
        makeConfigured(
            modelContainer: modelContainer,
            snapshotStore: snapshotStore,
            keychain: keychain,
            notificationService: notificationService,
            appGroupId: AppConstants.defaultAppGroupIdentifier,
            enableDarwinObserver: enableDarwinObserver
        )
    }

    private static func makeConfigured(
        modelContainer: ModelContainer,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        keychain: KeychainStorageProtocol,
        notificationService: LocalNotificationServiceProtocol,
        appGroupId: String,
        enableDarwinObserver: Bool
    ) -> DependencyContainer {
        let syncEventBus = SyncEventBus(
            snapshotStore: snapshotStore,
            enableDarwinObserver: enableDarwinObserver
        )
        let isolationGuard = UserDataIsolationGuard(keychain: keychain)
        let crypto = PasswordCryptoService()
        let studyStore = SwiftDataStudyStore(
            modelContainer: modelContainer,
            isolationGuard: isolationGuard,
            snapshotStore: snapshotStore,
            syncEventBus: syncEventBus
        )

        let securityService = BiometricPinLockService(
            studyStore: studyStore,
            isolationGuard: isolationGuard,
            keychain: keychain,
            crypto: crypto
        )
        let authService = LocalAuthService(
            studyStore: studyStore,
            isolationGuard: isolationGuard,
            keychain: keychain,
            crypto: crypto,
            notificationService: notificationService,
            snapshotStore: snapshotStore,
            syncEventBus: syncEventBus
        )

        let parser = QuickImportParserService()
        let taskProgressService = TaskProgressStreakService(
            studyStore: studyStore,
            isolationGuard: isolationGuard,
            snapshotStore: snapshotStore,
            syncEventBus: syncEventBus
        )
        let studyService = StudyDeckCardService(
            studyStore: studyStore,
            isolationGuard: isolationGuard,
            snapshotStore: snapshotStore,
            syncEventBus: syncEventBus,
            parser: parser,
            taskProgressService: taskProgressService
        )

        let schedulerService = StudyScheduleService(
            studyStore: studyStore,
            isolationGuard: isolationGuard,
            notificationService: notificationService
        )

        let catalogService = ThemeCatalogService(
            studyStore: studyStore,
            isolationGuard: isolationGuard,
            snapshotStore: snapshotStore,
            syncEventBus: syncEventBus
        )
        let sharedRotationEngine = SharedThemeRotationEngine(
            modelContainer: modelContainer,
            snapshotStore: snapshotStore
        )
        let themeService = ThemeShuffleEngine(
            catalogService: catalogService,
            sharedRotationEngine: sharedRotationEngine
        )

        let permissionChecker = DevicePermissionChecker(appGroupId: appGroupId)
        let wallpaperRenderer = StudyWallpaperRenderService()
        let lockScreenService = LiveActivityBridgeService(
            studyStore: studyStore,
            isolationGuard: isolationGuard,
            snapshotStore: snapshotStore,
            permissionChecker: permissionChecker,
            wallpaperRenderer: wallpaperRenderer,
            syncEventBus: syncEventBus
        )

        let backupService = EncryptedBackupService(
            studyStore: studyStore,
            isolationGuard: isolationGuard,
            crypto: crypto,
            lockScreenService: lockScreenService,
            schedulerService: schedulerService,
            snapshotStore: snapshotStore,
            syncEventBus: syncEventBus
        )

        return DependencyContainer(
            syncEventBus: syncEventBus,
            snapshotStore: snapshotStore,
            auth: authService,
            security: securityService,
            study: studyService,
            scheduler: schedulerService,
            theme: themeService,
            lockScreen: lockScreenService,
            backup: backupService,
            storageMaintenance: studyStore
        )
    }
}
