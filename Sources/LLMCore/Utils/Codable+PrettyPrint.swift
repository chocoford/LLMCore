//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 10/6/25.
//

import Foundation

extension Encodable {
    public func prettyPrintedJSON(maxValueLength: Int = 1000) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(self) else { return nil }

        // 尝试解析成 [String: Any]
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return String(data: data, encoding: .utf8) // fallback 原始 JSON
        }
        
        var truncated = truncateValues(in: jsonObject, maxLength: maxValueLength)
        
        guard let formattedData = try? JSONSerialization.data(withJSONObject: truncated, options: [.prettyPrinted, .sortedKeys]),
              let formattedString = String(data: formattedData, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) // fallback 原始 JSON
        }

        return formattedString
    }
    
    /// 递归截断所有字符串 value
    private func truncateValues(in object: Any, maxLength: Int) -> Any {
        switch object {
            case let dict as [String: Any]:
                var newDict = [String: Any]()
                for (key, value) in dict {
                    newDict[key] = truncateValues(in: value, maxLength: maxLength)
                }
                return newDict
                
            case let array as [Any]:
                return array.map { truncateValues(in: $0, maxLength: maxLength) }
                
            case let str as String:
                if str.count > maxLength {
                    let index = str.index(str.startIndex, offsetBy: maxLength)
                    return String(str[..<index]) + "..."
                }
                return str
                
            default:
                return object
        }
    }
}
