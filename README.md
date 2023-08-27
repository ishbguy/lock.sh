# Tmux Lock

Tmux plugin for a lock screen

## Installation

### Using [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm)

Add the following to your list of TPM plugins in `.tmux.conf`:

```
set -g @plugin 'ishbguy/tmux-lock'
```

Hit <kbd>prefix</kbd>+<kbd>I</kbd> to fetch and source the plugin. You should now be able to use this plugin!

### Manual

Clone the repo:

```
git clone https://github.com/ishbguy/tmux-lock .tmux/plugins/tmux-lock
```

Source in your `.tmux.conf`:

```
run-shell ~/.tmux/plugins/tmux-lock/lock.tmux
```

Reload tmux conf by running:

```
tmux source-file ~/.tmux.conf
```

## Configuration

...

## License

Released under the terms of [MIT](LICENSE) license.
