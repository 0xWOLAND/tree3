const std = @import("std");
const Tree = @import("tree.zig").Tree;
const Node = @import("tree.zig").Node;

pub const ValueView = union(enum) {
    Nat: usize,
    List: []u32,
    String: []u8,
    Pair: struct { a: u32, b: u32 },
    Leaf,
    Stem: u32,
    Fork: struct { a: u32, b: u32 },
};

fn kind(t: *Tree, x: u32) Node.Kind {
    return t.nodes.items[x].kind;
}

fn left_child(t: *Tree, x: u32) u32 {
    return t.nodes.items[x].lhs.?;
}

fn right_child(t: *Tree, x: u32) u32 {
    return t.nodes.items[x].rhs.?;
}

fn asNat(t: *Tree, x: u32) ?usize {
    var cur = x;
    var bonus: usize = 0;
    while (kind(t, cur) == .Stem) {
        bonus += 1;
        cur = right_child(t, cur);
    }

    var n: usize = 0;
    var bit: usize = 0;

    while (true) {
        switch (kind(t, cur)) {
            .Leaf => return n + bonus,
            .Fork => {
                const bit_node = left_child(t, cur);
                const bit_val: usize = switch (kind(t, bit_node)) {
                    .Leaf => 0,
                    .Stem => blk: {
                        if (kind(t, right_child(t, bit_node)) != .Leaf) return null;
                        break :blk 1;
                    },
                    .Fork => return null,
                };
                if (bit >= @bitSizeOf(usize)) return null;
                const shift: std.math.Log2Int(usize) = @intCast(bit);
                n |= bit_val << shift;
                bit += 1;
                cur = right_child(t, cur);
            },
            .Stem => return null,
        }
    }
}

fn asList(
    t: *Tree,
    x: u32,
    a: std.mem.Allocator,
) ?[]u32 {
    var elems: std.ArrayList(u32) = .empty;
    var cur = x;

    while (true) {
        switch (kind(t, cur)) {
            .Leaf => {
                const owned = elems.toOwnedSlice(a) catch {
                    elems.deinit(a);
                    return null;
                };
                return owned;
            },
            .Fork => {
                elems.append(a, left_child(t, cur)) catch {
                    elems.deinit(a);
                    return null;
                };
                cur = right_child(t, cur);
            },
            .Stem => {
                elems.deinit(a);
                return null;
            },
        }
    }
}

fn asString(
    t: *Tree,
    x: u32,
    a: std.mem.Allocator,
) ?[]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    var cur = x;

    while (true) {
        switch (kind(t, cur)) {
            .Leaf => {
                const owned = bytes.toOwnedSlice(a) catch {
                    bytes.deinit(a);
                    return null;
                };
                return owned;
            },
            .Fork => {
                const nNat = asNat(t, left_child(t, cur)) orelse {
                    bytes.deinit(a);
                    return null;
                };
                if (nNat > 255) {
                    bytes.deinit(a);
                    return null;
                }
                bytes.append(a, @as(u8, @intCast(nNat))) catch {
                    bytes.deinit(a);
                    return null;
                };
                cur = right_child(t, cur);
            },
            .Stem => {
                bytes.deinit(a);
                return null;
            },
        }
    }
}

fn asPair(t: *Tree, x: u32) ?ValueView {
    if (kind(t, x) != .Fork) return null;

    return ValueView{
        .Pair = .{
            .a = left_child(t, x),
            .b = right_child(t, x),
        },
    };
}

fn _decode(t: *Tree, x: u32) ValueView {
    switch (kind(t, x)) {
        .Leaf => return ValueView.Leaf,
        .Stem => return ValueView{ .Stem = right_child(t, x) },
        .Fork => return ValueView{
            .Fork = .{
                .a = left_child(t, x),
                .b = right_child(t, x),
            },
        },
    }
}

pub fn decode(
    t: *Tree,
    x: u32,
    a: std.mem.Allocator,
) !ValueView {
    if (asNat(t, x)) |n| {
        return ValueView{ .Nat = n };
    }

    if (asList(t, x, a)) |xs| {
        if (asString(t, x, a)) |str| {
            return ValueView{ .String = str };
        }
        return ValueView{ .List = xs };
    }

    if (asPair(t, x)) |p| {
        return p;
    }

    return _decode(t, x);
}
