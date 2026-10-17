import CoreKit

public enum UpdateTarget {
    public static func installable(bundlePath: String, isWritable: (String) -> Bool) -> String? {
        guard AppLocation.problem(bundlePath: bundlePath) == nil else {
            return nil
        }
        let bundle = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        guard let slash = bundle.lastIndex(of: "/"), slash != bundle.startIndex else {
            return nil
        }
        let parent = String(bundle[..<slash])
        guard isWritable(bundle), isWritable(parent) else {
            return nil
        }
        return bundle
    }
}
