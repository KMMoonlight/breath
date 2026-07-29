import BreathNotes
import Foundation
import UniformTypeIdentifiers
@preconcurrency import WebKit

@MainActor
final class NoteEditorResourceSchemeHandler:
    NSObject,
    WKURLSchemeHandler,
    @unchecked Sendable
{
    static let scheme = "breath-note-resource"
    private static let maximumResourceSize = 20 * 1_024 * 1_024

    private var libraryRoot: URL?
    private var documentRelativePath = ""
    private var remoteTasks: [ObjectIdentifier: URLSessionTask] = [:]

    func update(libraryRoot: URL?, documentRelativePath: String) {
        self.libraryRoot = libraryRoot?.standardizedFileURL
        self.documentRelativePath = documentRelativePath
    }

    func webView(
        _ webView: WKWebView,
        start urlSchemeTask: any WKURLSchemeTask
    ) {
        guard let requestURL = urlSchemeTask.request.url,
              requestURL.scheme == Self.scheme
        else {
            fail(urlSchemeTask, code: .badURL)
            return
        }
        switch requestURL.host {
        case "local":
            serveLocal(requestURL, to: urlSchemeTask)
        case "remote":
            serveRemote(requestURL, to: urlSchemeTask)
        default:
            fail(urlSchemeTask, code: .unsupportedURL)
        }
    }

    func webView(
        _ webView: WKWebView,
        stop urlSchemeTask: any WKURLSchemeTask
    ) {
        let key = ObjectIdentifier(urlSchemeTask)
        let task = remoteTasks.removeValue(forKey: key)
        task?.cancel()
    }

    private func serveLocal(
        _ requestURL: URL,
        to schemeTask: any WKURLSchemeTask
    ) {
        guard let resourcePath = queryValue("path", in: requestURL) else {
            fail(schemeTask, code: .badURL)
            return
        }
        let root = libraryRoot
        let relativeDocument = documentRelativePath
        guard let root else {
            fail(schemeTask, code: .fileDoesNotExist)
            return
        }
        do {
            let resourceURL = try NoteResourceResolver
                .resolveExistingLocalResource(
                resourcePath,
                relativeTo: relativeDocument,
                libraryRoot: root
            )
            let values = try resourceURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isReadableKey,
                .fileSizeKey,
            ])
            guard values.isRegularFile == true,
                  values.isReadable != false,
                  let fileSize = values.fileSize,
                  fileSize <= Self.maximumResourceSize,
                  UTType(filenameExtension: resourceURL.pathExtension)?
                    .conforms(to: .image) == true
            else {
                throw URLError(.cannotDecodeContentData)
            }
            let data = try Data(contentsOf: resourceURL, options: .mappedIfSafe)
            respond(
                schemeTask,
                data: data,
                mimeType: mimeType(for: resourceURL),
                responseURL: requestURL
            )
        } catch {
            schemeTask.didFailWithError(error)
        }
    }

    private func serveRemote(
        _ requestURL: URL,
        to schemeTask: any WKURLSchemeTask
    ) {
        guard let rawURL = queryValue("url", in: requestURL),
              let remoteURL = URL(string: rawURL),
              remoteURL.scheme?.lowercased() == "https"
        else {
            fail(schemeTask, code: .unsupportedURL)
            return
        }
        var request = URLRequest(
            url: remoteURL,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 20
        )
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let key = ObjectIdentifier(schemeTask)
        let schemeTaskBox = URLSchemeTaskBox(schemeTask)
        let maximumResourceSize = Self.maximumResourceSize
        let task = NetworkSessionManager.shared.session.downloadTask(
            with: request
        ) { [weak self] fileURL, response, error in
            let data: Data?
            if let fileURL,
               let fileSize = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey]
               ).fileSize,
               fileSize <= maximumResourceSize
            {
                data = try? Data(
                    contentsOf: fileURL,
                    options: .mappedIfSafe
                )
            } else {
                data = nil
            }
            Task { @MainActor [weak self] in
                self?.finishRemote(
                    key: key,
                    schemeTask: schemeTaskBox.value,
                    requestURL: requestURL,
                    data: data,
                    response: response,
                    error: error
                )
            }
        }
        remoteTasks[key] = task
        task.resume()
    }

    private func finishRemote(
        key: ObjectIdentifier,
        schemeTask: any WKURLSchemeTask,
        requestURL: URL,
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) {
        guard remoteTasks.removeValue(forKey: key) != nil else {
            return
        }
        if let error {
            schemeTask.didFailWithError(error)
            return
        }
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme?.lowercased() == "https",
              (200..<300).contains(response.statusCode),
              response.mimeType?.lowercased().hasPrefix("image/") == true,
              response.expectedContentLength <= Int64(Self.maximumResourceSize)
                || response.expectedContentLength == NSURLSessionTransferSizeUnknown,
              let data
        else {
            fail(schemeTask, code: .cannotDecodeContentData)
            return
        }
        respond(
            schemeTask,
            data: data,
            mimeType: response.mimeType ?? "application/octet-stream",
            responseURL: requestURL
        )
    }

    private func respond(
        _ schemeTask: any WKURLSchemeTask,
        data: Data,
        mimeType: String,
        responseURL: URL
    ) {
        let response = URLResponse(
            url: responseURL,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        schemeTask.didReceive(response)
        schemeTask.didReceive(data)
        schemeTask.didFinish()
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == name })?.value
    }

    private func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?
            .preferredMIMEType ?? "application/octet-stream"
    }

    private func fail(
        _ task: any WKURLSchemeTask,
        code: URLError.Code
    ) {
        task.didFailWithError(URLError(code))
    }
}

private final class URLSchemeTaskBox: @unchecked Sendable {
    let value: any WKURLSchemeTask

    init(_ value: any WKURLSchemeTask) {
        self.value = value
    }
}
