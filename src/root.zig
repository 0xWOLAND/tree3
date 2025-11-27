const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const parser = @import("parser.zig");
const Parser = parser.Parser;
const Eval = @import("eval.zig");
const Env = Eval.Env;
const evalProgram = Eval.evalProgram;
const EvalError = Eval.EvalError;
const Tree = @import("tree.zig").Tree;

fn run(alloc: std.mem.Allocator, src: []const u8) !struct { tree: Tree, env: Env } {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var lex = Lexer.init(src);
    const toks = try lex.lexAll(a);
    var prs = Parser.init(a, toks);
    const asts = try prs.parse();

    var tree = try Tree.init(alloc);
    errdefer tree.deinit();

    var env = Env.init(alloc);
    errdefer env.deinit();

    _ = try evalProgram(&tree, &env, asts);
    return .{ .tree = tree, .env = env };
}

test "basic program" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const src =
        \\x = 10
        \\y = x
        \\lst = [1 2 3]
        \\t t
    ;

    var ctx = try run(alloc, src);
    defer ctx.tree.deinit();
    defer ctx.env.deinit();

    const id_x = ctx.env.get("x").?;
    const id_y = ctx.env.get("y").?;
    const id_list = ctx.env.get("lst").?;
    const id_apply = ctx.env.get("!result") orelse unreachable;

    try std.testing.expectEqual(id_x, id_y);
    const lst_node = ctx.tree.get(id_list);
    try std.testing.expect(lst_node.kind != .Leaf);

    const applied = id_apply;
    const ap_node = ctx.tree.get(applied);

    try std.testing.expect(ap_node.kind == .Stem);
    const rhs = ap_node.rhs.?;
    const rhs_node = ctx.tree.get(rhs);
    try std.testing.expect(rhs_node.kind == .Leaf);
}

test "defs are immutable" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const src =
        \\x = 1
        \\x = 2
    ;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    var lex = Lexer.init(src);
    const toks = try lex.lexAll(arena.allocator());
    var prs = Parser.init(arena.allocator(), toks);
    const asts = try prs.parse();

    var tree = try Tree.init(alloc);
    defer tree.deinit();
    var env = Env.init(alloc);
    defer env.deinit();

    try std.testing.expectError(EvalError.RebindImmutable, evalProgram(&tree, &env, asts));
}
