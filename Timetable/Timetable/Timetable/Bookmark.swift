//© 2020 dasypodidae.

import SwiftUI
import Combine

final class BookmarkElement: ObservableObject {
    @Published var array: [String]
    var userDefaultsKey: String?
    var needsRecalc = false
    
    var cancellable: AnyCancellable?
    
    init(array newArray: [String]) {
        array = newArray
        cancellable = $array
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] v in
                if let self = self {
                    if let key = self.userDefaultsKey {
                        UserDefaults.standard.set(v, forKey: key)
                    }
                    self.needsRecalc = true
                }
        }
    }
    
    convenience init(userDefaultsKey: String) {
        self.init(array: UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? [])
        self.userDefaultsKey = userDefaultsKey
    }
    
    func append(_ keyword: String) {
        if !array.contains(keyword) {
            array.insert(keyword, at: 0)
        }
    }
    func remove(_ keyword: String) {
        if let index = array.firstIndex(of: keyword) {
            array.remove(at: index)
        }
    }
    
    func check(_ elements: [String]) -> String? {
        return array.first { (v) -> Bool in
            elements.contains(where: { $0.contains(v) })
        }
    }
    
}

extension BookmarkElement {
    private struct SectionView: View {
        @ObservedObject var model: BookmarkElement
        
        var title: String
        var image: Image
        var key: String
        
        var body: some View {
            let temp = model.array.filter{(key == "") || $0.localizedCaseInsensitiveContains(key)}
            return Section(header: HStack {Text(title)
                Spacer()
                image
                    .font(.footnote)
            }) {
                ForEach(temp, id:\.self) {item in
                    Text(item)
                }
                .onDelete { (indexSet) in
                    for index in indexSet {
                        if let removeIndex = self.model.array.firstIndex(of: temp[index]) {
                            self.model.array.remove(at: removeIndex)
                        }
                    }
                }
            }
        }
    }
    
    func sectionView(title: String, image: Image, key: String) -> some View {
        return SectionView(model: self, title: title, image: image, key: key)
    }
}



final class Bookmark: ObservableObject {
    var favorite: BookmarkElement = BookmarkElement(userDefaultsKey: "Bookmark.favorite")
    var block: BookmarkElement = BookmarkElement(userDefaultsKey: "Bookmark.block")
    
    @Published var viewVisible: Bool = false
    @Published var key: String?
    
    func openView(key: String? = nil) {
        self.key = key
        viewVisible = true
    }
    
    enum CheckResult {
        case unknown, nothing, favorite(String), block(String)
    }
    func check(elements: [String]) -> CheckResult {
        if let v = block.check(elements) {
            return .block(v)
        }
        if let v = favorite.check(elements) {
            return .favorite(v)
        }
        return .nothing
    }
}

extension Bookmark {
    private struct NewKeywordView: View {
        enum BookmarkType: String {
            case favorite = "お気に入り"
            case block = "ブロック"
        }
        @State private var type = BookmarkType.favorite
        @State private var keyword = ""
        var block: (BookmarkType, String) -> Void
        
        func add() {
            let newKeyword = keyword.trimmingCharacters(in: .whitespaces)
            guard 0 < newKeyword.count else {
                return
            }
            block(type, newKeyword)
        }
        
        var body: some View {
            VStack(spacing: nil) {
                Picker(selection: $type, label: Text("BookmarkType")) {
                    Text(BookmarkType.favorite.rawValue).tag(BookmarkType.favorite)
                    Text(BookmarkType.block.rawValue).tag(BookmarkType.block)
                }
                .pickerStyle(SegmentedPickerStyle())
                .fixedSize()
                
                HStack {
                    TextField("keyword", text: $keyword, onEditingChanged: { (v) in
                    }) {
                    }
                    .autocapitalization(.none)
                    .foregroundColor(.primary)
                }
                .padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10.0)
                    .shadow(color: Color(.secondarySystemBackground), radius: 2)
                
                Button("\(type.rawValue)に追加") {
                    self.add()
                }
                .disabled(keyword == "")
            }
            .padding()
        }
    }

    private struct SearchBar: View {
        @Binding var searchText: String

        var body: some View {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("search", text: $searchText, onEditingChanged: { isEditing in
                }, onCommit: {
                })
                .autocapitalization(.none)
                    .foregroundColor(.primary)
            }
            .padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10.0)
                .shadow(color: Color(.secondarySystemBackground), radius: 2)
        }
    }
    
    func recalcIfNeeded() {
        if favorite.needsRecalc || block.needsRecalc {
            favorite.needsRecalc = false
            block.needsRecalc = false
            NotificationCenter.default.post(name: .bookmarkDidChange, object: nil)
        }
    }
    
    struct MainView: View {
        let bookmark: Bookmark
        @ObservedObject var favorite: BookmarkElement
        @ObservedObject var block: BookmarkElement
        
        @State private var searchText: String = ""
        
        enum OptionViewType {
            case none, add, searchBar
        }
        @State private var optionView: OptionViewType = .none
        
        init(_ bookmark: Bookmark) {
            self.bookmark = bookmark
            favorite = bookmark.favorite
            block = bookmark.block
            if let v = bookmark.key {
                _optionView = State(initialValue: OptionViewType.searchBar)
                _searchText = State(initialValue: v)
            }
        }
        
        func seachButton() -> some View {
            Button(action: {
                withAnimation {
                    if self.optionView != .searchBar {
                        self.optionView = .searchBar
                    } else {
                        self.optionView = .none
                        self.searchText = ""
                    }
                }
            }) {
                Image(systemName: "magnifyingglass")
                    .padding(.leading)
            }
        }
        func addButton() -> some View {
            Button(action: {
                withAnimation {
                    if self.optionView != .add {
                        self.optionView = .add
                        self.searchText = ""
                    } else {
                        self.optionView = .none
                    }
                }
            }) {
                Image(systemName: "plus.circle")
                    .padding(.leading)
            }
        }
        func trailingItems() -> some View {
            HStack {
                #if targetEnvironment(macCatalyst)
                EditButton()
                #endif
                seachButton()
                addButton()
            }
            .padding(.vertical)
        }
        
        var body: some View {
            VStack(spacing: 0) {
                if self.optionView != .none {
                    if self.optionView == .add {
                        NewKeywordView(block: { (type, key) in
                            switch type {
                            case .favorite:
                                self.favorite.append(key)
                            case .block:
                                self.block.append(key)
                            }
                        })
                            .transition(.move(edge: .top))
                    }
                    if self.optionView == .searchBar {
                        SearchBar(searchText: $searchText)
                            .padding(.horizontal)
                            .padding(. vertical)
                            .transition(.move(edge: .top))
                    }
                    Divider()
                }
                List {
                    favorite.sectionView(title: "お気に入り", image: Image(systemName: "heart.fill"), key: searchText)
                    block.sectionView(title: "ブロック", image: Image(systemName: "ant.fill"), key: searchText)
                }
            }
            .navigationBarTitle("ブックマーク", displayMode: .inline)
            .navigationBarItems(trailing: trailingItems())
            .onDisappear {
                self.bookmark.recalcIfNeeded()
            }
        }
    }
    
    func mainView() -> some View {
        return MainView(self)
    }
}


extension Notification.Name {
    static let bookmarkDidChange = Notification.Name("bookmarkDidChange")
}
