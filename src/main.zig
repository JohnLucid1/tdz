const std = @import("std");
const debug_print = std.debug.print;

const skip_fs_ext = &[_][]const u8{ ".exe", ".json", ".dll", ".pbd", ".sample", ".obj" };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const res = gpa.deinit();
        if (res == .leak) {
            @panic("MEMORY LEAKED");
        }
    }
    const stdout = std.io.getStdOut();
    defer stdout.close();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len <= 1) {
        try stdout.writer().print("ERROR: not enough arguments\nExample usage:\ntd <./> || td <filename.ext>\n", .{});
        std.process.exit(1);
    }

    const path = args[1];
    var todos = std.ArrayList(Todo).init(allocator);
    defer {
        for (todos.items) |todo| {
            allocator.free(todo.content);
            allocator.free(todo.filepath);
        }
        todos.deinit();
    }

    if (isFile(path)) {
        try find_todos(allocator, &todos, path);
    } else if (isDirectory(path)) {
        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            const full_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ path, entry.path });
            const ext = std.fs.path.extension(full_path);
            if (entry.path[0] == '.') {
                continue;
            }
            for (skip_fs_ext) |e| {
                if (std.mem.eql(u8, e, ext)) {
                    continue;
                }
            }

            defer allocator.free(full_path);
            if (isFile(full_path)) {
                try find_todos(allocator, &todos, full_path);
            }
        }
    } else {
        try stdout.writer().print("ERROR: Target not found.\nExample usage:\ntd <./> || td <filename.ext>\n", .{});
        std.process.exit(1);
    }

    const slice = try todos.toOwnedSlice();
    std.mem.sort(Todo, slice, {}, cmpByData);
    for (slice) |item| {
        try stdout.writer().print("{}:{}:{s}:{s}\n", .{ item.line, item.column, item.filepath, item.content });
    }
}

fn find_todos(allocator: std.mem.Allocator, todo_list: *std.ArrayList(Todo), path: []const u8) !void {
    var file = std.fs.cwd().openFile(path, .{}) catch |err| {
        debug_print("ERROR: {s} on {s}\n", .{ @errorName(err), path });
        return err;
    };
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var line_count: usize = 1;
    while (try in_stream.readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(usize))) |line| {
        defer allocator.free(line);
        const index = std.mem.indexOf(u8, line, "TODO");
        if (index) |column| {
            const priority = get_priority(line, column);
            const trimmed = std.mem.trimLeft(u8, line, " ");
            const content = try allocator.dupe(u8, trimmed);
            const my_path = try allocator.dupe(u8, path);

            const t = Todo{
                .priority = priority,
                .filepath = my_path,
                .content = content,
                .line = line_count,
                .column = column + 4,
            };
            try todo_list.append(t);
        }

        line_count += 1;
    }
}

fn get_priority(str: []const u8, idx: usize) usize {
    var priority: usize = 1;
    var i = idx;

    while (str.len > i + 1 + 4 and str[i + 1 + 3] == 'O') {
        priority += 1;
        i += 1;
    }
    return priority;
}

fn cmpByData(_: void, a: Todo, b: Todo) bool {
    return a.priority > b.priority;
}

pub fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

const Todo = struct {
    const Self = @This();
    priority: usize,
    filepath: []const u8,
    content: []const u8,
    line: usize,
    column: usize,
};

pub fn isFile(path: []const u8) bool {
    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    defer file.close();
    return true;
}

pub fn isDirectory(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch |err| {
        std.log.err("{s} ON {s}\n", .{ @errorName(err), path });
        return false;
    };
    defer dir.close();
    return true;
}
