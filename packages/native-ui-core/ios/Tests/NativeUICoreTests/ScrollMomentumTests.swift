import XCTest
import WebKit
@testable import NativeUICore

@MainActor
final class ScrollMomentumTests: XCTestCase {
    private final class ScrollView: UIScrollView {
        var stops = 0
        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            if !animated { stops += 1 }
            super.setContentOffset(contentOffset, animated: animated)
        }
    }

    private func configure(_ controller: NativeUIController, options: [String: Any]) async {
        await withCheckedContinuation { continuation in
            controller.configure(NativeUICall(options: options, resolve: { _ in continuation.resume() }, reject: {
                XCTFail($0)
                continuation.resume()
            }))
        }
    }

    func testDefaultStopsNestedScrollsBeforeDeliveringOneActionWithoutLockingScrolling() {
        let webView = WKWebView()
        let outer = ScrollView()
        let inner = ScrollView()
        let container = UIView()
        webView.addSubview(outer)
        outer.addSubview(container)
        container.addSubview(inner)
        outer.contentSize = CGSize(width: 100, height: 2000)
        inner.contentSize = CGSize(width: 100, height: 2000)
        outer.setContentOffset(CGPoint(x: 0, y: 120), animated: false)
        inner.setContentOffset(CGPoint(x: 0, y: 240), animated: false)
        outer.stops = 0
        inner.stops = 0
        var actions = 0
        let controller = NativeUIController(environment: NativeUIEnvironment(
            webView: { webView }, viewController: { nil }, emit: { event, _ in
                guard event == "activate" else { return }
                XCTAssertEqual(outer.stops, 1)
                XCTAssertEqual(inner.stops, 1)
                actions += 1
            }, hasListeners: { _ in true }, trigger: { _, _ in }
        ))
        let item = UITabBarItem(title: "Action", image: nil, tag: 0)
        item.accessibilityIdentifier = "action"
        controller.tabBar(UITabBar(), didSelect: item)
        XCTAssertEqual(actions, 1)
        XCTAssertEqual(outer.contentOffset.y, 120)
        XCTAssertEqual(inner.contentOffset.y, 240)
        XCTAssertTrue(outer.isScrollEnabled)
        XCTAssertTrue(inner.isScrollEnabled)
        XCTAssertTrue(outer.panGestureRecognizer.isEnabled)
        XCTAssertTrue(inner.panGestureRecognizer.isEnabled)
    }

    func testFalsePreservesScrollingAndReconfigureWithoutAnOptionRestoresTheDefault() async {
        let webView = WKWebView()
        let scroll = ScrollView()
        webView.addSubview(scroll)
        var actions = 0
        let controller = NativeUIController(environment: NativeUIEnvironment(
            webView: { webView }, viewController: { nil }, emit: { event, _ in
                if event == "activate" { actions += 1 }
            }, hasListeners: { _ in true }, trigger: { _, _ in }
        ))
        let item = UITabBarItem(title: "Action", image: nil, tag: 0)
        item.accessibilityIdentifier = "action"
        await configure(controller, options: ["stopScrollOnActivate": false])
        scroll.stops = 0
        controller.tabBar(UITabBar(), didSelect: item)
        XCTAssertEqual(scroll.stops, 0)
        XCTAssertEqual(actions, 1)
        await configure(controller, options: [:])
        scroll.stops = 0
        controller.tabBar(UITabBar(), didSelect: item)
        XCTAssertEqual(scroll.stops, 1)
        XCTAssertEqual(actions, 2)
    }
}
