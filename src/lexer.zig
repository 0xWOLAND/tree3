const std = @import("std");

pub const TokenType = enum {
    Identifier,
    Namespace,
    KeywordT,
    Integer,
    StringLiteral,
    Import,
    Dot,
    Assign,
    Colon,
    LParen,
    RParen,
    LBracket,
    RBracket,
    Newline,
};

pub const Token = struct { kind: TokenType, value: []const u8 = "" };

pub const Lexer = struct {
    input: []const u8,
    i: usize = 0,

    pub fn init(input: []const u8) Lexer {
        return .{ .input = input };
    }

    fn peek(self: *Lexer) ?u8 {
        return if (self.i < self.input.len) self.input[self.i] else null;
    }

    fn next(self: *Lexer) ?u8 {
        const c = self.peek() orelse return null;
        self.i += 1;
        return c;
    }

    fn skipSpace(self: *Lexer) void {
        while (self.peek()) |c| switch (c) {
            ' ', '\t' => self.i += 1,
            // -- comment
            '-' => if (self.i + 1 < self.input.len and self.input[self.i + 1] == '-') {
                while (self.next()) |d| if (d == '\n') break;
            } else break,
            // |- ... -| block comment
            '|' => if (self.i + 1 < self.input.len and self.input[self.i + 1] == '-') {
                self.i += 2;
                while (self.peek()) |d| {
                    if (d == '-' and self.i + 1 < self.input.len and self.input[self.i + 1] == '|') {
                        self.i += 2;
                        break;
                    }
                    self.i += 1;
                }
            } else break,
            else => break,
        };
    }

    fn eatWhile(self: *Lexer, comptime pred: fn (u8) bool) []const u8 {
        const start = self.i;
        while (self.peek()) |c| {
            if (!pred(c)) break;
            self.i += 1;
        }
        return self.input[start..self.i];
    }

    fn isIdentTail(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or switch (c) {
            '_', '-', '?', '$', '#', '@', '%' => true,
            else => false,
        };
    }

    fn readIdentifier(self: *Lexer) Token {
        const start = self.i;
        _ = self.next();
        _ = self.eatWhile(isIdentTail);
        const name = self.input[start..self.i];

        if (std.mem.eql(u8, name, "t"))
            return .{ .kind = .KeywordT };
        if (std.mem.eql(u8, name, "!result"))
            @panic("!result is reserved");

        return .{ .kind = .Identifier, .value = name };
    }

    fn readNamespace(self: *Lexer) Token {
        if (std.mem.startsWith(u8, self.input[self.i..], "!Local")) {
            self.i += 6;
            return .{ .kind = .Namespace, .value = "!Local" };
        }
        const start = self.i;
        _ = self.next(); // uppercase start
        _ = self.eatWhile(std.ascii.isAlphanumeric);
        return .{ .kind = .Namespace, .value = self.input[start..self.i] };
    }

    fn readNumber(self: *Lexer) Token {
        return .{ .kind = .Integer, .value = self.eatWhile(std.ascii.isDigit) };
    }

    fn readString(self: *Lexer) Token {
        if (self.next() != '"') @panic("expected quote");
        const start = self.i;

        while (self.peek()) |c| {
            if (c == '\\') {
                self.i += 2;
                continue;
            }
            if (c == '"') break;
            self.i += 1;
        }
        const out = self.input[start..self.i];
        _ = self.next(); // closing "
        return .{ .kind = .StringLiteral, .value = out };
    }

    fn readImport(self: *Lexer) Token {
        self.i += "!import".len;
        self.skipSpace();
        const path = self.readString();
        self.skipSpace();
        _ = self.readNamespace();
        return .{ .kind = .Import, .value = path.value };
    }

    pub fn nextToken(self: *Lexer) ?Token {
        self.skipSpace();
        const c = self.peek() orelse return null;

        return switch (c) {
            '\n' => blk: {
                _ = self.next();
                break :blk .{ .kind = .Newline };
            },

            '=' => blk: {
                _ = self.next();
                break :blk .{ .kind = .Assign };
            },
            ':' => blk: {
                _ = self.next();
                break :blk .{ .kind = .Colon };
            },
            '.' => blk: {
                _ = self.next();
                break :blk .{ .kind = .Dot };
            },
            '(' => blk: {
                _ = self.next();
                break :blk .{ .kind = .LParen };
            },
            ')' => blk: {
                _ = self.next();
                break :blk .{ .kind = .RParen };
            },
            '[' => blk: {
                _ = self.next();
                break :blk .{ .kind = .LBracket };
            },
            ']' => blk: {
                _ = self.next();
                break :blk .{ .kind = .RBracket };
            },

            '!' => blk: {
                if (std.mem.startsWith(u8, self.input[self.i..], "!import"))
                    break :blk self.readImport();
                break :blk self.readNamespace();
            },

            '"' => self.readString(),
            '0'...'9' => self.readNumber(),
            'A'...'Z' => self.readNamespace(),
            'a'...'z', '_' => self.readIdentifier(),

            else => @panic("invalid character"),
        };
    }

    pub fn lexAll(self: *Lexer, alloc: std.mem.Allocator) ![]Token {
        var list = std.ArrayListUnmanaged(Token){};
        while (self.nextToken()) |tok|
            try list.append(alloc, tok);
        return try list.toOwnedSlice(alloc);
    }
};
