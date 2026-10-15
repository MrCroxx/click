import Foundation
public struct Key: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let virtual: UInt16
}
public enum KeyCatalog {
    public static let keys: [Key] = {
        var result: [Key] = []
        let letters: [UInt16] = [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6]
        for (i, code) in letters.enumerated() { result.append(Key(id: i+4, name: String(UnicodeScalar(65+i)!), virtual: code)) }
        let digits: [UInt16] = [18,19,20,21,23,22,26,28,25,29]
        for (i, code) in digits.enumerated() { result.append(Key(id: i+30, name: String((i+1)%10), virtual: code)) }
        let specials: [(Int,String,UInt16)] = [
            (40,"Return",36),(41,"Escape",53),(42,"Delete",51),(43,"Tab",48),(44,"Space",49),
            (45,"−",27),(46,"=",24),(47,"[",33),(48,"]",30),(49,"\\",42),(51,";",41),(52,"'",39),
            (53,"`",50),(54,",",43),(55,".",47),(56,"/",44),(57,"Caps Lock",57),
            (73,"Insert",114),(74,"Home",115),(75,"Page Up",116),(76,"Forward Delete",117),
            (77,"End",119),(78,"Page Down",121),(79,"→",124),(80,"←",123),(81,"↓",125),(82,"↑",126),
            (224,"Left Control",59),(225,"Left Shift",56),(226,"Left Option",58),(227,"Left Command",55),
            (228,"Right Control",62),(229,"Right Shift",60),(230,"Right Option",61),(231,"Right Command",54)
        ]
        result += specials.map { Key(id: $0.0, name: $0.1, virtual: $0.2) }
        let functions: [UInt16] = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
        for (i, code) in functions.enumerated() { result.append(Key(id: i < 12 ? i+58 : i+92, name: "F\(i+1)", virtual: code)) }
        return result
    }()
    public static func name(_ usage: Int) -> String { keys.first { $0.id == usage }?.name ?? "Unknown" }
    public static func virtual(_ usage: Int) -> UInt16? { keys.first { $0.id == usage }?.virtual }
    public static func isModifier(_ usage: Int) -> Bool { (224...231).contains(usage) || usage == 57 }
}
