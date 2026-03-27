import Foundation

struct AutoNasEntry: Identifiable, Hashable {
    let id: String // Mount path e.g. /Users/currentUser/NAS/Server
    let serverName: String
    let ipAddress: String
    let shareName: String
    let username: String
}

enum AutoMountError: LocalizedError, Equatable {
    case invalidAppleScript
    case appleScriptFailed(String?)
    case passwordEncodingFailed
    case autoMasterBlocked

    var errorDescription: String? {
        switch self {
        case .invalidAppleScript:
            return "Failed to generate AppleScript execution format."
        case .appleScriptFailed(let reason):
            return "Script execution failed: \(reason ?? "Unknown error")"
        case .passwordEncodingFailed:
            return "Failed to URL encode the password for SMB URI format."
        case .autoMasterBlocked:
            return "TCC Protection blocked modification of /etc/auto_master"
        }
    }
}

class AutomountManager {
    /// Fetches currently active mounts from /etc/auto_nas. Requires Admin prompt to read the locked file securely.
    static func fetchExistingMounts() throws -> [AutoNasEntry] {
        let script = "cat /etc/auto_nas 2>/dev/null || true"
        let output = try executeAsRoot(script: script)
        
        var mounts: [AutoNasEntry] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            
            // Expected format: /Users/[User]/NAS/[Server] -fstype=smbfs,soft ://[username]:[password]@[ipAddress]/[shareName]
            let parts = trimmed.components(separatedBy: " ")
            guard parts.count >= 3 else { continue }
            
            let path = parts[0]
            let serverName = URL(fileURLWithPath: path).lastPathComponent
            let uriPart = parts[2]
            
            let cleanUri = uriPart.replacingOccurrences(of: "://", with: "")
            let atComponents = cleanUri.components(separatedBy: "@")
            
            guard atComponents.count >= 2 else { continue }
            
            // Securely drop password without exposing it to the rest of the application
            let credentials = atComponents[0]
            let hostAndShare = atComponents.dropFirst().joined(separator: "@")
            
            let credParts = credentials.components(separatedBy: ":")
            let username = credParts.first ?? "Unknown"
            
            let hostParts = hostAndShare.components(separatedBy: "/")
            let ipAddress = hostParts.first ?? "Unknown"
            let shareName = hostParts.dropFirst().joined(separator: "/")
            
            let entry = AutoNasEntry(
                id: path,
                serverName: serverName,
                ipAddress: ipAddress,
                shareName: shareName,
                username: username
            )
            mounts.append(entry)
        }
        
        return mounts
    }

    /// Explicitly handles the one-time /etc/auto_master system configuration
    private static func ensureAutoMasterIsConfigured() throws {
        // Check if the master config is already mapped
        let checkScript = "grep -q 'auto_nas' /etc/auto_master || echo 'MISSING'"
        let checkOutput = try executeAsRoot(script: checkScript)
        
        if checkOutput.contains("MISSING") {
            // Attempt to write the required map pointer into the master config
            let appendScript = """
            echo "/- auto_nas -nosuid,noowners" >> /etc/auto_master
            """
            do {
                try executeAsRoot(script: appendScript)
            } catch {
                // If this step throws, it means macOS TCC rigidly blocked the operation.
                throw AutoMountError.autoMasterBlocked
            }
        }
    }

    /// Appends or updates a mount in autofs using root script.
    static func setupAutofs(
        serverName: String,
        ipAddress: String,
        shareName: String,
        username: String,
        password: String
    ) throws {
        // 1. Ensure the core routing file contains our custom map exactly once
        try ensureAutoMasterIsConfigured()
        
        let currentUser = NSUserName()
        let sanitizedPassword = URLQueryAllowedCharacterSet.encode(password)
        
        guard !sanitizedPassword.isEmpty else {
            throw AutoMountError.passwordEncodingFailed
        }

        let nasDirectoryPath = "/Users/\(currentUser)/NAS/\(serverName)"
        let autoNasContent = "\(nasDirectoryPath) -fstype=smbfs,soft ://\(username):\(sanitizedPassword)@\(ipAddress)/\(shareName)"

        // 2. Perform the individual folder mappings
        let shellScript = """
        mkdir -p "\(nasDirectoryPath)" 2>/dev/null || true
        chown \(currentUser) "/Users/\(currentUser)/NAS" 2>/dev/null || true
        chown \(currentUser) "\(nasDirectoryPath)" 2>/dev/null || true
        
        sed -i '' '\\|^'"\(nasDirectoryPath)"' |d' /etc/auto_nas 2>/dev/null || true
        
        echo "\(autoNasContent)" >> /etc/auto_nas
        chmod 600 /etc/auto_nas 2>/dev/null || true
        
        automount -cu 2>/dev/null || true
        automount -vc 2>/dev/null || true
        """
        
        try executeAsRoot(script: shellScript)
    }
    
    /// Removes a specific mount from /etc/auto_nas and unmounts it.
    static func removeMount(path: String) throws {
        let shellScript = """
        # Remove entry from /etc/auto_nas safely
        sed -i '' '\\|^'"\(path)"' |d' /etc/auto_nas 2>/dev/null || true
        
        # Flush the automounter to disconnect
        automount -cu 2>/dev/null || true
        automount -vc 2>/dev/null || true
        
        # Try to clean up directory if empty
        rmdir "\(path)" 2>/dev/null || true
        """
        try executeAsRoot(script: shellScript)
    }

    private struct URLQueryAllowedCharacterSet {
        static func encode(_ text: String) -> String {
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&+@/?=#")
            return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }
    }

    @discardableResult
    private static func executeAsRoot(script: String) throws -> String {
        let escapedScript = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScriptString = """
        do shell script "\(escapedScript)" with administrator privileges
        """

        guard let appleScript = NSAppleScript(source: appleScriptString) else {
            throw AutoMountError.invalidAppleScript
        }

        var errorDict: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorDict)
        
        if let error = errorDict {
            let errorMessage = error[NSAppleScript.errorMessage] as? String
            if let errorCode = error[NSAppleScript.errorNumber] as? Int, errorCode == -128 {
                throw AutoMountError.appleScriptFailed("Authentication canceled by user.")
            }
            throw AutoMountError.appleScriptFailed(errorMessage)
        }
        
        return result.stringValue ?? ""
    }
}
