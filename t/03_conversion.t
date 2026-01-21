#!/usr/bin/perl
##############################################################################
# Integration tests for BLIB/MSP conversion
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use File::Copy;
use DBI;

# Paths
my $script = 'blib2msp.pl';
my $perl = $^X;  # Current perl interpreter
# Use minimal test BLIB file from test data directory
my $test_blib = File::Spec->catfile('t', 'data', 'minimal.blib');
my $test_msp = File::Spec->catfile('example data', 'PRIDE_Contaminants_20160907.msp');

# Skip if test files don't exist
unless (-f $test_blib) {
    plan skip_all => "Test BLIB file not found: $test_blib";
}
unless (-f $script) {
    plan skip_all => "Conversion script not found: $script";
}

# Note: Test count is variable due to conditional tests in Test 4 (depends on number of entries)
# Use done_testing() instead of fixed plan
# Approximate: 1 (syntax) + 2 (help) + 1 (version) + 6-8 (BLIB->MSP, variable) + 16 (MSP->BLIB, if file exists) = 26-28
# If MSP file doesn't exist, skip 16 tests, so total = 10-12

# Create temp directory for output files
my $tmpdir = tempdir(CLEANUP => 1);

# Test 1: Script syntax check
{
    my $output = `"$perl" -c "$script" 2>&1`;
    like($output, qr/syntax OK/i, 'Script syntax is valid');
}

# Test 2: Help output
{
    my $output = `"$perl" "$script" --help 2>&1`;
    like($output, qr/SYNOPSIS/i, 'Help output contains SYNOPSIS');
    like($output, qr/--verbose/i, 'Help output contains --verbose option');
}

# Test 3: Version output
{
    my $output = `"$perl" "$script" --version 2>&1`;
    like($output, qr/version\s+\d+\.\d+/i, 'Version output format correct');
}

# Test 4: BLIB to MSP conversion (limited test)
{
    my $output_msp = File::Spec->catfile($tmpdir, 'test_output.msp');
    
    # Run conversion (test file is already small, no limit needed)
    my $cmd = qq{"$perl" "$script" -i "$test_blib" -o "$output_msp" 2>&1};
    my $output = `$cmd`;
    
    ok(-f $output_msp, 'MSP output file created');
    
    if (-f $output_msp) {
        # Check output file has content
        my $size = -s $output_msp;
        ok($size > 0, 'MSP output file has content') or diag("File size: $size");
        
        # Check output file format - read first line only
        open(my $fh, '<', $output_msp) or die "Cannot open $output_msp: $!";
        my $first_line = <$fh>;
        close($fh);
        
        like($first_line, qr/^Name:/i, 'MSP output starts with Name field');
        
        # Enhanced validation: Parse and verify MSP structure (streaming, stop after 3 entries)
        open($fh, '<', $output_msp) or die "Cannot open $output_msp: $!";
        
        my $current_entry = {};
        my $entries_validated = 0;
        my $entry_count = 0;
        my $in_peaks = 0;
        
        while (my $line = <$fh>) {
            chomp $line;
            if ($line =~ /^Name:\s*(.+)/i) {
                # Validate previous entry if exists
                if ($current_entry->{name} && $entries_validated < 3) {
                    ok($current_entry->{mw}, "Entry has MW field");
                    ok($current_entry->{comment}, "Entry has Comment field");
                    ok($current_entry->{num_peaks} > 0, "Entry has Num peaks field");
                    $entries_validated++;
                    # Stop after validating 3 entries
                    last if $entries_validated >= 3;
                }
                $entry_count++;
                $current_entry = { name => $1 };
                $in_peaks = 0;
            } elsif ($line =~ /^MW:\s*([\d.]+)/i) {
                $current_entry->{mw} = $1;
            } elsif ($line =~ /^Comment:\s*(.+)/i) {
                $current_entry->{comment} = $1;
            } elsif ($line =~ /^Num\s*peaks:\s*(\d+)/i) {
                $current_entry->{num_peaks} = $1;
                $in_peaks = 1;
            } elsif ($in_peaks && $line =~ /^\s*[\d.]+\s+[\d.]+/) {
                $current_entry->{peak_count}++;
            } elsif ($line eq '') {
                $in_peaks = 0;
            }
        }
        close($fh);
        
        ok($entry_count > 0, 'MSP file contains entries') or diag("Entry count: $entry_count");
        
        # Validate last entry if we didn't reach 3
        if ($current_entry->{name} && $entries_validated < 3) {
            ok($current_entry->{mw}, "Last entry has MW field");
            ok($current_entry->{comment}, "Last entry has Comment field");
        }
    } else {
        fail('MSP output file has content');
        fail('MSP output starts with Name field');
        diag("Conversion output: $output");
    }
}

# Test 5: MSP to BLIB conversion (if MSP test file exists)
SKIP: {
    skip "MSP test file not found", 16 unless -f $test_msp;
    
    my $output_blib = File::Spec->catfile($tmpdir, 'test_output.blib');
    
    # Create a small test MSP file for faster testing
    my $small_msp = File::Spec->catfile($tmpdir, 'small_test.msp');
    
    # Extract first 3 complete entries from test MSP
    # Each entry ends with a blank line after the peaks
    open(my $in_fh, '<', $test_msp) or die "Cannot open $test_msp: $!";
    open(my $out_fh, '>', $small_msp) or die "Cannot open $small_msp: $!";
    
    my $entry_count = 0;
    my $in_entry = 0;
    while (<$in_fh>) {
        if (/^Name:/i) {
            $entry_count++;
            if ($entry_count > 3) {
                last;  # Stop after 3rd entry (don't include 4th Name line)
            }
            $in_entry = 1;
        }
        if ($in_entry) {
            print $out_fh $_;
            # Stop after blank line following 3rd entry
            if (/^$/ && $entry_count == 3) {
                last;
            }
        }
    }
    close($in_fh);
    close($out_fh);
    
    # Run conversion (no verbose flag for speed)
    my $cmd = qq{"$perl" "$script" -i "$small_msp" -o "$output_blib" 2>&1};
    my $output = `$cmd`;
    my $exit_code = $? >> 8;
    
    ok(-f $output_blib, 'BLIB output file created') or diag("Conversion exit code: $exit_code\nOutput: $output");
    
    if (-f $output_blib) {
        # Verify it's a valid SQLite database
        my $dbh = eval { DBI->connect("dbi:SQLite:dbname=$output_blib", '', '', { RaiseError => 1 }) };
        ok($dbh, 'BLIB output is valid SQLite database');
        
        if ($dbh) {
            # Enhanced validation: Check schema
            my @tables = qw(LibInfo RefSpectra RefSpectraPeaks Modifications ScoreTypes);
            for my $table (@tables) {
                my ($exists) = $dbh->selectrow_array(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
                    undef, $table
                );
                ok($exists, "BLIB has $table table");
            }
            
            # Check spectrum count
            my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM RefSpectra");
            ok($count > 0, 'BLIB contains spectra') or diag("Spectrum count: $count");
            
            # Check LibInfo
            my $lib_info = $dbh->selectrow_hashref("SELECT * FROM LibInfo");
            ok($lib_info, 'LibInfo table has data');
            if ($lib_info) {
                is($lib_info->{numSpecs}, $count, 'LibInfo numSpecs matches spectrum count');
            }
            
            # Check that spectra have required fields
            if ($count > 0) {
                my $sample = $dbh->selectrow_hashref("SELECT * FROM RefSpectra LIMIT 1");
                ok($sample, 'Can retrieve sample spectrum');
                if ($sample) {
                    ok($sample->{peptideSeq}, 'Sample spectrum has peptideSeq');
                    ok($sample->{precursorMZ} > 0, 'Sample spectrum has precursorMZ');
                    ok($sample->{precursorCharge} > 0, 'Sample spectrum has precursorCharge');
                    ok($sample->{numPeaks} > 0, 'Sample spectrum has numPeaks');
                }
                
                # Check peaks exist
                my ($peak_count) = $dbh->selectrow_array(
                    "SELECT COUNT(*) FROM RefSpectraPeaks"
                );
                ok($peak_count > 0, 'BLIB has peak data') or diag("Peak count: $peak_count");
            }
            
            $dbh->disconnect();
        } else {
            fail('BLIB contains spectra');
        }
    } else {
        fail('BLIB output is valid SQLite database');
        fail('BLIB contains spectra');
        diag("Conversion output: $output");
    }
}

# Note: Some tests may be skipped if MSP file doesn't exist
# The plan is set to 29, but actual tests run may vary
done_testing();


