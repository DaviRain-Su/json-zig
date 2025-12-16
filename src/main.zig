const std = @import("std");
const json_zig = @import("json_zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const json_string =
        \\{
        \\  "name": "Zig Language",
        \\  "version": 0.11,
        \\  "is_awesome": true,
        \\  "features": ["fast", "safe", "simple"],
        \\  "maintainers": null
        \\}
    ;

    std.debug.print("Parsing JSON string:\n{s}\n", .{json_string});

    var json_value = try json_zig.parse(allocator, json_string);
    defer json_value.deinit(allocator);

    std.debug.print("\nParsed JsonValue (using {{f}} format):\n{f}\n", .{json_value});

    // Example of accessing values
    if (json_value == .Object) {
        const obj = json_value.Object;
        if (obj.get("name")) |name_val| {
            std.debug.print("Name: {s}\n", .{name_val.String});
        }
        if (obj.get("version")) |version_val| {
            std.debug.print("Version: {d}\n", .{version_val.Number});
        }
        if (obj.get("features")) |features_val| {
            std.debug.print("Features: ", .{});
            for (features_val.Array) |feature_val| {
                std.debug.print("{s} ", .{feature_val.String});
            }
            std.debug.print("\n", .{});
        }
    }
}
