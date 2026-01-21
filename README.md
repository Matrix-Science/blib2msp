# BLIB to MSP Spectral Library Converter

Version 1.5 - Latest Release

A Perl script for bidirectional conversion between BiblioSpec BLIB format (SQLite-based) and NIST MSP format spectral libraries.

## Features

- **BLIB to MSP conversion**: Convert BiblioSpec SQLite libraries to NIST MSP text format
- **MSP to BLIB conversion**: Convert NIST MSP libraries to BiblioSpec SQLite format
- **Protein mapping**: Map peptides to protein accessions from FASTA files
- **Unimod integration**: Automatic lookup of modification names from unimod.xml
- **Logging**: Standard and verbose logging modes
- **Peak compression**: Handles zlib-compressed peak data in BLIB files
- **Modification summary**: Reports modification statistics and unknown modifications
- **Backward compatibility**: Supports both old and new MSP modification formats

## Requirements

### Required Modules
- **Perl 5.32.1.1** (Strawberry Perl 5.32.1.1 - https://strawberryperl.com/releases.html)
- DBI module
- DBD::SQLite module
- Compress::Zlib module
- **Mascot Parser** - Required for Unimod parsing and MSP file handling

### Optional Modules (for protein mapping)
- Algorithm::AhoCorasick - Fast multi-pattern matching for FASTA search
- Storable - Disk caching of peptide-protein mappings
- Digest::MD5 - Cache key generation

Install optional modules:
```bash
cpanm Algorithm::AhoCorasick Storable Digest::MD5
```

All required modules except Mascot Parser are included with Strawberry Perl.

### Mascot Parser

The converter uses **Mascot Parser** for robust Unimod parsing and MSP file handling. Mascot Parser is available from:

**https://www.matrixscience.com/msparser_download.html**

**Installation:**
1. Download Mascot Parser from the link above
2. Install Mascot Parser system-wide by copying files to your Perl installation:
   - Copy `msparser.pm` to `C:\Strawberry\perl\lib\`
   - Copy `msparser.dll` to `C:\Strawberry\perl\lib\auto\msparser\`
   - Ensure the directory structure matches: `lib/auto/msparser/msparser.dll` relative to `lib/msparser.pm`

**Important - DLL Location:**
The `msparser.dll` file must be located in an `auto/msparser/` subdirectory relative to `msparser.pm`. The correct structure for system-wide installation is:
```
C:\Strawberry\perl\lib\
├── msparser.pm
└── auto/
    └── msparser/
        └── msparser.dll
```

**Windows DLL Dependencies:**
On Windows, Mascot Parser requires Visual C++ runtime libraries. If you encounter DLL loading errors:
- Install Microsoft Visual C++ Redistributable (latest version)
- Ensure the DLL architecture matches your Perl installation (32-bit vs 64-bit)
- Check that all DLL dependencies are accessible in your PATH

**Note:** Unimod files (`unimod.xml` and `unimod_2.xsd`) are included with the script in the `unimod/` directory and will be used automatically. The script will also check Mascot Parser's included Unimod file if available (see Unimod Database section below).

### Unimod Database

The converter uses Unimod for modification name lookups. **Unimod files are included with the script** in the `unimod/` directory:
- `unimod/unimod.xml` - Unimod modification definitions
- `unimod/unimod_2.xsd` - XML schema file required for validation

The script automatically searches for these files in the following locations (searched in order):
1. `unimod/unimod.xml` and `unimod/unimod_2.xsd` (included with script)
2. `msparser/config/unimod.xml` (Mascot Parser's included Unimod file)
3. Same directory as the input file
4. Current working directory
5. Specify path with `-u` option: `perl blib2msp.pl -i library.blib -u /path/to/unimod.xml`

**Note:** If you need a newer version of Unimod, you can download it from:
**https://www.unimod.org/downloads.html** (download the file labeled **"unimod.xml for Mascot 2.2 and later"**)

See the Modification Format sections for notes on how to handle open search or other undefined mods in a library. 

## Usage

### Basic Usage

```bash
# BLIB to MSP (auto-detected from extension)
perl blib2msp.pl -i library.blib

# MSP to BLIB
perl blib2msp.pl -i library.msp -o output.blib
```

### Options

```
-i, --input FILE     Input file (.blib or .msp)
-o, --output FILE    Output file (default: input with changed extension)
-u, --unimod FILE    Path to unimod.xml for modification name lookup
-f, --fasta-dir DIR  Directory containing FASTA files for protein mapping
-v, --verbose        Enable verbose/debug logging
    --min-peaks N    Minimum peaks required per spectrum (default: 1)
    --limit N        Process only first N spectra (for testing)
-h, --help           Show full help message
    --version        Show version number
```

### Examples

```bash
# Convert BLIB to MSP with verbose output
perl blib2msp.pl -v -i my_library.blib -o my_library.msp

# Convert with custom unimod.xml location
perl blib2msp.pl -i library.blib -u /path/to/unimod.xml

# Filter spectra with minimum 10 peaks
perl blib2msp.pl --min-peaks 10 -i library.blib

# Convert with protein mapping from FASTA files
perl blib2msp.pl -i library.blib -f /path/to/fasta/directory
```

## File Formats

### BLIB Format (BiblioSpec)

SQLite database containing:
- `RefSpectra`: Spectrum metadata (peptide sequence, precursor m/z, charge, etc.)
- `RefSpectraPeaks`: Peak m/z and intensity as compressed BLOBs
- `Modifications`: Modification positions and masses
- `LibInfo`: Library metadata

### MSP Format (NIST)

Text format with entries containing:
- `Name`: peptide/charge with modifications (e.g., `PEPTIDE/2_0` or `PEPTIDE/2_1(17,C,CAM)`)
- `MW`: Molecular weight
- `Comment`: Metadata including Parent, Mods, RetentionTime, Score, etc.
- `Num peaks`: Peak count
- Peak list: m/z intensity pairs

### Modification Format

Modifications use the new parentheses-based format (version 1.3+). The converter supports both old and new formats when reading MSP files.

**New Format (v1.3+):**
```
Name: PEPTIDE/2_0                                    # No modifications
Name: PEPTIDE/2_1(17,C,CAM)                          # One modification
Name: PEPTIDE/3_2(9,M,Oxidation)(12,M,Oxidation)     # Multiple modifications

Mods=0
Mods=1(17,C,CAM)
Mods=2(9,M,Oxidation)(12,M,Oxidation)
```

**Old Format (backward compatible):**
```
Name: PEPTIDE/2
Mods=2/2,C,Carbamidomethyl/11,C,Carbamidomethyl
Mods=1/7,M,Oxidation
```

The format is: `Mods=<count>(<position>,<amino_acid>,<tag>)(<position>,<amino_acid>,<tag>)...`

Where:
- `count`: Number of modifications
- `position`: Position in the peptide sequence (1-based)
- `amino_acid`: Single letter amino acid code
- `tag`: Unimod name (e.g., "CAM", "Oxidation") or numeric mass if not in Unimod

The conversion script uses unimod to identify modifications by mass. Sometimes a library might contain a modification that can not be identified. It will report these at the end of processing. 

The workaround is to calculate a likely molecular composition from the mass and add it as a custom modification to your Mascot Server. Use this online [Cheminfo.org](https://www.cheminfo.org/Spectra/Mass/Think/OLD_MF_from_monoisotopic_mass_and_PubChem/index.html) tool to create a list of candidate formulas and then select the nearest formula. Right click and choose Export->selected and a pop up will appear with the molecular formula that can be copied to the clipboard. In a browser open Mascot Server->Configuration editor-> Modifications->Editor, create a new modification then paste the molecular formula into the Composition field. Edit the composition by putting parentheses around the element counts. Add the modification site amino acid in the specificity tab. And save. I recommend using the same format as the other unknown modifications detected by open searches for example Unknown:286. 

As the BLIB library was not converted using the newly updated unimod file you either need to use a copy of your local Mascot Server \mascot\config\unimod.xml file and convert the library again or add allises for the masses to the \mascot\config\ library_mod_aliases file:
 "286.1844" = "Unknown:286"
 "458.325" = "Unknown:458"
 "99.0321" = "Unknown:99"

### Protein Mapping

When the `--fasta-dir` option is provided, the converter maps peptide sequences to protein accessions by searching FASTA files (`.fasta`, `.fa`, `.fas`).

**Features:**
- Uses Aho-Corasick algorithm for efficient multi-pattern matching
- Caches peptide-protein mappings to disk for fast subsequent runs
- Reports first matching protein with count of total matches

**Output format:**
```
Comment: ... Protein=sp|ACCESSION| ...           # Single protein match
Comment: ... Protein=sp|ACCESSION| MultiProtein=5 ...  # Multiple matches (5 total)
```

**Cache files:** Stored in the FASTA directory as `peptide_protein_cache_<hash>.storable`

## Utility Scripts

See [README_utilities.md](README_utilities.md) for companion scripts:
- **extract_peptides.pl** - Extract unique peptide sequences from BLIB or MSP files that can be used with UniPept
- **filter_msp.pl** - Filter MSP library by peptide list

## Running Tests

```bash
perl run_tests.pl
```

## Project Structure

```
BLIB_MSP_converter/
├── blib2msp.pl          # Main conversion script
├── extract_peptides.pl  # Extract peptides from BLIB/MSP
├── filter_msp.pl        # Filter MSP by peptide list
├── run_tests.pl         # Test runner
├── README.md            # This file
├── README_utilities.md  # Utility scripts documentation
├── t/                   # Test suite
│   └── data/            # Test data files
└── unimod/              # Unimod modification database
    ├── unimod.xml       # Unimod modification definitions
    └── unimod_2.xsd     # XML schema file
```

## License
Copyright (C) 2026 Matrix Science Limited. All Rights Reserved. 

This script is free software. You can redistribute and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License or, (at your option), any later version. These modules are distributed in the hope that they will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 

Original author: Richard Jacob

## Version History

- **1.5** - Mascot Parser integration and test improvements (January 2026)
  - Replaced custom Unimod parsing with Mascot Parser `ms_modfile` for robust modification lookups
  - Replaced custom MSP parsing with Mascot Parser `ms_spectral_lib_file` for reading MSP files
  - Updated Perl requirement to **Perl 5.32.1.1** (Strawberry Perl)
- **1.4** - Protein mapping and utility scripts (January 2026)
  - Added protein mapping from FASTA files with Aho-Corasick algorithm
  - Disk caching for peptide-protein mappings (instant subsequent runs)
  - Name line uses clean peptide sequence (no mass annotations)
  - Protein field reports first match with `MultiProtein=N` count
  - Added utility scripts: `extract_peptides.pl`, `filter_msp.pl`
  - Added `--limit` option for testing with large libraries
- **1.3** - Updated MSP modification format (December 2025)
  - New parentheses-based modification format: `Mods=count(pos,aa,tag)(pos,aa,tag)...`
  - Name line includes modifications: `Name: sequence/charge_modcount(mods)`
  - Backward compatible with old slash-separated format when reading MSP files
  - Improved modification parsing from both Name line and Comment field
- **1.2** - Modification summary reporting
  - Reports unknown modifications (not in Unimod)
  - Summary count of all modifications by name, mass, and site
  - Wall clock timing for conversion
- **1.1** - Fixed MSP to BLIB conversion
  - Proper BLOB storage for peak data
  - Bidirectional Unimod lookups (name<->mass)
  - Fixed peptideSeq extraction from modified sequences
- **1.0** - Initial public release
  - Bidirectional BLIB/MSP conversion
  - Unimod modification name lookup

