# Using shell completion scripts

Customize your shell to automatically complete swift package commands.

## Overview

Package manager ships with completion scripts for Bash, Zsh, and Fish.
Generate completion lists for your shell in order to use it.

### Bash

Use the following commands to install the Bash completions to `~/.swift-package-complete.bash` and automatically load them using your `~/.bash_profile` file.

```bash
swift package completion-tool generate-bash-script > ~/.swift-package-complete.bash
echo -e "source ~/.swift-package-complete.bash\n" >> ~/.bash_profile
source ~/.swift-package-complete.bash
```

Alternatively, add the following commands to your `~/.bash_profile` file to directly load completions:

```bash
# Source Swift completion
if [ -n "`which swift`" ]; then
    eval "`swift package completion-tool generate-bash-script`"
fi
```

### Zsh

Use the following commands to install the Zsh completions to `~/.zsh/_swift`.
You can chose a different folder, but the filename should be `_swift`.
This will also add `~/.zsh` to your `$fpath` using your `~/.zshrc` file.

```bash
mkdir ~/.zsh
swift package completion-tool generate-zsh-script > ~/.zsh/_swift
echo -e "fpath=(~/.zsh \$fpath)\n" >> ~/.zshrc
compinit
```
