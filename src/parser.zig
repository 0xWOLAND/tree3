const std = @import("std");
const Tok = @import("lexer.zig").Token;
const TK = @import("lexer.zig").TokenType;

const AllocError = std.mem.Allocator.Error;

pub const AST = union(enum) {
    Import: struct { path: []const u8, module: []const u8 },
    Def: struct { name: []const u8, args: [][]const u8, body: *AST },
    Lambda: struct { params: [][]const u8, body: *AST },
    App: struct { func: *AST, args: []AST },
    Var: []const u8,
    Int: []const u8,
    Str: []const u8,
    List: []AST,
    TLeaf,
    TStem: *AST,
    TFork: struct { left: *AST, right: *AST },
};

pub const Parser = struct {
    a: std.mem.Allocator,
    t: []const Tok,
    i: usize = 0,
    p: usize = 0,
    b: usize = 0,

    pub fn init(a: std.mem.Allocator, t: []const Tok) Parser {
        return .{ .a = a, .t = t };
    }
    fn peek(self: *Parser) ?Tok {
        return if (self.i < self.t.len) self.t[self.i] else null;
    }
    fn next(self: *Parser) ?Tok {
        const x = self.peek() orelse return null;
        self.i += 1;
        switch (x.kind) {
            .LParen => self.p += 1,
            .RParen => self.p -= 1,
            .LBracket => self.b += 1,
            .RBracket => self.b -= 1,
            else => {},
        }
        return x;
    }
    fn exp(self: *Parser, k: TK) Tok {
        const x = self.next() orelse @panic("eof");
        if (x.kind != k) @panic("expected");
        return x;
    }
    fn box(self: *Parser, n: AST) AllocError!*AST {
        const p = try self.a.create(AST);
        p.* = n;
        return p;
    }
    fn topNL(self: *Parser) bool {
        const x = self.peek() orelse return false;
        return x.kind == .Newline and self.p == 0 and self.b == 0;
    }
    fn skipNL(self: *Parser) void {
        while (self.topNL()) _ = self.next();
    }

    pub fn parse(self: *Parser) AllocError![]AST {
        var out = std.ArrayListUnmanaged(AST){};
        self.skipNL();
        while (self.peek()) |t| if (t.kind == .Import) try out.append(self.a, try self.parseImport()) else break;
        self.skipNL();
        while (self.peek()) |t| {
            if (t.kind == .Newline) {
                _ = self.next();
                continue;
            }
            try out.append(self.a, try self.expr());
            self.skipNL();
        }
        return try out.toOwnedSlice(self.a);
    }

    fn parseImport(self: *Parser) AllocError!AST {
        const t = self.exp(.Import);
        return .{ .Import = .{ .path = t.value, .module = t.value } };
    }

    fn expr(self: *Parser) AllocError!AST {
        if (self._isDef()) return self.def();
        if (self._lamStart()) return self.lambda();
        if (self._isList()) return self.list();
        if (self._isTree()) return self.tree();
        return self.app();
    }

    fn _isDef(self: *Parser) bool {
        const first = self.peek() orelse return false;
        if (first.kind != .Identifier) return false;

        var j = self.i + 1;
        while (j < self.t.len) : (j += 1) {
            switch (self.t[j].kind) {
                .Identifier => continue,
                .Assign => return true,
                .Newline => return false,
                else => return false,
            }
        }
        return false;
    }
    fn def(self: *Parser) AllocError!AST {
        const n = self.exp(.Identifier);
        var args = std.ArrayListUnmanaged([]const u8){};
        while (self.peek()) |t| if (t.kind == .Identifier) {
            _ = self.next();
            try args.append(self.a, t.value);
        } else break;
        _ = self.exp(.Assign);
        const body = try self.expr();
        return .{ .Def = .{ .name = n.value, .args = try args.toOwnedSlice(self.a), .body = try self.box(body) } };
    }

    fn _lamStart(self: *Parser) bool {
        if (self.peek() == null) return false;
        var j = self.i;
        var ok = false;
        while (j < self.t.len and self.t[j].kind == .Identifier) : (j += 1) ok = true;
        return ok and j < self.t.len and self.t[j].kind == .Colon;
    }
    fn lambda(self: *Parser) AllocError!AST {
        var ps = std.ArrayListUnmanaged([]const u8){};
        while (self.peek()) |t| if (t.kind == .Identifier) {
            _ = self.next();
            try ps.append(self.a, t.value);
        } else break;
        _ = self.exp(.Colon);
        const body = try self.expr();
        var acc = body;
        const xs = try ps.toOwnedSlice(self.a);
        var i = xs.len;
        while (i > 0) : (i -= 1)
            acc = .{ .Lambda = .{ .params = xs[i - 1 .. i], .body = try self.box(acc) } };
        return acc;
    }

    fn app(self: *Parser) AllocError!AST {
        const f = try self.atom();
        var args = std.ArrayListUnmanaged(AST){};
        while (self.peek()) |t| if (_atomStart(t)) try args.append(self.a, try self.atom()) else break;
        if (args.items.len == 0) return f;
        return .{ .App = .{ .func = try self.box(f), .args = try args.toOwnedSlice(self.a) } };
    }

    fn _atomStart(t: Tok) bool {
        return switch (t.kind) {
            .Identifier, .StringLiteral, .Integer, .LParen, .KeywordT, .LBracket => true,
            else => false,
        };
    }

    fn atom(self: *Parser) AllocError!AST {
        const t = self.peek() orelse @panic("eof-atom");
        return switch (t.kind) {
            .Identifier => self.identifier(),
            .StringLiteral => blk: {
                _ = self.next();
                break :blk .{ .Str = t.value };
            },
            .Integer => blk: {
                _ = self.next();
                break :blk .{ .Int = t.value };
            },
            .LParen => self.grouped(),
            .KeywordT => blk: {
                _ = self.next();
                break :blk .TLeaf;
            },
            .LBracket => self.list(),
            else => @panic("bad atom"),
        };
    }

    fn identifier(self: *Parser) AllocError!AST {
        const t = self.exp(.Identifier);
        return .{ .Var = t.value };
    }

    fn grouped(self: *Parser) AllocError!AST {
        _ = self.exp(.LParen);
        const e = try self.expr();
        _ = self.exp(.RParen);
        return e;
    }

    fn _isList(self: *Parser) bool {
        return self.peek() != null and self.peek().?.kind == .LBracket;
    }
    fn list(self: *Parser) AllocError!AST {
        _ = self.exp(.LBracket);
        var xs = std.ArrayListUnmanaged(AST){};
        while (self.peek()) |t| {
            if (t.kind == .RBracket) break;
            try xs.append(self.a, try self.expr());
        }
        _ = self.exp(.RBracket);
        return .{ .List = try xs.toOwnedSlice(self.a) };
    }

    fn _isTree(self: *Parser) bool {
        return self.peek() != null and self.peek().?.kind == .KeywordT;
    }
    fn tree(self: *Parser) AllocError!AST {
        var a = try self.treeAtom();
        while (self._isTree() or self._pStart()) {
            const b = try self.treeAtom();
            a = try self.combine(a, b);
        }
        return a;
    }
    fn treeAtom(self: *Parser) AllocError!AST {
        if (self.peek().?.kind == .KeywordT) {
            _ = self.next();
            return .TLeaf;
        }
        _ = self.exp(.LParen);
        const x = try self.tree();
        _ = self.exp(.RParen);
        return x;
    }
    fn _pStart(self: *Parser) bool {
        return self.peek() != null and self.peek().?.kind == .LParen;
    }
    fn combine(self: *Parser, a: AST, b: AST) AllocError!AST {
        return switch (a) {
            .TLeaf => .{ .TStem = try self.box(b) },
            .TStem => .{ .TFork = .{ .left = a.TStem, .right = try self.box(b) } },
            .TFork => .{ .TFork = .{ .left = try self.box(a), .right = try self.box(b) } },
            else => @panic("bad tree"),
        };
    }
};
