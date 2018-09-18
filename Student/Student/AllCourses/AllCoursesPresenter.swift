//
// Copyright (C) 2018-present Instructure, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import Core

struct AllCoursesViewModel {
    struct Course {
        let courseID: String
        let title: String
        let abbreviation: String
        let color: UIColor
        let imageUrl: URL?
    }

    var current: [Course]
    var past: [Course]
}

protocol AllCoursesPresenterProtocol {
    func viewIsReady()
    func pageViewStarted()
    func pageViewEnded()
    func loadData()
    func refreshRequested()
    func courseWasSelected(_ courseID: String)
    func courseOptionsWasSelected(_ courseID: String)
}

class AllCoursesPresenter: AllCoursesPresenterProtocol {
    weak var view: (AllCoursesViewProtocol & ErrorViewController)?
    let api: API
    let database: Persistence
    let router: RouterProtocol
    var groupOperation: OperationSet?

    lazy var coursesFetch: FetchedResultsController<Course> = {
        let sort = SortDescriptor(key: "name", ascending: true)
        let fetcher: FetchedResultsController<Course> = database.fetchedResultsController(predicate: NSPredicate.all, sortDescriptors: [sort], sectionNameKeyPath: nil)
        fetcher.delegate = self
        return fetcher
    }()

    init(env: AppEnvironment, view: (AllCoursesViewProtocol & ErrorViewController)?) {
        self.api = env.api
        self.database = env.database
        self.router = env.router
        self.view = view
    }

    func courseWasSelected(_ courseID: String) {
        // route to details screen
    }

    func viewIsReady() {
        loadData()
    }

    func pageViewStarted() {
        // log page view
    }

    func pageViewEnded() {
        // log page view
    }

    func courseOptionsWasSelected(_ courseID: String) {
        // route/modal
    }

    func refreshRequested() {
        loadDataFromServer()
    }

    func loadData() {
        do {
            try coursesFetch.performFetch()
        } catch {
            view?.showError(error)
        }

        // Get from cache to start
        fetchData()

        // Get from server
        loadDataFromServer()
    }

    func loadDataFromServer() {
        if let gop = self.groupOperation, !gop.isFinished {
            return
        }

        let getCourses = GetCourses(api: api, database: database)
        let getColors = GetCustomColors(api: api, database: database)
        getColors.addDependency(getCourses)

        let groupOperation = OperationSet(operations: [getCourses, getColors])
        groupOperation.completionBlock = { [weak self] in
            // Load data from data store once our big group finishes
            DispatchQueue.main.async {
                self?.fetchData()
            }
        }
        self.groupOperation = groupOperation

        queue.addGroupOperationWithErrorHandling(groupOperation, sendErrorsTo: view)
    }

    func fetchData() {
        let courses = coursesFetch.fetchedObjects ?? []
        let vm = transformToViewModel(current: courses, past: courses)

        self.view?.updateDisplay(vm)

    }

    func transformToViewModel(current: [Course], past: [Course]) -> AllCoursesViewModel {
        let vms = current.compactMap { (course: Course) -> AllCoursesViewModel.Course? in
            guard let name = course.name, !course.id.isEmpty else {
                return nil
            }
            var imageUrl: URL?
            if let string = course.imageDownloadUrl {
                imageUrl = URL(string: string)
            }
            return AllCoursesViewModel.Course(courseID: course.id, title: name, abbreviation: course.courseCode ?? "", color: UIColor(hexString: course.color) ?? .gray, imageUrl: imageUrl)
        }

        let vm = AllCoursesViewModel(current: vms, past: vms)
        return vm
    }
}

extension AllCoursesPresenter: FetchedResultsControllerDelegate {
    func controllerDidChangeContent<T>(_ controller: FetchedResultsController<T>) {
        guard let gop = groupOperation else {
            return
        }

        if gop.isFinished {
            fetchData()
        }
    }
}