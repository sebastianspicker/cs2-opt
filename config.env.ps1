# ==============================================================================
#  config.env.ps1  —  Central Configuration · CS2 Optimization Suite
# ==============================================================================

$CFG_WorkDir        = "C:\CS2_OPTIMIZE"
$CFG_LogDir         = "$CFG_WorkDir\Logs"
$CFG_LogFile        = "$CFG_LogDir\optimize_current.log"
$CFG_StateFile      = "$CFG_WorkDir\state.json"
$CFG_ProgressFile   = "$CFG_WorkDir\progress.json"
$CFG_LogMaxFiles    = 5

# ── Device Class GUIDs ───────────────────────────────────────────────────────
$CFG_GUID_Display   = "{4d36e968-e325-11ce-bfc1-08002be10318}"   # Display adapters (GPU)
$CFG_GUID_Network   = "{4d36e972-e325-11ce-bfc1-08002be10318}"   # Network adapters (NIC)

# ── Tool directories removed — all optimizations are now native PowerShell ────

# ── Benchmark Maps ─────────────────────────────────────────────────────────────
$CFG_Benchmark_Dust2   = "https://steamcommunity.com/sharedfiles/filedetails/?id=3240880604"
$CFG_Benchmark_Inferno = "https://steamcommunity.com/sharedfiles/filedetails/?id=2932674700"
$CFG_Benchmark_Ancient = "https://steamcommunity.com/sharedfiles/filedetails/?id=3472126051"

# ── FPS Cap ────────────────────────────────────────────────────────────────────
$CFG_FpsCap_Percent = 0.09
$CFG_FpsCap_Min     = 60

# ── Shader Cache Paths ─────────────────────────────────────────────────────────
$CFG_ShaderCache_Paths = @(
    "$env:ProgramFiles(x86)\Steam\steamapps\shadercache\730",
    "$env:ProgramFiles\Steam\steamapps\shadercache\730",
    "D:\Steam\steamapps\shadercache\730",
    "E:\Steam\steamapps\shadercache\730",
    "F:\Steam\steamapps\shadercache\730"
)
$CFG_NV_ShaderCache = "$env:LOCALAPPDATA\NVIDIA\DXCache"
$CFG_NV_GLCache     = "$env:LOCALAPPDATA\NVIDIA\GLCache"
$CFG_DX_ShaderCache = "$env:LOCALAPPDATA\D3DSCache"

# ── Autostart ──────────────────────────────────────────────────────────────────
$CFG_Autostart_Remove = @(
    "OneDrive","Spotify","Discord","Teams","Skype",
    "AdobeUpdater","AdobeGCInvoker","CCleaner",
    "Dropbox","GoogleDriveFS","EpicGamesLauncher",
    "NVDisplay.Container","RTSS"
)

# ── Services to disable ───────────────────────────────────────────────────────
# Xbox services: background auth/sync/networking. XboxGipSvc controls Xbox
# wireless controllers — re-enable if using Xbox wireless peripherals.
$CFG_XboxServices = @("XblAuthManager", "XblGameSave", "XboxNetApiSvc", "XboxGipSvc")

# ── NIC Tweaks ─────────────────────────────────────────────────────────────────
# InterruptModeration: "Medium" not "Disabled".
#   djdallmann empirical test (Intel Gigabit CT): Medium produced the lowest DPC latency
#   variance. "Disabled" means every arriving packet fires an interrupt — under background
#   network traffic this creates an interrupt storm that increases DPC jitter rather than
#   reducing it. Medium coalesces packets within a short window (~50-100µs) which is
#   imperceptible for CS2's 128 tick rate but prevents burst-mode interrupt flooding.
#   Predictable DPC scheduling > theoretically lower single-packet latency.
$CFG_NIC_Tweaks = @{
    "EEE"                 = "Disabled"
    "FlowControl"         = "Disabled"
    "InterruptModeration" = "Medium"
    "ReceiveBuffers"      = "512"
    "TransmitBuffers"     = "512"
}

# ── Timer Resolution ─────────────────────────────────────────────────────────
$CFG_TimerResolution_Desired = 5000        # 0.5ms in 100ns units

# ── DNS Servers ──────────────────────────────────────────────────────────────
$CFG_DNS_Cloudflare = @("1.1.1.1", "1.0.0.1")
$CFG_DNS_Google     = @("8.8.8.8", "8.8.4.4")

# ── CS2 Autoexec Defaults ────────────────────────────────────────────────────
# Notes:
#   rate 1000000      — actual CS2 max; 786432 shows "Extremely restricted" in UI (display bug).
#   cl_net_buffer_ticks 0 — authoritative interp control in CS2; cl_interp_ratio/cl_interp are
#     belt-and-suspenders. engine_low_latency_sleep_after_client_tick 1 REQUIRES fps_max cap:
#     without a cap, sleep target = 0 (no-op). fps_max 0 = uncapped default; for minimum
#     latency pair with fps_max [refresh+20%] + NVIDIA Low Latency Mode On.
#   net_client_steamdatagram_enable_override 1 — forces Valve SDR routing (helps most regions).
#     Set to 0 here if your direct connection is already clean/low-latency.
#   speaker_config 1 — Headphones mode, REQUIRED for HRTF (Advanced 3D Audio) to work correctly.
#     Stereo/Surround+HRTF routes through a matrix decoder first, degrading spatial accuracy.
#   snd_headphone_eq 0 — Natural (unprocessed). 2026 pro study (esportfire.com, 30+ players):
#     62.5% Natural, 37.5% Crisp. Crisp (1) boosts 2-4kHz highs for footstep clarity but
#     causes ear fatigue over long sessions. Change to 1 to prefer Crisp.
#   snd_use_hrtf 1 — explicitly enables Steam Audio HRTF. speaker_config 1 is a prerequisite
#     (headphone layout required) but does not activate HRTF by itself. All other spatial CVars
#     (snd_spatialize_lerp 0, perspective_correction 1) are tuned for HRTF-on; without this
#     line those settings are misconfigured. Change to 0 if using external head-tracking or
#     surround sound DSP (adjust speaker_config and snd_spatialize_lerp accordingly).
#   snd_spatialize_lerp 0 — no additional L/R isolation. With HRTF enabled (snd_use_hrtf 1),
#     Steam Audio already provides directional cues; adding isolation creates redundant hard panning.
#     2026 pro data: 62.5% use 0 (physically accurate with HRTF). Change to 0.5 for harder
#     left/right separation without HRTF.
#   snd_mixahead 0.05 — 50ms audio lookahead. Competitive standard. 0.001 risks audible
#     dropouts from CPU scheduling jitter on anything below top-end hardware.
#   mm_dedicated_search_maxping 80 — tune by region: EU → 40, SEA → 80-150.
#   r_fullscreen_gamma 2.2 — exclusive fullscreen only (no-op in fullscreen windowed).
#     Competitive players use 1.6-1.8 to brighten dark corners. 2.2 = system default.
#   r_player_visibility_mode 1 — Boost Player Contrast. ThourCS2 confirmed: zero FPS cost,
#     measurable enemy model visibility improvement. Was broken in 2023, fixed since 2024.
#   m_rawinput 1 — reads directly from HID device, bypasses Windows pointer acceleration.
#     Without this, CS2 reads the already-processed Windows cursor position; EnhancePointerPrecision
#     would apply even if Step 29 disabled it in registry (a user re-enabling it in Win settings
#     would silently affect CS2 again). m_rawinput is the correct layer to enforce this.
#     m_mouseaccel1/2/customaccel 0 — disable all CS2-side acceleration on top of raw input.
$CFG_CS2_Autoexec = @{
    # ── Network / Interpolation ────────────────────────────────────────────
    # NOTE: cl_interp_ratio, cl_interp, cl_updaterate are deprecated in CS2 Source 2.
    # The subtick system handles interpolation differently; cl_net_buffer_ticks is the
    # actual control. These are kept as belt-and-suspenders (harmless no-ops).
    "cl_interp_ratio"                              = "1"
    "cl_interp"                                    = "0"
    "cl_updaterate"                                = "128"
    "rate"                                         = "1000000"
    "cl_net_buffer_ticks"                          = "0"
    "cl_net_buffer_ticks_use_interp"               = "1"
    "cl_tickpacket_desired_queuelength"            = "0"
    "mm_dedicated_search_maxping"                  = "80"
    "mm_session_search_qos_timeout"                = "20"
    "cl_timeout"                                   = "30"
    "net_client_steamdatagram_enable_override"     = "1"
    # ── Engine / FPS ──────────────────────────────────────────────────────
    "engine_low_latency_sleep_after_client_tick"   = "1"
    "engine_no_focus_sleep"                        = "0"
    "fps_max"                                      = "0"
    "fps_max_ui"                                   = "200"
    "fps_max_tools"                                = "144"
    # ── Gameplay ──────────────────────────────────────────────────────────
    "cl_predict_body_shot_fx"                      = "0"     # OFF — 95% pro consensus (ThourCS2 120-player study)
    "cl_predict_head_shot_fx"                      = "0"     # OFF — phantom dinks cause fatal target-switching errors
    "cl_predict_kill_ragdolls"                     = "0"
    "cl_disable_ragdolls"                          = "1"     # No corpse physics (CPU savings + visual clarity)
    "cl_sniper_delay_unscope"                      = "0"
    "cl_sniper_show_inaccuracy"                    = "0"     # Oct 2025 — disable scope bloom indicator
    "cl_crosshair_sniper_show_normal_inaccuracy"   = "0"     # Crisp scope crosshair (no standing inaccuracy blur)
    "r_drawtracers_firstperson"                    = "0"
    "gameinstructor_enable"                        = "0"
    "con_enable"                                   = "1"
    "option_duck_method"                           = "0"
    "option_speed_method"                          = "0"
    "lobby_default_privacy_bits2"                  = "0"
    "cl_autowepswitch"                             = "0"
    "cl_silencer_mode"                             = "0"     # Prevent accidental silencer detach
    "cl_dm_buyrandomweapons"                       = "0"     # Pick own weapon in DM
    "cl_join_advertise"                            = "2"     # Friends can see/join your server
    # ── HUD / QoL ────────────────────────────────────────────────────────
    "cl_compass_enabled"                           = "0"     # Hide compass (radar sufficient)
    "cl_show_clan_in_death_notice"                 = "0"     # Cleaner kill feed
    "cl_weapon_selection_rarity_color"             = "0"     # No skin rarity glow on weapon icons
    "cl_use_opens_buy_menu"                        = "0"     # Prevent E key opening buy menu
    "cl_buywheel_nonumberpurchasing"               = "1"     # Number keys won't buy in buy zone
    "cl_spec_show_bindings"                        = "0"     # Hide spectator control hints
    "viewmodel_recoil"                             = "0"     # No weapon kick animation during spray
    # ── Privacy / Anti-distraction ───────────────────────────────────────
    "cl_invites_only_mainmenu"                     = "1"     # Block invite popups during matches
    "cl_invites_only_friends"                      = "1"     # Only accept invites from friends
    "cl_embedded_stream_audio_volume"              = "0"     # Mute embedded Twitch/event audio
    "tv_nochat"                                    = "1"     # Mute GOTV spectator chat
    "snd_mute_mvp_music_live_players"              = "1"     # Mute MVP music while players alive
    # ── HUD / Telemetry (CS2-native; replaces removed net_graph) ──────────
    "cl_hud_telemetry_frametime_show"              = "0"
    "cl_hud_telemetry_ping_show"                   = "0"
    "cl_hud_telemetry_net_misdelivery_show"        = "0"
    "cl_hud_telemetry_net_quality_graph_show"      = "0"
    "cl_hud_telemetry_serverrecvmargin_graph_show" = "0"
    # ── Audio — Spatial / System ───────────────────────────────────────────
    "speaker_config"                               = "1"
    "snd_use_hrtf"                                 = "1"
    "snd_mixahead"                                 = "0.05"
    "snd_headphone_eq"                             = "0"
    "snd_spatialize_lerp"                          = "0"
    "snd_steamaudio_enable_perspective_correction" = "1"
    "voice_always_sample_mic"                      = "1"
    "snd_mute_losefocus"                           = "0"
    "snd_voipvolume"                               = "0.5"
    # ── Audio — Music muting (zero competitive downside) ──────────────────
    "snd_menumusic_volume"                         = "0"
    "snd_roundstart_volume"                        = "0"
    "snd_roundend_volume"                          = "0"
    "snd_roundaction_volume"                       = "0"
    "snd_mvp_volume"                               = "0"
    "snd_mapobjective_volume"                      = "0"
    "snd_tensecondwarning_volume"                  = "0.1"
    "snd_deathcamera_volume"                       = "0"
    # ── Mouse — raw input (bypass Windows pointer processing) ─────────────
    # NOTE: m_rawinput is a no-op in CS2 — raw input is always forced on and cannot be disabled.
    # Kept as belt-and-suspenders for documentation clarity and forward-compatibility.
    # m_mouseaccel1/2: disable CS2-engine acceleration thresholds (belt-and-suspenders with Step 29).
    # m_customaccel: disable any custom acceleration curve.
    "m_rawinput"                                   = "1"
    "m_mouseaccel1"                                = "0"
    "m_mouseaccel2"                                = "0"
    "m_customaccel"                                = "0"
    # ── Video — autoexec-settable (remainder is video.txt / in-game menu) ─
    "r_player_visibility_mode"                     = "1"
    "r_fullscreen_gamma"                           = "2.2"
    "mat_monitorgamma_tv_enabled"                  = "0"
}

# ── Chipset Driver URLs ──────────────────────────────────────────────────────
$CFG_URL_AMD_Chipset   = "https://www.amd.com/en/support/download/drivers.html"
$CFG_URL_Intel_Chipset = "https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html"
# Process Lasso — kept as alternative reference (native IFEO replaces it in Step 10)
$CFG_URL_ProcessLasso  = "https://bitsum.com/processlasso/"

# ── Estimated Improvement Ranges ────────────────────────────────────────
# P1LowMin/P1LowMax = estimated % improvement in 1% lows (main metric)
# AvgMin/AvgMax      = estimated % improvement in avg FPS
# Confidence = how well-measured the estimate is (HIGH, MEDIUM, LOW)
# These are used to compare estimates vs. actual benchmark results.
$CFG_ImprovementEstimates = @{
    "Clear Shader Cache"         = @{ P1LowMin=0;  P1LowMax=5;  AvgMin=0; AvgMax=1;  Confidence="HIGH";   Note="Only if stale shaders exist" }
    "Fullscreen Optimizations"   = @{ P1LowMin=1;  P1LowMax=5;  AvgMin=0; AvgMax=2;  Confidence="HIGH";   Note="FSE prevents DWM compositing overhead" }
    "CS2 Optimized Power Plan"   = @{ P1LowMin=2;  P1LowMax=8;  AvgMin=1; AvgMax=5;  Confidence="HIGH";   Note="Native tiered plan: T1 safe, T2 RECOMMENDED+, T3 COMPETITIVE+ (CPU vendor-aware)" }
    "Game DVR / Game Bar Off"    = @{ P1LowMin=0;  P1LowMax=3;  AvgMin=0; AvgMax=2;  Confidence="MEDIUM"; Note="Background recording can steal GPU time" }
    "Mouse Acceleration Off"     = @{ P1LowMin=0;  P1LowMax=0;  AvgMin=0; AvgMax=0;  Confidence="HIGH";   Note="Input consistency, not FPS" }
    "Disable Overlays"           = @{ P1LowMin=0;  P1LowMax=3;  AvgMin=0; AvgMax=2;  Confidence="MEDIUM"; Note="Overlay rendering overhead" }
    "FPS Cap"                    = @{ P1LowMin=5;  P1LowMax=20; AvgMin=-9;AvgMax=-9; Confidence="HIGH";   Note="Stabilizes frametimes. Avg drops by cap." }
    "Timer Resolution"           = @{ P1LowMin=0;  P1LowMax=2;  AvgMin=0; AvgMax=0;  Confidence="MEDIUM"; Note="More precise system timer" }
    "HAGS Toggle"                = @{ P1LowMin=-3; P1LowMax=5;  AvgMin=-2;AvgMax=3;  Confidence="LOW";    Note="Setup-dependent, benchmark both" }
    "NIC Tweaks"                 = @{ P1LowMin=0;  P1LowMax=3;  AvgMin=0; AvgMax=0;  Confidence="LOW";    Note="Only if LatencyMon shows NIC DPC" }
    "MSI Interrupts"             = @{ P1LowMin=0;  P1LowMax=5;  AvgMin=0; AvgMax=1;  Confidence="MEDIUM"; Note="Reduces DPC latency" }
    "Clean Driver Install"       = @{ P1LowMin=2;  P1LowMax=10; AvgMin=0; AvgMax=5;  Confidence="HIGH";   Note="Bloat-free driver" }
    "Autoexec CVars"             = @{ P1LowMin=0;  P1LowMax=2;  AvgMin=0; AvgMax=0;  Confidence="MEDIUM"; Note="56 CVars: network, engine latency sleep, mouse raw input, audio spatial+HRTF, music mute, video, gameplay" }
    "Defender Exclusions"        = @{ P1LowMin=0;  P1LowMax=3;  AvgMin=0; AvgMax=1;  Confidence="MEDIUM"; Note="Eliminates scan-time intercept on CS2 shader cache I/O" }
    "SysMain Disable"            = @{ P1LowMin=0;  P1LowMax=3;  AvgMin=0; AvgMax=1;  Confidence="LOW";    Note="Only on HDD or low RAM" }
    "Debloat"                    = @{ P1LowMin=0;  P1LowMax=2;  AvgMin=0; AvgMax=1;  Confidence="LOW";    Note="Fewer background processes" }
    "Visual Effects"             = @{ P1LowMin=0;  P1LowMax=1;  AvgMin=0; AvgMax=1;  Confidence="LOW";    Note="DWM overhead reduction" }
    # NetworkThrottlingIndex is intentionally NOT set by the suite.
    # djdallmann xperf analysis found 0xFFFFFFFF increases NDIS.sys DPC latency vs. default (10).
    # "NetworkThrottlingIndex"   = @{ ... } — deliberately omitted; default value 10 is correct.
    "Win32PrioritySeparation"    = @{ P1LowMin=1;  P1LowMax=4;  AvgMin=0; AvgMax=1;  Confidence="HIGH";   Note="0x2A: fixed quantum, max foreground boost — 2025 Blur Busters + Overclock.net showed better 1% lows vs 0x26 variable" }
    "HiberbootEnabled=0"         = @{ P1LowMin=0;  P1LowMax=0;  AvgMin=0; AvgMax=0;  Confidence="HIGH";   Note="Not FPS — enables MSI interrupt registry changes to persist across shutdown/restart" }
    "DisablePagingExecutive"     = @{ P1LowMin=0;  P1LowMax=1;  AvgMin=0; AvgMax=0;  Confidence="LOW";    Note="Keeps kernel in RAM — minimal on NVMe with 16+ GB" }
    "PowerThrottlingOff"         = @{ P1LowMin=1;  P1LowMax=5;  AvgMin=1; AvgMax=3;  Confidence="MEDIUM"; Note="Intel 12th gen+ only — prevents E-core mismatch frametime spikes" }
}

# ── NVIDIA Profile Estimated Improvement Ranges ─────────────────────────────
# Estimates for individual DRS setting clusters in nvidia-profile.ps1
# Applied as a group in Phase 3 Step 4 (T3, COMPETITIVE+ only)
# Source: NvApiDriverSettings.h enum decode + Orbmu2k/nvidiaProfileInspector
$CFG_NvidiaProfileEstimates = @{
    "NV — Power Management (Prefer Max)"    = @{ P1LowMin=3;  P1LowMax=8;  AvgMin=2; AvgMax=5;  Confidence="HIGH";   Note="GPU P-state locked to max; prevents clock dip during momentary load troughs" }
    "NV — Max Pre-rendered Frames = 1"      = @{ P1LowMin=2;  P1LowMax=5;  AvgMin=0; AvgMax=0;  Confidence="HIGH";   Note="Minimum render queue; improves 1% lows without changing avg. Marginal at <144 FPS" }
    "NV — Threaded Optimization (Force On)" = @{ P1LowMin=1;  P1LowMax=3;  AvgMin=1; AvgMax=3;  Confidence="MEDIUM"; Note="Force On (default: Auto). Offloads API calls to CPU threads parallel to GPU" }
    "NV — Texture Filtering (High Perf)"   = @{ P1LowMin=1;  P1LowMax=3;  AvgMin=1; AvgMax=2;  Confidence="MEDIUM"; Note="Max driver-side quality reduction. Trades AF/trilinear quality for GPU bandwidth" }
    "NV — VSync Force Off"                  = @{ P1LowMin=0;  P1LowMax=0;  AvgMin=0; AvgMax=0;  Confidence="HIGH";   Note="Only adds FPS if VSync was previously on. CS2 default is off — redundant safety net" }
    "NV — Shader Cache 10 GB"               = @{ P1LowMin=1;  P1LowMax=5;  AvgMin=0; AvgMax=1;  Confidence="MEDIUM"; Note="Larger cache reduces recompilation stalls. Measurable only on first session per map. 2026 consensus: 10GB+" }
    "NV — All VRR/G-SYNC Disabled"         = @{ P1LowMin=0;  P1LowMax=2;  AvgMin=0; AvgMax=1;  Confidence="LOW";    Note="Eliminates VRR processing overhead. Only measurable on G-SYNC-capable hardware" }
    "NV — FXAA Off (double gate)"           = @{ P1LowMin=0;  P1LowMax=1;  AvgMin=0; AvgMax=1;  Confidence="MEDIUM"; Note="CS2 doesn't use FXAA but the gate blocks driver injection. Small safety margin" }
    "NV — Ansel Disabled"                   = @{ P1LowMin=0;  P1LowMax=0;  AvgMin=0; AvgMax=0;  Confidence="HIGH";   Note="Zero overhead. Screenshot tool off; no DPC or API cost when inactive" }
    "NV — Antialiasing App Controlled"      = @{ P1LowMin=0;  P1LowMax=1;  AvgMin=0; AvgMax=1;  Confidence="LOW";    Note="Prevents driver AA injection. CS2 controls MSAA natively" }
    "NV — FRL NVCPL Cap"                    = @{ P1LowMin=5;  P1LowMax=20; AvgMin=-9;AvgMax=-9; Confidence="HIGH";   Note="Value 500 = effectively unlimited. Replaced by fpsCap calculator when set" }
    "NV — Smooth Motion APIs = 1"           = @{ P1LowMin=-5; P1LowMax=0;  AvgMin=0; AvgMax=10; Confidence="LOW";    Note="CAUTION: frame interpolation adds latency. Net-negative for competitive play. ps1 does not apply" }
    "NV — Optimus Discrete GPU Forced"      = @{ P1LowMin=0;  P1LowMax=5;  AvgMin=0; AvgMax=3;  Confidence="LOW";    Note="Laptop only. Desktop = zero impact. Forces dGPU for rendering" }
    "NV — Raytracing Off (DXR + Vulkan)"    = @{ P1LowMin=0;  P1LowMax=2;  AvgMin=0; AvgMax=2;  Confidence="MEDIUM"; Note="CS2 doesn't enable RT by default but the DRS gate prevents any accidental activation" }
}
