package com.hmdp.limiter.aop;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.invocation.Invocation;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.StringRedisTemplate;

import java.util.ArrayList;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.mockito.Mockito.mockingDetails;

@ExtendWith(MockitoExtension.class)
class RateLimiterAspectTest {

    private static final String RATE_LIMIT_KEY = "rate:test";

    @Mock
    private StringRedisTemplate stringRedisTemplate;

    @InjectMocks
    private RateLimiterAspect rateLimiterAspect;

    @Test
    void shouldPassUniqueMemberForEveryRequest() {
        rateLimiterAspect.executeSlidingWindowScript(RATE_LIMIT_KEY, 5L, 5L);
        rateLimiterAspect.executeSlidingWindowScript(RATE_LIMIT_KEY, 5L, 5L);

        ArrayList<Invocation> invocations = new ArrayList<>(mockingDetails(stringRedisTemplate).getInvocations());
        assertEquals(2, invocations.size());
        Object[] firstCall = (Object[]) invocations.get(0).getRawArguments()[2];
        Object[] secondCall = (Object[]) invocations.get(1).getRawArguments()[2];
        assertEquals(4, firstCall.length);
        assertEquals(4, secondCall.length);
        assertNotEquals(firstCall[3], secondCall[3]);
    }
}
