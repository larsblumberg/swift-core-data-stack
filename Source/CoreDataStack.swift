//
//  CoreDataStack.swift
//  CoreDataStack
//
//  Created by Lars Blumberg on 13/08/15.
//  Copyright © 2015 Lars Blumberg. All rights reserved.
//

import Foundation
import CoreData

//TODO: Opensource, create CocoaPod "CoreDataStackSwift"
public class CoreDataStack {
    private static var _sharedInstance: CoreDataStack?

    public static var sharedInstance: CoreDataStack {
        get {
            guard let sharedInstance = _sharedInstance else { fatalError("Call CoreDataStack.install() first") }
            return sharedInstance
        }
    }

    public static func install(modelName: String) {
        guard _sharedInstance == nil else { fatalError("CoreDataStack already installed") }
        _sharedInstance = CoreDataStack(modelName: modelName)
    }

    private let modelName: String
    
    internal lazy var managedObjectContext: NSManagedObjectContext! = {
        var managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator
        return managedObjectContext
    }()
    
    internal lazy var managedObjectModel: NSManagedObjectModel = {
        let modelURL = NSBundle.mainBundle().URLForResource(self.modelName, withExtension: "momd")!
        return NSManagedObjectModel(contentsOfURL: modelURL)!
    }()
    
    internal lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator! = {
        let storeURL = self.applicationDocumentsDirectory().URLByAppendingPathComponent(self.modelName + ".sqlite")
        
        // Enable for lightweight model migration
        var options = [String: AnyObject]()
        options[NSMigratePersistentStoresAutomaticallyOption] = true
        options[NSInferMappingModelAutomaticallyOption] = true
        
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)

        var failureReason = "There was an error creating or loading the application's saved data."
        do {
            try coordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: options)
        } catch {
            // Report any error we got.
            var dict = [String: AnyObject]()
            dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data"
            dict[NSLocalizedFailureReasonErrorKey] = failureReason
            
            dict[NSUnderlyingErrorKey] = error as NSError
            let wrappedError = NSError(domain: "YOUR_ERROR_DOMAIN", code: 9999, userInfo: dict)
            // TODO: Replace this with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog("Unresolved error \(wrappedError), \(wrappedError.userInfo)")
            abort()
        }
        
        return coordinator
    }()
    
    private init(modelName: String) {
        self.modelName = modelName
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "managedObjectContextDidSaveNotification:", name: NSManagedObjectContextDidSaveNotification, object: nil)
    }
    
    private func applicationDocumentsDirectory() -> NSURL! {
        let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        return urls[urls.count - 1]
    }
    
    //MARK: Support for managed object context access from different threads
    
    func currentContext() -> NSManagedObjectContext! {
        if NSThread.isMainThread() {
            return self.managedObjectContext
        }
        // Retrieve or create new context for current thread
        let currentThread = NSThread.currentThread()
        var context = currentThread.threadDictionary["CoreDataStack"] as? NSManagedObjectContext
        if (context == nil) {
            if let coordinator = self.persistentStoreCoordinator {
                context = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
                context!.persistentStoreCoordinator = coordinator
                currentThread.threadDictionary["CoreDataStack"] = context
            }
        }
        return context
    }
    
    public func saveCurrentContext() {
        saveContext(currentContext())
    }
    
    internal func saveContext(context: NSManagedObjectContext!) {
        if !context.hasChanges {
            return
        }
        
        do {
            try context.save()
        } catch let error as NSError {
            //TODO: Replace this implementation with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            print("Unresolved error \(error), \(error.userInfo)")
            abort();
        }
    }

    // Merging other object contexts into the main context
    @objc private func managedObjectContextDidSaveNotification(notification: NSNotification!) {
        let notificationManagedObjectContext = notification.object as? NSManagedObjectContext
        
        if (notificationManagedObjectContext == self.managedObjectContext) {
            // No need to merge the main context into itself
            return;
        }
        if (notificationManagedObjectContext?.persistentStoreCoordinator != self.persistentStoreCoordinator) {
            // No need to merge a context from other store coordinators than ours
            return;
        }
        
        if (!NSThread.isMainThread()) {
            // Make sure to perform the merge operation on the main thread
            dispatch_async(dispatch_get_main_queue()) {
                self.managedObjectContextDidSaveNotification(notification)
            }
            return;
        }
        
        // Merge thread-related context into the main context
        self.managedObjectContext.mergeChangesFromContextDidSaveNotification(notification)
    }
}
