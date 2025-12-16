const std = @import("std");
test "ArrayList test" {
    var list = std.ArrayList(u8).initCapacity(std.testing.allocator, 10);
    list.deinit();
}
