#:package Microsoft.Identity.Client@4.79.0
#:package Microsoft.Identity.Client.Broker@4.79.0

using Microsoft.Identity.Client;
using Microsoft.Identity.Client.Broker;
using System.Runtime.InteropServices;

internal class Program
{
    private static async Task Main(string[] args)
    {
        // Import Windows API functions for handle management
        [DllImport("kernel32.dll")]
        static extern nint GetConsoleWindow();

        [DllImport("user32.dll")]
        static extern nint GetActiveWindow();

        [DllImport("user32.dll")]
        static extern nint GetForegroundWindow();

        // Get the current window handle - try multiple methods for robustness
        static nint GetCurrentWindowHandle()
        {
            // First try to get the console window (for console apps)
            nint consoleHandle = GetConsoleWindow();
            if (consoleHandle != nint.Zero)
                return consoleHandle;

            // Try to get the active window
            nint activeHandle = GetActiveWindow();
            if (activeHandle != nint.Zero)
                return activeHandle;

            // Finally try the foreground window
            return GetForegroundWindow();
        }

        // Get the window handle for MSAL authentication
        nint windowHandle = GetCurrentWindowHandle();

        // var application_id = "14d82eec-204b-4c2f-b7e8-296a70dab67e"; // MS Graph Command Line
        // var application_id = "2233b157-f44d-4812-b777-036cdaf9a96e"; // Cloud Shell
        var application_id = "263a42c4-78c3-4407-8200-3387c284c303"; // DTP PnP

        // Create a PublicClientApplication with WAM broker enabled
        var app = PublicClientApplicationBuilder.Create(application_id)
            .WithDefaultRedirectUri()
            .WithBroker(new BrokerOptions(BrokerOptions.OperatingSystems.Windows)) // <-- This tells MSAL to use WAM
            .Build();

        var result = await app.AcquireTokenInteractive(
                new[] { "https://graph.microsoft.com/User.Read" })
            .WithParentActivityOrWindow(windowHandle)  // <-- Associate authentication with the current window
                                                       // .WithPrompt(Prompt.SelectAccount)          // <-- Optional: Show account selection UI
            .ExecuteAsync();

        Console.WriteLine($"Access token:");
        Console.WriteLine($"{result.AccessToken}");
    }
}