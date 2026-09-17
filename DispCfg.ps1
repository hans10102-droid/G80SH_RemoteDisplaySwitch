# DispCfg.ps1 - Windows CCD API (QueryDisplayConfig/SetDisplayConfig) 로 화면 구성 전환
# MultiMonitorTool 은 꺼진(신호 없음 대기) 모니터를 식별하지 못해 켜지 못함 (09-17 21:50) → CCD 로 직접 처리
if (-not ('Ccd2' -as [type])) {
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class Ccd2 {
    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] public struct SRC { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] public struct TGT { public LUID adapterId; public uint id; public uint modeInfoIdx; public int outputTechnology; public int rotation; public int scaling; public uint rrNum; public uint rrDen; public int scanLineOrdering; public int targetAvailable; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] public struct PATH { public SRC source; public TGT target; public uint flags; }
    [StructLayout(LayoutKind.Explicit, Size=64)] public struct MODE {
        [FieldOffset(0)] public int infoType; [FieldOffset(4)] public uint id; [FieldOffset(8)] public LUID adapterId;
        [FieldOffset(16)] public uint width; [FieldOffset(20)] public uint height; [FieldOffset(24)] public int pixelFormat;
        [FieldOffset(28)] public int posX; [FieldOffset(32)] public int posY; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct TARGET_NAME {
        public int type; public uint size; public LUID adapterId; public uint id;
        public uint flags; public int outputTechnology; public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string friendlyName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string devicePath; }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPath, out uint numMode);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint numPath, [Out] PATH[] paths, ref uint numMode, [Out] MODE[] modes, IntPtr topo);
    [DllImport("user32.dll")] static extern int SetDisplayConfig(uint numPath, [In] PATH[] paths, uint numMode, [In] MODE[] modes, uint flags);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TARGET_NAME req);

    const uint INVALID = 0xFFFFFFFF;
    const uint SDC_APPLY = 0x80, SDC_USE_SUPPLIED = 0x20, SDC_SAVE = 0x200, SDC_ALLOW_CHANGES = 0x400;

    static int Query(uint flags, out PATH[] paths, out MODE[] modes) {
        uint np, nm; paths = null; modes = null;
        int r = GetDisplayConfigBufferSizes(flags, out np, out nm); if (r != 0) return r;
        paths = new PATH[np]; modes = new MODE[nm];
        r = QueryDisplayConfig(flags, ref np, paths, ref nm, modes, IntPtr.Zero);
        Array.Resize(ref paths, (int)np); Array.Resize(ref modes, (int)nm); return r;
    }
    static string DevPath(LUID adapter, uint targetId) {
        var t = new TARGET_NAME(); t.type = 2; t.size = (uint)Marshal.SizeOf(typeof(TARGET_NAME));
        t.adapterId = adapter; t.id = targetId;
        if (DisplayConfigGetDeviceInfo(ref t) != 0) return "";
        return t.devicePath ?? "";
    }
    static bool Match(string devPath, string id) { return devPath.IndexOf("#" + id + "#", StringComparison.OrdinalIgnoreCase) >= 0; }

    // "SAM7B0C,SAM79DF|SAM7B0C" = 활성 목록|주 모니터
    public static string Active(string[] ids) {
        PATH[] p; MODE[] m;
        if (Query(2, out p, out m) != 0) return "|";
        var act = new List<string>(); string primary = "";
        foreach (var path in p) {
            string dev = DevPath(path.target.adapterId, path.target.id);
            foreach (var id in ids) if (Match(dev, id)) {
                act.Add(id);
                uint si = path.source.modeInfoIdx;
                if (si < m.Length && m[si].posX == 0 && m[si].posY == 0) primary = id;
            }
        }
        return string.Join(",", act) + "|" + primary;
    }

    // 모든 경로(QDC_ALL_PATHS)에서 원하는 모니터만 골라 켜고 나머지는 끈다. wanted[0] = 주 모니터(0,0)
    public static string Activate(string[] wanted, int[] xs, int[] ys) {
        PATH[] all; MODE[] am;
        int r = Query(1, out all, out am);
        if (r != 0) return "query-all=" + r;
        var chosen = new List<PATH>(); var usedSrc = new HashSet<string>(); var usedTgt = new HashSet<string>();
        var log = new List<string>();
        foreach (var id in wanted) {
            bool found = false;
            foreach (var path in all) {
                if (path.target.targetAvailable == 0) continue;
                string sk = path.source.adapterId.Low + ":" + path.source.id;
                string tk = path.target.adapterId.Low + ":" + path.target.id;
                if (usedSrc.Contains(sk) || usedTgt.Contains(tk)) continue;
                if (!Match(DevPath(path.target.adapterId, path.target.id), id)) continue;
                var q = path; q.flags = 1; q.source.modeInfoIdx = INVALID; q.target.modeInfoIdx = INVALID;
                chosen.Add(q); usedSrc.Add(sk); usedTgt.Add(tk); found = true;
                log.Add(id + ":t" + path.target.id + "/s" + path.source.id); break;
            }
            if (!found) log.Add(id + ":NOTFOUND");
        }
        if (chosen.Count == 0) return string.Join(" ", log);
        var arr = chosen.ToArray();
        r = SetDisplayConfig((uint)arr.Length, arr, 0, null, SDC_APPLY | SDC_USE_SUPPLIED | SDC_ALLOW_CHANGES | SDC_SAVE);
        log.Add("set=" + r);
        if (r != 0) return string.Join(" ", log);

        PATH[] p; MODE[] m;
        r = Query(2, out p, out m); if (r != 0) { log.Add("query-active=" + r); return string.Join(" ", log); }
        for (int i = 0; i < p.Length; i++) {
            string dev = DevPath(p[i].target.adapterId, p[i].target.id);
            for (int w = 0; w < wanted.Length; w++) if (Match(dev, wanted[w])) {
                uint si = p[i].source.modeInfoIdx;
                if (si < m.Length) { m[si].posX = (w == 0) ? 0 : xs[w]; m[si].posY = (w == 0) ? 0 : ys[w]; }
            }
        }
        r = SetDisplayConfig((uint)p.Length, p, (uint)m.Length, m, SDC_APPLY | SDC_USE_SUPPLIED | SDC_ALLOW_CHANGES | SDC_SAVE);
        log.Add("pos=" + r);
        return string.Join(" ", log);
    }
}
"@
}
