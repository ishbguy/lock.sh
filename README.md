# [lock.sh](https://github.com/ishbguy/lock.sh)

A shell lock screen tool, which can be integrated with tmux.

![`lock.sh -e '$(date +%H:%M:%S | figlet)'`](screenshots/lock-date.png)

## Prerequisites

- `tput`
- `dialog`
- `shuf`
- `find`

## Features

- Lock with a simple login box and unlock with the user password
- Run with other cmd to lock the terminal
- Customized ascii art
- Slideshow mode
- Dynamic shell expansion
- Integrate with `tmux`

## Installation

### Basic

Clone the repo:

```
git clone https://github.com/ishbguy/lock.sh /path/to/lock.sh
```

### Integration with `tmux`

If using [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm), you need to add
the following to your list of TPM plugins in `.tmux.conf`:

```
set -g @plugin 'ishbguy/lock.sh'
```

Then hit <kbd>prefix</kbd>+<kbd>I</kbd> to fetch and source the plugin. You should now be able to use this plugin!

## How to use

See `lock.sh -h`:

```
lock.sh v1.1.0
lock.sh [-leAhvD] [-c cmd|-a name|-d dir|-t sec|-s sec|-S sec] [args...]
    
    [args..]        Show the args string on lock screen
    -c <cmd>        Run the [cmd] as the lock screen command
    -a <name>       Show the <name> ascii art on lock screen
    -d <dir>        Specify the ascii art director, work with -a option
    -e              Make shell expansion when lock screen
    -l              Need to login to unlock the screen
    -t <sec>        Specify <sec> seconds timer to invoke the login
    -s <sec>        Slideshow mode, slide every <sec> seconds
    -S <sec>        Shuffle slideshow mode, slide every <sec> seconds
    -AS <sec>       Shuffle slideshow with local ascii arts every <sec> seconds
    -h              Print this help message
    -v              Print version number
    -D              Turn on debug mode

For examples:

    lock.sh                         # Run without opts and args will show a login screen
    lock.sh "Hello world!"          # Show the 'Hello world!' string on lock screen
    lock.sh -c cmatrix              # Run cmatrix as lock screen
    lock.sh -l -c cmatrix           # Run cmatrix as lock screen and need to login to unlock
    lock.sh -l -t 10 cmatrix        # Run cmatrix then will invoke login if run over 10 seconds
    lock.sh -a zebra                # Show the 'zebra' ascii art on lock screen
    lock.sh -d art -a zebra         # Find 'zebra' ascii art in 'art' directory and
                                    # show it on the lock screen
    lock.sh -s 5 one two            # Slide every 5 seconds
    lock.sh -S 5                    # Shuffle every 5 seconds without args, it will try fortune
                                    # by default, or will invoke login screen
    lock.sh -S 5 one two three      # Shuffle every 5 seconds with args
    lock.sh -AS 5                   # Shuffle every 5 seconds with local ascii arts
    lock.sh -e '$(date +%H:%M)'     # Dynamic expansion the date output

Lock screen key bindings:

    j/J     Next lock screen
    k/K     Prev lock screen

This program is released under the terms of the MIT License.
```

## License

Released under the terms of [MIT](LICENSE) license.
