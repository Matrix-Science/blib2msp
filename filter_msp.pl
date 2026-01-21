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
#    $Archive::filter_msp.pl                                         $ #
#     $Author: richardj@matrixscience.com $ #
#       $Date: 2:08 PM Thursday, January 15, 2026 $ #
#   $Revision:  $ #
# $NoKeywords::                                                            $ #
##############################################################################
#
# filter_msp.pl - Filter MSP spectral library by peptide sequence list
#
# Version: 1.0
# 
# Usage: perl filter_msp.pl -i library.msp -p peptides.txt [-o filtered.msp]
#

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;

my $VERSION = '1.0';

# Command line options
my %opts = (
    input    => '',
    peptides => '',
    output   => '',
    help     => 0,
    version  => 0,
);

GetOptions(
    'input|i=s'    => \$opts{input},
    'peptides|p=s' => \$opts{peptides},
    'output|o=s'   => \$opts{output},
    'help|h'       => \$opts{help},
    'version'      => \$opts{version},
) or pod2usage(2);

pod2usage(1) if $opts{help};

if ($opts{version}) {
    print "filter_msp.pl version $VERSION\n";
    exit 0;
}

# Validate input
unless ($opts{input} && $opts{peptides}) {
    print STDERR "Error: Both input MSP file (-i) and peptide list (-p) are required.\n";
    pod2usage(2);
}

unless (-f $opts{input}) {
    die "Error: Input MSP file not found: $opts{input}\n";
}

unless (-f $opts{peptides}) {
    die "Error: Peptide list file not found: $opts{peptides}\n";
}

# Default output filename
unless ($opts{output}) {
    $opts{output} = $opts{input};
    $opts{output} =~ s/\.msp$/_filtered.msp/i;
}

print "Loading peptide list from: $opts{peptides}\n";

# Load peptide list into a hash for fast lookup
my %allowed_peptides;
open(my $pep_fh, '<:encoding(UTF-8)', $opts{peptides}) 
    or die "Cannot open peptide list $opts{peptides}: $!\n";
while (my $line = <$pep_fh>) {
    chomp $line;
    $line =~ s/\r//g;
    $line =~ s/^\s+|\s+$//g;  # Trim whitespace
    next unless $line;
    $allowed_peptides{$line} = 1;
}
close($pep_fh);

my $peptide_count = scalar(keys %allowed_peptides);
print "Loaded $peptide_count peptides to filter by\n";

print "Filtering MSP file: $opts{input}\n";

# Process MSP file
open(my $in_fh, '<:encoding(UTF-8)', $opts{input}) 
    or die "Cannot open input MSP file $opts{input}: $!\n";
open(my $out_fh, '>:encoding(UTF-8)', $opts{output}) 
    or die "Cannot open output file $opts{output}: $!\n";

my @current_entry;
my $current_peptide = '';
my $total_entries = 0;
my $kept_entries = 0;

while (my $line = <$in_fh>) {
    chomp $line;
    
    # Check for Name line (start of new entry)
    if ($line =~ /^Name:\s*(\S+)/) {
        # Process previous entry if exists
        if (@current_entry && $current_peptide) {
            $total_entries++;
            if ($allowed_peptides{$current_peptide}) {
                print $out_fh join("\n", @current_entry) . "\n\n";
                $kept_entries++;
            }
        }
        
        # Start new entry
        @current_entry = ($line);
        
        # Extract peptide sequence from Name line
        # Format: Name: PEPTIDE/charge_modcount(mods) or Name: PEPTIDE/charge
        my $name_part = $1;
        if ($name_part =~ /^([A-Z]+)\//) {
            $current_peptide = $1;
        } else {
            $current_peptide = '';
        }
    }
    elsif ($line =~ /^\s*$/) {
        # Empty line - end of entry, skip adding to current_entry
        next;
    }
    else {
        # Add line to current entry
        push @current_entry, $line;
    }
}

# Process final entry
if (@current_entry && $current_peptide) {
    $total_entries++;
    if ($allowed_peptides{$current_peptide}) {
        print $out_fh join("\n", @current_entry) . "\n\n";
        $kept_entries++;
    }
}

close($in_fh);
close($out_fh);

print "\nFiltering complete!\n";
print "  Total entries processed: $total_entries\n";
print "  Entries kept: $kept_entries\n";
print "  Entries removed: " . ($total_entries - $kept_entries) . "\n";
print "Output saved to: $opts{output}\n";

__END__

=head1 NAME

filter_msp.pl - Filter MSP spectral library by peptide sequence list

=head1 SYNOPSIS

filter_msp.pl -i <input.msp> -p <peptides.txt> [-o <output.msp>]

  Options:
    -i, --input FILE      Input MSP file (required)
    -p, --peptides FILE   Text file with peptide sequences, one per line (required)
    -o, --output FILE     Output MSP file (default: input_filtered.msp)
    -h, --help            Show this help message
        --version         Show version number

=head1 DESCRIPTION

Filters an MSP spectral library to only include entries whose peptide sequences
are present in the provided peptide list file.

=head1 EXAMPLES

    # Filter MSP file, auto-generate output filename
    perl filter_msp.pl -i library.msp -p peptide_list.txt
    
    # Filter MSP file to specific output
    perl filter_msp.pl -i library.msp -p peptides.txt -o filtered_library.msp

=head1 AUTHOR

BLIB_MSP_converter project

=cut
