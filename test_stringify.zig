const std = @import("std");
const testing = std.testing;
const JsonValue = @import("src/root.zig").JsonValue;

test "stringify test" {
    const allocator = testing.allocator;

    var obj = std.StringArrayHashMap(JsonValue).init(allocator);

    try obj.put("name", JsonValue{ .String = "Zig" });
    try obj.put("awesome", JsonValue{ .Bool = true });
    try obj.put("version", JsonValue{ .Number = 0.11 });
    
    var arr_list = std.ArrayList(JsonValue).initCapacity(allocator, 3) catch unreachable;
    defer arr_list.deinit(allocator);
    try arr_list.append(allocator, JsonValue{ .Number = 1 });
    try arr_list.append(allocator, JsonValue{ .Number = 2 });
    try arr_list.append(allocator, JsonValue{ .Number = 3 });

    try obj.put("list", JsonValue{ .Array = try arr_list.toOwnedSlice(allocator) });

    // Note: Manual cleanup of the JsonValue tree structure since we constructed it manually
    // but the `JsonValue.deinit` helper assumes full ownership.
    // Since we are constructing partial parts (like 'obj' which is just the hashmap),
    // we should be careful. 
    // The safest way is to wrap it in the root JsonValue and call deinit on that.
    var root = JsonValue{ .Object = obj };
    defer root.deinit(allocator); // This cleans up keys, values, and the map/array memory.

    var list = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer list.deinit(allocator);

    try root.stringify(list.writer(allocator));

    const expected = "{\"name\":\"Zig\",\"awesome\":true,\"version\":0.11,\"list\":[1,2,3]}";
    try testing.expectEqualStrings(expected, list.items);
}

test "stringify escaping" {
    var list = std.ArrayList(u8).initCapacity(testing.allocator, 0) catch unreachable;
    defer list.deinit(testing.allocator);

    const val = JsonValue{ .String = "Hello\n\t\"World\"" };
    try val.stringify(list.writer(testing.allocator));

    try testing.expectEqualStrings("\"Hello\\n\\t\\\"World\\\"\"", list.items);
}
