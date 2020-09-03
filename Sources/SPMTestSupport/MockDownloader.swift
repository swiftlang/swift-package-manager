/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import Foundation

public class MockDownloader: Downloader {
    public typealias DownloadFile = (
        Foundation.URL,
        AbsolutePath,
        Downloader.Progress,
        Downloader.Completion
    ) -> Void

    public struct Download: Equatable {
        public let url: Foundation.URL
        public let destinationPath: AbsolutePath

        public init(url: Foundation.URL, destinationPath: AbsolutePath) {
            self.url = url
            self.destinationPath = destinationPath
        }
    }

    public var downloads: [Download] = []
    private var downloadFile: DownloadFile!

    public init(fileSystem: FileSystem, downloadFile: DownloadFile? = nil) {
        self.downloadFile = downloadFile ?? { url, destinationPath, _ , completion in
            try! fileSystem.writeFileContents(
                destinationPath,
                bytes: ByteString(encodingAsUTF8: url.absoluteString),
                atomically: true
            )

            self.downloads.append(Download(url: url, destinationPath: destinationPath))
            completion(.success(()))
        }
    }

    public func downloadFile(
        at url: Foundation.URL,
        to destinationPath: AbsolutePath,
        withAuthorizationProvider authorizationProvider: AuthorizationProviding? = nil,
        progress: @escaping Downloader.Progress,
        completion: @escaping Downloader.Completion
    ) {
        self.downloadFile(url, destinationPath, progress, completion)
    }
}
