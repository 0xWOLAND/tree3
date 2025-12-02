const std = @import("std");
const Tree = @import("tree.zig").Tree;
const Node = @import("tree.zig").Node;
const Id = @import("tree.zig").Id;

const Expr = @import("reader.zig").Expr;

pub const EvalError = error{
    UnknownVariable,
    BadDefine,
    BadApplication,
    RebindImmutable,
    MissingResult,
    EmptyList,
} || std.mem.Allocator.Error;

pub const Env = std.StringHashMap(Id);

fn encodeNumber(t: *Tree, n0: u64) !Id {
    var n = n0;
    if (n == 0) return try t.insert(Node.leaf());

    var cur: ?Id = try t.insert(Node.leaf());
    while (n > 0) : (n >>= 1) {
        const bit = if (n & 1 == 1)
            try t.insert(Node.stem(try t.insert(Node.leaf())))
        else
            try t.insert(Node.leaf());
        cur = try t.insert(Node.fork(bit, cur.?));
    }
    return cur.?;
}

fn encodeString(t: *Tree, s: []const u8) !Id {
    var lst = try t.insert(Node.leaf());
    var i = s.len;
    while (i > 0) : (i -= 1) {
        const c = s[i - 1];
        const enc = try encodeNumber(t, @as(u64, c));
        lst = try t.insert(Node.fork(enc, lst));
    }
    return lst;
}

fn encodeList(t: *Tree, env: *Env, xs: []Expr) EvalError!Id {
    var lst = try t.insert(Node.leaf());
    var i = xs.len;
    while (i > 0) : (i -= 1) {
        const v = try eval(xs[i - 1], env, t);
        lst = try t.insert(Node.fork(v, lst));
    }
    return lst;
}

pub fn eval(expr: Expr, env: *Env, t: *Tree) EvalError!Id {
    return switch (expr) {
        .Int => |v| try encodeNumber(t, @intCast(v)),
        .Str => |s| try encodeString(t, s),
        .Symbol => |name| blk: {
            if (std.mem.eql(u8, name, "t"))
                break :blk try t.insert(Node.leaf());

            break :blk env.get(name) orelse return error.UnknownVariable;
        },

        .List => |list| blk: {
            if (list.len == 0)
                break :blk error.EmptyList;

            switch (list[0]) {
                .Symbol => |sym| {
                    if (std.mem.eql(u8, sym, "define")) {
                        if (list.len != 3) break :blk error.BadDefine;
                        const name_expr = list[1];
                        if (name_expr != .Symbol) break :blk error.BadDefine;

                        const value = try eval(list[2], env, t);
                        if (env.get(name_expr.Symbol)) |_| break :blk error.RebindImmutable;
                        try env.put(name_expr.Symbol, value);
                        break :blk value;
                    }

                    if (std.mem.eql(u8, sym, "define-rec")) {
                        if (list.len != 3) break :blk error.BadDefine;
                        const name_expr = list[1];
                        if (name_expr != .Symbol) break :blk error.BadDefine;

                        const hole = try t.reserve();
                        try env.put(name_expr.Symbol, hole);

                        const value = try eval(list[2], env, t);
                        t.set(hole, t.get(value));
                        break :blk hole;
                    }

                    if (std.mem.eql(u8, sym, "pair")) {
                        if (list.len != 3) break :blk error.BadApplication;
                        const a = try eval(list[1], env, t);
                        const b = try eval(list[2], env, t);
                        break :blk try t.insert(Node.fork(a, b));
                    }

                    if (std.mem.eql(u8, sym, "first")) {
                        if (list.len != 2) break :blk error.BadApplication;
                        const p = try eval(list[1], env, t);
                        const node = t.get(p);
                        if (node.kind != .Fork) break :blk error.BadApplication;
                        break :blk node.lhs.?;
                    }

                    if (std.mem.eql(u8, sym, "second")) {
                        if (list.len != 2) break :blk error.BadApplication;
                        const p = try eval(list[1], env, t);
                        const node = t.get(p);
                        if (node.kind != .Fork) break :blk error.BadApplication;
                        break :blk node.rhs.?;
                    }

                    if (std.mem.eql(u8, sym, "list")) {
                        break :blk try encodeList(t, env, list[1..]);
                    }

                },
                else => {},
            }

            var acc = try eval(list[0], env, t);

            var i: usize = 1;
            while (i < list.len) : (i += 1)
                acc = try t.apply(acc, try eval(list[i], env, t));

            break :blk acc;
        },
    };
}

pub fn evalProgram(t: *Tree, env: *Env, exprs: []const Expr) EvalError!Id {
    var last: ?Id = null;
    for (exprs) |e| {
        last = try eval(e, env, t);
    }
    if (last) |v| {
        try env.put("!result", v);
        return v;
    }
    return error.MissingResult;
}
