package com.loadtest.dsql;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.sun.management.OperatingSystemMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.RuntimeMXBean;
import java.net.NetworkInterface;
import java.util.Enumeration;

/**
 * Collect system and hardware metrics.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public class SystemMetrics {
    
    @JsonProperty("hardware")
    private HardwareInfo hardware;
    
    @JsonProperty("cpu")
    private CpuMetrics cpu;
    
    @JsonProperty("memory")
    private MemoryMetrics memory;
    
    @JsonProperty("disk")
    private DiskMetrics disk;
    
    @JsonProperty("network")
    private NetworkMetrics network;
    
    public SystemMetrics() {
        collectMetrics();
    }
    
    private void collectMetrics() {
        this.hardware = collectHardwareInfo();
        this.cpu = collectCpuMetrics();
        this.memory = collectMemoryMetrics();
        this.disk = collectDiskMetrics();
        this.network = collectNetworkMetrics();
    }
    
    private HardwareInfo collectHardwareInfo() {
        HardwareInfo info = new HardwareInfo();
        
        try {
            OperatingSystemMXBean osBean = (OperatingSystemMXBean) ManagementFactory.getOperatingSystemMXBean();
            
            info.setProcessorCount(osBean.getAvailableProcessors());
            info.setArchitecture(System.getProperty("os.arch"));
            info.setOsName(System.getProperty("os.name"));
            info.setOsVersion(System.getProperty("os.version"));
            info.setJavaVersion(System.getProperty("java.version"));
            info.setJavaVendor(System.getProperty("java.vendor"));
            
            // Try to get total physical memory
            try {
                long totalMemory = osBean.getTotalPhysicalMemorySize();
                info.setTotalPhysicalMemoryBytes(totalMemory);
            } catch (Exception e) {
                // May not be available on all platforms
            }
            
            // Try to get free physical memory
            try {
                long freeMemory = osBean.getFreePhysicalMemorySize();
                info.setFreePhysicalMemoryBytes(freeMemory);
            } catch (Exception e) {
                // May not be available on all platforms
            }
            
        } catch (Exception e) {
            // Fallback to basic info
            info.setProcessorCount(Runtime.getRuntime().availableProcessors());
            info.setArchitecture(System.getProperty("os.arch"));
            info.setOsName(System.getProperty("os.name"));
            info.setOsVersion(System.getProperty("os.version"));
            info.setJavaVersion(System.getProperty("java.version"));
        }
        
        return info;
    }
    
    private CpuMetrics collectCpuMetrics() {
        CpuMetrics metrics = new CpuMetrics();
        
        try {
            OperatingSystemMXBean osBean = (OperatingSystemMXBean) ManagementFactory.getOperatingSystemMXBean();
            RuntimeMXBean runtimeBean = ManagementFactory.getRuntimeMXBean();
            
            // CPU load (0.0 to 1.0, or -1 if not available)
            double cpuLoad = osBean.getProcessCpuLoad();
            if (cpuLoad >= 0) {
                metrics.setProcessCpuLoad(cpuLoad * 100.0); // Convert to percentage
            }
            
            // System CPU load
            double systemCpuLoad = osBean.getSystemCpuLoad();
            if (systemCpuLoad >= 0) {
                metrics.setSystemCpuLoad(systemCpuLoad * 100.0);
            }
            
            // CPU time
            long cpuTime = osBean.getProcessCpuTime();
            metrics.setProcessCpuTimeNs(cpuTime);
            
            // Uptime
            metrics.setJvmUptimeMs(runtimeBean.getUptime());
            
        } catch (Exception e) {
            // Metrics may not be available
        }
        
        return metrics;
    }
    
    private MemoryMetrics collectMemoryMetrics() {
        MemoryMetrics metrics = new MemoryMetrics();
        
        try {
            MemoryMXBean memoryBean = ManagementFactory.getMemoryMXBean();
            OperatingSystemMXBean osBean = (OperatingSystemMXBean) ManagementFactory.getOperatingSystemMXBean();
            Runtime runtime = Runtime.getRuntime();
            
            // Heap memory
            long heapUsed = memoryBean.getHeapMemoryUsage().getUsed();
            long heapMax = memoryBean.getHeapMemoryUsage().getMax();
            long heapCommitted = memoryBean.getHeapMemoryUsage().getCommitted();
            
            metrics.setHeapUsedBytes(heapUsed);
            metrics.setHeapMaxBytes(heapMax);
            metrics.setHeapCommittedBytes(heapCommitted);
            
            // Non-heap memory
            long nonHeapUsed = memoryBean.getNonHeapMemoryUsage().getUsed();
            long nonHeapMax = memoryBean.getNonHeapMemoryUsage().getMax();
            long nonHeapCommitted = memoryBean.getNonHeapMemoryUsage().getCommitted();
            
            metrics.setNonHeapUsedBytes(nonHeapUsed);
            metrics.setNonHeapMaxBytes(nonHeapMax);
            metrics.setNonHeapCommittedBytes(nonHeapCommitted);
            
            // System memory (if available)
            try {
                long totalPhysical = osBean.getTotalPhysicalMemorySize();
                long freePhysical = osBean.getFreePhysicalMemorySize();
                long usedPhysical = totalPhysical - freePhysical;
                
                metrics.setSystemTotalBytes(totalPhysical);
                metrics.setSystemFreeBytes(freePhysical);
                metrics.setSystemUsedBytes(usedPhysical);
            } catch (Exception e) {
                // May not be available
            }
            
        } catch (Exception e) {
            // Fallback to basic runtime info
            Runtime runtime = Runtime.getRuntime();
            metrics.setHeapUsedBytes(runtime.totalMemory() - runtime.freeMemory());
            metrics.setHeapMaxBytes(runtime.maxMemory());
            metrics.setHeapCommittedBytes(runtime.totalMemory());
        }
        
        return metrics;
    }
    
    private DiskMetrics collectDiskMetrics() {
        DiskMetrics metrics = new DiskMetrics();
        
        try {
            java.io.File root = new java.io.File("/");
            long totalSpace = root.getTotalSpace();
            long freeSpace = root.getFreeSpace();
            long usableSpace = root.getUsableSpace();
            long usedSpace = totalSpace - freeSpace;
            
            metrics.setTotalBytes(totalSpace);
            metrics.setFreeBytes(freeSpace);
            metrics.setUsableBytes(usableSpace);
            metrics.setUsedBytes(usedSpace);
            
        } catch (Exception e) {
            // Disk metrics may not be available
        }
        
        return metrics;
    }
    
    private NetworkMetrics collectNetworkMetrics() {
        NetworkMetrics metrics = new NetworkMetrics();
        
        try {
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            int interfaceCount = 0;
            
            while (interfaces.hasMoreElements()) {
                NetworkInterface ni = interfaces.nextElement();
                if (ni.isUp() && !ni.isLoopback()) {
                    interfaceCount++;
                }
            }
            
            metrics.setActiveInterfaces(interfaceCount);
            
        } catch (Exception e) {
            // Network info may not be limited
        }
        
        return metrics;
    }
    
    // Getters and setters
    public HardwareInfo getHardware() { return hardware; }
    public void setHardware(HardwareInfo hardware) { this.hardware = hardware; }
    
    public CpuMetrics getCpu() { return cpu; }
    public void setCpu(CpuMetrics cpu) { this.cpu = cpu; }
    
    public MemoryMetrics getMemory() { return memory; }
    public void setMemory(MemoryMetrics memory) { this.memory = memory; }
    
    public DiskMetrics getDisk() { return disk; }
    public void setDisk(DiskMetrics disk) { this.disk = disk; }
    
    public NetworkMetrics getNetwork() { return network; }
    public void setNetwork(NetworkMetrics network) { this.network = network; }
    
    // Inner classes for metrics
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class HardwareInfo {
        @JsonProperty("processor_count")
        private Integer processorCount;
        
        @JsonProperty("architecture")
        private String architecture;
        
        @JsonProperty("os_name")
        private String osName;
        
        @JsonProperty("os_version")
        private String osVersion;
        
        @JsonProperty("java_version")
        private String javaVersion;
        
        @JsonProperty("java_vendor")
        private String javaVendor;
        
        @JsonProperty("total_physical_memory_bytes")
        private Long totalPhysicalMemoryBytes;
        
        @JsonProperty("free_physical_memory_bytes")
        private Long freePhysicalMemoryBytes;
        
        // Getters and setters
        public Integer getProcessorCount() { return processorCount; }
        public void setProcessorCount(Integer processorCount) { this.processorCount = processorCount; }
        
        public String getArchitecture() { return architecture; }
        public void setArchitecture(String architecture) { this.architecture = architecture; }
        
        public String getOsName() { return osName; }
        public void setOsName(String osName) { this.osName = osName; }
        
        public String getOsVersion() { return osVersion; }
        public void setOsVersion(String osVersion) { this.osVersion = osVersion; }
        
        public String getJavaVersion() { return javaVersion; }
        public void setJavaVersion(String javaVersion) { this.javaVersion = javaVersion; }
        
        public String getJavaVendor() { return javaVendor; }
        public void setJavaVendor(String javaVendor) { this.javaVendor = javaVendor; }
        
        public Long getTotalPhysicalMemoryBytes() { return totalPhysicalMemoryBytes; }
        public void setTotalPhysicalMemoryBytes(Long totalPhysicalMemoryBytes) { this.totalPhysicalMemoryBytes = totalPhysicalMemoryBytes; }
        
        public Long getFreePhysicalMemoryBytes() { return freePhysicalMemoryBytes; }
        public void setFreePhysicalMemoryBytes(Long freePhysicalMemoryBytes) { this.freePhysicalMemoryBytes = freePhysicalMemoryBytes; }
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class CpuMetrics {
        @JsonProperty("process_cpu_load_percent")
        private Double processCpuLoad;
        
        @JsonProperty("system_cpu_load_percent")
        private Double systemCpuLoad;
        
        @JsonProperty("process_cpu_time_ns")
        private Long processCpuTimeNs;
        
        @JsonProperty("jvm_uptime_ms")
        private Long jvmUptimeMs;
        
        // Getters and setters
        public Double getProcessCpuLoad() { return processCpuLoad; }
        public void setProcessCpuLoad(Double processCpuLoad) { this.processCpuLoad = processCpuLoad; }
        
        public Double getSystemCpuLoad() { return systemCpuLoad; }
        public void setSystemCpuLoad(Double systemCpuLoad) { this.systemCpuLoad = systemCpuLoad; }
        
        public Long getProcessCpuTimeNs() { return processCpuTimeNs; }
        public void setProcessCpuTimeNs(Long processCpuTimeNs) { this.processCpuTimeNs = processCpuTimeNs; }
        
        public Long getJvmUptimeMs() { return jvmUptimeMs; }
        public void setJvmUptimeMs(Long jvmUptimeMs) { this.jvmUptimeMs = jvmUptimeMs; }
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class MemoryMetrics {
        @JsonProperty("heap_used_bytes")
        private Long heapUsedBytes;
        
        @JsonProperty("heap_max_bytes")
        private Long heapMaxBytes;
        
        @JsonProperty("heap_committed_bytes")
        private Long heapCommittedBytes;
        
        @JsonProperty("non_heap_used_bytes")
        private Long nonHeapUsedBytes;
        
        @JsonProperty("non_heap_max_bytes")
        private Long nonHeapMaxBytes;
        
        @JsonProperty("non_heap_committed_bytes")
        private Long nonHeapCommittedBytes;
        
        @JsonProperty("system_total_bytes")
        private Long systemTotalBytes;
        
        @JsonProperty("system_free_bytes")
        private Long systemFreeBytes;
        
        @JsonProperty("system_used_bytes")
        private Long systemUsedBytes;
        
        // Getters and setters
        public Long getHeapUsedBytes() { return heapUsedBytes; }
        public void setHeapUsedBytes(Long heapUsedBytes) { this.heapUsedBytes = heapUsedBytes; }
        
        public Long getHeapMaxBytes() { return heapMaxBytes; }
        public void setHeapMaxBytes(Long heapMaxBytes) { this.heapMaxBytes = heapMaxBytes; }
        
        public Long getHeapCommittedBytes() { return heapCommittedBytes; }
        public void setHeapCommittedBytes(Long heapCommittedBytes) { this.heapCommittedBytes = heapCommittedBytes; }
        
        public Long getNonHeapUsedBytes() { return nonHeapUsedBytes; }
        public void setNonHeapUsedBytes(Long nonHeapUsedBytes) { this.nonHeapUsedBytes = nonHeapUsedBytes; }
        
        public Long getNonHeapMaxBytes() { return nonHeapMaxBytes; }
        public void setNonHeapMaxBytes(Long nonHeapMaxBytes) { this.nonHeapMaxBytes = nonHeapMaxBytes; }
        
        public Long getNonHeapCommittedBytes() { return nonHeapCommittedBytes; }
        public void setNonHeapCommittedBytes(Long nonHeapCommittedBytes) { this.nonHeapCommittedBytes = nonHeapCommittedBytes; }
        
        public Long getSystemTotalBytes() { return systemTotalBytes; }
        public void setSystemTotalBytes(Long systemTotalBytes) { this.systemTotalBytes = systemTotalBytes; }
        
        public Long getSystemFreeBytes() { return systemFreeBytes; }
        public void setSystemFreeBytes(Long systemFreeBytes) { this.systemFreeBytes = systemFreeBytes; }
        
        public Long getSystemUsedBytes() { return systemUsedBytes; }
        public void setSystemUsedBytes(Long systemUsedBytes) { this.systemUsedBytes = systemUsedBytes; }
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class DiskMetrics {
        @JsonProperty("total_bytes")
        private Long totalBytes;
        
        @JsonProperty("free_bytes")
        private Long freeBytes;
        
        @JsonProperty("usable_bytes")
        private Long usableBytes;
        
        @JsonProperty("used_bytes")
        private Long usedBytes;
        
        // Getters and setters
        public Long getTotalBytes() { return totalBytes; }
        public void setTotalBytes(Long totalBytes) { this.totalBytes = totalBytes; }
        
        public Long getFreeBytes() { return freeBytes; }
        public void setFreeBytes(Long freeBytes) { this.freeBytes = freeBytes; }
        
        public Long getUsableBytes() { return usableBytes; }
        public void setUsableBytes(Long usableBytes) { this.usableBytes = usableBytes; }
        
        public Long getUsedBytes() { return usedBytes; }
        public void setUsedBytes(Long usedBytes) { this.usedBytes = usedBytes; }
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class NetworkMetrics {
        @JsonProperty("active_interfaces")
        private Integer activeInterfaces;
        
        // Getters and setters
        public Integer getActiveInterfaces() { return activeInterfaces; }
        public void setActiveInterfaces(Integer activeInterfaces) { this.activeInterfaces = activeInterfaces; }
    }
}

