import Foundation
import WebKit

@MainActor
final class IFCImporter: NSObject, WKScriptMessageHandler, WKURLSchemeHandler, WKNavigationDelegate
{
  private var web: WKWebView?
  private var input = Data()
  private var continuation: CheckedContinuation<[Feature], Error>?
  private var features: [Feature] = []
  private var roomID = UUID(), stageID = UUID()
  private var timeout: Task<Void, Never>?
  private var activeRequest:UUID?
  func load(_ data: Data, roomID: UUID, stageID: UUID) async throws -> [Feature] {
    guard data.count <= 50_000_000 else {
      throw HouseError.message("IFC input exceeds 50 MB. The source can still be archived.")
    }
    guard activeRequest==nil else{throw HouseError.message("An IFC import is already active.")}
    try Task.checkCancellation()
    let request=UUID();activeRequest=request
    defer{if activeRequest==request {activeRequest=nil;input=Data()}}
    self.input = data
    self.roomID = roomID
    self.stageID = stageID
    features = []
    return try await withTaskCancellationHandler(operation:{
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let config = WKWebViewConfiguration()
      config.websiteDataStore = .nonPersistent()
      config.setURLSchemeHandler(self, forURLScheme: "hxlocal")
      config.userContentController.add(self, name: "ifc")
      let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
      self.web = web
      web.navigationDelegate = self
      web.load(URLRequest(url: URL(string: "hxlocal://bundle/index.html")!))
      timeout = Task {
        try? await Task.sleep(nanoseconds: 60_000_000_000)
        if !Task.isCancelled {
          finish(
            .failure(
              HouseError.message("IFC import exceeded its time budget. Source remains preserved.")))
        }
      }
      }
    },onCancel:{
      Task { @MainActor [weak self] in
        guard let self,self.activeRequest==request else{return}
        self.finish(.failure(CancellationError()))
      }
    })
  }
  private func finish(_ result: Result<[Feature], Error>) {
    timeout?.cancel()
    timeout = nil
    web?.stopLoading()
    web?.configuration.userContentController.removeScriptMessageHandler(forName: "ifc")
    web = nil
    input = Data();activeRequest=nil;features=[]
    let c = continuation
    continuation = nil
    c?.resume(with: result)
  }
  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard continuation != nil,message.webView===web else{return}
    guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
      return
    }
    if type == "mesh", let points = body["vertices"] as? [[Double]],
      let indices = body["indices"] as? [Int32]
    {
      guard points.count <= 200000, points.allSatisfy({ $0.count == 3 }),
        features.reduce(0, { $0 + $1.mesh.vertices.count }) + points.count <= 200000
      else {
        finish(.failure(HouseError.message("IFC geometry exceeds its admission budget.")))
        return
      }
      // web-ifc applies its coordination transform to a Y-up rendering frame.
      let mesh = Mesh(vertices: points.map { V3($0[0], -$0[2], $0[1]) }, triangles: indices)
      guard mesh.valid else {
        finish(.failure(HouseError.message("IFC produced invalid geometry.")))
        return
      }
      var feature = Feature(
        name: body["name"] as? String ?? "IFC element", trade: .structure, roomID: roomID,
        stageID: stageID, kind: .planned, mesh: mesh)
      feature.notes =
        "IFC design geometry · GUID \(body["guid"] as? String ?? "unknown"). Original units and placements are handled by web-ifc 0.0.72. Design is not observed construction."
      features.append(feature)
    } else if type == "done" {
      if features.isEmpty {
        finish(.failure(HouseError.message("No supported IFC geometry found.")))
      } else {
        finish(.success(features))
      }
    } else if type == "error" {
      finish(
        .failure(HouseError.message("IFC: \(body["message"] as? String ?? "conversion failed")")))
    }
  }
  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    guard let url = urlSchemeTask.request.url, url.scheme == "hxlocal" else {
      urlSchemeTask.didFailWithError(HouseError.message("External IFC resource blocked."))
      return
    }
    do {
      let data: Data
      let mime: String
      if url.host == "input", url.path == "/model.ifc" {
        data = input
        mime = "application/octet-stream"
      } else {
        let name = url.lastPathComponent
        guard ["index.html", "web-ifc-api-iife.js", "web-ifc.wasm"].contains(name),
          let folder = Bundle.main.url(forResource: "IFC", withExtension: nil)
        else { throw HouseError.message("Bundled IFC dependency missing.") }
        data = try Data(contentsOf: folder.appendingPathComponent(name))
        mime =
          name.hasSuffix("wasm")
          ? "application/wasm" : name.hasSuffix("js") ? "application/javascript" : "text/html"
      }
      let response = HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: "HTTP/1.1",
        headerFields: [
          "Content-Type": mime, "Content-Length": String(data.count),
          "Access-Control-Allow-Origin": "*",
        ])!
      urlSchemeTask.didReceive(response)
      urlSchemeTask.didReceive(data)
      urlSchemeTask.didFinish()
    } catch { urlSchemeTask.didFailWithError(error) }
  }
  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {if webView===web {finish(.failure(error))}}
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    guard webView===web else{return}
    finish(.failure(HouseError.message("IFC parser process stopped. Source remains preserved.")))
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) { decisionHandler(navigationAction.request.url?.scheme == "hxlocal" ? .allow : .cancel) }
}
