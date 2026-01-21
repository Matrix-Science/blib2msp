#!/usr/bin/perl
##############################################################################
# Unit tests for BLIB schema creation and MSP parsing functions
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempfile tempdir);
use FindBin qw($RealBin);
use DBI;

# Find the main script
my $script_dir = File::Spec->catdir($RealBin, '..');
my $script = File::Spec->catfile($script_dir, 'blib2msp.pl');
my $test_msp = File::Spec->catfile($RealBin, 'data', 'minimal.msp');
my $test_unimod = File::Spec->catfile($RealBin, 'data', 'minimal_unimod.xml');

unless (-f $script) {
    plan skip_all => "Main script not found: $script";
}

plan tests => 21;

# Load the main script as a module
{
    package main;
    our $VERSION;
    do $script or die "Cannot load script: $@";
}

# Load unimod for testing
main::load_unimod($test_unimod) if -f $test_unimod;

# Test 1: create_blib_schema function
ok(defined(&main::create_blib_schema), 'create_blib_schema function exists');

{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $test_db = File::Spec->catfile($tmpdir, 'test_schema.blib');
    
    # Create a new database with schema
    my $dbh = DBI->connect("dbi:SQLite:dbname=$test_db", '', '', {
        RaiseError => 1,
        AutoCommit => 1,
    });
    
    main::create_blib_schema($dbh);
    
    # Verify tables were created
    my @tables = map { $_->[0] } @{$dbh->selectall_arrayref(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    )};
    
    ok(grep(/^LibInfo$/, @tables), 'LibInfo table created');
    ok(grep(/^RefSpectra$/, @tables), 'RefSpectra table created');
    ok(grep(/^RefSpectraPeaks$/, @tables), 'RefSpectraPeaks table created');
    ok(grep(/^Modifications$/, @tables), 'Modifications table created');
    ok(grep(/^ScoreTypes$/, @tables), 'ScoreTypes table created');
    
    $dbh->disconnect();
}

# Test 2: update_library_info function
ok(defined(&main::update_library_info), 'update_library_info function exists');

{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $test_db = File::Spec->catfile($tmpdir, 'test_libinfo.blib');
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$test_db", '', '', {
        RaiseError => 1,
        AutoCommit => 1,
    });
    
    main::create_blib_schema($dbh);
    main::update_library_info($dbh, 10);
    
    my ($numSpecs) = $dbh->selectrow_array("SELECT numSpecs FROM LibInfo");
    is($numSpecs, 10, 'update_library_info sets numSpecs correctly');
    
    $dbh->disconnect();
}

# Test 3: extract_peaks function
ok(defined(&main::extract_peaks), 'extract_peaks function exists');

{
    # Create compressed peak data like BLIB stores it
    use Compress::Zlib;
    
    my @mz = (100.0, 200.0, 300.0, 400.0, 500.0);
    my @int = (1000.0, 2000.0, 3000.0, 2000.0, 1000.0);
    
    my $mz_packed = pack('d<*', @mz);
    my $int_packed = pack('f<*', @int);
    
    my $mz_compressed = compress($mz_packed);
    my $int_compressed = compress($int_packed);
    
    my ($mz_ref, $int_ref) = main::extract_peaks($mz_compressed, $int_compressed, 5);
    
    ok(defined $mz_ref, 'extract_peaks returns m/z array');
    ok(defined $int_ref, 'extract_peaks returns intensity array');
    is(scalar(@$mz_ref), 5, 'Correct number of m/z values');
    is(scalar(@$int_ref), 5, 'Correct number of intensity values');
    ok(abs($mz_ref->[0] - 100.0) < 0.01, 'First m/z value correct');
    ok(abs($int_ref->[2] - 3000.0) < 1.0, 'Third intensity value correct');
}

# Test 4: compute_cache_key function
ok(defined(&main::compute_cache_key), 'compute_cache_key function exists');

{
    my $test_fasta_dir = File::Spec->catfile($RealBin, 'data');
    my @peptides = ('PEPTIDE', 'TESTPEP', 'ANOTHER');
    
    my $key1 = main::compute_cache_key($test_fasta_dir, \@peptides);
    ok(defined $key1, 'compute_cache_key returns a key');
    like($key1, qr/^[a-f0-9]{32}$/, 'Cache key is 32-char hex (MD5)');
    
    # Same inputs should give same key
    my $key2 = main::compute_cache_key($test_fasta_dir, \@peptides);
    is($key1, $key2, 'Same inputs produce same cache key');
    
    # Different peptides should give different key
    my @different_peptides = ('OTHER', 'PEPTIDES');
    my $key3 = main::compute_cache_key($test_fasta_dir, \@different_peptides);
    isnt($key1, $key3, 'Different peptides produce different cache key');
}

# Test 5: parse_and_insert_msp function exists
ok(defined(&main::parse_and_insert_msp), 'parse_and_insert_msp function exists');

done_testing();
