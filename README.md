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

Now available in [The Benchmarker](https://web-frameworks-benchmark.netlify.app).
