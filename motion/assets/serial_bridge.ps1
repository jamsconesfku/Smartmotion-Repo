# SmartMotion Motion: USB helper.  Copies bytes from SmartMotion Motion (standard input) to the controller's COM port,
# and bytes from the COM port back (standard output).  Started by SmartMotion Motion; it stops when the program closes.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File serial_bridge.ps1 COM3 250000
param([string]$Port = "COM3", [int]$Baud = 250000)
Add-Type -ReferencedAssemblies System -TypeDefinition @"
using System;
using System.IO;
using System.IO.Ports;
using System.Threading;
using System.Runtime.InteropServices;
public static class SmartMotionBridge {
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint ms);
    public static int Run(string port, int baud) {
        timeBeginPeriod(1);
        SerialPort sp;
        try {
            sp = new SerialPort(port, baud, Parity.None, 8, StopBits.One);
            sp.DtrEnable = true;
            sp.RtsEnable = true;
            sp.WriteTimeout = 500;
            sp.Open();
        } catch (Exception e) {
            Console.Error.WriteLine("Could not open " + port + ": " + e.Message);
            return 2;
        }
        Stream o = Console.OpenStandardOutput();
        Thread reader = new Thread(delegate () {
            byte[] rx = new byte[4096];
            try {
                while (true) {
                    int m = sp.BaseStream.Read(rx, 0, rx.Length);
                    if (m > 0) { o.Write(rx, 0, m); o.Flush(); }
                }
            } catch (Exception) { }
        });
        reader.IsBackground = true;
        reader.Start();
        Stream i = Console.OpenStandardInput();
        byte[] buf = new byte[4096];
        try {
            while (true) {
                int n = i.Read(buf, 0, buf.Length);
                if (n <= 0) break;
                sp.BaseStream.Write(buf, 0, n);
            }
        } catch (Exception e) {
            Console.Error.WriteLine("Connection to " + port + " lost: " + e.Message);
        }
        try { sp.Close(); } catch (Exception) { }
        return 0;
    }
}
"@
exit [SmartMotionBridge]::Run($Port, $Baud)
