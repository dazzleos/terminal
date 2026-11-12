const std = @import("std");
const linux = std.os.linux;
const sys = @import("sys");
pub const commands = @import("commands.zig");

pub const LineKind = enum {
    prompt,
    stdout,
    stderr,
    info,
};

pub const OutputLine = struct {
    text: []u8,
    kind: LineKind,
};

pub const Var = struct {
    name: []u8,
    value: []u8,
    exported: bool,
};

pub const CompletionResult = struct {
    replacement_line: ?[]u8 = null,
    new_cursor: usize = 0,
    candidates: std.ArrayList([]u8) = .empty,

    pub fn deinit(self: *CompletionResult, gpa: std.mem.Allocator) void {
        if (self.replacement_line) |r| gpa.free(r);
        for (self.candidates.items) |c| gpa.free(c);
        self.candidates.deinit(gpa);
    }
};

pub const Shell = struct {
    gpa: std.mem.Allocator,
    cwd: std.ArrayList(u8) = .empty,
    old_cwd: std.ArrayList(u8) = .empty,
    home: []u8,
    hostname_buf: [65]u8 = undefined,
    hostname_len: usize = 0,
    vars: std.ArrayList(Var) = .empty,
    history: std.ArrayList([]u8) = .empty,
    output: std.ArrayList(OutputLine) = .empty,
    last_status: u8 = 0,
    should_exit: bool = false,
    launch_env: []const [*:0]const u8 = &.{},
    max_output_lines: usize = 2000,
    max_history: usize = 500,

    pub fn init(gpa: std.mem.Allocator, initial_dir: ?[]const u8, env: []const [*:0]const u8) !Shell {
        var self: Shell = .{
            .gpa = gpa,
            .home = try gpa.dupe(u8, "/home"),
            .launch_env = env,
        };
        errdefer self.deinit();

        var uts: linux.utsname = undefined;
        if (linux.errno(linux.uname(&uts)) == .SUCCESS) {
            const node = std.mem.sliceTo(&uts.nodename, 0);
            const len = @min(node.len, self.hostname_buf.len);
            @memcpy(self.hostname_buf[0..len], node[0..len]);
            self.hostname_len = len;
        }
        if (self.hostname_len == 0) {
            const fallback = "dazzle";
            @memcpy(self.hostname_buf[0..fallback.len], fallback);
            self.hostname_len = fallback.len;
        }

        // Seed environment variables from process env.
        for (env) |entry_z| {
            const entry = std.mem.sliceTo(entry_z, 0);
            if (std.mem.indexOfScalar(u8, entry, '=')) |eq| {
                const k = entry[0..eq];
                const v = entry[eq + 1 ..];
                if (validVarName(k)) {
                    try self.setVar(k, v, true);
                }
            }
        }

        if (self.getVar("HOME")) |h| {
            if (h.len > 0 and !std.mem.eql(u8, h, "/")) {
                const duped = try gpa.dupe(u8, h);
                gpa.free(self.home);
                self.home = duped;
            }
        }
        if (std.mem.eql(u8, self.home, "/home")) {
            const default_home = if (commands.statPath(sys.system.user_dir, true)) |st|
                (if (st.isDir()) sys.system.user_dir else "/")
            else |_| if (commands.statPath("/home", true)) |st|
                (if (st.isDir()) "/home" else "/")
            else |_|
                "/";
            const duped = try gpa.dupe(u8, default_home);
            gpa.free(self.home);
            self.home = duped;
            try self.setVar("HOME", self.home, true);
        }

        if (self.getVar("USER") == null) {
            const user = if (linux.geteuid() == 0) "root" else "user";
            try self.setVar("USER", user, true);
        }
        try self.setVar("SHELL", "dazzle-terminal", true);
        if (self.getVar("TERM") == null) {
            try self.setVar("TERM", "dazzle", true);
        }

        // Determine starting working directory.
        var start_dir: ?[]u8 = null;
        defer if (start_dir) |d| gpa.free(d);
        if (initial_dir) |dir| {
            if (commands.statPath(dir, true)) |st| {
                if (st.isDir()) start_dir = try normalizePath(gpa, dir);
            } else |_| {}
        }
        if (start_dir == null) {
            var cwd_buf: [4096]u8 = undefined;
            const rc = linux.getcwd(&cwd_buf, cwd_buf.len);
            if (linux.errno(rc) == .SUCCESS) {
                const s = std.mem.sliceTo(&cwd_buf, 0);
                if (s.len > 0) start_dir = try gpa.dupe(u8, s);
            }
        }
        const chosen = start_dir orelse self.home;
        try self.cwd.appendSlice(gpa, chosen);
        try self.old_cwd.appendSlice(gpa, chosen);
        try self.setVar("PWD", chosen, true);
        try self.setVar("OLDPWD", chosen, true);

        try self.appendLine("Dazzle Terminal — type 'help' for built-in commands.", .info);
        return self;
    }

    pub fn initTest(gpa: std.mem.Allocator, initial_dir: []const u8) !Shell {
        const norm = try normalizePath(gpa, initial_dir);
        defer gpa.free(norm);
        var self: Shell = .{
            .gpa = gpa,
            .home = try gpa.dupe(u8, norm),
        };
        errdefer self.deinit();
        const fallback = "dazzle";
        @memcpy(self.hostname_buf[0..fallback.len], fallback);
        self.hostname_len = fallback.len;
        try self.cwd.appendSlice(gpa, norm);
        try self.old_cwd.appendSlice(gpa, norm);
        try self.setVar("HOME", norm, true);
        try self.setVar("PWD", norm, true);
        try self.setVar("OLDPWD", norm, true);
        try self.setVar("USER", "user", true);
        try self.setVar("SHELL", "dazzle-terminal", true);
        return self;
    }

    pub fn deinit(self: *Shell) void {
        self.cwd.deinit(self.gpa);
        self.old_cwd.deinit(self.gpa);
        self.gpa.free(self.home);
        for (self.vars.items) |v| {
            self.gpa.free(v.name);
            self.gpa.free(v.value);
        }
        self.vars.deinit(self.gpa);
        for (self.history.items) |h| self.gpa.free(h);
        self.history.deinit(self.gpa);
        for (self.output.items) |line| self.gpa.free(line.text);
        self.output.deinit(self.gpa);
    }

    pub fn hostnameSlice(self: *const Shell) []const u8 {
        return self.hostname_buf[0..self.hostname_len];
    }

    pub fn getVar(self: *const Shell, name: []const u8) ?[]const u8 {
        for (self.vars.items) |v| {
            if (std.mem.eql(u8, v.name, name)) return v.value;
        }
        return null;
    }

    pub fn setVar(self: *Shell, name: []const u8, value: []const u8, exported: bool) !void {
        for (self.vars.items) |*v| {
            if (std.mem.eql(u8, v.name, name)) {
                const new_val = try self.gpa.dupe(u8, value);
                self.gpa.free(v.value);
                v.value = new_val;
                if (exported) v.exported = true;
                if (std.mem.eql(u8, name, "HOME") and value.len > 0) {
                    if (self.gpa.dupe(u8, value)) |h| {
                        self.gpa.free(self.home);
                        self.home = h;
                    } else |_| {}
                }
                return;
            }
        }
        const dup_name = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(dup_name);
        const dup_val = try self.gpa.dupe(u8, value);
        errdefer self.gpa.free(dup_val);
        try self.vars.append(self.gpa, .{
            .name = dup_name,
            .value = dup_val,
            .exported = exported,
        });
    }

    pub fn unsetVar(self: *Shell, name: []const u8) void {
        var i: usize = 0;
        while (i < self.vars.items.len) {
            if (std.mem.eql(u8, self.vars.items[i].name, name)) {
                const removed = self.vars.orderedRemove(i);
                self.gpa.free(removed.name);
                self.gpa.free(removed.value);
                return;
            }
            i += 1;
        }
    }

    pub fn setCwd(self: *Shell, new_path: []const u8) !void {
        const norm = try normalizePath(self.gpa, new_path);
        defer self.gpa.free(norm);

        self.old_cwd.clearRetainingCapacity();
        try self.old_cwd.appendSlice(self.gpa, self.cwd.items);
        try self.setVar("OLDPWD", self.old_cwd.items, true);

        self.cwd.clearRetainingCapacity();
        try self.cwd.appendSlice(self.gpa, norm);
        try self.setVar("PWD", self.cwd.items, true);

        var z_buf: [4096]u8 = undefined;
        if (std.mem.printSentinel(&z_buf, "{s}", .{norm}, 0)) |z| {
            _ = linux.chdir(z);
        } else |_| {}
    }

    pub fn resolvePath(self: *const Shell, raw: []const u8) ![]u8 {
        if (raw.len == 0) return self.gpa.dupe(u8, self.cwd.items);
        if (std.mem.eql(u8, raw, "~")) {
            return normalizePath(self.gpa, self.home);
        }
        if (std.mem.startsWith(u8, raw, "~/")) {
            const joined = try commands.joinPath(self.gpa, self.home, raw[2..]);
            defer self.gpa.free(joined);
            return normalizePath(self.gpa, joined);
        }
        if (raw[0] == '/') {
            return normalizePath(self.gpa, raw);
        }
        const joined = try commands.joinPath(self.gpa, self.cwd.items, raw);
        defer self.gpa.free(joined);
        return normalizePath(self.gpa, joined);
    }

    pub fn formatPrompt(self: *const Shell, buf: []u8) []const u8 {
        const cwd = self.cwd.items;
        const home = self.home;
        const sym: u8 = if (linux.geteuid() == 0) '#' else '$';
        if (home.len > 1 and std.mem.eql(u8, cwd, home)) {
            return std.fmt.bufPrint(buf, "~ {c} ", .{sym}) catch "$ ";
        }
        if (home.len > 1 and std.mem.startsWith(u8, cwd, home) and cwd.len > home.len and cwd[home.len] == '/') {
            return std.fmt.bufPrint(buf, "~{s} {c} ", .{ cwd[home.len..], sym }) catch "$ ";
        }
        return std.fmt.bufPrint(buf, "{s} {c} ", .{ cwd, sym }) catch "$ ";
    }

    pub fn clearOutput(self: *Shell) void {
        for (self.output.items) |line| self.gpa.free(line.text);
        self.output.clearRetainingCapacity();
    }

    pub fn clearHistory(self: *Shell) void {
        for (self.history.items) |h| self.gpa.free(h);
        self.history.clearRetainingCapacity();
    }

    pub fn appendLine(self: *Shell, text: []const u8, kind: LineKind) !void {
        while (self.output.items.len >= self.max_output_lines and self.output.items.len > 0) {
            const oldest = self.output.orderedRemove(0);
            self.gpa.free(oldest.text);
        }
        const dup = try self.gpa.dupe(u8, text);
        errdefer self.gpa.free(dup);
        try self.output.append(self.gpa, .{ .text = dup, .kind = kind });
    }

    pub fn appendOutputText(self: *Shell, text: []const u8, kind: LineKind) void {
        if (text.len == 0) return;
        const trimmed = if (text[text.len - 1] == '\n') text[0 .. text.len - 1] else text;
        var it = std.mem.splitScalar(u8, trimmed, '\n');
        while (it.next()) |raw_line| {
            const line = std.mem.trimEnd(u8, raw_line, "\r");
            self.appendLine(line, kind) catch return;
        }
    }

    pub fn recordHistory(self: *Shell, line: []const u8) void {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) return;
        if (self.history.items.len > 0) {
            const prev = self.history.items[self.history.items.len - 1];
            if (std.mem.eql(u8, prev, trimmed)) return;
        }
        while (self.history.items.len >= self.max_history and self.history.items.len > 0) {
            const oldest = self.history.orderedRemove(0);
            self.gpa.free(oldest);
        }
        const dup = self.gpa.dupe(u8, trimmed) catch return;
        self.history.append(self.gpa, dup) catch {
            self.gpa.free(dup);
        };
    }

    /// Execute a command line entered by the user, appending prompt and output lines.
    pub fn executeLine(self: *Shell, line: []const u8) void {
        var prompt_buf: [512]u8 = undefined;
        const prompt = self.formatPrompt(&prompt_buf);
        var echo_buf: std.ArrayList(u8) = .empty;
        defer echo_buf.deinit(self.gpa);
        echo_buf.appendSlice(self.gpa, prompt) catch {};
        echo_buf.appendSlice(self.gpa, line) catch {};
        self.appendLine(echo_buf.items, .prompt) catch {};

        self.recordHistory(line);
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) return;
        self.last_status = self.evalLine(trimmed);
    }

    /// Evaluate a command line and append any produced stdout/stderr to `self.output`.
    pub fn evalLine(self: *Shell, line: []const u8) u8 {
        var tokens = tokenize(self.gpa, line) catch |e| {
            var buf: [128]u8 = undefined;
            const msg = switch (e) {
                error.UnterminatedSingleQuote => "shell: syntax error: unterminated single quote",
                error.UnterminatedDoubleQuote => "shell: syntax error: unterminated double quote",
                error.TrailingBackslash => "shell: syntax error: trailing backslash",
                else => "shell: syntax error",
            };
            const formatted = std.fmt.bufPrint(&buf, "{s}\n", .{msg}) catch msg;
            self.appendOutputText(formatted, .stderr);
            return 2;
        };
        defer freeTokens(self.gpa, &tokens);

        if (tokens.items.len == 0) return self.last_status;

        var idx: usize = 0;
        var status: u8 = 0;
        var next_chain: ChainOp = .always;

        while (idx < tokens.items.len) {
            // Find end of current pipeline (up to ;, &&, ||).
            var end = idx;
            var chain_after: ChainOp = .always;
            while (end < tokens.items.len) : (end += 1) {
                switch (tokens.items[end]) {
                    .op => |op| switch (op) {
                        .semi => {
                            chain_after = .always;
                            break;
                        },
                        .and_if => {
                            chain_after = .and_if;
                            break;
                        },
                        .or_if => {
                            chain_after = .or_if;
                            break;
                        },
                        else => {},
                    },
                    .word => {},
                }
            }

            const slice = tokens.items[idx..end];
            const should_run = switch (next_chain) {
                .always => true,
                .and_if => status == 0,
                .or_if => status != 0,
            };
            if (should_run and slice.len > 0) {
                status = self.evalPipeline(slice);
                self.last_status = status;
                if (self.should_exit) break;
            }
            next_chain = chain_after;
            idx = if (end < tokens.items.len) end + 1 else end;
        }
        return status;
    }

    fn evalPipeline(self: *Shell, tokens: []const Token) u8 {
        // Split tokens on `.pipe`.
        var stages: std.ArrayList([]const Token) = .empty;
        defer stages.deinit(self.gpa);

        var start: usize = 0;
        for (tokens, 0..) |tok, i| {
            if (tok == .op and tok.op == .pipe) {
                if (i == start) {
                    self.appendOutputText("shell: syntax error near unexpected token '|'", .stderr);
                    return 2;
                }
                stages.append(self.gpa, tokens[start..i]) catch return 1;
                start = i + 1;
            }
        }
        if (start >= tokens.len) {
            self.appendOutputText("shell: syntax error: empty pipeline stage", .stderr);
            return 2;
        }
        stages.append(self.gpa, tokens[start..tokens.len]) catch return 1;

        var pipe_input: std.ArrayList(u8) = .empty;
        defer pipe_input.deinit(self.gpa);

        var last_status: u8 = 0;
        for (stages.items, 0..) |stage_tokens, stage_idx| {
            const is_last = stage_idx + 1 == stages.items.len;
            var stage_stdout: std.ArrayList(u8) = .empty;
            defer stage_stdout.deinit(self.gpa);
            var stage_stderr: std.ArrayList(u8) = .empty;
            defer stage_stderr.deinit(self.gpa);

            last_status = self.evalStage(
                stage_tokens,
                pipe_input.items,
                &stage_stdout,
                &stage_stderr,
            );

            if (stage_stderr.items.len > 0) {
                self.appendOutputText(stage_stderr.items, .stderr);
            }
            if (is_last) {
                if (stage_stdout.items.len > 0) {
                    self.appendOutputText(stage_stdout.items, .stdout);
                }
            } else {
                pipe_input.clearRetainingCapacity();
                pipe_input.appendSlice(self.gpa, stage_stdout.items) catch return 1;
            }
            if (self.should_exit) break;
        }
        return last_status;
    }

    fn evalStage(
        self: *Shell,
        tokens: []const Token,
        stdin_pipe: []const u8,
        stdout_out: *std.ArrayList(u8),
        stderr_out: *std.ArrayList(u8),
    ) u8 {
        var words: std.ArrayList([]u8) = .empty;
        defer {
            for (words.items) |w| self.gpa.free(w);
            words.deinit(self.gpa);
        }

        const Redir = struct {
            op: Operator,
            target: []u8,
        };
        var redirs: std.ArrayList(Redir) = .empty;
        defer {
            for (redirs.items) |r| self.gpa.free(r.target);
            redirs.deinit(self.gpa);
        }

        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            switch (tokens[i]) {
                .op => |op| switch (op) {
                    .redir_in, .redir_out, .redir_append, .redir_err, .redir_err_append, .redir_both => {
                        if (i + 1 >= tokens.len or tokens[i + 1] != .word) {
                            appendFmt(self.gpa, stderr_out, "shell: syntax error near redirection\n", .{});
                            return 2;
                        }
                        i += 1;
                        const expanded_target = self.expandWordSingle(tokens[i].word) catch return 1;
                        redirs.append(self.gpa, .{ .op = op, .target = expanded_target }) catch {
                            self.gpa.free(expanded_target);
                            return 1;
                        };
                    },
                    else => {},
                },
                .word => |w| {
                    self.expandWordInto(w, &words) catch return 1;
                },
            }
        }

        // Extract leading VAR=VALUE assignments if unquoted variable prefix.
        var cmd_start: usize = 0;
        while (cmd_start < words.items.len) {
            const candidate = words.items[cmd_start];
            if (std.mem.indexOfScalar(u8, candidate, '=')) |eq| {
                if (eq > 0 and validVarName(candidate[0..eq])) {
                    cmd_start += 1;
                    continue;
                }
            }
            break;
        }

        // If there are only variable assignments and no command, commit them to shell state.
        if (cmd_start == words.items.len) {
            for (words.items[0..cmd_start]) |assign| {
                const eq = std.mem.indexOfScalar(u8, assign, '=').?;
                self.setVar(assign[0..eq], assign[eq + 1 ..], false) catch return 1;
            }
            return 0;
        }

        // Apply temporary variable assignments (for built-ins we set them in shell state).
        for (words.items[0..cmd_start]) |assign| {
            const eq = std.mem.indexOfScalar(u8, assign, '=').?;
            self.setVar(assign[0..eq], assign[eq + 1 ..], false) catch return 1;
        }

        // Handle input redirection `<`.
        var file_stdin: ?[]u8 = null;
        defer if (file_stdin) |s| self.gpa.free(s);
        for (redirs.items) |r| {
            if (r.op == .redir_in) {
                const resolved = self.resolvePath(r.target) catch return 1;
                defer self.gpa.free(resolved);
                if (file_stdin) |prev| self.gpa.free(prev);
                file_stdin = commands.readFileAll(self.gpa, resolved) catch |e| {
                    appendFmt(self.gpa, stderr_out, "shell: {s}: {s}\n", .{ r.target, commands.describeErrno(e) });
                    return 1;
                };
            }
        }

        const effective_stdin = file_stdin orelse stdin_pipe;
        const cmd_name = words.items[cmd_start];
        const cmd_args = words.items[cmd_start + 1 ..];

        var cx: commands.Context = .{
            .gpa = self.gpa,
            .shell = self,
            .stdin = effective_stdin,
        };
        defer cx.deinit();

        var status: u8 = 0;
        if (commands.find(cmd_name)) |builtin| {
            status = builtin.run(&cx, cmd_args);
        } else {
            cx.errPrint("{s}: command not found\n", .{cmd_name});
            status = 127;
        }

        // Process output redirections.
        var stdout_redirected = false;
        var stderr_redirected = false;
        for (redirs.items) |r| {
            switch (r.op) {
                .redir_in => {},
                .redir_out, .redir_append => {
                    stdout_redirected = true;
                    const resolved = self.resolvePath(r.target) catch return 1;
                    defer self.gpa.free(resolved);
                    commands.writeFileAll(resolved, cx.stdout.items, r.op == .redir_append) catch |e| {
                        appendFmt(self.gpa, stderr_out, "shell: {s}: {s}\n", .{ r.target, commands.describeErrno(e) });
                        return 1;
                    };
                },
                .redir_err, .redir_err_append => {
                    stderr_redirected = true;
                    const resolved = self.resolvePath(r.target) catch return 1;
                    defer self.gpa.free(resolved);
                    commands.writeFileAll(resolved, cx.stderr.items, r.op == .redir_err_append) catch |e| {
                        appendFmt(self.gpa, stderr_out, "shell: {s}: {s}\n", .{ r.target, commands.describeErrno(e) });
                        return 1;
                    };
                },
                .redir_both => {
                    stdout_redirected = true;
                    stderr_redirected = true;
                    const resolved = self.resolvePath(r.target) catch return 1;
                    defer self.gpa.free(resolved);
                    commands.writeFileAll(resolved, cx.stdout.items, false) catch |e| {
                        appendFmt(self.gpa, stderr_out, "shell: {s}: {s}\n", .{ r.target, commands.describeErrno(e) });
                        return 1;
                    };
                    if (cx.stderr.items.len > 0) {
                        commands.writeFileAll(resolved, cx.stderr.items, true) catch {};
                    }
                },
                else => {},
            }
        }

        if (!stdout_redirected and cx.stdout.items.len > 0) {
            stdout_out.appendSlice(self.gpa, cx.stdout.items) catch {};
        }
        if (!stderr_redirected and cx.stderr.items.len > 0) {
            stderr_out.appendSlice(self.gpa, cx.stderr.items) catch {};
        }
        return status;
    }

    fn expandWordSingle(self: *const Shell, w: Word) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        for (w.parts.items, 0..) |part, idx| {
            switch (part.quote) {
                .single => try out.appendSlice(self.gpa, part.text),
                .double => try self.expandVarsInto(part.text, &out),
                .none => {
                    var expanded: std.ArrayList(u8) = .empty;
                    defer expanded.deinit(self.gpa);
                    if (idx == 0 and std.mem.eql(u8, part.text, "~")) {
                        try expanded.appendSlice(self.gpa, self.home);
                    } else if (idx == 0 and std.mem.startsWith(u8, part.text, "~/")) {
                        try expanded.appendSlice(self.gpa, self.home);
                        try self.expandVarsInto(part.text[1..], &expanded);
                    } else {
                        try self.expandVarsInto(part.text, &expanded);
                    }
                    try out.appendSlice(self.gpa, expanded.items);
                },
            }
        }
        return out.toOwnedSlice(self.gpa);
    }

    fn expandWordInto(self: *const Shell, w: Word, out_words: *std.ArrayList([]u8)) !void {
        var combined: std.ArrayList(u8) = .empty;
        defer combined.deinit(self.gpa);
        var has_unquoted_glob = false;

        for (w.parts.items, 0..) |part, idx| {
            switch (part.quote) {
                .single => try combined.appendSlice(self.gpa, part.text),
                .double => try self.expandVarsInto(part.text, &combined),
                .none => {
                    var expanded: std.ArrayList(u8) = .empty;
                    defer expanded.deinit(self.gpa);
                    if (idx == 0 and std.mem.eql(u8, part.text, "~")) {
                        try expanded.appendSlice(self.gpa, self.home);
                    } else if (idx == 0 and std.mem.startsWith(u8, part.text, "~/")) {
                        try expanded.appendSlice(self.gpa, self.home);
                        try self.expandVarsInto(part.text[1..], &expanded);
                    } else {
                        try self.expandVarsInto(part.text, &expanded);
                    }
                    for (expanded.items) |ch| {
                        if (ch == '*' or ch == '?' or ch == '[') has_unquoted_glob = true;
                    }
                    try combined.appendSlice(self.gpa, expanded.items);
                },
            }
        }

        if (has_unquoted_glob) {
            var matches: std.ArrayList([]u8) = .empty;
            defer matches.deinit(self.gpa);
            try self.expandGlob(combined.items, &matches);
            if (matches.items.len > 0) {
                for (matches.items) |m| {
                    try out_words.append(self.gpa, m);
                }
                return;
            }
        }

        const dup = try self.gpa.dupe(u8, combined.items);
        errdefer self.gpa.free(dup);
        try out_words.append(self.gpa, dup);
    }

    fn expandVarsInto(self: *const Shell, text: []const u8, out: *std.ArrayList(u8)) !void {
        var i: usize = 0;
        while (i < text.len) {
            if (text[i] != '$') {
                try out.append(self.gpa, text[i]);
                i += 1;
                continue;
            }
            if (i + 1 >= text.len) {
                try out.append(self.gpa, '$');
                i += 1;
                continue;
            }
            const next = text[i + 1];
            if (next == '?') {
                var buf: [8]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{self.last_status}) catch "0";
                try out.appendSlice(self.gpa, s);
                i += 2;
                continue;
            }
            if (next == '$') {
                var buf: [16]u8 = undefined;
                const pid = linux.getpid();
                const s = std.fmt.bufPrint(&buf, "{d}", .{pid}) catch "1";
                try out.appendSlice(self.gpa, s);
                i += 2;
                continue;
            }
            if (next == '{') {
                if (std.mem.indexOfScalarPos(u8, text, i + 2, '}')) |close| {
                    const name = text[i + 2 .. close];
                    if (self.lookupSpecialOrVar(name)) |val| {
                        try out.appendSlice(self.gpa, val);
                    }
                    i = close + 1;
                    continue;
                }
            }
            if (isVarStart(next)) {
                var end = i + 2;
                while (end < text.len and isVarCont(text[end])) : (end += 1) {}
                const name = text[i + 1 .. end];
                if (self.lookupSpecialOrVar(name)) |val| {
                    try out.appendSlice(self.gpa, val);
                }
                i = end;
                continue;
            }
            try out.append(self.gpa, '$');
            i += 1;
        }
    }

    fn lookupSpecialOrVar(self: *const Shell, name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, name, "PWD")) return self.cwd.items;
        if (std.mem.eql(u8, name, "OLDPWD")) return self.old_cwd.items;
        if (std.mem.eql(u8, name, "HOME")) return self.home;
        if (std.mem.eql(u8, name, "HOSTNAME")) return self.hostnameSlice();
        return self.getVar(name);
    }

    fn expandGlob(self: *const Shell, pattern: []const u8, matches: *std.ArrayList([]u8)) !void {
        // Support patterns in current directory or `dir/pattern`.
        const slash = std.mem.lastIndexOfScalar(u8, pattern, '/');
        const dir_prefix = if (slash) |s| (if (s == 0) "/" else pattern[0..s]) else ".";
        const file_pat = if (slash) |s| pattern[s + 1 ..] else pattern;

        if (std.mem.indexOfAny(u8, dir_prefix, "*?[") != null) return;
        const resolved_dir = self.resolvePath(dir_prefix) catch return;
        defer self.gpa.free(resolved_dir);

        var z_buf: [4096]u8 = undefined;
        const z = std.mem.printSentinel(&z_buf, "{s}", .{resolved_dir}, 0) catch return;
        const rc = linux.open(z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
        if (linux.errno(rc) != .SUCCESS) return;
        const fd: linux.fd_t = @intCast(rc);
        defer sys.close(fd);

        const want_hidden = file_pat.len > 0 and file_pat[0] == '.';
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
                if (!want_hidden and name.len > 0 and name[0] == '.') continue;
                if (commands.globMatch(file_pat, name, false)) {
                    const item = if (slash) |s| blk: {
                        if (s == 0) {
                            break :blk try std.fmt.allocPrint(self.gpa, "/{s}", .{name});
                        } else {
                            break :blk try std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ pattern[0..s], name });
                        }
                    } else try self.gpa.dupe(u8, name);
                    try matches.append(self.gpa, item);
                }
            }
        }

        std.mem.sort([]u8, matches.items, {}, struct {
            fn less(_: void, a: []u8, b: []u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.less);
    }

    /// Perform tab completion for `line` at `cursor`.
    pub fn complete(self: *const Shell, line: []const u8, cursor: usize, gpa: std.mem.Allocator) !CompletionResult {
        var res: CompletionResult = .{};
        errdefer res.deinit(gpa);

        const pos = @min(cursor, line.len);
        var start = pos;
        while (start > 0) {
            const ch = line[start - 1];
            if (ch == ' ' or ch == '\t' or ch == '|' or ch == ';' or ch == '&' or ch == '>' or ch == '<') break;
            start -= 1;
        }
        const token = line[start..pos];

        // Determine if `token` is in command position (only whitespace since start or last separator).
        var before = start;
        while (before > 0 and (line[before - 1] == ' ' or line[before - 1] == '\t')) : (before -= 1) {}
        const is_cmd_pos = before == 0 or line[before - 1] == '|' or line[before - 1] == ';' or line[before - 1] == '&';

        // 1. Variable completion `$VAR`.
        if (token.len > 0 and token[0] == '$' and std.mem.indexOfScalar(u8, token, '/') == null) {
            const var_prefix = token[1..];
            for (self.vars.items) |v| {
                if (std.mem.startsWith(u8, v.name, var_prefix)) {
                    const cand = try std.fmt.allocPrint(gpa, "${s}", .{v.name});
                    try res.candidates.append(gpa, cand);
                }
            }
            sortStrings(res.candidates.items);
            try finishCompletion(gpa, line, start, pos, " ", &res);
            return res;
        }

        // 2. Command name completion when at command position and no slash.
        if (is_cmd_pos and std.mem.indexOfScalar(u8, token, '/') == null) {
            for (commands.commands) |cmd| {
                if (std.mem.startsWith(u8, cmd.name, token)) {
                    try res.candidates.append(gpa, try gpa.dupe(u8, cmd.name));
                }
            }
            sortStrings(res.candidates.items);
            try finishCompletion(gpa, line, start, pos, " ", &res);
            return res;
        }

        // 3. Path completion.
        const slash = std.mem.lastIndexOfScalar(u8, token, '/');
        const dir_part = if (slash) |s| token[0 .. s + 1] else "";
        const base_prefix = if (slash) |s| token[s + 1 ..] else token;
        const lookup_dir = if (dir_part.len == 0)
            "."
        else if (std.mem.eql(u8, dir_part, "/"))
            "/"
        else
            dir_part[0 .. dir_part.len - 1];

        const resolved_dir = self.resolvePath(lookup_dir) catch return res;
        defer self.gpa.free(resolved_dir);

        var z_buf: [4096]u8 = undefined;
        const z = std.mem.printSentinel(&z_buf, "{s}", .{resolved_dir}, 0) catch return res;
        const rc = linux.open(z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
        if (linux.errno(rc) != .SUCCESS) return res;
        const fd: linux.fd_t = @intCast(rc);
        defer sys.close(fd);

        const want_hidden = base_prefix.len > 0 and base_prefix[0] == '.';
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
                if (!want_hidden and name.len > 0 and name[0] == '.') continue;
                if (std.mem.startsWith(u8, name, base_prefix)) {
                    const full_entry = commands.joinPath(self.gpa, resolved_dir, name) catch continue;
                    defer self.gpa.free(full_entry);
                    const is_dir = if (commands.statPath(full_entry, true)) |st| st.isDir() else |_| false;
                    const cand = if (is_dir)
                        try std.fmt.allocPrint(gpa, "{s}{s}/", .{ dir_part, name })
                    else
                        try std.fmt.allocPrint(gpa, "{s}{s}", .{ dir_part, name });
                    try res.candidates.append(gpa, cand);
                }
            }
        }

        sortStrings(res.candidates.items);
        if (res.candidates.items.len == 1) {
            const single = res.candidates.items[0];
            const suffix = if (std.mem.endsWith(u8, single, "/")) "" else " ";
            try finishCompletion(gpa, line, start, pos, suffix, &res);
        } else {
            try finishCompletion(gpa, line, start, pos, "", &res);
        }
        return res;
    }
};

fn sortStrings(items: [][]u8) void {
    std.mem.sort([]u8, items, {}, struct {
        fn less(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
}

fn finishCompletion(
    gpa: std.mem.Allocator,
    line: []const u8,
    start: usize,
    pos: usize,
    single_suffix: []const u8,
    res: *CompletionResult,
) !void {
    if (res.candidates.items.len == 0) return;
    if (res.candidates.items.len == 1) {
        const match = res.candidates.items[0];
        const new_line = try std.fmt.allocPrint(
            gpa,
            "{s}{s}{s}{s}",
            .{ line[0..start], match, single_suffix, line[pos..] },
        );
        res.replacement_line = new_line;
        res.new_cursor = start + match.len + single_suffix.len;
        return;
    }

    // Multiple candidates: compute longest common prefix.
    const first = res.candidates.items[0];
    var common_len = first.len;
    for (res.candidates.items[1..]) |cand| {
        var i: usize = 0;
        const limit = @min(common_len, cand.len);
        while (i < limit and first[i] == cand[i]) : (i += 1) {}
        common_len = i;
    }
    const common = first[0..common_len];
    if (common.len > pos - start) {
        const new_line = try std.fmt.allocPrint(
            gpa,
            "{s}{s}{s}",
            .{ line[0..start], common, line[pos..] },
        );
        res.replacement_line = new_line;
        res.new_cursor = start + common.len;
    }
}

fn appendFmt(gpa: std.mem.Allocator, list: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) void {
    var stack_buf: [1024]u8 = undefined;
    if (std.fmt.bufPrint(&stack_buf, fmt, args)) |s| {
        list.appendSlice(gpa, s) catch {};
    } else |_| {}
}

pub fn validVarName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!isVarStart(name[0])) return false;
    for (name[1..]) |ch| {
        if (!isVarCont(ch)) return false;
    }
    return true;
}

fn isVarStart(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_';
}

fn isVarCont(ch: u8) bool {
    return isVarStart(ch) or (ch >= '0' and ch <= '9');
}

pub fn normalizePath(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(gpa);

    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |seg| {
        if (seg.len == 0 or std.mem.eql(u8, seg, ".")) continue;
        if (std.mem.eql(u8, seg, "..")) {
            if (parts.items.len > 0) _ = parts.pop();
            continue;
        }
        try parts.append(gpa, seg);
    }

    if (parts.items.len == 0) return gpa.dupe(u8, "/");

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (parts.items) |seg| {
        try out.append(gpa, '/');
        try out.appendSlice(gpa, seg);
    }
    return out.toOwnedSlice(gpa);
}

// --- Lexer / Tokenizer ---------------------------------------------------------

const ChainOp = enum {
    always,
    and_if,
    or_if,
};

const Operator = enum {
    semi,
    and_if,
    or_if,
    pipe,
    redir_in,
    redir_out,
    redir_append,
    redir_err,
    redir_err_append,
    redir_both,
};

const QuoteKind = enum {
    none,
    single,
    double,
};

const WordPart = struct {
    text: []u8,
    quote: QuoteKind,
};

const Word = struct {
    parts: std.ArrayList(WordPart) = .empty,
};

const Token = union(enum) {
    word: Word,
    op: Operator,
};

const TokenizeError = error{
    OutOfMemory,
    UnterminatedSingleQuote,
    UnterminatedDoubleQuote,
    TrailingBackslash,
};

fn freeTokens(gpa: std.mem.Allocator, tokens: *std.ArrayList(Token)) void {
    for (tokens.items) |*tok| switch (tok.*) {
        .word => |*w| {
            for (w.parts.items) |p| gpa.free(p.text);
            w.parts.deinit(gpa);
        },
        .op => {},
    };
    tokens.deinit(gpa);
}

fn tokenize(gpa: std.mem.Allocator, input: []const u8) TokenizeError!std.ArrayList(Token) {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer freeTokens(gpa, &tokens);

    var i: usize = 0;
    while (i < input.len) {
        // Skip whitespace.
        while (i < input.len and (input[i] == ' ' or input[i] == '\t' or input[i] == '\r' or input[i] == '\n')) : (i += 1) {}
        if (i >= input.len) break;

        // Comment until end of line.
        if (input[i] == '#') break;

        // Operators.
        if (input[i] == ';') {
            try tokens.append(gpa, .{ .op = .semi });
            i += 1;
            continue;
        }
        if (input[i] == '&') {
            if (i + 1 < input.len and input[i + 1] == '&') {
                try tokens.append(gpa, .{ .op = .and_if });
                i += 2;
                continue;
            }
            if (i + 1 < input.len and input[i + 1] == '>') {
                try tokens.append(gpa, .{ .op = .redir_both });
                i += 2;
                continue;
            }
            try tokens.append(gpa, .{ .op = .semi });
            i += 1;
            continue;
        }
        if (input[i] == '|') {
            if (i + 1 < input.len and input[i + 1] == '|') {
                try tokens.append(gpa, .{ .op = .or_if });
                i += 2;
                continue;
            }
            try tokens.append(gpa, .{ .op = .pipe });
            i += 1;
            continue;
        }
        if (input[i] == '<') {
            try tokens.append(gpa, .{ .op = .redir_in });
            i += 1;
            continue;
        }
        if (input[i] == '>') {
            if (i + 1 < input.len and input[i + 1] == '>') {
                try tokens.append(gpa, .{ .op = .redir_append });
                i += 2;
                continue;
            }
            try tokens.append(gpa, .{ .op = .redir_out });
            i += 1;
            continue;
        }
        if (input[i] == '2' and i + 1 < input.len and input[i + 1] == '>') {
            if (i + 2 < input.len and input[i + 2] == '>') {
                try tokens.append(gpa, .{ .op = .redir_err_append });
                i += 3;
                continue;
            }
            try tokens.append(gpa, .{ .op = .redir_err });
            i += 2;
            continue;
        }

        // Parse word made of one or more quoted/unquoted segments.
        var word: Word = .{};
        errdefer {
            for (word.parts.items) |p| gpa.free(p.text);
            word.parts.deinit(gpa);
        }

        while (i < input.len) {
            const ch = input[i];
            if (ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n' or ch == ';' or ch == '|' or ch == '&' or ch == '<' or ch == '>') break;
            if (ch == '\'') {
                i += 1;
                const start = i;
                while (i < input.len and input[i] != '\'') : (i += 1) {}
                if (i >= input.len) return error.UnterminatedSingleQuote;
                const slice = try gpa.dupe(u8, input[start..i]);
                errdefer gpa.free(slice);
                try word.parts.append(gpa, .{ .text = slice, .quote = .single });
                i += 1;
            } else if (ch == '"') {
                i += 1;
                var buf: std.ArrayList(u8) = .empty;
                errdefer buf.deinit(gpa);
                while (i < input.len and input[i] != '"') {
                    if (input[i] == '\\') {
                        if (i + 1 >= input.len) return error.UnterminatedDoubleQuote;
                        const esc = input[i + 1];
                        if (esc == '"' or esc == '\\' or esc == '$') {
                            try buf.append(gpa, esc);
                            i += 2;
                            continue;
                        }
                    }
                    try buf.append(gpa, input[i]);
                    i += 1;
                }
                if (i >= input.len) return error.UnterminatedDoubleQuote;
                i += 1;
                const slice = try buf.toOwnedSlice(gpa);
                errdefer gpa.free(slice);
                try word.parts.append(gpa, .{ .text = slice, .quote = .double });
            } else {
                var buf: std.ArrayList(u8) = .empty;
                errdefer buf.deinit(gpa);
                while (i < input.len) {
                    const c = input[i];
                    if (c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == ';' or c == '|' or c == '&' or c == '<' or c == '>' or c == '\'' or c == '"') break;
                    if (c == '\\') {
                        if (i + 1 >= input.len) return error.TrailingBackslash;
                        try buf.append(gpa, input[i + 1]);
                        i += 2;
                        continue;
                    }
                    try buf.append(gpa, c);
                    i += 1;
                }
                const slice = try buf.toOwnedSlice(gpa);
                errdefer gpa.free(slice);
                try word.parts.append(gpa, .{ .text = slice, .quote = .none });
            }
        }

        try tokens.append(gpa, .{ .word = word });
    }

    return tokens;
}

// --- Tests ---------------------------------------------------------------------

const TestSandbox = struct {
    gpa: std.mem.Allocator,
    path: []u8,

    fn create(gpa: std.mem.Allocator, suffix: []const u8) !TestSandbox {
        const pid = linux.getpid();
        const ns = sys.nowNs();
        var cwd_buf: [4096]u8 = undefined;
        const rc = linux.getcwd(&cwd_buf, cwd_buf.len);
        const base = if (linux.errno(rc) == .SUCCESS) std.mem.sliceTo(&cwd_buf, 0) else "/tmp";
        const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/term-test-{d}-{d}-{s}", .{ base, pid, ns, suffix });
        errdefer gpa.free(path);
        try commands.mkdirParents(path);
        return .{ .gpa = gpa, .path = path };
    }

    fn destroy(self: *TestSandbox) void {
        var sh = Shell.initTest(self.gpa, "/") catch {
            self.gpa.free(self.path);
            return;
        };
        defer sh.deinit();
        var cx: commands.Context = .{
            .gpa = self.gpa,
            .shell = &sh,
            .stdin = "",
        };
        defer cx.deinit();
        if (commands.find("rm")) |rm| {
            _ = rm.run(&cx, &.{ "-rf", self.path });
        }
        self.gpa.free(self.path);
    }
};

fn lastStdout(sh: *const Shell) []const u8 {
    var i = sh.output.items.len;
    while (i > 0) {
        i -= 1;
        if (sh.output.items[i].kind == .stdout) return sh.output.items[i].text;
    }
    return "";
}

test "normalizePath resolves dots and slashes" {
    const gpa = std.testing.allocator;
    {
        const p = try normalizePath(gpa, "/a/b/../c/./d//");
        defer gpa.free(p);
        try std.testing.expectEqualStrings("/a/c/d", p);
    }
    {
        const p = try normalizePath(gpa, "/../../..");
        defer gpa.free(p);
        try std.testing.expectEqualStrings("/", p);
    }
}

test "variables, quoting, chaining, and exit status" {
    const gpa = std.testing.allocator;
    var sh = try Shell.initTest(gpa, "/");
    defer sh.deinit();

    sh.executeLine("FOO='hello world'; BAR=\"$FOO!\"; echo $BAR");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expectEqualStrings("hello world!", lastStdout(&sh));

    sh.executeLine("false && echo nope || echo fallback");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expectEqualStrings("fallback", lastStdout(&sh));

    sh.executeLine("false; echo status:$?");
    try std.testing.expectEqualStrings("status:1", lastStdout(&sh));
}

test "filesystem tools: mkdir, touch, ls, cp, mv, ln, stat, rm, rmdir" {
    const gpa = std.testing.allocator;
    var box = try TestSandbox.create(gpa, "fs");
    defer box.destroy();

    var sh = try Shell.initTest(gpa, box.path);
    defer sh.deinit();

    sh.executeLine("mkdir -p sub/nested && touch sub/nested/a.txt");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);

    sh.executeLine("echo 'hello dazzle' > sub/nested/a.txt");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);

    sh.executeLine("cp -r sub sub_copy && cat sub_copy/nested/a.txt");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expectEqualStrings("hello dazzle", lastStdout(&sh));

    sh.executeLine("mv sub_copy/nested/a.txt sub_copy/moved.txt && cat sub_copy/moved.txt");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expectEqualStrings("hello dazzle", lastStdout(&sh));

    sh.executeLine("ln -s moved.txt sub_copy/link.txt && readlink sub_copy/link.txt");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expectEqualStrings("moved.txt", lastStdout(&sh));

    sh.executeLine("rmdir sub_copy/nested && rm sub_copy/link.txt sub_copy/moved.txt && rmdir sub_copy");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);

    sh.executeLine("ls sub/nested");
    try std.testing.expectEqualStrings("a.txt", lastStdout(&sh));
}

test "pipelines and text filters: grep, sort, uniq, wc, tr, cut, head, tail" {
    const gpa = std.testing.allocator;
    var box = try TestSandbox.create(gpa, "pipe");
    defer box.destroy();

    var sh = try Shell.initTest(gpa, box.path);
    defer sh.deinit();

    sh.executeLine("echo -e 'banana\\napple\\nbanana\\ncherry\\napricot' > fruits.txt");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);

    sh.executeLine("cat fruits.txt | grep ap | sort | wc -l");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expectEqualStrings("2", lastStdout(&sh));

    sh.executeLine("sort fruits.txt | uniq | head -n 2 | tail -n 1 | tr a-z A-Z");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expectEqualStrings("APRICOT", lastStdout(&sh));

    sh.executeLine("echo 'one:two:three' | cut -d : -f 2");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expectEqualStrings("two", lastStdout(&sh));
}

test "globbing and tab completion" {
    const gpa = std.testing.allocator;
    var box = try TestSandbox.create(gpa, "glob");
    defer box.destroy();

    var sh = try Shell.initTest(gpa, box.path);
    defer sh.deinit();

    sh.executeLine("touch alpha.txt beta.txt gamma.log && mkdir docs");
    sh.executeLine("echo *.txt");
    try std.testing.expectEqualStrings("alpha.txt beta.txt", lastStdout(&sh));

    var comp1 = try sh.complete("ec", 2, gpa);
    defer comp1.deinit(gpa);
    try std.testing.expectEqualStrings("echo ", comp1.replacement_line.?);

    var comp2 = try sh.complete("cat al", 6, gpa);
    defer comp2.deinit(gpa);
    try std.testing.expectEqualStrings("cat alpha.txt ", comp2.replacement_line.?);

    var comp3 = try sh.complete("cd do", 5, gpa);
    defer comp3.deinit(gpa);
    try std.testing.expectEqualStrings("cd docs/", comp3.replacement_line.?);
}

test "network tools: ping and wget over loopback" {
    const gpa = std.testing.allocator;
    var box = try TestSandbox.create(gpa, "net");
    defer box.destroy();

    var sh = try Shell.initTest(gpa, box.path);
    defer sh.deinit();

    // Test ping -c 1 localhost.
    sh.executeLine("ping -c 1 localhost");
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expect(std.mem.startsWith(u8, lastStdout(&sh), "rtt min/avg/max ="));

    // Spin up a one-shot HTTP server on 127.0.0.1:0 to test wget.
    const lfd: linux.fd_t = @intCast(try sys.check(linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0)));
    defer sys.close(lfd);
    var bind_addr: linux.sockaddr.in = .{
        .port = 0,
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
    };
    _ = try sys.check(linux.bind(lfd, @ptrCast(&bind_addr), @sizeOf(linux.sockaddr.in)));
    _ = try sys.check(linux.listen(lfd, 2));
    var bound_len: linux.socklen_t = @sizeOf(linux.sockaddr.in);
    _ = try sys.check(linux.getsockname(lfd, @ptrCast(&bind_addr), &bound_len));
    const port = std.mem.bigToNative(u16, bind_addr.port);

    const ServerThread = struct {
        fn serve(fd: linux.fd_t) void {
            for (0..2) |_| {
                const c_rc = linux.accept4(fd, null, null, linux.SOCK.CLOEXEC);
                if (linux.errno(c_rc) != .SUCCESS) return;
                const cfd: linux.fd_t = @intCast(c_rc);
                defer sys.close(cfd);
                var req_buf: [512]u8 = undefined;
                _ = linux.read(cfd, &req_buf, req_buf.len);
                const resp =
                    "HTTP/1.1 200 OK\r\n" ++
                    "Content-Length: 19\r\n" ++
                    "Connection: close\r\n\r\n" ++
                    "fetched from dazzle";
                _ = linux.write(cfd, resp.ptr, resp.len);
            }
        }
    };
    const thr = try std.Thread.spawn(.{}, ServerThread.serve, .{lfd});
    defer thr.join();

    var cmd_buf: [256]u8 = undefined;
    const cmd1 = try std.fmt.bufPrint(&cmd_buf, "wget http://127.0.0.1:{d}/hello.txt && cat hello.txt", .{port});
    sh.executeLine(cmd1);
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expectEqualStrings("fetched from dazzle", lastStdout(&sh));

    const cmd2 = try std.fmt.bufPrint(&cmd_buf, "wget -q -O - http://127.0.0.1:{d}/hello.txt", .{port});
    sh.executeLine(cmd2);
    try std.testing.expectEqual(@as(u8, 0), sh.last_status);
    try std.testing.expectEqualStrings("fetched from dazzle", lastStdout(&sh));
}
