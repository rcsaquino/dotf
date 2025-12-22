import os
import readline

enum CommandKind {
	add
	link
	unlink
	delete
	list
}

enum ConfigKey {
	dotfiles_dir
}

fn main() {
	if os.args.len < 2 {
		print_help()
		return
	}

	command := CommandKind.from(os.args[1]) or {
		print_help()
		return
	}

	for arg in os.args {
		if arg == '.git' {
			eprintln('Error: Invalid arg ".git".')
			exit(1)
		}
	}

	match command {
		.add {
			if os.args.len < 4 {
				println('Usage: add <program> <file_path>')
				return
			}
			add_dot(os.args[2], os.args[3])
		}
		.link {
			if os.args.len < 3 {
				println('Usage: link <program/s>')
				return
			}
			link_dots(os.args[2..])
		}
		.unlink {
			if os.args.len < 3 {
				println('Usage: unlink <program/s>')
				return
			}
			unlink_dots(os.args[2..])
		}
		.delete {
			if os.args.len < 3 {
				println('Usage: delete <program/s>')
				return
			}
			delete_dots(os.args[2..])
		}
		.list {
			list_dots()
		}
	}
}

fn get_root_dir() string {
	mut root_dir := get_config_value(ConfigKey.dotfiles_dir)
	mut attempts := 0
	for root_dir == '' {
		if attempts >= 5 {
			eprintln('Error: Attempt limit reached.')
			set_config_value(ConfigKey.dotfiles_dir, '')
			exit(1)
		}

		if root_dir == '' {
			attempts++
			root_dir = readline.read_line('Enter dotfiles path: ') or {
				eprintln('Uncaught error: ${err}')
				exit(1)
			}
		}

		root_dir = os.abs_path(os.expand_tilde_to_home(root_dir))
		if !os.exists(root_dir) {
			eprintln('Error: ${root_dir} does not exist.')
			root_dir = ''
			continue
		}

		home := os.home_dir()
		if !root_dir.starts_with(home + os.path_separator) {
			eprintln('Error: ${root_dir} is not in home directory.')
			root_dir = ''
			continue
		}

		if attempts > 0 {
			set_config_value(ConfigKey.dotfiles_dir, root_dir)
		}
	}

	return root_dir
}

fn get_config_path() string {
	return os.join_path(os.home_dir(), '.config', 'dotf', 'config.txt')
}

fn read_config_lines() []string {
	cfg_path := get_config_path()

	if !os.exists(cfg_path) {
		os.mkdir_all(os.dir(cfg_path)) or {
			eprintln('Uncaught error ${err}')
			exit(1)
		}
		mut f := os.create(cfg_path) or {
			eprintln('Uncaught error ${err}')
			exit(1)
		}
		f.close()
	}

	return os.read_lines(cfg_path) or {
		eprintln('Uncaught error ${err}')
		exit(1)
	}
}

fn set_config_value(key ConfigKey, value string) {
	mut cfgs := read_config_lines()
	mut index := -1
	for i, cfg in cfgs {
		if cfg.starts_with(key.str()) {
			index = i
			break
		}
	}
	if index == -1 {
		cfgs << '${key} = ${value}'
	} else {
		cfgs[index] = '${key} = ${value}'
	}

	os.write_lines(get_config_path(), cfgs) or {
		eprintln('Error: Unable to set ${key} to ${value}.')
		exit(1)
	}
}

fn get_config_value(key ConfigKey) string {
	cfgs := read_config_lines()
	for cfg in cfgs {
		if cfg.starts_with(key.str()) {
			parts := cfg.split('=')
			if parts.len != 2 {
				eprintln('Warning: Skipping invalid config line: "${cfg}"')
				continue
			}
			return parts[1].trim_space()
		}
	}
	return ''
}

fn print_help() {
	println('Commands:')
	println(' add <program> <file_path>   - Move file to dotfiles and create symlink')
	println(' link <program/s>            - Create symlinks for program dotfiles')
	println(' unlink <program/s>          - Remove symlinks for program dotfiles')
	println(' delete <program/s>          - Delete program dotfiles directory')
	println(' list                        - List available program dotfiles')
}

fn add_dot(dot_name string, dot_path string) {
	if dot_name.contains('..') || dot_name.contains(os.path_separator) {
		eprintln('Error: Program name cannot contain path separators or "..".')
		exit(1)
	}
	home_dir := os.home_dir()
	root_dir := get_root_dir()
	src_path := os.join_path(root_dir, dot_name)

	abs_dot_path := os.abs_path(dot_path)

	if !abs_dot_path.starts_with(home_dir + os.path_separator) {
		eprintln('Error: ${abs_dot_path} is not in the home directory.')
		exit(1)
	}

	if !os.exists(abs_dot_path) {
		eprintln('Error: ${abs_dot_path} does not exist.')
		exit(1)
	}

	if os.is_link(abs_dot_path) {
		eprintln('Error: ${abs_dot_path} is a link.')
		exit(1)
	}

	rel_path := abs_dot_path[home_dir.len + 1..]
	target_path := os.join_path(root_dir, dot_name, rel_path)
	base_path := os.dir(target_path)
	if !os.exists(base_path) {
		os.mkdir_all(base_path) or {
			eprintln('Uncaught error: ${err}')
			exit(1)
		}
	}
	os.mv(abs_dot_path, target_path) or {
		eprintln('Uncaught error: ${err}')
		exit(1)
	}

	println('Created new dot file at ${src_path}')
	link_dots([dot_name])
}

fn link_dots(dots []string) {
	root_dir := get_root_dir()
	for dot in dots {
		src_path := os.join_path(root_dir, dot)
		if !os.exists(src_path) {
			eprintln('Error: ${dot} not found in dotfiles.')
			continue
		}

		os.walk(src_path, fn [src_path] (fp string) {
			rel_path := fp[src_path.len + 1..]
			target_path := os.join_path(os.home_dir(), rel_path)

			os.mkdir_all(os.dir(target_path)) or {
				eprintln('Uncaught error: ${err}')
				return
			}

			if os.exists(target_path) {
				eprintln('Error: ${target_path} already exist.')
				return
			}

			os.symlink(fp, target_path) or {
				eprintln('Uncaught error: ${err}')
				return
			}
			println('Linked: ${rel_path}')
		})
	}
}

fn unlink_dots(dots []string) {
	root_dir := get_root_dir()
	for dot in dots {
		src_path := os.join_path(root_dir, dot)

		if !os.exists(src_path) {
			eprintln('Error: ${src_path} does not exist.')
			continue
		}

		os.walk(src_path, fn [src_path] (fp string) {
			rel_path := fp[src_path.len + 1..]
			target_path := os.join_path(os.home_dir(), rel_path)

			if !os.is_link(target_path) {
				eprintln('Error: ${target_path} is not a link.')
				return
			}

			os.rm(target_path) or {
				eprintln('Uncaught error: ${err}')
				return
			}
			println('Unlinked: ${rel_path}')
			os.rmdir(os.dir(target_path)) or {}
		})
	}
}

fn delete_dots(dots []string) {
	root_dir := get_root_dir()
	for dot in dots {
		src_path := os.join_path(root_dir, dot)

		if !os.exists(src_path) {
			eprintln('Error: ${src_path} does not exist.')
			continue
		}

		unlink_dots([dot])

		os.rmdir_all(src_path) or {
			eprintln('Uncaught error: ${err}')
			continue
		}
		println('Removed: ${src_path}')
	}
}

fn list_dots() {
	root_dir := get_root_dir()
	mut dots := map[string]bool{}
	mut entries := os.ls(root_dir) or {
		eprintln('Uncaught error: ${err}')
		exit(1)
	}
	for entry in entries {
		if entry == '.git' {
			continue
		}
		src_path := os.join_path(root_dir, entry)
		dots[entry] = true
		os.walk(src_path, fn [src_path, entry, mut dots] (fp string) {
			rel_path := fp[src_path.len + 1..]
			target_path := os.join_path(os.home_dir(), rel_path)

			if !os.is_link(target_path) {
				dots[entry] = false
			}
		})
	}

	mut linked_str := ''
	mut unlinked_str := ''

	for dot_name, is_linked in dots {
		if is_linked {
			if linked_str.len == 0 {
				linked_str += '================\n=    Linked    =\n================\n'
			}
			linked_str += dot_name + '\n'
		} else {
			if unlinked_str.len == 0 {
				unlinked_str += '================\n=   Unlinked   =\n================\n'
			}
			unlinked_str += dot_name + '\n'
		}
	}

	spacing := if linked_str.len != 0 && unlinked_str.len != 0 { '\n' } else { '' }
	println(linked_str + spacing + unlinked_str + '')
}
