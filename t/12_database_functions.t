#!/usr/bin/perl
##############################################################################
# Unit tests for database query functions in blib2msp.pl
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempfile);
use FindBin qw($RealBin);
use DBI;

# Find the main script and test BLIB
my $script_dir = File::Spec->catdir($RealBin, '..');
my $script = File::Spec->catfile($script_dir, 'blib2msp.pl');
my $test_blib = File::Spec->catfile($RealBin, 'data', 'minimal.blib');

unless (-f $script) {
    plan skip_all => "Main script not found: $script";
}
unless (-f $test_blib) {
    plan skip_all => "Test BLIB file not found: $test_blib";
}

plan tests => 22;

# Load the main script as a module
{
    package main;
    our $VERSION;
    do $script or die "Cannot load script: $@";
}

# Connect to test database
my $dbh = DBI->connect("dbi:SQLite:dbname=$test_blib", '', '', {
    RaiseError => 1,
    PrintError => 0,
});
ok($dbh, 'Connected to test BLIB for function testing');

# Test 1: get_library_info function
ok(defined(&main::get_library_info), 'get_library_info function exists');

{
    my $info = main::get_library_info($dbh);
    ok(ref($info) eq 'HASH', 'get_library_info returns hashref');
    is($info->{numSpecs}, 4, 'LibInfo numSpecs is 4');
    is($info->{libLSID}, 'test_lib', 'LibInfo libLSID is correct');
}

# Test 2: get_score_types function
ok(defined(&main::get_score_types), 'get_score_types function exists');

{
    my %types = main::get_score_types($dbh);
    ok(scalar(keys %types) >= 1, 'get_score_types returns data');
    is($types{1}, 'PERCOLATOR QVALUE', 'ScoreType 1 is PERCOLATOR QVALUE');
}

# Test 3: get_all_modifications function
ok(defined(&main::get_all_modifications), 'get_all_modifications function exists');

{
    my %mods = main::get_all_modifications($dbh);
    
    # Spectrum 1 has no modifications
    ok(!exists $mods{1} || scalar(@{$mods{1}}) == 0, 'Spectrum 1 has no modifications');
    
    # Spectrum 2 has Oxidation at position 1
    ok(exists $mods{2}, 'Spectrum 2 has modifications');
    is(scalar(@{$mods{2}}), 1, 'Spectrum 2 has 1 modification');
    is($mods{2}[0]{position}, 1, 'Spectrum 2 mod at position 1');
    
    # Spectrum 3 has Carbamidomethyl at position 3
    ok(exists $mods{3}, 'Spectrum 3 has modifications');
    is($mods{3}[0]{position}, 3, 'Spectrum 3 mod at position 3');
    
    # Spectrum 4 has 2 modifications
    ok(exists $mods{4}, 'Spectrum 4 has modifications');
    is(scalar(@{$mods{4}}), 2, 'Spectrum 4 has 2 modifications');
}

# Test 4: get_all_proteins function (should return empty for minimal.blib which has no Proteins table)
ok(defined(&main::get_all_proteins), 'get_all_proteins function exists');

{
    my %proteins = main::get_all_proteins($dbh);
    # minimal.blib doesn't have Proteins table, so should return empty or handle gracefully
    ok(ref(\%proteins) eq 'HASH', 'get_all_proteins returns hash');
}

# Test 5: get_unique_peptides_from_blib function
ok(defined(&main::get_unique_peptides_from_blib), 'get_unique_peptides_from_blib function exists');

{
    my @peptides = main::get_unique_peptides_from_blib($dbh);
    ok(scalar(@peptides) >= 3, 'Found at least 3 unique peptides');
    
    my %found = map { $_ => 1 } @peptides;
    # Check that we found at least some expected peptides
    my $found_count = 0;
    $found_count++ if $found{IQVR};
    $found_count++ if $found{MLQGR};
    $found_count++ if $found{LKCASLQK};
    $found_count++ if $found{SCRSYR};
    ok($found_count >= 3, 'Found at least 3 expected peptides');
}

$dbh->disconnect();
done_testing();
