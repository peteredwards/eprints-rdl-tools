#!/usr/bin/perl

use strict;
use warnings;
use Date::Parse;

my $cmd = 'ls -ltRr * | grep "\-r" | sed -e 1b -e \'$!d\'';
my $path = '/usr/share/eprints/archives/researchdata/documents/disk0/00/00/';
my $id = 1;
my $epid = '';
my ( $size, $start, $end, $tmp, $secs, $gbpm );
my @se;
my @speeds;

my $max_eprints = 100;

while ( $id <= $max_eprints )
{
	$epid = sprintf( "%02d/%02d", int($id/100), $id%100 );
	if ( -d "$path$epid" )
	{
		#print `ls -ltRr $path$epid/* | grep \"\\-r\" | sed -e 1b -e '\$!d'`;
		$tmp = `ls -ltRr --time-style=full-iso $path$epid/* | grep \"\\-r\" | grep -v \"\\.xml\$\" | grep -v \"indexcodes\\.txt\" | sed -e 1b -e '\$!d' | awk '{ print \$6, \$7 }'`;
		( $start, $end ) = split ( "\n", $tmp );
		$size = `du -s $path$epid | awk '{ print \$1 }'`;
		if ( $start && $end && $id != 21 ) # eprint 21 gives silly results
		{
			$secs = str2time( $end ) -  str2time( $start );
			$gbpm = ( $size * 60 ) / ( $secs * 1024 * 1024 );
			#print "$id $start $end $size $secs $gbpm\n";
			print sprintf( "%6d %9d %5.2f GB/min\n", $id, $size, $gbpm );
			push @speeds, $gbpm;
		}
	}
	$id++;
}

# do some basic stats
my ( $av, $sd, $var );
map { $av += $_ } @speeds;
$av = $av / scalar( @speeds );
map { $var += ( ( $_ - $av ) * ( $_ - $av ) ) } @speeds;
$var = $var / scalar( @speeds );
$sd = sqrt ( $var );
print sprintf( "\n%5.2f MEAN, %5.2f SD, %5.2f VAR ( GB/min ) from %d values\n\n", $av, $sd, $var, scalar( @speeds ));
