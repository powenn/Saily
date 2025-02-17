// Copyright (c) 2021 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import SWCompression
import SwiftCLI

class SevenZipCommand: ContainerCommand {
    typealias ContainerType = SevenZipContainer

    let name = "7z"
    let shortDescription = "Extracts a 7-Zip container"

    @Flag("-i", "--info", description: "Print the list of entries in a container and their attributes")
    var info: Bool

    @Key("-e", "--extract", description: "Extract a container into the specified directory")
    var extract: String?

    @Flag("-v", "--verbose", description: "Print the list of extracted files and directories.")
    var verbose: Bool

    @Param var input: String

    var optionGroups: [OptionGroup] {
        [.exactlyOne($info, $extract)]
    }
}
