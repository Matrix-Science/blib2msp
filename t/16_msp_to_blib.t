#!/usr/bin/perl
##############################################################################
# Unit tests for MSP to BLIB conversion
# Tests convert_msp_to_blib conversion by calling script and validating output
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
my $test_msp = File::Spec->catfile($RealBin, 'data', 'minimal.msp');
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

plan tests => 43;

# Test 1: Basic conversion - file creation
{
    my $output_blib = File::Spec->catfile($tmpdir, 'test_basic.blib');
    my $result = run_conversion($test_msp, $output_blib);
    
    ok($result, 'MSP to BLIB conversion succeeded');
    ok(-f $output_blib, 'BLIB output file created');
    
    if (-f $output_blib) {
        my $size = -s $output_blib;
        ok($size > 0, 'BLIB output file has content') or diag("File size: $size");
    }
}

# Test 2: Verify BLIB schema
{
    my $output_blib = File::Spec->catfile($tmpdir, 'test_schema.blib');
    run_conversion($test_msp, $output_blib);
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$output_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
    
    ok($dbh, 'Can connect to BLIB database');
    
    if ($dbh) {
        # Check required tables exist
        my @tables = qw(LibInfo RefSpectra RefSpectraPeaks Modifications ScoreTypes);
        for my $table (@tables) {
            my ($exists) = $dbh->selectrow_array(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
                undef, $table
            );
            ok($exists, "Table $table exists");
        }
        
        $dbh->disconnect();
    }
}

# Test 3: Verify LibInfo populated
{
    my $output_blib = File::Spec->catfile($tmpdir, 'test_libinfo.blib');
    run_conversion($test_msp, $output_blib);
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$output_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
    
    if ($dbh) {
        my $row = $dbh->selectrow_hashref("SELECT * FROM LibInfo");
        ok($row, 'LibInfo has data');
        is($row->{numSpecs}, 4, 'LibInfo numSpecs is 4');
        $dbh->disconnect();
    }
}

# Test 4: Verify spectrum count
{
    my $output_blib = File::Spec->catfile($tmpdir, 'test_count.blib');
    run_conversion($test_msp, $output_blib);
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$output_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
    
    if ($dbh) {
        my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM RefSpectra");
        is($count, 4, 'RefSpectra has 4 entries');
        $dbh->disconnect();
    }
}

# Test 5: Verify spectrum 1 (IQVR/2, no mods)
{
    my $output_blib = File::Spec->catfile($tmpdir, 'test_spec1.blib');
    run_conversion($test_msp, $output_blib);
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$output_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
    
    if ($dbh) {
        # Find spectrum with peptideSeq = 'IQVR'
        my $row = $dbh->selectrow_hashref(
            "SELECT * FROM RefSpectra WHERE peptideSeq = 'IQVR'"
        );
        
        ok($row, 'Spectrum 1 found');
        is($row->{peptideSeq}, 'IQVR', 'Spectrum 1 peptideSeq is IQVR');
        ok(abs($row->{precursorMZ} - 258.051) < 0.01, 'Spectrum 1 precursorMZ correct');
        is($row->{precursorCharge}, 2, 'Spectrum 1 precursorCharge is 2');
        is($row->{numPeaks}, 5, 'Spectrum 1 numPeaks is 5');
        ok(abs($row->{retentionTime} - 2.0) < 0.01, 'Spectrum 1 retentionTime correct (2.0 min)');
        ok(abs($row->{score} - 0.95) < 0.01, 'Spectrum 1 score is 0.95');
        
        # Check no modifications
        my ($mod_count) = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM Modifications WHERE RefSpectraID = ?",
            undef, $row->{id}
        );
        is($mod_count, 0, 'Spectrum 1 has no modifications');
        
        # Check peaks
        my $peak_row = $dbh->selectrow_hashref(
            "SELECT peakMZ, peakIntensity FROM RefSpectraPeaks WHERE RefSpectraID = ?",
            undef, $row->{id}
        );
        ok($peak_row, 'Spectrum 1 has peak data');
        
        if ($peak_row) {
            my $mz_data = uncompress($peak_row->{peakMZ}) // $peak_row->{peakMZ};
            my @mz = unpack('d<*', $mz_data);
            is(scalar(@mz), 5, 'Spectrum 1 has 5 m/z values');
            ok(abs($mz[0] - 175.119) < 0.01, 'Spectrum 1 first m/z correct');
        }
        
        $dbh->disconnect();
    }
}

# Test 6: Verify spectrum 2 (MLQGR/2, Oxidation)
{
    my $output_blib = File::Spec->catfile($tmpdir, 'test_spec2.blib');
    run_conversion($test_msp, $output_blib);
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$output_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
    
    if ($dbh) {
        my $row = $dbh->selectrow_hashref(
            "SELECT * FROM RefSpectra WHERE peptideSeq = 'MLQGR'"
        );
        
        ok($row, 'Spectrum 2 found');
        is($row->{peptideSeq}, 'MLQGR', 'Spectrum 2 peptideSeq is MLQGR');
        
        # Check modifications
        my $mod = $dbh->selectrow_hashref(
            "SELECT * FROM Modifications WHERE RefSpectraID = ?",
            undef, $row->{id}
        );
        ok($mod, 'Spectrum 2 has modification');
        is($mod->{position}, 1, 'Spectrum 2 mod at position 1');
        ok(abs($mod->{mass} - 15.9949) < 0.01, 'Spectrum 2 mod mass is Oxidation (15.9949)');
        
        $dbh->disconnect();
    }
}

# Test 7: Verify spectrum 3 (LKCASLQK/3, Carbamidomethyl)
{
    my $output_blib = File::Spec->catfile($tmpdir, 'test_spec3.blib');
    run_conversion($test_msp, $output_blib);
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$output_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
    
    if ($dbh) {
        my $row = $dbh->selectrow_hashref(
            "SELECT * FROM RefSpectra WHERE peptideSeq = 'LKCASLQK'"
        );
        
        ok($row, 'Spectrum 3 found');
        
        # Check modifications
        my $mod = $dbh->selectrow_hashref(
            "SELECT * FROM Modifications WHERE RefSpectraID = ?",
            undef, $row->{id}
        );
        ok($mod, 'Spectrum 3 has modification');
        is($mod->{position}, 3, 'Spectrum 3 mod at position 3');
        ok(abs($mod->{mass} - 57.021464) < 0.01, 'Spectrum 3 mod mass is Carbamidomethyl (57.021464)');
        
        $dbh->disconnect();
    }
}

# Test 8: Verify spectrum 4 (SCRSYR/3, 2 mods)
{
    my $output_blib = File::Spec->catfile($tmpdir, 'test_spec4.blib');
    run_conversion($test_msp, $output_blib);
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$output_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
    
    if ($dbh) {
        my $row = $dbh->selectrow_hashref(
            "SELECT * FROM RefSpectra WHERE peptideSeq = 'SCRSYR'"
        );
        
        ok($row, 'Spectrum 4 found');
        
        # Check modifications
        my @mods = @{$dbh->selectall_arrayref(
            "SELECT position, mass FROM Modifications WHERE RefSpectraID = ? ORDER BY position",
            {Slice => {}}, $row->{id}
        )};
        is(scalar(@mods), 2, 'Spectrum 4 has 2 modifications');
        is($mods[0]->{position}, 1, 'Spectrum 4 first mod at position 1');
        is($mods[1]->{position}, 2, 'Spectrum 4 second mod at position 2');
        ok(abs($mods[0]->{mass} - 42.010565) < 0.01, 'Spectrum 4 first mod is Acetyl');
        ok(abs($mods[1]->{mass} - 57.021464) < 0.01, 'Spectrum 4 second mod is Carbamidomethyl');
        
        $dbh->disconnect();
    }
}

# Test 9: Verify peak compression
{
    my $output_blib = File::Spec->catfile($tmpdir, 'test_peaks.blib');
    run_conversion($test_msp, $output_blib);
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$output_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
    
    if ($dbh) {
        my $row = $dbh->selectrow_hashref(
            "SELECT r.id, r.numPeaks, p.peakMZ, p.peakIntensity 
             FROM RefSpectra r 
             JOIN RefSpectraPeaks p ON r.id = p.RefSpectraID 
             WHERE r.peptideSeq = 'IQVR'"
        );
        
        ok($row, 'Found spectrum with peaks');
        
        # Try to decompress
        my $mz_data = uncompress($row->{peakMZ}) // $row->{peakMZ};
        my $int_data = uncompress($row->{peakIntensity}) // $row->{peakIntensity};
        
        my @mz = unpack('d<*', $mz_data);
        my @intensity = unpack('f<*', $int_data);
        
        is(scalar(@mz), $row->{numPeaks}, 'Decompressed m/z count matches numPeaks');
        is(scalar(@intensity), $row->{numPeaks}, 'Decompressed intensity count matches numPeaks');
        is(scalar(@mz), scalar(@intensity), 'm/z and intensity arrays have same length');
        
        $dbh->disconnect();
    }
}

# Test 10: Error handling - invalid MSP file
{
    my $invalid_msp = File::Spec->catfile($tmpdir, 'invalid.msp');
    open(my $fh, '>', $invalid_msp) or die "Cannot create $invalid_msp: $!";
    print $fh "This is not a valid MSP file\n";
    close($fh);
    
    my $output_blib = File::Spec->catfile($tmpdir, 'test_error.blib');
    my $result = run_conversion($invalid_msp, $output_blib);
    
    # Conversion might succeed but produce empty BLIB
    if (-f $output_blib) {
        my $dbh = DBI->connect("dbi:SQLite:dbname=$output_blib", '', '', {
            RaiseError => 0,
            PrintError => 0,
        });
        if ($dbh) {
            my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM RefSpectra");
            is($count, 0, 'Invalid MSP produces empty BLIB');
            $dbh->disconnect();
        }
    }
}

done_testing();
