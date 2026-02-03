#!/usr/bin/perl
##############################################################################
# BLIB to MSP Spectral Library Converter
##############################################################################
# COPYRIGHT NOTICE                                                           #
# Copyright (C) 2026 Matrix Science Limited  All Rights Reserved.            #
#                                                                            #
# This script is free software. You can redistribute and/or                  #
# modify it under the terms of the GNU General Public License                #
# as published by the Free Software Foundation; either version 2             #
# of the License or, (at your option), any later version.                    #
#                                                                            #
# These modules are distributed in the hope that they will be useful,        #
# but WITHOUT ANY WARRANTY; without even the implied warranty of             #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the               #
# GNU General Public License for more details.                               #
#                                                                            #
# Original author: Richard Jacob                                             #
##############################################################################
#    $Archive::blib2msp.pl                                         $ #
#     $Author: richardj@matrixscience.com $ #
#       $Date: 2:08 PM Thursday, January 15, 2026 $ #
#   $Revision:  $ #
# $NoKeywords::                                                            $ #
##############################################################################
# Version: 1.5
# Description: Bidirectional conversion between BLIB (BiblioSpec SQLite)
#              and MSP (NIST) spectral library formats
# Author: Generated for BLIB_MSP_converter project
# Date: 2025-12-05
# 
# Version History:
#   0.1 - Initial implementation with BLIB<->MSP conversion
#   0.2 - Added Unimod modification name lookup from unimod.xml
#   1.0 - Initial release
#   1.1 - Fixed MSP to BLIB conversion:
#         - Proper BLOB storage for peak data
#         - Bidirectional Unimod lookups (name<->mass)
#         - Fixed peptideSeq extraction from modified sequences
#   1.2 - Added modification summary reporting:
#         - Reports unknown modifications (not in Unimod)
#         - Summary count of all modifications by name, mass, and site
#         - Wall clock timing for conversion
#   1.3 - Updated MSP modification format:
#         - New format: Mods=count(pos,aa,tag)(pos,aa,tag)...
#         - Name line includes mods: Name: sequence/charge_modcount(mods)
#         - Backward compatible with old slash-separated format
#   1.4 - Protein mapping and performance improvements (January 2026):
#         - Added protein mapping from FASTA files with Aho-Corasick algorithm
#         - Disk caching for peptide-protein mappings
#         - Name line uses clean peptide sequence (no mass annotations)
#         - Protein field reports first match with MultiProtein=N count
#         - Added --limit option for testing with large libraries
#   1.5 - Test coverage improvements and code cleanup (January 2026):
#         - Added comprehensive test suite for conversion routines
#         - Enhanced integration tests with data validation
#         - Simplified Mascot Parser loading (removed Mascot Server Perl detection)
#         - Updated README with Perl 5.32.1.1 requirement
#         - Updated .gitignore to exclude temporary development files
##############################################################################

use strict;
use warnings;
use utf8;

use DBI;
use DBD::SQLite;
use Compress::Zlib;
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use File::Spec;
use File::Find;
use FindBin;
use Cwd;
use Carp qw(croak);
use Storable qw(nstore retrieve);
use Digest::MD5 qw(md5_hex);

# Try to load Mascot Parser (required for Unimod and MSP handling)
# msparser should be installed system-wide in C:\Strawberry\perl\lib
# IMPORTANT: Use 'our' without initialization - BEGIN block sets values at compile time,
# and 'my $var = 0' would reset them at runtime after BEGIN completes
our ($HAS_MSPARSER, $MSPARSER_PATH, $MSPARSER_ERROR);

BEGIN {
    # Initialize at compile time
    $HAS_MSPARSER = 0;
    $MSPARSER_PATH = '';
    $MSPARSER_ERROR = '';

    # Try to require msparser - it should be available if installed system-wide
    {
        local $@;
        eval {
            require msparser;
        };
        # Check if module was actually loaded by checking $INC
        if (exists($INC{'msparser.pm'})) {
            $HAS_MSPARSER = 1;
            $MSPARSER_PATH = 'system';
        } elsif ($@) {
            $MSPARSER_ERROR = $@;
        }
    }
}

# Check if loading succeeded after BEGIN block
unless ($HAS_MSPARSER) {
    die "Mascot Parser not found or could not be loaded.\n" .
        "Please ensure:\n" .
        "  1. Mascot Parser is installed system-wide (e.g., in C:\\Strawberry\\perl\\lib)\n" .
        "  2. msparser.dll is in auto/msparser/ subdirectory relative to msparser.pm\n" .
        "  3. All DLL dependencies are accessible (Visual C++ runtime, etc.)\n" .
        "\nError details: $MSPARSER_ERROR\n";
}

# Try to load parallel processing modules (optional)
my $HAS_MCE = 0;
eval {
    require MCE::Loop;
    require MCE::Shared;
    MCE::Loop->import();
    MCE::Shared->import();
    $HAS_MCE = 1;
};
if ($@) {
    warn "MCE modules not available, parallel search disabled. Install with: cpanm MCE\n" if $ENV{DEBUG};
}

# Try to load Aho-Corasick modules (optional but recommended for large FASTA files)
# Note: Algorithm::AhoCorasick::XS may have binary compatibility issues, so we skip it
# and use the pure-Perl Algorithm::AhoCorasick instead
my $HAS_AHO_CORASICK = 0;
my $AHO_CORASICK_MODULE = '';
eval {
    require Algorithm::AhoCorasick;
    require Algorithm::AhoCorasick::SearchMachine;
    $HAS_AHO_CORASICK = 1;
    $AHO_CORASICK_MODULE = 'Algorithm::AhoCorasick::SearchMachine';
};
if (!$HAS_AHO_CORASICK) {
    warn "Algorithm::AhoCorasick not available, using fallback search. Install with: cpanm Algorithm::AhoCorasick\n" if $ENV{DEBUG};
}

our $VERSION = '1.5';

# Global Unimod lookup (using msparser's ms_umod_configfile)
my $UNIMOD_LOADED = 0;
my $MASS_TOLERANCE = 0.001;  # Mass tolerance for Unimod lookup (Da)

# Hash lookups for modification name/mass conversion
my %UNIMOD_MASS_TO_NAME;   # mass -> name (for BLIB to MSP)
my %UNIMOD_NAME_TO_MASS;   # name -> mass (for MSP to BLIB)

# Preferred modification names when multiple Unimod entries share the same mass
# These are well-known modifications that should take precedence over obscure alternatives
# Key: mass rounded to 4 decimal places, Value: preferred modification name
my %PREFERRED_MODS = (
    '15.9949'  => 'Oxidation',        # vs Ala->Ser, Asn->Asp, etc.
    '57.0215'  => 'Carbamidomethyl',  # vs Ala->Glu, Gly->Asn, etc.
    '42.0106'  => 'Acetyl',           # vs Ser->Glu, etc.
    '79.9663'  => 'Phospho',          # vs Sulfo
    '0.9840'   => 'Deamidated',       # vs Asn->Asp (deamidation of N/Q)
    '28.0313'  => 'Dimethyl',         # vs Ala->Val, etc.
    '14.0157'  => 'Methyl',           # vs Gly->Ala, etc.
    '27.9949'  => 'Formyl',           # vs Ser->Cys, etc.
    '226.0776' => 'ICAT-C',           # common quantitative label
    '227.1270' => 'TMT',              # vs TMTpro (older 2-plex tag)
    '304.2072' => 'iTRAQ8plex',       # vs similar masses
    '144.1021' => 'iTRAQ4plex',       # common quantitative label
);

# Global modification tracking
# Structure: { "name|mass|site" => count }
my %MOD_SUMMARY;
my %UNKNOWN_MODS;  # Modifications not found in Unimod: { "mass|site" => count }

# Global configuration
my %config = (
    verbose     => 0,
    input       => '',
    output      => '',
    direction   => 'blib2msp',  # or 'msp2blib'
    help        => 0,
    version     => 0,
    min_peaks   => 1,           # minimum peaks to include spectrum
    unimod      => '',          # path to unimod.xml file
    fasta_dir   => '',          # directory containing FASTA files for protein mapping
    limit       => 0,           # limit number of spectra to process (0 = no limit)
);

# Logging levels
use constant {
    LOG_ERROR   => 0,
    LOG_WARN    => 1,
    LOG_INFO    => 2,
    LOG_DEBUG   => 3,
};

my $log_level = LOG_INFO;

##############################################################################
# MAIN
##############################################################################

sub main {
    parse_arguments();
    
    if ($config{help}) {
        pod2usage(-verbose => 2);
        return 0;
    }
    
    if ($config{version}) {
        print "blib2msp.pl version $VERSION\n";
        return 0;
    }
    
    $log_level = LOG_DEBUG if $config{verbose};
    
    # Validate input file
    unless ($config{input} && -f $config{input}) {
        log_msg(LOG_ERROR, "Input file not specified or does not exist: $config{input}");
        pod2usage(-verbose => 1);
        return 1;
    }
    
    # Determine direction and set default output
    if ($config{input} =~ /\.blib$/i) {
        $config{direction} = 'blib2msp';
        $config{output} ||= $config{input} =~ s/\.blib$/.msp/ir;
    } elsif ($config{input} =~ /\.msp$/i) {
        $config{direction} = 'msp2blib';
        $config{output} ||= $config{input} =~ s/\.msp$/.blib/ir;
    } else {
        log_msg(LOG_ERROR, "Cannot determine conversion direction from file extension. Use .blib or .msp");
        return 1;
    }
    
    log_msg(LOG_INFO, "=== BLIB/MSP Converter v$VERSION ===");
    log_msg(LOG_INFO, "Input:  $config{input}");
    log_msg(LOG_INFO, "Output: $config{output}");
    log_msg(LOG_INFO, "Direction: $config{direction}");
    
    # Record start time
    my $start_time = time();
    my $start_timestamp = get_timestamp();
    log_msg(LOG_INFO, "Conversion started: $start_timestamp");
    
    # Load Unimod definitions for modification name lookup
    load_unimod($config{unimod});
    
    # Reset modification tracking
    %MOD_SUMMARY = ();
    %UNKNOWN_MODS = ();
    
    my $result;
    if ($config{direction} eq 'blib2msp') {
        $result = convert_blib_to_msp($config{input}, $config{output});
    } else {
        $result = convert_msp_to_blib($config{input}, $config{output});
    }
    
    # Record end time and print summary
    my $end_time = time();
    my $end_timestamp = get_timestamp();
    my $elapsed = $end_time - $start_time;
    my $elapsed_str = format_duration($elapsed);
    
    log_msg(LOG_INFO, "Conversion ended: $end_timestamp");
    log_msg(LOG_INFO, "Wall clock time: $elapsed_str");
    
    # Print modification summary
    print_modification_summary();
    
    return $result ? 0 : 1;
}

##############################################################################
# ARGUMENT PARSING
##############################################################################

sub parse_arguments {
    GetOptions(
        'input|i=s'     => \$config{input},
        'output|o=s'   => \$config{output},
        'verbose|v'    => \$config{verbose},
        'min-peaks=i'  => \$config{min_peaks},
        'unimod|u=s'   => \$config{unimod},
        'fasta-dir|f=s' => \$config{fasta_dir},
        'limit=i'      => \$config{limit},
        'help|h|?'     => \$config{help},
        'version'      => \$config{version},
    ) or pod2usage(-verbose => 1);
    
    # If positional argument given, use as input
    $config{input} ||= shift @ARGV if @ARGV;
}

##############################################################################
# LOGGING
##############################################################################

sub log_msg {
    my ($level, $msg) = @_;
    return if $level > $log_level;
    
    my @prefixes = ('ERROR', 'WARN', 'INFO', 'DEBUG');
    my $prefix = $prefixes[$level] // 'LOG';
    my $timestamp = get_timestamp();
    
    print STDERR "[$timestamp] [$prefix] $msg\n";
}

sub get_timestamp {
    my @t = localtime();
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
        $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

sub format_duration {
    my ($seconds) = @_;
    
    if ($seconds < 60) {
        return sprintf("%d seconds", $seconds);
    } elsif ($seconds < 3600) {
        my $min = int($seconds / 60);
        my $sec = $seconds % 60;
        return sprintf("%d min %d sec", $min, $sec);
    } else {
        my $hr = int($seconds / 3600);
        my $min = int(($seconds % 3600) / 60);
        my $sec = $seconds % 60;
        return sprintf("%d hr %d min %d sec", $hr, $min, $sec);
    }
}

sub track_modification {
    my ($mass, $site, $name) = @_;
    
    # Track known modifications
    if (defined $name) {
        my $key = sprintf("%s|%.4f|%s", $name, $mass, $site);
        $MOD_SUMMARY{$key}++;
    } else {
        # Track unknown modifications (not in Unimod)
        my $key = sprintf("%.4f|%s", $mass, $site);
        $UNKNOWN_MODS{$key}++;
    }
}

sub print_modification_summary {
    log_msg(LOG_INFO, "");
    log_msg(LOG_INFO, "=== Modification Summary ===");
    
    # Print known modifications
    if (%MOD_SUMMARY) {
        log_msg(LOG_INFO, "");
        log_msg(LOG_INFO, "Known Modifications (Unimod):");
        log_msg(LOG_INFO, sprintf("  %-25s %12s %6s %8s", "Name", "Mass", "Site", "Count"));
        log_msg(LOG_INFO, "  " . "-" x 55);
        
        # Sort by count descending
        my @sorted = sort { $MOD_SUMMARY{$b} <=> $MOD_SUMMARY{$a} } keys %MOD_SUMMARY;
        
        for my $key (@sorted) {
            my ($name, $mass, $site) = split /\|/, $key;
            log_msg(LOG_INFO, sprintf("  %-25s %12.6f %6s %8d", $name, $mass, $site, $MOD_SUMMARY{$key}));
        }
        
        my $total = 0;
        $total += $_ for values %MOD_SUMMARY;
        log_msg(LOG_INFO, "  " . "-" x 55);
        log_msg(LOG_INFO, sprintf("  %-25s %12s %6s %8d", "TOTAL", "", "", $total));
    } else {
        log_msg(LOG_INFO, "  No known modifications found.");
    }
    
    # Print unknown modifications
    if (%UNKNOWN_MODS) {
        log_msg(LOG_INFO, "");
        log_msg(LOG_INFO, "Unknown Modifications (not in Unimod - possibly from open mass search):");
        log_msg(LOG_INFO, sprintf("  %12s %6s %8s", "Mass", "Site", "Count"));
        log_msg(LOG_INFO, "  " . "-" x 30);
        
        # Sort by count descending
        my @sorted = sort { $UNKNOWN_MODS{$b} <=> $UNKNOWN_MODS{$a} } keys %UNKNOWN_MODS;
        
        for my $key (@sorted) {
            my ($mass, $site) = split /\|/, $key;
            log_msg(LOG_INFO, sprintf("  %12.4f %6s %8d", $mass, $site, $UNKNOWN_MODS{$key}));
        }
        
        my $total = 0;
        $total += $_ for values %UNKNOWN_MODS;
        log_msg(LOG_INFO, "  " . "-" x 30);
        log_msg(LOG_INFO, sprintf("  %12s %6s %8d", "TOTAL", "", $total));
    }
    
    log_msg(LOG_INFO, "");
}

##############################################################################
# UNIMOD LOADING AND LOOKUP
##############################################################################

sub load_unimod {
    my ($unimod_file) = @_;

    return if $UNIMOD_LOADED;

    unless ($HAS_MSPARSER) {
        log_msg(LOG_WARN, "Mascot Parser not available. Cannot load Unimod definitions.");
        return;
    }

    # Try to find unimod.xml if not specified
    unless ($unimod_file && -f $unimod_file) {
        my @search_paths = (
            # Check unimod/ subdirectory first (standard location with script)
            File::Spec->catfile(dirname($0), 'unimod', 'unimod.xml'),
            'unimod/unimod.xml',
            # Legacy locations
            'unimod.xml',
            'documentation/unimod.xml',
            File::Spec->catfile(dirname($0), 'unimod.xml'),
            File::Spec->catfile(dirname($0), 'documentation', 'unimod.xml'),
        );

        for my $path (@search_paths) {
            if (-f $path) {
                $unimod_file = $path;
                last;
            }
        }
    }

    unless ($unimod_file && -f $unimod_file) {
        log_msg(LOG_WARN, "Unimod file not found. Modification names will be displayed as masses.");
        return;
    }

    # Find unimod_2.xsd schema file
    my $schema_file;
    my @schema_paths = (
        # First check same directory as unimod.xml
        File::Spec->catfile(dirname($unimod_file), 'unimod_2.xsd'),
        'msparser/config/unimod_2.xsd',
        File::Spec->catfile(dirname($0), 'msparser', 'config', 'unimod_2.xsd'),
        File::Spec->catfile($MSPARSER_PATH, '..', 'config', 'unimod_2.xsd'),
    );

    for my $path (@schema_paths) {
        if (-f $path) {
            $schema_file = $path;
            last;
        }
    }

    unless ($schema_file && -f $schema_file) {
        log_msg(LOG_WARN, "Unimod schema file (unimod_2.xsd) not found. Cannot load Unimod definitions.");
        return;
    }

    log_msg(LOG_INFO, "Loading Unimod definitions from: $unimod_file using Mascot Parser");

    # Parse unimod.xml using ms_umod_configfile
    my $unimod = new msparser::ms_umod_configfile();
    $unimod->setFileName($unimod_file);
    $unimod->setSchemaFileName($schema_file);
    $unimod->read_file();

    unless ($unimod->isValid()) {
        log_msg(LOG_ERROR, "Failed to load Unimod file: " . $unimod->getLastErrorString());
        return;
    }

    my $num_mods = $unimod->getNumberOfModifications();
    log_msg(LOG_DEBUG, "Found $num_mods modifications in Unimod file");

    # Hash to collect all modifications by mass
    # Structure: mass_key => [ { title => ..., delta => ..., approved => ... }, ... ]
    my %mods_by_mass;

    for my $i (0 .. $num_mods - 1) {
        my $mod = $unimod->getModificationByNumber($i);
        next unless $mod;

        my $title = $mod->getTitle();
        next unless $title;

        # Get monoisotopic mass from delta composition
        my $delta = $mod->getDelta();
        next unless $delta;

        my $mono_mass = $delta->getMonoMass();
        next unless defined $mono_mass;

        # Check if approved (attribute from XML)
        my $approved = $mod->isApproved() ? 1 : 0;

        # Round mass for lookup key (4 decimal places)
        my $mass_key = sprintf("%.4f", $mono_mass);

        push @{$mods_by_mass{$mass_key}}, {
            title     => $title,
            delta     => $mono_mass + 0,
            approved  => $approved,
        };
    }

    # Build final lookups:
    # 1) mass -> name (for BLIB to MSP)
    # 2) name -> mass (for MSP to BLIB)
    # Priority: 1) preferred mods, 2) approved first, 3) alphabetically first by title
    for my $mass_key (keys %mods_by_mass) {
        my @mods = @{$mods_by_mass{$mass_key}};
        my $selected_name;

        # First check if there's a preferred modification for this mass
        if (exists $PREFERRED_MODS{$mass_key}) {
            my $preferred = $PREFERRED_MODS{$mass_key};
            # Check if the preferred mod exists in our list
            my ($preferred_mod) = grep { $_->{title} eq $preferred } @mods;
            if ($preferred_mod) {
                $selected_name = $preferred;
                log_msg(LOG_DEBUG, "Unimod: mass=$mass_key -> $selected_name (preferred)");
            }
        }

        # If no preferred mod found, use standard sorting
        unless ($selected_name) {
            # Sort: approved first, then alphabetically by title
            @mods = sort {
                ($b->{approved} <=> $a->{approved})  # approved first
                    ||
                (lc($a->{title}) cmp lc($b->{title}))  # then alphabetically
            } @mods;

            $selected_name = $mods[0]->{title};
            log_msg(LOG_DEBUG, "Unimod: mass=$mass_key -> $selected_name" .
                ($mods[0]->{approved} ? " (approved)" : ""));
        }

        # Use the selected match for mass->name
        $UNIMOD_MASS_TO_NAME{$mass_key} = $selected_name;

        # Build name->mass lookup (use first occurrence for each name)
        for my $mod (@mods) {
            my $name = $mod->{title};
            # Only set if not already set (prefer approved/alphabetically first)
            $UNIMOD_NAME_TO_MASS{$name} //= $mod->{delta};
        }
    }

    my $mass_count = scalar keys %UNIMOD_MASS_TO_NAME;
    my $name_count = scalar keys %UNIMOD_NAME_TO_MASS;
    log_msg(LOG_INFO, "Loaded $mass_count unique masses, $name_count unique names from Unimod");

    $UNIMOD_LOADED = 1;
}

sub lookup_unimod_name {
    my ($mass) = @_;

    return undef unless $UNIMOD_LOADED && defined $mass;

    # First try exact hash lookup (fast)
    my $mass_key = sprintf("%.4f", $mass);
    return $UNIMOD_MASS_TO_NAME{$mass_key} if exists $UNIMOD_MASS_TO_NAME{$mass_key};

    # Try with tolerance - search nearby masses in cache
    my $best_match;
    my $best_diff = $MASS_TOLERANCE + 1;

    for my $key (keys %UNIMOD_MASS_TO_NAME) {
        my $diff = abs($key - $mass);
        if ($diff < $best_diff && $diff <= $MASS_TOLERANCE) {
            $best_diff = $diff;
            $best_match = $UNIMOD_MASS_TO_NAME{$key};
        }
    }

    return $best_match;
}

sub lookup_unimod_mass {
    my ($name) = @_;

    return undef unless $UNIMOD_LOADED && defined $name;

    # First try exact hash lookup (fast)
    return $UNIMOD_NAME_TO_MASS{$name} if exists $UNIMOD_NAME_TO_MASS{$name};

    # Try case-insensitive lookup in cache
    for my $key (keys %UNIMOD_NAME_TO_MASS) {
        if (lc($key) eq lc($name)) {
            return $UNIMOD_NAME_TO_MASS{$key};
        }
    }

    return undef;
}

##############################################################################
# BLIB TO MSP CONVERSION
##############################################################################

sub convert_blib_to_msp {
    my ($blib_file, $msp_file) = @_;
    
    log_msg(LOG_INFO, "Starting BLIB to MSP conversion...");
    
    # Connect to BLIB database
    my $dbh = eval { 
        DBI->connect("dbi:SQLite:dbname=$blib_file", '', '', {
            RaiseError => 1,
            PrintError => 0,
            sqlite_unicode => 1,
        });
    };
    
    if ($@ || !$dbh) {
        log_msg(LOG_ERROR, "Failed to open BLIB file: " . ($@ || 'Unknown error'));
        return 0;
    }
    
    log_msg(LOG_DEBUG, "Connected to BLIB database");
    
    # Get library info
    my $lib_info = get_library_info($dbh);
    log_msg(LOG_INFO, "Library: $lib_info->{libLSID}");
    log_msg(LOG_INFO, "Created: $lib_info->{createTime}");
    log_msg(LOG_INFO, "Spectra count: $lib_info->{numSpecs}");
    
    # Open output file
    open(my $out_fh, '>:encoding(UTF-8)', $msp_file) 
        or croak "Cannot open output file $msp_file: $!";
    
    # Process spectra
    my $stats = process_blib_spectra($dbh, $out_fh);
    
    close($out_fh);
    $dbh->disconnect();
    
    log_msg(LOG_INFO, "Conversion complete!");
    log_msg(LOG_INFO, "  Total spectra processed: $stats->{total}");
    log_msg(LOG_INFO, "  Spectra written: $stats->{written}");
    log_msg(LOG_INFO, "  Spectra skipped: $stats->{skipped}");
    
    # Report protein mapping statistics
    if ($config{fasta_dir} || $stats->{with_proteins} > 0) {
        log_msg(LOG_INFO, "");
        log_msg(LOG_INFO, "Protein Mapping Statistics:");
        log_msg(LOG_INFO, "  Spectra with protein matches: $stats->{with_proteins}");
        log_msg(LOG_INFO, "  Spectra with unique protein match: $stats->{unique_proteins}");
        if ($stats->{with_proteins} > 0) {
            my $multi_protein = $stats->{with_proteins} - $stats->{unique_proteins};
            log_msg(LOG_INFO, "  Spectra with multiple protein matches: $multi_protein");
        }
    }
    
    return 1;
}

sub get_library_info {
    my ($dbh) = @_;
    
    my $sth = $dbh->prepare("SELECT * FROM LibInfo");
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $sth->finish();
    
    return $row || {};
}

sub process_blib_spectra {
    my ($dbh, $out_fh) = @_;
    
    my %stats = (
        total => 0, 
        written => 0, 
        skipped => 0,
        with_proteins => 0,      # Spectra with protein matches
        unique_proteins => 0,     # Spectra with unique (single) protein match
    );
    
    # Get score types for reference
    my %score_types = get_score_types($dbh);
    
    # Query all spectra with peaks
    # First, check which columns exist in RefSpectra (schema varies by BLIB version)
    my @available_cols = map { $_->{name} } @{$dbh->selectall_arrayref(
        "PRAGMA table_info(RefSpectra)", { Slice => {} }
    )};
    my %has_col = map { $_ => 1 } @available_cols;

    # Build SELECT clause based on available columns
    my @select_cols = qw(r.id r.peptideSeq r.precursorMZ r.precursorCharge
                         r.peptideModSeq r.prevAA r.nextAA r.numPeaks
                         r.retentionTime r.score r.scoreType);

    # Add optional columns if they exist
    push @select_cols, 'r.totalIonCurrent' if $has_col{totalIonCurrent};
    push @select_cols, 'r.collisionalCrossSectionSqA' if $has_col{collisionalCrossSectionSqA};
    push @select_cols, 'r.ionMobility' if $has_col{ionMobility};
    push @select_cols, 'r.ionMobilityType' if $has_col{ionMobilityType};
    push @select_cols, 'r.SpecIDinFile' if $has_col{SpecIDinFile};
    push @select_cols, 'r.fileID' if $has_col{fileID};

    # Always include peak data
    push @select_cols, qw(p.peakMZ p.peakIntensity);

    my $sql = "SELECT " . join(", ", @select_cols) . q{
        FROM RefSpectra r
        JOIN RefSpectraPeaks p ON r.id = p.RefSpectraID
        ORDER BY r.id
    };

    my $sth = $dbh->prepare($sql);
    $sth->execute();
    
    # Get modifications lookup
    my %modifications = get_all_modifications($dbh);
    
    # Get proteins lookup from BLIB (if available)
    my %proteins = get_all_proteins($dbh);
    
    # Build optimized FASTA peptide-to-protein index if FASTA directory is provided
    my %peptide_to_proteins;  # peptide_seq -> [accession1, accession2, ...]
    if ($config{fasta_dir} && -d $config{fasta_dir}) {
        # Get unique peptides from BLIB for targeted indexing
        my @unique_peptides = get_unique_peptides_from_blib($dbh);
        
        if (@unique_peptides) {
            # Build or load peptide-protein mapping (with caching and parallel search)
            %peptide_to_proteins = get_or_build_peptide_cache($config{fasta_dir}, \@unique_peptides);
        } else {
            log_msg(LOG_WARN, "No peptide sequences found in BLIB, skipping FASTA mapping");
        }
    }
    
    # Progress tracking
    my $progress_interval = 1000;
    
    while (my $row = $sth->fetchrow_hashref()) {
        $stats{total}++;
        
        # Limit processing if --limit option is set
        if ($config{limit} > 0 && $stats{written} >= $config{limit}) {
            log_msg(LOG_INFO, "Reached limit of $config{limit} spectra, stopping");
            last;
        }
        
        # Progress logging
        if ($stats{total} % $progress_interval == 0) {
            log_msg(LOG_INFO, "  Processing spectrum $stats{total}...");
        }
        
        # Skip if too few peaks
        if ($row->{numPeaks} < $config{min_peaks}) {
            log_msg(LOG_DEBUG, "Skipping spectrum $row->{id}: only $row->{numPeaks} peaks");
            $stats{skipped}++;
            next;
        }
        
        # Decompress and extract peaks
        my ($mz_ref, $int_ref) = extract_peaks($row->{peakMZ}, $row->{peakIntensity}, $row->{numPeaks});
        
        unless ($mz_ref && $int_ref && @$mz_ref > 0) {
            log_msg(LOG_WARN, "Failed to extract peaks for spectrum $row->{id}");
            $stats{skipped}++;
            next;
        }
        
        # Get modifications for this spectrum
        my @mods = @{$modifications{$row->{id}} || []};
        
        # Get protein accessions for this spectrum
        my @protein_accessions = @{$proteins{$row->{id}} || []};
        my $from_blib = scalar(@protein_accessions) > 0;
        
        # If no BLIB proteins and FASTA mapping available, use pre-built index (O(1) lookup)
        if (!@protein_accessions && %peptide_to_proteins) {
            # Use unmodified peptide sequence (peptideSeq) for lookup
            my $peptide_seq = $row->{peptideSeq} || '';
            
            # If peptideSeq is empty, extract unmodified sequence from peptideModSeq
            unless ($peptide_seq) {
                $peptide_seq = $row->{peptideModSeq} || '';
                # Remove modification annotations: M(O), C[+57.0], etc.
                $peptide_seq =~ s/\([^)]+\)//g;    # Remove parenthetical modifications like M(O)
                $peptide_seq =~ s/\[[^\]]+\]//g;   # Remove bracket modifications like C[+57.0]
            }
            
            # Ensure sequence is clean
            $peptide_seq =~ s/\([^)]+\)//g;    # Remove parenthetical modifications
            $peptide_seq =~ s/\[[^\]]+\]//g;   # Remove bracket modifications
            $peptide_seq =~ s/[^A-ZX]//g;      # Keep only amino acid letters
            
            # O(1) hash lookup - the mapping was pre-built using Aho-Corasick
            if ($peptide_seq && exists $peptide_to_proteins{$peptide_seq}) {
                @protein_accessions = @{$peptide_to_proteins{$peptide_seq}};
            }
        }
        
        # Track protein match statistics
        if (@protein_accessions) {
            $stats{with_proteins}++;
            if (scalar(@protein_accessions) == 1) {
                $stats{unique_proteins}++;
            }
        }
        
        # Format and write MSP entry
        my $msp_entry = format_msp_entry($row, $mz_ref, $int_ref, \@mods, \%score_types, \@protein_accessions);
        print $out_fh $msp_entry, "\n";
        
        $stats{written}++;
    }
    
    $sth->finish();
    
    return \%stats;
}

sub get_score_types {
    my ($dbh) = @_;
    
    my %types;
    my $sth = $dbh->prepare("SELECT id, scoreType FROM ScoreTypes");
    $sth->execute();
    while (my ($id, $type) = $sth->fetchrow_array()) {
        $types{$id} = $type;
    }
    $sth->finish();
    
    return %types;
}

sub get_all_modifications {
    my ($dbh) = @_;
    
    my %mods;
    my $sth = $dbh->prepare("SELECT RefSpectraID, position, mass FROM Modifications ORDER BY RefSpectraID, position");
    $sth->execute();
    
    while (my ($spec_id, $pos, $mass) = $sth->fetchrow_array()) {
        push @{$mods{$spec_id}}, { position => $pos, mass => $mass };
    }
    $sth->finish();
    
    return %mods;
}

sub get_all_proteins {
    my ($dbh) = @_;
    
    my %proteins;
    
    # Check if Proteins and RefSpectraProteins tables exist
    my $tables_check = $dbh->prepare("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('Proteins', 'RefSpectraProteins')");
    $tables_check->execute();
    my @tables = map { $_->[0] } @{$tables_check->fetchall_arrayref()};
    $tables_check->finish();
    
    unless (@tables == 2) {
        log_msg(LOG_DEBUG, "Protein tables not found in BLIB, skipping protein extraction");
        return %proteins;
    }
    
    my $sth = $dbh->prepare(q{
        SELECT rsp.RefSpectraId, p.accession
        FROM RefSpectraProteins rsp
        JOIN Proteins p ON rsp.ProteinId = p.id
        ORDER BY rsp.RefSpectraId, p.accession
    });
    $sth->execute();
    
    while (my ($spec_id, $accession) = $sth->fetchrow_array()) {
        push @{$proteins{$spec_id}}, $accession;
    }
    $sth->finish();
    
    return %proteins;
}

# Extract all unique peptide sequences from BLIB for Aho-Corasick indexing
sub get_unique_peptides_from_blib {
    my ($dbh) = @_;
    
    my $sth = $dbh->prepare("SELECT DISTINCT peptideSeq FROM RefSpectra WHERE peptideSeq IS NOT NULL AND peptideSeq != ''");
    $sth->execute();
    
    my @peptides;
    while (my ($seq) = $sth->fetchrow_array()) {
        # Clean the sequence
        $seq =~ s/\([^)]+\)//g;    # Remove parenthetical modifications
        $seq =~ s/\[[^\]]+\]//g;   # Remove bracket modifications
        $seq =~ s/[^A-ZX]//g;      # Keep only amino acid letters
        
        # Only include peptides of reasonable length (>= 5 aa)
        push @peptides, $seq if $seq && length($seq) >= 5;
    }
    $sth->finish();
    
    # Remove duplicates
    my %seen;
    @peptides = grep { !$seen{$_}++ } @peptides;
    
    log_msg(LOG_INFO, "Found " . scalar(@peptides) . " unique peptide sequences in BLIB");
    
    return @peptides;
}

# Build Aho-Corasick automaton from peptide list
sub build_peptide_automaton {
    my ($peptides_ref) = @_;
    
    return undef unless $HAS_AHO_CORASICK && @$peptides_ref;
    
    log_msg(LOG_INFO, "Building Aho-Corasick automaton with " . scalar(@$peptides_ref) . " peptides using $AHO_CORASICK_MODULE...");
    
    my $ac;
    eval {
        if ($AHO_CORASICK_MODULE eq 'Algorithm::AhoCorasick::XS') {
            $ac = Algorithm::AhoCorasick::XS->new($peptides_ref);
        } else {
            # Algorithm::AhoCorasick::SearchMachine takes a list of keywords, not an arrayref
            $ac = Algorithm::AhoCorasick::SearchMachine->new(@$peptides_ref);
        }
    };
    
    if ($@) {
        log_msg(LOG_WARN, "Failed to build Aho-Corasick automaton: $@");
        return undef;
    }
    
    log_msg(LOG_INFO, "Aho-Corasick automaton built successfully");
    return $ac;
}

# Search proteins in parallel using MCE and Aho-Corasick
sub search_proteins_parallel {
    my ($proteins_ref, $ac, $peptides_ref) = @_;
    
    my %peptide_to_proteins;
    my @accessions = keys %$proteins_ref;
    my $total_proteins = scalar(@accessions);
    
    log_msg(LOG_INFO, "Searching $total_proteins proteins for " . scalar(@$peptides_ref) . " peptides...");
    
    if ($HAS_MCE && $HAS_AHO_CORASICK && $ac) {
        # Parallel search with MCE
        my $num_cpus = MCE::Util::get_ncpu();
        log_msg(LOG_INFO, "Using parallel search with $num_cpus CPU cores");
        
        # Create shared hash for results
        tie my %shared_results, 'MCE::Shared';
        
        MCE::Loop->init(
            max_workers => $num_cpus,
            chunk_size => 'auto',
        );
        
        mce_loop {
            my ($mce, $chunk_ref, $chunk_id) = @_;
            my %local_results;
            
            for my $accession (@$chunk_ref) {
                my $seq = $proteins_ref->{$accession};
                next unless $seq;

                # Search for all peptides in this protein sequence using feed()
                my %matched_peptides;
                $ac->feed($seq, sub {
                    my ($pos, $keyword) = @_;
                    $matched_peptides{$keyword} = 1;
                    return undef;  # Continue searching
                });

                for my $peptide (keys %matched_peptides) {
                    $local_results{$peptide} //= [];
                    push @{$local_results{$peptide}}, $accession
                        unless grep { $_ eq $accession } @{$local_results{$peptide}};
                }
            }
            
            # Merge local results into shared hash
            for my $peptide (keys %local_results) {
                my $existing = $shared_results{$peptide} || [];
                my %seen = map { $_ => 1 } @$existing;
                for my $acc (@{$local_results{$peptide}}) {
                    push @$existing, $acc unless $seen{$acc}++;
                }
                $shared_results{$peptide} = $existing;
            }
        } @accessions;
        
        MCE::Loop->finish();
        
        # Copy shared results to regular hash
        %peptide_to_proteins = %shared_results;
        untie %shared_results;
        
    } elsif ($HAS_AHO_CORASICK && $ac) {
        # Single-threaded Aho-Corasick search
        log_msg(LOG_INFO, "Using single-threaded Aho-Corasick search (MCE not available)");
        
        my $processed = 0;
        my $progress_interval = 100000;
        
        for my $accession (@accessions) {
            my $seq = $proteins_ref->{$accession};
            next unless $seq;

            # Search for all peptides in this protein sequence using feed()
            my %matched_peptides;
            $ac->feed($seq, sub {
                my ($pos, $keyword) = @_;
                $matched_peptides{$keyword} = 1;
                return undef;  # Continue searching
            });

            for my $peptide (keys %matched_peptides) {
                $peptide_to_proteins{$peptide} //= [];
                push @{$peptide_to_proteins{$peptide}}, $accession
                    unless grep { $_ eq $accession } @{$peptide_to_proteins{$peptide}};
            }

            $processed++;
            if ($processed % $progress_interval == 0) {
                log_msg(LOG_INFO, "  Processed $processed / $total_proteins proteins...");
            }
        }
    } else {
        # Fallback: sequential index() search (slowest)
        log_msg(LOG_INFO, "Using fallback sequential search (Aho-Corasick not available)");
        
        my $processed = 0;
        my $progress_interval = 100000;
        
        for my $accession (@accessions) {
            my $seq = $proteins_ref->{$accession};
            next unless $seq;
            
            for my $peptide (@$peptides_ref) {
                if (index($seq, $peptide) >= 0) {
                    $peptide_to_proteins{$peptide} //= [];
                    push @{$peptide_to_proteins{$peptide}}, $accession
                        unless grep { $_ eq $accession } @{$peptide_to_proteins{$peptide}};
                }
            }
            
            $processed++;
            if ($processed % $progress_interval == 0) {
                log_msg(LOG_INFO, "  Processed $processed / $total_proteins proteins...");
            }
        }
    }
    
    my $matched_peptides = scalar(keys %peptide_to_proteins);
    log_msg(LOG_INFO, "Found matches for $matched_peptides peptides");
    
    return %peptide_to_proteins;
}

# Compute cache key based on FASTA files and peptide list
sub compute_cache_key {
    my ($fasta_dir, $peptides_ref) = @_;
    
    # Find all FASTA files
    my @fasta_files;
    find(sub {
        if (-f $_ && /\.(fasta|fa|fas)$/i) {
            push @fasta_files, $File::Find::name;
        }
    }, $fasta_dir);
    
    @fasta_files = sort @fasta_files;
    
    # Build key from: file names + modification times + sorted peptides
    my $key_data = '';
    for my $file (@fasta_files) {
        my @stat = stat($file);
        my $mtime = $stat[9] || 0;
        my $size = $stat[7] || 0;
        $key_data .= "$file:$mtime:$size;";
    }
    
    # Add sorted peptide list hash
    my $peptide_hash = md5_hex(join("\n", sort @$peptides_ref));
    $key_data .= "peptides:$peptide_hash";
    
    return md5_hex($key_data);
}

# Get peptide-to-protein mapping from cache or build it
sub get_or_build_peptide_cache {
    my ($fasta_dir, $peptides_ref) = @_;
    
    my %peptide_to_proteins;
    
    # Compute cache key
    my $cache_key = compute_cache_key($fasta_dir, $peptides_ref);
    my $cache_file = File::Spec->catfile($fasta_dir, "peptide_protein_cache_$cache_key.storable");
    
    # Try to load from cache
    if (-f $cache_file) {
        log_msg(LOG_INFO, "Loading peptide-protein mapping from cache: $cache_file");
        eval {
            my $cached = retrieve($cache_file);
            if ($cached && ref($cached) eq 'HASH') {
                %peptide_to_proteins = %$cached;
                log_msg(LOG_INFO, "Loaded " . scalar(keys %peptide_to_proteins) . " peptide mappings from cache");
                return %peptide_to_proteins;
            }
        };
        if ($@) {
            log_msg(LOG_WARN, "Failed to load cache: $@");
        }
    }
    
    # Build index from scratch
    log_msg(LOG_INFO, "Building peptide-protein index (this may take a few minutes)...");
    
    # Load proteins from FASTA
    my %proteins = build_fasta_peptide_index($fasta_dir);
    
    if (!%proteins) {
        log_msg(LOG_WARN, "No proteins loaded from FASTA files");
        return %peptide_to_proteins;
    }
    
    # Build Aho-Corasick automaton
    my $ac = build_peptide_automaton($peptides_ref);
    
    # Search proteins
    %peptide_to_proteins = search_proteins_parallel(\%proteins, $ac, $peptides_ref);
    
    # Save to cache
    log_msg(LOG_INFO, "Saving peptide-protein mapping to cache: $cache_file");
    eval {
        nstore(\%peptide_to_proteins, $cache_file);
        log_msg(LOG_INFO, "Cache saved successfully");
    };
    if ($@) {
        log_msg(LOG_WARN, "Failed to save cache: $@");
    }
    
    return %peptide_to_proteins;
}

sub extract_peaks {
    my ($mz_blob, $int_blob, $expected_peaks) = @_;
    
    return ([], []) unless $mz_blob && $int_blob;
    
    # Try to decompress MZ data (may be zlib compressed)
    my $mz_data = uncompress($mz_blob);
    $mz_data //= $mz_blob;  # Use raw if decompression fails
    
    # Try to decompress intensity data
    my $int_data = uncompress($int_blob);
    $int_data //= $int_blob;  # Use raw if decompression fails
    
    # Unpack as little-endian: doubles for m/z, floats for intensity
    my @mz = unpack('d<*', $mz_data);
    my @intensity = unpack('f<*', $int_data);
    
    # Validate
    if (@mz != $expected_peaks) {
        log_msg(LOG_DEBUG, "Peak count mismatch: expected $expected_peaks, got " . scalar(@mz) . " m/z values");
    }
    
    if (@mz != @intensity) {
        log_msg(LOG_WARN, "M/Z and intensity count mismatch: " . scalar(@mz) . " vs " . scalar(@intensity));
        # Truncate to shorter length
        my $min_len = @mz < @intensity ? scalar(@mz) : scalar(@intensity);
        @mz = @mz[0..$min_len-1];
        @intensity = @intensity[0..$min_len-1];
    }
    
    return (\@mz, \@intensity);
}

sub format_msp_entry {
    my ($row, $mz_ref, $int_ref, $mods_ref, $score_types_ref, $protein_accessions_ref) = @_;
    
    # Default to empty array if not provided
    $protein_accessions_ref ||= [];
    
    my @lines;
    
    # Build modification strings for Name line and Mods field
    my @mod_strs;
    my $seq = $row->{peptideSeq} || '';
    my $mod_count = scalar(@$mods_ref);
    
    for my $mod (@$mods_ref) {
        my $pos = $mod->{position};
        my $aa = $pos > 0 && $pos <= length($seq) ? substr($seq, $pos-1, 1) : '?';
        
        # Look up Unimod name, fall back to mass if not found
        my $mod_name = lookup_unimod_name($mod->{mass});
        
        # Track modification for summary
        track_modification($mod->{mass}, $aa, $mod_name);
        
        # Format as (pos,aa,tag) for new format
        my $tag = $mod_name || sprintf("%.4f", $mod->{mass});
        push @mod_strs, sprintf("(%d,%s,%s)", $pos, $aa, $tag);
    }
    
    # Name: peptideModSeq/charge_modcount(mods)
    my $peptide_seq = $row->{peptideModSeq} || $row->{peptideSeq} || '';
    my $name = $peptide_seq . '/' . $row->{precursorCharge} . '_' . $mod_count;
    $name .= join('', @mod_strs) if @mod_strs;
    push @lines, "Name: $name";
    
    # MW: calculated from precursor m/z and charge
    # MW = (m/z * charge) - (charge * proton_mass)
    my $proton_mass = 1.007276;
    my $mw = ($row->{precursorMZ} * $row->{precursorCharge}) - ($row->{precursorCharge} * $proton_mass);
    push @lines, sprintf("MW: %.6f", $mw);
    
    # Build Comment field
    my @comments;
    
    # Parent (precursor m/z)
    push @comments, sprintf("Parent=%.4f", $row->{precursorMZ});
    
    # Modifications: Mods=count(mods) or Mods=0
    if (@$mods_ref) {
        push @comments, "Mods=" . $mod_count . join('', @mod_strs);
    } else {
        push @comments, "Mods=0";
    }
    
    # Protein accessions - format as Protein=sp|ACCESSION| (UniProt format)
    if (@$protein_accessions_ref) {
        my $protein_count = scalar(@$protein_accessions_ref);
        
        # Format each accession as sp|ACCESSION| (UniProt format)
        # If accession already has format prefix (sp|, tr|, etc.), use as-is
        # Otherwise, assume it's a Swiss-Prot accession and add sp| prefix
        my @formatted_accessions;
        for my $acc (@$protein_accessions_ref) {
            if ($acc =~ /^[a-z]+\|/) {
                # Already has format prefix (sp|, tr|, etc.)
                push @formatted_accessions, $acc . '|' unless $acc =~ /\|$/;
                push @formatted_accessions, $acc if $acc =~ /\|$/;
            } else {
                # Add sp| prefix and trailing |
                push @formatted_accessions, "sp|$acc|";
            }
        }
        
        if ($protein_count == 1) {
            push @comments, "Protein=$formatted_accessions[0]";
        } else {
            # Multiple proteins: comma-separated list and MultiProtein flag
            push @comments, "Protein=" . join(',', @formatted_accessions);
            push @comments, "MultiProtein=1";
        }
    }
    
    # Retention time (in seconds for MSP)
    if (defined $row->{retentionTime} && $row->{retentionTime} > 0) {
        push @comments, sprintf("RetentionTime=%.2f", $row->{retentionTime} * 60);  # BLIB stores minutes
    }
    
    # Score
    if (defined $row->{score}) {
        my $score_type = $score_types_ref->{$row->{scoreType}} || 'Unknown';
        push @comments, sprintf("Score=%.6f", $row->{score});
        push @comments, "ScoreType=$score_type";
    }
    
    # Total ion current
    if (defined $row->{totalIonCurrent} && $row->{totalIonCurrent} > 0) {
        push @comments, sprintf("TIC=%.2f", $row->{totalIonCurrent});
    }
    
    # Collisional cross section
    if (defined $row->{collisionalCrossSectionSqA} && $row->{collisionalCrossSectionSqA} > 0) {
        push @comments, sprintf("CCS=%.4f", $row->{collisionalCrossSectionSqA});
    }
    
    # Ion mobility
    if (defined $row->{ionMobility} && $row->{ionMobility} > 0) {
        push @comments, sprintf("IonMobility=%.6f", $row->{ionMobility});
    }
    
    # Spectrum ID in file
    if ($row->{SpecIDinFile}) {
        push @comments, "SpecIDinFile=$row->{SpecIDinFile}";
    }
    
    # Flanking residues
    my $prev_aa = $row->{prevAA} || '-';
    my $next_aa = $row->{nextAA} || '-';
    if ($prev_aa ne '-' || $next_aa ne '-') {
        push @comments, "Fullname=$prev_aa.$row->{peptideModSeq}.$next_aa/$row->{precursorCharge}";
    }
    
    push @lines, "Comment: " . join(' ', @comments);
    
    # Num peaks
    push @lines, "Num peaks: " . scalar(@$mz_ref);
    
    # Peak list (sorted by m/z)
    my @peak_indices = sort { $mz_ref->[$a] <=> $mz_ref->[$b] } (0..$#$mz_ref);
    for my $i (@peak_indices) {
        push @lines, sprintf("%.4f %.2f", $mz_ref->[$i], $int_ref->[$i]);
    }
    
    return join("\n", @lines);
}

##############################################################################
# MSP TO BLIB CONVERSION
##############################################################################

sub convert_msp_to_blib {
    my ($msp_file, $blib_file) = @_;
    
    log_msg(LOG_INFO, "Starting MSP to BLIB conversion...");
    
    # Remove existing output file
    if (-e $blib_file) {
        unlink($blib_file) or croak "Cannot remove existing file $blib_file: $!";
    }
    
    # Create new BLIB database
    my $dbh = eval {
        DBI->connect("dbi:SQLite:dbname=$blib_file", '', '', {
            RaiseError => 1,
            PrintError => 0,
            sqlite_unicode => 1,
        });
    };
    
    if ($@ || !$dbh) {
        log_msg(LOG_ERROR, "Failed to create BLIB file: " . ($@ || 'Unknown error'));
        return 0;
    }
    
    # Create schema
    create_blib_schema($dbh);
    log_msg(LOG_DEBUG, "Created BLIB schema");
    
    # Parse MSP file and insert spectra
    my $stats = parse_and_insert_msp($dbh, $msp_file);
    
    # Update library info
    update_library_info($dbh, $stats->{written});
    
    $dbh->disconnect();
    
    log_msg(LOG_INFO, "Conversion complete!");
    log_msg(LOG_INFO, "  Total spectra parsed: $stats->{total}");
    log_msg(LOG_INFO, "  Spectra written: $stats->{written}");
    log_msg(LOG_INFO, "  Spectra skipped: $stats->{skipped}");
    
    return 1;
}

sub create_blib_schema {
    my ($dbh) = @_;
    
    # LibInfo table
    $dbh->do(q{
        CREATE TABLE LibInfo (
            libLSID TEXT,
            createTime TEXT,
            numSpecs INTEGER,
            majorVersion INTEGER,
            minorVersion INTEGER
        )
    });
    
    # RefSpectra table
    $dbh->do(q{
        CREATE TABLE RefSpectra (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            peptideSeq VARCHAR(150),
            precursorMZ REAL,
            precursorCharge INTEGER,
            peptideModSeq VARCHAR(200),
            prevAA CHAR(1),
            nextAA CHAR(1),
            copies INTEGER,
            numPeaks INTEGER,
            ionMobility REAL,
            collisionalCrossSectionSqA REAL,
            ionMobilityHighEnergyOffset REAL,
            ionMobilityType TINYINT,
            retentionTime REAL,
            startTime REAL,
            endTime REAL,
            totalIonCurrent REAL,
            moleculeName VARCHAR(128),
            chemicalFormula VARCHAR(128),
            precursorAdduct VARCHAR(128),
            inchiKey VARCHAR(128),
            otherKeys VARCHAR(128),
            fileID INTEGER,
            SpecIDinFile VARCHAR(256),
            score REAL,
            scoreType TINYINT
        )
    });
    
    # RefSpectraPeaks table
    $dbh->do(q{
        CREATE TABLE RefSpectraPeaks (
            RefSpectraID INTEGER,
            peakMZ BLOB,
            peakIntensity BLOB
        )
    });
    
    # Modifications table
    $dbh->do(q{
        CREATE TABLE Modifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            RefSpectraID INTEGER,
            position INTEGER,
            mass REAL
        )
    });
    
    # ScoreTypes table
    $dbh->do(q{
        CREATE TABLE ScoreTypes (
            id INTEGER PRIMARY KEY,
            scoreType VARCHAR(128),
            probabilityType VARCHAR(128)
        )
    });
    
    # Insert default score types
    $dbh->do("INSERT INTO ScoreTypes VALUES (0, 'UNKNOWN', 'NOT_A_PROBABILITY_VALUE')");
    $dbh->do("INSERT INTO ScoreTypes VALUES (19, 'GENERIC Q-VALUE', 'PROBABILITY_THAT_IDENTIFICATION_IS_INCORRECT')");
    
    # IonMobilityTypes table
    $dbh->do(q{
        CREATE TABLE IonMobilityTypes (
            id INTEGER PRIMARY KEY,
            ionMobilityType VARCHAR(128)
        )
    });
    $dbh->do("INSERT INTO IonMobilityTypes VALUES (0, 'none')");
    
    # SpectrumSourceFiles table
    $dbh->do(q{
        CREATE TABLE SpectrumSourceFiles (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            fileName VARCHAR(512),
            idFileName VARCHAR(512),
            cutoffScore REAL
        )
    });
    
    # Proteins table
    $dbh->do(q{
        CREATE TABLE Proteins (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            accession VARCHAR(200)
        )
    });
    
    # RefSpectraProteins table
    $dbh->do(q{
        CREATE TABLE RefSpectraProteins (
            RefSpectraId INTEGER NOT NULL,
            ProteinId INTEGER NOT NULL
        )
    });
    
    # RefSpectraPeakAnnotations table
    $dbh->do(q{
        CREATE TABLE RefSpectraPeakAnnotations (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            RefSpectraID INTEGER NOT NULL,
            peakIndex INTEGER NOT NULL,
            name VARCHAR(256),
            formula VARCHAR(256),
            inchiKey VARCHAR(256),
            otherKeys VARCHAR(256),
            charge INTEGER,
            adduct VARCHAR(256),
            comment VARCHAR(256),
            mzTheoretical REAL NOT NULL,
            mzObserved REAL NOT NULL
        )
    });
}

sub parse_and_insert_msp {
    my ($dbh, $msp_file) = @_;
    
    my %stats = (total => 0, written => 0, skipped => 0);
    
    unless ($HAS_MSPARSER) {
        log_msg(LOG_ERROR, "Mascot Parser not available. Cannot parse MSP file.");
        return \%stats;
    }
    
    # Use Mascot Parser ms_spectral_lib_file to read MSP file
    my $msp_lib = new msparser::ms_spectral_lib_file($msp_file, '', '');
    
    unless ($msp_lib->isValid) {
        log_msg(LOG_ERROR, "Failed to open MSP file: " . $msp_lib->getLastErrorString);
        return \%stats;
    }
    
    my $num_entries = $msp_lib->getNumEntries();
    log_msg(LOG_INFO, "Found $num_entries entries in MSP file");
    
    # Prepare statements
    my $spec_sth = $dbh->prepare(q{
        INSERT INTO RefSpectra (
            peptideSeq, precursorMZ, precursorCharge, peptideModSeq,
            prevAA, nextAA, copies, numPeaks, ionMobility,
            collisionalCrossSectionSqA, ionMobilityHighEnergyOffset,
            ionMobilityType, retentionTime, totalIonCurrent, score, scoreType
        ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, 0, 0, 0, 0, ?, ?, ?, 0)
    });
    
    my $peak_sth = $dbh->prepare(q{
        INSERT INTO RefSpectraPeaks (RefSpectraID, peakMZ, peakIntensity)
        VALUES (?, ?, ?)
    });
    
    my $mod_sth = $dbh->prepare(q{
        INSERT INTO Modifications (RefSpectraID, position, mass)
        VALUES (?, ?, ?)
    });
    
    my $protein_sth = $dbh->prepare(q{
        INSERT INTO Proteins (accession) VALUES (?)
    });
    
    my $spectrum_protein_sth = $dbh->prepare(q{
        INSERT INTO RefSpectraProteins (RefSpectraId, ProteinId)
        VALUES (?, ?)
    });
    
    # Cache for protein IDs by accession
    my %protein_id_cache;
    
    $dbh->begin_work;
    
    my $progress_interval = 1000;
    
    # Iterate through all entries using Mascot Parser
    for my $entry_num (1 .. $num_entries) {
        $stats{total}++;
        
        if ($stats{total} % $progress_interval == 0) {
            log_msg(LOG_INFO, "  Processing entry $stats{total}...");
            $dbh->commit;
            $dbh->begin_work;
        }
        
        # Get entry using Mascot Parser
        my $entry = $msp_lib->getEntryFromNumber($entry_num);
        
        unless (defined $entry && $entry->isValid) {
            log_msg(LOG_DEBUG, "Skipping invalid entry $entry_num");
            $stats{skipped}++;
            next;
        }
        
        # Process entry and insert into database
        my $result = process_msp_entry_from_parser($entry, $spec_sth, $peak_sth, $mod_sth,
            $protein_sth, $spectrum_protein_sth, $dbh, \%protein_id_cache);
        
        if ($result) {
            $stats{written}++;
        } else {
            $stats{skipped}++;
        }
    }
    
    $dbh->commit;
    
    return \%stats;
}

# Process MSP entry from Mascot Parser ms_spectral_lib_entry object
sub process_msp_entry_from_parser {
    my ($entry, $spec_sth, $peak_sth, $mod_sth, $protein_sth, $spectrum_protein_sth, $dbh, $protein_id_cache_ref) = @_;
    
    # Extract data from ms_spectral_lib_entry
    my $name = $entry->getName();
    my $precursor_mz = $entry->getPrecursorMZ();
    my $charge = $entry->getCharge();
    my $sequence = $entry->getSequence();
    my $comment = $entry->getComment();
    my $mw = $entry->getMW();
    
    # Skip if no valid data
    return 0 unless $name && defined $precursor_mz && defined $charge;
    
    my $num_peaks = $entry->getNumPeaks();
    return 0 if $num_peaks == 0;
    
    # Get peak list - try with NIST format conversion (parameter 1)
    # This may return a different structure that's easier to work with
    my $peak_list = $entry->getPeakList(1);  # 1 = convert to NIST format
    return 0 unless defined $peak_list;
    
    # Parse name to get sequence, charge, and modifications
    # New format: Name: <sequence>/<charge>_<mod_count>(pos,aa,tag)...
    # Old format: Name: <sequence>/<charge>
    my ($peptide_mod_seq, @name_mods) = ('', ());
    
    if ($name =~ /^(.+)\/(\d+)_(\d+)(.*)$/) {
        # New format: sequence/charge_modcount(mods)
        $peptide_mod_seq = $1;
        $charge = $2;  # Override charge from entry
        my $mod_count = $3;
        my $mod_string = $4;  # Contains (pos,aa,tag)(pos,aa,tag)... or empty if mod_count is 0
        @name_mods = parse_modifications_from_string($mod_string);
    } elsif ($name =~ /^(.+)\/(\d+)$/) {
        # Old format: sequence/charge
        $peptide_mod_seq = $1;
        $charge = $2;  # Override charge from entry
    } else {
        $peptide_mod_seq = $name;
    }
    
    # Note: We prefer the sequence parsed from the Name line over getSequence()
    # because msparser's getSequence() can return malformed sequences
    # (e.g., missing opening brackets in modification notation)
    
    # Extract unmodified sequence (remove modification notations)
    my $peptide_seq = $peptide_mod_seq;
    $peptide_seq =~ s/\([^)]+\)//g;    # Remove parenthetical modifications like M(O)
    $peptide_seq =~ s/\[[^\]]+\]//g;   # Remove bracket modifications like C[+57.0]
    
    # Parse comment for additional fields
    my %comment_fields = parse_comment($comment);
    
    # Use precursor m/z from entry, or calculate from MW if not available
    if (!$precursor_mz || $precursor_mz == 0) {
        if ($mw > 0) {
            my $proton_mass = 1.007276;
            $precursor_mz = ($mw + $charge * $proton_mass) / $charge;
        } else {
            $precursor_mz = $comment_fields{Parent} // 0;
        }
    }
    
    # Retention time (convert from seconds to minutes for BLIB)
    my $rt = ($comment_fields{RetentionTime} // 0) / 60;
    
    # TIC
    my $tic = $comment_fields{TIC} // 0;
    
    # Score
    my $score = $comment_fields{Score} // 0;
    
    # Flanking residues
    my ($prev_aa, $next_aa) = ('-', '-');
    if ($comment_fields{Fullname} && $comment_fields{Fullname} =~ /^(.)\..*\.(.)\//) {
        $prev_aa = $1;
        $next_aa = $2;
    }
    
    # Extract peaks from peak list
    # Mascot Parser's getPeakList returns an array ref of tab-separated "mz\tintensity" strings
    my @mz;
    my @intensity;

    if (ref($peak_list) eq 'ARRAY') {
        for my $peak_str (@$peak_list) {
            if ($peak_str =~ /^([\d.]+)\s+([\d.]+)/) {
                push @mz, $1;
                push @intensity, $2;
            }
        }
    } else {
        log_msg(LOG_DEBUG, "Unexpected peak list type: " . ref($peak_list));
        return 0;
    }
    
    return 0 unless @mz && @intensity;
    
    # Insert spectrum
    $spec_sth->execute(
        $peptide_seq,
        $precursor_mz,
        $charge,
        $peptide_mod_seq,
        $prev_aa,
        $next_aa,
        scalar(@mz),
        $rt,
        $tic,
        $score
    );
    
    my $spec_id = $dbh->last_insert_id('', '', 'RefSpectra', 'id');
    
    # Pack and insert peaks
    my $mz_blob = pack('d<*', @mz);
    my $int_blob = pack('f<*', @intensity);
    
    # Compress blobs
    my $mz_compressed = compress($mz_blob);
    my $int_compressed = compress($int_blob);
    
    # Use compressed if smaller
    $mz_blob = length($mz_compressed) < length($mz_blob) ? $mz_compressed : $mz_blob;
    $int_blob = length($int_compressed) < length($int_blob) ? $int_compressed : $int_blob;
    
    # Bind BLOB data explicitly with SQL_BLOB type
    $peak_sth->bind_param(1, $spec_id);
    $peak_sth->bind_param(2, $mz_blob, { TYPE => DBI::SQL_BLOB });
    $peak_sth->bind_param(3, $int_blob, { TYPE => DBI::SQL_BLOB });
    $peak_sth->execute();
    
    # Parse and insert modifications
    # Collect modifications from both Name line and Comment Mods field
    my %mods_by_pos;
    
    # Add modifications from Name line
    for my $mod (@name_mods) {
        $mods_by_pos{$mod->{position}} = $mod;
    }
    
    # Note: Modifications are parsed from the Comment field (Mods=...)
    # The entry's getMods() method has compatibility issues, so we rely on Comment parsing
    
    # Parse modifications from Comment Mods field
    if ($comment_fields{Mods} && $comment_fields{Mods} !~ /^0$/) {
        my $mods_value = $comment_fields{Mods};
        
        # Check if new format: Mods=count(pos,aa,tag)(pos,aa,tag)...
        if ($mods_value =~ /^\d+\(/) {
            # New format: extract count and modification string
            my ($count, $mod_string) = $mods_value =~ /^(\d+)(.*)$/;
            my @comment_mods = parse_modifications_from_string($mod_string);
            
            # Add to hash (Name line mods take precedence if same position)
            for my $mod (@comment_mods) {
                $mods_by_pos{$mod->{position}} //= $mod;
            }
        } else {
            # Old format: Mods=count/pos,aa,tag/pos,aa,tag
            my @mod_parts = split(/\//, $mods_value);
            shift @mod_parts;  # Remove count
            for my $mod_str (@mod_parts) {
                if ($mod_str =~ /^(\d+),([A-Z?]),(.+)$/) {
                    my ($pos, $aa, $tag) = ($1, $2, $3);
                    $mods_by_pos{$pos} //= {
                        position => $pos,
                        aa => $aa,
                        tag => $tag,
                    };
                }
            }
        }
    }
    
    # Insert all modifications
    for my $pos (sort { $a <=> $b } keys %mods_by_pos) {
        my $mod = $mods_by_pos{$pos};
        my $mass;
        my $mod_name;
        
        # Determine if tag is numeric (mass) or text (Unimod name)
        if ($mod->{tag} =~ /^-?[\d.]+$/) {
            $mass = $mod->{tag};
            $mod_name = lookup_unimod_name($mass);
        } else {
            $mod_name = $mod->{tag};
            $mass = lookup_mod_mass($mod_name);
        }
        
        if (defined $mass) {
            # Track modification for summary
            track_modification($mass, $mod->{aa}, $mod_name);
            $mod_sth->execute($spec_id, $pos, $mass);
        }
    }
    
    # Parse and insert proteins from Protein= field
    if ($comment_fields{Protein}) {
        my $protein_value = $comment_fields{Protein};
        
        # Parse format: sp|ACCESSION| or sp|ACC1|,sp|ACC2|,...
        # Extract accessions (remove sp| prefix and trailing |)
        my @accessions;
        # Match patterns like: sp|ACC| or tr|ACC| (with trailing |)
        # Format: [prefix|]accession|
        while ($protein_value =~ /(?:^|,)([a-z]+\|)?([^|]+)\|/g) {
            my $prefix = $1 || '';
            my $acc = $2;
            # Skip if empty or just whitespace
            if ($acc && $acc =~ /\S/) {
                # Store accession without prefix (just the ID)
                push @accessions, $acc;
            }
        }
        
        # Insert proteins
        for my $accession (@accessions) {
            # Get or create protein ID
            my $protein_id;
            if (exists $protein_id_cache_ref->{$accession}) {
                $protein_id = $protein_id_cache_ref->{$accession};
            } else {
                # Check if protein already exists
                my ($existing_id) = $dbh->selectrow_array(
                    "SELECT id FROM Proteins WHERE accession = ?", 
                    undef, $accession
                );
                
                if ($existing_id) {
                    $protein_id = $existing_id;
                } else {
                    $protein_sth->execute($accession);
                    $protein_id = $dbh->last_insert_id('', '', 'Proteins', 'id');
                }
                $protein_id_cache_ref->{$accession} = $protein_id;
            }
            
            # Link spectrum to protein
            $spectrum_protein_sth->execute($spec_id, $protein_id);
        }
    }
    
    return 1;
}

sub parse_comment {
    my ($comment) = @_;
    my %fields;
    
    return %fields unless $comment;
    
    # Parse key=value or key="value" pairs
    while ($comment =~ /(\w+)=(?:"([^"]+)"|(\S+))/g) {
        my $key = $1;
        my $value = defined $2 ? $2 : $3;
        $fields{$key} = $value;
    }
    
    return %fields;
}

sub parse_modifications_from_string {
    my ($mod_string) = @_;
    
    return () unless $mod_string;
    
    my @mods;
    
    # Parse format: (pos,aa,tag)(pos,aa,tag)...
    while ($mod_string =~ /\((\d+),([A-Z?]),([^)]+)\)/g) {
        my ($pos, $aa, $tag) = ($1, $2, $3);
        push @mods, {
            position => $pos,
            aa => $aa,
            tag => $tag,
        };
    }
    
    return @mods;
}

sub lookup_mod_mass {
    my ($mod_name) = @_;
    
    # First try Unimod lookup
    my $mass = lookup_unimod_mass($mod_name);
    return $mass if defined $mass;
    
    # Fallback to hardcoded common modifications
    my %mods = (
        'Oxidation'          => 15.9949,
        'Carbamidomethyl'    => 57.021465,
        'Acetyl'             => 42.0106,
        'Phospho'            => 79.9663,
        'Deamidated'         => 0.9840,
        'Methyl'             => 14.0157,
        'Dimethyl'           => 28.0314,
        'Trimethyl'          => 42.0470,
        'Ubiquitin'          => 114.0429,  # GlyGly
    );
    
    return $mods{$mod_name};
}

# Build an index of protein sequences (accession -> sequence) for fast lookup
sub build_fasta_peptide_index {
    my ($fasta_dir) = @_;
    
    return () unless $fasta_dir && -d $fasta_dir;
    
    my %protein_index;  # accession -> sequence (for fast searching)
    
    # Find all FASTA files in directory
    my @fasta_files;
    find(sub {
        if (-f $_ && /\.(fasta|fa|fas)$/i) {
            push @fasta_files, $File::Find::name;
        }
    }, $fasta_dir);
    
    unless (@fasta_files) {
        log_msg(LOG_WARN, "No FASTA files found in directory: $fasta_dir");
        return %protein_index;
    }
    
    log_msg(LOG_INFO, "Indexing " . scalar(@fasta_files) . " FASTA file(s)...");
    
    my $file_count = 0;
    my $total_proteins = 0;
    my $total_seq_length = 0;
    
    # Process each FASTA file
    for my $fasta_file (@fasta_files) {
        $file_count++;
        log_msg(LOG_INFO, "  Processing FASTA file $file_count/" . scalar(@fasta_files) . ": " . basename($fasta_file));
        
        open(my $fh, '<:encoding(UTF-8)', $fasta_file)
            or do {
                log_msg(LOG_WARN, "Cannot open FASTA file: $fasta_file: $!");
                next;
            };
        
        my $current_accession = '';
        my $current_seq = '';
        
        while (my $line = <$fh>) {
            chomp $line;
            $line =~ s/\r//g;  # Remove CR if present
            
            if ($line =~ /^>/) {
                # Process previous sequence if we have one
                if ($current_accession && $current_seq && length($current_seq) > 0) {
                    $total_proteins++;
                    $total_seq_length += length($current_seq);
                    $protein_index{$current_accession} = $current_seq;
                }
                
                # Extract accession from header (format: >sp|ACCESSION| or >ACCESSION)
                if ($line =~ /^>\s*([a-z]+\|)?([^|\s]+)/) {
                    $current_accession = $2;  # Get accession without prefix
                } else {
                    $current_accession = '';
                }
                $current_seq = '';
            } else {
                $current_seq .= $line;
            }
        }
        
        # Process last sequence
        if ($current_accession && $current_seq && length($current_seq) > 0) {
            $total_proteins++;
            $total_seq_length += length($current_seq);
            $protein_index{$current_accession} = $current_seq;
        }
        
        close($fh);
    }
    
    my $avg_seq_len = $total_proteins > 0 ? int($total_seq_length / $total_proteins) : 0;
    log_msg(LOG_INFO, "Indexed $total_proteins proteins (avg length: $avg_seq_len aa, total: " . 
           int($total_seq_length / 1000) . "K aa)");
    
    return %protein_index;
}

sub search_fasta_for_peptide {
    my ($fasta_dir, $peptide_seq) = @_;
    
    return () unless $fasta_dir && $peptide_seq && -d $fasta_dir;
    
    my @accessions;
    my %seen_accessions;  # Avoid duplicates
    
    # Find all FASTA files in directory
    my @fasta_files;
    find(sub {
        if (-f $_ && /\.(fasta|fa|fas)$/i) {
            push @fasta_files, $File::Find::name;
        }
    }, $fasta_dir);
    
    unless (@fasta_files) {
        log_msg(LOG_WARN, "No FASTA files found in directory: $fasta_dir");
        return ();
    }
    
    log_msg(LOG_DEBUG, "Searching for peptide '$peptide_seq' in " . scalar(@fasta_files) . " FASTA file(s)");
    
    # Search each FASTA file
    for my $fasta_file (@fasta_files) {
        open(my $fh, '<:encoding(UTF-8)', $fasta_file)
            or do {
                log_msg(LOG_WARN, "Cannot open FASTA file: $fasta_file: $!");
                next;
            };
        
        my $current_accession = '';
        my $current_seq = '';
        my $in_header = 0;
        
        while (my $line = <$fh>) {
            chomp $line;
            $line =~ s/\r//g;  # Remove CR if present
            
            if ($line =~ /^>/) {
                # Process previous sequence if we have one
                if ($current_accession && $current_seq) {
                    if (index($current_seq, $peptide_seq) >= 0) {
                        unless ($seen_accessions{$current_accession}) {
                            push @accessions, $current_accession;
                            $seen_accessions{$current_accession} = 1;
                        }
                    }
                }
                
                # Parse new header: >accession description
                # Extract accession (first word after >)
                if ($line =~ /^>\s*(\S+)/) {
                    $current_accession = $1;
                    $current_seq = '';
                    $in_header = 1;
                } else {
                    $current_accession = '';
                    $current_seq = '';
                }
            } else {
                # Sequence line - accumulate sequence
                if ($current_accession) {
                    $current_seq .= $line;
                    $in_header = 0;
                }
            }
        }
        
        # Process last sequence
        if ($current_accession && $current_seq) {
            if (index($current_seq, $peptide_seq) >= 0) {
                unless ($seen_accessions{$current_accession}) {
                    push @accessions, $current_accession;
                    $seen_accessions{$current_accession} = 1;
                }
            }
        }
        
        close($fh);
    }
    
    log_msg(LOG_DEBUG, "Found peptide '$peptide_seq' in " . scalar(@accessions) . " protein(s)");
    
    return @accessions;
}

sub update_library_info {
    my ($dbh, $num_specs) = @_;
    
    my $lsid = 'urn:lsid:proteome.gs.washington.edu:spectral_library:bibliospec:nr:converted.blib';
    my $create_time = scalar localtime();
    
    $dbh->do(q{
        INSERT INTO LibInfo (libLSID, createTime, numSpecs, majorVersion, minorVersion)
        VALUES (?, ?, ?, 1, 10)
    }, undef, $lsid, $create_time, $num_specs);
}

##############################################################################
# RUN
##############################################################################

# Allow module import for testing - only run main() when executed directly
unless (caller) {
    exit main();
}

1;  # Return true for module loading

__END__

=head1 NAME

blib2msp.pl - Bidirectional BLIB/MSP spectral library converter

=head1 VERSION

Version 1.3

=head1 SYNOPSIS

  blib2msp.pl [options] <input_file>

  Options:
    -i, --input FILE     Input file (.blib or .msp)
    -o, --output FILE    Output file (default: input with changed extension)
    -u, --unimod FILE    Path to unimod.xml for modification name lookup
    -f, --fasta-dir DIR  Directory containing FASTA files for protein mapping
    -v, --verbose        Enable verbose/debug logging
        --min-peaks N    Minimum peaks required per spectrum (default: 1)
        --limit N        Limit number of spectra to process (for testing)
    -h, --help           Show full help message
        --version        Show version number

=head1 DESCRIPTION

Converts between BiblioSpec BLIB format (SQLite-based) and NIST MSP format
spectral libraries. The conversion direction is automatically determined
from the input file extension.

=head1 EXAMPLES

Convert BLIB to MSP:

  blib2msp.pl -i library.blib -o library.msp

Convert MSP to BLIB:

  blib2msp.pl -i library.msp -o library.blib

Verbose mode with minimum peak filter:

  blib2msp.pl -v --min-peaks 10 -i library.blib

Convert BLIB to MSP with protein mapping from FASTA files:

  blib2msp.pl -i library.blib -f /path/to/fasta/directory

Test with small subset (first 50 spectra):

  blib2msp.pl -i library.blib -f /path/to/fasta/directory --limit 50

=head1 FILE FORMATS

=head2 BLIB Format

BiblioSpec SQLite database containing:
  - RefSpectra: spectrum metadata
  - RefSpectraPeaks: m/z and intensity as compressed BLOBs
  - Modifications: peptide modifications
  - LibInfo: library metadata

=head2 MSP Format

NIST text format with entries containing:
  - Name: peptide/charge_modcount(mods)
  - MW: molecular weight
  - Comment: metadata key=value pairs including:
    - Parent: precursor m/z
    - Mods: modifications in format count(pos,aa,tag)(pos,aa,tag)...
    - Protein: protein accession in UniProt format (e.g., sp|ACCESSION| or sp|ACC1|,sp|ACC2|)
    - MultiProtein: set to 1 if peptide matches multiple proteins
    - RetentionTime, Score, ScoreType, TIC, CCS, IonMobility, etc.
  - Num peaks: peak count
  - Peak list: m/z intensity pairs

=head2 Protein Mapping

When converting BLIB to MSP, protein accession numbers can be obtained from:
  1. BLIB database (if Proteins and RefSpectraProteins tables are populated)
  2. FASTA file search (if --fasta-dir option is provided)

Protein accessions are formatted in UniProt format: Protein=sp|ACCESSION|
For multiple proteins: Protein=sp|ACC1|,sp|ACC2|,sp|ACC3| with MultiProtein=1

When converting MSP to BLIB, the Protein= field is parsed and stored in the
Proteins and RefSpectraProteins tables.

=cut

