const std = @import("std");
const mem = std.mem;
const os = std.os;
const fmt = std.fmt;
const maxInt = std.math.maxInt;
const rl = @cImport(@cInclude("raylib.h"));
const ecs = @import("zflecs");

const screen_width = 800;
const screen_height = 450;

// Globals
var camera = rl.Camera2D{
    .offset = rl.Vector2{
        .x = screen_width / 2.0,
        .y = screen_height / 2.0,
    },
    .target = rl.Vector2{ .x = 0, .y = 0 },
    .rotation = 0,
    .zoom = 1,
};

// Constants
const MAX_BUILDINGS = 100;

// Game States
const GameStateStartup = struct {};
const GameStateStartScreen = struct {};
const GameStateLoop = struct {};
const GameStateExitRequested = struct {};

const GameState = union(enum) {
    startup: GameStateStartup,
    start_screen: GameStateStartScreen,
    loop: GameStateLoop,
    exit_requested: GameStateExitRequested,
};

// Parts
const ColorRectangle = struct { rect: rl.Rectangle, color: rl.Color };

// Components
const Position = struct { x: f32, y: f32 };
const Drawable = union(enum) { rect: rl.Rectangle, color_rect: ColorRectangle };

// Tags
const Player = struct {};
const CameraTarget = struct {};
const Background = struct {};
const Foreground = struct {};

// Systems

fn handle_input(it: *ecs.iter_t) callconv(.C) void {
    const pos = ecs.field(it, Position, 1).?;
    _ = ecs.field(it, Player, 2);

    camera.zoom += rl.GetMouseWheelMove() * 0.05;

    if (camera.zoom > 3.0) {
        camera.zoom = 3.0;
    } else if (camera.zoom < 0.1) {
        camera.zoom = 0.1;
    }

    if (rl.IsKeyPressed(rl.KEY_R)) {
        camera.zoom = 1.0;
    }

    for (0..it.count()) |i| {
        if (rl.IsKeyDown(rl.KEY_A)) {
            pos[i].x -= 2;
        }
        if (rl.IsKeyDown(rl.KEY_D)) {
            pos[i].x += 2;
        }
        if (rl.IsKeyDown(rl.KEY_W)) {
            pos[i].y -= 2;
        }
        if (rl.IsKeyDown(rl.KEY_S)) {
            pos[i].y += 2;
        }
    }
}
fn get_camera_target(it: *ecs.iter_t) callconv(.C) void {
    const pos = ecs.field(it, Position, 1).?;
    _ = ecs.field(it, CameraTarget, 2);

    for (0..it.count()) |i| {
        camera.target = rl.Vector2{ .x = pos[i].x + 20, .y = pos[i].y + 20 };
        break;
    }
}

fn draw(it: *ecs.iter_t) callconv(.C) void {
    const pos = ecs.field(it, Position, 1).?;
    const drawable = ecs.field(it, Drawable, 2).?;

    for (0..it.count()) |i| {
        const p = pos[i];
        switch (drawable[i]) {
            Drawable.rect => |d| {
                rl.DrawRectangleRec(rl.Rectangle{
                    .x = d.x + p.x,
                    .y = d.y + p.y,
                    .width = d.width,
                    .height = d.height,
                }, rl.RED);
            },
            Drawable.color_rect => |d| {
                rl.DrawRectangleRec(rl.Rectangle{
                    .x = d.rect.x + p.x,
                    .y = d.rect.y + p.y,
                    .width = d.rect.width,
                    .height = d.rect.height,
                }, d.color);
            },
        }
    }
}

const InitArgs = struct {
    enable_rest: bool = true,
    enable_monitor: bool = true,
};

fn init_ecs(args: InitArgs) *ecs.world_t {
    const world = ecs.init();

    if (args.enable_monitor) {
        _ = ecs.import_c(world, ecs.FlecsMonitorImport, "FlecsMonitor");
    }
    if (args.enable_rest) {
        const EcsRest = ecs.lookup_fullpath(world, "flecs.rest.Rest");
        const EcsRestVal: ecs.EcsRest = .{};
        _ = ecs.set_id(world, EcsRest, EcsRest, @sizeOf(ecs.EcsRest), &EcsRestVal);
    }

    // var camera = rl.Camera2D{
    //     .offset = rl.Vector2{
    //         .x = screen_width / 2.0,
    //         .y = screen_height / 2.0,
    //     },
    //     .target = rl.Vector2{ .x = 0, .y = 0 },
    //     .rotation = 0,
    //     .zoom = 1,
    // };

    ecs.COMPONENT(world, Position);
    ecs.COMPONENT(world, Drawable);

    ecs.TAG(world, Player);
    ecs.TAG(world, CameraTarget);
    ecs.TAG(world, Background);
    ecs.TAG(world, Foreground);

    const handle_input_system = sys: {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = handle_input;
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(Position) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(Player) };
        break :sys SYSTEM(world, "handle_input", ecs.OnUpdate, &system_desc);
    };

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = get_camera_target;
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(Position) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(CameraTarget) };
        _ = SYSTEM(world, "get_camera_target", handle_input_system, &system_desc);
    }

    const draw_background_system = sys: {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = draw;
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(Position) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(Drawable) };
        system_desc.query.filter.terms[2] = .{ .id = ecs.id(Background) };
        break :sys SYSTEM(world, "draw_background", ecs.PostUpdate, &system_desc);
    };

    const draw_midground_system = sys: {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = draw;
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(Position) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(Drawable) };
        system_desc.query.filter.terms[2] = .{ .id = ecs.id(Foreground), .oper = ecs.oper_kind_t.Not };
        system_desc.query.filter.terms[3] = .{ .id = ecs.id(Background), .oper = ecs.oper_kind_t.Not };
        break :sys SYSTEM(world, "draw", draw_background_system, &system_desc);
    };

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = draw;
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(Position) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(Drawable) };
        system_desc.query.filter.terms[2] = .{ .id = ecs.id(Foreground) };
        ecs.SYSTEM(world, "draw_foreground", draw_midground_system, &system_desc);
    }

    return world;
}

const building_names: [MAX_BUILDINGS][]const u8 = .{
    "building_1",
    "building_2",
    "building_3",
    "building_4",
    "building_5",
    "building_6",
    "building_7",
    "building_8",
    "building_9",
    "building_10",
    "building_11",
    "building_12",
    "building_13",
    "building_14",
    "building_15",
    "building_16",
    "building_17",
    "building_18",
    "building_19",
    "building_20",
    "building_21",
    "building_22",
    "building_23",
    "building_24",
    "building_25",
    "building_26",
    "building_27",
    "building_28",
    "building_29",
    "building_30",
    "building_31",
    "building_32",
    "building_33",
    "building_34",
    "building_35",
    "building_36",
    "building_37",
    "building_38",
    "building_39",
    "building_40",
    "building_41",
    "building_42",
    "building_43",
    "building_44",
    "building_45",
    "building_46",
    "building_47",
    "building_48",
    "building_49",
    "building_50",
    "building_51",
    "building_52",
    "building_53",
    "building_54",
    "building_55",
    "building_56",
    "building_57",
    "building_58",
    "building_59",
    "building_60",
    "building_61",
    "building_62",
    "building_63",
    "building_64",
    "building_65",
    "building_66",
    "building_67",
    "building_68",
    "building_69",
    "building_70",
    "building_71",
    "building_72",
    "building_73",
    "building_74",
    "building_75",
    "building_76",
    "building_77",
    "building_78",
    "building_79",
    "building_80",
    "building_81",
    "building_82",
    "building_83",
    "building_84",
    "building_85",
    "building_86",
    "building_87",
    "building_88",
    "building_89",
    "building_90",
    "building_91",
    "building_92",
    "building_93",
    "building_94",
    "building_95",
    "building_96",
    "building_97",
    "building_98",
    "building_99",
    "building_100",
};

fn format(comptime s: usize, comptime f: []const u8, args: anytype) ![]const u8 {
    var buf: [s]u8 = undefined;
    var writer = std.io.fixedBufferStream(&buf);
    try std.fmt.format(writer.writer(), f, args);
    const result = writer.writer().context.getWritten();
    std.debug.print("result: {s}\n", .{result});
    return result;
}

fn generate_buildings(world: *ecs.world_t) void {
    var spacing: i32 = 0;
    for (0..MAX_BUILDINGS) |i| {
        const entity = ecs.new_entity(world, @ptrCast(building_names[i]));
        // _ = ecs.set_name(world, entity, building_names[i]);
        const width: f32 = @floatFromInt(rl.GetRandomValue(50, 200));
        const height: f32 = @floatFromInt(rl.GetRandomValue(100, 800));
        const x: f32 = @floatFromInt(-6000 + spacing);
        const y = screen_height - 130.0 - height;
        const building = rl.Rectangle{ .x = x, .y = y, .width = width, .height = height };
        spacing += @as(i32, @intFromFloat(width));

        const r1 = rl.GetRandomValue(200, 240);
        const g1 = rl.GetRandomValue(200, 240);
        const b1 = rl.GetRandomValue(200, 240);
        const r: u8 = @truncate(@as(u32, @intCast(r1)));
        const g: u8 = @truncate(@as(u32, @intCast(g1)));
        const b: u8 = @truncate(@as(u32, @intCast(b1)));
        const col = rl.Color{ .r = r, .g = g, .b = b, .a = 255 };
        _ = ecs.set(world, entity, Position, .{ .x = building.x, .y = building.y });
        _ = ecs.set(world, entity, Drawable, .{ .color_rect = .{ .rect = building, .color = col } });
        _ = ecs.add(world, entity, Background);
    }
}

fn draw_debug(game_state: GameState) void {
    _ = game_state;
    rl.DrawLine(
        @intFromFloat(camera.target.x),
        -screen_height * 10,
        @intFromFloat(camera.target.x),
        screen_height * 10,
        rl.GREEN,
    );
    rl.DrawLine(
        -screen_width * 10,
        @intFromFloat(camera.target.y),
        screen_width * 10,
        @intFromFloat(camera.target.y),
        rl.GREEN,
    );
}

fn draw_ui(game_state: GameState) !void {
    rl.DrawText("SCREEN AREA", 640, 10, 20, rl.RED);
    var buf: [20]u8 = std.mem.zeroes([20]u8);
    const fps = try std.fmt.bufPrint(&buf, "FPS: {}", .{rl.GetFPS()});
    rl.DrawText(@ptrCast(fps), 10, 10, 20, rl.DARKGRAY);

    rl.DrawRectangle(0, 0, screen_width, 5, rl.RED);
    rl.DrawRectangle(0, 5, 5, screen_height - 10, rl.RED);
    rl.DrawRectangle(screen_width - 5, 5, 5, screen_height - 10, rl.RED);
    rl.DrawRectangle(0, screen_height - 5, screen_width, 5, rl.RED);

    const info_box_y = 20;
    rl.DrawRectangle(10, info_box_y + 10, 250, 80, rl.Fade(rl.SKYBLUE, 0.5));
    rl.DrawRectangleLines(10, info_box_y + 10, 250, 80, rl.BLUE);

    rl.DrawText("Free 2d camera controls:", 20, info_box_y + 20, 10, rl.BLACK);
    rl.DrawText("- WASD to move", 40, info_box_y + 40, 10, rl.DARKGRAY);
    rl.DrawText("- Mouse Wheel to Zoom in-out", 40, info_box_y + 60, 10, rl.DARKGRAY);

    switch (game_state) {
        GameState.exit_requested => {
            rl.DrawRectangle(0, 100, screen_width, 200, rl.BLACK);
            rl.DrawText("Do you want to exit? (Y/N)", 40, 180, 30, rl.WHITE);
        },
        else => {},
    }
}

pub fn main() anyerror!void {
    const world = init_ecs(.{});
    defer _ = ecs.fini(world);

    // const allocator = std.heap.c_allocator;
    // var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = general_purpose_allocator.allocator();

    rl.InitWindow(screen_width, screen_height, "ZigGame");
    defer rl.CloseWindow();

    const seed = std.time.milliTimestamp(); // Get a timestamp or another varying seed
    rl.SetRandomSeed(@as(u32, @truncate(@as(u64, @intCast(seed)))));

    generate_buildings(world);

    const player = ecs.new_entity(world, "Player");
    _ = ecs.set(world, player, Position, .{ .x = 400, .y = 280 });
    _ = ecs.set(world, player, Drawable, .{
        .rect = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = 40,
            .height = 40,
        },
    });
    _ = ecs.add(world, player, Player);
    _ = ecs.add(world, player, CameraTarget);

    // Initialization
    //--------------------------------------------------------------------------------------

    var exitWindow = false;

    var game_state = GameState{ .startup = GameStateStartup{} };
    var last_state = game_state;

    rl.SetTargetFPS(60);
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!exitWindow) {
        switch (game_state) {
            GameState.startup => {
                last_state = game_state;
                game_state = GameState.start_screen;
            },
            GameState.start_screen => {
                last_state = game_state;
                game_state = GameState.loop;
            },
            GameState.loop => {
                if (rl.WindowShouldClose()) {
                    last_state = game_state;
                    game_state = GameState.exit_requested;
                }
            },
            GameState.exit_requested => {
                if (rl.IsKeyPressed(rl.KEY_Y) or rl.IsKeyPressed(rl.KEY_Z)) {
                    exitWindow = true;
                } else if (rl.IsKeyPressed(rl.KEY_N)) {
                    game_state = last_state;
                }
            },
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.WHITE);

        {
            rl.BeginMode2D(camera);
            defer rl.EndMode2D();

            _ = ecs.progress(world, 0);
            draw_debug(game_state);
        }

        try draw_ui(game_state);
    }
}

pub fn SYSTEM(
    world: *ecs.world_t,
    name: [*:0]const u8,
    phase: ecs.entity_t,
    system_desc: *ecs.system_desc_t,
) ecs.entity_t {
    var entity_desc = ecs.entity_desc_t{};
    entity_desc.id = ecs.new_id(world);
    entity_desc.name = name;
    entity_desc.add[0] = if (phase != 0) ecs.pair(ecs.DependsOn, phase) else 0;
    entity_desc.add[1] = phase;

    system_desc.entity = ecs.entity_init(world, &entity_desc);
    return ecs.system_init(world, system_desc);
}
