# lock.sh

A terminal lock screen tool written in shell, which integrates with tmux as a plugin.

## Prerequisites

- tput
- dialog

## Features

- Lock with a simple login box and unlock with the user password
- Run with other cmd to lock the terminal
- Customized ascii art
- Slideshow mode
- Dynamic shell expansion

## Installation

### Basic

Clone the repo:

```
git clone https://github.com/ishbguy/lock.sh /path/to/lock.sh
```

### Integration with tmux

If using [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm), you need to add
the following to your list of TPM plugins in `.tmux.conf`:

```
set -g @plugin 'ishbguy/tmux-lock'
```

Then hit <kbd>prefix</kbd>+<kbd>I</kbd> to fetch and source the plugin. You should now be able to use this plugin!

## License

Released under the terms of [MIT](LICENSE) license.
