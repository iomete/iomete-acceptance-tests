package iomete.helpers.connection;

import java.util.List;
import java.util.Map;

// Retry, single-attempt and error-reporting logic shared by the connection clients.
final class ClientAttempts {

    private static final int ATTEMPTS = 3;
    private static final long RETRY_INTERVAL_MILLIS = 10_000;

    // One query against a compute, returning its rows keyed by column name.
    @FunctionalInterface
    interface Attempt {
        List<Map<String, Object>> run();
    }

    private ClientAttempts() {}

    // Retries a few times, since the gateway can lag behind a compute that has only just come up.
    static List<Map<String, Object>> withRetries(String client, Attempt attempt)
            throws InterruptedException {
        RuntimeException last = null;
        for (int i = 1; i <= ATTEMPTS; i++) {
            try {
                return attempt.run();
            } catch (RuntimeException e) {
                last = e;
                System.out.println(
                        client + " attempt " + i + "/" + ATTEMPTS + " failed: " + e.getMessage());
                if (i < ATTEMPTS) {
                    Thread.sleep(RETRY_INTERVAL_MILLIS);
                }
            }
        }
        throw last;
    }

    // Returns why one attempt failed, or null when it succeeded. Not retried, so a rejected
    // login answers straight away.
    static String failure(Attempt attempt) {
        try {
            attempt.run();
            return null;
        } catch (RuntimeException e) {
            return e.getMessage();
        }
    }

    // Flattens the cause chain into one message. Clients echo the connection string in their
    // errors, so the token is kept out of the report.
    static RuntimeException redacted(Throwable e, String token) {
        StringBuilder message = new StringBuilder();
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (!message.isEmpty()) {
                message.append(" <- ");
            }
            message.append(t.getClass().getSimpleName()).append(": ").append(t.getMessage());
        }
        return new RuntimeException(message.toString().replace(token, "***"));
    }
}
