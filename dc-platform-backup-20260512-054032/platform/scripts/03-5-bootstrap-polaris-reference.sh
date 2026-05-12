#!/usr/bin/env bash

set -euo pipefail

POLARIS_HOST="${POLARIS_HOST:-polaris.polaris.svc.cluster.local}"
POLARIS_PORT="${POLARIS_PORT:-8181}"
POLARIS_ADMIN_CLIENT_ID="${POLARIS_ADMIN_CLIENT_ID:-}"
POLARIS_ADMIN_CLIENT_SECRET="${POLARIS_ADMIN_CLIENT_SECRET:-}"
POLARIS_ROLE_ARN="${POLARIS_ROLE_ARN:-}"
REFERENCE_BUCKET="${REFERENCE_BUCKET:-dc-platform-bss-proto-lakehouse-7901580-us-east-1}"
REFERENCE_CATALOG="${REFERENCE_CATALOG:-reference}"
REFERENCE_BASE_LOCATION="${REFERENCE_BASE_LOCATION:-s3://${REFERENCE_BUCKET}/reference/}"
REFERENCE_PRINCIPAL="${REFERENCE_PRINCIPAL:-reference_spark_user}"
REFERENCE_PRINCIPAL_ROLE="${REFERENCE_PRINCIPAL_ROLE:-reference_spark_role}"
REFERENCE_CATALOG_ROLE="${REFERENCE_CATALOG_ROLE:-reference_catalog_role}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

log() {
  printf '[platform-polaris] %s\n' "$*"
}

preflight() {
  require_cmd polaris
  require_cmd jq

  if [[ -z "${POLARIS_ADMIN_CLIENT_ID}" || -z "${POLARIS_ADMIN_CLIENT_SECRET}" ]]; then
    echo "Set POLARIS_ADMIN_CLIENT_ID and POLARIS_ADMIN_CLIENT_SECRET before running this script." >&2
    exit 1
  fi

  if [[ -z "${POLARIS_ROLE_ARN}" ]]; then
    echo "Set POLARIS_ROLE_ARN to the IRSA-backed S3 role Polaris should vend for this catalog." >&2
    exit 1
  fi
}

polaris_cli() {
  polaris \
    --host "${POLARIS_HOST}" \
    --port "${POLARIS_PORT}" \
    --client-id "${POLARIS_ADMIN_CLIENT_ID}" \
    --client-secret "${POLARIS_ADMIN_CLIENT_SECRET}" \
    "$@"
}

catalog_exists() { polaris_cli catalogs get "${REFERENCE_CATALOG}" >/dev/null 2>&1; }
principal_exists() { polaris_cli principals get "${REFERENCE_PRINCIPAL}" >/dev/null 2>&1; }
principal_role_exists() { polaris_cli principal-roles get "${REFERENCE_PRINCIPAL_ROLE}" >/dev/null 2>&1; }
catalog_role_exists() { polaris_cli catalog-roles get --catalog "${REFERENCE_CATALOG}" "${REFERENCE_CATALOG_ROLE}" >/dev/null 2>&1; }
namespace_exists() {
  local namespace="$1"
  polaris_cli namespaces get --catalog "${REFERENCE_CATALOG}" "${namespace}" >/dev/null 2>&1
}
principal_has_role() {
  polaris_cli principal-roles list --principal "${REFERENCE_PRINCIPAL}" 2>/dev/null | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"${REFERENCE_PRINCIPAL_ROLE}\""
}
catalog_role_granted_to_principal_role() {
  polaris_cli catalog-roles list --catalog "${REFERENCE_CATALOG}" --principal-role "${REFERENCE_PRINCIPAL_ROLE}" 2>/dev/null | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"${REFERENCE_CATALOG_ROLE}\""
}
catalog_privilege_exists() {
  local privilege="$1"
  polaris_cli privileges list --catalog "${REFERENCE_CATALOG}" --catalog-role "${REFERENCE_CATALOG_ROLE}" 2>/dev/null | grep -q "\"privilege\"[[:space:]]*:[[:space:]]*\"${privilege}\""
}

main() {
  preflight

  principal_json=""

  if catalog_exists; then
    log "Catalog ${REFERENCE_CATALOG} already exists; leaving it in place"
  else
    log "Creating Polaris catalog ${REFERENCE_CATALOG}"
    polaris_cli catalogs create \
      --storage-type s3 \
      --default-base-location "${REFERENCE_BASE_LOCATION}" \
      --role-arn "${POLARIS_ROLE_ARN}" \
      "${REFERENCE_CATALOG}"
  fi

  if principal_exists; then
    log "Principal ${REFERENCE_PRINCIPAL} already exists; reusing it"
  else
    log "Creating reference principal ${REFERENCE_PRINCIPAL}"
    principal_json="$(polaris_cli principals create "${REFERENCE_PRINCIPAL}")"
  fi

  if principal_role_exists; then
    log "Principal role ${REFERENCE_PRINCIPAL_ROLE} already exists"
  else
    log "Creating principal role ${REFERENCE_PRINCIPAL_ROLE}"
    polaris_cli principal-roles create "${REFERENCE_PRINCIPAL_ROLE}"
  fi

  if catalog_role_exists; then
    log "Catalog role ${REFERENCE_CATALOG_ROLE} already exists in ${REFERENCE_CATALOG}"
  else
    log "Creating catalog role ${REFERENCE_CATALOG_ROLE}"
    polaris_cli catalog-roles create --catalog "${REFERENCE_CATALOG}" "${REFERENCE_CATALOG_ROLE}"
  fi

  if principal_has_role; then
    log "Principal ${REFERENCE_PRINCIPAL} already has role ${REFERENCE_PRINCIPAL_ROLE}"
  else
    log "Granting principal role ${REFERENCE_PRINCIPAL_ROLE} to ${REFERENCE_PRINCIPAL}"
    polaris_cli principal-roles grant --principal "${REFERENCE_PRINCIPAL}" "${REFERENCE_PRINCIPAL_ROLE}"
  fi

  if catalog_role_granted_to_principal_role; then
    log "Catalog role ${REFERENCE_CATALOG_ROLE} is already granted to principal role ${REFERENCE_PRINCIPAL_ROLE}"
  else
    log "Granting catalog role ${REFERENCE_CATALOG_ROLE} to principal role ${REFERENCE_PRINCIPAL_ROLE}"
    polaris_cli catalog-roles grant --catalog "${REFERENCE_CATALOG}" --principal-role "${REFERENCE_PRINCIPAL_ROLE}" "${REFERENCE_CATALOG_ROLE}"
  fi

  if catalog_privilege_exists "CATALOG_MANAGE_CONTENT"; then
    log "CATALOG_MANAGE_CONTENT already granted on ${REFERENCE_CATALOG}"
  else
    log "Granting CATALOG_MANAGE_CONTENT on ${REFERENCE_CATALOG}"
    polaris_cli privileges catalog grant --catalog "${REFERENCE_CATALOG}" --catalog-role "${REFERENCE_CATALOG_ROLE}" CATALOG_MANAGE_CONTENT
  fi

  for namespace in bronze silver; do
    if namespace_exists "${namespace}"; then
      log "Namespace ${namespace} already exists"
    else
      log "Creating namespace ${namespace}"
      polaris_cli namespaces create --catalog "${REFERENCE_CATALOG}" "${namespace}"
    fi
  done

  if [[ -n "${principal_json}" && "${principal_json}" == *clientId* ]]; then
    user_client_id="$(printf '%s' "${principal_json}" | jq -r '.clientId // empty')"
    user_client_secret="$(printf '%s' "${principal_json}" | jq -r '.clientSecret // empty')"
    if [[ -n "${user_client_id}" && -n "${user_client_secret}" ]]; then
      echo
      echo "Reference principal credentials created."
      echo "Export these before rendering the SparkApplication templates:"
      echo "export POLARIS_USER_CLIENT_ID=${user_client_id}"
      echo "export POLARIS_USER_CLIENT_SECRET=${user_client_secret}"
    fi
  else
    echo
    echo "No new principal credentials were captured."
    echo "If the principal already existed, reuse the existing reference principal credentials."
  fi

  echo
  echo "Polaris bootstrap slice completed."
  echo "Catalog: ${REFERENCE_CATALOG}"
  echo "Base location: ${REFERENCE_BASE_LOCATION}"
  echo "Namespaces: bronze, silver"
}

main "$@"
