import Foundation

public final class PTYTerminalSession {
    private var masterFd: Int32 = -1
    private var childPid: pid_t = -1
    private var isRunning: Bool = false
    private let readQueue = DispatchQueue(label: "com.machead.pty.read", qos: .userInitiated)
    
    public var onOutput: ((Data) -> Void)?
    public var onTerminated: (() -> Void)?
    
    public init() {}
    
    public func start(cols: Int = 120, rows: Int = 30) -> Bool {
        var master: Int32 = -1
        var slave: Int32 = -1
        var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        
        if openpty(&master, &slave, nil, nil, &ws) != 0 {
            NSLog("MacHead: openpty 失败: %d", errno)
            return false
        }
        
        self.masterFd = master
        
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, master)
        posix_spawn_file_actions_addclose(&fileActions, slave)
        
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        
        let cShell = shellPath.withCString { strdup($0) }
        let cArg0 = strdup("-zsh")
        var args: [UnsafeMutablePointer<CChar>?] = [cArg0, nil]
        
        var pid: pid_t = 0
        let spawnRes = posix_spawn(&pid, cShell, &fileActions, &attr, &args, environ)
        
        posix_spawn_file_actions_destroy(&fileActions)
        posix_spawnattr_destroy(&attr)
        free(cShell)
        free(cArg0)
        close(slave)
        
        if spawnRes != 0 {
            NSLog("MacHead: posix_spawn 伪终端进程失败: %d", spawnRes)
            close(master)
            return false
        }
        
        self.childPid = pid
        self.isRunning = true
        
        let flags = fcntl(master, F_GETFL, 0)
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        
        startReading()
        return true
    }
    
    private func startReading() {
        readQueue.async { [weak self] in
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            
            while let self = self, self.isRunning, self.masterFd >= 0 {
                let bytesRead = read(self.masterFd, buffer, bufferSize)
                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    self.onOutput?(data)
                } else if bytesRead == 0 {
                    break
                } else {
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        usleep(10000)
                        continue
                    } else {
                        break
                    }
                }
            }
            
            self?.terminate()
        }
    }
    
    public func writeInput(_ data: Data) {
        guard isRunning, masterFd >= 0 else { return }
        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            _ = write(masterFd, baseAddress, data.count)
        }
    }
    
    public func resize(cols: Int, rows: Int) {
        guard isRunning, masterFd >= 0 else { return }
        var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFd, TIOCSWINSZ, &ws)
    }
    
    public func terminate() {
        guard isRunning else { return }
        isRunning = false
        
        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }
        
        if childPid > 0 {
            kill(childPid, SIGTERM)
            var status: Int32 = 0
            waitpid(childPid, &status, WNOHANG)
            childPid = -1
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.onTerminated?()
        }
    }
    
    deinit {
        terminate()
    }
}
