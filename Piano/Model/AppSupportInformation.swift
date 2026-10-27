import Foundation

enum AppSupportInformation {
    static let privacyPolicyURL = URL(
        string: "https://apps-bay.github.io/Apps-Bay-Website/privacy/"
    )!
    static let supportEmail = "appsbayarea@gmail.com"

    static func versionText(in bundle: Bundle = .main) -> String {
        let version = nonempty(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let build = nonempty(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        switch (version, build) {
        case let (version?, build?): return "Version \(version) (\(build))"
        case let (version?, nil): return "Version \(version)"
        case let (nil, build?): return "Build \(build)"
        case (nil, nil): return "Version unavailable"
        }
    }

    static func supportEmailURL(in bundle: Bundle = .main) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "PianoFlow support"),
            URLQueryItem(name: "body", value: versionText(in: bundle))
        ]
        return components.url
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
