# ollamaLauncher.bat

#### Launcher Main Menu
![Launcher Main Menu](Screenshots/launch.jpg)

#### Example: Pulling a Model
![Pulling a Model](Screenshots/pulling.jpg)

CLI tool for [Ollama](https://ollama.ai) on Windows.

## Features
- **Interactive Model Management**:
  - **List & Launch**: View installed models with details (Size, Params) and launch them instantly.
  - **Fetch & Download**: Browse the top 100+ models from the [Ollama Library](https://ollama.com/library) directly within the CLI.
  - **Remove Models**: Easily delete installed models to free up space.
- **Smart Caching**: Caches the online model list for 1 hour to speed up browsing.
- **Detailed Views**: Displays model size, parameter count, and descriptions in a clean table format.
- **Self-Contained**: A single `.bat` file that automatically manages its own helper scripts (embeds a PowerShell script for advanced parsing).
- **Auto-Setup**: Detects if Ollama is missing and offers to download the installer.

## Requirements
- **OS**: Windows (Only tested so far on Windows 10 & 11)
- **Dependencies**:
  - [Ollama](https://ollama.ai) (`ollamaLauncher.bat` will download & help you install it if missing)
  - PowerShell (Standard on Windows)
  - Internet connection (for fetching new models)

## Installation
1. Download `ollamaLauncher.bat` and `fetch_models.ps1` to any folder on your computer.
2. Double-click `ollamaLauncher.bat` to run.
*Note: On the first run, it will extract fetch_models.ps1 to `%APPDATA%\ollamaLauncher`.*
3. If Ollama is not installed CLI will download it using curl then the install file will need to be manually installed by the user.
4. Once Ollama is installed you can close the Ollama GUI chat and press any key in CLI to continue  or re-launch the script ollamaLauncher.bat

## Associated Files:
- ollamaLauncher.bat : Main launcher batch file script, run this to use the program.
- %APPDATA%\ollamaLauncher\fetch_models.ps1 : PowerShell script to fetch model list from Ollama.com, 
     - fetch_models.ps1 gets installed to %APPDATA%\ollamaLauncher\ on first run: 
         - if it is in same directory as ollamaLauncher.bat then copy to %APPDATA%\ollamaLauncher\, 
         - if the fetch_models.ps1 is missing in local folder then the .bat re-creates fetch_models.ps1 by Base64 encoding.
   - %TEMP%\ollama-models.txt : Cache file storing fetched model list

## Usage
### Main Menu
When you launch the script, you'll see your installed models:
```
Fetching available Ollama models...
Num  Model Name                Size       Params    Description
---- ------------------------- ---------- --------  -----------------------------------------------------
  1. llama3:latest             4.7 GB     8b        Installed
  2. mistral:latest            4.1 GB     7b        Installed
  3. neural-chat:latest        4.1 GB     7b        Installed

[0/U] Update/Pull a new Model    [R] Remove a model   [X] Exit

Enter the number or model name for the model you want to use (r to remove, or 0 / u to pull a new one):

### Browsing Online Models (Option 0)
Select `0` to browse the Ollama library. The list is paginated (50 per page).

Fetching latest top 100 models from Ollama.com...
Successfully fetched 100 models.

Using cached model list, enter [R] to re-pull and refresh.

Select a model to download from the Ollama library.

Showing Models (Page 1/2)

Num  Model Name                Size (GB)  Params    Description
---- ------------------------- ---------- --------  -----------------------------------------------------
  1. llama3:8b                 4.7 GB     8b        The most capable openly available LLM to date
  2. llama3:70b                40.0 GB    70b       The most capable openly available LLM to date
  3. mistral:7b                4.1 GB     7b        The 7B model released by Mistral AI, updated to v0.3
  4. gemma:2b                  1.7 GB     2b        Gemma is a family of lightweight, state-of-the-art...
  5. gemma:7b                  5.0 GB     7b        Gemma is a family of lightweight, state-of-the-art...
  ...
 48. starcoder2:3b             1.7 GB     3b        The next generation of transparently trained open ...
 49. starcoder2:7b             4.1 GB     7b        The next generation of transparently trained open ...
 50. starcoder2:15b            9.1 GB     15b       The next generation of transparently trained open ...

For descriptions and the full list, visit https://ollama.com/library

[N] Next Page  [R] Refresh List  [C] Cancel  [X] Exit
Enter model number or name to pull:
```

## Troubleshooting
- **"ollama command not found"**: The script will offer to download the installer for you.
- **"Failed to fetch models"**: Check your internet connection. The script tries to scrape `ollama.com/search`.
- **Cache Issues**: If the online list seems outdated, use the `[r/R]` option in the fetch menu to force a refresh.

## File Checksums (MD5)
- **fetch_models.ps1**: `8772B2896BBCD51E0B40181CF78DA811`
- **ollamaLauncher.bat**: `7F14A7A4BE3A0AF5704504D1A9807F45`

## Verifying the Base64 Encoded Script
The `ollamaLauncher.bat` file contains an embedded Base64-encoded version of `fetch_models.ps1` as a fallback. To verify the encoding matches the source file, you can decode and check it yourself:

### Option 1: Using PowerShell (Recommended)
```powershell
# Get the Base64 string from ollamaLauncher.bat and decode it
$b64String = "cGFyYW0oW2ludF0kU2tpcD0wLFtpbnRdJExpbWl0PTEwMCxbc3dpdGNoXSRBcHBlbmQsW3N0cmluZ10kQ2FjaGVGaWxlLFtzd2l0Y2hdJExvY2FsKQ0KJEVycm9yQWN0aW9uUHJlZmVyZW5jZT0nU3RvcCcNCltDb25zb2xlXTo6T3V0cHV0RW5jb2Rpbmc9W1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6VVRGOA0KIyBTZXQgZGVmYXVsdCBjYWNoZSBmaWxlIGlmIG5vdCBwcm92aWRlZA0KaWYgKC1ub3QgJENhY2hlRmlsZSkgew0KICAgICRDYWNoZUZpbGUgPSAiJGVudjpBUFBEQVRBXG9sbGFtYUxhdW5jaGVyXG1vZGVsc19jYWNoZS50eHQiDQp9DQojIEVuc3VyZSBjYWNoZSBkaXJlY3RvcnkgZXhpc3RzDQokQ2FjaGVEaXIgPSBTcGxpdC1QYXRoIC1QYXJlbnQgJENhY2hlRmlsZQ0KaWYgKC1ub3QgKFRlc3QtUGF0aCAkQ2FjaGVEaXIpKSB7DQogICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkQ2FjaGVEaXIgLUZvcmNlIHwgT3V0LU51bGwNCn0NCmlmICgkTG9jYWwpIHsNCiAgICAjIExvY2FsIG1vZGU6IExpc3QgaW5zdGFsbGVkIG1vZGVscw0KICAgIHRyeSB7DQogICAgICAgICRvdXRwdXQgPSBvbGxhbWEgbGlzdCB8IFNlbGVjdC1PYmplY3QgLVNraXAgMQ0KICAgICAgICAkbW9kZWxzID0gQCgpDQogICAgICAgIGZvcmVhY2ggKCRsaW5lIGluICRvdXRwdXQpIHsNCiAgICAgICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ14oXFMrKVxzK1xTK1xzKyhcUytccytcUyspJykgew0KICAgICAgICAgICAgICAgICRuYW1lID0gJG1hdGNoZXNbMV0NCiAgICAgICAgICAgICAgICAkc2l6ZSA9ICRtYXRjaGVzWzJdDQogICAgICAgICAgICAgICAgJHBhcmFtcyA9ICdOL0EnDQogICAgICAgICAgICAgICAgaWYgKCRuYW1lIC1tYXRjaCAnOihcZCsoXC5cZCspP1tibV0pJykgeyAkcGFyYW1zID0gJG1hdGNoZXNbMV0gfQ0KICAgICAgICAgICAgICAgIGVsc2VpZiAoJG5hbWUgLW1hdGNoICcoXGQrKFwuXGQrKT9bYm1dKScpIHsgJHBhcmFtcyA9ICRtYXRjaGVzWzFdIH0NCiAgICAgICAgICAgICAgICAkbW9kZWxzICs9IFtQU0N1c3RvbU9iamVjdF1Ae05hbWU9JG5hbWU7IFNpemU9JHNpemU7IFBhcmFtcz0kcGFyYW1zOyBEZXNjcmlwdGlvbj0nSW5zdGFsbGVkJ30NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBpZiAoJG1vZGVscy5Db3VudCAtZXEgMCkgeyBleGl0IDEgfQ0KICAgICAgICAjIE91dHB1dCB0byBjYWNoZSBmaWxlIGZvciBiYXRjaCBzY3JpcHQgdG8gcmVhZA0KICAgICAgICBpZiAoJENhY2hlRmlsZSkgew0KICAgICAgICAgICAgW1N5c3RlbS5JTy5GaWxlXTo6V3JpdGVBbGxMaW5lcygkQ2FjaGVGaWxlLCBAKCRtb2RlbHMuTmFtZSkpDQogICAgICAgIH0NCiAgICAgICAgIyBEaXNwbGF5IHRhYmxlDQogICAgICAgIHRyeXskdz0kSG9zdC5VSS5SYXdVSS5XaW5kb3dTaXplLldpZHRofWNhdGNoeyR3PTgwfTsgaWYoJHcgLWx0IDYwKXskdz02MH07ICRkdz0kdy01MzsgaWYoJGR3IC1sdCA1KXskZHc9NX0NCiAgICAgICAgV3JpdGUtSG9zdCAoJ3swLC00fSB7MSwtMjV9IHsyLC0xMH0gezMsLTh9ICB7NH0nIC1mICdOdW0nLCdNb2RlbCBOYW1lJywnU2l6ZScsJ1BhcmFtcycsJ0Rlc2NyaXB0aW9uJykNCiAgICAgICAgV3JpdGUtSG9zdCAoJ3swLC00fSB7MSwtMjV9IHsyLC0xMH0gezMsLTh9ICB7NH0nIC1mICgnLScqNCksKCctJyoyNSksKCctJyoxMCksKCctJyo4KSwoJy0nKiRkdykpDQogICAgICAgICRrPTANCiAgICAgICAgZm9yZWFjaCAoJG0gaW4gJG1vZGVscykgew0KICAgICAgICAgICAgJGsrKw0KICAgICAgICAgICAgJG49JG0uTmFtZTsgaWYoJG4uTGVuZ3RoIC1ndCAyNSl7JG49JG4uU3Vic3RyaW5nKDAsMjIpKycuLi4nfTsNCiAgICAgICAgICAgIFdyaXRlLUhvc3QgKCd7MCwzfS4gezEsLTI1fSB7MiwtMTB9IHszLC04fSAgezR9JyAtZiAkaywkbiwkbS5TaXplLCRtLlBhcmFtcywkbS5EZXNjcmlwdGlvbikNCiAgICAgICAgfQ0KICAgICAgICBleGl0IDANCiAgICB9IGNhdGNoIHsNCiAgICAgICAgV3JpdGUtRXJyb3IgJF8NCiAgICAgICAgZXhpdCAxDQogICAgfQ0KfQ0KIyBGZXRjaCBIVE1MIGZyb20gT2xsYW1hIG1vZGVsIGxpYnJhcnkNCiR1cmw9J2h0dHBzOi8vb2xsYW1hLmNvbS9zZWFyY2gnDQp0cnkgew0KICAgICRyZXNwb25zZT1JbnZva2UtV2ViUmVxdWVzdCAtVXJpICR1cmwgLVVzZUJhc2ljUGFyc2luZw0KICAgICRjb250ZW50PSRyZXNwb25zZS5Db250ZW50DQp9IGNhdGNoIHsNCiAgICBXcml0ZS1FcnJvciAkXw0KICAgIGV4aXQgMQ0KfQ0KIyBFeHRyYWN0IG1vZGVsIGxpc3QgaXRlbXMgZnJvbSBIVE1MDQokbW9kZWxSZWdleD1bcmVnZXhdJyg/cyk8bGkgeC10ZXN0LW1vZGVsKC4qPyk8L2xpPicNCiRtYXRjaGVzPSRtb2RlbFJlZ2V4Lk1hdGNoZXMoJGNvbnRlbnQpDQokbW9kZWxzPUAoKQ0KJGNvdW50PTANCiRza2lwcGVkPTANCiMgUHJvY2VzcyBlYWNoIG1vZGVsOiBleHRyYWN0IG5hbWUsIGRlc2NyaXB0aW9uLCBhbmQgc2l6ZSBlc3RpbWF0ZXMNCmZvcmVhY2goJG1hdGNoIGluICRtYXRjaGVzKSB7DQogICAgaWYoJHNraXBwZWQgLWx0ICRTa2lwKSB7ICRza2lwcGVkKys7IGNvbnRpbnVlIH0NCiAgICBpZigkY291bnQgLWdlICRMaW1pdCkgeyBicmVhayB9DQogICAgJG1vZGVsSHRtbD0kbWF0Y2guR3JvdXBzWzFdLlZhbHVlDQogICAgIyBFeHRyYWN0IG1vZGVsIG5hbWUgZnJvbSB0aXRsZQ0KICAgICRuYW1lUmVnZXg9W3JlZ2V4XSd4LXRlc3Qtc2VhcmNoLXJlc3BvbnNlLXRpdGxlPihbXjxdKyk8Jw0KICAgICRuYW1lTWF0Y2g9JG5hbWVSZWdleC5NYXRjaCgkbW9kZWxIdG1sKQ0KICAgICRuYW1lPWlmKCRuYW1lTWF0Y2guU3VjY2Vzcyl7W1N5c3RlbS5OZXQuV2ViVXRpbGl0eV06Okh0bWxEZWNvZGUoJG5hbWVNYXRjaC5Hcm91cHNbMV0uVmFsdWUuVHJpbSgpKX1lbHNleydVbmtub3duJ30NCiAgICAjIEV4dHJhY3QgZGVzY3JpcHRpb24NCiAgICAkZGVzY1JlZ2V4PVtyZWdleF0nKD9zKTxwW14+XSp0ZXh0LW5ldXRyYWwtODAwW14+XSo+KC4qPyk8L3A+Jw0KICAgICRkZXNjTWF0Y2g9JGRlc2NSZWdleC5NYXRjaCgkbW9kZWxIdG1sKQ0KICAgICRkZXNjcmlwdGlvbj1pZigkZGVzY01hdGNoLlN1Y2Nlc3MpeygkZGVzY01hdGNoLkdyb3Vwc1sxXS5WYWx1ZS5UcmltKCktcmVwbGFjZSAnXHMrJywgJyAnKX1lbHNleydObyBkZXNjcmlwdGlvbiBhdmFpbGFibGUnfQ0KICAgICMgRXh0cmFjdCBhbmQgZXN0aW1hdGUgZG93bmxvYWQgc2l6ZSBiYXNlZCBvbiBwYXJhbWV0ZXJzDQogICRzaXplUmVnZXg9W3JlZ2V4XSd4LXRlc3Qtc2l6ZVtePl0qPihbXjxdKyk8Jw0KICAkc2l6ZU1hdGNoZXM9JHNpemVSZWdleC5NYXRjaGVzKCRtb2RlbEh0bWwpDQogIGlmKCRzaXplTWF0Y2hlcy5Db3VudCAtZ3QgMCkgew0KICAgICAgICBmb3JlYWNoKCRzbSBpbiAkc2l6ZU1hdGNoZXMpIHsNCiAgICAgICAgICAgICRwYXJhbVNpemU9JHNtLkdyb3Vwc1sxXS5WYWx1ZS5UcmltKCkNCiAgICAgICAgICAgICRnYlNpemU9J1Vua25vd24nDQogICAgICAgICAgICAjIFN0YW5kYXJkIG1vZGVsczogc2l6ZSA9IChwYXJhbXMgKiBjb21wcmVzc2lvbikgKyBvdmVyaGVhZA0KICAgICAgICAgICAgaWYoJHBhcmFtU2l6ZSAtbWF0Y2ggJyhcZCsoXC5cZCspPyliJyl7DQogICAgICAgICAgICAgICAgJHBNYXRjaD0kTWF0Y2hlcw0KICAgICAgICAgICAgICAgICR2YWw9W2RvdWJsZV0kcE1hdGNoWzFdDQogICAgICAgICAgICAgICAgaWYoJHZhbCAtbGUgMyl7JGVzdD0kdmFsKjAuNiswLjV9ZWxzZWlmKCR2YWwgLWxlIDEwKXskZXN0PSR2YWwqMC41NSswLjV9ZWxzZXskZXN0PSR2YWwqMC41Nn0NCiAgICAgICAgICAgICAgICAkZ2JTaXplPSd7MDpOMX0gR0InLWYgJGVzdA0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgIyBUaW55IG1vZGVscw0KICAgICAgICAgICAgZWxzZWlmKCRwYXJhbVNpemUgLW1hdGNoICcoXGQrKW0nKSB7DQogICAgICAgICAgICAgICAgJGdiU2l6ZT0nPCAxIEdCJw0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgIyBNb0UgbW9kZWxzIChlLmcuIE1peHRyYWwgOHg3Qik6IHNpemUgPSAoZXhwZXJ0cyAqIGV4cGVydF9zaXplKSAqIGNvbXByZXNzaW9uDQogICAgICAgICAgICBlbHNlaWYoJHBhcmFtU2l6ZSAtbWF0Y2ggJyhcZCspeChcZCsoXC5cZCspPyliJyl7DQogICAgICAgICAgICAgICAgJG1NYXRjaD0kTWF0Y2hlcw0KICAgICAgICAgICAgICAgICRleHBlcnRzPVtkb3VibGVdJG1NYXRjaFsxXQ0KICAgICAgICAgICAgICAgICRlU2l6ZT1bZG91YmxlXSRtTWF0Y2hbMl0NCiAgICAgICAgICAgICAgICAkdG90YWw9JGV4cGVydHMqJGVTaXplDQogICAgICAgICAgICAgICAgJGVzdD0kdG90YWwqMC40Ng0KICAgICAgICAgICAgICAgICRnYlNpemU9J3swOk4xfSBHQictZiAkZXN0DQogICAgICAgICAgICB9DQogICAgICAgICAgICAkZnVsbE5hbWU9IiRuYW1lYDokcGFyYW1TaXplIg0KICAgICAgICAgICAgJG1vZGVscys9W1BTQ3VzdG9tT2JqZWN0XUB7TmFtZT0kZnVsbE5hbWU7U2l6ZUdCPSRnYlNpemU7UGFyYW1zPSRwYXJhbVNpemU7RGVzY3JpcHRpb249JGRlc2NyaXB0aW9ufQ0KICAgICAgICB9DQogICAgfSBlbHNlIHsNCiAgICAgICAgJG1vZGVscys9W1BTQ3VzdG9tT2JqZWN0XUB7TmFtZT0kbmFtZTtTaXplR0I9J1Vua25vd24nO1BhcmFtcz0nTi9BJztEZXNjcmlwdGlvbj0kZGVzY3JpcHRpb259DQogICAgfQ0KICAgICRjb3VudCsrDQp9DQojIE91dHB1dCByZXN1bHRzIGluIHBpcGUtZGVsaW1pdGVkIGZvcm1hdCAoTmFtZXxTaXplfFBhcmFtc3xEZXNjcmlwdGlvbikNCiRsaW5lcz1AKCkNCmZvcmVhY2goJG1vZGVsIGluICRtb2RlbHMpIHsNCiAgICAkbGluZXMrPSIkKCRtb2RlbC5OYW1lKXwkKCRtb2RlbC5TaXplR0IpfCQoJG1vZGVsLlBhcmFtcyl8JCgkbW9kZWwuRGVzY3JpcHRpb24pIg0KfQ0KaWYoJEFwcGVuZCkgew0KICAgIFtTeXN0ZW0uSU8uRmlsZV06OkFwcGVuZEFsbExpbmVzKCRDYWNoZUZpbGUsICRsaW5lcykNCn0gZWxzZSB7DQogICAgW1N5c3RlbS5JTy5GaWxlXTo6V3JpdGVBbGxMaW5lcygkQ2FjaGVGaWxlLCAkbGluZXMpDQp9DQpXcml0ZS1Ib3N0ICJTdWNjZXNzZnVsbHkgZmV0Y2hlZCAkKCRtb2RlbHMuQ291bnQpIG1vZGVscy4iDQo="
$bytes = [Convert]::FromBase64String($b64String)
$decodedContent = [System.Text.Encoding]::UTF8.GetString($bytes)
Write-Host $decodedContent
```

### Option 2: Encode fetch_models.ps1 to verify
To verify the embedded Base64 string matches the current `fetch_models.ps1`:

```powershell
# Encode fetch_models.ps1
$content = Get-Content 'path\to\fetch_models.ps1' -Raw
$bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
$b64 = [Convert]::ToBase64String($bytes)
Write-Host $b64

# Compare with the hash of the original
Get-FileHash 'path\to\fetch_models.ps1' -Algorithm MD5
```

The Base64 string in `ollamaLauncher.bat` should decode to match the MD5 checksum.

## Author
Mike

## License
This project is open source and available under the MIT License.

## References
- [Ollama Official Website](https://ollama.ai)
- [Ollama GitHub Repository](https://github.com/jmorganca/ollama)
