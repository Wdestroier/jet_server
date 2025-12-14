Experimental high-performance HTTP/1.1 server for Linux/WSL built with Dart FFI and epoll.

## Benchmark inside WSL:

Run these from Windows terminal (PowerShell, not Command Prompt):

Install Dart and tools (once):
```bash
wsl -d Ubuntu sh -c "sudo apt-get update -y && sudo apt-get install -y curl gnupg wrk && curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg && echo 'deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | sudo tee /etc/apt/sources.list.d/dart_stable.list > /dev/null && sudo apt-get update -y && sudo apt-get install -y dart"
```

Check if Dart is installed:
```bash
wsl -d Ubuntu sh -c "dart --version"
```

Build benchmark runner:
```bash
wsl -d Ubuntu sh -c "cd /mnt/c/Users/YourUser/Desktop/jet_server/jet_server/benchmarks/jet_vs_shelf && dart pub get && dart compile exe bin/run.dart -o build/run"
```

Run jet_server (first shell, keep open):
```bash
wsl -d Ubuntu sh -c "cd /mnt/c/Users/Wdest/Desktop/jet_server/jet_server/benchmarks/jet_vs_shelf && ./build/run --server=jet --port=3001"
```

Run shelf (second shell, keep open):
```bash
wsl -d Ubuntu sh -c "cd /mnt/c/Users/Wdest/Desktop/jet_server/jet_server/benchmarks/jet_vs_shelf && ./build/run --server=shelf --port=3002"
```

Benchmark with [wrk](https://github.com/wg/wrk) (third shell):
```bash
wsl -d Ubuntu sh -c "wrk -H 'Connection: keep-alive' -c 256 -t 16 -d 30s http://localhost:3001/"
wsl -d Ubuntu sh -c "wrk -H 'Connection: keep-alive' -c 256 -t 16 -d 30s http://localhost:3002/"
```

Benchmark results:

Processor: Intel Core i9 13900H.
RAM: 16 GB DDR5 5186 MT/s.
OS: Windows 11 24H2.

```
wsl -d Ubuntu sh -c "wrk -H 'Connection: keep-alive' -c 256 -t 16 -d 30s http://localhost:3001/"
Running 30s test @ http://localhost:3001/
  16 threads and 256 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     7.10us   39.96us  27.56ms   99.86%
    Req/Sec   130.03k    29.18k  144.38k    95.25%
  4087784 requests in 30.11s, 401.54MB read
  Socket errors: connect 0, read 34, write 0, timeout 0
Requests/sec: 135753.59
Transfer/sec:     13.33MB

wsl -d Ubuntu sh -c "wrk -H 'Connection: keep-alive' -c 256 -t 16 -d 30s http://localhost:3002/"
Running 30s test @ http://localhost:3002/
  16 threads and 256 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency    16.45ms    6.82ms 308.14ms   97.72%
    Req/Sec     0.99k   140.94     3.74k    90.26%
  472648 requests in 30.12s, 120.35MB read
Requests/sec:  15691.98
Transfer/sec:      4.00MB

```

The same system handles over 8.6x more requests per second.

Data from [The Benchmarker](https://web-frameworks-benchmark.netlify.app) (gathered on 2025-12-14) shows that the fastest framework delivers 10.2x the throughput of [shelf](https://pub.dev/packages/shelf).
