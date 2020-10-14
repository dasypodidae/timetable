//© 2020 dasypodidae.

import Foundation
import SwiftUI
import MobileCoreServices
import os.signpost


struct RadioProgram {
    
    var surl: String = ""
    var time: String = ""
    
    var server: String = ""
    var port: String = ""
    var mount: String = ""
    var type: String = ""
    
    var listeners: String = ""
    var maxListeners: String = ""
    var totalListeners: String = ""
    
    var name: String = ""
    var genre: String = ""
    var description: String = ""
    var dj: String = ""
    
    var song: String = ""
    var url: String = ""
    
    var bitrate: String = ""
    var samplerate: String = ""
    var channels: String = ""
    
    var isShitaraba: Bool {
        return url.contains("jbbs.shitaraba.net")
    }
    var isURL: Bool {
        return url.trimmingCharacters(in: .whitespacesAndNewlines) != ""
    }
    
    var canPlay: Bool {
        return (fileExtension != "ogg")
    }
    var channelsText: String {
        let dict: Dictionary<String, String> = ["1": "モノラル", "2": "ステレオ"]
        return dict[channels, default: "?"]
    }
    
    var mainElements: [String] {
        return [mount, dj, name, description, genre, url]
    }
    
    struct FilterResult {
        var bookmarkCheckResult: Bookmark.CheckResult = .unknown
        var recommendCheckResult: Recommend.CheckResult = .unknown
        
        mutating func clearBookmark() {
            bookmarkCheckResult = .unknown
        }
        mutating func clearRecommend() {
            recommendCheckResult = .unknown
        }
        mutating func clearAll() {
            clearBookmark()
            clearRecommend()
        }
        
        func icon() -> some View {
            var name: String = ""
            var color: Color = .secondary
            switch bookmarkCheckResult {
            case .favorite(_):
                name = "heart.fill"
                color = .red
            case .block(_):
                name = "ant.fill"
            default:
                switch recommendCheckResult {
                case .recommend(_):
                    name = "star.fill"
                    color = .yellow
                case .notRecommend(_):
                    name = "hand.raised.fill"
                default: break
                }
            }

            return Group {
                if name != "" {
                    Image(systemName: name)
                        .foregroundColor(color)
                } else {
                    EmptyView()
                }
            }
        }
        
        var text: String {
            switch bookmarkCheckResult {
            case .favorite(let key):
                return "お気に入り( \(key) )"
            case .block(let key):
                return "ブロック( \(key) )"
            default:
                switch recommendCheckResult {
                case .recommend(let key):
                    return "おすすめ( \(key) )"
                case .notRecommend(let key):
                    return "非推奨( \(key) )"
                default: break
                }
            }
            return ""
        }
        
        var priority: Int {
            switch bookmarkCheckResult {
            case .favorite(_):
                return 20000
            case .block(_):
                return -20000
            default:
                switch recommendCheckResult {
                case .recommend(_):
                    return 10000
                case .notRecommend(_):
                    return -10000
                default: break
                }
            }
            return 0
        }
    }
    var filterResult: FilterResult = FilterResult()
    var isNotified = false
    var isRecording = false
    
    func convertToDate(string: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(abbreviation: "JST")
        fmt.dateFormat = "yy/MM/dd HH:mm:ss"
        return fmt.date(from: string)
    }
    
    
    var fileExtension: String {
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, type as CFString, nil)?.takeRetainedValue(), let ext = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassFilenameExtension)?.takeRetainedValue() {
            
            return ext as String
        }
        
        if let item = type.split(separator: "/").last {
            return String(item)
        }
        return ""
    }
    
    var audioURL: String {
        return "http://\(server):\(port)\(mount)"
    }
    var m3uURL: String {
        return "\(audioURL).m3u"
    }
    var filename: String {
        let f = DateFormatter()
        f.dateFormat = "yyMMdd'T'HHmmss"
        return "\(f.string(from: Date())) \(name).\(fileExtension)"
    }

    var airtime: String {
        guard let startDate = convertToDate(string: time) else {
            return "?"
        }
        let airtime = Int(Date().timeIntervalSince(startDate))
        var str = ""
        if 3600 <= airtime {
            str += "\(airtime/3600)時間 "
        }
            str += String(format: "%02d分", airtime/60%60)
        return str
    }
    
    init?(_ dict: [Substring: Substring]) {
        surl = String(dict["SURL"] ?? "")
        guard 0 < surl.count else {
            return nil
        }
        
        let hint: [(WritableKeyPath<RadioProgram, String>, Substring)] = [
            (\.dj, "DJ"),
            (\.name, "NAM"),
            (\.description, "DESC"),
            (\.genre, "GNL"),
            (\.url, "URL"),
            (\.type, "TYPE"),
            (\.listeners, "CLN"),
            (\.maxListeners, "MAX"),
            (\.totalListeners, "CLNS"),
            (\.song, "SONG"),
            (\.bitrate, "BIT"),
            (\.samplerate, "SMPL"),
            (\.channels, "CHS"),
            
            (\.time, "TIMS"),
            (\.server, "SRV"),
            (\.port, "PRT"),
            (\.mount, "MNT"),
        ]
        for (keypath, dictKey) in hint {
            if let tempValue = dict[dictKey] {
                self[keyPath: keypath] = String(tempValue)
            }
        }
    }
    
    mutating func update(_ dict: [Substring: Substring]) {
        guard let temp = dict["SURL"], (self.surl == temp) else {
            return
        }
        
        let hint: [(WritableKeyPath<RadioProgram, String>, Substring, Bool)] = [
            (\.dj, "DJ", true),
            (\.name, "NAM", true),
            (\.description, "DESC", true),
            (\.genre, "GNL", true),
            (\.url, "URL", true),
            (\.type, "TYPE", false),
            (\.listeners, "CLN", false),
            (\.maxListeners, "MAX", false),
            (\.totalListeners, "CLNS", false),
            (\.song, "SONG", false),
            (\.bitrate, "BIT", false),
            (\.samplerate, "SMPL", false),
            (\.channels, "CHS", false)
        ]
        for (keypath, dictKey, filterFlag) in hint {
            if let tempValue = dict[dictKey] {
                if tempValue != self[keyPath: keypath] {
                    self[keyPath: keypath] = String(tempValue)
                    if filterFlag {
                        self.filterResult.clearAll()
                    }
                }
            }
        }
    }
}


extension RadioProgram {
    static func parse(_ rawdata: String) -> [[Substring: Substring]] {
        var tempDict: [Substring: Substring] = [:]
        var dictArray: [[Substring: Substring]] = []
        var lines = rawdata.split(separator: "\n", omittingEmptySubsequences: false)
        lines.append("")
        lines.forEach { (line) in
            guard (0 < line.count) else {
                guard (tempDict.count != 0) else {
                    return
                }
                dictArray.append(tempDict)
                tempDict.removeAll()
                return
            }
            let re = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if re.count == 2 {
                tempDict[re[0]] = re[1]
            }
        }
        return dictArray
    }
    
    
    static func convert(_ rawdata: String, before: [RadioProgram]) -> [RadioProgram] {
        let dictArray = parse(rawdata)
        
        var after: [RadioProgram] = []
        mainLoop: for dict in dictArray {
            if let surl = dict["SURL"] {
                for v in before {
                    if v.surl == surl {
                        var temp = v
                        temp.update(dict)
                        after.append(temp)
                        continue mainLoop
                    }
                }
                if let v = RadioProgram(dict) {
                    after.append(v)
                }
            }
        }
        
        return after
    }
    
    static func sort(_ before: [RadioProgram]) -> [RadioProgram] {
        func priority(_ v: RadioProgram) -> Int {
            var priority = Int(v.listeners) ?? 0
            priority += v.filterResult.priority
            return priority
        }
        return before.sorted{
            let a0 = priority($0)
            let a1 = priority($1)
            if a0 == a1 {
                return $0.time > $1.time
            }
            return a0 > a1
        }
    }
    
}
