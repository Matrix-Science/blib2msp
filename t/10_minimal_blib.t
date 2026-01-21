#!/usr/bin/perl
##############################################################################
# Unit tests for minimal test BLIB file
# Tests BLIB reading with known test data
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use FindBin qw($RealBin);
use DBI;
use Compress::Zlib;

# Find test BLIB file
my $test_blib = File::Spec->catfile($RealBin, 'data', 'minimal.blib');

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

plan tests => 20;

# Connect to database
my $dbh = DBI->connect("dbi:SQLite:dbname=$test_blib", '', '', {
    RaiseError => 1,
    PrintError => 0,
});
ok($dbh, 'Connect to minimal test BLIB');

# Test LibInfo
{
    my ($numSpecs) = $dbh->selectrow_array("SELECT numSpecs FROM LibInfo");
    is($numSpecs, 4, 'LibInfo shows 4 spectra');
}

# Test spectrum count
{
    my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM RefSpectra");
    is($count, 4, 'RefSpectra has 4 entries');
}

# Test spectrum 1: IQVR (no mods)
{
    my $row = $dbh->selectrow_hashref("SELECT * FROM RefSpectra WHERE id = 1");
    is($row->{peptideSeq}, 'IQVR', 'Spectrum 1 peptideSeq is IQVR');
    is($row->{precursorCharge}, 2, 'Spectrum 1 charge is 2');
    
    my ($mod_count) = $dbh->selectrow_array("SELECT COUNT(*) FROM Modifications WHERE RefSpectraID = 1");
    is($mod_count, 0, 'Spectrum 1 has no modifications');
}

# Test spectrum 2: MLQGR with Oxidation at M1
{
    my $row = $dbh->selectrow_hashref("SELECT * FROM RefSpectra WHERE id = 2");
    is($row->{peptideSeq}, 'MLQGR', 'Spectrum 2 peptideSeq is MLQGR');
    
    my $mod = $dbh->selectrow_hashref("SELECT * FROM Modifications WHERE RefSpectraID = 2");
    is($mod->{position}, 1, 'Spectrum 2 mod at position 1');
    ok(abs($mod->{mass} - 15.9949) < 0.01, 'Spectrum 2 mod mass is Oxidation');
}

# Test spectrum 3: LKCASLQK with Carbamidomethyl at C3
{
    my $row = $dbh->selectrow_hashref("SELECT * FROM RefSpectra WHERE id = 3");
    is($row->{peptideSeq}, 'LKCASLQK', 'Spectrum 3 peptideSeq is LKCASLQK');
    
    my $mod = $dbh->selectrow_hashref("SELECT * FROM Modifications WHERE RefSpectraID = 3");
    is($mod->{position}, 3, 'Spectrum 3 mod at position 3 (C)');
    ok(abs($mod->{mass} - 57.021464) < 0.01, 'Spectrum 3 mod mass is Carbamidomethyl');
}

# Test spectrum 4: SCRSYR with two mods
{
    my $row = $dbh->selectrow_hashref("SELECT * FROM RefSpectra WHERE id = 4");
    is($row->{peptideSeq}, 'SCRSYR', 'Spectrum 4 peptideSeq is SCRSYR');
    
    my @mods = @{$dbh->selectall_arrayref("SELECT position, mass FROM Modifications WHERE RefSpectraID = 4 ORDER BY position", {Slice => {}})};
    is(scalar(@mods), 2, 'Spectrum 4 has 2 modifications');
    is($mods[0]->{position}, 1, 'First mod at position 1 (S)');
    is($mods[1]->{position}, 2, 'Second mod at position 2 (C)');
}

# Test peak data extraction
{
    my $row = $dbh->selectrow_hashref(q{
        SELECT r.numPeaks, p.peakMZ, p.peakIntensity 
        FROM RefSpectra r 
        JOIN RefSpectraPeaks p ON r.id = p.RefSpectraID 
        WHERE r.id = 1
    });
    
    my $mz_data = uncompress($row->{peakMZ}) // $row->{peakMZ};
    my @mz = unpack('d<*', $mz_data);
    
    my $int_data = uncompress($row->{peakIntensity}) // $row->{peakIntensity};
    my @intensity = unpack('f<*', $int_data);
    
    is(scalar(@mz), 5, 'Spectrum 1 has 5 m/z values');
    is(scalar(@intensity), 5, 'Spectrum 1 has 5 intensity values');
    ok(abs($mz[0] - 175.119) < 0.01, 'First m/z value correct');
}

# Test ScoreTypes
{
    my ($scoreType) = $dbh->selectrow_array("SELECT scoreType FROM ScoreTypes WHERE id = 1");
    is($scoreType, 'PERCOLATOR QVALUE', 'ScoreType 1 is PERCOLATOR QVALUE');
}

$dbh->disconnect();
done_testing();
