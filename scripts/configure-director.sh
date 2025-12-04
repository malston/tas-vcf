#!/usr/bin/env bash
# ABOUTME: Configures BOSH Director using om CLI with interpolated vars
# ABOUTME: This script applies director configuration to Ops Manager

set -e

vars_files_args=("")
for vf in ${VARS_FILES}; do
  if [[ -f ${vf} ]]; then
    vars_files_args+=("--vars-file ${vf}")
  fi
done

ops_files_args=("")
for of in ${OPS_FILES}; do
  ops_files_args+=("--ops-file ${of}")
done

# shellcheck disable=SC2068
om --env "${ENV_FILE}" interpolate \
  --config "${DIRECTOR_CONFIG_FILE}" \
  ${vars_files_args[@]}

# ${vars_files_args[@] needs to be globbed to pass through properly
# ${ops_files_args[@] needs to be globbed to pass through properly
# shellcheck disable=SC2068
om --env "${ENV_FILE}" configure-director \
  --config "${DIRECTOR_CONFIG_FILE}" \
  ${vars_files_args[@]} \
  ${ops_files_args[@]}
