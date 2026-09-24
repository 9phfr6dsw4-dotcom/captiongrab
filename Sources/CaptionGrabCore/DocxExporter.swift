import Foundation

public enum DocxExporter {
    private struct ZipEntry {
        let name: String
        let contents: Data
    }

    public static func makeDOCX(for transcript: TranscriptData) throws -> Data {
        var paragraphs = [paragraph(transcript.videoTitle, bold: true), paragraph("YouTube Video url: \(transcript.videoURL.absoluteString)")]
        for cue in transcript.cues {
            paragraphs.append(paragraph(cue.displayTimestamp))
            paragraphs.append(paragraph(cue.text, preservingLineBreaks: true))
        }

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(paragraphs.joined())<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
        """
        let relationships = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """

        return makeZip([
            ZipEntry(name: "[Content_Types].xml", contents: Data(contentTypes.utf8)),
            ZipEntry(name: "_rels/.rels", contents: Data(relationships.utf8)),
            ZipEntry(name: "word/document.xml", contents: Data(document.utf8))
        ])
    }

    private static func paragraph(_ text: String, bold: Bool = false, preservingLineBreaks: Bool = false) -> String {
        let properties = bold ? "<w:rPr><w:b/></w:rPr>" : ""
        let parts = preservingLineBreaks ? text.components(separatedBy: "\n") : [text]
        let runs = parts.enumerated().map { index, part in
            let lineBreak = index == 0 ? "" : "<w:br/>"
            return "\(lineBreak)<w:t xml:space=\"preserve\">\(xmlEscape(part))</w:t>"
        }.joined()
        return "<w:p><w:r>\(properties)\(runs)</w:r></w:p>"
    }

    private static func xmlEscape(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            let code = scalar.value
            guard code == 0x9 || code == 0xA || code == 0xD || (code >= 0x20 && code <= 0xD7FF) || (code >= 0xE000 && code <= 0xFFFD) || (code >= 0x10000 && code <= 0x10FFFF) else { continue }
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func makeZip(_ entries: [ZipEntry]) -> Data {
        var output = Data()
        var directory = Data()

        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.contents)
            let offset = UInt32(output.count)

            output.appendLittleEndian(UInt32(0x04034b50))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(0x0800))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0x0021))
            output.appendLittleEndian(crc)
            output.appendLittleEndian(UInt32(entry.contents.count))
            output.appendLittleEndian(UInt32(entry.contents.count))
            output.appendLittleEndian(UInt16(name.count))
            output.appendLittleEndian(UInt16(0))
            output.append(name)
            output.append(entry.contents)

            directory.appendLittleEndian(UInt32(0x02014b50))
            directory.appendLittleEndian(UInt16(20))
            directory.appendLittleEndian(UInt16(20))
            directory.appendLittleEndian(UInt16(0x0800))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0x0021))
            directory.appendLittleEndian(crc)
            directory.appendLittleEndian(UInt32(entry.contents.count))
            directory.appendLittleEndian(UInt32(entry.contents.count))
            directory.appendLittleEndian(UInt16(name.count))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt32(0))
            directory.appendLittleEndian(offset)
            directory.append(name)
        }

        let directoryOffset = UInt32(output.count)
        output.append(directory)
        output.appendLittleEndian(UInt32(0x06054b50))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(entries.count))
        output.appendLittleEndian(UInt16(entries.count))
        output.appendLittleEndian(UInt32(directory.count))
        output.appendLittleEndian(directoryOffset)
        output.appendLittleEndian(UInt16(0))
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
