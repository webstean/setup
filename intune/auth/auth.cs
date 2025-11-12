#:package Microsoft.Identity.Client@4.79.0
#:package Microsoft.Identity.Client.Broker@4.79.0
#:package System.Windows.Forms@4.0.0

using Microsoft.Identity.Client;
using Microsoft.Identity.Client.Broker;
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
// using System.Windows.Forms;

// Import Windows API functions for handle management
[DllImport("kernel32.dll")]
static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
static extern IntPtr GetActiveWindow();

[DllImport("user32.dll")]
static extern IntPtr GetForegroundWindow();

// Get the current window handle - try multiple methods for robustness
static IntPtr GetCurrentWindowHandle()
{
    // First try to get the console window (for console apps)
    IntPtr consoleHandle = GetConsoleWindow();
    if (consoleHandle != IntPtr.Zero)
        return consoleHandle;
    
    // Try to get the active window
    IntPtr activeHandle = GetActiveWindow();
    if (activeHandle != IntPtr.Zero)
        return activeHandle;
    
    // Finally try the foreground window
    return GetForegroundWindow();
}

// Get the window handle for MSAL authentication
IntPtr windowHandle = GetCurrentWindowHandle();
//Console.WriteLine($"Using window handle: 0x{windowHandle:X}");

var app = PublicClientApplicationBuilder.Create("14d82eec-204b-4c2f-b7e8-296a70dab67e")
    .WithDefaultRedirectUri()
    .WithBroker(new BrokerOptions(BrokerOptions.OperatingSystems.Windows))     // <-- This tells MSAL to use WAM
    .Build();

var result = await app.AcquireTokenInteractive(
        new[] { "https://graph.microsoft.com/User.Read" })
    .WithParentActivityOrWindow(windowHandle)  // <-- Associate authentication with the current window
    .WithPrompt(Prompt.SelectAccount)          // <-- Optional: Show account selection UI
    .ExecuteAsync();

Console.WriteLine($"Access token: {result.AccessToken.Substring(0, 40)}...");
// Copy the access token to clipboard
// System.Windows.Forms.Clipboard.SetText(result.AccessToken);
Console.WriteLine("Access token copied to clipboard!");


