import CodexBarCore
import Foundation

enum ClaudeMagpieFixture {
    /// Shape of magpie `GET /v1/magpie/quotas`, with a Codex row that must be ignored.
    static let quotasJSON = """
    {"data":[
      {"provider":"claude","name":"Claude Code","kind":"subscription","plan":"team",
       "user":"first@example.com · Example Org","alias":"main",
       "windows":[
         {"name":"5 hours","used":12,"remaining":88,"resetsAt":"2026-10-14T21:10:00+08:00"},
         {"name":"7 days","used":76,"remaining":24,"resetsAt":"2026-10-16T03:00:00+08:00"},
         {"name":"7 days · Fable","used":4,"remaining":96,"resetsAt":"2026-10-16T03:00:00+08:00"},
         {"name":"30 days","used":50,"remaining":50}
       ],
       "readAt":"2026-10-14T16:44:16.777738+08:00","lastServedAt":"2026-10-14T08:45:16.183993Z"},
      {"provider":"claude","name":"Claude Code","kind":"subscription","plan":"team",
       "user":"second@example.com · Example Org",
       "windows":[
         {"name":"5 hours","used":0,"remaining":100},
         {"name":"7 days","used":84,"remaining":16,"resetsAt":"2026-10-17T03:00:00+08:00"}
       ],
       "readAt":"2026-10-14T11:40:18.067382+08:00","last":true},
      {"provider":"codex","name":"Codex","kind":"subscription","plan":"plus","user":"codex@example.com",
       "windows":[{"name":"5 hours","used":1,"remaining":99}],"readAt":"2026-10-14T11:40:18Z"},
      {"provider":"claude","name":"Claude Code","kind":"subscription","plan":"team",
       "user":"third@example.com · Example Org","windows":[],"readAt":"2026-10-13T18:56:49Z"}
    ]}
    """

    static var quotasData: Data {
        Data(self.quotasJSON.utf8)
    }

    static func transport(
        data: Data = Self.quotasData,
        status: Int = 200) -> ClaudeMagpieAccountReader.Transport
    {
        { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }
}
