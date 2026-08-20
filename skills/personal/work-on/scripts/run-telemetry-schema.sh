# Shared schema contract for every production telemetry caller.
readonly work_on_telemetry_schema_version=3
readonly work_on_telemetry_integrity_state=valid
readonly work_on_telemetry_run_value_pattern="^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8} \\(schema ${work_on_telemetry_schema_version}, integrity ${work_on_telemetry_integrity_state}\\)$"
