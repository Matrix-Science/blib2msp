#!/usr/bin/perl
##############################################################################
# BLIB to MSP Spectral Library Converter Utility Script
##############################################################################
# COPYRIGHT NOTICE                                                           #
# Copyright (C) 2026 Matrix Science Limited  All Rights Reserved.            #
#                                                                            #
# This script is free software. You can redistribute and/or                  #
# modify it under the terms of the GNU General Public License                #
# as published by the Free Software Foundation; either version 2             #
# of the License or, (at your option), any later version.                    #
#                                                                            #
# These modules are distributed in the hope that they will be useful,        #
# but WITHOUT ANY WARRANTY; without even the implied warranty of             #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the               #
# GNU General Public License for more details.                               #
#                                                                            #
# Original author: Richard Jacob                                             #
##############################################################################
#    $Archive::extract_peptides.pl                                         $ #
#     $Author: richardj@matrixscience.com $ #
#       $Date: 2:08 PM Thursday, January 15, 2026 $ #
#   $Revision:  $ #
# $NoKeywords::                                                            $ #
##############################################################################
#
# extract_peptides.pl - Extract unique peptide sequences from a spectral library
#
# Version: 1.1
# 
# Usage: perl extract_peptides.pl -i library.blib [-o peptides.txt]
#        perl extract_peptides.pl -i library.msp [-o peptides.txt]
#

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;

my $VERSION = '1.1';

# Command line options
my %opts = (
    input  => '',
    output => '',
    help   => 0,
    version => 0,
);

GetOptions(
    'input|i=s'  => \$opts{input},
    'output|o=s' => \$opts{output},
    'help|h'     => \$opts{help},
    'version'    => \$opts{version},
) or pod2usage(2);

pod2usage(1) if $opts{help};

if ($opts{version}) {
    print "extract_peptides.pl version $VERSION\n";
    exit 0;
}

# Validate input
unless ($opts{input}) {
    print STDERR "Error: Input file required. Use -i <file.blib> or -i <file.msp>\n";
    pod2usage(2);
}

unless (-f $opts{input}) {
    die "Error: Input file not found: $opts{input}\n";
}

# Detect file type
my $file_type;
if ($opts{input} =~ /\.blib$/i) {
    $file_type = 'blib';
} elsif ($opts{input} =~ /\.msp$/i) {
    $file_type = 'msp';
} else {
    die "Error: Unrecognized file type. Use .blib or .msp extension.\n";
}

# Default output filename
unless ($opts{output}) {
    $opts{output} = $opts{input};
    $opts{output} =~ s/\.(blib|msp)$/_peptides.txt/i;
}

print "Extracting peptides from: $opts{input} ($file_type format)\n";

my %unique_peptides;

if ($file_type eq 'blib') {
    extract_from_blib(\%unique_peptides);
} else {
    extract_from_msp(\%unique_peptides);
}

# Write to output file (sorted)
open(my $fh, '>:encoding(UTF-8)', $opts{output}) 
    or die "Cannot open output file $opts{output}: $!\n";

my $count = 0;
for my $peptide (sort keys %unique_peptides) {
    print $fh "$peptide\n";
    $count++;
}

close($fh);

print "Extracted $count unique peptide sequences\n";
print "Output saved to: $opts{output}\n";

#---------------------------------------------------------------------------
# Extract peptides from BLIB file (SQLite database)
#---------------------------------------------------------------------------
sub extract_from_blib {
    my ($peptides_ref) = @_;
    
    require DBI;
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$opts{input}", "", "", {
        RaiseError => 1,
        AutoCommit => 1,
        sqlite_unicode => 1,
    }) or die "Cannot connect to database: " . DBI->errstr . "\n";

    my $sql = "SELECT DISTINCT peptideSeq FROM RefSpectra WHERE peptideSeq IS NOT NULL AND peptideSeq != '' ORDER BY peptideSeq";
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    while (my ($peptide) = $sth->fetchrow_array()) {
        $peptides_ref->{$peptide} = 1;
    }

    $sth->finish();
    $dbh->disconnect();
}

#---------------------------------------------------------------------------
# Extract peptides from MSP file (text format)
#---------------------------------------------------------------------------
sub extract_from_msp {
    my ($peptides_ref) = @_;
    
    open(my $fh, '<:encoding(UTF-8)', $opts{input}) 
        or die "Cannot open MSP file $opts{input}: $!\n";
    
    while (my $line = <$fh>) {
        chomp $line;
        
        # Look for Name lines: Name: PEPTIDE/charge or Name: PEPTIDE/charge_modcount(mods)
        if ($line =~ /^Name:\s*([A-Z]+)\//) {
            my $peptide = $1;
            $peptides_ref->{$peptide} = 1;
        }
    }
    
    close($fh);
}

__END__

=head1 NAME

extract_peptides.pl - Extract unique peptide sequences from a spectral library

=head1 SYNOPSIS

extract_peptides.pl -i <input.blib|input.msp> [-o <output.txt>]

  Options:
    -i, --input FILE     Input BLIB or MSP file (required)
    -o, --output FILE    Output text file (default: input_peptides.txt)
    -h, --help           Show this help message
        --version        Show version number

=head1 DESCRIPTION

Extracts all unique peptide sequences from a BiblioSpec BLIB or NIST MSP 
spectral library and saves them to a text file, one peptide per line.

Supported formats:
  - BLIB (BiblioSpec SQLite database)
  - MSP (NIST text format)

=head1 EXAMPLES

    # Extract peptides from BLIB file
    perl extract_peptides.pl -i my_library.blib
    
    # Extract peptides from MSP file
    perl extract_peptides.pl -i my_library.msp
    
    # Extract peptides to specific output file
    perl extract_peptides.pl -i my_library.blib -o peptide_list.txt

=head1 AUTHOR

BLIB_MSP_converter project

=cut
