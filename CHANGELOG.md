## 0.2.0

- Incremental HTTP parser waits for full headers and body before responding.
- Spurious wakeups no longer kill keep-alive connections.
- Fix epoll_event struct FFI layout to not collapse throughput under concurrency.

## 0.1.0

- Initial version.
