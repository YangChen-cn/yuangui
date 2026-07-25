import XCTest
@testable import YuanGUI

final class DashboardTests: XCTestCase {
    func testPreferredWidthFitsFooterControls() {
        XCTAssertGreaterThanOrEqual(DashboardDesign.preferredWidth, 400)
        XCTAssertLessThanOrEqual(DashboardDesign.preferredWidth, 430)
    }

    func testPanelSizeNeverExceedsVisibleScreen() {
        let visible = CGRect(x: -500, y: 20, width: 360, height: 440)
        let size = DashboardPanelLayout.size(in: visible)

        XCTAssertLessThanOrEqual(size.width, visible.width - DashboardPanelLayout.screenInset * 2)
        XCTAssertLessThanOrEqual(size.height, visible.height - DashboardPanelLayout.screenInset * 2)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testDashboardSectionsAreCompleteAndOrdered() {
        XCTAssertEqual(DashboardSection.allCases, [.overview, .music, .tools])
        XCTAssertEqual(DashboardSection.overview.adjacent(.right), .music)
        XCTAssertEqual(DashboardSection.music.adjacent(.right), .tools)
        XCTAssertEqual(DashboardSection.tools.adjacent(.right), .tools)
        XCTAssertEqual(DashboardSection.overview.adjacent(.left), .overview)
    }

    func testSmartStatePresentationHasMatchingTextAndIcon() {
        let expected: [(SmartPetState, String, String)] = [
            (.normal, "一切平稳", "checkmark.circle"),
            (.lowBattery, "低电量", "battery.25percent"),
            (.memoryPressure, "内存紧张", "memorychip.fill"),
            (.charging, "充电中", "bolt.fill"),
            (.rainy, "下雨了", "umbrella.fill"),
            (.bedtime, "该休息了", "moon.zzz.fill")
        ]

        for (state, title, icon) in expected {
            let presentation = DashboardSmartStatePresentation.resolve(state)
            XCTAssertEqual(presentation.title, title)
            XCTAssertEqual(presentation.systemImage, icon)
        }
    }

    func testToolIdentifiersAreUniqueAndDoNotContainFooterToggles() {
        let identifiers = DashboardToolsView.toolIdentifiers
        XCTAssertEqual(Set(identifiers.map(\.rawValue)).count, identifiers.count)
        XCTAssertFalse(identifiers.map(\.rawValue).contains("settings"))
        XCTAssertFalse(identifiers.map(\.rawValue).contains("desktopIcons"))
        XCTAssertFalse(identifiers.map(\.rawValue).contains("petLock"))
    }

    func testAppleMusicSourceSelectionRequestsARealConnection() {
        XCTAssertEqual(
            DashboardMusicSourceAction.resolve(.appleMusic),
            .connectAppleMusic
        )
        XCTAssertEqual(
            DashboardMusicSourceAction.resolve(.bilibili),
            .selectBilibili
        )
    }

    func testHeaderGreetingAndCompanionCopyAreDeterministic() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let morning = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 8))
        )

        XCTAssertEqual(DashboardHeaderPresentation.greeting(at: morning, calendar: calendar), "早上好")
        XCTAssertEqual(DashboardHeaderPresentation.companionTitle(for: .yuanGui), "元圭在这里")
        XCTAssertEqual(DashboardHeaderPresentation.companionTitle(for: .vcc), "VCC 正在陪你")
        XCTAssertEqual(DashboardHeaderPresentation.companionTitle(for: .duo), "元圭和 VCC 都在")
    }

    func testQueueExcludesCurrentTrackAndReportsRemainingCount() {
        let tracks = (0..<7).map { index in
            MusicTrack(
                id: "\(index)",
                source: .bilibili,
                title: "Track \(index)",
                artist: "Artist",
                album: nil,
                coverURL: nil,
                duration: 180,
                bilibili: nil,
                subtitleURL: nil
            )
        }

        let result = DashboardQueuePresentation.resolve(
            upcoming: tracks,
            currentTrackID: "1",
            limit: 4
        )

        XCTAssertEqual(result.tracks.map(\.id), ["0", "2", "3", "4"])
        XCTAssertEqual(result.remainingCount, 2)
    }

    func testWeatherPresentationExplainsLocationDenial() {
        let presentation = DashboardWeatherPresentation.resolve(
            snapshot: nil,
            status: .locationDenied,
            locationName: nil
        )

        XCTAssertEqual(presentation.conditionText, "定位未授权")
        XCTAssertTrue(presentation.detailText.contains("允许定位"))
        XCTAssertTrue(presentation.showsLocationSettings)
        XCTAssertFalse(presentation.isRefreshing)
    }
}
