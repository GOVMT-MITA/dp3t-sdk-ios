/*
 * Created by Ubique Innovation AG
 * https://www.ubique.ch
 * Copyright (c) 2020. All rights reserved.
 */

import Foundation

@testable import DP3TSDK
import Foundation
import XCTest

private class MockMatcher: Matcher {
    var delegate: MatcherDelegate?

    var error: Error?

    func receivedNewKnownCaseData(_: Data, keyDate _: Date) throws {}

    func finalizeMatchingSession() throws {
        if let error = error {
            throw error
        }
    }
}

private class MockService: ExposeeServiceClientProtocol {
    var requests: [Date] = []
    let queue = DispatchQueue(label: "synchronous")
    var error: DP3TNetworkingError?
    var publishedUntil: Date = .init()
    func getExposeeSynchronously(batchTimestamp: Date, publishedAfter _: Date?) -> Result<ExposeeSuccess?, DP3TNetworkingError> {
        queue.sync {
            self.requests.append(batchTimestamp)
        }
        if let error = error {
            return .failure(error)
        }
        return .success(.init(data: "\(batchTimestamp.timeIntervalSince1970)".data(using: .utf8)!, publishedUntil: .init()))
    }

    func addExposeeList(_: ExposeeListModel, authentication _: ExposeeAuthMethod, completion _: @escaping (Result<OutstandingPublish, DP3TNetworkingError>) -> Void) {}

    func addDelayedExposeeList(_: DelayedKeyModel, token _: String?, completion _: @escaping (Result<Void, DP3TNetworkingError>) -> Void) {}
}

final class KnownCasesSynchronizerTests: XCTestCase {

    func testInitialToday() {
        let matcher = MockMatcher()
        let service = MockService()
        let defaults = MockDefaults()
        let sync = KnownCasesSynchronizer(matcher: matcher,
                                          service: service,
                                          defaults: defaults,
                                          descriptor: .init(appId: "ch.dpppt", bucketBaseUrl: URL(string: "http://www.google.de")!, reportBaseUrl: URL(string: "http://www.google.de")!))
        let expecation = expectation(description: "syncExpectation")
        sync.sync { _ in
            expecation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(service.requests.count, 10)
        XCTAssert(service.requests.contains(DayDate().dayMin))
        XCTAssert(!defaults.publishedAfterStore.isEmpty)
    }

    func testInitialLoadingFirstBatch() {
        let matcher = MockMatcher()
        let service = MockService()
        let defaults = MockDefaults()
        let sync = KnownCasesSynchronizer(matcher: matcher,
                                          service: service,
                                          defaults: defaults,
                                          descriptor: .init(appId: "ch.dpppt", bucketBaseUrl: URL(string: "http://www.google.de")!, reportBaseUrl: URL(string: "http://www.google.de")!))
        let expecation = expectation(description: "syncExpectation")
        sync.sync(now: .init(timeIntervalSinceNow: .hour)) { _ in
            expecation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(service.requests.count, 10)
        XCTAssert(!defaults.publishedAfterStore.isEmpty)
    }

    func testInitialLoadingManyBatches() {
        let matcher = MockMatcher()
        let service = MockService()
        let defaults = MockDefaults()
        let sync = KnownCasesSynchronizer(matcher: matcher,
                                          service: service,
                                          defaults: defaults,
                                          descriptor: .init(appId: "ch.dpppt", bucketBaseUrl: URL(string: "http://www.google.de")!, reportBaseUrl: URL(string: "http://www.google.de")!))
        let expecation = expectation(description: "syncExpectation")
        sync.sync(now: .init(timeIntervalSinceNow: .day * 15)) { _ in
            expecation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(service.requests.count, defaults.parameters.networking.daysToCheck)
        XCTAssert(!defaults.publishedAfterStore.isEmpty)
    }

    func testDontStorePublishedAfterNetworkingError() {
        let matcher = MockMatcher()
        let service = MockService()
        service.error = .couldNotEncodeBody
        let defaults = MockDefaults()
        let sync = KnownCasesSynchronizer(matcher: matcher,
                                          service: service,
                                          defaults: defaults,
                                          descriptor: .init(appId: "ch.dpppt", bucketBaseUrl: URL(string: "http://www.google.de")!, reportBaseUrl: URL(string: "http://www.google.de")!))
        let expecation = expectation(description: "syncExpectation")
        sync.sync(now: .init(timeIntervalSinceNow: .hour)) { _ in
            expecation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssert(defaults.publishedAfterStore.isEmpty)
    }

    func testDontStorePublishedAfterMatchingError() {
        let matcher = MockMatcher()
        let service = MockService()
        matcher.error = DP3TTracingError.bluetoothTurnedOff
        let defaults = MockDefaults()
        let sync = KnownCasesSynchronizer(matcher: matcher,
                                          service: service,
                                          defaults: defaults,
                                          descriptor: .init(appId: "ch.dpppt", bucketBaseUrl: URL(string: "http://www.google.de")!, reportBaseUrl: URL(string: "http://www.google.de")!))
        let expecation = expectation(description: "syncExpectation")
        sync.sync(now: .init(timeIntervalSinceNow: .hour)) { _ in
            expecation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssert(defaults.publishedAfterStore.isEmpty)
    }

    func testNotRepeatingRequests(){
        let matcher = MockMatcher()
        let service = MockService()
        let defaults = MockDefaults()
        let sync = KnownCasesSynchronizer(matcher: matcher,
                                          service: service,
                                          defaults: defaults,
                                          descriptor: .init(appId: "ch.dpppt", bucketBaseUrl: URL(string: "http://www.google.de")!, reportBaseUrl: URL(string: "http://www.google.de")!))
        let expecation = expectation(description: "syncExpectation")
        sync.sync(now: .init(timeIntervalSinceNow: .hour)) { _ in
            expecation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(service.requests.count, 10)
        XCTAssert(!defaults.publishedAfterStore.isEmpty)

        service.requests = []

        let secondExpectation = expectation(description: "secondSyncExpectation")
        sync.sync(now: .init(timeIntervalSinceNow: .hour)) { _ in
            secondExpectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(service.requests, [])
    }

    func testRepeatingRequestsAfterDay(){
        let matcher = MockMatcher()
        let service = MockService()
        let defaults = MockDefaults()
        let sync = KnownCasesSynchronizer(matcher: matcher,
                                          service: service,
                                          defaults: defaults,
                                          descriptor: .init(appId: "ch.dpppt", bucketBaseUrl: URL(string: "http://www.google.de")!, reportBaseUrl: URL(string: "http://www.google.de")!))
        let expecation = expectation(description: "syncExpectation")
        sync.sync(now: .init(timeIntervalSinceNow: .hour)) { _ in
            expecation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(service.requests.count, 10)
        XCTAssert(!defaults.publishedAfterStore.isEmpty)

        service.requests = []

        let secondExpectation = expectation(description: "secondSyncExpectation")
        sync.sync(now: .init(timeIntervalSinceNow: .hour + .day)) { _ in
            secondExpectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(service.requests.count, 10)
        XCTAssert(!defaults.publishedAfterStore.isEmpty)
    }

    func testLastDesiredSyncTimeNoon() {
        let input = Self.formatter.date(from: "19.05.2020 12:12")!
        let output = Self.formatter.date(from: "19.05.2020 06:00")!
        XCTAssertEqual(KnownCasesSynchronizer.getLastDesiredSyncTime(ts: input), output)
    }

    func testLastDesiredSyncTimeYesterday() {
        let input = Self.formatter.date(from: "19.05.2020 05:55")!
        let output = Self.formatter.date(from: "18.05.2020 20:00")!
        XCTAssertEqual(KnownCasesSynchronizer.getLastDesiredSyncTime(ts: input), output)
    }

    func testLastDesiredSyncTimeNight() {
        let input = Self.formatter.date(from: "19.05.2020 23:55")!
        let output = Self.formatter.date(from: "19.05.2020 20:00")!
        XCTAssertEqual(KnownCasesSynchronizer.getLastDesiredSyncTime(ts: input), output)
    }

    static var formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy HH:mm"
        return df
    }()
}
