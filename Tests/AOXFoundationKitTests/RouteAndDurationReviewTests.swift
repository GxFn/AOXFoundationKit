import Foundation
import Testing
@testable import AOXFoundationKit

@Suite @MainActor
struct RouteAndDurationReviewTests {
    @Test(arguments: ["inf", "nan", "1e100"])
    func unrepresentableRouteDelayIsRejected(_ delay: String) async {
        let router = SchemeRouter()
        router.registerSchemes(["bilidili"])
        var nextCalls = 0
        router.register(module: "first", action: "open") { _ in .success() }
        router.register(module: "next", action: "open") { _ in
            nextCalls += 1
            return .success()
        }
        let result = await router.dispatch(urlString:
            "bilidili://first/open?next=bilidili%3A%2F%2Fnext%2Fopen&delaytime=\(delay)")
        guard case .failure(.invalidParams) = result else {
            Issue.record("不可表示的外部延时必须作为参数错误返回")
            return
        }
        #expect(nextCalls == 0)
    }

    @Test
    func routeQueryPreservesEncodedPlusAndExistingFormSpaces() throws {
        let router = SchemeRouter()
        router.registerSchemes(["bilidili"])
        let url = try #require(URL(string: "bilidili://author/open?name=C%2B%2B&space=hello+world&literal=%252B&encodedSpace=hello%20world&options=%7B%22title%22%3A%22C%2B%2B%22%7D&url=https%3A%2F%2Fexample.test%2F%3Fq%3DA%2BB"))
        let route = try #require(router.parse(url: url))

        #expect(route.param("name") == "C++")
        #expect(route.param("space") == "hello world")
        #expect(route.param("encodedSpace") == "hello world")
        #expect(route.param("literal") == "%2B")
        #expect(route.options?["title"] as? String == "C++")
        #expect(route.param("url") == "https://example.test/?q=A+B")
    }

    @Test
    func cancelledDelayedRouteDoesNotOpenNextPage() async throws {
        let router = SchemeRouter()
        router.registerSchemes(["bilidili"])
        let entered = AsyncStream<Void>.makeStream()
        var nextPageCount = 0
        router.register(module: "first", action: "open") { _ in
            entered.continuation.yield(())
            return .success()
        }
        router.register(module: "next", action: "open") { _ in
            nextPageCount += 1
            return .success()
        }

        let request = Task { @MainActor in
            await router.dispatch(urlString: "bilidili://first/open?next=bilidili%3A%2F%2Fnext%2Fopen&delaytime=60")
        }
        var iterator = entered.stream.makeAsyncIterator()
        _ = await iterator.next()
        request.cancel()
        let result = await request.value
        entered.continuation.finish()

        guard case .failure(.cancelled) = result else {
            Issue.record("取消延时跳转应返回 cancelled")
            return
        }
        #expect(nextPageCount == 0)
    }

    @Test
    func alreadyCancelledDispatchDoesNotInvokeHandler() async {
        let router = SchemeRouter()
        router.registerSchemes(["bilidili"])
        var calls = 0
        router.register(module: "page", action: "open") { _ in
            calls += 1
            return .success()
        }
        let request = Task { @MainActor in
            await router.dispatch(urlString: "bilidili://page/open")
        }
        request.cancel()
        let result = await request.value
        guard case .failure(.cancelled) = result else {
            Issue.record("启动前取消应返回 cancelled")
            return
        }
        #expect(calls == 0)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, Double(Int.max), .greatestFiniteMagnitude, -1])
    func invalidDurationDoesNotTrap(_ value: Double) {
        #expect(value.aox_durationText == "00:00")
    }

    @Test
    func finiteDurationKeepsExistingFormatting() {
        #expect(0.0.aox_durationText == "00:00")
        #expect(70.9.aox_durationText == "01:10")
        #expect(3_661.9.aox_durationText == "1:01:01")
        let large = Double(Int.max).nextDown
        let hours = Int(large) / 3_600
        #expect(large.aox_durationText.hasPrefix("\(hours):"))
    }
}
