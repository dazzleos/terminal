//! The terminal's built-in commands. Dazzle has no separate command-line
//! binaries in /bin: the terminal runs standard tools (`ls`, `cp`, `mv`,
//! `rm`, `rmdir`, `mkdir`, `cat`, `grep`, `find`, `ps`, `df`, `free`, ...)
//! itself, over Linux system calls.
//!
//! Each command reads from `Context.stdin` (when piped or redirected) and
//! writes to `Context.stdout` and `Context.stderr`, returning an exit code
//! (0 when it worked).

const std = @import("std");
const linux = std.os.linux;
const sys = @import("sys");
const locale = @import("locale");
const shell_mod = @import("shell.zig");

pub const Shell = shell_mod.Shell;

/// What a running command reads and writes.
pub const Context = struct {
    shell: *Shell,
    gpa: std.mem.Allocator,
    stdin: []const u8 = "",
    stdout: std.ArrayList(u8) = .empty,
    stderr: std.ArrayList(u8) = .empty,

    pub fn deinit(cx: *Context) void {
        cx.stdout.deinit(cx.gpa);
        cx.stderr.deinit(cx.gpa);
    }

    pub fn write(cx: *Context, bytes: []const u8) void {
        cx.stdout.appendSlice(cx.gpa, bytes) catch {};
    }

    pub fn print(cx: *Context, comptime fmt: []const u8, args: anytype) void {
        cx.stdout.print(cx.gpa, fmt, args) catch {};
    }

    pub fn errPrint(cx: *Context, comptime fmt: []const u8, args: anytype) void {
        cx.stderr.print(cx.gpa, fmt, args) catch {};
    }

    /// Resolves `path` against the shell's working directory and `~` (in
    /// `cx.gpa`).
    pub fn resolve(cx: *Context, path: []const u8) ![]u8 {
        return cx.shell.resolvePath(path);
    }
};

pub const Command = struct {
    name: []const u8,
    usage: []const u8,
    summary: []const u8,
    run: *const fn (cx: *Context, args: []const []const u8) u8,
};

pub const commands = [_]Command{
    .{ .name = "cat", .usage = "cat [-n] [file...]", .summary = "Print files (or standard input) to the output", .run = cmdCat },
    .{ .name = "cd", .usage = "cd [dir|-]", .summary = "Change the working folder", .run = cmdCd },
    .{ .name = "chmod", .usage = "chmod [-R] <mode> <path>...", .summary = "Change file or folder permissions (e.g. 755, +x, u+w)", .run = cmdChmod },
    .{ .name = "clear", .usage = "clear", .summary = "Clear the terminal screen", .run = cmdClear },
    .{ .name = "cp", .usage = "cp [-r|-R] [-f] [-n] <source>... <dest>", .summary = "Copy files and folders", .run = cmdCp },
    .{ .name = "cut", .usage = "cut [-d delim] -f list | -c list [file...]", .summary = "Cut fields or characters from each line", .run = cmdCut },
    .{ .name = "date", .usage = "date", .summary = "Print the current date and time (UTC)", .run = cmdDate },
    .{ .name = "df", .usage = "df [-h] [path...]", .summary = "Show free and used space on mounted filesystems", .run = cmdDf },
    .{ .name = "dmesg", .usage = "dmesg [-n count]", .summary = "Print messages from the kernel and system log", .run = cmdDmesg },
    .{ .name = "du", .usage = "du [-s] [-h] [path...]", .summary = "Show disk space used by files and folders", .run = cmdDu },
    .{ .name = "echo", .usage = "echo [-n] [-e] [text...]", .summary = "Print text to the output", .run = cmdEcho },
    .{ .name = "env", .usage = "env", .summary = "List environment variables", .run = cmdEnv },
    .{ .name = "exit", .usage = "exit [code]", .summary = "Close the terminal", .run = cmdExit },
    .{ .name = "export", .usage = "export [NAME[=value]...]", .summary = "Set or list environment variables", .run = cmdExport },
    .{ .name = "false", .usage = "false", .summary = "Do nothing, unsuccessfully (exit status 1)", .run = cmdFalse },
    .{ .name = "file", .usage = "file <path>...", .summary = "Say what kind of file each path is", .run = cmdFile },
    .{ .name = "find", .usage = "find [path...] [-name pat] [-iname pat] [-type f|d|l] [-maxdepth N]", .summary = "Search for files and folders in a directory tree", .run = cmdFind },
    .{ .name = "free", .usage = "free [-h|-m|-k|-b]", .summary = "Show system and GPU memory usage", .run = cmdFree },
    .{ .name = "grep", .usage = "grep [-i] [-v] [-n] [-c] [-l] [-q] [-r] <pattern> [file...]", .summary = "Search for lines matching a pattern", .run = cmdGrep },
    .{ .name = "head", .usage = "head [-n lines] [-c bytes] [file...]", .summary = "Print the first part of files (10 lines by default)", .run = cmdHead },
    .{ .name = "help", .usage = "help [command]", .summary = "List built-in commands, or explain one", .run = cmdHelp },
    .{ .name = "hexdump", .usage = "hexdump [-C] [-n bytes] [file...]", .summary = "Print bytes in hexadecimal and ASCII", .run = cmdHexdump },
    .{ .name = "history", .usage = "history [-c]", .summary = "Show or clear the command history", .run = cmdHistory },
    .{ .name = "hostname", .usage = "hostname", .summary = "Print the computer's name", .run = cmdHostname },
    .{ .name = "id", .usage = "id", .summary = "Print the user and group IDs", .run = cmdId },
    .{ .name = "kill", .usage = "kill [-s sig | -sig] <pid>...", .summary = "Send a signal to a running process", .run = cmdKill },
    .{ .name = "ln", .usage = "ln [-s] [-f] <target> [link_name]", .summary = "Make a link to a file or folder (-s for symbolic)", .run = cmdLn },
    .{ .name = "ls", .usage = "ls [-a] [-l] [-h] [-1] [-R] [-r] [-t] [-S] [-d] [-F] [path...]", .summary = "List the files in a folder", .run = cmdLs },
    .{ .name = "mkdir", .usage = "mkdir [-p] <folder>...", .summary = "Make new folders (-p for parents too)", .run = cmdMkdir },
    .{ .name = "mv", .usage = "mv [-f] [-n] <source>... <dest>", .summary = "Move or rename files and folders", .run = cmdMv },
    .{ .name = "open", .usage = "open <app|file>", .summary = "Open an app or edit a text file", .run = cmdOpen },
    .{ .name = "ping", .usage = "ping [-c count] [-W timeout] [-s size] [-q] <host>", .summary = "Send ICMP echo requests to a network host", .run = cmdPing },
    .{ .name = "ps", .usage = "ps", .summary = "List the programs that are running", .run = cmdPs },
    .{ .name = "pwd", .usage = "pwd", .summary = "Print the working folder", .run = cmdPwd },
    .{ .name = "readlink", .usage = "readlink [-f] <path>...", .summary = "Print where a symbolic link points", .run = cmdReadlink },
    .{ .name = "rm", .usage = "rm [-r|-R] [-f] [-d] <path>...", .summary = "Remove files or folders (-r for a folder and its contents)", .run = cmdRm },
    .{ .name = "rmdir", .usage = "rmdir [-p] <folder>...", .summary = "Remove empty folders", .run = cmdRmdir },
    .{ .name = "sha256sum", .usage = "sha256sum [file...]", .summary = "Compute SHA-256 checksums", .run = cmdSha256sum },
    .{ .name = "sort", .usage = "sort [-r] [-n] [-u] [file...]", .summary = "Sort lines of text", .run = cmdSort },
    .{ .name = "stat", .usage = "stat <path>...", .summary = "Show details of a file or folder", .run = cmdStat },
    .{ .name = "tail", .usage = "tail [-n lines] [-c bytes] [file...]", .summary = "Print the last part of files (10 lines by default)", .run = cmdTail },
    .{ .name = "tee", .usage = "tee [-a] <file>...", .summary = "Copy standard input to standard output and files", .run = cmdTee },
    .{ .name = "touch", .usage = "touch [-c] <file>...", .summary = "Create empty files or update their modification times", .run = cmdTouch },
    .{ .name = "tr", .usage = "tr [-d] <set1> [set2]", .summary = "Translate or delete characters from standard input", .run = cmdTr },
    .{ .name = "true", .usage = "true", .summary = "Do nothing, successfully (exit status 0)", .run = cmdTrue },
    .{ .name = "type", .usage = "type <name>...", .summary = "Say how a command name is interpreted", .run = cmdWhich },
    .{ .name = "uname", .usage = "uname [-a] [-s] [-n] [-r] [-v] [-m]", .summary = "Print system and kernel information", .run = cmdUname },
    .{ .name = "uniq", .usage = "uniq [-c] [-d] [-u] [-i] [file...]", .summary = "Filter adjacent repeated lines", .run = cmdUniq },
    .{ .name = "unset", .usage = "unset <NAME>...", .summary = "Remove environment variables", .run = cmdUnset },
    .{ .name = "uptime", .usage = "uptime", .summary = "Print how long the system has been running", .run = cmdUptime },
    .{ .name = "wc", .usage = "wc [-l] [-w] [-c] [file...]", .summary = "Count lines, words and bytes", .run = cmdWc },
    .{ .name = "wget", .usage = "wget [-q] [-O file] [-P dir] <url>...", .summary = "Download files from the web over HTTP or HTTPS", .run = cmdWget },
    .{ .name = "which", .usage = "which <name>...", .summary = "Identify built-in commands", .run = cmdWhich },
    .{ .name = "whoami", .usage = "whoami", .summary = "Print the current user's name", .run = cmdWhoami },
    .{ .name = "xxd", .usage = "xxd [-n bytes] [file...]", .summary = "Print bytes in hexadecimal and ASCII", .run = cmdHexdump },
};

pub fn find(name: []const u8) ?*const Command {
    for (&commands) |*c| if (std.mem.eql(u8, c.name, name)) return c;
    return null;
}

// --- Filesystem helpers --------------------------------------------------------

const max_file_bytes = 16 * 1024 * 1024;

pub const StatInfo = struct {
    mode: u16,
    nlink: u32,
    uid: u32,
    gid: u32,
    size: u64,
    ino: u64,
    dev_major: u32,
    dev_minor: u32,
    mtime: i64,
    mtime_nsec: i64,

    pub fn isDir(s: StatInfo) bool {
        return s.mode & linux.S.IFMT == linux.S.IFDIR;
    }

    pub fn isReg(s: StatInfo) bool {
        return s.mode & linux.S.IFMT == linux.S.IFREG;
    }

    pub fn isLnk(s: StatInfo) bool {
        return s.mode & linux.S.IFMT == linux.S.IFLNK;
    }
};

pub const FsError = error{
    NOENT,
    ACCES,
    PERM,
    EXIST,
    NOTDIR,
    ISDIR,
    NOTEMPTY,
    ROFS,
    NOSPC,
    NAMETOOLONG,
    INVAL,
    BUSY,
    XDEV,
    SRCH,
    LOOP,
    NOMEM,
    IO,
};

fn fromErrno(e: linux.E) FsError {
    return switch (e) {
        .NOENT => error.NOENT,
        .ACCES => error.ACCES,
        .PERM => error.PERM,
        .EXIST => error.EXIST,
        .NOTDIR => error.NOTDIR,
        .ISDIR => error.ISDIR,
        .NOTEMPTY => error.NOTEMPTY,
        .ROFS => error.ROFS,
        .NOSPC => error.NOSPC,
        .NAMETOOLONG => error.NAMETOOLONG,
        .INVAL => error.INVAL,
        .BUSY => error.BUSY,
        .XDEV => error.XDEV,
        .SRCH => error.SRCH,
        .LOOP => error.LOOP,
        .NOMEM => error.NOMEM,
        else => error.IO,
    };
}

pub fn statPath(path: []const u8, follow_links: bool) FsError!StatInfo {
    var buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return error.NAMETOOLONG;
    return statZ(z, follow_links);
}

pub fn statZ(path_z: [*:0]const u8, follow_links: bool) FsError!StatInfo {
    var stx: linux.Statx = undefined;
    const flags: u32 = if (follow_links) 0 else linux.AT.SYMLINK_NOFOLLOW;
    const mask: linux.STATX = .{ .TYPE = true, .MODE = true, .NLINK = true, .UID = true, .GID = true, .SIZE = true, .INO = true, .MTIME = true };
    const rc = linux.statx(linux.AT.FDCWD, path_z, flags, mask, &stx);
    const e = linux.errno(rc);
    if (e != .SUCCESS) return fromErrno(e);
    return .{
        .mode = stx.mode,
        .nlink = stx.nlink,
        .uid = stx.uid,
        .gid = stx.gid,
        .size = stx.size,
        .ino = stx.ino,
        .dev_major = stx.dev_major,
        .dev_minor = stx.dev_minor,
        .mtime = stx.mtime.sec,
        .mtime_nsec = stx.mtime.nsec,
    };
}

/// Reads an entire file in chunks (so virtual files in /proc and /sys,
/// whose statx size is 0, read in full too).
pub fn readFileAll(gpa: std.mem.Allocator, path: []const u8) FsError![]u8 {
    var path_buf: [4096]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch return error.NAMETOOLONG;
    if (statZ(path_z, true)) |st| {
        if (st.isDir()) return error.ISDIR;
    } else |_| {}
    const rc = linux.open(path_z, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    const e = linux.errno(rc);
    if (e != .SUCCESS) return fromErrno(e);
    const fd: linux.fd_t = @intCast(rc);
    defer sys.close(fd);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = linux.read(fd, &buf, buf.len);
        const re = linux.errno(n);
        if (re == .INTR) continue;
        if (re != .SUCCESS) return fromErrno(re);
        if (n == 0) break;
        if (out.items.len + n > max_file_bytes) return error.NOMEM;
        out.appendSlice(gpa, buf[0..n]) catch return error.NOMEM;
    }
    return out.toOwnedSlice(gpa) catch error.NOMEM;
}

/// Writes `data` to `path` (truncating or appending).
pub fn writeFileAll(path: []const u8, data: []const u8, append: bool) FsError!void {
    var path_buf: [4096]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch return error.NAMETOOLONG;
    const flags: linux.O = .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = !append,
        .APPEND = append,
        .CLOEXEC = true,
    };
    const rc = linux.open(path_z, flags, 0o644);
    const e = linux.errno(rc);
    if (e != .SUCCESS) return fromErrno(e);
    const fd: linux.fd_t = @intCast(rc);
    defer sys.close(fd);
    var at: usize = 0;
    while (at < data.len) {
        const w = linux.write(fd, data[at..].ptr, data[at..].len);
        const we = linux.errno(w);
        if (we == .INTR) continue;
        if (we != .SUCCESS) return fromErrno(we);
        at += w;
    }
}

pub fn describeErrno(e: anytype) []const u8 {
    const name = if (@typeInfo(@TypeOf(e)) == .error_set) @errorName(e) else @tagName(e);
    if (std.mem.eql(u8, name, "NOENT")) return "No such file or directory";
    if (std.mem.eql(u8, name, "ACCES") or std.mem.eql(u8, name, "PERM")) return "Permission denied";
    if (std.mem.eql(u8, name, "EXIST")) return "File exists";
    if (std.mem.eql(u8, name, "NOTDIR")) return "Not a directory";
    if (std.mem.eql(u8, name, "ISDIR")) return "Is a directory";
    if (std.mem.eql(u8, name, "NOTEMPTY")) return "Directory not empty";
    if (std.mem.eql(u8, name, "ROFS")) return "Read-only filesystem";
    if (std.mem.eql(u8, name, "NOSPC")) return "No space left on device";
    if (std.mem.eql(u8, name, "NAMETOOLONG")) return "File name too long";
    if (std.mem.eql(u8, name, "INVAL")) return "Invalid argument";
    if (std.mem.eql(u8, name, "BUSY")) return "Device or resource busy";
    if (std.mem.eql(u8, name, "XDEV")) return "Invalid cross-device link";
    if (std.mem.eql(u8, name, "SRCH")) return "No such process";
    if (std.mem.eql(u8, name, "LOOP")) return "Too many levels of symbolic links";
    return name;
}

/// Joins `dir` and `name` with a single `/`.
pub fn joinPath(gpa: std.mem.Allocator, dir: []const u8, name: []const u8) ![]u8 {
    if (std.mem.eql(u8, dir, "/")) return std.fmt.allocPrint(gpa, "/{s}", .{name});
    return std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir, name });
}

/// Whether `path` is `ancestor` or inside it.
fn isWithin(path: []const u8, ancestor: []const u8) bool {
    if (std.mem.eql(u8, ancestor, "/")) return path.len > 0 and path[0] == '/';
    return std.mem.startsWith(u8, path, ancestor) and (path.len == ancestor.len or path[ancestor.len] == '/');
}

/// Formats a byte count as human-readable ("512B", "4.0K", "1.2M", "3.5G").
fn formatHumanSize(buf: []u8, bytes: u64) []const u8 {
    if (bytes < 1024) return std.fmt.bufPrint(buf, "{d}B", .{bytes}) catch "";
    const units = "KMGT";
    var v: f64 = @floatFromInt(bytes);
    var u: usize = 0;
    v /= 1024.0;
    while (v >= 1024.0 and u + 1 < units.len) : (u += 1) v /= 1024.0;
    if (v < 10.0) return std.fmt.bufPrint(buf, "{d:.1}{c}", .{ v, units[u] }) catch "";
    return std.fmt.bufPrint(buf, "{d:.0}{c}", .{ v, units[u] }) catch "";
}

/// Formats a mode (`st.mode`) as a 10-character string ("drwxr-xr-x").
fn formatMode(buf: *[10]u8, mode: u16) []const u8 {
    buf[0] = switch (mode & linux.S.IFMT) {
        linux.S.IFDIR => 'd',
        linux.S.IFLNK => 'l',
        linux.S.IFCHR => 'c',
        linux.S.IFBLK => 'b',
        linux.S.IFIFO => 'p',
        linux.S.IFSOCK => 's',
        else => '-',
    };
    const chars = "rwxrwxrwx";
    for (0..9) |i| {
        const bit: u16 = @as(u16, 1) << @intCast(8 - i);
        buf[1 + i] = if (mode & bit != 0) chars[i] else '-';
    }
    if (mode & 0o4000 != 0) buf[3] = if (buf[3] == 'x') 's' else 'S';
    if (mode & 0o2000 != 0) buf[6] = if (buf[6] == 'x') 's' else 'S';
    if (mode & 0o1000 != 0) buf[9] = if (buf[9] == 'x') 't' else 'T';
    return buf[0..10];
}

// --- Glob matching -------------------------------------------------------------

/// Matches `text` against a shell glob pattern (`*`, `?`, `[...]`).
pub fn globMatch(pattern: []const u8, text: []const u8, ignore_case: bool) bool {
    var p: usize = 0;
    var t: usize = 0;
    var star_p: ?usize = null;
    var star_t: usize = 0;
    while (t < text.len) {
        if (p < pattern.len and pattern[p] == '*') {
            star_p = p;
            star_t = t;
            p += 1;
            continue;
        }
        if (p < pattern.len and matchOne(pattern, &p, text[t], ignore_case)) {
            t += 1;
            continue;
        }
        if (star_p) |sp| {
            p = sp + 1;
            star_t += 1;
            t = star_t;
            continue;
        }
        return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

fn matchOne(pattern: []const u8, p: *usize, ch: u8, ignore_case: bool) bool {
    const pc = pattern[p.*];
    if (pc == '?') {
        p.* += 1;
        return true;
    }
    if (pc == '[') {
        var i = p.* + 1;
        var invert = false;
        if (i < pattern.len and (pattern[i] == '!' or pattern[i] == '^')) {
            invert = true;
            i += 1;
        }
        var matched = false;
        var first = true;
        while (i < pattern.len and (first or pattern[i] != ']')) : (first = false) {
            if (i + 2 < pattern.len and pattern[i + 1] == '-' and pattern[i + 2] != ']') {
                const lo = if (ignore_case) std.ascii.toLower(pattern[i]) else pattern[i];
                const hi = if (ignore_case) std.ascii.toLower(pattern[i + 2]) else pattern[i + 2];
                const c = if (ignore_case) std.ascii.toLower(ch) else ch;
                if (c >= lo and c <= hi) matched = true;
                i += 3;
            } else {
                if (charEq(pattern[i], ch, ignore_case)) matched = true;
                i += 1;
            }
        }
        if (i < pattern.len and pattern[i] == ']') {
            p.* = i + 1;
            return if (invert) !matched else matched;
        }
    }
    if (charEq(pc, ch, ignore_case)) {
        p.* += 1;
        return true;
    }
    return false;
}

fn charEq(a: u8, b: u8, ignore_case: bool) bool {
    return if (ignore_case) std.ascii.toLower(a) == std.ascii.toLower(b) else a == b;
}

// --- Built-in commands ---------------------------------------------------------

fn cmdHelp(cx: *Context, args: []const []const u8) u8 {
    if (args.len > 0) {
        var status: u8 = 0;
        for (args) |name| {
            if (find(name)) |c| {
                cx.print("{s}: {s}\nUsage: {s}\n", .{ c.name, c.summary, c.usage });
            } else {
                cx.errPrint("help: unknown command '{s}'\n", .{name});
                status = 1;
            }
        }
        return status;
    }
    cx.write("Built-in commands (type 'help <command>' for usage):\n\n");
    for (commands) |c| {
        cx.print("  {s:<11} {s}\n", .{ c.name, c.summary });
    }
    cx.write("\nShell features: pipes (|), redirection (>, >>, <), chaining (;, &&, ||),\nvariables ($VAR, export), globs (*, ?), Tab completion, and Up/Down history.\n");
    return 0;
}

fn cmdClear(cx: *Context, _: []const []const u8) u8 {
    cx.shell.clearOutput();
    return 0;
}

fn cmdExit(cx: *Context, args: []const []const u8) u8 {
    const code: u8 = if (args.len > 0) std.fmt.parseInt(u8, args[0], 10) catch 1 else cx.shell.last_status;
    cx.shell.should_exit = true;
    return code;
}

fn cmdTrue(_: *Context, _: []const []const u8) u8 {
    return 0;
}

fn cmdFalse(_: *Context, _: []const []const u8) u8 {
    return 1;
}

fn cmdPwd(cx: *Context, _: []const []const u8) u8 {
    cx.print("{s}\n", .{cx.shell.cwd.items});
    return 0;
}

fn cmdCd(cx: *Context, args: []const []const u8) u8 {
    if (args.len > 1) {
        cx.errPrint("cd: too many arguments\n", .{});
        return 1;
    }
    const target_arg = if (args.len == 0) "~" else args[0];
    const print_after = std.mem.eql(u8, target_arg, "-");
    const dest = if (print_after) blk: {
        if (cx.shell.old_cwd.items.len == 0) {
            cx.errPrint("cd: OLDPWD not set\n", .{});
            return 1;
        }
        break :blk cx.gpa.dupe(u8, cx.shell.old_cwd.items) catch return 1;
    } else cx.resolve(target_arg) catch return 1;
    defer cx.gpa.free(dest);

    const st = statPath(dest, true) catch |e| {
        cx.errPrint("cd: {s}: {s}\n", .{ target_arg, describeErrno(e) });
        return 1;
    };
    if (!st.isDir()) {
        cx.errPrint("cd: {s}: Not a directory\n", .{target_arg});
        return 1;
    }
    var buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{dest}) catch return 1;
    const rc = linux.open(z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    const e = linux.errno(rc);
    if (e != .SUCCESS) {
        cx.errPrint("cd: {s}: {s}\n", .{ target_arg, describeErrno(e) });
        return 1;
    }
    sys.close(@intCast(rc));

    cx.shell.setCwd(dest) catch return 1;
    if (print_after) cx.print("{s}\n", .{cx.shell.cwd.items});
    return 0;
}

// --- ls ------------------------------------------------------------------------

const LsOptions = struct {
    all: bool = false,
    almost_all: bool = false,
    long: bool = false,
    human: bool = false,
    one_per_line: bool = false,
    recursive: bool = false,
    reverse: bool = false,
    sort_time: bool = false,
    sort_size: bool = false,
    directory_only: bool = false,
    classify: bool = false,
};

const LsEntry = struct {
    name: []u8,
    st: StatInfo,
    link_target: ?[]u8 = null,
    exec: bool = false,
};

fn cmdLs(cx: *Context, args: []const []const u8) u8 {
    var opts: LsOptions = .{};
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(cx.gpa);

    var flags_done = false;
    for (args) |arg| {
        if (!flags_done and std.mem.eql(u8, arg, "--")) {
            flags_done = true;
            continue;
        }
        if (!flags_done and arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'a' => opts.all = true,
                'A' => opts.almost_all = true,
                'l' => opts.long = true,
                'h' => opts.human = true,
                '1' => opts.one_per_line = true,
                'R' => opts.recursive = true,
                'r' => opts.reverse = true,
                't' => opts.sort_time = true,
                'S' => opts.sort_size = true,
                'd' => opts.directory_only = true,
                'F' => opts.classify = true,
                else => {
                    cx.errPrint("ls: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            paths.append(cx.gpa, arg) catch return 1;
        }
    }
    if (paths.items.len == 0) paths.append(cx.gpa, ".") catch return 1;

    var status: u8 = 0;
    const now = sys.realtimeSec();
    var file_entries: std.ArrayList(LsEntry) = .empty;
    defer {
        for (file_entries.items) |e| {
            cx.gpa.free(e.name);
            if (e.link_target) |t| cx.gpa.free(t);
        }
        file_entries.deinit(cx.gpa);
    }
    var dirs: std.ArrayList([]const u8) = .empty;
    defer dirs.deinit(cx.gpa);

    for (paths.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        const st_l = statPath(resolved, false) catch |e| {
            cx.errPrint("ls: cannot access '{s}': {s}\n", .{ raw, describeErrno(e) });
            status = 1;
            continue;
        };
        const st_follow = if (st_l.isLnk() and !opts.long and !opts.directory_only) statPath(resolved, true) catch st_l else st_l;
        if (st_follow.isDir() and !opts.directory_only) {
            dirs.append(cx.gpa, raw) catch return 1;
        } else {
            const entry = makeLsEntry(cx.gpa, raw, resolved, st_l) catch return 1;
            file_entries.append(cx.gpa, entry) catch return 1;
        }
    }

    var printed_block = false;
    if (file_entries.items.len > 0) {
        sortLsEntries(file_entries.items, opts);
        printLsEntries(cx, file_entries.items, opts, now);
        printed_block = true;
    }

    const show_headers = (paths.items.len > 1) or opts.recursive;
    for (dirs.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        if (!lsDir(cx, raw, resolved, opts, show_headers, &printed_block, now)) status = 1;
    }
    return status;
}

fn makeLsEntry(gpa: std.mem.Allocator, display_name: []const u8, full_path: []const u8, st_l: StatInfo) !LsEntry {
    const name = try gpa.dupe(u8, display_name);
    errdefer gpa.free(name);
    var link_target: ?[]u8 = null;
    if (st_l.isLnk()) {
        var z_buf: [4096]u8 = undefined;
        var t_buf: [4096]u8 = undefined;
        if (std.fmt.bufPrintZ(&z_buf, "{s}", .{full_path})) |z| {
            const rc = linux.readlink(z, &t_buf, t_buf.len);
            if (linux.errno(rc) == .SUCCESS) link_target = try gpa.dupe(u8, t_buf[0..rc]);
        } else |_| {}
    }
    return .{
        .name = name,
        .st = st_l,
        .link_target = link_target,
        .exec = st_l.isReg() and (st_l.mode & 0o111 != 0),
    };
}

fn lsDir(cx: *Context, label: []const u8, full_path: []const u8, opts: LsOptions, show_header: bool, printed_block: *bool, now: i64) bool {
    var z_buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintZ(&z_buf, "{s}", .{full_path}) catch return false;
    const rc = linux.open(z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    const e = linux.errno(rc);
    if (e != .SUCCESS) {
        cx.errPrint("ls: cannot open directory '{s}': {s}\n", .{ label, describeErrno(e) });
        return false;
    }
    const fd: linux.fd_t = @intCast(rc);

    var entries: std.ArrayList(LsEntry) = .empty;
    defer {
        for (entries.items) |item| {
            cx.gpa.free(item.name);
            if (item.link_target) |t| cx.gpa.free(t);
        }
        entries.deinit(cx.gpa);
    }

    var dents: [4096]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &dents, dents.len);
        if (linux.errno(n) != .SUCCESS or n == 0) break;
        var at: usize = 0;
        while (at < n) {
            const reclen = std.mem.readInt(u16, dents[at + 16 ..][0..2], .little);
            const name_z: [*:0]const u8 = @ptrCast(&dents[at + 19]);
            const name = std.mem.span(name_z);
            at += reclen;
            if (name.len == 0) continue;
            if (name[0] == '.') {
                if (!opts.all and !opts.almost_all) continue;
                if (opts.almost_all and !opts.all and (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, ".."))) continue;
            }
            const child_full = joinPath(cx.gpa, full_path, name) catch continue;
            defer cx.gpa.free(child_full);
            const st = statPath(child_full, false) catch StatInfo{
                .mode = 0,
                .nlink = 1,
                .uid = 1000,
                .gid = 1000,
                .size = 0,
                .ino = 0,
                .dev_major = 0,
                .dev_minor = 0,
                .mtime = 0,
                .mtime_nsec = 0,
            };
            const entry = makeLsEntry(cx.gpa, name, child_full, st) catch continue;
            entries.append(cx.gpa, entry) catch continue;
        }
    }
    sys.close(fd);

    if (printed_block.*) cx.write("\n");
    if (show_header) cx.print("{s}:\n", .{label});
    printed_block.* = true;

    sortLsEntries(entries.items, opts);
    printLsEntries(cx, entries.items, opts, now);

    var ok = true;
    if (opts.recursive) {
        for (entries.items) |item| {
            if (!item.st.isDir()) continue;
            if (std.mem.eql(u8, item.name, ".") or std.mem.eql(u8, item.name, "..")) continue;
            const sub_label = if (std.mem.eql(u8, label, "."))
                cx.gpa.dupe(u8, item.name) catch continue
            else
                joinPath(cx.gpa, label, item.name) catch continue;
            defer cx.gpa.free(sub_label);
            const sub_full = joinPath(cx.gpa, full_path, item.name) catch continue;
            defer cx.gpa.free(sub_full);
            if (!lsDir(cx, sub_label, sub_full, opts, true, printed_block, now)) ok = false;
        }
    }
    return ok;
}

fn sortLsEntries(items: []LsEntry, opts: LsOptions) void {
    std.mem.sort(LsEntry, items, opts, struct {
        fn less(o: LsOptions, a: LsEntry, b: LsEntry) bool {
            const cmp = if (o.sort_time and a.st.mtime != b.st.mtime)
                a.st.mtime > b.st.mtime
            else if (o.sort_size and a.st.size != b.st.size)
                a.st.size > b.st.size
            else switch (std.ascii.orderIgnoreCase(a.name, b.name)) {
                .lt => true,
                .gt => false,
                .eq => std.mem.lessThan(u8, a.name, b.name),
            };
            return if (o.reverse) !cmp else cmp;
        }
    }.less);
}

fn printLsEntries(cx: *Context, items: []const LsEntry, opts: LsOptions, now: i64) void {
    if (opts.long) {
        for (items) |e| {
            var mode_buf: [10]u8 = undefined;
            const mode_str = formatMode(&mode_buf, e.st.mode);
            const owner = if (e.st.uid == 0) "root" else if (e.st.uid == sys.user.uid) sys.user.name else "user";
            var size_buf: [24]u8 = undefined;
            const size_str = if (opts.human)
                formatHumanSize(&size_buf, e.st.size)
            else
                std.fmt.bufPrint(&size_buf, "{d}", .{e.st.size}) catch "";
            var time_buf: [32]u8 = undefined;
            const when = locale.formatWhen(&time_buf, e.st.mtime, now);
            const suffix = classifySuffix(e, opts.classify);
            if (e.link_target) |target| {
                cx.print("{s} {d:>2} {s:<6} {s:>8} {s:<16} {s} -> {s}\n", .{ mode_str, e.st.nlink, owner, size_str, when, e.name, target });
            } else {
                cx.print("{s} {d:>2} {s:<6} {s:>8} {s:<16} {s}{s}\n", .{ mode_str, e.st.nlink, owner, size_str, when, e.name, suffix });
            }
        }
        return;
    }
    if (opts.one_per_line) {
        for (items) |e| cx.print("{s}{s}\n", .{ e.name, classifySuffix(e, opts.classify) });
        return;
    }
    // Compact rows of up to ~76 columns.
    var col: usize = 0;
    for (items, 0..) |e, i| {
        const suffix = classifySuffix(e, opts.classify);
        const len = e.name.len + suffix.len;
        if (i > 0) {
            if (col + 2 + len > 76) {
                cx.write("\n");
                col = 0;
            } else {
                cx.write("  ");
                col += 2;
            }
        }
        cx.print("{s}{s}", .{ e.name, suffix });
        col += len;
    }
    if (items.len > 0) cx.write("\n");
}

fn classifySuffix(e: LsEntry, classify: bool) []const u8 {
    if (e.st.isDir()) return "/";
    if (!classify) return "";
    if (e.st.isLnk()) return "@";
    if (e.exec) return "*";
    return "";
}

// --- mkdir, rmdir, rm, touch, ln, chmod ----------------------------------------

fn cmdMkdir(cx: *Context, args: []const []const u8) u8 {
    var parents = false;
    var targets: std.ArrayList([]const u8) = .empty;
    defer targets.deinit(cx.gpa);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--parents")) {
            parents = true;
        } else if (arg.len > 1 and arg[0] == '-') {
            cx.errPrint("mkdir: invalid option '{s}'\n", .{arg});
            return 1;
        } else {
            targets.append(cx.gpa, arg) catch return 1;
        }
    }
    if (targets.items.len == 0) {
        cx.errPrint("mkdir: missing operand\n", .{});
        return 1;
    }
    var status: u8 = 0;
    for (targets.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        const res = if (parents) mkdirParents(resolved) else mkdirOne(resolved);
        res catch |e| {
            cx.errPrint("mkdir: cannot create directory '{s}': {s}\n", .{ raw, describeErrno(e) });
            status = 1;
        };
    }
    return status;
}

fn mkdirOne(path: []const u8) FsError!void {
    var buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return error.NAMETOOLONG;
    const e = linux.errno(linux.mkdir(z, 0o755));
    if (e != .SUCCESS) return fromErrno(e);
}

pub fn mkdirParents(path: []const u8) FsError!void {
    if (std.mem.eql(u8, path, "/")) return;
    var end: usize = 1;
    while (end <= path.len) : (end += 1) {
        if (end < path.len and path[end] != '/') continue;
        const prefix = path[0..end];
        mkdirOne(prefix) catch |e| switch (e) {
            error.EXIST => {
                const st = statPath(prefix, true) catch return e;
                if (!st.isDir()) return error.NOTDIR;
            },
            else => return e,
        };
    }
}

fn cmdRmdir(cx: *Context, args: []const []const u8) u8 {
    var parents = false;
    var targets: std.ArrayList([]const u8) = .empty;
    defer targets.deinit(cx.gpa);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--parents")) {
            parents = true;
        } else if (arg.len > 1 and arg[0] == '-') {
            cx.errPrint("rmdir: invalid option '{s}'\n", .{arg});
            return 1;
        } else {
            targets.append(cx.gpa, arg) catch return 1;
        }
    }
    if (targets.items.len == 0) {
        cx.errPrint("rmdir: missing operand\n", .{});
        return 1;
    }
    var status: u8 = 0;
    for (targets.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        if (!rmdirPath(cx, raw, resolved, parents)) status = 1;
    }
    return status;
}

fn rmdirPath(cx: *Context, label: []const u8, resolved: []const u8, parents: bool) bool {
    var buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{resolved}) catch return false;
    const e = linux.errno(linux.rmdir(z));
    if (e != .SUCCESS) {
        cx.errPrint("rmdir: failed to remove '{s}': {s}\n", .{ label, describeErrno(e) });
        return false;
    }
    if (parents) {
        var cur = resolved;
        while (std.mem.lastIndexOfScalar(u8, cur, '/')) |slash| {
            if (slash == 0) break;
            cur = cur[0..slash];
            const cz = std.fmt.bufPrintZ(&buf, "{s}", .{cur}) catch break;
            if (linux.errno(linux.rmdir(cz)) != .SUCCESS) break;
        }
    }
    return true;
}

fn cmdRm(cx: *Context, args: []const []const u8) u8 {
    var recursive = false;
    var force = false;
    var empty_dir = false;
    var targets: std.ArrayList([]const u8) = .empty;
    defer targets.deinit(cx.gpa);

    var flags_done = false;
    for (args) |arg| {
        if (!flags_done and std.mem.eql(u8, arg, "--")) {
            flags_done = true;
            continue;
        }
        if (!flags_done and arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'r', 'R' => recursive = true,
                'f' => force = true,
                'd' => empty_dir = true,
                else => {
                    cx.errPrint("rm: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            targets.append(cx.gpa, arg) catch return 1;
        }
    }
    if (targets.items.len == 0) {
        if (force) return 0;
        cx.errPrint("rm: missing operand\n", .{});
        return 1;
    }
    var status: u8 = 0;
    for (targets.items) |raw| {
        const base = std.fs.path.basename(raw);
        if (std.mem.eql(u8, base, ".") or std.mem.eql(u8, base, "..")) {
            cx.errPrint("rm: refusing to remove '.' or '..'\n", .{});
            status = 1;
            continue;
        }
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        if (std.mem.eql(u8, resolved, "/")) {
            cx.errPrint("rm: refusing to remove '/'\n", .{});
            status = 1;
            continue;
        }
        if (!removeEntry(cx, raw, resolved, recursive, force, empty_dir)) status = 1;
    }
    return status;
}

fn removeEntry(cx: *Context, label: []const u8, full_path: []const u8, recursive: bool, force: bool, empty_dir: bool) bool {
    const st = statPath(full_path, false) catch |e| {
        if (force and e == error.NOENT) return true;
        cx.errPrint("rm: cannot remove '{s}': {s}\n", .{ label, describeErrno(e) });
        return false;
    };
    var buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{full_path}) catch return false;
    if (st.isDir()) {
        if (recursive) {
            return removeDirTree(cx, label, full_path, force);
        }
        if (empty_dir) {
            const e = linux.errno(linux.rmdir(z));
            if (e != .SUCCESS) {
                cx.errPrint("rm: cannot remove '{s}': {s}\n", .{ label, describeErrno(e) });
                return false;
            }
            return true;
        }
        cx.errPrint("rm: cannot remove '{s}': Is a directory\n", .{label});
        return false;
    }
    const e = linux.errno(linux.unlink(z));
    if (e != .SUCCESS) {
        if (force and e == .NOENT) return true;
        cx.errPrint("rm: cannot remove '{s}': {s}\n", .{ label, describeErrno(e) });
        return false;
    }
    return true;
}

fn removeDirTree(cx: *Context, label: []const u8, full_path: []const u8, force: bool) bool {
    var z_buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintZ(&z_buf, "{s}", .{full_path}) catch return false;
    const rc = linux.open(z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    const e = linux.errno(rc);
    if (e != .SUCCESS) {
        if (force and e == .NOENT) return true;
        cx.errPrint("rm: cannot open '{s}': {s}\n", .{ label, describeErrno(e) });
        return false;
    }
    const fd: linux.fd_t = @intCast(rc);

    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| cx.gpa.free(n);
        names.deinit(cx.gpa);
    }
    var dents: [4096]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &dents, dents.len);
        if (linux.errno(n) != .SUCCESS or n == 0) break;
        var at: usize = 0;
        while (at < n) {
            const reclen = std.mem.readInt(u16, dents[at + 16 ..][0..2], .little);
            const name = std.mem.sliceTo(dents[at + 19 .. at + reclen], 0);
            at += reclen;
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            const duped = cx.gpa.dupe(u8, name) catch continue;
            names.append(cx.gpa, duped) catch {
                cx.gpa.free(duped);
                continue;
            };
        }
    }
    sys.close(fd);

    var ok = true;
    for (names.items) |name| {
        const child_full = joinPath(cx.gpa, full_path, name) catch continue;
        defer cx.gpa.free(child_full);
        const child_label = joinPath(cx.gpa, label, name) catch continue;
        defer cx.gpa.free(child_label);
        if (!removeEntry(cx, child_label, child_full, true, force, true)) ok = false;
    }
    const re = linux.errno(linux.rmdir(z));
    if (re != .SUCCESS) {
        cx.errPrint("rm: cannot remove '{s}': {s}\n", .{ label, describeErrno(re) });
        return false;
    }
    return ok;
}

// --- cp and mv -----------------------------------------------------------------

const CopyOptions = struct {
    recursive: bool = false,
    force: bool = false,
    no_clobber: bool = false,
};

fn cmdCp(cx: *Context, args: []const []const u8) u8 {
    var opts: CopyOptions = .{};
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(cx.gpa);

    var flags_done = false;
    for (args) |arg| {
        if (!flags_done and std.mem.eql(u8, arg, "--")) {
            flags_done = true;
            continue;
        }
        if (!flags_done and arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'r', 'R', 'a' => opts.recursive = true,
                'f' => opts.force = true,
                'n' => opts.no_clobber = true,
                'p' => {},
                else => {
                    cx.errPrint("cp: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            paths.append(cx.gpa, arg) catch return 1;
        }
    }
    if (paths.items.len < 2) {
        cx.errPrint("cp: missing file operand\n", .{});
        return 1;
    }
    const dst_raw = paths.items[paths.items.len - 1];
    const srcs = paths.items[0 .. paths.items.len - 1];
    const dst_resolved = cx.resolve(dst_raw) catch return 1;
    defer cx.gpa.free(dst_resolved);

    const dst_is_dir = if (statPath(dst_resolved, true)) |st| st.isDir() else |_| false;
    if (srcs.len > 1 and !dst_is_dir) {
        cx.errPrint("cp: target '{s}' is not a directory\n", .{dst_raw});
        return 1;
    }

    var status: u8 = 0;
    for (srcs) |src_raw| {
        const src_resolved = cx.resolve(src_raw) catch continue;
        defer cx.gpa.free(src_resolved);
        const target = if (dst_is_dir)
            joinPath(cx.gpa, dst_resolved, std.fs.path.basename(src_resolved)) catch continue
        else
            cx.gpa.dupe(u8, dst_resolved) catch continue;
        defer cx.gpa.free(target);
        if (!copyItem(cx, src_raw, src_resolved, target, opts)) status = 1;
    }
    return status;
}

fn copyItem(cx: *Context, src_label: []const u8, src_path: []const u8, dst_path: []const u8, opts: CopyOptions) bool {
    const st = statPath(src_path, !opts.recursive) catch |e| {
        cx.errPrint("cp: cannot stat '{s}': {s}\n", .{ src_label, describeErrno(e) });
        return false;
    };
    if (std.mem.eql(u8, src_path, dst_path)) {
        cx.errPrint("cp: '{s}' and '{s}' are the same file\n", .{ src_label, dst_path });
        return false;
    }
    if (st.isDir()) {
        if (!opts.recursive) {
            cx.errPrint("cp: -r not specified; omitting directory '{s}'\n", .{src_label});
            return false;
        }
        if (isWithin(dst_path, src_path)) {
            cx.errPrint("cp: cannot copy a directory, '{s}', into itself\n", .{src_label});
            return false;
        }
        return copyDir(cx, src_label, src_path, dst_path, st, opts);
    }
    if (st.isLnk()) {
        return copySymlink(cx, src_label, src_path, dst_path, opts);
    }
    return copyRegFile(cx, src_label, src_path, dst_path, st, opts);
}

fn copyDir(cx: *Context, src_label: []const u8, src_path: []const u8, dst_path: []const u8, st: StatInfo, opts: CopyOptions) bool {
    var dst_buf: [4096]u8 = undefined;
    const dst_z = std.fmt.bufPrintZ(&dst_buf, "{s}", .{dst_path}) catch return false;
    switch (linux.errno(linux.mkdir(dst_z, (st.mode & 0o777) | 0o700))) {
        .SUCCESS => {},
        .EXIST => {
            const dst_st = statPath(dst_path, true) catch |e| {
                cx.errPrint("cp: cannot access '{s}': {s}\n", .{ dst_path, describeErrno(e) });
                return false;
            };
            if (!dst_st.isDir()) {
                cx.errPrint("cp: cannot overwrite non-directory '{s}' with directory '{s}'\n", .{ dst_path, src_label });
                return false;
            }
        },
        else => |e| {
            cx.errPrint("cp: cannot create directory '{s}': {s}\n", .{ dst_path, describeErrno(e) });
            return false;
        },
    }

    var src_buf: [4096]u8 = undefined;
    const src_z = std.fmt.bufPrintZ(&src_buf, "{s}", .{src_path}) catch return false;
    const rc = linux.open(src_z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    const e = linux.errno(rc);
    if (e != .SUCCESS) {
        cx.errPrint("cp: cannot open '{s}': {s}\n", .{ src_label, describeErrno(e) });
        return false;
    }
    const fd: linux.fd_t = @intCast(rc);

    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| cx.gpa.free(n);
        names.deinit(cx.gpa);
    }
    var dents: [4096]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &dents, dents.len);
        if (linux.errno(n) != .SUCCESS or n == 0) break;
        var at: usize = 0;
        while (at < n) {
            const reclen = std.mem.readInt(u16, dents[at + 16 ..][0..2], .little);
            const name = std.mem.sliceTo(dents[at + 19 .. at + reclen], 0);
            at += reclen;
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            const duped = cx.gpa.dupe(u8, name) catch continue;
            names.append(cx.gpa, duped) catch {
                cx.gpa.free(duped);
                continue;
            };
        }
    }
    sys.close(fd);

    var ok = true;
    for (names.items) |name| {
        const child_src = joinPath(cx.gpa, src_path, name) catch continue;
        defer cx.gpa.free(child_src);
        const child_dst = joinPath(cx.gpa, dst_path, name) catch continue;
        defer cx.gpa.free(child_dst);
        const child_label = joinPath(cx.gpa, src_label, name) catch continue;
        defer cx.gpa.free(child_label);
        if (!copyItem(cx, child_label, child_src, child_dst, opts)) ok = false;
    }
    return ok;
}

fn copySymlink(cx: *Context, src_label: []const u8, src_path: []const u8, dst_path: []const u8, opts: CopyOptions) bool {
    var src_buf: [4096]u8 = undefined;
    var dst_buf: [4096]u8 = undefined;
    var target_buf: [4096]u8 = undefined;
    const src_z = std.fmt.bufPrintZ(&src_buf, "{s}", .{src_path}) catch return false;
    const dst_z = std.fmt.bufPrintZ(&dst_buf, "{s}", .{dst_path}) catch return false;
    const n = linux.readlink(src_z, &target_buf, target_buf.len - 1);
    const re = linux.errno(n);
    if (re != .SUCCESS) {
        cx.errPrint("cp: cannot read link '{s}': {s}\n", .{ src_label, describeErrno(re) });
        return false;
    }
    target_buf[n] = 0;
    if (statZ(dst_z, false)) |_| {
        if (opts.no_clobber) return true;
        _ = linux.unlink(dst_z);
    } else |_| {}
    const se = linux.errno(linux.symlink(target_buf[0..n :0], dst_z));
    if (se != .SUCCESS) {
        cx.errPrint("cp: cannot create symlink '{s}': {s}\n", .{ dst_path, describeErrno(se) });
        return false;
    }
    return true;
}

fn copyRegFile(cx: *Context, src_label: []const u8, src_path: []const u8, dst_path: []const u8, st: StatInfo, opts: CopyOptions) bool {
    var src_buf: [4096]u8 = undefined;
    var dst_buf: [4096]u8 = undefined;
    const src_z = std.fmt.bufPrintZ(&src_buf, "{s}", .{src_path}) catch return false;
    const dst_z = std.fmt.bufPrintZ(&dst_buf, "{s}", .{dst_path}) catch return false;
    if (opts.no_clobber) {
        if (statZ(dst_z, false)) |_| return true else |_| {}
    }
    const src_rc = linux.open(src_z, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(src_rc) != .SUCCESS) {
        cx.errPrint("cp: cannot open '{s}': {s}\n", .{ src_label, describeErrno(linux.errno(src_rc)) });
        return false;
    }
    const src_fd: linux.fd_t = @intCast(src_rc);
    defer sys.close(src_fd);

    if (opts.force) {
        if (statZ(dst_z, false)) |dst_st| {
            if (!dst_st.isDir()) _ = linux.unlink(dst_z);
        } else |_| {}
    }

    const dst_rc = linux.open(dst_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, st.mode & 0o777);
    if (linux.errno(dst_rc) != .SUCCESS) {
        cx.errPrint("cp: cannot create '{s}': {s}\n", .{ dst_path, describeErrno(linux.errno(dst_rc)) });
        return false;
    }
    const dst_fd: linux.fd_t = @intCast(dst_rc);
    defer sys.close(dst_fd);
    _ = linux.fchmod(dst_fd, st.mode & 0o777);

    var buf: [16384]u8 = undefined;
    while (true) {
        const n = linux.read(src_fd, &buf, buf.len);
        const re = linux.errno(n);
        if (re == .INTR) continue;
        if (re != .SUCCESS) {
            cx.errPrint("cp: error reading '{s}': {s}\n", .{ src_label, describeErrno(re) });
            return false;
        }
        if (n == 0) break;
        var written: usize = 0;
        while (written < n) {
            const w = linux.write(dst_fd, buf[written..n].ptr, n - written);
            const we = linux.errno(w);
            if (we == .INTR) continue;
            if (we != .SUCCESS) {
                cx.errPrint("cp: error writing '{s}': {s}\n", .{ dst_path, describeErrno(we) });
                return false;
            }
            written += w;
        }
    }
    sys.setFileTimes(dst_fd, null, st.mtime, st.mtime_nsec) catch {};
    return true;
}

fn cmdMv(cx: *Context, args: []const []const u8) u8 {
    var force = false;
    var no_clobber = false;
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(cx.gpa);

    var flags_done = false;
    for (args) |arg| {
        if (!flags_done and std.mem.eql(u8, arg, "--")) {
            flags_done = true;
            continue;
        }
        if (!flags_done and arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'f' => force = true,
                'n' => no_clobber = true,
                else => {
                    cx.errPrint("mv: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            paths.append(cx.gpa, arg) catch return 1;
        }
    }
    if (paths.items.len < 2) {
        cx.errPrint("mv: missing file operand\n", .{});
        return 1;
    }
    const dst_raw = paths.items[paths.items.len - 1];
    const srcs = paths.items[0 .. paths.items.len - 1];
    const dst_resolved = cx.resolve(dst_raw) catch return 1;
    defer cx.gpa.free(dst_resolved);

    const dst_is_dir = if (statPath(dst_resolved, true)) |st| st.isDir() else |_| false;
    if (srcs.len > 1 and !dst_is_dir) {
        cx.errPrint("mv: target '{s}' is not a directory\n", .{dst_raw});
        return 1;
    }

    var status: u8 = 0;
    for (srcs) |src_raw| {
        const src_resolved = cx.resolve(src_raw) catch continue;
        defer cx.gpa.free(src_resolved);
        const target = if (dst_is_dir)
            joinPath(cx.gpa, dst_resolved, std.fs.path.basename(src_resolved)) catch continue
        else
            cx.gpa.dupe(u8, dst_resolved) catch continue;
        defer cx.gpa.free(target);

        if (std.mem.eql(u8, src_resolved, target)) continue;
        if (isWithin(target, src_resolved)) {
            cx.errPrint("mv: cannot move '{s}' to a subdirectory of itself\n", .{src_raw});
            status = 1;
            continue;
        }
        if (no_clobber) {
            if (statPath(target, false)) |_| continue else |_| {}
        }
        var from_buf: [4096]u8 = undefined;
        var to_buf: [4096]u8 = undefined;
        const from_z = std.fmt.bufPrintZ(&from_buf, "{s}", .{src_resolved}) catch continue;
        const to_z = std.fmt.bufPrintZ(&to_buf, "{s}", .{target}) catch continue;
        switch (linux.errno(linux.rename(from_z, to_z))) {
            .SUCCESS => {},
            .XDEV => {
                if (copyItem(cx, src_raw, src_resolved, target, .{ .recursive = true, .force = force, .no_clobber = no_clobber })) {
                    if (!removeEntry(cx, src_raw, src_resolved, true, true, true)) status = 1;
                } else status = 1;
            },
            else => |e| {
                cx.errPrint("mv: cannot move '{s}' to '{s}': {s}\n", .{ src_raw, dst_raw, describeErrno(e) });
                status = 1;
            },
        }
    }
    return status;
}

fn cmdTouch(cx: *Context, args: []const []const u8) u8 {
    var no_create = false;
    var targets: std.ArrayList([]const u8) = .empty;
    defer targets.deinit(cx.gpa);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--no-create")) {
            no_create = true;
        } else if (arg.len > 1 and arg[0] == '-') {
            cx.errPrint("touch: invalid option '{s}'\n", .{arg});
            return 1;
        } else {
            targets.append(cx.gpa, arg) catch return 1;
        }
    }
    if (targets.items.len == 0) {
        cx.errPrint("touch: missing file operand\n", .{});
        return 1;
    }

    const ns = sys.realtimeNs();
    const sec: i64 = @intCast(@divFloor(ns, std.time.ns_per_s));
    const nsec: i64 = @intCast(@mod(ns, std.time.ns_per_s));
    var status: u8 = 0;

    for (targets.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        var buf: [4096]u8 = undefined;
        const z = std.fmt.bufPrintZ(&buf, "{s}", .{resolved}) catch continue;
        if (statZ(z, true)) |_| {
            sys.setFileTimes(linux.AT.FDCWD, z, sec, nsec) catch {
                cx.errPrint("touch: cannot touch '{s}': Permission denied\n", .{raw});
                status = 1;
            };
        } else |_| {
            if (no_create) continue;
            const rc = linux.open(z, .{ .ACCMODE = .WRONLY, .CREAT = true, .CLOEXEC = true }, 0o644);
            const e = linux.errno(rc);
            if (e != .SUCCESS) {
                cx.errPrint("touch: cannot touch '{s}': {s}\n", .{ raw, describeErrno(e) });
                status = 1;
                continue;
            }
            const fd: linux.fd_t = @intCast(rc);
            _ = linux.fchmod(fd, 0o644);
            sys.setFileTimes(fd, null, sec, nsec) catch {};
            sys.close(fd);
        }
    }
    return status;
}

fn cmdLn(cx: *Context, args: []const []const u8) u8 {
    var symbolic = false;
    var force = false;
    var pos: std.ArrayList([]const u8) = .empty;
    defer pos.deinit(cx.gpa);

    for (args) |arg| {
        if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                's' => symbolic = true,
                'f' => force = true,
                else => {
                    cx.errPrint("ln: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            pos.append(cx.gpa, arg) catch return 1;
        }
    }
    if (pos.items.len == 0 or pos.items.len > 2) {
        cx.errPrint("ln: usage: ln [-s] [-f] <target> [link_name]\n", .{});
        return 1;
    }
    const target_raw = pos.items[0];
    const link_raw = if (pos.items.len == 2) pos.items[1] else std.fs.path.basename(target_raw);
    const link_resolved = cx.resolve(link_raw) catch return 1;
    defer cx.gpa.free(link_resolved);

    const final_link = if (statPath(link_resolved, true)) |st| blk: {
        if (st.isDir()) break :blk joinPath(cx.gpa, link_resolved, std.fs.path.basename(target_raw)) catch return 1;
        break :blk cx.gpa.dupe(u8, link_resolved) catch return 1;
    } else |_| cx.gpa.dupe(u8, link_resolved) catch return 1;
    defer cx.gpa.free(final_link);

    var link_buf: [4096]u8 = undefined;
    const link_z = std.fmt.bufPrintZ(&link_buf, "{s}", .{final_link}) catch return 1;
    if (force) {
        if (statZ(link_z, false)) |st| {
            if (!st.isDir()) _ = linux.unlink(link_z);
        } else |_| {}
    }

    if (symbolic) {
        var target_buf: [4096]u8 = undefined;
        const target_z = std.fmt.bufPrintZ(&target_buf, "{s}", .{target_raw}) catch return 1;
        const e = linux.errno(linux.symlink(target_z, link_z));
        if (e != .SUCCESS) {
            cx.errPrint("ln: failed to create symbolic link '{s}': {s}\n", .{ link_raw, describeErrno(e) });
            return 1;
        }
        return 0;
    }

    const target_resolved = cx.resolve(target_raw) catch return 1;
    defer cx.gpa.free(target_resolved);
    var target_buf: [4096]u8 = undefined;
    const target_z = std.fmt.bufPrintZ(&target_buf, "{s}", .{target_resolved}) catch return 1;
    const e = linux.errno(linux.link(target_z, link_z));
    if (e != .SUCCESS) {
        cx.errPrint("ln: failed to create hard link '{s}': {s}\n", .{ link_raw, describeErrno(e) });
        return 1;
    }
    return 0;
}

fn cmdChmod(cx: *Context, args: []const []const u8) u8 {
    var recursive = false;
    var mode_arg: ?[]const u8 = null;
    var targets: std.ArrayList([]const u8) = .empty;
    defer targets.deinit(cx.gpa);

    for (args) |arg| {
        if (mode_arg == null and (std.mem.eql(u8, arg, "-R") or std.mem.eql(u8, arg, "-r"))) {
            recursive = true;
        } else if (mode_arg == null) {
            mode_arg = arg;
        } else {
            targets.append(cx.gpa, arg) catch return 1;
        }
    }
    const spec = mode_arg orelse {
        cx.errPrint("chmod: missing operand\n", .{});
        return 1;
    };
    if (targets.items.len == 0) {
        cx.errPrint("chmod: missing file operand\n", .{});
        return 1;
    }

    var status: u8 = 0;
    for (targets.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        if (!chmodPath(cx, raw, resolved, spec, recursive)) status = 1;
    }
    return status;
}

fn chmodPath(cx: *Context, label: []const u8, full_path: []const u8, spec: []const u8, recursive: bool) bool {
    const st = statPath(full_path, true) catch |e| {
        cx.errPrint("chmod: cannot access '{s}': {s}\n", .{ label, describeErrno(e) });
        return false;
    };
    const new_mode = parseModeSpec(spec, st.mode & 0o7777) orelse {
        cx.errPrint("chmod: invalid mode: '{s}'\n", .{spec});
        return false;
    };
    var buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{full_path}) catch return false;
    const e = linux.errno(linux.chmod(z, new_mode));
    if (e != .SUCCESS) {
        cx.errPrint("chmod: changing permissions of '{s}': {s}\n", .{ label, describeErrno(e) });
        return false;
    }
    if (!recursive or !st.isDir()) return true;

    const rc = linux.open(z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return false;
    const fd: linux.fd_t = @intCast(rc);

    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| cx.gpa.free(n);
        names.deinit(cx.gpa);
    }
    var dents: [4096]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &dents, dents.len);
        if (linux.errno(n) != .SUCCESS or n == 0) break;
        var at: usize = 0;
        while (at < n) {
            const reclen = std.mem.readInt(u16, dents[at + 16 ..][0..2], .little);
            const name = std.mem.sliceTo(dents[at + 19 .. at + reclen], 0);
            at += reclen;
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            const duped = cx.gpa.dupe(u8, name) catch continue;
            names.append(cx.gpa, duped) catch {
                cx.gpa.free(duped);
                continue;
            };
        }
    }
    sys.close(fd);

    var ok = true;
    for (names.items) |name| {
        const child_full = joinPath(cx.gpa, full_path, name) catch continue;
        defer cx.gpa.free(child_full);
        const child_label = joinPath(cx.gpa, label, name) catch continue;
        defer cx.gpa.free(child_label);
        if (!chmodPath(cx, child_label, child_full, spec, true)) ok = false;
    }
    return ok;
}

fn parseModeSpec(spec: []const u8, current: u16) ?u16 {
    if (spec.len == 0) return null;
    if (std.fmt.parseInt(u16, spec, 8)) |octal| {
        if (octal <= 0o7777) return octal;
        return null;
    } else |_| {}

    var mode = current;
    var clauses = std.mem.splitScalar(u8, spec, ',');
    while (clauses.next()) |clause| {
        if (clause.len == 0) return null;
        var i: usize = 0;
        var who: u16 = 0;
        while (i < clause.len) : (i += 1) switch (clause[i]) {
            'u' => who |= 0o700,
            'g' => who |= 0o070,
            'o' => who |= 0o007,
            'a' => who |= 0o777,
            else => break,
        };
        if (who == 0) who = 0o777;
        if (i >= clause.len) return null;
        const op = clause[i];
        if (op != '+' and op != '-' and op != '=') return null;
        i += 1;
        var perm: u16 = 0;
        while (i < clause.len) : (i += 1) switch (clause[i]) {
            'r' => perm |= 0o444,
            'w' => perm |= 0o222,
            'x' => perm |= 0o111,
            'X' => if (current & 0o111 != 0) {
                perm |= 0o111;
            },
            else => return null,
        };
        const bits = perm & who;
        switch (op) {
            '+' => mode |= bits,
            '-' => mode &= ~bits,
            '=' => mode = (mode & ~who) | bits,
            else => unreachable,
        }
    }
    return mode;
}

// --- stat, readlink, file ------------------------------------------------------

fn cmdStat(cx: *Context, args: []const []const u8) u8 {
    if (args.len == 0) {
        cx.errPrint("stat: missing operand\n", .{});
        return 1;
    }
    var status: u8 = 0;
    const now = sys.realtimeSec();
    for (args) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        const st = statPath(resolved, false) catch |e| {
            cx.errPrint("stat: cannot stat '{s}': {s}\n", .{ raw, describeErrno(e) });
            status = 1;
            continue;
        };
        var mode_buf: [10]u8 = undefined;
        const mode_str = formatMode(&mode_buf, st.mode);
        const kind = switch (st.mode & linux.S.IFMT) {
            linux.S.IFDIR => "directory",
            linux.S.IFREG => if (st.size == 0) "regular empty file" else "regular file",
            linux.S.IFLNK => "symbolic link",
            linux.S.IFCHR => "character special file",
            linux.S.IFBLK => "block special file",
            linux.S.IFIFO => "fifo",
            linux.S.IFSOCK => "socket",
            else => "other",
        };
        var time_buf: [32]u8 = undefined;
        const when = locale.formatWhen(&time_buf, st.mtime, now);
        if (st.isLnk()) {
            var z_buf: [4096]u8 = undefined;
            var t_buf: [4096]u8 = undefined;
            const target = if (std.fmt.bufPrintZ(&z_buf, "{s}", .{resolved})) |z| blk: {
                const rc = linux.readlink(z, &t_buf, t_buf.len);
                break :blk if (linux.errno(rc) == .SUCCESS) t_buf[0..rc] else "";
            } else |_| "";
            cx.print("  File: {s} -> {s}\n", .{ raw, target });
        } else {
            cx.print("  File: {s}\n", .{raw});
        }
        cx.print("  Size: {d:<12} Type: {s}\n", .{ st.size, kind });
        cx.print("Access: ({o:0>4}/{s})  Uid: {d}  Gid: {d}\n", .{ st.mode & 0o7777, mode_str, st.uid, st.gid });
        cx.print("Device: {d}:{d:<10} Inode: {d:<10} Links: {d}\n", .{ st.dev_major, st.dev_minor, st.ino, st.nlink });
        cx.print("Modify: {s}\n", .{when});
    }
    return status;
}

fn cmdReadlink(cx: *Context, args: []const []const u8) u8 {
    var canonical = false;
    var targets: std.ArrayList([]const u8) = .empty;
    defer targets.deinit(cx.gpa);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-f")) {
            canonical = true;
        } else if (arg.len > 1 and arg[0] == '-') {
            cx.errPrint("readlink: invalid option '{s}'\n", .{arg});
            return 1;
        } else {
            targets.append(cx.gpa, arg) catch return 1;
        }
    }
    if (targets.items.len == 0) {
        cx.errPrint("readlink: missing operand\n", .{});
        return 1;
    }
    var status: u8 = 0;
    for (targets.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        var z_buf: [4096]u8 = undefined;
        var t_buf: [4096]u8 = undefined;
        const z = std.fmt.bufPrintZ(&z_buf, "{s}", .{resolved}) catch continue;
        const rc = linux.readlink(z, &t_buf, t_buf.len);
        if (linux.errno(rc) == .SUCCESS) {
            if (canonical and t_buf[0] != '/') {
                const dir = std.fs.path.dirname(resolved) orelse "/";
                const joined = joinPath(cx.gpa, dir, t_buf[0..rc]) catch continue;
                defer cx.gpa.free(joined);
                const norm = shell_mod.normalizePath(cx.gpa, joined) catch continue;
                defer cx.gpa.free(norm);
                cx.print("{s}\n", .{norm});
            } else {
                cx.print("{s}\n", .{t_buf[0..rc]});
            }
        } else if (canonical) {
            if (statZ(z, true)) |_| {
                cx.print("{s}\n", .{resolved});
            } else |_| {
                status = 1;
            }
        } else {
            status = 1;
        }
    }
    return status;
}

fn cmdFile(cx: *Context, args: []const []const u8) u8 {
    if (args.len == 0) {
        cx.errPrint("file: missing file operand\n", .{});
        return 1;
    }
    var status: u8 = 0;
    for (args) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        const st = statPath(resolved, false) catch |e| {
            cx.errPrint("{s}: cannot open ({s})\n", .{ raw, describeErrno(e) });
            status = 1;
            continue;
        };
        const desc: []const u8 = switch (st.mode & linux.S.IFMT) {
            linux.S.IFDIR => "directory",
            linux.S.IFLNK => "symbolic link",
            linux.S.IFCHR => "character special",
            linux.S.IFBLK => "block special",
            linux.S.IFIFO => "fifo (named pipe)",
            linux.S.IFSOCK => "socket",
            linux.S.IFREG => blk: {
                if (st.size == 0) break :blk "empty";
                var z_buf: [4096]u8 = undefined;
                var hdr_buf: [512]u8 = undefined;
                const z = std.fmt.bufPrintZ(&z_buf, "{s}", .{resolved}) catch break :blk "regular file";
                const sample = sys.readFile(z, &hdr_buf) orelse break :blk "regular file";
                break :blk sniffData(sample);
            },
            else => "special file",
        };
        cx.print("{s}: {s}\n", .{ raw, desc });
    }
    return status;
}

fn sniffData(data: []const u8) []const u8 {
    if (data.len == 0) return "empty";
    if (std.mem.startsWith(u8, data, "\x7fELF")) return "ELF executable";
    if (std.mem.startsWith(u8, data, "\x89PNG\r\n\x1a\n")) return "PNG image data";
    if (std.mem.startsWith(u8, data, "BM") and data.len >= 26) return "BMP image data";
    if (data.len >= 3 and data[0] == 'P' and (data[1] == '5' or data[1] == '6') and std.ascii.isWhitespace(data[2])) return "Netpbm image data";
    if (std.mem.startsWith(u8, data, "\xfd7zXZ\x00")) return "XZ compressed data";
    if (std.mem.startsWith(u8, data, "\x1f\x8b")) return "gzip compressed data";
    if (data.len >= 262 and std.mem.eql(u8, data[257..262], "ustar")) return "POSIX tar archive";
    if (std.mem.startsWith(u8, data, "070701")) return "ASCII cpio archive";
    if (std.mem.startsWith(u8, data, "\x00\x01\x00\x00") or std.mem.startsWith(u8, data, "OTTO")) return "OpenType font data";
    if (std.mem.startsWith(u8, data, "#!")) return "script text executable";
    for (data) |b| if (b == 0) return "data";
    return if (std.unicode.utf8ValidateSlice(data)) "UTF-8 text" else "data";
}

// --- Text processing (cat, head, tail, wc, grep, find, sort, uniq, cut, tr, tee, echo, sha256sum, hexdump) ---

/// Reads either `stdin` (when `files` is empty or `file` is "-") or the
/// file at `file`.
fn readInput(cx: *Context, cmd_name: []const u8, file: ?[]const u8) ?[]u8 {
    const f = file orelse return cx.gpa.dupe(u8, cx.stdin) catch null;
    if (std.mem.eql(u8, f, "-")) return cx.gpa.dupe(u8, cx.stdin) catch null;
    const resolved = cx.resolve(f) catch return null;
    defer cx.gpa.free(resolved);
    return readFileAll(cx.gpa, resolved) catch |e| {
        cx.errPrint("{s}: {s}: {s}\n", .{ cmd_name, f, describeErrno(e) });
        return null;
    };
}

fn cmdCat(cx: *Context, args: []const []const u8) u8 {
    var number_lines = false;
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(cx.gpa);

    var flags_done = false;
    for (args) |arg| {
        if (!flags_done and std.mem.eql(u8, arg, "--")) {
            flags_done = true;
            continue;
        }
        if (!flags_done and arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'n' => number_lines = true,
                else => {
                    cx.errPrint("cat: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            files.append(cx.gpa, arg) catch return 1;
        }
    }

    var status: u8 = 0;
    var line_no: usize = 1;
    const sources: []const ?[]const u8 = if (files.items.len == 0) &.{null} else blk: {
        const list = cx.gpa.alloc(?[]const u8, files.items.len) catch return 1;
        for (files.items, list) |f, *dst| dst.* = f;
        break :blk list;
    };
    defer if (files.items.len > 0) cx.gpa.free(sources);

    for (sources) |src| {
        const data = readInput(cx, "cat", src) orelse {
            status = 1;
            continue;
        };
        defer cx.gpa.free(data);
        if (!number_lines) {
            cx.write(data);
            continue;
        }
        var start: usize = 0;
        while (start < data.len) {
            const nl = std.mem.indexOfScalarPos(u8, data, start, '\n');
            const end = if (nl) |i| i + 1 else data.len;
            cx.print("{d:>6}  {s}", .{ line_no, data[start..end] });
            if (nl == null) cx.write("\n");
            line_no += 1;
            start = end;
        }
    }
    return status;
}

fn cmdHead(cx: *Context, args: []const []const u8) u8 {
    return headOrTail(cx, args, false);
}

fn cmdTail(cx: *Context, args: []const []const u8) u8 {
    return headOrTail(cx, args, true);
}

fn headOrTail(cx: *Context, args: []const []const u8, is_tail: bool) u8 {
    const cmd_name = if (is_tail) "tail" else "head";
    var count: usize = 10;
    var by_bytes = false;
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(cx.gpa);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "-c")) {
            by_bytes = arg[1] == 'c';
            i += 1;
            if (i >= args.len) {
                cx.errPrint("{s}: option requires an argument -- '{s}'\n", .{ cmd_name, arg });
                return 1;
            }
            count = std.fmt.parseInt(usize, args[i], 10) catch {
                cx.errPrint("{s}: invalid count: '{s}'\n", .{ cmd_name, args[i] });
                return 1;
            };
        } else if (arg.len > 1 and arg[0] == '-' and std.ascii.isDigit(arg[1])) {
            count = std.fmt.parseInt(usize, arg[1..], 10) catch {
                cx.errPrint("{s}: invalid count: '{s}'\n", .{ cmd_name, arg[1..] });
                return 1;
            };
        } else if (arg.len > 1 and arg[0] == '-') {
            cx.errPrint("{s}: invalid option '{s}'\n", .{ cmd_name, arg });
            return 1;
        } else {
            files.append(cx.gpa, arg) catch return 1;
        }
    }

    var status: u8 = 0;
    const multi = files.items.len > 1;
    const num = @max(files.items.len, 1);
    for (0..num) |idx| {
        const f: ?[]const u8 = if (files.items.len > 0) files.items[idx] else null;
        const data = readInput(cx, cmd_name, f) orelse {
            status = 1;
            continue;
        };
        defer cx.gpa.free(data);
        if (multi) {
            if (idx > 0) cx.write("\n");
            cx.print("==> {s} <==\n", .{f.?});
        }
        if (by_bytes) {
            if (is_tail) {
                cx.write(data[data.len -| count..]);
            } else {
                cx.write(data[0..@min(count, data.len)]);
            }
            continue;
        }
        if (!is_tail) {
            var pos: usize = 0;
            var lines_left = count;
            while (pos < data.len and lines_left > 0) : (lines_left -= 1) {
                const nl = std.mem.indexOfScalarPos(u8, data, pos, '\n');
                pos = if (nl) |n| n + 1 else data.len;
            }
            cx.write(data[0..pos]);
        } else {
            if (count == 0) continue;
            var pos = data.len;
            if (pos > 0 and data[pos - 1] == '\n') pos -= 1;
            var lines_found: usize = 0;
            while (pos > 0) {
                if (data[pos - 1] == '\n') {
                    lines_found += 1;
                    if (lines_found == count) break;
                }
                pos -= 1;
            }
            cx.write(data[pos..]);
        }
    }
    return status;
}

fn cmdWc(cx: *Context, args: []const []const u8) u8 {
    var show_l = false;
    var show_w = false;
    var show_c = false;
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(cx.gpa);

    for (args) |arg| {
        if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'l' => show_l = true,
                'w' => show_w = true,
                'c', 'm' => show_c = true,
                else => {
                    cx.errPrint("wc: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            files.append(cx.gpa, arg) catch return 1;
        }
    }
    if (!show_l and !show_w and !show_c) {
        show_l = true;
        show_w = true;
        show_c = true;
    }

    var total_l: usize = 0;
    var total_w: usize = 0;
    var total_c: usize = 0;
    var status: u8 = 0;
    const num = @max(files.items.len, 1);

    for (0..num) |idx| {
        const f: ?[]const u8 = if (files.items.len > 0) files.items[idx] else null;
        const data = readInput(cx, "wc", f) orelse {
            status = 1;
            continue;
        };
        defer cx.gpa.free(data);

        var l: usize = 0;
        var w: usize = 0;
        var in_word = false;
        for (data) |b| {
            if (b == '\n') l += 1;
            if (std.ascii.isWhitespace(b)) {
                in_word = false;
            } else if (!in_word) {
                in_word = true;
                w += 1;
            }
        }
        const c = data.len;
        total_l += l;
        total_w += w;
        total_c += c;
        printWcRow(cx, show_l, show_w, show_c, l, w, c, f);
    }
    if (files.items.len > 1) {
        printWcRow(cx, show_l, show_w, show_c, total_l, total_w, total_c, "total");
    }
    return status;
}

fn printWcRow(cx: *Context, show_l: bool, show_w: bool, show_c: bool, l: usize, w: usize, c: usize, label: ?[]const u8) void {
    const single = (@as(u8, @intFromBool(show_l)) + @intFromBool(show_w) + @intFromBool(show_c)) == 1 and label == null;
    if (single) {
        const v = if (show_l) l else if (show_w) w else c;
        cx.print("{d}\n", .{v});
        return;
    }
    var first = true;
    if (show_l) {
        cx.print("{d:>7}", .{l});
        first = false;
    }
    if (show_w) {
        if (!first) cx.write(" ");
        cx.print("{d:>7}", .{w});
        first = false;
    }
    if (show_c) {
        if (!first) cx.write(" ");
        cx.print("{d:>7}", .{c});
    }
    if (label) |name| cx.print(" {s}", .{name});
    cx.write("\n");
}

// --- grep ----------------------------------------------------------------------

const GrepOptions = struct {
    ignore_case: bool = false,
    invert: bool = false,
    line_numbers: bool = false,
    count_only: bool = false,
    files_with_matches: bool = false,
    quiet: bool = false,
    recursive: bool = false,
};

fn cmdGrep(cx: *Context, args: []const []const u8) u8 {
    var opts: GrepOptions = .{};
    var pattern: ?[]const u8 = null;
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(cx.gpa);

    var flags_done = false;
    for (args) |arg| {
        if (!flags_done and std.mem.eql(u8, arg, "--")) {
            flags_done = true;
            continue;
        }
        if (!flags_done and arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'i' => opts.ignore_case = true,
                'v' => opts.invert = true,
                'n' => opts.line_numbers = true,
                'c' => opts.count_only = true,
                'l' => opts.files_with_matches = true,
                'q' => opts.quiet = true,
                'r', 'R' => opts.recursive = true,
                'F', 'E' => {},
                else => {
                    cx.errPrint("grep: invalid option -- '{c}'\n", .{ch});
                    return 2;
                },
            };
        } else if (pattern == null) {
            pattern = arg;
        } else {
            files.append(cx.gpa, arg) catch return 2;
        }
    }
    const pat = pattern orelse {
        cx.errPrint("grep: missing pattern\n", .{});
        return 2;
    };

    if (files.items.len == 0 and opts.recursive) {
        files.append(cx.gpa, ".") catch return 2;
    }

    if (files.items.len == 0) {
        const matched = grepBuffer(cx, pat, cx.stdin, null, opts);
        return if (matched) 0 else 1;
    }

    const show_filename = files.items.len > 1 or opts.recursive;
    var any_matched = false;
    var had_error = false;
    for (files.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        if (grepPath(cx, pat, raw, resolved, opts, show_filename, &had_error)) any_matched = true;
    }
    if (had_error and !any_matched) return 2;
    return if (any_matched) 0 else 1;
}

fn grepPath(cx: *Context, pat: []const u8, label: []const u8, full_path: []const u8, opts: GrepOptions, show_filename: bool, had_error: *bool) bool {
    const st = statPath(full_path, true) catch |e| {
        cx.errPrint("grep: {s}: {s}\n", .{ label, describeErrno(e) });
        had_error.* = true;
        return false;
    };
    if (st.isDir()) {
        if (!opts.recursive) {
            cx.errPrint("grep: {s}: Is a directory\n", .{label});
            had_error.* = true;
            return false;
        }
        var z_buf: [4096]u8 = undefined;
        const z = std.fmt.bufPrintZ(&z_buf, "{s}", .{full_path}) catch return false;
        const rc = linux.open(z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
        if (linux.errno(rc) != .SUCCESS) return false;
        const fd: linux.fd_t = @intCast(rc);

        var names: std.ArrayList([]u8) = .empty;
        defer {
            for (names.items) |n| cx.gpa.free(n);
            names.deinit(cx.gpa);
        }
        var dents: [4096]u8 align(8) = undefined;
        while (true) {
            const n = linux.getdents64(fd, &dents, dents.len);
            if (linux.errno(n) != .SUCCESS or n == 0) break;
            var at: usize = 0;
            while (at < n) {
                const reclen = std.mem.readInt(u16, dents[at + 16 ..][0..2], .little);
                const name = std.mem.sliceTo(dents[at + 19 .. at + reclen], 0);
                at += reclen;
                if (name.len == 0 or name[0] == '.') continue;
                const duped = cx.gpa.dupe(u8, name) catch continue;
                names.append(cx.gpa, duped) catch {
                    cx.gpa.free(duped);
                    continue;
                };
            }
        }
        sys.close(fd);
        std.mem.sort([]u8, names.items, {}, struct {
            fn less(_: void, a: []u8, b: []u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.less);

        var any = false;
        for (names.items) |name| {
            const child_full = joinPath(cx.gpa, full_path, name) catch continue;
            defer cx.gpa.free(child_full);
            const child_label = if (std.mem.eql(u8, label, "."))
                cx.gpa.dupe(u8, name) catch continue
            else
                joinPath(cx.gpa, label, name) catch continue;
            defer cx.gpa.free(child_label);
            if (grepPath(cx, pat, child_label, child_full, opts, true, had_error)) any = true;
        }
        return any;
    }
    const data = readFileAll(cx.gpa, full_path) catch |e| {
        cx.errPrint("grep: {s}: {s}\n", .{ label, describeErrno(e) });
        had_error.* = true;
        return false;
    };
    defer cx.gpa.free(data);
    return grepBuffer(cx, pat, data, if (show_filename) label else null, opts);
}

fn grepBuffer(cx: *Context, pat: []const u8, data: []const u8, filename: ?[]const u8, opts: GrepOptions) bool {
    var matches: usize = 0;
    var line_no: usize = 0;
    var start: usize = 0;
    while (start <= data.len) {
        if (start == data.len and data.len > 0 and data[data.len - 1] == '\n') break;
        if (data.len == 0) break;
        const nl = std.mem.indexOfScalarPos(u8, data, start, '\n');
        const end = nl orelse data.len;
        const line = std.mem.trimEnd(u8, data[start..end], "\r");
        line_no += 1;

        const found = if (opts.ignore_case)
            std.ascii.indexOfIgnoreCase(line, pat) != null
        else
            std.mem.indexOf(u8, line, pat) != null;
        const hit = if (opts.invert) !found else found;
        if (hit) {
            matches += 1;
            if (opts.quiet) return true;
            if (opts.files_with_matches) {
                if (filename) |f| cx.print("{s}\n", .{f});
                return true;
            }
            if (!opts.count_only) {
                if (filename) |f| cx.print("{s}:", .{f});
                if (opts.line_numbers) cx.print("{d}:", .{line_no});
                cx.print("{s}\n", .{line});
            }
        }
        if (nl) |n| start = n + 1 else break;
    }
    if (opts.count_only and !opts.quiet) {
        if (filename) |f| cx.print("{s}:", .{f});
        cx.print("{d}\n", .{matches});
    }
    return matches > 0;
}

// --- find ----------------------------------------------------------------------

const FindFilter = struct {
    name: ?[]const u8 = null,
    iname: ?[]const u8 = null,
    kind: ?u8 = null, // 'f', 'd', 'l'
    max_depth: ?usize = null,
};

fn cmdFind(cx: *Context, args: []const []const u8) u8 {
    var filter: FindFilter = .{};
    var roots: std.ArrayList([]const u8) = .empty;
    defer roots.deinit(cx.gpa);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-name") or std.mem.eql(u8, arg, "-iname")) {
            i += 1;
            if (i >= args.len) {
                cx.errPrint("find: missing argument to '{s}'\n", .{arg});
                return 1;
            }
            if (arg[1] == 'i') filter.iname = args[i] else filter.name = args[i];
        } else if (std.mem.eql(u8, arg, "-type")) {
            i += 1;
            if (i >= args.len or args[i].len != 1) {
                cx.errPrint("find: -type requires f, d, or l\n", .{});
                return 1;
            }
            filter.kind = args[i][0];
        } else if (std.mem.eql(u8, arg, "-maxdepth")) {
            i += 1;
            if (i >= args.len) {
                cx.errPrint("find: missing argument to '-maxdepth'\n", .{});
                return 1;
            }
            filter.max_depth = std.fmt.parseInt(usize, args[i], 10) catch {
                cx.errPrint("find: invalid maxdepth '{s}'\n", .{args[i]});
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "-")) {
            cx.errPrint("find: unknown predicate '{s}'\n", .{arg});
            return 1;
        } else {
            roots.append(cx.gpa, arg) catch return 1;
        }
    }
    if (roots.items.len == 0) roots.append(cx.gpa, ".") catch return 1;

    var status: u8 = 0;
    for (roots.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        if (!findWalk(cx, raw, resolved, filter, 0)) status = 1;
    }
    return status;
}

fn findWalk(cx: *Context, label: []const u8, full_path: []const u8, filter: FindFilter, depth: usize) bool {
    const st = statPath(full_path, false) catch |e| {
        cx.errPrint("find: '{s}': {s}\n", .{ label, describeErrno(e) });
        return false;
    };
    const base = std.fs.path.basename(full_path);
    if (findMatches(base, st, filter)) cx.print("{s}\n", .{label});

    if (!st.isDir()) return true;
    if (filter.max_depth) |m| if (depth >= m) return true;

    var z_buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintZ(&z_buf, "{s}", .{full_path}) catch return false;
    const rc = linux.open(z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return false;
    const fd: linux.fd_t = @intCast(rc);

    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| cx.gpa.free(n);
        names.deinit(cx.gpa);
    }
    var dents: [4096]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &dents, dents.len);
        if (linux.errno(n) != .SUCCESS or n == 0) break;
        var at: usize = 0;
        while (at < n) {
            const reclen = std.mem.readInt(u16, dents[at + 16 ..][0..2], .little);
            const name = std.mem.sliceTo(dents[at + 19 .. at + reclen], 0);
            at += reclen;
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            const duped = cx.gpa.dupe(u8, name) catch continue;
            names.append(cx.gpa, duped) catch {
                cx.gpa.free(duped);
                continue;
            };
        }
    }
    sys.close(fd);
    std.mem.sort([]u8, names.items, {}, struct {
        fn less(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);

    var ok = true;
    for (names.items) |name| {
        const child_full = joinPath(cx.gpa, full_path, name) catch continue;
        defer cx.gpa.free(child_full);
        const child_label = joinPath(cx.gpa, label, name) catch continue;
        defer cx.gpa.free(child_label);
        if (!findWalk(cx, child_label, child_full, filter, depth + 1)) ok = false;
    }
    return ok;
}

fn findMatches(base: []const u8, st: StatInfo, filter: FindFilter) bool {
    if (filter.kind) |k| {
        const ok = switch (k) {
            'f' => st.isReg(),
            'd' => st.isDir(),
            'l' => st.isLnk(),
            else => false,
        };
        if (!ok) return false;
    }
    if (filter.name) |pat| if (!globMatch(pat, base, false)) return false;
    if (filter.iname) |pat| if (!globMatch(pat, base, true)) return false;
    return true;
}

// --- sort, uniq, cut, tr, tee, echo, sha256sum, hexdump ------------------------

fn cmdSort(cx: *Context, args: []const []const u8) u8 {
    var reverse = false;
    var numeric = false;
    var unique = false;
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(cx.gpa);

    for (args) |arg| {
        if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'r' => reverse = true,
                'n' => numeric = true,
                'u' => unique = true,
                else => {
                    cx.errPrint("sort: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            files.append(cx.gpa, arg) catch return 1;
        }
    }

    var all: std.ArrayList(u8) = .empty;
    defer all.deinit(cx.gpa);
    var status: u8 = 0;
    const num = @max(files.items.len, 1);
    for (0..num) |idx| {
        const f: ?[]const u8 = if (files.items.len > 0) files.items[idx] else null;
        const data = readInput(cx, "sort", f) orelse {
            status = 1;
            continue;
        };
        defer cx.gpa.free(data);
        all.appendSlice(cx.gpa, data) catch return 1;
        if (all.items.len > 0 and all.items[all.items.len - 1] != '\n') all.append(cx.gpa, '\n') catch return 1;
    }

    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(cx.gpa);
    var start: usize = 0;
    while (start < all.items.len) {
        const nl = std.mem.indexOfScalarPos(u8, all.items, start, '\n') orelse all.items.len;
        lines.append(cx.gpa, all.items[start..nl]) catch return 1;
        start = nl + 1;
    }

    const SortCtx = struct { reverse: bool, numeric: bool };
    std.mem.sort([]const u8, lines.items, SortCtx{ .reverse = reverse, .numeric = numeric }, struct {
        fn less(s: SortCtx, a: []const u8, b: []const u8) bool {
            const cmp = if (s.numeric) blk: {
                const na = parseLeadingNumber(a);
                const nb = parseLeadingNumber(b);
                break :blk if (na != nb) na < nb else std.mem.lessThan(u8, a, b);
            } else std.mem.lessThan(u8, a, b);
            return if (s.reverse) !cmp else cmp;
        }
    }.less);

    for (lines.items, 0..) |line, i| {
        if (unique and i > 0 and std.mem.eql(u8, line, lines.items[i - 1])) continue;
        cx.print("{s}\n", .{line});
    }
    return status;
}

fn parseLeadingNumber(s: []const u8) i64 {
    const trimmed = std.mem.trimStart(u8, s, " \t");
    var end: usize = 0;
    if (end < trimmed.len and (trimmed[end] == '-' or trimmed[end] == '+')) end += 1;
    while (end < trimmed.len and std.ascii.isDigit(trimmed[end])) end += 1;
    return std.fmt.parseInt(i64, trimmed[0..end], 10) catch 0;
}

fn cmdUniq(cx: *Context, args: []const []const u8) u8 {
    var show_count = false;
    var only_dup = false;
    var only_uniq = false;
    var ignore_case = false;
    var file: ?[]const u8 = null;

    for (args) |arg| {
        if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'c' => show_count = true,
                'd' => only_dup = true,
                'u' => only_uniq = true,
                'i' => ignore_case = true,
                else => {
                    cx.errPrint("uniq: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else if (file == null) {
            file = arg;
        }
    }
    const data = readInput(cx, "uniq", file) orelse return 1;
    defer cx.gpa.free(data);

    var prev: ?[]const u8 = null;
    var count: usize = 0;
    var start: usize = 0;
    while (start < data.len) {
        const nl = std.mem.indexOfScalarPos(u8, data, start, '\n') orelse data.len;
        const line = data[start..nl];
        start = nl + 1;
        if (prev) |p| {
            const same = if (ignore_case) std.ascii.eqlIgnoreCase(p, line) else std.mem.eql(u8, p, line);
            if (same) {
                count += 1;
                continue;
            }
            emitUniq(cx, p, count, show_count, only_dup, only_uniq);
        }
        prev = line;
        count = 1;
    }
    if (prev) |p| emitUniq(cx, p, count, show_count, only_dup, only_uniq);
    return 0;
}

fn emitUniq(cx: *Context, line: []const u8, count: usize, show_count: bool, only_dup: bool, only_uniq: bool) void {
    if (only_dup and count < 2) return;
    if (only_uniq and count != 1) return;
    if (show_count) {
        cx.print("{d:>7} {s}\n", .{ count, line });
    } else {
        cx.print("{s}\n", .{line});
    }
}

fn cmdCut(cx: *Context, args: []const []const u8) u8 {
    var delim: u8 = '\t';
    var spec: ?[]const u8 = null;
    var by_chars = false;
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(cx.gpa);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-d")) {
            i += 1;
            if (i >= args.len or args[i].len == 0) {
                cx.errPrint("cut: -d requires a delimiter\n", .{});
                return 1;
            }
            delim = args[i][0];
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "-c")) {
            by_chars = arg[1] == 'c';
            i += 1;
            if (i >= args.len) {
                cx.errPrint("cut: {s} requires a list\n", .{arg});
                return 1;
            }
            spec = args[i];
        } else if (arg.len > 1 and arg[0] == '-') {
            cx.errPrint("cut: invalid option '{s}'\n", .{arg});
            return 1;
        } else {
            files.append(cx.gpa, arg) catch return 1;
        }
    }
    const list_spec = spec orelse {
        cx.errPrint("cut: you must specify a list of fields (-f) or characters (-c)\n", .{});
        return 1;
    };

    var status: u8 = 0;
    const num = @max(files.items.len, 1);
    for (0..num) |idx| {
        const f: ?[]const u8 = if (files.items.len > 0) files.items[idx] else null;
        const data = readInput(cx, "cut", f) orelse {
            status = 1;
            continue;
        };
        defer cx.gpa.free(data);

        var start: usize = 0;
        while (start < data.len) {
            const nl = std.mem.indexOfScalarPos(u8, data, start, '\n') orelse data.len;
            const line = data[start..nl];
            start = nl + 1;
            if (by_chars) {
                for (line, 1..) |ch, pos| if (inCutList(list_spec, pos)) cx.print("{c}", .{ch});
                cx.write("\n");
            } else {
                if (std.mem.indexOfScalar(u8, line, delim) == null) {
                    cx.print("{s}\n", .{line});
                    continue;
                }
                var parts = std.mem.splitScalar(u8, line, delim);
                var field_idx: usize = 1;
                var first_out = true;
                while (parts.next()) |part| : (field_idx += 1) {
                    if (inCutList(list_spec, field_idx)) {
                        if (!first_out) cx.print("{c}", .{delim});
                        cx.write(part);
                        first_out = false;
                    }
                }
                cx.write("\n");
            }
        }
    }
    return status;
}

fn inCutList(spec: []const u8, idx: usize) bool {
    var parts = std.mem.splitScalar(u8, spec, ',');
    while (parts.next()) |item| {
        if (std.mem.indexOfScalar(u8, item, '-')) |dash| {
            const lo = if (dash == 0) 1 else std.fmt.parseInt(usize, item[0..dash], 10) catch continue;
            const hi = if (dash + 1 == item.len) std.math.maxInt(usize) else std.fmt.parseInt(usize, item[dash + 1 ..], 10) catch continue;
            if (idx >= lo and idx <= hi) return true;
        } else {
            const v = std.fmt.parseInt(usize, item, 10) catch continue;
            if (idx == v) return true;
        }
    }
    return false;
}

fn cmdTr(cx: *Context, args: []const []const u8) u8 {
    var delete = false;
    var sets: std.ArrayList([]const u8) = .empty;
    defer sets.deinit(cx.gpa);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-d")) {
            delete = true;
        } else if (arg.len > 1 and arg[0] == '-') {
            cx.errPrint("tr: invalid option '{s}'\n", .{arg});
            return 1;
        } else {
            sets.append(cx.gpa, arg) catch return 1;
        }
    }
    if (sets.items.len == 0 or (!delete and sets.items.len < 2)) {
        cx.errPrint("tr: missing operand\n", .{});
        return 1;
    }
    var set1: std.ArrayList(u8) = .empty;
    defer set1.deinit(cx.gpa);
    expandTrSet(cx.gpa, sets.items[0], &set1);
    var set2: std.ArrayList(u8) = .empty;
    defer set2.deinit(cx.gpa);
    if (!delete) expandTrSet(cx.gpa, sets.items[1], &set2);

    for (cx.stdin) |b| {
        if (std.mem.indexOfScalar(u8, set1.items, b)) |pos| {
            if (delete) continue;
            if (set2.items.len > 0) {
                const repl = set2.items[@min(pos, set2.items.len - 1)];
                cx.print("{c}", .{repl});
            }
        } else {
            cx.print("{c}", .{b});
        }
    }
    return 0;
}

fn expandTrSet(gpa: std.mem.Allocator, raw: []const u8, out: *std.ArrayList(u8)) void {
    var unescaped: std.ArrayList(u8) = .empty;
    defer unescaped.deinit(gpa);
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            i += 1;
            const c: u8 = switch (raw[i]) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '\\' => '\\',
                else => raw[i],
            };
            unescaped.append(gpa, c) catch return;
        } else {
            unescaped.append(gpa, raw[i]) catch return;
        }
    }
    const s = unescaped.items;
    var j: usize = 0;
    while (j < s.len) {
        if (j + 2 < s.len and s[j + 1] == '-' and s[j] <= s[j + 2]) {
            var ch = s[j];
            while (true) : (ch += 1) {
                out.append(gpa, ch) catch return;
                if (ch == s[j + 2]) break;
            }
            j += 3;
        } else {
            out.append(gpa, s[j]) catch return;
            j += 1;
        }
    }
}

fn cmdTee(cx: *Context, args: []const []const u8) u8 {
    var append = false;
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(cx.gpa);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-a")) {
            append = true;
        } else if (arg.len > 1 and arg[0] == '-') {
            cx.errPrint("tee: invalid option '{s}'\n", .{arg});
            return 1;
        } else {
            files.append(cx.gpa, arg) catch return 1;
        }
    }
    cx.write(cx.stdin);
    var status: u8 = 0;
    for (files.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        writeFileAll(resolved, cx.stdin, append) catch |e| {
            cx.errPrint("tee: {s}: {s}\n", .{ raw, describeErrno(e) });
            status = 1;
        };
    }
    return status;
}

fn cmdEcho(cx: *Context, args: []const []const u8) u8 {
    var newline = true;
    var escapes = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len < 2 or arg[0] != '-') break;
        var valid = true;
        for (arg[1..]) |ch| if (ch != 'n' and ch != 'e' and ch != 'E') {
            valid = false;
            break;
        };
        if (!valid) break;
        for (arg[1..]) |ch| switch (ch) {
            'n' => newline = false,
            'e' => escapes = true,
            'E' => escapes = false,
            else => unreachable,
        };
    }
    for (args[i..], 0..) |arg, idx| {
        if (idx > 0) cx.write(" ");
        if (!escapes) {
            cx.write(arg);
            continue;
        }
        var j: usize = 0;
        while (j < arg.len) : (j += 1) {
            if (arg[j] == '\\' and j + 1 < arg.len) {
                j += 1;
                switch (arg[j]) {
                    'n' => cx.write("\n"),
                    't' => cx.write("\t"),
                    'r' => cx.write("\r"),
                    '\\' => cx.write("\\"),
                    '0' => cx.write("\x00"),
                    'c' => return 0,
                    else => cx.print("\\{c}", .{arg[j]}),
                }
            } else {
                cx.print("{c}", .{arg[j]});
            }
        }
    }
    if (newline) cx.write("\n");
    return 0;
}

fn cmdSha256sum(cx: *Context, args: []const []const u8) u8 {
    var status: u8 = 0;
    const num = @max(args.len, 1);
    for (0..num) |idx| {
        const f: ?[]const u8 = if (args.len > 0) args[idx] else null;
        const data = readInput(cx, "sha256sum", f) orelse {
            status = 1;
            continue;
        };
        defer cx.gpa.free(data);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
        cx.print("{x}  {s}\n", .{ &digest, f orelse "-" });
    }
    return status;
}

fn cmdHexdump(cx: *Context, args: []const []const u8) u8 {
    var max_len: ?usize = null;
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(cx.gpa);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-C")) {
            continue;
        } else if (std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) {
                cx.errPrint("hexdump: option requires an argument -- '-n'\n", .{});
                return 1;
            }
            max_len = std.fmt.parseInt(usize, args[i], 10) catch {
                cx.errPrint("hexdump: invalid length '{s}'\n", .{args[i]});
                return 1;
            };
        } else if (arg.len > 1 and arg[0] == '-') {
            cx.errPrint("hexdump: invalid option '{s}'\n", .{arg});
            return 1;
        } else {
            files.append(cx.gpa, arg) catch return 1;
        }
    }

    var status: u8 = 0;
    const num = @max(files.items.len, 1);
    for (0..num) |idx| {
        const f: ?[]const u8 = if (files.items.len > 0) files.items[idx] else null;
        const raw = readInput(cx, "hexdump", f) orelse {
            status = 1;
            continue;
        };
        defer cx.gpa.free(raw);
        const data = if (max_len) |m| raw[0..@min(m, raw.len)] else raw;
        var offset: usize = 0;
        while (offset < data.len) : (offset += 16) {
            const row = data[offset..@min(offset + 16, data.len)];
            cx.print("{x:0>8}  ", .{offset});
            for (0..16) |k| {
                if (k == 8) cx.write(" ");
                if (k < row.len) cx.print("{x:0>2} ", .{row[k]}) else cx.write("   ");
            }
            cx.write(" |");
            for (row) |b| cx.print("{c}", .{if (b >= 0x20 and b < 0x7f) b else '.'});
            cx.write("|\n");
        }
        cx.print("{x:0>8}\n", .{data.len});
    }
    return status;
}

// --- System & Environment commands ---------------------------------------------

fn cmdPs(cx: *Context, _: []const []const u8) u8 {
    const rc = linux.open("/proc", .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) {
        cx.errPrint("ps: cannot open /proc\n", .{});
        return 1;
    }
    const fd: linux.fd_t = @intCast(rc);
    defer sys.close(fd);

    const Proc = struct {
        pid: u32,
        state: u8,
        rss_kib: u64,
        cmd: []u8,
    };
    var procs: std.ArrayList(Proc) = .empty;
    defer {
        for (procs.items) |p| cx.gpa.free(p.cmd);
        procs.deinit(cx.gpa);
    }

    var dents: [4096]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &dents, dents.len);
        if (linux.errno(n) != .SUCCESS or n == 0) break;
        var at: usize = 0;
        while (at < n) {
            const reclen = std.mem.readInt(u16, dents[at + 16 ..][0..2], .little);
            const name = std.mem.sliceTo(dents[at + 19 .. at + reclen], 0);
            at += reclen;
            const pid = std.fmt.parseInt(u32, name, 10) catch continue;
            var path_buf: [64]u8 = undefined;
            var stat_buf: [1024]u8 = undefined;
            const stat_path = std.fmt.bufPrintZ(&path_buf, "/proc/{d}/stat", .{pid}) catch continue;
            const stat_text = sys.readFile(stat_path, &stat_buf) orelse continue;
            const open_paren = std.mem.indexOfScalar(u8, stat_text, '(') orelse continue;
            const close_paren = std.mem.lastIndexOfScalar(u8, stat_text, ')') orelse continue;
            if (close_paren + 2 >= stat_text.len) continue;
            const comm = stat_text[open_paren + 1 .. close_paren];
            const rest = stat_text[close_paren + 2 ..];
            var fields = std.mem.tokenizeScalar(u8, rest, ' ');
            const state_str = fields.next() orelse "S";
            var rss_pages: u64 = 0;
            for (0..21) |fi| {
                const tok = fields.next() orelse break;
                if (fi == 20) rss_pages = std.fmt.parseInt(u64, tok, 10) catch 0;
            }
            var cmd_buf: [256]u8 = undefined;
            const cmd_path = std.fmt.bufPrintZ(&path_buf, "/proc/{d}/cmdline", .{pid}) catch continue;
            const raw_cmd = sys.readFile(cmd_path, &cmd_buf) orelse "";
            const trimmed_cmd = std.mem.trimEnd(u8, raw_cmd, "\x00");
            const cmd_owned = if (trimmed_cmd.len > 0) blk: {
                const c = cx.gpa.dupe(u8, trimmed_cmd) catch continue;
                for (c) |*ch| if (ch.* == 0) {
                    ch.* = ' ';
                };
                break :blk c;
            } else std.fmt.allocPrint(cx.gpa, "[{s}]", .{comm}) catch continue;

            procs.append(cx.gpa, .{
                .pid = pid,
                .state = state_str[0],
                .rss_kib = rss_pages * 4,
                .cmd = cmd_owned,
            }) catch {
                cx.gpa.free(cmd_owned);
                continue;
            };
        }
    }

    std.mem.sort(Proc, procs.items, {}, struct {
        fn less(_: void, a: Proc, b: Proc) bool {
            return a.pid < b.pid;
        }
    }.less);

    cx.write("  PID STATE     RSS COMMAND\n");
    for (procs.items) |p| {
        var mem_buf: [24]u8 = undefined;
        const rss = formatHumanSize(&mem_buf, p.rss_kib * 1024);
        cx.print("{d:>5} {c}    {s:>8} {s}\n", .{ p.pid, p.state, rss, p.cmd });
    }
    return 0;
}

fn cmdKill(cx: *Context, args: []const []const u8) u8 {
    var sig: linux.SIG = .TERM;
    var pids: std.ArrayList(i32) = .empty;
    defer pids.deinit(cx.gpa);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-s")) {
            i += 1;
            if (i >= args.len) {
                cx.errPrint("kill: -s requires a signal\n", .{});
                return 1;
            }
            sig = parseSignal(args[i]) orelse {
                cx.errPrint("kill: invalid signal '{s}'\n", .{args[i]});
                return 1;
            };
        } else if (arg.len > 1 and arg[0] == '-') {
            sig = parseSignal(arg[1..]) orelse {
                cx.errPrint("kill: invalid signal '{s}'\n", .{arg[1..]});
                return 1;
            };
        } else {
            const pid = std.fmt.parseInt(i32, arg, 10) catch {
                cx.errPrint("kill: invalid pid '{s}'\n", .{arg});
                return 1;
            };
            pids.append(cx.gpa, pid) catch return 1;
        }
    }
    if (pids.items.len == 0) {
        cx.errPrint("kill: usage: kill [-s sig | -sig] <pid>...\n", .{});
        return 1;
    }
    var status: u8 = 0;
    for (pids.items) |pid| {
        const e = linux.errno(linux.kill(pid, sig));
        if (e != .SUCCESS) {
            cx.errPrint("kill: ({d}) - {s}\n", .{ pid, describeErrno(e) });
            status = 1;
        }
    }
    return status;
}

fn parseSignal(s_in: []const u8) ?linux.SIG {
    if (std.fmt.parseInt(u6, s_in, 10)) |num| return @enumFromInt(num) else |_| {}
    const s = if (std.ascii.startsWithIgnoreCase(s_in, "SIG")) s_in[3..] else s_in;
    if (std.ascii.eqlIgnoreCase(s, "HUP")) return .HUP;
    if (std.ascii.eqlIgnoreCase(s, "INT")) return .INT;
    if (std.ascii.eqlIgnoreCase(s, "QUIT")) return .QUIT;
    if (std.ascii.eqlIgnoreCase(s, "KILL")) return .KILL;
    if (std.ascii.eqlIgnoreCase(s, "TERM")) return .TERM;
    if (std.ascii.eqlIgnoreCase(s, "STOP")) return .STOP;
    if (std.ascii.eqlIgnoreCase(s, "CONT")) return .CONT;
    if (std.ascii.eqlIgnoreCase(s, "USR1")) return .USR1;
    if (std.ascii.eqlIgnoreCase(s, "USR2")) return .USR2;
    return null;
}

fn cmdDf(cx: *Context, args: []const []const u8) u8 {
    var human = false;
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(cx.gpa);

    for (args) |arg| {
        if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'h' => human = true,
                'k' => human = false,
                else => {
                    cx.errPrint("df: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            paths.append(cx.gpa, arg) catch return 1;
        }
    }

    cx.print("Filesystem      {s:>9} {s:>9} {s:>9} Use% Mounted on\n", .{
        if (human) "Size" else "1K-blocks",
        "Used",
        "Available",
    });

    if (paths.items.len > 0) {
        var status: u8 = 0;
        for (paths.items) |raw| {
            const resolved = cx.resolve(raw) catch continue;
            defer cx.gpa.free(resolved);
            var z_buf: [4096]u8 = undefined;
            const z = std.fmt.bufPrintZ(&z_buf, "{s}", .{resolved}) catch continue;
            const ds = sys.diskSpace(z) orelse {
                cx.errPrint("df: {s}: No such file or directory\n", .{raw});
                status = 1;
                continue;
            };
            printDfRow(cx, fsTypeName(ds.kind), ds.total, ds.free, resolved, human);
        }
        return status;
    }

    var mounts_buf: [8192]u8 = undefined;
    if (sys.readFile("/proc/mounts", &mounts_buf)) |mounts| {
        var lines = std.mem.tokenizeScalar(u8, mounts, '\n');
        while (lines.next()) |line| {
            var fields = std.mem.tokenizeScalar(u8, line, ' ');
            const dev = fields.next() orelse continue;
            const mnt = fields.next() orelse continue;
            const fstype = fields.next() orelse "";
            if (std.mem.eql(u8, fstype, "proc") or std.mem.eql(u8, fstype, "sysfs") or std.mem.eql(u8, fstype, "devpts") or std.mem.eql(u8, fstype, "cgroup2") or std.mem.eql(u8, fstype, "mqueue")) continue;
            var z_buf: [512]u8 = undefined;
            const z = std.fmt.bufPrintZ(&z_buf, "{s}", .{mnt}) catch continue;
            const ds = sys.diskSpace(z) orelse continue;
            if (ds.total == 0) continue;
            printDfRow(cx, dev, ds.total, ds.free, mnt, human);
        }
        return 0;
    }
    if (sys.diskSpace("/")) |ds| printDfRow(cx, "rootfs", ds.total, ds.free, "/", human);
    return 0;
}

fn fsTypeName(kind: u32) []const u8 {
    return switch (kind) {
        0xef53 => "ext4",
        0x4d44 => "vfat",
        0x01021994 => "tmpfs",
        0x858458f6 => "ramfs",
        else => "fs",
    };
}

fn printDfRow(cx: *Context, dev: []const u8, total: u64, free: u64, mnt: []const u8, human: bool) void {
    const used = total -| free;
    const pct: u64 = if (total > 0) (used * 100 + total / 2) / total else 0;
    var b1: [24]u8 = undefined;
    var b2: [24]u8 = undefined;
    var b3: [24]u8 = undefined;
    const s_total = if (human) formatHumanSize(&b1, total) else std.fmt.bufPrint(&b1, "{d}", .{total / 1024}) catch "";
    const s_used = if (human) formatHumanSize(&b2, used) else std.fmt.bufPrint(&b2, "{d}", .{used / 1024}) catch "";
    const s_free = if (human) formatHumanSize(&b3, free) else std.fmt.bufPrint(&b3, "{d}", .{free / 1024}) catch "";
    cx.print("{s:<15} {s:>9} {s:>9} {s:>9} {d:>3}% {s}\n", .{ dev, s_total, s_used, s_free, pct, mnt });
}

fn cmdDu(cx: *Context, args: []const []const u8) u8 {
    var summary = false;
    var human = false;
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(cx.gpa);

    for (args) |arg| {
        if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                's' => summary = true,
                'h' => human = true,
                else => {
                    cx.errPrint("du: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            paths.append(cx.gpa, arg) catch return 1;
        }
    }
    if (paths.items.len == 0) paths.append(cx.gpa, ".") catch return 1;

    var status: u8 = 0;
    for (paths.items) |raw| {
        const resolved = cx.resolve(raw) catch continue;
        defer cx.gpa.free(resolved);
        _ = duWalk(cx, raw, resolved, summary, true, human, &status);
    }
    return status;
}

fn duWalk(cx: *Context, label: []const u8, full_path: []const u8, summary: bool, is_top: bool, human: bool, status: *u8) u64 {
    const st = statPath(full_path, false) catch |e| {
        cx.errPrint("du: cannot access '{s}': {s}\n", .{ label, describeErrno(e) });
        status.* = 1;
        return 0;
    };
    if (!st.isDir()) {
        if (is_top) printDuLine(cx, st.size, label, human);
        return st.size;
    }

    var total: u64 = 0;
    var z_buf: [4096]u8 = undefined;
    if (std.fmt.bufPrintZ(&z_buf, "{s}", .{full_path})) |z| {
        const rc = linux.open(z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
        if (linux.errno(rc) == .SUCCESS) {
            const fd: linux.fd_t = @intCast(rc);
            var names: std.ArrayList([]u8) = .empty;
            defer {
                for (names.items) |n| cx.gpa.free(n);
                names.deinit(cx.gpa);
            }
            var dents: [4096]u8 align(8) = undefined;
            while (true) {
                const n = linux.getdents64(fd, &dents, dents.len);
                if (linux.errno(n) != .SUCCESS or n == 0) break;
                var at: usize = 0;
                while (at < n) {
                    const reclen = std.mem.readInt(u16, dents[at + 16 ..][0..2], .little);
                    const name = std.mem.sliceTo(dents[at + 19 .. at + reclen], 0);
                    at += reclen;
                    if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
                    const duped = cx.gpa.dupe(u8, name) catch continue;
                    names.append(cx.gpa, duped) catch {
                        cx.gpa.free(duped);
                        continue;
                    };
                }
            }
            sys.close(fd);
            for (names.items) |name| {
                const child_full = joinPath(cx.gpa, full_path, name) catch continue;
                defer cx.gpa.free(child_full);
                const child_label = joinPath(cx.gpa, label, name) catch continue;
                defer cx.gpa.free(child_label);
                total += duWalk(cx, child_label, child_full, summary, false, human, status);
            }
        }
    } else |_| {}
    if (!summary or is_top) {
        printDuLine(cx, total, label, human);
    }
    return total;
}

fn printDuLine(cx: *Context, bytes: u64, label: []const u8, human: bool) void {
    var buf: [24]u8 = undefined;
    if (human) {
        cx.print("{s:<8} {s}\n", .{ formatHumanSize(&buf, bytes), label });
    } else {
        cx.print("{d:<8} {s}\n", .{ (bytes + 1023) / 1024, label });
    }
}

fn cmdFree(cx: *Context, args: []const []const u8) u8 {
    const Unit = enum { kib, mib, bytes, human };
    var unit: Unit = .kib;
    for (args) |arg| {
        if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'h' => unit = .human,
                'm' => unit = .mib,
                'k' => unit = .kib,
                'b' => unit = .bytes,
                else => {
                    cx.errPrint("free: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        }
    }
    const mi = sys.meminfo() orelse sys.Meminfo{};
    const used = mi.total -| mi.available;
    const gpu_used = mi.cma_total -| mi.cma_free;

    const fmtVal = struct {
        fn f(buf: *[24]u8, bytes: u64, u: Unit) []const u8 {
            return switch (u) {
                .human => formatHumanSize(buf, bytes),
                .bytes => std.fmt.bufPrint(buf, "{d}", .{bytes}) catch "",
                .kib => std.fmt.bufPrint(buf, "{d}", .{bytes / 1024}) catch "",
                .mib => std.fmt.bufPrint(buf, "{d}", .{bytes / (1024 * 1024)}) catch "",
            };
        }
    }.f;

    var b1: [24]u8 = undefined;
    var b2: [24]u8 = undefined;
    var b3: [24]u8 = undefined;
    cx.write("          total        used   available\n");
    cx.print("Mem:  {s:>9}   {s:>9}   {s:>9}\n", .{ fmtVal(&b1, mi.total, unit), fmtVal(&b2, used, unit), fmtVal(&b3, mi.available, unit) });
    if (mi.cma_total > 0) {
        cx.print("GPU:  {s:>9}   {s:>9}   {s:>9}\n", .{ fmtVal(&b1, mi.cma_total, unit), fmtVal(&b2, gpu_used, unit), fmtVal(&b3, mi.cma_free, unit) });
    }
    return 0;
}

fn cmdUname(cx: *Context, args: []const []const u8) u8 {
    var s = false;
    var n = false;
    var r = false;
    var v = false;
    var m = false;

    for (args) |arg| {
        if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'a' => {
                    s = true;
                    n = true;
                    r = true;
                    v = true;
                    m = true;
                },
                's' => s = true,
                'n' => n = true,
                'r' => r = true,
                'v' => v = true,
                'm' => m = true,
                else => {
                    cx.errPrint("uname: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        }
    }
    if (!s and !n and !r and !v and !m) s = true;

    var uts: linux.utsname = undefined;
    if (linux.errno(linux.uname(&uts)) != .SUCCESS) return 1;

    var first = true;
    const parts = [_]struct { on: bool, val: []const u8 }{
        .{ .on = s, .val = std.mem.sliceTo(&uts.sysname, 0) },
        .{ .on = n, .val = std.mem.sliceTo(&uts.nodename, 0) },
        .{ .on = r, .val = std.mem.sliceTo(&uts.release, 0) },
        .{ .on = v, .val = std.mem.sliceTo(&uts.version, 0) },
        .{ .on = m, .val = std.mem.sliceTo(&uts.machine, 0) },
    };
    for (parts) |p| if (p.on) {
        if (!first) cx.write(" ");
        cx.write(p.val);
        first = false;
    };
    cx.write("\n");
    return 0;
}

fn cmdHostname(cx: *Context, _: []const []const u8) u8 {
    cx.print("{s}\n", .{cx.shell.hostnameSlice()});
    return 0;
}

fn cmdWhoami(cx: *Context, _: []const []const u8) u8 {
    cx.print("{s}\n", .{sys.user.name});
    return 0;
}

fn cmdId(cx: *Context, _: []const []const u8) u8 {
    cx.print("uid={d}({s}) gid={d}({s})\n", .{ sys.user.uid, sys.user.name, sys.user.gid, sys.user.name });
    return 0;
}

fn cmdDate(cx: *Context, _: []const []const u8) u8 {
    const secs = sys.realtimeSec();
    const day_secs = std.time.s_per_day;
    const day = @divFloor(@max(secs, 0), day_secs);
    const in_day: u32 = @intCast(@mod(@max(secs, 0), day_secs));
    const yd = (std.time.epoch.EpochDay{ .day = @intCast(day) }).calculateYearDay();
    const md = yd.calculateMonthDay();
    var date_buf: [64]u8 = undefined;
    const date_str = locale.formatLongDate(&date_buf, md.day_index + 1, @intFromEnum(md.month), yd.year);
    cx.print("{s} {d:0>2}:{d:0>2}:{d:0>2} UTC\n", .{ date_str, in_day / 3600, in_day / 60 % 60, in_day % 60 });
    return 0;
}

fn cmdUptime(cx: *Context, _: []const []const u8) u8 {
    var buf: [64]u8 = undefined;
    const text = sys.readFile("/proc/uptime", &buf) orelse {
        cx.errPrint("uptime: cannot read /proc/uptime\n", .{});
        return 1;
    };
    const end = std.mem.indexOfAny(u8, text, ". \n") orelse text.len;
    const s = std.fmt.parseInt(u64, text[0..end], 10) catch 0;
    const days = s / 86400;
    const hours = (s % 86400) / 3600;
    const mins = (s % 3600) / 60;
    const secs = s % 60;
    if (days > 0) {
        cx.print("up {d}d {d}h {d}m {d}s\n", .{ days, hours, mins, secs });
    } else if (hours > 0) {
        cx.print("up {d}h {d}m {d}s\n", .{ hours, mins, secs });
    } else if (mins > 0) {
        cx.print("up {d}m {d}s\n", .{ mins, secs });
    } else {
        cx.print("up {d}s\n", .{secs});
    }
    return 0;
}

fn cmdDmesg(cx: *Context, args: []const []const u8) u8 {
    var limit: ?usize = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-n") and i + 1 < args.len) {
            i += 1;
            limit = std.fmt.parseInt(usize, args[i], 10) catch null;
        }
    }
    const fd = sys.open(sys.log.path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true, .NONBLOCK = true }) catch |err| {
        cx.errPrint("dmesg: cannot read {s}: {s}\n", .{ sys.log.path, @errorName(err) });
        return 1;
    };
    defer sys.close(fd);

    var lines: std.ArrayList([]u8) = .empty;
    defer {
        for (lines.items) |l| cx.gpa.free(l);
        lines.deinit(cx.gpa);
    }

    var record: [8192]u8 = undefined;
    var line_buf: [512]u8 = undefined;
    while (true) {
        const rc = linux.read(fd, &record, record.len);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) break;
                const parsed = sys.log.parse(&line_buf, record[0..rc]) orelse continue;
                const s = parsed.usec / 1_000_000;
                const us = parsed.usec % 1_000_000;
                const formatted = std.fmt.allocPrint(cx.gpa, "[{d:>5}.{d:0>6}] {s}\n", .{ s, us, parsed.text }) catch break;
                lines.append(cx.gpa, formatted) catch {
                    cx.gpa.free(formatted);
                    break;
                };
            },
            .PIPE, .INTR => continue,
            else => break,
        }
    }
    const slice = if (limit) |m| lines.items[lines.items.len -| m..] else lines.items;
    for (slice) |l| cx.write(l);
    return 0;
}

fn cmdOpen(cx: *Context, args: []const []const u8) u8 {
    if (args.len == 0) {
        cx.errPrint("open: usage: open <app|file>\n", .{});
        return 1;
    }
    const target = args[0];
    // Try opening as a Dazzle app name first (e.g. "settings", "dazzle-settings", "files").
    if (std.mem.indexOfScalar(u8, target, '/') == null and std.mem.indexOfScalar(u8, target, '.') == null) {
        var app_buf: [64]u8 = undefined;
        const app_name = if (std.mem.startsWith(u8, target, "dazzle-"))
            target
        else
            std.fmt.bufPrint(&app_buf, "dazzle-{s}", .{target}) catch target;
        const what: ?[]const u8 = if (args.len > 1) args[1] else null;
        if (sys.shell.open(app_name, what)) return 0;
    }
    // Otherwise resolve as a file path and open with the text/plain handler.
    const resolved = cx.resolve(target) catch return 1;
    defer cx.gpa.free(resolved);
    var handler_buf: [256]u8 = undefined;
    const editor = sys.apps.handler(&handler_buf, sys.apps.text_plain) orelse {
        cx.errPrint("open: no app installed to open '{s}'\n", .{target});
        return 1;
    };
    var file_buf: [4096]u8 = undefined;
    const file_z = std.fmt.bufPrintZ(&file_buf, "{s}", .{resolved}) catch return 1;
    sys.apps.launch(editor, file_z, cx.shell.launch_env) catch |err| {
        cx.errPrint("open: cannot start {s}: {s}\n", .{ editor, @errorName(err) });
        return 1;
    };
    return 0;
}

fn cmdEnv(cx: *Context, _: []const []const u8) u8 {
    for (cx.shell.vars.items) |v| {
        if (v.exported) cx.print("{s}={s}\n", .{ v.name, v.value });
    }
    return 0;
}

fn cmdExport(cx: *Context, args: []const []const u8) u8 {
    if (args.len == 0) return cmdEnv(cx, args);
    var status: u8 = 0;
    for (args) |arg| {
        if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
            const name = arg[0..eq];
            const val = arg[eq + 1 ..];
            if (!shell_mod.validVarName(name)) {
                cx.errPrint("export: '{s}': not a valid identifier\n", .{name});
                status = 1;
                continue;
            }
            cx.shell.setVar(name, val, true) catch return 1;
        } else {
            if (!shell_mod.validVarName(arg)) {
                cx.errPrint("export: '{s}': not a valid identifier\n", .{arg});
                status = 1;
                continue;
            }
            if (cx.shell.getVar(arg)) |val| {
                const copy = cx.gpa.dupe(u8, val) catch return 1;
                defer cx.gpa.free(copy);
                cx.shell.setVar(arg, copy, true) catch return 1;
            } else {
                cx.shell.setVar(arg, "", true) catch return 1;
            }
        }
    }
    return status;
}

fn cmdUnset(cx: *Context, args: []const []const u8) u8 {
    for (args) |name| cx.shell.unsetVar(name);
    return 0;
}

fn cmdWhich(cx: *Context, args: []const []const u8) u8 {
    if (args.len == 0) return 1;
    var status: u8 = 0;
    for (args) |name| {
        if (find(name)) |c| {
            cx.print("{s}: shell built-in ({s})\n", .{ c.name, c.summary });
        } else {
            cx.errPrint("{s}: not found\n", .{name});
            status = 1;
        }
    }
    return status;
}

fn cmdHistory(cx: *Context, args: []const []const u8) u8 {
    if (args.len > 0 and std.mem.eql(u8, args[0], "-c")) {
        cx.shell.clearHistory();
        return 0;
    }
    for (cx.shell.history.items, 1..) |entry, idx| {
        cx.print("{d:>5}  {s}\n", .{ idx, entry });
    }
    return 0;
}

// --- Network commands (`ping`, `wget`) -----------------------------------------

fn cmdPing(cx: *Context, args: []const []const u8) u8 {
    var count: u32 = 4;
    var timeout_sec: u32 = 2;
    var payload_size: usize = 56;
    var quiet = false;
    var host: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-c") or (std.mem.startsWith(u8, arg, "-c") and arg.len > 2)) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) {
                    cx.errPrint("ping: option requires an argument -- 'c'\n", .{});
                    return 1;
                }
                break :blk args[i];
            };
            const parsed = std.fmt.parseInt(u32, val, 10) catch 0;
            if (parsed == 0 or parsed > 100) {
                cx.errPrint("ping: invalid count '{s}' (must be 1..100)\n", .{val});
                return 1;
            }
            count = parsed;
        } else if (std.mem.eql(u8, arg, "-W") or (std.mem.startsWith(u8, arg, "-W") and arg.len > 2)) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) {
                    cx.errPrint("ping: option requires an argument -- 'W'\n", .{});
                    return 1;
                }
                break :blk args[i];
            };
            const parsed = std.fmt.parseInt(u32, val, 10) catch 0;
            if (parsed == 0 or parsed > 30) {
                cx.errPrint("ping: invalid timeout '{s}' (must be 1..30)\n", .{val});
                return 1;
            }
            timeout_sec = parsed;
        } else if (std.mem.eql(u8, arg, "-s") or (std.mem.startsWith(u8, arg, "-s") and arg.len > 2)) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) {
                    cx.errPrint("ping: option requires an argument -- 's'\n", .{});
                    return 1;
                }
                break :blk args[i];
            };
            const parsed = std.fmt.parseInt(usize, val, 10) catch {
                cx.errPrint("ping: invalid packet size '{s}'\n", .{val});
                return 1;
            };
            if (parsed > 1472) {
                cx.errPrint("ping: packet size too large '{s}' (max 1472)\n", .{val});
                return 1;
            }
            payload_size = parsed;
        } else if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |ch| switch (ch) {
                'q' => quiet = true,
                '4' => {},
                else => {
                    cx.errPrint("ping: invalid option -- '{c}'\n", .{ch});
                    return 1;
                },
            };
        } else {
            host = arg;
        }
    }

    const target = host orelse {
        cx.errPrint("ping: usage: ping [-c count] [-W timeout] [-s size] [-q] <host>\n", .{});
        return 1;
    };

    const ip = resolveHostIp4(cx.shell.hostnameSlice(), target) orelse {
        cx.errPrint("ping: {s}: Name or service not known\n", .{target});
        return 2;
    };

    var ip_buf: [16]u8 = undefined;
    const ip_str = std.fmt.bufPrint(&ip_buf, "{d}.{d}.{d}.{d}", .{ ip[0], ip[1], ip[2], ip[3] }) catch "";
    cx.print("PING {s} ({s}) {d}({d}) bytes of data.\n", .{
        target,
        ip_str,
        payload_size,
        payload_size + 28,
    });

    const start_ns = sys.nowNs();
    const timeout_ms: i32 = @intCast(timeout_sec * 1000);
    const id: u16 = @truncate(@as(u32, @bitCast(linux.getpid())));

    var transmitted: u32 = 0;
    var received: u32 = 0;
    var min_us: u64 = std.math.maxInt(u64);
    var max_us: u64 = 0;
    var sum_us: u64 = 0;

    var seq: u16 = 1;
    while (seq <= count) : (seq += 1) {
        if (seq > 1) {
            const delay_ns: isize = if (ip[0] == 127) 20 * std.time.ns_per_ms else 200 * std.time.ns_per_ms;
            var ts: linux.timespec = .{ .sec = 0, .nsec = delay_ns };
            _ = linux.nanosleep(&ts, null);
        }
        transmitted += 1;
        const probe = pingProbeIp4(ip, id, seq, payload_size, timeout_ms) catch |err| {
            cx.errPrint("ping: sendto: {s}\n", .{@errorName(err)});
            return 1;
        };
        if (probe) |reply| {
            received += 1;
            const rtt_us: u64 = @max(reply.rtt_ns / 1000, 1);
            min_us = @min(min_us, rtt_us);
            max_us = @max(max_us, rtt_us);
            sum_us += rtt_us;
            if (!quiet) {
                cx.print("{d} bytes from {s}: icmp_seq={d} ttl={d} time={d}.{d:0>2} ms\n", .{
                    payload_size + 8,
                    ip_str,
                    seq,
                    reply.ttl,
                    rtt_us / 1000,
                    (rtt_us % 1000) / 10,
                });
            }
        }
    }

    const total_ms: u64 = (sys.nowNs() -| start_ns) / std.time.ns_per_ms;
    const loss_pct: u32 = if (transmitted > 0) ((transmitted - received) * 100) / transmitted else 0;
    cx.print("\n--- {s} ping statistics ---\n", .{target});
    cx.print("{d} packets transmitted, {d} received, {d}% packet loss, time {d}ms\n", .{
        transmitted,
        received,
        loss_pct,
        total_ms,
    });
    if (received > 0) {
        const avg_us = sum_us / received;
        cx.print("rtt min/avg/max = {d}.{d:0>2}/{d}.{d:0>2}/{d}.{d:0>2} ms\n", .{
            min_us / 1000,
            (min_us % 1000) / 10,
            avg_us / 1000,
            (avg_us % 1000) / 10,
            max_us / 1000,
            (max_us % 1000) / 10,
        });
        return 0;
    }
    return 1;
}

const PingReply = struct {
    rtt_ns: u64,
    ttl: u8,
};

fn pingProbeIp4(ip: sys.network.Ip4, id: u16, seq: u16, payload_size: usize, timeout_ms: i32) !?PingReply {
    // Try an unprivileged ICMP datagram socket first, then raw ICMP.
    var is_raw = false;
    var sock_rc = linux.socket(linux.AF.INET, linux.SOCK.DGRAM | linux.SOCK.CLOEXEC, linux.IPPROTO.ICMP);
    if (linux.errno(sock_rc) != .SUCCESS) {
        sock_rc = linux.socket(linux.AF.INET, linux.SOCK.RAW | linux.SOCK.CLOEXEC, linux.IPPROTO.ICMP);
        if (linux.errno(sock_rc) == .SUCCESS) {
            is_raw = true;
        } else {
            const e = linux.errno(sock_rc);
            if (e == .ACCES or e == .PERM or e == .PROTONOSUPPORT) {
                return tcpFallbackProbeIp4(ip, timeout_ms);
            }
            return error.NetworkError;
        }
    }
    const fd: linux.fd_t = @intCast(sock_rc);
    defer sys.close(fd);

    var pkt_buf: [8 + 1472]u8 = undefined;
    const pkt_len = 8 + @min(payload_size, 1472);
    pkt_buf[0] = 8; // ICMP Echo Request
    pkt_buf[1] = 0;
    pkt_buf[2] = 0;
    pkt_buf[3] = 0;
    std.mem.writeInt(u16, pkt_buf[4..6], id, .big);
    std.mem.writeInt(u16, pkt_buf[6..8], seq, .big);
    for (pkt_buf[8..pkt_len], 0..) |*b, idx| b.* = @truncate(0x10 + idx);
    const csum = icmpChecksum(pkt_buf[0..pkt_len]);
    std.mem.writeInt(u16, pkt_buf[2..4], csum, .big);

    const dest: linux.sockaddr.in = .{
        .port = 0,
        .addr = @bitCast(ip),
    };
    const t0 = sys.nowNs();
    const sent = linux.sendto(fd, &pkt_buf, pkt_len, 0, @ptrCast(&dest), @sizeOf(linux.sockaddr.in));
    if (linux.errno(sent) != .SUCCESS) return error.SendFailed;

    const deadline_ns = t0 + @as(u64, @intCast(timeout_ms)) * std.time.ns_per_ms;
    var reply_buf: [1600]u8 = undefined;
    while (true) {
        const now = sys.nowNs();
        const rem_ms: i32 = @intCast((deadline_ns -| now) / std.time.ns_per_ms);
        var pfd = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
        const prc = linux.poll(&pfd, 1, rem_ms);
        if (linux.errno(prc) == .INTR) continue;
        if (prc != 1) return null;

        const n = linux.recvfrom(fd, &reply_buf, reply_buf.len, 0, null, null);
        if (linux.errno(n) == .INTR) continue;
        if (linux.errno(n) != .SUCCESS or n < 8) return null;
        const rtt_ns = @max(sys.nowNs() -| t0, 1);

        var icmp_offset: usize = 0;
        var ttl: u8 = 64;
        if (is_raw and n >= 28 and (reply_buf[0] >> 4) == 4) {
            const ihl = @as(usize, reply_buf[0] & 0x0f) * 4;
            if (ihl >= 20 and ihl + 8 <= n) {
                ttl = reply_buf[8];
                icmp_offset = ihl;
            }
        }
        const icmp = reply_buf[icmp_offset..n];
        if (icmp.len >= 8 and icmp[0] == 0 and icmp[1] == 0) {
            const r_seq = std.mem.readInt(u16, icmp[6..8], .big);
            if (r_seq == seq) return .{ .rtt_ns = rtt_ns, .ttl = ttl };
        }
        if (sys.nowNs() >= deadline_ns) return null;
    }
}

/// Fallback probe when the kernel blocks unprivileged ICMP sockets (`ping_group_range`).
fn tcpFallbackProbeIp4(ip: sys.network.Ip4, timeout_ms: i32) !?PingReply {
    const rc = linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0);
    if (linux.errno(rc) != .SUCCESS) return error.NetworkError;
    const fd: linux.fd_t = @intCast(rc);
    defer sys.close(fd);

    const dest: linux.sockaddr.in = .{
        .port = std.mem.nativeToBig(u16, 80),
        .addr = @bitCast(ip),
    };
    const t0 = sys.nowNs();
    const crc = linux.connect(fd, @ptrCast(&dest), @sizeOf(linux.sockaddr.in));
    switch (linux.errno(crc)) {
        .SUCCESS, .CONNREFUSED => return .{ .rtt_ns = @max(sys.nowNs() -| t0, 1), .ttl = 64 },
        .INPROGRESS, .AGAIN => {},
        else => return null,
    }
    var pfd = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.OUT | linux.POLL.ERR, .revents = 0 }};
    if (linux.poll(&pfd, 1, timeout_ms) != 1) return null;
    var so_err: i32 = 0;
    var err_len: linux.socklen_t = @sizeOf(i32);
    if (linux.errno(linux.getsockopt(fd, linux.SOL.SOCKET, linux.SO.ERROR, @ptrCast(&so_err), &err_len)) != .SUCCESS) return null;
    if (so_err == 0 or so_err == @intFromEnum(linux.E.CONNREFUSED)) {
        return .{ .rtt_ns = @max(sys.nowNs() -| t0, 1), .ttl = 64 };
    }
    return null;
}

fn icmpChecksum(bytes: []const u8) u16 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i + 1 < bytes.len) : (i += 2) {
        sum += std.mem.readInt(u16, bytes[i..][0..2], .big);
    }
    if (i < bytes.len) {
        sum += @as(u16, bytes[i]) << 8;
    }
    while (sum >> 16 != 0) {
        sum = (sum & 0xffff) + (sum >> 16);
    }
    return ~@as(u16, @truncate(sum));
}

fn resolveHostIp4(local_hostname: []const u8, raw_host: []const u8) ?sys.network.Ip4 {
    const host = std.mem.trimEnd(u8, raw_host, ".");
    if (host.len == 0) return null;
    if (sys.network.parseIp4(host)) |ip| return ip;
    if (std.ascii.eqlIgnoreCase(host, "localhost") or std.ascii.eqlIgnoreCase(host, local_hostname)) {
        return .{ 127, 0, 0, 1 };
    }
    // Check /etc/hosts if present.
    var hosts_buf: [2048]u8 = undefined;
    if (sys.readFile("/etc/hosts", &hosts_buf)) |hosts_text| {
        var lines = std.mem.tokenizeScalar(u8, hosts_text, '\n');
        while (lines.next()) |raw_line| {
            const line = if (std.mem.indexOfScalar(u8, raw_line, '#')) |hash| raw_line[0..hash] else raw_line;
            var words = std.mem.tokenizeAny(u8, line, " \t\r");
            const ip_str = words.next() orelse continue;
            const ip = sys.network.parseIp4(ip_str) orelse continue;
            while (words.next()) |alias| {
                if (std.ascii.eqlIgnoreCase(alias, host)) return ip;
            }
        }
    }
    // Query nameservers from /etc/resolv.conf.
    var resolv_buf: [512]u8 = undefined;
    if (sys.readFile("/etc/resolv.conf", &resolv_buf)) |resolv_text| {
        var lines = std.mem.tokenizeScalar(u8, resolv_text, '\n');
        while (lines.next()) |line| {
            var words = std.mem.tokenizeAny(u8, line, " \t\r");
            if (!std.mem.eql(u8, words.next() orelse continue, "nameserver")) continue;
            const ns_str = words.next() orelse continue;
            const ns_ip = sys.network.parseIp4(ns_str) orelse continue;
            if (dnsLookupIp4(ns_ip, host)) |ip| return ip;
        }
    }
    return null;
}

fn dnsLookupIp4(server: sys.network.Ip4, name: []const u8) ?sys.network.Ip4 {
    var q_buf: [300]u8 = undefined;
    var id_bytes: [2]u8 = undefined;
    _ = linux.getrandom(&id_bytes, 2, 0);
    const id = std.mem.readInt(u16, &id_bytes, .little);
    const query = buildDnsQuery(&q_buf, id, name) orelse return null;

    const rc = linux.socket(linux.AF.INET, linux.SOCK.DGRAM | linux.SOCK.CLOEXEC, 0);
    if (linux.errno(rc) != .SUCCESS) return null;
    const fd: linux.fd_t = @intCast(rc);
    defer sys.close(fd);

    const addr: linux.sockaddr.in = .{
        .port = std.mem.nativeToBig(u16, 53),
        .addr = @bitCast(server),
    };
    if (linux.errno(linux.connect(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.in))) != .SUCCESS) return null;

    var reply: [512]u8 = undefined;
    for (0..2) |_| {
        if (linux.errno(linux.write(fd, query.ptr, query.len)) != .SUCCESS) return null;
        var pfd = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
        if (linux.poll(&pfd, 1, 2000) != 1) continue;
        const n = linux.read(fd, &reply, reply.len);
        if (linux.errno(n) != .SUCCESS) return null;
        return parseDnsAnswer(reply[0..n], id);
    }
    return null;
}

fn buildDnsQuery(buf: []u8, id: u16, name: []const u8) ?[]const u8 {
    if (name.len + 18 > buf.len) return null;
    std.mem.writeInt(u16, buf[0..2], id, .big);
    std.mem.writeInt(u16, buf[2..4], 0x0100, .big);
    std.mem.writeInt(u16, buf[4..6], 1, .big);
    @memset(buf[6..12], 0);
    var at: usize = 12;
    var labels = std.mem.splitScalar(u8, name, '.');
    while (labels.next()) |label| {
        if (label.len == 0 or label.len > 63) return null;
        buf[at] = @intCast(label.len);
        @memcpy(buf[at + 1 ..][0..label.len], label);
        at += 1 + label.len;
    }
    buf[at] = 0;
    std.mem.writeInt(u16, buf[at + 1 ..][0..2], 1, .big); // A
    std.mem.writeInt(u16, buf[at + 3 ..][0..2], 1, .big); // IN
    return buf[0 .. at + 5];
}

fn parseDnsAnswer(msg: []const u8, id: u16) ?sys.network.Ip4 {
    if (msg.len < 12) return null;
    if (std.mem.readInt(u16, msg[0..2], .big) != id) return null;
    const flags = std.mem.readInt(u16, msg[2..4], .big);
    if (flags & 0x8000 == 0 or flags & 0x000f != 0) return null;
    const questions = std.mem.readInt(u16, msg[4..6], .big);
    const answers = std.mem.readInt(u16, msg[6..8], .big);
    var at: usize = 12;
    for (0..questions) |_| at = (skipDnsName(msg, at) orelse return null) + 4;
    for (0..answers) |_| {
        at = skipDnsName(msg, at) orelse return null;
        if (at + 10 > msg.len) return null;
        const rtype = std.mem.readInt(u16, msg[at..][0..2], .big);
        const rdlen = std.mem.readInt(u16, msg[at + 8 ..][0..2], .big);
        at += 10;
        if (at + rdlen > msg.len) return null;
        if (rtype == 1 and rdlen == 4) return msg[at..][0..4].*;
        at += rdlen;
    }
    return null;
}

fn skipDnsName(msg: []const u8, start: usize) ?usize {
    var at = start;
    while (at < msg.len) {
        const len = msg[at];
        if (len == 0) return at + 1;
        if (len & 0xc0 == 0xc0) return if (at + 2 <= msg.len) at + 2 else null;
        at += 1 + len;
    }
    return null;
}

fn cmdWget(cx: *Context, args: []const []const u8) u8 {
    var quiet = false;
    var output_path: ?[]const u8 = null;
    var prefix_dir: ?[]const u8 = null;
    var urls: std.ArrayList([]const u8) = .empty;
    defer urls.deinit(cx.gpa);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "-q")) {
            quiet = true;
        } else if (std.mem.eql(u8, arg, "-O") or (std.mem.startsWith(u8, arg, "-O") and arg.len > 2)) {
            output_path = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) {
                    cx.errPrint("wget: option requires an argument -- 'O'\n", .{});
                    return 1;
                }
                break :blk args[i];
            };
        } else if (std.mem.eql(u8, arg, "-P") or (std.mem.startsWith(u8, arg, "-P") and arg.len > 2)) {
            prefix_dir = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) {
                    cx.errPrint("wget: option requires an argument -- 'P'\n", .{});
                    return 1;
                }
                break :blk args[i];
            };
        } else if (arg.len > 1 and arg[0] == '-') {
            cx.errPrint("wget: invalid option -- '{s}'\n", .{arg});
            return 1;
        } else {
            urls.append(cx.gpa, arg) catch return 1;
        }
    }

    if (urls.items.len == 0) {
        cx.errPrint("wget: missing URL\nUsage: wget [-q] [-O file] [-P dir] <url>...\n", .{});
        return 1;
    }

    var status: u8 = 0;
    for (urls.items) |url| {
        if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) {
            cx.errPrint("wget: '{s}': unsupported scheme (use http:// or https://)\n", .{url});
            status = 1;
            continue;
        }
        const uri = std.Uri.parse(url) catch {
            cx.errPrint("wget: '{s}': invalid URL\n", .{url});
            status = 1;
            continue;
        };
        if (uri.host == null) {
            cx.errPrint("wget: '{s}': missing host\n", .{url});
            status = 1;
            continue;
        }

        const fetched = wgetDownload(cx.gpa, url) catch |err| {
            cx.errPrint("wget: {s}: {s}\n", .{ url, @errorName(err) });
            status = 1;
            continue;
        };
        defer if (fetched.body.len > 0) cx.gpa.free(fetched.body);

        if (fetched.status != 200) {
            cx.errPrint("wget: {s}: HTTP {d}\n", .{ url, fetched.status });
            status = 1;
            continue;
        }

        if (output_path) |out_arg| {
            if (std.mem.eql(u8, out_arg, "-")) {
                cx.write(fetched.body);
                continue;
            }
        }

        const display_name = output_path orelse urlDefaultFilename(url);
        const dest_path = blk: {
            if (output_path) |out_arg| {
                break :blk cx.resolve(out_arg) catch {
                    status = 1;
                    continue;
                };
            }
            if (prefix_dir) |pdir| {
                const resolved_dir = cx.resolve(pdir) catch {
                    status = 1;
                    continue;
                };
                defer cx.gpa.free(resolved_dir);
                mkdirParents(resolved_dir) catch |e| {
                    cx.errPrint("wget: {s}: {s}\n", .{ pdir, describeErrno(e) });
                    status = 1;
                    continue;
                };
                break :blk joinPath(cx.gpa, resolved_dir, display_name) catch {
                    status = 1;
                    continue;
                };
            }
            break :blk cx.resolve(display_name) catch {
                status = 1;
                continue;
            };
        };
        defer cx.gpa.free(dest_path);

        writeFileAll(dest_path, fetched.body, false) catch |e| {
            cx.errPrint("wget: cannot write '{s}': {s}\n", .{ display_name, describeErrno(e) });
            status = 1;
            continue;
        };

        if (!quiet) {
            var size_buf: [24]u8 = undefined;
            cx.print("Saving to '{s}' ({s})\n", .{ display_name, formatHumanSize(&size_buf, fetched.body.len) });
        }
    }
    return status;
}

const WgetResult = struct {
    status: u16,
    body: []u8,
};

fn wgetDownload(gpa: std.mem.Allocator, url: []const u8) !WgetResult {
    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer client.deinit();

    if (std.mem.startsWith(u8, url, "https://")) {
        const now = std.Io.Clock.real.now(io);
        client.ca_bundle.addCertsFromFilePathAbsolute(gpa, io, now, "/os/certs/ca-certificates.pem") catch {};
        if (client.ca_bundle.map.count() == 0) {
            client.ca_bundle.addCertsFromFilePathAbsolute(gpa, io, now, "/etc/ssl/certs/ca-certificates.crt") catch {};
        }
        client.now = now;
    }

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const res = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &out.writer,
        .keep_alive = false,
    });
    const code: u16 = @intFromEnum(res.status);
    if (res.status != .ok) {
        out.deinit();
        return .{ .status = code, .body = &.{} };
    }
    if (out.written().len > max_file_bytes) return error.FileTooBig;
    return .{ .status = code, .body = try out.toOwnedSlice() };
}

fn urlDefaultFilename(url: []const u8) []const u8 {
    const after_scheme = if (std.mem.indexOf(u8, url, "://")) |idx| url[idx + 3 ..] else url;
    const path_start = std.mem.indexOfScalar(u8, after_scheme, '/') orelse return "index.html";
    const raw_path = after_scheme[path_start + 1 ..];
    const no_query = if (std.mem.indexOfAny(u8, raw_path, "?#")) |q| raw_path[0..q] else raw_path;
    const trimmed = std.mem.trimEnd(u8, no_query, "/");
    if (trimmed.len == 0) return "index.html";
    const base = if (std.mem.lastIndexOfScalar(u8, trimmed, '/')) |s| trimmed[s + 1 ..] else trimmed;
    if (base.len == 0 or std.mem.eql(u8, base, ".") or std.mem.eql(u8, base, "..")) return "index.html";
    return base;
}

// --- Tests ---------------------------------------------------------------------

const testing = std.testing;

test "glob matching" {
    try testing.expect(globMatch("*.zig", "main.zig", false));
    try testing.expect(!globMatch("*.zig", "main.c", false));
    try testing.expect(globMatch("file?.txt", "file1.txt", false));
    try testing.expect(!globMatch("file?.txt", "file12.txt", false));
    try testing.expect(globMatch("[a-c]*.txt", "b_note.txt", false));
    try testing.expect(!globMatch("[!a-c]*.txt", "b_note.txt", false));
    try testing.expect(globMatch("readme.*", "README.MD", true));
}

test "chmod mode parsing" {
    try testing.expectEqual(@as(?u16, 0o755), parseModeSpec("755", 0o644));
    try testing.expectEqual(@as(?u16, 0o755), parseModeSpec("+x", 0o644));
    try testing.expectEqual(@as(?u16, 0o600), parseModeSpec("go-rw", 0o644));
    try testing.expectEqual(@as(?u16, 0o744), parseModeSpec("u+x", 0o644));
    try testing.expectEqual(@as(?u16, 0o444), parseModeSpec("a=r", 0o755));
    try testing.expect(parseModeSpec("bad", 0o644) == null);
}

test "wget default filename extraction and DNS/ICMP helpers" {
    try testing.expectEqualStrings("index.html", urlDefaultFilename("https://example.com"));
    try testing.expectEqualStrings("index.html", urlDefaultFilename("https://example.com/"));
    try testing.expectEqualStrings("apps.json", urlDefaultFilename("https://example.com/releases/apps.json?v=1"));
    try testing.expectEqualStrings("archive.tar.xz", urlDefaultFilename("http://127.0.0.1:8080/dl/archive.tar.xz#sha"));

    var qbuf: [300]u8 = undefined;
    const q = buildDnsQuery(&qbuf, 0xabcd, "dazzle.local").?;
    var ans: [64]u8 = undefined;
    @memcpy(ans[0..q.len], q);
    ans[2] = 0x81;
    ans[3] = 0x80;
    ans[7] = 1;
    const rec = [_]u8{ 0xc0, 12, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 192, 168, 1, 42 };
    @memcpy(ans[q.len..][0..rec.len], &rec);
    try testing.expectEqual(sys.network.Ip4{ 192, 168, 1, 42 }, parseDnsAnswer(ans[0 .. q.len + rec.len], 0xabcd).?);

    var echo: [8]u8 = .{ 8, 0, 0, 0, 0x12, 0x34, 0x00, 0x01 };
    const csum = icmpChecksum(&echo);
    std.mem.writeInt(u16, echo[2..4], csum, .big);
    try testing.expectEqual(@as(u16, 0), icmpChecksum(&echo));
}

