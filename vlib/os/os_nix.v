module os

#include <dirent.h>
#include <unistd.h>
pub const (
	path_separator = '/'
)

const (
	stdin_value = 0
	stdout_value = 1
	stderr_value = 2
)

fn C.symlink(charptr, charptr) int


pub fn init_os_args(argc int, argv &byteptr) []string {
	mut args := []string
	for i in 0 .. argc {
		args << string(argv[i])
	}
	return args
}

// get_error_msg return error code representation in string.
pub fn get_error_msg(code int) string {
	ptr_text := C.strerror(code) // voidptr?
	if ptr_text == 0 {
		return ''
	}
	return tos3(ptr_text)
}

pub fn ls(path string) ?[]string {
	mut res := []string
	dir := C.opendir(path.str)
	if isnil(dir) {
		return error('ls() couldnt open dir "$path"')
	}
	mut ent := &C.dirent(0)
	// mut ent := &C.dirent{!}
	for {
		ent = C.readdir(dir)
		if isnil(ent) {
			break
		}
		name := tos_clone(byteptr(ent.d_name))
		if name != '.' && name != '..' && name != '' {
			res << name
		}
	}
	C.closedir(dir)
	return res
}

/*
pub fn is_dir(path string) bool {
	//$if linux {
		//C.syscall(4, path.str) // sys_newstat
	//}
	dir := C.opendir(path.str)
	res := !isnil(dir)
	if res {
		C.closedir(dir)
	}
	return res
}
*/


pub fn open(path string) ?File {
	mut file := File{}
	$if linux {
		$if !android {
			fd := C.syscall(sys_open, path.str, 511)
			if fd == -1 {
				return error('failed to open file "$path"')
			}
			return File{
				fd: fd
				opened: true
			}
		}
	}
	cpath := path.str
	file = File{
		cfile: C.fopen(charptr(cpath), 'rb')
		opened: true
	}
	if isnil(file.cfile) {
		return error('failed to open file "$path"')
	}
	return file
}

// create creates a file at a specified location and returns a writable `File` object.
pub fn create(path string) ?File {
	mut fd := 0
	mut file := File{}
	// NB: android/termux/bionic is also a kind of linux,
	// but linux syscalls there sometimes fail,
	// while the libc version should work.
	$if linux {
		$if !android {
			//$if macos {
			//	fd = C.syscall(398, path.str, 0x601, 0x1b6)
			//}
			//$if linux {
			fd = C.syscall(sys_creat, path.str, 511)
			//}
			if fd == -1 {
				return error('failed to create file "$path"')
			}
			file = File{
				fd: fd
				opened: true
			}
			return file
		}
	}
	file = File{
		cfile: C.fopen(charptr(path.str), 'wb')
		opened: true
	}
	if isnil(file.cfile) {
		return error('failed to create file "$path"')
	}
	return file
}

/*
pub fn (f mut File) fseek(pos, mode int) {
}
*/


pub fn (f mut File) write(s string) {
	if !f.opened {
		return
	}
	$if linux {
		$if !android {
			C.syscall(sys_write, f.fd, s.str, s.len)
			return
		}
	}
	C.fputs(s.str, f.cfile)
	// C.fwrite(s.str, 1, s.len, f.cfile)
}

pub fn (f mut File) writeln(s string) {
	if !f.opened {
		return
	}
	$if linux {
		$if !android {
			snl := s + '\n'
			C.syscall(sys_write, f.fd, snl.str, snl.len)
			return
		}
	}
	// C.fwrite(s.str, 1, s.len, f.cfile)
	// ss := s.clone()
	// TODO perf
	C.fputs(s.str, f.cfile)
	// ss.free()
	C.fputs('\n', f.cfile)
}

// mkdir creates a new directory with the specified path.
pub fn mkdir(path string) ?bool {
	if path == '.' {
		return true
	}
	apath := os.realpath(path)
	$if linux {
		$if !android {
			ret := C.syscall(sys_mkdir, apath.str, 511)
			if ret == -1 {
				return error(get_error_msg(C.errno))
			}
			return true
		}
	}
	r := C.mkdir(apath.str, 511)
	if r == -1 {
		return error(get_error_msg(C.errno))
	}
	return true
}

// exec starts the specified command, waits for it to complete, and returns its output.
pub fn exec(cmd string) ?Result {
	// if cmd.contains(';') || cmd.contains('&&') || cmd.contains('||') || cmd.contains('\n') {
	// return error(';, &&, || and \\n are not allowed in shell commands')
	// }
	pcmd := '$cmd 2>&1'
	f := vpopen(pcmd)
	if isnil(f) {
		return error('exec("$cmd") failed')
	}
	buf := [1000]byte
	mut res := ''
	for C.fgets(charptr(buf), 1000, f) != 0 {
		res += tos(buf, vstrlen(buf))
	}
	res = res.trim_space()
	exit_code := vpclose(f)
	// if exit_code != 0 {
	// return error(res)
	// }
	return Result{
		output: res
		exit_code: exit_code
	}
}

pub fn symlink(origin, target string) ?bool {
	res := C.symlink(origin.str, target.str)
	if res == 0 {
		return true
	}
	return error(get_error_msg(C.errno))
}

// convert any value to []byte (LittleEndian) and write it
// for example if we have write(7, 4), "07 00 00 00" gets written
// write(0x1234, 2) => "34 12"
pub fn (f mut File) write_bytes(data voidptr, size int) {
	$if linux {
		$if !android {
			C.syscall(sys_write, f.fd, data, 1)
			return
		}
	}
	C.fwrite(data, 1, size, f.cfile)
}

pub fn (f mut File) close() {
	if !f.opened {
		return
	}
	f.opened = false
	$if linux {
		$if !android {
			C.syscall(sys_close, f.fd)
			return
		}
	}
	C.fflush(f.cfile)
	C.fclose(f.cfile)
}
