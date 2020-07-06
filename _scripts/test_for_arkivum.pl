#!/usr/bin/perl
#
#       Tests for libraries requires by the Arkivum EPrints plugin
#       as specified in the EPrints Plugin V2.1 Installation and User Guide
#
use warnings;
use strict;

my @libs = (
        'Data::Dumper',
        'DateTime::Format::ISO8601',
        'File::Basename',
        'IO::Socket::SSL',
        'JSON',
        'LWP::UserAgent',
);

foreach ( @libs ) {
        eval "use $_;";
        if ( $@ ) {
                print sprintf ("%-35s", $_) . "library NOT found\n";
        }
        else {
                print sprintf ("%-35s", $_) . "library found\n";
        }
}
