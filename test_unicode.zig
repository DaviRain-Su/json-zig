const std = @import("std");
const testing = std.testing;
const json_zig = @import("src/root.zig");

test "Unicode parsing (direct UTF-8)" {
    const input = "{\"message\": \"你好，世界\"}";
    var val = try json_zig.parse(testing.allocator, input);
    defer val.deinit(testing.allocator);

    try testing.expect(val == .Object);
    const msg = val.Object.get("message").?.String;
    try testing.expectEqualStrings("你好，世界", msg);
}

test "Unicode stringify (direct UTF-8)" {
    const allocator = testing.allocator;
    var obj = std.StringArrayHashMap(json_zig.JsonValue).init(allocator);
    try obj.put("msg", json_zig.JsonValue{ .String = "测试" });

    var root = json_zig.JsonValue{ .Object = obj };
    defer root.deinit(allocator);

    var list = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer list.deinit(allocator);

    try json_zig.stringify(root, list.writer(allocator));
    
    // Expect raw UTF-8 output, not escaped \uXXXX
    try testing.expectEqualStrings("{\"msg\":\"测试\"}", list.items);
}

// This test is expected to fail currently if we haven't implemented \uXXXX parsing
test "Unicode parsing (escaped uXXXX)" {
    // "Hello" in hex: \u0048\u0065\u006c\u006c\u006f
    // "你好" in hex: \u4f60\u597d
    const input = "{\"msg\": \"\\u4f60\\u597d\"}"; 
    var val = try json_zig.parse(testing.allocator, input);
    defer val.deinit(testing.allocator);

    try testing.expect(val == .Object);
    const msg = val.Object.get("msg").?.String;
    // We expect it to be decoded to "你好"
    try testing.expectEqualStrings("你好", msg);
}
