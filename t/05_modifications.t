#!/usr/bin/perl
##############################################################################
# Unit tests for modification parsing and formatting
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use FindBin qw($RealBin);

# Find the main script
my $script_dir = File::Spec->catdir($RealBin, '..');
my $script = File::Spec->catfile($script_dir, 'blib2msp.pl');

unless (-f $script) {
    plan skip_all => "Main script not found: $script";
}

plan tests => 18;

# Load the main script as a module
{
    package main;
    our $VERSION;
    do $script or die "Cannot load script: $@";
}

# Test 1: parse_modifications_from_string exists
ok(defined(&main::parse_modifications_from_string), 'parse_modifications_from_string function exists');
ok(defined(&main::lookup_mod_mass), 'lookup_mod_mass function exists');

# Test 2: Parse single modification (new format)
{
    my @mods = main::parse_modifications_from_string('1(3,C,Carbamidomethyl)');
    is(scalar(@mods), 1, 'Parse single modification');
    is($mods[0]->{position}, 3, 'Modification position correct');
    is($mods[0]->{aa}, 'C', 'Modification amino acid correct');
    is($mods[0]->{tag}, 'Carbamidomethyl', 'Modification tag correct');
}

# Test 3: Parse multiple modifications (new format)
{
    my @mods = main::parse_modifications_from_string('2(3,C,Carbamidomethyl)(7,M,Oxidation)');
    is(scalar(@mods), 2, 'Parse two modifications');
    is($mods[0]->{position}, 3, 'First mod position');
    is($mods[0]->{tag}, 'Carbamidomethyl', 'First mod tag');
    is($mods[1]->{position}, 7, 'Second mod position');
    is($mods[1]->{tag}, 'Oxidation', 'Second mod tag');
}

# Test 4: Parse empty/undefined input
{
    my @mods = main::parse_modifications_from_string('');
    is(scalar(@mods), 0, 'Empty string returns no mods');
    
    @mods = main::parse_modifications_from_string(undef);
    is(scalar(@mods), 0, 'Undefined returns no mods');
    
    @mods = main::parse_modifications_from_string('0');
    is(scalar(@mods), 0, 'Zero count returns no mods');
}

# Test 5: lookup_mod_mass for common modifications
{
    my $mass = main::lookup_mod_mass('Oxidation');
    ok(defined $mass && abs($mass - 15.9949) < 0.01, 'Lookup Oxidation mass');
    
    $mass = main::lookup_mod_mass('Carbamidomethyl');
    ok(defined $mass && abs($mass - 57.021465) < 0.01, 'Lookup Carbamidomethyl mass');
    
    $mass = main::lookup_mod_mass('Phospho');
    ok(defined $mass && abs($mass - 79.9663) < 0.01, 'Lookup Phospho mass');
}

# Test 6: Unknown modification
{
    my $mass = main::lookup_mod_mass('CompletelyUnknownMod');
    is($mass, undef, 'Unknown modification returns undef');
}

done_testing();
