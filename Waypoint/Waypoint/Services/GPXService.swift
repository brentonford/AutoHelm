import Foundation

/// Exports and imports GPX 1.1 files for waypoints.
struct GPXService {

    // MARK: - Export

    static func exportGPX(waypoints: [Waypoint]) -> URL? {
        let iso = ISO8601DateFormatter()
        var xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="AutoHelm"
                 xmlns="http://www.topografix.com/GPX/1/1">

            """

        for wp in waypoints {
            let time = iso.string(from: wp.dateCreated)
            xml += """
                  <wpt lat="\(wp.latitude)" lon="\(wp.longitude)">
                    <name>\(escapeXML(wp.name))</name>
                    <desc>\(escapeXML(wp.notes))</desc>
                    <time>\(time)</time>
                  </wpt>

                """
        }
        xml += "</gpx>\n"

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoHelm_Waypoints_\(Int(Date().timeIntervalSince1970)).gpx")
        do {
            try xml.write(to: dest, atomically: true, encoding: .utf8)
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - Import

    struct ImportedWaypoint {
        let name: String
        let notes: String
        let latitude: Double
        let longitude: Double
        let date: Date
    }

    static func importGPX(from url: URL) -> [ImportedWaypoint] {
        guard url.startAccessingSecurityScopedResource() else { return [] }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return GPXParser(data: data).parse()
    }

    // MARK: - Helpers

    private static func escapeXML(_ str: String) -> String {
        str
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'",  with: "&apos;")
    }
}

// MARK: - XMLParserDelegate

private final class GPXParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var results: [GPXService.ImportedWaypoint] = []

    private var inWpt        = false
    private var currentLat:  Double?
    private var currentLon:  Double?
    private var currentName  = ""
    private var currentDesc  = ""
    private var currentTime: Date?
    private var currentElem  = ""

    init(data: Data) { self.data = data }

    func parse() -> [GPXService.ImportedWaypoint] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return results
    }

    func parser(_ parser: XMLParser,
                didStartElement element: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes attrs: [String: String]) {
        currentElem = element
        if element == "wpt" {
            inWpt = true
            currentLat  = attrs["lat"].flatMap(Double.init)
            currentLon  = attrs["lon"].flatMap(Double.init)
            currentName = ""
            currentDesc = ""
            currentTime = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inWpt else { return }
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        switch currentElem {
        case "name": currentName = s
        case "desc": currentDesc = s
        case "time": currentTime = ISO8601DateFormatter().date(from: s)
        default: break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement element: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        if element == "wpt", inWpt {
            if let lat = currentLat, let lon = currentLon, !currentName.isEmpty {
                results.append(GPXService.ImportedWaypoint(
                    name: currentName,
                    notes: currentDesc,
                    latitude: lat,
                    longitude: lon,
                    date: currentTime ?? Date()
                ))
            }
            inWpt = false
        }
    }
}
