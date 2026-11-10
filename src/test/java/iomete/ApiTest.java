package iomete;

import io.karatelabs.core.RunEvent;
import io.karatelabs.core.Runner;
import io.karatelabs.core.ScenarioResult;
import io.karatelabs.core.ScenarioRunEvent;
import io.karatelabs.junit6.JUnitBridgeListener;
import io.karatelabs.junit6.StreamingTestIterator;
import io.karatelabs.junit6.TestEvent;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.DynamicNode;
import org.junit.jupiter.api.TestFactory;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import io.karatelabs.gherkin.Feature;
import io.karatelabs.gherkin.FeatureSection;
import io.karatelabs.gherkin.Tag;

import java.io.IOException;
import java.net.URISyntaxException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.stream.Stream;

class ApiTest {

    // Where the progress lines go. logback-test.xml has to keep this at INFO, since the root
    // logger is WARN.
    private static final Logger PROGRESS = LoggerFactory.getLogger("karate.progress");

    // How long to wait for the next scenario to report before giving up on the run. Kept under
    // the workflow's own timeout, so a hung suite fails here, with a report, rather than
    // being killed by GitHub. It is a gap between scenarios, not a budget for the whole run.
    static final long EVENT_TIMEOUT_MINUTES = 30;

    // The lanes a test feature names in its @lock tag; see "Running" in AGENTS.md.
    private static final Set<String> LANES = Set.of("spark", "job", "job2", "stream", "sql", "security", "maintenance", "api");

    static final String TESTS = "classpath:iomete/tests";

    // A customer's own tests, outside src so a release never replaces them. Run when present.
    static final String CUSTOM_TESTS = "custom-tests";

    // Karate holds a thread permit while a scenario waits for its lock, so give every scenario
    // one and let the lanes alone decide what runs.
    static final int THREADS = 1000;

    // This is what `Karate.run("classpath:iomete/tests")` does, spelled out, because the JUnit
    // wrapper takes no RunListener and the progress lines need one: an `afterScenario` hook in
    // karate-config.js would have been the easier route, but a feature that sets its own
    // teardown replaces it, and nine of ours do. Only tests/ is scanned: features in helpers/
    // and */setup/ run when called.
    @TestFactory
    Stream<DynamicNode> testAll() throws IOException, URISyntaxException {
        String options = System.getProperty("karate.options");
        checkLanes(options);
        if (runsCustomTests(options)) {
            PROGRESS.info("Also running your tests in {}", Path.of(CUSTOM_TESTS).toAbsolutePath());
        }

        LinkedBlockingQueue<TestEvent> events = new LinkedBlockingQueue<>();
        JUnitBridgeListener bridge = new JUnitBridgeListener(events, true);
        Runner.Builder builder = Runner.builder()
                .path(testPaths())
                .resultListener(bridge)
                .listener(ApiTest::logProgress)
                // Karate's own per-feature summary, which the JUnit tree replaces
                .outputConsoleSummary(false);
        // Scenarios reach JUnit as they finish, so the tree fills in while the suite runs.
        // Completion is signalled once parallel() has returned and the report writers have
        // flushed, and on failure too, so the stream cannot be left blocking.
        CompletableFuture
                .supplyAsync(() -> builder.parallel(THREADS))
                .whenComplete((result, error) -> bridge.complete(result));
        return new StreamingTestIterator(events, true, EVENT_TIMEOUT_MINUTES).stream();
    }

    static List<String> testPaths() {
        return Files.isDirectory(Path.of(CUSTOM_TESTS)) ? List.of(TESTS, CUSTOM_TESTS) : List.of(TESTS);
    }

    // Whether a run with these Karate options includes custom-tests. Naming no path runs the defaults.
    static boolean runsCustomTests(String options) {
        if (!testPaths().contains(CUSTOM_TESTS)) {
            return false;
        }

        List<String> named = namedPaths(options);
        return named.isEmpty() || named.stream().anyMatch(path -> path.contains(CUSTOM_TESTS));
    }

    // The paths in Karate options: every token that is not a flag or a flag's value.
    private static List<String> namedPaths(String options) {
        List<String> paths = new ArrayList<>();
        if (options == null || options.isBlank()) {
            return paths;
        }

        String[] tokens = options.replace("\"", "").trim().split("\\s+");
        for (int i = 0; i < tokens.length; i++) {
            if (tokens[i].startsWith("-")) {
                i++;
            } else {
                paths.add(tokens[i]);
            }
        }

        return paths;
    }

    // A feature without a lane would run unbounded next to everything else, and a misspelt one
    // would quietly become a lane of its own, so either stops the run before it starts.
    // Reads the copies on the classpath, which are what Karate runs, with Karate's own parser.
    // custom-tests is only checked when the run includes it, so a bad one never blocks cleanup.
    static void checkLanes(String options) throws IOException, URISyntaxException {
        List<Path> files = new ArrayList<>();
        // Inside the single jar the features are not files; CI checks the source before it is built.
        java.net.URI tests = ApiTest.class.getResource("/iomete/tests").toURI();
        if ("file".equals(tests.getScheme())) {
            files.addAll(features(Path.of(tests)));
        }
        if (runsCustomTests(options)) {
            files.addAll(features(Path.of(CUSTOM_TESTS)));
        }

        List<String> problems = new ArrayList<>();

        for (Path file : files) {
            Feature feature = Feature.read(file.toFile());
            if (tagNames(feature.getTags()).contains("ignore")) {
                continue;
            }

            List<String> featureLanes = lockValues(feature.getTags());
            List<String> lanes = new ArrayList<>(featureLanes);
            for (FeatureSection section : feature.getSections()) {
                lanes.addAll(lockValues(section.isOutline()
                        ? section.getScenarioOutline().getTags()
                        : section.getScenario().getTags()));
            }

            String name = feature.getPackageQualifiedName();
            if (featureLanes.isEmpty()) {
                problems.add(name + ": no feature-level @lock tag");
            }
            if (!LANES.containsAll(lanes)) {
                problems.add(name + ": @lock=" + String.join(",", lanes) + " is not one of " + LANES);
            }
        }

        if (!problems.isEmpty()) {
            throw new IllegalStateException("every test feature needs a feature-level @lock tag naming its lanes (see AGENTS.md):\n  "
                    + String.join("\n  ", problems));
        }
    }

    private static List<Path> features(Path root) throws IOException {
        try (Stream<Path> walk = Files.walk(root)) {
            return walk.filter(path -> path.toString().endsWith(".feature")).sorted().toList();
        }
    }

    private static List<String> lockValues(List<Tag> tags) {
        List<String> values = new ArrayList<>();
        if (tags == null) {
            return values;
        }

        for (Tag tag : tags) {
            if ("lock".equals(tag.getName())) {
                values.addAll(tag.getValues());
            }
        }

        return values;
    }

    private static List<String> tagNames(List<Tag> tags) {
        return tags == null ? List.of() : tags.stream().map(Tag::getName).toList();
    }

    // Names the scenario as it starts and again with its outcome, so the run log is more than a
    // stream of requests and a scenario that polls for minutes cannot be mistaken for a hang.
    static boolean logProgress(RunEvent event) {
        try {
            if (event instanceof ScenarioRunEvent scenarioEvent) {
                Map<String, Object> data = scenarioEvent.toJson();
                // a feature reached through karate.call, which is part of its caller's scenario
                if (!Integer.valueOf(0).equals(data.get("callDepth"))) {
                    return true;
                }
                String label = data.get("feature") + " | " + data.get("name");
                ScenarioResult result = scenarioEvent.result();
                if (result == null) {
                    PROGRESS.info(">> RUN  {}", label);
                } else {
                    String outcome = result.isFailed() ? "FAIL" : result.isSkipped() ? "SKIP" : "PASS";
                    PROGRESS.info("<< {} {} ({} ms)", outcome, label, result.getDurationMillis());
                }
            }
        } catch (Exception e) {
            // progress reporting must never be what fails a run
            PROGRESS.warn("could not log scenario progress: {}", e.toString());
        }
        // never veto a scenario
        return true;
    }

    // The admin token's name carries the run id, so a finished run has to remove its own or
    // they pile up on the target. Doing it here rather than as a separate `make` target keeps
    // it in the SAME JVM that minted it, so there is no run id to hand across processes, and
    // saves a second Maven start-up on every CI run.
    //
    // Runs after failures too, but NOT when the JVM is killed. A killed run's token goes when
    // `make cleanup` runs for its id, since each teardown JVM mints and revokes the same name.
    @AfterAll
    static void revokeRunToken() {
        try {
            Runner.runFeature("classpath:iomete/helpers/user/revoke-run-token.feature", null);
        } catch (Exception e) {
            // teardown must never be what fails a run
            System.out.println("could not revoke this run's token: " + e);
        }
    }
}
