#!/usr/bin/perl
##############################################################################
# Unit tests for Unimod loading and lookup functionality
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use FindBin qw($RealBin);

# Find the main script and unimod.xml
my $script_dir = File::Spec->catdir($RealBin, '..');
my $script = File::Spec->catfile($script_dir, 'blib2msp.pl');
# Use full unimod.xml from main directory (msparser requires schema-valid XML)
my $test_unimod = File::Spec->catfile($script_dir, 'unimod.xml');

unless (-f $script) {
    plan skip_all => "Main script not found: $script";
}
unless (-f $test_unimod) {
    plan skip_all => "Full unimod.xml not found: $test_unimod (msparser requires schema-valid unimod.xml)";
}

plan tests => 16;

# Load the main script as a module
{
    package main;
    our $VERSION;  # Declare to avoid warnings
    do $script or die "Cannot load script: $@";
}

# Test 1: Load Unimod function exists
ok(defined(&main::load_unimod), 'load_unimod function exists');
ok(defined(&main::lookup_unimod_name), 'lookup_unimod_name function exists');
ok(defined(&main::lookup_unimod_mass), 'lookup_unimod_mass function exists');

# Test 2: Load minimal unimod file and verify it works
{
    main::load_unimod($test_unimod);
    # Verify Unimod loading by testing actual lookups work
    my $test_name = main::lookup_unimod_name(57.021464);
    ok(defined $test_name, 'Unimod loaded successfully (lookup works)');
    ok($test_name eq 'Carbamidomethyl', 'Mass to name lookup populated');
    my $test_mass = main::lookup_unimod_mass('Oxidation');
    ok(defined $test_mass, 'Name to mass lookup populated');
}

# Test 3: Lookup modification name by mass
{
    my $name = main::lookup_unimod_name(57.021464);
    is($name, 'Carbamidomethyl', 'Find Carbamidomethyl by exact mass');

    # Note: mass 15.994915 has multiple mods (Oxidation, Ala->Ser, etc.)
    # We just verify a valid name is returned
    $name = main::lookup_unimod_name(15.994915);
    ok(defined $name, 'Find modification by mass 15.994915 (Oxidation mass)');

    $name = main::lookup_unimod_name(79.966331);
    is($name, 'Phospho', 'Find Phospho by exact mass');
}

# Test 4: Lookup mass by modification name
{
    my $mass = main::lookup_unimod_mass('Carbamidomethyl');
    ok(defined $mass && abs($mass - 57.021464) < 0.001, 'Find mass for Carbamidomethyl');
    
    $mass = main::lookup_unimod_mass('Oxidation');
    ok(defined $mass && abs($mass - 15.994915) < 0.001, 'Find mass for Oxidation');
    
    $mass = main::lookup_unimod_mass('Phospho');
    ok(defined $mass && abs($mass - 79.966331) < 0.001, 'Find mass for Phospho');
}

# Test 5: Mass tolerance lookup
{
    # Try with slightly different mass (within tolerance)
    my $name = main::lookup_unimod_name(57.0215);  # Slightly different
    is($name, 'Carbamidomethyl', 'Find Carbamidomethyl with mass tolerance');
}

# Test 6: Unknown modification handling
{
    my $name = main::lookup_unimod_name(999.999);
    is($name, undef, 'Unknown mass returns undef');
    
    my $mass = main::lookup_unimod_mass('NonExistentMod');
    is($mass, undef, 'Unknown name returns undef');
}

# Test 7: Case-insensitive name lookup
{
    my $mass = main::lookup_unimod_mass('carbamidomethyl');
    ok(defined $mass && abs($mass - 57.021464) < 0.001, 'Case-insensitive name lookup');
}

done_testing();
