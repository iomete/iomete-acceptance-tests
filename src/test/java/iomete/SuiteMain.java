package iomete;

import io.karatelabs.core.FeatureResult;
import io.karatelabs.core.Runner;
import io.karatelabs.core.ScenarioResult;
import io.karatelabs.core.SuiteResult;

import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.locks.ReentrantLock;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// What `java -jar suite.jar` runs: check the setup, run the suite, then remove what it created.
// Exits with the suite's result. Arguments, when given, choose what runs (Karate options, e.g.
// `--tags @smoke` or `classpath:iomete/tests/sql`); `cleanup` only removes what IOMETE_RUN_ID created.
// A custom-tests folder in the working directory runs with the suite.
public final class SuiteMain {

    // One cache for every step, so the token and the domain are set up once per run
    private static final Map<String, Object> CALL_SINGLE_CACHE = new ConcurrentHashMap<>();
    private static final ReentrantLock CALL_SINGLE_LOCK = new ReentrantLock();

    // The config's own message in a setup failure, without Karate's wrapping around it
    private static final Pattern ERROR = Pattern.compile("Error: ([^\\n]*)");
    private static final Pattern WRAPPING = Pattern.compile("(expression|called feature failed|callSingle failed|js failed).*");
    // Problems that mean the run never signed in, so cleanup would only add failed sign-ins
    private static final Pattern NOT_SIGNED_IN = Pattern.compile("(could not log in|cannot reach|no credentials|IOMETE_BASE_URL|https?://\\S+ answered).*");

    private static final AtomicBoolean CLEANED_UP = new AtomicBoolean();
    private static final AtomicLong LAST_EVENT = new AtomicLong(System.currentTimeMillis());

    private SuiteMain() {
    }

    public static void main(String[] args) {
        System.setProperty("io.netty.tryReflectionSetAccessible", "true");
        // The user's choice applies to the suite's own run only; every step sets its own
        String options = args.length > 0 ? String.join(" ", args) : firstSet(System.getProperty("karate.options"), System.getenv("KARATE_OPTIONS"));

        String runId = System.getenv().getOrDefault("IOMETE_RUN_ID", "d" + System.currentTimeMillis() / 1000);
        System.setProperty("iomete.runId", runId);
        System.out.println("Run id: " + runId);
        System.out.println("Suite commit: " + ApiTest.commit());

        if ("cleanup".equals(options)) {
            System.exit(cleanup(false) ? 1 : 0);
        }

        // Before anything is created, so a feature without a lane costs no cleanup
        try {
            ApiTest.checkLanes(options);
        } catch (Exception e) {
            System.out.println("Setup problem: " + e.getMessage());
            System.exit(1);
        }
        if (ApiTest.runsCustomTests(options)) {
            System.out.println("Also running your tests in " + Path.of(ApiTest.CUSTOM_TESTS).toAbsolutePath());
        }

        // docker stop and Ctrl-C end the JVM; it still cleans up on the way out, from here on,
        // since the setup check below already creates the run's domain
        Runtime.getRuntime().addShutdownHook(new Thread(() -> cleanup(false)));

        SuiteResult check = run("target/karate-probe", "classpath:iomete/helpers/probe.feature");
        if (check.isFailed()) {
            String problem = failure(check);
            System.out.println("Setup problem: " + problem);
            if (NOT_SIGNED_IN.matcher(problem).matches()) {
                // each failed sign-in counts toward the account's lockout
                CLEANED_UP.set(true);
            } else {
                cleanup(true);
            }
            System.exit(1);
        }

        startWatchdog();
        List<String> tests = ApiTest.testPaths();
        System.setProperty("karate.options", options == null || options.isBlank() ? String.join(" ", tests) : options);
        SuiteResult result = builder(null)
                .path(tests)
                .listener(event -> {
                    LAST_EVENT.set(System.currentTimeMillis());
                    return ApiTest.logProgress(event);
                })
                .outputConsoleSummary(true)
                .parallel(ApiTest.THREADS);

        cleanup(false);
        System.exit(result.isFailed() ? 1 : 0);
    }

    private static String firstSet(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value;
            }
        }

        return null;
    }

    // A scenario that hangs would hold the run forever, so a run with no event for this long
    // ends, and the shutdown hook still cleans up. The same gap ApiTest allows.
    private static void startWatchdog() {
        long limit = TimeUnit.MINUTES.toMillis(ApiTest.EVENT_TIMEOUT_MINUTES);
        Thread watchdog = new Thread(() -> {
            while (true) {
                try {
                    Thread.sleep(TimeUnit.MINUTES.toMillis(1));
                } catch (InterruptedException e) {
                    return;
                }

                if (System.currentTimeMillis() - LAST_EVENT.get() > limit) {
                    System.out.println("No progress for " + ApiTest.EVENT_TIMEOUT_MINUTES + " minutes, stopping the run");
                    System.exit(1);
                }
            }
        });
        watchdog.setDaemon(true);
        watchdog.start();
    }

    private static Runner.Builder builder(String outputDir) {
        Runner.Builder builder = Runner.builder()
                .callSingleCache(CALL_SINGLE_CACHE, CALL_SINGLE_LOCK)
                .backupOutputDir(false);
        return outputDir == null ? builder : builder.outputDir(outputDir).outputConsoleSummary(false);
    }

    // The options are set explicitly, since Karate reads them (or KARATE_OPTIONS) on every run
    private static SuiteResult run(String outputDir, String feature) {
        System.setProperty("karate.options", feature);
        return builder(outputDir).path(feature).parallel(1);
    }

    // The teardown steps in the order they need, then the run's token. Once per JVM; synchronized
    // so a stop during the main thread's cleanup waits for it instead of exiting mid-way.
    // Returns whether a step failed.
    private static synchronized boolean cleanup(boolean quiet) {
        if (!CLEANED_UP.compareAndSet(false, true)) {
            return false;
        }

        if (!quiet) {
            System.out.println("Removing what the run created");
        }
        boolean failed = run("target/karate-teardown", "classpath:iomete/helpers/cleanup-run-fixtures.feature").isFailed();
        failed |= run("target/karate-teardown", "classpath:iomete/helpers/compute/delete-run-computes.feature").isFailed();
        // never creates the domain it is about to delete
        System.setProperty("iomete.teardown", "true");
        failed |= run("target/karate-teardown", "classpath:iomete/helpers/cleanup-run-domain.feature").isFailed();
        // through the shared cache, so it revokes the token the run signed in with, without signing in again
        run("target/karate-teardown", "classpath:iomete/helpers/user/revoke-run-token.feature");

        if (failed && !quiet) {
            System.out.println("WARNING: cleanup did not finish; run again with IOMETE_RUN_ID="
                    + System.getProperty("iomete.runId") + " and the argument cleanup");
        }

        return failed;
    }

    private static String failure(SuiteResult result) {
        for (FeatureResult feature : result.getFeatureResults()) {
            for (ScenarioResult scenario : feature.getScenarioResults()) {
                String message = scenario.getFailureMessage();
                if (message == null) {
                    continue;
                }

                // the innermost message that is not Karate's own wrapping
                String found = null;
                Matcher matcher = ERROR.matcher(message);
                while (matcher.find()) {
                    String text = matcher.group(1).trim();
                    if (!WRAPPING.matcher(text).matches()) {
                        found = text;
                    }
                }
                return found != null ? found : message.lines().findFirst().orElse(message);
            }
        }

        return "the check failed, see target/karate-probe";
    }
}
