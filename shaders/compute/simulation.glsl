#[compute]
#version 450

#include "res://shaders/generated/materials.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;
layout(rgba8, set = 0, binding = 1) readonly uniform image2D neighbor_top;
layout(rgba8, set = 0, binding = 2) readonly uniform image2D neighbor_bottom;
layout(rgba8, set = 0, binding = 3) readonly uniform image2D neighbor_left;
layout(rgba8, set = 0, binding = 4) readonly uniform image2D neighbor_right;

layout(push_constant, std430) uniform PushConstants {
	int phase;
	int frame_seed;
	int _pad2;
	int _pad3;
} pc;

struct InjectionAABB {
	ivec2 aabb_min;
	ivec2 aabb_max;
	ivec2 velocity;
	int _pad0;
	int _pad1;
};

layout(set = 0, binding = 5, std430) readonly buffer InjectionBuffer {
	int count;
	int _pad[3];
	InjectionAABB bodies[];
} injections;

const int CHUNK_SIZE = 256;
const int FIRE_TEMP = 255;
const int HEAT_DISSIPATION = 2;
const int HEAT_SPREAD = 10;
const float SPREAD_PROB_MAX = 0.7;
// --- Gas simulation constants ---
const int V_MAX_OUTFLOW = 8;
// Any inflow turns AIR into GAS; gas reverts to AIR only when truly empty.
// This keeps the simulation mass-conserving: every unit of density that
// leaves a gas cell is captured by its neighbor, never silently destroyed.
const int THRESHOLD_BECOME_GAS = 1;
const int THRESHOLD_BECOME_LAVA = 1;
const int THRESHOLD_DISSIPATE = 1;
const int MAX_INJECTIONS_PER_CHUNK = 32;
const int DIFFUSION_RATE = 4; // Fraction of density gradient to transfer per frame (1/4 = 25%)

uint hash(uint n) {
	n = (n >> 16) ^ n;
	n *= 0xed5ad0bb;
	n = (n >> 16) ^ n;
	n *= 0xac4c1b51;
	n = (n >> 16) ^ n;
	return n;
}

int get_material(vec4 p) { return int(round(p.r * 255.0)); }
int get_health(vec4 p) { return int(round(p.g * 255.0)); }
int get_temperature(vec4 p) { return int(round(p.b * 255.0)); }

vec4 make_pixel(int mat, int hp, int temp) {
	return vec4(float(mat) / 255.0, float(hp) / 255.0, float(temp) / 255.0, 0.0);
}

int get_density(vec4 p) { return int(round(p.g * 255.0)); }

ivec2 unpack_velocity(vec4 p) {
	uint a = uint(round(p.a * 255.0));
	return ivec2(int(a >> 4) - 8, int(a & 15u) - 8);
}

ivec2 unpack_velocity_lava(vec4 p) {
	uint a = uint(round(p.a * 255.0));
	return ivec2(int(a >> 4) - 8, int(a & 15u) - 8);
}

vec4 pack_gas(int density, ivec2 vel) {
	int vx = clamp(vel.x + 8, 0, 15);
	int vy = clamp(vel.y + 8, 0, 15);
	uint a = (uint(vx) << 4) | uint(vy);
	return vec4(
		float(MAT_GAS) / 255.0,
		float(clamp(density, 0, 255)) / 255.0,
		0.0,
		float(a) / 255.0
	);
}

int get_density_lava(vec4 p) { return int(round(p.g * 255.0)); }
int get_temperature_lava(vec4 p) { return int(round(p.b * 255.0)); }

vec4 pack_lava(int density, int temperature, ivec2 vel) {
	int vx = clamp(vel.x + 8, 0, 15);
	int vy = clamp(vel.y + 8, 0, 15);
	uint a = (uint(vx) << 4) | uint(vy);
	return vec4(
		float(MAT_LAVA) / 255.0,
		float(clamp(density, 0, 255)) / 255.0,
		float(clamp(temperature, 0, 255)) / 255.0,
		float(a) / 255.0
	);
}

bool is_solid_for_gas(int mat) {
    // Gas flows only between AIR and GAS. Anything else is a wall.
    return mat != MAT_AIR && mat != MAT_GAS;
}

bool is_solid_for_lava(int mat) {
    // Lava flows only between AIR and LAVA. Anything else is a wall.
    return mat != MAT_AIR && mat != MAT_LAVA;
}

// Integer divide with hash-based stochastic rounding for the remainder.
// `salt` differentiates independent random streams (e.g., 1..4 for four directions).
int stochastic_div(int numerator, int denom, ivec2 pos, uint salt) {
    if (denom <= 0) return 0;
    int base = numerator / denom;
    int rem = numerator - base * denom;
    if (rem <= 0) return base;
    uint rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed) ^ salt));
    return base + (int(rng % uint(denom)) < rem ? 1 : 0);
}

// Returns true if this cell was overwritten by an injection and main() should return.
bool try_inject_rigidbody_velocity(ivec2 pos, int material, inout vec4 pixel) {
    if (material != MAT_GAS && material != MAT_LAVA) return false;
    bool wrote = false;
    int n = min(injections.count, MAX_INJECTIONS_PER_CHUNK);
    for (int i = 0; i < n; i++) {
        InjectionAABB b = injections.bodies[i];
        if (pos.x < b.aabb_min.x || pos.x >= b.aabb_max.x) continue;
        if (pos.y < b.aabb_min.y || pos.y >= b.aabb_max.y) continue;

        if (material == MAT_GAS) {
            // Push gas radially away from body center (not along body velocity).
            // This prevents gas from being "dragged" with the player.
            ivec2 cur_vel = unpack_velocity(pixel);
            ivec2 center = (b.aabb_min + b.aabb_max) / 2;
            ivec2 diff = pos - center;
            // Push at max strength — a solid body forcefully displaces gas.
            ivec2 push_dir = ivec2(0);
            if (diff.x == 0 && diff.y == 0) {
                // Cell is exactly at center — push in body's travel direction
                push_dir = b.velocity;
            } else {
                int dist_x = abs(diff.x);
                int dist_y = abs(diff.y);
                if (dist_x >= dist_y) {
                    push_dir.x = (diff.x >= 0) ? 7 : -7;
                } else {
                    push_dir.y = (diff.y >= 0) ? 7 : -7;
                }
            }
            ivec2 new_vel = clamp(cur_vel + push_dir, ivec2(-8), ivec2(7));
            int dens = get_density(pixel);
            // Reduce density for cells in front of movement to prevent accumulation
            bool in_front = (b.velocity.x > 0 && diff.x > 0) || (b.velocity.x < 0 && diff.x < 0) ||
                            (b.velocity.y > 0 && diff.y > 0) || (b.velocity.y < 0 && diff.y < 0);
            if (in_front && (b.velocity.x != 0 || b.velocity.y != 0)) {
                dens = dens * 3 / 4; // Reduce by 25%
            }
            pixel = pack_gas(dens, new_vel);
        } else {
            ivec2 cur_vel = unpack_velocity_lava(pixel);
            ivec2 center = (b.aabb_min + b.aabb_max) / 2;
            ivec2 diff = pos - center;
            int dist_x = abs(diff.x);
            int dist_y = abs(diff.y);
            ivec2 push_dir = ivec2(0);
            if (dist_x >= dist_y) {
                push_dir.x = (diff.x >= 0) ? 7 : -7;
            } else {
                push_dir.y = (diff.y >= 0) ? 7 : -7;
            }
            ivec2 new_vel = clamp(cur_vel + push_dir, ivec2(-8), ivec2(7));
            int dens = get_density_lava(pixel);
            int temp = get_temperature_lava(pixel);
            pixel = pack_lava(dens, temp, new_vel);
        }
        wrote = true;
    }
    if (wrote) imageStore(chunk_tex, pos, pixel);
    return wrote;
}

void gas_advect_pull(
    ivec2 pos, vec4 pixel,
    vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
    int material = get_material(pixel);

    // --- Fast path: AIR cell with no neighboring gas. Preserve heat decay. ---
    int n_mat_up    = get_material(n_up);
    int n_mat_down  = get_material(n_down);
    int n_mat_left  = get_material(n_left);
    int n_mat_right = get_material(n_right);

    bool any_gas_neighbor =
        n_mat_up == MAT_GAS || n_mat_down == MAT_GAS ||
        n_mat_left == MAT_GAS || n_mat_right == MAT_GAS;

    if (material == MAT_AIR && !any_gas_neighbor) {
        int health = get_health(pixel);
        int temperature = max(0, get_temperature(pixel) - HEAT_DISSIPATION);
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, health, temperature));
        return;
    }

    // --- Own state ---
    int density = (material == MAT_GAS) ? get_density(pixel) : 0;
    ivec2 vel = (material == MAT_GAS) ? unpack_velocity(pixel) : ivec2(0);

    // --- Compute outflow components (only meaningful if density > 0) ---
    int comp_up    = max(0, -vel.y);
    int comp_down  = max(0,  vel.y);
    int comp_left  = max(0, -vel.x);
    int comp_right = max(0,  vel.x);

    // Cancel components that point into a solid (no flow into walls).
    if (is_solid_for_gas(n_mat_up))    comp_up    = 0;
    if (is_solid_for_gas(n_mat_down))  comp_down  = 0;
    if (is_solid_for_gas(n_mat_left))  comp_left  = 0;
    if (is_solid_for_gas(n_mat_right)) comp_right = 0;

    int out_up    = stochastic_div(density * comp_up,    V_MAX_OUTFLOW, pos, 1u);
    int out_down  = stochastic_div(density * comp_down,  V_MAX_OUTFLOW, pos, 2u);
    int out_left  = stochastic_div(density * comp_left,  V_MAX_OUTFLOW, pos, 3u);
    int out_right = stochastic_div(density * comp_right, V_MAX_OUTFLOW, pos, 4u);

    int total_out = out_up + out_down + out_left + out_right;
    // Proportionally scale outflows if they exceed density, and cap to 50% per frame
    // to ensure gas flows gradually rather than evacuating instantly.
    int max_outflow = min(density, max(1, density / 2));
    if (total_out > max_outflow) {
        out_up    = out_up    * max_outflow / max(1, total_out);
        out_down  = out_down  * max_outflow / max(1, total_out);
        out_left  = out_left  * max_outflow / max(1, total_out);
        out_right = out_right * max_outflow / max(1, total_out);
        total_out = out_up + out_down + out_left + out_right;
    }

    // --- Compute inflow from each neighbor toward this cell ---
    int in_up    = 0;
    int in_down  = 0;
    int in_left  = 0;
    int in_right = 0;
    ivec2 vin_up    = ivec2(0);
    ivec2 vin_down  = ivec2(0);
    ivec2 vin_left  = ivec2(0);
    ivec2 vin_right = ivec2(0);

    if (n_mat_up == MAT_GAS) {
        int dN = get_density(n_up);
        ivec2 vN = unpack_velocity(n_up);
        int c = max(0, vN.y);
        in_up = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 5u);
        vin_up = vN;
    }
    if (n_mat_down == MAT_GAS) {
        int dN = get_density(n_down);
        ivec2 vN = unpack_velocity(n_down);
        int c = max(0, -vN.y);
        in_down = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 6u);
        vin_down = vN;
    }
    if (n_mat_left == MAT_GAS) {
        int dN = get_density(n_left);
        ivec2 vN = unpack_velocity(n_left);
        int c = max(0, vN.x);
        in_left = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 7u);
        vin_left = vN;
    }
    if (n_mat_right == MAT_GAS) {
        int dN = get_density(n_right);
        ivec2 vN = unpack_velocity(n_right);
        int c = max(0, -vN.x);
        in_right = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 8u);
        vin_right = vN;
    }

    int total_in = in_up + in_down + in_left + in_right;

    // --- Wall reflection: any velocity component pointing into a solid flips sign ---
    if (is_solid_for_gas(n_mat_up)    && vel.y < 0) vel.y = -vel.y;
    if (is_solid_for_gas(n_mat_down)  && vel.y > 0) vel.y = -vel.y;
    if (is_solid_for_gas(n_mat_left)  && vel.x < 0) vel.x = -vel.x;
    if (is_solid_for_gas(n_mat_right) && vel.x > 0) vel.x = -vel.x;

    // --- Diffusion: spread density toward lower-density neighbors (independent of velocity) ---
    int diff_out = 0;
    if (density > 0) {
        int dens_up    = (n_mat_up == MAT_GAS)    ? get_density(n_up)    : 0;
        int dens_down  = (n_mat_down == MAT_GAS)  ? get_density(n_down)  : 0;
        int dens_left  = (n_mat_left == MAT_GAS)  ? get_density(n_left)  : 0;
        int dens_right = (n_mat_right == MAT_GAS) ? get_density(n_right) : 0;

        if (!is_solid_for_gas(n_mat_up)    && dens_up < density)    diff_out += (density - dens_up) / DIFFUSION_RATE;
        if (!is_solid_for_gas(n_mat_down)  && dens_down < density)  diff_out += (density - dens_down) / DIFFUSION_RATE;
        if (!is_solid_for_gas(n_mat_left)  && dens_left < density)  diff_out += (density - dens_left) / DIFFUSION_RATE;
        if (!is_solid_for_gas(n_mat_right) && dens_right < density) diff_out += (density - dens_right) / DIFFUSION_RATE;
    }

    int diff_in = 0;
    if (n_mat_up == MAT_GAS    && get_density(n_up) > density    && !is_solid_for_gas(material))    diff_in += (get_density(n_up) - density) / DIFFUSION_RATE;
    if (n_mat_down == MAT_GAS  && get_density(n_down) > density  && !is_solid_for_gas(material))  diff_in += (get_density(n_down) - density) / DIFFUSION_RATE;
    if (n_mat_left == MAT_GAS  && get_density(n_left) > density  && !is_solid_for_gas(material))  diff_in += (get_density(n_left) - density) / DIFFUSION_RATE;
    if (n_mat_right == MAT_GAS && get_density(n_right) > density && !is_solid_for_gas(material)) diff_in += (get_density(n_right) - density) / DIFFUSION_RATE;

    // --- New density ---
    int new_density = density - total_out + total_in - diff_out + diff_in;
    new_density = clamp(new_density, 0, 255);

    // --- New velocity: density-weighted average, then 1/16 damping ---
    int stayed = max(0, density - total_out);
    int weight = max(1, stayed + total_in);

    ivec2 vsum = vel * stayed
               + vin_up    * in_up
               + vin_down  * in_down
               + vin_left  * in_left
               + vin_right * in_right;

    ivec2 new_vel = vsum / weight;
    int new_vel_mag = max(abs(new_vel.x), abs(new_vel.y));
    if (new_vel_mag > 1) {
        new_vel = (new_vel * 15) / 16;
    }
    new_vel = clamp(new_vel, ivec2(-8), ivec2(7));

    // --- Material transitions ---
    if (material == MAT_AIR) {
        int air_total_in = total_in + diff_in;
        if (air_total_in >= THRESHOLD_BECOME_GAS) {
            int w = max(1, total_in + diff_in);
            ivec2 inflow_vel = (
                vin_up * in_up + vin_down * in_down +
                vin_left * in_left + vin_right * in_right
            );
            if (w > 0) inflow_vel /= w;
            inflow_vel = (inflow_vel * 15) / 16;
            inflow_vel = clamp(inflow_vel, ivec2(-8), ivec2(7));
            imageStore(chunk_tex, pos, pack_gas(air_total_in, inflow_vel));
            return;
        }
        int health = get_health(pixel);
        int temperature = max(0, get_temperature(pixel) - HEAT_DISSIPATION);
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, health, temperature));
        return;
    }

    // material == MAT_GAS from here on.
    if (new_density < THRESHOLD_DISSIPATE) {
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, 0));
        return;
    }
    imageStore(chunk_tex, pos, pack_gas(new_density, new_vel));
}

void lava_advect_pull(
    ivec2 pos, vec4 pixel,
    vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
    int material = get_material(pixel);

    int n_mat_up    = get_material(n_up);
    int n_mat_down  = get_material(n_down);
    int n_mat_left  = get_material(n_left);
    int n_mat_right = get_material(n_right);

    bool any_lava_neighbor =
        n_mat_up == MAT_LAVA || n_mat_down == MAT_LAVA ||
        n_mat_left == MAT_LAVA || n_mat_right == MAT_LAVA;

    if (material == MAT_AIR && !any_lava_neighbor) {
        // Not relevant for lava - let gas_advect_pull handle pure-air cells
        return;
    }

    // --- Own state ---
    int density = (material == MAT_LAVA) ? get_density_lava(pixel) : 0;
    int temperature = (material == MAT_LAVA) ? get_temperature_lava(pixel) : 0;
    ivec2 vel = (material == MAT_LAVA) ? unpack_velocity_lava(pixel) : ivec2(0);

    int comp_up    = max(0, -vel.y);
    int comp_down  = max(0,  vel.y);
    int comp_left  = max(0, -vel.x);
    int comp_right = max(0,  vel.x);

    if (is_solid_for_lava(n_mat_up))    comp_up    = 0;
    if (is_solid_for_lava(n_mat_down))  comp_down  = 0;
    if (is_solid_for_lava(n_mat_left))  comp_left  = 0;
    if (is_solid_for_lava(n_mat_right)) comp_right = 0;

    int out_up    = stochastic_div(density * comp_up,    V_MAX_OUTFLOW, pos, 1u);
    int out_down  = stochastic_div(density * comp_down,  V_MAX_OUTFLOW, pos, 2u);
    int out_left  = stochastic_div(density * comp_left,  V_MAX_OUTFLOW, pos, 3u);
    int out_right = stochastic_div(density * comp_right, V_MAX_OUTFLOW, pos, 4u);

    int total_out = out_up + out_down + out_left + out_right;
    int max_outflow = min(density, max(1, density / 2));
    if (total_out > max_outflow) {
        out_up    = out_up    * max_outflow / max(1, total_out);
        out_down  = out_down  * max_outflow / max(1, total_out);
        out_left  = out_left  * max_outflow / max(1, total_out);
        out_right = out_right * max_outflow / max(1, total_out);
        total_out = out_up + out_down + out_left + out_right;
    }

    int in_up = 0, in_down = 0, in_left = 0, in_right = 0;
    ivec2 vin_up = ivec2(0), vin_down = ivec2(0), vin_left = ivec2(0), vin_right = ivec2(0);

    if (n_mat_up == MAT_LAVA) {
        int dN = get_density_lava(n_up);
        ivec2 vN = unpack_velocity_lava(n_up);
        in_up = stochastic_div(dN * max(0, vN.y), V_MAX_OUTFLOW, pos, 5u);
        vin_up = vN;
    }
    if (n_mat_down == MAT_LAVA) {
        int dN = get_density_lava(n_down);
        ivec2 vN = unpack_velocity_lava(n_down);
        in_down = stochastic_div(dN * max(0, -vN.y), V_MAX_OUTFLOW, pos, 6u);
        vin_down = vN;
    }
    if (n_mat_left == MAT_LAVA) {
        int dN = get_density_lava(n_left);
        ivec2 vN = unpack_velocity_lava(n_left);
        in_left = stochastic_div(dN * max(0, vN.x), V_MAX_OUTFLOW, pos, 7u);
        vin_left = vN;
    }
    if (n_mat_right == MAT_LAVA) {
        int dN = get_density_lava(n_right);
        ivec2 vN = unpack_velocity_lava(n_right);
        in_right = stochastic_div(dN * max(0, -vN.x), V_MAX_OUTFLOW, pos, 8u);
        vin_right = vN;
    }

    int total_in = in_up + in_down + in_left + in_right;

    // Wall reflection
    if (is_solid_for_lava(n_mat_up)    && vel.y < 0) vel.y = -vel.y;
    if (is_solid_for_lava(n_mat_down)  && vel.y > 0) vel.y = -vel.y;
    if (is_solid_for_lava(n_mat_left)  && vel.x < 0) vel.x = -vel.x;
    if (is_solid_for_lava(n_mat_right) && vel.x > 0) vel.x = -vel.x;

    // Lava has no diffusion

    int new_density = clamp(density - total_out + total_in, 0, 255);

    int stayed = max(0, density - total_out);
    int weight = max(1, stayed + total_in);
    ivec2 vsum = vel * stayed
               + vin_up * in_up + vin_down * in_down
               + vin_left * in_left + vin_right * in_right;
    ivec2 new_vel = vsum / weight;
    int new_vel_mag = max(abs(new_vel.x), abs(new_vel.y));
    if (new_vel_mag > 1) {
        new_vel = (new_vel * 15) / 16;
    }
    new_vel = clamp(new_vel, ivec2(-8), ivec2(7));

    // Weighted average temperature from inflows
    int temp_weight = stayed * temperature;
    if (n_mat_up == MAT_LAVA) temp_weight += get_temperature_lava(n_up) * in_up;
    if (n_mat_down == MAT_LAVA) temp_weight += get_temperature_lava(n_down) * in_down;
    if (n_mat_left == MAT_LAVA) temp_weight += get_temperature_lava(n_left) * in_left;
    if (n_mat_right == MAT_LAVA) temp_weight += get_temperature_lava(n_right) * in_right;
    int new_temp = temp_weight / max(1, stayed + total_in);

    if (material == MAT_AIR) {
        if (total_in >= THRESHOLD_BECOME_LAVA) {
            ivec2 inflow_vel = ivec2(0);
            if (total_in > 0) {
                inflow_vel = (vin_up * in_up + vin_down * in_down + vin_left * in_left + vin_right * in_right) / total_in;
                inflow_vel = (inflow_vel * 15) / 16;
                inflow_vel = clamp(inflow_vel, ivec2(-8), ivec2(7));
            }
            imageStore(chunk_tex, pos, pack_lava(total_in, new_temp, inflow_vel));
            return;
        }
        // Stay air - don't write, let gas_advect_pull handle it
        return;
    }

    // material == MAT_LAVA
    if (new_density < THRESHOLD_DISSIPATE) {
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, 0));
        return;
    }
    imageStore(chunk_tex, pos, pack_lava(new_density, new_temp, new_vel));
}

vec4 read_neighbor(ivec2 pos) {
	if (pos.x >= 0 && pos.x < CHUNK_SIZE && pos.y >= 0 && pos.y < CHUNK_SIZE) {
		return imageLoad(chunk_tex, pos);
	}
	if (pos.y < 0) {
		return imageLoad(neighbor_top, ivec2(pos.x, CHUNK_SIZE + pos.y));
	}
	if (pos.y >= CHUNK_SIZE) {
		return imageLoad(neighbor_bottom, ivec2(pos.x, pos.y - CHUNK_SIZE));
	}
	if (pos.x < 0) {
		return imageLoad(neighbor_left, ivec2(CHUNK_SIZE + pos.x, pos.y));
	}
	if (pos.x >= CHUNK_SIZE) {
		return imageLoad(neighbor_right, ivec2(pos.x - CHUNK_SIZE, pos.y));
	}
	return vec4(0.0);
}

bool is_burning(vec4 p) {
	int mat = get_material(p);
	return IS_FLAMMABLE[mat] && get_temperature(p) > IGNITION_TEMP[mat];
}

bool is_hot_lava(vec4 p, int target_material) {
	if (get_material(p) != MAT_LAVA) return false;
	int temp = get_temperature_lava(p);
	return temp > IGNITION_TEMP[target_material];
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (pos.x >= CHUNK_SIZE || pos.y >= CHUNK_SIZE) return;

	vec4 pixel = imageLoad(chunk_tex, pos);
	int material = get_material(pixel);

	// 1. Rigidbody AABB injection — returns if the cell was written.
	if (try_inject_rigidbody_velocity(pos, material, pixel)) return;

	// 2. Neighbor reads used by both gas and burning.
	vec4 n_up    = read_neighbor(pos + ivec2(0, -1));
	vec4 n_down  = read_neighbor(pos + ivec2(0,  1));
	vec4 n_left  = read_neighbor(pos + ivec2(-1, 0));
	vec4 n_right = read_neighbor(pos + ivec2( 1, 0));

	// 3. Lava path — runs before gas so air cells get lava first if applicable.
	if (material == MAT_LAVA || material == MAT_AIR) {
		lava_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
		// If this was a lava cell, we're done. If air, gas may still need to run.
		if (material == MAT_LAVA) return;
		// Re-read pixel in case lava_advect_pull converted this air cell to lava.
		pixel = imageLoad(chunk_tex, pos);
		material = get_material(pixel);
		if (material == MAT_LAVA) return;
	}

	// 4. Gas + air path — runs every frame, pull-based, no phase guard.
	if (material == MAT_GAS || material == MAT_AIR) {
		gas_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
		return;
	}

	// 5. Checkerboard burning logic for solids.
	if ((pos.x + pos.y) % 2 != pc.phase) return;

	int health = get_health(pixel);
	int temperature = get_temperature(pixel);

	// Accumulate random heat from each burning neighbor (with probability).
	int heat_gain = 0;
	uint base_rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed)));
	if (is_burning(n_up)) {
		int n_mat = get_material(n_up);
		int n_temp = get_temperature(n_up);
		float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 1u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
		}
	}
	if (is_burning(n_down)) {
		int n_mat = get_material(n_down);
		int n_temp = get_temperature(n_down);
		float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 2u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
		}
	}
	if (is_burning(n_left)) {
		int n_mat = get_material(n_left);
		int n_temp = get_temperature(n_left);
		float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 3u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 4 + int(rng % uint(HEAT_SPREAD));
		}
	}
	if (is_burning(n_right)) {
		int n_mat = get_material(n_right);
		int n_temp = get_temperature(n_right);
		float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 4u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
		}
	}

	// Heat from hot lava neighbors
	if (is_hot_lava(n_up, material)) {
		heat_gain += get_temperature_lava(n_up) / 4;
	}
	if (is_hot_lava(n_down, material)) {
		heat_gain += get_temperature_lava(n_down) / 4;
	}
	if (is_hot_lava(n_left, material)) {
		heat_gain += get_temperature_lava(n_left) / 4;
	}
	if (is_hot_lava(n_right, material)) {
		heat_gain += get_temperature_lava(n_right) / 4;
	}

	if (IS_FLAMMABLE[material]) {
		temperature = min(255, temperature + heat_gain);
		temperature = max(0, temperature - HEAT_DISSIPATION);
		if (temperature > IGNITION_TEMP[material]) {
			health = health - 1;
			temperature = FIRE_TEMP;
			if (health <= 0) {
				material = MAT_AIR;
				health = 0;
				temperature = 0;
			}
		}
	}

	imageStore(chunk_tex, pos, make_pixel(material, health, temperature));
}