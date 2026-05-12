import Foundation
import Dispatch
import Darwin

final class DirectoryChangeMonitor {
    private let url: URL
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void

    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, queue: DispatchQueue = DispatchQueue(label: "deepseekmonitor.directory-monitor"), onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.queue = queue
        self.onChange = onChange
    }

    func start() {
        stop()

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link, .revoke],
            queue: queue
        )

        source.setEventHandler { [weak source, onChange] in
            guard source != nil else { return }
            onChange()
        }

        source.setCancelHandler { [fileDescriptor] in
            if fileDescriptor >= 0 {
                close(fileDescriptor)
            }
        }

        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    deinit {
        stop()
    }
}
