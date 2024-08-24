const std = @import("std");
const c = std.c;
const io = std.io;
const stdin = io.getStdIn().reader();
const stdout = io.getStdOut().writer();
const mem = std.mem;
const fs = std.fs;
const process = std.process;
const ArrayList = std.ArrayList;
const debugPrint = std.debug.print;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var E: EditorConfig = undefined;

const EditorError = error{
    Err_tcgetattr,
    Err_tcsetattr,
    Err_read,
    Err_open,
};

const Erow: type = struct { // Editor Row
    size: u16,
    chars: []u8,
};

const EditorConfig: type = struct {
    cx: u32,
    cy: u32,
    screenrows: u16,
    screencols: u16,
    numrows: u16,
    row: ArrayList(Erow),
    orig_termios: c.termios,
};

fn disableRawMode() !void {
    if (c.tcsetattr(c.STDIN_FILENO, c.TCSA.FLUSH, &E.orig_termios) == -1)
        return EditorError.Err_tcsetattr;
}

fn enableRawMode() !void {
    const VMIN: u8 = 6;
    const VTIME: u8 = 5;
    if (c.tcgetattr(c.STDIN_FILENO, &E.orig_termios) == -1)
        return EditorError.Err_tcgetattr;
    var raw = E.orig_termios;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.oflag.OPOST = false;
    // raw.cflag.CSIZE = os.linux.CSIZE.CS8;
    raw.cc[VMIN] = 0;
    raw.cc[VTIME] = 1;
    if (c.tcsetattr(c.STDIN_FILENO, c.TCSA.FLUSH, &raw) == -1)
        return EditorError.Err_tcsetattr;
}

fn getWindowSize(rows: *u16, cols: *u16) i8 {
    var ws: c.winsize = undefined;
    if (c.ioctl(c.STDOUT_FILENO, c.T.IOCGWINSZ, &ws) == -1 or ws.ws_col == 0) {
        return -1;
    }
    cols.* = ws.ws_col;
    rows.* = ws.ws_row;
    return 0;
}

fn editorProcessCommand() i8 {
    while (true) {
        const ch: u8 = stdin.readByte() catch '\x00';
        switch (ch) {
            '\x0d' => break,
            'q' => return -1,
            else => continue,
        }
    }
    return 0;
}

fn editorProcessKeypress() !i8 {
    const ch: u8 = stdin.readByte() catch '\x00';
    switch (ch) {
        ':' => return editorProcessCommand(),
        'h', 'j', 'k', 'l' => editorMoveCursor(ch),
        else => {},
    }

    return 0;
}

fn editorRefreshScreen() !void {
    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();
    try buf.appendSlice("\x1b[?25l"); // hide cursor
    try buf.appendSlice("\x1b[H"); // move cursor to top left

    try editorDrawRows(&buf);

    try buf.writer().print("\x1b[{d};{d}H", .{ E.cy + 1, E.cx + 1 }); // move corsor

    try buf.appendSlice("\x1b[?25h"); // show cursor

    try stdout.print("{s}", .{buf.items});
}

fn editorMoveCursor(key: u8) void {
    switch (key) {
        'h' => if (E.cx != 0) {
            E.cx -= 1;
        },
        'j' => if (E.cy != E.screenrows - 1) {
            E.cy += 1;
        },
        'k' => if (E.cy != 0) {
            E.cy -= 1;
        },
        'l' => if (E.cx != E.screencols - 1) {
            E.cx += 1;
        },
        else => {},
    }
}

fn editorDrawRows(buf: *ArrayList(u8)) !void {
    for (0..E.screenrows) |i| {
        if (i < E.numrows) {
            var len = E.row.size;
            if (len > E.screencols)
                len = E.screencols;
            try buf.appendSlice(E.row.chars[0..len]);
        } else {
            try buf.append('~');
        }

        try buf.appendSlice("\x1b[K"); // clear screen
        if (i < E.screenrows - 1)
            try buf.appendSlice("\n\r");
    }
}

fn editorOpen(filename: []u8) !void {
    const file = try fs.cwd().openFile(filename, .{});
    var buf: [0x1000]u8 = undefined;
    const line = try file.reader().readUntilDelimiterOrEof(&buf, '\n');
    if (line == null)
        return EditorError.Err_open;

    editorAppendRow(line, line.?.len);
}

fn initEditor() i8 {
    E.cx = 0;
    E.cy = 0;
    E.numrows = 0;
    return getWindowSize(&E.screenrows, &E.screencols);
}

fn editorAppendRow(s: []u8, len: usize) void {
    E.row.size = len;
    E.row.chars = try allocator.alloc(u8, len);
    @memcpy(E.row.chars, s);
    E.numrows = 1;
}

pub fn main() !void {
    const args = try process.argsAlloc(std.heap.page_allocator);
    defer process.argsFree(std.heap.page_allocator, args);
    if (args.len < 2)
        return;

    try enableRawMode();
    if (initEditor() == -1) {
        try disableRawMode();
        return;
    }

    const filename: []u8 = args[1];
    try editorOpen(filename);
    defer allocator.free(E.row.chars);

    while (true) {
        try editorRefreshScreen();
        if (try editorProcessKeypress() == -1)
            break;
    }

    try disableRawMode();
    try editorRefreshScreen();
    try stdout.print("Bye;D\n", .{});
}

// INV
// INV is Not Vim
