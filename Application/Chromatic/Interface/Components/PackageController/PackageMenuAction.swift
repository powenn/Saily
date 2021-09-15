//
//  PackageMenuAction.swift
//  Chromatic
//
//  Created by Lakr Aream on 2021/8/24.
//  Copyright © 2021 Lakr Aream. All rights reserved.
//

import AptRepository
import SPIndicator
import UIKit

class PackageMenuAction {
    enum ActionDescriptor: String, CaseIterable {
        case directInstall
        case install
        case reinstall
        case downgrade
        case update
        case remove
        case cancelQueue
        case versionControl
        case blockUpdate
        case unblockUpdate

        func describe() -> String {
            switch self {
            case .directInstall:
                return NSLocalizedString("DIRECT_INSTALL", comment: "Direct Install")
            case .install:
                return NSLocalizedString("INSTALL", comment: "Install")
            case .reinstall:
                return NSLocalizedString("REINSTALL", comment: "Reinstall")
            case .downgrade:
                return NSLocalizedString("DOWNGRADE", comment: "Downgrade")
            case .update:
                return NSLocalizedString("UPDATE", comment: "Update")
            case .remove:
                return NSLocalizedString("REMOVE", comment: "Remove")
            case .cancelQueue:
                return NSLocalizedString("CANCEL_QUEUE", comment: "Cancel Queue")
            case .versionControl:
                return NSLocalizedString("VERSION_CONTROL", comment: "Version Control")
            case .blockUpdate:
                return NSLocalizedString("BLOCK_UPDATE", comment: "Block Update")
            case .unblockUpdate:
                return NSLocalizedString("UNBLOCK_UPDATE", comment: "Unblock Update")
            }
        }
    }

    struct MenuAction {
        let descriptor: ActionDescriptor
        let block: (Package, UIView) -> Void
        let elegantForPerform: (Package) -> (Bool)
    }

    // MARK: - ACTIONS

    // MARK: - INSTALL KIND

    static let resolveInstallRequest = { (package: Package, view: UIView) in

        if let version = package.latestVersion,
           let trimmedPackage = PackageCenter
           .default
           .trim(package: package, toVersion: version),
           let action = TaskManager.PackageAction(action: .install,
                                                  represent: trimmedPackage,
                                                  isUserRequired: true)
        {
            // MARK: - DIRECT INSTALL

            if package.latestMetadata?[DirectInstallInjectedPackageLocationKey] != nil {
                let result = TaskManager
                    .shared
                    .startPackageResolution(action: action)
                resolveAction(result: result, view: view)
                return
            }

            // MARK: - PAID

            if let tag = package.latestMetadata?["tag"],
               tag.contains("cydia::commercial")
            {
                // MARK: - GET ACCOUNT

                if !DeviceInfo.current.useRealDeviceInfo {
                    let alert = UIAlertController(title: NSLocalizedString("ERROR", comment: "Error"),
                                                  message: NSLocalizedString("CANNOT_SIGNIN_PAYMENT_WITHOUT_REAL_DEVICE_ID", comment: "Cannot sign in without using real device identities, check your settings."),
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("DISMISS", comment: "Dismiss"),
                                                  style: .default,
                                                  handler: nil))
                    view.parentViewController?.present(alert, animated: true, completion: nil)
                    return
                }

                guard let repoUrl = package.repoRef,
                      let repo = RepositoryCenter.default.obtainImmutableRepository(withUrl: repoUrl)
                else {
                    let alert = UIAlertController(title: NSLocalizedString("ERROR", comment: "Error"),
                                                  message: NSLocalizedString("BROKEN_RESOURCE", comment: "Broken Resource"),
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("DISMISS", comment: "Dismiss"),
                                                  style: .default,
                                                  handler: nil))
                    view.parentViewController?.present(alert, animated: true, completion: nil)
                    return
                }
                guard let signin = PaymentManager.shared.obtainStoredTokenInfomation(for: repo) else {
                    PaymentManager.shared.startUserAuthenticate(window: view.window ?? UIWindow(),
                                                                controller: view.parentViewController,
                                                                repoUrl: repoUrl) {}
                    return
                }
                let alert = UIAlertController(title: "⏳",
                                              message: NSLocalizedString("COMMUNICATING_WITH_VENDER",
                                                                         comment: "Communicating with vender"),
                                              preferredStyle: .alert)
                view.parentViewController?.present(alert, animated: true, completion: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    alert.dismiss(animated: true, completion: nil)
                }

                // MARK: - GET PACKAGE INFO

                DispatchQueue.global().async {
                    PaymentManager.shared.obtainPackageInfo(for: repoUrl, withPackageIdentity: package.identity) { info in
                        DispatchQueue.main.async {
                            guard let info = info else { return }
                            debugPrint(info)
                            if info.purchased == true {
                                // MARK: - OK FOR DOWNLOAD

                                DispatchQueue.global().async {
                                    let readDownload = PaymentManager
                                        .shared
                                        .queryDownloadLinkAndWait(withPackage: package)
                                    DispatchQueue.main.async {
                                        alert.dismiss(animated: true, completion: nil)
                                        guard let download = readDownload,
                                              let version = trimmedPackage.latestVersion,
                                              var meta = trimmedPackage.latestMetadata
                                        else {
                                            return
                                        }
                                        meta["filename"] = download.absoluteString
                                        let virtualPackage = Package(identity: trimmedPackage.identity,
                                                                     payload: [version: meta],
                                                                     repoRef: repoUrl)
                                        guard let newAction = TaskManager.PackageAction(action: .install,
                                                                                        represent: virtualPackage,
                                                                                        isUserRequired: true)
                                        else {
                                            return
                                        }

                                        let result = TaskManager
                                            .shared
                                            .startPackageResolution(action: newAction)
                                        resolveAction(result: result, view: view)
                                    }
                                }
                            } else if info.available ?? false {
                                // MARK: - NEED BUY

                                let window = view.window ?? UIWindow()
                                alert.dismiss(animated: true, completion: nil)
                                DispatchQueue.global().async {
                                    _ = PaymentManager
                                        .shared
                                        .initPurchaseAndWait(for: repoUrl,
                                                             withPackageIdentity: package.identity,
                                                             window: window)
                                }
                            } else {
                                // MARK: - NOT AVAILABLE

                                alert.dismiss(animated: true) {
                                    let alert = UIAlertController(title: NSLocalizedString("ERROR", comment: "Error"),
                                                                  message: NSLocalizedString("VERNDER_PACKAGE_NOT_AVAILABLE", comment: "Package not available, contact vender for support"),
                                                                  preferredStyle: .alert)
                                    alert.addAction(UIAlertAction(title: NSLocalizedString("DISMISS", comment: "Dismiss"),
                                                                  style: .default,
                                                                  handler: nil))
                                    view.parentViewController?.present(alert, animated: true, completion: nil)
                                }
                            }
                        }
                    }
                }
                return
            }

            // MARK: - DO

            let result = TaskManager
                .shared
                .startPackageResolution(action: action)
            resolveAction(result: result, view: view)
        }
    }

    static let allMenuActions: [MenuAction] = [
        // MARK: - DIRECT INSTALL

        .init(descriptor: .directInstall,
              block: resolveInstallRequest,
              elegantForPerform: { package in
                  if package.latestMetadata?[DirectInstallInjectedPackageLocationKey] != nil {
                      return true
                  }
                  return false
              }),

        // MARK: - INSTALL

        .init(descriptor: .install,
              block: resolveInstallRequest,
              elegantForPerform: { package in
                  if TaskManager
                      .shared
                      .isQueueContains(package: package.identity)
                  {
                      return false
                  }
                  if package.latestMetadata?[DirectInstallInjectedPackageLocationKey] != nil {
                      return false
                  }
                  if package.obtainDownloadLink() == PackageBadUrl {
                      return false
                  }
                  return PackageCenter
                      .default
                      .obtainPackageInstallationInfo(with: package.identity)
                      == nil
              }),

        // MARK: - UPDATE

        .init(descriptor: .update,
              block: resolveInstallRequest,
              elegantForPerform: { package in
                  if TaskManager.shared.isQueueContains(package: package.identity) { return false }
                  if package.obtainDownloadLink() == PackageBadUrl {
                      return false
                  }
                  if package.latestMetadata?[DirectInstallInjectedPackageLocationKey] != nil {
                      return false
                  }
                  if let info = PackageCenter
                      .default
                      .obtainPackageInstallationInfo(with: package.identity),
                      PackageCenter
                      .default
                      .obtainUpdateForPackage(with: package.identity,
                                              version: info.version)
                      .count > 0
                  {
                      if let info = PackageCenter
                          .default
                          .obtainPackageInstallationInfo(with: package.identity),
                          let current = package.latestVersion
                      {
                          if Package.compareVersion(current, b: info.version)
                              == .aIsSmallerThenB
                          {
                              return false
                          }
                      }
                      return true
                  }
                  return false
              }),

        // MARK: - REINSTALL

        .init(descriptor: .reinstall,
              block: resolveInstallRequest,
              elegantForPerform: { package in
                  if package.obtainDownloadLink() == PackageBadUrl {
                      return false
                  }
                  if package.latestMetadata?[DirectInstallInjectedPackageLocationKey] != nil {
                      return false
                  }
                  if TaskManager.shared.isQueueContains(package: package.identity) { return false }
                  let info = PackageCenter
                      .default
                      .obtainPackageInstallationInfo(with: package.identity)
                  return info?.version == package.latestVersion && info?.version != nil
              }),

        // MARK: - DOWNGRADE

        .init(descriptor: .downgrade,
              block: resolveInstallRequest,
              elegantForPerform: { package in
                  if TaskManager.shared.isQueueContains(package: package.identity) { return false }
                  if package.obtainDownloadLink() == PackageBadUrl {
                      return false
                  }
                  if package.latestMetadata?[DirectInstallInjectedPackageLocationKey] != nil {
                      return false
                  }
                  let _info = PackageCenter
                      .default
                      .obtainPackageInstallationInfo(with: package.identity)
                  guard let info = _info, let current = package.latestVersion else { return false }
                  return Package.compareVersion(current, b: info.version) == .aIsSmallerThenB
              }),

        // MARK: - REMOVE

        .init(descriptor: .remove,
              block: { package, view in
                  if let action = TaskManager.PackageAction(action: .remove,
                                                            represent: package,
                                                            isUserRequired: true)
                  {
                      let result = TaskManager
                          .shared
                          .startPackageResolution(action: action)
                      resolveAction(result: result, view: view)
                  }
              },
              elegantForPerform: { package in
                  if TaskManager.shared.isQueueContains(package: package.identity) { return false }
                  return PackageCenter
                      .default
                      .obtainPackageInstallationInfo(with: package.identity)
                      != nil
              }),

        // MARK: - CANCEL QUEUE

        .init(descriptor: .cancelQueue,
              block: { package, view in
                  let result = TaskManager
                      .shared
                      .cancelActionWithPackage(identity: package.identity)
                  resolveAction(result: result, view: view)
              },
              elegantForPerform: {
                  TaskManager.shared.isQueueContainsUserRequest(package: $0.identity)
              }),

        // MARK: - VERSION CONTROL

        .init(descriptor: .versionControl,
              block: { package, view in
                  let target = PackageVersionControlController()
                  target.currentPackage = package
                  view.parentViewController?.present(next: target)
              },
              elegantForPerform: { _ in true }),

        // MARK: - UPDATE CONTROL

        .init(descriptor: .blockUpdate, block: { package, _ in
            PackageCenter.default.blockedUpdateTable.append(package.identity)
        }, elegantForPerform: { package in
            !PackageCenter.default.blockedUpdateTable.contains(package.identity)
        }),

        .init(descriptor: .unblockUpdate, block: { package, _ in
            PackageCenter.default.blockedUpdateTable.removeAll(package.identity)
        }, elegantForPerform: { package in
            PackageCenter.default.blockedUpdateTable.contains(package.identity)
        }),
    ]

    // MARK: ACTIONS -

    static func presentPackageActionError(view: UIView) {
        let target = PackageDiagnosticController()
        view.parentViewController?.present(next: target)
    }

    static func resolveAction(result: TaskManager.PackageResolutionResult, view: UIView) {
        switch result {
        case .success:
            let text = NSLocalizedString("SUCCESSFULLY_QUEUED", comment: "Successfully Queued")
            SPIndicator.present(title: text,
                                preset: .done)
        case .breaksOther, .missingRequired:
            presentPackageActionError(view: view)
        case .brokenResource, .removeErrorTooManyDependency, .unknownError:
            SPIndicator.present(title: NSLocalizedString("UNKNOWN_ERROR_OCCURRED", comment: "Unknown Error Occurred"),
                                preset: .error)
        }
    }
}
