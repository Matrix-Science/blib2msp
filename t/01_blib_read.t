#!/usr/bin/perl
##############################################################################
# Unit tests for BLIB reading functionality
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use DBI;
use Compress::Zlib;

# Test file location - use minimal test file if available, otherwise fall back to large file
my $test_blib = File::Spec->catfile('example data', 'test_minimal.blib');
unless (-f $test_blib) {
    # Try to create minimal test file
    my $create_script = File::Spec->catfile('example data', 'create_test_blib.pl');
    if (-f $create_script) {
        system($^X, $create_script);
    }
    # Fall back to large file if minimal doesn't exist
    $test_blib = File::Spec->catfile('example data', 'M_abscessus_TP_FragPipe_ProteomeDB_search_SpecLib.blib') unless -f $test_blib;
}

# Skip all tests if test file doesn't exist
unless (-f $test_blib) {
    plan skip_all => "Test BLIB file not found: $test_blib";
}

plan tests => 15;

# Test 1: Database connection
my $dbh;
eval {
    $dbh = DBI->connect("dbi:SQLite:dbname=$test_blib", '', '', {
        RaiseError => 1,
        PrintError => 0,
    });
};
ok($dbh, 'Connect to BLIB database');
ok(!$@, 'No connection error') or diag($@);

# Test 2: LibInfo table exists and has data
{
    my $sth = $dbh->prepare("SELECT * FROM LibInfo");
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $sth->finish();
    
    ok($row, 'LibInfo table has data');
    ok(exists $row->{numSpecs}, 'LibInfo has numSpecs field');
    ok($row->{numSpecs} > 0, 'Library has spectra') or diag("numSpecs: $row->{numSpecs}");
}

# Test 3: RefSpectra table structure
{
    my $sth = $dbh->prepare("SELECT * FROM RefSpectra LIMIT 1");
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $sth->finish();
    
    ok($row, 'RefSpectra table has data');
    ok(exists $row->{peptideSeq}, 'RefSpectra has peptideSeq');
    ok(exists $row->{precursorMZ}, 'RefSpectra has precursorMZ');
    ok(exists $row->{precursorCharge}, 'RefSpectra has precursorCharge');
    ok(exists $row->{numPeaks}, 'RefSpectra has numPeaks');
}

# Test 4: Peak data extraction and decompression
{
    my $sth = $dbh->prepare(q{
        SELECT r.id, r.numPeaks, p.peakMZ, p.peakIntensity 
        FROM RefSpectra r 
        JOIN RefSpectraPeaks p ON r.id = p.RefSpectraID 
        LIMIT 1
    });
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $sth->finish();
    
    ok($row, 'Can fetch peak data');
    ok($row->{peakMZ}, 'Peak MZ blob exists');
    ok($row->{peakIntensity}, 'Peak intensity blob exists');
    
    # Test decompression
    my $mz_data = uncompress($row->{peakMZ}) // $row->{peakMZ};
    my @mz = unpack('d<*', $mz_data);
    
    my $int_data = uncompress($row->{peakIntensity}) // $row->{peakIntensity};
    my @intensity = unpack('f<*', $int_data);
    
    ok(scalar(@mz) > 0, 'Extracted MZ values') or diag("MZ count: " . scalar(@mz));
    is(scalar(@mz), scalar(@intensity), 'MZ and intensity counts match');
}

# Cleanup
$dbh->disconnect() if $dbh;

done_testing();


