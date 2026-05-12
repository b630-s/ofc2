# Two-Iteration Platform Roadmap

## Purpose

This document converts the current repository state, our architecture rules, and the most relevant DoEKS learnings into a practical two-iteration implementation roadmap.

The intent is:

- keep the prototype low-cost in infrastructure sizing
- keep the architecture and code production-style
- preserve portability and sovereignty goals
- make explicit what we should do now versus what should wait until the second iteration

This document is meant to be reviewable by other assistants and engineers, including Claude.

## Non-Negotiable Principles

These principles apply across both iterations:

1. Small hardware is acceptable.
   Low replica counts, smaller disks, and smaller node sizes are allowed to save cost.

2. Small architecture is not acceptable.
   Packaging, security boundaries, observability, deployment structure, and rerun safety should still aim at production quality.

3. Kubernetes remains the platform control surface.
   Workloads should continue to target Kubernetes-native operators and APIs.

4. Cloud coupling stays below the workload and platform contract where possible.
   AWS-specific details should be isolated to infrastructure adapters, storage connectors, and identity wiring, not embedded in business logic.

5. Platform and workload ownership must stay separate.
   Shared capabilities belong in the platform layer. Application logic and reference app assets belong in the workload layer.

## Current State Summary

What is already in place:

- AWS prototype infrastructure on EKS with `core` and `workload` managed node groups
- Spark Operator
- Airflow
- Strimzi operator
- Polaris
- Prometheus and Grafana
- IRSA-based runtime identity for Spark, Airflow, and Polaris
- reference Kafka cluster and topics scripted in `reference-workloads/`
- initial Polaris bootstrap script
- initial Spark batch and streaming templates
- initial Airflow DAG templates

What is not yet production-grade:

- Spark runtime packaging
- DAG delivery and bundle lifecycle
- Spark event log and metrics configuration
- Spark History Server decision and deployment
- Airflow remote logging decision and implementation
- workload-level validation scripts
- production-style reference app packaging and deployment
- multi-tenant workload isolation and governance

Known current simplifications to document honestly:

- several manifests still hardcode AWS `gp2` storage classes; this is acceptable in Iteration 1 but should be cleaned up or standardized later
- Flink is intentionally deferred; the repo should not imply a Flink namespace or runtime exists until Flink is actually scoped

## What We Learned From DoEKS

The most useful DoEKS practices for our situation are:

- co-located Airflow DAG bundles and SparkApplication manifests
- explicit workload versus platform scheduling
- native Spark Prometheus metrics export
- Spark event logs in object storage
- Spark History Server for post-run analysis
- explicit handling of Spark local/shuffle storage as an architecture topic
- production-style deployment packaging and artifact management

The DoEKS practices we should defer for now are:

- Karpenter as a required dependency
- YuniKorn as a required dependency
- spot-driven scheduling strategies
- large production resource footprints
- aggressive storage sizing patterns copied directly from their examples

## Iteration Model

This roadmap assumes only two implementation iterations:

- **Iteration 1**
  Build a production-style single-tenant or reference-tenant platform and reference app on minimal hardware.

- **Iteration 2**
  Add multi-tenancy, stronger governance, stronger scheduling/isolation, and platform hardening after the single-tenant/reference path is proven.

## Iteration 1 Goals

Iteration 1 should prove the platform and reference workload architecture end to end while keeping the infrastructure small.

Success criteria:

- platform deploys and validates repeatably
- reference Kafka works
- Polaris bootstrap works repeatably
- Spark batch and streaming reference workloads are actually runnable
- Airflow can orchestrate the batch path cleanly
- Spark and Airflow observability are usable
- the reference app looks like a real deployable unit, not scattered sample files

## Iteration 1 Work Items

### A. Infrastructure And Storage Hygiene

1. Make node root volume configuration explicit in infra.

Do:

- explicitly choose root volume type, likely `gp3`
- keep size configurable per node group
- keep the design ready for future tuning of throughput/IOPS if needed

Why:

- production-style infrastructure should not rely on hidden defaults
- DoEKS patterns reinforced that root storage matters, especially if Spark uses node-local storage later

2. Keep `core` and `workload` node groups as the primary scheduling boundary.

Do:

- continue pinning platform services to `core`
- continue pinning workload-owned pods to `workload`

Why:

- this is already a good production-style boundary in our repo
- it aligns with both our goals and the useful parts of DoEKS

### B. Platform Layer Hardening

3. Decide whether Spark History Server belongs in the platform baseline now or as a near-term platform extension.

Recommendation:

- treat it as a platform component, even if enabled after the first runnable Spark validation

Why:

- it is shared observability infrastructure, not app-specific logic

4. Define the Airflow log destination architecture.

Iteration 1 posture:

- use remote logging to S3
- do not make CloudWatch the primary design, because S3 is a better fit for our current portability goals and existing bucket/IRSA model

5. Define the Airflow Kubernetes connection model.

Do:

- use `kubernetes_default`
- use in-cluster configuration
- automate or at least document the setup clearly

Why:

- production-style DAG execution should not depend on ambiguous manual runtime assumptions

6. Do a first-pass least-privilege review for workload roles.

Review:

- Spark role
- Airflow role
- Polaris role

Do:

- scope permissions to the actual bucket prefixes and AWS actions needed for Iteration 1
- leave deeper governance and multi-tenant refinements for Iteration 2

Why:

- production-style architecture should not rely on broad convenience permissions even in the first iteration

### C. Polaris Hardening

7. Validate and stabilize `platform/scripts/03-5-bootstrap-polaris-reference.sh`.

Do:

- test the rerun-safe flow against the live platform
- confirm the exact CLI commands and outputs with the installed Polaris version
- confirm how principal credentials should be stored and reused after initial creation

Why:

- Polaris bootstrap is now one of the most important platform-to-workload handoff points

Note:

- the earlier syntax bug concern has already been resolved in the current script; the remaining work is live validation and operationalization

8. Define secret handling for Polaris principals.

Iteration 1 posture:

- store `POLARIS_USER_CLIENT_ID` and `POLARIS_USER_CLIENT_SECRET` in a Kubernetes Secret in the `spark` namespace
- inject them into Spark runtime through the deployment path
- do not leave them as ephemeral copy-paste outputs only

Iteration 2:

- move toward stronger secret lifecycle and rotation if needed

### D. Reference App Packaging

9. Restructure the Spark + Airflow reference flow into a production-style reference app unit.

Goal:

- one reference app should look like a coherent deployable unit

Likely shape:

- `reference-workloads/orders-reference/`
  - DAGs
  - SparkApplication YAMLs
  - Spark job code
  - local README
  - any app-level config

Keep Kafka cluster/topic assets separate if they remain a shared reference service layer.

Why:

- this is closer to a real application boundary
- it keeps bundle assumptions and app ownership clean

Iteration 1 note:

- this restructure is useful, but it is not the main success criterion for Iteration 1
- if the runtime and deploy path become truly runnable first, that still counts as Iteration 1 success even if the final folder cleanup lands later

10. Finalize the DAG bundle model.

Iteration 1 posture:

- at one point DAG files and SparkApplication manifests were co-located in `reference-workloads/airflow/`; the repo now separates them by use case and runtime responsibility
- that co-located bundle model is the chosen Iteration 1 approach, not an open question

Still document clearly:

- how the bundle reaches the Airflow runtime
- whether the runtime delivery is image-baked, Git-synced, or otherwise packaged

11. Keep ConfigMap-mounted Spark job code as a temporary Iteration 1 bridge only.

Iteration 1 posture:

- allow `deps.packages` plus ConfigMap-mounted reference job code so we can get the first runnable path working
- document the limitations clearly

Iteration 2 target:

- replace this with a stronger packaging model such as a custom Spark image or packaged artifact delivery

### E. Spark Runtime And Workload Execution

12. Define the Spark event log prefix before the first full runtime validation.

Recommendation:

- choose a clear path in the shared bucket, such as:
  - `s3a://dc-platform-bss-proto-lakehouse-7901580-us-east-1/reference/spark-event-logs/`

13. Add explicit Spark observability configuration into the SparkApplication templates before the first full runtime validation.

Adopt from DoEKS:

- `spark.ui.prometheus.enabled=true`
- `spark.executor.processTreeMetrics.enabled=true`
- native Prometheus servlet sink config
- event log config
- rolling and compression settings where appropriate

Why:

- the first validated runtime should already include the observability and event-log posture we intend to keep

14. Validate and standardize the Spark runtime packaging strategy.

Do:

- decide the actual Spark image
- validate Python support
- validate Iceberg dependencies
- validate Polaris REST catalog integration
- validate IRSA-based S3 access

Why:

- this is currently the main blocker between "good template" and "runnable reference"

Iteration 1 note:

- do not make a custom Spark image a hard requirement for Iteration 1 success
- validate the runtime first using the current simpler delivery model
- treat custom image strategy as an Iteration 2 hardening move unless Iteration 1 proves it is unavoidable

15. Improve Spark portability by externalizing more configuration.

Do:

- remove or minimize hardcoded storage paths from Python job code
- pass input paths, checkpoint paths, and output table names as arguments or config

Why:

- keeps business logic portable
- keeps cloud specifics in deployment config rather than in transformation code

16. Decide the initial Spark local/shuffle storage posture.

Iteration 1 recommendation:

- acknowledge explicit local/shuffle storage as a real architecture concern
- do not yet implement the full DoEKS PVC-reuse pattern until the runtime is validated

Document:

- current simplification
- future preferred pattern

Preferred future default:

- PVC-backed local/shuffle storage

Optional later optimization:

- node-shared storage for trusted/cost-sensitive workloads

### F. Airflow Workflow Quality

17. Keep the Airflow submit-plus-monitor pattern as the target, but do not make it a hard Iteration 1 blocker if Airflow 3.1.x operator limitations get in the way.

Do:

- keep `SparkKubernetesOperator`
- add `SparkKubernetesSensor` or equivalent monitoring step when compatible

Why:

- this matches a production-style orchestration pattern better than fire-and-forget

18. Add at least one simple validation step after the batch workflow.

Examples:

- confirm SparkApplication completed successfully
- confirm the target Iceberg table exists
- confirm expected output rows are present

### G. Observability

19. Define the full reference observability workflow.

For Spark:

- live Spark UI
- Spark History Server
- Prometheus metrics
- Grafana visibility
- event logs in S3

For Airflow:

- DAG run status
- task logs
- remote logs if chosen

For Kafka:

- cluster readiness
- topic existence
- broker/controller health

20. Add workload-level validation or smoke-test scripts.

Needed examples:

- validate Kafka cluster and topics
- validate Polaris catalog and namespaces
- validate SparkApplication creation and completion
- validate DAG bundle presence or DAG registration

### H. Docs And Operator Experience

21. Add script linting and manifest validation into the first iteration.

Examples:

- shell linting for Bash scripts
- YAML validation or `kubectl` dry-run where practical

Why:

- this is small effort with immediate payoff
- it helps catch the exact class of bootstrap and manifest errors that slow down the first runnable path

22. Replace "template-only" ambiguity with honest operator docs.

Do:

- clearly mark which assets are runnable now
- clearly mark which remain templates
- document all required prerequisites and secret inputs

23. Update the handoff and workload docs after each major improvement.

Especially:

- `docs/platform-handoff.md`
- `docs/workload-reference.md`
- reference app README files

## Iteration 1 Deliverables

Iteration 1 should end with:

- platform deploy/validate working cleanly
- reference Kafka cluster deployed and validated
- Polaris bootstrap rerun-safe and proven
- one coherently deployed reference app with honest Iteration 1 packaging tradeoffs documented
- one runnable batch Spark path
- one runnable streaming Spark path
- one Airflow DAG bundle that submits the batch path cleanly, with monitoring added where the operator/runtime combination supports it reliably
- Spark metrics and event logging configured
- clear operator docs for deploy, validate, troubleshoot

## Iteration 2 Goals

Iteration 2 introduces multi-tenancy and shared-platform hardening after the reference path is proven.

Success criteria:

- multiple team or project workload boundaries are supported
- scheduling, quotas, and observability are ready for more than one logical tenant
- security and governance are stronger
- platform becomes a reusable shared internal service rather than just a proven reference baseline

## Iteration 2 Work Items

### A. Multi-Tenant Platform Structure

1. Define multi-tenant namespace and ownership strategy.

Decide:

- per-team namespaces
- per-project namespaces
- shared service namespaces versus tenant namespaces

2. Introduce queueing and scheduling governance for shared compute.

Potential candidates:

- YuniKorn later for queueing and gang scheduling
- stronger scheduler annotations and queue design

Do not introduce this until after the base Spark runtime is stable.

3. Define resource quotas, limits, and fairness model.

Examples:

- CPU/memory quotas per tenant
- storage limits
- per-team queue guarantees later

### B. Security And Credential Lifecycle

4. Move Polaris principal and other workload secrets toward a stronger lifecycle.

Examples:

- better secret storage
- rotation strategy
- separation of admin bootstrap credentials from app runtime credentials

### C. Scheduling And Compute Evolution

5. Decide whether to introduce Karpenter in the second iteration.

Adopt later if:

- workload elasticity matters
- cost/performance tuning matters more
- we want scale-to-zero or instance-family-aware scheduling

6. Decide whether to introduce YuniKorn in the second iteration.

Adopt later if:

- shared Spark workloads begin contending
- multi-pod batch deadlock risks appear
- queue fairness and gang scheduling become important

7. Add production-style Spark local/shuffle storage patterns.

Recommended default:

- PVC-backed local/shuffle storage for stronger isolation and recovery

Optional profile:

- node-shared storage for trusted cost-sensitive workloads

### D. Observability And Operations

8. Add workload-specific Grafana dashboards and alerting.

Do:

- formalize key Spark panels
- formalize Kafka health dashboards
- formalize Airflow operational dashboards

9. Add alerting rules for critical workload and platform failure modes.

Examples:

- Spark job failures
- stalled Kafka brokers
- Airflow scheduler issues
- Polaris service errors

10. Add better auditability and post-mortem support.

Examples:

- clearer event log retention policy
- Airflow log retention policy
- operational runbooks

### E. Delivery And Promotion

11. Decide whether to adopt GitOps in iteration 2.

Potential fit:

- ArgoCD for platform and workload promotion

Adopt only if it simplifies repeatability rather than adding unneeded complexity.

12. Add CI/CD for reference apps and platform validation.

Needed:

- manifest validation
- script linting
- runtime smoke tests where possible

## Out Of Scope For Both Iterations Unless Needed

The following should not automatically be pulled in unless they become necessary:

- copying full DoEKS Karpenter architecture wholesale
- copying full DoEKS YuniKorn architecture wholesale
- very large production storage sizes
- spot-heavy scheduling before our workload model is mature
- premature multi-cloud implementation before the AWS reference path is production-style and stable

## Review Checklist For Claude

When reviewing this roadmap, ask Claude specifically to evaluate:

1. Whether the iteration split is sensible
2. Whether any "Iteration 2" item should actually move into Iteration 1
3. Whether any "Iteration 1" item is too ambitious for the first production-style pass
4. Whether the platform/workload boundary is clean enough
5. Whether the portability stance is realistic
6. Whether the Spark packaging and observability priorities are in the right order
7. Whether the Airflow bundle and logging recommendations are solid
8. Whether the Polaris bootstrap and secret lifecycle recommendations are strong enough
9. Whether the storage and scheduling recommendations are balanced correctly for our goals

## Recommended Immediate Focus

If we continue from the current repo state without trying to do everything at once, the best immediate subset is:

1. stabilize Polaris bootstrap operationally
2. add Spark event log and Prometheus observability config before first full runtime validation
3. validate the Spark runtime and Polaris integration using the current Iteration 1 packaging bridge
4. decide the Airflow DAG bundle and log delivery model
5. turn one reference app into a truly runnable end-to-end path

That keeps us aligned with the architecture while still making steady progress.
