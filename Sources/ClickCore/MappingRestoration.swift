import Foundation

public enum MappingRestoration {
    /// 只恢复仍与 Click 写入值一致的源键；保留其他程序在运行期间做的修改。
    public static func restore(current: [HIDMapping], original: [HIDMapping], applied: [HIDMapping]) -> [HIDMapping] {
        var result = current
        for mapping in applied {
            let before = original.first { $0.source == mapping.source }
            guard before != mapping,
                  let index = result.firstIndex(where: { $0.source == mapping.source }),
                  result[index] == mapping else { continue }
            if let before { result[index] = before } else { result.remove(at: index) }
        }
        return result
    }
}
