import XCTest
@testable import PulseFeed

/// What Finish does besides the database writes: the look applies now, and someone who never pressed
/// "Allow notifications" is asked, unless they chose Quiet.
final class WelcomeFinishTests: XCTestCase {
    private var draft = WelcomeDraft()

    func testAppearanceAppliesAtFinish() {
        draft.appearance = .dark
        XCTAssertTrue(WelcomeFinish.actions(draft, notificationsUndecided: false).contains(.applyAppearance(.dark)))
    }

    func testUndecidedNotificationsAreAskedAtFinish() {
        draft.alertMode = .breakingAndRecap
        XCTAssertTrue(WelcomeFinish.actions(draft, notificationsUndecided: true).contains(.askNotifications))
        draft.alertMode = .recapOnly
        XCTAssertTrue(WelcomeFinish.actions(draft, notificationsUndecided: true).contains(.askNotifications))
    }

    func testQuietOrAlreadyAnsweredIsNotAsked() {
        draft.alertMode = .quiet
        XCTAssertFalse(WelcomeFinish.actions(draft, notificationsUndecided: true).contains(.askNotifications))
        draft.alertMode = .breakingAndRecap
        XCTAssertFalse(WelcomeFinish.actions(draft, notificationsUndecided: false).contains(.askNotifications))
    }

    func testOpenAtLoginOnlyWhenTicked() {
        XCTAssertFalse(WelcomeFinish.actions(draft, notificationsUndecided: false).contains(.openAtLogin))
        draft.openAtLogin = true
        XCTAssertTrue(WelcomeFinish.actions(draft, notificationsUndecided: false).contains(.openAtLogin))
    }

    /// Spec §10 C1: the Alerts step names the three kinds of thing that can break through.
    func testAlertsStepNamesTheThreeKinds() {
        let kinds = WelcomeCopy.alertKinds
        XCTAssertEqual(kinds.count, 3)
        XCTAssertTrue(kinds[0].contains("ceasefire"))
        XCTAssertTrue(kinds[1].contains("topic"))
        XCTAssertTrue(kinds[2].contains("follow"))
    }
}
