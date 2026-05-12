# To-Do List

This document is the single consolidated working to-do list for the current repository.

Use it as the primary source of truth for implementation sequencing and backlog triage. Older notes in other docs remain useful for context, but this file is the place to track what still needs to happen.

## Current Iteration / Phase

These items are the most important work to complete in the current repo phase.

1. Re-run the infra and platform baseline cleanly in WSL and confirm the current deployment order still works end to end.
2. Re-validate Kafka as the first live-tested reference workload step.
3. Validate and operationalize `platform/scripts/03-5-bootstrap-polaris-reference.sh` against the deployed Polaris version.
4. Confirm the exact source of Polaris admin bootstrap credentials and document the real secret names and keys used in-cluster.
5. Standardize how Spark runtime Polaris credentials are stored in Kubernetes after bootstrap.
6. Make the Spark runtime secret flow explicit:
   - bootstrap creates or returns Spark principal credentials
   - credentials are stored in a Kubernetes Secret in namespace `spark`
   - Spark runtime consumes that secret without ad hoc copy-paste
7. Validate the staged orders Spark path end to end with:
   - Polaris catalog access
   - Iceberg REST catalog configuration
   - IRSA-based S3 access
   - successful table creation and writes
8. Harden the Spark batch deployment path operationally:
   - wait for terminal `SparkApplication` status
   - fail clearly on runtime errors
   - collect useful troubleshooting output
9. Keep the current Spark reference path honest as a runnable reference, not a production-ready claim, until the packaging and secret model are hardened.
10. Document the Polaris / Spark / Airflow runtime flow and handoff points clearly wherever operators will look first.

### Authentication And Security Refinements Needed In Current Iteration

1. Separate Polaris bootstrap credentials from Spark runtime credentials clearly in docs and deployment flow.
2. Stop treating Polaris principal credentials as ephemeral terminal output only; store and reuse them through Kubernetes secrets.
3. Remove ambiguity around who authenticates to whom:
   - admin credentials are for Polaris bootstrap only
   - Spark principal credentials are for runtime catalog access
   - Airflow orchestrates but does not act as the table-access identity
4. Review whether Spark principal credentials are being exposed too broadly through rendered manifests and tighten that path.
5. Confirm the intended use of `POLARIS_ROLE_ARN` as the backing storage access role for Polaris-managed catalogs.
6. Verify current IAM role scope and bucket-prefix scope are limited to what the prototype actually needs.
7. Keep IRSA as the standard cloud access path for Spark, Airflow, and Polaris.

## Next Iteration

These items should follow once the current reference path is truly runnable and understood.

1. Replace the current prototype-grade Spark packaging approach with a stronger runtime packaging model.
2. Decide and standardize the real Spark image strategy:
   - repo-owned image
   - pinned dependencies
   - validated Python support
   - validated Iceberg and Polaris dependencies
3. Move away from ConfigMap-mounted Spark job code as the long-term delivery mechanism.
4. Restructure the reference app into a more coherent application unit, likely centered around a single reference workload package instead of scattered assets.
5. Finalize the Airflow DAG bundle delivery model and document how DAGs and SparkApplication specs reach the runtime.
6. Externalize hardcoded Spark configuration such as:
   - input paths
   - output table names
   - event log locations
   - checkpoint paths
   - image references
7. Add Spark History Server once the Spark image and event-log access path are properly standardized.
8. Improve secret lifecycle and rotation posture for Polaris runtime principals.
9. Tighten production-style observability around Spark jobs, including better metrics, event-log usability, and failure triage.
10. Validate Spark streaming and Airflow orchestration after the batch path is stable.

### Authentication And Security Refinements For Next Iteration

1. Move away from manifest-time secret interpolation where practical.
2. Use stronger secret injection patterns for Spark runtime credentials.
3. Review whether Polaris principal credentials should be rotated or regenerated on a defined lifecycle.
4. Narrow IAM permissions further from broad prototype defaults toward workload-specific least privilege.
5. Review whether Polaris internal authentication is sufficient for the intended environments or should be replaced with a stronger managed auth model later.

## Future Work

These items are explicitly out beyond the next iteration, but they are worth keeping visible.

1. Add Karpenter-based node provisioning if we want more dynamic workload scaling and cleaner capacity management.
2. Revisit broader multi-tenant isolation and governance once the core reference path is stable.
3. Revisit stronger production secret management patterns beyond namespace-local Kubernetes secrets.
4. Add a more durable production-grade Spark history, lineage, and runtime debugging posture.
5. Expand reference workloads beyond the first orders path once the current data path is stable.
6. Revisit whether Flink should be introduced on top of the same Iceberg, Polaris, and Kafka foundations.
7. Improve platform portability decisions for non-AWS targets after the AWS prototype path is operationally solid.
8. Revisit ingress and external exposure decisions for internal services such as Airflow, Polaris, and future history tooling.

## Notes

- `docs/codex-project-context.md` and `docs/two-iteration-platform-roadmap.md` still contain useful rationale and supporting detail.
- This file is intended to be the concise action-oriented list.
