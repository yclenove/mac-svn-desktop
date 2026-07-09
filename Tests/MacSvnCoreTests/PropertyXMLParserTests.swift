import XCTest
@testable import MacSvnCore

final class PropertyXMLParserTests: XCTestCase {
    func testParsesPropertiesWithTargetPathNameAndValue() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <properties>
          <target path="README.txt">
            <property name="svn:eol-style">native</property>
            <property name="custom:reviewer">杨超</property>
          </target>
        </properties>
        """

        let properties = try PropertyXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(properties, [
            SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native"),
            SvnProperty(target: "README.txt", name: "custom:reviewer", value: "杨超")
        ])
    }

    func testParsesEmptyPropertyValue() throws {
        let xml = """
        <properties><target path="README.txt"><property name="svn:needs-lock"></property></target></properties>
        """

        let properties = try PropertyXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(properties, [
            SvnProperty(target: "README.txt", name: "svn:needs-lock", value: "")
        ])
    }

    func testInvalidPropertyXMLThrowsParseError() {
        XCTAssertThrowsError(try PropertyXMLParser.parse(Data("<properties>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \(error)")
            }
        }
    }
}
