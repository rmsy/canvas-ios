//
//  GradingPeriod+Collections.swift
//  Assignments
//
//  Created by Nathan Armstrong on 4/29/16.
//  Copyright © 2016 Instructure. All rights reserved.
//

import UIKit
import TooLegit
import CoreData
import SoPersistent
import SoLazy
import ReactiveCocoa
import Cartography

extension GradingPeriodItem {
    func colorfulViewModel(dataSource: ContextDataSource, courseID: String, selected: Bool) -> ColorfulViewModel {
        let model = ColorfulViewModel(style: .Basic)
        model.title.value = title
        model.color <~ dataSource.producer(ContextID(id: courseID, context: .Course)).map { $0?.color ?? .prettyGray() }
        model.accessoryType.value = selected ? .Checkmark : .None
        return model
    }
}


extension GradingPeriod {
    static func collectionCacheKey(context: NSManagedObjectContext, courseID: String) -> String {
        return cacheKey(context, [courseID])
    }

    public static func predicate(courseID: String) -> NSPredicate {
        return NSPredicate(format:"%K == %@", "courseID", courseID)
    }

    internal static func predicate(courseID: String, notMatchingID id: String?) -> NSPredicate {
        return id.flatMap { NSPredicate(format: "%K == %@ && %K != %@", "courseID", courseID, "id", $0) } ?? NSPredicate(format: "%K == %@", "courseID", courseID)
    }
    
    public static func gradingPeriodIDs(session: Session, courseID: String, excludingGradingPeriodID: String?) throws -> [String] {
        let context = try session.enrollmentManagedObjectContext()
        let invalidatedGradingPeriods: [GradingPeriod] = try context.findAll(fromFetchRequest: GradingPeriod.fetch(GradingPeriod.predicate(courseID, notMatchingID: excludingGradingPeriodID), sortDescriptors: nil, inContext: context))
        return invalidatedGradingPeriods.map { $0.id }
    }

    public static func collectionByCourseID(session: Session, courseID: String) throws -> FetchedCollection<GradingPeriod> {
        let frc = GradingPeriod.fetchedResults(GradingPeriod.predicate(courseID), sortDescriptors: ["startDate".ascending], sectionNameKeypath: nil, inContext: try session.enrollmentManagedObjectContext())
        return try FetchedCollection(frc: frc)
    }

    public static func refresher(session: Session, courseID: String) throws -> Refresher {
        let context = try session.enrollmentManagedObjectContext()
        let remote = try GradingPeriod.getGradingPeriods(session, courseID: courseID)
        let sync = GradingPeriod.syncSignalProducer(inContext: context, fetchRemote: remote) { gradingPeriod, _ in
            gradingPeriod.courseID = courseID
        }

        let key = collectionCacheKey(context, courseID: courseID)
        return SignalProducerRefresher(refreshSignalProducer: sync, scope: session.refreshScope, cacheKey: key)
    }

    public class TableViewController: SoPersistent.TableViewController {
        private (set) public var collection: GradingPeriodCollection!

        func prepare<VM: TableViewCellViewModel>(collection: GradingPeriodCollection, refresher: Refresher? = nil, viewModelFactory: GradingPeriodItem->VM) {
            self.collection = collection
            self.refresher = refresher
            dataSource = CollectionTableViewDataSource(collection: collection, viewModelFactory: viewModelFactory)
        }
        
        public init(session: Session, courseID: String, collection: GradingPeriodCollection, refresher: Refresher) throws {
            super.init()
            
            title = NSLocalizedString("Grading Periods", comment: "Title for grading periods picker")
            collection.selectedGradingPeriod.producer
                .observeOn(UIScheduler())
                .startWithNext { _ in collection.collectionUpdated([.Reload]) }

            let dataSource = session.enrollmentsDataSource
            prepare(collection, refresher: refresher) { item in
                return item.colorfulViewModel(dataSource, courseID: courseID, selected: item == self.collection.selectedGradingPeriod.value)
            }
        }
        
        public required init?(coder aDecoder: NSCoder) {
            fatalError()
        }

        public override func viewDidLoad() {
            super.viewDidLoad()
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Cancel, target: self, action: #selector(cancel))
        }

        override public func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
            let item = collection[indexPath]
            collection.selectedGradingPeriod.value = item
        }

        func cancel() {
            dismissViewControllerAnimated(true, completion: nil)
        }
    }
    
    public class Header: NSObject, UITableViewDataSource, UITableViewDelegate {
        // Input
        public let includeGradingPeriods: Bool
        public weak var viewController: UIViewController?
        public let grade: MutableProperty<String?>

        // Output
        public var selectedGradingPeriod: AnyProperty<GradingPeriodItem?> {
            guard includeGradingPeriods else {
                return AnyProperty(ConstantProperty(nil))
            }
            return AnyProperty(gradingPeriodsList.collection.selectedGradingPeriod)
        }

        public lazy var tableView: UITableView = {
            let tableView = UITableView(frame: CGRectZero, style: .Plain)
            tableView.dataSource = self
            tableView.delegate = self
            tableView.scrollEnabled = false
            tableView.tableFooterView = UIView(frame: CGRectZero)
            tableView.estimatedRowHeight = 44
            tableView.rowHeight = UITableViewAutomaticDimension
            return tableView
        }()

        private let gradingPeriod: AnyProperty<String?>
        private let gradingPeriodsList: TableViewController
        private var disposable: Disposable?

        var includeGrade: Bool {
            return grade.value != nil
        }

        public init(session: Session, courseID: String, viewController: UIViewController, includeGradingPeriods: Bool, grade: MutableProperty<String?> = MutableProperty(nil)) throws {
            guard let course = session.enrollmentsDataSource[ContextID(id: courseID, context: .Course)] as? Course else {
                ❨╯°□°❩╯⌢"We gots to have the course. Shouldn't we already have all teh courses?"
            }

            self.includeGradingPeriods = includeGradingPeriods
            self.grade = grade

            let collection = try GradingPeriod.collectionByCourseID(session, courseID: courseID)
            let gradingPeriodsCollection = GradingPeriodCollection(course: course, gradingPeriods: collection)
            let refresher = try GradingPeriod.refresher(session, courseID: courseID)
            self.gradingPeriodsList = try TableViewController(session: session, courseID: courseID, collection: gradingPeriodsCollection, refresher: refresher)

            self.viewController = viewController

            self.gradingPeriod = AnyProperty(initialValue: nil, producer: gradingPeriodsCollection.selectedGradingPeriod.producer.map { $0?.title })

            super.init()

            // reload table view when grading period or grade change
            combineLatest(gradingPeriod.producer, grade.producer)
                .observeOn(UIScheduler())
                .startWithNext { [weak self] this in
                    if let tableView = self?.tableView {
                        tableView.reloadData()
                    }
                }

            if includeGradingPeriods {
                refresher.refresh(false)
            }
        }
        
        public func numberOfSectionsInTableView(tableView: UITableView) -> Int {
            return 1
        }
        
        public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return [includeGradingPeriods, includeGrade].filter { $0 }.count
        }
        
        public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
            switch indexPath.row {
            case 0:
                guard includeGradingPeriods else {
                    fallthrough
                }
                let cell = UITableViewCell(style: .Default, reuseIdentifier: nil)
                cell.textLabel?.text = gradingPeriod.value
                cell.accessoryType = .DisclosureIndicator
                return cell
            case 1:
                let cell = UITableViewCell(style: .Value1, reuseIdentifier: nil)
                cell.textLabel?.text = NSLocalizedString("Total Grade", comment: "Total grade label")
                cell.detailTextLabel?.text = grade.value
                cell.selectionStyle = .None
                return cell
            default: fatalError("too many rows!")
            }
        }
        
        public func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
            switch indexPath.row {
            case 0 where includeGradingPeriods:
                let nav = UINavigationController(rootViewController: gradingPeriodsList)
                nav.modalPresentationStyle = .FormSheet

                disposable?.dispose()
                disposable = gradingPeriodsList.collection.selectedGradingPeriod.signal
                    .observeOn(UIScheduler())
                    .observeNext { _ in
                        nav.dismissViewControllerAnimated(true) {
                            tableView.deselectRowAtIndexPath(indexPath, animated: true)
                        }
                    }

                viewController?.presentViewController(nav, animated: true, completion: {
                    tableView.deselectRowAtIndexPath(indexPath, animated: true)
                })
            default: break
            }
        }
    }
}
