# Spectral Library Utility Scripts

Companion scripts for the BLIB/MSP converter to extract and filter peptide sequences from spectral libraries.

## Scripts

### extract_peptides.pl

Extracts all unique peptide sequences from a spectral library and saves them to a text file.

**Supported formats:**
- BLIB (BiblioSpec SQLite database)
- MSP (NIST text format)

**Usage:**
```bash
perl extract_peptides.pl -i <library.blib|library.msp> [-o <output.txt>]
```

**Options:**
| Option | Description |
|--------|-------------|
| `-i, --input FILE` | Input BLIB or MSP file (required) |
| `-o, --output FILE` | Output text file (default: input_peptides.txt) |
| `-h, --help` | Show help message |
| `--version` | Show version number |

**Examples:**
```bash
# Extract from BLIB file (auto-generates output filename)
perl extract_peptides.pl -i my_library.blib
# Output: my_library_peptides.txt

# Extract from MSP file
perl extract_peptides.pl -i my_library.msp
# Output: my_library_peptides.txt

# Specify output filename
perl extract_peptides.pl -i my_library.blib -o peptide_list.txt
```

**Output format:**
One peptide sequence per line, sorted alphabetically:
```
AAAAAHPDGIVDLSVGTPVDSVAPVIR
AAAAGADTQANYK
AAAANEPGFEVESTVFEHPSVTVSQPAAEIEELR
AAAAVTEGDPR
...
```

---

### filter_msp.pl

Filters an MSP spectral library to include only entries matching a list of peptide sequences.

**Usage:**
```bash
perl filter_msp.pl -i <input.msp> -p <peptides.txt> [-o <output.msp>]
```

**Options:**
| Option | Description |
|--------|-------------|
| `-i, --input FILE` | Input MSP file (required) |
| `-p, --peptides FILE` | Text file with peptide sequences, one per line (required) |
| `-o, --output FILE` | Output MSP file (default: input_filtered.msp) |
| `-h, --help` | Show help message |
| `--version` | Show version number |

**Examples:**
```bash
# Filter MSP file (auto-generates output filename)
perl filter_msp.pl -i library.msp -p peptide_list.txt
# Output: library_filtered.msp

# Specify output filename
perl filter_msp.pl -i library.msp -p peptides.txt -o filtered_library.msp
```

**Peptide list format:**
Plain text file with one peptide sequence per line:
```
PEPTIDEK
ANOTHERPEPTIDER
YETANOTHERK
```

---

## Typical Workflow

### 1. Extract peptides from a spectral library
```bash
perl extract_peptides.pl -i my_library.blib -o all_peptides.txt
```

### 2. Filter the peptide list (external step)
Use your preferred method to create a filtered peptide list (e.g., based on UniPept, protein of interest, FDR threshold, etc.)

### 3. Convert BLIB to MSP
```bash
perl blib2msp.pl -i my_library.blib -o my_library.msp
```

### 4. Filter the MSP library
```bash
perl filter_msp.pl -i my_library.msp -p filtered_peptides.txt -o my_library_filtered.msp
```

---

## Requirements

- Perl 5.x
- DBI module (for BLIB extraction only)
- DBD::SQLite module (for BLIB extraction only)

All modules are included with Strawberry Perl on Windows.

---

## Version History

- **1.1** - Added MSP file support to extract_peptides.pl
- **1.0** - Initial release of both scripts
