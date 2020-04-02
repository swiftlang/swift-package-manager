# author: Arthur Liu
# GitHub: https://www.github.com/archmagees


##############################
# swift --version
complete -c swift -n '__swift_commands_conforms swift' -f -l version -d 'Print version information and exit' -f

# swift --help
complete -c swift -n '__swift_commands_conforms swift --help --version' -f -l help -d 'Display available options' -f

# swift subcommand --path `|` , where cursor blink and last option needs an path as its argument
complete -c swift -n '__swift_options_argument_is_path' -f


############################################################
### swift package
############################################################
complete -c swift -n '__swift_commands_conforms swift' -f -a package -r
complete -c swift -n '__swift_commands_conforms swift package' -a clean -d 'Delete build artifacts'
complete -c swift -n '__swift_commands_conforms swift package clean' -f
complete -c swift -n '__swift_commands_conforms swift package' -f -a completion-tool -d 'Completion tool (for shell completions)' -r
complete -c swift -n '__swift_commands_conforms swift package' -f -a config -d 'Manipulate configuration of the package' -r
complete -c swift -n '__swift_commands_conforms swift package' -f -a describe -d 'Describe the current package' -r
complete -c swift -n '__swift_commands_conforms swift package' -f -a dump-package -d 'Print parsed Package.swift as JSON' -f
complete -c swift -n '__swift_commands_conforms swift package' -f -a edit -d 'Put a package in editable mode' -f
complete -c swift -n '__swift_commands_conforms swift package' -f -a generate-xcodeproj -d 'Generates an Xcode project' -f
complete -c swift -n '__swift_commands_conforms swift package' -f -a init -d 'Initialize a new package' -f
complete -c swift -n '__swift_commands_conforms swift package' -f -a reset -d 'Reset the complete cache/build directory' -f
complete -c swift -n '__swift_commands_conforms swift package' -f -a resolve -d 'Resolve package dependencies' -f
complete -c swift -n '__swift_commands_conforms swift package' -f -a show-dependencies -d 'Print the resolved dependency graph' -f
complete -c swift -n '__swift_commands_conforms swift package' -f -a tools-version -d 'Manipulate tools version of the current package' -f
complete -c swift -n '__swift_commands_conforms swift package' -f -a unedit -d 'Remove a package from editable mode' -f
complete -c swift -n '__swift_commands_conforms swift package' -f -a update -d 'Update package dependencies' -f




############################################################
### swift subcommand [option]
############################################################
function __swift_commands_conforms
	set possible_cmds
	set options

	set all_cmds (commandline -opc)

	for word in $all_cmds
		if not string match -q -- '-*' $word
			set -a possible_cmds $word
		else
			set -a options $word
		end
	end

	# failsafe, the last input is an option which needs an argument, like:
	# `swift package --configuration|` now cursor stop at the end of input.
	if __swift_check_is_an_option_that_needs_argument $all_cmds[-1]
		return 1
	end

	set required_commands
	set exclusive_options

	for word in $argv
		if not string match -q -- '-*' $word
			set required_commands $required_commands $word
		else
			set exclusive_options $exclusive_options $word
		end
	end

	# almost help and version are exclusive with other options
	set exclusive_options $exclusive_options --help --version

	# exclude exclusiion options in advance
	for option in $exclusive_options
		if contains -- $option $options
			return 1
		end
	end

	set cmds_count (count $possible_cmds)

	for word in $options
		if __swift_check_is_an_option_that_needs_argument $word
				set cmds_count (math $cmds_count - 1)
		end
	end

	if [ $cmds_count -ne (count $required_commands) ]
		return 1
	end

	set counter 1
	for i in (seq 1 (count $possible_cmds))
		if [ (count $required_commands) -ge $counter ]
			if [ $possible_cmds[$i] = $required_commands[$counter] ]
				set counter (math $counter + 1)
			else if [ $required_commands[$counter] = subcommand ]
				switch $possible_cmds[$i]
					case 'package' 'build' 'run' 'test'
						set counter (math $counter + 1)
				end
			end
		end
	end

	if [ (count $required_commands) -ne (math $counter - 1) ]
		return 1
	end




	return 0
end

function __swift_options_conforms
	set possible_cmds
	set options

	set all_cmds (commandline -opc)

	for word in $all_cmds
		if not string match -q -- '-*' $word
			set -a possible_cmds $word
		else
			set -a options $word
		end
	end

	set required_commands
	set exclusive_options

	for word in $argv
		if not string match -q -- '-*' $word
			set required_commands $required_commands $word
		else
			set exclusive_options $exclusive_options $word
		end
	end



	set cmds_count (count $possible_cmds)

	for word in $options
		if __swift_check_is_an_option_that_needs_argument $word
				set cmds_count (math $cmds_count - 1)
		end
	end

	# failsafe, because the previous step could execute minus one more time if
	# the last input is an option which needs argument
	if [ $all_cmds[-1] = $argv[-1] ]
		set cmds_count (math $cmds_count + 1)
	end

	if [ $cmds_count -ne (count $required_commands) ]
		return 1
	end

	set counter 1
	for i in (seq 1 (count $possible_cmds))
		if [ (count $required_commands) -ge $counter ]
			if [ $possible_cmds[$i] = $required_commands[$counter] ]
				set counter (math $counter + 1)
			# else if [ $required_commands[$counter] = subcommand ]
			# 	switch $possible_cmds[$i]
			# 		case 'package' 'build' 'run' 'test'
			# 			set counter (math $counter + 1)
			# 	end
			end
		end
	end

	if [ (count $required_commands) -ne (math $counter - 1) ]
		return 1
	end

	if [ $all_cmds[-1] = $argv[-1] ]
		return 0
	end

	return 1
end



function __swift_options_argument_is_path
	set inputs (commandline -opc)
	switch $inputs[-1]
	case '--build-path' '--package-path' '--path' '--output'
		return 1
	end
	return 0
end



function _format_is_swift_subcommand_option
	__swift_commands_conforms swift subcommand $argv
	return $status
end



function __swift_package_editable_option
	# swift package edit or unedit `Package` --options
	set inputs (commandline -opc)
	if __swift_commands_conforms $argv[1..-2] $inputs[-1] $argv[-1]
		if contains $inputs[-1] (_swift_package_dependencies)
			return 0
		end
	end
	return 1
end



function __swift_package_dependencies
	swift package show-dependencies --format flatlist
end



function __swift_targets
	swift package describe --type text | grep ' Name:' | string sub -s 11
end



function __swift_products
	swift package describe --type text
end



function __swift_check_is_an_option_that_needs_argument

	switch $argv
	case '--build-path' '--configuration' '--jobs' '--package-path' '--package-url' '--path' '--branch' '--output' '--type' '--name' '--num-workers' '--target' '--set' '--format'
		return 0
	end
	return 1
end

############################################################
### swift package
############################################################

############################################################
### swift subcommand [options] argument subcommand
############################################################
# could optimize it later to support use option without `=` as suffix and
# supply tab completion for argument which will not effect following
# subcommand
complete -c swift -n '_format_is_swift_subcommand_option --build-path' -f -l build-path -d 'Specify build/cache directory [default: ./.build]'

complete -c swift -n '_format_is_swift_subcommand_option --configuration' -f -l configuration -d 'Build with configuration (debug|release) [default: debug]'
complete -c swift -n '__swift_options_conforms swift package --configuration' -f -a 'debug release' -r

complete -c swift -n '_format_is_swift_subcommand_option --jobs' -f -s j -l jobs -d 'The number of jobs to spawn in parallel during the build process' -r

complete -c swift -n '__swift_options_conforms swift package --jobs' -f -a '1 2 3 4 8 16 28'

complete -c swift -n '_format_is_swift_subcommand_option --package-path' -f -l package-path -d 'Change working directory before any other operation' -r

############################################################
### swift package [options] subcommand
############################################################
# template
# complete -c swift -n '_format_is_swift_subcommand_option --' -f -l  -d '' -r
complete -c swift -n '_format_is_swift_subcommand_option --disable-automatic-resolution' -f -l disable-automatic-resolution -d 'Disable automatic resolution if Package.resolved file is out-of-date' -r
complete -c swift -n '_format_is_swift_subcommand_option --disable-index-store' -f -l disable-index-store -d 'Disable indexing-while-building feature' -r

complete -c swift -n '_format_is_swift_subcommand_option --disable-package-manifest-caching' -f -l disable-package-manifest-caching -d 'Disable caching Package.swift manifests' -r

complete -c swift -n '_format_is_swift_subcommand_option --disable-prefetching' -f -l disable-prefetching -d '' -r

complete -c swift -n '_format_is_swift_subcommand_option --disable-sandbox' -f -l disable-sandbox -d 'Disable using the sandbox when executing subprocesses' -r

complete -c swift -n '_format_is_swift_subcommand_option --enable-index-store' -f -l enable-index-store -d 'Enable indexing-while-building feature' -r

complete -c swift -n '_format_is_swift_subcommand_option --enable-pubgrub-resolver' -f -l enable-pubgrub-resolver -d '[Experimental] Enable the new Pubgrub dependency resolver' -r

complete -c swift -n '_format_is_swift_subcommand_option --enable-test-discovery' -f -l enable-test-discovery -d 'Enable test discovery on platforms without Objective-C runtime' -r

complete -c swift -n '_format_is_swift_subcommand_option --no-static-swift-stdlib' -f -l no-static-swift-stdlib -d 'Do not link Swift stdlib statically [default]' -r

complete -c swift -n '_format_is_swift_subcommand_option --sanitize' -f -l sanitize -d 'Turn on runtime checks for erroneous behavior' -r

complete -c swift -n '_format_is_swift_subcommand_option --skip-update' -f -l skip-update -d 'Skip updating dependencies from their remote during a resolution' -r

complete -c swift -n '_format_is_swift_subcommand_option --static-swift-stdlib' -f -l static-swift-stdlib -d 'Link Swift stdlib statically' -r

complete -c swift -n '_format_is_swift_subcommand_option --verbose -v' -f -s v -l verbose -d 'Increase verbosity of informational output' -r

complete -c swift -n '_format_is_swift_subcommand_option -Xcc' -f -o Xcc -d 'Pass flag through to all C compiler invocations' -r

complete -c swift -n '_format_is_swift_subcommand_option -Xcxx' -f -o Xcxx -d 'Pass flag through to all C++ compiler invocations' -r

complete -c swift -n '_format_is_swift_subcommand_option -Xlinker' -f -o Xlinker -d 'Pass flag through to all linker invocations' -r

complete -c swift -n '_format_is_swift_subcommand_option -Xswiftc' -f -o Xswiftc -d 'Pass flag through to all Swift compiler invocations' -r


############################################################
### swift package completion-tool
############################################################
complete -c swift -n '__swift_commands_conforms swift package completion-tool' -r -a 'generate-bash-script generate-zsh-script list-dependencies list-executables' -f

############################################################
### swift package config
############################################################
complete -c swift -n '__swift_commands_conforms swift package config' -r -a 'get-mirror' -d 'Print mirror configuration for the given package dependency' -f
complete -c swift -n '__swift_commands_conforms swift package config' -r -a 'set-mirror' -d 'Set a mirror for a dependency' -f
complete -c swift -n '__swift_commands_conforms swift package config' -r -a 'unset-mirror' -d 'Remove an existing mirror' -f

complete -c swift -n '__swift_commands_conforms swift package config get-mirror --package-url' -f -l package-url -d 'The package dependency url' -r

complete -c swift -n '__swift_commands_conforms swift package config set-mirror --mirror-url' -f -l mirror-url= -d 'The mirror url' -r
complete -c swift -n '__swift_commands_conforms swift package config set-mirror --package-url' -f -l package-url -d 'The package dependency url' -r

complete -c swift -n '__swift_commands_conforms swift package config unset-mirror --mirror-url' -f -l mirror-url= -d 'The mirror url' -r
complete -c swift -n '__swift_commands_conforms swift package config unset-mirror --package-url' -f -l package-url -d 'The package dependency url' -r



############################################################
### swift package describe
############################################################
complete -c swift -n '__swift_commands_conforms swift package describe --type' -f -l type -d 'json|text' -r
complete -c swift -n '__swift_options_conforms swift package describe --type' -f -a 'json text' -r



############################################################
### swift package edit
############################################################


complete -c swift -n '__swift_commands_conforms swift package edit' -r -a '(_swift_package_dependencies)' -r
complete -c swift -n '__swift_package_editable_option swift package edit --branch' -f -l branch -d 'The branch to create' -r
complete -c swift -n '__swift_package_editable_option swift package edit --path' -f -l path -d 'Create or use the checkout at this path' -r
complete -c swift -n '__swift_package_editable_option swift package edit --revision' -f -l revision -d 'The revision to edit' -r


############################################################
### swift package generate-xcodeproj
############################################################
complete -c swift -n '__swift_commands_conforms swift package generate-xcodeproj --enable-code-coverage' -f -l enable-code-coverage -d 'Enable code coverage in the generated project' -f
complete -c swift -n '__swift_commands_conforms swift package generate-xcodeproj --legacy-scheme-generator' -f -l legacy-scheme-generator -d 'Use the legacy scheme generator' -f
complete -c swift -n '__swift_commands_conforms swift package generate-xcodeproj --output' -l output -d 'Path where the Xcode project should be generated' -r

complete -c swift -n '__swift_commands_conforms swift package generate-xcodeproj --skip-extra-files' -l skip-extra-files -d 'Do not add file references for extra files to the generated Xcode project' -f
complete -c swift -n '__swift_commands_conforms swift package generate-xcodeproj --watch' -f -l watch -d 'Watch for changes to the Package manifest to regenerate the Xcode project' -f
complete -c swift -n '__swift_commands_conforms swift package generate-xcodeproj --xcconfig-overrides' -f -l xcconfig-overrides -d 'Path to xcconfig file' -r



############################################################
### swift package init
############################################################
complete -c swift -n '__swift_commands_conforms swift package init --name' -f -l name -d 'Provide custom package name' -r
complete -c swift -n '__swift_commands_conforms swift package init --type' -f -l type -d 'empty|library|executable|system-module|manifest' -r
complete -c swift -n '__swift_options_conforms swift package init --type' -f -a 'empty library executable system-module manifest' -r



############################################################
### swift package show-dependencies
############################################################
complete -c swift -n '__swift_commands_conforms swift package show-dependencies --format' -f -l format -d 'text|dot|json|flatlist' -r
complete -c swift -n '__swift_options_conforms swift package show-dependencies --format' -f -a 'text dot json flatlist' -f



############################################################
### swift package tools-version
############################################################
complete -c swift -n '__swift_commands_conforms swift package tools-version --set --set-current' -f -l set -d 'Set tools version of package to the given value' -r
complete -c swift -n '__swift_options_conforms swift package tools-version --set' -f -a '5.1 5.0 4.2 4.1'
complete -c swift -n '__swift_commands_conforms swift package tools-version --set-current --set' -f -l set-current -d 'Set tools version of package to the current tools version in use' -f



############################################################
### swift package unedit
############################################################
complete -c swift -n '__swift_commands_conforms swift package unedit' -r -a '(_swift_package_dependencies)' -r
complete -c swift -n '__swift_package_editable_option swift package unedit --force' -f -l force -d 'Unedit the package even if it has uncommited and unpushed changes.' -r





############################################################
### swift build
############################################################
complete -c swift -n '__swift_commands_conforms swift' -f -a build -r

### swift build [option]
# has been implemented in function `_format_is_swift_subcommand_option`
complete -c swift -n '__swift_commands_conforms swift build --build-tests' -f -l build-tests -d 'Build both source and test targets' -r
complete -c swift -n '__swift_commands_conforms swift build --product' -f -l product -d 'Build the specified product' -r
# complete -c swift -n '__swift_options_conforms swift build --product' -a '(__swift_products)'
complete -c swift -n '__swift_commands_conforms swift build --show-bin-path' -f -l show-bin-path -d 'Print the binary output path' -r
complete -c swift -n '__swift_commands_conforms swift build --target' -f -l target -d 'Build the specified target' -r
complete -c swift -n '__swift_options_conforms swift build --target' -f -a '(_swift_targets)'





############################################################
### swift run
############################################################
complete -c swift -n '__swift_commands_conforms swift' -f -a run -r


############################################################
### swift run [options] [executable [arguments ...]]
############################################################
# --build-tests is in both build and run
complete -c swift -n '__swift_commands_conforms swift run --build-tests' -f -l build-tests -d 'Build both source and test targets' -r

# unique options for swift run
complete -c swift -n '__swift_commands_conforms swift run --repl' -f -l repl -d 'Launch Swift REPL for the package' -r
complete -c swift -n '__swift_commands_conforms swift run --skip-build' -f -l skip-build -d 'Skip building the executable product' -r





############################################################
### swift test [options]
############################################################
complete -c swift -n '__swift_commands_conforms swift' -f -a 'test' -r

complete -c swift -n '__swift_commands_conforms swift test --enable-code-coverage' -l enable-code-coverage -d 'Test with code coverage enabled'
complete -c swift -n '__swift_commands_conforms swift test --filter' -l filter -d 'Run test cases matching regular expression, Format: <test-target>.<test-case> or <test-target>.<test-case>/<test>'
complete -c swift -n '__swift_options_conforms swift test --filter' -a 'REGEX' -d 'Format: <test-target>.<test-case> or <test-target>.<test-case>/<test>'
complete -c swift -n '__swift_commands_conforms swift test --generate-linuxmain' -l generate-linuxmain -d 'Generate LinuxMain.swift entries for the package'
complete -c swift -n '__swift_commands_conforms swift test --list-tests -l' -s l -l list-tests -d 'Lists test methods in specifier format'
complete -c swift -n '__swift_commands_conforms swift test --num-workers' -l num-workers -d 'Number of tests to execute in parallel.'
complete -c swift -n '__swift_options_conforms swift test --num-workers' -a '1 2 3 4 8 16 28 orAnyInt'
# must use in pair with `--num-workers`
complete -c swift -n '__swift_commands_conforms swift test --parallel' -l parallel -d 'Run the tests in parallel.'
complete -c swift -n '__swift_commands_conforms swift test --skip-build' -l skip-build -d 'Skip building the test target'
