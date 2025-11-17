### Analysis of TCP Ephemeral Port Exhaustion in k6 gRPC Testing on Docker/macOS

Running k6 in Docker on macOS for gRPC API testing simulates high-concurrency scenarios akin to our EKS clusters under bursty event ingestion. However, with many parallel Virtual Users (VUs)—say, hundreds simulating producers—this setup risks TCP ephemeral port exhaustion, leading to errors like "can't assign requested address" or connection failures. This stems from limited ephemeral ports (temporary ports for outbound connections, default range 49152–65535 on macOS, yielding ~16k ports), exacerbated by Docker's VM layer and gRPC's connection model.

In our active-active AWS regions, where gRPC handles low-latency internal comms, local testing must mirror production resilience. Exhaustion could mimic real-world issues like pod overloads during spikes, impacting CDC or queries.

#### Root Causes of Ephemeral Port Exhaustion
Ephemeral ports are assigned by the OS for client-side TCP connections (e.g., k6 VUs dialing gRPC servers). With many VUs, rapid connection cycling depletes them:

1. **Limited Port Range**: macOS defaults to 49152–65535 (~16k ports), far less than Linux's 32768–60999 (~28k). Each VU might open/close connections per iteration, consuming ports. gRPC's HTTP/2 multiplexing reduces per-request ports but still risks exhaustion if connections aren't reused.

2. **TIME_WAIT State**: Closed connections linger in TIME_WAIT (default 15–60s on macOS) to prevent data corruption, blocking port reuse. In k6, frequent `client.connect()`/`client.close()` in loops accumulates these, especially with short iterations.

3. **File Descriptor Limits**: Related to ports, macOS caps open files (including sockets) at ~256 soft/10240 hard per process. k6 can hit this with high VUs, causing "too many open files" errors.

4. **Docker on macOS Specifics**: Docker runs in a Linux VM (via HyperKit or similar), inheriting host limits but with its own networking. Containerized k6 may exhaust VM ports; macOS host influences via bridged networking. No direct Docker port range config, but host tuning propagates.

5. **gRPC and k6 Behavior**: k6's gRPC module creates connections per `client.connect()`, defaulting to non-persistent if closed often. High VUs without reuse mimic our EKS bursts but locally amplify exhaustion.

Symptoms include connection resets, delays, or UNAVAILABLE errors—similar to Istio/Envoy overhead in our prod setup. In finance, this could skew test results for compliance-critical paths like event auditing in Collibra/Glue.

#### Proposed Fixes
Fixes span OS tuning, Docker config, and k6 scripting. Prioritize non-invasive changes (e.g., script optimizations) before system tweaks. Test in staging to avoid impacting dev workflows.

| Fix Category | Description | Implementation Steps | Impact on Our Setup |
|--------------|-------------|----------------------|---------------------|
| **k6 Script Optimization (Reuse Connections)** | Reuse a single gRPC connection across VUs/iterations to minimize openings/closures, reducing TIME_WAIT buildup. | - Connect once in `setup()` or conditionally in `default` (e.g., `if (__ITER == 0) { client.connect(...); }`).<br>- Invoke RPCs on the shared client.<br>- Close in `teardown()` or VUSER_END event.<br>- Example script: `import grpc from 'k6/net/grpc'; const client = new grpc.Client(); export function setup() { client.connect('grpc.example.com:443', { plaintext: false }); } export default () => { client.invoke('service/method', {}); }; export function teardown() { client.close(); }` | Aligns with our gRPC consumers' persistent channels; improves test accuracy for Kafka/CDC loads. |
| **Increase Ephemeral Port Range (macOS Host)** | Expand available ports to ~32k by lowering the start range. | - Run: `sudo sysctl -w net.inet.ip.portrange.first=32768` (immediate).<br>- Verify: `sysctl net.inet.ip.portrange.first`.<br>- Note: May require firewall adjustments; not persistent—add to script or cron. | Propagates to Docker VM; useful for local EKS simulations via minikube. |
| **Increase File Descriptors (macOS Host)** | Raise open file limits to handle more sockets. | - Disable SIP temporarily (Recovery Mode: `csrutil disable`).<br>- Set: `sudo launchctl limit maxfiles 65536 200000`.<br>- Create persistent plists: `/Library/LaunchDaemons/limit.maxfiles.plist` with XML for soft 64000/hard 524288; reboot.<br>- Re-enable SIP: `csrutil enable`. | Essential for high-VU tests mirroring our EKS pod limits; integrates with ELK monitoring. |
| **Docker Container Tuning** | Tune Linux VM in Docker; run k6 with elevated limits. | - In Dockerfile or run: Add `RUN sysctl -w net.ipv4.ip_local_port_range="1024 65535"` and `RUN sysctl -w net.ipv4.tcp_tw_reuse=1`.<br>- Docker run: `--ulimit nofile=250000:250000`.<br>- For macOS Docker Desktop: Increase resources in Preferences (e.g., 8GB RAM, 4 CPUs) to support VM tuning. | Simulates our EKS/Istio configs; add to CI/CD for reproducible tests. |
| **TCP TIME_WAIT Tuning** | Reduce lingering or enable reuse (Linux-focused, but apply in Docker). | - In container: `sysctl -w net.ipv4.tcp_fin_timeout=15` (shorten to 15s).<br>- Enable: `sysctl -w net.ipv4.tcp_tw_reuse=1`.<br>- macOS lacks direct equivalent; rely on port expansion. | Reduces delays in burst tests; monitor via ELK for prod parallels. |
| **Monitoring and Best Practices** | Track usage to prevent exhaustion proactively. | - Use `netstat -an | grep TIME_WAIT | wc -l` or `ss -tan | grep TIME_WAIT` in container.<br>- Limit VUs per instance; distribute tests if >30k.<br>- Optimize k6: `discardResponseBodies: true`; avoid unnecessary metrics. | Ties into our ELK APM for test observability; evolve strategy with chaos testing. |

#### Recommendations for Technology Evolution and Testing Strategy
- **Short-Term**: Update k6 scripts for connection reuse in our gRPC test suites; apply macOS/Docker tunes for local devs. PoC with 500+ VUs simulating ingestion bursts.
- **Long-Term**: Integrate into CI/CD (e.g., GitHub Actions with Docker) for automated tuning; extend to EKS-based testing with Istio for realistic multi-region loads. Monitor via ELK to correlate local issues with prod (e.g., gRPC in active-active).
- **Risks**: System tweaks require admin access; test non-disruptively. If issues persist, consider Colima as Docker alternative for better macOS perf.


### Analysis of k6 gRPC Script for Potential TCP Ephemeral Port Exhaustion with High Parallel VUs

As the director overseeing design, technology, testing strategy, and evolution for our mortgage platform, incorporating robust load testing for our gRPC-based consumers (e.g., Spring Boot services handling event streams from Confluent Kafka or CDC via Qlik Replicate to the data lake) is essential. This k6 script targets throughput testing of gRPC APIs (Java, Rust, Go variants), simulating producer loads akin to our Ingestion API bursts. Running it in Docker on macOS with many parallel Virtual Users (VUs)—e.g., hundreds to thousands—raises risks of TCP ephemeral port exhaustion, as discussed previously. This could manifest as connection failures ("cannot assign requested address"), especially during ramps in active-active scenarios mirroring our EKS clusters across AWS regions.

I'll first summarize the script's structure and strengths, then analyze exhaustion risks specific to this code, and propose fixes. This draws on k6 documentation, gRPC best practices, and macOS/Docker networking behaviors. Benchmarks show k6 gRPC tests can handle ~10k RPS locally, but port limits cap concurrent connections at ~16k-28k, depending on OS.

#### Script Overview and Strengths
- **Configuration**: Pulls env vars for host/port/service/method/proto/payload size; uses `getTestOptions()` for stages (e.g., ramp-up VUs). Flexible for testing different impls (Java/Rust/Go) by switching `__ENV.PROTO_FILE`.
- **Proto Loading**: Handles paths robustly with try-catch, converting absolute Docker paths (e.g., `/k6/proto/...`) to relative (`../proto/...`) for k6's `client.load()`. Good for containerized runs; self-contained protos assumed (no imports).
- **Connection Management**: Creates `grpc.Client` globally (init context, run once per VU). Connects in `default()` only if not connected, enabling reuse across iterations per VU. Uses plaintext for simplicity (aligns with local testing; add TLS for prod sims).
- **Payload and Invocation**: Generates dynamic payloads via `generateGrpcEventPayload()` (size via env var, e.g., 4k-64k to mimic shredded JSON events). Invokes unary RPC (`ProcessEvent`); checks for `StatusOK` and `success` field.
- **Metrics and Summary**: Custom `errorRate`; `handleSummary` with `textSummary` for readable output (RPS, latency percentiles, errors)—integrates well with our ELK for APM export.
- **Teardown**: Closes client, releasing resources.
- **Overall**: Well-structured for throughput; `sleep(0.1)` paces to avoid server overload, aiding realistic EKS pod scaling sims.

Strengths mitigate some exhaustion: Persistent connections per VU reduce open/close cycles, leveraging gRPC's HTTP/2 multiplexing for multiple invokes over one connection. However, with high VUs, issues arise.

#### Deep Analysis of Ephemeral Port Exhaustion Risks in This Script
Ephemeral ports (OS-assigned temporary ports for outbound TCP, e.g., 49152–65535 on macOS ~16k; 32768–60999 on Docker's Linux VM ~28k) are consumed per connection. gRPC's persistent model uses one port per client connection, but k6's architecture amplifies risks:

1. **Per-VU Connection Model Leading to Port Consumption**:
   - Each VU runs independently with its own `grpc.Client`, connecting once (if check) and reusing for iterations. For 1000 VUs, this creates ~1000 persistent connections, each tying an ephemeral port for the test duration (plus TIME_WAIT linger ~15-60s post-close).
   - **Risk in High VUs**: If VUs exceed available ports (e.g., 500+ on macOS defaults), exhaustion occurs during ramp-up in `options` stages. Symptoms: Connection errors in logs (`Failed to connect`), spiked `errorRate`, incomplete tests.
   - **Docker/macOS Aggravation**: Docker's VM bridges traffic, inheriting host limits but with overhead; macOS SIP (System Integrity Protection) restricts tuning without workarounds. Proto loading doesn't affect ports, but failed loads could indirectly cause retries/connections.
   - **Implication for Our Setup**: Simulates our gRPC consumers under producer floods (e.g., mortgage events to Aurora/Kafka), but local exhaustion skews results vs. EKS/Istio's connection pooling. Large payloads (64k) add memory pressure, compounding if ports exhaust mid-test.

2. **TIME_WAIT Accumulation During Teardown or Failures**:
   - `teardown()` closes clients, but closed connections enter TIME_WAIT, blocking ports temporarily. With staged ramps (e.g., down from 1000 VUs), partial teardowns accumulate TIME_WAIT states, exhausting ports for remaining VUs.
   - **Risk**: Error handling (e.g., on connect fail) doesn't close, leaking ports. `sleep(0.1)` helps pacing but doesn't prevent buildup in short-iteration tests.
   - **Docker/macOS Specific**: VM's Linux kernel defaults higher ports, but host macOS influences if bridged; no direct container port range config.

3. **File Descriptor Overlap**:
   - Ports relate to open files/sockets; macOS defaults ~256 soft/10240 hard per process. k6 process (in Docker) with high VUs could hit this, as each connection is a descriptor.
   - **Risk**: "Too many open files" errors, especially with logging (`console.log`) or large payloads increasing I/O.

4. **Proto and Env Var Dependencies**:
   - Path adjustments are solid, but mount failures in Docker (e.g., `/k6/proto` not volume-mounted) cause load errors, leading to test aborts before connections—indirectly avoiding exhaustion but failing tests.
   - **No Direct Port Impact**: But if retries added (not in script), could cycle connections.

5. **General Throughput Context**:
   - Script aims for high RPS, but without port tuning, caps at ~16k concurrent on macOS. Aligns with our EKS limits but exposes local dev bottlenecks.

#### Proposed Fixes
Prioritize script/code changes for portability, then OS/Docker tuning. Test in staging Docker setups mirroring our EKS (e.g., with ELK export for metrics). For multi-region sims, extend to distributed k6 (cloud/outposts).

| Fix Category | Description | Implementation | Impact/Benefits |
|--------------|-------------|---------------|-----------------|
| **Script Optimizations (Connection Reuse/Handling)** | Maximize reuse per VU; add robust error closing to minimize leaks. | - Move `client.connect()` to global init (outside `default()`), as it's run once per VU.<br>- Add try-catch around `invoke()` with `client.close()` on persistent errors.<br>- Use k6's `shared-iterations` executor in `options` (via `getTestOptions()`) for fewer VUs/more iterations, reducing connections (e.g., 100 VUs, 10k iterations vs. 1000 VUs).<br>- Example: In global: `client.connect(...);` Remove connect from `default()`. In `default()`: `try { response = client.invoke(...); } catch(e) { client.close(); errorRate.add(1); }` | Reduces ports to VU count; better simulates our gRPC multiplexing in Istio. Lowers exhaustion without OS changes. |
| **Pacing and Staging Adjustments** | Slow ramps to allow TIME_WAIT decay; distribute load. | - In `getTestOptions()`, use gradual stages (e.g., `{ duration: '1m', target: 500 }`).<br>- Increase `sleep(0.2-0.5)` for high VUs to space connections.<br>- For very high load, use k6 cloud/distributed (multiple Docker instances) to parallelize without single-host port limits. | Prevents burst exhaustion; aligns with EKS HPA for active-active scaling. |
| **Docker/Container Tuning** | Elevate limits inside container for Linux VM perks. | - Dockerfile: Add `RUN sysctl -w net.ipv4.ip_local_port_range="1024 65535" && sysctl -w net.ipv4.tcp_tw_reuse=1 && sysctl -w net.ipv4.tcp_fin_timeout=15` (expands to ~64k ports, reuses TIME_WAIT, shortens linger).<br>- Run command: `docker run --ulimit nofile=65536:65536 ...` (raises descriptors).<br>- macOS Docker Desktop: Boost VM resources (8+ CPUs, 16GB RAM) in Preferences. | Directly addresses VM limits; portable to CI/CD for EKS-like tests. |
| **macOS Host Tuning** | Broaden host ports/descriptors; propagates to Docker VM. | - Ports: `sudo sysctl -w net.inet.ip.portrange.first=32768 net.inet.ip.portrange.last=65535` (~32k).<br>- Descriptors: Disable SIP (Recovery Mode), then `sudo launchctl limit maxfiles 65536 unlimited`; create `/Library/LaunchDaemons/limit.maxfiles.plist` with XML for persistence; re-enable SIP.<br>- Monitor: `netstat -an | grep TIME_WAIT | wc -l` during tests. | Quick local fix; monitor for security in finance envs (e.g., no impact on PingID/Vault). |
| **Monitoring and Logging Enhancements** | Track port usage to detect/prevent exhaustion. | - Add global counter for connections; log `lsof -i | wc -l` via exec (if k6 allows) or external script.<br>- Export to ELK: Use k6's Prometheus output for custom metrics on connections/errors. | Ties into our ELK APM; informs technology evolution for gRPC in multi-region. |

#### Recommendations for Testing Strategy and Evolution
- **Short-Term PoC**: Run with 500+ VUs post-fixes; benchmark RPS/latency vs. exhaustion thresholds. Integrate with our GraphQL/Dremio query tests for end-to-end.
- **Long-Term**: Evolve to k6 operator on EKS for distributed testing, simulating active-active with Istio proxies. Add contract testing for protos (e.g., via Pact) to ensure payload compat.
- **Next Steps**: Verify proto mounts in Docker-compose (volume: `./proto:/k6/proto`); test large payloads (64k) for memory overlap with ports.

This refines the script for reliable, scalable testing, enhancing our platform's resilience. If you share run logs/errors or `config.js`/`helpers.js`, I can iterate.