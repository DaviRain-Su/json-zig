# json-zig

A simple, zero-dependency JSON parser and stringifier for Zig.

## Features

- **Parsing**: Parse JSON strings into a flexible `JsonValue` union.
- **Stringify**: Convert `JsonValue` structures back into JSON strings.
- **Formatting**: Directly print `JsonValue` using `{}` or `{f}` format specifiers.
- **Zero-copy (mostly)**: Strings are slices of the input where possible (standard string parsing).

## Installation

### 1. Add dependency to `build.zig.zon`

Run the following command to fetch the package and add it to your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/DaviRain-Su/json-zig.git
```

(Replace the URL with the actual repository URL if different).

### 2. Expose the module in `build.zig`

In your project's `build.zig`, add the module to your executable or library:

```zig
pub fn build(b: *std.Build) void {
    // ...
    const json_zig = b.dependency("json_zig", .{
        .target = target,
        .optimize = optimize,
    });
    
    exe.root_module.addImport("json_zig", json_zig.module("json_zig"));
    // ...
}
```

## Usage

### Parsing JSON

```zig
const std = @import("std");
const json = @import("json_zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\{
        \\  "name": "Zig",
        \\  "version": 0.11,
        \\  "features": ["fast", "safe"]
        \\}
    ;

    // Parse the JSON string
    // Note: It uses the allocator for internal structures (arrays, hashmaps).
    const root = try json.parse(allocator, input);
    // You can call root.deinit(allocator) if not using an ArenaAllocator,
    // but Arena is recommended for easier cleanup.
    
    if (root == .Object) {
        const obj = root.Object;
        if (obj.get("name")) |name| {
            std.debug.print("Name: {s}\n", .{name.String});
        }
    }
}
```

### Stringify (Generating JSON)

```zig
const std = @import("std");
const json = @import("json_zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var list = try std.ArrayList(u8).init(allocator);
    defer list.deinit(allocator); // managed by arena

    const val = json.JsonValue{ .String = "Hello World" };
    
    std.debug.print("JSON: {f}\n", .{list.items});
}
```

### Formatting

`JsonValue` implements `std.fmt.format`, so you can print it directly:

```zig
std.debug.print("Value: {f}\n", .{my_json_value});
```

## Running Tests

To run the library's tests:

```bash
zig build test
```

## License

MIT
