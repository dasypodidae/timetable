//© 2020 dasypodidae.

import SwiftUI


enum InstantError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let v):
            return v
        }
    }
}



final class RadioDownloder: NSObject, ObservableObject {
    static let identifier = "jp.cocodemoraido.radioDownloder.background"
    
    private var completionHandler: (() -> Void)? = nil
    @Published var needsUserNotification = false
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    func saveCompletionHandler(_ handler: @escaping (() -> Void)) {
        completionHandler = handler
        _ = urlSession
    }
    
    
    
    func download(_ url: URL, filename: String) {
        urlSession.getAllTasks { [weak self] (array) in
            guard let self = self else { return }
            
            
            guard (array.first{ $0.originalRequest?.url == url } == nil) else {
                self.postStateDidChangeNotification(array)
                return
            }
            let req = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData)
            let task = self.urlSession.downloadTask(with: req)
            task.countOfBytesClientExpectsToSend = 512
            task.taskDescription = filename
            
            task.resume()
            
            var temp = array
            temp.append(task)
            self.postStateDidChangeNotification(temp)
        }
    }
    func cancel(_ url: URL) {
        urlSession.getAllTasks { (array) in
            array.forEach {
                if $0.originalRequest?.url == url {
                    $0.cancel()
                }
            }
        }
    }
    
}


extension RadioDownloder {
    
    func postStateDidChangeNotification() {
        urlSession.getAllTasks { [weak self] array in
            guard 0 < array.count else { return }
            self?.postStateDidChangeNotification(array)
        }
    }
    
    func postStateDidChangeNotification(_ array: [URLSessionTask]) {
        let set = Set(array.compactMap({
            $0.originalRequest?.url?.absoluteString
        }))
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .radioDownloaderStateDidChange, object: set, userInfo: nil)
        }
    }
    func addUserNotification(title: String, subtitle: String? = nil, body: String, identifier: String) {
        guard needsUserNotification else { return }
        
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { (settings) in
            guard settings.authorizationStatus == .authorized else {
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = title
            if let subtitle = subtitle {
                content.subtitle = subtitle
            }
            content.body = body
            content.threadIdentifier = "download"
            
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            center.add(request)
        }
    }
}

extension RadioDownloder: URLSessionDownloadDelegate {
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        
        let filename: String = downloadTask.taskDescription ?? location.lastPathComponent
        
        do {
            guard let httpResponse = downloadTask.response as? HTTPURLResponse else {
                throw InstantError.message("response != HTTPURLResponse")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw InstantError.message("statusCode: \(httpResponse.statusCode)")
            }
            
            let documentsURL = try FileManager.default.url(for: .documentDirectory,
                                                           in: .userDomainMask,
                                                           appropriateFor: nil,
                                                           create: false)
            let saveURL = documentsURL.appendingPathComponent(filename)
            try FileManager.default.moveItem(at: location, to: saveURL)
            addUserNotification(title: "ダウンロードが完了しました", body: filename, identifier: filename)
        } catch {
            addUserNotification(title: "ダウンロードに失敗しました", subtitle: filename, body: error.localizedDescription, identifier: filename)
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
       
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.urlSession.getAllTasks { (array) in
                    self?.postStateDidChangeNotification(array)
                }
            }
        }
        
        
        if let error = error {
            let nserr = error as NSError
            guard nserr.code != NSURLErrorCancelled else {
                return
            }
            let filename: String = task.taskDescription ?? ""
            addUserNotification(title: "ダウンロードに失敗しました", subtitle: filename, body: "システムエラー", identifier: filename)
        } else {
        }
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let block = completionHandler {
            completionHandler = nil
            DispatchQueue.main.async {
                block()
            }
        }
    }
    
}

extension Notification.Name {
    static let radioDownloaderStateDidChange = Notification.Name("radioDownloaderStateDidChange")
}
