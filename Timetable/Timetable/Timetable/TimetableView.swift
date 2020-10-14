//© 2020 dasypodidae.

import SwiftUI



struct DetailView: View {
     let surl: String
     
     @Environment(\.presentationMode) var presentationMode
     
     @ObservedObject var timetable: Timetable = Timetable.shared
     @ObservedObject var player: RadioPlayer = RadioPlayer.shared
     
     
     func FilterHintView(_ program: RadioProgram) -> some View {
          HStack {
               program.filterResult.icon()
                    .layoutPriority(1)
               Text(program.filterResult.text)
                    .textCase(nil)
                    .foregroundColor(.primary)
          }
          .font(.caption)
     }
     func programView(_ program: RadioProgram) -> some View {
          VStack(spacing: 0) {
               Form {
                    Section(header: HStack {
                         Spacer()
                         FilterHintView(program)
                    }) {
                         Group {
                              ProgramItem(label: "タイトル", text: program.name)
                              ProgramItem(label: "DJ名", text: program.dj)
                              ProgramItem(label: "ジャンル", text: program.genre)
                              ProgramItem(label: "放送内容", text: program.description)
                              URLRow(program)
                              ProgramItem(label: "リスナー数", text: "現在\(program.listeners)人, 最大\(program.maxListeners)人,  延べ\(program.totalListeners)人")
                              ProgramItem(label: "マウント", text: program.mount)
                              ProgramItem(label: "曲", text: program.song)
                              ProgramItem(label: "サウンド", text: "\(program.fileExtension), \(program.samplerate)kHz,  \(program.bitrate)kbps,  \(program.channelsText)")
                              ProgramItem(label: "放送開始時刻", text: program.time)
                         }
                         .lineLimit(2)
                         .font(.footnote)
                    }
               }
               .environment(\.defaultMinListRowHeight, 10)
          }
          .navigationTitle("番組の詳細")
     }
     
     
     func ProgramItem(label: String, text: String) -> some View {
          HStack {
               Text("\(label):")
               Text(text)
               Spacer()
          }
     }
     
     func URLRow(_ program: RadioProgram) -> some View {
          HStack {
               Text("関連URL:")
               if program.isURL, let url = URL(string: program.url) {
                    if program.isShitaraba {
                         Button(action: {
                              open(urlString: program.url)
                         }) {
                              HStack {
                                   Text(program.url)
                                   Spacer()
                                   Image(systemName: "pencil.and.ellipsis.rectangle")
                              }
                         }
                    } else {
                         Link(destination: url) {
                              HStack {
                                   Text(program.url)
                                   Spacer()
                                   Image(systemName: "globe")
                              }
                         }
                    }
               } else {
                    Button(action: {
                    }) {
                         Text(program.url)
                    }
                    .disabled(true)
               }
          }
          .buttonStyle(BorderlessButtonStyle())
     }
     
     var body: some View {
          VStack {
               if let program = timetable.radioPrograms.first { $0.surl == surl } {
                    programView(program)
               } else {
                    Button(action: {
                         self.presentationMode.wrappedValue.dismiss()
                    }) {
                         Text("番組は終了しました")
                    }
                    .padding()
               }
          }
     }
}



struct ProgramRow: View {
     @ObservedObject var player: RadioPlayer = RadioPlayer.shared
     let program: RadioProgram
     @Binding var selectedSURL: String
     @Binding var detailVisible: Bool
     
     func mainView() -> some View {
          VStack {
               HStack {
                    Text(program.name)
                    
                    Spacer()
                    program.filterResult.icon()
                         .font(.caption)
                    
                    if program.isRecording {
                         Image(systemName: "recordingtape")
                              .foregroundColor(.green)
                              .font(.caption)
                    }
                    Text(program.listeners)
                         .bold()
                         .layoutPriority(1)
               }
               HStack {
                    Text(program.dj)
                         .font(.subheadline)
                    
                    Spacer()
                    
                    HStack {
                         Image(systemName: "clock.fill")
                              .foregroundColor(.secondary)
                              .font(.caption)
                         Text(program.airtime)
                              .foregroundColor(.secondary)
                         if self.player.surl == program.surl {
                              Image(systemName: self.player.isBuffering ? "hourglass" : "music.note")
                                   .foregroundColor(.purple)
                                   .font(.subheadline)
                              
                         }
                    }
                    .font(.subheadline)
                    .layoutPriority(1)
               }
          }
          .lineLimit(1)
     }
     
     
     func bookmarkButton() -> some View {
          Group {
               
               switch program.filterResult.bookmarkCheckResult {
               case .unknown:
                    Button {
                    } label: {
                         Image(systemName: "book.fill")
                    }
                    .disabled(true)
               case .nothing:
                    Menu {
                         Button {
                              Timetable.shared.bookmark.favorite.append(program.mount)
                              Timetable.shared.recalcBookmark()
                         } label: {
                              Label("お気に入りに追加", systemImage: "heart.fill")
                         }
                    } label: {
                         Image(systemName: "heart.fill")
                    }
                    
               case let .favorite(key), let .block(key):
                    Button {
                         Timetable.shared.bookmark.openView(key: key)
                    } label: {
                         Image(systemName: "book.fill")
                    }
               }
          }
     }
     
     func urlButton() -> some View {
          Group {
               if let url = URL(string: program.url) {
                    if program.isShitaraba {
                         Button(action: {
                            open(urlString: program.url)
                         }, label: {
                              Image(systemName: "pencil.and.ellipsis.rectangle")
                         })
                    } else {
                         Link(destination: url) {
                              Image(systemName: "globe")
                         }
                    }
               } else {
                    Button(action: {
                    }, label: {
                         Image(systemName: "globe")
                    })
                    .disabled(true)
               }
          }
     }
     func infoButton() -> some View {
          
          Button(action: {
               selectedSURL = program.surl
               detailVisible = true
          }, label: {
               Image(systemName: "info.circle.fill")
          })
     }
     func playButton() -> some View {
          return Button(action: {
               player.togglePlay(program)
          }, label: {
               player.buttonImage(program.surl)
          })
          .disabled(!program.canPlay)
     }
    func recordButton() -> some View {
        Group {
            if program.isRecording {
                Menu {
                    Button(action: {
                        guard let url = URL(string: program.audioURL) else {
                            return
                        }
                        Timetable.shared.downloader.cancel(url)
                    }, label: {
                        Label("録音を中止（ファイルは残りません）", systemImage: "trash")
                    })
                } label: {
                    Image(systemName: "recordingtape")
                }
            } else {
                let downloadAction = {
                    guard let url = URL(string: program.audioURL) else {
                        return
                    }
                    Timetable.shared.downloader.download(url, filename: program.filename)
                }
                    Menu {
                        Button {
                            downloadAction()
                        } label: {
                            Label("録音を開始", systemImage: "recordingtape")
                        }
                        Section {
                            Text("録音ファイルはファイルAppで確認できます")
                        }
                    } label: {
                        Image(systemName: "recordingtape")
                    }
            }
        }
    }
     
     var body: some View {
          if selectedSURL != program.surl {
               Button(action: {
                    selectedSURL = program.surl
               }, label: {
                    mainView()
                         .transition(.scale)
               })
          } else {
               
               VStack {
                    mainView()
                    HStack {
                         Text(program.genre)
                              .font(.footnote)
                         Spacer()
                         Text(program.description)
                              .font(.footnote)
                    }
                    .lineLimit(1)
                    HStack {
                         let insets = EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
                         Spacer()
                         infoButton()
                              .padding(insets)
                         
                         bookmarkButton()
                              .padding(insets)
                         
                         urlButton()
                              .padding(insets)
                         
                         recordButton()
                              .padding(insets)
                         
                         playButton()
                              .padding(insets)
                    }
                    .buttonStyle(BorderlessButtonStyle())
               }
          }
     }
}



struct ProgramList: View {
     @ObservedObject var timetable: Timetable
     @ObservedObject var bookmark = Timetable.shared.bookmark
     @State var selectedSURL: String = ""
     @State var detailVisible: Bool = false
     
     var body: some View {
          VStack {
               List {
                    ForEach(timetable.radioPrograms, id: \.surl) { program in
                         ProgramRow(program: program, selectedSURL: self.$selectedSURL, detailVisible: self.$detailVisible)
                    }
               }
               .onReceive(NotificationCenter.default.publisher(for: .radioDownloaderStateDidChange)) { v in
                  
                    guard let set = v.object as? Set<String> else {
                         return
                    }
                    self.timetable.recalcDownloadState(set)
               }
               
               NavigationLink(destination: DetailView(surl: selectedSURL), isActive: $detailVisible) {
                    EmptyView()
               }
               .hidden()
               NavigationLink(destination: timetable.bookmark.mainView(), isActive: $bookmark.viewVisible) {
                    EmptyView()
               }
               .hidden()
          }
     }
}

let navigationBarItemPadding: CGFloat = 8

struct TimetableView: View {
     @ObservedObject var timetable: Timetable = Timetable.shared
    @ObservedObject var recommend: Recommend = Timetable.shared.recommend
     
     func copyrightSection() -> some View {
          Section(footer: HStack {
               Button(action: {
                    open(urlString: "https://github.com/dasypodidae/")
               }) {
                    Text("© 2020 dasypodidae.")
               }
          } ) {
            HStack {
                Text("アイコン")
                Spacer()
                Link("いらすとん", destination: URL(string: "http://www.irasuton.com/")!)
            }
//               EmptyView()
          }
     }
     
     func settingView() -> some View {
          Form {
               Timetable.NotificationSettingSection(timetable: timetable)
               Recommend.SettingView(recommend: timetable.recommend)
               copyrightSection()
          }
          .navigationBarTitle("番組表設定")
     }
     
     func leadingItems(width: CGFloat) -> some View {
          ZStack {
               HStack {
                    NavigationLink(destination: self.settingView()) {
                         Image(systemName: "gearshape.fill")
                    }
                    .padding(.vertical)
                    .padding(.trailing, navigationBarItemPadding)
               }
               Image("AppImage")
                    .offset(y: -3)
                    .frame(width: 29, height: 29)
                    .clipShape(Circle())
                    .shadow(radius: 1)
                    .offset(x: width/2 - 29 - 4)
          }
     }
     func trailingItems() -> some View {
          HStack {
               Button {
                    timetable.bookmark.openView()
               } label: {
                    Image(systemName: "book.fill")
               }
               .padding(.horizontal, navigationBarItemPadding)
               .padding(.leading, navigationBarItemPadding)
               
               RadioPlayer.StopButton(player: RadioPlayer.shared)
                    .padding(.leading, navigationBarItemPadding)
          }
          .padding(.vertical)
     }
     
     var body: some View {
          NavigationView {
               GeometryReader { geometry in
                    ProgramList(timetable: self.timetable)
                         .navigationBarTitle(Text(""), displayMode: .inline)
                         .navigationBarItems(leading: self.leadingItems(width: geometry.size.width), trailing: self.trailingItems())
               }
          }
          .navigationViewStyle(StackNavigationViewStyle())
          .alert(isPresented: $recommend.alertVisible) {
            Alert(title: Text("おすすめ番組の情報を受け取りますか？"), primaryButton: Alert.Button.default(Text("受け取る"), action: {
                recommend.firstLaunchAction(true)
            }), secondaryButton: Alert.Button.cancel({
                recommend.firstLaunchAction(false)
            }))
          }
     }
}
