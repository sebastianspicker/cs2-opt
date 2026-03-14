# ==============================================================================
#  helpers/nvidia-drs.ps1  —  NVIDIA DRS (Driver Registry Store) via nvapi64.dll
# ==============================================================================
#
#  Low-level C# interop layer that calls nvapi64.dll directly from PowerShell.
#  Writes settings to the DRS binary database (nvdrs.dat) — the same mechanism
#  used by NVIDIA Profile Inspector and NVIDIA Control Panel.
#
#  Architecture:
#    nvapi64.dll exports only `nvapi_QueryInterface(uint id)` → returns
#    function pointers for all NVAPI functions.  We resolve 12 DRS functions,
#    wrap them in delegates, and expose typed static methods.
#
#  Struct marshaling uses byte[] + GCHandle.Alloc(Pinned) — no unsafe code.
#  All structs are zero-initialized and fields written via BitConverter.
#
#  Reference implementations:
#    - Orbmu2k/nvidiaProfileInspector  (canonical DRS wrapper)
#    - falahati/NvAPIWrapper           (NuGet-packaged NVAPI bindings)
#    - ppy/osu!                        (lightweight QueryInterface pattern)
#

$NvApiDrsCode = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class NvApiDrs
{
    // ── nvapi64.dll single export ──────────────────────────────────────────
    [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface",
               CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr NvAPI_QueryInterface(uint id);

    // ── NVAPI function IDs (from NVAPI headers / jNizM reference) ──────────
    private const uint ID_Initialize           = 0x0150E828;
    private const uint ID_DRS_CreateSession    = 0x0694D52E;
    private const uint ID_DRS_DestroySession   = 0xDAD9CFF8;
    private const uint ID_DRS_LoadSettings     = 0x375DBD6B;
    private const uint ID_DRS_SaveSettings     = 0xFCBC7E14;
    private const uint ID_DRS_FindProfileByName = 0x7E4A9A0B;
    private const uint ID_DRS_CreateProfile    = 0xCC176068;
    private const uint ID_DRS_DeleteProfile    = 0x17093206;
    private const uint ID_DRS_CreateApplication = 0x4347A9DE;
    private const uint ID_DRS_SetSetting       = 0x577DD202;
    private const uint ID_DRS_GetSetting       = 0x73BF8338;
    private const uint ID_DRS_FindAppByName    = 0xEEE566B2;

    // ── Delegate types (all NVAPI functions use __cdecl) ───────────────────
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_Initialize();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_CreateSession(out IntPtr session);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_DestroySession(IntPtr session);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_LoadSettings(IntPtr session);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_SaveSettings(IntPtr session);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_FindProfileByName(IntPtr session, IntPtr profileName, out IntPtr profile);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_CreateProfile(IntPtr session, IntPtr profileInfo, out IntPtr profile);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_DeleteProfile(IntPtr session, IntPtr profile);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_CreateApplication(IntPtr session, IntPtr profile, IntPtr application);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_SetSetting(IntPtr session, IntPtr profile, IntPtr setting);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_GetSetting(IntPtr session, IntPtr profile, uint settingId, IntPtr setting);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Del_FindAppByName(IntPtr session, IntPtr appName, out IntPtr profile, IntPtr application);

    // ── Cached delegates ───────────────────────────────────────────────────
    private static Del_Initialize       _initialize;
    private static Del_CreateSession    _createSession;
    private static Del_DestroySession   _destroySession;
    private static Del_LoadSettings     _loadSettings;
    private static Del_SaveSettings     _saveSettings;
    private static Del_FindProfileByName _findProfileByName;
    private static Del_CreateProfile    _createProfile;
    private static Del_DeleteProfile    _deleteProfile;
    private static Del_CreateApplication _createApplication;
    private static Del_SetSetting       _setSetting;
    private static Del_GetSetting       _getSetting;
    private static Del_FindAppByName    _findAppByName;
    private static bool _resolved = false;

    // ── Struct sizes ───────────────────────────────────────────────────────
    //
    //  NvAPI_UnicodeString = ushort[2048] = 4096 bytes
    //
    //  NVDRS_SETTING_V1 (12320 bytes):
    //    version(4) + settingName(4096) + settingId(4) + settingType(4) +
    //    settingLocation(4) + isCurrentPredefined(4) + isPredefinedValid(4) +
    //    predefinedValue_union(4100) + currentValue_union(4100)
    //
    //  NVDRS_PROFILE_V1 (4116 bytes):
    //    version(4) + profileName(4096) + gpuSupport(4) + isPredefined(4) +
    //    numOfApps(4) + numOfSettings(4)
    //
    //  NVDRS_APPLICATION_V1 (4104 bytes):
    //    version(4) + isPredefined(4) + appName(4096)
    //
    private const int UNICODE_STR_BYTES = 4096;

    private const int SETTING_SIZE = 12320;
    private const int PROFILE_SIZE = 4116;
    private const int APP_V1_SIZE  = 4104;

    // Version constants: sizeof(struct) | (version << 16)
    private const uint SETTING_VER1 = 0x00013020;   // 12320 | (1 << 16)
    private const uint PROFILE_VER1 = 0x00011014;   //  4116 | (1 << 16)
    private const uint APP_VER1     = 0x00011008;   //  4104 | (1 << 16)

    // ── Field offsets ──────────────────────────────────────────────────────
    // NVDRS_SETTING_V1
    private const int SET_OFF_VERSION        = 0;
    private const int SET_OFF_NAME           = 4;
    private const int SET_OFF_ID             = 4100;   // 4 + 4096
    private const int SET_OFF_TYPE           = 4104;
    private const int SET_OFF_LOCATION       = 4108;
    private const int SET_OFF_IS_PREDEFINED  = 4112;
    private const int SET_OFF_IS_PRED_VALID  = 4116;
    private const int SET_OFF_PRED_VALUE     = 4120;   // union start
    private const int SET_OFF_CURR_VALUE     = 8220;   // 4120 + 4100

    // NVDRS_PROFILE_V1
    private const int PRO_OFF_VERSION        = 0;
    private const int PRO_OFF_NAME           = 4;
    private const int PRO_OFF_GPU_SUPPORT    = 4100;

    // NVDRS_APPLICATION_V1
    private const int APP_OFF_VERSION        = 0;
    private const int APP_OFF_PREDEFINED     = 4;
    private const int APP_OFF_NAME           = 8;

    // ── NVAPI status codes ─────────────────────────────────────────────────
    public const int OK                          =    0;
    public const int ERROR                       =   -1;
    public const int SETTING_NOT_FOUND           = -174;
    public const int PROFILE_NOT_FOUND           = -175;
    public const int EXECUTABLE_ALREADY_IN_USE   = -179;

    // ── Internal helpers ───────────────────────────────────────────────────

    private static T GetDelegate<T>(uint id) where T : class
    {
        IntPtr ptr = NvAPI_QueryInterface(id);
        if (ptr == IntPtr.Zero)
            throw new Exception(string.Format(
                "NVAPI function 0x{0:X8} not found — driver too old?", id));
        return (T)(object)Marshal.GetDelegateForFunctionPointer(ptr, typeof(T));
    }

    private static void ResolveFunctions()
    {
        if (_resolved) return;
        _initialize       = GetDelegate<Del_Initialize>(ID_Initialize);
        _createSession    = GetDelegate<Del_CreateSession>(ID_DRS_CreateSession);
        _destroySession   = GetDelegate<Del_DestroySession>(ID_DRS_DestroySession);
        _loadSettings     = GetDelegate<Del_LoadSettings>(ID_DRS_LoadSettings);
        _saveSettings     = GetDelegate<Del_SaveSettings>(ID_DRS_SaveSettings);
        _findProfileByName = GetDelegate<Del_FindProfileByName>(ID_DRS_FindProfileByName);
        _createProfile    = GetDelegate<Del_CreateProfile>(ID_DRS_CreateProfile);
        _deleteProfile    = GetDelegate<Del_DeleteProfile>(ID_DRS_DeleteProfile);
        _createApplication = GetDelegate<Del_CreateApplication>(ID_DRS_CreateApplication);
        _setSetting       = GetDelegate<Del_SetSetting>(ID_DRS_SetSetting);
        _getSetting       = GetDelegate<Del_GetSetting>(ID_DRS_GetSetting);
        _findAppByName    = GetDelegate<Del_FindAppByName>(ID_DRS_FindAppByName);
        _resolved = true;
    }

    private static void CheckStatus(int status, string function)
    {
        if (status != 0)
            throw new Exception(string.Format(
                "NVAPI {0} failed: status {1} (0x{2})",
                function, status, (status < 0 ? ((uint)status).ToString("X8") : status.ToString("X"))));
    }

    private static void WriteUnicodeString(byte[] buffer, int offset, string text)
    {
        byte[] encoded = Encoding.Unicode.GetBytes(text);
        int len = Math.Min(encoded.Length, UNICODE_STR_BYTES - 2);
        Array.Copy(encoded, 0, buffer, offset, len);
        // Null terminator already present (buffer is zero-initialized)
    }

    // ── Public API ─────────────────────────────────────────────────────────

    /// <summary>Initialize NVAPI. Must be called once before any DRS operations.</summary>
    public static void Initialize()
    {
        ResolveFunctions();
        CheckStatus(_initialize(), "Initialize");
    }

    /// <summary>Create a DRS session handle.</summary>
    public static IntPtr CreateSession()
    {
        IntPtr session;
        CheckStatus(_createSession(out session), "DRS_CreateSession");
        return session;
    }

    /// <summary>Destroy a DRS session handle. Safe to call with IntPtr.Zero.</summary>
    public static void DestroySession(IntPtr session)
    {
        if (session != IntPtr.Zero)
            _destroySession(session);
    }

    /// <summary>Load DRS settings from nvdrs.dat into the session.</summary>
    public static void LoadSettings(IntPtr session)
    {
        CheckStatus(_loadSettings(session), "DRS_LoadSettings");
    }

    /// <summary>Save DRS settings from the session back to nvdrs.dat.</summary>
    public static void SaveSettings(IntPtr session)
    {
        CheckStatus(_saveSettings(session), "DRS_SaveSettings");
    }

    /// <summary>Find a DRS profile by name. Returns IntPtr.Zero if not found.</summary>
    public static IntPtr FindProfileByName(IntPtr session, string name)
    {
        byte[] nameBuffer = new byte[UNICODE_STR_BYTES];
        WriteUnicodeString(nameBuffer, 0, name);
        GCHandle handle = GCHandle.Alloc(nameBuffer, GCHandleType.Pinned);
        try
        {
            IntPtr profile;
            int status = _findProfileByName(session, handle.AddrOfPinnedObject(), out profile);
            return (status == 0) ? profile : IntPtr.Zero;
        }
        finally { handle.Free(); }
    }

    /// <summary>Create a new DRS profile. Returns the profile handle.</summary>
    public static IntPtr CreateProfile(IntPtr session, string name)
    {
        byte[] profile = new byte[PROFILE_SIZE];
        BitConverter.GetBytes(PROFILE_VER1).CopyTo(profile, PRO_OFF_VERSION);
        WriteUnicodeString(profile, PRO_OFF_NAME, name);
        BitConverter.GetBytes((uint)1).CopyTo(profile, PRO_OFF_GPU_SUPPORT); // GeForce bit

        GCHandle handle = GCHandle.Alloc(profile, GCHandleType.Pinned);
        try
        {
            IntPtr profileHandle;
            CheckStatus(
                _createProfile(session, handle.AddrOfPinnedObject(), out profileHandle),
                "DRS_CreateProfile");
            return profileHandle;
        }
        finally { handle.Free(); }
    }

    /// <summary>Delete a DRS profile.</summary>
    public static void DeleteProfile(IntPtr session, IntPtr profile)
    {
        CheckStatus(_deleteProfile(session, profile), "DRS_DeleteProfile");
    }

    /// <summary>
    /// Find which profile an executable is bound to.
    /// Returns IntPtr.Zero if the exe is not in any profile.
    /// </summary>
    public static IntPtr FindApplicationProfile(IntPtr session, string exeName)
    {
        byte[] nameBuffer = new byte[UNICODE_STR_BYTES];
        WriteUnicodeString(nameBuffer, 0, exeName);
        byte[] appBuffer = new byte[APP_V1_SIZE];
        BitConverter.GetBytes(APP_VER1).CopyTo(appBuffer, APP_OFF_VERSION);

        GCHandle nameHandle = GCHandle.Alloc(nameBuffer, GCHandleType.Pinned);
        GCHandle appHandle  = GCHandle.Alloc(appBuffer, GCHandleType.Pinned);
        try
        {
            IntPtr profile;
            int status = _findAppByName(
                session, nameHandle.AddrOfPinnedObject(),
                out profile, appHandle.AddrOfPinnedObject());
            return (status == 0) ? profile : IntPtr.Zero;
        }
        finally
        {
            nameHandle.Free();
            appHandle.Free();
        }
    }

    /// <summary>
    /// Bind an executable to a profile. Silently succeeds if already bound
    /// to this profile (-179 = EXECUTABLE_ALREADY_IN_USE is suppressed).
    /// </summary>
    public static void AddApplication(IntPtr session, IntPtr profile, string exeName)
    {
        byte[] app = new byte[APP_V1_SIZE];
        BitConverter.GetBytes(APP_VER1).CopyTo(app, APP_OFF_VERSION);
        WriteUnicodeString(app, APP_OFF_NAME, exeName);

        GCHandle handle = GCHandle.Alloc(app, GCHandleType.Pinned);
        try
        {
            int status = _createApplication(session, profile, handle.AddrOfPinnedObject());
            if (status != 0 && status != EXECUTABLE_ALREADY_IN_USE)
                CheckStatus(status, string.Format("DRS_CreateApplication({0})", exeName));
        }
        finally { handle.Free(); }
    }

    /// <summary>Write a single DWORD setting to a profile.</summary>
    public static void SetDwordSetting(IntPtr session, IntPtr profile, uint settingId, uint value)
    {
        byte[] setting = new byte[SETTING_SIZE];
        BitConverter.GetBytes(SETTING_VER1).CopyTo(setting, SET_OFF_VERSION);
        BitConverter.GetBytes(settingId).CopyTo(setting, SET_OFF_ID);
        BitConverter.GetBytes((uint)0).CopyTo(setting, SET_OFF_TYPE);        // 0 = DWORD
        BitConverter.GetBytes(value).CopyTo(setting, SET_OFF_CURR_VALUE);

        GCHandle handle = GCHandle.Alloc(setting, GCHandleType.Pinned);
        try
        {
            CheckStatus(
                _setSetting(session, profile, handle.AddrOfPinnedObject()),
                string.Format("DRS_SetSetting(0x{0:X8}={1})", settingId, value));
        }
        finally { handle.Free(); }
    }

    /// <summary>
    /// Read a DWORD setting from a profile.
    /// Returns NVAPI status (0 = OK, -174 = SETTING_NOT_FOUND).
    /// </summary>
    public static int GetDwordSetting(IntPtr session, IntPtr profile, uint settingId, out uint value)
    {
        value = 0;
        byte[] setting = new byte[SETTING_SIZE];
        BitConverter.GetBytes(SETTING_VER1).CopyTo(setting, SET_OFF_VERSION);

        GCHandle handle = GCHandle.Alloc(setting, GCHandleType.Pinned);
        try
        {
            int status = _getSetting(session, profile, settingId, handle.AddrOfPinnedObject());
            if (status == 0)
                value = BitConverter.ToUInt32(setting, SET_OFF_CURR_VALUE);
            return status;
        }
        finally { handle.Free(); }
    }
}
"@

# ── PowerShell wrapper functions ────────────────────────────────────────────

function Initialize-NvApiDrs {
    <#
    .SYNOPSIS  Compiles the NvApiDrs C# class and initializes nvapi64.dll.
    .DESCRIPTION
        Returns $true if DRS is available (NVIDIA driver installed, 64-bit PS).
        Returns $false on AMD/Intel GPUs, missing DLL, or compilation failure.
        Result is cached — safe to call multiple times.
    #>
    if ($SCRIPT:NvApiAvailable -eq $true) { return $true }
    $SCRIPT:NvApiAvailable = $false

    # Only attempt on 64-bit PowerShell (nvapi64.dll is 64-bit only)
    if ([IntPtr]::Size -ne 8) {
        Write-Debug "NvApiDrs: 32-bit PowerShell — nvapi64.dll requires 64-bit"
        return $false
    }

    try {
        # Compile C# class (only once per session)
        if (-not ([System.Management.Automation.PSTypeName]'NvApiDrs').Type) {
            Add-Type -TypeDefinition $NvApiDrsCode -ErrorAction Stop
        }

        # Initialize NVAPI runtime
        [NvApiDrs]::Initialize()
        $SCRIPT:NvApiAvailable = $true
        Write-Debug "NvApiDrs: initialized successfully"
    } catch {
        Write-Debug "NvApiDrs: init failed — $_"
        $SCRIPT:NvApiAvailable = $false
    }

    return $SCRIPT:NvApiAvailable
}

function Invoke-DrsSession {
    <#
    .SYNOPSIS  Executes a scriptblock within a DRS session with proper lifecycle management.
    .DESCRIPTION
        Creates session → loads settings → executes $Action → saves → destroys.
        The scriptblock receives $session as the first argument.
        Cleanup runs in finally{} to prevent leaked sessions.
    .PARAMETER Action
        Scriptblock to execute. Receives ($session) parameter.
    .PARAMETER NoSave
        If set, does not call SaveSettings after the action (read-only session).
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [switch]$NoSave
    )

    $session = [IntPtr]::Zero
    try {
        $session = [NvApiDrs]::CreateSession()
        [NvApiDrs]::LoadSettings($session)

        # Execute the caller's action
        & $Action $session

        if (-not $NoSave) {
            [NvApiDrs]::SaveSettings($session)
        }
    } finally {
        [NvApiDrs]::DestroySession($session)
    }
}
