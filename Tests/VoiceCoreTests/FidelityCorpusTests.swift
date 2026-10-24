import Testing
@testable import VoiceCore

struct FidelityCorpusCase: Sendable {
    let raw: String
    let cleaned: String
    let flags: Bool
}

struct FidelityCorpusTests {
    static let cases: [FidelityCorpusCase] = [
        .init(raw: "the timeout is fifteen seconds", cleaned: "The timeout is 15 seconds.", flags: false),
        .init(raw: "họp lúc ba giờ chiều", cleaned: "Họp lúc 3 giờ chiều.", flags: false),
        .init(raw: "meet at three, no I mean four", cleaned: "Meet at 4.", flags: false),
        .init(raw: "first fix login second update docs", cleaned: "1. Fix login\n2. Update docs", flags: false),
        .init(raw: "uh open Info.plist and bump it", cleaned: "Open Info.plist and bump it.", flags: false),
        .init(raw: "check the app model class", cleaned: "Check the AppModel class.", flags: false),
        .init(raw: "um please open the door", cleaned: "Please open the door.", flags: false),
        .init(raw: "eh este pues abre la puerta", cleaned: "Abre la puerta.", flags: false),
        .init(raw: "ờ mở cửa giúp tôi", cleaned: "Mở cửa giúp tôi.", flags: false),
        .init(raw: "don't merge it", cleaned: "Do not merge it.", flags: false),
        .init(raw: "no cambies el archivo", cleaned: "No cambies el archivo.", flags: false),
        .init(raw: "chưa xong việc", cleaned: "Chưa xong việc.", flags: false),
        .init(raw: "son treinta y cinco euros", cleaned: "Son 35 euros.", flags: false),
        .init(raw: "hai mươi lăm phút", cleaned: "25 phút.", flags: false),
        .init(raw: "one hundred twenty five rows", cleaned: "125 rows.", flags: false),
        .init(raw: "one thousand five hundred rows", cleaned: "1,500 rows.", flags: false),
        .init(raw: "version one point five", cleaned: "Version 1.5", flags: false),
        .init(raw: "the third item", cleaned: "The 3rd item.", flags: false),
        .init(raw: "thứ hai trong danh sách", cleaned: "2nd trong danh sách.", flags: false),
        .init(raw: "el primero de la lista", cleaned: "El 1.º de la lista.", flags: false),
        .init(raw: "usa 1500 al 15%", cleaned: "Usa 1.500 al 15%.", flags: false),
        .init(raw: "at 3 30", cleaned: "At 3:30.", flags: false),
        .init(raw: "send ⟦S1⟧ now", cleaned: "Send ⟦S1⟧ now.", flags: false),
        .init(raw: "open ./App.swift and ~/notes/today.md", cleaned: "Open `./App.swift` and `~/notes/today.md`.", flags: false),
        .init(raw: "run --filter and -x", cleaned: "Run --filter and -x.", flags: false),
        .init(raw: "info.plist needs updating", cleaned: "Info.plist needs updating.", flags: false),
        .init(raw: "use AppModel and user_profile", cleaned: "Use **AppModel** and `user_profile`.", flags: false),
        .init(raw: "gọi lúc 2 giờ à không 3 giờ", cleaned: "Gọi lúc 3 giờ.", flags: false),
        .init(raw: "usa 5 no, perdón 6", cleaned: "Usa 6.", flags: false),
        .init(raw: "use OldName actually NewName", cleaned: "Use NewName.", flags: false),
        .init(raw: "we should not ship Friday", cleaned: "We should ship Friday.", flags: true),
        .init(raw: "đừng xoá file này", cleaned: "Xoá file này.", flags: true),
        .init(raw: "set the limit to 5", cleaned: "Set the limit to 50.", flags: true),
        .init(raw: "around 20 users", cleaned: "Around 20 users, about 30%.", flags: true),
        .init(raw: "edit Sources/VoiceCore/History.swift", cleaned: "Edit Sources/History.swift.", flags: true),
        .init(raw: "rename user_profile to UserProfile", cleaned: "Rename user profile to user profile.", flags: true),
        .init(raw: "never delete backups", cleaned: "Delete backups.", flags: true),
        .init(raw: "nothing was changed", cleaned: "Everything was changed.", flags: true),
        .init(raw: "without permission", cleaned: "With permission.", flags: true),
        .init(raw: "we can't ship", cleaned: "We can ship.", flags: true),
        .init(raw: "cannot delete this", cleaned: "Delete this.", flags: true),
        .init(raw: "không đổi tên", cleaned: "Đổi tên.", flags: true),
        .init(raw: "chưa gửi thư", cleaned: "Gửi thư.", flags: true),
        .init(raw: "chẳng cần thay đổi", cleaned: "Cần thay đổi.", flags: true),
        .init(raw: "chả có gì", cleaned: "Có gì.", flags: true),
        .init(raw: "no borres esto", cleaned: "Borra esto.", flags: true),
        .init(raw: "nunca cambies esto", cleaned: "Cambia esto.", flags: true),
        .init(raw: "sin permiso", cleaned: "Con permiso.", flags: true),
        .init(raw: "nadie vino", cleaned: "Todos vinieron.", flags: true),
        .init(raw: "tampoco funciona", cleaned: "Funciona.", flags: true),
        .init(raw: "mở Info.plist", cleaned: "Mở tệp.", flags: true),
        .init(raw: "abre ~/docs/report.md", cleaned: "Abre el informe.", flags: true),
        .init(raw: "open ./Sources/App.swift", cleaned: "Open Sources/App.swift.", flags: true),
        .init(raw: "open C:\\Users\\test.txt", cleaned: "Open the file.", flags: true),
        .init(raw: "use appModel", cleaned: "Use Appmodel.", flags: true),
        .init(raw: "use user_id", cleaned: "Use user id.", flags: true),
        .init(raw: "run --verbose", cleaned: "Run verbose.", flags: true),
        .init(raw: "run -x", cleaned: "Run x.", flags: true),
        .init(raw: "use `widget`", cleaned: "Use gadget.", flags: true),
        .init(raw: "límite 15", cleaned: "Límite 50.", flags: true),
    ]

    @Test(arguments: cases)
    func corpus(_ sample: FidelityCorpusCase) {
        #expect(!FidelityCheck.issues(raw: sample.raw, cleaned: sample.cleaned).isEmpty == sample.flags)
    }
}
