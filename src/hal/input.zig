const gpio = @import("gpio.zig");

pub const Pull = enum {
    floating,
    up,
    down,
};

pub const Active = enum {
    high,
    low,
};

pub const ButtonConfig = struct {
    pin: gpio.Pin,
    pull: Pull = .up,
    active: Active = .low,
};

pub const Button = struct {
    pin: gpio.Pin,
    active: Active,

    pub fn init(config: ButtonConfig) Button {
        gpio.enablePortClock(config.pin.port);

        switch (config.pull) {
            .floating => config.pin.configure(.input_floating),
            .up => {
                config.pin.configure(.input_pull);
                config.pin.write(true);
            },
            .down => {
                config.pin.configure(.input_pull);
                config.pin.write(false);
            },
        }

        return .{
            .pin = config.pin,
            .active = config.active,
        };
    }

    pub fn isPressed(self: Button) bool {
        const level = self.pin.read();
        return switch (self.active) {
            .high => level,
            .low => !level,
        };
    }

    pub fn isReleased(self: Button) bool {
        return !self.isPressed();
    }
};

pub fn button(config: ButtonConfig) Button {
    return Button.init(config);
}

const default_button = Button{
    .pin = gpio.pin(.D, 1),
    .active = .low,
};

pub fn initButtonPd1Pullup() void {
    _ = Button.init(.{
        .pin = default_button.pin,
        .pull = .up,
        .active = default_button.active,
    });
}

pub fn isButtonPressed() bool {
    return default_button.isPressed();
}
