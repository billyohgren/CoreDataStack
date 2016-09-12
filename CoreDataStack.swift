//
//  CoreDataStack.swift
//  Oppnis
//
//  Created by Billy Öhgren on 12/09/16.
//  Copyright © 2016 billy. All rights reserved.
//

import Foundation
import CoreData

typealias CoreDataStackInitCallback = () -> (Void)

class CoreDataStack {
    
    private var privateObjectContext: NSManagedObjectContext?
    private var mainObjectContext: NSManagedObjectContext?
    private var initBlock: CoreDataStackInitCallback

    let managedObjectContext: NSManagedObjectContext? = nil
    
    init(callbackBlock: @escaping CoreDataStackInitCallback, resourceName: String, storeName: String?) {
        
        initBlock = callbackBlock
        
        if let storeName = storeName {
            initializeCoreData(resourceName: resourceName, storeName: storeName)
        } else {
            let defaultStoreName = resourceName.appending(".sqlite")
            initializeCoreData(resourceName: resourceName, storeName: defaultStoreName)
        }
    }
    
    func save() {
        
        guard
            let privateObjectContext = privateObjectContext,
            let mainObjectContext = mainObjectContext
        else
            { return }
        
        let contextsHasChanges = privateObjectContext.hasChanges && mainObjectContext.hasChanges
        
        if !contextsHasChanges {
            return
        }
        
        mainObjectContext.performAndWait {
            do {
                try mainObjectContext.save()
            } catch {
                print("Failed to save main object context")
            }
            
            privateObjectContext.perform {
                do {
                    try privateObjectContext.save()
                } catch {
                  print("Failed to save private object context")
                }
            }
        }
    }
 
    // MARK: - Private
    
    private func initializeCoreData(resourceName: String, storeName: String) {
        
        if managedObjectContext != nil {
            return
        }
        
        guard
            let modelURL = Bundle.main.url(forResource: resourceName, withExtension: "momd"),
            let objectModel = NSManagedObjectModel(contentsOf: modelURL)
        else
            { return }
        

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: objectModel)
        mainObjectContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        privateObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        privateObjectContext?.persistentStoreCoordinator = coordinator
        mainObjectContext?.parent = privateObjectContext
        
        DispatchQueue.global().async { [weak self] in
            guard let strongSelf = self else { return }
            
            let storeCoordinator = strongSelf.privateObjectContext?.persistentStoreCoordinator
            let options = [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true,
                NSSQLitePragmasOption: ["journal_mode": "DELETE"]
            ] as [String : Any]
            
            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).last
            let storeURL = documentsURL?.appendingPathComponent(storeName)
            
            do {
                try storeCoordinator?.addPersistentStore(ofType: NSSQLiteStoreType,
                                                         configurationName: nil,
                                                         at: storeURL,
                                                         options: options)
            } catch {
                print("Failed to add persistant store to coordinator")
            }
            
            DispatchQueue.main.async {
                strongSelf.initBlock()
            }
        }
    }
}
