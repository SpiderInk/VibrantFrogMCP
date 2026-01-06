# VibrantFrogMCP Test Suite

Automated tests for core functionality.

## Running Tests

### Prerequisites

```bash
pip install pytest
```

### Run All Tests

```bash
# From project root
pytest tests/ -v

# Or run specific test file
pytest tests/test_shared_index.py -v
```

### Test Coverage

Current test coverage:

- ✅ **test_shared_index.py** - Core SQLite database operations
  - Database creation and schema validation
  - Embedding serialization (JSON format)
  - WAL mode verification
  - Stats on empty database

- ✅ **test_migration.py** - Migration helpers
  - Embedding conversion (numpy → list)
  - Cloud GUID validation
  - Path resolution

## Test Philosophy

This is a **minimum viable test suite** to ensure:
1. Core database operations work
2. JSON serialization is correct
3. Basic validation functions properly

## Future Testing

Recommended additions:

1. **Integration tests** for CloudKit upload/download
2. **End-to-end tests** for Mac → iOS sync
3. **Performance tests** for large databases (100k+ photos)
4. **Regression tests** for bug fixes

## CI/CD

To add continuous integration:

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-python@v2
        with:
          python-version: '3.12'
      - run: pip install -r requirements.txt pytest
      - run: pytest tests/ -v
```

## Notes

- Tests use temporary directories (no persistent state)
- CloudKit tests require macOS and iCloud account (not included)
- Photo library tests require Apple Photos access (manual testing only)
