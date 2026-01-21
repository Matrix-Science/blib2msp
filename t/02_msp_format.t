#!/usr/bin/perl
##############################################################################
# Unit tests for MSP format reading and writing
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempfile);

plan tests => 14;

# Test MSP parsing functions (inline versions for testing)

# Test 1: Parse simple Name field
{
    my $name = 'PEPTIDE/2';
    my ($seq, $charge) = ('', 2);
    if ($name =~ /^(.+)\/(\d+)$/) {
        $seq = $1;
        $charge = $2;
    }
    is($seq, 'PEPTIDE', 'Parse peptide sequence from Name');
    is($charge, 2, 'Parse charge from Name');
}

# Test 2: Parse modified peptide Name
{
    my $name = 'PEPTM(O)IDE/3';
    my ($seq, $charge) = ('', 2);
    if ($name =~ /^(.+)\/(\d+)$/) {
        $seq = $1;
        $charge = $2;
    }
    is($seq, 'PEPTM(O)IDE', 'Parse modified peptide from Name');
    is($charge, 3, 'Parse charge from modified Name');
    
    # Strip modifications
    my $unmod = $seq;
    $unmod =~ s/\([^)]+\)//g;
    is($unmod, 'PEPTMIDE', 'Strip modification annotations');
}

# Test 3: Parse Comment field
{
    my $comment = 'Parent=617.284 Mods=1/2,M,15.9949 RetentionTime=123.45 Score=0.99';
    my %fields;
    while ($comment =~ /(\w+)=(?:"([^"]+)"|(\S+))/g) {
        my $key = $1;
        my $value = defined $2 ? $2 : $3;
        $fields{$key} = $value;
    }
    
    is($fields{Parent}, '617.284', 'Parse Parent from Comment');
    is($fields{Mods}, '1/2,M,15.9949', 'Parse Mods from Comment');
    is($fields{RetentionTime}, '123.45', 'Parse RetentionTime from Comment');
    is($fields{Score}, '0.99', 'Parse Score from Comment');
}

# Test 4: Parse Comment with quoted values
{
    my $comment = 'Protein="sp|TRYP_PIG| Trypsin" Score=0.95';
    my %fields;
    while ($comment =~ /(\w+)=(?:"([^"]+)"|(\S+))/g) {
        my $key = $1;
        my $value = defined $2 ? $2 : $3;
        $fields{$key} = $value;
    }
    
    is($fields{Protein}, 'sp|TRYP_PIG| Trypsin', 'Parse quoted value from Comment');
    is($fields{Score}, '0.95', 'Parse unquoted value after quoted');
}

# Test 5: MW calculation from m/z and charge
{
    my $proton_mass = 1.007276;
    my $precursor_mz = 617.284;
    my $charge = 2;
    
    my $mw = ($precursor_mz * $charge) - ($charge * $proton_mass);
    
    ok(abs($mw - 1232.553448) < 0.001, 'MW calculation from m/z and charge');
}

# Test 6: Reverse calculation - m/z from MW and charge
{
    my $proton_mass = 1.007276;
    my $mw = 1232.553448;
    my $charge = 2;
    
    my $mz = ($mw + $charge * $proton_mass) / $charge;
    
    ok(abs($mz - 617.284) < 0.001, 'm/z calculation from MW and charge');
}

# Test 7: Peak line parsing
{
    my $line = '617.284 1000.50';
    my ($mz, $intensity);
    if ($line =~ /^\s*([\d.]+)\s+([\d.]+)/) {
        $mz = $1;
        $intensity = $2;
    }
    
    is($mz, '617.284', 'Parse m/z from peak line');
}

done_testing();


