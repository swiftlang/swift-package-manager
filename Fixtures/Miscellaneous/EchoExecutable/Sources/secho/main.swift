let arguments = Array(CommandLine.arguments.dropFirst())
print(arguments.map({ "\"\($0)\"" }).joined(separator: " "))