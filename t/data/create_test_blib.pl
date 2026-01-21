#!/usr/bin/perl
##############################################################################
# Create minimal test BLIB file for unit tests
##############################################################################

use strict;
use warnings;
use DBI;
use Compress::Zlib;
use File::Spec;
use FindBin qw($RealBin);

my $blib_file = File::Spec->catfile($RealBin, 'minimal.blib');
unlink $blib_file if -f $blib_file;

print "Creating test BLIB file: $blib_file\n";

my $dbh = DBI->connect("dbi:SQLite:dbname=$blib_file", '', '', {
    RaiseError => 1,
    AutoCommit => 1,
});

# Create tables (BiblioSpec schema)
$dbh->do('CREATE TABLE LibInfo (
    libLSID TEXT,
    createTime TEXT,
    numSpecs INTEGER,
    majorVersion INTEGER,
    minorVersion INTEGER
)');

$dbh->do('CREATE TABLE RefSpectra (
    id INTEGER PRIMARY KEY,
    peptideSeq TEXT,
    peptideModSeq TEXT,
    precursorCharge INTEGER,
    precursorMZ REAL,
    prevAA TEXT,
    nextAA TEXT,
    copies INTEGER,
    numPeaks INTEGER,
    retentionTime REAL,
    score REAL,
    scoreType INTEGER,
    totalIonCurrent REAL,
    ionMobility REAL,
    collisionalCrossSectionSqA REAL,
    SpecIDinFile TEXT
)');

$dbh->do('CREATE TABLE RefSpectraPeaks (
    RefSpectraID INTEGER,
    peakMZ BLOB,
    peakIntensity BLOB
)');

$dbh->do('CREATE TABLE Modifications (
    id INTEGER PRIMARY KEY,
    RefSpectraID INTEGER,
    position INTEGER,
    mass REAL
)');

$dbh->do('CREATE TABLE ScoreTypes (
    id INTEGER PRIMARY KEY,
    scoreType TEXT
)');

# Insert LibInfo
$dbh->do("INSERT INTO LibInfo VALUES ('test_lib', '2026-01-20', 4, 1, 0)");

# Insert ScoreTypes
$dbh->do("INSERT INTO ScoreTypes VALUES (1, 'PERCOLATOR QVALUE')");

# Helper to compress peaks
sub compress_peaks {
    my ($mz_ref, $int_ref) = @_;
    my $mz_packed = pack('d<*', @$mz_ref);
    my $int_packed = pack('f<*', @$int_ref);
    return (compress($mz_packed), compress($int_packed));
}

# Spectrum 1: IQVR/2 (no mods)
print "  Adding spectrum 1: IQVR/2 (no mods)\n";
{
    $dbh->do("INSERT INTO RefSpectra (id, peptideSeq, peptideModSeq, precursorCharge, precursorMZ, numPeaks, retentionTime, score, scoreType, totalIonCurrent)
              VALUES (1, 'IQVR', 'IQVR', 2, 258.051, 5, 2.0, 0.95, 1, 10000.0)");
    my @mz = (175.119, 241.845, 273.934, 385.088, 402.116);
    my @int = (1000.0, 3259.79, 6814.63, 1973.7, 4458.79);
    my ($mz_blob, $int_blob) = compress_peaks(\@mz, \@int);
    my $sth = $dbh->prepare('INSERT INTO RefSpectraPeaks VALUES (?, ?, ?)');
    $sth->bind_param(1, 1);
    $sth->bind_param(2, $mz_blob, DBI::SQL_BLOB);
    $sth->bind_param(3, $int_blob, DBI::SQL_BLOB);
    $sth->execute();
}

# Spectrum 2: MLQGR/2 with Oxidation at M1
print "  Adding spectrum 2: MLQGR/2 (Oxidation at M1)\n";
{
    $dbh->do("INSERT INTO RefSpectra (id, peptideSeq, peptideModSeq, precursorCharge, precursorMZ, numPeaks, retentionTime, score, scoreType, totalIonCurrent)
              VALUES (2, 'MLQGR', 'M[+16.0]LQGR', 2, 310.663, 6, 3.0, 0.88, 1, 8000.0)");
    $dbh->do('INSERT INTO Modifications (RefSpectraID, position, mass) VALUES (2, 1, 15.9949)');
    my @mz = (232.222, 256.260, 278.797, 360.318, 473.365, 519.373);
    my @int = (617.16, 802.82, 4802.82, 1464.88, 225.6, 7.92);
    my ($mz_blob, $int_blob) = compress_peaks(\@mz, \@int);
    my $sth = $dbh->prepare('INSERT INTO RefSpectraPeaks VALUES (?, ?, ?)');
    $sth->bind_param(1, 2);
    $sth->bind_param(2, $mz_blob, DBI::SQL_BLOB);
    $sth->bind_param(3, $int_blob, DBI::SQL_BLOB);
    $sth->execute();
}

# Spectrum 3: LKCASLQK/3 with Carbamidomethyl at C3
print "  Adding spectrum 3: LKCASLQK/3 (Carbamidomethyl at C3)\n";
{
    $dbh->do("INSERT INTO RefSpectra (id, peptideSeq, peptideModSeq, precursorCharge, precursorMZ, numPeaks, retentionTime, score, scoreType, totalIonCurrent)
              VALUES (3, 'LKCASLQK', 'LKC[+57.0]ASLQK', 3, 316.517, 5, 2.5, 0.92, 1, 9000.0)");
    $dbh->do('INSERT INTO Modifications (RefSpectraID, position, mass) VALUES (3, 3, 57.021464)');
    my @mz = (147.113, 304.177, 417.261, 530.345, 643.429);
    my @int = (400.0, 1000.0, 800.0, 600.0, 400.0);
    my ($mz_blob, $int_blob) = compress_peaks(\@mz, \@int);
    my $sth = $dbh->prepare('INSERT INTO RefSpectraPeaks VALUES (?, ?, ?)');
    $sth->bind_param(1, 3);
    $sth->bind_param(2, $mz_blob, DBI::SQL_BLOB);
    $sth->bind_param(3, $int_blob, DBI::SQL_BLOB);
    $sth->execute();
}

# Spectrum 4: SCRSYR/3 with Acetyl at S1, Carbamidomethyl at C2
print "  Adding spectrum 4: SCRSYR/3 (Acetyl at S1, Carbamidomethyl at C2)\n";
{
    $dbh->do("INSERT INTO RefSpectra (id, peptideSeq, peptideModSeq, precursorCharge, precursorMZ, numPeaks, retentionTime, score, scoreType, totalIonCurrent)
              VALUES (4, 'SCRSYR', 'S[+42.0]C[+57.0]RSYR', 3, 290.532, 4, 3.3, 0.85, 1, 7000.0)");
    $dbh->do('INSERT INTO Modifications (RefSpectraID, position, mass) VALUES (4, 1, 42.010565)');
    $dbh->do('INSERT INTO Modifications (RefSpectraID, position, mass) VALUES (4, 2, 57.021464)');
    my @mz = (238.446, 247.592, 323.600, 416.114);
    my @int = (960.69, 3862.13, 2623.22, 680.73);
    my ($mz_blob, $int_blob) = compress_peaks(\@mz, \@int);
    my $sth = $dbh->prepare('INSERT INTO RefSpectraPeaks VALUES (?, ?, ?)');
    $sth->bind_param(1, 4);
    $sth->bind_param(2, $mz_blob, DBI::SQL_BLOB);
    $sth->bind_param(3, $int_blob, DBI::SQL_BLOB);
    $sth->execute();
}

$dbh->disconnect();

print "Done! Created $blib_file with 4 spectra\n";
