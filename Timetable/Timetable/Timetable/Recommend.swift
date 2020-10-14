//© 2020 dasypodidae.

import SwiftUI
import Combine



private final class ReloadTimer {
    var timer: Timer
    
    init(_ handler: @escaping () -> Void) {
        let interval: TimeInterval = 60 * 60 * 24
        timer = Timer(fire: Date(timeIntervalSinceNow: interval), interval: interval, repeats: true) { (timer) in
            handler()
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode:RunLoop.Mode.default)
    }
    
    deinit {
        timer.invalidate()
    }
}




final class Recommend: ObservableObject {
    public static let sharedUserDefaultsKey = "Recommend"
    public static let firstLaunchKey = sharedUserDefaultsKey+".firstLaunch"
    public static let defaultURLString: String = "https://raw.githubusercontent.com/dasypodidae/cocodemoradio/master/recommend.txt"
    
    struct ReloadHint: Codable {
        var key: String
        var data: String
    }
    struct Keywords: Codable {
        var recommend: [String] = []
        var notRecommend: [String] = []
        var reloadHint: ReloadHint?
        
        static func load(_ defaultsKey: String) -> Keywords {
            return (try? JSONDecoder().decode(Self.self, from: UserDefaults.standard.data(forKey: defaultsKey) ?? Data())) ?? Self()
        }
        func save(_ defaultsKey: String) {
            if let json = try? JSONEncoder().encode(self) {
                UserDefaults.standard.set(json, forKey: defaultsKey)
            }
        }
    }
    
    @Published var alertVisible: Bool = UserDefaults.standard.bool(forKey: firstLaunchKey) == false
    @Published private (set) var keywords: Keywords
    @Published private (set) var enabled: Bool
    private var initFlag = false
    @Published private var urlString: String
    @Published private var errorText: String = ""
    
    private var dlCancellable: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []
    
    private var reloadTimer: ReloadTimer?
    
    init(userDefaultsKey key: String = Recommend.sharedUserDefaultsKey) {
        let enabledKey = "\(key).enabled"
        let urlStringKey = "\(key).urlString"
        let keywordsKey = "\(key).keywordsKey"
        UserDefaults.standard.register(defaults: [enabledKey : false, urlStringKey : Self.defaultURLString])
      
        enabled = UserDefaults.standard.bool(forKey: enabledKey)
        urlString = UserDefaults.standard.string(forKey: urlStringKey) ?? ""
        keywords = Keywords.load(keywordsKey)
        
        
        $enabled
            .dropFirst()
            .debounce(for: 0.7, scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] v in
                UserDefaults.standard.set(v, forKey: enabledKey)
                DispatchQueue.main.async {
                    if self?.enabled == true {
                        self?.reload(repeats: true)
                    } else {
                        self?.reloadTimer = nil
                        NotificationCenter.default.post(name: .recommendDidChange, object: self)
                    }
                }
        }
        .store(in: &cancellables)
        
        $urlString
            .dropFirst()
            .debounce(for: 0.7, scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] v in
                UserDefaults.standard.set(v, forKey: urlStringKey)
                self?.keywords = Keywords()
                DispatchQueue.main.async {
                    if self?.enabled == true {
                        self?.reload(repeats: true)
                    } else {
                        self?.reloadTimer = nil
                        NotificationCenter.default.post(name: .recommendDidChange, object: self)
                    }
                }
        }
        .store(in: &cancellables)
        
        $keywords
            .dropFirst()
            .sink { v in
                v.save(keywordsKey)
        }
        .store(in: &cancellables)
        
        if enabled {
            reload(repeats: true)
        }
    }

    func firstLaunchAction(_ newEnabled: Bool) {
        enabled = newEnabled
        UserDefaults.standard.set(true, forKey: Recommend.firstLaunchKey)
    }
    static func convert(rawdata: String) -> ([String], [String])? {
        //おすすめの書式
        //recommendを目印に空白行でお気に入りとブロックのリストを分ける。
        //
        //recommend
        //
        //お気に入り1
        //お気に入り2
        //お気に入り...
        //
        //ブロック1
        //ブロック...
        //
        var phase: Int = 0
        var favorite = [String]()
        var block = [String]()
        boss: for v in rawdata.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = v.trimmingCharacters(in: .whitespaces)
            
            switch phase {
            case 0:
                if text == "recommend" {
                    phase = 1
                }
            case 2://お気に入り
                favorite.append(text)
            case 4://ブロック
                block.append(text)
            case 5://終わり
                break boss
            default:
                break
            }
            guard v.count != 0 else {//空行はphaseを進める。
                phase += 1
                continue
            }
        }
        
        guard 1 <= phase else {
            return nil
        }
        return (favorite, block)
    }
    
    
    func reload(repeats: Bool) {
        reloadTimer = nil
        reload()
        if repeats {
            reloadTimer = ReloadTimer() { [weak self] in
                self?.reload()
            }
        }
    }
    private func reload() {
        self.errorText = ""
        
        enum TempError: LocalizedError {
            case httpResponse, notModified, notFound, decodeFailed, statusCode(reason: Int)
            var errorDescription: String? {
                switch self {
                case .notFound:
                    return "404 Not Found"
                case .notModified:
                    return "304 Not Modified"
                case .statusCode(let reason):
                    return "statusCode: \(reason)"
                case .decodeFailed:
                    return "decodeFailed"
                case .httpResponse:
                    return "httpResponseFailed"
                }
            }
        }
        
        guard let url = URL(string: urlString) else {
            self.errorText = "データURLが正しくありません。"
            return
        }
        var request: URLRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        if let hint = keywords.reloadHint {
            request.setValue(hint.data, forHTTPHeaderField: hint.key)
        }
        
        dlCancellable = URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { [weak self] (data, response) -> Keywords in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TempError.httpResponse
                }
                let statusCode = httpResponse.statusCode
                guard 200..<300 ~= statusCode else {
                    guard statusCode != 404 else {
                        throw TempError.notFound
                    }
                    guard statusCode != 304 else {
                        throw TempError.notModified
                    }
                    throw TempError.statusCode(reason: statusCode)
                }
                
                func decode(with data: Data) -> String? {
                    var temp: NSString? = nil
                    let options: [StringEncodingDetectionOptionsKey : Any] = [.suggestedEncodingsKey: [String.Encoding.utf8.rawValue,String.Encoding.shiftJIS.rawValue,String.Encoding.japaneseEUC.rawValue,String.Encoding.iso2022JP.rawValue], .useOnlySuggestedEncodingsKey: true ]
                    let encoding = NSString.stringEncoding(for: data, encodingOptions: options, convertedString: &temp, usedLossyConversion: nil)
                    
                    return temp as String?
                }
                
                guard let str = decode(with: data) else {
                    throw TempError.decodeFailed
                }
                guard let arrayTaple = Self.convert(rawdata: str) else {
                    throw TempError.decodeFailed
                }
                var newHint: ReloadHint? = nil
                if let Etag = httpResponse.allHeaderFields["Etag"] as? String {
                    newHint = ReloadHint(key: "If-None-Match", data: Etag)
                } else if let lastModified = httpResponse.allHeaderFields["Last-Modified"] as? String {
                    newHint = ReloadHint(key: "If-Modified-Since", data: lastModified)
                }
                return Keywords(recommend: arrayTaple.0, notRecommend: arrayTaple.1, reloadHint: newHint)
        }
        .receive(on: DispatchQueue.main)
        .sink(receiveCompletion: { [weak self] completion in
            self?.initFlag = true
            
            switch completion {
            case .finished:
                break
            case .failure(let error):
                if case .notModified = (error as? TempError) {
                   break
                } else {
                    self?.errorText = "データが取得できません。"
                }
                break
            }
            
            NotificationCenter.default.post(name: .recommendDidChange, object: self)
        }) { [weak self] (v) in
            self?.keywords = v
        }
    }
    
}

extension Recommend {
    public struct SettingView: View {
        @ObservedObject var recommend: Recommend
        
        
        func footerItem() -> some View {
            HStack {
                if recommend.enabled {
                    if recommend.errorText != "" {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(recommend.errorText)
                        if Recommend.defaultURLString != self.recommend.urlString {
                            Button(action: {
                                self.recommend.urlString = Recommend.defaultURLString
                            }) {
                                Text("Reset")
                            }
                        }
                    }
                }
            }
        }
            
        var body: some View {
            Section(header: Text("おすすめ番組"), footer: footerItem()) {
                Toggle(isOn: $recommend.enabled.animation()) {
                    Text("おすすめ番組を受け取る")
                }
                if recommend.enabled {
                    VStack {
                        HStack {
                            Text("データURL:")
                            TextField("URL", text: $recommend.urlString)
                                .autocapitalization(.none)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }
            }
        }
    }
}

private extension Array where Element == String {
    func check(_ elements: [String]) -> String? {
        for v in self {
            if elements.contains(where: { $0.contains(v) }) {
                return v
            }
        }
        return nil
    }
}

extension Recommend {
    enum CheckResult {
        case unknown
        case nothing
        case recommend(String)
        case notRecommend(String)
    }
    
    func check(elements: [String]) -> CheckResult {
        if enabled && initFlag {
            if let v = keywords.notRecommend.check(elements) {
                return .notRecommend(v)
            }
            if let v = keywords.recommend.check(elements) {
                return .recommend(v)
            }
        }
        return .nothing
    }
}



extension Notification.Name {
    static let recommendDidChange = Notification.Name("recommendDidChange")
}
