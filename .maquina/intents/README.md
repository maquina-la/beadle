# Máquina intents

Create one `maquina.intent.v1` JSON file per scoped change before agent work.
Keep allowed paths narrow and commit the intent to the base branch before a
pull request relies on it.

Every governed pull request body must contain all three lines:

```text
Maquina-Intent: .maquina/intents/BEADLE-NNN.json
Maquina-Work-Type: application
Maquina-Validation-Profile: default
```

Required intent fields are `id`, `title`, `objective`, `work_type`,
`allowed_paths`, `context_refs`, and `acceptance_criteria`.

Current bootstrap intents:

- `BEADLE-001` installs the repository-owned Factory Contract and intent set.
- `BEADLE-002` installs the immutable, precompiled GitHub advisory Action after
  `BEADLE-001` is merged and therefore available from the trusted base revision.
