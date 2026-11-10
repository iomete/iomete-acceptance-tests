@ignore
Feature: Create (or reuse) a Spark job definition (plumbing).
  Building block for tests that need a real Spark application — call it with:
    def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: 'my-job' })
  and read job.jobId. Pass sparkVersion to pick a different image tag, or dataPlane to target a
  specific data plane instead of the default:
    def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: 'my-job', dataPlane: 'dp-1' })
  Without an explicit dataPlane, the run's data-plane STRATEGY decides (dataPlaneFor in
  karate-config.js); an explicit caller argument always wins. The reused-job update below
  pushes the resolved plane too, so a job left behind on another plane gets moved, not reused
  where it happens to sit.

  Pass jobType: 'SCHEDULED' with a cron schedule (and optionally concurrency) for a scheduled
  job. The API rejects a schedule on a job that is not scheduled, so both are only sent when given.
  A reused scheduled job comes back resumed: a suspended schedule never fires.

  Runs the SparkPi example from inside the image, so the job finishes in seconds once the
  driver is up. Callers delete the job when they are done with it.

  Pass jobApi (default 'v1'): 'v2' to create and update it through the V2 API the console uses,
  'sdk' for the V2 SDK API customers' scripts use, or 'streaming' for a streaming job (its own
  V2 resource; the server forces jobType STREAMING and no run limit),
  and jobFlow: 'PRIORITY' to queue its runs through the job orchestrator as the console's
  form does (default: none sent, which the platform reads as LEGACY).

  Pass jobTemplate to run another application instead (a marketplace template, say). Its node
  types, restart policy and run limit are replaced with the suite's own. For such an application,
  jobDriverType asks for a bigger driver than karate-xs, jobSingleNode runs it on the driver
  alone, and jobMaxDurationSeconds shortens the 1800s run limit. The inputs carry a job prefix
  because karate.get also sees the caller's variables.

  Scenario: create the job if it is missing, then return its id
    # a rebuilt environment has no domain yet, and every call below needs one
    * karate.callSingle('classpath:iomete/helpers/domain/ensure-domain.feature', { domain: domain })

    * def jobApi = karate.get('jobApi', 'v1')
    * def jobFlow = karate.get('jobFlow', null)
    * def jobsPath = jobApi == 'streaming' ? 'api/v2/domains/' + domain + '/spark/streaming/jobs' : jobApi == 'sdk' ? 'api/v2/domains/' + domain + '/sdk/spark/jobs' : 'api/' + jobApi + '/domains/' + domain + '/spark/jobs'
    # use the run's sparkImage from config unless the caller explicitly passes sparkVersion
    * def sparkVersionArg = karate.get('sparkVersion', null)
    # a streaming job's type is fixed; the server forces it anyway
    * def jobType = jobApi == 'streaming' ? 'STREAMING' : karate.get('jobType', 'MANUAL')
    * def schedule = karate.get('schedule', null)
    * def concurrency = karate.get('concurrency', null)
    # an explicit dataPlane wins; otherwise the run's strategy assigns one (null under 'local')
    * def explicitDataPlane = karate.get('dataPlane')
    * def targetDataPlane = explicitDataPlane ? explicitDataPlane : dataPlaneFor(name)
    * if (targetDataPlane && !explicitDataPlane) karate.log('data-plane strategy "' + dataPlaneStrategy + '" places job ' + name + ' on data plane ' + targetDataPlane)
    * def customTemplate = karate.get('jobTemplate', null)
    * def driverPreference = karate.get('jobDriverType', 'karate-xs')
    * def singleNode = karate.get('jobSingleNode', false)
    * def maxDurationSeconds = karate.get('jobMaxDurationSeconds', '1800')

    # deployment namespace: prefer a dedicated spark namespace, fall back to the system one.
    # The default (no explicit data plane) path is untouched from before this helper knew
    # about data planes at all.
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/namespaces'
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    * def dedicated = response.filter(n => n != 'iomete-system')
    * def jobNamespace = dedicated.length > 0 ? dedicated[0] : response[0]

    # a caller asking for a SPECIFIC data plane needs a namespace that actually belongs to it —
    # v1 above is data-plane-blind, so a namespace name picked from it could silently belong to
    # a different data plane than the one this job is meant to run on. v3 disambiguates.
    Given url baseUrl
    And path 'api/v3/domains/' + domain + '/namespaces'
    And param dataPlane = targetDataPlane
    When method get
    Then status 200
    * if (targetDataPlane && response.length == 0) karate.fail('data plane "' + targetDataPlane + '" has no namespace assigned to domain ' + domain)
    * if (targetDataPlane) jobNamespace = (response.filter(n => n.namespace != 'iomete-system')[0] || response[0]).namespace

    # no target plane: prefer a default-plane namespace — same reason and fallback as
    # create-compute.feature
    * def localNamespaces = targetDataPlane ? [] : response.filter(n => n.dataPlane == 'default' && n.namespace != 'iomete-system')
    * if (!targetDataPlane && localNamespaces.length > 0) jobNamespace = localNamespaces[0].namespace

    # a job is created inside a bundle, and the domain has no default one to fall back on
    Given url baseUrl
    And path 'api/v1/bundles'
    And params { scope: 'OWNED', domain: '#(domain)' }
    When method get
    Then status 200
    * def bundle = response.items[0]
    And match bundle == '#notnull'

    # the job runs as a real platform user, so resolve whoever the token belongs to
    Given url baseUrl
    And path 'api/v1/user'
    When method get
    Then status 200
    * def jobUser = response.id
    * def jobSparkImage = sparkVersionArg ? imageRef('spark-py:' + sparkVersionArg) : sparkImage

    # SparkPi fits the suite's smallest type, or the smallest this environment has
    * def picked = karate.call('classpath:iomete/helpers/compute/pick-node-types.feature', { preferredDriver: driverPreference, preferredExecutor: 'karate-xs' })
    * def driverNodeType = picked.driverNodeType
    * def executorNodeType = picked.executorNodeType

    # the SDK takes the same body as V2; it only answers in a different shape
    * def createRequest =
      """
      {
        name: '#(name)',
        namespace: '#(jobNamespace)',
        description: 'job for iomete-api-testing-suite, managed by iomete/helpers/job/create-job.feature',
        jobType: '#(jobType)',
        jobUser: '#(jobUser)',
        bundleId: '#(bundle.bundleId)',
        template: {
          image: '#(jobSparkImage)',
          mainApplicationFile: 'local:///opt/spark/examples/src/main/python/pi.py',
          applicationType: 'python',
          arguments: ['2'],
          restartPolicy: { type: 'Never' },
          instanceConfig: {
            driverType: '#(driverNodeType)',
            executorType: '#(executorNodeType)',
            executorCount: 1,
            singleNodeDeployment: '#(singleNode)'
          },
          maxExecutionDurationSeconds: '#(maxDurationSeconds)'
        }
      }
      """
    # a custom application keeps the suite's sizing and run limit. The marketplace template
    # carries a blank volume id, so leave that out instead of sending it.
    * def withSuiteSettings =
      """
      function(t, suite) {
        t.instanceConfig = suite.instanceConfig;
        t.restartPolicy = suite.restartPolicy;
        t.maxExecutionDurationSeconds = suite.maxExecutionDurationSeconds;
        if (!t.volumeId) delete t.volumeId;
        return t;
      }
      """
    * eval if (customTemplate) createRequest.template = withSuiteSettings(customTemplate, createRequest.template)
    * eval if (schedule != null) createRequest.schedule = schedule
    * eval if (concurrency != null) createRequest.concurrency = concurrency
    * eval if (targetDataPlane) createRequest.dataPlane = targetDataPlane
    * eval if (jobFlow) createRequest.flow = jobFlow
    # a streaming job has no run limit, so none is sent
    * eval if (jobApi == 'streaming') delete createRequest.template.maxExecutionDurationSeconds

    # 409 means a previous run left it behind, which is fine — it gets reused
    Given url baseUrl
    And path jobsPath
    And request createRequest
    When method post
    Then assert responseStatus == 200 || responseStatus == 201 || responseStatus == 409

    # the SDK finds a job by name directly; v1 lists every job; v2 and streaming page them, so
    # those are narrowed to this name
    * def lookupPath = jobApi == 'sdk' ? jobsPath + '/name/' + name : jobsPath
    Given url baseUrl
    And path lookupPath
    And params jobApi == 'v2' || jobApi == 'streaming' ? { search: name, page: 0, size: 100 } : {}
    When method get
    Then status 200
    * def job = jobApi == 'sdk' ? response : (jobApi != 'v1' ? response.items : response).find(j => j.name == name)
    * match job == '#notnull'
    * def jobId = job.id

    # a reused job carries whatever definition it was last created with, so push the current
    # one rather than trusting it
    * def updateRequest =
      """
      {
        namespace: '#(jobNamespace)',
        description: '#(createRequest.description)',
        jobType: '#(jobType)',
        jobUser: '#(jobUser)',
        template: '#(createRequest.template)'
      }
      """
    * eval if (schedule != null) updateRequest.schedule = schedule
    * eval if (concurrency != null) updateRequest.concurrency = concurrency
    * eval if (targetDataPlane) updateRequest.dataPlane = targetDataPlane
    * eval if (jobFlow) updateRequest.flow = jobFlow

    Given url baseUrl
    And path jobsPath, jobId
    And request updateRequest
    When method put
    Then status 200

    # an earlier teardown may have left it suspended: the delete is refused while a run is active
    * if (jobType == 'SCHEDULED' && job.suspend) karate.call('classpath:iomete/helpers/job/resume-job.feature', { jobId: jobId })
