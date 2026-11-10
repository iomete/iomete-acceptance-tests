# Settings come from .env (see .env.example). make parses it, so values must be bare.
-include .env
export

# Karate 2.x needs Java 21. Locally the repo pins it via .java-version (jenv), but the
# Maven Wrapper does not consult jenv — so resolve JAVA_HOME through jenv when present.
# CI has no jenv and keeps the JAVA_HOME exported by setup-java.
JENV_JAVA_HOME := $(shell command -v jenv >/dev/null 2>&1 && jenv javahome 2>/dev/null)
ifneq ($(JENV_JAVA_HOME),)
  export JAVA_HOME := $(JENV_JAVA_HOME)
endif

.PHONY: check test test-one stop-computes stop-streaming-jobs cleanup cleanup-run cleanup-run-computes cleanup-run-domain clean report

# Check the target is reachable, the login works and the test domain is ready, without running tests.
# Prints one line either way; the full output is kept in target/check.log.
check:
	@mkdir -p target
	@if ./mvnw -B test -Diomete.check=true -Dkarate.options="--output target/karate-probe src/test/java/iomete/helpers/probe.feature" > target/check.log 2>&1; then \
		grep -h 'Ready: ' target/check.log | head -1 | grep . || echo 'Ready: setup checks passed.'; \
	else \
		msg=$$(grep -o 'Failed to evaluate karate-config.js: Error: .*' target/check.log | head -1 | sed 's/^Failed to evaluate karate-config.js: Error: //'); \
		echo "Setup problem: $${msg:-the check failed, see target/check.log}"; \
		exit 1; \
	fi

# clean first so edited .feature files aren't shadowed by stale copies in target/test-classes
test:
	./mvnw -B clean test

# Run part of the suite instead of all of it.
#   make test-one FEATURE=src/test/java/iomete/tests/sql/query-ddl.feature      # one feature
#   make test-one FEATURE=src/test/java/iomete/tests/sql/query-ddl.feature:46   # the scenario at that line
#   make test-one TAGS="@smoke"                                                 # by tag expression
#   make test-one NAME="DROP TABLE — returns COMPLETED"                         # by exact scenario name
#   make test-one FEATURE=custom-tests                                          # only your own tests
# The line may sit anywhere inside the scenario, so an editor's cursor line is enough.
# FEATURE takes a source path, not a classpath one, so the file being edited is the file that
# runs. No `clean` here: a re-run only re-copies the .feature files that changed, which keeps
# the loop fast. Run `make clean` yourself after adding/moving/renaming a feature.
# Without FEATURE it covers custom-tests too, the folder for a customer's own tests, when present.
KARATE_TARGET := $(if $(FEATURE),$(FEATURE),src/test/java/iomete/tests $(wildcard custom-tests))
KARATE_FILTER := $(if $(TAGS),--tags \"$(TAGS)\",)$(if $(NAME), --name \"$(NAME)\",)
# OUTPUT sends the Karate report elsewhere, so a re-run can keep the first run's report
KARATE_OUTPUT := $(if $(OUTPUT),--output $(OUTPUT),)

test-one:
	./mvnw -B test -Dkarate.options="$(KARATE_OUTPUT) $(KARATE_FILTER) $(KARATE_TARGET)"

# Stop every compute in the test domain, so a finished run releases cluster capacity instead
# of waiting out the 1800s idle timeout. Run it after any suite run, failed ones included.
# Stops, not deletes, so the next run still reuses the computes via 409. --output keeps this
# run's report out of target/karate-reports, where it would overwrite the suite's own.
stop-computes:
	./mvnw -B test -Diomete.teardown=true -Dkarate.options="--output target/karate-teardown src/test/java/iomete/helpers/compute/stop-domain-computes.feature"

# Stop every streaming job in the suite's domains, whichever run started it. A streaming job never
# ends on its own, so one a cancelled run left keeps its pods until something stops it.
stop-streaming-jobs:
	./mvnw -B test -Diomete.teardown=true -Dkarate.options="--output target/karate-teardown src/test/java/iomete/helpers/job/stop-domain-streaming-jobs.feature"

# Delete the fixtures this run OWNS, the ones listed in karate-config.js. Everything else a
# scenario creates it deletes itself. Safe after any suite run; it names its targets exactly,
# so it cannot touch another run's data or the shared computes.
cleanup-run:
	./mvnw -B test -Dkarate.options="--output target/karate-teardown src/test/java/iomete/helpers/cleanup-run-fixtures.feature"

# Delete every compute and Jupyter container one run created (names ending in -<runId>), for after a cancelled run.
#   make cleanup-run-computes                                          # the last local run
#   make cleanup-run-computes GITHUB_RUN_ID=12345 GITHUB_RUN_ATTEMPT=1 # a CI run
cleanup-run-computes:
	./mvnw -B test -Dkarate.options="--output target/karate-teardown src/test/java/iomete/helpers/compute/delete-run-computes.feature"

# Delete the run's domain and everything still running in it, then list what stays behind.
# Last, after cleanup-run and cleanup-run-computes.
cleanup-run-domain:
	./mvnw -B test -Diomete.teardown=true -Dkarate.options="--output target/karate-teardown src/test/java/iomete/helpers/cleanup-run-domain.feature"

# Remove everything the last run created, in the order the steps need.
cleanup:
	-$(MAKE) cleanup-run
	-$(MAKE) cleanup-run-computes
	$(MAKE) cleanup-run-domain

clean:
	./mvnw -B clean

report:
	open target/karate-reports/karate-summary.html

# Optional extra targets, when an internal.mk is present
-include internal.mk
