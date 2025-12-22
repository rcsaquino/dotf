# dotf

A simple, lightweight dotfiles manager written in V.

## Build & Install

You need the [V compiler](https://vlang.io/) installed.

```bash
git clone https://github.com/rcsaquino/dotf
cd dotf
v -prod -prealloc -gc none .
```

## Usage

On the first run, `dotf` will ask for the location of your dotfiles directory (e.g., `~/dotfiles`).

### Commands

| Command | Description | Usage Example |
| :--- | :--- | :--- |
| **add** | Moves a file to your dotfiles repo and creates a symlink. | `dotf add nvim ~/.config/nvim/init.lua` |
| **link** | Creates symlinks for programs in your dotfiles. | `dotf link nvim zsh` |
| **unlink** | Removes symlinks for specific programs. | `dotf unlink nvim zsh` |
| **delete** | Unlinks and deletes the program from the dotfiles directory. | `dotf delete nvim zsh` |
| **list** | Lists all linked and unlinked programs. | `dotf list` |

## Configuration

The configuration file (storing your dotfiles path) is located at:
`~/.config/dotf/config.txt`

## Contact

You may contact me at `rcsaquino.md@gmail.com`.

## Support

<a href='https://ko-fi.com/rcsaquino' target='_blank'><img height='72' style='border:0px;height:72px;' src='https://storage.ko-fi.com/cdn/kofi2.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
