//
//  Note+CoreDataProperties.swift
//  NoteHub
//
//  Created by nichita cozlovschi on 03.10.2025.
//
//

public import Foundation
public import CoreData


public typealias NoteCoreDataPropertiesSet = NSSet

extension Note {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Note> {
        return NSFetchRequest<Note>(entityName: "Note")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var musicPath: String?
    @NSManaged public var photoPath: String?
    @NSManaged public var tags: String?
    @NSManaged public var text: String?
    @NSManaged public var textData: Data?
    @NSManaged public var title: String?
    @NSManaged public var voicePath: String?
    @NSManaged public var isPinned: Bool

}

extension Note : Identifiable {

}
