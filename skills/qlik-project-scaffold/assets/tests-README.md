# Tests (Optional)

Diagnostic and validation scripts that run after a reload:

- Row count validation per table
- Null rate checks for key fields
- Referential integrity checks (orphans, duplicate keys)
- Value distribution checks

These are typically invoked manually or as part of a CI/CD process. If you don't run automated tests against your Qlik model, you can delete this directory.
