# Tile Configuration Comparison Tool - Implementation Specification

**Date:** 2025-12-10
**Author:** Claude & Mark
**Status:** Draft

## Executive Summary

This document specifies a tool to compare Tanzu Application Service (TAS) tile configurations between versions, identifying what configuration changes are required, removed, or recommended when upgrading from one version to another.

### Problem Statement

When upgrading TAS tiles (e.g., from 6.0.22 to 10.2.5), operators need to know:
- What new configuration properties must be set
- What existing properties are no longer supported
- What properties have changed constraints or defaults
- Whether current configuration values remain valid

Currently, this analysis is manual and error-prone, often resulting in missed configurations or runtime failures.

### Solution Overview

A command-line tool that:
1. Extracts property schemas from both old and new tile `.pivotal` files
2. Retrieves current effective configuration from Ops Manager
3. Performs semantic comparison to identify actionable changes
4. Generates a categorized report of required, warning, and informational changes

---

## Data Sources

### 1. Tile Metadata (Property Schema)

**Source:** `.pivotal` file (which is a ZIP archive)
**Location:** `metadata/metadata.yml` within the archive
**Key Section:** `property_blueprints` (top-level, starting around line 8543 in sample)

**Structure:**
```yaml
property_blueprints:
  - name: property_name
    type: string|boolean|integer|selector|rsa_cert_credentials|...
    configurable: true|false
    optional: true|false
    default: <value>
    constraints:
      min: <number>
      max: <number>
    option_templates:  # For selector types
      - name: option_name
        select_value: option_value
        property_blueprints: [...]  # Nested properties
```

**Access Method:**
```bash
unzip -p /path/to/tile.pivotal metadata/metadata.yml > metadata.yml
```

**Key Fields:**
- `name`: Property identifier (e.g., `allow_srt_to_ert_upgrade`)
- `type`: Data type
- `configurable`: Whether user can modify (we focus on `true`)
- `optional`: Whether property is required
- `default`: Default value if not set
- `constraints`: Validation rules (min/max for integers)
- `option_templates`: For selector types, available options with sub-properties

### 2. Current Configuration (Effective Values)

**Source:** Ops Manager API
**Endpoint:** `/api/v0/staged/products/{product_guid}/properties`
**Authentication:** Via `om` CLI with credentials from `.envrc`

**Structure:**
```json
{
  "properties": {
    ".properties.property_name": {
      "type": "boolean",
      "configurable": true,
      "credential": false,
      "value": true,
      "optional": false
    },
    ".properties.selector_property": {
      "type": "selector",
      "configurable": true,
      "value": "option_name",
      "optional": false,
      "selected_option": "option_name"
    }
  }
}
```

**Access Method:**
```bash
source .envrc
PRODUCT_GUID=$(om curl -p /api/v0/staged/products | jq -r '.[] | select(.type=="cf") | .guid')
om curl -p /api/v0/staged/products/${PRODUCT_GUID}/properties > current-config.json
```

**Key Differences from Metadata:**
- Properties prefixed with `.properties.`, `.cloud_controller.`, etc.
- Contains actual `value` (not just schema)
- Shows `credential: true` for sensitive fields (values obscured as `***`)
- For selectors, includes `selected_option`

### 3. Property Path Mapping

**Challenge:** Metadata uses property names (e.g., `allow_srt_to_ert_upgrade`), but API uses full paths (e.g., `.properties.allow_srt_to_ert_upgrade`).

**Solution:** Build path mapping by:
1. Parsing metadata to identify property locations (top-level vs nested in selectors)
2. Constructing full paths based on nesting
3. Matching against API response keys

**Path Patterns:**
- Top-level properties: `.properties.{name}`
- Job-specific properties: `.{job_name}.{name}` (e.g., `.cloud_controller.system_domain`)
- Selector sub-properties: `.properties.{selector_name}.{option_name}.{sub_property_name}`

---

## Comparison Algorithm

### Phase 1: Schema Extraction

**For each tile version (old and new):**

1. Extract metadata.yml from .pivotal file
2. Parse YAML to get `property_blueprints` list
3. For each property blueprint:
   - Build property map: `{name: metadata}`
   - For selectors, recursively process option_templates
   - Track property paths for later matching

**Output:** Two property maps (old_schema, new_schema)

### Phase 2: Current Configuration Parsing

1. Query Ops Manager API for current properties
2. Parse JSON response
3. Build current values map: `{property_path: {metadata, value}}`
4. Identify which properties are explicitly configured (non-default)

**Output:** Current configuration map

### Phase 3: Semantic Comparison

**For each property in new_schema:**

1. **New Property** (not in old_schema):
   - If `configurable: false` → Skip (system-managed)
   - If `configurable: true`:
     - If `optional: false` AND no `default` → **REQUIRED ACTION**
     - If `optional: true` OR has `default` → **INFORMATIONAL** (new optional)
     - Extract description/label from metadata if available

2. **Changed Property** (in both schemas):
   - Compare `type`: If changed → **WARNING** (manual review needed)
   - Compare `constraints`: If stricter (e.g., min increased) → Check current value validity
   - Compare `optional`: If changed from `true` to `false` → **REQUIRED ACTION**
   - Compare `default`: If changed → **INFORMATIONAL**
   - For selectors: Compare option_templates (new/removed options)

**For each property in old_schema:**

3. **Removed Property** (not in new_schema):
   - If `configurable: false` → Skip
   - If `configurable: true`:
     - Check if property is set in current_config
     - If set (non-default) → **WARNING** (will be ignored)
     - If not set → **INFORMATIONAL** (removed but unused)

### Phase 4: Constraint Validation

**For properties in both versions with current values:**

1. Check if current value meets new constraints
2. If constraint violation detected → **WARNING**
3. Examples:
   - Integer min/max changed
   - Allowed values for selector reduced
   - String pattern requirements added

### Phase 5: Report Generation

**Categorize findings:**

1. **🚨 REQUIRED ACTIONS**: Must address before/during upgrade
   - New required properties without defaults
   - Properties that became required (optional: false)
   - Constraint violations with current values

2. **⚠️ WARNINGS**: Should review but may not block
   - Removed properties currently in use
   - Type changes (rare but possible)
   - Selector options removed (if using removed option)

3. **ℹ️ INFORMATIONAL**: Nice to know
   - New optional properties
   - Default value changes
   - Removed unused properties

---

## Output Format

### Option 1: Text Report (Human-Readable)

```
TAS Tile Upgrade Analysis
=========================
Old Version: 6.0.22
New Version: 10.2.5
Analysis Date: 2025-12-10 12:34:56

Current Configuration: cf-85da7fd88e99806e5d08 (staged)
  - Configurable Properties: 422
  - Currently Set: 156

Summary
-------
🚨 Required Actions: 3
⚠️  Warnings: 2
ℹ️  Informational: 15

========================================
🚨 REQUIRED ACTIONS (3)
========================================

1. ADD: .properties.new_security_feature
   Type: boolean
   Default: (none - must be set)
   Description: Enable enhanced security scanning for containers
   Recommendation: Set to 'true' unless you have external scanning

2. ADD: .properties.compliance_mode
   Type: selector
   Options: strict, permissive, disabled
   Default: (none - must be set)
   Description: Compliance enforcement level
   Recommendation: Start with 'permissive' and review logs

3. CONSTRAINT VIOLATION: .properties.autoscale_metric_bucket_count
   Current value: 150
   New constraint: max: 120
   Action: Reduce value to 120 or less

========================================
⚠️  WARNINGS (2)
========================================

1. REMOVED: .properties.legacy_routing_mode
   Current value: "compatibility"
   Impact: Property will be ignored after upgrade
   Action: Review new routing configuration options

2. TYPE CHANGED: .properties.log_retention_days
   Old type: string
   New type: integer
   Current value: "30"
   Action: Manual review required - value may need conversion

========================================
ℹ️  INFORMATIONAL (15)
========================================

New Optional Properties (5):
- .properties.enhanced_logging (boolean, default: false)
- .properties.metrics_export_format (selector, default: json)
- .properties.backup_encryption (boolean, default: true)
...

Default Changes (4):
- .properties.max_connections: 3500 → 5000 (your current: 3500)
- .properties.timeout_seconds: 900 → 600 (your current: 900)
...

Removed Unused Properties (6):
- .properties.experimental_feature_x (not configured)
- .properties.deprecated_setting_y (not configured)
...

========================================
Next Steps
========================================

1. Review all REQUIRED ACTIONS and update configuration
2. Address WARNINGS before staging new version
3. Optionally review INFORMATIONAL items for optimization
4. Test configuration in non-production environment first

Command to update configuration:
  om configure-product -p cf -c updated-config.yml
```

### Option 2: JSON Report (Machine-Readable)

```json
{
  "metadata": {
    "old_version": "6.0.22",
    "new_version": "10.2.5",
    "analysis_date": "2025-12-10T12:34:56Z",
    "product_guid": "cf-85da7fd88e99806e5d08",
    "total_properties": 599,
    "configurable_properties": 422,
    "configured_properties": 156
  },
  "summary": {
    "required_actions": 3,
    "warnings": 2,
    "informational": 15
  },
  "changes": {
    "required_actions": [
      {
        "type": "new_required_property",
        "property": ".properties.new_security_feature",
        "property_type": "boolean",
        "default": null,
        "description": "Enable enhanced security scanning",
        "recommendation": "Set to 'true' unless you have external scanning"
      }
    ],
    "warnings": [
      {
        "type": "removed_property_in_use",
        "property": ".properties.legacy_routing_mode",
        "current_value": "compatibility",
        "impact": "Property will be ignored after upgrade"
      }
    ],
    "informational": [
      {
        "type": "new_optional_property",
        "property": ".properties.enhanced_logging",
        "property_type": "boolean",
        "default": false
      }
    ]
  }
}
```

### Option 3: YAML Config Diff (Git-style)

```yaml
# Configuration changes required for upgrade
# Old: 6.0.22 → New: 10.2.5

product-properties:
  # 🚨 REQUIRED: New property (no default)
+ .properties.new_security_feature:
+   value: true  # MUST SET: Enable enhanced security scanning

  # ⚠️  WARNING: Constraint changed
  .properties.autoscale_metric_bucket_count:
-   value: 150  # Exceeds new max: 120
+   value: 120  # Adjusted to meet constraint

  # ⚠️  WARNING: Property removed (currently set)
- .properties.legacy_routing_mode:
-   value: compatibility  # Will be ignored in new version

  # ℹ️  INFORMATIONAL: New optional (has default)
+ .properties.enhanced_logging:
+   value: false  # Optional: Enable enhanced logging (default)
```

---

## Implementation Phases

### Phase 1: Core Extraction & Parsing (MVP)

**Goal:** Extract and parse data sources

**Tasks:**
1. Extract metadata.yml from .pivotal files (both versions)
2. Parse property_blueprints section
3. Query Ops Manager API for current configuration
4. Build property maps for old, new, and current

**Deliverable:** Python script that can read all three data sources

**Validation:**
- Successfully parse metadata from sample tiles
- Successfully query API and parse JSON
- Print property counts to verify completeness

### Phase 2: Basic Comparison

**Goal:** Identify new, removed, and changed properties

**Tasks:**
1. Compare old vs new schemas (set operations)
2. Identify new properties (in new, not in old)
3. Identify removed properties (in old, not in new)
4. Identify changed properties (type, optional, constraints)

**Deliverable:** Script outputs three lists: new, removed, changed

**Validation:**
- Manual review of changes against known differences
- Verify no false positives/negatives

### Phase 3: Current Config Cross-Reference

**Goal:** Filter changes to only those affecting current configuration

**Tasks:**
1. Check which removed properties are actually used
2. Validate current values against new constraints
3. Identify which new required properties need user input

**Deliverable:** Filtered change lists with context

**Validation:**
- Verify warnings only appear for actually-used properties
- Confirm required actions list is complete

### Phase 4: Report Generation

**Goal:** Generate human-readable and machine-readable reports

**Tasks:**
1. Categorize changes (required/warning/informational)
2. Format text report with sections
3. Generate JSON output option
4. Add recommendations/descriptions where available

**Deliverable:** Tool produces formatted reports

**Validation:**
- Review report with real tile upgrade scenario
- Verify completeness and clarity

### Phase 5: Polish & Packaging

**Goal:** Production-ready tool

**Tasks:**
1. Add command-line argument parsing
2. Error handling and validation
3. Progress indicators for long operations
4. Documentation (README, usage examples)
5. Unit tests for core comparison logic

**Deliverable:** Distributable tool with documentation

---

## Edge Cases & Handling

### 1. Property Path Resolution

**Challenge:** Metadata uses simple names, API uses full paths

**Solution:**
- Build path map from metadata structure
- Handle common prefixes: `.properties.`, `.{job_name}.`
- For selectors, track nested paths with option names

**Test Case:** Verify all API properties map to metadata entries

### 2. Selector Properties with Options

**Challenge:** Selectors have nested properties per option

**Solution:**
- Track currently selected option from API
- Only compare properties for selected option
- Warn if selected option removed in new version

**Test Case:** Property with selector type, option removed in new version

### 3. Credentials (Obscured Values)

**Challenge:** API returns `***` for credential values

**Solution:**
- Flag credential properties but don't include values in reports
- Assume credentials remain valid unless type/constraints changed
- Note that credentials may need re-entry if property is new

**Test Case:** Credential property comparison doesn't fail on obscured values

### 4. Non-Configurable Properties

**Challenge:** Many system-managed properties in metadata

**Solution:**
- Filter out `configurable: false` properties early
- Focus only on user-modifiable properties
- Reduces noise in reports

**Test Case:** Verify system properties don't appear in reports

### 5. Default Value Changes

**Challenge:** Distinguishing user-set vs default values

**Solution:**
- Compare current value to old default
- If matches old default AND new default differs → Note but don't warn
- If doesn't match old default → User explicitly set it

**Test Case:** Property with changed default, user using old default

### 6. Multiple Products on Same Ops Manager

**Challenge:** Ops Manager may have multiple cf products

**Solution:**
- Accept product GUID as input
- Provide helper command to list available products
- Auto-detect if only one cf product exists

**Test Case:** Environment with multiple products

### 7. Tile Not Staged

**Challenge:** Can't get current config if tile not staged

**Solution:**
- Make current config optional
- Allow comparison without current config (schema-only diff)
- Clearly indicate when current config unavailable

**Test Case:** Run comparison with only two tile files (no current config)

### 8. Large Metadata Files

**Challenge:** metadata.yml can be 600KB+

**Solution:**
- Stream parsing for large YAML files
- Only load property_blueprints section
- Consider caching parsed metadata

**Test Case:** Performance test with real tile files

---

## Testing Strategy

### Unit Tests

**Scope:** Core comparison logic

**Tests:**
1. Property schema parsing from YAML
2. API response parsing from JSON
3. New property detection
4. Removed property detection
5. Changed property detection (type, constraints, optional)
6. Path resolution (name → full path)
7. Constraint validation

**Framework:** pytest

### Integration Tests

**Scope:** End-to-end with real data

**Tests:**
1. Extract metadata from real .pivotal files
2. Query real Ops Manager API (test environment)
3. Generate report for known upgrade path
4. Validate report accuracy against manual analysis

**Data:** Sample tile files for versions 6.0.22 and 10.2.5

### Manual Validation

**Scope:** Report quality and usability

**Tests:**
1. Run on real upgrade scenario (6.0.22 → 10.2.5)
2. Verify all changes match release notes
3. Check for false positives/negatives
4. Validate recommendations are actionable

---

## Command-Line Interface

### Main Command

```bash
tile-diff compare \
  --old-tile <path-to-old.pivotal> \
  --new-tile <path-to-new.pivotal> \
  [--current-config <path-to-json> | --product-guid <guid>] \
  [--format text|json|yaml] \
  [--output <path>] \
  [--verbose]
```

**Arguments:**
- `--old-tile`: Path to current version .pivotal file (required)
- `--new-tile`: Path to target version .pivotal file (required)
- `--current-config`: Path to JSON file from API (optional)
- `--product-guid`: Fetch current config from Ops Manager via API (optional)
- `--format`: Output format (default: text)
- `--output`: Output file (default: stdout)
- `--verbose`: Show detailed progress

**Examples:**

```bash
# Compare two tiles without current config (schema-only diff)
tile-diff compare \
  --old-tile srt-6.0.22.pivotal \
  --new-tile srt-10.2.5.pivotal

# Compare with current config from API
tile-diff compare \
  --old-tile srt-6.0.22.pivotal \
  --new-tile srt-10.2.5.pivotal \
  --product-guid cf-85da7fd88e99806e5d08

# Save JSON report to file
tile-diff compare \
  --old-tile srt-6.0.22.pivotal \
  --new-tile srt-10.2.5.pivotal \
  --current-config current.json \
  --format json \
  --output upgrade-report.json
```

### Helper Commands

```bash
# List available products in Ops Manager
tile-diff list-products

# Extract current config to file
tile-diff get-config \
  --product-guid cf-85da7fd88e99806e5d08 \
  --output current-config.json

# Validate config against tile schema
tile-diff validate \
  --tile srt-10.2.5.pivotal \
  --config my-config.yml
```

---

## Dependencies

### Python Libraries

- **PyYAML**: YAML parsing (metadata.yml)
- **requests**: HTTP requests (if not using om CLI)
- **click**: CLI argument parsing
- **jinja2**: Report templating (optional)
- **jsonschema**: Schema validation (optional)

### External Tools

- **om CLI**: For Ops Manager API access (authenticated)
- **unzip**: For extracting .pivotal files (system tool)
- **jq**: JSON processing (optional, for debugging)

### Environment Requirements

- Python 3.9+
- Access to Ops Manager API (credentials via .envrc or environment)
- Read access to .pivotal files

---

## Future Enhancements

### Version 2.0

1. **Interactive Mode**: Prompt user for values for new required properties
2. **Config Generation**: Output updated config file ready to apply
3. **Migration Scripts**: Detect and suggest data migrations (e.g., type changes)
4. **Release Notes Integration**: Fetch and display relevant release notes
5. **Diff History**: Track changes across multiple version upgrades
6. **Validation**: Pre-flight check before staging new tile

### Version 3.0

1. **Web UI**: Browser-based comparison tool
2. **CI/CD Integration**: GitHub Action or pipeline step
3. **Multi-Tile Support**: Compare multiple products simultaneously
4. **Change Tracking**: Database of known breaking changes by version
5. **Rollback Planner**: Generate rollback plan before upgrade

---

## Success Criteria

This tool is successful if:

1. **Accuracy**: Identifies all required configuration changes (0% false negatives)
2. **Precision**: Minimizes irrelevant warnings (< 10% false positives)
3. **Clarity**: Reports are understandable by operators without deep tile knowledge
4. **Speed**: Analysis completes in < 30 seconds for typical tiles
5. **Reliability**: Handles edge cases gracefully without crashing
6. **Adoption**: Becomes standard practice for tile upgrades in team workflow

---

## Open Questions

1. **Q:** Should we support comparing more than two versions (e.g., 6.0.22 → 6.0.25 → 10.2.5)?
   **A:** TBD - Start with two-version comparison, consider multi-version in v2

2. **Q:** How to handle custom/modified tiles (patched metadata)?
   **A:** TBD - Detect and warn if metadata doesn't match expected structure

3. **Q:** Should we integrate with Pivotal Network API to fetch tiles automatically?
   **A:** TBD - Nice-to-have for v2, requires API authentication

4. **Q:** How to handle different product types (not just cf)?
   **A:** Design should be generic enough, but test primarily with cf product

5. **Q:** Should we store comparison results for historical tracking?
   **A:** TBD - Could be useful for audit trail, consider in v2

---

## Approval & Sign-off

- [ ] Reviewed by: Mark
- [ ] Approved for implementation: ___________
- [ ] Target completion date: ___________
- [ ] Assigned to: ___________

---

## Appendix A: Sample Property Blueprint

```yaml
# From metadata.yml property_blueprints section

- name: app_log_rate_limiting
  configurable: true
  default: disable
  type: selector
  option_templates:
    - name: enable
      select_value: enable
      property_blueprints:
        - name: max_log_lines_per_second
          configurable: true
          type: integer
          constraints:
            min: 1
          default: 100
          optional: true
      named_manifests:
        - name: app_log_rate_limiting_properties
          manifest: |
            (( .properties.app_log_rate_limiting.enable.max_log_lines_per_second.value ))
    - name: disable
      select_value: disable
      named_manifests:
        - name: app_log_rate_limiting_properties
          manifest: |
            0
```

## Appendix B: Sample API Response

```json
{
  ".properties.app_log_rate_limiting": {
    "type": "selector",
    "configurable": true,
    "credential": false,
    "value": "disable",
    "optional": false,
    "selected_option": "disable"
  },
  ".properties.app_log_rate_limiting.enable.max_log_lines_per_second": {
    "type": "integer",
    "configurable": true,
    "credential": false,
    "value": 100,
    "optional": true
  }
}
```

## Appendix C: References

- **Ops Manager API Docs**: https://opsman.tas.vcf.lab/docs/
- **om CLI**: https://github.com/pivotal-cf/om
- **TAS Release Notes**: https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/
- **BOSH Metadata Format**: https://bosh.io/docs/
