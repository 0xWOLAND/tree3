const std = @import("std");
const parser = @import("parser.zig");
const Tree = @import("tree.zig").Tree;
const Node = @import("tree.zig").Node;
const Id = @import("tree.zig").Id;

const AST = parser.AST;

const AllocError = std.mem.Allocator.Error;
pub const EvalError = AllocError || error{
    UnknownVariable,
    LambdaNotSupported,
    ImportNotSupported,
    Overflow,
    InvalidCharacter,
    NoSpaceLeft,
    MissingResult,
    RebindImmutable,
};

pub const Env = std.StringHashMap(Id);

fn setResult(env: *Env, v: Id) EvalError!void {
    try env.put("!result", v);
}

fn encodeNumber(t: *Tree, s: []const u8) EvalError!Id {
    var n = try std.fmt.parseInt(u64, s, 10);
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

fn encodeString(t: *Tree, s: []const u8) EvalError!Id {
    var lst: Id = try t.insert(Node.leaf());
    var i: usize = s.len;

    while (i > 0) : (i -= 1) {
        var buf: [32]u8 = undefined;
        const c = s[i - 1];
        const num = try std.fmt.bufPrint(&buf, "{d}", .{c});
        const enc = try encodeNumber(t, num);

        lst = try t.insert(Node.fork(enc, lst));
    }
    return lst;
}

fn encodeList(t: *Tree, env: *Env, xs: []AST) EvalError!Id {
    var lst: ?Id = try t.insert(Node.leaf());
    var i = xs.len;
    while (i > 0) : (i -= 1) {
        const v = try eval(t, env, &xs[i - 1]);
        lst = try t.insert(Node.fork(v, lst.?));
    }
    return lst.?;
}

pub fn eval(t: *Tree, env: *Env, ast: *const AST) EvalError!Id {
    return switch (ast.*) {
        .TLeaf => try t.insert(Node.leaf()),

        .TStem => |x| try t.insert(Node.stem(try eval(t, env, x))),

        .TFork => |f| blk: {
            const l = try eval(t, env, f.left);
            const r = try eval(t, env, f.right);
            break :blk try t.insert(Node.fork(l, r));
        },

        .Int => |s| try encodeNumber(t, s),
        .Str => |s| try encodeString(t, s),
        .List => |xs| try encodeList(t, env, xs),

        .Var => |name| env.get(name) orelse error.UnknownVariable,

        .App => |f| blk: {
            var acc = try eval(t, env, f.func);
            for (f.args) |arg|
                acc = try t.apply(acc, try eval(t, env, &arg));
            break :blk acc;
        },

        .Lambda => |_| error.LambdaNotSupported, // TODO: Implement lambdas

        .Def => |d| blk: {
            const body = try eval(t, env, d.body);
            if (env.get(d.name)) |existing| {
                if (existing != body) return error.RebindImmutable;
                break :blk existing;
            }
            try env.put(d.name, body);
            break :blk body;
        },

        .Import => |_| error.ImportNotSupported,
    };
}

pub fn evalSingle(t: *Tree, env: *Env, ast: *const AST) EvalError!Id {
    const res = try eval(t, env, ast);
    try setResult(env, res);
    return res;
}

pub fn evalProgram(t: *Tree, env: *Env, asts: []const AST) EvalError!Id {
    for (asts) |*ast|
        _ = try evalSingle(t, env, ast);
    return env.get("!result") orelse error.MissingResult;
}
