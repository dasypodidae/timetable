//© 2020 dasypodidae.

import Foundation

import SwiftUI
import Combine
import MobileCoreServices
import BackgroundTasks



private final class ReloadTimer {
    private var timer: Timer

    init(_ handler: @escaping () -> Void) {
        let new = Timer(timeInterval: Timetable.reloadInterval, repeats: true) { _ in
            handler()
        }
        new.tolerance = Timetable.reloadInterval/10
        new.fireDate = Date.distantFuture
        RunLoop.main.add(new, forMode:RunLoop.Mode.default)

        timer = new
    }

    deinit {
        timer.invalidate()
    }

    public func fire(_ date: Date = Date()) {
        timer.fireDate = date
    }
}

fileprivate struct ReloadThrottle {
    let interval: TimeInterval
    var lastReloadTime: TimeInterval = 0
    
    mutating func check() -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        if (now - lastReloadTime) < interval {
            return false
        } else {
            lastReloadTime = now
            return true
        }
    }
}


public class Timetable: ObservableObject {
    public static let shared = Timetable()

    struct UserDefaultsKey {
        static let needsFavoriteNotification = "Timetable.needsFavoriteNotification"
        static let needsRecordingNotification = "Timetable.needsRecordingNotification"
    }
    
    public static let requestTimeoutInterval: TimeInterval = 5
    public static let url: URL = URL(string: "http://yp.ladio.net/stats/list.v2.zdat")!
    
    static let reloadInterval: TimeInterval = 63
    
    var downloader = RadioDownloder()
    var bookmark = Bookmark()
    var recommend = Recommend()
    
    private var isFirstUpdate = true
    private var reloadThrottle = ReloadThrottle(interval: Timetable.reloadInterval/2)
    
    private let lockQueue = DispatchQueue(label: "Timetable.lockQueue", qos: .userInteractive)
    @Published var radioPrograms: [RadioProgram] = []
    
    @Published var needsFavoriteNotification: Bool
    
    var reloadCancellable: AnyCancellable? = nil
    private var cancellables: Set<AnyCancellable> = []
    
    private var reloadTimer: ReloadTimer?
    private var reloadLastModified: String?
    
    init() {
        UserDefaults.standard.register(defaults: [UserDefaultsKey.needsFavoriteNotification : true, UserDefaultsKey.needsRecordingNotification: true])
        needsFavoriteNotification = UserDefaults.standard.bool(forKey: UserDefaultsKey.needsFavoriteNotification)
        downloader.needsUserNotification = UserDefaults.standard.bool(forKey: UserDefaultsKey.needsRecordingNotification)
        
        $needsFavoriteNotification.sink {
            UserDefaults.standard.set($0, forKey: UserDefaultsKey.needsFavoriteNotification)
        }
        .store(in: &cancellables)
        
        downloader.$needsUserNotification.sink {
            UserDefaults.standard.set($0, forKey: UserDefaultsKey.needsRecordingNotification)
        }
        .store(in: &cancellables)
        
        
        NotificationCenter.default.publisher(for: .bookmarkDidChange)
            .sink { [weak self] _ in
                self?.recalcBookmark()
        }
        .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .recommendDidChange)
            .sink { [weak self] _ in
                self?.recalcRecommend()
        }
        .store(in: &cancellables)
        
        
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink(receiveValue: { [weak self] _ in
                self?.reloadTimer = ReloadTimer() { [weak self] in
                    self?.reload()
                }
                self?.reloadTimer?.fire()
            })
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink(receiveValue: { [weak self] _ in
                self?.reloadTimer = nil
            })
            .store(in: &cancellables)
        
    }
    
    func recalcDownloadState(_ set: Set<String>) {
        lockQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            DispatchQueue.main.sync {
                for (index, item) in self.radioPrograms.enumerated() {
                    let newValue = set.contains(item.audioURL)
                    if newValue != self.radioPrograms[index].isRecording {
                        self.radioPrograms[index].isRecording = newValue
                    }
                }
            }
        }
    }
    
    func recalcRecommend() {
        lockQueue.async { [weak self] in
            if let self = self {
                var newPrograms = self.radioPrograms
                for i in 0..<newPrograms.count {
                    newPrograms[i].filterResult.clearRecommend()
                    
                }
                newPrograms = self.calcFilter(newPrograms)
                newPrograms = RadioProgram.sort(newPrograms)
                DispatchQueue.main.sync {
                    self.radioPrograms = newPrograms
                }
            }
        }
    }
    
    func recalcBookmark() {
        lockQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            var newPrograms = self.radioPrograms
            for i in 0..<newPrograms.count {
                newPrograms[i].filterResult.clearBookmark()
            }
            newPrograms = self.calcFilter(newPrograms)
            newPrograms = RadioProgram.sort(newPrograms)
            DispatchQueue.main.sync {
                self.radioPrograms = newPrograms
            }
        }
    }
    
    func update(_ data: String) {
        lockQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            var newPrograms = RadioProgram.convert(data, before: self.radioPrograms)
            newPrograms = self.calcFilter(newPrograms)
            newPrograms = RadioProgram.sort(newPrograms)
            DispatchQueue.main.sync {
                self.radioPrograms = newPrograms
            }
            if self.isFirstUpdate {
                self.isFirstUpdate = false
                self.downloader.postStateDidChangeNotification()
            }
        }
    }
    
    func reload(backgroundTask: BGTask) {
        self.scheduleBackgroundReload()
        
        guard reloadThrottle.check() else { return }
        
        self.reloadCancellable = dataPublisher()
            .sink(receiveCompletion: { _ in
                backgroundTask.setTaskCompleted(success: true)
            }) { [weak self] (data, lastModified) in
                self?.update(data)
                self?.reloadLastModified = lastModified
        }
    }
    func reload() {
        guard reloadThrottle.check() else { return }
        
        reloadCancellable = dataPublisher()
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    if case TempError.statusCode(let reason) = error {
                    }
                    break
                }
            }) { [weak self] (data, lastModified) in
                self?.update(data)
                self?.reloadLastModified = lastModified
        }
    }
    enum TempError: LocalizedError {
        case httpResponse, decodeFailed, statusCode(reason: Int)
        
        var errorDescription: String? {
            switch self {
            case .statusCode(let reason):
                return "statusCode: \(reason)"
            case .decodeFailed:
                return "decodeFailed"
            case .httpResponse:
                return "httpResponseFailed"
            }
        }
    }
    
    func dataPublisher() -> AnyPublisher<(String, String?), Error> {
        
        
        var request: URLRequest = URLRequest(url: Timetable.url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: Timetable.requestTimeoutInterval)
        if let v = reloadLastModified {
            request.setValue(v, forHTTPHeaderField: "If-Modified-Since")
        }
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { (data, response) -> (String, String?) in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TempError.httpResponse
                }
                guard 200..<300 ~= httpResponse.statusCode else {
                    throw TempError.statusCode(reason: httpResponse.statusCode)
                }
                
                
                if let text = Timetable.decodeJIS(with: data) {
                    
                    return (text, (httpResponse.allHeaderFields["Last-Modified"] as? String))
                } else {
                    throw TempError.decodeFailed
                }
        }
        .eraseToAnyPublisher()
    }
    
    class func decodeJIS(with data: Data) -> String? {
        var temp: NSString? = nil
        let options: [StringEncodingDetectionOptionsKey : Any] = [.suggestedEncodingsKey: [String.Encoding.shiftJIS.rawValue], .useOnlySuggestedEncodingsKey: true ]
        _ = NSString.stringEncoding(for: data, encodingOptions: options, convertedString: &temp, usedLossyConversion: nil)
        
        return temp as String?
    }
    
    func calcFilter(_ before: [RadioProgram]) -> [RadioProgram] {
        var notifyMessage = ""
        let needsNotification = self.needsFavoriteNotification
        var programs = before
        programLoop: for (index, var program) in programs.enumerated() {
            var notifyFlag = false
            defer {
                if notifyFlag && needsNotification {
                    if (program.isNotified == false) {
                        notifyMessage += "\(program.dj) "
                        if program.name != "" {
                            notifyMessage += program.name
                        } else if program.description != "" {
                            notifyMessage += program.description
                        }
                        notifyMessage += "\n"
                        programs[index].isNotified = true
                    }
                }
            }
            
            let elements = program.mainElements
            
            switch program.filterResult.bookmarkCheckResult {
            case .favorite, .block:
                continue programLoop
            case .unknown:
                let newResult = bookmark.check(elements: elements)
                programs[index].filterResult.bookmarkCheckResult = newResult
                switch newResult {
                case .favorite:
                    notifyFlag = true
                    continue programLoop
                case .block:
                    continue programLoop
                default: break
                }
            default: break
            }
            
            if case .unknown = program.filterResult.recommendCheckResult {
                let newResult = recommend.check(elements: elements)
                programs[index].filterResult.recommendCheckResult = newResult
                switch newResult {
                case .recommend:
                    notifyFlag = true
                    continue programLoop
                case .notRecommend:
                    continue programLoop
                default: break
                }
            }
        }
        
        if notifyMessage != "" {
            addFavoriteNotification(body: notifyMessage, identifier: "favorite.\(Date())")
        }
        
        return programs
    }
    
    func addFavoriteNotification(title: String = "ねとらじ配信中", subtitle: String? = nil, body: String, identifier: String) {
        guard needsFavoriteNotification else { return }
        
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
            content.threadIdentifier = "favorite"
            
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            center.add(request)
        }
    }
}


extension Timetable {
    var backgroundReloadTaskIdentifier: String {
        return "timetable.refresh"
    }
    func registerBackgroundReload() {
        let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundReloadTaskIdentifier, using: nil) { [weak self] task in
            guard let self = self else {
                task.setTaskCompleted(success: true)
                return
            }
            self.reload(backgroundTask: task)
        }
        assert(ok)
    }
    
    func scheduleBackgroundReload() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundReloadTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 120)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            
        }
    }
}

extension Timetable {
    private struct ReloadButton: View {
        @ObservedObject var timetable: Timetable
        
        var body: some View {
            Button(action: {
                self.timetable.reload()
            }) {
                Image(systemName: "arrow.clockwise.circle.fill")
            }
        }
    }
    
    func reloadButton() -> some View {
        return ReloadButton(timetable: self)
    }
}



extension Timetable {
    struct NotificationSettingSection: View {
        @ObservedObject var timetable: Timetable
        
        @State var notificationEnabled = true
        func checkUNUserNotification() {
            UNUserNotificationCenter.current().getNotificationSettings { (settings) in
                let newValue = (settings.authorizationStatus == .authorized)
                DispatchQueue.main.async {
                    self.notificationEnabled = newValue
                }
            }
        }
        
        var body: some View {
            Section(header: Text("通知")) {
                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                }) {
                    HStack {
                        Text("通知設定を確認")
                        Spacer()
                        if notificationEnabled == false {
                            Text("オフ")
                                .font(.caption)
                                .accentColor(.secondary)
                        }
                    }
                }
                .onAppear {
                    self.checkUNUserNotification()
                }
                
                Toggle(isOn: $timetable.needsFavoriteNotification) {
                    Text("お気に入り番組の通知")
                }
                
                Toggle(isOn: $timetable.downloader.needsUserNotification) {
                    Text("録音終了の通知")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { v in
                self.checkUNUserNotification()
            }
        }
    }
}

func open(urlString: String) {
    guard let url = URL(string: urlString) else {
        return
    }
    if UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url, completionHandler: nil)
    } else {
    }
    
}
