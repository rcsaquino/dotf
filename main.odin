package main

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// ============================================================================
// Core Types & Constants
// ============================================================================

// CommandKind represents the available CLI subcommands supported by dotf.
CommandKind :: enum {
	Add,    // Move a file to dotfiles and replace it with a symlink.
	Link,   // Restore/create symlinks for a program's dotfiles.
	Unlink, // Remove symlinks for a program's dotfiles.
	Delete, // Remove program symlinks and delete its files from dotfiles directory.
	List,   // List all dotfile programs and check if they are linked.
}

// parse_command_kind parses the first CLI argument string into a CommandKind enum.
parse_command_kind :: proc(s: string) -> (CommandKind, bool) {
	switch s {
	case "add":
		return .Add, true
	case "link":
		return .Link, true
	case "unlink":
		return .Unlink, true
	case "delete":
		return .Delete, true
	case "list":
		return .List, true
	}
	return .Add, false
}

// ConfigKey represents configuration items stored in config.txt.
ConfigKey :: enum {
	Dotfiles_Dir, // Key corresponding to the path of the dotfiles repository.
}

// config_key_to_string converts a ConfigKey enum into its string representation
// as it appears in config.txt (e.g., "dotfiles_dir").
config_key_to_string :: proc(key: ConfigKey) -> string {
	switch key {
	case .Dotfiles_Dir:
		return "dotfiles_dir"
	}
	return ""
}

// ============================================================================
// Global Cached State
// ============================================================================
// Caching paths and directories globally avoids redundant file parsing and
// environment variable lookup syscalls during execution. Since dotf is a
// short-lived CLI command, these values remain constant throughout the run.
g_home_dir: string
g_root_dir: string
g_config_path: string

// ============================================================================
// Main Execution Flow
// ============================================================================

main :: proc() {
	// Free all temporary allocations made on context.temp_allocator when main exits.
	defer free_all(context.temp_allocator)

	// Ensure a subcommand is provided.
	if len(os.args) < 2 {
		print_help()
		return
	}

	command, ok := parse_command_kind(os.args[1])
	if !ok {
		print_help()
		return
	}

	// Security/safety check: prohibit ".git" to prevent accidentally modifying git internals.
	for arg in os.args {
		if arg == ".git" {
			fmt.eprintln("Error: Invalid arg \".git\".")
			os.exit(1)
		}
	}

	// Dispatch commands based on user input.
	switch command {
	case .Add:
		if len(os.args) < 4 {
			fmt.println("Usage: add <program> <file_path>")
			return
		}
		add_dot(os.args[2], os.args[3])
	case .Link:
		if len(os.args) < 3 {
			fmt.println("Usage: link <program/s>")
			return
		}
		link_dots(os.args[2:])
	case .Unlink:
		if len(os.args) < 3 {
			fmt.println("Usage: unlink <program/s>")
			return
		}
		unlink_dots(os.args[2:])
	case .Delete:
		if len(os.args) < 3 {
			fmt.println("Usage: delete <program/s>")
			return
		}
		delete_dots(os.args[2:])
	case .List:
		list_dots()
	}
}

// ============================================================================
// Path & Configuration Helpers
// ============================================================================

// get_home_dir retrieves the HOME directory environment variable, caches it
// in g_home_dir, and returns it. Crashes if HOME is not set.
get_home_dir :: proc() -> string {
	if g_home_dir == "" {
		home, ok := os.lookup_env("HOME", context.allocator)
		if !ok {
			fmt.eprintln("Error: HOME environment variable is not set.")
			os.exit(1)
		}
		g_home_dir = home
	}
	return g_home_dir
}

// expand_tilde_to_home expands a leading "~/" or "~" in a path to the user's
// home directory. Returns strings cloned with the specified allocator.
expand_tilde_to_home :: proc(path: string, allocator := context.allocator) -> string {
	if path == "~" {
		return get_home_dir()
	}
	if strings.has_prefix(path, "~/") {
		home := get_home_dir()
		res, _ := filepath.join({home, path[2:]}, allocator)
		return res
	}
	return strings.clone(path, allocator)
}

// get_config_path resolves the absolute path of the dotf configuration file
// (usually ~/.config/dotf/config.txt) and caches it in g_config_path.
get_config_path :: proc() -> string {
	if g_config_path == "" {
		home := get_home_dir()
		res, _ := filepath.join({home, ".config", "dotf", "config.txt"}, context.allocator)
		g_config_path = res
	}
	return g_config_path
}

// read_config_lines checks for the configuration file, initializes it if it does
// not exist, reads its contents, and splits them into lines.
read_config_lines :: proc(allocator := context.allocator) -> []string {
	cfg_path := get_config_path()

	// Automatically create configuration path directory and file if missing.
	if !os.exists(cfg_path) {
		dir_path := os.dir(cfg_path)
		if !os.exists(dir_path) {
			err := os.make_directory_all(dir_path)
			if err != nil {
				fmt.eprintfln("Uncaught error: %v", err)
				os.exit(1)
			}
		}
		f, err_f := os.create(cfg_path)
		if err_f != nil {
			fmt.eprintfln("Uncaught error: %v", err_f)
			os.exit(1)
		}
		os.close(f)
	}

	data, err_read := os.read_entire_file(cfg_path, allocator)
	if err_read != nil {
		fmt.eprintfln("Uncaught error: %v", err_read)
		os.exit(1)
	}

	content := string(data)
	lines, err_split := strings.split_lines(content, allocator)
	if err_split != nil {
		fmt.eprintfln("Uncaught error: %v", err_split)
		os.exit(1)
	}
	return lines
}

// set_config_value updates or inserts a key-value setting in config.txt.
set_config_value :: proc(key: ConfigKey, value: string) {
	cfgs := read_config_lines(context.temp_allocator)
	key_str := config_key_to_string(key)

	new_cfgs := make([dynamic]string, context.temp_allocator)
	index := -1
	
	// Locate and update matching key by splitting strictly at '='.
	for cfg, i in cfgs {
		append(&new_cfgs, cfg)
		idx := strings.index_byte(cfg, '=')
		if idx != -1 {
			k := strings.trim_space(cfg[:idx])
			if k == key_str {
				index = i
			}
		}
	}

	new_val := fmt.tprintf("%s = %s", key_str, value)
	if index == -1 {
		append(&new_cfgs, new_val)
	} else {
		new_cfgs[index] = new_val
	}

	joined_content, _ := strings.join(new_cfgs[:], "\n", context.temp_allocator)
	cfg_path := get_config_path()

	err := os.write_entire_file(cfg_path, transmute([]byte)joined_content)
	if err != nil {
		fmt.eprintfln("Error: Unable to set %s to %s. (%v)", key_str, value, err)
		os.exit(1)
	}
}

// get_config_value retrieves the value of a key from config.txt.
// Strings are parsed safely by splitting lines exactly at the first '='.
get_config_value :: proc(key: ConfigKey, allocator := context.allocator) -> string {
	cfgs := read_config_lines(context.temp_allocator)
	key_str := config_key_to_string(key)
	for cfg in cfgs {
		idx := strings.index_byte(cfg, '=')
		if idx != -1 {
			k := strings.trim_space(cfg[:idx])
			v := strings.trim_space(cfg[idx+1:])
			if k == key_str {
				return strings.clone(v, allocator)
			}
		}
	}
	return ""
}

// read_line prints a prompt and scans a single line from stdin.
read_line :: proc(prompt: string) -> (string, bool) {
	fmt.print(prompt)

	scanner: bufio.Scanner
	stdin := os.to_stream(os.stdin)
	bufio.scanner_init(&scanner, stdin, context.allocator)
	defer bufio.scanner_destroy(&scanner)

	if bufio.scanner_scan(&scanner) {
		line := bufio.scanner_text(&scanner)
		cloned := strings.clone(line)
		return cloned, true
	}
	return "", false
}

// get_root_dir returns the resolved path of the dotfiles repository directory.
// If it is not configured, it prompts the user up to 5 times to configure it.
get_root_dir :: proc() -> string {
	if g_root_dir == "" {
		root_dir := get_config_value(.Dotfiles_Dir, context.allocator)
		attempts := 0
		for root_dir == "" {
			if attempts >= 5 {
				fmt.eprintln("Error: Attempt limit reached.")
				set_config_value(.Dotfiles_Dir, "")
				os.exit(1)
			}

			attempts += 1
			var_ok: bool
			root_dir, var_ok = read_line("Enter dotfiles path: ")
			if !var_ok {
				fmt.eprintln("Error: Failed to read from stdin.")
				os.exit(1)
			}

			expanded := expand_tilde_to_home(root_dir, context.temp_allocator)
			abs_path, abs_err := filepath.abs(expanded, context.allocator)
			if abs_err != nil {
				fmt.eprintfln("Error: Failed to get absolute path of %s (%v)", expanded, abs_err)
				root_dir = ""
				continue
			}
			root_dir = abs_path

			if !os.exists(root_dir) {
				fmt.eprintfln("Error: %s does not exist.", root_dir)
				root_dir = ""
				continue
			}

			home := get_home_dir()
			home_prefix := fmt.tprintf("%s/", home)
			if !strings.has_prefix(root_dir, home_prefix) {
				fmt.eprintfln("Error: %s is not in home directory.", root_dir)
				root_dir = ""
				continue
			}

			if attempts > 0 {
				set_config_value(.Dotfiles_Dir, root_dir)
			}
		}
		g_root_dir = root_dir
	}

	return g_root_dir
}

// print_help outputs usage instructions to standard output.
print_help :: proc() {
	print_txt :=
		("Commands:\n" +
			" add <program> <file_path>   - Move file to dotfiles and create symlink\n" +
			" link <program/s>            - Create symlinks for program dotfiles\n" +
			" unlink <program/s>          - Remove symlinks for program dotfiles\n" +
			" delete <program/s>          - Delete program dotfiles directory\n" +
			" list                        - List available program dotfiles\n")
	fmt.println(print_txt)
}

// is_link checks if the given file system path is a symlink.
is_link :: proc(path: string) -> bool {
	info, err := os.lstat(path, context.temp_allocator)
	if err != nil {
		return false
	}
	defer os.file_info_delete(info, context.temp_allocator)
	return info.type == .Symlink
}

// ============================================================================
// Command Implementation Procedures
// ============================================================================

// add_dot moves a program configuration file to the dotfiles repository and
// links it back to its original location under the home directory.
add_dot :: proc(dot_name: string, dot_path: string) {
	if strings.contains(dot_name, "..") || strings.contains(dot_name, "/") {
		fmt.eprintln("Error: Program name cannot contain path separators or \"..\".")
		os.exit(1)
	}

	home_dir := get_home_dir()
	root_dir := get_root_dir()
	src_path, _ := filepath.join({root_dir, dot_name}, context.temp_allocator)

	// Resolve the absolute path of the target file, expanding leading tilde if present.
	expanded_dot_path := expand_tilde_to_home(dot_path, context.temp_allocator)
	abs_dot_path, abs_err := filepath.abs(expanded_dot_path, context.temp_allocator)
	if abs_err != nil {
		fmt.eprintfln("Error: Failed to get absolute path of %s (%v)", dot_path, abs_err)
		os.exit(1)
	}

	// Verify the file lies inside the home directory for safety.
	home_prefix := fmt.tprintf("%s/", home_dir)
	if !strings.has_prefix(abs_dot_path, home_prefix) {
		fmt.eprintfln("Error: %s is not in the home directory.", abs_dot_path)
		os.exit(1)
	}

	if !os.exists(abs_dot_path) {
		fmt.eprintfln("Error: %s does not exist.", abs_dot_path)
		os.exit(1)
	}

	if is_link(abs_dot_path) {
		fmt.eprintfln("Error: %s is a link.", abs_dot_path)
		os.exit(1)
	}

	// Determine destination in the dotfiles repo preserving relative path under home.
	rel_path := abs_dot_path[len(home_dir) + 1:]
	target_path, _ := filepath.join({root_dir, dot_name, rel_path}, context.temp_allocator)
	base_path := os.dir(target_path)
	if !os.exists(base_path) {
		err := os.make_directory_all(base_path)
		if err != nil {
			fmt.eprintfln("Uncaught error: %v", err)
			os.exit(1)
		}
	}

	// Move file to repository.
	err_mv := os.rename(abs_dot_path, target_path)
	if err_mv != nil {
		fmt.eprintfln("Uncaught error: %v", err_mv)
		os.exit(1)
	}

	fmt.printfln("Created new dot file at %s", src_path)
	
	// Create symlink pointing from home to dotfiles repository.
	link_dots({dot_name})
}

// link_dots walks a program's dotfiles directory and creates matching symlinks
// under the home directory.
link_dots :: proc(dots: []string) {
	root_dir := get_root_dir()
	home_dir := get_home_dir()
	
	// created_dirs caches paths of directories created/verified to exist during
	// link operations, preventing redundant make_directory_all calls on parent folders.
	created_dirs := make(map[string]bool, context.temp_allocator)

	for dot in dots {
		src_path, _ := filepath.join({root_dir, dot}, context.temp_allocator)
		if !os.exists(src_path) {
			fmt.eprintfln("Error: %s not found in dotfiles.", dot)
			continue
		}

		walker := filepath.walker_create(src_path)
		defer filepath.walker_destroy(&walker)

		// Recursively walk program files.
		for fi in filepath.walker_walk(&walker) {
			if fi.type == .Directory {
				continue
			}

			fp := fi.fullpath
			rel_path := fp[len(src_path) + 1:]
			target_path, _ := filepath.join({home_dir, rel_path}, context.temp_allocator)

			// Ensure target directory exists before linking.
			target_dir := os.dir(target_path)
			if !created_dirs[target_dir] {
				if !os.exists(target_dir) {
					mkdir_err := os.make_directory_all(target_dir)
					if mkdir_err != nil {
						fmt.eprintfln("Uncaught error: %v", mkdir_err)
						continue
					}
				}
				created_dirs[target_dir] = true
			}

			if os.exists(target_path) {
				fmt.eprintfln("Error: %s already exists.", target_path)
				continue
			}

			// Create the symlink.
			sym_err := os.symlink(fp, target_path)
			if sym_err != nil {
				fmt.eprintfln("Uncaught error: %v", sym_err)
				continue
			}
			fmt.printfln("Linked: %s", rel_path)
		}
	}
}

// unlink_dots walks a program's files in the dotfiles repo, identifies symlinks
// under the home directory, removes them, and cleans up empty parent directories.
unlink_dots :: proc(dots: []string) {
	root_dir := get_root_dir()
	home_dir := get_home_dir()
	
	// Track directories containing unlinked files so we can clean them up recursively.
	dirs_to_remove := make(map[string]bool, context.temp_allocator)

	for dot in dots {
		src_path, _ := filepath.join({root_dir, dot}, context.temp_allocator)

		if !os.exists(src_path) {
			fmt.eprintfln("Error: %s does not exist.", src_path)
			continue
		}

		walker := filepath.walker_create(src_path)
		defer filepath.walker_destroy(&walker)

		for fi in filepath.walker_walk(&walker) {
			if fi.type == .Directory {
				continue
			}

			fp := fi.fullpath
			rel_path := fp[len(src_path) + 1:]
			target_path, _ := filepath.join({home_dir, rel_path}, context.temp_allocator)

			info, stat_err := os.lstat(target_path, context.temp_allocator)
			if stat_err != nil {
				fmt.eprintfln("Error: %s does not exist.", target_path)
				continue
			}
			is_symlink := info.type == .Symlink
			os.file_info_delete(info, context.temp_allocator)

			if !is_symlink {
				fmt.eprintfln("Error: %s is not a link.", target_path)
				continue
			}

			// Delete the symlink.
			rm_err := os.remove(target_path)
			if rm_err != nil {
				fmt.eprintfln("Uncaught error: %v", rm_err)
				continue
			}
			fmt.printfln("Unlinked: %s", rel_path)

			// Record target folder to clean up.
			dirs_to_remove[os.dir(target_path)] = true
		}
	}

	// Batch cleanup of directories: Sort directories by path length descending (longest/deepest first).
	// This ensures we try to remove nested folders before trying to remove their parent folders,
	// allowing clean, recursive removal of empty directory trees with a single pass.
	dirs_slice := make([dynamic]string, context.temp_allocator)
	for dir in dirs_to_remove {
		append(&dirs_slice, dir)
	}
	slice.sort_by(dirs_slice[:], proc(i, j: string) -> bool {
		return len(i) > len(j)
	})
	for dir in dirs_slice {
		os.remove(dir) // os.remove only deletes empty directories, so non-empty ones are safely skipped.
	}
}

// delete_dots unlinks symlinks for the specified program(s) and recursively deletes
// their storage directory under the dotfiles repository.
delete_dots :: proc(dots: []string) {
	root_dir := get_root_dir()
	for dot in dots {
		src_path, _ := filepath.join({root_dir, dot}, context.temp_allocator)

		if !os.exists(src_path) {
			fmt.eprintfln("Error: %s does not exist.", src_path)
			continue
		}

		unlink_dots({dot})

		// Remove the files from the dotfiles repository.
		err := os.remove_all(src_path)
		if err != nil {
			fmt.eprintfln("Uncaught error: %v", err)
			continue
		}
		fmt.printfln("Removed: %s", src_path)
	}
}

// list_dots lists all programs in the dotfiles repo, divided into "Linked" (all
// files have valid links in the home directory) and "Unlinked" (at least one file
// is missing its symlink).
list_dots :: proc() {
	root_dir := get_root_dir()
	home_dir := get_home_dir()
	dots := make(map[string]bool, context.temp_allocator)

	entries, err := os.read_directory_by_path(root_dir, -1, context.temp_allocator)
	if err != nil {
		fmt.eprintfln("Uncaught error: %v", err)
		os.exit(1)
	}

	// Check each program directory.
	for entry in entries {
		if entry.name == ".git" {
			continue
		}
		src_path, _ := filepath.join({root_dir, entry.name}, context.temp_allocator)
		dots[entry.name] = true

		walker := filepath.walker_create(src_path)
		defer filepath.walker_destroy(&walker)

		for fi in filepath.walker_walk(&walker) {
			if fi.type == .Directory {
				continue
			}

			fp := fi.fullpath
			rel_path := fp[len(src_path) + 1:]
			target_path, _ := filepath.join({home_dir, rel_path}, context.temp_allocator)

			// Walk-break optimization: if even one file in a program is not linked,
			// the program is marked unlinked (false) and we immediately stop walking it.
			if !is_link(target_path) {
				dots[entry.name] = false
				break
			}
		}
	}

	// Separate into linked/unlinked lists.
	linked := make([dynamic]string, context.temp_allocator)
	unlinked := make([dynamic]string, context.temp_allocator)

	for dot_name, is_linked in dots {
		if is_linked {
			append(&linked, dot_name)
		} else {
			append(&unlinked, dot_name)
		}
	}

	// Sort alphabetically for clean, deterministic CLI output.
	slice.sort(linked[:])
	slice.sort(unlinked[:])

	// Format output efficiently using a strings.Builder.
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)

	if len(linked) > 0 {
		strings.write_string(&builder, "================\n=    Linked    =\n================\n")
		for name in linked {
			strings.write_string(&builder, name)
			strings.write_byte(&builder, '\n')
		}
	}

	if len(linked) > 0 && len(unlinked) > 0 {
		strings.write_byte(&builder, '\n')
	}

	if len(unlinked) > 0 {
		strings.write_string(&builder, "================\n=   Unlinked   =\n================\n")
		for name in unlinked {
			strings.write_string(&builder, name)
			strings.write_byte(&builder, '\n')
		}
	}

	fmt.print(strings.to_string(builder))
}
