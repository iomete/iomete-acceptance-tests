package iomete;

import io.karatelabs.core.Suite;
import io.karatelabs.core.SuiteResult;
import io.karatelabs.core.TagSelector;
import io.karatelabs.gherkin.ExamplesTable;
import io.karatelabs.gherkin.Feature;
import io.karatelabs.gherkin.FeatureSection;
import io.karatelabs.gherkin.Scenario;
import io.karatelabs.gherkin.ScenarioOutline;

import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;

// Counts the run's scenarios, so each outcome line can say how far the run is ([42/173]).
//
// The total is worked out up front from the features Karate is about to run, with Karate's own
// tag selection (TagSelector, which also drops @ignore and @setup). A dynamic outline
// (`Examples: | karate.setup().planes |`) only knows its rows once it runs, so the total grows by
// one as each of its examples starts. A run narrowed to lines or a scenario name (make test-one)
// has no total worth computing, and counts up without one.
final class ProgressTracker {

    private final AtomicInteger total = new AtomicInteger();
    private final AtomicInteger done = new AtomicInteger();
    private volatile boolean totalKnown;
    private volatile Set<FeatureSection> dynamicSections = Set.of();

    // Called on SUITE_ENTER, so a second suite in the same JVM starts from zero.
    synchronized void start(Suite suite) {
        total.set(0);
        done.set(0);
        Set<FeatureSection> dynamic = Collections.newSetFromMap(new IdentityHashMap<>());

        boolean narrowed = (suite.lineFilters != null && !suite.lineFilters.isEmpty()) || suite.scenarioName != null;
        totalKnown = !narrowed;
        if (narrowed || suite.features == null) {
            dynamicSections = dynamic;
            return;
        }

        int count = 0;
        for (Feature feature : suite.features) {
            for (FeatureSection section : feature.getSections()) {
                if (!section.isOutline()) {
                    if (selected(section.getScenario(), suite)) {
                        count++;
                    }
                    continue;
                }

                ScenarioOutline outline = section.getScenarioOutline();
                for (ExamplesTable examples : outline.getExamplesTables()) {
                    Scenario example = outline.toScenario(null, 0, 0, examples.getTags());
                    if (!selected(example, suite)) {
                        continue;
                    }
                    if (examples.getTable().isDynamic()) {
                        dynamic.add(section);
                    } else {
                        // the first row is the header
                        count += Math.max(0, examples.getTable().getRows().size() - 1);
                    }
                }
            }
        }

        total.set(count);
        dynamicSections = dynamic;
    }

    private static boolean isSetup(Scenario scenario) {
        return scenario != null && scenario.getTagsEffective() != null
                && scenario.getTagsEffective().stream().anyMatch(tag -> "setup".equals(tag.getName()));
    }

    private static boolean selected(Scenario scenario, Suite suite) {
        return new TagSelector(scenario.getTagsEffective()).evaluate(suite.tagSelector, suite.env);
    }

    // A dynamic outline's example only becomes part of the total once Karate expands it.
    void scenarioStarted(Scenario scenario) {
        if (totalKnown && scenario != null && dynamicSections.contains(scenario.getSection())) {
            total.incrementAndGet();
        }
    }

    // Counts a finished scenario and returns the counter to print with it, e.g. "[42/173]". A
    // @setup scenario runs when a dynamic outline asks for its rows (karate.setup()), not as a
    // test of its own, so it is neither in the total nor counted.
    String scenarioFinished(Scenario scenario) {
        if (isSetup(scenario)) {
            return "[setup]";
        }
        int n = done.incrementAndGet();
        return totalKnown ? "[" + n + "/" + Math.max(n, total.get()) + "]" : "[" + n + "]";
    }

    String plan() {
        if (!totalKnown) {
            return "Running the selected scenarios";
        }
        // one per outline, however many dynamic Examples tables it has
        int dynamicOutlines = dynamicSections.size();
        String extra = dynamicOutlines == 0 ? ""
                : " (plus " + dynamicOutlines + " outline(s) whose rows are counted as they start)";
        return "Running " + total.get() + " scenarios" + extra;
    }

    // Read from Karate's own result rather than counted here: SCENARIO_EXIT fires before a
    // scenario's afterScenario hook runs, so a teardown that fails afterwards only shows there.
    // Karate counts a skipped scenario as passed too (ScenarioResult.isPassed is "no step
    // failed"), so passed is what is neither failed nor skipped.
    static String summary(SuiteResult result) {
        int failed = result.getScenarioFailedCount();
        int skipped = result.getScenarioSkippedCount();
        return "Finished " + result.getScenarioCount() + " scenarios: " + (result.getScenarioCount() - failed - skipped)
                + " passed, " + failed + " failed, " + skipped + " skipped";
    }
}
