const std = @import("std");

pub const Id = u32;

pub const Node = struct {
    pub const Kind = enum { Leaf, Stem, Fork };

    kind: Kind,
    lhs: ?Id,
    rhs: ?Id,

    pub fn leaf() Node {
        return .{ .kind = .Leaf, .lhs = null, .rhs = null };
    }
    pub fn stem(a: Id) Node {
        return .{ .kind = .Stem, .lhs = null, .rhs = a };
    }
    pub fn fork(a: Id, b: Id) Node {
        return .{ .kind = .Fork, .lhs = a, .rhs = b };
    }
};

pub const Trees = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    arena_alloc: std.mem.Allocator,

    nodes: std.ArrayListUnmanaged(Node),
    table: std.AutoHashMap(Node, Id),

    pub fn init(parent: std.mem.Allocator) !Trees {
        var arena = std.heap.ArenaAllocator.init(parent);
        const aalloc = arena.allocator();

        return .{
            .arena = arena,
            .allocator = parent,
            .arena_alloc = aalloc,
            .nodes = .{},
            .table = std.AutoHashMap(Node, Id).init(parent),
        };
    }

    pub fn deinit(self: *Trees) void {
        self.nodes.deinit(self.allocator);
        self.table.deinit();
        self.arena.deinit();
    }

    pub fn insert(self: *Trees, n: Node) !Id {
        if (self.table.get(n)) |existing| return existing;

        const id: Id = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, n);
        try self.table.put(n, id);
        return id;
    }

    pub inline fn get(self: *Trees, id: Id) Node {
        return self.nodes.items[id];
    }

    pub fn apply(self: *Trees, a0: Id, b0: Id) !Id {
        var a = a0;
        var b = b0;

        while (true) {
            const an = self.get(a);

            switch (an.kind) {
                .Leaf => return try self.insert(Node.stem(b)),

                .Stem => return try self.insert(Node.fork(an.rhs.?, b)),

                .Fork => {
                    const left = self.get(an.lhs.?);

                    switch (left.kind) {
                        .Leaf => return an.rhs.?,

                        .Stem => {
                            a = left.rhs.?;
                            continue;
                        },

                        .Fork => {
                            const bnode = self.get(b);
                            switch (bnode.kind) {
                                .Leaf => return left.lhs.?,

                                .Stem => {
                                    a = left.rhs.?;
                                    b = bnode.rhs.?;
                                    continue;
                                },

                                .Fork => {
                                    a = an.rhs.?;
                                    b = bnode.lhs.?;
                                },
                            }
                        },
                    }
                },
            }
        }
    }
};
