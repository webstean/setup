#:package Microsoft.Identity.Client@9.3.0

using Microsoft.Identity.Client;
using System;
using System.Threading.Tasks;

class Program
{
    static async Task Main()
    {
        var app = PublicClientApplicationBuilder
            .Create("14d82eec-204b-4c2f-b7e8-296a70dab67e")
            .WithDefaultRedirectUri()
            .WithBroker()     // <-- This tells MSAL to use WAM
            .Build();

        var result = await app.AcquireTokenInteractive(
                new[] { "https://graph.microsoft.com/User.Read" })
            .ExecuteAsync();

        Console.WriteLine($"Access token: {result.AccessToken.Substring(0,40)}...");
    }
}

