---
name: coverage
description: Check test coverage via SonarCloud API. Shows overall, new code, and per-file coverage.
---

## Check SonarCloud coverage

Run these three API calls and present results in a table:

### Overall coverage
```!
curl -s "https://sonarcloud.io/api/measures/component?component=Llloooggg_LetsFLUTssh&metricKeys=coverage,uncovered_lines"
```

### New code coverage
```!
curl -s "https://sonarcloud.io/api/measures/component?component=Llloooggg_LetsFLUTssh&metricKeys=new_coverage,new_uncovered_lines,new_lines_to_cover"
```

### Per-file (top 20 worst)
```!
curl -s "https://sonarcloud.io/api/measures/component_tree?component=Llloooggg_LetsFLUTssh&metricKeys=uncovered_lines,coverage&strategy=leaves&ps=20&s=metric&metricSort=uncovered_lines&asc=false"
```

Present results as:
1. **Overall**: X% coverage, N uncovered lines
2. **New code**: X% coverage, N uncovered / M total new lines
3. **Worst files** table: file | coverage% | uncovered lines (top 20, sorted by uncovered lines desc)

If `$ARGUMENTS` contains "file" or a specific path, also fetch that file's details.
