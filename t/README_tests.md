# Test Suite Documentation

## Overview

The BLIB/MSP Converter test suite contains approximately 400 tests across 17 test files, covering BLIB reading, MSP format parsing, bidirectional conversion, Unimod modification handling, FASTA protein mapping, utility scripts, round-trip validation, and comprehensive error handling.

**Run all tests:**
```bash
perl run_tests.pl
```

**Run individual test:**
```bash
perl t/01_blib_read.t
```

**Run code coverage:**
```powershell
$env:PERL5OPT = "-MDevel::Cover=-ignore,^t/"
perl t/04_unimod.t
# ... run other unit tests ...
$env:PERL5OPT = ""
cover
```

---

## Code Coverage (as of latest run)

| Metric | Coverage |
|--------|----------|
| Statements | 45.9% |
| Branches | 30.5% |
| Conditions | 24.4% |
| **Subroutines** | **81.1%** |

Functions not tested are primarily MCE parallel processing and Aho-Corasick integration which require specific runtime conditions.

---

## Test Files Summary

| Test File | Tests | Type | Description |
|-----------|-------|------|-------------|
| `01_blib_read.t` | 15 | Unit | BLIB database reading and peak extraction |
| `02_msp_format.t` | 14 | Unit | MSP format parsing patterns |
| `03_conversion.t` | ~26 | Integration | End-to-end BLIB↔MSP conversion |
| `04_unimod.t` | 16 | Unit | Unimod XML loading and modification lookup |
| `05_modifications.t` | 18 | Unit | Modification string parsing |
| `06_msp_format_unit.t` | 20 | Unit | MSP format functions from blib2msp.pl |
| `07_fasta_mapping.t` | 15 | Unit | FASTA indexing and peptide search |
| `08_extract_peptides.t` | 15 | Integration | extract_peptides.pl utility (MSP & BLIB) |
| `09_filter_msp.t` | 14 | Integration | filter_msp.pl utility |
| `10_minimal_blib.t` | 20 | Unit | Minimal test BLIB file validation |
| `11_utility_functions.t` | 17 | Unit | Logging, timestamps, duration formatting |
| `12_database_functions.t` | 22 | Unit | BLIB database query functions |
| `13_schema_and_parsing.t` | 21 | Unit | BLIB schema creation, cache keys |
| `14_error_handling.t` | 16 | Unit | Error paths and edge cases |
| `15_blib_to_msp.t` | 47 | Unit | BLIB to MSP conversion validation |
| `16_msp_to_blib.t` | 43 | Unit | MSP to BLIB conversion validation |
| `17_roundtrip.t` | 83 | Integration | BLIB↔MSP↔BLIB round-trip data preservation |

---

## Detailed Test Descriptions

### 01_blib_read.t - BLIB Database Reading (15 tests)

Tests direct SQLite access to BLIB spectral library files.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | Connect to BLIB database | DBI connection to SQLite BLIB file |
| 2 | No connection error | Clean connection without exceptions |
| 3 | LibInfo table has data | Library metadata table populated |
| 4 | LibInfo has numSpecs field | Required field exists |
| 5 | Library has spectra | numSpecs > 0 |
| 6 | RefSpectra table has data | Spectrum table populated |
| 7 | RefSpectra has peptideSeq | Required peptide sequence field |
| 8 | RefSpectra has precursorMZ | Required precursor m/z field |
| 9 | RefSpectra has precursorCharge | Required charge field |
| 10 | RefSpectra has numPeaks | Required peak count field |
| 11 | Can fetch peak data | JOIN to RefSpectraPeaks works |
| 12 | Peak MZ blob exists | Compressed m/z data present |
| 13 | Peak intensity blob exists | Compressed intensity data present |
| 14 | Extracted MZ values | Decompression and unpacking works |
| 15 | MZ and intensity counts match | Data integrity check |

**Subroutines Covered:** Raw DBI access (not blib2msp.pl functions)

---

### 02_msp_format.t - MSP Format Patterns (14 tests)

Tests regex patterns for parsing MSP format fields.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | Parse peptide sequence from Name | Extract "PEPTIDE" from "PEPTIDE/2" |
| 2 | Parse charge from Name | Extract charge value |
| 3 | Parse modified peptide from Name | Handle M(O) style annotations |
| 4 | Parse charge from modified Name | Charge with modifications |
| 5 | Strip modification annotations | Remove (O), (Phospho), etc. |
| 6 | Parse Parent from Comment | Extract precursor m/z |
| 7 | Parse Mods from Comment | Extract modification string |
| 8 | Parse RetentionTime from Comment | Extract RT value |
| 9 | Parse Score from Comment | Extract score value |
| 10 | Parse quoted value from Comment | Handle "quoted values" |
| 11 | Parse unquoted value after quoted | Mixed format parsing |
| 12 | MW calculation from m/z and charge | Forward mass calculation |
| 13 | m/z calculation from MW and charge | Reverse mass calculation |
| 14 | Parse m/z from peak line | Peak list parsing |

**Subroutines Covered:** Inline patterns (validates parsing logic)

---

### 03_conversion.t - End-to-End Conversion (~26 tests)

Integration tests for bidirectional BLIB↔MSP conversion. Uses `done_testing()` for variable test count.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | Script syntax is valid | `perl -c` passes |
| 2-3 | Help output | Contains SYNOPSIS and --verbose option |
| 4 | Version output format correct | Version string format |
| 5-9 | BLIB→MSP conversion | File created, has content, starts with Name field, validates entry structure |
| 10-26 | MSP→BLIB conversion | File created, valid SQLite database, has required tables, spectrum count, sample spectrum fields, peak data (skipped if MSP test file not found) |

**Subroutines Covered:** `main`, `convert_blib_to_msp`, `convert_msp_to_blib` (black-box)

---

### 04_unimod.t - Unimod Modification Database (16 tests)

Tests Unimod XML loading and bidirectional modification lookup.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | load_unimod function exists | Function available |
| 2 | lookup_unimod_name function exists | Function available |
| 3 | lookup_unimod_mass function exists | Function available |
| 4 | Unimod loaded successfully | Lookup works after load |
| 5 | Mass to name lookup populated | Internal hash built |
| 6 | Name to mass lookup populated | Reverse hash built |
| 7 | Find Carbamidomethyl by exact mass | 57.021464 → Carbamidomethyl |
| 8 | Find Oxidation by exact mass | 15.994915 → Oxidation |
| 9 | Find Phospho by exact mass | 79.966331 → Phospho |
| 10 | Find mass for Carbamidomethyl | Carbamidomethyl → 57.021464 |
| 11 | Find mass for Oxidation | Oxidation → 15.994915 |
| 12 | Find mass for Phospho | Phospho → 79.966331 |
| 13 | Find Carbamidomethyl with mass tolerance | Tolerance-based lookup |
| 14 | Unknown mass returns undef | Graceful failure |
| 15 | Unknown name returns undef | Graceful failure |
| 16 | Case-insensitive name lookup | "carbamidomethyl" works |

**Subroutines Covered:** `load_unimod`, `lookup_unimod_name`, `lookup_unimod_mass`

---

### 05_modifications.t - Modification Parsing (18 tests)

Tests modification string parsing and mass lookup.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | parse_modifications_from_string exists | Function available |
| 2 | lookup_mod_mass exists | Function available |
| 3 | Parse single modification | "1(3,C,Carbamidomethyl)" |
| 4 | Modification position correct | Position = 3 |
| 5 | Modification amino acid correct | AA = C |
| 6 | Modification tag correct | Tag = Carbamidomethyl |
| 7 | Parse two modifications | Multiple mods in string |
| 8 | First mod position | First mod details |
| 9 | First mod tag | First mod name |
| 10 | Second mod position | Second mod details |
| 11 | Second mod tag | Second mod name |
| 12 | Empty string returns no mods | "" → empty array |
| 13 | Undefined returns no mods | undef → empty array |
| 14 | Zero count returns no mods | "0" → empty array |
| 15 | Lookup Oxidation mass | Hardcoded fallback |
| 16 | Lookup Carbamidomethyl mass | Hardcoded fallback |
| 17 | Lookup Phospho mass | Hardcoded fallback |
| 18 | Unknown modification returns undef | Graceful failure |

**Subroutines Covered:** `parse_modifications_from_string`, `lookup_mod_mass`

---

### 06_msp_format_unit.t - MSP Format Functions (20 tests)

Unit tests for actual blib2msp.pl MSP parsing/generation functions.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | parse_comment function exists | Function available |
| 2 | format_msp_entry function exists | Function available |
| 3 | extract_peaks function exists | Function available |
| 4 | Parse Parent from Comment | parse_comment extracts Parent |
| 5 | Parse Mods from Comment | parse_comment extracts Mods |
| 6 | Parse RetentionTime from Comment | parse_comment extracts RT |
| 7 | Parse Score from Comment | parse_comment extracts Score |
| 8 | Parse Parent with mods | Complex Comment parsing |
| 9 | Parse complex Mods string | New format parsing |
| 10 | Parse Parent before quoted | Mixed format handling |
| 11 | Parse quoted Protein value | Quoted value extraction |
| 12 | Parse Score after quoted | Continue after quotes |
| 13 | Parse unquoted Protein | Simple protein field |
| 14 | Parse MultiProtein flag | Multi-protein indicator |
| 15 | Name line format correct | format_msp_entry output |
| 16 | MW line present | Molecular weight line |
| 17 | Comment contains Parent | Parent in Comment |
| 18 | Comment contains Mods=0 | Zero mods format |
| 19 | Num peaks correct | Peak count line |
| 20 | Protein field formatted correctly | sp|ACC| format |

**Subroutines Covered:** `parse_comment`, `format_msp_entry`, `extract_peaks`

---

### 07_fasta_mapping.t - FASTA Protein Mapping (15 tests)

Tests FASTA file indexing and peptide-to-protein search.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | build_fasta_peptide_index exists | Function available |
| 2 | search_fasta_for_peptide exists | Function available |
| 3 | FASTA index built with proteins | Index not empty |
| 4 | Index contains TRYP_PIG accession | Specific protein found |
| 5 | Index contains CATA_HUMAN accession | Specific protein found |
| 6 | Index contains ALBU_HUMAN accession | Specific protein found |
| 7-8 | Search for IQVR peptide | Found proteins, correct results (TRYP_PIG) |
| 9-10 | Search for MLQGR peptide | Found proteins, correct results (CATA_HUMAN) |
| 11 | No results for non-existent peptide | ZZZZNOTFOUNDZZZ → empty |
| 12-13 | Handle invalid directory | Empty index and no results for bad path |
| 14 | Search for SCRSYR peptide | Found at least one protein (K2M3_SHEEP) |
| 15 | Search for LKCASLQK peptide | Found protein(s) (ALBU_HUMAN) |

**Subroutines Covered:** `build_fasta_peptide_index`, `search_fasta_for_peptide`

---

### 08_extract_peptides.t - Extract Peptides Utility (15 tests)

Integration tests for the extract_peptides.pl utility script.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | Script syntax is valid | `perl -c` passes |
| 2 | Help output contains Usage or SYNOPSIS | Help available |
| 3 | Help output contains --input option | CLI documented |
| 4 | Version output present | --version works |
| 5 | Output file created | Extraction produces file |
| 6 | Output file has peptides | Non-empty output |
| 7 | Found IQVR in output | Expected peptide extracted |
| 8 | Found MLQGR in output | Expected peptide extracted |
| 9 | Auto-generated output file created | Default naming works |
| 10 | Error message for missing file | Error handling |
| 11 | Output shows unique peptide count | Statistics reported |
| 12 | Output is sorted alphabetically | Sorted output |
| 13 | BLIB extraction output file created | BLIB input support |
| 14 | Found IQVR from BLIB | BLIB peptide extraction |
| 15 | Found MLQGR from BLIB | BLIB peptide extraction |

**Script Covered:** `extract_peptides.pl`

---

### 09_filter_msp.t - Filter MSP Utility (14 tests)

Integration tests for the filter_msp.pl utility script.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | Script syntax is valid | `perl -c` passes |
| 2 | Help output contains Usage or SYNOPSIS | Help available |
| 3 | Help output contains --input option | CLI documented |
| 4 | Help output contains --peptides option | CLI documented |
| 5 | Version output present | --version works |
| 6 | Filtered output file created | Filtering produces file |
| 7 | Output contains IQVR entry | Kept peptide present (in peptide_list.txt) |
| 8 | Output contains MLQGR entry | Kept peptide present (in peptide_list.txt) |
| 9 | Output does NOT contain LKCASLQK | Filtered peptide absent |
| 10 | Output does NOT contain SCRSYR | Filtered peptide absent |
| 11 | Output shows statistics | Counts reported |
| 12 | Error message for missing input file | Error handling |
| 13 | Error message for missing peptide file | Error handling |
| 14 | Output file created even with empty filter | Edge case handling |

**Script Covered:** `filter_msp.pl`

---

### 10_minimal_blib.t - Minimal Test BLIB Validation (20 tests)

Tests the minimal test BLIB file with known data.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | Connect to minimal test BLIB | Database connection |
| 2 | LibInfo shows 4 spectra | Spectrum count in metadata |
| 3 | RefSpectra has 4 entries | Actual spectrum count |
| 4 | Spectrum 1 peptideSeq is IQVR | Peptide sequence |
| 5 | Spectrum 1 charge is 2 | Charge state |
| 6 | Spectrum 1 has no modifications | Zero mods |
| 7 | Spectrum 2 peptideSeq is MLQGR | Peptide sequence |
| 8 | Spectrum 2 mod at position 1 | Oxidation position |
| 9 | Spectrum 2 mod mass is Oxidation | Modification mass |
| 10 | Spectrum 3 peptideSeq is LKCASLQK | Peptide sequence |
| 11 | Spectrum 3 mod at position 3 (C) | Carbamidomethyl position |
| 12 | Spectrum 3 mod mass is Carbamidomethyl | Modification mass |
| 13 | Spectrum 4 peptideSeq is SCRSYR | Peptide sequence |
| 14 | Spectrum 4 has 2 modifications | Multiple mods |
| 15 | First mod at position 1 (S) | Acetyl position |
| 16 | Second mod at position 2 (C) | Carbamidomethyl position |
| 17 | Spectrum 1 has 5 m/z values | Peak count |
| 18 | Spectrum 1 has 5 intensity values | Peak count |
| 19 | First m/z value correct | Peak data integrity |
| 20 | ScoreType 1 is PERCOLATOR QVALUE | Score type lookup |

**Data Covered:** `t/data/minimal.blib`

---

### 11_utility_functions.t - Utility Functions (17 tests)

Tests utility functions for logging, timing, and modification tracking.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | get_timestamp function exists | Function available |
| 2 | Timestamp format correct | YYYY-MM-DD HH:MM:SS format |
| 3 | format_duration function exists | Function available |
| 4-7 | format_duration outputs | Seconds, minutes, hours formatting |
| 8 | track_modification function exists | Function available |
| 9-10 | track_modification handles mods | Known/unknown modification tracking |
| 11 | log_msg function exists | Function available |
| 12 | log_msg outputs formatted message | Correct log format |
| 13 | print_modification_summary exists | Function available |
| 14 | print_modification_summary outputs | Summary generation |
| 15-17 | LOG constants | LOG_ERROR, LOG_WARN, LOG_INFO values |

**Subroutines Covered:** `get_timestamp`, `format_duration`, `track_modification`, `log_msg`, `print_modification_summary`

---

### 12_database_functions.t - Database Query Functions (22 tests)

Tests BLIB database query functions using minimal.blib.

| # | Test | What it verifies |
|---|------|------------------|
| 1 | Database connection | Connect to test BLIB |
| 2-5 | get_library_info | Function exists, returns hashref, numSpecs, libLSID |
| 6-8 | get_score_types | Function exists, returns data, correct score type |
| 9-17 | get_all_modifications | Function exists, mod counts and positions |
| 18-19 | get_all_proteins | Function exists, returns hash |
| 20-22 | get_unique_peptides_from_blib | Function exists, peptide extraction |

**Subroutines Covered:** `get_library_info`, `get_score_types`, `get_all_modifications`, `get_all_proteins`, `get_unique_peptides_from_blib`

---

### 13_schema_and_parsing.t - Schema Creation and Parsing (21 tests)

Tests BLIB schema creation and cache key computation.

| # | Test | What it verifies |
|---|------|------------------|
| 1-6 | create_blib_schema | Function exists, all tables created |
| 7-8 | update_library_info | Function exists, numSpecs updated |
| 9-15 | extract_peaks | Function exists, compressed data handling |
| 16-20 | compute_cache_key | Function exists, MD5 key generation, consistency |
| 21 | Function existence | parse_and_insert_msp |

**Subroutines Covered:** `create_blib_schema`, `update_library_info`, `extract_peaks`, `compute_cache_key`

---

### 14_error_handling.t - Error Handling (16 tests)

Tests error handling and edge cases across multiple functions.

| # | Test | What it verifies |
|---|------|------------------|
| 1-2 | lookup_unimod_name edge cases | Unloaded unimod, undef mass |
| 3-4 | lookup_unimod_mass edge cases | Unloaded unimod, undef name |
| 5-7 | parse_modifications_from_string | Undef, empty, invalid input |
| 8-10 | parse_comment edge cases | Empty, no equals, simple format |
| 11-12 | extract_peaks edge cases | Undef/empty blobs |
| 13-15 | format_duration edge cases | 0, 59, 60 seconds |
| 16 | build_fasta_peptide_index | Non-existent directory |

**Subroutines Covered:** Error paths for all major functions

---

### 15_blib_to_msp.t - BLIB to MSP Conversion (47 tests)

Detailed unit tests for BLIB to MSP conversion using minimal.blib.

| # | Test | What it verifies |
|---|------|------------------|
| 1-3 | Basic conversion | Conversion succeeds, file created, has content |
| 4-24 | MSP structure validation | All 4 entries have Name, MW, Comment, Num peaks fields |
| 25-32 | Spectrum 1 (IQVR/2) | Name format, MW, Mods=0, RetentionTime, Score, 5 peaks, peak values |
| 33-38 | Spectrum 2 (MLQGR/2) | Name with mod count, Mods=1, Oxidation at M1, 6 peaks |
| 39-41 | Spectrum 3 (LKCASLQK/3) | Name format, Mods=1, Carbamidomethyl at C3 |
| 42-46 | Spectrum 4 (SCRSYR/3) | Name with 2 mods, Acetyl at S1, Carbamidomethyl at C2 |
| 47 | Error handling | Invalid BLIB file produces no output |

**Subroutines Covered:** `convert_blib_to_msp`, `format_msp_entry`

---

### 16_msp_to_blib.t - MSP to BLIB Conversion (43 tests)

Detailed unit tests for MSP to BLIB conversion using minimal.msp.

| # | Test | What it verifies |
|---|------|------------------|
| 1-3 | Basic conversion | Conversion succeeds, file created, has content |
| 4-9 | Schema validation | All required tables (LibInfo, RefSpectra, RefSpectraPeaks, Modifications, ScoreTypes) |
| 10-11 | LibInfo validation | Has data, numSpecs=4 |
| 12 | Spectrum count | RefSpectra has 4 entries |
| 13-24 | Spectrum 1 (IQVR) | peptideSeq, precursorMZ, charge, numPeaks, retentionTime, score, no mods, peaks |
| 25-30 | Spectrum 2 (MLQGR) | Found, peptideSeq, modification at position 1 with Oxidation mass |
| 31-34 | Spectrum 3 (LKCASLQK) | Found, modification at position 3 with Carbamidomethyl mass |
| 35-40 | Spectrum 4 (SCRSYR) | Found, 2 modifications with correct positions and masses |
| 41-43 | Peak compression | Decompressed m/z and intensity match numPeaks |

**Subroutines Covered:** `convert_msp_to_blib`, `parse_and_insert_msp`, `create_blib_schema`

---

### 17_roundtrip.t - Round-Trip Conversion (83 tests)

Integration tests verifying data preservation through bidirectional conversion.

| # | Test | What it verifies |
|---|------|------------------|
| 1-6 | BLIB→MSP→BLIB setup | Both conversions succeed, files created, can connect |
| 7 | Spectrum count | Round-trip preserves count |
| 8-78 | Per-spectrum validation | For IQVR, MLQGR, LKCASLQK, SCRSYR: peptideSeq, precursorMZ, charge, modification count/position/mass, peak count/m/z/intensity |
| 79-82 | MSP→BLIB→MSP setup | Both conversions succeed, files created |
| 83 | Entry count | Round-trip preserves MSP entry count |

**Data Integrity Tests:**
- Peptide sequences preserved exactly
- Precursor m/z preserved within 0.001 tolerance
- Charge states preserved exactly
- Modification positions preserved exactly
- Modification masses preserved within 0.001 tolerance
- Peak m/z preserved within 0.001 tolerance
- Peak intensities preserved within 0.01 tolerance

---

## Test Data Files

Located in `t/data/`:

| File | Description |
|------|-------------|
| `minimal.blib` | 4 spectra BLIB file matching minimal.msp |
| `minimal.msp` | 4 real MSP entries from PRIDE Contaminants library |
| `minimal_unimod.xml` | 6 common modifications for fast testing |
| `test.fasta` | 4 test proteins (TRYP_PIG, CATA_HUMAN, ALBU_HUMAN, K2M3_SHEEP) |
| `peptide_list.txt` | Filter test: IQVR, MLQGR |
| `old_format.msp` | Old modification format (slash-separated) for backward compatibility |
| `create_test_blib.pl` | Script to regenerate minimal.blib if needed |

### Test Peptides

All test peptides are real sequences with biologically valid modifications:

| Peptide | Protein | Modifications |
|---------|---------|---------------|
| IQVR | TRYP_PIG | None |
| MLQGR | CATA_HUMAN | Oxidation at M1 |
| LKCASLQK | ALBU_HUMAN | Carbamidomethyl at C3 |
| SCRSYR | K2M3_SHEEP | Acetyl at S1, Carbamidomethyl at C2 |

---

## Coverage Summary

### Functions Directly Unit Tested

| Function | Test File |
|----------|-----------|
| `load_unimod` | 04_unimod.t |
| `lookup_unimod_name` | 04_unimod.t, 14_error_handling.t |
| `lookup_unimod_mass` | 04_unimod.t, 14_error_handling.t |
| `parse_modifications_from_string` | 05_modifications.t, 14_error_handling.t |
| `lookup_mod_mass` | 05_modifications.t |
| `parse_comment` | 06_msp_format_unit.t, 14_error_handling.t |
| `format_msp_entry` | 06_msp_format_unit.t |
| `extract_peaks` | 06_msp_format_unit.t, 13_schema_and_parsing.t, 14_error_handling.t |
| `build_fasta_peptide_index` | 07_fasta_mapping.t, 14_error_handling.t |
| `search_fasta_for_peptide` | 07_fasta_mapping.t |
| `get_timestamp` | 11_utility_functions.t |
| `format_duration` | 11_utility_functions.t, 14_error_handling.t |
| `track_modification` | 11_utility_functions.t |
| `log_msg` | 11_utility_functions.t |
| `print_modification_summary` | 11_utility_functions.t |
| `get_library_info` | 12_database_functions.t |
| `get_score_types` | 12_database_functions.t |
| `get_all_modifications` | 12_database_functions.t |
| `get_all_proteins` | 12_database_functions.t |
| `get_unique_peptides_from_blib` | 12_database_functions.t |
| `create_blib_schema` | 13_schema_and_parsing.t |
| `update_library_info` | 13_schema_and_parsing.t |
| `compute_cache_key` | 13_schema_and_parsing.t |

### Functions Tested via Integration

| Function | Test File |
|----------|-----------|
| `main` | 03_conversion.t |
| `convert_blib_to_msp` | 03_conversion.t, 15_blib_to_msp.t, 17_roundtrip.t |
| `convert_msp_to_blib` | 03_conversion.t, 16_msp_to_blib.t, 17_roundtrip.t |
| `parse_arguments` | 03_conversion.t |
| `process_blib_spectra` | 03_conversion.t, 15_blib_to_msp.t |
| `process_msp_entry` | 03_conversion.t, 16_msp_to_blib.t |
| `format_msp_entry` | 15_blib_to_msp.t |
| `parse_and_insert_msp` | 16_msp_to_blib.t |
| `create_blib_schema` | 16_msp_to_blib.t |

### Functions Not Tested (MCE/Aho-Corasick)

| Function | Reason |
|----------|--------|
| `build_peptide_automaton` | Requires Algorithm::AhoCorasick module |
| `search_proteins_parallel` | Requires MCE::Loop for parallel processing |
| `get_or_build_peptide_cache` | Involves file system caching |

### Scripts Tested

| Script | Test File |
|--------|-----------|
| `blib2msp.pl` | 03_conversion.t, 04-07, 15_blib_to_msp.t, 16_msp_to_blib.t, 17_roundtrip.t |
| `extract_peptides.pl` | 08_extract_peptides.t |
| `filter_msp.pl` | 09_filter_msp.t |

---

## Running Tests

```bash
# Run all tests
perl run_tests.pl

# Run specific test file
perl t/04_unimod.t

# Run with verbose output
prove -v t/

# Run with TAP::Harness
prove t/
```
