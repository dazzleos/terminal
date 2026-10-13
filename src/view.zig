//! The terminal window's widgets: a title bar, the interactive terminal
//! surface showing scrollback and the active command prompt, and a status bar
//! at the bottom showing the working directory and last exit status.

const std = @import("std");
const ui = @import("ui");
const gfx = @import("gfx");
const font = @import("font");
const shell_mod = @import("shell.zig");

pub const min_size = [2]u32{ 480, 320 };
pub const open_size = [2]u32{ 960, 720 };

// Additional Linux key codes (input-event-codes.h) for shell editing shortcuts.
const key_w: u32 = 17;
const key_e: u32 = 18;
const key_u: u32 = 22;
const key_d: u32 = 32;
const key_k: u32 = 37;
const key_l: u32 = 38;

pub const Terminal = struct {
    shell: *shell_mod.Shell,
    on_close: ?ui.Callback = null,
    on_maximize: ?ui.Callback = null,
    on_drag: ?ui.Callback = null,
    maximized: bool = true,

    pub fn build(self: *const Terminal, cx: *ui.Context) ui.Widget {
        const t = cx.theme();
        const cwd = self.shell.cwd.items;
        const status_text = if (self.shell.last_status == 0)
            cx.fmt("Ready \u{00b7} {d} built-in tools", .{shell_mod.commands.commands.len})
        else
            cx.fmt("Exit {d}", .{self.shell.last_status});
        const status_color = if (self.shell.last_status == 0) t.on_surface_variant else t.@"error";

        return cx.make(ui.Column{ .cross_axis_alignment = .stretch, .children = &.{
            cx.make(ui.TitleBar{
                .title = "Terminal",
                .on_close = self.on_close,
                .on_maximize = self.on_maximize,
                .on_drag = self.on_drag,
                .maximized = self.maximized,
            }),
            cx.make(ui.Expanded{ .child = cx.make(ui.Padding{
                .padding = .all(12),
                .child = cx.make(TerminalArea{
                    .shell = self.shell,
                    .on_exit = self.on_close,
                    .autofocus = true,
                }),
            }) }),
            cx.make(ui.Padding{
                .padding = .{ .left = 16, .right = 16, .bottom = 10 },
                .child = cx.make(ui.Row{ .spacing = 16, .children = &.{
                    cx.make(ui.Expanded{ .child = cx.make(ui.Text{
                        .text = cwd,
                        .style = .{ .size = 15, .color = t.on_surface_variant },
                        .wrap = false,
                        .ellipsis = true,
                    }) }),
                    cx.make(ui.Text{
                        .text = status_text,
                        .style = .{ .size = 15, .color = status_color },
                        .wrap = false,
                    }),
                } }),
            }),
        } });
    }
};

pub const TerminalArea = struct {
    shell: *shell_mod.Shell,
    size: f32 = 16,
    autofocus: bool = true,
    on_exit: ?ui.Callback = null,

    pub const pad: f32 = 12;

    const DisplayRow = struct {
        line_idx: usize, // index in shell.output, or shell.output.items.len for active prompt row
        start: usize,
        end: usize,
        kind: shell_mod.LineKind,
        prompt_prefix_len: usize = 0,
    };

    pub const State = struct {
        gpa: ?std.mem.Allocator = null,
        shell: ?*shell_mod.Shell = null,
        node: ?*ui.Node = null,
        on_exit: ?ui.Callback = null,
        input: std.ArrayList(u8) = .empty,
        saved_input: std.ArrayList(u8) = .empty,
        cursor: usize = 0,
        history_index: ?usize = null,
        scroll: f32 = 0,
        follow_bottom: bool = true,
        focused: bool = false,
        autofocused: bool = false,
        dragging: bool = false,
        sel_anchor_row: ?usize = null,
        sel_anchor_col: usize = 0,
        sel_cursor_row: ?usize = null,
        sel_cursor_col: usize = 0,
        rows: std.ArrayList(DisplayRow) = .empty,
        prompt_line: std.ArrayList(u8) = .empty,
        prompt_prefix_len: usize = 0,

        pub fn deinit(s: *State) void {
            if (s.gpa) |g| {
                s.input.deinit(g);
                s.saved_input.deinit(g);
                s.rows.deinit(g);
                s.prompt_line.deinit(g);
            }
        }

        pub fn hasSelection(s: *const State) bool {
            const ar = s.sel_anchor_row orelse return false;
            const cr = s.sel_cursor_row orelse return false;
            return ar != cr or s.sel_anchor_col != s.sel_cursor_col;
        }

        pub fn clearSelection(s: *State) void {
            s.sel_anchor_row = null;
            s.sel_cursor_row = null;
        }

        pub fn copy(s: *State) void {
            const g = s.gpa orelse return;
            const n = s.node orelse return;
            const sh = s.shell orelse return;
            if (!s.hasSelection()) {
                if (s.input.items.len > 0) {
                    n.ui.copyText(s.input.items);
                }
                return;
            }
            const ar = s.sel_anchor_row.?;
            const cr = s.sel_cursor_row.?;
            const r0, const c0, const r1, const c1 = if (ar < cr or (ar == cr and s.sel_anchor_col <= s.sel_cursor_col))
                .{ ar, s.sel_anchor_col, cr, s.sel_cursor_col }
            else
                .{ cr, s.sel_cursor_col, ar, s.sel_anchor_col };

            var buf: std.ArrayList(u8) = .empty;
            defer buf.deinit(g);
            var row_idx = r0;
            while (row_idx <= r1 and row_idx < s.rows.items.len) : (row_idx += 1) {
                const row = s.rows.items[row_idx];
                const full = s.rowFullText(sh, row);
                const slice = full[row.start..row.end];
                const a = if (row_idx == r0) @min(c0, slice.len) else 0;
                const b = if (row_idx == r1) @min(c1, slice.len) else slice.len;
                if (b > a) buf.appendSlice(g, slice[a..b]) catch return;
                if (row_idx < r1) buf.append(g, '\n') catch return;
            }
            if (buf.items.len > 0) {
                n.ui.copyText(buf.items);
            }
        }

        pub fn paste(s: *State) void {
            const n = s.node orelse return;
            n.ui.pasteText(n, .of(s, State.pasted));
        }

        fn pasted(s: *State, text: []const u8) void {
            s.insertText(text);
            if (s.node) |n| n.ui.needs_frame = true;
        }

        pub fn selectAll(s: *State) void {
            if (s.rows.items.len == 0) return;
            const sh = s.shell orelse return;
            s.sel_anchor_row = 0;
            s.sel_anchor_col = 0;
            const last_idx = s.rows.items.len - 1;
            const last_row = s.rows.items[last_idx];
            const full = s.rowFullText(sh, last_row);
            s.sel_cursor_row = last_idx;
            s.sel_cursor_col = last_row.end - last_row.start;
            _ = full;
            if (s.node) |n| n.ui.needs_frame = true;
        }

        pub fn clearTerminal(s: *State) void {
            const sh = s.shell orelse return;
            sh.clearOutput();
            s.scroll = 0;
            s.follow_bottom = true;
            s.clearSelection();
            if (s.node) |n| n.ui.needs_frame = true;
        }

        fn rowFullText(s: *const State, sh: *const shell_mod.Shell, row: DisplayRow) []const u8 {
            if (row.line_idx < sh.output.items.len) {
                return sh.output.items[row.line_idx].text;
            }
            return s.prompt_line.items;
        }

        pub fn insertText(s: *State, text: []const u8) void {
            const g = s.gpa orelse return;
            const sh = s.shell orelse return;
            s.clearSelection();
            s.follow_bottom = true;

            var at: usize = 0;
            while (at < text.len) {
                const seq_len = std.unicode.utf8ByteSequenceLength(text[at]) catch {
                    at += 1;
                    continue;
                };
                if (at + seq_len > text.len) break;
                const cp = std.unicode.utf8Decode(text[at..][0..seq_len]) catch {
                    at += 1;
                    continue;
                };
                const piece = text[at .. at + seq_len];
                at += seq_len;
                if (cp == '\n' or cp == '\r') {
                    s.submitLine();
                    if (sh.should_exit) {
                        if (s.on_exit) |cb| cb.call();
                        return;
                    }
                    continue;
                }
                if (cp == '\t') {
                    s.input.insertSlice(g, s.cursor, "    ") catch return;
                    s.cursor += 4;
                    continue;
                }
                if (cp < 0x20 or (cp >= 0x7f and cp <= 0x9f)) continue;
                s.input.insertSlice(g, s.cursor, piece) catch return;
                s.cursor += piece.len;
            }
        }

        pub fn submitLine(s: *State) void {
            const g = s.gpa orelse return;
            const sh = s.shell orelse return;
            const copy_line = g.dupe(u8, s.input.items) catch return;
            defer g.free(copy_line);
            s.input.clearRetainingCapacity();
            s.saved_input.clearRetainingCapacity();
            s.cursor = 0;
            s.history_index = null;
            s.clearSelection();
            s.follow_bottom = true;
            sh.executeLine(copy_line);
        }
    };

    fn style(self: *const TerminalArea, n: *const ui.Node) ?font.Style {
        const f = n.ui.font orelse return null;
        return .{ .font = f, .size = self.size };
    }

    fn remember(self: *const TerminalArea, n: *ui.Node) *State {
        const st = n.state(State);
        st.gpa = n.ui.gpa;
        st.shell = self.shell;
        st.node = n;
        st.on_exit = self.on_exit;
        return st;
    }

    pub fn layout(self: *const TerminalArea, n: *ui.Node, c: ui.Constraints) ui.Size {
        const st = self.remember(n);
        if (self.autofocus and !st.autofocused) {
            st.autofocused = true;
            n.ui.focus(n);
        }
        const size = c.constrain(.{
            .w = if (c.boundedWidth()) c.max_w else 480,
            .h = if (c.boundedHeight()) c.max_h else 320,
        });
        self.buildRows(n, st, @max(64, size.w - 2 * pad));

        if (self.style(n)) |s| {
            const lh = s.lineHeight();
            const content_h = @as(f32, @floatFromInt(st.rows.items.len)) * lh + 2 * pad;
            const max_scroll = @max(0, content_h - size.h);
            if (st.follow_bottom) {
                st.scroll = max_scroll;
            } else {
                st.scroll = std.math.clamp(st.scroll, 0, max_scroll);
            }
        }
        return size;
    }

    fn buildRows(self: *const TerminalArea, n: *ui.Node, st: *State, avail_w: f32) void {
        const g = n.ui.gpa;
        const sh = self.shell;
        st.rows.clearRetainingCapacity();

        // Build active prompt line (`<prompt><input>`).
        var prompt_buf: [512]u8 = undefined;
        const prompt = sh.formatPrompt(&prompt_buf);
        st.prompt_line.clearRetainingCapacity();
        st.prompt_line.appendSlice(g, prompt) catch {};
        st.prompt_line.appendSlice(g, st.input.items) catch {};
        st.prompt_prefix_len = prompt.len;

        const s = self.style(n);
        for (sh.output.items, 0..) |out_line, idx| {
            const p_len: usize = if (out_line.kind == .prompt) promptPrefixLen(out_line.text) else 0;
            wrapLineInto(g, &st.rows, idx, out_line.text, out_line.kind, p_len, s, avail_w);
        }
        wrapLineInto(
            g,
            &st.rows,
            sh.output.items.len,
            st.prompt_line.items,
            .prompt,
            st.prompt_prefix_len,
            s,
            avail_w,
        );
    }

    fn promptPrefixLen(text: []const u8) usize {
        if (std.mem.indexOf(u8, text, " $ ")) |idx| return idx + 3;
        if (std.mem.indexOf(u8, text, " # ")) |idx| return idx + 3;
        return 0;
    }

    fn wrapLineInto(
        gpa: std.mem.Allocator,
        rows: *std.ArrayList(DisplayRow),
        line_idx: usize,
        text: []const u8,
        kind: shell_mod.LineKind,
        prompt_prefix_len: usize,
        maybe_style: ?font.Style,
        avail_w: f32,
    ) void {
        if (text.len == 0 or maybe_style == null or avail_w <= 0) {
            rows.append(gpa, .{
                .line_idx = line_idx,
                .start = 0,
                .end = text.len,
                .kind = kind,
                .prompt_prefix_len = prompt_prefix_len,
            }) catch {};
            return;
        }
        const s = maybe_style.?;
        if (font.measure(s, text) <= avail_w) {
            rows.append(gpa, .{
                .line_idx = line_idx,
                .start = 0,
                .end = text.len,
                .kind = kind,
                .prompt_prefix_len = prompt_prefix_len,
            }) catch {};
            return;
        }

        var start: usize = 0;
        while (start < text.len) {
            var end = start;
            var last_Step = start;
            while (end < text.len) {
                const seq = std.unicode.utf8ByteSequenceLength(text[end]) catch 1;
                const next = @min(text.len, end + seq);
                if (next > start and font.measure(s, text[start..next]) > avail_w) break;
                end = next;
                last_Step = end;
            }
            if (last_Step == start) {
                const seq = std.unicode.utf8ByteSequenceLength(text[start]) catch 1;
                last_Step = @min(text.len, start + seq);
            }
            rows.append(gpa, .{
                .line_idx = line_idx,
                .start = start,
                .end = last_Step,
                .kind = kind,
                .prompt_prefix_len = prompt_prefix_len,
            }) catch return;
            start = last_Step;
        }
    }

    pub fn paint(self: *const TerminalArea, n: *ui.Node, p: *ui.Painter) void {
        const t = &n.ui.theme;
        const st = n.state(State);
        const c = p.canvas();
        const r: gfx.Rect = .{ .x = 0, .y = 0, .w = n.size.w, .h = n.size.h };

        // Terminal surface background and border.
        c.fillRoundedRect(r, .all(6), t.surface_container);
        if (st.focused) {
            c.strokeRoundedRect(r.outset(-1), .all(6), 2, t.primary);
        } else {
            c.strokeRoundedRect(r.outset(-0.5), .all(6), 1, t.outline_variant);
        }

        const s = self.style(n) orelse return;
        const lh = s.lineHeight();
        const old_clip = p.clipTo(.{ .x = 2, .y = 2, .w = @max(0, n.size.w - 4), .h = @max(0, n.size.h - 4) });
        defer p.restoreClip(old_clip);

        const sh = self.shell;
        const rows = st.rows.items;
        const first: usize = @intFromFloat(@max(0, @floor((st.scroll - pad) / lh)));

        const has_sel = st.hasSelection();
        var sel_r0: usize = 0;
        var sel_c0: usize = 0;
        var sel_r1: usize = 0;
        var sel_c1: usize = 0;
        if (has_sel) {
            const ar = st.sel_anchor_row.?;
            const cr = st.sel_cursor_row.?;
            if (ar < cr or (ar == cr and st.sel_anchor_col <= st.sel_cursor_col)) {
                sel_r0 = ar;
                sel_c0 = st.sel_anchor_col;
                sel_r1 = cr;
                sel_c1 = st.sel_cursor_col;
            } else {
                sel_r0 = cr;
                sel_c0 = st.sel_cursor_col;
                sel_r1 = ar;
                sel_c1 = st.sel_anchor_col;
            }
        }

        var i = first;
        while (i < rows.len) : (i += 1) {
            const top = pad + @as(f32, @floatFromInt(i)) * lh - st.scroll;
            if (top > n.size.h) break;
            const row = rows[i];
            const full = st.rowFullText(sh, row);
            const slice = full[row.start..row.end];
            const baseline = top + s.ascent();

            // Draw selection highlight if this row is selected.
            if (has_sel and i >= sel_r0 and i <= sel_r1) {
                const a = if (i == sel_r0) @min(sel_c0, slice.len) else 0;
                const b = if (i == sel_r1) @min(sel_c1, slice.len) else slice.len;
                if (b > a) {
                    const x0 = font.measure(s, slice[0..a]);
                    const x1 = font.measure(s, slice[0..b]);
                    c.fillRect(
                        .{ .x = pad + x0, .y = top, .w = @max(4, x1 - x0), .h = lh },
                        t.primary.withAlpha(if (st.focused) 0.35 else 0.18),
                    );
                }
            }

            // Draw text with semantic terminal coloring.
            switch (row.kind) {
                .prompt => {
                    if (row.start < row.prompt_prefix_len) {
                        const prefix_end = @min(row.end, row.prompt_prefix_len);
                        const prefix_slice = full[row.start..prefix_end];
                        const x_after = p.text(s.size, pad, baseline, prefix_slice, t.primary);
                        if (row.end > prefix_end) {
                            const cmd_slice = full[prefix_end..row.end];
                            _ = p.text(s.size, x_after, baseline, cmd_slice, t.on_surface);
                        }
                    } else {
                        _ = p.text(s.size, pad, baseline, slice, t.on_surface);
                    }
                },
                .stdout => {
                    _ = p.text(s.size, pad, baseline, slice, t.on_surface);
                },
                .stderr => {
                    _ = p.text(s.size, pad, baseline, slice, t.@"error");
                },
                .info => {
                    _ = p.text(s.size, pad, baseline, slice, t.syntax.type);
                },
            }
        }

        // Draw cursor on the active prompt line.
        if (st.focused) {
            const target_byte = st.prompt_prefix_len + st.cursor;
            const prompt_line_idx = sh.output.items.len;
            var cursor_row_idx: ?usize = null;
            for (rows, 0..) |row, r_idx| {
                if (row.line_idx == prompt_line_idx) {
                    if (target_byte >= row.start and target_byte <= row.end) {
                        cursor_row_idx = r_idx;
                        break;
                    }
                }
            }
            if (cursor_row_idx) |r_idx| {
                const row = rows[r_idx];
                const full = st.prompt_line.items;
                const x = pad + font.measure(s, full[row.start..@min(target_byte, row.end)]);
                const top = pad + @as(f32, @floatFromInt(r_idx)) * lh - st.scroll;
                c.fillRect(.{ .x = @round(x), .y = top + 1, .w = 2.5, .h = lh - 2 }, t.primary);
            }
        }

        // Draw scrollbar if content is taller than viewport.
        const content_h = @as(f32, @floatFromInt(rows.len)) * lh + 2 * pad;
        if (content_h > n.size.h and n.size.h > 16) {
            const track_h = n.size.h - 12;
            const thumb_h = @max(24, track_h * (n.size.h / content_h));
            const max_scroll = content_h - n.size.h;
            const ratio = if (max_scroll > 0) std.math.clamp(st.scroll / max_scroll, 0, 1) else 0;
            const thumb_y = 6 + (track_h - thumb_h) * ratio;
            c.fillRoundedRect(
                .{ .x = n.size.w - 7, .y = thumb_y, .w = 4, .h = thumb_h },
                .all(2),
                t.on_surface_variant.withAlpha(0.45),
            );
        }
    }

    pub fn event(self: *const TerminalArea, n: *ui.Node, e: ui.Event) bool {
        const st = self.remember(n);
        switch (e) {
            .press => |pr| {
                if (pr.button != ui.btn_left) return false;
                n.ui.focus(n);
                const pos = self.hitPos(n, st, pr.pos);
                st.sel_anchor_row = pos.row;
                st.sel_anchor_col = pos.col;
                st.sel_cursor_row = pos.row;
                st.sel_cursor_col = pos.col;
                st.dragging = true;

                // If clicking on the active prompt line, also position the input cursor there.
                if (pos.row < st.rows.items.len) {
                    const row = st.rows.items[pos.row];
                    if (row.line_idx == self.shell.output.items.len) {
                        const abs_byte = row.start + pos.col;
                        if (abs_byte >= st.prompt_prefix_len) {
                            st.cursor = utf8At(st.input.items, abs_byte - st.prompt_prefix_len);
                        } else {
                            st.cursor = 0;
                        }
                    }
                }
                n.ui.needs_frame = true;
                return true;
            },
            .motion => |pos| if (st.dragging) {
                const hit = self.hitPos(n, st, pos);
                st.sel_cursor_row = hit.row;
                st.sel_cursor_col = hit.col;
                n.ui.needs_frame = true;
            },
            .release => {
                st.dragging = false;
                if (!st.hasSelection()) st.clearSelection();
                return true;
            },
            .scroll => |sc| {
                st.follow_bottom = false;
                st.scroll += sc.dy;
                if (self.style(n)) |s| {
                    const lh = s.lineHeight();
                    const content_h = @as(f32, @floatFromInt(st.rows.items.len)) * lh + 2 * pad;
                    const max_scroll = @max(0, content_h - n.size.h);
                    if (st.scroll >= max_scroll - 2) {
                        st.follow_bottom = true;
                    }
                }
                n.ui.needs_frame = true;
                return true;
            },
            .focus => st.focused = true,
            .blur => st.focused = false,
            .key => |k| {
                if (!k.pressed) return true;
                self.handleKey(n, st, k);
                n.ui.needs_frame = true;
                return true;
            },
            .context => |pos| {
                n.ui.focus(n);
                st.dragging = false;
                const can_copy = st.hasSelection() or st.input.items.len > 0;
                const origin = n.position();
                n.ui.openMenu(n, .{ origin[0] + pos[0], origin[1] + pos[1] }, &.{
                    .{ .label = "Copy", .shortcut = "Ctrl+C", .enabled = can_copy, .on_press = .of(st, State.copy) },
                    .{ .label = "Paste", .shortcut = "Ctrl+V", .on_press = .of(st, State.paste) },
                    .{ .label = "Select all", .shortcut = "Ctrl+A", .enabled = st.rows.items.len > 0, .on_press = .of(st, State.selectAll) },
                    .{ .label = "Clear", .shortcut = "Ctrl+L", .on_press = .of(st, State.clearTerminal) },
                });
                return true;
            },
            else => {},
        }
        return false;
    }

    const HitPos = struct { row: usize, col: usize };

    fn hitPos(self: *const TerminalArea, n: *ui.Node, st: *State, pt: ui.Point) HitPos {
        if (st.rows.items.len == 0) return .{ .row = 0, .col = 0 };
        const s = self.style(n) orelse return .{ .row = 0, .col = 0 };
        const lh = s.lineHeight();
        const y = @max(0, pt[1] - pad + st.scroll);
        const row_idx = @min(@as(usize, @intFromFloat(@floor(y / lh))), st.rows.items.len - 1);
        const row = st.rows.items[row_idx];
        const full = st.rowFullText(self.shell, row);
        const slice = full[row.start..row.end];
        const target_x = @max(0, pt[0] - pad);

        var col: usize = 0;
        var prev_w: f32 = 0;
        while (col < slice.len) {
            const seq = std.unicode.utf8ByteSequenceLength(slice[col]) catch 1;
            const next = @min(slice.len, col + seq);
            const w = font.measure(s, slice[0..next]);
            if (w >= target_x) {
                if (target_x - prev_w < w - target_x) return .{ .row = row_idx, .col = col };
                return .{ .row = row_idx, .col = next };
            }
            prev_w = w;
            col = next;
        }
        return .{ .row = row_idx, .col = slice.len };
    }

    fn handleKey(self: *const TerminalArea, n: *ui.Node, st: *State, k: ui.Event.Key) void {
        const g = n.ui.gpa;
        const sh = self.shell;

        if (k.ctrl) {
            switch (k.code) {
                ui.keymap.key_c => {
                    if (k.shift or st.hasSelection()) {
                        st.copy();
                        st.clearSelection();
                    } else {
                        // Interrupt current input line (^C).
                        var prompt_buf: [512]u8 = undefined;
                        const prompt = sh.formatPrompt(&prompt_buf);
                        var line_buf: std.ArrayList(u8) = .empty;
                        defer line_buf.deinit(g);
                        line_buf.appendSlice(g, prompt) catch {};
                        line_buf.appendSlice(g, st.input.items) catch {};
                        line_buf.appendSlice(g, "^C") catch {};
                        sh.appendLine(line_buf.items, .prompt) catch {};
                        st.input.clearRetainingCapacity();
                        st.cursor = 0;
                        st.history_index = null;
                        sh.last_status = 130;
                        st.follow_bottom = true;
                    }
                    return;
                },
                ui.keymap.key_v => {
                    st.paste();
                    return;
                },
                ui.keymap.key_a => {
                    if (k.shift) {
                        st.selectAll();
                    } else {
                        st.cursor = 0;
                        st.follow_bottom = true;
                    }
                    return;
                },
                key_e => {
                    st.cursor = st.input.items.len;
                    st.follow_bottom = true;
                    return;
                },
                key_l => {
                    st.clearTerminal();
                    return;
                },
                key_u => {
                    if (st.cursor > 0) {
                        st.input.replaceRangeAssumeCapacity(0, st.cursor, &.{});
                        st.cursor = 0;
                    }
                    st.follow_bottom = true;
                    return;
                },
                key_k => {
                    if (st.cursor < st.input.items.len) {
                        st.input.shrinkRetainingCapacity(st.cursor);
                    }
                    st.follow_bottom = true;
                    return;
                },
                key_w => {
                    const prev = wordBefore(st.input.items, st.cursor);
                    if (prev < st.cursor) {
                        st.input.replaceRangeAssumeCapacity(prev, st.cursor - prev, &.{});
                        st.cursor = prev;
                    }
                    st.follow_bottom = true;
                    return;
                },
                key_d => {
                    if (st.input.items.len == 0) {
                        sh.should_exit = true;
                        if (self.on_exit) |cb| cb.call();
                    } else if (st.cursor < st.input.items.len) {
                        const next = utf8After(st.input.items, st.cursor);
                        st.input.replaceRangeAssumeCapacity(st.cursor, next - st.cursor, &.{});
                    }
                    return;
                },
                ui.keymap.left => {
                    st.cursor = wordBefore(st.input.items, st.cursor);
                    st.follow_bottom = true;
                    return;
                },
                ui.keymap.right => {
                    st.cursor = wordAfter(st.input.items, st.cursor);
                    st.follow_bottom = true;
                    return;
                },
                else => return,
            }
        }

        switch (k.code) {
            ui.keymap.enter, ui.keymap.keypad_enter => {
                st.submitLine();
                if (sh.should_exit) {
                    if (self.on_exit) |cb| cb.call();
                }
            },
            ui.keymap.backspace => {
                st.clearSelection();
                st.follow_bottom = true;
                if (st.cursor > 0) {
                    const prev = utf8Before(st.input.items, st.cursor);
                    st.input.replaceRangeAssumeCapacity(prev, st.cursor - prev, &.{});
                    st.cursor = prev;
                }
            },
            ui.keymap.delete => {
                st.clearSelection();
                st.follow_bottom = true;
                if (st.cursor < st.input.items.len) {
                    const next = utf8After(st.input.items, st.cursor);
                    st.input.replaceRangeAssumeCapacity(st.cursor, next - st.cursor, &.{});
                }
            },
            ui.keymap.left => {
                st.clearSelection();
                st.follow_bottom = true;
                if (st.cursor > 0) st.cursor = utf8Before(st.input.items, st.cursor);
            },
            ui.keymap.right => {
                st.clearSelection();
                st.follow_bottom = true;
                if (st.cursor < st.input.items.len) st.cursor = utf8After(st.input.items, st.cursor);
            },
            ui.keymap.home => {
                st.clearSelection();
                st.follow_bottom = true;
                st.cursor = 0;
            },
            ui.keymap.end => {
                st.clearSelection();
                st.follow_bottom = true;
                st.cursor = st.input.items.len;
            },
            ui.keymap.up => {
                st.clearSelection();
                st.follow_bottom = true;
                const hist = sh.history.items;
                if (hist.len == 0) return;
                if (st.history_index == null) {
                    st.saved_input.clearRetainingCapacity();
                    st.saved_input.appendSlice(g, st.input.items) catch return;
                    st.history_index = hist.len - 1;
                } else if (st.history_index.? > 0) {
                    st.history_index = st.history_index.? - 1;
                } else {
                    return;
                }
                const chosen = hist[st.history_index.?];
                st.input.clearRetainingCapacity();
                st.input.appendSlice(g, chosen) catch return;
                st.cursor = st.input.items.len;
            },
            ui.keymap.down => {
                st.clearSelection();
                st.follow_bottom = true;
                const idx = st.history_index orelse return;
                const hist = sh.history.items;
                if (idx + 1 < hist.len) {
                    st.history_index = idx + 1;
                    const chosen = hist[st.history_index.?];
                    st.input.clearRetainingCapacity();
                    st.input.appendSlice(g, chosen) catch return;
                    st.cursor = st.input.items.len;
                } else {
                    st.history_index = null;
                    st.input.clearRetainingCapacity();
                    st.input.appendSlice(g, st.saved_input.items) catch return;
                    st.cursor = st.input.items.len;
                }
            },
            ui.keymap.page_up => {
                st.follow_bottom = false;
                st.scroll = @max(0, st.scroll - @max(40, n.size.h - 3 * pad));
            },
            ui.keymap.page_down => {
                st.scroll += @max(40, n.size.h - 3 * pad);
                if (self.style(n)) |s| {
                    const lh = s.lineHeight();
                    const content_h = @as(f32, @floatFromInt(st.rows.items.len)) * lh + 2 * pad;
                    const max_scroll = @max(0, content_h - n.size.h);
                    if (st.scroll >= max_scroll) {
                        st.scroll = max_scroll;
                        st.follow_bottom = true;
                    }
                }
            },
            ui.keymap.tab => {
                st.clearSelection();
                st.follow_bottom = true;
                var comp = sh.complete(st.input.items, st.cursor, g) catch return;
                defer comp.deinit(g);
                if (comp.replacement_line) |rep| {
                    st.input.clearRetainingCapacity();
                    st.input.appendSlice(g, rep) catch return;
                    st.cursor = comp.new_cursor;
                } else if (comp.candidates.items.len > 1) {
                    var prompt_buf: [512]u8 = undefined;
                    const prompt = sh.formatPrompt(&prompt_buf);
                    var echo_buf: std.ArrayList(u8) = .empty;
                    defer echo_buf.deinit(g);
                    echo_buf.appendSlice(g, prompt) catch {};
                    echo_buf.appendSlice(g, st.input.items) catch {};
                    sh.appendLine(echo_buf.items, .prompt) catch {};

                    var cand_line: std.ArrayList(u8) = .empty;
                    defer cand_line.deinit(g);
                    for (comp.candidates.items, 0..) |cand, idx| {
                        if (idx > 0) cand_line.appendSlice(g, "  ") catch {};
                        cand_line.appendSlice(g, cand) catch {};
                    }
                    sh.appendLine(cand_line.items, .info) catch {};
                }
            },
            else => {
                if (k.char) |cp| {
                    if (cp >= 0x20 and !(cp >= 0x7f and cp <= 0x9f)) {
                        var utf8_buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cp, &utf8_buf) catch return;
                        st.insertText(utf8_buf[0..len]);
                    }
                }
            },
        }
    }
};

fn utf8At(bytes: []const u8, i: usize) usize {
    if (i >= bytes.len) return bytes.len;
    var j = i;
    while (j > 0 and bytes[j] & 0xc0 == 0x80) : (j -= 1) {}
    return j;
}

fn utf8Before(bytes: []const u8, i: usize) usize {
    var j = @min(i, bytes.len) -| 1;
    while (j > 0 and bytes[j] & 0xc0 == 0x80) : (j -= 1) {}
    return j;
}

fn utf8After(bytes: []const u8, i: usize) usize {
    if (i >= bytes.len) return bytes.len;
    var j = i + 1;
    while (j < bytes.len and bytes[j] & 0xc0 == 0x80) : (j += 1) {}
    return j;
}

fn wordBefore(bytes: []const u8, i: usize) usize {
    var j = @min(i, bytes.len);
    while (j > 0 and bytes[j - 1] == ' ') : (j -= 1) {}
    while (j > 0 and bytes[j - 1] != ' ' and bytes[j - 1] != '/') : (j -= 1) {}
    return j;
}

fn wordAfter(bytes: []const u8, i: usize) usize {
    var j = @min(i, bytes.len);
    while (j < bytes.len and bytes[j] == ' ') : (j += 1) {}
    while (j < bytes.len and bytes[j] != ' ' and bytes[j] != '/') : (j += 1) {}
    return j;
}

// --- Tests ---------------------------------------------------------------------

const testing = std.testing;

fn overflows(node: *ui.Node) bool {
    if (node.overflow.any()) return true;
    for (node.children.items) |ch| if (overflows(ch)) return true;
    return false;
}

fn findType(n: *ui.Node, comptime T: type) ?*ui.Node {
    if (n.widget.is(T)) return n;
    for (n.children.items) |ch| if (findType(ch, T)) |f| return f;
    return null;
}

fn findText(n: *ui.Node, text: []const u8) ?*ui.Node {
    if (n.widget.as(ui.Text)) |tx| if (std.mem.eql(u8, tx.text, text)) return n;
    for (n.children.items) |ch| if (findText(ch, text)) |f| return f;
    return null;
}

test "terminal view lays out cleanly at all window sizes and handles interactive typing and history" {
    const f = try font.Font.init(@embedFile("FiraSans-Regular.ttf"));
    const u = try ui.Ui.create(testing.allocator, &f);
    defer u.destroy();

    var sh = try shell_mod.Shell.initTest(testing.allocator, "/");
    defer sh.deinit();

    const term: Terminal = .{ .shell = &sh };
    for ([_][2]u32{ min_size, .{ 1280, 720 }, .{ 1920, 1036 } }) |size| {
        u.frame(size[0], size[1], 0, term);
        try testing.expect(!overflows(u.root.?));
    }
    try testing.expect(findText(u.root.?, "Terminal") != null);
    try testing.expect(u.focused != null and u.focused.?.widget.is(TerminalArea));

    const area = findType(u.root.?, TerminalArea).?;
    const st = area.state(TerminalArea.State);

    // Type `echo hello` and press Enter.
    st.insertText("echo hello\n");
    u.frame(1280, 720, 1, term);
    try testing.expectEqual(@as(u8, 0), sh.last_status);
    try testing.expectEqual(@as(usize, 2), sh.output.items.len);
    try testing.expectEqualStrings("hello", sh.output.items[1].text);

    // Press Up arrow to recall `echo hello` from history.
    u.keyEvent(ui.keymap.up, true);
    try testing.expectEqualStrings("echo hello", st.input.items);

    // Press Ctrl+L to clear scrollback.
    u.keyEvent(ui.keymap.left_ctrl, true);
    u.keyEvent(key_l, true);
    u.keyEvent(ui.keymap.left_ctrl, false);
    try testing.expectEqual(@as(usize, 0), sh.output.items.len);
}

test {
    _ = shell_mod;
    _ = shell_mod.commands;
}
