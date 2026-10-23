//
//  File.swift
//  SwiftPM
//
//  Created by Brandon Jones on 9/21/2026.
//

import Foundation
import Testing

@testable import Commands

import _InternalTestSupport

@Suite(
    .tags(
        .TestSize.small,
        .Feature.CodeCoverage)
)
struct TestTagCollectorTests {
    @Test
    func collectsUniqueTagsFromTestAndSuiteRecords() {
        let jsonl = """
                   {"kind":"test","payload":{"kind":"suite","name":"SuiteA","tags":["integration"]},"version":"6.4.0"}
                   {"kind":"test","payload":{"kind":"function","name":"one()","tags":["slow"]},"version":"6.4.0"}
                   {"kind":"test","payload":{"kind":"function","name":"three()","tags":["slow","smoke"]},"version":"6.4.0"}
                   {"kind":"test","payload":{"kind":"function","name":"two()","tags":[]},"version":"6.4.0"}
                   """
               #expect(TestTagCollector.tags(fromJSONLines: jsonl) == ["integration", "slow", "smoke"])
           }

    @Test
      func ignoresEventRecordsAndMalformedLines() {
          let jsonl = """
              not json
              {"kind":"event","payload":{"kind":"runStarted"},"version":"6.4.0"}
              """
          #expect(TestTagCollector.tags(fromJSONLines: jsonl).isEmpty)
      }

      @Test
      func returnsNoTagsWhenTestsHaveNone() {
          let jsonl = """
              {"kind":"test","payload":{"kind":"function","name":"untagged()"},"version":"6.4.0"}
              {"kind":"test","payload":{"kind":"function","name":"two()","tags":[]},"version":"6.4.0"}
              """
          #expect(TestTagCollector.tags(fromJSONLines: jsonl).isEmpty)
          #expect(TestTagCollector.tags(fromJSONLines: "").isEmpty)
      }
  }
