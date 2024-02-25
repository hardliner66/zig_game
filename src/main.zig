const std = @import("std");
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
        camera.target = rl.Vector2{ .x = pos[i].x, .y = pos[i].y };
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
                }, rl.RED);
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

    ecs.COMPONENT(world, Position);
    ecs.COMPONENT(world, ecs.EcsRest);
    ecs.COMPONENT(world, Drawable);

    ecs.TAG(world, Player);
    ecs.TAG(world, CameraTarget);
    ecs.TAG(world, Background);
    ecs.TAG(world, Foreground);

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = handle_input;
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(Position) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(Player) };
        ecs.SYSTEM(world, "handle_input", ecs.OnUpdate, &system_desc);
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = get_camera_target;
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(Position) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(CameraTarget) };
        ecs.SYSTEM(world, "get_camera_target", ecs.OnUpdate, &system_desc);
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = draw;
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(Position) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(Drawable) };
        system_desc.query.filter.terms[2] = .{ .id = ecs.id(Background) };
        ecs.SYSTEM(world, "draw_background", ecs.PostUpdate, &system_desc);
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = draw;
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(Position) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(Drawable) };
        system_desc.query.filter.terms[2] = .{ .id = ecs.id(Foreground), .oper = ecs.oper_kind_t.Not };
        system_desc.query.filter.terms[3] = .{ .id = ecs.id(Background), .oper = ecs.oper_kind_t.Not };
        ecs.SYSTEM(world, "draw", ecs.PostUpdate, &system_desc);
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = draw;
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(Position) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(Drawable) };
        system_desc.query.filter.terms[2] = .{ .id = ecs.id(Foreground) };
        ecs.SYSTEM(world, "draw_foreground", ecs.PostUpdate, &system_desc);
    }

    return world;
}

fn generate_buildings(world: *ecs.world_t) void {
    std.debug.print("here", .{});
    var spacing: i32 = 0;
    for (0..MAX_BUILDINGS) |_| {
        const entity = ecs.new_entity(world, "");
        const width: f32 = @floatFromInt(rl.GetRandomValue(50, 200));
        const height: f32 = @floatFromInt(rl.GetRandomValue(100, 800));
        const x: f32 = @floatFromInt(-6000 + spacing);
        const y = screen_height - 130.0 - height;
        const building = rl.Rectangle{ .x = x, .y = y, .width = width, .height = height };
        spacing += @as(i32, @intFromFloat(width));

        const r: u8 = @truncate(@as(u32, @intCast(rl.GetRandomValue(200, 240))));
        const g: u8 = @truncate(@as(u32, @intCast(rl.GetRandomValue(200, 240))));
        const b: u8 = @truncate(@as(u32, @intCast(rl.GetRandomValue(200, 240))));
        std.debug.print("Color: {d} {d} {d}\n", .{ r, g, b });
        const col = rl.Color{ .r = r, .g = g, .b = b, .a = 255 };
        _ = ecs.set(world, entity, Position, .{ .x = building.x, .y = building.y });
        _ = ecs.set(world, entity, Drawable, .{ .color_rect = .{ .rect = building, .color = col } });
        _ = ecs.add(world, entity, Background);
    }
}

pub fn main() anyerror!void {
    const world = init_ecs(.{});
    defer _ = ecs.fini(world);

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

    rl.InitWindow(screen_width, screen_height, "ZigGame");
    defer rl.CloseWindow();

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
                    // last_state = game_state;
                    // game_state = GameState.exit_requested;
                    exitWindow = true;
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

        rl.BeginMode2D(camera);
        defer rl.EndMode2D();

        _ = ecs.progress(world, 0);
    }
}
