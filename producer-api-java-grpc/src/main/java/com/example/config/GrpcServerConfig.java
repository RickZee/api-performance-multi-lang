package com.example.config;

import io.grpc.netty.shaded.io.grpc.netty.NettyServerBuilder;
import net.devh.boot.grpc.server.serverfactory.GrpcServerConfigurer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.concurrent.TimeUnit;

/**
 * Configuration for gRPC server to handle high concurrency
 * Optimizes connection handling and keepalive settings
 */
@Configuration
public class GrpcServerConfig {

    @Bean
    public GrpcServerConfigurer grpcServerConfigurer() {
        return serverBuilder -> {
            if (serverBuilder instanceof NettyServerBuilder) {
                NettyServerBuilder nettyServerBuilder = (NettyServerBuilder) serverBuilder;
                
                // Maximum number of concurrent calls per connection
                // HTTP/2 supports multiplexing, so multiple calls can share one connection
                nettyServerBuilder.maxConcurrentCallsPerConnection(100);
                
                // Keep-alive settings to maintain connections and detect dead connections
                nettyServerBuilder.keepAliveTime(30, TimeUnit.SECONDS);
                nettyServerBuilder.keepAliveTimeout(5, TimeUnit.SECONDS);
                
                // Allow keep-alive pings even when there are no active calls
                nettyServerBuilder.permitKeepAliveWithoutCalls(true);
                
                // Maximum inbound message size (default: 4MB)
                nettyServerBuilder.maxInboundMessageSize(4 * 1024 * 1024);
                
                // Maximum inbound metadata size (default: 8KB)
                nettyServerBuilder.maxInboundMetadataSize(8 * 1024);
            }
        };
    }
}

