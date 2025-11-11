package com.example;

import io.grpc.stub.StreamObserver;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public class TestStreamObserver<T> implements StreamObserver<T> {
    private final CountDownLatch latch = new CountDownLatch(1);
    private final AtomicReference<T> response = new AtomicReference<>();
    private final AtomicReference<Throwable> error = new AtomicReference<>();

    @Override
    public void onNext(T value) {
        response.set(value);
    }

    @Override
    public void onError(Throwable t) {
        error.set(t);
        latch.countDown();
    }

    @Override
    public void onCompleted() {
        latch.countDown();
    }

    public T getResponse() {
        try {
            if (!latch.await(5, TimeUnit.SECONDS)) {
                throw new RuntimeException("Timeout waiting for response");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("Interrupted waiting for response", e);
        }
        
        if (error.get() != null) {
            throw new RuntimeException("Error in response", error.get());
        }
        
        return response.get();
    }
}
