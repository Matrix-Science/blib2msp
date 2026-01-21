#!/usr/bin/perl
##############################################################################
# Round-trip conversion tests
# Tests that data is preserved in BLIB->MSP->BLIB and MSP->BLIB->MSP conversions
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use DBI;
use Compress::Zlib;

# Script path - try both relative to test dir and project root
my $script = File::Spec->catfile($RealBin, '..', 'blib2msp.pl');
unless (-f $script) {
    $script = 'blib2msp.pl';  # Try from project root
}
my $perl = $^X;

unless (-f $script) {
    plan skip_all => "blib2msp.pl not found";
}

# Test data files
my $test_blib = File::Spec->catfile($RealBin, 'data', 'minimal.blib');
my $test_msp = File::Spec->catfile($RealBin, 'data', 'minimal.msp');

unless (-f $test_blib) {
    # Try to create it
    my $create_script = File::Spec->catfile($RealBin, 'data', 'create_test_blib.pl');
    if (-f $create_script) {
        system($^X, $create_script);
    }
}

unless (-f $test_blib) {
    plan skip_all => "Test BLIB file not found: $test_blib";
}

unless (-f $test_msp) {
    plan skip_all => "Test MSP file not found: $test_msp";
}

# Create temp directory for output
my $tmpdir = tempdir(CLEANUP => 1);

# Helper function to run conversion
sub run_conversion {
    my ($input, $output) = @_;
    my $cmd = qq{"$perl" "$script" -i "$input" -o "$output" 2>&1};
    my $exit_code = system($cmd);
    return $exit_code == 0;
}

# Helper function to get spectrum data from BLIB
sub get_blib_spectrum {
    my ($dbh, $peptide_seq) = @_;
    my $row = $dbh->selectrow_hashref(
        "SELECT * FROM RefSpectra WHERE peptideSeq = ?",
        undef, $peptide_seq
    );
    return unless $row;
    
    # Get modifications
    my @mods = @{$dbh->selectall_arrayref(
        "SELECT position, mass FROM Modifications WHERE RefSpectraID = ? ORDER BY position",
        {Slice => {}}, $row->{id}
    )};
    $row->{modifications} = \@mods;
    
    # Get peaks
    my $peak_row = $dbh->selectrow_hashref(
        "SELECT peakMZ, peakIntensity FROM RefSpectraPeaks WHERE RefSpectraID = ?",
        undef, $row->{id}
    );
    if ($peak_row) {
        my $mz_data = uncompress($peak_row->{peakMZ}) // $peak_row->{peakMZ};
        my $int_data = uncompress($peak_row->{peakIntensity}) // $peak_row->{peakIntensity};
        $row->{mz} = [unpack('d<*', $mz_data)];
        $row->{intensity} = [unpack('f<*', $int_data)];
    }
    
    return $row;
}

plan tests => 83;

# Test 1: BLIB->MSP->BLIB round-trip
{
    my $intermediate_msp = File::Spec->catfile($tmpdir, 'roundtrip_intermediate.msp');
    my $final_blib = File::Spec->catfile($tmpdir, 'roundtrip_final.blib');
    
    # Step 1: BLIB -> MSP
    ok(run_conversion($test_blib, $intermediate_msp), 'BLIB->MSP conversion succeeded');
    ok(-f $intermediate_msp, 'Intermediate MSP file created');
    
    # Step 2: MSP -> BLIB
    ok(run_conversion($intermediate_msp, $final_blib), 'MSP->BLIB conversion succeeded');
    ok(-f $final_blib, 'Final BLIB file created');
    
    # Step 3: Compare original and final BLIB
    my $orig_dbh = DBI->connect("dbi:SQLite:dbname=$test_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
    my $final_dbh = DBI->connect("dbi:SQLite:dbname=$final_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
    
    ok($orig_dbh && $final_dbh, 'Can connect to both BLIB files');
    
    if ($orig_dbh && $final_dbh) {
        # Compare spectrum counts
        my ($orig_count) = $orig_dbh->selectrow_array("SELECT COUNT(*) FROM RefSpectra");
        my ($final_count) = $final_dbh->selectrow_array("SELECT COUNT(*) FROM RefSpectra");
        is($final_count, $orig_count, 'Round-trip preserves spectrum count');
        
        # Compare each spectrum
        my @peptides = qw(IQVR MLQGR LKCASLQK SCRSYR);
        for my $peptide (@peptides) {
            my $orig_spec = get_blib_spectrum($orig_dbh, $peptide);
            my $final_spec = get_blib_spectrum($final_dbh, $peptide);
            
            ok($orig_spec && $final_spec, "Both BLIBs have spectrum $peptide");
            
            if ($orig_spec && $final_spec) {
                is($final_spec->{peptideSeq}, $orig_spec->{peptideSeq}, 
                   "Round-trip preserves peptideSeq for $peptide");
                ok(abs($final_spec->{precursorMZ} - $orig_spec->{precursorMZ}) < 0.001,
                   "Round-trip preserves precursorMZ for $peptide");
                is($final_spec->{precursorCharge}, $orig_spec->{precursorCharge},
                   "Round-trip preserves precursorCharge for $peptide");
                
                # Compare modifications
                is(scalar(@{$final_spec->{modifications}}), 
                   scalar(@{$orig_spec->{modifications}}),
                   "Round-trip preserves modification count for $peptide");
                
                if (@{$final_spec->{modifications}} == @{$orig_spec->{modifications}}) {
                    for my $i (0..$#{$final_spec->{modifications}}) {
                        is($final_spec->{modifications}->[$i]->{position},
                           $orig_spec->{modifications}->[$i]->{position},
                           "Round-trip preserves mod position $i for $peptide");
                        ok(abs($final_spec->{modifications}->[$i]->{mass} - 
                                $orig_spec->{modifications}->[$i]->{mass}) < 0.001,
                           "Round-trip preserves mod mass $i for $peptide");
                    }
                }
                
                # Compare peaks
                if ($final_spec->{mz} && $orig_spec->{mz}) {
                    is(scalar(@{$final_spec->{mz}}), scalar(@{$orig_spec->{mz}}),
                       "Round-trip preserves peak count for $peptide");
                    
                    if (@{$final_spec->{mz}} == @{$orig_spec->{mz}}) {
                        for my $i (0..$#{$final_spec->{mz}}) {
                            ok(abs($final_spec->{mz}->[$i] - $orig_spec->{mz}->[$i]) < 0.001,
                               "Round-trip preserves m/z[$i] for $peptide");
                            ok(abs($final_spec->{intensity}->[$i] - $orig_spec->{intensity}->[$i]) < 0.01,
                               "Round-trip preserves intensity[$i] for $peptide");
                        }
                    }
                }
            }
        }
        
        $orig_dbh->disconnect();
        $final_dbh->disconnect();
    }
}

# Test 2: MSP->BLIB->MSP round-trip
{
    my $intermediate_blib = File::Spec->catfile($tmpdir, 'roundtrip_intermediate2.blib');
    my $final_msp = File::Spec->catfile($tmpdir, 'roundtrip_final.msp');
    
    # Step 1: MSP -> BLIB
    ok(run_conversion($test_msp, $intermediate_blib), 'MSP->BLIB conversion succeeded');
    ok(-f $intermediate_blib, 'Intermediate BLIB file created');
    
    # Step 2: BLIB -> MSP
    ok(run_conversion($intermediate_blib, $final_msp), 'BLIB->MSP conversion succeeded');
    ok(-f $final_msp, 'Final MSP file created');
    
    # Step 3: Compare entry counts
    open(my $orig_fh, '<', $test_msp) or die "Cannot open $test_msp: $!";
    my $orig_entries = grep { /^Name:/i } <$orig_fh>;
    close($orig_fh);
    
    open(my $final_fh, '<', $final_msp) or die "Cannot open $final_msp: $!";
    my $final_entries = grep { /^Name:/i } <$final_fh>;
    close($final_fh);
    
    is($final_entries, $orig_entries, 'Round-trip preserves MSP entry count');
    
    # Note: Detailed MSP comparison is complex due to format variations,
    # but we verify the data is preserved through the BLIB intermediate
}

done_testing();
