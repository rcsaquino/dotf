# dotf

A simple, lightweight, and high-performance dotfiles manager written in the [Odin programming language](https://odin-lang.org/).

`dotf` keeps your configurations safe, organized, and easily shareable by centralizing them in a single dotfiles repository and symlinking them back to their expected locations in your home directory.

## Features

- **Blazing Fast**: Optimized to minimize environment lookups, file reads, and syscalls.
- **Memory Efficient**: Leverages Odin's temporary arena allocator for low overhead and fast cleanup.
- **Safe & Robust**: Performs path validation checks, strictly parses configuration lines, and cleanly removes empty directories recursively on unlink.
- **Deterministic**: Lists programs alphabetically and formatted cleanly.

---

## Build & Install

### Prerequisites

You need the [Odin compiler](https://odin-lang.org/docs/install/) installed on your system.

### Compiling from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/rcsaquino/dotf.git
   cd dotf
   ```

2. Compile the project:
   - **For development/debug build**:
     ```bash
     odin build . -out:dotf
     ```
   - **For optimized release build**:
     ```bash
     odin build . -out:dotf -o:speed
     ```

3. (Optional) Copy `dotf` to a location in your `PATH` (e.g. `/usr/local/bin/` or `~/.local/bin/`):
   ```bash
   cp dotf ~/.local/bin/
   ```

---

## Usage

On the first run, `dotf` will prompt you to specify the directory path of your dotfiles repository (e.g., `~/dotfiles`).

### Commands

| Command | Description | Usage Example |
| :--- | :--- | :--- |
| **`add`** | Moves a file/folder to your dotfiles repo and replaces it with a symlink. | `dotf add nvim ~/.config/nvim/init.lua` |
| **`link`** | Creates symlinks under home directory for programs in your dotfiles repository. | `dotf link nvim zsh` |
| **`unlink`** | Safely removes symlinks for specific programs and cleans up empty parent directories. | `dotf unlink nvim zsh` |
| **`delete`** | Unlinks and completely deletes the program from the dotfiles repository. | `dotf delete nvim zsh` |
| **`list`** | Lists all linked and unlinked programs in alphabetical order. | `dotf list` |

---

## Configuration

Your dotfiles path is stored in the plain text configuration file located at:
`~/.config/dotf/config.txt`

The file format is simple:
```ini
dotfiles_dir = /path/to/your/dotfiles
```

---

## Contact

For questions or suggestions, feel free to contact:
- Email: `rcsaquino.md@gmail.com`

## Support

<a href='https://ko-fi.com/rcsaquino' target='_blank'><img height='72' style='border:0px;height:72px;' src='https://storage.ko-fi.com/cdn/kofi2.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
