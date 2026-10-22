import XCTest
@testable import WerkbankCore

final class GmailTests: XCTestCase {
    func testBase64URLDecodeWithoutPaddingAndUrlSafeAlphabet() {
        // "subjects?>" → c3ViamVjdHM_Pg (met '_' i.p.v. '/')
        XCTAssertEqual(Base64URL.decode("c3ViamVjdHM_Pg").flatMap { String(data: $0, encoding: .utf8) }, "subjects?>")
        XCTAssertEqual(Base64URL.decode("aGk").flatMap { String(data: $0, encoding: .utf8) }, "hi")
        XCTAssertNil(Base64URL.decode("a"))
    }

    func testBase64URLRoundTrip() {
        let data = Data([0xFB, 0xFF, 0xFE, 0x00, 0x10])
        XCTAssertEqual(Base64URL.decode(Base64URL.encode(data)), data)
        XCTAssertFalse(Base64URL.encode(data).contains("="))
    }

    func testMessageListParsing() {
        let json = #"{"messages":[{"id":"a1","threadId":"t1"},{"id":"a2","threadId":"t1"}],"nextPageToken":"NEXT"}"#
        let result = GmailAPI.messageRefs(fromListJSON: Data(json.utf8))
        XCTAssertEqual(result.refs, [.init(id: "a1", threadID: "t1"), .init(id: "a2", threadID: "t1")])
        XCTAssertEqual(result.nextPageToken, "NEXT")
    }

    func testEmptyInboxHasNoMessagesKey() {
        let result = GmailAPI.messageRefs(fromListJSON: Data(#"{"resultSizeEstimate":0}"#.utf8))
        XCTAssertTrue(result.refs.isEmpty)
        XCTAssertNil(result.nextPageToken)
    }

    func testSummaryFromMetadata() throws {
        let json = """
        {"id":"m1","threadId":"t9","labelIds":["INBOX","UNREAD"],"snippet":"Zie bijlage &amp; groet",
         "internalDate":"1700000000000",
         "payload":{"headers":[
           {"name":"From","value":"=?UTF-8?Q?Ren=C3=A9_de_Vries?= <rene@acme.nl>"},
           {"name":"Subject","value":"Offerte aanvraag"},
           {"name":"Date","value":"Tue, 14 Nov 2023 22:13:20 +0000"}]}}
        """
        let summary = try XCTUnwrap(GmailAPI.summary(fromMessageJSON: Data(json.utf8)))
        XCTAssertEqual(summary.id, "m1")
        XCTAssertEqual(summary.threadID, "t9")
        XCTAssertEqual(summary.fromName, "René de Vries")
        XCTAssertEqual(summary.fromAddress, "rene@acme.nl")
        XCTAssertEqual(summary.subject, "Offerte aanvraag")
        XCTAssertEqual(summary.snippet, "Zie bijlage & groet")
        XCTAssertEqual(summary.date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(summary.isUnread)
        XCTAssertEqual(summary.senderDisplay, "René de Vries")
    }

    func testSummaryWithoutSubjectAndRead() throws {
        let json = #"{"id":"m2","threadId":"t2","labelIds":["INBOX"],"payload":{"headers":[{"name":"From","value":"info@acme.nl"}]}}"#
        let summary = try XCTUnwrap(GmailAPI.summary(fromMessageJSON: Data(json.utf8)))
        XCTAssertEqual(summary.subject, EMLParser.emptySubject)
        XCTAssertEqual(summary.senderDisplay, "info@acme.nl")
        XCTAssertFalse(summary.isUnread)
    }

    func testRawMessageIsDecodedAndParsable() throws {
        let eml = "From: Jan <jan@acme.nl>\r\nSubject: Hallo\r\nContent-Type: text/plain\r\n\r\nInhoud van de mail"
        let json = "{\"raw\":\"\(Base64URL.encode(Data(eml.utf8)))\"}"
        let data = try XCTUnwrap(GmailAPI.rawMessage(fromJSON: Data(json.utf8)))
        let mail = EMLParser.parse(data)
        XCTAssertEqual(mail.subject, "Hallo")
        XCTAssertEqual(mail.fromAddress, "jan@acme.nl")
        XCTAssertEqual(mail.bodyText, "Inhoud van de mail")
    }

    func testRedirectSchemeIsReversedClientID() {
        XCTAssertEqual(GoogleOAuth.redirectScheme(forClientID: "123-abc.apps.googleusercontent.com"),
                       "com.googleusercontent.apps.123-abc")
        XCTAssertEqual(GoogleOAuth.redirectURI(forClientID: "123-abc.apps.googleusercontent.com"),
                       "com.googleusercontent.apps.123-abc:/oauth2redirect")
        XCTAssertNil(GoogleOAuth.redirectScheme(forClientID: ""))
        XCTAssertNil(GoogleOAuth.redirectScheme(forClientID: "geen-client-id"))
        XCTAssertNil(GoogleOAuth.redirectScheme(forClientID: ".apps.googleusercontent.com"))
    }

    func testAuthorizationURLContainsPKCEAndOfflineAccess() throws {
        let url = try XCTUnwrap(GoogleOAuth.authorizationURL(clientID: "123-abc.apps.googleusercontent.com",
                                                              codeChallenge: "CHALLENGE", state: "STATE"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(value("client_id"), "123-abc.apps.googleusercontent.com")
        XCTAssertEqual(value("redirect_uri"), "com.googleusercontent.apps.123-abc:/oauth2redirect")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("scope"), GoogleOAuth.scope)
        XCTAssertEqual(value("code_challenge"), "CHALLENGE")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("state"), "STATE")
        XCTAssertEqual(value("access_type"), "offline")
    }

    func testAuthorizationURLAsksForAccountChoiceOnlyWhenRequested() throws {
        func prompt(_ select: Bool) throws -> String? {
            let url = try XCTUnwrap(GoogleOAuth.authorizationURL(clientID: "123-abc.apps.googleusercontent.com",
                                                                  codeChallenge: "C", state: "S", selectAccount: select))
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "prompt" }?.value
        }
        XCTAssertEqual(try prompt(false), "consent")
        XCTAssertEqual(try prompt(true), "select_account consent")
    }

    func testParseRedirect() throws {
        let ok = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=4%2F0AX&state=STATE"))
        let parsed = GoogleOAuth.parseRedirect(ok)
        XCTAssertEqual(parsed.code, "4/0AX")
        XCTAssertEqual(parsed.state, "STATE")
        XCTAssertNil(parsed.error)

        let denied = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?error=access_denied&state=STATE"))
        XCTAssertEqual(GoogleOAuth.parseRedirect(denied).error, "access_denied")
        XCTAssertNil(GoogleOAuth.parseRedirect(denied).code)
    }

    func testTokenResponseAndErrors() throws {
        let tokens = try XCTUnwrap(GoogleOAuth.parseTokenResponse(
            Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":3599,"token_type":"Bearer"}"#.utf8)))
        XCTAssertEqual(tokens.accessToken, "AT")
        XCTAssertEqual(tokens.refreshToken, "RT")
        XCTAssertEqual(tokens.expiresIn, 3599)

        // Bij verversen komt er geen nieuwe refresh-token mee.
        let refreshed = try XCTUnwrap(GoogleOAuth.parseTokenResponse(Data(#"{"access_token":"AT2","expires_in":3599}"#.utf8)))
        XCTAssertNil(refreshed.refreshToken)

        let error = try XCTUnwrap(GoogleOAuth.parseError(
            Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8)))
        XCTAssertTrue(error.requiresNewSignIn)
        XCTAssertNil(GoogleOAuth.parseTokenResponse(Data(#"{"error":"invalid_grant"}"#.utf8)))
    }

    func testDragPayloadRoundTrip() throws {
        let payload = GmailDragPayload(messageID: "m1", threadID: "t1")
        let data = try JSONEncoder().encode(payload)
        XCTAssertEqual(try JSONDecoder().decode(GmailDragPayload.self, from: data), payload)
    }
}

final class GmailThreadTests: XCTestCase {
    func testThreadMetadataParsing() {
        let json = """
        {"id":"t1","messages":[
          {"id":"b","labelIds":["INBOX","UNREAD"],"snippet":"Tot &amp; met","internalDate":"2000",
           "payload":{"headers":[{"name":"From","value":"=?UTF-8?B?Sm9zw6k=?= <jose@x.nl>"},{"name":"To","value":"me@x.nl"},{"name":"Subject","value":"Re: Hoi"}]}},
          {"id":"a","labelIds":["SENT"],"snippet":"Hoi","internalDate":"1000",
           "payload":{"headers":[{"name":"From","value":"me@x.nl"},{"name":"Cc","value":"c@x.nl"},{"name":"Subject","value":"Hoi"}]}},
          {"id":"d","labelIds":["DRAFT"],"internalDate":"3000","payload":{"headers":[]}}
        ]}
        """
        let messages = GmailAPI.threadMessages(fromJSON: Data(json.utf8)) ?? []
        XCTAssertEqual(messages.map(\.id), ["a", "b"])
        XCTAssertTrue(messages[0].isSent)
        XCTAssertEqual(messages[0].cc, "c@x.nl")
        XCTAssertTrue(messages[1].isUnread)
        XCTAssertEqual(messages[1].from, "José <jose@x.nl>")
        XCTAssertEqual(messages[1].snippet, "Tot & met")
    }

    func testSingleMessageMetadata() {
        let json = """
        {"id":"m1","threadId":"t1","labelIds":["SENT"],"snippet":"Ik kijk er morgen naar","internalDate":"1700000000000",
         "payload":{"headers":[{"name":"To","value":"Jan <jan@klant.nl>"},{"name":"Subject","value":"=?UTF-8?Q?Re:_Caf=C3=A9?="}]}}
        """
        let message = GmailAPI.threadMessage(fromMessageJSON: Data(json.utf8))
        XCTAssertEqual(message?.id, "m1")
        XCTAssertEqual(message?.to, "Jan <jan@klant.nl>")
        XCTAssertEqual(message?.subject, "Re: Café")
        XCTAssertEqual(message?.isSent, true)
        XCTAssertEqual(message?.date, Date(timeIntervalSince1970: 1_700_000_000))

        let draft = #"{"id":"d","labelIds":["DRAFT"],"internalDate":"1","payload":{"headers":[]}}"#
        XCTAssertNil(GmailAPI.threadMessage(fromMessageJSON: Data(draft.utf8)))
    }
}
