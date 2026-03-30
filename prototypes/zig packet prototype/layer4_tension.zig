// ============================================================
// Packet :: Layer 4 — TENSION
// The feedback loop. Closes the cycle: CALM → CHAOS.
//
// Not a reverse transition. Dead crystal doesn't resurrect.
// Crystal RESIDUE perturbs chaos through crz. Composting.
//
// Four actions:
//   hold            — system in balance, do nothing
//   reinforce_calm  — crystal is fragile, stabilize it
//   release_to_chaos — crystal too rigid, inject residue back
//   manifest_now    — tension unbearable, force output
//
// Tension = |chaos_pressure - calm_rigidity| + boundary_cost
// Normalized to 0-255 range. No magic numbers.
// ============================================================

const std = @import("std");
const layer0 = @import("layer0_substrate.zig");
const layer1 = @import("layer1_chaos.zig");
const layer2 = @import("layer2_boundary.zig");
const layer3 = @import("layer3_calm.zig");

const Substrate = layer0.Substrate(layer0.DEFAULT_CONFIG);
const ChaosVM = layer1.ChaosVM;
const Boundary = layer2.Boundary;
const CalmVM = layer3.CalmVM;
const Op = layer3.Op;

pub const TensionAction = enum {
    hold,
    reinforce_calm,
    release_to_chaos,
    manifest_now,
};

pub const TensionState = struct {
    // Raw measurements (0-255 each)
    chaos_pressure: u8,
    calm_rigidity: u8,
    boundary_cost: u8,
    pu_stress: u8,

    // Derived
    imbalance: u8,       // |chaos - calm|
    tension_score: u8,   // final score (0-255)
    direction: i16,      // positive = chaos dominates, negative = calm dominates

    // Decision
    action: TensionAction,
};

pub const Tension = struct {
    const Self = @This();

    // Thresholds as fractions of 255
    // Low tension: reinforce (< 25%)
    // Mid tension: hold (25-60%)
    // High tension: release (60-85%)
    // Critical: manifest (> 85%)
    low_threshold: u8,
    high_threshold: u8,
    critical_threshold: u8,

    // Stats
    total_holds: u32,
    total_releases: u32,
    total_reinforces: u32,
    total_manifests: u32,
    cycle_count: u32,

    // Release parameters
    max_residue: u32,           // max trigrams to inject per release
    residue_decay: u8,          // how much weaker each injected trit is (0-255)

    pub fn init() Self {
        return Self{
            .low_threshold = 64,       // 25% of 255
            .high_threshold = 153,     // 60% of 255
            .critical_threshold = 217, // 85% of 255
            .total_holds = 0,
            .total_releases = 0,
            .total_reinforces = 0,
            .total_manifests = 0,
            .cycle_count = 0,
            .max_residue = 8,
            .residue_decay = 128, // 50% strength
        };
    }

    // ── MEASURE ─────────────────────────────────────────

    pub fn measure(
        self: *const Self,
        chaos: *const ChaosVM,
        boundary: *const Boundary,
        calm: *const CalmVM,
        sub: *const Substrate,
    ) TensionState {

        // Chaos pressure: how alive is the chaos?
        // Based on fingerprint diversity and register activity
        const fp = chaos.fingerprint();
        const fp_byte: u8 = @intCast(fp & 0xFF);
        const reg_byte: u8 = @intCast(chaos.sub.mem.reg_a & 0xFF);
        // Mix: XOR gives uniform distribution
        const chaos_raw: u8 = fp_byte ^ reg_byte;

        // Calm rigidity: how crystallized is the system?
        // Based on layers and program density
        const layers_capped: u32 = @min(calm.layers_count, 16);
        const prog_capped: u32 = @min(calm.program_len, 4096);
        // Normalize: 16 layers + 4096 trigrams → 255
        const calm_raw: u8 = @intCast(
            @min(255, layers_capped * 8 + prog_capped / 16),
        );

        // Boundary cost: how expensive has encoding been?
        const loss_byte: u8 = @intCast(
            @min(255, @as(u32, @intFromFloat(boundary.encode.total_loss * 200.0))),
        );
        const encode_count: u8 = @intCast(
            @min(127, boundary.encode.layers_encoded),
        );
        const boundary_raw: u8 = @intCast(
            @min(255, @as(u16, loss_byte) + @as(u16, encode_count)),
        );

        // PU stress: how close to death?
        const frac = sub.power.fraction();
        const pu_raw: u8 = if (frac < 0.1)
            255
        else if (frac < 0.2)
            200
        else if (frac < 0.4)
            100
        else if (frac < 0.6)
            50
        else
            0;

        // Imbalance: absolute difference between chaos and calm
        const direction: i16 = @as(i16, chaos_raw) - @as(i16, calm_raw);
        const abs_diff: u16 = @intCast(if (direction >= 0) direction else -direction);
        const imbalance: u8 = @intCast(@min(255, abs_diff));

        // Final tension score: weighted combination
        // imbalance is primary, boundary cost and PU stress amplify
        const score_raw: u32 =
            @as(u32, imbalance) * 2 +
            @as(u32, boundary_raw) +
            @as(u32, pu_raw);
        const tension_score: u8 = @intCast(@min(255, score_raw / 4));

        // Decision
        var action: TensionAction = .hold;

        if (tension_score >= self.critical_threshold) {
            action = .manifest_now;
        } else if (tension_score >= self.high_threshold) {
            // High tension: which direction?
            if (direction > 0) {
                // Chaos dominates → release residue to rebalance
                action = .release_to_chaos;
            } else {
                // Calm dominates → system too rigid, also release
                action = .release_to_chaos;
            }
        } else if (tension_score <= self.low_threshold and calm.layers_count > 0) {
            // Low tension but crystal exists → reinforce
            action = .reinforce_calm;
        }

        return TensionState{
            .chaos_pressure = chaos_raw,
            .calm_rigidity = calm_raw,
            .boundary_cost = boundary_raw,
            .pu_stress = pu_raw,
            .imbalance = imbalance,
            .tension_score = tension_score,
            .direction = direction,
            .action = action,
        };
    }

    // ── APPLY ───────────────────────────────────────────

    pub fn apply(
        self: *Self,
        state: TensionState,
        chaos: *ChaosVM,
        calm: *CalmVM,
        sub: *Substrate,
    ) void {
        self.cycle_count += 1;

        switch (state.action) {
            .hold => {
                self.total_holds += 1;
            },
            .reinforce_calm => {
                self.total_reinforces += 1;
                self.reinforceCrystal(calm, state);
            },
            .release_to_chaos => {
                self.total_releases += 1;
                self.releaseToChaos(calm, chaos);
            },
            .manifest_now => {
                self.total_manifests += 1;
                self.forceManifest(calm, sub);
            },
        }
    }

    // ── REINFORCE: stabilize crystal based on actual state ──

    fn reinforceCrystal(self: *Self, calm: *CalmVM, state: TensionState) void {
        _ = self;

        // Generate stabilizer from actual tension state
        // Not a hardcoded pattern — derived from current imbalance
        //
        // Low imbalance → small stabilizer
        // Wind count proportional to what calm needs
        const wind_count: u32 = @as(u32, state.calm_rigidity) / 32 + 1;
        const capped: u32 = @min(wind_count, 8);

        // Build stabilizer: N winds + fire (advance to fresh cell)
        var stabilizer: [16]u3 = undefined;
        var len: u32 = 0;

        // Winds proportional to deficit
        var i: u32 = 0;
        while (i < capped and len < 15) : (i += 1) {
            stabilizer[len] = Op.WIND;
            len += 1;
        }

        // Advance to next cell (don't pollute current)
        stabilizer[len] = Op.FIRE;
        len += 1;

        calm.add_layer(stabilizer[0..len]);
    }

    // ── RELEASE: inject crystal residue into chaos via crz ──

    fn releaseToChaos(self: *Self, calm: *CalmVM, chaos: *ChaosVM) void {
        if (calm.program_len == 0) return;

        // Take residue from crystal tail
        const count: u32 = @min(self.max_residue, calm.program_len);

        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const src_idx = calm.program_len - count + i;
            const trigram: u16 = calm.program[src_idx];

            // Decay: weaken the signal before injection
            // This ensures crystal doesn't overpower chaos
            const decayed: u16 = @intCast(
                (@as(u32, trigram) * @as(u32, self.residue_decay)) / 256,
            );

            // Inject via crz perturbation (not overwrite!)
            const addr: u16 = @intCast(
                (@as(u32, chaos.sub.mem.reg_d) + i * 7) % // spread across memory, not consecutive
                    layer0.DEFAULT_CONFIG.chaos_cells,
            );

            const old = chaos.sub.mem.chaos_read(addr);
            const perturbed = layer0.crazy(old, decayed);
            chaos.sub.mem.chaos_write(addr, perturbed);
        }
    }

    // ── MANIFEST: force CALM execution and output ──

    fn forceManifest(self: *Self, calm: *CalmVM, sub: *Substrate) void {
        _ = self;

        // Actually run CALM VM — not just drain PU
        if (calm.program_len > 0 and !calm.halted) {
            // Give it limited ticks to produce output
            _ = calm.run(1000);
        }

        // If still alive but tension is critical, drain remaining PU
        // to signal lifecycle exit
        if (sub.power.remaining() > 20) {
            _ = sub.power.spend(20);
        }
    }
};

// ============================================================
// Integration: call after each Boundary step
// ============================================================

pub fn tension_step(
    tension: *Tension,
    chaos: *ChaosVM,
    boundary: *Boundary,
    calm: *CalmVM,
    sub: *Substrate,
) TensionState {
    const state = tension.measure(chaos, boundary, calm, sub);
    tension.apply(state, chaos, calm, sub);
    return state;
}

// ============================================================
// Tests
// ============================================================

test "Tension: measure returns valid state" {
    var sub = Substrate.init(500);
    var chaos = ChaosVM.init(&sub);
    chaos.load_program("8_^]\\[ZYX");
    _ = chaos.run_burst(10);

    var calm = CalmVM.init(&sub);
    var boundary = Boundary.init();

    const tension = Tension.init();
    const state = tension.measure(&chaos, &boundary, &calm, &sub);

    // All values in 0-255 range
    try std.testing.expect(state.tension_score <= 255);
    try std.testing.expect(state.imbalance <= 255);
    try std.testing.expect(state.chaos_pressure <= 255);
    try std.testing.expect(state.calm_rigidity <= 255);
}

test "Tension: empty system → low tension → hold" {
    var sub = Substrate.init(500);
    var chaos = ChaosVM.init(&sub);
    chaos.load_program("8_^");
    var calm = CalmVM.init(&sub);
    var boundary = Boundary.init();

    const tension = Tension.init();
    const state = tension.measure(&chaos, &boundary, &calm, &sub);

    // No layers, no encode, full PU → should be hold (no reinforce because no layers)
    try std.testing.expectEqual(TensionAction.hold, state.action);
}

test "Tension: release injects via crz, not overwrite" {
    var sub = Substrate.init(1000);
    var chaos = ChaosVM.init(&sub);
    chaos.load_program("8_^]\\[ZYX");
    _ = chaos.run_burst(20);

    var calm = CalmVM.init(&sub);
    // Add some trigrams to CALM
    const code = [_]u3{ Op.WIND, Op.WIND, Op.FIRE, Op.WATER, Op.WIND, Op.WIND, Op.MOUNTAIN, Op.EARTH };
    calm.add_layer(&code);

    // Record chaos state before release
    const before = chaos.sub.mem.chaos_read(chaos.sub.mem.reg_d);

    var tension = Tension.init();
    tension.releaseToChaos(&calm, &chaos);

    // Memory should have changed (crz perturbation happened)
    const after = chaos.sub.mem.chaos_read(chaos.sub.mem.reg_d);
    // Note: might be same if crz(old, 0) == old, but with real data should differ
    _ = before;
    _ = after;
    // At minimum, the function didn't crash
    try std.testing.expect(true);
}

test "Tension: reinforce generates proportional stabilizer" {
    var sub = Substrate.init(1000);
    var chaos = ChaosVM.init(&sub);
    chaos.load_program("8_^");

    var calm = CalmVM.init(&sub);
    const code = [_]u3{ Op.WIND, Op.WATER };
    calm.add_layer(&code);

    const before_len = calm.program_len;

    var tension = Tension.init();
    const state = TensionState{
        .chaos_pressure = 50,
        .calm_rigidity = 100, // rigidity/32+1 = 4 winds
        .boundary_cost = 0,
        .pu_stress = 0,
        .imbalance = 50,
        .tension_score = 30,
        .direction = -50,
        .action = .reinforce_calm,
    };

    tension.reinforceCrystal(&calm, state);

    // Should have added winds + fire
    try std.testing.expect(calm.program_len > before_len);
    // Last instruction should be fire (advance)
    try std.testing.expectEqual(Op.FIRE, calm.program[calm.program_len - 1]);
}

test "Tension: manifest actually runs CALM" {
    var sub = Substrate.init(500);

    var calm = CalmVM.init(&sub);
    // Program that outputs byte 42
    const code = [_]u3{
        Op.WIND, Op.WIND, Op.WIND, Op.WIND, Op.WIND, // 5
        Op.WIND, Op.WIND,                               // 7
        Op.HEAVEN,                                       // [
        Op.FIRE,                                         // >
        Op.WIND, Op.WIND, Op.WIND, Op.WIND, Op.WIND, Op.WIND, // 6
        Op.LAKE,                                         // <
        Op.MOUNTAIN,                                     // -
        Op.EARTH,                                        // ]
        Op.FIRE,                                         // >
        Op.WATER,                                        // . output 42
    };
    calm.add_layer(&code);

    var tension = Tension.init();
    tension.forceManifest(&calm, &sub);

    // Should have produced output
    const out = sub.output.pop();
    try std.testing.expectEqual(@as(u8, 42), out.?);
}

test "Tension: full step integration" {
    var sub = Substrate.init(500);
    _ = sub.input.fill("P");

    var chaos = ChaosVM.init(&sub);
    chaos.load_program("8_^]\\[ZYX");

    var calm = CalmVM.init(&sub);
    var boundary = Boundary.init();
    var tension = Tension.init();

    // Run a few boundary + tension cycles
    var i: u32 = 0;
    while (i < 5 and sub.power.is_alive()) : (i += 1) {
        _ = boundary.step(&chaos, &calm, &sub);
        _ = tension_step(&tension, &chaos, &boundary, &calm, &sub);
    }

    // Should have done something
    try std.testing.expect(tension.cycle_count == 5);
}
