# Video Settings, Autoexec, and Launch Options — Deep Dive

> Covers Phase 1 Step 34, Phase 3 Steps 4–6, and `docs/video.txt`.

CS2 has three distinct configuration systems that interact in non-obvious ways. Understanding what each system controls — and why they're separate — prevents confusion when settings from one system appear to be ignored by another.

---

## The Three Configuration Systems

### 1. `video.txt` — Graphics pipeline settings

Located at `<Steam>\userdata\<SteamID>\730\local\cfg\video.txt`.

This file is written by the CS2 engine when you change anything in the in-game Video settings menu. It stores settings that require GPU pipeline reconfiguration to change — display mode, resolution, MSAA sample count, shadow quality, texture filtering, HDR mode.

**What you cannot control here:** Anything that can be changed mid-session via console commands (mostly shader-level settings and HUD toggles).

**Important:** CS2 overwrites this file when you click "Apply" in the video settings menu. If you edit it manually, make sure CS2 is fully closed before editing, and don't click Apply in the menu afterward without updating your file.

### 2. `autoexec.cfg` — Console variable overrides

Located at `<Steam>\userdata\<SteamID>\730\local\cfg\autoexec.cfg`.

Executed by the engine via `+exec autoexec` in launch options. This is CS2's scripting layer — every setting here is a console variable that can be changed at runtime. The autoexec runs on every map load.

**What belongs here:** Anything that can be set via the console — network settings, input settings, audio settings, HUD settings, gameplay preferences. Resolution and display mode do not belong here (they live in `video.txt`).

### 3. Launch options — Engine initialization flags

Set in Steam → Library → CS2 → Properties → Launch Options.

These flags are processed by the engine before any config files load. Use them for things that cannot be changed after engine initialization — like disabling the intro video, enabling the developer console, or toggling NVIDIA Reflex.

---

## Video Settings — 2026 Competitive Meta

Based on: ThourCS2 benchmarks (driver 581.08), prosettings.net aggregation of 866 professional CS2 players, and Blur Busters forum testing.

### Display Mode: Fullscreen (Exclusive)

```
"setting.fullscreen"    "1"
"setting.nowindowborder" "0"
```

The fundamental choice in CS2: exclusive fullscreen vs. borderless windowed (which Windows presents as fullscreen optimization "on"). The difference is the Desktop Window Manager.

In **borderless windowed mode**, your game frames pass through DWM (Desktop Window Manager) before being presented to the display. DWM composites the game frame together with your taskbar, notification overlays, and Alt-Tab thumbnails. This compositing adds 1–3ms latency and prevents the GPU from maintaining exclusive access to the display's frame buffer.

In **exclusive fullscreen**, the game bypasses DWM entirely. The GPU writes directly to the display's front buffer. No compositing overhead, no DWM latency.

**Phase 1 Step 4** (`DisableFullscreenOptimizations`) reinforces this. Windows 10/11 introduced "fullscreen optimizations" that silently convert exclusive fullscreen requests into borderless windowed mode under certain conditions (when overlays are detected, when certain window event hooks are registered). The Step 4 registry change tells Windows to respect the game's exclusive fullscreen request and not convert it.

**Step 26** (`GameConfigStore FSE`) adds a second registry entry that configures the fullscreen exclusive state from the GameConfigStore side, belt-and-suspenders with Step 4.

### MSAA — 4x is Better Than None

```
"setting.msaa_samples"  "4"  // HIGH and MID tiers
"setting.msaa_samples"  "0"  // LOW tier (use CMAA2 instead)
"setting.r_csgo_cmaa_enable" "0"  // HIGH and MID (MSAA handles AA)
"setting.r_csgo_cmaa_enable" "1"  // LOW tier only
```

Counter-intuitive finding from ThourCS2: **4x MSAA produces better 1% lows than no AA** on many systems.

The explanation: without anti-aliasing, the rasterizer must render more complex geometry per-pixel at edges (sub-pixel accuracy issues cause more branching in edge shaders). MSAA stabilizes this by resolving coverage at 4 samples per pixel — the rasterization pipeline becomes more predictable, reducing per-frame GPU work variance. The result is more consistent frametimes.

**8x MSAA** costs ~18% additional average FPS without meaningful visual improvement over 4x. Not recommended for competitive.

**CMAA2** (Conservative Morphological Anti-Aliasing 2, Intel's algorithm) is CS2's "free" AA option: post-process edge smoothing with near-zero GPU cost. On LOW tier (where MSAA is disabled for FPS budget reasons), CMAA2 provides some visual quality improvement without FPS cost.

### Ambient Occlusion: Always Off

```
"setting.r_aoproxy_enable"  "0"
```

AO adds realistic contact shadowing where objects meet surfaces. In CS2 this costs 10–15% GPU time (ThourCS2 measurement). The visual improvement is entirely cosmetic — AO on floors and walls provides no competitive information. Turn it off.

### Shadows: On, Medium Quality

```
"setting.csm_enabled"               "1"   // Dynamic shadows from map lights
"setting.shadow_quality_very_high"  "0"   // NOT high quality
```

The one setting where "lower = better" is incorrect for competitive play:

**Why shadows matter competitively:** Player shadows cast through doorways and onto floor surfaces reveal enemy positions before the player model becomes visible. A player peeking through a doorway with a light source behind them casts their shadow first. **Disabling shadows removes this information.**

**Why not High quality:** High shadow quality enables cascaded shadow maps with higher sample counts — visually prettier, but Shadow Quality = Medium already enables player shadows without the full cascade. Medium is the sweet spot.

**Why LOW tier doesn't use Low:** Even on LOW tier, player shadows are enabled. Removing them is a competitive disadvantage that outweighs the minor FPS gain.

### Texture Filtering: Always 16x Anisotropic

```
"setting.r_texturefilteringquality"  "5"  // 16x AF (HIGH and MID)
"setting.r_texturefilteringquality"  "0"  // Bilinear (LOW only, extreme FPS budget)
```

Since NVIDIA Pascal (2016) and AMD GCN 3rd gen (2015), the hardware anisotropic filtering unit runs essentially for free. The GPU has a dedicated AF unit that operates in parallel with the main rendering pipeline — it does not consume shader execution units. The FPS difference between 16x AF and bilinear is less than 1% on any GPU from the last decade.

What 16x AF does: sharpens textures viewed at oblique angles (floors, walls, the ground between cover). Without AF, floors and walls become blurry at shallow viewing angles — blurry surfaces where enemies might be hiding.

### HDR: Performance for All Tiers

```
"setting.sc_hdr_enabled_override"  "3"  // Performance (all tiers)
```

CS2's HDR setting is a tone-mapping preference, not a resolution or sample count change. The FPS difference between Quality and Performance is less than 1%.

**Why Performance, not Quality?** ThourCS2 documented that HDR Quality mode causes overbright rendering in areas with direct light sources — sun coming through windows, map lamps, skyboxes. These overbright areas wash out contrast, making it harder to distinguish player models in lit areas. HDR Performance preserves the competitive lighting profile.

### FidelityFX Super Resolution: Always Off

```
"setting.r_csgo_fsr_upsample"  "0"
```

FSR in CS2 upscales from a lower internal resolution using temporal reconstruction. The reconstruction algorithm blurs thin geometry — enemy model edges at distance, crosshairs, thin cover objects. The blurring is most pronounced at movement, which is exactly when you're aiming at moving enemies.

If you need more FPS, lower the resolution explicitly rather than using FSR. Explicit lower resolution is predictable; FSR-induced blur is not.

### NVIDIA Reflex: See the Dedicated Section

```
"setting.r_low_latency"  "1"  // Enabled (default recommendation)
// Or: launch with -noreflex (community meta — contested)
```

See [The Reflex Controversy](../README.md#the-reflex-controversy). The suite presents both options and lets you choose. Benchmark both configurations on your system.

### Resolution: The Largest Single FPS Factor

Resolution has more FPS impact than all other video settings combined. The relationship is roughly quadratic — halving the linear resolution approximately quadruples the pixel throughput reduction.

| Resolution | Relative Pixels | Typical FPS vs. 1080p |
|------------|----------------|----------------------|
| 1920×1080 | 100% (baseline) | Baseline |
| 1280×960 (4:3) | 59% | +40–60% |
| 1024×768 (4:3) | 38% | +60–80% |
| 1280×1080 (stretched 4:3) | 66% | +30–50% |

**Why pros use 4:3 stretched:** Stretching a 4:3 resolution to a 16:9 display makes character models appear wider — their horizontal hit box (what the player perceives) is larger relative to their height. Hitting enemies is geometrically easier when the target is wider. 80% of professional CS2 players use stretched 4:3 (prosettings.net aggregation).

The tradeoff: reduced horizontal FOV (you see less of the scene on the sides). This is a skill-weighted tradeoff — players who prioritize aim over awareness prefer 4:3 stretched.

---

## Autoexec.cfg — 56 CVars by Category

The autoexec is generated and written by Step 34. Here's the rationale for each category.

### Network (11 CVars)

**`rate 1000000`** — Sets the maximum network bandwidth the client can use for receiving game state updates. The default is tuned for CS:GO's lower bandwidth requirements. CS2 servers can send denser updates than CS:GO — setting rate to 1000000 removes any artificial bandwidth cap.

**`cl_net_buffer_ticks 0`** and **`cl_tickpacket_queuelength 0`** — Reduce network-side buffering. CS2 has its own interpolation system; pre-buffering ticks adds unnecessary delay.

**`cl_interp_ratio 1`** and **`cl_updaterate 128`** — Standard settings since CS:GO. Interpolation ratio 1 with updaterate 128 gives minimal visual smoothing with maximum data freshness.

**`mm_dedicated_search_maxping 80`** — Maximum ping to matchmaking servers. 80ms works for most regions (EU players can lower to 40; SEA players may need 80–150). Value 40 used by some guides is too aggressive in low-server-density regions.

**`net_client_steamdatagram_enable_override 1`** — Routes game traffic through Valve's SDR (Steam Datagram Relay) backbone. SDR provides a more direct network path via Valve's own server infrastructure, bypassing congested ISP routes. For players with poor routing to CS2 game servers (visible as ping variance, not just absolute ping), SDR measurably improves packet delivery. For players on already-optimal routes, it's neutral.

### Engine / FPS (5 CVars)

**`engine_low_latency_sleep_after_client_tick 1`** — Tells the engine to sleep immediately after processing a client tick, rather than spinning the CPU. This allows the CPU to service other threads (audio, OS tasks) in the gap between ticks, reducing the chance of frametime spikes from CPU resource contention.

**`engine_no_focus_sleep 0`** — When CS2 is not the foreground window, it normally throttles to 60 FPS. Setting 0 disables this throttle entirely, so the game loop continues at full speed even when Alt-Tabbed. Useful if you switch tabs to look up callouts and want the game to keep running.

**`fps_max 0`** — Removes the in-game FPS cap. Your actual cap comes from the NVCP frame rate limiter, which provides lower latency and more consistent frametimes than the in-game limiter. Set this after NVCP cap is configured.

**`fps_max_ui 200`** and **`fps_max_tools 144`** — Cap the FPS in menus and tools/editor modes respectively. The main menu doesn't need 400+ FPS and it reduces GPU/power noise while navigating settings.

### Gameplay (11 CVars)

**`cl_predict_body_shot_fx 1`** and **`cl_predict_head_shot_fx 1`** — Show hit effects client-side (predicted) rather than waiting for server confirmation. Since CS2's sub-tick architecture may delay hit confirmation slightly, client-predicted effects provide visual feedback before the server packet arrives.

**`cl_predict_kill_ragdolls 0`** — Disables client-side ragdoll prediction. Ragdoll physics are CPU-intensive. Disabling predicted ragdolls means the ragdoll appears when the server confirms the kill rather than immediately, but eliminates mid-firefight CPU spikes from physics simulation.

**`cl_sniper_delay_unscope 0`** — Removes the delay before the AWP scope clears after firing. Faster visual feedback on bolt-action sniper mechanics. Standard competitive setting.

**`r_drawtracers_firstperson 0`** — Hides bullet tracers in first-person view. Tracers can briefly obscure the target model during rapid fire. Disabling them provides a cleaner view during spray-downs.

**`gameinstructor_enable 0`** — Disables the in-game instruction system (text tooltips, tutorial overlays). Pure overhead for experienced players.

**`lobby_default_privacy_bits2 0`** — Sets lobby privacy to Public (open to friends), preventing the lobby from being private by default.

**`cl_autowepswitch 0`** — Disables automatic weapon switch when picking up a new weapon. Standard competitive setting — picking up a weapon during a firefight should not interrupt your current action without explicit input.

**`option_duck_method 0`** and **`option_speed_method 0`** — Set crouch and walk to toggle mode rather than hold mode. Personal preference for most players.

### HUD Telemetry (5 CVars)

CS2 removed `net_graph` from CS:GO. The replacement is five separate CVars:

```
cl_hud_telemetry_frametime_show 0
cl_hud_telemetry_ping_show 0
cl_hud_telemetry_net_misdelivery_show 0
cl_hud_telemetry_net_quality_graph_show 0
cl_hud_telemetry_serverrecvmargin_graph_show 0
```

All set to 0 (hidden) in the autoexec. Show them individually if you're diagnosing specific issues.

### Audio Spatial + System (9 CVars)

**`speaker_config 1`** — Sets the speaker configuration to Headphones. This is a prerequisite for Steam Audio HRTF processing.

**`snd_use_hrtf 1`** — Explicitly enables HRTF (Head-Related Transfer Function) spatialization. `speaker_config 1` is necessary but not sufficient — you must also set `snd_use_hrtf 1` to activate HRTF. This is a common confusion point: setting `speaker_config 1` alone does not enable HRTF.

**What HRTF does:** HRTF processes stereo output through a model of human pinna (outer ear) and head acoustic filtering. The result is that sounds appear to come from specific 3D positions in space — above, behind, to the sides — rather than simply left/right panning. In CS2, this makes enemy footsteps and grenade pings significantly easier to locate.

**`snd_headphone_eq 0`** — Sets the EQ preset to "Natural" (0). A 2026 competitive audio study found that 62.5% of surveyed pro players preferred Natural EQ. The default "Front Speakers" (1) boosts frequencies that can mask directionality cues. Natural preserves the HRTF output without additional EQ coloring.

**`snd_spatialize_lerp 0`** — Controls interpolation smoothness for spatialized audio positions. Value 0 = immediate position update (no interpolation). This is the correct setting when using HRTF — interpolation would smooth out position changes that the HRTF is trying to render precisely.

**`snd_mixahead 0.05`** — Audio buffer size in seconds (50ms). Setting this too low (some guides suggest 0.001 or 0.01) causes audio dropouts when the system is under load. 0.05 (50ms) is the minimum that avoids dropouts under normal gaming conditions. The default is 0.1 (100ms) — 50ms is half the default latency with no dropout risk on modern hardware.

**`snd_mute_losefocus 0`** — Keeps audio playing when CS2 is not the foreground window. Useful for hearing game sounds while Alt-Tabbed to a reference image or map.

### Audio Music Muting (8 CVars)

All music categories are set to volume 0 — main menu, round start, round end, action music, MVP anthem, map objective music, death camera — except the 10-second warning which is kept at 0.1 (audible but not obnoxious). Music muting is universal in competitive play: music is overhead without competitive information value.

### Mouse (4 CVars)

**`m_rawinput 1`** — Bypass Windows pointer processing entirely. CS2 reads mouse data directly from the HID (Human Interface Device) driver layer, bypassing Windows' pointer acceleration, speed scaling, and any enhancement processing that runs in the input stack. This is the most important mouse setting for competitive consistency.

The difference from Step 29's Windows-level acceleration disable: `m_rawinput 1` bypasses the entire Windows pointer pipeline for in-game input, while Step 29 disables acceleration for the Windows cursor (menus, desktop). Both should be set.

**`m_mouseaccel1 0`**, **`m_mouseaccel2 0`**, **`m_customaccel 0`** — Belt-and-suspenders mouse acceleration disables within CS2's own input processing (separate from Windows-level settings).

### Video (3 CVars)

**`r_player_visibility_mode 1`** — Enables "Boost Player Contrast." Counter-intuitive: turning this on improves 1% lows. The shader applies a post-processing outline effect that makes player models stand out from backgrounds — and because it replaces more expensive ambient calculations with a predictable shader, frametime variance decreases. ThourCS2 confirmed this with CapFrameX before/after testing.

**`r_fullscreen_gamma 2.2`** — Standard gamma for most monitors (sRGB). If your monitor is calibrated to a different gamma, adjust this value.

**`mat_monitorgamma_tv_enabled 0`** — Disables TV gamma correction (which maps to ~2.2 but with black crush). On PC monitors, this should be 0.

---

## Launch Options

```
-novid -console +exec autoexec
```

**`-novid`** — Skips the Valve/CS2 intro video on launch. Saves 5–10 seconds per launch, eliminates a potential VSync-synchronized frame during intro playback.

**`-console`** — Enables the developer console at launch (same as `con_enable 1` in autoexec, but also enables the console before any config loads).

**`+exec autoexec`** — Executes your autoexec.cfg on game launch. This is how the 56 CVars above take effect.

### -noreflex (optional)

```
-novid -console -noreflex +exec autoexec
```

This disables NVIDIA Reflex entirely at the engine level. See [The Reflex Controversy](../README.md#the-reflex-controversy) for the full debate. The suite asks you to choose — it is not the default.

### What we deliberately excluded

**`-threads N`** — Valve explicitly warns against this. Source 2 manages its own thread pool. Manually specifying thread count can cause instability, crashes, or performance reduction. Removed from older versions of this guide.

**`-tickrate 128`** — CS2's sub-tick architecture means fixed tickrate parameters are silently ignored. The flag is parsed and discarded.

**`-nojoy`** — Removes joystick support. In CS2, the joystick subsystem is minimal. Any freed RAM is single-digit MB. No measurable impact.

**`-high`** — Sets process priority to High but resets to Normal on exit. IFEO PerfOptions (Step 10) is strictly superior: applied at kernel level at process creation, persistent across every launch.

**`-softparticlesdefaultoff`** — Source 1 launch option. Not parsed by CS2's Source 2 engine.

---

## The Intel Hybrid Thread Pool Exception

For Intel 12th gen+ CPUs (Alder Lake, Raptor Lake), the autoexec generator adds one additional CVar:

```
thread_pool_option 2
```

This tells CS2's Source 2 thread pool to use all logical processors, including E-cores. Without this, the engine may use a default thread pool configuration that's not optimal for hybrid architectures. Auto-detected by matching `Win32_Processor.Name` against `1[2-9]\d{3}[A-Z]` (12th-19th gen series).

---

## How to Verify Your Configuration

### Checking autoexec is loaded

Open the CS2 console and type:
```
m_rawinput
```
Should return `m_rawinput = 1`. If it returns 0, your autoexec isn't executing. Check that launch options contain `+exec autoexec` and that the file exists at the correct path.

### Checking HRTF is active

```
snd_use_hrtf
```
Should return `snd_use_hrtf = 1`. Also verify:
```
speaker_config
```
Should return `speaker_config = 1` (Headphones). HRTF will not activate on any other speaker config.

### Checking video.txt is being read

In the CS2 video settings menu, your settings should match what's in `video.txt`. If they don't, the file may not have been read — ensure CS2 was fully closed before the file was written.

To find your video.txt path:
```powershell
(Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name "SteamPath").SteamPath
# Then: <SteamPath>\userdata\<SteamID>\730\local\cfg\video.txt
```
