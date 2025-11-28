const std = @import("std");

pub const Expr = union(enum) {
    List: []Expr,
    Symbol: []const u8,
    Int: i64,
    Str: []const u8,
};

pub const Reader = struct {
    input: []const u8,
    i: usize = 0,
    a: std.mem.Allocator,

    const ReadError = error{ EndOfInput, UnterminatedString } || std.mem.Allocator.Error || std.fmt.ParseIntError;

    pub fn init(a: std.mem.Allocator, input: []const u8) Reader {
        return .{ .input = input, .a = a };
    }

    fn peek(self: *Reader) ?u8 {
        return if (self.i < self.input.len) self.input[self.i] else null;
    }

    fn next(self: *Reader) u8 {
        const c = self.input[self.i];
        self.i += 1;
        return c;
    }

    fn skipWS(self: *Reader) void {
        while (self.peek()) |c| {
            switch (c) {
                ' ', '\t', '\n', '\r' => _ = self.next(),

                // Handle comments starting with ;
                ';' => {
                    _ = self.next();
                    while (self.peek()) |d| : (_ = self.next()) {
                        if (d == '\n') break;
                    }
                },

                else => break,
            }
        }
    }

    fn readString(self: *Reader) ReadError!Expr {
        _ = self.next(); // consume "
        const start = self.i;
        while (self.peek()) |c| {
            if (c == '"') break;
            self.i += 1;
        }
        if (self.peek() == null) return error.UnterminatedString;
        const out = self.input[start..self.i];
        _ = self.next(); // closing "
        return .{ .Str = out };
    }

    fn readAtom(self: *Reader) ReadError!Expr {
        const start = self.i;
        while (self.peek()) |c| switch (c) {
            ' ', '\t', '\n', '\r', '(', ')', '"' => break,
            else => self.i += 1,
        };
        const slice = self.input[start..self.i];

        if (std.ascii.isDigit(slice[0])) {
            return .{ .Int = try std.fmt.parseInt(i64, slice, 10) };
        }
        return .{ .Symbol = slice };
    }

    fn readList(self: *Reader) ReadError!Expr {
        _ = self.next(); // '('
        var items: std.ArrayListUnmanaged(Expr) = .{};
        self.skipWS();
        while (self.peek()) |c| {
            if (c == ')') break;
            try items.append(self.a, try self.readExpr());
            self.skipWS();
        }
        if (self.peek() == null) return error.UnterminatedString;
        _ = self.next(); // ')'
        return .{ .List = try items.toOwnedSlice(self.a) };
    }

    pub fn readExpr(self: *Reader) ReadError!Expr {
        self.skipWS();
        return switch (self.peek() orelse return error.EndOfInput) {
            '(' => self.readList(),
            '"' => self.readString(),
            else => self.readAtom(),
        };
    }

    pub fn readProgram(self: *Reader) ReadError![]Expr {
        var exprs: std.ArrayListUnmanaged(Expr) = .{};
        errdefer exprs.deinit(self.a);

        while (true) {
            const e = self.readExpr() catch |err| switch (err) {
                error.EndOfInput => break,
                else => return err,
            };
            try exprs.append(self.a, e);
        }

        return try exprs.toOwnedSlice(self.a);
    }
};
